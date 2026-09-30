import SwiftUI
import UIKit

struct Palette: Equatable {
    var background: Color
    var surface: Color
    var border: Color
    var accent: Color
    var text: Color
    var dim: Color
    var style: TerminalStyle = .cozy
    /// Drives the status bar and system controls; flips when a custom background is light.
    var isDark = true

    /// Rebuilds the neutral colours around a custom background, keeping text readable on it.
    func withBackground(_ color: Color) -> Palette {
        let dark = color.isDark
        let ink = dark ? Color(hex: 0xEDEDED) : Color(hex: 0x1A1A1A)
        var palette = self
        palette.background = color
        palette.surface = color.mix(with: ink, by: 0.06)
        palette.border = color.mix(with: ink, by: 0.18)
        palette.text = ink
        palette.dim = color.mix(with: ink, by: 0.55)
        palette.isDark = dark
        return palette
    }
}

/// The terminal the app imitates: its colours, prompt, and flavour text.
enum TerminalStyle: String, CaseIterable, Identifiable {
    case cozy, powershell

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cozy: "Cozy"
        case .powershell: "PowerShell"
        }
    }

    func basePalette(for mode: TimerMode) -> Palette {
        switch (self, mode) {
        case (.cozy, .focus):
            Palette(background: Color(hex: 0x1A1614), surface: Color(hex: 0x241E1B), border: Color(hex: 0x3A302A),
                    accent: Color(hex: 0xF5A05A), text: Color(hex: 0xE8DCCF), dim: Color(hex: 0x8A7D72), style: self)
        case (.cozy, .rest):
            Palette(background: Color(hex: 0x111C17), surface: Color(hex: 0x17261F), border: Color(hex: 0x28402F),
                    accent: Color(hex: 0x8FD694), text: Color(hex: 0xD9E8DD), dim: Color(hex: 0x6F8577), style: self)
        case (.powershell, .focus):
            // Classic Windows PowerShell console blue, with its yellow command colour.
            Palette(background: Color(hex: 0x012456), surface: Color(hex: 0x032F6B), border: Color(hex: 0x1D4F91),
                    accent: Color(hex: 0xF9F1A5), text: Color(hex: 0xEEEDF0), dim: Color(hex: 0x8FA8CC), style: self)
        case (.powershell, .rest):
            Palette(background: Color(hex: 0x001A40), surface: Color(hex: 0x022452), border: Color(hex: 0x17437A),
                    accent: Color(hex: 0x16C60C), text: Color(hex: 0xEEEDF0), dim: Color(hex: 0x8FA8CC), style: self)
        }
    }

    /// Header prompt, split so the path can take the accent colour.
    var promptPath: String { self == .cozy ? "~/focus " : "PS C:\\focus" }
    var promptSymbol: String { self == .cozy ? "$ " : "> " }
    var command: String { self == .cozy ? "pomodoro" : "Start-Pomodoro" }
    var cursor: String { self == .cozy ? "▌" : "_" }
    var tasksCommand: String { self == .cozy ? "$ tasks --list" : "PS> Get-Task" }
    var emptyTasks: String {
        self == .cozy ? "// nothing queued. add something to focus on." : "# No tasks found. Type below to run New-Task."
    }
    var linePrefix: String { self == .cozy ? "> " : "PS> " }
    /// CRT scanlines and vignette suit the cozy terminal; the Windows console is flat.
    var hasScanlines: Bool { self == .cozy }
}

/// The user's look: a terminal style plus optional colours picked on the colour wheel.
struct Appearance: Equatable {
    var style: TerminalStyle
    var focusAccent: Color?
    var restAccent: Color?
    var focusBackground: Color?
    var restBackground: Color?

    func palette(for mode: TimerMode) -> Palette {
        var palette = style.basePalette(for: mode)
        if let background = mode == .focus ? focusBackground : restBackground {
            palette = palette.withBackground(background)
        }
        if let accent = mode == .focus ? focusAccent : restAccent {
            palette.accent = accent
        }
        return palette
    }
}

enum Theme {
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
