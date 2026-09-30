import CoreText
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
    var font: TerminalFont = .jetbrains

    /// The terminal font at a given size and weight.
    @MainActor
    func mono(_ size: CGFloat, _ weight: Theme.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        font.font(size, weight, relativeTo: style)
    }

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

    /// JetBrains Mono for the cozy terminal; Cascadia Mono, Windows Terminal's font, for PowerShell.
    var defaultFont: TerminalFont { self == .cozy ? .jetbrains : .cascadia }

    func basePalette(for mode: TimerMode) -> Palette {
        var palette = colors(for: mode)
        palette.font = defaultFont
        return palette
    }

    private func colors(for mode: TimerMode) -> Palette {
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
    var font: TerminalFont?
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
        if let font { palette.font = font }
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

    /// JetBrains Mono, for the few places without a palette at hand.
    @MainActor
    static func mono(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        TerminalFont.jetbrains.font(size, weight, relativeTo: style)
    }
}

/// Monospaced terminal fonts the user can pick per style.
enum TerminalFont: String, CaseIterable, Identifiable {
    case jetbrains, cascadia, sfMono, menlo, courier, plex, fira, sourceCode, space, ubuntu, anonymous, shareTech, vt323

    var id: String { rawValue }

    var name: String {
        switch self {
        case .jetbrains: "JetBrains Mono"
        case .cascadia: "Cascadia Mono"
        case .sfMono: "SF Mono"
        case .menlo: "Menlo"
        case .courier: "Courier New"
        case .plex: "IBM Plex Mono"
        case .fira: "Fira Mono"
        case .sourceCode: "Source Code Pro"
        case .space: "Space Mono"
        case .ubuntu: "Ubuntu Mono"
        case .anonymous: "Anonymous Pro"
        case .shareTech: "Share Tech Mono"
        case .vt323: "VT323"
        }
    }

    private enum Source {
        /// Bundled TTFs by file name; missing weights fall back to regular.
        case bundled(light: String?, regular: String, bold: String?)
        /// Fonts that ship with iOS, by PostScript name.
        case installed(regular: String, bold: String)
        /// The system monospaced design (SF Mono).
        case system
    }

    private var source: Source {
        switch self {
        case .jetbrains: .bundled(light: "JetBrainsMono-Light", regular: "JetBrainsMono-Regular", bold: "JetBrainsMono-Bold")
        case .cascadia: .bundled(light: "CascadiaMono-Light", regular: "CascadiaMono-Regular", bold: "CascadiaMono-Bold")
        case .sfMono: .system
        case .menlo: .installed(regular: "Menlo-Regular", bold: "Menlo-Bold")
        case .courier: .installed(regular: "CourierNewPSMT", bold: "CourierNewPS-BoldMT")
        case .plex: .bundled(light: "IBMPlexMono-Light", regular: "IBMPlexMono-Regular", bold: "IBMPlexMono-Bold")
        case .fira: .bundled(light: nil, regular: "FiraMono-Regular", bold: "FiraMono-Bold")
        case .sourceCode: .bundled(light: "SourceCodePro-Light", regular: "SourceCodePro-Regular", bold: "SourceCodePro-Bold")
        case .space: .bundled(light: nil, regular: "SpaceMono-Regular", bold: "SpaceMono-Bold")
        case .ubuntu: .bundled(light: nil, regular: "UbuntuMono-Regular", bold: "UbuntuMono-Bold")
        case .anonymous: .bundled(light: nil, regular: "AnonymousPro-Regular", bold: "AnonymousPro-Bold")
        case .shareTech: .bundled(light: nil, regular: "ShareTechMono-Regular", bold: nil)
        case .vt323: .bundled(light: nil, regular: "VT323-Regular", bold: nil)
        }
    }

    @MainActor
    func font(_ size: CGFloat, _ weight: Theme.Weight, relativeTo style: Font.TextStyle) -> Font {
        let fallback = Font.system(size: size, weight: weight.systemWeight, design: .monospaced)
        switch source {
        case .system:
            return fallback
        case let .installed(regular, bold):
            let name = weight == .bold ? bold : regular
            return UIFont(name: name, size: size) != nil ? .custom(name, size: size, relativeTo: style) : fallback
        case let .bundled(light, regular, bold):
            let file: String
            switch weight {
            case .light: file = light ?? regular
            case .regular: file = regular
            case .bold: file = bold ?? regular
            }
            guard let name = FontRegistry.postScriptName(forFile: file) else { return fallback }
            return .custom(name, size: size, relativeTo: style)
        }
    }
}

/// Registers the bundled fonts at launch and remembers each file's PostScript name,
/// read from the font itself so nothing depends on hand-typed names.
@MainActor
enum FontRegistry {
    private static var names: [String: String] = [:]

    static func registerBundledFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            guard
                let provider = CGDataProvider(url: url as CFURL),
                let font = CGFont(provider),
                let postScriptName = font.postScriptName as String?
            else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            names[url.deletingPathExtension().lastPathComponent] = postScriptName
        }
    }

    static func postScriptName(forFile file: String) -> String? {
        names[file]
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
