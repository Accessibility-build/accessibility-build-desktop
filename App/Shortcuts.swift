import KeyboardShortcuts

// Defaults use Control-Option-Command. Option-Command-P and Option-Command-L
// are Finder shortcuts (path bar, Downloads), and a global hotkey would take
// them over in every app.
extension KeyboardShortcuts.Name {
    static let pickContrast = Self("pickContrast", initial: .init(.c, modifiers: [.control, .option, .command]))
    static let pickContrastDelayed = Self("pickContrastDelayed")
    static let toggleLens = Self("toggleLens", initial: .init(.l, modifiers: [.control, .option, .command]))
    static let captureRegion = Self("captureRegion", initial: .init(.r, modifiers: [.control, .option, .command]))
    static let captureRegionDelayed = Self("captureRegionDelayed", initial: .init(.d, modifiers: [.control, .option, .command]))
    static let captureWindow = Self("captureWindow")
    static let captureDisplay = Self("captureDisplay")
}

enum Shortcuts {
    struct Entry: Identifiable {
        let name: KeyboardShortcuts.Name
        let title: String
        var id: String { name.rawValue }
    }

    static let all: [Entry] = [
        Entry(name: .pickContrast, title: "Pick contrast"),
        Entry(name: .pickContrastDelayed, title: "Pick contrast in 3 seconds"),
        Entry(name: .toggleLens, title: "Color-vision lens"),
        Entry(name: .captureRegion, title: "Capture region"),
        Entry(name: .captureRegionDelayed, title: "Capture region in 3 seconds"),
        Entry(name: .captureWindow, title: "Capture front window"),
        Entry(name: .captureDisplay, title: "Capture display"),
    ]

    @MainActor
    static func register() {
        let a = AppActions.shared
        KeyboardShortcuts.onKeyUp(for: .pickContrast) { a.pickContrast() }
        KeyboardShortcuts.onKeyUp(for: .pickContrastDelayed) { a.pickContrastDelayed() }
        KeyboardShortcuts.onKeyUp(for: .toggleLens) { a.toggleLens() }
        KeyboardShortcuts.onKeyUp(for: .captureRegion) { a.captureRegion() }
        KeyboardShortcuts.onKeyUp(for: .captureRegionDelayed) { a.captureRegionDelayed() }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { a.captureFrontWindow() }
        KeyboardShortcuts.onKeyUp(for: .captureDisplay) { a.captureDisplay() }
    }
}
