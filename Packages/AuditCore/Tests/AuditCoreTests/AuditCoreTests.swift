import ColorCore
import CoreGraphics
import Foundation
import Testing
@testable import AuditCore

struct DisplayGeometryTests {
    // A Retina primary display and a 1x display to its left, top-aligned,
    // like a laptop with an external monitor on the left.
    let retina = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let external = DisplayGeometry(frame: CGRect(x: -1920, y: -98, width: 1920, height: 1080), scale: 1)

    @Test func mapsTheTopLeftCornerToTheFirstPixel() {
        let p = retina.pixel(forLocal: CGPoint(x: 0.1, y: 981.9))
        #expect(p.x == 0 && p.y == 0)
    }

    @Test func pointsMapToPhysicalPixelsOnRetina() {
        // One point is two pixels; the top half of a point is the even row.
        let p = retina.pixel(forLocal: CGPoint(x: 10.25, y: 982 - 5.25))
        #expect(p.x == 20 && p.y == 10)
    }

    @Test func roundTripsEveryPixelThroughItsCenter() {
        for geometry in [retina, external] {
            for (x, y) in [(0, 0), (1, 1), (17, 33), (geometry.pixelWidth - 1, geometry.pixelHeight - 1)] {
                let back = geometry.pixel(forGlobal: geometry.globalPoint(forPixel: x, y))
                #expect(back.x == x && back.y == y, "\(geometry.scale)x (\(x), \(y))")
            }
        }
    }

    @Test func handlesDisplaysWithNegativeOrigins() {
        // The external display's top-left pixel sits at global (-1920, 982).
        let p = external.pixel(forGlobal: CGPoint(x: -1919.5, y: 981.5))
        #expect(p.x == 0 && p.y == 0)
        #expect(external.contains(global: CGPoint(x: -1, y: 0)))
        #expect(!external.contains(global: CGPoint(x: 0, y: 0)))
        #expect(retina.contains(global: CGPoint(x: 0, y: 1)))
    }

    @Test func thePointerOnTheTopRowBelongsToThatDisplay() {
        // AppKit reports the top row as y == maxY; it must not fall through
        // to the display above or to display 0.
        #expect(retina.contains(global: CGPoint(x: 100, y: 982)))
        #expect(retina.pixel(forGlobal: CGPoint(x: 100, y: 982)).y == 0)
        #expect(!retina.contains(global: CGPoint(x: 100, y: 0)))
    }

    @Test func clampsPointsOutsideTheDisplay() {
        let p = retina.pixel(forLocal: CGPoint(x: -50, y: 5000))
        #expect(p.x == 0 && p.y == 0)
    }

    @Test func pixelRectanglesMapBackToViewRectangles() {
        let r = retina.localRect(for: PixelRect(x: 20, y: 10, width: 40, height: 20))
        #expect(r == CGRect(x: 10, y: 982 - 15, width: 20, height: 10))
    }

    @Test func captureSourceRectIsTopLeftRelativeToTheDisplay() {
        let r = external.captureSourceRect(forGlobal: CGRect(x: -1900, y: 800, width: 300, height: 100))
        #expect(r == CGRect(x: 20, y: 82, width: 300, height: 100))
    }

    @Test func convertsToQuartzForCursorWarping() {
        #expect(DisplayGeometry.quartz(fromGlobal: CGPoint(x: 5, y: 900), primaryHeight: 982) == CGPoint(x: 5, y: 82))
    }
}

struct PixelBufferTests {
    /// 4x2 image: white, light grey, mid grey, white / white x4.
    func sample() -> PixelBuffer {
        let px: [[UInt8]] = [
            [255, 255, 255], [0xCC, 0xCC, 0xCC], [0x77, 0x77, 0x77], [255, 255, 255],
            [255, 255, 255], [255, 255, 255], [255, 255, 255], [255, 255, 255],
        ]
        return PixelBuffer(width: 4, height: 2, bytes: px.flatMap { $0 + [255] })
    }

    @Test func readsColorsTopRowFirst() {
        #expect(sample().color(x: 2, y: 0).hex == "#777777")
        #expect(sample().color(x: 2, y: 1).hex == "#FFFFFF")
    }

