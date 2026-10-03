import SwiftUI

/// Settings → sound & haptics: clicks, buzzes, the per-second tick, and the boot animation.
struct SoundSettingsPage: View {
    let palette: Palette

    @AppStorage(Feedback.Key.sounds) private var soundsEnabled = true
    @AppStorage(Feedback.Key.haptics) private var hapticsEnabled = true
    @AppStorage(Feedback.Key.tickSound) private var tickSound = true
    @AppStorage(Feedback.Key.tickHaptics) private var tickHaptics = true
    @AppStorage(BootView.enabledKey) private var bootAnimation = true

    var body: some View {
        Form {
            Section {
                Toggle("sounds", isOn: $soundsEnabled)
                Toggle("haptics", isOn: $hapticsEnabled)
                HapticStrengthPicker(palette: palette)
                Toggle("tick sound", isOn: $tickSound)
                    .disabled(!soundsEnabled)
                Toggle("tick haptics", isOn: $tickHaptics)
                    .disabled(!hapticsEnabled)
                Toggle("boot animation", isOn: $bootAnimation)
            } header: {
                SettingsHeader("feedback", palette: palette)
            } footer: {
                SettingsFooter("Clicks and beeps for start, pause, reset, tasks and settings, plus a tick every second while running. Haptic strength sets how hard the buzzes hit. Sounds follow the silent switch; the end-of-block chime doesn't. Boot animation is the terminal start-up screen when the app opens.", palette: palette)
            }
            .listRowBackground(palette.surface)
        }
        .settingsFormStyle(palette)
        .navigationTitle("sound & haptics")
        .navigationBarTitleDisplayMode(.inline)
        // A soft key click for every change made here.
        .onChange(of: [soundsEnabled, hapticsEnabled, tickSound, tickHaptics]) { Feedback.play(.tap) }
    }
}
