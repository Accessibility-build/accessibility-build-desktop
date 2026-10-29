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
        show("checker", title: "Check Colors", size: NSSize(width: 540, height: 680), toolbar: true) {
            ContrastView(model: ContrastModel.shared)
        }
    }

    static func showSessionLog() {
        show("log", title: "Session Log", size: NSSize(width: 540, height: 460), toolbar: true) {
            SessionLogView(store: SessionStore.shared)
        }
    }

    static func showSettings() {
        show("settings", title: "Settings", size: NSSize(width: 540, height: 620)) {
            SettingsView()
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
