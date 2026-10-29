import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Settings the way macOS apps present them: a fixed-size window with
/// toolbar tabs, each tab a short grouped form that fits without scrolling.
final class SettingsTabsController: NSTabViewController {
    static let tabs: [(title: String, symbol: String, view: AnyView)] = [
        ("General", "gearshape", AnyView(GeneralSettings())),
        ("Shortcuts", "keyboard", AnyView(ShortcutSettings())),
        ("Privacy", "hand.raised", AnyView(PrivacySettings())),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        for tab in Self.tabs {
            let host = NSHostingController(rootView: tab.view)
            // The tab controller titles the window from the selected tab's
            // view controller; without this it reads "Untitled".
            host.title = tab.title
            // Each tab sizes the window to its own content, as System
            // Settings-style preference windows do.
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            // Stable identifiers, so the toolbar code can tell tabs apart
            // from system items.
            item.identifier = "settings.\(tab.title.lowercased())"
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            addTabViewItem(item)
        }
    }

    // On macOS 26 and later, toolbar items placed side by side are drawn as
    // one joined group, so the three tabs touched. A standard space item
    // between neighbours separates them, as in Apple's own settings windows.
    override func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let identifiers = super.toolbarDefaultItemIdentifiers(toolbar)
        let tabs = Set(tabViewItems.compactMap { $0.identifier as? String }.map { NSToolbarItem.Identifier($0) })
        var spaced: [NSToolbarItem.Identifier] = []
        for id in identifiers {
            if tabs.contains(id), let last = spaced.last, tabs.contains(last) {
                spaced.append(.space)
            }
            spaced.append(id)
        }
        return spaced
    }

    override func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        super.toolbarAllowedItemIdentifiers(toolbar) + [.space]
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        // The window takes the selected tab's name, like every macOS settings window.
        view.window?.title = tabViewItem?.label ?? "Settings"
    }
}

struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var autoUpdate = Updater.shared.automaticallyChecks

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError {
                    Text(loginError).foregroundStyle(Palette.fail)
                }
            } footer: {
                Text("Accessibility Build lives in the menu bar and uses almost no resources while idle.")
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { Updater.shared.automaticallyChecks = autoUpdate }
                LabeledContent("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                    Button("Check Now") { Updater.shared.checkForUpdates() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "macOS did not accept the change: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(Shortcuts.all) { entry in
                    LabeledContent(entry.title) {
                        ShortcutRecorder(name: entry.name, label: "\(entry.title) shortcut")
                    }
                }
            } footer: {
                Text("Click a shortcut, then press the new combination. Press Delete to remove it.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PrivacySettings: View {
    @State private var hasPermission = Permissions.hasScreenRecording

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Open System Settings") { Permissions.openSystemSettings() }
                } label: {
                    Label {
                        Text("Screen Recording")
                        Text(hasPermission ? "Allowed" : "Not allowed yet. The picker, lens and captures need it.")
                    } icon: {
                        Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasPermission ? Palette.pass : Palette.caution)
                    }
                }
            }

            Section {
                LabeledContent {
                    Button("Clear") {
                        ContrastModel.shared.clearRecent()
                        Announcer.say("Recent colors cleared")
                    }
                } label: {
                    Text("Recent colors")
                    Text("The last ten pairs, kept on this Mac.")
                }
            } footer: {
                Text("Screen pixels are processed on this Mac and never uploaded. There is no account, analytics or tracking. The only network requests are the update check, which fetches a small file from accessibility.build, and update downloads from GitHub when you choose to install one.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { hasPermission = Permissions.hasScreenRecording }
    }
}

/// The library's recorder field, with its accessible name set on the
/// AppKit control itself: the stock SwiftUI wrapper leaves the field
/// unnamed, so VoiceOver announced only "search text field".
struct ShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let label: String

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let field = KeyboardShortcuts.RecorderCocoa(for: name)
        apply(to: field)
        return field
    }

    func updateNSView(_ field: KeyboardShortcuts.RecorderCocoa, context: Context) {
        apply(to: field)
    }

    // Text fields answer accessibility through their cell.
    private func apply(to field: KeyboardShortcuts.RecorderCocoa) {
        field.setAccessibilityLabel(label)
        field.cell?.setAccessibilityLabel(label)
    }
}

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Allow Screen Recording")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Accessibility Build reads the pixels on your screen to pick colors, run the lens and take captures. What it sees stays on this Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Step(number: 1, text: "Choose Allow Screen Recording.")
                Step(number: 2, text: "In System Settings, turn on Accessibility Build.")
                Step(number: 3, text: "Choose Quit and Reopen.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 10) {
                Button {
                    Permissions.request()
                } label: {
                    Text("Allow Screen Recording").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    Permissions.relaunch()
                } label: {
                    Text("Quit and Reopen").frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button("Check colors without it") { Windows.showChecker() }
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 420)
    }

    private struct Step: View {
        let number: Int
        let text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.secondary, lineWidth: 1))
                    .foregroundStyle(.primary)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                Text(text)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
