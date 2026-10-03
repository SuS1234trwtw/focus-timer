import UIKit

/// What the phone's hardware can show. Live Activities appear on the lock screen of every iPhone;
/// only Dynamic Island phones also get the island, so wording and island-only options adapt.
@MainActor
enum DeviceCapabilities {
    private static var cachedIsland: Bool?

    /// True on iPhones with a Dynamic Island. Measured once a window exists, then cached.
    static var hasDynamicIsland: Bool {
        if let cachedIsland { return cachedIsland }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        // No window yet: say no, and don't cache the guess.
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return false }
        // In landscape the cutout's inset moves to a side, so take the largest edge.
        let insets = window.safeAreaInsets
        let value = hasIsland(topInset: max(insets.top, insets.left, insets.right),
                              idiom: UIDevice.current.userInterfaceIdiom)
        cachedIsland = value
        return value
    }

    /// Island iPhones have a cutout inset of 59 pt or more; notch phones ~44–50, home-button
    /// phones ~20. iPads never have an island.
    // ponytail: inset heuristic; swap for a model-identifier table if Apple ships a >= 59 pt notch.
    nonisolated static func hasIsland(topInset: CGFloat, idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .phone && topInset >= 59
    }
}
