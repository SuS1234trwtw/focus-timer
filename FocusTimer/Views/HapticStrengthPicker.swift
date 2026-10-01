import SwiftUI

/// The `haptic strength` row in Settings → feedback. Plays the start pattern on change as a preview.
struct HapticStrengthPicker: View {
    let palette: Palette

    @AppStorage(Feedback.Key.hapticStrength) private var strength: HapticStrength = .default
    @AppStorage(Feedback.Key.haptics) private var hapticsEnabled = true

    var body: some View {
        HStack(spacing: 12) {
            Text("haptic strength")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Picker("haptic strength", selection: $strength) {
                ForEach(HapticStrength.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .font(palette.mono(15, relativeTo: .body))
        .foregroundStyle(hapticsEnabled ? palette.text : palette.dim)
        .disabled(!hapticsEnabled)
        .onChange(of: strength) { Feedback.play(.start) }
        .accessibilityElement(children: .contain)
    }
}
