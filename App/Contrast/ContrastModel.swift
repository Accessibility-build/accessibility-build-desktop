import AuditCore
import ColorCore
import Foundation
import Observation

@Observable
@MainActor
final class ContrastModel {
    static let shared = ContrastModel()

    private(set) var text = SRGB(hex: "#767676")!
    private(set) var background = SRGB.white
    var textField = "#767676"
    var backgroundField = "#FFFFFF"
    var textError: String?
    var backgroundError: String?
    /// Set when the background came from the lowest-contrast pixel of an area.
    private(set) var worstCaseArea: PixelRect?
    private(set) var recent: [ContrastCheck] = RecentColors.load()

    var ratio: Double { WCAG.contrastRatio(text, background) }
    var lc: Double { APCA.lc(text: text, background: background) }

    func load(text: SRGB, background: SRGB, worstCaseArea: PixelRect?) {
        set(text: text, background: background)
        self.worstCaseArea = worstCaseArea
        remember()
    }

    func setText(_ c: SRGB) { set(text: c, background: background) }
    func setBackground(_ c: SRGB) { set(text: text, background: c) }

    private func set(text: SRGB, background: SRGB) {
        self.text = text.quantized
        self.background = background.quantized
        textField = self.text.hex
        backgroundField = self.background.hex
        textError = nil
        backgroundError = nil
        worstCaseArea = nil
    }

    static let hexHint = "Enter a hex color such as #1A7F37."

    /// Applies a typed value as soon as it parses; reports an error only
    /// when the user commits something that does not.
    func textFieldChanged(commit: Bool) {
        if let c = SRGB(hex: textField) {
            if c.quantized != text { text = c.quantized; worstCaseArea = nil }
            textError = nil
            if commit { textField = text.hex; remember() }
        } else if commit {
            textError = Self.hexHint
        }
    }

    func backgroundFieldChanged(commit: Bool) {
        if let c = SRGB(hex: backgroundField) {
            if c.quantized != background { background = c.quantized; worstCaseArea = nil }
            backgroundError = nil
            if commit { backgroundField = background.hex; remember() }
        } else if commit {
            backgroundError = Self.hexHint
        }
    }

    func swap() {
        set(text: background, background: text)
    }

    // MARK: Fixes

    struct Fix: Identifiable, Hashable {
        let side: AutoFix.Side
        let goal: String
        let target: Double
        let color: SRGB
        let ratio: Double
        var id: String { "\(side)-\(target)" }
        var sideLabel: String { side == .text ? "Text color" : "Background color" }
    }

    /// The goal the suggestions aim for: the next WCAG level this pair
    /// does not reach (AA for normal text, then AAA). Nil once AAA passes.
    var fixGoal: (label: String, target: Double)? {
        let r = ratio
        if r < 4.5 { return ("AA, normal text", 4.5) }
        if r < 7 { return ("AAA, normal text", 7) }
        return nil
    }

    /// The nearest passing color on each side of the pair, for `fixGoal`.
    var fixes: [Fix] {
        guard let goal = fixGoal else { return [] }
        return [AutoFix.Side.text, .background].compactMap { side in
            let color = AutoFix.nudge(text: text, background: background, target: goal.target, side: side)
            let after = side == .text ? WCAG.contrastRatio(color, background) : WCAG.contrastRatio(text, color)
            // Out of reach at this hue (white cannot get lighter, for one).
            guard after >= goal.target else { return nil }
            return Fix(side: side, goal: goal.label, target: goal.target, color: color, ratio: after)
        }
    }

    func apply(_ fix: Fix) {
        if fix.side == .text { setText(fix.color) } else { setBackground(fix.color) }
        remember()
    }

    // MARK: Recent pairs

    private func remember() {
        let check = ContrastCheck(text: text, background: background)
        recent.removeAll { $0.text == check.text && $0.background == check.background }
        recent.insert(check, at: 0)
        recent = Array(recent.prefix(10))
        RecentColors.save(recent)
    }

    func clearRecent() {
        recent = []
        RecentColors.save([])
    }
}

/// The last ten pairs, kept in the sandbox's UserDefaults as hex strings.
enum RecentColors {
    private static let key = "recentPairs"

    static func load() -> [ContrastCheck] {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return raw.compactMap { pair in
            let parts = pair.split(separator: "/").map(String.init)
            guard parts.count == 2, let t = SRGB(hex: parts[0]), let b = SRGB(hex: parts[1]) else { return nil }
            return ContrastCheck(text: t, background: b)
        }
    }

    static func save(_ checks: [ContrastCheck]) {
        UserDefaults.standard.set(checks.map { "\($0.text.hex)/\($0.background.hex)" }, forKey: key)
    }
}
