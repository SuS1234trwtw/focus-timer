import SwiftUI

/// Settings → appearance: terminal style, font, app icon, and colours from the colour wheel.
struct AppearanceSettingsPage: View {
    let palette: Palette

    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .mono
    @AppStorage("focusAccentHex") private var focusAccentHex = ""
    @AppStorage("restAccentHex") private var restAccentHex = ""
    @AppStorage("focusBackgroundHex") private var focusBackgroundHex = ""
    @AppStorage("restBackgroundHex") private var restBackgroundHex = ""
    @AppStorage(FontChoices.key) private var fontByStyle = ""
    @AppStorage(AppIconManager.followsStyleKey) private var iconFollowsStyle = true

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
        .onChange(of: terminalStyle) { Feedback.play(.tap) }  // RootView switches the app icon
        .onChange(of: iconFollowsStyle) {
            Feedback.play(.tap)
            if iconFollowsStyle { AppIconManager.apply(style: terminalStyle) }
        }
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

    private var fontSection: some View {
        let current = FontChoices.font(for: terminalStyle, in: fontByStyle)
        return Section {
            NavigationLink {
                FontPickerPage(palette: palette)
            } label: {
                LabeledContent {
                    Text(current.name)
                        .font(current.font(15, .regular, relativeTo: .body))
                        .foregroundStyle(palette.dim)
                        .lineLimit(1)
                } label: {
                    Text("font")
                }
            }
            Toggle("app icon follows style", isOn: $iconFollowsStyle)
        } header: {
            SettingsHeader("font", palette: palette)
        } footer: {
            NavigationLink {
                FontsGuidePage(palette: palette)
            } label: {
                Text("curious about fonts? check here")
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(palette.dim)
                    .underline()
            }
            .buttonStyle(.plain)
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
