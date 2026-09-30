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
        style: "cozy", prompt: "~/focus $", accentHex: "F5A05A",
        backgroundHex: "1A1614", textHex: "E8DCCF", dimHex: "8A7D72"
    )

    private static let key = "liveActivity.look"

    static var saved: LiveLook? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LiveLook.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Keeps one Live Activity (lock screen + Dynamic Island) alive at all times, running or not, and saves
/// the snapshot the home/lock widgets read.
///
/// iOS only lets an app *create* a Live Activity while it's on screen, but an existing one survives the
/// app being backgrounded or force-quit, and its buttons relaunch the app in the background. So we create
/// it whenever the app is open, never end it when the timer stops, and renew it before iOS's 8-hour limit.
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

    /// Ends whatever exists and creates a fresh island now (the app must be on screen).
    func restart(engine: PomodoroEngine, look: LiveLook, taskTitle: String?, trackLine: String?) {
        UserDefaults.standard.removeObject(forKey: startedAtKey)
        lastState = nil
        // `replace` creates the new island first and only then ends the others, so a refused
        // request leaves the old one in place instead of nothing.
        update(engine: engine, look: look, taskTitle: taskTitle, trackLine: trackLine, appIsActive: true, forceNew: true)
    }

    /// - Parameter appIsActive: the app is on screen, so a new activity may be created if needed.
    func update(engine: PomodoroEngine, look: LiveLook, taskTitle: String?, trackLine: String?, appIsActive: Bool, forceNew: Bool = false) {
        let hasStarted = engine.isRunning || engine.segmentStartedAt != nil

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
            started: hasStarted
        )

        saveSnapshot(TimerSnapshot(
            mode: state.mode, endDate: state.endDate, remaining: state.remaining, total: state.total,
            taskTitle: taskTitle, style: look.style, prompt: look.prompt,
            accentHex: look.accentHex, backgroundHex: look.backgroundHex,
            textHex: look.textHex, dimHex: look.dimHex, trackLine: trackLine
        ))

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

    /// The activity we own, dropping duplicates or ones the user dismissed.
    private func liveActivity() -> Activity<FocusActivityAttributes>? {
        // Anything not finished counts, including one iOS is still bringing up.
        let alive = Activity<FocusActivityAttributes>.activities.filter {
            $0.activityState != .ended && $0.activityState != .dismissed
        }
        let keep = alive.first { $0.id == activity?.id } ?? alive.first
        for extra in alive where extra.id != keep?.id {
            let id = extra.id
            Task { await Self.end(activityID: id) }
        }
        activity = keep
        return keep
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
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            let created = try Activity.request(attributes: FocusActivityAttributes(prompt: prompt), content: content, pushType: nil)
            for other in Activity<FocusActivityAttributes>.activities where other.id != created.id {
                let id = other.id
                Task { await Self.end(activityID: id) }
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
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await Self.update(activityID: id, with: content) }
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
