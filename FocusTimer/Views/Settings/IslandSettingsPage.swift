import SwiftUI

/// Settings → dynamic island: what the island shows, plus diagnostics and a restart button.
struct IslandSettingsPage: View {
    let palette: Palette

    var body: some View {
        Form {
            IslandSettingsSection(palette: palette)
            diagnosticsSection
        }
        .settingsFormStyle(palette)
        .navigationTitle("dynamic island")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasWidgetExtension: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(atPath: plugins.appending(path: "FocusWidgets.appex").path(percentEncoded: false))
    }

    private var diagnosticsSection: some View {
        let live = AppModel.shared.live
        return Section {
            LabeledContent("live activities", value: live.areActivitiesEnabled ? "allowed" : "turned off")
            // The island is drawn by the widget extension; sideloading can strip it out of the app.
            LabeledContent("island extension", value: hasWidgetExtension ? "installed" : "missing")
            // How the extension was signed: a mismatch here means iOS ignores it (empty island).
            let signing = ExtensionSigning.current()
            LabeledContent("signing", value: signing.verdict)
            VStack(alignment: .leading, spacing: 2) {
                Text("app id: \(signing.appID ?? "?")")
                Text("ext id: \(signing.extensionID ?? "?")")
                Text("ext profile: \(signing.extensionProfileID ?? "none")")
                Text("app profile: \(signing.appProfileID ?? "none")")
            }
            .font(palette.mono(10, relativeTo: .caption2))
            .foregroundStyle(palette.dim)
            .textSelection(.enabled)
            LabeledContent("islands", value: live.activityStates.isEmpty ? "none" : live.activityStates.joined(separator: ", "))
            if let created = live.lastCreated {
                LabeledContent("created", value: created.formatted(date: .omitted, time: .shortened))
            }
            if let error = live.lastError {
                Text(error)
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0xE0786A))
                    .textSelection(.enabled)
            }
            Button("restart island", systemImage: "arrow.clockwise") {
                Feedback.play(.tap)
                AppModel.shared.restartLiveActivity()
            }
            .foregroundStyle(palette.accent)
        } header: {
            SettingsHeader("island", palette: palette)
        } footer: {
            SettingsFooter("The Dynamic Island shows while a block is running or paused, and closes when the timer is idle or the app is closed. If it doesn't appear during a block: \"turned off\" means iOS Settings → Focus → Live Activities; any red text is the exact reason iOS gave. Restart only does something while a block is in use.", palette: palette)
        }
        .listRowBackground(palette.surface)
    }
}
