import SwiftUI

struct HeaderView: View {
    let palette: Palette
    let mode: TimerMode
    let sessionsToday: Int
    let syncStatus: SyncCoordinator.Status

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("~/focus ").foregroundStyle(palette.accent)
                Text("$ ").foregroundStyle(palette.dim)
                Text("pomodoro").foregroundStyle(palette.text)
                cursor
            }
            .font(Theme.mono(17, .bold, relativeTo: .headline))

            HStack(spacing: 14) {
                Text("[ \(mode.label) ]")
                    .foregroundStyle(palette.accent)
                    .contentTransition(.opacity)
                Text("◆ \(sessionsToday) today")
                    .foregroundStyle(palette.dim)
                    .contentTransition(.numericText())
                Spacer()
                Text(syncLabel)
                    .foregroundStyle(syncStatus == .offline ? Color(hex: 0xE0786A) : palette.dim)
            }
            .font(Theme.mono(12, relativeTo: .caption))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cursor: some View {
        let block = Text("▌").foregroundStyle(palette.accent)
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
