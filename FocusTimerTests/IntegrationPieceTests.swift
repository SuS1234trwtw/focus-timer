import Foundation
import SwiftUI
import Testing
@testable import FocusTimer

struct SpotifyAuthTests {
    @Test func pkceChallengeMatchesRFC7636Example() {
        // RFC 7636, Appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(SpotifyAuth.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsURLSafeAndLongEnough() {
        let verifier = SpotifyAuth.makeVerifier()
        #expect(verifier.count >= 43)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func callbackYieldsCode() throws {
        let url = try #require(URL(string: "focustimer://spotify-callback?code=abc123&state=s1"))
        #expect(try SpotifyAuth.code(from: url, expectedState: "s1") == "abc123")
    }

    @Test func callbackRejectsWrongState() throws {
        let url = try #require(URL(string: "focustimer://spotify-callback?code=abc123&state=other"))
        #expect(throws: SpotifyAuth.CallbackError.stateMismatch) {
            try SpotifyAuth.code(from: url, expectedState: "s1")
        }
    }

    @Test func callbackReportsDenial() throws {
        let url = try #require(URL(string: "focustimer://spotify-callback?error=access_denied&state=s1"))
        #expect(throws: SpotifyAuth.CallbackError.denied("access_denied")) {
            try SpotifyAuth.code(from: url, expectedState: "s1")
        }
    }
}

struct SpotifyTokenFailureTests {
    @Test func deadRefreshTokenUnlinks() {
        let body = Data(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#.utf8)
        #expect(SpotifyAuth.tokenFailure(status: 400, body: body) == .revoked)
        #expect(SpotifyAuth.tokenFailure(status: 401, body: Data()) == .revoked)
    }

    @Test func hiccupsKeepTheLogin() {
        #expect(SpotifyAuth.tokenFailure(status: 500, body: Data()) == .transient)
        #expect(SpotifyAuth.tokenFailure(status: 503, body: Data()) == .transient)
        #expect(SpotifyAuth.tokenFailure(status: 429, body: Data()) == .transient)
        #expect(SpotifyAuth.tokenFailure(status: 400, body: Data(#"{"error":"invalid_request"}"#.utf8)) == .transient)
    }
}

struct FontChoicesTests {
    @Test func defaultsPerStyle() {
        #expect(FontChoices.font(for: .mono, in: "") == .geist)
        #expect(FontChoices.font(for: .cozy, in: "") == .jetbrains)
        #expect(FontChoices.font(for: .cmd, in: "") == .cascadia)
        #expect(FontChoices.font(for: .ubuntu, in: "") == .ubuntu)
    }

    @Test func storesEachStyleIndependently() {
        var stored = FontChoices.setting(.vt323, for: .cmd, in: "")
        stored = FontChoices.setting(.dejavu, for: .ubuntu, in: stored)
        #expect(FontChoices.font(for: .cmd, in: stored) == .vt323)
        #expect(FontChoices.font(for: .ubuntu, in: stored) == .dejavu)
        #expect(FontChoices.font(for: .cozy, in: stored) == .jetbrains)
    }

    @Test func ignoresGarbage() {
        #expect(FontChoices.font(for: .cmd, in: "cmd=nope;;=;x") == .cascadia)
    }

    @Test func migratesOldPerStyleKeys() throws {
        let suite = "FontChoicesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("plex", forKey: "fontCozy")
        FontChoices.migrate(defaults)
        let stored = try #require(defaults.string(forKey: FontChoices.key))
        #expect(FontChoices.font(for: .cozy, in: stored) == .plex)
        #expect(FontChoices.font(for: .powershell, in: stored) == .cascadia)
    }
}

struct MonoStyleTests {
    @Test func monoIsListedFirstAndFlat() {
        #expect(TerminalStyle.allCases.first == .mono)
        #expect(TerminalStyle.mono.isFlat)
        #expect(!TerminalStyle.cozy.isFlat)
        #expect(TerminalStyle.mono.radius(10) == 0)
        #expect(TerminalStyle.cozy.radius(10) == 10)
    }

    @Test func monoMatchesTheWebsiteInk() {
        let focus = TerminalStyle.mono.basePalette(for: .focus)
        #expect(focus.background == Color(hex: 0x050505))
        #expect(focus.text == Color(hex: 0xF5F5F2))
        #expect(TerminalStyle.mono.label("3 open") == "3 OPEN")
        #expect(TerminalStyle.cozy.label("3 open") == "3 open")
    }
}

struct TimerSnapshotTests {
    @Test func roundTripsThroughDefaults() throws {
        let suite = "TimerSnapshotTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let snapshot = TimerSnapshot(
            mode: "focus", endDate: Date(timeIntervalSince1970: 2_000_000_000), remaining: 1200, total: 1500,
            taskTitle: "ship it", style: "cmd", prompt: "C:\\Users\\focus>", accentHex: "3B78FF",
            backgroundHex: "0C0C0C", textHex: "CCCCCC", dimHex: "767676", trackLine: "Song — Artist"
        )
        snapshot.save(to: defaults)
        #expect(TimerSnapshot.load(from: defaults) == snapshot)
    }
}

struct SpotifyInviteOnlyTests {
    @Test func unregisteredAccountIsDetected() {
        let body = Data("Check settings on developer.spotify.com/dashboard, the user may not be registered.".utf8)
        #expect(SpotifyService.isNotRegistered(status: 403, body: body))
    }

    @Test func premiumRefusalIsNotMistakenForInviteOnly() {
        let body = Data(#"{"error":{"status":403,"message":"Player command failed: Premium required"}}"#.utf8)
        #expect(!SpotifyService.isNotRegistered(status: 403, body: body))
        #expect(!SpotifyService.isNotRegistered(status: 200, body: Data("may not be registered".utf8)))
    }
}
