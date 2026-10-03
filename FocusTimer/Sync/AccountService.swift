import Foundation
import Observation
import Supabase

/// Optional email account on top of the anonymous (guest) Supabase user.
///
/// Everyone starts as a guest: an anonymous user whose rows are backed up but only reachable from
/// this install. Creating an account upgrades that same user in place (same id, so every synced row
/// stays). Logging in to an existing account on another device downloads its rows and uploads the
/// guest's local rows under it. Signing out goes back to a fresh guest and keeps the local data.
@MainActor
@Observable
final class AccountService {
    static let shared = AccountService(sync: AppModel.shared.sync)

    /// Supabase is configured in this build (otherwise the app is local-only).
    var isAvailable: Bool { service != nil }
    /// No email account: an anonymous user, or no session yet.
    private(set) var isGuest = true
    /// The account's email when signed in.
    private(set) var email: String?
    /// An email waiting to be confirmed from the inbox (create account, step one).
    private(set) var pendingEmail: String?
    /// The email is confirmed but the password still has to be set (the app was closed in between).
    private(set) var needsPassword = false
    private(set) var busy = false
    /// A one-line status for the form: an error or what to do next.
    private(set) var message: String?
    /// `message` is a problem rather than progress.
    private(set) var messageIsError = false

    @ObservationIgnored private let sync: SyncCoordinator?
    @ObservationIgnored private let defaults: UserDefaults
    /// The password chosen while the email confirmation is pending. Memory only, never stored.
    @ObservationIgnored private var pendingPassword: String?

    private static let pendingEmailKey = "account.pendingEmail"

    private var service: SupabaseService? { sync?.supabase }
    private var auth: AuthClient? { service?.client.auth }

    init(sync: SyncCoordinator?, defaults: UserDefaults = .standard) {
        self.sync = sync
        self.defaults = defaults
        pendingEmail = defaults.string(forKey: Self.pendingEmailKey)
        Task { await refresh() }
    }

    // MARK: State

    /// Re-reads the signed-in user from the server. Finishes a pending sign-up once its email is confirmed.
    func refresh() async {
        guard let service else { return }
        guard let user = await service.currentUser() else {
            isGuest = true
            email = nil
            return
        }
        apply(user)
        if let pending = pendingEmail, !busy, !isGuest, email?.lowercased() == pending.lowercased() {
            // Email confirmed in the browser: the password can be set now.
            if let password = pendingPassword {
                await finishSignUp(password: password)
            } else {
                needsPassword = true
            }
        }
    }

    private func apply(_ user: User) {
        let address = user.email.flatMap { $0.isEmpty ? nil : $0 }
        isGuest = user.isAnonymous || address == nil
        email = isGuest ? nil : address
    }

    // MARK: Actions

    /// Turns the current guest into an account with this email and password, keeping its id and data.
    /// When the project asks for email confirmation, the password is set once the email is confirmed.
    func createAccount(email rawEmail: String, password: String) async {
        let email = Self.clean(rawEmail)
        if let problem = Self.validate(email: email, password: password) { return fail(problem) }
        guard let service, let auth else { return fail("sync isn't set up in this build") }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        clearMessage()

        do {
            try await service.ensureSignedIn()
            // Supabase won't give an anonymous user a password before it has an email, so: email first.
            let user = try await auth.update(user: UserAttributes(email: email))
            apply(user)
            if !isGuest, self.email?.lowercased() == email.lowercased() {
                // Confirmed straight away (email confirmation is off).
                _ = try await auth.update(user: UserAttributes(password: password))
                clearPending()
                say("backup & sync is on for \(email)")
            } else {
                pendingEmail = email
                pendingPassword = password
                defaults.set(email, forKey: Self.pendingEmailKey)
                say("check your inbox to confirm \(email), then come back here")
            }
        } catch {
            fail(Self.explain(error))
        }
    }

    /// Sets the password after the email was confirmed (when the app was closed in between).
    func setPassword(_ password: String) async {
        if password.count < 8 { return fail("password needs at least 8 characters") }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        clearMessage()
        await finishSignUp(password: password)
    }

