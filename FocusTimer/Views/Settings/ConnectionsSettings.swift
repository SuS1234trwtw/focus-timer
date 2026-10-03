import AuthenticationServices
import SwiftUI

/// Settings → connections: Spotify and Google Calendar.
struct ConnectionsSettingsPage: View {
    let palette: Palette

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(SpotifyService.self) private var spotify

    @AppStorage("spotifyInIsland") private var spotifyInIsland = true

    var body: some View {
        Form {
            musicSection
            CalendarSettingsSection(palette: palette)
        }
        .settingsFormStyle(palette)
        .navigationTitle("connections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var musicSection: some View {
        Section {
            if !spotify.isConfigured {
                Text("Spotify isn't set up in this build yet.")
                    .foregroundStyle(palette.dim)
            } else if spotify.isConnected {
                LabeledContent("spotify", value: "linked")
                Toggle("show song in Dynamic Island", isOn: $spotifyInIsland)
                Button("unlink spotify", systemImage: "xmark.circle", role: .destructive) {
                    Feedback.play(.tap)
                    spotify.disconnect()
                }
            } else {
                Button {
                    Feedback.play(.tap)
                    Task { await spotify.connect(using: webAuthenticationSession) }
                } label: {
                    Label("connect spotify", systemImage: "music.note")
                        .foregroundStyle(palette.accent)
                }
            }
            if let message = spotify.message {
                Text(message)
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0xE0786A))
            }
        } header: {
            SettingsHeader("music", palette: palette)
        } footer: {
            SettingsFooter("Log in to Spotify to show the song under the timer and in the Dynamic Island. Play/pause/skip need Spotify Premium. The song updates while the app is open.", palette: palette)
        }
        .listRowBackground(palette.surface)
    }
}
