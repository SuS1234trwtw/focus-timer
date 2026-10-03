import ActivityKit
import Foundation
import Observation
import OSLog
import WidgetKit

/// The colours and prompt the Live Activity and widgets draw with, taken from the current palette.
struct LiveLook: Equatable, Codable {
    var style: String
    var prompt: String
    var accentHex: String
    var backgroundHex: String
    var textHex: String
    var dimHex: String

    static let placeholder = LiveLook(
        style: "mono", prompt: "~/focus $", accentHex: "F5F5F2",
        backgroundHex: "050505", textHex: "F5F5F2", dimHex: "8C8C89"
    )

    private static let key = "liveActivity.look"

    static var saved: LiveLook? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LiveLook.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// When the island should exist at all: only while the timer is in use.
///
/// "In use" means running, or paused partway through a block (it has a start time but no end date).
/// An idle timer (never started, reset, or a block just finished and the next not started) has
/// nothing worth keeping on the lock screen, so the island goes away.
enum LiveActivityPolicy {
    static func shouldShow(isRunning: Bool, segmentStartedAt: Date?) -> Bool {
        isRunning || segmentStartedAt != nil
    }
}

/// Shows one Live Activity (lock screen + Dynamic Island) while the timer is in use, ends it as soon
/// as the timer goes idle or the app is closed, and saves the snapshot the home/lock widgets read.
///
/// iOS only lets an app *create* a Live Activity while it's on screen, but an existing one survives the
/// app being backgrounded and its buttons relaunch the app in the background. So we create it from the
/// foreground when a block is in use, keep updating it from wherever we are, and renew it before iOS's
/// 8-hour limit if a block sits paused that long.
@MainActor
@Observable
final class LiveActivityController {
    /// Why the last attempt to create the island failed, straight from iOS; nil after a success.
    private(set) var lastError: String?
    /// When the island was last created successfully.
    private(set) var lastCreated: Date?

    @ObservationIgnored private var activity: Activity<FocusActivityAttributes>?
    @ObservationIgnored private var lastState: FocusActivityAttributes.ContentState?
    @ObservationIgnored private var lastSnapshot: TimerSnapshot?
    /// Activities we've asked iOS to end. Ending is async, so for a moment they still look alive;
    /// without this a quick reset → start would reuse one that's about to disappear.
    @ObservationIgnored private var endingIDs: Set<String> = []
    @ObservationIgnored private let log = Logger(subsystem: "com.focustimer.app", category: "LiveActivity")

    @ObservationIgnored private let startedAtKey = "liveActivity.startedAt"
    /// Renew well before iOS ends activities (8 hours), whenever the app is on screen.
    @ObservationIgnored private let renewAfter: TimeInterval = 6 * 60 * 60

    // MARK: Diagnostics (Settings → island)

    /// Whether iOS lets this app show Live Activities (Settings → Focus → Live Activities).
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Every activity iOS knows for this app, with its state, e.g. ["active"].
    var activityStates: [String] {
        Activity<FocusActivityAttributes>.activities.map { String(describing: $0.activityState) }
    }

    /// Ends whatever exists and, if the timer is in use, creates a fresh island now (the app must be
    /// on screen). With an idle timer this just clears any leftover island.
    func restart(engine: PomodoroEngine, look: LiveLook, taskTitle: String?, trackLine: String?) {
        UserDefaults.standard.removeObject(forKey: startedAtKey)
        lastState = nil
        // `replace` creates the new island first and only then ends the others, so a refused
        // request leaves the old one in place instead of nothing.
        update(engine: engine, look: look, taskTitle: taskTitle, trackLine: trackLine, appIsActive: true, forceNew: true)
    }

    /// - Parameter appIsActive: the app is on screen, so a new activity may be created if needed.
    func update(engine: PomodoroEngine, look: LiveLook, taskTitle: String?, trackLine: String?, appIsActive: Bool, forceNew: Bool = false) {
        let inUse = LiveActivityPolicy.shouldShow(isRunning: engine.isRunning, segmentStartedAt: engine.segmentStartedAt)

        let state = FocusActivityAttributes.ContentState(
            mode: engine.mode.rawValue,
            endDate: engine.endDate,
            remaining: engine.remaining,
            total: engine.total,
            taskTitle: taskTitle,
            accentHex: look.accentHex,
            backgroundHex: look.backgroundHex,
            textHex: look.textHex,
            dimHex: look.dimHex,
            trackLine: trackLine,
            started: inUse,
            controls: IslandSettings.buttons(),
            showToggle: IslandSettings.pauseButton(),
            showSwitch: IslandSettings.switchButton(),
            lockControls: IslandSettings.lockScreenButtons(),
            // Kept so older builds' states still decode; an island only exists while the app is alive now.
            appAlive: true
        )

        // The widgets show the idle timer too, so the snapshot is saved whether or not there's an island.
        saveSnapshot(TimerSnapshot(
            mode: state.mode, endDate: state.endDate, remaining: state.remaining, total: state.total,
            taskTitle: taskTitle, style: look.style, prompt: look.prompt,
            accentHex: look.accentHex, backgroundHex: look.backgroundHex,
            textHex: look.textHex, dimHex: look.dimHex, trackLine: trackLine
        ))

        guard inUse else {
            endAll()
            return
        }

        let current = forceNew ? nil : liveActivity()
        let needsNew = current == nil || current?.attributes.prompt != look.prompt || (appIsActive && isOld)

        if needsNew {
            // Only possible while the app is on screen; from the background we keep what exists.
            guard appIsActive else {
                if let current { push(state, to: current) }
                return
            }
            replace(current, with: state, prompt: look.prompt)
        } else if let current, state != lastState {
            push(state, to: current)
        }
    }

