import SwiftUI

struct SettingsSheet: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @AppStorage("timerFont") private var timerFont: TimerFont = .carved
    @AppStorage("chimeEnabled") private var chimeEnabled = true
    @AppStorage("tickHaptics") private var tickHaptics = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Timer font") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(TimerFont.allCases) { option in
                                fontCard(option)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    Stepper(value: minutesBinding(.focus), in: PomodoroEngine.minuteRange) {
                        LabeledContent("Focus", value: "\(engine.focusMinutes) min")
                    }
                    Stepper(value: minutesBinding(.rest), in: PomodoroEngine.minuteRange) {
                        LabeledContent("Break", value: "\(engine.restMinutes) min")
                    }
                } header: {
                    Text("Durations")
                } footer: {
                    Text("You can also scroll the big numbers to change the current block.")
                }

                Section {
                    Toggle("Chime at zero", isOn: $chimeEnabled)
                    Toggle("Tick haptics", isOn: $tickHaptics)
                } footer: {
                    Text("A soft tick every second while the timer runs, and a firmer one each minute.")
                }

                Section("Today") {
                    LabeledContent("Focus blocks done", value: "\(engine.completedFocusCount)")
                    LabeledContent("Sync", value: syncLabel)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: timerFont)
    }

    private func fontCard(_ option: TimerFont) -> some View {
        let selected = option == timerFont
        return Button {
            withAnimation(.snappy) { timerFont = option }
        } label: {
            VStack(spacing: 6) {
                CarvedNumeral(text: "25", font: option, tone: Theme.focus.carvedLit, castShadow: .black.opacity(0.4))
                    .frame(width: 76, height: 58)
                Text(option.name)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(.fill.tertiary, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? Color.primary : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.name) font")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func minutesBinding(_ mode: TimerMode) -> Binding<Int> {
        Binding(
            get: { engine.minutes(for: mode) },
            set: { engine.setMinutes($0, for: mode) }
        )
    }

    private var syncLabel: String {
        switch sync.status {
        case .localOnly: "Local only"
        case .idle: "Idle"
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .offline: "Offline"
        }
    }
}