    @Test func findsTheLowestContrastPixelForDarkText() {
        // Against black text the darkest background is the worst case.
        let worst = sample().lowestContrast(in: PixelRect(x: 0, y: 0, width: 4, height: 2), against: .black)
        #expect(worst?.x == 2 && worst?.y == 0)
        #expect(worst?.color.hex == "#777777")
        #expect(worst.map { abs($0.ratio - WCAG.contrastRatio(.black, SRGB(hex: "#777777")!)) < 1e-12 } == true)
    }

    @Test func findsTheLowestContrastPixelForLightText() {
        let worst = sample().lowestContrast(in: PixelRect(x: 0, y: 0, width: 4, height: 2), against: .white)
        #expect(worst?.x == 0 && worst?.y == 0, "white on white is the worst case")
        #expect(worst?.ratio == 1)
    }

    @Test func clampsAreasThatSpillPastTheEdge() {
        let worst = sample().lowestContrast(in: PixelRect(x: 2, y: -5, width: 100, height: 100), against: .black)
        #expect(worst?.area == PixelRect(x: 2, y: 0, width: 2, height: 2))
        #expect(sample().lowestContrast(in: PixelRect(x: 10, y: 10, width: 3, height: 3), against: .black) == nil)
    }

    @Test func cornerRectanglesIncludeBothCorners() {
        #expect(PixelRect(corner: (5, 9), corner: (2, 3)) == PixelRect(x: 2, y: 3, width: 4, height: 7))
    }
}

struct FindingTextTests {
    @Test func failingPairNamesTheCriterionAndThreshold() {
        let s = FindingText.sentence(text: SRGB(hex: "#777777")!, background: .white)
        #expect(s.hasPrefix("Text color #777777 on background #FFFFFF has a contrast ratio of 4.47:1."))
        #expect(s.contains("fails WCAG 2.2 Success Criterion 1.4.3 Contrast (Minimum) at Level AA, which requires 4.5:1"))
        #expect(s.contains("meets the 3:1 minimum for large text"))
    }

    @Test func passingPairsDoNotOverclaim() {
        let aa = FindingText.sentence(text: SRGB(hex: "#666666")!, background: .white)
        #expect(aa.contains("meets WCAG 2.2 Success Criterion 1.4.3"))
        #expect(aa.contains("does not meet 1.4.6"))
        let aaa = FindingText.sentence(text: .black, background: .white)
        #expect(aaa.contains("Level AAA (7:1)"))
    }

    @Test func noEmDashesInGeneratedText() {
        for hex in ["#000000", "#595959", "#777777", "#CCCCCC"] {
            #expect(!FindingText.sentence(text: SRGB(hex: hex)!, background: .white).contains("\u{2014}"))
        }
    }
}

struct MarkdownExportTests {
    let utc = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_GB")
    let noon = Date(timeIntervalSince1970: 1_793_275_200) // 29 Oct 2026 12:00 UTC

    @Test func exportsChecksAndCapturesAsTables() {
        let entries: [LogEntry] = [
            .contrast(ContrastCheck(date: noon, text: SRGB(hex: "#777777")!, background: .white)),
            .contrast(ContrastCheck(date: noon, text: .black, background: SRGB(hex: "#CCCCCC")!,
                                    worstCaseArea: PixelRect(x: 0, y: 0, width: 120, height: 40))),
            .capture(CaptureRecord(date: noon, kind: .window(appName: "Safari"), pixelWidth: 800, pixelHeight: 600, delayed: true)),
        ]
        let md = MarkdownExport.session(entries, generated: noon, appVersion: "1.0.0", locale: locale, timeZone: utc)
        #expect(md.contains("## Contrast checks (2)"))
        #expect(md.contains("| 1 | 12:00 | `#777777` | `#FFFFFF` | 4.47:1 | Fail | Pass | Pass | Fail | Lc 71.1 |"))
        #expect(md.contains("- Check 2: background is the lowest-contrast pixel in a 120 × 40 px area."))
        #expect(md.contains("## Captures (1)"))
        #expect(md.contains("| 1 | 12:00 | Window (Safari), after a 3-second delay | 800 × 600 px |"))
        #expect(!md.contains("\u{2014}"))
    }

    @Test func emptySessionSaysSo() {
        let md = MarkdownExport.session([], generated: noon, appVersion: "1.0.0", locale: locale, timeZone: utc)
        #expect(md.contains("No checks or captures yet."))
    }
}
