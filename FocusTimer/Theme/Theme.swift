import SwiftUI
import UIKit

/// Focus is dark; break inverts to light.
struct Palette: Equatable {
    let background: Color
    /// Face of numerals that aren't lit (idle reel, neighbours).
    let numeral: Color
    /// Face of the numeral while the timer runs.
    let numeralLit: Color
    /// Readout and icons.
    let ink: Color
    let secondary: Color
    let castShadow: Color
}

enum Theme {
    static let focus = Palette(
        background: Color(hex: 0x141414),
        numeral: Color(hex: 0x2C2C2C),
        numeralLit: Color(hex: 0xF4F4F2),
        ink: Color(hex: 0xF4F4F2),
        secondary: Color(hex: 0x8C8C8C),
        castShadow: .black.opacity(0.75)
    )

    static let rest = Palette(
        background: Color(hex: 0xECEAE5),
        numeral: Color(hex: 0xDAD7D0),
        numeralLit: Color(hex: 0x1C1C1C),
        ink: Color(hex: 0x161616),
        secondary: Color(hex: 0x77746E),
        castShadow: .black.opacity(0.28)
    )

    static func palette(for mode: TimerMode) -> Palette {
        mode == .focus ? focus : rest
    }

    /// Compressed readout type, like a stopwatch label.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).width(.compressed).monospacedDigit()
    }
}

/// Typeface for the big numerals, chosen in Settings.
enum TimerFont: String, CaseIterable, Identifiable {
    case block, hairline, mono, round, serif

    var id: String { rawValue }

    var name: String {
        switch self {
        case .block: "Block"
        case .hairline: "Hairline"
        case .mono: "Mono"
        case .round: "Round"
        case .serif: "Serif"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .block:
            .system(size: size, weight: .heavy).width(.compressed)
        case .hairline:
            .system(size: size, weight: .ultraLight).width(.condensed)
        case .mono:
            UIFont(name: "JetBrainsMono-Bold", size: size) != nil
                ? .custom("JetBrainsMono-Bold", fixedSize: size)
                : .system(size: size, weight: .bold, design: .monospaced)
        case .round:
            .system(size: size, weight: .bold, design: .rounded)
        case .serif:
            .system(size: size, weight: .black, design: .serif)
        }
    }

    /// Hairline strokes are too thin to extrude convincingly.
    var extrusion: CGFloat { self == .hairline ? 0.35 : 1 }
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

/// Fine film grain over the background, like the matte surface in the reference.
struct GrainOverlay: View {
    @MainActor private static let tile: Image = {
        let side = 160
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<7000 {
                let x = Int.random(in: 0..<side, using: &generator)
                let y = Int.random(in: 0..<side, using: &generator)
                UIColor(white: Bool.random(using: &generator) ? 1 : 0, alpha: 0.55).setFill()
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return Image(uiImage: image)
    }()

    var body: some View {
        Self.tile
            .resizable(resizingMode: .tile)
            .opacity(0.07)
            .blendMode(.overlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
