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
    case mono, cozy, powershell, cmd, ubuntu

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mono: "Mono"
        case .cozy: "Cozy"
        case .powershell: "PowerShell"
        case .cmd: "CMD"
        case .ubuntu: "Ubuntu"
        }
    }

    /// Each terminal's own font: Geist Mono for mono (the website's font), JetBrains Mono for cozy,
    /// Cascadia Mono (Windows Terminal) for PowerShell and CMD, Ubuntu Mono for Ubuntu.
    var defaultFont: TerminalFont {
        switch self {
        case .mono: .geist
        case .cozy: .jetbrains
        case .powershell, .cmd: .cascadia
        case .ubuntu: .ubuntu
        }
    }

    func basePalette(for mode: TimerMode) -> Palette {
        var palette = colors(for: mode)
        palette.font = defaultFont
        return palette
    }

    private func colors(for mode: TimerMode) -> Palette {
        switch (self, mode) {
        case (.mono, .focus):
            // The website: near-black, off-white text and accent, faint hairlines.
            Palette(background: Color(hex: 0x050505), surface: Color(hex: 0x0C0C0C), border: Color(hex: 0x2A2A29),
                    accent: Color(hex: 0xF5F5F2), text: Color(hex: 0xF5F5F2), dim: Color(hex: 0x8C8C89), style: self)
        case (.mono, .rest):
            // Same ink on a break, lifted a little so the switch still reads.
            Palette(background: Color(hex: 0x0D0D0D), surface: Color(hex: 0x151515), border: Color(hex: 0x323231),
                    accent: Color(hex: 0xC9C9C5), text: Color(hex: 0xF5F5F2), dim: Color(hex: 0x8C8C89), style: self)
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
        case (.cmd, .focus):
            // Windows Terminal "Campbell": near-black, light grey text, bright blue.
            Palette(background: Color(hex: 0x0C0C0C), surface: Color(hex: 0x161616), border: Color(hex: 0x2E2E2E),
                    accent: Color(hex: 0x3B78FF), text: Color(hex: 0xCCCCCC), dim: Color(hex: 0x767676), style: self)
        case (.cmd, .rest):
            Palette(background: Color(hex: 0x101418), surface: Color(hex: 0x181D22), border: Color(hex: 0x2A3138),
                    accent: Color(hex: 0x16C60C), text: Color(hex: 0xCCCCCC), dim: Color(hex: 0x767676), style: self)
        case (.ubuntu, .focus):
            // GNOME Terminal on Ubuntu: aubergine, white text, Ubuntu orange.
            Palette(background: Color(hex: 0x300A24), surface: Color(hex: 0x3B1230), border: Color(hex: 0x5A2A4D),
                    accent: Color(hex: 0xE95420), text: Color(hex: 0xFFFFFF), dim: Color(hex: 0xB08FA8), style: self)
        case (.ubuntu, .rest):
            Palette(background: Color(hex: 0x1E0A18), surface: Color(hex: 0x2A1223), border: Color(hex: 0x472340),
                    accent: Color(hex: 0x8AE234), text: Color(hex: 0xFFFFFF), dim: Color(hex: 0xB08FA8), style: self)
        }
    }

    /// Ubuntu's green `user@host` before the path; nil for the other terminals.
    var promptHost: String? { self == .ubuntu ? "focus@ubuntu" : nil }
    /// Colour of `promptHost` (GNOME Terminal's bold green).
    var promptHostColor: Color { Color(hex: 0x8AE234) }

    /// Header prompt, split so the path can take the accent colour.
    var promptPath: String {
        switch self {
        case .mono, .cozy: "~/focus "
        case .powershell: "PS C:\\focus"
        case .cmd: "C:\\Users\\focus"
        case .ubuntu: ":~/focus"
        }
    }

    var promptSymbol: String {
        switch self {
        case .mono, .cozy, .ubuntu: "$ "
        case .powershell, .cmd: "> "
        }
    }

    var command: String {
        switch self {
        case .mono: "focus --start"
        case .cozy, .ubuntu: "pomodoro"
        case .powershell: "Start-Pomodoro"
        case .cmd: "pomodoro.exe"
        }
    }

    var cursor: String {
        switch self {
        case .cozy, .ubuntu: "▌"
        case .mono, .powershell, .cmd: "_"
        }
    }

    var tasksCommand: String {
        switch self {
        case .mono: "$ focus --tasks"
        case .cozy: "$ tasks --list"
        case .powershell: "PS> Get-Task"
        case .cmd: "C:\\focus> dir tasks"
        case .ubuntu: "$ ls ~/tasks"
        }
    }

    var emptyTasks: String {
        switch self {
        case .mono, .cozy: "// nothing queued. add something to focus on."
        case .powershell: "# No tasks found. Type below to run New-Task."
        case .cmd: "File Not Found"
        case .ubuntu: "ls: cannot access 'tasks': No such file or directory"
        }
    }

    var linePrefix: String {
        switch self {
        case .mono, .cozy, .ubuntu: "> "
        case .powershell: "PS> "
        case .cmd: "C:\\> "
        }
    }

    var settingsTitle: String {
        switch self {
        case .mono, .cozy: "~/config"
        case .powershell: "Get-Config"
        case .cmd: "C:\\focus>config"
        case .ubuntu: "~/.config/focus"
        }
    }

    var versionCommand: String {
        switch self {
        case .mono, .cozy, .ubuntu: "$ focus --version"
        case .powershell: "PS> (Get-Focus).Version"
        case .cmd: "C:\\focus> ver"
        }
    }

    func sectionHeader(_ name: String) -> String {
        switch self {
        case .mono: "// \(name.uppercased())"
        case .cozy, .ubuntu: "# \(name)"
        case .powershell: "## \(name.capitalized)"
        case .cmd: "REM \(name)"
        }
    }

    /// CRT scanlines and vignette suit the cozy terminal; the others are flat modern consoles.
    var hasScanlines: Bool { self == .cozy }

    /// Mono mirrors the website: square hairline boxes, no accent glow, spaced uppercase labels.
    var isFlat: Bool { self == .mono }

    /// Corner radius for boxes, squared off in the flat style.
    func radius(_ rounded: CGFloat) -> CGFloat { isFlat ? 0 : rounded }

    /// A small label, set the website's way (UPPERCASE, wide tracking) in the flat style.
    func label(_ text: String) -> String { isFlat ? text.uppercased() : text }

    /// Letter spacing for small labels in the flat style.
    var labelTracking: CGFloat { isFlat ? 1.4 : 0 }
}

