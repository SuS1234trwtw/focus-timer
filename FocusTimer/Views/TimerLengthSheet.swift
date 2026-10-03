import SwiftUI

/// The focus and break lengths: preset chips and steppers. Opened by tapping the idle clock.
struct TimerLengthSheet: View {
    let palette: Palette

    @Environment(\.dismiss) private var dismiss
    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("restMinutes") private var restMinutes = 5

    struct Preset: Hashable, Sendable {
        let focus: Int
        let rest: Int
    }

    nonisolated static let presets = [Preset(focus: 25, rest: 5), Preset(focus: 50, rest: 10), Preset(focus: 15, rest: 3), Preset(focus: 90, rest: 20)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        ForEach(Self.presets, id: \.self) { preset in
                            presetChip(preset)
                        }
                    }
                    Stepper(value: $focusMinutes, in: PomodoroDurations.focusRange) {
                        LabeledContent("focus", value: "\(focusMinutes) min")
                    }
                    Stepper(value: $restMinutes, in: PomodoroDurations.restRange) {
                        LabeledContent("break", value: "\(restMinutes) min")
                    }
                } footer: {
                    Text("an idle timer updates right away; a running block keeps its time and the change applies next block.")
                        .font(palette.mono(11, relativeTo: .caption))
                        .foregroundStyle(palette.dim)
                }
                .listRowBackground(palette.surface)
            }
            .font(palette.mono(15, relativeTo: .body))
            .foregroundStyle(palette.text)
            .tint(palette.accent)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(palette.background)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .onChange(of: [focusMinutes, restMinutes]) { Feedback.play(.tap) }
    }

    private func presetChip(_ preset: Preset) -> some View {
        let selected = preset.focus == focusMinutes && preset.rest == restMinutes
        return Button {
            focusMinutes = preset.focus
            restMinutes = preset.rest
        } label: {
            Text("\(preset.focus)/\(preset.rest)")
                .font(palette.mono(13, selected ? .bold : .regular, relativeTo: .footnote))
                .foregroundStyle(selected ? palette.background : palette.text)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(selected ? palette.accent : palette.border.opacity(0.5), in: .rect(cornerRadius: palette.style.radius(6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.focus) minute focus, \(preset.rest) minute break")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
