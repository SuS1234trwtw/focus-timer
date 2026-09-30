import ActivityKit
import Foundation
import WidgetKit

/// The colours and prompt the Live Activity and widgets draw with, taken from the current palette.
struct LiveLook: Equatable {
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
}

/// Starts, updates and ends the Live Activity, and saves the snapshot the home/lock widgets read.
@MainActor
final class LiveActivityController {
    private var activity: Activity<FocusActivityAttributes>?
    private var lastState: FocusActivityAttributes.ContentState?
    private var lastSnapshot: TimerSnapshot?

    func update(engine: PomodoroEngine, look: LiveLook, taskTitle: String?, trackLine: String?) {
        let inProgress = engine.isRunning || engine.segmentStartedAt != nil

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
            trackLine: trackLine
        )

        saveSnapshot(TimerSnapshot(
            mode: state.mode, endDate: state.endDate, remaining: state.remaining, total: state.total,
            taskTitle: taskTitle, style: look.style, prompt: look.prompt,
            accentHex: look.accentHex, backgroundHex: look.backgroundHex,
            textHex: look.textHex, dimHex: look.dimHex, trackLine: trackLine
        ))

        if inProgress {
            guard state != lastState || activity?.attributes.prompt != look.prompt else { return }
            lastState = state
            show(state, prompt: look.prompt)
        } else {
            end()
        }
    }

    private func show(_ state: FocusActivityAttributes.ContentState, prompt: String) {
        let content = ActivityContent(state: state, staleDate: nil)
        let current = activity ?? Activity<FocusActivityAttributes>.activities.first

        if let current, current.attributes.prompt == prompt {
            activity = current
            let id = current.id
            Task { await Self.update(activityID: id, with: content) }
            return
        }
        // A new style means new attributes: replace the activity.
        if let current {
            let id = current.id
            Task { await Self.end(activityID: id) }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(attributes: FocusActivityAttributes(prompt: prompt), content: content, pushType: nil)
    }

    private func end() {
        lastState = nil
        let current = activity ?? Activity<FocusActivityAttributes>.activities.first
        activity = nil
        guard let id = current?.id else { return }
        Task { await Self.end(activityID: id) }
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

    private func saveSnapshot(_ snapshot: TimerSnapshot) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
