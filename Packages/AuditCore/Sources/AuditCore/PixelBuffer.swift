import ColorCore
import Foundation

/// A rectangle in a display's pixel grid (origin top-left, y down).
public struct PixelRect: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The rectangle spanning two corner pixels, inclusive of both.
    public init(corner a: (x: Int, y: Int), corner b: (x: Int, y: Int)) {
        x = min(a.x, b.x)
        y = min(a.y, b.y)
        width = abs(a.x - b.x) + 1
        height = abs(a.y - b.y) + 1
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func clamped(width maxWidth: Int, height maxHeight: Int) -> PixelRect {
        let x0 = max(0, min(x, maxWidth)), y0 = max(0, min(y, maxHeight))
        let x1 = max(0, min(x + width, maxWidth)), y1 = max(0, min(y + height, maxHeight))
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

/// An opaque RGBA8 image, top row first, as captured from a display after
/// conversion to sRGB.
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count >= width * height * 4, "buffer too small")
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// The color at a pixel, clamped to the buffer's edges.
    public func color(x: Int, y: Int) -> SRGB {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return SRGB(r8: bytes[i], g8: bytes[i + 1], b8: bytes[i + 2])
    }

    public struct WorstCase: Sendable, Equatable {
        public let x: Int
        public let y: Int
        public let color: SRGB
        public let ratio: Double
        /// Pixels examined, for the "in a W x H px area" note.
        public let area: PixelRect
    }

    /// The pixel in `rect` with the lowest WCAG contrast against `text`:
    /// the background color that decides whether text over a gradient or
    /// photo passes. Ties keep the first pixel in reading order.
    public func lowestContrast(in rect: PixelRect, against text: SRGB) -> WorstCase? {
        let r = rect.clamped(width: width, height: height)
        guard !r.isEmpty else { return nil }
        let textLuminance = WCAG.relativeLuminance(text.quantized)
        var best: (x: Int, y: Int, ratio: Double)?
        var lastKey = -1
        var lastRatio = 0.0
        for y in r.y..<(r.y + r.height) {
            var i = (y * width + r.x) * 4
            for x in r.x..<(r.x + r.width) {
                let key = Int(bytes[i]) << 16 | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2])
                // Flat areas repeat the same color; skip the luminance maths.
                if key != lastKey {
                    let l = WCAG.relativeLuminance(r8: bytes[i], g8: bytes[i + 1], b8: bytes[i + 2])
                    lastRatio = WCAG.contrastRatio(luminance: textLuminance, l)
                    lastKey = key
                }
                if best == nil || lastRatio < best!.ratio { best = (x, y, lastRatio) }
                i += 4
            }
        }
        guard let b = best else { return nil }
        return WorstCase(x: b.x, y: b.y, color: color(x: b.x, y: b.y), ratio: b.ratio, area: r)
    }
}
