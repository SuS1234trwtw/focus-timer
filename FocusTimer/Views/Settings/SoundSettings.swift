import SwiftUI

/// Settings → sound & haptics: clicks, buzzes, the per-second tick, and the boot animation.
struct SoundSettingsPage: View {
    let palette: Palette

    @AppStorage(Feedback.Key.sounds) private var soundsEnabled = true
    @AppStorage(Feedback.Key.haptics) private var hapticsEnabled = true
    @AppStorage(Feedback.Key.tickSound) private var tickSound = true
    @AppStorage(Feedback.Key.tickHaptics) private var tickHaptics = true
    @AppStorage(BootView.enabledKey) private var bootAnimation = true
    /// Re-read on appear so a pick made on the picker page shows when coming back.
    @State private var choices: [SoundMoment: SoundChoice] = [:]

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

            Section {
                ForEach(SoundMoment.allCases) { moment in
                    NavigationLink {
                        SoundPickerPage(palette: palette, moment: moment)
                    } label: {
                        LabeledContent {
                            Text(choices[moment]?.name ?? "")
                                .font(palette.mono(13, relativeTo: .footnote))
                                .foregroundStyle(palette.dim)
                                .lineLimit(1)
                        } label: {
                            Text(moment.label)
                                .foregroundStyle(palette.text)
                        }
                    }
                }
            } header: {
                SettingsHeader("sounds", palette: palette)
            } footer: {
                SettingsFooter("What plays when a block starts or ends. End sounds ring even on silent and in the notification when the app is closed.", palette: palette)
            }
            .listRowBackground(palette.surface)
        }
        .settingsFormStyle(palette)
        .onAppear {
            choices = Dictionary(uniqueKeysWithValues: SoundMoment.allCases.map { ($0, SoundBoard.choice(for: $0)) })
        }
        .navigationTitle("sound & haptics")
        .navigationBarTitleDisplayMode(.inline)
        // A soft key click for every change made here.
        .onChange(of: [soundsEnabled, hapticsEnabled, tickSound, tickHaptics]) { Feedback.play(.tap) }
    }
}