    private func finishSignUp(password: String) async {
        guard let auth else { return }
        do {
            _ = try await auth.update(user: UserAttributes(password: password))
            let address = email ?? pendingEmail ?? ""
            clearPending()
            say("backup & sync is on for \(address)")
        } catch {
            fail(Self.explain(error))
        }
    }

    /// Logs in to an existing account: downloads its data and uploads this device's guest data under it.
    func logIn(email rawEmail: String, password: String) async {
        let email = Self.clean(rawEmail)
        if let problem = Self.validate(email: email, password: password) { return fail(problem) }
        guard let auth, let sync else { return fail("sync isn't set up in this build") }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        clearMessage()

        await sync.waitUntilIdle()
        do {
            let session = try await auth.signIn(email: email, password: password)
            apply(session.user)
            clearPending()
            await sync.adoptLocalData()
            sync.resetPullCursor()
            await sync.syncNow()
            say("logged in as \(email)")
        } catch {
            fail(Self.explain(error))
        }
    }

    /// Back to a guest. Local tasks stay on this device; the account keeps its copy.
    func signOut() async {
        guard let service, let auth, let sync else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        clearMessage()

        await sync.waitUntilIdle()
        do {
            try await auth.signOut()
        } catch {
            return fail(Self.explain(error))
        }
        isGuest = true
        email = nil
        clearPending()
        await sync.prepareForSignOut()
        sync.resetPullCursor()
        try? await service.ensureSignedIn()
        await sync.syncNow()
        say("signed out. this iPhone is a guest again")
    }

    func clearMessage() {
        message = nil
        messageIsError = false
    }

    private func clearPending() {
        pendingEmail = nil
        pendingPassword = nil
        needsPassword = false
        defaults.removeObject(forKey: Self.pendingEmailKey)
    }

    private func say(_ text: String) {
        message = text
        messageIsError = false
    }

    private func fail(_ text: String) {
        message = text
        messageIsError = true
    }

    // MARK: Helpers

    nonisolated static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Nil when the email and password are usable, otherwise what to fix.
    nonisolated static func validate(email: String, password: String) -> String? {
        let email = clean(email)
        guard !email.isEmpty else { return "enter your email" }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !email.contains(" ")
        else { return "that email doesn't look right" }
        guard password.count >= 8 else { return "password needs at least 8 characters" }
        return nil
    }

    /// A short, readable reason for an auth failure.
    nonisolated static func explain(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff:
                return "you're offline. try again when connected"
            default:
                return "couldn't reach the server (\(urlError.code.rawValue))"
            }
        }
        return explain(text: "\(String(describing: error)) \(error.localizedDescription)")
    }

    /// Matches Supabase's error codes and messages (kept separate so it can be tested on plain text).
    nonisolated static func explain(text raw: String) -> String {
        let text = raw.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }

        if has("invalid_credentials", "invalid login credentials", "invalid email or password") {
            return "wrong email or password"
        }
        if has("email_not_confirmed", "email not confirmed") {
            return "confirm your email first: open the link in your inbox, then log in"
        }
        if has("email_exists", "user_already_exists", "already registered", "already been registered", "already exists") {
            return "that email already has an account. log in instead"
        }
        if has("weak_password", "password should", "password is too weak", "weak password") {
            return "pick a stronger password: at least 8 characters, mix letters and numbers"
        }
        if has("email_address_invalid", "invalid email", "unable to validate email", "email address is invalid") {
            return "that email doesn't look right"
        }
        if has("rate_limit", "rate limit", "too many requests", "429", "for security purposes") {
            return "too many tries. wait a minute and try again"
        }
        if has("signup_disabled", "signups not allowed", "email_provider_disabled", "email logins are disabled") {
            return "new accounts are turned off on the server right now"
        }
        if has("anonymous_provider_disabled", "anonymous sign-ins are disabled") {
            return "guest sign-in is turned off on the server"
        }
        if has("same_password", "should be different from the old password") {
            return "that's already your password"
        }
        if has("offline", "not connected to the internet", "network connection was lost", "timed out",
               "could not connect", "nsurlerrordomain") {
            return "you're offline. try again when connected"
        }
        if has("session_not_found", "sessionmissing", "session missing", "auth session missing") {
            return "your session ran out. log in again"
        }
        let short = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
        return short.isEmpty ? "something went wrong" : "couldn't do that: \(short)"
    }
}
