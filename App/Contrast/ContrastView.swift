import AppKit
import AuditCore
import ColorCore
import SwiftUI

/// Results for one color pair, laid out the way macOS presents settings:
/// the answer first, then grouped rows. Every verdict is a word plus an
/// icon shape, never color alone, and each row reads to VoiceOver as one
/// sentence. Actions live in the window toolbar.
struct ContrastView: View {
    @Bindable var model: ContrastModel
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            Section {
                ContrastHero(model: model)
                ColorRow(title: "Text", field: $model.textField, color: model.text, error: model.textError,
                         onChange: { model.textFieldChanged(commit: false) },
                         onCommit: { model.textFieldChanged(commit: true) },
                         onPick: { model.setText($0) }, copied: show)
                ColorRow(title: "Background", field: $model.backgroundField, color: model.background, error: model.backgroundError,
                         onChange: { model.backgroundFieldChanged(commit: false) },
                         onCommit: { model.backgroundFieldChanged(commit: true) },
                         onPick: { model.setBackground($0) }, copied: show)
            } footer: {
                if let area = model.worstCaseArea {
                    Text("The background is the lowest-contrast pixel in a \(area.width) × \(area.height) px area.")
                }
            }

            Section("WCAG 2.2") {
                RequirementRow(title: "Normal text", detail: "1.4.3 and 1.4.6, needs 4.5:1 and 7:1",
                               checks: [(.normalTextAA, "AA"), (.normalTextAAA, "AAA")], ratio: model.ratio)
                RequirementRow(title: "Large text", detail: "1.4.3 and 1.4.6, needs 3:1 and 4.5:1",
                               checks: [(.largeTextAA, "AA"), (.largeTextAAA, "AAA")], ratio: model.ratio)
                RequirementRow(title: "UI components and graphics", detail: "1.4.11, needs 3:1",
                               checks: [(.nonText, "AA")], ratio: model.ratio)
            }

            Section {
                APCARow(lc: model.lc)
            } footer: {
                Text("APCA is the method in the WCAG 3 working draft. Guidance only, not a WCAG 2.2 test.")
            }

            Section {
                VisionStrip(text: model.text, background: model.background, baseRatio: model.ratio)
            } header: {
                Text("Color vision")
            } footer: {
                Text("Simulated with the Machado 2009 model. Ratios are indicative.")
            }

            if !model.fixes.isEmpty {
                Section {
                    ForEach(model.fixes) { fix in
                        FixRow(fix: fix, use: {
                            model.apply(fix)
                            show("Applied. \(WCAG.formatRatio(model.ratio))", spoken: "Applied. Contrast ratio \(WCAG.spokenRatio(model.ratio)).")
                        }, copy: {
                            Pasteboard.copy(fix.color.hex)
                            show("Copied \(fix.color.hex)")
                        })
                    }
                } header: {
                    Text("Nearest colors for \(model.fixGoal?.label ?? "")")
                } footer: {
                    Text("Lightness changes only, keeping hue and chroma where possible.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 480)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                    .padding(.bottom, 16)
                    .transition(reduceMotion ? .identity : .opacity)
                    .accessibilityHidden(true)
            }
        }
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { AppActions.shared.pickContrast() } label: {
                Label("Pick from Screen", systemImage: "eyedropper")
            }
            .help("Pick both colors from the screen")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.swap()
                show("Swapped", spoken: "Swapped. Text \(model.text.hex), background \(model.background.hex).")
            } label: {
                Label("Swap Colors", systemImage: "arrow.left.arrow.right")
            }
            .help("Swap text and background colors")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if model.recent.isEmpty {
                    Text("No recent pairs")
                }
                ForEach(model.recent) { check in
                    Button("\(check.text.hex) on \(check.background.hex), \(WCAG.formatRatio(check.ratio))") {
                        model.load(text: check.text, background: check.background, worstCaseArea: nil)
                    }
                }
                if !model.recent.isEmpty {
                    Divider()
                    Button("Clear Recent Pairs") { model.clearRecent() }
                }
            } label: {
                Label("Recent Pairs", systemImage: "clock.arrow.circlepath")
            }
            .help("Recent pairs")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Pasteboard.copy(FindingText.sentence(text: model.text, background: model.background))
                show("Finding copied")
            } label: {
                Label("Copy Finding", systemImage: "doc.on.doc")
            }
            .help("Copy a sentence describing this result against WCAG 2.2")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                SessionStore.shared.add(.contrast(ContrastCheck(text: model.text, background: model.background, worstCaseArea: model.worstCaseArea)))
                show("Added to the session log")
            } label: {
                Label("Add to Session Log", systemImage: "text.badge.plus")
            }
            .help("Add this pair to the session log")
        }
    }

    private func show(_ message: String) { show(message, spoken: message) }

    private func show(_ message: String, spoken: String) {
        Announcer.say(spoken)
        toastTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) { toast = nil }
        }
    }
}

