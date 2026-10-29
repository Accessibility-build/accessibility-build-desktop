import AppKit
import AuditCore
import ColorCore
import SwiftUI

/// What the overlay's floating chrome shows.
struct OverlayChrome {
    var step: Int?
    var title: String
    var hint: String
    var textChip: SRGB?
    var keys: [KeyHint]
    /// Loupe and caption are shown in contrast mode only; region mode keeps
    /// the crosshair pointer and shows a size caption.
    var showsLoupe: Bool
    var caption: LoupeCaption.Content
}

extension OverlayChrome {
    /// What the HUD shows; the caption changes on every move, the HUD rarely.
    var hudKey: String {
        "\(step ?? 0)|\(title)|\(hint)|\(textChip?.hex ?? "")|" + keys.map { $0.key + $0.label }.joined()
    }
}

struct KeyHint: Hashable {
    let key: String
    let label: String
}

/// One display's frozen frame plus the magnifier, caption, selection and HUD.
final class OverlayView: NSView {
    private weak var overlay: FreezeOverlay?
    private let display: FrozenDisplay
    private let index: Int
    private let insets: (top: CGFloat, bottom: CGFloat)
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let selectionDark = CAShapeLayer()
    private let selectionLight = CAShapeLayer()
    private let loupe: RoundLoupeView
    private let caption = NSHostingView(rootView: LoupeCaption(content: .init()))
    private let hud = NSHostingView(rootView: OverlayHUD(chrome: nil))
    private var hudKey = ""
    private var hudSize = NSSize.zero

    init(display: FrozenDisplay, index: Int, overlay: FreezeOverlay) {
        self.display = display
        self.index = index
        self.overlay = overlay
        loupe = RoundLoupeView(pixels: display.pixels)
        let screen = NSScreen.screens.first { $0.displayID == display.displayID }
        insets = screen.map { ($0.frame.maxY - $0.visibleFrame.maxY, $0.visibleFrame.minY - $0.frame.minY) } ?? (0, 0)
        super.init(frame: NSRect(origin: .zero, size: display.geometry.frame.size))

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contents = display.image
        imageLayer.contentsGravity = .resize
        // Nearest-neighbour keeps single pixels crisp at non-integral scales.
        imageLayer.magnificationFilter = .nearest
        layer?.addSublayer(imageLayer)

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.4).cgColor
        layer?.addSublayer(dimLayer)
        // A light dashed line over a dark solid one stays visible on any content.
        selectionDark.fillColor = nil
        selectionDark.strokeColor = NSColor.black.withAlphaComponent(0.8).cgColor
        selectionDark.lineWidth = 3
        selectionLight.fillColor = nil
        selectionLight.strokeColor = NSColor.white.cgColor
        selectionLight.lineWidth = 1
        selectionLight.lineDashPattern = [5, 3]
        layer?.addSublayer(selectionDark)
        layer?.addSublayer(selectionLight)

        #if DEBUG
        if Snapshot.isActive {
            let still = NSImageView(frame: bounds)
            still.image = NSImage(cgImage: display.image, size: bounds.size)
            still.imageScaling = .scaleAxesIndependently
            still.setAccessibilityElement(false)
            addSubview(still)
        }
        #endif
        for view in [loupe, caption, hud] as [NSView] {
            view.isHidden = true
            addSubview(view)
        }
        caption.setAccessibilityElement(false)
        hud.setAccessibilityElement(false)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [imageLayer, dimLayer, selectionDark, selectionLight] { l.frame = bounds }
        CATransaction.commit()
    }

    private func local(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) { overlay?.mouseMoved(to: local(event), in: index) }
    override func mouseDown(with event: NSEvent) { overlay?.mouseDown(at: local(event), in: index) }
    override func mouseDragged(with event: NSEvent) { overlay?.mouseDragged(to: local(event), in: index) }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp(at: local(event), in: index) }
    override func keyDown(with event: NSEvent) { overlay?.keyDown(event) }
    // Esc can arrive as cancelOperation when a key-binding handler claims it.
    override func cancelOperation(_ sender: Any?) {
        if let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
            overlay?.keyDown(esc)
        }
    }

    func update(cursor: (x: Int, y: Int)?, selection: PixelRect?, dimOutside: Bool, chrome: OverlayChrome) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let selection {
            let rect = display.geometry.localRect(for: selection)
            let outline = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            selectionDark.path = outline
            selectionLight.path = outline
            if dimOutside {
                let path = CGMutablePath()
                path.addRect(bounds)
                path.addRect(rect)
                dimLayer.path = path
            } else {
                dimLayer.path = nil
            }
        } else {
            selectionDark.path = nil
            selectionLight.path = nil
            dimLayer.path = nil
        }
        CATransaction.commit()

        var pointer: CGPoint?
        if let cursor {
            let p = display.geometry.localPoint(forPixel: cursor.x, cursor.y)
            pointer = p
            var anchorRect = NSRect(origin: p, size: .zero)
            if chrome.showsLoupe {
                loupe.update(center: cursor)
                // Centered on the pick point, like the system color sampler.
                let d = RoundLoupeView.diameter
                loupe.frame = NSRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
                loupe.isHidden = false
                anchorRect = loupe.frame
            } else {
                loupe.isHidden = true
                anchorRect = NSRect(x: p.x, y: p.y - 12, width: 0, height: 0)
            }
            caption.rootView = LoupeCaption(content: chrome.caption)
            let size = caption.fittingSize
            var origin = CGPoint(x: anchorRect.midX - size.width / 2, y: anchorRect.minY - 10 - size.height)
            if !chrome.showsLoupe { origin = CGPoint(x: p.x + 16, y: p.y - 16 - size.height) }
            if origin.y < bounds.minY + 8 { origin.y = anchorRect.maxY + 10 }
            origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
            caption.frame = NSRect(origin: origin, size: size)
            caption.isHidden = chrome.caption.isEmpty
        } else {
            loupe.isHidden = true
            caption.isHidden = true
        }

        if chrome.hudKey != hudKey {
            hudKey = chrome.hudKey
            hud.rootView = OverlayHUD(chrome: chrome)
            hudSize = hud.fittingSize
        }
        let size = hudSize
        var frame = NSRect(x: (bounds.width - size.width) / 2, y: bounds.minY + insets.bottom + 28, width: size.width, height: size.height)
        // Out of the way when the pointer or loupe comes near it.
        if let pointer, frame.insetBy(dx: -40, dy: -80).contains(pointer) || frame.intersects(loupe.isHidden ? .zero : loupe.frame) {
            frame.origin.y = bounds.maxY - insets.top - 20 - size.height
        }
        hud.frame = frame
        hud.isHidden = false

        setAccessibilityLabel("Frozen screen. \(chrome.title).")
        setAccessibilityHelp(chrome.hint + ". " + chrome.keys.map { "\($0.label): \($0.key)" }.joined(separator: ", "))
    }
}

