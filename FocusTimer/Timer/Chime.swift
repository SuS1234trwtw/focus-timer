import AVFoundation
import UserNotifications

/// Rings the end-of-block sound while the app is open: the user's pick from Settings → sounds,
/// falling back to the bundled chime.
@MainActor
final class ChimePlayer {
    static let shared = ChimePlayer()

    /// `mode` is the block that just ended. When omitted it's inferred from the engine, which has
    /// already moved on to the next block by the time a finished one is reported.
    func play(for mode: TimerMode? = nil) {
        let ended = mode ?? AppModel.shared.engine.mode.next
        SoundBoard.play(ended == .focus ? .focusEnd : .breakEnd)
    }
}

/// Schedules the end-of-block notification so the chosen sound rings even when the app is closed.
enum TimerNotifier {
    private static let requestID = "pomodoro.end"

    static func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(at endDate: Date, mode: TimerMode, taskTitle: String?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])

        let content = UNMutableNotificationContent()
        switch mode {
        case .focus:
            content.title = "focus block done"
            content.body = taskTitle.map { "Nice work on \"\($0)\". Take five." } ?? "Nice work. Take five."
        case .rest:
            content.title = "break's over"
            content.body = "Back to it."
        }
        content.sound = SoundBoard.notificationSound(for: mode == .focus ? .focusEnd : .breakEnd)

        let interval = max(1, endDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID])
    }
}
