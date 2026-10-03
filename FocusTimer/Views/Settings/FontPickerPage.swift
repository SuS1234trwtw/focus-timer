import SwiftUI

/// Settings → appearance → font: every font named in itself; tapping one picks it for the current style.
struct FontPickerPage: View {
    let palette: Palette

    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .mono
    @AppStorage(FontChoices.key) private var fontByStyle = ""
    @Environment(\.dismiss) private var dismiss

    private var current: TerminalFont { FontChoices.font(for: terminalStyle, in: fontByStyle) }

    var body: some View {
        Form {
            if current != terminalStyle.defaultFont {
                Section {
                    Button("use style default", systemImage: "arrow.counterclockwise") {
                        pick(terminalStyle.defaultFont)
                    }
                    .foregroundStyle(palette.accent)
                }
                .listRowBackground(palette.surface)
            }
            Section {
                ForEach(TerminalFont.allCases) { font in
                    row(font)
                }
            } header: {
                SettingsHeader("font", palette: palette)
            } footer: {
                SettingsFooter("each style keeps its own font.", palette: palette)
            }
            .listRowBackground(palette.surface)
        }
        .settingsFormStyle(palette)
        .navigationTitle("font")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pick(_ font: TerminalFont) {
        fontByStyle = FontChoices.setting(font, for: terminalStyle, in: fontByStyle)
        dismiss()
    }

    private func row(_ font: TerminalFont) -> some View {
        let selected = font == current
        return Button {
            pick(font)
        } label: {
            HStack(spacing: 10) {
                Text(font.name)
                    .font(font.font(16, selected ? .bold : .regular, relativeTo: .body))
                    .foregroundStyle(selected ? palette.accent : palette.text)
                    .lineLimit(1)
                if font == terminalStyle.defaultFont {
                    Text("default")
                        .font(palette.mono(11, relativeTo: .caption))
                        .foregroundStyle(palette.dim)
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
        .accessibilityLabel(font == terminalStyle.defaultFont ? "\(font.name), default" : font.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
