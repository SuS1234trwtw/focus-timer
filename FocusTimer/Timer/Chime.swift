import AVFoundation
import UserNotifications

/// Plays the bundled chime while the app is open.
@MainActor
final class ChimePlayer {
    static let shared = ChimePlayer()

    private var player: AVAudioPlayer?

    func play() {
        guard let url = Bundle.main.url(forResource: "chime", withExtension: "wav") else { return }
        do {
            // Playback so it sounds even with the ring switch on silent; mix so music keeps playing.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.8
            player.play()
            self.player = player
        } catch {
            // A missing chime should never interrupt the timer.
        }
    }
}

/// Schedules the end-of-block notification so the chime rings even when the app is closed.
enum TimerNotifier {
    private static let requestID = "pomodoro.end"

    static func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(at endDate: Date, mode: TimerMode, taskTitle: String?, sound: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])

        let content = UNMutableNotificationContent()
        switch mode {
        case .focus:
            content.title = "Focus block done"
            content.body = taskTitle.map { "Nice work on \"\($0)\". Time for a break." } ?? "Nice work. Time for a break."
        case .rest:
            content.title = "Break's over"
            content.body = "Back to it."
        }
        content.sound = sound ? UNNotificationSound(named: UNNotificationSoundName("chime.wav")) : nil

        let interval = max(1, endDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID])
    }
}
