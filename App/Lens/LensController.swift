import AppKit
import AuditCore
import ColorCore
import CoreImage
import CoreImage.CIFilterBuiltins
import ScreenCaptureKit
import SwiftUI

@Observable
@MainActor
final class LensModel {
    var simulation: CVD? = .deuteranopia
    var severity = 1.0
    /// Blur radius in points; 0 is off.
    var blur = 0.0
    /// 0 is off, 0.8 removes most contrast.
    var contrastLoss = 0.0
    var split = false
    var status: String?

    var settings: LensSettings {
        LensSettings(simulation: simulation, severity: severity, blur: blur, contrastLoss: contrastLoss, split: split)
    }
}

struct LensSettings: Sendable, Equatable {
    var simulation: CVD?
    var severity: Double
    var blur: Double
    var contrastLoss: Double
    var split: Bool
}

/// A floating panel that shows what is beneath it through a color-vision or
/// low-vision filter. ScreenCaptureKit streams just the region under the
/// panel's image area, with every window of this app excluded so the lens
/// never films itself.
@MainActor
final class LensController: NSObject, NSWindowDelegate {
    static let shared = LensController()

    let model = LensModel()
    private var panel: LensPanel?
    private var imageView: LensImageView?
    private var stream: SCStream?
    private var streamDisplay: CGDirectDisplayID?
    private var streamScale: CGFloat = 2
    private let renderer = LensRenderer()
    private var geometryTask: Task<Void, Never>?
    // Every start, update and stop runs through one chain of tasks, each
    // awaiting the last, so two starts can never both create a stream. The
    // generation lets a queued start notice it has been superseded.
    private var streamTask: Task<Void, Never>?
    private var generation = 0
    private var isObserving = false
    #if DEBUG
    /// Snapshots show a still image; no screen stream may start.
    private var isDemo = false
    #endif

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            let mouse = NSEvent.mouseLocation
            panel.setFrameTopLeftPoint(NSPoint(x: mouse.x - 260, y: mouse.y + 160))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        observeSettings()
        renderer.update(model.settings)
        restartStream()
        Announcer.say("Color-vision lens open. \(simulationName). Arrow keys move the lens when its view has focus.")
    }

    func close() {
        panel?.orderOut(nil)
        stopStream()
    }

    var simulationName: String { model.simulation?.name ?? "No simulation" }

    // MARK: Panel

    private func makePanel() -> LensPanel {
        let panel = LensPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 380))
        panel.delegate = self
        let image = LensImageView()
        image.onMove = { [weak panel] dx, dy in
            guard let panel else { return }
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
        }
        image.onDigit = { [weak self] digit in self?.selectSimulation(digit) }
        image.simulationName = simulationName
        renderer.target = image.layer
        imageView = image
        panel.contentView = NSHostingView(rootView: LensRootView(model: model, imageView: image))
        return panel
    }

    func selectSimulation(_ digit: Int) {
        let options: [CVD?] = [.protanopia, .deuteranopia, .tritanopia, .achromatopsia, nil]
        guard (1...options.count).contains(digit) else { return }
        model.simulation = options[digit - 1]
        Announcer.say(simulationName)
    }

    private func observeSettings() {
        guard !isObserving else { return }
        isObserving = true
        track()
    }

    private func track() {
        withObservationTracking {
            _ = model.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.renderer.update(self.model.settings)
                self.imageView?.simulationName = self.simulationName
                self.track()
            }
        }
    }

    func windowDidMove(_ notification: Notification) { scheduleGeometryUpdate() }
    func windowDidResize(_ notification: Notification) { scheduleGeometryUpdate() }
    func windowWillClose(_ notification: Notification) { stopStream() }

    /// Throttled, not debounced: during a drag the lens follows every 30 ms
    /// instead of waiting for the pointer to pause.
    private func scheduleGeometryUpdate() {
        guard geometryTask == nil else { return }
        geometryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            self?.geometryTask = nil
            self?.restartStream()
        }
    }

    /// Called by the renderer when ScreenCaptureKit ends the stream (the
    /// user stopped sharing, the display went away). The next move or open
    /// builds a fresh stream instead of updating a dead one.
    func streamDidStop(_ error: Error) {
        stream = nil
        streamDisplay = nil
        model.status = "The lens stopped: \(error.localizedDescription)"
    }

    // MARK: Stream

    /// The image area in global coordinates and the screen holding its center.
    private func captureArea() -> (screen: NSScreen, rect: CGRect)? {
        guard let panel, let imageView else { return nil }
        let rect = panel.convertToScreen(imageView.convert(imageView.bounds, to: nil))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) ?? panel.screen else { return nil }
        return (screen, rect.intersection(screen.frame))
    }

    private func restartStream() {
        generation += 1
        let gen = generation
        let previous = streamTask
        streamTask = Task { [weak self] in
            await previous?.value
            await self?.startOrUpdateStream(generation: gen)
        }
    }

    private func stopStream() {
        generation += 1
        let previous = streamTask
        streamTask = Task { [weak self] in
            await previous?.value
            await self?.stopStreamAsync()
        }
    }

    private func isCurrent(_ gen: Int) -> Bool { gen == generation && isOpen }

    private func startOrUpdateStream(generation gen: Int) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard isCurrent(gen), let (screen, rect) = captureArea(), !rect.isEmpty, let displayID = screen.displayID else { return }

        func configuration(scale: CGFloat) -> SCStreamConfiguration {
            let geometry = DisplayGeometry(frame: screen.frame, scale: scale)
            let config = ScreenCapture.configuration(width: Int((rect.width * scale).rounded()), height: Int((rect.height * scale).rounded()))
            config.sourceRect = geometry.captureSourceRect(forGlobal: rect)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 4
            return config
        }

        do {
            // Same display: a move or resize only changes the source rect.
            if let stream, streamDisplay == displayID {
                try await stream.updateConfiguration(configuration(scale: streamScale))
                return
            }

            var content = try await ScreenCapture.shareableContent()
            // A just-shown lens can take a moment to reach the window list,
            // and until the app is listed it cannot be excluded as a whole.
            let pid = ProcessInfo.processInfo.processIdentifier
            if !content.applications.contains(where: { $0.processID == pid }) {
                try? await Task.sleep(for: .milliseconds(150))
                content = try await ScreenCapture.shareableContent()
            }
            guard isCurrent(gen), let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
            let filter = ScreenCapture.filterExcludingSelf(display: display, in: content)
            let scale = CGFloat(filter.pointPixelScale)
            renderer.pixelScale = scale

            await stopStreamAsync()
            let stream = SCStream(filter: filter, configuration: configuration(scale: scale), delegate: renderer)
            try stream.addStreamOutput(renderer, type: .screen, sampleHandlerQueue: renderer.queue)
            try await stream.startCapture()
            guard isCurrent(gen) else {
                // Closed or superseded while starting: do not leave it running.
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            streamDisplay = displayID
            streamScale = scale
            model.status = nil
        } catch ScreenCapture.Failure.permissionDenied {
            model.status = "The lens needs Screen Recording permission. Choose Allow Screen Recording in the menu."
        } catch {
            model.status = "The lens could not start: \(error.localizedDescription)"
        }
    }

    private func stopStreamAsync() async {
        guard let stream else { return }
        self.stream = nil
        streamDisplay = nil
        try? await stream.stopCapture()
    }
}

