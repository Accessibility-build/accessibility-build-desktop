import Foundation

/// OKLCH conversion and sRGB gamut mapping, matching culori 4 (which the
/// website's lib/color/oklch.ts uses), so auto-fix suggestions agree.
public struct OKLCH: Hashable, Sendable {
    public var l: Double
    public var c: Double
    /// Hue in degrees. Achromatic colors report 0, as the website does.
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }

    public init(_ color: SRGB) {
        let r = Transfer.toLinear(color.r), g = Transfer.toLinear(color.g), b = Transfer.toLinear(color.b)
        let lms = (
            cbrt(0.412221469470763 * r + 0.5363325372617348 * g + 0.0514459932675022 * b),
            cbrt(0.2119034958178252 * r + 0.6806995506452344 * g + 0.1073969535369406 * b),
            cbrt(0.0883024591900564 * r + 0.2817188391361215 * g + 0.6299787016738222 * b)
        )
        let L = 0.210454268309314 * lms.0 + 0.7936177747023054 * lms.1 - 0.0040720430116193 * lms.2
        let A = 1.9779985324311684 * lms.0 - 2.4285922420485799 * lms.1 + 0.450593709617411 * lms.2
        let B = 0.0259040424655478 * lms.0 + 0.7827717124575296 * lms.1 - 0.8086757549230774 * lms.2
        let chroma = (A * A + B * B).squareRoot()
        var hue = 0.0
        if chroma != 0 {
            hue = atan2(B, A) * 180 / .pi
            hue = hue.truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
        }
        self.init(l: L, c: chroma, h: hue)
    }

    /// Unclamped sRGB (gamma-encoded) channels; may fall outside 0...1.
    func rawRGB() -> (Double, Double, Double) {
        let a = c != 0 ? c * cos(h / 180 * .pi) : 0
        let b = c != 0 ? c * sin(h / 180 * .pi) : 0
        let L = pow(l + 0.3963377773761749 * a + 0.2158037573099136 * b, 3)
        let M = pow(l - 0.1055613458156586 * a - 0.0638541728258133 * b, 3)
        let S = pow(l - 0.0894841775298119 * a - 1.2914855480194092 * b, 3)
        let lr = 4.0767416360759574 * L - 3.3077115392580616 * M + 0.2309699031821044 * S
        let lg = -1.2684379732850317 * L + 2.6097573492876887 * M - 0.3413193760026573 * S
        let lb = -0.0041960761386756 * L - 0.7034186179359362 * M + 1.7076146940746117 * S
        return (Transfer.toGamma(lr), Transfer.toGamma(lg), Transfer.toGamma(lb))
    }

    func isDisplayable() -> Bool {
        let (r, g, b) = rawRGB()
        return (0...1).contains(r) && (0...1).contains(g) && (0...1).contains(b)
    }

    /// Maps into sRGB by lowering chroma while keeping lightness and hue
    /// (culori's clampChroma in OKLCH mode), then converts.
    public func toSRGB() -> SRGB {
        if isDisplayable() {
            let (r, g, b) = rawRGB()
            return SRGB(r: r, g: g, b: b)
        }
        var clamped = self
        clamped.c = 0
        if !clamped.isDisplayable() {
            let (r, g, b) = clamped.rawRGB()
            return SRGB(r: r, g: g, b: b)
        }
        var start = 0.0
        var end = c
        let resolution = 0.4 / 8192 // culori: chroma range / 2^13
        var lastGood = 0.0
        while end - start > resolution {
            clamped.c = start + (end - start) * 0.5
            if clamped.isDisplayable() {
                lastGood = clamped.c
                start = clamped.c
            } else {
                end = clamped.c
            }
        }
        if !clamped.isDisplayable() { clamped.c = lastGood }
        let (r, g, b) = clamped.rawRGB()
        return SRGB(r: r, g: g, b: b)
    }
}
