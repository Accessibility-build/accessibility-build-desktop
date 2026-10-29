import Foundation

/// An opaque sRGB color with channels in 0...1.
///
/// Every value the app shows or compares is an 8-bit sRGB color, the same
/// thing a CSS hex value describes, so results match what a developer types
/// into a stylesheet and what the website's contrast checker reports.
public struct SRGB: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = SRGB.clamp01(r)
        self.g = SRGB.clamp01(g)
        self.b = SRGB.clamp01(b)
    }

    public init(r8: UInt8, g8: UInt8, b8: UInt8) {
        self.init(r: Double(r8) / 255, g: Double(g8) / 255, b: Double(b8) / 255)
    }

    /// Parses "#RGB", "#RRGGBB" or the same without "#". Surrounding
    /// whitespace is ignored. Returns nil for anything else.
    public init?(hex input: String) {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 3 || s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            r8: UInt8((value >> 16) & 0xFF),
            g8: UInt8((value >> 8) & 0xFF),
            b8: UInt8(value & 0xFF)
        )
    }

    /// 8-bit channels, rounded the way CSS serializers (and culori) do.
    public var r8: UInt8 { SRGB.to8(r) }
    public var g8: UInt8 { SRGB.to8(g) }
    public var b8: UInt8 { SRGB.to8(b) }

    /// Upper-case "#RRGGBB".
    public var hex: String {
        String(format: "#%02X%02X%02X", r8, g8, b8)
    }

    /// The same color snapped to 8-bit channels, so comparisons and
    /// fixtures operate on exactly what `hex` prints.
    public var quantized: SRGB { SRGB(r8: r8, g8: g8, b8: b8) }

    public static let black = SRGB(r: 0, g: 0, b: 0)
    public static let white = SRGB(r: 1, g: 1, b: 1)

    static func clamp01(_ v: Double) -> Double {
        if v.isNaN { return 0 }
        return min(1, max(0, v))
    }

    static func to8(_ v: Double) -> UInt8 {
        // JavaScript's Math.round rounds .5 up; for non-negative values
        // Swift's .toNearestOrAwayFromZero is identical.
        UInt8((clamp01(v) * 255).rounded(.toNearestOrAwayFromZero))
    }
}

/// sRGB transfer functions.
public enum Transfer {
    public static func toLinear(_ c: Double) -> Double {
        let a = abs(c)
        if a <= 0.04045 { return c / 12.92 }
        return (c < 0 ? -1 : 1) * pow((a + 0.055) / 1.055, 2.4)
    }

    public static func toGamma(_ c: Double) -> Double {
        let a = abs(c)
        if a > 0.0031308 { return (c < 0 ? -1 : 1) * (1.055 * pow(a, 1 / 2.4) - 0.055) }
        return c * 12.92
    }

    /// Linear values for the 256 possible 8-bit channel values. The
    /// worst-case search over a dragged area calls this per pixel.
    public static let linear8: [Double] = (0...255).map { toLinear(Double($0) / 255) }
}
