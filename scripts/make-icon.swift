#!/usr/bin/env swift
// Draws the app icon from vectors at every size the asset catalog needs.
// The Accessibility.build mark (an "A" crossed by two eye-like arcs) only
// exists as a 512 px PNG, which goes soft when scaled up, so its geometry is
// re-measured here in that PNG's 512-unit space and drawn crisply.
//
//   swift scripts/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset

import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "Resources/Assets.xcassets/AppIcon.appiconset"

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: an 824-unit rounded square centered in 1024, with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle top light so the tile is not a flat slab.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 512), options: [])
    ctx.restoreGState()

    // Mark, in the source PNG's 512-unit space (y down), mapped onto the tile.
    let k: CGFloat = 1.55
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + (x - 256) * k, y: 512 - (y - 256) * k) }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))

    // The A's legs: an inverted V with a pointed apex and flat feet.
    let legs = CGMutablePath()
    legs.addLines(between: [p(256, 108), p(358, 404), p(318, 404), p(256, 196), p(194, 404), p(152, 404)])
    legs.closeSubpath()
    ctx.addPath(legs)
    ctx.fillPath()

    // Crossbar between the legs.
    let bar = CGMutablePath()
    func leftEdge(_ y: CGFloat) -> CGFloat { 256 - (y - 108) * (104.0 / 296.0) }
    func rightEdge(_ y: CGFloat) -> CGFloat { 256 + (y - 108) * (102.0 / 296.0) }
    bar.addLines(between: [p(leftEdge(300), 300), p(rightEdge(300), 300), p(rightEdge(336), 336), p(leftEdge(336), 336)])
    bar.closeSubpath()
    ctx.addPath(bar)
    ctx.fillPath()

    // The two arcs, like an eye around the A.
    ctx.setLineWidth(22 * k)
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

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! drawIcon(size: size * scale).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    }
}
// A 1024 px preview for checking the drawing by eye.
try? FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
try! drawIcon(size: 1024).write(to: URL(fileURLWithPath: "build/icon-1024.png"))
print("icons written to \(outDir)")
