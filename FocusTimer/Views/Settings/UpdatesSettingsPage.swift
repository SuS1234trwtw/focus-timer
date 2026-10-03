import SwiftUI

/// Settings → updates.
struct UpdatesSettingsPage: View {
    let palette: Palette

    var body: some View {
        Form {
            UpdateSettingsSection(palette: palette)
        }
        .settingsFormStyle(palette)
        .navigationTitle("updates")
        .navigationBarTitleDisplayMode(.inline)
    }
}
