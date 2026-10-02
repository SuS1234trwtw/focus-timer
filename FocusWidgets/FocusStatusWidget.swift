import SwiftUI
import WidgetKit

struct FocusEntry: TimelineEntry {
    let date: Date
    /// nil when the App Group isn't reachable (e.g. stripped by sideload signing) or nothing was saved yet.
    let snapshot: TimerSnapshot?
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(FocusEntry(date: .now, snapshot: TimerSnapshot.load() ?? Self.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let snapshot = TimerSnapshot.load()
        let entry = FocusEntry(date: .now, snapshot: snapshot)
        // Re-render when a running block ends so the widget stops showing 0:00.
        if let end = snapshot?.endDate, end > .now {
            completion(Timeline(entries: [entry], policy: .after(end.addingTimeInterval(1))))
        } else {
            completion(Timeline(entries: [entry], policy: .never))
        }
    }

    static let sample = TimerSnapshot(
        mode: "focus", endDate: nil, remaining: 25 * 60, total: 25 * 60, taskTitle: "write the sync layer",
        style: "mono", prompt: "~/focus $", accentHex: "F5F5F2", backgroundHex: "050505",
        textHex: "F5F5F2", dimHex: "8C8C89", trackLine: nil
    )
}

/// Home screen (small/medium) and lock screen (circular/rectangular/inline) timer widget.
struct FocusStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusStatus", provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus timer")
        .description("The current focus or break block, in your terminal style.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .accessoryCircular: circular(snapshot)
                case .accessoryRectangular: rectangular(snapshot)
                case .accessoryInline: inline(snapshot)
                default: home(snapshot)
                }
            } else {
                launcher
            }
        }
        .widgetURL(URL(string: "focustimer://open"))
    }

    // MARK: Home screen

    private func home(_ s: TimerSnapshot) -> some View {
        let accent = Color(hexString: s.accentHex) ?? .orange
        let text = Color(hexString: s.textHex) ?? .white
        let dim = Color(hexString: s.dimHex) ?? .gray

        return VStack(alignment: .leading, spacing: 6) {
            Text(s.prompt)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
            Text("[ \(s.mode == "focus" ? "FOCUS" : "BREAK") ]")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(dim)
            Spacer(minLength: 0)
            countdown(s)
                .font(.system(size: family == .systemSmall ? 34 : 40, weight: .bold, design: .monospaced))
                .foregroundStyle(text)
                .minimumScaleFactor(0.6)
            if let task = s.taskTitle {
                Text("> \(task)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(text.opacity(0.85))
                    .lineLimit(family == .systemSmall ? 1 : 2)
            }
            if family == .systemMedium, let track = s.trackLine {
                Label(track, systemImage: "music.note")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(dim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(hexString: s.backgroundHex) ?? .black }
    }

    // MARK: Lock screen

    private func circular(_ s: TimerSnapshot) -> some View {
        let now = Date.now  // one read, so the range below can't come out backwards
        return Group {
            if let end = s.endDate, end > now {
                ProgressView(timerInterval: end.addingTimeInterval(-s.total)...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Text(timerInterval: now...end, countsDown: true)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
                .progressViewStyle(.circular)
            } else {
                Gauge(value: max(0, min(1, 1 - s.remaining / max(s.total, 1)))) {
                    Text(s.mode == "focus" ? "FOC" : "BRK")
                } currentValueLabel: {
                    Text("\(Int((s.remaining / 60).rounded(.up)))")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
        }
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    private func rectangular(_ s: TimerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(s.mode == "focus" ? "FOCUS" : "BREAK")\(s.isRunning ? "" : " · paused")")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
            countdown(s)
                .font(.system(.title3, design: .monospaced).weight(.bold))
            if let task = s.taskTitle {
                Text(task).font(.system(.caption2, design: .monospaced)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private func inline(_ s: TimerSnapshot) -> some View {
        HStack {
            Image(systemName: s.mode == "focus" ? "brain.head.profile" : "cup.and.saucer.fill")
            countdown(s)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: Pieces

    @ViewBuilder
    private func countdown(_ s: TimerSnapshot) -> some View {
        let now = Date.now  // one read, so the range below can't come out backwards
        if let end = s.endDate, end > now {
            Text(timerInterval: now...end, countsDown: true).monospacedDigit()
        } else {
            Text(Duration.seconds(s.remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
        }
    }

    /// Shown when the widget can't read the timer (no shared App Group after sideloading).
    private var launcher: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("~/focus $").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
            Spacer(minLength: 0)
            Text("tap to focus▌").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(hex: 0x1A1614) }
    }
}
