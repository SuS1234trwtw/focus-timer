import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.createdAt)
    private var tasks: [TaskItem]

    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("restMinutes") private var restMinutes = 5
    @AppStorage("terminalStyle") private var terminalStyle: TerminalStyle = .cozy
    @AppStorage("focusAccentHex") private var focusAccentHex = ""
    @AppStorage("restAccentHex") private var restAccentHex = ""
    @AppStorage("focusBackgroundHex") private var focusBackgroundHex = ""
    @AppStorage("restBackgroundHex") private var restBackgroundHex = ""

    @State private var chimeCount = 0
    @State private var showSettings = false

    private var appearance: Appearance {
        Appearance(
            style: terminalStyle,
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

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            TerminalOverlay(accent: palette.accent, scanlines: palette.style.hasScanlines)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                    TaskListView(palette: palette, tasks: tasks, activeID: activeTask?.id)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.easeInOut(duration: 1.2), value: engine.mode)
        .animation(.easeInOut(duration: 0.4), value: appearance)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .sensoryFeedback(.success, trigger: chimeCount)
        .sheet(isPresented: $showSettings) { SettingsSheet(palette: palette) }
        .onChange(of: [focusMinutes, restMinutes]) { _, minutes in
            guard !ProcessInfo.processInfo.arguments.contains("-fastTimer") else { return }
            engine.setDurations(PomodoroDurations(focusMinutes: minutes[0], restMinutes: minutes[1]))
        }
        .task { await runClock() }
        .task { await sync.syncNow() }
        #if DEBUG
        .task {
            // `-autostart` starts the timer on launch (used for CI screenshots).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-autostart") { engine.start() }
            if let flag = args.firstIndex(of: "-style"), args.indices.contains(flag + 1),
               let style = TerminalStyle(rawValue: args[flag + 1]) {
                terminalStyle = style
            }
            if args.contains("-openSettings") { showSettings = true }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if let segment = engine.tick() { finish(segment) }
            Task { await sync.syncNow() }
        }
        .onChange(of: engine.isRunning, initial: true) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }

    // MARK: Timer actions

    private func start() {
        engine.start()
        guard let endDate = engine.endDate else { return }
        let mode = engine.mode
        let title = activeTask?.title
        Task {
            await TimerNotifier.requestPermission()
            await TimerNotifier.schedule(at: endDate, mode: mode, taskTitle: title)
        }
    }

    private func pause() {
        engine.pause()
        TimerNotifier.cancel()
    }

    private func reset() {
        engine.reset()
        TimerNotifier.cancel()
    }

    private func switchMode(_ mode: TimerMode) {
        engine.switchMode(to: mode)
        TimerNotifier.cancel()
    }

    private func runClock() async {
        while !Task.isCancelled {
            if let segment = engine.tick() { finish(segment) }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func finish(_ segment: CompletedSegment) {
        // If the app was in the background, the scheduled notification already rang.
        if segment.lateBy < 3 {
            ChimePlayer.shared.play()
            chimeCount += 1
        }
        sync.record(segment, taskID: segment.mode == .focus ? activeTask?.id : nil)
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
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
