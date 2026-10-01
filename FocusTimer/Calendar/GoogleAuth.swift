import Foundation
import Security

/// Google sign-in for an iOS OAuth client: Authorization Code + PKCE, no client secret.
/// Google sends the user back to the reversed client ID scheme (`com.googleusercontent.apps.<id>:/oauthredirect`).
enum GoogleAuth {
    /// Only lets the app create calendars and manage the events in them; it can't read the user's other calendars.
    static let scope = "https://www.googleapis.com/auth/calendar.app.created"
    static let authorizeEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    static let clientIDSuffix = ".apps.googleusercontent.com"
    static let reversedPrefix = "com.googleusercontent.apps."

    /// Baked in at build time from Config/*.xcconfig; empty when this build isn't registered with Google.
    static var clientID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
        return value.contains("$(") ? "" : value.trimmingCharacters(in: .whitespaces)
    }

    static var isConfigured: Bool { !clientID.isEmpty }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`.
    static func reversedScheme(for clientID: String) -> String {
        let id = clientID.hasSuffix(clientIDSuffix) ? String(clientID.dropLast(clientIDSuffix.count)) : clientID
        return reversedPrefix + id
    }

    static func redirectURI(for clientID: String) -> String {
        reversedScheme(for: clientID) + ":/oauthredirect"
    }

    static var callbackScheme: String { reversedScheme(for: clientID) }
    static var redirectURI: String { redirectURI(for: clientID) }

    static func authorizeURL(clientID: String = GoogleAuth.clientID, verifier: String, state: String) -> URL {
        var components = URLComponents(string: authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI(for: clientID)),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: SpotifyAuth.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    /// PKCE helpers are shared with Spotify (same RFC 7636 S256 scheme).
    static func makeVerifier() -> String { SpotifyAuth.makeVerifier() }

    /// Pulls the authorization code out of `com.googleusercontent.apps.…:/oauthredirect?code=…&state=…`.
    static func code(from callback: URL, expectedState: String) throws(SpotifyAuth.CallbackError) -> String {
        try SpotifyAuth.code(from: callback, expectedState: expectedState)
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

    static func exchange(code: String, verifier: String) async throws -> Tokens {
        try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], previousRefresh: nil)
    }

    /// Throws `URLError(.userAuthenticationRequired)` when Google rejects the refresh token (revoked / expired).
    static func refresh(_ tokens: Tokens) async throws -> Tokens {
        try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": clientID,
        ], previousRefresh: tokens.refreshToken)
    }

    /// Form body for the token endpoint. `+`, `/` and `=` are escaped so codes and tokens survive form decoding.
    static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form
            .sorted { $0.key < $1.key }
            .map { pair -> String in
                let k = pair.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? pair.key
                let v = pair.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? pair.value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func requestTokens(_ form: [String: String], previousRefresh: String?) async throws -> Tokens {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(form)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // 400/401 = bad or revoked grant; anything else (5xx) is worth retrying later.
            throw URLError((400..<500).contains(status) ? .userAuthenticationRequired : .badServerResponse)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        // Google only returns a refresh token on the first consent; keep the one we have.
        guard let refresh = decoded.refresh_token ?? previousRefresh else { throw URLError(.userAuthenticationRequired) }
        return Tokens(accessToken: decoded.access_token, refreshToken: refresh,
                      expiresAt: .now.addingTimeInterval(decoded.expires_in))
    }

    // MARK: Keychain

    private static let account = "google.tokens"

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
