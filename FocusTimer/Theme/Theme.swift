import SwiftUI
import UIKit

struct Palette: Equatable {
    let background: Color
    let surface: Color
    let border: Color
    let accent: Color
    let text: Color
    let dim: Color
}

enum Theme {
    static let focus = Palette(
        background: Color(hex: 0x1A1614),
        surface: Color(hex: 0x241E1B),
        border: Color(hex: 0x3A302A),
        accent: Color(hex: 0xF5A05A),
        text: Color(hex: 0xE8DCCF),
        dim: Color(hex: 0x8A7D72)
    )

    static let rest = Palette(
        background: Color(hex: 0x111C17),
        surface: Color(hex: 0x17261F),
        border: Color(hex: 0x28402F),
        accent: Color(hex: 0x8FD694),
        text: Color(hex: 0xD9E8DD),
        dim: Color(hex: 0x6F8577)
    )

    static func palette(for mode: TimerMode) -> Palette {
        mode == .focus ? focus : rest
    }

    enum Weight {
        case light, regular, bold

        var postScriptName: String {
            switch self {
            case .light: "JetBrainsMono-Light"
            case .regular: "JetBrainsMono-Regular"
            case .bold: "JetBrainsMono-Bold"
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .light: .light
            case .regular: .regular
            case .bold: .bold
            }
        }
    }

    /// JetBrains Mono when bundled, otherwise the system monospaced face.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        if UIFont(name: weight.postScriptName, size: size) != nil {
            return .custom(weight.postScriptName, size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight.systemWeight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
