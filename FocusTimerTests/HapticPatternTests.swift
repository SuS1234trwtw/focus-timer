import Foundation
import Testing
@testable import FocusTimer

struct HapticPatternTests {
    private func close(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.0001 }
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    @Test(arguments: FeedbackEvent.allCases, HapticStrength.allCases)
    func everyPatternIsPlayable(event: FeedbackEvent, strength: HapticStrength) {
        let beats = HapticPatterns.beats(for: event, strength: strength)
        #expect(!beats.isEmpty)
        for beat in beats {
            #expect((0...1).contains(beat.intensity))
            #expect((0...1).contains(beat.sharpness))
            #expect(beat.time >= 0)
            #expect(beat.duration >= 0)
            if beat.kind == .transient { #expect(beat.duration == 0) }
        }
        #expect(beats.map(\.time) == beats.map(\.time).sorted())
    }

    @Test func startIsSharpDoubleTapAtFullIntensity() {
        let beats = HapticPatterns.beats(for: .start, strength: .strong)
        #expect(beats.count == 2)
        #expect(beats.allSatisfy { $0.kind == .transient && close($0.intensity, 1) && $0.sharpness >= 0.8 })
    }

    @Test func pauseIsFirmAndDull() throws {
        let first = try #require(HapticPatterns.beats(for: .pause, strength: .strong).first)
        #expect(first.intensity >= 0.9)
        #expect(first.sharpness <= 0.3)
    }

    @Test func switchRises() {
        let beats = HapticPatterns.beats(for: .switch, strength: .strong)
        #expect(beats.count == 2)
        #expect(beats[1].intensity > beats[0].intensity)
    }

    @Test func completeIsThreePulsesThenBuzz() {
        let beats = HapticPatterns.beats(for: .complete, strength: .strong)
        #expect(beats.filter { $0.kind == .transient }.count == 3)
        let buzz = beats.last
        #expect(buzz?.kind == .continuous)
        #expect(buzz.map { close($0.duration, 0.4) } == true)
        #expect(beats.dropLast().allSatisfy { $0.intensity >= 0.9 })
    }

    @Test func tapsAreStrongerThanTicks() {
        let tick = HapticPatterns.beats(for: .tick, strength: .strong)[0].intensity
        #expect(tick >= 0.4 && tick <= 0.6)
        for event in [FeedbackEvent.tap, .taskFocus, .taskAdd] {
            #expect(HapticPatterns.beats(for: event, strength: .strong)[0].intensity > tick)
        }
        #expect(HapticPatterns.beats(for: .minute, strength: .strong)[0].intensity > tick)
    }

    @Test func softScalesIntensityDown() {
        for event in FeedbackEvent.allCases {
            let base = HapticPatterns.beats(for: event)
            let soft = HapticPatterns.beats(for: event, strength: .soft)
            for (b, s) in zip(base, soft) {
                #expect(close(s.intensity, b.intensity * 0.6))
                #expect(close(s.sharpness, b.sharpness))
            }
        }
    }

    @Test func strongIsTheBasePattern() {
        for event in FeedbackEvent.allCases {
            #expect(HapticPatterns.beats(for: event, strength: .strong) == HapticPatterns.beats(for: event))
        }
    }

    @Test func maxIsSharperAndLongerButClamped() {
        let strong = HapticPatterns.beats(for: .complete, strength: .strong)
        let max = HapticPatterns.beats(for: .complete, strength: .max)
        for (s, m) in zip(strong, max) {
            #expect(m.sharpness >= s.sharpness)
            #expect(m.sharpness <= 1)
            #expect(m.intensity <= 1)
        }
        #expect(max.last!.duration > strong.last!.duration)
        // Start's 0.9 sharpness + 0.15 boost must clamp to 1.
        #expect(HapticPatterns.beats(for: .start, strength: .max).allSatisfy { close($0.sharpness, 1) })
    }

    @Test func longerBuzzDelaysLaterBeats() {
        let beats = [HapticBeat.buzz(duration: 0.2, intensity: 1, sharpness: 0.5), .tap(at: 0.3, intensity: 1, sharpness: 0.5)]
        let scaled = HapticStrength.max.apply(to: beats)
        #expect(close(scaled[0].duration, 0.3))
        #expect(close(scaled[1].time, 0.4))
    }

    @Test func clampKeepsValuesInRange() {
        #expect(HapticStrength.clamp(1.4) == 1)
        #expect(HapticStrength.clamp(-0.2) == 0)
        #expect(HapticStrength.clamp(0.5) == 0.5)
    }

    @Test func storedStrengthDefaultsToStrong() throws {
        let suite = "HapticPatternTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(HapticStrength.stored(in: defaults) == .strong)
        defaults.set("nonsense", forKey: Feedback.Key.hapticStrength)
        #expect(HapticStrength.stored(in: defaults) == .strong)
        defaults.set("max", forKey: Feedback.Key.hapticStrength)
        #expect(HapticStrength.stored(in: defaults) == .max)
        defaults.set("soft", forKey: Feedback.Key.hapticStrength)
        #expect(HapticStrength.stored(in: defaults) == .soft)
    }

    @Test func rawValuesMatchSettings() {
        #expect(HapticStrength.allCases.map(\.rawValue) == ["soft", "strong", "max"])
        #expect(HapticStrength.default == .strong)
    }
}
