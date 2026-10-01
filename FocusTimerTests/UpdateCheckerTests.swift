import Foundation
import Testing
@testable import FocusTimer

struct UpdateCheckerTests {
    private let sample = """
    {
      "name": "Focus",
      "identifier": "io.github.sus1234trwtw.focus",
      "sourceURL": "https://example.com/ignored",
      "news": [],
      "apps": [
        {
          "name": "Focus",
          "bundleIdentifier": "com.focustimer.app",
          "developerName": "unknown field",
          "versions": [
            {
              "version": "1.7.1",
              "buildVersion": "17",
              "date": "2026-10-01T06:00:00Z",
              "localizedDescription": "notes",
              "downloadURL": "https://github.com/SuS1234trwtw/focus-timer/releases/download/v1.7.1-17/FocusTimer-1.7.1-17.ipa",
              "size": 6370878,
              "minOSVersion": "26.0"
            },
            {
              "version": "1.7.0",
              "buildVersion": "16",
              "downloadURL": "https://example.com/FocusTimer-1.7.0-16.ipa"
            }
          ]
        }
      ]
    }
    """

    @Test func decodesLatestVersion() throws {
        let update = try #require(UpdateChecker.decodeLatest(from: Data(sample.utf8)))
        #expect(update.version == "1.7.1")
        #expect(update.build == 17)
        #expect(update.notes == "notes")
        #expect(update.downloadURL.absoluteString == "https://github.com/SuS1234trwtw/focus-timer/releases/download/v1.7.1-17/FocusTimer-1.7.1-17.ipa")
    }

    @Test func picksHighestBuildRegardlessOfOrder() throws {
        let json = """
        {"apps":[{"bundleIdentifier":"com.focustimer.app","versions":[
          {"version":"1.0","buildVersion":"3","downloadURL":"https://example.com/a.ipa"},
          {"version":"1.1","buildVersion":12,"downloadURL":"https://example.com/b.ipa"}
        ]}]}
        """
        let update = try #require(UpdateChecker.decodeLatest(from: Data(json.utf8)))
        #expect(update.build == 12)
        #expect(update.version == "1.1")
        #expect(update.notes.isEmpty)
    }

    @Test(arguments: ["", "not json", "{}", #"{"apps":[]}"#, #"{"apps":[{"versions":[{"version":"1.0","buildVersion":"abc","downloadURL":"https://e.com/x.ipa"}]}]}"#])
    func decodeFailureIsNil(_ text: String) {
        #expect(UpdateChecker.decodeLatest(from: Data(text.utf8)) == nil)
    }

    @Test func isNewerComparesBuildNumbers() {
        #expect(UpdateChecker.isNewer(remoteBuild: "17", localBuild: "16"))
        #expect(UpdateChecker.isNewer(remoteBuild: "100", localBuild: "99"))
        #expect(!UpdateChecker.isNewer(remoteBuild: "16", localBuild: "16"))
        #expect(!UpdateChecker.isNewer(remoteBuild: "15", localBuild: "16"))
        #expect(!UpdateChecker.isNewer(remoteBuild: "abc", localBuild: "16"))
        #expect(!UpdateChecker.isNewer(remoteBuild: "17", localBuild: ""))
        #expect(!UpdateChecker.isNewer(remoteBuild: "1.7.1", localBuild: "16"))
    }

    @Test func sideStoreURLEncodesSourceAndRoundTrips() throws {
        let url = UpdateChecker.sideStoreURL()
        #expect(url.scheme == "sidestore")
        #expect(url.host() == "source")

        // The query holds a single, fully escaped parameter.
        let query = try #require(url.query(percentEncoded: true))
        #expect(query.hasPrefix("url="))
        let encoded = String(query.dropFirst("url=".count))
        for reserved in [":", "/", "?", "&", "="] {
            #expect(!encoded.contains(reserved))
        }

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let value = try #require(components.queryItems?.first { $0.name == "url" }?.value)
        #expect(value == UpdateChecker.sourceURL.absoluteString)
        #expect(encoded.removingPercentEncoding == UpdateChecker.sourceURL.absoluteString)
    }
}
