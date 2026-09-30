import AppIntents
import Foundation

/// Hooks the app installs at launch. Live Activity intents run in the app's process
/// (iOS launches it in the background if needed); in the widget process these stay nil.
@MainActor
enum TimerIntentBridge {
    static var toggle: (@MainActor () -> Void)?
    static var skip: (@MainActor () -> Void)?
}

/// Pause / resume from the Dynamic Island or lock screen.
struct ToggleTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume focus timer"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerIntentBridge.toggle?()
        return .result()
    }
}

/// Ends the current block and readies the next one (focus → break, break → focus).
struct SkipBlockIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip to next block"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        TimerIntentBridge.skip?()
        return .result()
    }
}
