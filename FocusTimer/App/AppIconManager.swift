import os
import UIKit

/// Switches the home-screen icon to match the terminal style (alternate icons from the asset catalog).
@MainActor
enum AppIconManager {
    static let followsStyleKey = "appIcon.followsStyle"

    private static let log = Logger(subsystem: "com.focustimer.app", category: "AppIcon")

    /// The alternate icon for a style; nil means the primary icon (mono).
    static func iconName(for style: TerminalStyle) -> String? {
        switch style {
        case .mono: nil
        case .cozy: "AppIcon-cozy"
        case .powershell: "AppIcon-powershell"
        case .cmd: "AppIcon-cmd"
        case .ubuntu: "AppIcon-ubuntu"
        }
    }

    /// Whether the icon should follow the style; on unless the user turned it off.
    static var followsStyle: Bool {
        UserDefaults.standard.object(forKey: followsStyleKey) as? Bool ?? true
    }

    static func apply(style: TerminalStyle) {
        let app = UIApplication.shared
        let target = iconName(for: style)
        guard followsStyle, app.supportsAlternateIcons, app.alternateIconName != target else { return }
        Task {
            do {
                try await app.setAlternateIconName(target)
            } catch {
                log.error("could not set app icon \(target ?? "AppIcon", privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
