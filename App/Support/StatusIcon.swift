import AppKit

/// The menu-bar glyph: the Accessibility.build mark (an "A" crossed by two
/// eye-like arcs) as a vector template image, so macOS tints it for light,
/// dark and tinted menu bars and it stays crisp at every scale.
///
/// Geometry is the same as scripts/make-icon.swift, measured in the source
/// PNG's 512-unit space (y down): the mark spans x 138...374, y 108...404.
enum StatusIcon {
    static func make(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Accessibility Build"
        return image
    }

    static func draw(in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Mark height fills all but a point of the box; centered horizontally.
        let k = (rect.height - 2) / 296
        let dx = rect.minX + (rect.width - 236 * k) / 2 - 138 * k
        let dy = rect.minY + 1 - 108 * k
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * k, y: dy + y * k) }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)

        let legs = CGMutablePath()
        legs.addLines(between: [p(256, 108), p(358, 404), p(318, 404), p(256, 196), p(194, 404), p(152, 404)])
        legs.closeSubpath()
        ctx.addPath(legs)
        ctx.fillPath()

        func left(_ y: CGFloat) -> CGFloat { 256 - (y - 108) * (104.0 / 296.0) }
        func right(_ y: CGFloat) -> CGFloat { 256 + (y - 108) * (102.0 / 296.0) }
        let bar = CGMutablePath()
        bar.addLines(between: [p(left(300), 300), p(right(300), 300), p(right(336), 336), p(left(336), 336)])
        bar.closeSubpath()
        ctx.addPath(bar)
        ctx.fillPath()

        // The arcs are drawn a little heavier than in the app icon so they
        // survive at menu-bar size.
        ctx.setLineWidth(27 * k)
        ctx.setLineCap(.round)
        let upper = CGMutablePath()
        upper.move(to: p(150, 238))
        upper.addQuadCurve(to: p(362, 238), control: p(256, 176))
        ctx.addPath(upper)
        ctx.strokePath()
        let lower = CGMutablePath()
        lower.move(to: p(150, 270))
        lower.addQuadCurve(to: p(362, 270), control: p(256, 334))
        ctx.addPath(lower)
        ctx.strokePath()
    }
}
