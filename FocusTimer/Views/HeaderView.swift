import SwiftUI

struct HeaderView: View {
    let palette: Palette
    let mode: TimerMode
    let sessionsToday: Int
    let syncStatus: SyncCoordinator.Status
    let onSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                if let host = palette.style.promptHost {
                    Text(host).foregroundStyle(palette.style.promptHostColor)
                }
                Text(palette.style.promptPath).foregroundStyle(palette.accent)
                Text(palette.style.promptSymbol).foregroundStyle(palette.dim)
                Text(palette.style.command).foregroundStyle(palette.text)
                cursor
                Spacer(minLength: 8)
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.dim)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .font(palette.mono(17, .bold, relativeTo: .headline))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            HStack(spacing: 14) {
                Text(palette.style.label("[ \(mode.label) ]"))
                    .foregroundStyle(palette.accent)
                    .contentTransition(.opacity)
                Text(palette.style.label("◆ \(sessionsToday) today"))
                    .foregroundStyle(palette.dim)
                    .contentTransition(.numericText())
                Spacer()
                Text(palette.style.label(syncLabel))
                    .foregroundStyle(syncStatus == .offline ? Color(hex: 0xE0786A) : palette.dim)
            }
            .font(palette.mono(palette.style.isFlat ? 10.5 : 12, relativeTo: .caption))
            .tracking(palette.style.labelTracking)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var cursor: some View {
        let block = Text(palette.style.cursor).foregroundStyle(palette.accent)
        if reduceMotion {
            block
        } else {
            block.phaseAnimator([1.0, 0.0]) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.55)
            }
        }
    }

    private var syncLabel: String {
        switch syncStatus {
        case .localOnly: "○ local"
        case .idle: "○ idle"
        case .syncing: "◌ syncing"
        case .synced: "● synced"
        case .offline: "✕ offline"
        }
    }
}
