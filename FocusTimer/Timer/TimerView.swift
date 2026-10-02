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

            if palette.style.isFlat {
                LineProgressBar(progress: engine.progress, palette: palette)
            } else {
                AsciiProgressBar(progress: engine.progress, palette: palette)
            }

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
        .background(palette.surface.opacity(0.55), in: .rect(cornerRadius: palette.style.radius(10)))
        .overlay(RoundedRectangle(cornerRadius: palette.style.radius(10)).strokeBorder(palette.border, lineWidth: 1))
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
                    let name = palette.style.isFlat ? mode.label.uppercased() : mode.label.lowercased()
                    Text(selected ? "[\(name)]" : " \(name) ")
                        .font(palette.mono(palette.style.isFlat ? 12 : 14, selected ? .bold : .regular, relativeTo: .subheadline))
                        .tracking(palette.style.labelTracking)
                        .foregroundStyle(selected ? palette.accent : palette.dim)
                }
                .buttonStyle(.plain)
                .disabled(selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if palette.style.isFlat {
            HStack(spacing: 10) {
                FlatButton(title: "start", palette: palette, prominent: true, action: onStart)
                    .disabled(engine.isRunning)
                FlatButton(title: "pause", palette: palette, prominent: false, action: onPause)
                    .disabled(!engine.isRunning)
                FlatButton(title: "reset", palette: palette, prominent: false, action: onReset)
            }
        } else {
            glassControls
        }
    }

    private var glassControls: some View {
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

/// The website's button: a square hairline box with a spaced uppercase label; the prominent one is
/// solid ink. Pressing flips it, like the site's hover.
private struct FlatButton: View {
    let title: String
    let palette: Palette
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(palette.mono(12, .bold, relativeTo: .body))
                .tracking(1.6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(FlatButtonStyle(palette: palette, prominent: prominent))
    }
}

private struct FlatButtonStyle: ButtonStyle {
    let palette: Palette
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let filled = prominent != configuration.isPressed
        configuration.label
            .foregroundStyle(filled ? palette.background : palette.text)
            .background(filled ? palette.text : Color.clear)
            .overlay(Rectangle().strokeBorder(filled ? palette.text : palette.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.32)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The website's meter: a hairline box with a solid fill and the percentage after it.
private struct LineProgressBar: View {
    let progress: Double
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: max(0, (proxy.size.width - 4) * progress))
                    .padding(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.4), value: progress)
            }
            .frame(height: 12)
            .overlay(Rectangle().strokeBorder(palette.border, lineWidth: 1))
            Text(String(format: "%3ld%%", Int(progress * 100)))
                .font(palette.mono(12, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(palette.dim)
        }
        .accessibilityHidden(true)
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
