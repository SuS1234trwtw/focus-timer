import SwiftUI

struct TimerView: View {
    @Environment(PomodoroEngine.self) private var engine

    let palette: Palette
    let activeTaskTitle: String?
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void
    let onSwitch: (TimerMode) -> Void

    var body: some View {
        VStack(spacing: 20) {
            modeTabs

            Text(engine.remaining.clockString)
                .font(palette.mono(96, .light, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.3), value: engine.remaining.clockString)
                .accessibilityLabel("\(Int(engine.remaining.rounded(.up)) / 60) minutes \(Int(engine.remaining.rounded(.up)) % 60) seconds remaining")

            AsciiProgressBar(progress: engine.progress, palette: palette)

            Text(focusLine)
                .font(palette.mono(13, relativeTo: .footnote))
                .foregroundStyle(palette.dim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)

            controls
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(palette.surface.opacity(0.55), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.border, lineWidth: 1))
    }

    private var focusLine: String {
        switch engine.mode {
        case .focus: "\(palette.style.linePrefix)focusing on: \(activeTaskTitle ?? "—")"
        case .rest: "\(palette.style.linePrefix)stretch. hydrate. look away."
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 18) {
            ForEach([TimerMode.focus, .rest], id: \.self) { mode in
                let selected = engine.mode == mode
                Button {
                    onSwitch(mode)
                } label: {
                    Text(selected ? "[\(mode.label.lowercased())]" : " \(mode.label.lowercased()) ")
                        .font(palette.mono(14, selected ? .bold : .regular, relativeTo: .subheadline))
                        .foregroundStyle(selected ? palette.accent : palette.dim)
                }
                .buttonStyle(.plain)
                .disabled(selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ControlButton(title: "start", systemImage: "play.fill", palette: palette, prominent: true, action: onStart)
                    .disabled(engine.isRunning)
                ControlButton(title: "pause", systemImage: "pause.fill", palette: palette, prominent: false, action: onPause)
                    .disabled(!engine.isRunning)
                ControlButton(title: "reset", systemImage: "arrow.counterclockwise", palette: palette, prominent: false, action: onReset)
            }
        }
    }
}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    let palette: Palette
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        let label = Label(title, systemImage: systemImage)
            .font(palette.mono(15, .bold, relativeTo: .body))
            .frame(maxWidth: .infinity, minHeight: 30)

        if prominent {
            Button(action: action) { label.foregroundStyle(palette.accent.isDark ? Color(hex: 0xF5F5F5) : Color(hex: 0x1A1614)) }
                .buttonStyle(.glassProminent)
                .tint(palette.accent)
        } else {
            Button(action: action) { label.foregroundStyle(palette.accent) }
                .buttonStyle(.glass)
        }
    }
}

/// `[██████████░░░░░░░░░░]  42%`
private struct AsciiProgressBar: View {
    let progress: Double
    let palette: Palette
    private let cells = 20

    var body: some View {
        let filled = Int((progress * Double(cells)).rounded(.down))
        HStack(spacing: 0) {
            Text("[").foregroundStyle(palette.dim)
            Text(String(repeating: "█", count: filled)).foregroundStyle(palette.accent)
            Text(String(repeating: "░", count: cells - filled)).foregroundStyle(palette.border)
            Text("]").foregroundStyle(palette.dim)
            Text(String(format: " %3ld%%", Int(progress * 100))).foregroundStyle(palette.dim)
        }
        .font(palette.mono(13, relativeTo: .footnote))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityHidden(true)
    }
}
