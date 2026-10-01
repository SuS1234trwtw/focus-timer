import Foundation
import Testing
@testable import FocusTimer

struct GoogleAuthTests {
    private let clientID = "1234567890-abcdef.apps.googleusercontent.com"

    @Test func reversedSchemeDropsSuffixAndPrefixesGoogle() {
        #expect(GoogleAuth.reversedScheme(for: clientID) == "com.googleusercontent.apps.1234567890-abcdef")
        #expect(GoogleAuth.redirectURI(for: clientID) == "com.googleusercontent.apps.1234567890-abcdef:/oauthredirect")
    }

    @Test func authorizeURLCarriesPKCEAndScope() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let url = GoogleAuth.authorizeURL(clientID: clientID, verifier: verifier, state: "s1")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        func value(_ name: String) -> String? { components.queryItems?.first { $0.name == name }?.value }

        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")
        #expect(value("client_id") == clientID)
        #expect(value("response_type") == "code")
        #expect(value("redirect_uri") == "com.googleusercontent.apps.1234567890-abcdef:/oauthredirect")
        #expect(value("scope") == "https://www.googleapis.com/auth/calendar.app.created")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(value("state") == "s1")
        #expect(value("prompt") == "consent")
    }

    @Test func callbackYieldsCode() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?state=s1&code=4/0Ab-xyz&scope=x"))
        #expect(try GoogleAuth.code(from: url, expectedState: "s1") == "4/0Ab-xyz")
    }

    @Test func formBodyEscapesReservedCharacters() throws {
        let body = try #require(String(data: GoogleAuth.formBody(["code": "4/0A+b=", "a": "x y"]), encoding: .utf8))
        #expect(body == "a=x%20y&code=4%2F0A%2Bb%3D")
    }
}

struct GoogleCalendarEventTests {
    @Test func eventIDsAreValidForGoogle() {
        for _ in 0..<50 {
            #expect(PendingCalendarEvent.isValidGoogleID(PendingCalendarEvent.makeID()))
        }
        #expect(PendingCalendarEvent.makeID().count == 32)
        #expect(!PendingCalendarEvent.isValidGoogleID("abcd"))         // too short
        #expect(!PendingCalendarEvent.isValidGoogleID("abcdwxyz"))     // w–z aren't base32hex
        #expect(!PendingCalendarEvent.isValidGoogleID("ABCDEF0123"))   // uppercase
    }

    @Test func summaries() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(1500)
        #expect(PendingCalendarEvent.make(mode: "focus", start: start, end: end, taskTitle: "write report").summary == "Focus · write report")
        #expect(PendingCalendarEvent.make(mode: "focus", start: start, end: end, taskTitle: "  ").summary == "Focus")
        #expect(PendingCalendarEvent.make(mode: "focus", start: start, end: end, taskTitle: nil).summary == "Focus")
        #expect(PendingCalendarEvent.make(mode: "rest", start: start, end: end, taskTitle: "ignored").summary == "Break")
    }

    @Test func eventJSONMatchesCalendarAPI() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let event = PendingCalendarEvent.make(
            mode: "focus", start: start, end: start.addingTimeInterval(25 * 60), taskTitle: "deep work",
            id: "0123456789abcdef0123456789abcdef", timeZone: berlin
        )
        let data = try GoogleCalendarAPI.eventBody(for: event)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let startJSON = try #require(json["start"] as? [String: String])
        let endJSON = try #require(json["end"] as? [String: String])

        #expect(json["id"] as? String == "0123456789abcdef0123456789abcdef")
        #expect(json["summary"] as? String == "Focus · deep work")
        #expect(json["description"] as? String == "Logged by Focus")
        #expect(startJSON["dateTime"] == "2023-11-14T22:13:20Z")
        #expect(endJSON["dateTime"] == "2023-11-14T22:38:20Z")
        #expect(startJSON["timeZone"] == "Europe/Berlin")
        #expect(endJSON["timeZone"] == "Europe/Berlin")
    }

    @Test func pendingEventsRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [PendingCalendarEvent.make(mode: "rest", start: start, end: start.addingTimeInterval(300), taskTitle: nil)]
        let decoded = try JSONDecoder().decode([PendingCalendarEvent].self, from: JSONEncoder().encode(events))
        #expect(decoded == events)
    }

    @Test func calendarPathEscapesID() {
        #expect(GoogleCalendarAPI.calendarPath("abc@group.calendar.google.com") == "/calendars/abc@group.calendar.google.com")
        #expect(GoogleCalendarAPI.calendarPath("a/b") == "/calendars/a%2Fb")
    }
}

struct GoogleErrorExplainTests {
    @Test func disabledAPIIsExplained() {
        let body = Data(#"{"error":{"code":403,"message":"Google Calendar API has not been used in project 930489858135 before or it is disabled.","errors":[{"reason":"accessNotConfigured"}]}}"#.utf8)
        #expect(GoogleCalendarService.explain(status: 403, body: body, action: "x").contains("API is turned off"))
    }

    @Test func missingScopeIsExplained() {
        let body = Data(#"{"error":{"code":403,"message":"Request had insufficient authentication scopes.","errors":[{"reason":"insufficientPermissions"}]}}"#.utf8)
        #expect(GoogleCalendarService.explain(status: 403, body: body, action: "x").contains("permission"))
    }

    @Test func unknownBodyFallsBackToStatus() {
        #expect(GoogleCalendarService.explain(status: 500, body: Data(), action: "x") == "couldn't x (500)")
    }
}
