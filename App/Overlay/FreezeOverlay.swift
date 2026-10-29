import AppKit
import AuditCore
import ColorCore

/// Full-screen picker over frozen displays, shared by the contrast picker
/// and region capture. One borderless panel per display shows that
/// display's frozen frame; this object owns the pick point and the steps.
///
/// Everything works from the keyboard: arrow keys move the pick point one
/// pixel (Shift for ten) and warp the pointer with it, Return picks, Esc
/// cancels. VoiceOver hears the instructions on open and the color on
/// request (Space), not on every pixel, which would flood speech.
@MainActor
final class FreezeOverlay {
    enum Mode { case contrast, region }

    enum Outcome {
        case cancelled
        case contrast(text: SRGB, background: SRGB, worst: PixelBuffer.WorstCase?)
        case region(FrozenDisplay, PixelRect)
        case display(FrozenDisplay)
    }

    enum Step { case text, background }

    struct Point: Equatable {
        var display: Int
        var x: Int
        var y: Int
    }

    let displays: [FrozenDisplay]
    let mode: Mode
    private let completion: (Outcome) -> Void
    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private var finished = false
    // The click or keystroke that opened the picker must not count as a pick.
    private let openedAt = ProcessInfo.processInfo.systemUptime

    private(set) var cursor = Point(display: 0, x: 0, y: 0)
    private(set) var step: Step = .text
    private(set) var textColor: SRGB?
    /// Corner set with Return in region mode.
    private var anchor: Point?
    private var dragStart: Point?
    private var dragging = false
    /// Gets focus back if the picker is cancelled.
    private var previousApp: NSRunningApplication?

    init(displays: [FrozenDisplay], mode: Mode, completion: @escaping (Outcome) -> Void) {
        self.displays = displays
        self.mode = mode
        self.completion = completion
    }

    func show() {
        for (index, display) in displays.enumerated() {
            let panel = OverlayPanel(frame: display.geometry.frame)
            panel.title = mode == .contrast ? "Contrast picker" : "Capture region"
            let view = OverlayView(display: display, index: index, overlay: self)
            panel.contentView = view
            panel.setFrame(display.geometry.frame, display: false)
            panels.append(panel)
            views.append(view)
        }
        let mouse = NSEvent.mouseLocation
        let index = displays.firstIndex { $0.geometry.contains(global: mouse) } ?? 0
        let p = displays[index].geometry.pixel(forGlobal: mouse)
        cursor = Point(display: index, x: p.x, y: p.y)

        for panel in panels { panel.orderFrontRegardless() }
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        NSApp.activate()
        focus(index)
        // The contrast loupe sits centered on the pick point, so the pointer
        // is hidden there; region capture keeps a crosshair.
        if mode == .contrast { NSCursor.hide() } else { NSCursor.crosshair.push() }
        refresh()
        let c = chrome()
        Announcer.say("\(c.title). \(c.hint).")
    }

    // MARK: State shown by the views

    func chrome() -> OverlayChrome {
        let color = currentColor
        switch (mode, step) {
        case (.contrast, .text):
            return OverlayChrome(
                step: 1, title: "Pick the text color", hint: "Arrow keys move one pixel. Space reads the color aloud.",
                textChip: nil, keys: [KeyHint(key: "↩", label: "Pick"), KeyHint(key: "esc", label: "Cancel")],
                showsLoupe: true, caption: .init(color: color, hex: color.hex))
        case (.contrast, .background):
            if let sel = selection(on: cursor.display) {
                return OverlayChrome(
                    step: 2, title: "Release to use the lowest-contrast pixel", hint: "Measuring the area against the text color.",
                    textChip: textColor, keys: [KeyHint(key: "esc", label: "Cancel")],
                    showsLoupe: true, caption: .init(size: "\(sel.width) × \(sel.height) px"))
            }
            return OverlayChrome(
                step: 2, title: "Pick the background", hint: "Or drag across an area to use its lowest-contrast pixel.",
                textChip: textColor, keys: [KeyHint(key: "↩", label: "Pick"), KeyHint(key: "⌫", label: "Back"), KeyHint(key: "esc", label: "Cancel")],
                showsLoupe: true,
                caption: .init(color: color, hex: color.hex, text: textColor, ratio: textColor.map { WCAG.contrastRatio($0, color) }))
        case (.region, _):
            let sel = selection(on: cursor.display)
            let caption = LoupeCaption.Content(size: sel.map { "\($0.width) × \($0.height) px" })
            if anchor == nil {
                return OverlayChrome(
                    step: nil, title: "Drag to capture a region", hint: "Return sets a corner from the keyboard.",
                    textChip: nil, keys: [KeyHint(key: "↩", label: "Corner"), KeyHint(key: "space", label: "Whole display"), KeyHint(key: "esc", label: "Cancel")],
                    showsLoupe: false, caption: caption)
            }
            return OverlayChrome(
                step: nil, title: "Move to the opposite corner", hint: "Arrow keys move one pixel, Shift-arrow ten.",
                textChip: nil, keys: [KeyHint(key: "↩", label: "Capture"), KeyHint(key: "esc", label: "Clear corner")],
                showsLoupe: false, caption: caption)
        }
    }

