import AppKit

// A menu-bar app with no storyboard: build the application by hand so the
// delegate exists before launch finishes. `run()` blocks for the app's
// lifetime, which keeps the (weakly held) delegate alive.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    #if DEBUG
    // Debug builds only: `-activationPolicy regular` gives the app a Dock
    // icon, because UI automation tools only see regular apps.
    let regular = UserDefaults.standard.string(forKey: "activationPolicy") == "regular"
    app.setActivationPolicy(regular ? .regular : .accessory)
    #else
    app.setActivationPolicy(.accessory)
    #endif
    app.run()
}
