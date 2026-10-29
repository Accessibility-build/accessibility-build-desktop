import Foundation
import Testing
@testable import ColorCore

/// The app must report exactly what accessibility.build's contrast checker
/// reports for the same colors. Fixtures come from running the website's
/// lib/color code (scripts/fixtures-from-website.mjs); if the website's maths
/// changes, regenerating them makes these tests fail until the port follows.
struct WebsiteParityTests {
    struct Fixtures: Decodable {
        struct Pair: Decodable { let fg: String; let bg: String; let wcag: Double; let apca: Double }
        struct CVDCase: Decodable { let hex: String; let type: String; let severity: Double; let out: String }
        struct OKLCHCase: Decodable { let hex: String; let l: Double; let c: Double; let h: Double }
        struct GamutCase: Decodable { let l: Double; let c: Double; let h: Double; let out: String }
        struct FixCase: Decodable { let fg: String; let bg: String; let metric: String; let target: Double; let side: String; let out: String }
        let pairs: [Pair]
        let cvd: [CVDCase]
        let oklch: [OKLCHCase]
        let gamut: [GamutCase]
        let autofix: [FixCase]
    }

    static let fixtures: Fixtures = {
        let url = Bundle.module.url(forResource: "website-color", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }()

    @Test func wcagRatiosMatchTheWebsite() {
        for p in Self.fixtures.pairs {
            let ratio = WCAG.contrastRatio(SRGB(hex: p.fg)!, SRGB(hex: p.bg)!)
            #expect(abs(ratio - p.wcag) < 1e-9, "\(p.fg) on \(p.bg): \(ratio) vs \(p.wcag)")
        }
    }

    @Test func apcaValuesMatchTheWebsite() {
        for p in Self.fixtures.pairs {
            let lc = APCA.lc(text: SRGB(hex: p.fg)!, background: SRGB(hex: p.bg)!)
            #expect(abs(lc - p.apca) < 1e-9, "\(p.fg) on \(p.bg): \(lc) vs \(p.apca)")
        }
    }

    @Test func colorVisionSimulationMatchesTheWebsite() {
        for c in Self.fixtures.cvd {
            let type = CVD(rawValue: c.type)!
            let out = type.simulate(SRGB(hex: c.hex)!, severity: c.severity).hex
            #expect(out == c.out, "\(c.type) \(c.severity) \(c.hex): \(out) vs \(c.out)")
        }
    }

    @Test func oklchConversionMatchesTheWebsite() {
        for o in Self.fixtures.oklch {
            let mine = OKLCH(SRGB(hex: o.hex)!)
            #expect(abs(mine.l - o.l) < 1e-9, "\(o.hex) L")
            #expect(abs(mine.c - o.c) < 1e-9, "\(o.hex) C")
            // Hue is meaningless for greys, where floating-point noise
            // decides the angle; only compare it when there is chroma.
            if o.c > 1e-4 { #expect(abs(mine.h - o.h) < 1e-6, "\(o.hex) H") }
        }
    }

    @Test func gamutMappingMatchesTheWebsite() {
        for g in Self.fixtures.gamut {
            let out = OKLCH(l: g.l, c: g.c, h: g.h).toSRGB().hex
            #expect(out == g.out, "oklch(\(g.l) \(g.c) \(g.h)): \(out) vs \(g.out)")
        }
    }

    @Test func autoFixSuggestionsMatchTheWebsite() {
        var mismatches: [String] = []
        for f in Self.fixtures.autofix {
            let text = SRGB(hex: f.fg)!, background = SRGB(hex: f.bg)!
            let out = AutoFix.nudge(
                text: text, background: background, target: f.target,
                metric: f.metric == "apca" ? .apca : .wcag,
                side: f.side == "fg" ? .text : .background
            ).hex
            if out != f.out { mismatches.append("\(f.side) \(f.fg)/\(f.bg) \(f.metric) \(f.target): \(out) vs \(f.out)") }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(Self.fixtures.autofix.count): \(mismatches.prefix(5))")
    }
}
