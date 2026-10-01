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

        /// The block has been started at some point (so a stopped timer is "paused", not "ready").
        /// Optional so a state saved by an older build still decodes.
        var started: Bool?
        var hasStarted: Bool { started ?? false }

        // Island button settings, copied from `IslandSettings` by the app (the extension can't read
        // the app's defaults). All optional so older states still decode; nil means "on".

        /// Master switch for the buttons.
        var controls: Bool?
        /// The pause button.
        var showToggle: Bool?
        /// The focus ↔ break button.
        var showSwitch: Bool?
        /// Buttons on the lock-screen banner too.
        var lockControls: Bool?
        /// False once the app has been terminated (e.g. swiped away), so its buttons are hidden.
        var appAlive: Bool?

        var showsToggle: Bool { showToggle ?? true }
        var showsSwitch: Bool { showSwitch ?? true }

        var isRunning: Bool { endDate != nil }
        var modeLabel: String { mode == "focus" ? "FOCUS" : "BREAK" }

        /// Whether the island / lock screen shows its buttons right now: only while the timer is
        /// actually ticking, the app is still alive, and the user hasn't turned them all off.
        /// - Parameters:
        ///   - isStale: the activity is past its stale date (we set it to `endDate`, so this is how a
        ///     view that can't re-evaluate the clock by itself learns the block has run out).
        ///   - lockScreen: asking for the lock-screen banner rather than the Dynamic Island.
        func showsControls(now: Date, isStale: Bool, lockScreen: Bool) -> Bool {
            guard controls ?? true,
                  let endDate, endDate > now,
                  appAlive ?? true,
                  !isStale
            else { return false }
            if lockScreen, !(lockControls ?? true) { return false }
            return showsToggle || showsSwitch
        }
    }

    /// The terminal prompt of the chosen style, e.g. "PS C:\\focus>".
    var prompt: String
}
