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

    /// The nearest passing color for each unmet goal, on both sides of the pair.
    var fixes: [Fix] {
        let r = ratio
        let goals: [(String, Double)] = [
            ("AA large text and UI, 3:1", 3),
            ("AA normal text, 4.5:1", 4.5),
            ("AAA normal text, 7:1", 7),
        ].filter { r < $0.1 }
        var out: [Fix] = []
        for (goal, target) in goals {
            for side in [AutoFix.Side.text, .background] {
                let color = AutoFix.nudge(text: text, background: background, target: target, side: side)
                let after = side == .text ? WCAG.contrastRatio(color, background) : WCAG.contrastRatio(text, color)
                // The search can fail when the target is out of reach at this hue.
                guard after >= target else { continue }
                out.append(Fix(side: side, goal: goal, target: target, color: color, ratio: after))
            }
        }
        return out
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
