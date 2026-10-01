import CoreHaptics
import Foundation
import UIKit

// MARK: - Pattern description (pure, testable)

/// One haptic event in a pattern: a short tap (`transient`) or a buzz (`continuous`).
/// Intensity and sharpness are 0...1, times in seconds from the start of the pattern.
struct HapticBeat: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case transient, continuous
    }

    var kind: Kind
    var time: TimeInterval
    var intensity: Float
    var sharpness: Float
    /// Only meaningful for `continuous`; 0 for transients.
    var duration: TimeInterval = 0

    static func tap(at time: TimeInterval = 0, intensity: Float, sharpness: Float) -> HapticBeat {
        HapticBeat(kind: .transient, time: time, intensity: intensity, sharpness: sharpness)
    }

    static func buzz(at time: TimeInterval = 0, duration: TimeInterval, intensity: Float, sharpness: Float) -> HapticBeat {
        HapticBeat(kind: .continuous, time: time, intensity: intensity, sharpness: sharpness, duration: duration)
    }
}

/// How hard every haptic hits, chosen in Settings. Stored under `Feedback.Key.hapticStrength`.
enum HapticStrength: String, CaseIterable, Identifiable, Sendable {
    case soft, strong, max

    static let `default`: HapticStrength = .strong

    var id: String { rawValue }

    var label: String { rawValue }

    /// Multiplies every beat's intensity.
    var intensityScale: Float {
        switch self {
        case .soft: 0.6
        case .strong, .max: 1.0
        }
    }

    /// Added to every beat's sharpness, so `max` feels crisper.
    var sharpnessBoost: Float {
        switch self {
        case .soft, .strong: 0
        case .max: 0.15
        }
    }

    /// Multiplies the length of every buzz, so `max` lingers.
    var durationScale: Double {
        switch self {
        case .soft, .strong: 1.0
        case .max: 1.5
        }
    }

    /// The stored choice; anything missing or unknown means `.strong`.
    static func stored(in defaults: UserDefaults = .standard) -> HapticStrength {
        defaults.string(forKey: Feedback.Key.hapticStrength).flatMap(HapticStrength.init(rawValue:)) ?? .default
    }

    /// Scales a pattern, keeping intensity and sharpness inside 0...1.
    /// A lengthened buzz delays every beat after it by the same amount, so nothing overlaps.
    func apply(to beats: [HapticBeat]) -> [HapticBeat] {
        var shift: TimeInterval = 0
        return beats.map { beat in
            var scaled = beat
            scaled.intensity = Self.clamp(beat.intensity * intensityScale)
            scaled.sharpness = Self.clamp(beat.sharpness + sharpnessBoost)
            scaled.duration = beat.duration * durationScale
            scaled.time = beat.time + shift
            shift += scaled.duration - beat.duration
            return scaled
        }
    }

    static func clamp(_ value: Float) -> Float {
        Swift.min(1, Swift.max(0, value))
    }
}

/// The pattern for each event, before the strength setting is applied.
enum HapticPatterns {
    static func beats(for event: FeedbackEvent) -> [HapticBeat] {
        switch event {
        case .tick:
            // Stays light-ish: it fires every second.
            [.tap(intensity: 0.5, sharpness: 0.5)]
        case .minute:
            [.tap(intensity: 0.85, sharpness: 0.6)]
        case .start:
            // Sharp double tap at full intensity.
            [.tap(intensity: 1, sharpness: 0.9),
             .tap(at: 0.09, intensity: 1, sharpness: 0.9)]
        case .pause:
            // A firm thud: high intensity, low sharpness, with a short body behind it.
            [.tap(intensity: 1, sharpness: 0.15),
             .buzz(at: 0.01, duration: 0.06, intensity: 0.7, sharpness: 0.1)]
        case .reset:
            // Heavy rigid hit.
            [.tap(intensity: 1, sharpness: 0.75),
             .buzz(at: 0.01, duration: 0.09, intensity: 0.85, sharpness: 0.4)]
        case .switch:
            // Two rising taps.
            [.tap(intensity: 0.55, sharpness: 0.4),
             .tap(at: 0.12, intensity: 1, sharpness: 0.8)]
        case .complete:
            // Three strong pulses, then a 0.4s buzz.
            [.tap(intensity: 1, sharpness: 0.7),
             .tap(at: 0.15, intensity: 1, sharpness: 0.7),
             .tap(at: 0.30, intensity: 1, sharpness: 0.7),
             .buzz(at: 0.45, duration: 0.4, intensity: 0.9, sharpness: 0.4)]
        case .taskDone:
            // Strong double.
            [.tap(intensity: 1, sharpness: 0.7),
             .tap(at: 0.1, intensity: 1, sharpness: 0.7)]
        case .taskUndo:
            [.tap(intensity: 0.65, sharpness: 0.3)]
        case .taskDelete:
            // Heavy hit.
            [.tap(intensity: 1, sharpness: 0.5),
             .buzz(at: 0.01, duration: 0.08, intensity: 0.8, sharpness: 0.3)]
        case .tap, .taskFocus:
            // Crisp, clearly stronger than a selection tick.
            [.tap(intensity: 0.75, sharpness: 0.85)]
        case .taskAdd:
            [.tap(intensity: 0.8, sharpness: 0.75)]
        }
    }

