import CryptoKit
import Foundation
import Security

/// Spotify sign-in with Authorization Code + PKCE: the app ships only a public Client ID, never a secret.
/// Users just tap Connect and log in to Spotify.
enum SpotifyAuth {
    static let redirectURI = "focustimer://spotify-callback"
    static let callbackScheme = "focustimer"
    static let scopes = "user-read-currently-playing user-read-playback-state user-modify-playback-state"

    /// Baked in at build time from Config/*.xcconfig; empty when this build isn't registered with Spotify.
    static var clientID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String ?? ""
        return value.contains("$(") ? "" : value
    }

    static var isConfigured: Bool { !clientID.isEmpty }

    // MARK: PKCE

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    /// S256 code challenge (RFC 7636).
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizeURL(verifier: String, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    enum CallbackError: Error, Equatable {
        case denied(String)
        case stateMismatch
        case missingCode
    }

    /// Pulls the authorization code out of `focustimer://spotify-callback?code=…&state=…`.
    static func code(from callback: URL, expectedState: String) throws(CallbackError) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw .denied(error) }
        guard value("state") == expectedState else { throw .stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
    }

    // MARK: Tokens

    struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date

        var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }

    static func exchange(code: String, verifier: String) async throws(TokenError) -> Tokens {
        try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], previousRefresh: nil)
    }

    static func refresh(_ tokens: Tokens) async throws(TokenError) -> Tokens {
        try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": clientID,
        ], previousRefresh: tokens.refreshToken)
    }

    /// Why a token request failed: only `revoked` means the link is gone for good.
    enum TokenError: Error, Equatable {
        /// Spotify rejected the refresh token (unlinked in Spotify, or already rotated away).
        case revoked
        /// Offline, timed out, or Spotify had a hiccup; the saved login still works later.
        case transient
    }

    /// Spotify answers a dead refresh token with 400 `invalid_grant`; anything else is worth retrying.
    static func tokenFailure(status: Int, body: Data) -> TokenError {
        let text = String(decoding: body, as: UTF8.self)
        return (status == 400 && text.contains("invalid_grant")) || status == 401 ? .revoked : .transient
    }

    private static func requestTokens(_ form: [String: String], previousRefresh: String?) async throws(TokenError) -> Tokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { throw .transient }
        guard status == 200 else { throw tokenFailure(status: status, body: data) }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else { throw .transient }
        // Spotify rotates refresh tokens: keep the new one when it sends one, else the old one stays valid.
        guard let refresh = decoded.refresh_token ?? previousRefresh else { throw .revoked }
        return Tokens(accessToken: decoded.access_token, refreshToken: refresh,
                      expiresAt: .now.addingTimeInterval(decoded.expires_in))
    }

    // MARK: Keychain

    private static let account = "spotify.tokens"

    static func loadTokens() -> Tokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    static func saveTokens(_ tokens: Tokens?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
