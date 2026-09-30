import ActivityKit
import Foundation

/// The Live Activity shown on the lock screen and in the Dynamic Island while a block runs or is paused.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "focus" or "rest".
        var mode: String
        /// Set while running; the countdown renders itself from it, so the app needn't wake up.
        var endDate: Date?
        /// Seconds left, shown frozen while paused.
        var remaining: TimeInterval
        var total: TimeInterval
        var taskTitle: String?
        var accentHex: String
        var backgroundHex: String
        var textHex: String
        var dimHex: String
        /// e.g. "Song — Artist" from Spotify, when linked.
        var trackLine: String?

        var isRunning: Bool { endDate != nil }
        var modeLabel: String { mode == "focus" ? "FOCUS" : "BREAK" }
    }

    /// The terminal prompt of the chosen style, e.g. "PS C:\\focus>".
    var prompt: String
}
