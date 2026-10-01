import AuthenticationServices
import Foundation
import Observation
import SwiftUI

/// A finished timer block waiting to be written to Google Calendar.
struct PendingCalendarEvent: Codable, Sendable, Equatable, Identifiable {
    /// Doubles as the Google event id, so a retry after a lost response gets 409 instead of a duplicate.
    /// Lowercase hex from a UUID: valid base32hex (a–v, 0–9), 32 chars.
    let id: String
    let summary: String
    let start: Date
    let end: Date
    let timeZone: String

    static func makeID(_ uuid: UUID = UUID()) -> String {
        uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// `mode` is `TimerMode.rawValue`: "focus" or "rest".
    static func make(mode: String, start: Date, end: Date, taskTitle: String?,
                     id: String = PendingCalendarEvent.makeID(), timeZone: TimeZone = .current) -> PendingCalendarEvent {
        let summary: String
        if mode == "focus" {
            let task = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            summary = task.isEmpty ? "Focus" : "Focus · \(task)"
        } else {
            summary = "Break"
        }
        return PendingCalendarEvent(id: id, summary: summary, start: start, end: end, timeZone: timeZone.identifier)
    }

    /// Google event ids: 5–1024 chars of lowercase base32hex.
    static func isValidGoogleID(_ id: String) -> Bool {
        let letters: ClosedRange<Character> = "a"..."v"
        let digits: ClosedRange<Character> = "0"..."9"
        return (5...1024).contains(id.count) && id.allSatisfy { letters.contains($0) || digits.contains($0) }
    }
}

/// JSON bodies for the Calendar API (kept free of the service so tests can call them directly).
enum GoogleCalendarAPI {
    static let base = "https://www.googleapis.com/calendar/v3"
    static let calendarName = "Focus"
    static let eventDescription = "Logged by Focus"

    private struct EventTime: Encodable {
        let dateTime: String
        let timeZone: String
    }

    private struct EventBody: Encodable {
        let id: String
        let summary: String
        let description: String
        let start: EventTime
        let end: EventTime
    }

    private struct CalendarBody: Encodable {
        let summary: String
        let description: String
        let timeZone: String
    }

    static func eventBody(for event: PendingCalendarEvent) throws -> Data {
        let body = EventBody(
            id: event.id,
            summary: event.summary,
            description: eventDescription,
            start: EventTime(dateTime: event.start.formatted(.iso8601), timeZone: event.timeZone),
            end: EventTime(dateTime: event.end.formatted(.iso8601), timeZone: event.timeZone)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(body)
    }

    static func calendarBody(timeZone: TimeZone = .current) throws -> Data {
        try JSONEncoder().encode(CalendarBody(
            summary: calendarName,
            description: "Focus blocks from the Focus timer app.",
            timeZone: timeZone.identifier
        ))
    }

    /// `/calendars/{id}`, with the id escaped (secondary calendar ids contain `@`).
    static func calendarPath(_ calendarID: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return "/calendars/" + (calendarID.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendarID)
    }
}

/// Links a Google account and logs each finished focus block as an event in a "Focus" calendar.
/// Events are queued in UserDefaults first, so nothing is lost offline; `flushPending()` sends them.
@MainActor
@Observable
final class GoogleCalendarService {
    static let shared = GoogleCalendarService()

    enum Key {
        static let logFocus = "googleCalendar.logFocus"
        static let logBreaks = "googleCalendar.logBreaks"
        static let calendarID = "googleCalendar.calendarID"
        static let pending = "googleCalendar.pending"
    }

    private(set) var isConnected = false
    /// A short status line for errors.
    private(set) var message: String?
    private(set) var pending: [PendingCalendarEvent] = []

    var pendingCount: Int { pending.count }
    var isConfigured: Bool { GoogleAuth.isConfigured }

    @ObservationIgnored private var tokens: GoogleAuth.Tokens?
    @ObservationIgnored private var isFlushing = false
    @ObservationIgnored private let defaults: UserDefaults

    /// Keeps the queue bounded if the account stays unreachable for a long time.
    private static let maxPending = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tokens = GoogleAuth.loadTokens()
        isConnected = tokens != nil && GoogleAuth.isConfigured
        if let data = defaults.data(forKey: Key.pending),
           let saved = try? JSONDecoder().decode([PendingCalendarEvent].self, from: data) {
            pending = saved
        }
    }

    var logFocus: Bool { defaults.object(forKey: Key.logFocus) as? Bool ?? true }
    var logBreaks: Bool { defaults.object(forKey: Key.logBreaks) as? Bool ?? false }

    private var calendarID: String? {
        get { defaults.string(forKey: Key.calendarID) }
        set { defaults.set(newValue, forKey: Key.calendarID) }
    }

    // MARK: Linking

