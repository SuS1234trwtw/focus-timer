import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SpotifyService.self) private var spotify
    @Environment(\.scenePhase) private var scenePhase

    private let model = AppModel.shared

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.createdAt)
    private var tasks: [TaskItem]

    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("restMinutes") private var restMinutes = 5
    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .mono
    @AppStorage("focusAccentHex") private var focusAccentHex = ""
    @AppStorage("restAccentHex") private var restAccentHex = ""
    @AppStorage("focusBackgroundHex") private var focusBackgroundHex = ""
    @AppStorage("restBackgroundHex") private var restBackgroundHex = ""
    @AppStorage(FontChoices.key) private var fontByStyle = ""
    @AppStorage("spotifyInIsland") private var spotifyInIsland = true

    @State private var showSettings = false
    @AppStorage(OnboardingGate.key) private var onboardingDone = false
    /// The setup guide: new installs, or "run setup again" in Settings.
    @State private var showOnboarding = false
    /// The boot screen on each launch (off in Settings, or for CI screenshots).
    @State private var showBoot = UserDefaults.standard.object(forKey: BootView.enabledKey) as? Bool ?? true

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

    private var palette: Palette { appearance.palette(for: engine.mode) }

    private var activeTask: TaskItem? {
        tasks.filter { $0.isActive && !$0.isDone }.max { $0.updatedAt < $1.updatedAt }
    }

    /// Everything the Live Activity and widgets show that isn't timer state.
    private struct LiveKey: Equatable {
        let palette: Palette
        let taskID: UUID?
        let taskTitle: String?
        let trackLine: String?
        let showTrack: Bool
    }

    private var liveKey: LiveKey {
        LiveKey(palette: palette, taskID: activeTask?.id, taskTitle: activeTask?.title,
                trackLine: spotify.track?.line, showTrack: spotifyInIsland)
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            TerminalOverlay(accent: palette.accent, scanlines: palette.style.hasScanlines, glow: !palette.style.isFlat)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if UpdateChecker.shared.showsBanner, let update = UpdateChecker.shared.available {
                        updateBanner(update)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    HeaderView(
                        palette: palette,
                        mode: engine.mode,
                        sessionsToday: engine.completedFocusCount,
                        syncStatus: sync.status,
                        onSettings: { showSettings = true }
                    )
                    TimerView(
                        palette: palette,
                        activeTaskTitle: activeTask?.title,
                        onStart: start,
                        onPause: pause,
                        onReset: reset,
                        onSwitch: switchMode
                    )
                    if spotify.isConnected {
                        NowPlayingView(palette: palette)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    TaskListView(palette: palette, tasks: tasks, activeID: activeTask?.id)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay {
            if showOnboarding {
                OnboardingView { withAnimation(.easeOut(duration: 0.35)) { showOnboarding = false } }
                    .transition(.opacity)
            }
        }
        .overlay {
            if showBoot && !Self.isScreenshotRun {
                BootView(palette: palette) { showBoot = false }
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: engine.mode)
        .animation(.easeInOut(duration: 0.4), value: appearance)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .sheet(isPresented: $showSettings) { SettingsSheet(palette: palette) }
        .onChange(of: [focusMinutes, restMinutes]) { _, minutes in
            guard !ProcessInfo.processInfo.arguments.contains("-fastTimer") else { return }
            engine.setDurations(PomodoroDurations(focusMinutes: minutes[0], restMinutes: minutes[1]))
        }
        .onAppear {
            guard !Self.isScreenshotRun else { return }
            if OnboardingGate.shouldShow(defaults: .standard, taskCount: tasks.count) {
                showOnboarding = true
            } else if !onboardingDone {
                // Someone already using the app: don't walk them through setup after updating.
                onboardingDone = true
            }
        }
        .onChange(of: onboardingDone) { _, done in
            // Settings → "run setup again" clears the flag.
            guard !done else { return }
            showSettings = false
            withAnimation(.easeOut(duration: 0.35)) { showOnboarding = true }
        }
        .onOpenURL { url in
            // The website's "email confirmed" page sends people back here to finish creating the account.
            guard url.scheme == "focustimer", url.host == AccountService.confirmedDeepLinkHost else { return }
            Task { await AccountService.shared.refresh() }
        }
        .task { await runClock() }
        .task { await sync.syncNow() }
        .task(id: spotify.isConnected && scenePhase == .active) {
            // Now-playing refreshes only while the app is on screen; iOS gives no background polling.
            guard spotify.isConnected, scenePhase == .active else { return }
            await spotify.pollWhileActive()
        }
        .onChange(of: liveKey, initial: true) { _, key in
            model.currentTask = activeTask.map { ($0.id, $0.title) }
            model.showTrackInIsland = key.showTrack
            model.liveLook = LiveLook(
                style: key.palette.style.rawValue,
                prompt: (key.palette.style.promptHost ?? "") + key.palette.style.promptPath + key.palette.style.promptSymbol
                    .trimmingCharacters(in: .whitespaces),
                accentHex: key.palette.accent.hexString,
                backgroundHex: key.palette.background.hexString,
                textHex: key.palette.text.hexString,
                dimHex: key.palette.dim.hexString
            )
            model.refreshLiveActivity()
        }
        #if DEBUG
        .task {
            // `-autostart` starts the timer on launch (used for CI screenshots).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-autostart") { model.start() }
            if let flag = args.firstIndex(of: "-style"), args.indices.contains(flag + 1),
               let style = TerminalStyle(rawValue: args[flag + 1]) {
                terminalStyle = style
            }
            if args.contains("-openSettings") { showSettings = true }
        }
        #endif
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                // On screen: create or renew the Live Activity if a block is in use (only allowed now).
                model.isAppActive = true
                if let segment = engine.tick() { model.finish(segment) }
                model.refreshLiveActivity()
                Task { await sync.syncNow() }
                // Back from confirming the account email in the browser: finish the sign-up.
                if AccountService.shared.pendingEmail != nil { Task { await AccountService.shared.refresh() } }
            case .inactive, .background:
                model.isAppActive = false
                model.refreshLiveActivity()
            @unknown default:
                break
            }
        }
        .onChange(of: engine.isRunning, initial: true) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }

    /// CI screenshot runs seed demo data and must land on the timer, not the boot screen.
    private static var isScreenshotRun: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-seedDemo") || args.contains("-autostart")
    }

    // MARK: Update banner

    /// One terminal line saying a newer build is out; tap opens Settings, `[x]` hides it for this build.
    private func updateBanner(_ update: UpdateChecker.Update) -> some View {
        HStack(spacing: 8) {
            Button {
                Feedback.play(.tap)
                showSettings = true
            } label: {
                Text("> update available: focus \(update.version) (\(update.build))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Update available: Focus \(update.version), build \(update.build). Opens settings.")
            Button {
                Feedback.play(.tap)
                withAnimation(.easeInOut(duration: 0.25)) { UpdateChecker.shared.dismissBanner() }
            } label: {
                Text("[x]")
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update notice")
        }
        .font(palette.mono(13, relativeTo: .footnote))
        .foregroundStyle(palette.accent)
    }

    // MARK: Timer actions

    private func start() { model.start() }
    private func pause() { model.pause() }
    private func reset() { model.reset() }
    private func switchMode(_ mode: TimerMode) { model.switchMode(mode) }

    private func runClock() async {
        var lastSecond: Int?
        while !Task.isCancelled {
            if let segment = engine.tick() { model.finish(segment) }
            // One tick per whole second while running; a firmer one as each minute rolls over.
            if engine.isRunning {
                let second = Int(engine.remaining.rounded(.up))
                if let lastSecond, second != lastSecond, second > 0 {
                    Feedback.play(second % 60 == 0 ? .minute : .tick)
                }
                lastSecond = second
            } else {
                lastSecond = nil
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: TaskItem.self, FocusSessionRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(TaskItem(title: "write the sync layer", isActive: true))
    container.mainContext.insert(TaskItem(title: "review PR", isDone: true))
    container.mainContext.insert(TaskItem(title: "inbox zero"))
    return RootView()
        .environment(PomodoroEngine(durations: .standard, defaults: nil))
        .environment(SyncCoordinator(context: container.mainContext, service: nil))
        .environment(SpotifyService())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
