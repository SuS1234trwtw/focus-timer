import Foundation
import SwiftData

/// Owns the long-lived pieces (store, timer, sync, Spotify, Live Activity) and the timer actions,
/// so the UI and the Dynamic Island buttons drive the same timer — even when the app was
/// launched in the background just to handle a button press.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let container: ModelContainer
    let engine: PomodoroEngine
    let sync: SyncCoordinator
    let spotify = SpotifyService()

    private let live = LiveActivityController()

    /// Kept current by `RootView` so actions triggered outside the UI know what to show.
    var currentTask: (id: UUID, title: String)?
    var liveLook = LiveLook.placeholder
    var showTrackInIsland = true
    /// The app is on screen. Only then may a Live Activity be created; starts false because a
    /// Live Activity button can launch the app straight into the background.
    var isAppActive = false

    private init() {
        do {
            container = try ModelContainer(for: TaskItem.self, FocusSessionRecord.self)
        } catch {
            fatalError("Could not open local store: \(error)")
        }

        #if DEBUG
        // Launch with `-seedDemo` to fill an empty store with sample tasks (used for CI screenshots).
        if ProcessInfo.processInfo.arguments.contains("-seedDemo"),
           (try? container.mainContext.fetchCount(FetchDescriptor<TaskItem>())) == 0 {
            let context = container.mainContext
            context.insert(TaskItem(title: "wire up supabase sync", isActive: true, createdAt: .now.addingTimeInterval(-30)))
            context.insert(TaskItem(title: "review the timer PR", isDone: true, createdAt: .now.addingTimeInterval(-20)))
            context.insert(TaskItem(title: "inbox zero", createdAt: .now.addingTimeInterval(-10)))
            try? context.save()
        }
        #endif

        // Launch with `-fastTimer` (Xcode scheme argument) for 10s/5s cycles while testing.
        let fast = ProcessInfo.processInfo.arguments.contains("-fastTimer")
        let defaults = UserDefaults.standard
        let custom = PomodoroDurations(
            focusMinutes: defaults.object(forKey: "focusMinutes") as? Int ?? 25,
            restMinutes: defaults.object(forKey: "restMinutes") as? Int ?? 5
        )
        engine = PomodoroEngine(durations: fast ? .fast : custom)
        sync = SyncCoordinator(context: container.mainContext, service: SupabaseService.fromInfoPlist())

        TimerIntentBridge.toggle = { [weak self] in self?.toggle() }
        TimerIntentBridge.switchMode = { [weak self] in self?.switchAndStart() }
    }

    // MARK: Timer actions

    func start() {
        engine.start()
        guard let endDate = engine.endDate else { return }
        Feedback.play(.start)
        let mode = engine.mode
        let title = currentTask?.title
        Task {
            await TimerNotifier.requestPermission()
            await TimerNotifier.schedule(at: endDate, mode: mode, taskTitle: title)
        }
        refreshLiveActivity()
    }

    func pause() {
        engine.pause()
        Feedback.play(.pause)
        TimerNotifier.cancel()
        refreshLiveActivity()
    }

    func toggle() {
        // Catch up first: if the block already ended while we were suspended, finish it instead.
        if let segment = engine.tick() {
            finish(segment)
            return
        }
        engine.isRunning ? pause() : start()
    }

    func reset() {
        engine.reset()
        Feedback.play(.reset)
        TimerNotifier.cancel()
        refreshLiveActivity()
    }

    func switchMode(_ mode: TimerMode) {
        engine.switchMode(to: mode)
        Feedback.play(.switch)
        TimerNotifier.cancel()
        refreshLiveActivity()
    }

    /// Focus ↔ break, starting the new block straight away (the Dynamic Island's switch button).
    func switchAndStart() {
        if let segment = engine.tick() {
            // The block ended while the phone was locked: the timer already moved to the next mode.
            finish(segment)
        } else {
            engine.switchMode(to: engine.mode.next)
            TimerNotifier.cancel()
        }
        start()
    }

    func finish(_ segment: CompletedSegment) {
        // If the app was in the background, the scheduled notification already rang.
        if segment.lateBy < 3 {
            ChimePlayer.shared.play()
            Feedback.play(.complete)
        }
        sync.record(segment, taskID: segment.mode == .focus ? currentTask?.id : nil)
        refreshLiveActivity()
    }

    /// Pushes the current timer state to the Live Activity, the Dynamic Island and the widgets.
    func refreshLiveActivity() {
        live.update(
            engine: engine,
            look: liveLook,
            taskTitle: currentTask?.title,
            trackLine: showTrackInIsland ? spotify.track?.line : nil,
            appIsActive: isAppActive
        )
    }
}
