#if DEBUG
import AppKit
import AuditCore
import SwiftUI
import ColorCore

/// Debug builds only: renders the app's windows to PNG files for docs,
/// reviews and visual checks, with no Screen Recording permission and no
/// UI automation. The picker and lens are fed a sample screen image.
///
///   "Accessibility Build" -snapshotDir /path -snapshotAppearance dark
@MainActor
enum Snapshot {
    /// Offscreen rendering cannot draw glass, materials or raw layer
    /// contents, so while snapshotting the app uses its Reduce Transparency
    /// look and plain image views.
    nonisolated(unsafe) static var isActive = false

    static func runIfRequested() -> Bool {
        guard let dir = UserDefaults.standard.string(forKey: "snapshotDir") else { return false }
        isActive = true
        let appearance = UserDefaults.standard.string(forKey: "snapshotAppearance") ?? "light"
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        Task {
            await capture(to: URL(fileURLWithPath: dir), suffix: appearance)
            if appearance == "light" { await storeShots(to: URL(fileURLWithPath: dir).appendingPathComponent("app-store")) }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    private static func capture(to dir: URL, suffix: String) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ data: Data?, _ name: String) {
            guard let data else { return }
            try? data.write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
        }
        func audit(_ window: NSWindow?, _ name: String) {
            guard suffix == "light", let window else { return }
            AXAudit.write(AXAudit.audit(window), name: name, to: dir)
        }

        // The menu-bar glyph at 1x and 2x, black and white, magnified.
        write(statusIconPreview(), "status-icon")

        // Check Colors with a failing pair, so the fixes section shows.
        ContrastModel.shared.load(text: SRGB(hex: "#8A8A8A")!, background: .white, worstCaseArea: nil)
        Windows.showChecker()
        if let w = Windows.window("checker") {
            // Taller than most screens allow, so shoot the top and the bottom.
            w.setContentSize(NSSize(width: 540, height: 760))
            await settle()
            write(png(of: w), "check-colors")
            audit(w, "check-colors")
            scrollToBottom(w.contentView)
            await settle()
            write(png(of: w), "check-colors-lower")
            w.setContentSize(NSSize(width: 560, height: 720))
            w.close()
        }

        let store = SessionStore.shared
        store.add(.contrast(ContrastCheck(text: SRGB(hex: "#8A8A8A")!, background: .white)))
        store.add(.contrast(ContrastCheck(text: .white, background: SRGB(hex: "#E8743B")!, worstCaseArea: PixelRect(x: 0, y: 0, width: 480, height: 120))))
        store.add(.capture(CaptureRecord(kind: .window(appName: "Safari"), pixelWidth: 2560, pixelHeight: 1600, delayed: false)))
        store.add(.capture(CaptureRecord(kind: .region, pixelWidth: 640, pixelHeight: 360, delayed: true)))
        Windows.showSessionLog()
        if let w = Windows.window("log") { await settle(); write(png(of: w), "session-log"); audit(w, "session-log"); w.close() }

        Windows.showSettings()
        if let w = Windows.window("settings"), let tabs = w.contentViewController as? NSTabViewController {
            let items = (w.toolbar?.items ?? []).map(\.itemIdentifier.rawValue).joined(separator: "\n")
            try? (items + "\n").write(to: dir.appendingPathComponent("toolbar-settings.txt"), atomically: true, encoding: .utf8)
            for (i, tab) in SettingsTabsController.tabs.enumerated() {
                tabs.selectedTabViewItemIndex = i
                await settle()
                let name = "settings-\(tab.title.lowercased())"
                write(png(of: w), name)
                audit(w, name)
            }
            tabs.selectedTabViewItemIndex = 0
            w.close()
        }

        Windows.showWelcome()
        if let w = Windows.window("welcome") { await settle(); write(png(of: w), "welcome"); audit(w, "welcome"); w.close() }

        Windows.showPermission()
        if let w = Windows.window("permission") { await settle(); write(png(of: w), "screen-recording"); audit(w, "screen-recording"); w.close() }

        // A region capture of the sample page.
        let page = SampleScreen.image(width: 3200, height: 2000, scale: 2)
        if let region = page.cropping(to: CGRect(x: 80, y: 180, width: 1600, height: 900)) {
            Windows.showCaptureResult(CaptureResult(
                image: region, scale: 2,
                record: CaptureRecord(kind: .region, pixelWidth: region.width, pixelHeight: region.height, delayed: true)))
            if let w = Windows.window("capture") { await settle(); write(png(of: w), "capture"); audit(w, "capture"); w.close() }
        }

        // The three-second countdown.
        let countdownModel = CountdownHUD.Model()
        let countdown = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 112, height: 112), styleMask: [.borderless], backing: .buffered, defer: false)
        countdown.isOpaque = false
        countdown.backgroundColor = .clear
        countdown.contentView = NSHostingView(rootView: CountdownHUD.CountdownView(model: countdownModel))
        countdown.center()
        countdown.orderFrontRegardless()
        await settle()
        write(png(of: countdown), "countdown")
        countdown.orderOut(nil)

        // Lens over the sample screen.
        let sample = SampleScreen.image(width: 3200, height: 2000, scale: 2)
        let lens = LensController.shared
        lens.model.simulation = .deuteranopia
        lens.model.split = true
        // Over the chart and the status chips, where red and green matter.
        lens.showDemo(sample, crop: CGRect(x: 60, y: 400, width: 1120, height: 960))
        await settle()
        lens.showDemo(sample, crop: CGRect(x: 60, y: 400, width: 1120, height: 960))
        if let w = lens.demoWindow { await settle(); write(png(of: w), "lens"); audit(w, "lens") }
        lens.close()

        // Picker over the sample screen, on the background step, with the
        // loupe over the gradient behind white text.
        if let screen = NSScreen.main,
           let display = SampleScreen.frozenDisplay(for: screen) {
            let overlay = FreezeOverlay(displays: [display], mode: .contrast) { _ in }
            overlay.show()
            // Light end of the hero gradient, behind the white headline.
            let s = display.geometry.scale
            overlay.demo(text: .white, x: Int((screen.frame.width - 140) * s), y: Int(330 * s))
            await settle()
            if let w = overlay.demoView?.window { write(png(of: w), "picker"); audit(w, "picker") }
            overlay.demoCancel()
        }
    }

    private static func scrollToTop(_ view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let y = document.isFlipped ? 0 : max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        for sub in view.subviews { scrollToTop(sub) }
    }

    private static func scrollToBottom(_ view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let y = document.isFlipped ? document.bounds.height - scroll.contentView.bounds.height : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        for sub in view.subviews { scrollToBottom(sub) }
    }

    // MARK: Mac App Store screenshots

    /// 2880 x 1800 (16:10 at 2x), the largest size App Store Connect takes.
    /// Every image is the app's real interface over the sample page or a
    /// plain backdrop; nothing is drawn that the app does not draw.
    private static func storeShots(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let page = SampleScreen.image(width: 2880, height: 1800, scale: 2)
        let wallpaper = Self.wallpaper()
        func save(_ image: CGImage?, _ name: String) {
            // App Store Connect rejects screenshots that carry an alpha channel.
            guard let image, let flat = opaque(image),
                  let data = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { return }
            try? data.write(to: dir.appendingPathComponent("\(name).png"))
        }
        func capture(_ window: NSWindow) async -> CGImage? {
            await settle()
            return png(of: window).flatMap { NSBitmapImageRep(data: $0)?.cgImage }
        }

        // 1. The picker over a page, measuring white text on the gradient.
        if let screen = NSScreen.main, let id = screen.displayID,
           let (image, pixels) = try? ScreenCapture.toSRGB(page) {
            let display = FrozenDisplay(
                displayID: id,
                geometry: DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2),
                image: image, pixels: pixels)
            let overlay = FreezeOverlay(displays: [display], mode: .contrast) { _ in }
            overlay.show()
            overlay.demo(text: .white, x: 2600, y: 660)
            if let w = overlay.demoView?.window { save(await capture(w), "1-picker") }
            overlay.demoCancel()
        }

        // 2. Check Colors beside the page it is checking.
        ContrastModel.shared.load(text: .white, background: SRGB(hex: "#E8743B")!, worstCaseArea: nil)
        Windows.showChecker()
        if let w = Windows.window("checker") {
            w.setContentSize(NSSize(width: 540, height: 800))
            scrollToTop(w.contentView)
            save(compose(page, dim: true, [(await capture(w), CGPoint(x: 1640, y: 110))]), "2-check-colors")
            w.close()
        }

        // 3. The lens over the chart, showing exactly what is beneath it.
        let lens = LensController.shared
        lens.model.simulation = .deuteranopia
        lens.model.split = true
        let lensOrigin = CGPoint(x: 120, y: 500)
        lens.showDemo(page, crop: CGRect(x: lensOrigin.x, y: lensOrigin.y, width: 1120, height: 840))
        if let w = lens.demoWindow {
            await settle()
            // Crop exactly what the window covers, at its real size, so the
            // lens shows the chart that is beneath it.
            let scale = w.backingScaleFactor
            let crop = CGRect(x: lensOrigin.x, y: lensOrigin.y, width: w.frame.width * scale, height: w.frame.height * scale)
            lens.showDemo(page, crop: crop)
            save(compose(page, dim: false, [(await capture(w), lensOrigin)]), "3-lens")
        }
        lens.close()

        // 4. The session log and keyboard shortcuts.
        Windows.showSessionLog()
        Windows.showSettings()
        if let log = Windows.window("log"), let settings = Windows.window("settings"),
           let tabs = settings.contentViewController as? NSTabViewController {
            log.setContentSize(NSSize(width: 600, height: 340))
            tabs.selectedTabViewItemIndex = 2
            let logImage = await capture(log)
            let settingsImage = await capture(settings)
            save(compose(wallpaper, dim: false, [(logImage, CGPoint(x: 180, y: 420)), (settingsImage, CGPoint(x: 1500, y: 330))]), "4-log-and-privacy")
            tabs.selectedTabViewItemIndex = 0
            log.close()
            settings.close()
        }

        // 5. The welcome window, which points to the menu bar.
        Windows.showWelcome()
        if let w = Windows.window("welcome") {
            let image = await capture(w)
            let x = image.map { CGFloat(2880 - $0.width) / 2 } ?? 900
            save(compose(wallpaper, dim: false, [(image, CGPoint(x: x, y: 180))]), "5-welcome")
            w.close()
        }
    }

    /// The image drawn over white with no alpha channel.
    private static func opaque(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    /// A soft light backdrop for windows that are not about a page.
    private static func wallpaper() -> CGImage {
        let ctx = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
            CGColor(srgbRed: 0.86, green: 0.90, blue: 0.97, alpha: 1),
            CGColor(srgbRed: 0.95, green: 0.91, blue: 0.95, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1800), end: CGPoint(x: 2880, y: 0), options: [])
        return ctx.makeImage()!
    }

    /// Windows over a backdrop, with macOS-like rounded corners and shadow.
    /// Origins are in pixels from the top-left corner.
    private static func compose(_ backdrop: CGImage, dim: Bool, _ windows: [(CGImage?, CGPoint)]) -> CGImage? {
        let width = 2880, height = 1800
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(backdrop, in: CGRect(x: 0, y: 0, width: width, height: height))
        if dim {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.12))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        for case let (image?, origin) in windows {
            let rect = CGRect(x: origin.x, y: CGFloat(height) - origin.y - CGFloat(image.height), width: CGFloat(image.width), height: CGFloat(image.height))
            let shape = CGPath(roundedRect: rect, cornerWidth: 40, cornerHeight: 40, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: CGColor(gray: 0, alpha: 0.35))
            ctx.addPath(shape)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.draw(image, in: rect)
            ctx.restoreGState()
            ctx.addPath(shape)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
            ctx.setLineWidth(2)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    /// The glyph as the menu bar shows it (18 pt at 1x and 2x, light and
    /// dark bars), each cell blown up 8 times with no smoothing.
    private static func statusIconPreview() -> Data? {
        let cell = 18, zoom = 8, gap = 8
        let width = (cell * 2 + gap * 3) * zoom * 2, height = (cell * 2 + gap * 2) * zoom
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        for (i, (bar, ink)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.16, alpha: 1), NSColor.white)].enumerated() {
            let originX = i * width / 2
            ctx.setFillColor(bar.cgColor)
            ctx.fill(CGRect(x: originX, y: 0, width: width / 2, height: height))
            for (j, scale) in [1, 2].enumerated() {
                // Render at the real pixel size, then magnify.
                let px = cell * scale
                guard let small = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                small.translateBy(x: 0, y: CGFloat(px))
                small.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: small, flipped: true)
                StatusIcon.draw(in: CGRect(x: 0, y: 0, width: cell, height: cell))
                NSGraphicsContext.restoreGraphicsState()
                guard let mask = small.makeImage() else { continue }
                let size = cell * zoom
                let rect = CGRect(x: originX + (gap + j * (cell + gap)) * zoom, y: gap * zoom, width: size, height: size)
                ctx.saveGState()
                ctx.clip(to: rect, mask: mask)
                ctx.setFillColor(ink.cgColor)
                ctx.fill(rect)
                ctx.restoreGState()
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The window including its title bar.
    static func png(of window: NSWindow) -> Data? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Layer-tree render, for views whose content is set on layers directly.
    static func pngFromLayers(of view: NSView) -> Data? {
        guard let layer = view.layer else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// A made-up web page with the usual contrast and color-vision traps:
/// light grey body text, white text on a warm gradient, red and green
/// status chips, and a red/green chart.
@MainActor
enum SampleScreen {
    /// Drawn in points at `scale` pixels per point, so text is crisp and
    /// sized as it would be on screen.
    static func image(width: Int, height: Int, scale: CGFloat = 1) -> CGImage {
        let w = CGFloat(width) / scale, h = CGFloat(height) / scale
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        do {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: w, height: h).fill()

            NSColor(srgbRed: 0.04, green: 0.06, blue: 0.1, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: w, height: 72).fill()
            draw("Acme Analytics", at: NSPoint(x: 40, y: 22), size: 22, weight: .bold, color: .white)
            draw("Dashboard    Reports    Settings", at: NSPoint(x: w - 420, y: 26), size: 16, weight: .medium, color: NSColor(white: 0.8, alpha: 1))

            draw("Quarterly overview", at: NSPoint(x: 40, y: 110), size: 34, weight: .bold, color: NSColor(white: 0.07, alpha: 1))
            draw("Revenue grew in every region except the north, where two stores closed.", at: NSPoint(x: 40, y: 164), size: 18, weight: .regular, color: NSColor(srgbRed: 0.54, green: 0.54, blue: 0.54, alpha: 1))

            chip("Online", color: NSColor(srgbRed: 0.18, green: 0.62, blue: 0.29, alpha: 1), at: NSPoint(x: 40, y: 210))
            chip("Error", color: NSColor(srgbRed: 0.86, green: 0.2, blue: 0.2, alpha: 1), at: NSPoint(x: 150, y: 210))
            chip("Pending", color: NSColor(srgbRed: 0.93, green: 0.6, blue: 0.1, alpha: 1), at: NSPoint(x: 250, y: 210))

            // Chart: profit in green, loss in red.
            let chart = NSRect(x: 40, y: 280, width: 640, height: 420)
            NSColor(white: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: chart, xRadius: 12, yRadius: 12).fill()
            let values: [CGFloat] = [0.6, 0.8, -0.3, 0.5, -0.5, 0.9, 0.4, -0.2]
            for (i, v) in values.enumerated() {
                let barWidth: CGFloat = 52, mid = chart.midY
                let x = chart.minX + 30 + CGFloat(i) * 74
                let height = abs(v) * 170
                (v >= 0 ? NSColor(srgbRed: 0.2, green: 0.66, blue: 0.3, alpha: 1) : NSColor(srgbRed: 0.85, green: 0.22, blue: 0.2, alpha: 1)).setFill()
                NSRect(x: x, y: v >= 0 ? mid - height : mid, width: barWidth, height: height).fill()
            }

            // Hero with white text on a gradient.
            let hero = NSRect(x: 740, y: 280, width: w - 780, height: 420)
            let gradient = NSGradient(colors: [
                NSColor(srgbRed: 0.42, green: 0.25, blue: 0.85, alpha: 1),
                NSColor(srgbRed: 0.98, green: 0.6, blue: 0.3, alpha: 1),
            ])
            gradient?.draw(in: NSBezierPath(roundedRect: hero, xRadius: 16, yRadius: 16), angle: 0)
            draw("Try the new reports", at: NSPoint(x: hero.minX + 40, y: hero.minY + 140), size: 40, weight: .bold, color: .white)
            draw("Export any view as a PDF in one click.", at: NSPoint(x: hero.minX + 40, y: hero.minY + 200), size: 20, weight: .regular, color: .white)

            NSColor(srgbRed: 0.15, green: 0.39, blue: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 40, y: 740, width: 180, height: 52), xRadius: 10, yRadius: 10).fill()
            draw("Download", at: NSPoint(x: 82, y: 754), size: 18, weight: .semibold, color: .white)
            draw("Last updated 3 minutes ago", at: NSPoint(x: 250, y: 756), size: 16, weight: .regular, color: NSColor(white: 0.66, alpha: 1))
        }
        return ctx.makeImage()!
    }

    private static func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }

    private static func chip(_ text: String, color: NSColor, at point: NSPoint) {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: point.x, y: point.y, width: 90, height: 34), xRadius: 17, yRadius: 17).fill()
        draw(text, at: NSPoint(x: point.x + 18, y: point.y + 7), size: 15, weight: .semibold, color: .white)
    }

    static func frozenDisplay(for screen: NSScreen) -> FrozenDisplay? {
        let scale = screen.backingScaleFactor
        let geometry = DisplayGeometry(frame: screen.frame, scale: scale)
        let source = image(width: geometry.pixelWidth, height: geometry.pixelHeight, scale: scale)
        guard let (image, pixels) = try? ScreenCapture.toSRGB(source), let id = screen.displayID else { return nil }
        return FrozenDisplay(displayID: id, geometry: geometry, image: image, pixels: pixels)
    }
}
#endif
