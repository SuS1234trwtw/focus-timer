import Foundation
import Observation
import UserNotifications

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
        /// Newest build an iOS notification was already posted for (or seen in the app).
        static let notifiedBuild = "update.notifiedBuild"
        /// Bool, default true: post an iOS notification when a background check finds a build.
        static let alerts = "update.alerts"
    }

    /// Always serves the newest release's source file (GitHub redirects to the asset).
    nonisolated static let sourceURL = URL(string: "https://github.com/SuS1234trwtw/focus-timer/releases/latest/download/source.json")!

    /// The app's bundle id inside the source; used to pick the right app if the source lists several.
    nonisolated static let bundleIdentifier = "com.focustimer.app"

    /// Automatic foreground checks run at most this often.
    nonisolated static let checkInterval: TimeInterval = 5 * 60

    /// How often `checkLoop()` re-checks while the app is open.
    nonisolated static let loopInterval: Duration = .seconds(15 * 60)

    private(set) var available: Update?
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    /// Build number whose banner the user closed; that build won't show the banner again.
    private(set) var dismissedBuild: Int?
    /// Set when the user taps an update notification; RootView opens Settings → updates and resets it.
    var openUpdatesRequested = false

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

    /// Checks now, then every `loopInterval` until the calling task is cancelled (run it in a `.task`).
    func checkLoop() async {
        while !Task.isCancelled {
            await checkNow()
            do { try await Task.sleep(for: Self.loopInterval) } catch { return }
        }
    }

    /// Fetches the source right away (ignoring the throttle).
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        // Nil means offline, timed out, or a GitHub hiccup: stay quiet and try again next time.
        guard let latest = await Self.fetchLatest() else { return }
        let now = Date.now
        lastChecked = now
        defaults.set(now, forKey: Key.lastCheck)
        if Self.isNewer(remoteBuild: String(latest.build), localBuild: Self.localBuild) {
            available = latest
            // Seen in the app already, so a background check won't notify about it again.
            if latest.build > (defaults.object(forKey: Key.notifiedBuild) as? Int ?? 0) {
                defaults.set(latest.build, forKey: Key.notifiedBuild)
            }
        } else {
            available = nil
        }
    }

    /// Downloads and decodes the source; nil on any network or format error. Safe off the main actor.
    nonisolated static func fetchLatest() async -> Update? {
        var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return decodeLatest(from: data)
    }

    // MARK: Background check

    nonisolated static let notificationRoute = "updates"

    /// Background-refresh work: if a new build is out and nobody was told yet, post one iOS notification.
    /// Never asks for notification permission (that would prompt from the background); posts only if allowed.
    nonisolated static func backgroundCheck() async {
        guard let latest = await fetchLatest(), let installed = Int(localBuild) else { return }
        let defaults = UserDefaults.standard
        guard shouldNotify(
            latestBuild: latest.build,
            installedBuild: installed,
            notifiedBuild: defaults.object(forKey: Key.notifiedBuild) as? Int,
            alertsOn: defaults.object(forKey: Key.alerts) as? Bool ?? true
        ), !Task.isCancelled else { return }

        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let content = UNMutableNotificationContent()
        content.title = "Focus \(latest.version) (\(latest.build)) is out"
        content.body = "tap to update"
        content.sound = .default
        content.userInfo = ["route": notificationRoute]
        let request = UNNotificationRequest(identifier: "update.\(latest.build)", content: content, trigger: nil)
        do {
            try await center.add(request)
            defaults.set(latest.build, forKey: Key.notifiedBuild)
        } catch {
            // Not posted: the next background run tries again.
        }
    }

    // MARK: Pure helpers (tested)

    /// Notify once per build: only for a build newer than the installed one and than the last one notified, and only with alerts on.
    nonisolated static func shouldNotify(latestBuild: Int, installedBuild: Int, notifiedBuild: Int?, alertsOn: Bool) -> Bool {
        alertsOn && latestBuild > installedBuild && latestBuild > (notifiedBuild ?? Int.min)
    }

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
