import SwiftUI

/// `config`: timer lengths, terminal style, and colours from the colour wheel.
struct SettingsSheet: View {
    /// The screen's current palette, so the sheet looks like part of the same terminal.
    let palette: Palette

    @Environment(\.dismiss) private var dismiss

    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("restMinutes") private var restMinutes = 5
    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .cozy
    @AppStorage("focusAccentHex") private var focusAccentHex = ""
    @AppStorage("restAccentHex") private var restAccentHex = ""
    @AppStorage("focusBackgroundHex") private var focusBackgroundHex = ""
    @AppStorage("restBackgroundHex") private var restBackgroundHex = ""
    @AppStorage("fontCozy") private var fontCozy: TerminalFont = .jetbrains
    @AppStorage("fontPowershell") private var fontPowershell: TerminalFont = .cascadia
    @AppStorage(Feedback.Key.sounds) private var soundsEnabled = true
    @AppStorage(Feedback.Key.haptics) private var hapticsEnabled = true
    @AppStorage(Feedback.Key.tickSound) private var tickSound = true
    @AppStorage(Feedback.Key.tickHaptics) private var tickHaptics = true

    private struct Preset: Hashable {
        let focus: Int
        let rest: Int
    }

    private static let presets = [Preset(focus: 25, rest: 5), Preset(focus: 50, rest: 10), Preset(focus: 15, rest: 3), Preset(focus: 90, rest: 20)]

