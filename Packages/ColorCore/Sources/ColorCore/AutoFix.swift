import Foundation

/// Nearest passing color, ported from the website's lib/color/autofix.ts.
///
/// Binary-searches OKLCH lightness for the smallest change to one side of
/// the pair that reaches the target, keeping hue and chroma where the sRGB
/// gamut allows. Contrast rises monotonically as lightness moves away from
/// the fixed color, so the search is well defined.
public enum AutoFix {
    public enum Metric: Sendable {
        case wcag
        case apca
    }

    public enum Side: Sendable {
        case text
        case background
    }

    static func evaluate(_ text: SRGB, _ background: SRGB, _ metric: Metric) -> Double {
        switch metric {
        case .wcag: WCAG.contrastRatio(text, background)
        case .apca: abs(APCA.lc(text: text, background: background))
        }
    }

    /// Returns the adjusted color for `side`, quantized to 8 bits. Returns
    /// the original when the pair already meets the target.
    public static func nudge(
        text: SRGB,
        background: SRGB,
        target: Double,
        metric: Metric = .wcag,
        side: Side = .text,
        iterations: Int = 24
    ) -> SRGB {
        let moving = side == .text ? text : background
        let fixed = side == .text ? background : text

        if evaluate(text, background, metric) >= target { return moving }

        let mv = OKLCH(moving)
        let goDown = WCAG.relativeLuminance(fixed) > 0.5
        var lo = goDown ? 0 : mv.l
        var hi = goDown ? mv.l : 1

        func candidate(_ l: Double, chroma: Double? = nil) -> SRGB {
            OKLCH(l: l, c: chroma ?? mv.c, h: mv.h).toSRGB().quantized
        }
        func trial(_ c: SRGB) -> Double {
            side == .text ? evaluate(c, background, metric) : evaluate(text, c, metric)
        }

        let extreme = candidate(goDown ? lo : hi)
        if trial(extreme) < target {
            // Unreachable at this hue even at black or white; dropping
            // chroma sometimes helps, and is the best available answer.
            return candidate(goDown ? lo : hi, chroma: 0)
        }

        for _ in 0..<iterations {
            let mid = (lo + hi) / 2
            let v = trial(candidate(mid))
            if goDown {
                if v >= target { lo = mid } else { hi = mid }
            } else {
                if v >= target { hi = mid } else { lo = mid }
            }
        }
        return candidate(goDown ? lo : hi)
    }
}
