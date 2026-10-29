import AppKit
import KeyboardShortcuts
import SwiftUI

/// First launch, and any time the app is opened again from Finder or
/// Launchpad: a menu-bar app has no window of its own, so without this
/// people (and App Review) can launch it and see nothing happen.
struct WelcomeView: View {
    @State private var hasPermission = Permissions.hasScreenRecording

    private struct Tool: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        let shortcut: KeyboardShortcuts.Name
        var id: String { title }
    }

    private let tools = [
        Tool(symbol: "eyedropper", title: "Pick contrast", detail: "Check any two colors on screen against WCAG 2.2.", shortcut: .pickContrast),
        Tool(symbol: "eye", title: "Color-vision lens", detail: "See what is beneath it as color-blind people may.", shortcut: .toggleLens),
        Tool(symbol: "rectangle.dashed", title: "Capture", detail: "Grab a region, a window or the whole display.", shortcut: .captureRegion),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Welcome to Accessibility Build")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("It lives in the menu bar at the top of your screen. Click its icon to start.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MenuBarHint()

            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 { Divider().padding(.leading, 44) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title).fontWeight(.medium)
                            Text(tool.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(KeyboardShortcuts.getShortcut(for: tool.shortcut)?.description ?? "")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 10) {
                if hasPermission {
                    Button {
                        Windows.close("welcome")
                        AppActions.shared.pickContrast()
                    } label: {
                        Text("Pick Contrast Now").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        Windows.close("welcome")
                        Windows.showPermission()
                    } label: {
                        Text("Allow Screen Recording…").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                Button {
                    Windows.close("welcome")
                    Windows.showChecker()
                } label: {
                    Text("Check Colors by Hex").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 440)
        .onAppear { hasPermission = Permissions.hasScreenRecording }
    }
}

/// A sketch of the right end of the menu bar with the app's icon picked out.
private struct MenuBarHint: View {
    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi").foregroundStyle(.secondary)
            Image(systemName: "battery.75percent").foregroundStyle(.secondary)
            Image(nsImage: StatusIcon.make())
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
            Text("Thu 9:41").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Accessibility Build icon in the menu bar, next to the clock")
    }
}
