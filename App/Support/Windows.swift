import AppKit
import SwiftUI

/// Owns the app's ordinary windows. A menu-bar app has no scene to open
/// windows from a global shortcut, so they are plain NSWindows hosting
/// SwiftUI views, created once and reused.
@MainActor
enum Windows {
    private static var windows: [String: NSWindow] = [:]

    @discardableResult
    static func show<Content: View>(
        _ id: String,
        title: String,
        size: NSSize,
        resizable: Bool = true,
        toolbar: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
            if resizable { style.insert(.resizable) }
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: content())
            if toolbar {
                // SwiftUI's .toolbar items become a real unified window toolbar.
                host.sceneBridgingOptions = [.toolbars]
                window.toolbarStyle = .unified
            }
            window.contentViewController = host
            window.setContentSize(size)
            window.center()
            window.setFrameAutosaveName("window.\(id)")
            windows[id] = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    static func window(_ id: String) -> NSWindow? { windows[id] }

    static func close(_ id: String) {
        windows[id]?.close()
    }

    static func showChecker() {
        let window = show("checker", title: "Check Colors", size: NSSize(width: 540, height: 760), toolbar: true) {
            ContrastView(model: ContrastModel.shared)
        }
        // AppKit would focus the first hex field and select its text, which
        // reads as an edit in progress. Start with nothing focused; Tab
        // reaches the fields.
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }

    static func showSessionLog() {
        show("log", title: "Session Log", size: NSSize(width: 540, height: 460), toolbar: true) {
            SessionLogView(store: SessionStore.shared)
        }
    }

    static func showSettings() {
        if let window = windows["settings"] {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: SettingsTabsController())
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = SettingsTabsController.tabs.first?.title ?? "Settings"
        window.center()
        window.setFrameAutosaveName("window.settings")
        windows["settings"] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    static func showWelcome() {
        show("welcome", title: "Welcome", size: NSSize(width: 440, height: 620), resizable: false) {
            WelcomeView()
        }
    }

    static func showPermission() {
        Permissions.didExplain = true
        show("permission", title: "Screen Recording", size: NSSize(width: 420, height: 560), resizable: false) {
            PermissionView()
        }
    }

    static func showCaptureResult(_ result: CaptureResult) {
        // A new capture replaces the previous result window's content.
        windows["capture"]?.close()
        windows["capture"] = nil
        show("capture", title: result.record.description, size: NSSize(width: 640, height: 500), toolbar: true) {
            CaptureResultView(result: result)
        }
    }
}
