import Foundation

/// Reads how the installed widget extension was signed, to explain a Dynamic Island that iOS creates
/// but never draws. iOS only runs an extension whose bundle ID sits under the app's and whose
/// provisioning profile was issued for that same ID; a re-signer that renames one without the other
/// leaves the extension installed but ignored (no widget in the gallery, an empty island).
struct ExtensionSigning {
    let appID: String?
    let extensionID: String?
    /// The App ID the extension's embedded profile was issued for, without the team prefix.
    let extensionProfileID: String?
    let appProfileID: String?

    static func current(extensionName: String = "FocusWidgets") -> ExtensionSigning {
        let appex = Bundle.main.builtInPlugInsURL?.appending(path: "\(extensionName).appex")
        let appexBundle = appex.flatMap(Bundle.init(url:))
        return ExtensionSigning(
            appID: Bundle.main.bundleIdentifier,
            extensionID: appexBundle?.bundleIdentifier,
            extensionProfileID: appex.flatMap { profileAppID(in: $0) },
            appProfileID: profileAppID(in: Bundle.main.bundleURL)
        )
    }

    /// Plain-language verdict for Settings.
    var verdict: String {
        guard let appID, let extensionID else { return "extension missing" }
        guard extensionID.hasPrefix(appID + ".") else { return "✗ extension ID isn't under the app's ID" }
        guard let extensionProfileID else { return "? no profile in the extension (unsigned?)" }
        guard Self.matches(profile: extensionProfileID, bundleID: extensionID) else {
            return "✗ extension profile is for \(extensionProfileID)"
        }
        return "✓ signed correctly"
    }

    static func matches(profile: String, bundleID: String) -> Bool {
        if profile == "*" { return true }
        if profile.hasSuffix(".*") { return bundleID.hasPrefix(String(profile.dropLast(1))) }
        return profile == bundleID
    }

    /// `application-identifier` from `<bundle>/embedded.mobileprovision`, e.g. "ABCDE12345.com.x.widgets" → "com.x.widgets".
    static func profileAppID(in bundleURL: URL) -> String? {
        guard let data = try? Data(contentsOf: bundleURL.appending(path: "embedded.mobileprovision")) else { return nil }
        return appID(fromProvisioningProfile: data)
    }

    /// The profile is a signed CMS blob with the plist stored as plain XML inside it.
    static func appID(fromProvisioningProfile data: Data) -> String? {
        guard
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
            let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
            let entitlements = plist["Entitlements"] as? [String: Any],
            let identifier = entitlements["application-identifier"] as? String
        else { return nil }
        // Strip the team ID prefix.
        guard let dot = identifier.firstIndex(of: ".") else { return identifier }
        return String(identifier[identifier.index(after: dot)...])
    }
}
