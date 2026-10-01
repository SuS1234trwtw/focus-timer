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

    let live = LiveActivityController()

    /// Kept current by `RootView` so actions triggered outside the UI know what to show.
    var currentTask: (id: UUID, title: String)?
    /// Set by `RootView` from the current palette. Until it is, no island is created, so the first
    /// one isn't built with the placeholder look and then torn down and recreated.
    /// Saved, so a Dynamic Island button that relaunches the app in the background (no UI, so no
    /// `RootView`) still pushes the right colours.
    var liveLook: LiveLook? = LiveLook.saved {
        didSet { liveLook?.save() }
    }
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
        // The block already ran out while we were suspended (the island shows 00:00 and "start"):
        // record it, then start the next block, so one tap does what the button says.
        if let segment = engine.tick() {
            finish(segment)
            start()
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
        GoogleCalendarService.shared.log(
            mode: segment.mode.rawValue, start: segment.startedAt, end: segment.endedAt,
            taskTitle: segment.mode == .focus ? currentTask?.title : nil)
        refreshLiveActivity()
    }

    /// Settings → island → restart: ends any island and creates a fresh one.
    func restartLiveActivity() {
        live.restart(
            engine: engine,
            look: liveLook ?? .placeholder,
            taskTitle: currentTask?.title,
            trackLine: showTrackInIsland ? spotify.track?.line : nil
        )
    }

    // MARK: App lifecycle (see `AppLifecycle`)

    /// The app is about to be killed (e.g. swiped away): keep the island but hide its buttons.
    /// Blocks briefly so the update reaches iOS before the process ends.
    func appWillTerminate() {
        live.markTerminated()
    }

    /// Back on screen: the island's buttons may show again.
    func appDidBecomeActive() {
        live.appAlive = true
        refreshLiveActivity()
        Task { await GoogleCalendarService.shared.flushPending() }
    }

    /// Pushes the current timer state to the Live Activity, the Dynamic Island and the widgets.
    /// Also call this after changing an `IslandSettings` value.
    func refreshLiveActivity() {
        live.update(
            engine: engine,
            look: liveLook ?? .placeholder,
            taskTitle: currentTask?.title,
            trackLine: showTrackInIsland ? spotify.track?.line : nil,
            // Creating needs the app on screen *and* the real look (so launch order doesn't matter).
            appIsActive: isAppActive && liveLook != nil
        )
    }
}