    var currentColor: SRGB {
        displays[cursor.display].pixels.color(x: cursor.x, y: cursor.y)
    }

    private func selection(on index: Int) -> PixelRect? {
        if dragging, let s = dragStart, s.display == index {
            return PixelRect(corner: (s.x, s.y), corner: (cursor.x, cursor.y))
        }
        if let a = anchor, a.display == index, cursor.display == index {
            return PixelRect(corner: (a.x, a.y), corner: (cursor.x, cursor.y))
        }
        return nil
    }

    private func refresh() {
        let c = chrome()
        for (i, view) in views.enumerated() {
            view.update(
                cursor: cursor.display == i ? (cursor.x, cursor.y) : nil,
                selection: selection(on: i),
                dimOutside: mode == .region,
                chrome: c
            )
        }
    }

    private func focus(_ index: Int) {
        guard panels.indices.contains(index) else { return }
        panels[index].makeKey()
        panels[index].makeFirstResponder(views[index])
    }

    // MARK: Mouse

    func mouseMoved(to local: CGPoint, in index: Int) {
        let p = displays[index].geometry.pixel(forLocal: local)
        if cursor.display != index { focus(index) }
        cursor = Point(display: index, x: p.x, y: p.y)
        refresh()
    }

    func mouseDown(at local: CGPoint, in index: Int) {
        guard ProcessInfo.processInfo.systemUptime - openedAt > 0.25 else { return }
        mouseMoved(to: local, in: index)
        dragStart = cursor
        dragging = false
    }

    /// Drag events keep coming to the view where the drag began, so a drag
    /// stays on that display and clamps at its edge.
    func mouseDragged(to local: CGPoint, in index: Int) {
        guard let start = dragStart else { return }
        let geometry = displays[start.display].geometry
        let p = geometry.pixel(forLocal: local)
        cursor = Point(display: start.display, x: p.x, y: p.y)
        if !dragging {
            let threshold = Int((3 * geometry.scale).rounded())
            dragging = max(abs(p.x - start.x), abs(p.y - start.y)) >= threshold
        }
        refresh()
    }

    func mouseUp(at local: CGPoint, in index: Int) {
        guard let start = dragStart else { return }
        dragStart = nil
        if dragging {
            dragging = false
            finishArea(from: start, to: cursor)
        } else if mode == .contrast {
            commitPoint()
        }
    }

    // MARK: Keyboard

    func keyDown(_ event: NSEvent) {
        let amount = event.modifierFlags.contains(.shift) ? 10 : 1
        // Holding Return must not pick the text color and then the same
        // pixel as background. Only the arrow keys repeat.
        if event.isARepeat, !(123...126).contains(Int(event.keyCode)) { return }
        switch event.keyCode {
        case 53: escape()
        case 36, 76: commitPoint()
        case 49: space()
        case 51, 117, 48: back()
        case 123: move(dx: -amount, dy: 0)
        case 124: move(dx: amount, dy: 0)
        case 125: move(dx: 0, dy: amount)
        case 126: move(dx: 0, dy: -amount)
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "c" {
                Pasteboard.copy(currentColor.hex)
                Announcer.say("Copied \(currentColor.hex)")
            }
        }
    }

