import ActivityKit
import AuthenticationServices
import SwiftUI
import UserNotifications

/// Decides whether the setup guide opens on launch.
enum OnboardingGate {
    static let key = "onboarding.done"

    /// True only for a brand-new install: the guide was never finished, nothing has been customised
    /// and there are no tasks. (`FontChoices.migrate()` writes an empty font setting on every launch,
    /// so only a non-empty one counts as customised.)
    static func shouldShow(defaults: UserDefaults, taskCount: Int) -> Bool {
        guard !defaults.bool(forKey: key), taskCount == 0 else { return false }
        for customised in ["terminalStyle", "focusMinutes", "restMinutes"] where defaults.object(forKey: customised) != nil {
            return false
        }
        if let fonts = defaults.string(forKey: FontChoices.key), !fonts.isEmpty { return false }
        return true
    }
}

/// The first-run setup guide: style, colour, font, timer, feel, island, sync and extras,
/// drawn live in the palette being picked.
struct OnboardingView: View {
    let onDone: () -> Void

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @AppStorage(OnboardingGate.key) private var done = false
    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("restMinutes") private var restMinutes = 5
    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .mono
    @AppStorage("focusAccentHex") private var focusAccentHex = ""
    @AppStorage("restAccentHex") private var restAccentHex = ""
    @AppStorage("focusBackgroundHex") private var focusBackgroundHex = ""
    @AppStorage("restBackgroundHex") private var restBackgroundHex = ""
    @AppStorage(FontChoices.key) private var fontByStyle = ""
    @AppStorage(Feedback.Key.sounds) private var soundsEnabled = true
    @AppStorage(Feedback.Key.haptics) private var hapticsEnabled = true

    @State private var page = 0
    @State private var wantsSync = false
    @State private var notificationsAllowed: Bool?
    @State private var activitiesEnabled = true

    private var account: AccountService { AccountService.shared }
    private var spotify: SpotifyService { AppModel.shared.spotify }
    private var calendar: GoogleCalendarService { GoogleCalendarService.shared }

    // MARK: Steps

    enum Step: Int, CaseIterable {
        case welcome, style, color, font, timer, feel, island, sync, extras, done

        var label: String {
            switch self {
            case .welcome: "hello"
            case .style: "style"
            case .color: "colour"
            case .font: "font"
            case .timer: "timer"
            case .feel: "feel"
            case .island: "island & alerts"
            case .sync: "backup & sync"
            case .extras: "extras"
            case .done: "done"
            }
        }

        var title: String {
            switch self {
            case .welcome: ">_ focus"
            case .style: "pick a terminal"
            case .color: "pick an accent"
            case .font: "pick a font"
            case .timer: "how long?"
            case .feel: "clicks & buzzes"
            case .island: "stay in the loop"
            case .sync: "keep your tasks safe"
            case .extras: "plug things in"
            case .done: "you're set"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "a pomodoro timer and task list that looks like your terminal."
            case .style: "the whole app follows it: colours, prompt, wording."
            case .color: "the colour for the timer, cursor and buttons while you focus."
            case .font: "every style remembers its own font."
            case .timer: "one focus block, then a break. change it any time."
            case .feel: "a key click for every action, a tick every second."
            case .island: "the timer lives on your lock screen and in the Dynamic Island."
            case .sync: "optional. you can set this up later in config."
            case .extras: "optional. both can be linked later in config."
            case .done: "everything here can be changed later in config."
            }
        }

        /// Optional pages read "skip" instead of "next" until something is chosen.
        var isOptional: Bool { self == .sync || self == .extras }
    }

    private let steps = Step.allCases
    private var step: Step { Step(rawValue: page) ?? .welcome }
    private var isLast: Bool { page == steps.count - 1 }

    // MARK: Palette

    private var appearance: Appearance {
        Appearance(
            style: terminalStyle,
            font: FontChoices.font(for: terminalStyle, in: fontByStyle),
            focusAccent: Color(hexString: focusAccentHex),
            restAccent: Color(hexString: restAccentHex),
            focusBackground: Color(hexString: focusBackgroundHex),
            restBackground: Color(hexString: restBackgroundHex)
        )
    }

