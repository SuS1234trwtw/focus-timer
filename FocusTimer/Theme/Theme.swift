import CoreGraphics
import SwiftUI

/// An sRGB colour as plain numbers, so it can be mixed, hashed into cache keys,
/// and handed to the off-main renderer.
struct RGB: Sendable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }

    static let black = RGB(0, 0, 0)
    static let white = RGB(1, 1, 1)

    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }

    func opacity(_ alpha: Double) -> RGB { RGB(r, g, b, alpha) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Colours a carved numeral is shaded between.
struct CarvedTone: Sendable, Hashable {
    /// Stable identity for the render cache.
    let id: String
    /// Facets turned away from the light.
    let shadow: RGB
    /// Facets facing the light.
    let highlight: RGB
    /// The extruded sides.
    let side: RGB
}

/// Everything one screen state is drawn with. Focus is dark; break inverts to light.
struct Palette: Equatable {
    let background: Color
    /// Accent for the start streaks.
    let numeralLit: Color
    /// Readout and icons.
    let ink: Color
    let secondary: Color
    let castShadow: RGB
    /// Carved numerals at rest, and lit while the timer runs.
    let carved: CarvedTone
    let carvedLit: CarvedTone

    func carvedTone(lit: Bool) -> CarvedTone { lit ? carvedLit : carved }
}

/// Colour themes, chosen in Settings. Each defines a dark focus look and a light break look;
/// every other colour (carved facets, sides, ink) is derived from those four.
enum ColorTheme: String, CaseIterable, Identifiable, Sendable {
    case graphite, ember, moss, tide, bloom, dusk

    var id: String { rawValue }

    var name: String {
        switch self {
        case .graphite: "Graphite"
        case .ember: "Ember"
        case .moss: "Moss"
        case .tide: "Tide"
        case .bloom: "Bloom"
        case .dusk: "Dusk"
        }
    }

    private var spec: (focusBackground: RGB, focusLit: RGB, restBackground: RGB, restLit: RGB) {
        switch self {
        case .graphite: (RGB(hex: 0x141414), RGB(hex: 0xF4F4F2), RGB(hex: 0xECEAE5), RGB(hex: 0x1C1C1C))
        case .ember:    (RGB(hex: 0x1B120D), RGB(hex: 0xFFA56B), RGB(hex: 0xF6E8DC), RGB(hex: 0x7C3214))
        case .moss:     (RGB(hex: 0x0F1914), RGB(hex: 0xA3E6AE), RGB(hex: 0xE3EEE4), RGB(hex: 0x1F4D2E))
        case .tide:     (RGB(hex: 0x0D1520), RGB(hex: 0x94CCFF), RGB(hex: 0xE1EBF5), RGB(hex: 0x173B63))
        case .bloom:    (RGB(hex: 0x1D1016), RGB(hex: 0xFFA3C7), RGB(hex: 0xF7E5EC), RGB(hex: 0x6E1F3F))
        case .dusk:     (RGB(hex: 0x14111F), RGB(hex: 0xC0AEFF), RGB(hex: 0xE9E5F6), RGB(hex: 0x3B2D7A))
        }
    }

    /// Focus background and lit colour, for the swatch in Settings.
    var swatch: (background: Color, accent: Color) {
        (spec.focusBackground.color, spec.focusLit.color)
    }

    func palette(for mode: TimerMode) -> Palette {
        let spec = spec
        switch mode {
        case .focus:
            let bg = spec.focusBackground, lit = spec.focusLit
            return Palette(
                background: bg.color,
                numeralLit: lit.mix(.white, 0.3).color,
                ink: lit.mix(.white, 0.6).color,
                secondary: bg.mix(.white, 0.5).color,
                castShadow: RGB.black.opacity(0.75),
                carved: CarvedTone(id: "\(rawValue).focus", shadow: bg.mix(.black, 0.4), highlight: bg.mix(.white, 0.24), side: bg.mix(.black, 0.6)),
                carvedLit: CarvedTone(id: "\(rawValue).focus.lit", shadow: lit.mix(bg, 0.55), highlight: lit.mix(.white, 0.35), side: lit.mix(bg, 0.78))
            )
        case .rest:
            let bg = spec.restBackground, lit = spec.restLit
            return Palette(
                background: bg.color,
                numeralLit: lit.color,
                ink: lit.mix(.black, 0.35).color,
                secondary: bg.mix(.black, 0.5).color,
                castShadow: RGB.black.opacity(0.28),
                carved: CarvedTone(id: "\(rawValue).rest", shadow: bg.mix(.black, 0.22), highlight: bg.mix(.white, 0.7), side: bg.mix(.black, 0.34)),
                carvedLit: CarvedTone(id: "\(rawValue).rest.lit", shadow: lit.mix(.black, 0.45), highlight: lit.mix(.white, 0.4), side: lit.mix(.black, 0.7))
            )
        }
    }
}

enum Theme {
    /// Compressed readout type, like a stopwatch label.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).width(.compressed).monospacedDigit()
    }
}

/// Carved numeral family for the big numbers, chosen in Settings.
/// Raw values match the family keys in CarvedGlyphs.json.
enum TimerFont: String, CaseIterable, Identifiable, Sendable {
    case carved, heavy, hairline, block, soft, lean

    var id: String { rawValue }

    var name: String {
        switch self {
        case .carved: "Carved"
        case .heavy: "Heavy"
        case .hairline: "Hairline"
        case .block: "Block"
        case .soft: "Soft"
        case .lean: "Lean"
        }
    }
}

/// A small tile of black and white specks, used for the background grain and the stone texture on numerals.
final class GrainTile: @unchecked Sendable {
    static let shared = GrainTile()

    /// Immutable after init, so safe to read from any thread.
    let cgImage: CGImage?

    private init() {
        let side = 160
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            cgImage = nil
            return
        }
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<7000 {
            let white = Bool.random(using: &generator)
            context.setFillColor(CGColor(gray: white ? 1 : 0, alpha: 0.55))
            context.fill(CGRect(x: Int.random(in: 0..<side, using: &generator), y: Int.random(in: 0..<side, using: &generator), width: 1, height: 1))
        }
        cgImage = context.makeImage()
    }
}

/// Fine film grain over the background, like the matte surface in the reference.
struct GrainOverlay: View {
    var body: some View {
        if let tile = GrainTile.shared.cgImage {
            Image(decorative: tile, scale: 1)
                .resizable(resizingMode: .tile)
                .opacity(0.07)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}