    /// Opens Google's sign-in page; the user approves and comes straight back.
    func connect(using session: WebAuthenticationSession) async {
        guard isConfigured else { return }
        let verifier = GoogleAuth.makeVerifier()
        let state = UUID().uuidString
        do {
            let callback = try await session.authenticate(
                using: GoogleAuth.authorizeURL(verifier: verifier, state: state),
                callback: .customScheme(GoogleAuth.callbackScheme),
                preferredBrowserSession: .shared,
                additionalHeaderFields: [:]
            )
            let code = try GoogleAuth.code(from: callback, expectedState: state)
            let newTokens = try await GoogleAuth.exchange(code: code, verifier: verifier)
            tokens = newTokens
            GoogleAuth.saveTokens(newTokens)
            isConnected = true
            message = nil
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User closed the sheet; nothing to report.
            return
        } catch {
            message = "couldn't link Google — try again"
            return
        }
        // A stored calendar may belong to a previous account or have been deleted.
        if let stored = calendarID, let (_, status) = await send("GET", GoogleCalendarAPI.calendarPath(stored)),
           status == 404 || status == 403 {
            calendarID = nil
        }
        if await ensureCalendar() == nil, message == nil {
            message = "linked, but couldn't create the Focus calendar yet"
        }
        await flushPending()
    }

    /// Forgets the account, the calendar and anything still queued.
    func disconnect() {
        tokens = nil
        GoogleAuth.saveTokens(nil)
        isConnected = false
        calendarID = nil
        pending = []
        savePending()
        message = nil
    }

    /// Google rejected the refresh token: sign out but keep the queue so a reconnect sends it.
    private func expireSession() {
        tokens = nil
        GoogleAuth.saveTokens(nil)
        isConnected = false
        message = "Google session expired — connect again"
    }

    // MARK: Logging

    /// Queues one finished block (`mode` is `TimerMode.rawValue`) and tries to send it right away.
    func log(mode: String, start: Date, end: Date, taskTitle: String?) {
        guard isConfigured, isConnected || calendarID != nil else { return }
        guard mode == "focus" ? logFocus : logBreaks else { return }
        guard end > start else { return }
        pending.append(.make(mode: mode, start: start, end: end, taskTitle: taskTitle))
        if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
        savePending()
        Task { await flushPending() }
    }

    /// Sends queued events in order. Stops at the first network/server problem and tries again next time.
    func flushPending() async {
        guard isConnected, !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        var recreatedCalendar = false
        while isConnected, let event = pending.first {
            guard let calendar = await ensureCalendar(),
                  let body = try? GoogleCalendarAPI.eventBody(for: event) else { return }
            guard let (_, status) = await send("POST", GoogleCalendarAPI.calendarPath(calendar) + "/events", body: body) else { return }
            switch status {
            case 200..<300, 409:
                // 409: an earlier attempt already created this event id.
                remove(event)
            case 404:
                // The Focus calendar was deleted: make a new one once, then retry this event.
                guard !recreatedCalendar else { return }
                recreatedCalendar = true
                calendarID = nil
            case 401, 429, 500...:
                // Auth already retried once inside `send`; rate limits and outages are temporary.
                return
            default:
                // Other 4xx: Google will never accept this event; drop it so the queue keeps moving.
                remove(event)
            }
        }
        if pending.isEmpty, message?.hasPrefix("linked") == true { message = nil }
    }

    private func remove(_ event: PendingCalendarEvent) {
        pending.removeAll { $0.id == event.id }
        savePending()
    }

    private func savePending() {
        if pending.isEmpty {
            defaults.removeObject(forKey: Key.pending)
        } else if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Key.pending)
        }
    }

    // MARK: Calendar

    private struct CalendarResponse: Decodable { let id: String }

    /// The id of the app's "Focus" calendar, creating it on first use.
    private func ensureCalendar() async -> String? {
        if let calendarID { return calendarID }
        guard let body = try? GoogleCalendarAPI.calendarBody(),
              let (data, status) = await send("POST", "/calendars", body: body) else { return nil }
        guard (200..<300).contains(status), let created = try? JSONDecoder().decode(CalendarResponse.self, from: data) else {
            message = "couldn't create the Focus calendar (\(status))"
            return nil
        }
        calendarID = created.id
        return created.id
    }

    // MARK: Transport

    /// A usable access token, refreshing it if needed. Nil when offline or signed out.
    private func accessToken(forceRefresh: Bool = false) async -> String? {
        guard var current = tokens else { return nil }
        if forceRefresh || current.isExpired {
            do {
                current = try await GoogleAuth.refresh(current)
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                expireSession()
                return nil
            } catch {
                return nil  // Offline or Google hiccup: try again later.
            }
            tokens = current
            GoogleAuth.saveTokens(current)
        }
        return current.accessToken
    }

    /// One Calendar API call; on 401 refreshes the token and retries once. Nil = never reached Google.
    private func send(_ method: String, _ path: String, body: Data? = nil) async -> (Data, Int)? {
        var forceRefresh = false
        for _ in 0..<2 {
            guard let token = await accessToken(forceRefresh: forceRefresh),
                  let url = URL(string: GoogleCalendarAPI.base + path) else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
            if status == 401 && !forceRefresh {
                forceRefresh = true
                continue
            }
            return (data, status)
        }
        return nil
    }
}
