import AppKit
import KeyboardShortcuts

/// The menu-bar item. A native NSMenu, so VoiceOver, keyboard navigation and
/// Voice Control work without custom accessibility code.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        if let button = item.button {
            button.image = StatusIcon.make()
            button.toolTip = "Accessibility Build"
            button.setAccessibilityLabel("Accessibility Build")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // Rebuilt on every open so the lens checkmark, the session count and the
    // permission item always reflect the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if Updater.shared.updateAvailable {
            add(menu, "Update Available…", #selector(AppActions.checkForUpdates), symbol: "arrow.down.circle")
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: "Color"))
        add(menu, "Pick Contrast…", #selector(AppActions.pickContrast), symbol: "eyedropper", shortcut: .pickContrast)
        add(menu, "Pick Contrast in 3 Seconds", #selector(AppActions.pickContrastDelayed), symbol: "timer", shortcut: .pickContrastDelayed)
        let lens = add(menu, "Color-Vision Lens", #selector(AppActions.toggleLens), symbol: "eye", shortcut: .toggleLens)
        lens.state = LensController.shared.isOpen ? .on : .off
        add(menu, "Check Colors…", #selector(AppActions.showChecker), symbol: "circle.lefthalf.filled")

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Capture"))
        add(menu, "Capture Region…", #selector(AppActions.captureRegion), symbol: "rectangle.dashed", shortcut: .captureRegion)
        add(menu, "Capture Region in 3 Seconds", #selector(AppActions.captureRegionDelayed), symbol: "timer", shortcut: .captureRegionDelayed)
        add(menu, "Capture Front Window", #selector(AppActions.captureFrontWindow), symbol: "macwindow", shortcut: .captureWindow)
        add(menu, "Capture Display", #selector(AppActions.captureDisplay), symbol: "display", shortcut: .captureDisplay)
        let count = SessionStore.shared.entries.count
        add(menu, count == 0 ? "Session Log…" : "Session Log (\(count))…", #selector(AppActions.showSessionLog), symbol: "list.bullet.rectangle")

        menu.addItem(.separator())
        if !Permissions.hasScreenRecording {
            add(menu, "Allow Screen Recording…", #selector(AppActions.showPermission), symbol: "lock.open")
        }
        add(menu, "Settings…", #selector(AppActions.showSettings), symbol: "gearshape", key: ",")
        add(menu, "Check for Updates…", #selector(AppActions.checkForUpdates), symbol: "arrow.triangle.2.circlepath")
        add(menu, "About Accessibility Build", #selector(AppActions.showAbout), symbol: "info.circle")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Accessibility Build", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, symbol: String, shortcut: KeyboardShortcuts.Name? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = AppActions.shared
        // Leading symbols are the macOS 26 menu convention; earlier systems
        // keep plain text menus, as their own apps do.
        if #available(macOS 26.0, *) {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if let shortcut { item.setShortcut(for: shortcut) }
        menu.addItem(item)
        return item
    }
}
