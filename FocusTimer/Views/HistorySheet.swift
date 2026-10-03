import Charts
import SwiftData
import SwiftUI

/// Past focus and break blocks: totals, a 7-day bar chart, and a day-by-day log.
struct HistorySheet: View {
    let palette: Palette

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FocusSessionRecord.startedAt, order: .reverse) private var records: [FocusSessionRecord]
    @Query private var tasks: [TaskItem]

    private var entries: [HistoryEntry] {
        records.map {
            HistoryEntry(id: $0.id, taskID: $0.taskID, isFocus: $0.mode == TimerMode.focus.rawValue,
                         startedAt: $0.startedAt, endedAt: $0.endedAt, durationSec: $0.durationSec)
        }
    }

    var body: some View {
        let entries = entries
        let now = Date.now
        let calendar = Calendar.current
        NavigationStack {
            Group {
                if entries.isEmpty {
                    Text("// no blocks yet. finish a focus block and it shows up here.")
                        .font(palette.mono(13, relativeTo: .footnote))
                        .foregroundStyle(palette.dim)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    log(entries, now: now, calendar: calendar)
                }
            }
            .background(palette.background)
            .navigationTitle("history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(palette.accent)
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.background)
    }

    private func log(_ entries: [HistoryEntry], now: Date, calendar: Calendar) -> some View {
        let totals = HistoryMath.totals(entries, now: now, calendar: calendar)
        let titles = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("today \(HistoryMath.duration(totals.today)) · this week \(HistoryMath.duration(totals.week))")
                        .font(palette.mono(13, .bold, relativeTo: .footnote))
                        .foregroundStyle(palette.text)
                    chart(HistoryMath.lastSevenDays(entries, now: now, calendar: calendar))
                }
                .listRowBackground(Color.clear)
            }

            ForEach(HistoryMath.groupedByDay(entries, calendar: calendar)) { day in
                Section {
                    ForEach(day.entries) { entry in
                        row(entry, title: entry.taskID.flatMap { titles[$0] }, calendar: calendar)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(HistoryMath.dayTitle(day.day, now: now, calendar: calendar))
                        .font(palette.mono(11, .bold, relativeTo: .caption))
                        .foregroundStyle(palette.dim)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func chart(_ series: [DayTotal]) -> some View {
        Chart(series) { item in
            BarMark(
                x: .value("day", item.day, unit: .day),
                y: .value("minutes", Double(item.seconds) / 60)
            )
            .foregroundStyle(palette.accent)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    Text(value.as(Date.self).map { HistoryMath.weekdayName($0, calendar: .current) } ?? "")
                        .font(palette.mono(10, relativeTo: .caption2))
                        .foregroundStyle(palette.dim)
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(palette.border)
                AxisValueLabel {
                    Text(value.as(Double.self).map { "\(Int($0))m" } ?? "")
                        .font(palette.mono(10, relativeTo: .caption2))
                        .foregroundStyle(palette.dim)
                }
            }
        }
        .frame(height: 120)
        .accessibilityLabel("focus minutes, last 7 days")
    }

    private func row(_ entry: HistoryEntry, title: String?, calendar: Calendar) -> some View {
        HStack(spacing: 10) {
            Text(HistoryMath.timeRange(entry, calendar: calendar))
            Text(entry.isFocus ? "focus" : "break")
                .foregroundStyle(entry.isFocus ? palette.accent : palette.dim)
            Text(HistoryMath.duration(entry.durationSec))
            if let title {
                Text("· \(title)").lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(palette.mono(13, relativeTo: .footnote))
        .foregroundStyle(entry.isFocus ? palette.text : palette.dim)
        .opacity(entry.isFocus ? 1 : 0.6)
    }
}

struct HistoryEntry: Identifiable, Equatable, Sendable {
    var id = UUID()
    var taskID: UUID?
    var isFocus: Bool
    var startedAt: Date
    var endedAt: Date
    var durationSec: Int
}

struct DayTotal: Identifiable, Equatable, Sendable {
    let day: Date
    let seconds: Int
    var id: Date { day }
}

struct HistoryDay: Identifiable, Equatable, Sendable {
    let day: Date
    let entries: [HistoryEntry]
    var id: Date { day }
}

/// Pure helpers behind `HistorySheet`. Blocks count toward the day they started on.
enum HistoryMath {
    private static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Focus seconds today and in the current calendar week.
    static func totals(_ entries: [HistoryEntry], now: Date, calendar: Calendar) -> (today: Int, week: Int) {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        var today = 0, thisWeek = 0
        for entry in entries where entry.isFocus {
            if calendar.isDate(entry.startedAt, inSameDayAs: now) { today += entry.durationSec }
            if week?.contains(entry.startedAt) == true { thisWeek += entry.durationSec }
        }
        return (today, thisWeek)
    }

    /// Focus seconds per day for the 7 days ending today, oldest first.
    static func lastSevenDays(_ entries: [HistoryEntry], now: Date, calendar: Calendar) -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: Int] = [:]
        for entry in entries where entry.isFocus {
            byDay[calendar.startOfDay(for: entry.startedAt), default: 0] += entry.durationSec
        }
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { DayTotal(day: $0, seconds: byDay[$0] ?? 0) }
        }
    }

    /// Days newest first, each day's blocks newest first.
    static func groupedByDay(_ entries: [HistoryEntry], calendar: Calendar) -> [HistoryDay] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt) }
            .map { HistoryDay(day: $0.key, entries: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    /// "today", "yesterday", or e.g. "mon 29 sep".
    static func dayTitle(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "yesterday" }
        let c = calendar.dateComponents([.day, .month], from: day)
        return "\(weekdayName(day, calendar: calendar)) \(c.day ?? 0) \(months[(c.month ?? 1) - 1])"
    }

    static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        weekdays[calendar.component(.weekday, from: date) - 1]
    }

    /// "09:00–09:25"
    static func timeRange(_ entry: HistoryEntry, calendar: Calendar) -> String {
        "\(clock(entry.startedAt, calendar))–\(clock(entry.endedAt, calendar))"
    }

    /// "25m", "1h 15m"
    static func duration(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
