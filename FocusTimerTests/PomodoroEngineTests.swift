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

    func makeEngine(defaults: UserDefaults? = nil) -> PomodoroEngine {
        let clock = self.clock
        return PomodoroEngine(clock: { clock.date }, defaults: defaults)
    }

    @Test func startsAsFullFocusBlock() {
        let engine = makeEngine()
        #expect(engine.mode == .focus)
        #expect(engine.remaining == 25 * 60)
        #expect(engine.displayMinutes == 25)
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

    @Test func displayMinutesRoundsUp() {
        let engine = makeEngine()
        engine.start()
        clock.advance(1)
        engine.tick()
        #expect(engine.displayMinutes == 25) // 24:59 still reads 25
        clock.advance(60)
        engine.tick()
        #expect(engine.displayMinutes == 24)
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
        #expect(!engine.isInProgress)
        #expect(engine.remaining == 25 * 60)
    }

    @Test func setMinutesChangesIdleBlock() {
        let engine = makeEngine()
        engine.setMinutes(44)
        #expect(engine.focusMinutes == 44)
        #expect(engine.remaining == 44 * 60)
        #expect(engine.displayMinutes == 44)

        engine.setMinutes(500)
        #expect(engine.focusMinutes == 90)
    }

    @Test func setMinutesWhileRunningAppliesNextTime() {
        let engine = makeEngine()
        engine.start()
        clock.advance(60)
        engine.setMinutes(10)
        engine.tick()
        #expect(engine.isRunning)
        #expect(engine.remaining == 24 * 60)
        engine.reset()
        #expect(engine.remaining == 10 * 60)
    }

    @Test func completingFocusEntersOvertime() throws {
        let engine = makeEngine()
        engine.start()
        clock.advance(25 * 60 + 1)
        let segment = try #require(engine.tick())

        #expect(segment.mode == .focus)
        #expect(segment.lateBy == 1)
        #expect(segment.duration == 25 * 60)
        #expect(engine.isOvertime)
        #expect(!engine.isRunning)
        #expect(engine.mode == .focus)
        #expect(engine.completedFocusCount == 1)
        #expect(engine.overtime == 1)
        #expect(engine.tick() == nil)

        clock.advance(4)
        engine.tick()
        #expect(engine.overtime == 5)
    }

    @Test func advanceMovesToBreak() {
        let engine = makeEngine()
        engine.start()
        clock.advance(25 * 60)
        engine.tick()
        engine.advance()
        #expect(!engine.isOvertime)
        #expect(engine.mode == .rest)
        #expect(engine.remaining == 5 * 60)
        #expect(engine.displayMinutes == 5)
    }

    @Test func completingBreakDoesNotCount() throws {
        let engine = makeEngine()
        engine.switchMode(to: .rest)
        engine.start()
        clock.advance(5 * 60)
        let segment = try #require(engine.tick())
        #expect(segment.mode == .rest)
        #expect(engine.completedFocusCount == 0)
        engine.advance()
        #expect(engine.mode == .focus)
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

    @Test func fastUnitScalesMinutes() {
        let clock = self.clock
        let engine = PomodoroEngine(unit: 1, clock: { clock.date }, defaults: nil)
        #expect(engine.remaining == 25)
        #expect(engine.displayMinutes == 25)
    }

    @Test func persistsAcrossRelaunch() throws {
        let suite = "PomodoroEngineTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = makeEngine(defaults: defaults)
        first.setMinutes(40)
        first.start()
        clock.advance(120)

        let second = makeEngine(defaults: defaults)
        second.tick()
        #expect(second.focusMinutes == 40)
        #expect(second.isRunning)
        #expect(second.remaining == 40 * 60 - 120)
    }

    @Test func clockStrings() {
        #expect(TimeInterval(0.2).clockString == "00:01")
        #expect(TimeInterval(0).clockString == "00:00")
        #expect(TimeInterval(59.5).clockString == "01:00")
        #expect(TimeInterval(1.67).stopwatchString == "00:01:67")
        #expect(TimeInterval(61.5).stopwatchString == "01:01:50")
    }
}
