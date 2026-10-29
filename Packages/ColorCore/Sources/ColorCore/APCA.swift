import Foundation

/// APCA lightness contrast (Lc), the method in the WCAG 3 working draft.
///
/// Port of the website's lib/color/apca.ts, which follows APCA-W3 0.1.9.
/// APCA is guidance, not a WCAG 2 conformance test, so the app never turns
/// an Lc value into a WCAG pass or fail.
public enum APCA {
    static let rCoef = 0.2126729
    static let gCoef = 0.7151522
    static let bCoef = 0.072175
    static let mainTRC = 2.4
    static let blkThrs = 0.022
    static let blkClmp = 1.414
    static let deltaYmin = 0.0005
    static let normBG = 0.56
    static let normTXT = 0.57
    static let revBG = 0.65
    static let revTXT = 0.62
    static let scale = 1.14
    static let loClip = 0.1
    static let loOffset = 0.027

    /// APCA's "simple gamma" luminance (not the WCAG 2 luminance).
    public static func luminance(_ c: SRGB) -> Double {
        rCoef * pow(c.r, mainTRC) + gCoef * pow(c.g, mainTRC) + bCoef * pow(c.b, mainTRC)
    }

    static func softClip(_ y: Double) -> Double {
        y < blkThrs ? y + pow(blkThrs - y, blkClmp) : y
    }

    /// Signed Lc: positive for dark text on a light background, negative
    /// for light text on a dark background. Thresholds use the magnitude.
    public static func lc(text: SRGB, background: SRGB) -> Double {
        let textY = softClip(luminance(text))
        let bgY = softClip(luminance(background))
        if abs(bgY - textY) < deltaYmin { return 0 }

        let lc: Double
        if bgY > textY {
            let sapc = (pow(bgY, normBG) - pow(textY, normTXT)) * scale
            lc = sapc < loClip ? 0 : sapc - loOffset
        } else {
            let sapc = (pow(bgY, revBG) - pow(textY, revTXT)) * scale
            lc = sapc > -loClip ? 0 : sapc + loOffset
        }
        return lc * 100
    }

    public enum UseCase: String, CaseIterable, Sendable, Identifiable {
        case bodyText, fluentText, contentText, largeText, uiComponent, nonText, spotText
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .bodyText: "Body text"
            case .fluentText: "Fluent text"
            case .contentText: "Content text"
            case .largeText: "Large text"
            case .uiComponent: "UI components"
            case .nonText: "Non-text"
            case .spotText: "Spot text"
            }
        }

        /// Bronze Simple Mode thresholds, as on the website.
        public var thresholds: (pass: Double, caution: Double) {
            switch self {
            case .bodyText: (90, 75)
            case .fluentText: (75, 60)
            case .contentText: (60, 45)
            case .largeText: (45, 30)
            case .uiComponent: (60, 45)
            case .nonText: (45, 30)
            case .spotText: (30, 15)
            }
        }
    }

    public enum Level: String, Sendable {
        case pass = "Pass"
        case caution = "Use caution"
        case fail = "Fail"
    }

    public static func level(_ lc: Double, for useCase: UseCase) -> Level {
        let magnitude = abs(lc)
        let t = useCase.thresholds
        if magnitude >= t.pass { return .pass }
        if magnitude >= t.caution { return .caution }
        return .fail
    }

    /// "Lc 63.1" style text, one decimal like the APCA reference tools.
    public static func format(_ lc: Double) -> String {
        String(format: "Lc %.1f", lc)
    }
}