    private var palette: Palette { appearance.palette(for: .focus) }

    // MARK: Body

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                TabView(selection: $page) {
                    ForEach(steps, id: \.rawValue) { step in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                pageHeader(step)
                                content(for: step)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                            .frame(maxWidth: 560, alignment: .leading)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .tag(step.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                bottomBar
            }
        }
        .font(palette.mono(15, relativeTo: .body))
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.4), value: appearance)
        .animation(.easeInOut(duration: 0.25), value: page)
        .onChange(of: terminalStyle) { Feedback.play(.tap) }
        .onChange(of: [focusMinutes, restMinutes]) { Feedback.play(.tap) }
        .onChange(of: fontByStyle) { Feedback.play(.tap) }
        .onChange(of: [focusAccentHex, restAccentHex]) { Feedback.play(.tap) }
        .onChange(of: [soundsEnabled, hapticsEnabled]) { Feedback.play(.tap) }
        .task {
            activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            notificationsAllowed = await Self.notificationStatus()
            await account.refresh()
            if !account.isGuest || account.pendingEmail != nil { wantsSync = true }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(format: "%02d/%02d", page + 1, steps.count))
                    .font(palette.mono(12, .bold, relativeTo: .caption))
                    .foregroundStyle(palette.dim)
                    .monospacedDigit()
                    .accessibilityLabel("Step \(page + 1) of \(steps.count)")
                Spacer()
                if !isLast {
                    Button {
                        Feedback.play(.tap)
                        finish()
                    } label: {
                        Text(palette.style.label("skip setup"))
                            .font(palette.mono(13, relativeTo: .footnote))
                            .tracking(palette.style.labelTracking)
                            .foregroundStyle(palette.dim)
                            .frame(minHeight: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.border)
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: proxy.size.width * CGFloat(page + 1) / CGFloat(steps.count))
                }
            }
            .frame(height: 3)
            .clipShape(.rect(cornerRadius: palette.style.radius(1.5)))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button {
                    Feedback.play(.tap)
                    page -= 1
                } label: {
                    Text(palette.style.label("back"))
                        .font(palette.mono(15, relativeTo: .body))
                        .tracking(palette.style.labelTracking)
                        .foregroundStyle(palette.text)
                        .frame(minWidth: 88, minHeight: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: palette.style.radius(8))
                                .strokeBorder(palette.border, lineWidth: 1)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            Button {
                Feedback.play(.tap)
                if isLast { finish() } else { page += 1 }
            } label: {
                Text(palette.style.label(nextTitle))
                    .font(palette.mono(15, .bold, relativeTo: .body))
                    .tracking(palette.style.labelTracking)
                    .foregroundStyle(palette.background)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.accent, in: .rect(cornerRadius: palette.style.radius(8)))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var nextTitle: String {
        if isLast { return "start" }
        if step == .welcome { return "let's go" }
        switch step {
        case .sync: return wantsSync && account.isGuest ? "skip for now" : "next"
        case .extras: return spotify.isConnected || calendar.isConnected ? "next" : "skip"
        default: return "next"
        }
    }

    private func finish() {
        done = true
        onDone()
    }

    private func pageHeader(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(palette.style.sectionHeader(step.label))
                .font(palette.mono(12, .bold, relativeTo: .caption))
                .foregroundStyle(palette.accent)
            Text(step.title)
                .font(palette.mono(step == .welcome ? 40 : 26, .bold, relativeTo: .title))
                .foregroundStyle(step == .welcome ? palette.accent : palette.text)
            Text(step.subtitle)
                .font(palette.mono(14, relativeTo: .callout))
                .foregroundStyle(palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .welcome: welcomePage
        case .style: stylePage
        case .color: colorPage
        case .font: fontPage
        case .timer: timerPage
        case .feel: feelPage
        case .island: islandPage
        case .sync: syncPage
        case .extras: extrasPage
        case .done: donePage
        }
    }

    /// A bordered box in the current palette.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: palette.style.radius(10)))
            .overlay {
                RoundedRectangle(cornerRadius: palette.style.radius(10))
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }

    /// The current prompt and a command, as the header shows it.
    private var promptLine: some View {
        HStack(spacing: 0) {
            if let host = terminalStyle.promptHost { Text(host).foregroundStyle(terminalStyle.promptHostColor) }
            Text(terminalStyle.promptPath).foregroundStyle(palette.accent)
            Text(terminalStyle.promptSymbol).foregroundStyle(palette.dim)
            Text(terminalStyle.command).foregroundStyle(palette.text)
            Text(terminalStyle.cursor).foregroundStyle(palette.accent)
        }
        .font(palette.mono(14, .bold, relativeTo: .callout))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    // MARK: 1 Welcome

    private var welcomePage: some View {
        card {
            promptLine
            Text(String(format: "%02d:00", focusMinutes))
                .font(palette.mono(56, .bold, relativeTo: .largeTitle))
                .foregroundStyle(palette.accent)
                .monospacedDigit()
            Text("start a block, pick a task, take the break. that's it.")
                .foregroundStyle(palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 2 Style

    private var stylePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(TerminalStyle.allCases) { style in
                    styleCard(style)
                }
            }
            card { promptLine }
        }
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

    // MARK: 3 Colour

    private struct AccentPreset: Hashable {
        let name: String
        let hex: String
    }

    /// Bright enough to read on any of the dark terminal backgrounds.
    private static let accentPresets = [
        AccentPreset(name: "amber", hex: "F5A05A"),
        AccentPreset(name: "green", hex: "5AF78E"),
        AccentPreset(name: "cyan", hex: "57C7FF"),
        AccentPreset(name: "pink", hex: "FF6AC1"),
        AccentPreset(name: "violet", hex: "C792EA"),
        AccentPreset(name: "yellow", hex: "F3F99D")
    ]

    private var colorPage: some View {
        let defaultAccent = terminalStyle.basePalette(for: .focus).accent
        let isCustom = !focusAccentHex.isEmpty
            && !Self.accentPresets.contains { $0.hex.caseInsensitiveCompare(focusAccentHex) == .orderedSame }
        return VStack(alignment: .leading, spacing: 14) {
            card {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                    swatch("default", color: defaultAccent, selected: focusAccentHex.isEmpty) { setAccent("") }
                    ForEach(Self.accentPresets, id: \.self) { preset in
                        swatch(preset.name, color: Color(hexString: preset.hex) ?? defaultAccent,
                               selected: preset.hex.caseInsensitiveCompare(focusAccentHex) == .orderedSame) {
                            setAccent(preset.hex)
                        }
                    }
                    customSwatch(selected: isCustom)
                }
            }
            card {
                promptLine
                Text(String(format: "%02d:00", focusMinutes))
                    .font(palette.mono(40, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
            }
            Text("breaks keep the style's own colour, so you can tell them apart.")
                .font(palette.mono(12, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
    }

    private func setAccent(_ hex: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            focusAccentHex = hex
            restAccentHex = ""
        }
    }

    private func swatch(_ name: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle().strokeBorder(selected ? palette.text : palette.border, lineWidth: selected ? 2 : 1)
                            .padding(-4)
                    }
                    .padding(4)
                Text(name)
                    .font(palette.mono(11, selected ? .bold : .regular, relativeTo: .caption))
                    .foregroundStyle(selected ? palette.text : palette.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) accent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func customSwatch(selected: Bool) -> some View {
        let color = Binding<Color>(
            get: { Color(hexString: focusAccentHex) ?? palette.accent },
            set: { newValue in
                focusAccentHex = newValue.hexString
                restAccentHex = ""
            }
        )
        return VStack(spacing: 6) {
            ColorPicker("custom accent", selection: color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44, height: 44)
            Text("custom")
                .font(palette.mono(11, selected ? .bold : .regular, relativeTo: .caption))
                .foregroundStyle(selected ? palette.text : palette.dim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 4 Font

    private var orderedFonts: [TerminalFont] {
        let first = terminalStyle.defaultFont
        return [first] + TerminalFont.allCases.filter { $0 != first }
    }

    private var fontPage: some View {
        let current = FontChoices.font(for: terminalStyle, in: fontByStyle)
        return card {
            ForEach(Array(orderedFonts.enumerated()), id: \.element) { index, font in
                if index > 0 {
                    Rectangle().fill(palette.border).frame(height: 1)
                }
                fontRow(font, selected: font == current, isDefault: index == 0)
            }
        }
    }

    private func fontRow(_ font: TerminalFont, selected: Bool, isDefault: Bool) -> some View {
        Button {
            fontByStyle = FontChoices.setting(font, for: terminalStyle, in: fontByStyle)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isDefault ? "\(font.name) (default)" : font.name)
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
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDefault ? "\(font.name), default" : font.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 5 Timer

    private struct TimerPreset: Hashable {
        let focus: Int
        let rest: Int
    }

    private static let timerPresets = [TimerPreset(focus: 25, rest: 5), TimerPreset(focus: 50, rest: 10),
                                       TimerPreset(focus: 15, rest: 3), TimerPreset(focus: 90, rest: 20)]

    private var timerPage: some View {
        card {
            Stepper(value: $focusMinutes, in: PomodoroDurations.focusRange) {
                LabeledContent("focus", value: "\(focusMinutes) min")
            }
            Rectangle().fill(palette.border).frame(height: 1)
            Stepper(value: $restMinutes, in: PomodoroDurations.restRange) {
                LabeledContent("break", value: "\(restMinutes) min")
            }
            HStack(spacing: 8) {
                ForEach(Self.timerPresets, id: \.self) { preset in
                    let selected = preset.focus == focusMinutes && preset.rest == restMinutes
                    Button {
                        focusMinutes = preset.focus
                        restMinutes = preset.rest
                    } label: {
                        Text("\(preset.focus)/\(preset.rest)")
                            .font(palette.mono(13, selected ? .bold : .regular, relativeTo: .footnote))
                            .foregroundStyle(selected ? palette.background : palette.text)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(selected ? palette.accent : palette.border.opacity(0.5),
                                        in: .rect(cornerRadius: palette.style.radius(6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.focus) minute focus, \(preset.rest) minute break")
                }
            }
        }
    }

    // MARK: 6 Feel

    private var feelPage: some View {
        card {
            Toggle("sounds", isOn: $soundsEnabled)
            Toggle("haptics", isOn: $hapticsEnabled)
            HapticStrengthPicker(palette: palette)
            Text("sounds follow the silent switch; the end-of-block chime always rings.")
                .font(palette.mono(12, relativeTo: .caption))
                .foregroundStyle(palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 7 Island & alerts

    private var islandPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                Label("while a block is running or paused, the Dynamic Island and lock screen show the countdown, your task and a pause button.", systemImage: "capsule.fill")
                    .fixedSize(horizontal: false, vertical: true)
                Label("when a block ends, a notification rings the chime even if the app is closed.", systemImage: "bell")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(palette.mono(14, relativeTo: .callout))

            card {
                switch notificationsAllowed {
                case true?:
                    Label("notifications are on", systemImage: "checkmark.circle")
                        .foregroundStyle(palette.accent)
                case false?:
                    Text("notifications are off. turn them on in iOS settings → focus → notifications to hear the end of a block.")
                        .foregroundStyle(Color(hex: 0xE0786A))
                        .fixedSize(horizontal: false, vertical: true)
                case nil:
                    Button {
                        Feedback.play(.tap)
                        Task {
                            await TimerNotifier.requestPermission()
                            notificationsAllowed = await Self.notificationStatus()
                        }
                    } label: {
                        Label("allow notifications", systemImage: "bell.badge")
                            .font(palette.mono(15, .bold, relativeTo: .body))
                            .foregroundStyle(palette.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if !activitiesEnabled {
                    Text("live activities are off for focus, so the island stays empty. turn them on in iOS settings → focus → live activities.")
                        .font(palette.mono(13, relativeTo: .footnote))
                        .foregroundStyle(Color(hex: 0xE0786A))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Nil while the user hasn't been asked yet.
    nonisolated private static func notificationStatus() async -> Bool? {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return nil
        }
    }

    // MARK: 8 Backup & sync

    private var syncPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !account.isAvailable {
                card {
                    Text("sync isn't set up in this build, so everything stays on this iPhone.")
                        .foregroundStyle(palette.dim)
                }
            } else if !account.isGuest && !account.needsPassword {
                card {
                    Label("signed in as \(account.email ?? "?")", systemImage: "checkmark.circle")
                        .foregroundStyle(palette.accent)
                    Text("your tasks sync across every iPhone and iPad running Focus.")
                        .font(palette.mono(13, relativeTo: .footnote))
                        .foregroundStyle(palette.dim)
                }
            } else {
                choice(
                    title: "keep it on this iPhone",
                    detail: "no account needed. tasks stay on this device. the default.",
                    icon: "iphone",
                    selected: !wantsSync
                ) { wantsSync = false }
                choice(
                    title: "back up & sync across devices",
                    detail: "make an account (or log in) and your tasks follow you to every iPhone and iPad running Focus.",
                    icon: "arrow.triangle.2.circlepath",
                    selected: wantsSync
                ) { wantsSync = true }
                if wantsSync {
                    card { AccountForm(palette: palette) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: wantsSync)
    }

    private func choice(title: String, detail: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.play(.tap)
            action()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? palette.accent : palette.dim)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(palette.mono(16, .bold, relativeTo: .body))
                        .foregroundStyle(selected ? palette.accent : palette.text)
                    Text(detail)
                        .font(palette.mono(13, relativeTo: .footnote))
                        .foregroundStyle(palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? palette.accent : palette.border)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: palette.style.radius(10)))
            .overlay {
                RoundedRectangle(cornerRadius: palette.style.radius(10))
                    .strokeBorder(selected ? palette.accent : palette.border, lineWidth: selected ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 9 Extras

    private var extrasPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                Text("spotify")
                    .font(palette.mono(16, .bold, relativeTo: .body))
                Text("show the song under the timer and in the Dynamic Island.")
                    .font(palette.mono(13, relativeTo: .footnote))
                    .foregroundStyle(palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if !spotify.isConfigured {
                    Text("not set up in this build.")
                        .foregroundStyle(palette.dim)
                } else if spotify.isConnected {
                    Label("linked", systemImage: "checkmark.circle")
                        .foregroundStyle(palette.accent)
                } else {
                    connectButton(.spotify)
                }
                if let message = spotify.message {
                    errorLine(message)
                }
            }
            card {
                Text("google calendar")
                    .font(palette.mono(16, .bold, relativeTo: .body))
                Text("log every finished focus block as an event in a \"Focus\" calendar.")
                    .font(palette.mono(13, relativeTo: .footnote))
                    .foregroundStyle(palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if !calendar.isConfigured {
                    Text("not set up in this build.")
                        .foregroundStyle(palette.dim)
                } else if calendar.isConnected {
                    Label("linked", systemImage: "checkmark.circle")
                        .foregroundStyle(palette.accent)
                } else {
                    connectButton(.calendar)
                }
                if let message = calendar.message {
                    errorLine(message)
                }
            }
        }
    }

    private enum Link { case spotify, calendar }

    private func connectButton(_ link: Link) -> some View {
        Button {
            Feedback.play(.tap)
            Task {
                switch link {
                case .spotify: await spotify.connect(using: webAuthenticationSession)
                case .calendar: await calendar.connect(using: webAuthenticationSession)
                }
            }
        } label: {
            Label(link == .spotify ? "connect spotify" : "connect google calendar",
                  systemImage: link == .spotify ? "music.note" : "calendar")
                .font(palette.mono(15, .bold, relativeTo: .body))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func errorLine(_ text: String) -> some View {
        Text(text)
            .font(palette.mono(11, relativeTo: .caption))
            .foregroundStyle(Color(hex: 0xE0786A))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 10 Done

    private var donePage: some View {
        card {
            promptLine
            summaryRow("style", terminalStyle.name)
            summaryRow("font", FontChoices.font(for: terminalStyle, in: fontByStyle).name)
            summaryRow("timer", "\(focusMinutes) min focus / \(restMinutes) min break")
            summaryRow("account", account.isGuest ? "guest (this iPhone)" : (account.email ?? "signed in"))
            Text("tap start, then add your first task.")
                .foregroundStyle(palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(key):")
                .foregroundStyle(palette.dim)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(palette.mono(14, relativeTo: .callout))
    }
}

#Preview {
    OnboardingView(onDone: {})
}
