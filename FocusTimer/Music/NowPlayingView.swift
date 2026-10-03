import SwiftUI

/// `♪ now playing` — the linked Spotify track as a terminal line, with transport controls.
struct NowPlayingView: View {
    @Environment(SpotifyService.self) private var spotify
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(palette.style.linePrefix)now playing")
                .font(palette.mono(12, .bold, relativeTo: .caption))
                .foregroundStyle(palette.dim)

            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(spotify.track?.title ?? "nothing playing")
                        .font(palette.mono(14, .bold, relativeTo: .body))
                        .foregroundStyle(spotify.track == nil ? palette.dim : palette.text)
                    if let artist = spotify.track?.artist, !artist.isEmpty {
                        Text(artist)
                            .font(palette.mono(12, relativeTo: .caption))
                            .foregroundStyle(palette.dim)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                controls
            }

            if let message = spotify.message {
                Text(message)
                    .font(palette.mono(11, relativeTo: .caption2))
                    .foregroundStyle(Color(hex: 0xE0786A))
            }
        }
        .padding(14)
        .background(palette.surface.opacity(0.55), in: .rect(cornerRadius: palette.style.radius(10)))
        .overlay(RoundedRectangle(cornerRadius: palette.style.radius(10)).strokeBorder(palette.border, lineWidth: 1))
        .animation(Motion.swap(), value: spotify.track)
    }

    private var artwork: some View {
        AsyncImage(url: spotify.track?.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.border.opacity(0.4))
        }
        .frame(width: 42, height: 42)
        .clipShape(.rect(cornerRadius: palette.style.radius(6)))
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            control("backward.fill", label: "Previous track") { await spotify.previous() }
            control(spotify.track?.isPlaying == true ? "pause.fill" : "play.fill",
                    label: spotify.track?.isPlaying == true ? "Pause music" : "Play music") { await spotify.togglePlayback() }
            control("forward.fill", label: "Next track") { await spotify.next() }
        }
    }

    private func control(_ symbol: String, label: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Feedback.play(.tap)
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
