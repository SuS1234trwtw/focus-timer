import Foundation
import Testing
@testable import FocusTimer

struct LiveActivityPolicyTests {
    private let started = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func idleTimerHasNoIsland() {
        #expect(!LiveActivityPolicy.shouldShow(isRunning: false, segmentStartedAt: nil))
    }

    @Test func runningTimerShowsIsland() {
        #expect(LiveActivityPolicy.shouldShow(isRunning: true, segmentStartedAt: started))
    }

    @Test func pausedPartwayShowsIsland() {
        #expect(LiveActivityPolicy.shouldShow(isRunning: false, segmentStartedAt: started))
    }

    @Test func runningWithoutStartDateStillShowsIsland() {
        #expect(LiveActivityPolicy.shouldShow(isRunning: true, segmentStartedAt: nil))
    }

    /// A block that finishes flips the engine to the next mode with no start date: the timer is idle.
    @Test @MainActor func finishedBlockIsIdle() {
        let clock = TestClock()
        let engine = PomodoroEngine(durations: .fast, clock: { clock.date }, defaults: nil)
        engine.start()
        #expect(LiveActivityPolicy.shouldShow(isRunning: engine.isRunning, segmentStartedAt: engine.segmentStartedAt))

        clock.advance(PomodoroDurations.fast.focus + 1)
        #expect(engine.tick() != nil)
        #expect(!LiveActivityPolicy.shouldShow(isRunning: engine.isRunning, segmentStartedAt: engine.segmentStartedAt))
    }
}
