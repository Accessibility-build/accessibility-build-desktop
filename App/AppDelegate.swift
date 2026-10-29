import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory apps never show this menu bar, but text fields still
        // route Copy, Paste, Undo and Close through it. Without it, Command-V
        // does nothing in the hex fields.
        NSApp.mainMenu = MainMenu.make()
        #if DEBUG
        if Snapshot.runIfRequested() { return }
        #endif
        Updater.shared.start()
        statusMenu = StatusMenu()
        Shortcuts.register()

        #if DEBUG
        if let requested = UserDefaults.standard.string(forKey: "openWindows") {
            openForTesting(requested)
            return
        }
        #endif
        if !Permissions.hasScreenRecording && !Permissions.didExplain {
            Windows.showPermission()
        }
    }

    #if DEBUG
    /// Debug builds only: `-openWindows checker,log,settings,permission,lens`
    /// opens windows at launch. A menu-bar app has no window to drive
    /// otherwise, so UI tests and accessibility audits use this.
    private func openForTesting(_ list: String) {
        for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch name {
            case "checker": Windows.showChecker()
            case "log": Windows.showSessionLog()
            case "settings": Windows.showSettings()
            case "permission": Windows.showPermission()
            case "lens": LensController.shared.open()
            default: break
            }
        }
    }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again from Finder or Spotlight should show
        // something, since a menu-bar app has no window by default.
        if !flag { Permissions.hasScreenRecording ? Windows.showChecker() : Windows.showPermission() }
        return true
    }
}

enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Accessibility Build", action: #selector(AppActions.showAbout), keyEquivalent: "").target = AppActions.shared
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppActions.showSettings), keyEquivalent: ",").target = AppActions.shared
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Accessibility Build", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}
