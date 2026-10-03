import SwiftUI
import UniformTypeIdentifiers

/// Settings → sound & haptics → one moment: pick a built-in sound, none, or your own file.
struct SoundPickerPage: View {
    let palette: Palette
    let moment: SoundMoment

    @State private var selected: SoundChoice = .none
    @State private var customs: [String] = []
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section {
                ForEach(SoundBoard.builtIns, id: \.self) { name in
                    row(.builtIn(name))
                }
                row(.none)
            } header: {
                SettingsHeader("built-in", palette: palette)
            }
            .listRowBackground(palette.surface)

            Section {
                ForEach(customs, id: \.self) { file in
                    row(.custom(file))
                }
                .onDelete { offsets in
                    for index in offsets { SoundBoard.delete(customs[index]) }
                    reload()
                }
                Button {
                    Feedback.play(.tap)
                    importError = nil
                    importing = true
                } label: {
                    Text("+ your own file")
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if let importError {
                    Text("> \(importError)")
                        .font(palette.mono(12, relativeTo: .caption))
                        .foregroundStyle(Color(hex: 0xE0786A))
                }
            } header: {
                SettingsHeader("your files", palette: palette)
            } footer: {
                SettingsFooter("Any audio file works; it's trimmed to the first 29 seconds so it can ring in notifications too. Swipe to delete.", palette: palette)
            }
            .listRowBackground(palette.surface)
        }
        .settingsFormStyle(palette)
        .navigationTitle(moment.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        let name = try await SoundBoard.importFile(url)
                        customs = SoundBoard.customFiles()
                        choose(.custom(name))
                    } catch {
                        importError = "import failed: \(error.localizedDescription)"
                    }
                }
            case .failure(let error):
                importError = "import failed: \(error.localizedDescription)"
            }
        }
    }

    private func reload() {
        selected = SoundBoard.choice(for: moment)
        customs = SoundBoard.customFiles()
    }

    private func choose(_ choice: SoundChoice) {
        SoundBoard.set(choice, for: moment)
        selected = choice
        SoundBoard.preview(choice)
    }

    private func row(_ choice: SoundChoice) -> some View {
        HStack(spacing: 12) {
            if choice != .none {
                Button {
                    SoundBoard.preview(choice)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.footnote)
                        .foregroundStyle(palette.accent)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("preview \(choice.name)")
            }
            Text(choice.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            if selected == choice {
                Image(systemName: "checkmark")
                    .foregroundStyle(palette.accent)
            }
        }
        .contentShape(.rect)
        .onTapGesture { choose(choice) }
        .accessibilityAddTraits(selected == choice ? .isSelected : [])
    }
}

/// The setup guide's "when a block ends" row: one built-in sound for both focus and break ends.
struct EndSoundMenu: View {
    let palette: Palette

    @State private var current = SoundBoard.choice(for: .focusEnd)

    var body: some View {
        HStack(spacing: 12) {
            Text("when a block ends")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Menu {
                ForEach(SoundBoard.builtIns, id: \.self) { name in
                    Button(name) { pick(.builtIn(name)) }
                }
                Button("none") { pick(.none) }
            } label: {
                HStack(spacing: 4) {
                    Text(current.name)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(palette.accent)
            }
        }
        .font(palette.mono(15, relativeTo: .body))
    }

    private func pick(_ choice: SoundChoice) {
        SoundBoard.set(choice, for: .focusEnd)
        SoundBoard.set(choice, for: .breakEnd)
        current = choice
        SoundBoard.preview(choice)
    }
}