/// A round magnifier drawn cell by cell from the sRGB buffer, so what you
/// see is exactly the value that is measured.
final class RoundLoupeView: NSView {
    static let cells = 15
    static let cell: CGFloat = 9
    static var diameter: CGFloat { CGFloat(cells) * cell }

    private let pixels: PixelBuffer
    private var center = (x: 0, y: 0)

    init(pixels: PixelBuffer) {
        self.pixels = pixels
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func update(center: (x: Int, y: Int)) {
        self.center = center
        layer?.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter), transform: nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let circle = bounds.insetBy(dx: 1, dy: 1)
        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        let half = Self.cells / 2
        for row in 0..<Self.cells {
            for col in 0..<Self.cells {
                let px = center.x - half + col, py = center.y - half + row
                let rect = CGRect(x: CGFloat(col) * Self.cell, y: CGFloat(row) * Self.cell, width: Self.cell, height: Self.cell)
                let fill = pixels.contains(x: px, y: py) ? NSColor(pixels.color(x: px, y: py)) : NSColor(white: 0.2, alpha: 1)
                ctx.setFillColor(fill.cgColor)
                ctx.fill(rect)
            }
        }
        // A faint grid makes single pixels countable without competing with them.
        ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.18).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<Self.cells {
            let o = CGFloat(i) * Self.cell
            ctx.move(to: CGPoint(x: o, y: 0))
            ctx.addLine(to: CGPoint(x: o, y: Self.diameter))
            ctx.move(to: CGPoint(x: 0, y: o))
            ctx.addLine(to: CGPoint(x: Self.diameter, y: o))
        }
        ctx.strokePath()
        ctx.restoreGState()

        let target = CGRect(x: CGFloat(half) * Self.cell, y: CGFloat(half) * Self.cell, width: Self.cell, height: Self.cell)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(2.5)
        ctx.stroke(target.insetBy(dx: -1, dy: -1))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(target.insetBy(dx: -1, dy: -1))

        // Rim: white ring with a hairline outside it, legible on any content.
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 2, dy: 2))
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(0.75)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// Floating chrome material: Liquid Glass on macOS 26 and later, a thick
/// dark material before that, and solid when Reduce Transparency is on.
struct HUDBackground<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var solid: Bool {
        #if DEBUG
        if Snapshot.isActive { return true }
        #endif
        return reduceTransparency
    }

    func body(content: Content) -> some View {
        if solid {
            content
                .background(Color(white: 0.12), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.3), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.black.opacity(0.4)), in: shape)
        } else {
            content
                .background(.ultraThickMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}

struct LoupeCaption: View {
    struct Content {
        var color: SRGB?
        var hex: String?
        var text: SRGB?
        var ratio: Double?
        var size: String?
        var isEmpty: Bool { hex == nil && size == nil }
    }

    let content: Content

    var body: some View {
        HStack(spacing: 8) {
            if let text = content.text, let color = content.color {
                Text("Aa")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(text))
                    .frame(width: 28, height: 18)
                    .background(Color(color), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else if let color = content.color {
                Circle()
                    .fill(Color(color))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            }
            if let hex = content.hex {
                Text(hex).font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            if let ratio = content.ratio {
                let pass = ContrastRequirement.normalTextAA.passes(ratio)
                Text(WCAG.formatRatio(ratio)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(pass ? Palette.pass : Palette.fail)
                    .font(.system(size: 12))
            }
            if let size = content.size {
                Text(size).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .modifier(HUDBackground(shape: Capsule()))
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

struct OverlayHUD: View {
    let chrome: OverlayChrome?

    var body: some View {
        if let chrome {
            HStack(spacing: 14) {
                if let step = chrome.step {
                    HStack(spacing: 5) {
                        ForEach(1...2, id: \.self) { i in
                            Circle()
                                .fill(i == step ? Color.white : Color.white.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(chrome.title).font(.system(size: 13, weight: .semibold))
                        if let chip = chrome.textChip {
                            HStack(spacing: 4) {
                                Circle().fill(Color(chip)).frame(width: 10, height: 10)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                                Text("Text \(chip.hex)").font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(chrome.hint).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                }
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 26)
                HStack(spacing: 12) {
                    ForEach(chrome.keys, id: \.self) { hint in
                        HStack(spacing: 5) {
                            Text(hint.key)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5)
                                .frame(minWidth: 22, minHeight: 20)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.14)))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                            Text(hint.label).font(.system(size: 12))
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .modifier(HUDBackground(shape: Capsule()))
            .environment(\.colorScheme, .dark)
            .fixedSize()
        }
    }
}
