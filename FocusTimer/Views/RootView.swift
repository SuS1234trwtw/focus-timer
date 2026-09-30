import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// User order: lowest sortIndex first; new tasks go on top.
    @Query(
        filter: #Predicate<TaskItem> { $0.deletedAt == nil },
        sort: [SortDescriptor(\TaskItem.sortIndex), SortDescriptor(\TaskItem.createdAt, order: .reverse)]
    )
    private var tasks: [TaskItem]

    @AppStorage("timerFont") private var timerFont: TimerFont = .carved
    @AppStorage("chimeEnabled") private var chimeEnabled = true
    @AppStorage("tickHaptics") private var tickHaptics = true

    @State private var reelPosition: Int?
    @State private var showTasks = false
    @State private var showSettings = false
    @State private var burstCount = 0
    @State private var chimeCount = 0
    @State private var popCount = 0
    @State private var resetCount = 0
    @State private var taskDoneCount = 0
    @State private var pressed = false

    private static let reelValues = Array(PomodoroEngine.minuteRange.reversed())

    /// Overtime previews the next mode, so a finished focus block flips to the light break palette.
    private var shownMode: TimerMode { engine.isOvertime ? engine.mode.next : engine.mode }
    private var palette: Palette { Theme.palette(for: shownMode) }

    /// The task shown under the timer: the first open one in the user's order.
    private var currentTask: TaskItem? { tasks.first { !$0.isDone } }
    private var openCount: Int { tasks.filter { !$0.isDone }.count }

    /// Whole seconds left while running (drives the tick haptic); -1 otherwise.
    private var tickSecond: Int { engine.isRunning ? Int(engine.remaining.rounded(.up)) : -1 }

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
            // Press in on touch-down; spring back with a little bounce on release.
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .animation(pressed ? .spring(response: 0.18, dampingFraction: 0.9) : .spring(response: 0.42, dampingFraction: 0.5), value: pressed)
            // A quick pop when a block starts or pauses.
            .keyframeAnimator(initialValue: 1.0, trigger: popCount) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.05, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy(duration: 0.5, extraBounce: 0.15))
                }
            }
            .contentShape(.rect)
            .onTapGesture(perform: primaryAction)
            .onLongPressGesture(minimumDuration: 0.6, perform: reset, onPressingChanged: { pressed = $0 })
            .accessibilityAction(named: engine.isRunning ? "Pause" : "Start", primaryAction)
            .accessibilityAction(named: "Reset", reset)

            if engine.isOvertime {
                overtimeGlyph
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity)
                            .animation(.timingCurve(0.34, 1.36, 0.64, 1, duration: 0.5)),
                        removal: .opacity.animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15))
                    ))
            }

            StartBurst(trigger: burstCount, color: palette.numeralLit)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                topBar
                Spacer()
                readout
                taskCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.9), value: shownMode)
        .animation(.smooth(duration: 0.5), value: engine.isOvertime)
        .preferredColorScheme(shownMode == .rest ? .light : .dark)
        .tint(palette.ink)
        .sensoryFeedback(.success, trigger: chimeCount)
        .sensoryFeedback(.success, trigger: taskDoneCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: engine.isRunning)
        .sensoryFeedback(.impact(weight: .heavy), trigger: resetCount)
        .sensoryFeedback(trigger: tickSecond) { _, second in
            guard tickHaptics, second > 0 else { return nil }
            // A firmer knock as each minute rolls over, a soft tick every other second.
            return second % 60 == 0 ? .impact(weight: .medium, intensity: 0.9) : .impact(weight: .light, intensity: 0.45)
        }
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
                        .animation(.easeInOut(duration: 0.15), value: engine.remaining.clockString)
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

    /// The current task under the timer: check it off here, or tap to open the task list.
    private var taskCard: some View {
        HStack(spacing: 12) {
            if let task = currentTask {
                Button {
                    complete(task)
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(task.title)")

                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .id(task.id)
                    .transition(.blurReplace(.downUp))

                Spacer(minLength: 8)

                if openCount > 1 {
                    Text("+\(openCount - 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .contentTransition(.numericText())
                }
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                Text("Add a task")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondary)
        }
        .foregroundStyle(palette.ink)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { showTasks = true }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens your task list")
    }

    private var overtimeGlyph: some View {
        GeometryReader { proxy in
            NumeralFace(text: "+", font: timerFont, lit: true, palette: palette)
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
        if engine.isRunning { return engine.mode.label }
        if engine.isInProgress { return "paused · hold to reset" }
        let done = engine.completedFocusCount
        return "\(engine.mode.label) · tap to start" + (done > 0 ? " · \(done) done" : "")
    }

    // MARK: Actions

    private func primaryAction() {
        if engine.isOvertime {
            engine.advance()
            TimerNotifier.cancel()
            return
        }
        if !reduceMotion { popCount += 1 }
        if engine.isRunning {
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
        let title = currentTask?.title
        let sound = chimeEnabled
        Task {
            await TimerNotifier.requestPermission()
            await TimerNotifier.schedule(at: endDate, mode: mode, taskTitle: title, sound: sound)
        }
    }

    private func reset() {
        guard !engine.isOvertime else { return }
        engine.reset()
        resetCount += 1
        TimerNotifier.cancel()
    }

    private func complete(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.15)) { TaskActions.toggleDone(task) }
        taskDoneCount += 1
        sync.scheduleSync()
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
        sync.record(segment, taskID: segment.mode == .focus ? currentTask?.id : nil)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: TaskItem.self, FocusSessionRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(TaskItem(title: "write the sync layer"))
    return RootView()
        .environment(PomodoroEngine(defaults: nil))
        .environment(SyncCoordinator(context: container.mainContext, service: nil))
        .modelContainer(container)
}
