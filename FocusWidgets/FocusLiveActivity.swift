import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock-screen banner and Dynamic Island for a running or paused block.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenBanner(state: context.state, prompt: context.attributes.prompt, isStale: context.isStale)
                .activityBackgroundTint(Color(hexString: context.state.backgroundHex))
                .activitySystemActionForegroundColor(Color(hexString: context.state.accentHex) ?? .orange)
        } dynamicIsland: { context in
            let state = context.state
            let accent = Color(hexString: state.accentHex) ?? .orange
            let text = Color(hexString: state.textHex) ?? .white
            let dim = Color(hexString: state.dimHex) ?? .gray
            let isStale = context.isStale

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.modeLabel, systemImage: state.mode == "focus" ? "brain.head.profile" : "cup.and.saucer.fill")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(text)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let task = state.taskTitle {
                            Text("> \(task)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(text)
                                .lineLimit(1)
                        }
                        if let track = state.trackLine {
                            Label(track, systemImage: "music.note")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(dim)
                                .lineLimit(1)
                        }
                        ProgressBar(state: state, accent: accent, track: dim.opacity(0.35))
                        Controls(state: state, accent: accent, isStale: isStale, lockScreen: false)
                    }
                }
            } compactLeading: {
                // Left of the island: which block this is.
                Text(state.modeLabel)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(accent)
                    .padding(.leading, 2)
            } compactTrailing: {
                // Right of the island: the time left.
                Countdown(state: state)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.isRunning ? text : dim)
                    .frame(maxWidth: 48, alignment: .trailing)
            } minimal: {
                ProgressRing(state: state, accent: accent)
            }
            .keylineTint(accent)
            .widgetURL(URL(string: "focustimer://open"))
        }
    }
}

/// `PS C:\focus> 24:13` with the task, song, progress and controls, in the style's colours.
private struct LockScreenBanner: View {
    let state: FocusActivityAttributes.ContentState
    let prompt: String
    let isStale: Bool

    var body: some View {
        let accent = Color(hexString: state.accentHex) ?? .orange
        let text = Color(hexString: state.textHex) ?? .white
        let dim = Color(hexString: state.dimHex) ?? .gray

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // On island-less iPhones this banner is the whole Live Activity, so keep the header on
                // one line on narrow (SE-size) screens: the prompt gives way before the countdown.
                Text(prompt).foregroundStyle(dim).lineLimit(1).minimumScaleFactor(0.7)
                Text("[ \(state.modeLabel) ]").foregroundStyle(accent).fontWeight(.bold).lineLimit(1).layoutPriority(1)
                Spacer()
                Countdown(state: state)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .layoutPriority(2)
            }
            .font(.system(.footnote, design: .monospaced))

            if let task = state.taskTitle {
                Text("> focusing on: \(task)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(text)
                    .lineLimit(1)
            }
            if let track = state.trackLine {
                Label(track, systemImage: "music.note")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(dim)
                    .lineLimit(1)
            }
            ProgressBar(state: state, accent: accent, track: dim.opacity(0.35))
            Controls(state: state, accent: accent, isStale: isStale, lockScreen: true)
        }
        .padding(16)
    }
}

/// Counts down by itself while running (no app wake-ups); frozen while paused.
private struct Countdown: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        // Read the clock once: checking `end > .now` and then building `Date.now...end` can straddle
        // `end` and produce a backwards range, which traps and blanks the whole island.
        let now = Date.now
        if let end = state.endDate {
            if end > now {
                Text(timerInterval: now...end, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            } else {
                Text("00:00").monospacedDigit()
            }
        } else {
            Text(Duration.seconds(state.remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit()
        }
    }
}

private struct ProgressBar: View {
    let state: FocusActivityAttributes.ContentState
    let accent: Color
    let track: Color

    var body: some View {
        Group {
            if let end = state.endDate, end > .now {
                ProgressView(timerInterval: end.addingTimeInterval(-state.total)...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: max(0, min(1, 1 - state.remaining / max(state.total, 1))))
            }
        }
        .progressViewStyle(.linear)
        .tint(accent)
        .background(track, in: .capsule)
    }
}

private struct ProgressRing: View {
    let state: FocusActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        if let end = state.endDate, end > .now {
            ProgressView(timerInterval: end.addingTimeInterval(-state.total)...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(accent)
        } else {
            if state.hasStarted {
                Image(systemName: "pause.fill").foregroundStyle(accent)
            } else {
                Text(state.mode == "focus" ? "F" : "B")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(accent)
            }
        }
    }
}

/// Pause and focus ↔ break, handled by the app via Live Activity intents. Shown only while the timer
/// is ticking and the app is alive (see `ContentState.showsControls`), and only the buttons the user
/// enabled; a paused, finished or orphaned island shows no buttons at all.
private struct Controls: View {
    let state: FocusActivityAttributes.ContentState
    let accent: Color
    /// Past the stale date, which the app sets to `endDate`: the block has run out.
    let isStale: Bool
    let lockScreen: Bool

    var body: some View {
        if state.showsControls(now: .now, isStale: isStale, lockScreen: lockScreen) {
            HStack(spacing: 10) {
                // Only shown while running, so it's always "pause".
                if state.showsToggle {
                    Button(intent: ToggleTimerIntent()) {
                        Label("pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                // Focus ↔ break, and the new block starts straight away.
                if state.showsSwitch {
                    Button(intent: SwitchModeIntent()) {
                        Label(state.mode == "focus" ? "break" : "focus",
                              systemImage: state.mode == "focus" ? "cup.and.saucer.fill" : "brain.head.profile")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .buttonStyle(.bordered)
            .tint(accent)
        }
    }
}
