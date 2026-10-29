import Foundation

/// Color vision deficiency simulation (Machado, Oliveira and Fernandes 2009),
/// ported from the website's lib/color/cvd.ts.
public enum CVD: String, CaseIterable, Sendable, Identifiable {
    case protanopia, deuteranopia, tritanopia, achromatopsia

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .protanopia: "Protanopia"
        case .deuteranopia: "Deuteranopia"
        case .tritanopia: "Tritanopia"
        case .achromatopsia: "Achromatopsia"
        }
    }

    public var explanation: String {
        switch self {
        case .protanopia: "No red cones"
        case .deuteranopia: "No green cones"
        case .tritanopia: "No blue cones"
        case .achromatopsia: "No color vision"
        }
    }

    /// Row-major 3x3 matrix applied to linear RGB at full severity.
    /// Achromatopsia uses luminance instead and has no matrix.
    public var machadoMatrix: [Double]? {
        switch self {
        case .protanopia:
            [0.152286, 1.052583, -0.204868,
             0.114503, 0.786281, 0.099216,
             -0.003882, -0.048116, 1.051998]
        case .deuteranopia:
            [0.367322, 0.860646, -0.227968,
             0.280085, 0.672501, 0.047413,
             -0.01182, 0.04294, 0.968881]
        case .tritanopia:
            [1.255528, -0.076749, -0.178779,
             -0.078411, 0.930809, 0.147602,
             0.004733, 0.691367, 0.3039]
        case .achromatopsia:
            nil
        }
    }

    /// The color as this deficiency may perceive it. Severity 0 returns the
    /// input; values between 0 and 1 blend toward full dichromacy in sRGB,
    /// exactly as the website does, so both report the same hex.
    public func simulate(_ c: SRGB, severity: Double = 1) -> SRGB {
        if severity <= 0 { return c }
        let s = min(1, severity)

        guard let m = machadoMatrix else {
            // Rec. 709 luma keeps perceived lightness.
            let y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
            return SRGB(r: c.r * (1 - s) + y * s, g: c.g * (1 - s) + y * s, b: c.b * (1 - s) + y * s)
        }

        let r = Transfer.toLinear(c.r), g = Transfer.toLinear(c.g), b = Transfer.toLinear(c.b)
        func gamma(_ v: Double) -> Double {
            if v <= 0 { return 0 }
            if v >= 1 { return 1 }
            return Transfer.toGamma(v)
        }
        let simulated = SRGB(
            r: gamma(m[0] * r + m[1] * g + m[2] * b),
            g: gamma(m[3] * r + m[4] * g + m[5] * b),
            b: gamma(m[6] * r + m[7] * g + m[8] * b)
        )
        if s >= 1 { return simulated }
        return SRGB(
            r: c.r * (1 - s) + simulated.r * s,
            g: c.g * (1 - s) + simulated.g * s,
            b: c.b * (1 - s) + simulated.b * s
        )
    }

    /// Linear-light matrix for the live lens at a given severity, blending
    /// from identity to the Machado matrix. The lens filters in linear light
    /// (Core Image's working space), which is where the model is defined.
    public func linearMatrix(severity: Double) -> [Double] {
        let s = min(1, max(0, severity))
        let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        let target = machadoMatrix ?? [
            0.2126, 0.7152, 0.0722,
            0.2126, 0.7152, 0.0722,
            0.2126, 0.7152, 0.0722,
        ]
        return zip(identity, target).map { $0 * (1 - s) + $1 * s }
    }
}