/// Renders frames off the main thread. Settings are copied under a lock so
/// a slider change never races a frame in flight.
final class LensRenderer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "build.accessibility.lens", qos: .userInteractive)
    private let lock = NSLock()
    private var settings = LensSettings(simulation: nil, severity: 1, blur: 0, contrastLoss: 0, split: false)
    private var scale: CGFloat = 2
    weak var target: CALayer?
    // Core Image works in linear light by default, which is the space the
    // Machado model is defined in.
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    var pixelScale: CGFloat {
        get { lock.withLock { scale } }
        set { lock.withLock { scale = newValue } }
    }

    // The last complete frame, kept so a settings change shows at once even
    // when nothing under the lens moves: ScreenCaptureKit then sends only
    // idle frames. Touched on `queue` only.
    private var lastBuffer: CVPixelBuffer?

    func update(_ s: LensSettings) {
        lock.withLock { settings = s }
        queue.async { [weak self] in
            guard let self, let buffer = self.lastBuffer else { return }
            self.present(buffer)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        lastBuffer = pixelBuffer
        present(pixelBuffer)
    }

    private func present(_ pixelBuffer: CVPixelBuffer) {
        let (s, scale) = lock.withLock { (settings, self.scale) }
        guard let image = render(CIImage(cvPixelBuffer: pixelBuffer), s, scale: scale) else { return }
        DispatchQueue.main.async { [weak self] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.target?.contents = image
            CATransaction.commit()
        }
    }

    func render(_ original: CIImage, _ s: LensSettings, scale: CGFloat) -> CGImage? {
        let extent = original.extent
        var output = Self.filter(original, s, scale: scale)
        if s.split {
            let half = CGRect(x: extent.midX, y: extent.minY, width: extent.width / 2, height: extent.height)
            output = output.cropped(to: half).composited(over: original)
        }
        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: outputSpace)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in self?.lastBuffer = nil }
        Task { @MainActor in LensController.shared.streamDidStop(error) }
    }

    static func filter(_ input: CIImage, _ s: LensSettings, scale: CGFloat) -> CIImage {
        var image = input
        let extent = input.extent
        if let simulation = s.simulation, s.severity > 0 {
            let m = simulation.linearMatrix(severity: s.severity)
            let f = CIFilter.colorMatrix()
            f.inputImage = image
            f.rVector = CIVector(x: m[0], y: m[1], z: m[2], w: 0)
            f.gVector = CIVector(x: m[3], y: m[4], z: m[5], w: 0)
            f.bVector = CIVector(x: m[6], y: m[7], z: m[8], w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            image = f.outputImage ?? image
        }
        if s.contrastLoss > 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.contrast = Float(1 - s.contrastLoss)
            f.saturation = 1
            f.brightness = 0
            image = f.outputImage ?? image
        }
        if s.blur > 0 {
            image = image.clampedToExtent().applyingGaussianBlur(sigma: s.blur * scale).cropped(to: extent)
        }
        return image
    }
}