    private func move(dx: Int, dy: Int) {
        let g = displays[cursor.display].geometry
        cursor.x = min(max(cursor.x + dx, 0), g.pixelWidth - 1)
        cursor.y = min(max(cursor.y + dy, 0), g.pixelHeight - 1)
        // Keep the real pointer on the pick point so the mouse carries on
        // from where the keyboard left it.
        let global = g.globalPoint(forPixel: cursor.x, cursor.y)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? g.frame.height
        CGWarpMouseCursorPosition(DisplayGeometry.quartz(fromGlobal: global, primaryHeight: primaryHeight))
        CGAssociateMouseAndMouseCursorPosition(1)
        refresh()
    }

    private func escape() {
        if mode == .region, anchor != nil {
            anchor = nil
            refresh()
            Announcer.say("Corner cleared")
            return
        }
        finish(.cancelled)
    }

    private func back() {
        guard mode == .contrast, step == .background else { return }
        step = .text
        textColor = nil
        refresh()
        Announcer.say("Back to the text color")
    }

    private func space() {
        switch mode {
        case .region:
            finish(.display(displays[cursor.display]))
        case .contrast:
            var spoken = "\(step == .text ? "Text" : "Background") \(currentColor.hex)"
            if step == .background, let text = textColor {
                let ratio = WCAG.contrastRatio(text, currentColor)
                let verdict = ContrastRequirement.normalTextAA.passes(ratio) ? "passes" : "fails"
                spoken += ", \(WCAG.spokenRatio(ratio)), \(verdict) AA for normal text"
            }
            Announcer.say(spoken)
        }
    }

    private func commitPoint() {
        let color = currentColor
        switch mode {
        case .contrast:
            if step == .text {
                textColor = color
                step = .background
                refresh()
                Announcer.say("Text color \(color.hex). Now pick the background color.")
            } else if let text = textColor {
                finish(.contrast(text: text, background: color, worst: nil))
            }
        case .region:
            guard let a = anchor else {
                anchor = cursor
                refresh()
                Announcer.say("Corner set. Move to the opposite corner and press Return.")
                return
            }
            guard a.display == cursor.display else {
                Announcer.say("Move back to the display where you set the corner.")
                return
            }
            finish(.region(displays[a.display], PixelRect(corner: (a.x, a.y), corner: (cursor.x, cursor.y))))
        }
    }

    private func finishArea(from a: Point, to b: Point) {
        let rect = PixelRect(corner: (a.x, a.y), corner: (b.x, b.y))
        let display = displays[a.display]
        switch mode {
        case .region:
            finish(.region(display, rect))
        case .contrast:
            // A drag while choosing the text color picks where it ended.
            guard step == .background, let text = textColor else { commitPoint(); return }
            guard let worst = display.pixels.lowestContrast(in: rect, against: text) else { return }
            finish(.contrast(text: text, background: worst.color, worst: worst))
        }
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        if mode == .contrast { NSCursor.unhide() } else { NSCursor.pop() }
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        if case .cancelled = outcome { previousApp?.activate() }
        completion(outcome)
    }
}

#if DEBUG
extension FreezeOverlay {
    /// Puts the picker on its background step at a pixel, for snapshots.
    func demo(text: SRGB, x: Int, y: Int) {
        textColor = text
        step = .background
        cursor = Point(display: 0, x: x, y: y)
        refresh()
    }

    var demoView: NSView? { views.first }

    func demoCancel() { finish(.cancelled) }
}
#endif

/// Borderless, non-activating so it can take keyboard focus even when
/// macOS declines to activate the app, above everything including the menu bar.
final class OverlayPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Mouse moves come from each view's .activeAlways tracking area;
        // also accepting them on the key panel delivered every move twice.
        animationBehavior = .none
        // Keeps Esc and clicks working if a modal panel is somehow up.
        worksWhenModal = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
