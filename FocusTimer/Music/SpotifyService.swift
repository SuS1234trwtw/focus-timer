import AuthenticationServices
import Foundation
import Observation
import SwiftUI

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
    /// The one token refresh in flight. Spotify rotates refresh tokens, so two refreshes racing
    /// with the same old token would make the second fail and unlink the account.
    @ObservationIgnored private var refreshing: Task<SpotifyAuth.Tokens, any Error>?

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

    /// Shown when Spotify refuses an account that isn't on the app's dev-mode list (max 5 people).
    static let inviteOnlyMessage = "Spotify is invite-only for now — ask the developer to add your account"

    /// Spotify answers 403 with this hint for accounts missing from the Developer Dashboard's user list.
    nonisolated static func isNotRegistered(status: Int, body: Data) -> Bool {
        guard status == 403 else { return false }
        let text = String(decoding: body, as: UTF8.self).lowercased()
        return text.contains("not be registered") || text.contains("developer.spotify.com")
    }

    /// Unlinks and explains, instead of polling an account Spotify will never let in.
    private func handleNotRegistered() {
        disconnect()
        message = Self.inviteOnlyMessage
    }

    func refresh() async {
        guard let (data, status) = await send("GET", "/me/player/currently-playing") else { return }
        if Self.isNotRegistered(status: status, body: data) { return handleNotRegistered() }
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
        guard let (data, status) = await send(method, path) else { return }
        if Self.isNotRegistered(status: status, body: data) { return handleNotRegistered() }
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

    /// Refreshes once even when several requests ask at the same time; they all share the result.
    private func freshTokens(_ current: SpotifyAuth.Tokens) async throws(SpotifyAuth.TokenError) -> SpotifyAuth.Tokens {
        let task = refreshing ?? Task { try await SpotifyAuth.refresh(current) }
        refreshing = task
        defer { if refreshing == task { refreshing = nil } }
        let refreshed: SpotifyAuth.Tokens
        do {
            refreshed = try await task.value
        } catch {
            throw (error as? SpotifyAuth.TokenError) ?? .transient
        }
        guard tokens != nil else { throw .transient } // unlinked while the refresh was running
        tokens = refreshed
        SpotifyAuth.saveTokens(refreshed)
        return refreshed
    }

    private func send(_ method: String, _ path: String) async -> (Data, Int)? {
        guard var current = tokens else { return nil }
        if current.isExpired {
            do {
                current = try await freshTokens(current)
            } catch .revoked {
                disconnect()
                message = "Spotify session expired — connect again"
                return nil
            } catch {
                // Offline or Spotify hiccup: keep the login and try again on the next poll.
                return nil
            }
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
