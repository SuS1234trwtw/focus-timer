import Foundation
import Testing
@testable import FocusTimer

struct HistoryMathTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // monday
        return c
    }()

    /// Fri 3 Oct 2025, 15:00 UTC.
    var now: Date { date(2025, 10, 3, 15, 0) }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func block(_ start: Date, minutes: Int, focus: Bool = true) -> HistoryEntry {
        HistoryEntry(taskID: nil, isFocus: focus, startedAt: start,
                     endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)), durationSec: minutes * 60)
    }

    var sample: [HistoryEntry] {
        [
            block(date(2025, 10, 3, 9, 0), minutes: 25),
            block(date(2025, 10, 3, 9, 25), minutes: 5, focus: false),
            block(date(2025, 10, 3, 10, 0), minutes: 50),
            block(date(2025, 10, 2, 9, 0), minutes: 25),   // yesterday, same week
            block(date(2025, 9, 28, 9, 0), minutes: 25),   // sunday: previous week
            block(date(2025, 9, 20, 9, 0), minutes: 25),   // outside the 7 days
        ]
    }

    @Test func totalsCountFocusOnly() {
        let totals = HistoryMath.totals(sample, now: now, calendar: calendar)
        #expect(totals.today == 75 * 60)
        #expect(totals.week == 100 * 60)
    }

    @Test func lastSevenDaysOldestFirst() {
        let series = HistoryMath.lastSevenDays(sample, now: now, calendar: calendar)
        #expect(series.count == 7)
        #expect(series.first?.day == date(2025, 9, 27, 0, 0))
        #expect(series.last?.day == date(2025, 10, 3, 0, 0))
        #expect(series.map { $0.seconds / 60 } == [0, 25, 0, 0, 0, 25, 75])
    }

    @Test func groupsNewestDayFirst() {
        let days = HistoryMath.groupedByDay(sample, calendar: calendar)
        #expect(days.map(\.day) == [date(2025, 10, 3, 0, 0), date(2025, 10, 2, 0, 0),
                                    date(2025, 9, 28, 0, 0), date(2025, 9, 20, 0, 0)])
        #expect(days.first?.entries.map(\.durationSec) == [50 * 60, 5 * 60, 25 * 60])
    }

    @Test func dayTitles() {
        #expect(HistoryMath.dayTitle(date(2025, 10, 3, 0, 0), now: now, calendar: calendar) == "today")
        #expect(HistoryMath.dayTitle(date(2025, 10, 2, 0, 0), now: now, calendar: calendar) == "yesterday")
        #expect(HistoryMath.dayTitle(date(2025, 9, 29, 0, 0), now: now, calendar: calendar) == "mon 29 sep")
    }

    @Test func formatting() {
        #expect(HistoryMath.duration(25 * 60) == "25m")
        #expect(HistoryMath.duration(75 * 60) == "1h 15m")
        #expect(HistoryMath.timeRange(block(date(2025, 10, 3, 9, 0), minutes: 25), calendar: calendar) == "09:00–09:25")
    }
}
