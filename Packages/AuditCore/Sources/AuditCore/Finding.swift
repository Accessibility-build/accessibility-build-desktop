import ColorCore
import Foundation

/// The plain-language audit sentence behind "Copy finding".
///
/// The picker cannot know whether a pair is body text, large text or an
/// icon, so the sentence states the result for each case it bears on and
/// never claims more than the ratio supports.
public enum FindingText {
    public static func sentence(text: SRGB, background: SRGB) -> String {
        let ratio = WCAG.contrastRatio(text, background)
        let shown = WCAG.formatRatio(ratio)
        let pair = "Text color \(text.hex) on background \(background.hex) has a contrast ratio of \(shown)."

        let verdict: String
        switch ratio {
        case 7...:
            verdict = "This meets WCAG 2.2 Success Criterion 1.4.6 Contrast (Enhanced) at Level AAA (7:1) and 1.4.3 Contrast (Minimum) at Level AA (4.5:1)."
        case 4.5..<7:
            verdict = "This meets WCAG 2.2 Success Criterion 1.4.3 Contrast (Minimum) at Level AA for text of any size (4.5:1). It does not meet 1.4.6 Contrast (Enhanced) at Level AAA for normal text, which requires 7:1."
        case 3..<4.5:
            verdict = "For normal text this fails WCAG 2.2 Success Criterion 1.4.3 Contrast (Minimum) at Level AA, which requires 4.5:1. It meets the 3:1 minimum for large text under 1.4.3 and for user interface components and graphics under 1.4.11 Non-text Contrast."
        default:
            verdict = "This fails WCAG 2.2 Success Criterion 1.4.3 Contrast (Minimum) at Level AA for both normal text (4.5:1) and large text (3:1). If the colors belong to a user interface component or graphic, it also fails 1.4.11 Non-text Contrast, which requires 3:1."
        }
        return "\(pair) \(verdict)"
    }
}
