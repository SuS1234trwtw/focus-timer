import Foundation
import Observation

enum TimerMode: String, Codable, Sendable {
    case focus
    case rest

    var label: String { self == .focus ? "focus" : "break" }
    var next: TimerMode { self == .focus ? .rest : .focus }
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
///
/// idle → running ⇄ paused → overtime (counting up past zero) → `advance()` → idle in the next mode.
@MainActor
@Observable
final class PomodoroEngine {
    nonisolated static let minuteRange = 1...90

    private(set) var mode: TimerMode = .focus
    private(set) var focusMinutes = 25
    private(set) var restMinutes = 5
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval
    private(set) var segmentStartedAt: Date?
    /// Set when the countdown hits zero; the UI counts up from here until `advance()`.
    private(set) var finishedAt: Date?
    private(set) var completedFocusCount = 0
    private(set) var now: Date
    /// The big number on screen: whole minutes left, rounded up (44:00 and 43:59 both read "44").
    /// Stored, and only reassigned when it changes, so views reading it don't redraw on every tick.
    private(set) var displayMinutes = 25

    /// Seconds per "minute". 60 normally; 1 with `-fastTimer` so a 25 block lasts 25s.
    let unit: TimeInterval

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let storageKey = "pomodoro.engine.v2"

    init(unit: TimeInterval = 60, clock: @escaping () -> Date = { Date() }, defaults: UserDefaults? = .standard) {
        self.unit = unit
        self.clock = clock
        self.defaults = defaults
        self.now = clock()
        self.pausedRemaining = 25 * unit
        restore()
        refreshDisplay()
    }

    var isRunning: Bool { endDate != nil }
    var isOvertime: Bool { finishedAt != nil }
    /// Started at some point in this block (running or paused part-way).
    var isInProgress: Bool { segmentStartedAt != nil }

    func minutes(for mode: TimerMode) -> Int {
        mode == .focus ? focusMinutes : restMinutes
    }

    var total: TimeInterval { TimeInterval(minutes(for: mode)) * unit }

    var remaining: TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining
    }

    var overtime: TimeInterval {
        finishedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
    }

    private func refreshDisplay() {
        let value = isInProgress ? max(1, Int((remaining / unit).rounded(.up))) : minutes(for: mode)
        if value != displayMinutes { displayMinutes = value }
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    /// Sets a block length. Applied immediately if that mode is idle or paused; otherwise used next time.
    func setMinutes(_ minutes: Int, for target: TimerMode? = nil) {
        let target = target ?? mode
        let clamped = min(max(minutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        switch target {
        case .focus: focusMinutes = clamped
        case .rest: restMinutes = clamped
        }
        if target == mode, !isRunning, !isOvertime {
            pausedRemaining = total
            segmentStartedAt = nil
        }
        persist()
    }

    func start() {
        guard endDate == nil, !isOvertime else { return }
        now = clock()
        if segmentStartedAt == nil { segmentStartedAt = now }
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
        finishedAt = nil
        pausedRemaining = total
        segmentStartedAt = nil
        persist()
    }

    func switchMode(to newMode: TimerMode) {
        mode = newMode
        reset()
    }

    /// Leaves overtime and readies the other mode (idle, not started).
    func advance() {
        mode = mode.next
        reset()
    }

    /// Advances the clock. Returns the finished segment if the countdown just hit zero;
    /// the engine then enters overtime until `advance()`.
    @discardableResult
    func tick() -> CompletedSegment? {
        now = clock()
        refreshDisplay()
        guard let endDate, now >= endDate else { return nil }

        let segment = CompletedSegment(
            mode: mode,
            startedAt: segmentStartedAt ?? endDate.addingTimeInterval(-total),
            endedAt: endDate,
            duration: total,
            lateBy: now.timeIntervalSince(endDate)
        )
        if mode == .focus { completedFocusCount += 1 }
        finishedAt = endDate
        self.endDate = nil
        pausedRemaining = 0
        persist()
        return segment
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var mode: TimerMode
        var focusMinutes: Int?
        var restMinutes: Int?
        var endDate: Date?
        var pausedRemaining: TimeInterval
        var segmentStartedAt: Date?
        var finishedAt: Date?
        var completedFocusCount: Int
        var countDay: Date
    }

    private func persist() {
        refreshDisplay()
        guard let defaults else { return }
        let snapshot = Snapshot(
            mode: mode,
            focusMinutes: focusMinutes,
            restMinutes: restMinutes,
            endDate: endDate,
            pausedRemaining: pausedRemaining,
            segmentStartedAt: segmentStartedAt,
            finishedAt: finishedAt,
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
        focusMinutes = snapshot.focusMinutes ?? focusMinutes
        restMinutes = snapshot.restMinutes ?? restMinutes
        endDate = snapshot.endDate
        pausedRemaining = min(snapshot.pausedRemaining, total)
        segmentStartedAt = snapshot.segmentStartedAt
        finishedAt = snapshot.finishedAt
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

    /// "MM:SS:hh" for the overtime count-up.
    var stopwatchString: String {
        let hundredths = Int((self * 100).rounded())
        return String(format: "%02ld:%02ld:%02ld", hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }
}
