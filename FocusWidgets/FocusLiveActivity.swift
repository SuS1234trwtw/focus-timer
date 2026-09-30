import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock-screen banner and Dynamic Island for a running or paused block.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenBanner(state: context.state, prompt: context.attributes.prompt)
                .activityBackgroundTint(Color(hexString: context.state.backgroundHex))
                .activitySystemActionForegroundColor(Color(hexString: context.state.accentHex) ?? .orange)
        } dynamicIsland: { context in
            let state = context.state
            let accent = Color(hexString: state.accentHex) ?? .orange
            let text = Color(hexString: state.textHex) ?? .white
            let dim = Color(hexString: state.dimHex) ?? .gray

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
                        Controls(state: state, accent: accent)
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

    var body: some View {
        let accent = Color(hexString: state.accentHex) ?? .orange
        let text = Color(hexString: state.textHex) ?? .white
        let dim = Color(hexString: state.dimHex) ?? .gray

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(prompt).foregroundStyle(dim)
                Text("[ \(state.modeLabel) ]").foregroundStyle(accent).fontWeight(.bold)
                Spacer()
                Countdown(state: state)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(text)
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
            Controls(state: state, accent: accent)
        }
        .padding(16)
    }
}

/// Counts down by itself while running (no app wake-ups); frozen while paused.
private struct Countdown: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        if let end = state.endDate, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
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

/// Pause / resume and skip, handled by the app via Live Activity intents.
private struct Controls: View {
    let state: FocusActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            // Pause while running; otherwise start (fresh block) or resume (paused block).
            Button(intent: ToggleTimerIntent()) {
                Label(toggleTitle, systemImage: state.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            // Focus ↔ break, and the new block starts straight away.
            Button(intent: SwitchModeIntent()) {
                Label(state.mode == "focus" ? "break" : "focus",
                      systemImage: state.mode == "focus" ? "cup.and.saucer.fill" : "brain.head.profile")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(.caption, design: .monospaced).weight(.bold))
        .buttonStyle(.bordered)
        .tint(accent)
    }

    private var toggleTitle: String {
        if state.isRunning { return "pause" }
        return state.hasStarted ? "resume" : "start"
    }
}
