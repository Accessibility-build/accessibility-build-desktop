import AppKit
import ColorCore
import SwiftUI

/// VoiceOver announcements for moments with no focus change to carry the
/// information (a pick, a countdown, a copy).
@MainActor
enum Announcer {
    static func say(_ text: String) {
        let element: Any = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}

/// Verdict colors. The system green and red are too light on white to meet
/// 3:1 for icons, so these are tuned per appearance, including Increase
/// Contrast. Every verdict also carries a word and an icon shape, so color
/// is never the only signal.
enum Palette {
    static let pass = dynamic(light: 0x1A7F37, dark: 0x3FB950, lightHC: 0x0B5D24, darkHC: 0x56D364)
    static let fail = dynamic(light: 0xCF222E, dark: 0xFF7B72, lightHC: 0xA40E26, darkHC: 0xFFA198)
    static let caution = dynamic(light: 0x9A6700, dark: 0xD29922, lightHC: 0x7D4E00, darkHC: 0xE3B341)

    private static func dynamic(light: UInt32, dark: UInt32, lightHC: UInt32, darkHC: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let hex: UInt32
            switch match {
            case .darkAqua: hex = dark
            case .accessibilityHighContrastAqua: hex = lightHC
            case .accessibilityHighContrastDarkAqua: hex = darkHC
            default: hex = light
            }
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Color {
    init(_ c: SRGB) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }
}

extension NSColor {
    convenience init(_ c: SRGB) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Screen Recording permission. macOS caches the answer per launch, so after
/// granting it the app usually has to be reopened before captures work.
@MainActor
enum Permissions {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static var didExplain: Bool {
        get { UserDefaults.standard.bool(forKey: "didExplainScreenRecording") }
        set { UserDefaults.standard.set(newValue, forKey: "didExplainScreenRecording") }
    }

    /// Shows the system prompt the first time; afterwards macOS only lists
    /// the app in System Settings, so open that pane too.
    static func request() {
        if !CGRequestScreenCaptureAccess() { openSystemSettings() }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
