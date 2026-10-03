import SwiftUI

/// The categories under `config`. `.timer` opens `TimerLengthSheet` instead of a page.
enum SettingsPage: String, Hashable, CaseIterable {
    case timer, appearance, sound, island, account, connections, updates, about
}

/// `config`: a short list of categories; each opens its own page.
struct SettingsSheet: View {
    /// The screen's current palette, so the sheet looks like part of the same terminal.
    let palette: Palette
    /// Opens straight onto this page (e.g. from the update banner).
    var initialPage: SettingsPage? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(SpotifyService.self) private var spotify

    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("restMinutes") private var restMinutes = 5
    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .mono
    @AppStorage(FontChoices.key) private var fontByStyle = ""
    @AppStorage(Feedback.Key.sounds) private var soundsEnabled = true
    @AppStorage(Feedback.Key.haptics) private var hapticsEnabled = true

    @State private var path: [SettingsPage] = []
    @State private var showTimer = false

    private var updates: UpdateChecker { UpdateChecker.shared }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                headerCard
                Section {
                    timerRow
                    row(.appearance, "appearance", "paintpalette", appearancePreview)
                    row(.sound, "sound & haptics", "speaker.wave.2", soundPreview)
                    row(.island, "dynamic island", "capsule", AppModel.shared.live.areActivitiesEnabled ? "on" : "off")
                }
                .listRowBackground(palette.surface)
                Section {
                    row(.account, "account & sync", "person.crop.circle", accountPreview)
                    row(.connections, "connections", "link", connectionsPreview)
                }
                .listRowBackground(palette.surface)
                Section {
                    row(.updates, "updates", "arrow.down.circle", updates.available.map { "\($0.version) (\($0.build))" } ?? "up to date")
                    row(.about, "about", "info.circle", versionString)
                }
                .listRowBackground(palette.surface)
            }
            .settingsFormStyle(palette)
            .navigationTitle(terminalStyle.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .timer: EmptyView() // never pushed; the timer row presents a sheet
                case .appearance: AppearanceSettingsPage(palette: palette)
                case .sound: SoundSettingsPage(palette: palette)
                case .island: IslandSettingsPage(palette: palette)
                case .account: AccountSettingsPage(palette: palette)
                case .connections: ConnectionsSettingsPage(palette: palette)
                case .updates: UpdatesSettingsPage(palette: palette)
                case .about: AboutSettingsPage(palette: palette)
                }
            }
        }
        .sheet(isPresented: $showTimer) { TimerLengthSheet(palette: palette) }
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onAppear {
            guard let initialPage, path.isEmpty else { return }
            if initialPage == .timer { showTimer = true } else { path = [initialPage] }
        }
    }

    // MARK: Header

    /// e.g. "1.4.0 (6)", read from the app bundle so it always matches the installed build.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var headerCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(">_ focus \(versionString)")
                    .font(palette.mono(15, .bold, relativeTo: .body))
                    .foregroundStyle(palette.accent)
                    .textSelection(.enabled)
                Text("by An Le aka アン, 51")
                    .font(palette.mono(12, relativeTo: .caption))
                    .foregroundStyle(palette.dim)
                updateLine
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private var updateLine: some View {
        if let update = updates.available {
            HStack {
                Text("> update available: \(update.version) (\(update.build))")
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 8)
                Button("update") {
                    Feedback.play(.tap)
                    path.append(.updates)
                }
                .buttonStyle(.borderless)
                .font(palette.mono(13, .bold, relativeTo: .footnote))
            }
            .font(palette.mono(12, relativeTo: .caption))
        } else {
            Group {
                if let checked = updates.lastChecked {
                    Text("up to date · checked \(checked.formatted(.relative(presentation: .named)))")
                } else {
                    Text("up to date")
                }
            }
            .font(palette.mono(12, relativeTo: .caption))
            .foregroundStyle(palette.dim)
        }
    }

    // MARK: Rows

    private func rowLabel(_ title: String, _ symbol: String, _ preview: String) -> some View {
        LabeledContent {
            Text(preview)
                .font(palette.mono(13, relativeTo: .footnote))
                .foregroundStyle(palette.dim)
                .lineLimit(1)
        } label: {
            Label(title, systemImage: symbol)
                .foregroundStyle(palette.text)
        }
    }

    private func row(_ page: SettingsPage, _ title: String, _ symbol: String, _ preview: String) -> some View {
        NavigationLink(value: page) { rowLabel(title, symbol, preview) }
    }

    private var timerRow: some View {
        Button {
            Feedback.play(.tap)
            showTimer = true
        } label: {
            rowLabel("timer", "timer", "\(focusMinutes) / \(restMinutes) min")
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var appearancePreview: String {
        "\(terminalStyle.name) · \(FontChoices.font(for: terminalStyle, in: fontByStyle).name)"
    }

    private var soundPreview: String {
        switch (soundsEnabled, hapticsEnabled) {
        case (true, true): "sounds · haptics"
        case (true, false): "sounds"
        case (false, true): "haptics"
        case (false, false): "off"
        }
    }

    private var accountPreview: String {
        let account = AccountService.shared
        return account.isGuest ? "guest" : (account.email ?? "?")
    }

    private var connectionsPreview: String {
        let google = GoogleCalendarService.shared.isConnected
        return "spotify \(spotify.isConnected ? "on" : "off") · google \(google ? "on" : "off")"
    }
}

// MARK: Shared page styling

extension View {
    /// The terminal look every settings `Form` shares.
    func settingsFormStyle(_ palette: Palette) -> some View {
        font(palette.mono(15, relativeTo: .body))
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .scrollContentBackground(.hidden)
            .background(palette.background)
    }
}

/// A section header in the current style's comment format (`// TIMER`, `# timer`, …).
struct SettingsHeader: View {
    let name: String
    let palette: Palette

    init(_ name: String, palette: Palette) {
        self.name = name
        self.palette = palette
    }

    var body: some View {
        Text(palette.style.sectionHeader(name))
            .font(palette.mono(12, .bold, relativeTo: .caption))
            .foregroundStyle(palette.accent)
    }
}

/// A dim footnote under a section.
struct SettingsFooter: View {
    let text: String
    let palette: Palette

    init(_ text: String, palette: Palette) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text)
            .font(palette.mono(11, relativeTo: .caption))
            .foregroundStyle(palette.dim)
    }
}