/// Which font each style uses, stored as one string ("cozy=jetbrains;cmd=vt323") so new styles
/// need no new settings keys.
enum FontChoices {
    static let key = "fontByStyle"

    static func font(for style: TerminalStyle, in stored: String) -> TerminalFont {
        parse(stored)[style] ?? style.defaultFont
    }

    static func setting(_ font: TerminalFont, for style: TerminalStyle, in stored: String) -> String {
        var choices = parse(stored)
        choices[style] = font
        return TerminalStyle.allCases.compactMap { s in choices[s].map { "\(s.rawValue)=\($0.rawValue)" } }.joined(separator: ";")
    }

    static func parse(_ stored: String) -> [TerminalStyle: TerminalFont] {
        var result: [TerminalStyle: TerminalFont] = [:]
        for pair in stored.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let style = TerminalStyle(rawValue: parts[0]), let font = TerminalFont(rawValue: parts[1]) else { continue }
            result[style] = font
        }
        return result
    }

    /// Carries over the per-style keys used by 1.5.0 the first time the new key is read.
    static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: key) == nil else { return }
        var stored = ""
        for (oldKey, style) in [("fontCozy", TerminalStyle.cozy), ("fontPowershell", .powershell)] {
            if let raw = defaults.string(forKey: oldKey), let font = TerminalFont(rawValue: raw) {
                stored = setting(font, for: style, in: stored)
            }
        }
        defaults.set(stored, forKey: key)
    }
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
    case geist, jetbrains, cascadia, sfMono, menlo, courier, plex, fira, sourceCode, space, ubuntu, dejavu, noto, anonymous, shareTech, vt323

    var id: String { rawValue }

    var name: String {
        switch self {
        case .geist: "Geist Mono"
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
        case .dejavu: "DejaVu Sans Mono"
        case .noto: "Noto Sans Mono"
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
        case .geist: .bundled(light: "GeistMono-Light", regular: "GeistMono-Regular", bold: "GeistMono-Bold")
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
        case .dejavu: .bundled(light: nil, regular: "DejaVuSansMono", bold: "DejaVuSansMono-Bold")
        case .noto: .bundled(light: "NotoSansMono-Light", regular: "NotoSansMono-Regular", bold: "NotoSansMono-Bold")
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

