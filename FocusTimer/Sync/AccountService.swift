import Foundation
import Observation
import Supabase

/// Optional email account on top of the anonymous (guest) Supabase user, signed in with a 6-digit code.
///
/// Everyone starts as a guest: an anonymous user whose rows are backed up but only reachable from
/// this install. Creating an account emails a code and, once it's typed in, upgrades that same user in
/// place (same id, so every synced row stays). Logging in on another device emails a code too, then
/// downloads the account's rows and uploads the guest's local rows under it. No passwords, no links.
/// Signing out goes back to a fresh guest and keeps the local data.
@MainActor
@Observable
final class AccountService {
    static let shared = AccountService(sync: AppModel.shared.sync)

    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case create, logIn

        var id: String { rawValue }
        var label: String { self == .create ? "create account" : "log in" }
    }

    /// Supabase is configured in this build (otherwise the app is local-only).
    var isAvailable: Bool { service != nil }
    /// No email account: an anonymous user, or no session yet.
    private(set) var isGuest = true
    /// The account's email when signed in.
    private(set) var email: String?
    /// The email a code was sent to and is waiting to be typed in. Survives closing the app.
    private(set) var pendingEmail: String?
    /// What the pending code is for.
    private(set) var pendingMode: Mode = .create
    /// When the last code went out, for the resend cooldown.
    private(set) var codeSentAt: Date?
    private(set) var busy = false
    /// A one-line status for the form: an error or what to do next.
    private(set) var message: String?
    /// `message` is a problem rather than progress.
    private(set) var messageIsError = false

    /// Seconds between codes, so the inbox (and Supabase's email limit) isn't flooded.
    static let resendCooldown: TimeInterval = 60

    @ObservationIgnored private let sync: SyncCoordinator?
    @ObservationIgnored private let defaults: UserDefaults

    private static let pendingEmailKey = "account.pendingEmail"
    private static let pendingModeKey = "account.pendingMode"

    private var service: SupabaseService? { sync?.supabase }
    private var auth: AuthClient? { service?.client.auth }

    init(sync: SyncCoordinator?, defaults: UserDefaults = .standard) {
        self.sync = sync
        self.defaults = defaults
        pendingEmail = defaults.string(forKey: Self.pendingEmailKey)
        pendingMode = defaults.string(forKey: Self.pendingModeKey).flatMap(Mode.init(rawValue:)) ?? .create
        Task { await refresh() }
    }

    // MARK: State

    /// Re-reads the signed-in user from the server.
    func refresh() async {
        guard let service else { return }
        guard let user = await service.currentUser() else {
            isGuest = true
            email = nil
            return
        }
        apply(user)
        if !isGuest, let pending = pendingEmail, email?.lowercased() == pending.lowercased() {
            clearPending()  // already finished
        }
    }

    private func apply(_ user: User) {
        let address = user.email.flatMap { $0.isEmpty ? nil : $0 }
        isGuest = user.isAnonymous || address == nil
        email = isGuest ? nil : address
    }

    /// Seconds left before another code may be sent (0 when it can be sent now).
    func resendWait(now: Date = .now) -> Int {
        guard let codeSentAt else { return 0 }
        return max(0, Int((Self.resendCooldown - now.timeIntervalSince(codeSentAt)).rounded(.up)))
    }

    // MARK: Actions

    /// Emails a 6-digit code. `.create` turns this guest into an account; `.logIn` signs in to an existing one.
    func sendCode(email rawEmail: String, mode: Mode) async {
        let email = Self.clean(rawEmail)
        if let problem = Self.validate(email: email) { return fail(problem) }
        guard let service, let auth else { return fail("sync isn't set up in this build") }
        guard !busy else { return }
        if pendingEmail == email, resendWait() > 0 { return fail("wait \(resendWait())s before sending another code") }
        busy = true
        defer { busy = false }
        clearMessage()

        do {
            switch mode {
            case .create:
                try await service.ensureSignedIn()
                // Adding an email to the anonymous user sends the "Change Email Address" email with the code.
                let user = try await auth.update(user: UserAttributes(email: email))
                apply(user)
                if !isGuest, self.email?.lowercased() == email {
                    // The project confirms emails automatically: no code needed.
                    clearPending()
                    return say("backup & sync is on for \(email)")
                }
            case .logIn:
                // Only existing accounts: a typo shouldn't quietly create a new, empty one.
                try await auth.signInWithOTP(email: email, shouldCreateUser: false)
            }
            setPending(email, mode: mode)
            say("code sent to \(email). it can take a minute; check spam too")
        } catch {
            fail(Self.explain(error))
        }
    }

    /// Checks the 6-digit code from the email and finishes creating the account or logging in.
    func verify(code rawCode: String) async {
        let code = rawCode.filter(\.isNumber)
        if let problem = Self.validate(code: code) { return fail(problem) }
        guard let auth, let sync, let email = pendingEmail else { return fail("send a code first") }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        clearMessage()

        do {
            switch pendingMode {
            case .create:
                let response = try await auth.verifyOTP(email: email, token: code, type: .emailChange)
                apply(response.user)
                clearPending()
                await refresh()
                say("backup & sync is on for \(email)")
            case .logIn:
                await sync.waitUntilIdle()
                let response = try await auth.verifyOTP(email: email, token: code, type: .email)
                apply(response.user)
                clearPending()
                await sync.adoptLocalData()
                sync.resetPullCursor()
                await sync.syncNow()
                say("logged in as \(email)")
            }
        } catch {
            fail(Self.explain(error))
        }
    }

    /// Drops the pending code to start over with another email.
    func cancelCode() {
        clearPending()
        clearMessage()
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

    private func setPending(_ email: String, mode: Mode) {
        pendingEmail = email
        pendingMode = mode
        codeSentAt = .now
        defaults.set(email, forKey: Self.pendingEmailKey)
        defaults.set(mode.rawValue, forKey: Self.pendingModeKey)
    }

    private func clearPending() {
        pendingEmail = nil
        codeSentAt = nil
        defaults.removeObject(forKey: Self.pendingEmailKey)
        defaults.removeObject(forKey: Self.pendingModeKey)
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

    /// Nil when the email is usable, otherwise what to fix.
    nonisolated static func validate(email: String) -> String? {
        let email = clean(email)
        guard !email.isEmpty else { return "enter your email" }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !email.contains(" ")
        else { return "that email doesn't look right" }
        return nil
    }

    /// Nil when the code is exactly six digits, otherwise what to fix.
    nonisolated static func validate(code: String) -> String? {
        code.count == 6 && code.allSatisfy { $0.isASCII && $0.isNumber } ? nil : "the code is 6 digits"
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

        if has("otp_expired", "token has expired or is invalid", "invalid otp", "otp has expired") {
            return "wrong or expired code. check it, or send a new one"
        }
        if has("signups not allowed for otp", "otp_disabled", "user not found", "user_not_found") {
            return "no account with that email yet. create one instead"
        }
        if has("email_exists", "user_already_exists", "already registered", "already been registered", "already exists") {
            return "that email already has an account. log in instead"
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
        if has("offline", "not connected to the internet", "network connection was lost", "timed out",
               "could not connect", "nsurlerrordomain") {
            return "you're offline. try again when connected"
        }
        if has("session_not_found", "sessionmissing", "session missing", "auth session missing") {
            return "your session ran out. send a new code"
        }
        let short = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
        return short.isEmpty ? "something went wrong" : "couldn't do that: \(short)"
    }
}
