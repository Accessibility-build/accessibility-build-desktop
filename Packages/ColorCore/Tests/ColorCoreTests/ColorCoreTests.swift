import Testing
@testable import ColorCore

struct HexParsingTests {
    @Test func acceptsShortAndLongFormsWithOrWithoutHash() {
        #expect(SRGB(hex: "#fff")?.hex == "#FFFFFF")
        #expect(SRGB(hex: "767676")?.hex == "#767676")
        #expect(SRGB(hex: "  #0b0F19 ")?.hex == "#0B0F19")
    }

    @Test func rejectsAnythingThatIsNotAHexColor() {
        for bad in ["", "#", "#12", "#12345", "#1234567", "#GGGGGG", "red", "rgb(0,0,0)"] {
            #expect(SRGB(hex: bad) == nil, "\(bad)")
        }
    }
}

struct RatioDisplayTests {
    @Test func neverRoundsAFailingRatioUpToAPassingOne() {
        // #777777 on white is 4.478:1; a rounded "4.48" is fine, but a value
        // just under a threshold must never print as the threshold.
        #expect(WCAG.formatRatio(4.4999) == "4.49:1")
        #expect(WCAG.formatRatio(6.999) == "6.99:1")
        #expect(WCAG.formatRatio(4.5) == "4.50:1")
        #expect(WCAG.formatRatio(21) == "21.00:1")
    }

    @Test func knownPairsHaveTheirPublishedRatios() {
        let white = SRGB.white
        #expect(WCAG.formatRatio(WCAG.contrastRatio(SRGB(hex: "#767676")!, white)) == "4.54:1")
        #expect(WCAG.formatRatio(WCAG.contrastRatio(SRGB(hex: "#777777")!, white)) == "4.47:1")
        #expect(WCAG.formatRatio(WCAG.contrastRatio(.black, white)) == "21.00:1")
        #expect(WCAG.spokenRatio(WCAG.contrastRatio(SRGB(hex: "#767676")!, white)) == "4.54 to 1")
    }

    @Test func requirementsUseUnroundedRatios() {
        let ratio = WCAG.contrastRatio(SRGB(hex: "#777777")!, .white)
        #expect(!ContrastRequirement.normalTextAA.passes(ratio))
        #expect(ContrastRequirement.largeTextAA.passes(ratio))
        #expect(ContrastRequirement.nonText.passes(ratio))
    }

    @Test func fastLuminanceMatchesTheExactOne() {
        for v in stride(from: 0, through: 255, by: 17) {
            let c = SRGB(r8: UInt8(v), g8: UInt8(255 - v), b8: UInt8(v / 2))
            #expect(abs(WCAG.relativeLuminance(c) - WCAG.relativeLuminance(r8: c.r8, g8: c.g8, b8: c.b8)) < 1e-12)
        }
    }
}

struct APCATests {
    @Test func referenceValuesFromTheAPCADocumentation() {
        // APCA-W3 README examples: #888 on #fff is Lc 63.1, #fff on #888 is Lc -68.5.
        #expect(APCA.format(APCA.lc(text: SRGB(hex: "#888")!, background: .white)) == "Lc 63.1")
        #expect(APCA.format(APCA.lc(text: .white, background: SRGB(hex: "#888")!)) == "Lc -68.5")
        #expect(APCA.lc(text: .white, background: .white) == 0)
    }

    @Test func levelsUseTheMagnitude() {
        #expect(APCA.level(-80, for: .fluentText) == .pass)
        #expect(APCA.level(65, for: .fluentText) == .caution)
        #expect(APCA.level(20, for: .fluentText) == .fail)
    }
}

struct AutoFixTests {
    @Test func suggestionsActuallyPass() {
        let text = SRGB(hex: "#999999")!, background = SRGB.white
        for target in [3.0, 4.5, 7.0] {
            let fixed = AutoFix.nudge(text: text, background: background, target: target)
            #expect(WCAG.contrastRatio(fixed, background) >= target, "\(target): \(fixed.hex)")
            let bg = AutoFix.nudge(text: SRGB(hex: "#FFFFFF")!, background: SRGB(hex: "#AAAAAA")!, target: target, side: .background)
            #expect(WCAG.contrastRatio(.white, bg) >= target, "bg \(target): \(bg.hex)")
        }
    }

    @Test func passingPairsAreLeftAlone() {
        let text = SRGB(hex: "#333333")!
        #expect(AutoFix.nudge(text: text, background: .white, target: 4.5) == text)
    }
}

struct LensMatrixTests {
    @Test func zeroSeverityIsIdentityAndFullSeverityIsMachado() {
        for type in CVD.allCases {
            #expect(type.linearMatrix(severity: 0) == [1, 0, 0, 0, 1, 0, 0, 0, 1])
            if let m = type.machadoMatrix { #expect(type.linearMatrix(severity: 1) == m) }
        }
    }
}
