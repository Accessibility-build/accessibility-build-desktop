import AppKit
import AuditCore
import ColorCore

/// Every user-facing command, whether it comes from the menu, a global
/// shortcut or a button, goes through here.
@MainActor
final class AppActions: NSObject {
    static let shared = AppActions()

    private var overlay: FreezeOverlay?
    private var isCapturing = false

    // MARK: Contrast picker

    @objc func pickContrast() { freezeThen(delayed: false) { self.showPicker($0) } }
    @objc func pickContrastDelayed() { freezeThen(delayed: true) { self.showPicker($0) } }

    private func showPicker(_ displays: [FrozenDisplay]) {
        let overlay = FreezeOverlay(displays: displays, mode: .contrast) { [weak self] outcome in
            self?.overlay = nil
            guard case let .contrast(text, background, worst) = outcome else { return }
            let model = ContrastModel.shared
            model.load(text: text, background: background, worstCaseArea: worst?.area)
            SessionStore.shared.add(.contrast(ContrastCheck(text: text, background: background, worstCaseArea: worst?.area)))
            Windows.showChecker()
        }
        self.overlay = overlay
        overlay.show()
    }

    // MARK: Lens

    @objc func toggleLens() {
        // The lens would take keyboard focus from an open picker overlay.
        guard overlay == nil, !isCapturing else { return }
        if !LensController.shared.isOpen && !Permissions.hasScreenRecording && !Permissions.didExplain {
            Windows.showPermission()
            return
        }
        LensController.shared.toggle()
    }

    // MARK: Captures

    @objc func captureRegion() { freezeThen(delayed: false) { self.showRegionPicker($0, delayed: false) } }
    @objc func captureRegionDelayed() { freezeThen(delayed: true) { self.showRegionPicker($0, delayed: true) } }

    private func showRegionPicker(_ displays: [FrozenDisplay], delayed: Bool) {
        let overlay = FreezeOverlay(displays: displays, mode: .region) { [weak self] outcome in
            self?.overlay = nil
            switch outcome {
            case let .region(display, rect):
                guard let image = display.image.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)) else { return }
                self?.finishCapture(image, scale: display.geometry.scale, kind: .region, delayed: delayed)
            case let .display(display):
                self?.finishCapture(display.image, scale: display.geometry.scale, kind: .display, delayed: delayed)
            default:
                break
            }
        }
        self.overlay = overlay
        overlay.show()
    }

    @objc func captureFrontWindow() {
        guard canStartCapture() else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let shot = try await ScreenCapture.captureFrontWindow()
                finishCapture(shot.image, scale: shot.scale, kind: .window(appName: shot.appName), delayed: false)
            } catch {
                report(error)
            }
        }
    }

    @objc func captureDisplay() {
        freezeThen(delayed: false) { displays in
            let mouse = NSEvent.mouseLocation
            guard let display = displays.first(where: { $0.geometry.contains(global: mouse) }) ?? displays.first else { return }
            self.finishCapture(display.image, scale: display.geometry.scale, kind: .display, delayed: false)
        }
    }

    private func finishCapture(_ image: CGImage, scale: CGFloat, kind: CaptureRecord.Kind, delayed: Bool) {
        let record = CaptureRecord(kind: kind, pixelWidth: image.width, pixelHeight: image.height, delayed: delayed)
        CaptureOutput.copyToClipboard(image, scale: scale)
        SessionStore.shared.add(.capture(record))
        Windows.showCaptureResult(CaptureResult(image: image, scale: scale, record: record))
    }

    // MARK: Freeze plumbing

    private func canStartCapture() -> Bool {
        // A hotkey can fire while a save panel or alert runs modally; an
        // overlay above it would never receive Esc or clicks.
        guard overlay == nil, !isCapturing, NSApp.modalWindow == nil else { return false }
        if !Permissions.hasScreenRecording && !Permissions.didExplain {
            Windows.showPermission()
            return false
        }
        return true
    }

    /// Optionally waits three seconds (so hover states and menus can be
    /// opened), then freezes every display and hands the frames on.
    private func freezeThen(delayed: Bool, _ next: @escaping ([FrozenDisplay]) -> Void) {
        guard canStartCapture() else { return }
        isCapturing = true
        Task {
            if delayed { await CountdownHUD.run(seconds: 3) }
            do {
                let displays = try await ScreenCapture.freezeDisplays()
                isCapturing = false
                next(displays)
            } catch {
                isCapturing = false
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        if case ScreenCapture.Failure.permissionDenied = error {
            Windows.showPermission()
            return
        }
        let alert = NSAlert()
        alert.messageText = "The capture did not work"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Windows

    @objc func showChecker() { Windows.showChecker() }
    @objc func showSessionLog() { Windows.showSessionLog() }
    @objc func showSettings() { Windows.showSettings() }
    @objc func showPermission() { Windows.showPermission() }
    @objc func checkForUpdates() { Updater.shared.checkForUpdates() }

    @objc func showAbout() {
        let credits = NSAttributedString(
            string: "Free contrast, color-vision and capture tools from accessibility.build. Screen pixels are processed on this Mac and never uploaded.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor]
        )
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