    /// The pattern actually played: the event's beats scaled by the strength setting.
    static func beats(for event: FeedbackEvent, strength: HapticStrength) -> [HapticBeat] {
        strength.apply(to: beats(for: event))
    }
}

// MARK: - Engine

/// Plays `HapticPatterns` through Core Haptics, falling back to UIKit generators (at
/// heavier styles than before) when the hardware can't or the engine fails.
@MainActor
enum HapticEngine {
    private static var engine: CHHapticEngine?
    /// The engine stopped (app suspended, audio interruption, reset); start it before the next pattern.
    private static var needsStart = true
    private static let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    /// Creates and starts the engine (or warms up the fallback generators).
    static func prepare() {
        [impactLight, impactMedium, impactHeavy, impactRigid].forEach { $0.prepare() }
        notification.prepare()
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            // No audio in these patterns; skipping the audio graph lowers latency.
            engine.playsHapticsOnly = true
            // Ticks fire every second while running; keep the engine warm between them.
            engine.isAutoShutdownEnabled = false
            engine.stoppedHandler = makeStoppedHandler()
            engine.resetHandler = makeResetHandler()
            try engine.start()
            self.engine = engine
            needsStart = false
        } catch {
            self.engine = nil
        }
    }

    static func play(_ event: FeedbackEvent, strength: HapticStrength) {
        let beats = HapticPatterns.beats(for: event, strength: strength)
        if playCoreHaptics(beats) { return }
        playFallback(event, strength: strength)
    }

    /// Returns false when Core Haptics isn't available or failed, so the caller falls back.
    private static func playCoreHaptics(_ beats: [HapticBeat]) -> Bool {
        guard supportsHaptics else { return false }
        if engine == nil { prepare() }
        guard let engine else { return false }
        do {
            if needsStart {
                try engine.start()
                needsStart = false
            }
            let pattern = try CHHapticPattern(events: beats.map(makeEvent), parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            // Try a fresh start next time; this one goes to the UIKit generators.
            needsStart = true
            return false
        }
    }

    private static func makeEvent(_ beat: HapticBeat) -> CHHapticEvent {
        let parameters = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: beat.intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: beat.sharpness),
        ]
        switch beat.kind {
        case .transient:
            return CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: beat.time)
        case .continuous:
            return CHHapticEvent(eventType: .hapticContinuous, parameters: parameters, relativeTime: beat.time, duration: beat.duration)
        }
    }

    private static func playFallback(_ event: FeedbackEvent, strength: HapticStrength) {
        func hit(_ generator: UIImpactFeedbackGenerator, _ intensity: Float) {
            generator.impactOccurred(intensity: CGFloat(HapticStrength.clamp(intensity * strength.intensityScale)))
        }
        switch event {
        case .tick: hit(impactLight, 0.6)
        case .minute: hit(impactMedium, 1)
        case .start: hit(impactHeavy, 1)
        case .pause: hit(impactHeavy, 0.9)
        case .reset: hit(impactRigid, 1)
        case .switch: hit(impactMedium, 1)
        case .tap, .taskFocus: hit(impactRigid, 0.8)
        case .taskAdd: hit(impactMedium, 0.9)
        case .taskUndo: hit(impactMedium, 0.7)
        case .taskDelete: hit(impactHeavy, 1)
        case .taskDone, .complete: notification.notificationOccurred(.success)
        }
    }

    private static func engineStopped() {
        needsStart = true
    }

    /// The haptic server reset: the engine must be started again before it can play.
    private static func engineReset() {
        guard let engine else { return }
        do {
            try engine.start()
            needsStart = false
        } catch {
            needsStart = true
        }
    }

    // The engine calls these on its own queue. They're built outside the main actor so the
    // closures aren't main-actor isolated (which would trap when called off the main thread),
    // and they only hop back to the main actor.
    private nonisolated static func makeStoppedHandler() -> @Sendable (CHHapticEngine.StoppedReason) -> Void {
        { _ in Task { @MainActor in HapticEngine.engineStopped() } }
    }

    private nonisolated static func makeResetHandler() -> @Sendable () -> Void {
        { Task { @MainActor in HapticEngine.engineReset() } }
    }
}