    var body: some View {
        NavigationStack {
            Form {
                timerSection
                styleSection
                fontSection
                colorSection
                feedbackSection
                aboutSection
            }
            .font(palette.mono(15, relativeTo: .body))
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle(terminalStyle == .cozy ? "~/config" : "Get-Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        // A soft key click for every change made here.
        .onChange(of: terminalStyle) { Feedback.play(.tap) }
        .onChange(of: [focusMinutes, restMinutes]) { Feedback.play(.tap) }
        .onChange(of: [fontCozy, fontPowershell]) { Feedback.play(.tap) }
        .onChange(of: [focusAccentHex, restAccentHex, focusBackgroundHex, restBackgroundHex]) { Feedback.play(.tap) }
        .onChange(of: [soundsEnabled, hapticsEnabled, tickSound, tickHaptics]) { Feedback.play(.tap) }
    }

    // MARK: Timer

    private var timerSection: some View {
        Section {
            Stepper(value: $focusMinutes, in: PomodoroDurations.focusRange) {
                LabeledContent("focus", value: "\(focusMinutes) min")
            }
            Stepper(value: $restMinutes, in: PomodoroDurations.restRange) {
                LabeledContent("break", value: "\(restMinutes) min")
            }
            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { preset in
                    let selected = preset.focus == focusMinutes && preset.rest == restMinutes
                    Button {
                        focusMinutes = preset.focus
                        restMinutes = preset.rest
                    } label: {
                        Text("\(preset.focus)/\(preset.rest)")
                            .font(palette.mono(13, selected ? .bold : .regular, relativeTo: .footnote))
                            .foregroundStyle(selected ? palette.background : palette.text)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(selected ? palette.accent : palette.border.opacity(0.5), in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.focus) minute focus, \(preset.rest) minute break")
                }
            }
        } header: {
            header("timer")
        } footer: {
            Text("An idle timer updates right away; a running block keeps its time and the change applies next block.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
    }

    // MARK: Style

    private var styleSection: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(TerminalStyle.allCases) { style in
                    styleCard(style)
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            header("style")
        }
        .listRowBackground(palette.surface)
    }

    private func styleCard(_ style: TerminalStyle) -> some View {
        let preview = style.basePalette(for: .focus)
        let selected = style == terminalStyle
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { terminalStyle = style }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Text(style.promptPath).foregroundStyle(preview.accent)
                    Text(style.promptSymbol).foregroundStyle(preview.dim)
                    Text(style.cursor).foregroundStyle(preview.accent)
                }
                .font(preview.mono(12, .bold, relativeTo: .caption))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(style.name)
                    .font(preview.mono(13, selected ? .bold : .regular, relativeTo: .footnote))
                    .foregroundStyle(preview.text)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(preview.background, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? palette.accent : preview.border, lineWidth: selected ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.name) style")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Font

    /// The font for the current style; each style remembers its own.
    private var selectedFont: Binding<TerminalFont> {
        terminalStyle == .cozy ? $fontCozy : $fontPowershell
    }

    private var fontSection: some View {
        Section {
            ForEach(TerminalFont.allCases) { font in
                fontRow(font)
            }
            if selectedFont.wrappedValue != terminalStyle.defaultFont {
                Button("use \(terminalStyle.defaultFont.name) (default)", systemImage: "arrow.counterclockwise") {
                    selectedFont.wrappedValue = terminalStyle.defaultFont
                }
                .foregroundStyle(palette.accent)
            }
        } header: {
            header("font")
        } footer: {
            Text("Each style keeps its own font. Switch style to set the other one.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
    }

    private func fontRow(_ font: TerminalFont) -> some View {
        let selected = font == selectedFont.wrappedValue
        return Button {
            selectedFont.wrappedValue = font
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(font.name)
                        .font(font.font(15, .bold, relativeTo: .body))
                        .foregroundStyle(selected ? palette.accent : palette.text)
                    Text("\(terminalStyle.promptPath)\(terminalStyle.promptSymbol)25:00 0Oo1lI")
                        .font(font.font(12, .regular, relativeTo: .caption))
                        .foregroundStyle(palette.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        Section {
            Toggle("sounds", isOn: $soundsEnabled)
            Toggle("haptics", isOn: $hapticsEnabled)
            Toggle("tick sound", isOn: $tickSound)
                .disabled(!soundsEnabled)
            Toggle("tick haptics", isOn: $tickHaptics)
                .disabled(!hapticsEnabled)
        } header: {
            header("feedback")
        } footer: {
            Text("Clicks and beeps for start, pause, reset, tasks and settings, plus a tick every second while running. Sounds follow the silent switch; the end-of-block chime doesn't.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
    }

    // MARK: Colours

    private var colorSection: some View {
        Section {
            colorRow("focus accent", hex: $focusAccentHex, fallback: terminalStyle.basePalette(for: .focus).accent)
            colorRow("break accent", hex: $restAccentHex, fallback: terminalStyle.basePalette(for: .rest).accent)
            colorRow("focus background", hex: $focusBackgroundHex, fallback: terminalStyle.basePalette(for: .focus).background)
            colorRow("break background", hex: $restBackgroundHex, fallback: terminalStyle.basePalette(for: .rest).background)
            if hasCustomColors {
                Button("reset all colours", systemImage: "arrow.counterclockwise") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        focusAccentHex = ""
                        restAccentHex = ""
                        focusBackgroundHex = ""
                        restBackgroundHex = ""
                    }
                }
                .foregroundStyle(palette.accent)
            }
        } header: {
            header("colours")
        } footer: {
            Text("Tap a swatch to open the colour wheel. Text adjusts automatically on light backgrounds.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
    }

    private var hasCustomColors: Bool {
        ![focusAccentHex, restAccentHex, focusBackgroundHex, restBackgroundHex].allSatisfy(\.isEmpty)
    }

    /// A colour-wheel picker bound to a stored hex string; empty means "use the style's colour".
    private func colorRow(_ title: String, hex: Binding<String>, fallback: Color) -> some View {
        let color = Binding<Color>(
            get: { Color(hexString: hex.wrappedValue) ?? fallback },
            set: { hex.wrappedValue = $0.hexString }
        )
        return HStack {
            ColorPicker(title, selection: color, supportsOpacity: false)
            if !hex.wrappedValue.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { hex.wrappedValue = "" }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(palette.dim)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset \(title)")
            }
        }
    }

    // MARK: About

    /// e.g. "1.4.0 (6)", read from the app bundle so it always matches the installed build.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(terminalStyle == .cozy ? "$ focus --version" : "PS> (Get-Focus).Version")
                    .foregroundStyle(palette.dim)
                Text("focus \(versionString)")
                    .foregroundStyle(palette.accent)
                    .textSelection(.enabled)
            }
            .font(palette.mono(13, relativeTo: .footnote))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Version \(versionString)")
        } header: {
            header("about")
        }
        .listRowBackground(palette.surface)
    }

    private func header(_ name: String) -> some View {
        Text(terminalStyle == .cozy ? "# \(name)" : "## \(name.capitalized)")
            .font(palette.mono(12, .bold, relativeTo: .caption))
            .foregroundStyle(palette.accent)
    }
}
