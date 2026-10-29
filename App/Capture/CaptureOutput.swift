import AppKit
import AuditCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct CaptureResult {
    let image: CGImage
    let scale: CGFloat
    let record: CaptureRecord
}

enum CaptureOutput {
    /// PNG plus TIFF, sized in points so a Retina capture pastes at its
    /// on-screen size rather than double.
    @MainActor
    static func copyToClipboard(_ image: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pasteboard.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
    }

    /// Writes a PNG whose DPI records the scale, so image viewers show it
    /// at the size it had on screen.
    static func writePNG(_ image: CGImage, scale: CGFloat, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dpi = 72 * scale
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func defaultFileName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Capture \(f.string(from: date)).png"
    }
}

/// The capture on a quiet backdrop, the way Preview and the screenshot
/// thumbnail present an image: picture first, actions in the toolbar.
struct CaptureResultView: View {
    let result: CaptureResult
    @State private var status = "Copied to the clipboard"
    @State private var saved = false

    private var size: String { "\(result.image.width) × \(result.image.height) px" }

    var body: some View {
        VStack(spacing: 0) {
            Image(result.image, scale: result.scale, label: Text("Captured \(result.record.description.lowercased()), \(result.image.width) by \(result.image.height) pixels"))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))

            Divider()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.pass)
                    .accessibilityHidden(true)
                Text(status)
                Spacer()
                Text(size).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(minWidth: 420, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    CaptureOutput.copyToClipboard(result.image, scale: result.scale)
                    status = "Copied to the clipboard again"
                    Announcer.say(status)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy the capture")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { save() } label: {
                    Label("Save as PNG", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save the capture as a PNG file")
            }
        }
    }

    @MainActor
    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = CaptureOutput.defaultFileName(for: result.record.date)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CaptureOutput.writePNG(result.image, scale: result.scale, to: url)
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
        Announcer.say(status)
    }
}

/// A three-second countdown that never takes focus, so the menu or hover
/// state being captured stays open. It is excluded from captures anyway,
/// like every window of this app.
@MainActor
enum CountdownHUD {
    @Observable final class Model { var remaining = 3 }

    static func run(seconds: Int) async {
        let model = Model()
        model.remaining = seconds
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let size = NSSize(width: 112, height: 112)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CountdownView(model: model))
        if let visible = screen?.visibleFrame {
            // Bottom center, clear of most menus and tooltips.
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 48))
        }
        panel.orderFrontRegardless()
        Announcer.say("Capturing in \(seconds) seconds")
        for remaining in stride(from: seconds, to: 0, by: -1) {
            model.remaining = remaining
            try? await Task.sleep(for: .seconds(1))
        }
        panel.orderOut(nil)
        // Let the window server drop the panel before the frame is taken.
        try? await Task.sleep(for: .milliseconds(120))
    }

    struct CountdownView: View {
        let model: Model
        var body: some View {
            Text("\(model.remaining)")
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 112, height: 112)
                .modifier(HUDBackground(shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
                .environment(\.colorScheme, .dark)
                .accessibilityLabel("Capturing in \(model.remaining) seconds")
        }
    }
}
