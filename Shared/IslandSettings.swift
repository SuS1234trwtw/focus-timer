import Foundation

/// Which buttons the Live Activity (Dynamic Island + lock screen) shows. Stored in
/// `UserDefaults.standard` by the app; the widget extension never reads these (there's no App Group),
/// it only sees the copies the app puts into `FocusActivityAttributes.ContentState`.
enum IslandSettings {
    enum Key {
        /// Master switch: no buttons at all when off.
        static let buttons = "island.buttons"
        /// The pause button.
        static let pauseButton = "island.pauseButton"
        /// The focus ↔ break button.
        static let switchButton = "island.switchButton"
        /// Show the buttons on the lock-screen banner too (the Dynamic Island is unaffected).
        static let lockScreenButtons = "island.lockScreenButtons"
    }

    enum Default {
        static let buttons = true
        static let pauseButton = true
        static let switchButton = true
        static let lockScreenButtons = true
    }

    static func buttons(in defaults: UserDefaults = .standard) -> Bool {
        bool(Key.buttons, default: Default.buttons, in: defaults)
    }

    static func pauseButton(in defaults: UserDefaults = .standard) -> Bool {
        bool(Key.pauseButton, default: Default.pauseButton, in: defaults)
    }

    static func switchButton(in defaults: UserDefaults = .standard) -> Bool {
        bool(Key.switchButton, default: Default.switchButton, in: defaults)
    }

    static func lockScreenButtons(in defaults: UserDefaults = .standard) -> Bool {
        bool(Key.lockScreenButtons, default: Default.lockScreenButtons, in: defaults)
    }

    /// A stored Bool, or `fallback` when the user never touched the setting.
    private static func bool(_ key: String, default fallback: Bool, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
