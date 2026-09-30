import AppIntents
import Foundation

/// Hooks the app installs at launch. Live Activity intents run in the app's process
/// (iOS launches it in the background if needed); in the widget process these stay nil.
@MainActor
enum TimerIntentBridge {
    static var toggle: (@MainActor () -> Void)?
    static var switchMode: (@MainActor () -> Void)?
}

/// Start, pause or resume from the Dynamic Island or lock screen.
struct ToggleTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start or pause focus timer"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerIntentBridge.toggle?()
        return .result()
    }
}

/// Switches focus ↔ break and starts the new block right away.
struct SwitchModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Switch between focus and break"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerIntentBridge.switchMode?()
        return .result()
    }
}
