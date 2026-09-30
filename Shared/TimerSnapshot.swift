import Foundation

/// The App Group the app and the widgets share. Sideloading may strip the entitlement;
/// `isAvailable` tells the widgets whether live data is reachable.
enum AppGroup {
    static let identifier = "group.com.focustimer.app"

    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    static var defaults: UserDefaults? {
        isAvailable ? UserDefaults(suiteName: identifier) : nil
    }
}

/// What the home and lock-screen widgets need to draw the timer without the app running.
struct TimerSnapshot: Codable, Equatable, Sendable {
    /// "focus" or "rest".
    var mode: String
    /// Set while running: the widgets count down to it on their own.
    var endDate: Date?
    /// Seconds left when paused or idle.
    var remaining: TimeInterval
    var total: TimeInterval
    var taskTitle: String?
    var style: String
    var prompt: String
    var accentHex: String
    var backgroundHex: String
    var textHex: String
    var dimHex: String
    var trackLine: String?

    var isRunning: Bool { endDate.map { $0 > .now } ?? false }

    private static let key = "timer.snapshot.v1"

    static func load(from defaults: UserDefaults? = AppGroup.defaults) -> TimerSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TimerSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults? = AppGroup.defaults) {
        guard let defaults, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
