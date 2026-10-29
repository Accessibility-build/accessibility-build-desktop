import Foundation

/// WCAG 2.x contrast.
public enum WCAG {
    /// Relative luminance per WCAG 2.2. The spec's linearization threshold
    /// is 0.04045 (older texts say 0.03928); no 8-bit channel value falls
    /// between the two, so both give identical results for hex colors.
    public static func relativeLuminance(_ c: SRGB) -> Double {
        0.2126 * Transfer.toLinear(c.r) + 0.7152 * Transfer.toLinear(c.g) + 0.0722 * Transfer.toLinear(c.b)
    }

    /// Fast path for 8-bit channels, used when scanning many pixels.
    public static func relativeLuminance(r8: UInt8, g8: UInt8, b8: UInt8) -> Double {
        0.2126 * Transfer.linear8[Int(r8)] + 0.7152 * Transfer.linear8[Int(g8)] + 0.0722 * Transfer.linear8[Int(b8)]
    }

    public static func contrastRatio(luminance l1: Double, _ l2: Double) -> Double {
        (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    public static func contrastRatio(_ a: SRGB, _ b: SRGB) -> Double {
        contrastRatio(luminance: relativeLuminance(a), relativeLuminance(b))
    }

    /// Ratio text for display, truncated (never rounded up) to two
    /// decimals: 4.499 must read "4.49:1", not "4.50:1", because WCAG
    /// thresholds are not rounded and a rounded figure would show a
    /// failing pair as passing.
    public static func formatRatio(_ ratio: Double) -> String {
        let truncated = (ratio * 100 + 1e-9).rounded(.down) / 100
        return String(format: "%.2f:1", truncated)
    }

    /// The same figure phrased for speech, e.g. "4.49 to 1".
    public static func spokenRatio(_ ratio: Double) -> String {
        let truncated = (ratio * 100 + 1e-9).rounded(.down) / 100
        return String(format: "%.2f to 1", truncated)
    }
}

/// One WCAG requirement a color pair can be checked against.
public struct ContrastRequirement: Hashable, Sendable, Identifiable {
    public let id: String
    /// Short name shown in the results table.
    public let name: String
    /// Success criterion number, e.g. "1.4.3".
    public let criterion: String
    public let criterionTitle: String
    public let level: String
    public let minimum: Double

    public func passes(_ ratio: Double) -> Bool { ratio >= minimum }

    public static let normalTextAA = ContrastRequirement(
        id: "text-aa", name: "Normal text", criterion: "1.4.3",
        criterionTitle: "Contrast (Minimum)", level: "AA", minimum: 4.5)
    public static let normalTextAAA = ContrastRequirement(
        id: "text-aaa", name: "Normal text", criterion: "1.4.6",
        criterionTitle: "Contrast (Enhanced)", level: "AAA", minimum: 7)
    public static let largeTextAA = ContrastRequirement(
        id: "large-aa", name: "Large text", criterion: "1.4.3",
        criterionTitle: "Contrast (Minimum)", level: "AA", minimum: 3)
    public static let largeTextAAA = ContrastRequirement(
        id: "large-aaa", name: "Large text", criterion: "1.4.6",
        criterionTitle: "Contrast (Enhanced)", level: "AAA", minimum: 4.5)
    public static let nonText = ContrastRequirement(
        id: "non-text", name: "UI components and graphics", criterion: "1.4.11",
        criterionTitle: "Non-text Contrast", level: "AA", minimum: 3)

    /// Table order in the results window.
    public static let all: [ContrastRequirement] = [
        .normalTextAA, .normalTextAAA, .largeTextAA, .largeTextAAA, .nonText,
    ]

    public var w3cURL: URL {
        let anchor: String
        switch criterion {
        case "1.4.3": anchor = "contrast-minimum"
        case "1.4.6": anchor = "contrast-enhanced"
        default: anchor = "non-text-contrast"
        }
        return URL(string: "https://www.w3.org/WAI/WCAG22/quickref/#\(anchor)")!
    }
}
