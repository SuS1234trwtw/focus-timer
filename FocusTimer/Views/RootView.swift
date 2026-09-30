import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.createdAt)
    private var tasks: [TaskItem]

    @AppStorage("timerFont") private var timerFont: TimerFont = .carved
    @AppStorage("chimeEnabled") private var chimeEnabled = true

    @State private var reelPosition: Int?
    @State private var showTasks = false
    @State private var showSettings = false
    @State private var burstCount = 0
    @State private var chimeCount = 0

    private static let reelValues = Array(PomodoroEngine.minuteRange.reversed())

    /// Overtime previews the next mode, so a finished focus block flips to the light break palette.
    private var shownMode: TimerMode { engine.isOvertime ? engine.mode.next : engine.mode }
    private var palette: Palette { Theme.palette(for: shownMode) }

    private var activeTask: TaskItem? {
        tasks.filter { $0.isActive && !$0.isDone }.max { $0.updatedAt < $1.updatedAt }
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            GrainOverlay().ignoresSafeArea()

            NumeralReel(
                values: Self.reelValues,
                position: $reelPosition,
                font: timerFont,
                palette: palette,
                litValue: engine.isRunning ? engine.displayMinutes : nil,
                locked: engine.isRunning || engine.isOvertime
            )
            .ignoresSafeArea()
            .opacity(engine.isOvertime ? 0 : 1)
            .contentShape(.rect)
            .onTapGesture(perform: primaryAction)
            .onLongPressGesture(minimumDuration: 0.6, perform: reset)
            .accessibilityAction(named: engine.isRunning ? "Pause" : "Start", primaryAction)
            .accessibilityAction(named: "Reset", reset)

            if engine.isOvertime {
                overtimeGlyph
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            StartBurst(trigger: burstCount, color: palette.numeralLit)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                readout
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .animation(.easeInOut(duration: 0.9), value: shownMode)
        .animation(.smooth(duration: 0.5), value: engine.isOvertime)
        .preferredColorScheme(shownMode == .rest ? .light : .dark)
        .tint(palette.ink)
        .sensoryFeedback(.success, trigger: chimeCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: engine.isRunning)
        .sheet(isPresented: $showTasks) { TasksSheet().tint(palette.ink) }
        .sheet(isPresented: $showSettings) { SettingsSheet().tint(palette.ink) }
        .task { await runClock() }
        .task { await sync.syncNow() }
        .onAppear {
            reelPosition = engine.displayMinutes
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-autostart") { engine.start(); burstCount += 1 }
            if args.contains("-openSettings") { showSettings = true }
            if args.contains("-openTasks") { showTasks = true }
            #endif
        }
        .onChange(of: reelPosition) { _, value in
            // User scrolled the reel: that's the new block length (resets a paused block).
            guard let value, !engine.isRunning, !engine.isOvertime, value != engine.displayMinutes else { return }
            engine.setMinutes(value)
            TimerNotifier.cancel()
        }
        .onChange(of: engine.displayMinutes) { _, value in
            // Timer ticked past a minute, or the mode changed: roll the reel to follow.
            guard reelPosition != value else { return }
            withAnimation(.smooth(duration: 0.6)) { reelPosition = value }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if let segment = engine.tick() { finish(segment) }
            Task { await sync.syncNow() }
        }
        .onChange(of: engine.isRunning, initial: true) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            iconButton("checklist", label: "Tasks") { showTasks = true }
            Spacer()
            iconButton("slider.horizontal.3", label: "Settings") { showSettings = true }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var readout: some View {
        VStack(spacing: 4) {
            Group {
                if let finishedAt = engine.finishedAt {
                    TimelineView(.animation) { context in
                        Text("+" + max(0, context.date.timeIntervalSince(finishedAt)).stopwatchString)
                    }
                } else {
                    Text(engine.remaining.clockString)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.25), value: engine.remaining.clockString)
                }
            }
            .font(Theme.readout(26))
            .foregroundStyle(palette.ink)

            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private var overtimeGlyph: some View {
        GeometryReader { proxy in
            NumeralFace(text: "+", font: timerFont, lit: true, palette: palette, height: proxy.size.height * 0.3)
                .frame(width: proxy.size.width * 0.5, height: proxy.size.height * 0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(.rect)
        .onTapGesture(perform: primaryAction)
        .accessibilityLabel("Time's up")
        .accessibilityAddTraits(.isButton)
    }

    private var caption: String {
        if engine.isOvertime {
            return engine.mode == .focus ? "time's up · tap for a break" : "break's over · tap to focus"
        }
        if engine.isRunning {
            if engine.mode == .focus, let title = activeTask?.title { return title }
            return engine.mode == .focus ? "focus" : "break"
        }
        if engine.isInProgress { return "paused · hold to reset" }
        let done = engine.completedFocusCount
        return "\(engine.mode.label) · tap to start" + (done > 0 ? " · \(done) done" : "")
    }

    // MARK: Actions

    private func primaryAction() {
        if engine.isOvertime {
            engine.advance()
            TimerNotifier.cancel()
        } else if engine.isRunning {
            engine.pause()
            TimerNotifier.cancel()
        } else {
            start()
        }
    }

    private func start() {
        engine.start()
        burstCount += 1
        guard let endDate = engine.endDate else { return }
        let mode = engine.mode
        let title = activeTask?.title
        let sound = chimeEnabled
        Task {
            await TimerNotifier.requestPermission()
            await TimerNotifier.schedule(at: endDate, mode: mode, taskTitle: title, sound: sound)
        }
    }

    private func reset() {
        guard !engine.isOvertime else { return }
        engine.reset()
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
            if chimeEnabled { ChimePlayer.shared.play() }
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
    return RootView()
        .environment(PomodoroEngine(defaults: nil))
        .environment(SyncCoordinator(context: container.mainContext, service: nil))
        .modelContainer(container)
}
