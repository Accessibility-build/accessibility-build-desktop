import AppKit
import AuditCore
import ScreenCaptureKit

/// One display, frozen at the moment of capture.
struct FrozenDisplay {
    let displayID: CGDirectDisplayID
    let geometry: DisplayGeometry
    /// sRGB image at the display's pixel size.
    let image: CGImage
    let pixels: PixelBuffer
}

@MainActor
enum ScreenCapture {
    enum Failure: LocalizedError {
        case permissionDenied
        case noDisplays
        case noWindow
        case conversion

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Accessibility Build does not have Screen Recording permission."
            case .noDisplays: "No display could be captured."
            case .noWindow: "There is no window in front to capture. Click the window you want, then try again."
            case .conversion: "The captured image could not be read."
            }
        }
    }

    static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // ScreenCaptureKit reports a missing grant as a generic error;
            // the preflight check tells the two cases apart.
            if !CGPreflightScreenCaptureAccess() { throw Failure.permissionDenied }
            throw error
        }
    }

    /// The app's own windows (results, lens, countdown) never appear in a capture.
    static func ownWindows(in content: SCShareableContent) -> [SCWindow] {
        let pid = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter { $0.owningApplication?.processID == pid }
    }

    /// A display filter that leaves out every window of this app, including
    /// ones created after the filter (a popover, a tooltip). Falls back to
    /// the current window list when the app is not listed, which happens
    /// when it has no window on screen.
    static func filterExcludingSelf(display: SCDisplay, in content: SCShareableContent) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        if let me = content.applications.first(where: { $0.processID == pid }) {
            return SCContentFilter(display: display, excludingApplications: [me], exceptingWindows: [])
        }
        return SCContentFilter(display: display, excludingWindows: ownWindows(in: content))
    }

    static func configuration(width: Int, height: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.showsCursor = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // Ask for sRGB. On a Display P3 screen a raw capture holds display
        // values, so a CSS #767676 would read back as a different hex and
        // every ratio would be slightly off.
        config.colorSpaceName = CGColorSpace.sRGB
        return config
    }

    /// Freezes every display, in NSScreen order.
    static func freezeDisplays() async throws -> [FrozenDisplay] {
        let content = try await shareableContent()
        var frozen: [FrozenDisplay] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = filterExcludingSelf(display: display, in: content)
            let scale = CGFloat(filter.pointPixelScale)
            let geometry = DisplayGeometry(frame: screen.frame, scale: scale)
            let config = configuration(width: geometry.pixelWidth, height: geometry.pixelHeight)
            let captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let (image, pixels) = try toSRGB(captured)
            frozen.append(FrozenDisplay(
                displayID: id,
                geometry: DisplayGeometry(frame: screen.frame, scale: scale, pixelWidth: pixels.width, pixelHeight: pixels.height),
                image: image,
                pixels: pixels
            ))
        }
        if frozen.isEmpty { throw Failure.noDisplays }
        return frozen
    }

    /// The frontmost ordinary window that is not this app's, without its shadow.
    static func captureFrontWindow() async throws -> (image: CGImage, scale: CGFloat, appName: String?) {
        let content = try await shareableContent()
        let pid = ProcessInfo.processInfo.processIdentifier
        // CGWindowList is ordered front to back; ScreenCaptureKit's list is not.
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  // Invisible overlay windows sit at layer 0 too.
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner != pid,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let window = content.windows.first(where: { $0.windowID == number }),
                  window.frame.width >= 40, window.frame.height >= 40
            else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let config = configuration(
                width: Int((window.frame.width * scale).rounded()),
                height: Int((window.frame.height * scale).rounded())
            )
            config.ignoreShadowsSingleWindow = true
            let captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return (try toSRGB(captured).0, scale, window.owningApplication?.applicationName)
        }
        throw Failure.noWindow
    }

    /// Redraws a capture into an 8-bit sRGB bitmap. If ScreenCaptureKit
    /// already honored the sRGB request this is a copy; if not, Core
    /// Graphics color-matches here, so the pixel values are sRGB either way.
    static func toSRGB(_ source: CGImage) throws -> (CGImage, PixelBuffer) {
        let width = source.width, height = source.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { throw Failure.conversion }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data, let image = context.makeImage() else { throw Failure.conversion }
        let bytes = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
        return (image, PixelBuffer(width: width, height: height, bytes: bytes))
    }
}
