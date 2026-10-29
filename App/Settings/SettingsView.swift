import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var autoUpdate = Updater.shared.automaticallyChecks
    @State private var hasPermission = Permissions.hasScreenRecording

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                ForEach(Shortcuts.all) { entry in
                    LabeledContent(entry.title) {
                        ShortcutRecorder(name: entry.name, label: "\(entry.title) shortcut")
                    }
                }
                Text("Click a shortcut and press a new combination. Press Delete to remove one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open Accessibility Build at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(Palette.fail)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { Updater.shared.automaticallyChecks = autoUpdate }
                Button("Check for Updates Now") { Updater.shared.checkForUpdates() }
            }

            Section("Screen Recording") {
                Label(
                    hasPermission ? "Allowed. The picker, lens and captures can read the screen." : "Not allowed yet. The picker, lens and captures need it.",
                    systemImage: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                Button("Open Screen Recording Settings") { Permissions.openSystemSettings() }
            }

            Section("Privacy") {
                Text("Screen pixels are processed on this Mac and never uploaded. There is no account, no analytics and no tracking. The only network requests are the update check, which fetches a small file from accessibility.build, and update downloads from GitHub when you choose to install one.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Clear Recent Colors") {
                    ContrastModel.shared.clearRecent()
                    Announcer.say("Recent colors cleared")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .onAppear { hasPermission = Permissions.hasScreenRecording }
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