// MARK: Hero

/// The answer first: the pair as it looks, the ratio, and one verdict line.
struct ContrastHero: View {
    let model: ContrastModel

    private var verdict: (title: String, detail: String, symbol: String, color: Color) {
        let r = model.ratio
        switch r {
        case 7...: return ("Passes AAA", "Enough contrast for text of any size.", "checkmark.seal.fill", Palette.pass)
        case 4.5..<7: return ("Passes AA", "Enough for text of any size. AAA needs 7:1.", "checkmark.circle.fill", Palette.pass)
        case 3..<4.5: return ("Large text and UI only", "Normal text needs 4.5:1 for AA.", "exclamationmark.triangle.fill", Palette.caution)
        default: return ("Fails AA", "Below 3:1 for text and for UI components.", "xmark.octagon.fill", Palette.fail)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aa")
                    .font(.system(size: 46, weight: .semibold))
                Text("Sample text")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Color(model.text))
            .frame(width: 150, height: 104, alignment: .center)
            .background(Color(model.background), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(WCAG.formatRatio(model.ratio))
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .textSelection(.enabled)
                Label {
                    Text(verdict.title).font(.headline)
                } icon: {
                    Image(systemName: verdict.symbol).foregroundStyle(verdict.color)
                }
                Text(verdict.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Contrast ratio \(WCAG.spokenRatio(model.ratio)). \(verdict.title). \(verdict.detail)")
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// A color: system color well, hex field and copy.
struct ColorRow: View {
    let title: String
    @Binding var field: String
    let color: SRGB
    let error: String?
    let onChange: () -> Void
    let onCommit: () -> Void
    let onPick: (SRGB) -> Void
    let copied: (String) -> Void
    @FocusState private var focused: Bool

    private var well: Binding<Color> {
        Binding(
            get: { Color(color) },
            set: { newValue in
                // The color panel can hand back Display P3; measure in sRGB.
                guard let c = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                onPick(SRGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent))
            }
        )
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField(title, text: $field)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 96)
                    .multilineTextAlignment(.leading)
                    .focused($focused)
                    .onChange(of: field) { onChange() }
                    .onSubmit(onCommit)
                    .onChange(of: focused) { if !focused { onCommit() } }
                    .accessibilityLabel("\(title) color")
                    .accessibilityHint("Hex value, for example #1A7F37")
                Button {
                    Pasteboard.copy(color.hex)
                    copied("Copied \(color.hex)")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(title.lowercased()) color")
                .accessibilityLabel("Copy \(title.lowercased()) color \(color.hex)")
            }
        } label: {
            HStack(spacing: 10) {
                ColorPicker(title, selection: well, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("\(title) color well")
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let error {
                        Text(error).foregroundStyle(Palette.fail)
                    }
                }
            }
        }
    }
}

struct RequirementRow: View {
    let title: String
    let detail: String
    let checks: [(ContrastRequirement, String)]
    let ratio: Double

