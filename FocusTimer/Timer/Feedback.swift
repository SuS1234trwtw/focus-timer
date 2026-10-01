import AVFoundation
import Foundation

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
        /// A `HapticStrength` raw value: "soft", "strong" (default) or "max".
        static let hapticStrength = "hapticStrength"
    }

    private static var players: [FeedbackEvent: AVAudioPlayer] = [:]

    /// Loads every sound up front so the first tap isn't late.
    static func prepare() {
        for event in FeedbackEvent.allCases {
            guard let url = Bundle.main.url(forResource: event.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = event.isTick ? 0.35 : 0.9
            player.prepareToPlay()
            players[event] = player
        }
        HapticEngine.prepare()
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
        HapticEngine.play(event, strength: HapticStrength.stored())
    }

    /// UI sounds respect the ring/silent switch and mix with music. (The end-of-block chime
    /// switches to playback so it's heard on silent; this switches back.)
    private static func useAmbientSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .ambient else { return }
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }
}
