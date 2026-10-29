import ColorCore
import Foundation

/// One checked color pair.
public struct ContrastCheck: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: SRGB
    public let background: SRGB
    /// Set when the background came from the lowest-contrast pixel of a dragged area.
    public let worstCaseArea: PixelRect?

    public init(id: UUID = UUID(), date: Date = Date(), text: SRGB, background: SRGB, worstCaseArea: PixelRect? = nil) {
        self.id = id
        self.date = date
        self.text = text.quantized
        self.background = background.quantized
        self.worstCaseArea = worstCaseArea
    }

    public var ratio: Double { WCAG.contrastRatio(text, background) }
    public var lc: Double { APCA.lc(text: text, background: background) }
}

/// One screen capture.
public struct CaptureRecord: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case region
        case window(appName: String?)
        case display
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let delayed: Bool

    public init(id: UUID = UUID(), date: Date = Date(), kind: Kind, pixelWidth: Int, pixelHeight: Int, delayed: Bool) {
        self.id = id
        self.date = date
        self.kind = kind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.delayed = delayed
    }

    public var description: String {
        var what: String
        switch kind {
        case .region: what = "Region"
        case .window(let app): what = app.map { "Window (\($0))" } ?? "Window"
        case .display: what = "Display"
        }
        if delayed { what += ", after a 3-second delay" }
        return what
    }
}

public enum LogEntry: Identifiable, Hashable, Sendable {
    case contrast(ContrastCheck)
    case capture(CaptureRecord)

    public var id: UUID {
        switch self {
        case .contrast(let c): c.id
        case .capture(let c): c.id
        }
    }

    public var date: Date {
        switch self {
        case .contrast(let c): c.date
        case .capture(let c): c.date
        }
    }
}

/// The Markdown summary a session exports to.
public enum MarkdownExport {
    public static func session(
        _ entries: [LogEntry],
        generated: Date,
        appVersion: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = timeZone
        day.dateStyle = .long
        day.timeStyle = .short
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateStyle = .none
        time.timeStyle = .short

        let checks = entries.compactMap { if case .contrast(let c) = $0 { c } else { nil } }
        let captures = entries.compactMap { if case .capture(let c) = $0 { c } else { nil } }

        var md = "# Accessibility check session\n\n"
        md += "Generated \(day.string(from: generated)) by Accessibility Build \(appVersion). "
        md += "Contrast ratios follow WCAG 2.2. APCA is the method in the WCAG 3 working draft and is included for guidance only.\n"

        if checks.isEmpty && captures.isEmpty {
            md += "\nNo checks or captures yet.\n"
            return md
        }

        if !checks.isEmpty {
            md += "\n## Contrast checks (\(checks.count))\n\n"
            md += "| # | Time | Text | Background | Ratio | Normal text, AA 4.5:1 | Large text, AA 3:1 | Non-text, AA 3:1 | Normal text, AAA 7:1 | APCA |\n"
            md += "|---|---|---|---|---|---|---|---|---|---|\n"
            var notes: [String] = []
            for (i, c) in checks.enumerated() {
                let r = c.ratio
                func verdict(_ req: ContrastRequirement) -> String { req.passes(r) ? "Pass" : "Fail" }
                md += "| \(i + 1) | \(time.string(from: c.date)) | `\(c.text.hex)` | `\(c.background.hex)` | \(WCAG.formatRatio(r)) | "
                md += "\(verdict(.normalTextAA)) | \(verdict(.largeTextAA)) | \(verdict(.nonText)) | \(verdict(.normalTextAAA)) | \(APCA.format(c.lc)) |\n"
                if let area = c.worstCaseArea {
                    notes.append("- Check \(i + 1): background is the lowest-contrast pixel in a \(area.width) × \(area.height) px area.")
                }
            }
            if !notes.isEmpty { md += "\n" + notes.joined(separator: "\n") + "\n" }
        }

        if !captures.isEmpty {
            md += "\n## Captures (\(captures.count))\n\n"
            md += "| # | Time | What | Size |\n|---|---|---|---|\n"
            for (i, c) in captures.enumerated() {
                md += "| \(i + 1) | \(time.string(from: c.date)) | \(c.description) | \(c.pixelWidth) × \(c.pixelHeight) px |\n"
            }
        }
        return md
    }
}
