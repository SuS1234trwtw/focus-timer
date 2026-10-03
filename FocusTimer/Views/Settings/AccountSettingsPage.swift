import SwiftUI

/// Settings → account & sync.
struct AccountSettingsPage: View {
    let palette: Palette

    var body: some View {
        Form {
            AccountSettingsSection(palette: palette)
        }
        .settingsFormStyle(palette)
        .navigationTitle("account & sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}
