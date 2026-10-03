import SwiftUI

/// Settings → appearance → "curious about fonts?": a card per font with a sample and where it comes from.
struct FontsGuidePage: View {
    let palette: Palette

    var body: some View {
        Form {
            ForEach(TerminalFont.allCases) { font in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(font.name)
                            .font(font.font(17, .bold, relativeTo: .headline))
                            .foregroundStyle(palette.accent)
                        Text("$ focus --start 25:00")
                            .font(font.font(15, .regular, relativeTo: .body))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(font.about)
                            .font(palette.mono(12, relativeTo: .footnote))
                            .foregroundStyle(palette.dim)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(palette.surface)
            }
        }
        .settingsFormStyle(palette)
        .navigationTitle("fonts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension TerminalFont {
    /// One factual line: who made it and what it's known for.
    var about: String {
        switch self {
        case .geist: "vercel's mono (2023), drawn with basement.studio. clean, modern, the website's font."
        case .jetbrains: "jetbrains' coding font (2020). tall lowercase for long reads of code."
        case .cascadia: "microsoft's windows terminal font (2019). mono is the cut without ligatures."
        case .sfMono: "apple's system monospace from the san francisco family. built into ios."
        case .menlo: "apple's mac terminal font since 2009, based on bitstream vera and dejavu."
        case .courier: "the typewriter classic, first drawn by howard kettler for ibm in 1955."
        case .plex: "ibm's own typeface (2017), designed by mike abbink with bold monday."
        case .fira: "made for mozilla's firefox os by erik spiekermann and carrois. fira code grew from it."
        case .sourceCode: "adobe's first open-source family (2012), by paul d. hunt."
        case .space: "colophon foundry's retro-futurist mono, made for google design (2016)."
        case .ubuntu: "the ubuntu terminal font, by dalton maag for canonical."
        case .dejavu: "extends bitstream vera; long the default linux terminal font."
        case .noto: "part of google's noto family, which aims to cover every script."
        case .anonymous: "mark simonson's mono for coders (2009). clear 0/O and 1/l/I."
        case .shareTech: "carrois type design's squared, techy mono."
        case .vt323: "peter hull's revival of the dec vt320 terminal's bitmap font."
        case .commit: "eigil nikolajsen's neutral mono (2023), with smart kerning that evens out spacing."
        case .martian: "evil martians' wide, geometric mono, made for interfaces and code."
        case .victor: "rubjerg hansen's slim, narrow mono, known for its cursive italics."
        case .monaspace: "github next's superfamily (2023). neon is its neo-grotesque sans."
        }
    }
}