    var body: some View {
        LabeledContent {
            // Fixed AA and AAA columns, so verdicts line up row to row.
            HStack(spacing: 12) {
                ForEach(["AA", "AAA"], id: \.self) { level in
                    if let req = checks.first(where: { $0.1 == level })?.0 {
                        LevelBadge(level: level, pass: req.passes(ratio))
                    } else {
                        Color.clear.frame(width: LevelBadge.width, height: 1)
                    }
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): " + checks.map { "\($0.1) \($0.0.passes(ratio) ? "passes" : "fails")" }.joined(separator: ", "))
        .accessibilityHint(detail)
    }
}

struct LevelBadge: View {
    let level: String
    let pass: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(pass ? Palette.pass : Palette.fail)
            Text(level).fontWeight(.medium).foregroundStyle(.primary)
            Text(pass ? "Pass" : "Fail").foregroundStyle(.secondary)
        }
        .frame(width: Self.width, alignment: .leading)
    }

    static let width: CGFloat = 96
}

/// APCA in one row: Lc plus the three use cases that matter most.
struct APCARow: View {
    let lc: Double
    private let cases: [(APCA.UseCase, String)] = [(.fluentText, "Body"), (.largeText, "Large"), (.uiComponent, "UI")]

    var body: some View {
        LabeledContent {
            HStack(spacing: 14) {
                ForEach(cases, id: \.1) { useCase, short in
                    HStack(spacing: 4) {
                        APCASymbol(level: APCA.level(lc, for: useCase))
                        Text(short).foregroundStyle(.primary)
                    }
                    .help("\(useCase.label): preferred Lc \(Int(useCase.thresholds.pass)), \(APCA.level(lc, for: useCase).rawValue.lowercased())")
                }
            }
        } label: {
            Text("APCA")
            Text(APCA.format(lc)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("APCA, L c \(String(format: "%.1f", lc)): " + cases.map { "\($0.0.label) \(APCA.level(lc, for: $0.0).rawValue.lowercased())" }.joined(separator: ", "))
    }
}

struct APCASymbol: View {
    let level: APCA.Level
    var body: some View {
        switch level {
        case .pass: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.pass)
        case .caution: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.caution)
        case .fail: Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.fail)
        }
    }
}

/// The pair under each deficiency, side by side in one row.
struct VisionStrip: View {
    let text: SRGB
    let background: SRGB
    let baseRatio: Double
    private let short: [CVD: String] = [.protanopia: "Protan", .deuteranopia: "Deutan", .tritanopia: "Tritan", .achromatopsia: "Mono"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CVD.allCases) { type in
                let t = type.simulate(text), b = type.simulate(background)
                let r = WCAG.contrastRatio(t, b)
                let drops = ContrastRequirement.normalTextAA.passes(baseRatio) && !ContrastRequirement.normalTextAA.passes(r)
                VStack(spacing: 5) {
                    Text("Aa")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(t))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color(b), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                    HStack(spacing: 3) {
                        if drops {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.caution)
                        }
                        Text(short[type] ?? type.name).foregroundStyle(.secondary)
                        Text(WCAG.formatRatio(r)).monospacedDigit()
                    }
                    .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .help("\(type.name), \(type.explanation.lowercased())")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(type.name), \(type.explanation): simulated contrast \(WCAG.spokenRatio(r))\(drops ? ", below 4.5 to 1" : "")")
            }
        }
        .padding(.vertical, 4)
    }
}

struct FixRow: View {
    let fix: ContrastModel.Fix
    let use: () -> Void
    let copy: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(fix.color))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                    .accessibilityHidden(true)
                Button("Copy", action: copy)
                    .controlSize(.small)
                    .accessibilityLabel("Copy \(fix.color.hex)")
                Button("Use", action: use)
                    .controlSize(.small)
                    .accessibilityLabel("Use \(fix.color.hex) as the \(fix.sideLabel.lowercased())")
            }
        } label: {
            Text("\(fix.sideLabel) \(fix.color.hex)").monospacedDigit()
            Text("\(WCAG.formatRatio(fix.ratio)) against the current \(fix.side == .text ? "background" : "text")").monospacedDigit()
        }
    }
}
