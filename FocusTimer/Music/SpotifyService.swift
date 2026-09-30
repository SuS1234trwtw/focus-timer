import AuthenticationServices
import Foundation
import Observation

/// The song playing on the user's Spotify account.
struct NowPlaying: Equatable, Sendable {
    var title: String
    var artist: String
    var artworkURL: URL?
    var isPlaying: Bool

    /// One line for the terminal and the Dynamic Island.
    var line: String { artist.isEmpty ? title : "\(title) — \(artist)" }
}

/// Links a Spotify account and reads / controls what's playing (Spotify Web API).
@MainActor
@Observable
final class SpotifyService {
    private(set) var isConnected = false
    private(set) var track: NowPlaying?
    /// A short status line for errors (e.g. "Premium needed for controls").
    private(set) var message: String?

    @ObservationIgnored private var tokens: SpotifyAuth.Tokens?

    var isConfigured: Bool { SpotifyAuth.isConfigured }

    init() {
        tokens = SpotifyAuth.loadTokens()
        isConnected = tokens != nil && SpotifyAuth.isConfigured
    }

    // MARK: Linking

    /// Opens Spotify's login page; the user approves and comes straight back.
    func connect(using session: WebAuthenticationSession) async {
        guard isConfigured else { return }
        let verifier = SpotifyAuth.makeVerifier()
        let state = UUID().uuidString
        do {
            let callback = try await session.authenticate(
                using: SpotifyAuth.authorizeURL(verifier: verifier, state: state),
                callback: .customScheme(SpotifyAuth.callbackScheme),
                preferredBrowserSession: .shared,
                additionalHeaderFields: [:]
            )
            let code = try SpotifyAuth.code(from: callback, expectedState: state)
            let newTokens = try await SpotifyAuth.exchange(code: code, verifier: verifier)
            tokens = newTokens
            SpotifyAuth.saveTokens(newTokens)
            isConnected = true
            message = nil
            await refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User closed the sheet; nothing to report.
        } catch {
            message = "couldn't link Spotify — try again"
        }
    }

    func disconnect() {
        tokens = nil
        SpotifyAuth.saveTokens(nil)
        isConnected = false
        track = nil
        message = nil
    }

    // MARK: Now playing

    /// Refreshes every few seconds while the app is on screen; the caller's task cancellation stops it.
    func pollWhileActive() async {
        while !Task.isCancelled && isConnected {
            await refresh()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private struct CurrentlyPlaying: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable {
                struct Image: Decodable { let url: URL; let width: Int? }
                let images: [Image]
            }
            let name: String
            let artists: [Artist]?
            let album: Album?
        }
        let is_playing: Bool
        let item: Item?
    }

    func refresh() async {
        guard let (data, status) = await send("GET", "/me/player/currently-playing") else { return }
        guard status == 200, let playing = try? JSONDecoder().decode(CurrentlyPlaying.self, from: data), let item = playing.item else {
            track = nil  // 204: nothing playing
            return
        }
        let artwork = item.album?.images.min { ($0.width ?? 0) < ($1.width ?? 0) }?.url
        let next = NowPlaying(
            title: item.name,
            artist: item.artists?.map(\.name).joined(separator: ", ") ?? "",
            artworkURL: artwork,
            isPlaying: playing.is_playing
        )
        if next != track { track = next }
    }

    // MARK: Controls (Spotify Premium)

    func togglePlayback() async {
        let playing = track?.isPlaying ?? false
        await control("PUT", playing ? "/me/player/pause" : "/me/player/play")
    }

    func next() async { await control("POST", "/me/player/next") }
    func previous() async { await control("POST", "/me/player/previous") }

    private func control(_ method: String, _ path: String) async {
        guard let (_, status) = await send(method, path) else { return }
        switch status {
        case 200..<300: message = nil
        case 403: message = "Spotify Premium is needed for controls"
        case 404: message = "open Spotify on a device first"
        default: message = "Spotify didn't respond (\(status))"
        }
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
    }

    // MARK: Transport

    private func send(_ method: String, _ path: String) async -> (Data, Int)? {
        guard var current = tokens else { return nil }
        if current.isExpired {
            guard let refreshed = try? await SpotifyAuth.refresh(current) else {
                disconnect()
                message = "Spotify session expired — connect again"
                return nil
            }
            current = refreshed
            tokens = refreshed
            SpotifyAuth.saveTokens(refreshed)
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 401 {
            // Token revoked or expired early: force a refresh next time.
            tokens?.expiresAt = .distantPast
        }
        return (data, status)
    }
}
