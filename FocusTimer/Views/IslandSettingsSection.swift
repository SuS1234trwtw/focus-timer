import SwiftUI

/// Settings → which buttons the Dynamic Island and lock-screen banner show (lock screen only on
/// iPhones without an island). A `Section` meant to sit
/// inside `SettingsSheet`'s `Form`, styled the same way.
struct IslandSettingsSection: View {
    /// The sheet's palette (its `style` picks the header format).
    let palette: Palette

    @AppStorage(IslandSettings.Key.buttons) private var buttons = IslandSettings.Default.buttons
    @AppStorage(IslandSettings.Key.pauseButton) private var pauseButton = IslandSettings.Default.pauseButton
    @AppStorage(IslandSettings.Key.switchButton) private var switchButton = IslandSettings.Default.switchButton
    @AppStorage(IslandSettings.Key.lockScreenButtons) private var lockScreenButtons = IslandSettings.Default.lockScreenButtons

    /// Without a Dynamic Island the lock screen is the only place the buttons show, so one master
    /// toggle drives both "buttons" and "buttons on lock screen".
    private var hasIsland: Bool { DeviceCapabilities.hasDynamicIsland }

    private var lockScreenOnly: Binding<Bool> {
        Binding(get: { buttons && lockScreenButtons },
                set: { buttons = $0; lockScreenButtons = $0 })
    }

    private var enabled: Bool { hasIsland ? buttons : buttons && lockScreenButtons }

    var body: some View {
        Section {
            if hasIsland {
                Toggle("island buttons", isOn: $buttons)
            } else {
                Toggle("lock screen buttons", isOn: lockScreenOnly)
            }
            Group {
                Toggle("pause button", isOn: $pauseButton)
                Toggle("switch mode button", isOn: $switchButton)
                if hasIsland {
                    Toggle("buttons on lock screen", isOn: $lockScreenButtons)
                }
            }
            .padding(.leading, 16)
            .disabled(!enabled)
            .foregroundStyle(enabled ? palette.text : palette.dim)
        } header: {
            Text(palette.style.sectionHeader(hasIsland ? "island buttons" : "lock screen buttons"))
                .font(palette.mono(12, .bold, relativeTo: .caption))
                .foregroundStyle(palette.accent)
        } footer: {
            Text(hasIsland
                 ? "The Dynamic Island and lock-screen timer show while a block is running or paused, and disappear when the timer is idle or the app is closed. Its pause and focus/break buttons only show while the timer is running."
                 : "The lock-screen timer shows while a block is running or paused, and disappears when the timer is idle or the app is closed. Its pause and focus/break buttons only show while the timer is running.")
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