#if DEBUG
extension LensController {
    var demoWindow: NSWindow? { panel }

    /// Shows a still image through the current filters, for snapshots
    /// taken without Screen Recording permission.
    func showDemo(_ image: CGImage, crop: CGRect) {
        isDemo = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(NSSize(width: 560, height: 420))
        panel.center()
        panel.orderFrontRegardless()
        model.status = nil
        imageView?.simulationName = simulationName
        guard let cropped = image.cropping(to: crop),
              let frame = renderer.render(CIImage(cgImage: cropped), model.settings, scale: 2),
              let imageView else { return }
        imageView.layer?.contents = frame
        imageView.subviews.forEach { $0.removeFromSuperview() }
        let still = NSImageView(frame: imageView.bounds)
        still.image = NSImage(cgImage: frame, size: imageView.bounds.size)
        still.imageScaling = .scaleProportionallyUpOrDown
        still.autoresizingMask = [.width, .height]
        still.setAccessibilityElement(false)
        imageView.addSubview(still)
    }
}
#endif

final class LensPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Content-first: the view runs under a transparent title bar. The
        // title stays set for VoiceOver and the Window menu.
        title = "Color-Vision Lens"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        minSize = NSSize(width: 320, height: 240)
        // Every frame is filtered and copied; a bounded lens keeps that cheap.
        maxSize = NSSize(width: 1400, height: 1000)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    // Number keys switch the simulation from anywhere in the panel, unless a
    // text field is taking typing.
    override func keyDown(with event: NSEvent) {
        if let digit = Int(event.charactersIgnoringModifiers ?? ""), event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            LensController.shared.selectSimulation(digit)
            return
        }
        super.keyDown(with: event)
    }
}

