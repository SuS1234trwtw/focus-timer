import Foundation
import Testing
@testable import FocusTimer

@MainActor
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}

@MainActor
struct PomodoroEngineTests {
    let clock = TestClock()

    func makeEngine() -> PomodoroEngine {
        let clock = self.clock
        return PomodoroEngine(durations: .standard, clock: { clock.date }, defaults: nil)
    }

    @Test func startsAsFullFocusBlock() {
        let engine = makeEngine()
        #expect(engine.mode == .focus)
        #expect(engine.remaining == 25 * 60)
        #expect(!engine.isRunning)
        #expect(engine.remaining.clockString == "25:00")
    }

    @Test func countsDownFromEndDate() {
        let engine = makeEngine()
        engine.start()
        clock.advance(90)
        engine.tick()
        #expect(engine.remaining == 25 * 60 - 90)
        #expect(engine.remaining.clockString == "23:30")
    }

    @Test func pauseFreezesAndResumeContinues() {
        let engine = makeEngine()
        engine.start()
        clock.advance(60)
        engine.pause()
        clock.advance(600)
        engine.tick()
        #expect(engine.remaining == 24 * 60)

        engine.start()
        clock.advance(60)
        engine.tick()
        #expect(engine.remaining == 23 * 60)
    }

    @Test func resetRestoresFullDuration() {
        let engine = makeEngine()
        engine.start()
        clock.advance(300)
        engine.reset()
        #expect(!engine.isRunning)
        #expect(engine.remaining == 25 * 60)
    }

    @Test func completingFocusSwitchesToBreak() throws {
        let engine = makeEngine()
        engine.start()
        clock.advance(25 * 60 + 1)
        let segment = try #require(engine.tick())

        #expect(segment.mode == .focus)
        #expect(segment.lateBy == 1)
        #expect(segment.duration == 25 * 60)
        #expect(engine.mode == .rest)
        #expect(!engine.isRunning)
        #expect(engine.remaining == 5 * 60)
        #expect(engine.completedFocusCount == 1)
        #expect(engine.tick() == nil)
    }

    @Test func completingBreakReturnsToFocusWithoutCounting() throws {
        let engine = makeEngine()
        engine.switchMode(to: .rest)
        engine.start()
        clock.advance(5 * 60)
        let segment = try #require(engine.tick())
        #expect(segment.mode == .rest)
        #expect(engine.mode == .focus)
        #expect(engine.completedFocusCount == 0)
    }

    @Test func segmentStartSurvivesPause() throws {
        let engine = makeEngine()
        let startedAt = clock.date
        engine.start()
        clock.advance(100)
        engine.pause()
        clock.advance(50)
        engine.start()
        clock.advance(25 * 60)
        let segment = try #require(engine.tick())
        #expect(segment.startedAt == startedAt)
    }

    @Test func persistsAcrossRelaunch() throws {
        let suite = "PomodoroEngineTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = self.clock

        let first = PomodoroEngine(durations: .standard, clock: { clock.date }, defaults: defaults)
        first.start()
        clock.advance(120)

        let second = PomodoroEngine(durations: .standard, clock: { clock.date }, defaults: defaults)
        second.tick()
        #expect(second.isRunning)
        #expect(second.remaining == 25 * 60 - 120)
    }

    @Test func clockStringRoundsUp() {
        #expect(TimeInterval(0.2).clockString == "00:01")
        #expect(TimeInterval(0).clockString == "00:00")
        #expect(TimeInterval(59.5).clockString == "01:00")
    }
}
