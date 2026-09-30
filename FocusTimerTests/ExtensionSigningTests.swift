import Foundation
import Testing
@testable import FocusTimer

struct ExtensionSigningTests {
    /// A provisioning profile is a CMS blob with the plist embedded as plain XML; surround it with junk bytes.
    func profile(appIdentifier: String) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Entitlements</key><dict>
        <key>application-identifier</key><string>\(appIdentifier)</string>
        </dict></dict></plist>
        """
        return Data([0x30, 0x82, 0x1F, 0x00]) + Data(xml.utf8) + Data([0xA0, 0x82, 0x00])
    }

    @Test func readsAppIDWithoutTeamPrefix() {
        #expect(ExtensionSigning.appID(fromProvisioningProfile: profile(appIdentifier: "AB12CD34EF.com.focustimer.app.widgets")) == "com.focustimer.app.widgets")
    }

    @Test func garbageHasNoAppID() {
        #expect(ExtensionSigning.appID(fromProvisioningProfile: Data([1, 2, 3])) == nil)
    }

    @Test func matchesExactAndWildcard() {
        #expect(ExtensionSigning.matches(profile: "com.a.app.widgets", bundleID: "com.a.app.widgets"))
        #expect(ExtensionSigning.matches(profile: "com.a.*", bundleID: "com.a.app.widgets"))
        #expect(!ExtensionSigning.matches(profile: "com.a.app", bundleID: "com.a.app.widgets"))
    }

    @Test func verdictFlagsProfileMismatch() {
        let signing = ExtensionSigning(appID: "com.a.app", extensionID: "com.a.app.widgets",
                                       extensionProfileID: "com.a.app", appProfileID: "com.a.app")
        #expect(signing.verdict.hasPrefix("✗"))
    }

    @Test func verdictAcceptsCorrectSigning() {
        let signing = ExtensionSigning(appID: "com.a.app", extensionID: "com.a.app.widgets",
                                       extensionProfileID: "com.a.app.widgets", appProfileID: "com.a.app")
        #expect(signing.verdict == "✓ signed correctly")
    }
}
