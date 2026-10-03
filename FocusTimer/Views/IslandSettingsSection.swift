import SwiftUI

/// Settings → which buttons the Dynamic Island and lock-screen banner show. A `Section` meant to sit
/// inside `SettingsSheet`'s `Form`, styled the same way.
struct IslandSettingsSection: View {
    /// The sheet's palette (its `style` picks the header format).
    let palette: Palette

    @AppStorage(IslandSettings.Key.buttons) private var buttons = IslandSettings.Default.buttons
    @AppStorage(IslandSettings.Key.pauseButton) private var pauseButton = IslandSettings.Default.pauseButton
    @AppStorage(IslandSettings.Key.switchButton) private var switchButton = IslandSettings.Default.switchButton
    @AppStorage(IslandSettings.Key.lockScreenButtons) private var lockScreenButtons = IslandSettings.Default.lockScreenButtons

    var body: some View {
        Section {
            Toggle("island buttons", isOn: $buttons)
            Group {
                Toggle("pause button", isOn: $pauseButton)
                Toggle("switch mode button", isOn: $switchButton)
                Toggle("buttons on lock screen", isOn: $lockScreenButtons)
            }
            .padding(.leading, 16)
            .disabled(!buttons)
            .foregroundStyle(buttons ? palette.text : palette.dim)
        } header: {
            Text(palette.style.sectionHeader("island buttons"))
                .font(palette.mono(12, .bold, relativeTo: .caption))
                .foregroundStyle(palette.accent)
        } footer: {
            Text("The Dynamic Island and lock-screen timer show while a block is running or paused, and disappear when the timer is idle or the app is closed. Its pause and focus/break buttons only show while the timer is running.")
                .font(palette.mono(11, relativeTo: .caption))
                .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
        .onChange(of: [buttons, pauseButton, switchButton, lockScreenButtons]) {
            Feedback.play(.tap)
            AppModel.shared.refreshLiveActivity()
        }
    }
}
