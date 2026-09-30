import SwiftUI
import UIKit

/// Hex helpers shared by the app and the widgets (colours travel between them as "RRGGBB").
extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Parses "RRGGBB" (as stored in AppStorage); nil for an empty or malformed string.
    init?(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    private var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// "RRGGBB", for storing a colour picked on the wheel.
    var hexString: String {
        let (r, g, b) = rgb
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02lX%02lX%02lX", byte(r), byte(g), byte(b))
    }

    /// Relative luminance below the midpoint: light text reads better on it.
    var isDark: Bool {
        let (r, g, b) = rgb
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5
    }
}
