import AVFoundation
import UIKit

/// Everything in the app that can click, beep, or buzz. Raw values match the files in Resources/Sounds.
enum FeedbackEvent: String, CaseIterable {
    case tick, minute, start, pause, reset, `switch`, tap
    case taskAdd = "task_add"
    case taskDone = "task_done"
    case taskUndo = "task_undo"
    case taskDelete = "task_delete"
    case taskFocus = "task_focus"
    /// The block finished; the chime is played separately, this is the haptic.
    case complete

    fileprivate var isTick: Bool { self == .tick || self == .minute }
}

/// Plays a sound and a haptic for each `FeedbackEvent`, honouring the switches in Settings.
@MainActor
enum Feedback {
    /// UserDefaults keys, shared with the @AppStorage switches in Settings.
    enum Key {
        static let sounds = "soundsEnabled"
        static let haptics = "hapticsEnabled"
        static let tickSound = "tickSound"
        static let tickHaptics = "tickHaptics"
    }

    private static var players: [FeedbackEvent: AVAudioPlayer] = [:]
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Loads every sound up front so the first tap isn't late.
    static func prepare() {
        for event in FeedbackEvent.allCases {
            guard let url = Bundle.main.url(forResource: event.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = event.isTick ? 0.35 : 0.6
            player.prepareToPlay()
            players[event] = player
        }
        [impactLight, impactMedium, impactRigid, impactSoft].forEach { $0.prepare() }
        selection.prepare()
        notification.prepare()
    }

    static func play(_ event: FeedbackEvent) {
        let defaults = UserDefaults.standard
        func enabled(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }

        let wantsSound = enabled(Key.sounds) && (!event.isTick || enabled(Key.tickSound))
        let wantsHaptic = enabled(Key.haptics) && (!event.isTick || enabled(Key.tickHaptics))

        if wantsSound, let player = players[event] {
            useAmbientSession()
            player.currentTime = 0
            player.play()
        }
        if wantsHaptic { haptic(for: event) }
    }

    private static func haptic(for event: FeedbackEvent) {
        switch event {
        case .tick: impactLight.impactOccurred(intensity: 0.45)
        case .minute: impactMedium.impactOccurred(intensity: 0.9)
        case .start: impactMedium.impactOccurred()
        case .pause: impactSoft.impactOccurred()
        case .reset: impactRigid.impactOccurred()
        case .switch: selection.selectionChanged()
        case .tap: selection.selectionChanged()
        case .taskAdd: impactLight.impactOccurred()
        case .taskDone: notification.notificationOccurred(.success)
        case .taskUndo: impactSoft.impactOccurred(intensity: 0.6)
        case .taskDelete: impactRigid.impactOccurred(intensity: 0.8)
        case .taskFocus: selection.selectionChanged()
        case .complete: notification.notificationOccurred(.success)
        }
    }

    /// UI sounds respect the ring/silent switch and mix with music. (The end-of-block chime
    /// switches to playback so it's heard on silent; this switches back.)
    private static func useAmbientSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .ambient else { return }
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }
}
