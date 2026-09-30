import Foundation
import Observation

enum TimerMode: String, Codable, Sendable {
    case focus
    case rest

    var label: String { self == .focus ? "FOCUS" : "BREAK" }
    var next: TimerMode { self == .focus ? .rest : .focus }
}

struct PomodoroDurations: Sendable, Equatable {
    var focus: TimeInterval
    var rest: TimeInterval

    static let standard = PomodoroDurations(focus: 25 * 60, rest: 5 * 60)
    static let fast = PomodoroDurations(focus: 10, rest: 5)

    /// Allowed lengths in the settings, in minutes.
    static let focusRange = 1...120
    static let restRange = 1...60

    init(focus: TimeInterval, rest: TimeInterval) {
        self.focus = focus
        self.rest = rest
    }

    init(focusMinutes: Int, restMinutes: Int) {
        self.focus = TimeInterval(min(max(focusMinutes, Self.focusRange.lowerBound), Self.focusRange.upperBound)) * 60
        self.rest = TimeInterval(min(max(restMinutes, Self.restRange.lowerBound), Self.restRange.upperBound)) * 60
    }

    func duration(for mode: TimerMode) -> TimeInterval {
        mode == .focus ? focus : rest
    }
}

/// A finished work or break block, reported by `tick()`.
struct CompletedSegment: Sendable, Equatable {
    let mode: TimerMode
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    /// How long after the end the app noticed (large when the app was backgrounded).
    let lateBy: TimeInterval
}

/// Countdown state machine. Time is derived from a stored end date rather than
/// counted ticks, so it stays correct across backgrounding and relaunches.
@MainActor
@Observable
final class PomodoroEngine {
    private(set) var mode: TimerMode = .focus
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval
    private(set) var segmentStartedAt: Date?
    private(set) var completedFocusCount = 0
    private(set) var now: Date

    private(set) var durations: PomodoroDurations

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let storageKey = "pomodoro.engine.v1"
    /// Length of the block in progress, fixed when it starts so mid-block setting changes don't rewrite it.
    @ObservationIgnored private var blockTotal: TimeInterval?

    init(durations: PomodoroDurations = .standard, clock: @escaping () -> Date = { Date() }, defaults: UserDefaults? = .standard) {
        self.durations = durations
        self.clock = clock
        self.defaults = defaults
        self.now = clock()
        self.pausedRemaining = durations.focus
        restore()
    }

    var isRunning: Bool { endDate != nil }

    var total: TimeInterval { durations.duration(for: mode) }

    var remaining: TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    func start() {
        guard endDate == nil else { return }
        now = clock()
        if segmentStartedAt == nil {
            segmentStartedAt = now
            blockTotal = pausedRemaining
        }
        endDate = now.addingTimeInterval(pausedRemaining)
        persist()
    }

    func pause() {
        guard let endDate else { return }
        now = clock()
        pausedRemaining = max(0, endDate.timeIntervalSince(now))
        self.endDate = nil
        persist()
    }

    func reset() {
        now = clock()
        endDate = nil
        pausedRemaining = total
        segmentStartedAt = nil
        blockTotal = nil
        persist()
    }

    /// Changes the block lengths. An idle block picks up the new length straight away;
    /// a running or paused block keeps its time and the change applies from the next block.
    func setDurations(_ newValue: PomodoroDurations) {
        guard newValue != durations else { return }
        durations = newValue
        if endDate == nil, segmentStartedAt == nil {
            pausedRemaining = total
        }
        persist()
    }

    func switchMode(to newMode: TimerMode) {
        mode = newMode
        reset()
    }

    /// Advances the clock. Returns the finished segment if the countdown just hit zero;
    /// the engine then flips to the other mode, paused and ready to start.
    @discardableResult
    func tick() -> CompletedSegment? {
        now = clock()
        guard let endDate, now >= endDate else { return nil }

        let segment = CompletedSegment(
            mode: mode,
            startedAt: segmentStartedAt ?? endDate.addingTimeInterval(-total),
            endedAt: endDate,
            duration: blockTotal ?? total,
            lateBy: now.timeIntervalSince(endDate)
        )
        if mode == .focus { completedFocusCount += 1 }
        mode = mode.next
        self.endDate = nil
        pausedRemaining = total
        segmentStartedAt = nil
        blockTotal = nil
        persist()
        return segment
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var mode: TimerMode
        var endDate: Date?
        var pausedRemaining: TimeInterval
        var segmentStartedAt: Date?
        var completedFocusCount: Int
        var countDay: Date
    }

    private func persist() {
        guard let defaults else { return }
        let snapshot = Snapshot(
            mode: mode,
            endDate: endDate,
            pausedRemaining: pausedRemaining,
            segmentStartedAt: segmentStartedAt,
            completedFocusCount: completedFocusCount,
            countDay: Calendar.current.startOfDay(for: now)
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard let data = defaults?.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        mode = snapshot.mode
        endDate = snapshot.endDate
        pausedRemaining = min(snapshot.pausedRemaining, durations.duration(for: snapshot.mode))
        segmentStartedAt = snapshot.segmentStartedAt
        // The session counter is per day.
        let sameDay = Calendar.current.isDate(snapshot.countDay, inSameDayAs: now)
        completedFocusCount = sameDay ? snapshot.completedFocusCount : 0
    }
}

extension TimeInterval {
    /// "MM:SS", rounding up so the display reads 25:00 at the start and 00:01 in the last second.
    var clockString: String {
        let seconds = Int(self.rounded(.up))
        return String(format: "%02ld:%02ld", seconds / 60, seconds % 60)
    }
}