/// Shows the filtered frames. Focusable, so the lens can be moved with the
/// arrow keys instead of dragging.
final class LensImageView: NSView {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onDigit: ((Int) -> Void)?
    var simulationName = "" { didSet { updateAccessibility() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspectFill
        layer?.magnificationFilter = .nearest
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func updateAccessibility() {
        setAccessibilityLabel("Lens view, \(simulationName)")
        setAccessibilityHelp("Shows what is under the lens. Arrow keys move the lens, Shift-arrow moves it further. Keys 1 to 4 choose a simulation, 5 turns it off.")
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func drawFocusRingMask() { bounds.fill() }
    override var focusRingMaskBounds: NSRect { bounds }

    override func mouseDown(with event: NSEvent) {
        // Focus for the arrow keys, and still drag the lens like its frame.
        window?.makeFirstResponder(self)
        window?.performDrag(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 20 : 2
        switch event.keyCode {
        case 123: onMove?(-step, 0)
        case 124: onMove?(step, 0)
        case 125: onMove?(0, -step)
        case 126: onMove?(0, step)
        default:
            if let digit = Int(event.charactersIgnoringModifiers ?? "") { onDigit?(digit) } else { super.keyDown(with: event) }
        }
    }
}

struct LensImageRepresentable: NSViewRepresentable {
    let view: LensImageView
    func makeNSView(context: Context) -> LensImageView { view }
    func updateNSView(_ nsView: LensImageView, context: Context) {}
}

/// The lens is mostly picture: the filtered view fills the window, with a
/// slim control bar floating at the bottom and the split marked in place.
struct LensRootView: View {
    @Bindable var model: LensModel
    let imageView: LensImageView

    var body: some View {
        ZStack {
            LensImageRepresentable(view: imageView)
            if model.split {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1.5)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .frame(height: proxy.size.height)
                    HStack(spacing: 8) {
                        LensTag(text: "Original")
                        LensTag(text: model.simulation?.name ?? "No simulation")
                    }
                    .position(x: proxy.size.width / 2, y: 44)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            if let status = model.status {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(status)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Screen Recording Settings…") { Windows.showPermission() }
                }
                .padding(20)
                .frame(maxWidth: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .overlay(alignment: .bottom) {
            LensControlBar(model: model).padding(.bottom, 12)
        }
        .ignoresSafeArea()
    }
}

struct LensTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .modifier(HUDBackground(shape: Capsule()))
            .environment(\.colorScheme, .dark)
    }
}

struct LensControlBar: View {
    @Bindable var model: LensModel
    @State private var showsAdjustments = false

    private var simulationID: Binding<String> {
        Binding(get: { model.simulation?.rawValue ?? "none" }, set: { model.simulation = CVD(rawValue: $0) })
    }

    private static let shortNames: [CVD: String] = [
        .protanopia: "Protan", .deuteranopia: "Deutan", .tritanopia: "Tritan", .achromatopsia: "Mono",
    ]

    var body: some View {
        HStack(spacing: 8) {
            Picker("Simulation", selection: simulationID) {
                ForEach(CVD.allCases) { type in
                    Text(Self.shortNames[type] ?? type.name).tag(type.rawValue)
                        .accessibilityLabel(type.name)
                }
                Text("Off").tag("none").accessibilityLabel("No simulation")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Simulation. Keys 1 to 4 choose one, 5 turns it off.")

            Toggle(isOn: $model.split) {
                Label("Split View", systemImage: "rectangle.split.2x1")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help("Split view: original on the left, simulated on the right")

            Button {
                showsAdjustments.toggle()
            } label: {
                Label("Adjust", systemImage: "slider.horizontal.3")
            }
            .labelStyle(.iconOnly)
            .help("Severity, blur and contrast loss")
            .popover(isPresented: $showsAdjustments, arrowEdge: .top) {
                LensAdjustments(model: model)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .modifier(BarBackground())
    }
}

/// The lens bar sits on live content: glass on macOS 26 and later, a
/// regular material before, solid with Reduce Transparency.
struct BarBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var solid: Bool {
        #if DEBUG
        if Snapshot.isActive { return true }
        #endif
        return reduceTransparency
    }

    func body(content: Content) -> some View {
        if solid {
            content.background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

struct LensAdjustments: View {
    @Bindable var model: LensModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            row("Severity", value: $model.severity, range: 0...1,
                display: "\(Int((model.severity * 100).rounded()))%", disabled: model.simulation == nil)
            row("Blur", value: $model.blur, range: 0...12,
                display: model.blur < 0.5 ? "Off" : "\(Int(model.blur.rounded())) pt", disabled: false)
            row("Contrast loss", value: $model.contrastLoss, range: 0...0.8,
                display: model.contrastLoss < 0.01 ? "Off" : "\(Int((model.contrastLoss * 100).rounded()))%", disabled: false)
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private func row(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String, disabled: Bool) -> some View {
        GridRow {
            Text(title)
            Slider(value: value, in: range) { Text(title) }
                .labelsHidden()
                .accessibilityValue(display)
            Text(display)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .disabled(disabled)
    }
}
