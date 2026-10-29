import AppKit
import AuditCore
import ColorCore
import SwiftUI
import UniformTypeIdentifiers

/// Checks and captures from this session. Kept in memory only; nothing is
/// written to disk unless the user saves the Markdown export.
@Observable
@MainActor
final class SessionStore {
    static let shared = SessionStore()
    private(set) var entries: [LogEntry] = []

    func add(_ entry: LogEntry) { entries.append(entry) }
    func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    func clear() { entries.removeAll() }

    var markdown: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return MarkdownExport.session(entries, generated: Date(), appVersion: version)
    }
}

struct SessionLogView: View {
    let store: SessionStore
    @State private var selection = Set<UUID>()
    @State private var confirmsClear = false

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Checks Yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Contrast picks and captures from this session appear here, ready to export as a Markdown summary.")
                )
            } else {
                List(selection: $selection) {
                    ForEach(store.entries) { entry in
                        EntryRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Remove") { remove([entry.id]) }
                            }
                            .accessibilityAction(named: "Remove") { remove([entry.id]) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onDeleteCommand { remove(selection) }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { remove(selection) } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .disabled(selection.isEmpty)
                .help("Remove the selected entries (Delete)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Pasteboard.copy(store.markdown)
                    Announcer.say("Markdown copied")
                } label: {
                    Label("Copy Markdown", systemImage: "doc.on.doc")
                }
                .disabled(store.entries.isEmpty)
                .help("Copy the session as Markdown")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { save() } label: {
                    Label("Save Markdown", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.entries.isEmpty)
                .help("Save the session as a Markdown file")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { confirmsClear = true } label: {
                    Label("Clear Log", systemImage: "trash")
                }
                .disabled(store.entries.isEmpty)
                .help("Clear the session log")
            }
        }
        .confirmationDialog("Clear the session log?", isPresented: $confirmsClear) {
            Button("Clear Log", role: .destructive) {
                store.clear()
                selection.removeAll()
                Announcer.say("Session log cleared")
            }
        } message: {
            Text("This removes every check and capture listed here. Saved files are not affected.")
        }
    }

    private func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { store.remove(id) }
        selection.subtract(ids)
        Announcer.say(ids.count == 1 ? "Removed" : "Removed \(ids.count) entries")
    }

    @MainActor
    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Accessibility check session.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.markdown.write(to: url, atomically: true, encoding: .utf8)
            Announcer.say("Saved \(url.lastPathComponent)")
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

private struct EntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            switch entry {
            case .contrast(let check):
                Text("Aa")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(check.text))
                    .frame(width: 38, height: 26)
                    .background(Color(check.background), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(check.text.hex) on \(check.background.hex)").monospacedDigit()
                    let pass = ContrastRequirement.normalTextAA.passes(check.ratio)
                    Text("\(WCAG.formatRatio(check.ratio)), \(pass ? "passes" : "fails") AA for normal text")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .capture(let capture):
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.description)
                    Text("\(capture.pixelWidth) × \(capture.pixelHeight) px").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.date, style: .time)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
