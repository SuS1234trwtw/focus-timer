import SwiftUI

/// Settings → appearance: terminal style, font, and colours from the colour wheel.
struct AppearanceSettingsPage: View {
    let palette: Palette

    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .mono
    @AppStorage("focusAccentHex") private var focusAccentHex = ""
    @AppStorage("restAccentHex") private var restAccentHex = ""
    @AppStorage("focusBackgroundHex") private var focusBackgroundHex = ""
    @AppStorage("restBackgroundHex") private var restBackgroundHex = ""
    @AppStorage(FontChoices.key) private var fontByStyle = ""

    var body: some View {
        Form {
            styleSection
            fontSection
            colorSection
        }
        .settingsFormStyle(palette)
        .navigationTitle("appearance")
        .navigationBarTitleDisplayMode(.inline)
        // A soft key click for every change made here.
        .onChange(of: terminalStyle) { Feedback.play(.tap) }
        .onChange(of: fontByStyle) { Feedback.play(.tap) }
        .onChange(of: [focusAccentHex, restAccentHex, focusBackgroundHex, restBackgroundHex]) { Feedback.play(.tap) }
    }

    // MARK: Style

    private var styleSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(TerminalStyle.allCases) { style in
                    styleCard(style)
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            SettingsHeader("style", palette: palette)
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
                    if let host = style.promptHost { Text(host).foregroundStyle(style.promptHostColor) }
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
            .background(preview.background, in: .rect(cornerRadius: palette.style.radius(8)))
            .overlay {
                RoundedRectangle(cornerRadius: palette.style.radius(8))
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
        Binding(
            get: { FontChoices.font(for: terminalStyle, in: fontByStyle) },
            set: { fontByStyle = FontChoices.setting($0, for: terminalStyle, in: fontByStyle) }
        )
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
            SettingsHeader("font", palette: palette)
        } footer: {
            SettingsFooter("Each style keeps its own font. Switch style to set the other one.", palette: palette)
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
                    Text("\(terminalStyle.promptHost ?? "")\(terminalStyle.promptPath)\(terminalStyle.promptSymbol)25:00 0Oo1lI")
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
            SettingsHeader("colours", palette: palette)
        } footer: {
            SettingsFooter("Tap a swatch to open the colour wheel. Text adjusts automatically on light backgrounds.", palette: palette)
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
}