    // MARK: Activity lifecycle

    /// Activities that aren't finished (including one iOS is still bringing up) and that we haven't
    /// already asked to end.
    private func aliveActivities() -> [Activity<FocusActivityAttributes>] {
        Activity<FocusActivityAttributes>.activities.filter {
            $0.activityState != .ended && $0.activityState != .dismissed && !endingIDs.contains($0.id)
        }
    }

    /// The activity we own, dropping duplicates or ones the user dismissed.
    private func liveActivity() -> Activity<FocusActivityAttributes>? {
        let alive = aliveActivities()
        let keep = alive.first { $0.id == activity?.id } ?? alive.first
        for extra in alive where extra.id != keep?.id {
            end(extra.id)
        }
        activity = keep
        return keep
    }

    /// The timer went idle: take every island down right away.
    private func endAll() {
        // Forget ids iOS no longer lists, so the set doesn't grow forever.
        let known = Set(Activity<FocusActivityAttributes>.activities.map { $0.id })
        endingIDs.formIntersection(known)
        for alive in aliveActivities() {
            end(alive.id)
        }
        activity = nil
        lastState = nil
        // The next island is a new one; its age counts from when it's created.
        UserDefaults.standard.removeObject(forKey: startedAtKey)
    }

    private func end(_ id: String) {
        endingIDs.insert(id)
        Task { await Self.end(activityID: id) }
    }

    private var isOld: Bool {
        guard let started = UserDefaults.standard.object(forKey: startedAtKey) as? Date else { return true }
        return Date.now.timeIntervalSince(started) > renewAfter
    }

    /// Creates a new island, and only once that has succeeded ends every other one (including `old`).
    private func replace(_ old: Activity<FocusActivityAttributes>?, with state: FocusActivityAttributes.ContentState, prompt: String) {
        guard areActivitiesEnabled else {
            lastError = "Live Activities are turned off for Focus in iOS Settings"
            log.error("Live Activities disabled for this app")
            return
        }
        let content = ActivityContent(state: state, staleDate: Self.staleDate(for: state))
        do {
            let created = try Activity.request(attributes: FocusActivityAttributes(prompt: prompt), content: content, pushType: nil)
            for other in Activity<FocusActivityAttributes>.activities where other.id != created.id {
                end(other.id)
            }
            activity = created
            lastState = state
            lastError = nil
            lastCreated = .now
            UserDefaults.standard.set(Date.now, forKey: startedAtKey)
            log.info("Live Activity created")
        } catch {
            // The old island (if any) is still up; keep using it.
            activity = old
            // Keep the real reason: it's the only way to tell a settings problem from a signing one.
            lastError = "\(String(describing: error)) — \(error.localizedDescription)"
            log.error("Live Activity request failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func push(_ state: FocusActivityAttributes.ContentState, to current: Activity<FocusActivityAttributes>) {
        lastState = state
        let id = current.id
        let content = ActivityContent(state: state, staleDate: Self.staleDate(for: state))
        Task { await Self.update(activityID: id, with: content) }
    }

    /// While running, the activity goes stale when the block ends: the island can't re-check the clock
    /// by itself, and `isStale` is how it learns to hide the buttons. Never stale while paused.
    private nonisolated static func staleDate(for state: FocusActivityAttributes.ContentState) -> Date? {
        state.endDate
    }

    // MARK: Termination

    /// Ends every Live Activity immediately and waits (up to `timeout`) for iOS to take them down.
    /// Used when the app is being terminated (e.g. swiped away): an island left behind would show a
    /// timer nothing is driving any more, with buttons that act on a dead app.
    ///
    /// Safe to call on the main thread: the work runs on a detached task that never touches the main
    /// actor, so waiting for it here can't deadlock, and the timeout bounds the wait regardless.
    nonisolated static func endAllBlocking(timeout: TimeInterval = 2) {
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            let alive = Activity<FocusActivityAttributes>.activities.filter {
                $0.activityState != .ended && $0.activityState != .dismissed
            }
            for activity in alive {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    // `Activity` isn't Sendable, so the async calls look it up by id where they run
    // instead of carrying the main-actor reference across.

    private nonisolated static func update(activityID: String, with content: ActivityContent<FocusActivityAttributes.ContentState>) async {
        guard let activity = Activity<FocusActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.update(content)
    }

    private nonisolated static func end(activityID: String) async {
        guard let activity = Activity<FocusActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: Widgets

    private func saveSnapshot(_ snapshot: TimerSnapshot) {
        // Without the App Group the widgets can't read it, so don't spend their reload budget.
        guard AppGroup.isAvailable, snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
