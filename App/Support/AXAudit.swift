#if DEBUG
import AppKit

/// Debug builds only: walks a window's accessibility tree in-process, the
/// tree VoiceOver and Voice Control read, and lists controls and images
/// that have no name. Runs as part of `-snapshotDir`, writing an outline per
/// window and one combined findings file.
@MainActor
enum AXAudit {
    struct Result {
        var outline: [String] = []
        var findings: [String] = []
    }

    private static let namedRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXTextField", "AXPopUpButton",
        "AXMenuButton", "AXComboBox", "AXDisclosureTriangle", "AXIncrementor", "AXLink", "AXImage",
        "AXColorWell", "AXSearchField", "AXSegmentedControl", "AXTabGroup",
    ]

    static func audit(_ window: NSWindow) -> Result {
        var result = Result()
        visit(window, depth: 0, path: window.title, into: &result)
        return result
    }

    private struct Node {
        var role: String?
        var name: String?
        var value: String?
        var help: String?
        var isElement: Bool
        var labelledByElement: Bool
        var children: [NSObject]
    }

    /// Reads through the NSAccessibility protocol, which is what SwiftUI and
    /// AppKit implement and what VoiceOver ultimately sees. The legacy
    /// attribute API returns little for SwiftUI elements.
    private static func node(_ object: NSObject) -> Node {
        // Read by selector: the protocol members share names with NSObject's
        // older informal accessibility methods, which Swift cannot tell apart.
        func get(_ key: String) -> Any? {
            guard object.responds(to: NSSelectorFromString(key)) else { return nil }
            return object.value(forKey: key)
        }
        func text(_ key: String) -> String? {
            guard let s = get(key) as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        // The legacy attribute API still answers for some SwiftUI nodes the
        // protocol does not, so read both and take whichever has content.
        func legacy(_ attribute: NSAccessibility.Attribute) -> Any? { object.accessibilityAttributeValue(attribute) }
        func legacyText(_ attribute: NSAccessibility.Attribute) -> String? {
            guard let s = legacy(attribute) as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        let role = (get("accessibilityRole") as? String) ?? legacyText(.role)
        let subrole = (get("accessibilityRoleDescription") as? String).flatMap { _ in legacyText(.subrole) } ?? legacyText(.subrole)
        // Window buttons name themselves through their subrole.
        let systemName = ["AXCloseButton": "close", "AXMinimizeButton": "minimize", "AXZoomButton": "zoom", "AXFullScreenButton": "full screen"][subrole ?? ""]
        let name = text("accessibilityLabel") ?? text("accessibilityTitle") ?? legacyText(.description) ?? legacyText(.title) ?? systemName
        let value = get("accessibilityValue").map { "\($0)" }
        let explicit = get("isAccessibilityElement") as? Bool
        let labelled = get("accessibilityTitleUIElement") != nil || legacy(.titleUIElement) != nil
        var children = (get("accessibilityChildren") as? [NSObject]) ?? []
        if children.isEmpty { children = (legacy(.children) as? [NSObject]) ?? [] }
        return Node(role: role, name: name, value: value, help: text("accessibilityHelp") ?? legacyText(.help),
                    isElement: explicit ?? !object.accessibilityIsIgnored(), labelledByElement: labelled, children: children)
    }

    private static func visit(_ object: NSObject, depth: Int, path: String, into result: inout Result) {
        guard depth < 60 else { return }
        let n = node(object)
        let role = n.role ?? "?"
        let reported = n.isElement || object is NSWindow

        if reported {
            var line = String(repeating: "  ", count: depth) + role
            if let name = n.name { line += " \"\(name)\"" }
            if let value = n.value, !value.isEmpty, value.count < 80 { line += " value=\(value)" }
            if let help = n.help { line += " help=\"\(help.prefix(60))\"" }
            result.outline.append(line)

            if namedRoles.contains(role), n.name == nil, !n.labelledByElement {
                // A text field's value is its content, not its name; a
                // slider's value is a number. Neither counts as a label.
                result.findings.append("\(path): \(role)\(n.value.map { " (value \($0.prefix(30)))" } ?? "") has no accessible name")
            }
        }

        // A scroll bar's arrow and page parts are AppKit's, named by subrole.
        if role == "AXScrollBar" { return }
        let childPath = reported ? (n.name.map { "\(path) > \($0)" } ?? path) : path
        for child in n.children {
            visit(child, depth: reported ? depth + 1 : depth, path: childPath, into: &result)
        }
    }

    static func write(_ result: Result, name: String, to dir: URL) {
        let outline = result.outline.joined(separator: "\n") + "\n"
        try? outline.write(to: dir.appendingPathComponent("ax-\(name).txt"), atomically: true, encoding: .utf8)
        let findingsURL = dir.appendingPathComponent("ax-findings.txt")
        let existing = (try? String(contentsOf: findingsURL, encoding: .utf8)) ?? ""
        let section = "## \(name): \(result.findings.count) finding(s)\n" + result.findings.map { "- \($0)\n" }.joined()
        try? (existing + section).write(to: findingsURL, atomically: true, encoding: .utf8)
    }
}
#endif
