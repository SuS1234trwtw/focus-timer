import Foundation
import Observation

/// Checks the GitHub "latest release" AltStore/SideStore source for a newer build.
///
/// iOS can't install a sideloaded update by itself, so this only tells the user one exists and
/// links to the IPA (or SideStore). Network errors are silent: the next check just tries again.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Update: Equatable, Sendable {
        let version: String
        let build: Int
        let notes: String
        let downloadURL: URL
    }

    enum Key {
        static let lastCheck = "update.lastCheck"
        static let dismissedBuild = "update.dismissedBuild"
    }

    /// Always serves the newest release's source file (GitHub redirects to the asset).
    nonisolated static let sourceURL = URL(string: "https://github.com/SuS1234trwtw/focus-timer/releases/latest/download/source.json")!

    /// The app's bundle id inside the source; used to pick the right app if the source lists several.
    nonisolated static let bundleIdentifier = "com.focustimer.app"

    /// Automatic checks run at most this often.
    nonisolated static let checkInterval: TimeInterval = 6 * 60 * 60

    private(set) var available: Update?
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    /// Build number whose banner the user closed; that build won't show the banner again.
    private(set) var dismissedBuild: Int?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastChecked = defaults.object(forKey: Key.lastCheck) as? Date
        dismissedBuild = defaults.object(forKey: Key.dismissedBuild) as? Int
    }

    /// True when there's a newer build the user hasn't dismissed the banner for.
    var showsBanner: Bool {
        guard let available else { return false }
        return available.build != dismissedBuild
    }

    func dismissBanner() {
        guard let available else { return }
        dismissedBuild = available.build
        defaults.set(available.build, forKey: Key.dismissedBuild)
    }

    /// Checks only if the last successful check was more than `checkInterval` ago.
    func checkIfDue() async {
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.checkInterval, lastChecked <= .now {
            return
        }
        await checkNow()
    }

    /// Fetches the source right away (ignoring the throttle).
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return }
            guard let latest = Self.decodeLatest(from: data) else { return }
            let now = Date.now
            lastChecked = now
            defaults.set(now, forKey: Key.lastCheck)
            if Self.isNewer(remoteBuild: String(latest.build), localBuild: Self.localBuild) {
                available = latest
            } else {
                available = nil
            }
        } catch {
            // Offline, timed out, or GitHub hiccup: stay quiet and try again next time.
        }
    }

    // MARK: Pure helpers (tested)

    /// The installed build number (`CFBundleVersion`), e.g. "17".
    nonisolated static var localBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    /// Whether `remoteBuild` is a higher build number than `localBuild`. Anything non-numeric is never newer.
    nonisolated static func isNewer(remoteBuild: String, localBuild: String) -> Bool {
        guard let remote = Int(remoteBuild.trimmingCharacters(in: .whitespacesAndNewlines)),
              let local = Int(localBuild.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return remote > local
    }

    /// The highest-build version of Focus listed in an AltStore source, or nil if it can't be read.
    nonisolated static func decodeLatest(from data: Data) -> Update? {
        guard let source = try? JSONDecoder().decode(SourceFile.self, from: data) else { return nil }
        let apps = source.apps ?? []
        guard let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) ?? apps.first else { return nil }
        let updates = (app.versions ?? []).compactMap { entry -> Update? in
            guard let version = entry.version, let build = entry.buildVersion,
                  let link = entry.downloadURL, let url = URL(string: link) else { return nil }
            return Update(version: version, build: build, notes: entry.localizedDescription ?? "", downloadURL: url)
        }
        return updates.max { $0.build < $1.build }
    }

    /// Opens SideStore's "add source" flow for this app's source.
    nonisolated static func sideStoreURL() -> URL {
        // Only unreserved characters stay literal, so ':' '/' '?' '&' '=' are all escaped.
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = sourceURL.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "sidestore://source?url=" + encoded)!
    }
}

// MARK: Source file (AltStore source v2, only the fields we read)

private struct SourceFile: Decodable {
    let apps: [SourceApp]?
}

private struct SourceApp: Decodable {
    let bundleIdentifier: String?
    let versions: [SourceVersion]?
}

private struct SourceVersion: Decodable {
    let version: String?
    let buildVersion: Int?
    let localizedDescription: String?
    let downloadURL: String?

    private enum CodingKeys: String, CodingKey {
        case version, buildVersion, localizedDescription, downloadURL
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        localizedDescription = try? container.decodeIfPresent(String.self, forKey: .localizedDescription)
        downloadURL = try? container.decodeIfPresent(String.self, forKey: .downloadURL)
        // buildVersion is a string in the spec, but accept a bare number too.
        if let text = try? container.decodeIfPresent(String.self, forKey: .buildVersion) {
            buildVersion = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .buildVersion) {
            buildVersion = number
        } else {
            buildVersion = nil
        }
    }
}
