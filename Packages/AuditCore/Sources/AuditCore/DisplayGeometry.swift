import CoreGraphics
import Foundation

/// Maps between a display's points (as AppKit sees them) and the pixels of
/// its capture.
///
/// AppKit's global space puts the origin at the bottom-left of the primary
/// display with y growing upward, and displays to the left of or below the
/// primary one have negative origins. Captures are pixel grids with y
/// growing downward, scaled by the display's backing factor (2 on Retina).
/// Getting any of this wrong samples the wrong pixel, which is why it is
/// tested on its own.
public struct DisplayGeometry: Hashable, Sendable {
    /// The display's frame in AppKit global coordinates, in points.
    public let frame: CGRect
    /// Pixels per point.
    public let scale: CGFloat
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(frame: CGRect, scale: CGFloat, pixelWidth: Int, pixelHeight: Int) {
        self.frame = frame
        self.scale = scale
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public init(frame: CGRect, scale: CGFloat) {
        self.init(
            frame: frame, scale: scale,
            pixelWidth: Int((frame.width * scale).rounded()),
            pixelHeight: Int((frame.height * scale).rounded())
        )
    }

    /// Pixel under a point in the display's own view coordinates (origin
    /// bottom-left of the display), clamped to the capture.
    public func pixel(forLocal p: CGPoint) -> (x: Int, y: Int) {
        let x = Int((p.x * scale).rounded(.down))
        let y = Int(((frame.height - p.y) * scale).rounded(.down))
        return (min(max(x, 0), pixelWidth - 1), min(max(y, 0), pixelHeight - 1))
    }

    /// Pixel under a point in AppKit global coordinates.
    public func pixel(forGlobal p: CGPoint) -> (x: Int, y: Int) {
        pixel(forLocal: CGPoint(x: p.x - frame.minX, y: p.y - frame.minY))
    }

    /// Center of a pixel in the display's view coordinates.
    public func localPoint(forPixel x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: (CGFloat(x) + 0.5) / scale, y: frame.height - (CGFloat(y) + 0.5) / scale)
    }

    /// Center of a pixel in AppKit global coordinates.
    public func globalPoint(forPixel x: Int, _ y: Int) -> CGPoint {
        let p = localPoint(forPixel: x, y)
        return CGPoint(x: p.x + frame.minX, y: p.y + frame.minY)
    }

    /// The view-coordinate rectangle a pixel rectangle covers.
    public func localRect(for r: PixelRect) -> CGRect {
        CGRect(
            x: CGFloat(r.x) / scale,
            y: frame.height - CGFloat(r.y + r.height) / scale,
            width: CGFloat(r.width) / scale,
            height: CGFloat(r.height) / scale
        )
    }

    /// Matches NSMouseInRect for unflipped coordinates. AppKit reports the
    /// pointer on a display's top row as y == frame.maxY, so y is tested as
    /// (minY, maxY] and x as [minX, maxX). Adjacent displays never both
    /// claim a point.
    public func contains(global p: CGPoint) -> Bool {
        p.x >= frame.minX && p.x < frame.maxX && p.y > frame.minY && p.y <= frame.maxY
    }

    /// Converts an AppKit global point to the Quartz global space that
    /// CGWarpMouseCursorPosition uses (origin top-left of the primary display).
    public static func quartz(fromGlobal p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// The region of this display a global rectangle covers, in the
    /// display-local, top-left-origin points ScreenCaptureKit's sourceRect expects.
    public func captureSourceRect(forGlobal r: CGRect) -> CGRect {
        CGRect(x: r.minX - frame.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
    }
}
