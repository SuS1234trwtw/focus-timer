import Testing
@testable import FocusTimer

@MainActor
struct AppIconTests {
    /// Must match ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in project.yml.
    static let alternateIconNames = Set("AppIcon-cozy AppIcon-powershell AppIcon-cmd AppIcon-ubuntu".split(separator: " ").map(String.init))

    @Test func monoUsesThePrimaryIcon() {
        #expect(AppIconManager.iconName(for: .mono) == nil)
    }

    @Test func everyOtherStyleHasABundledAlternateIcon() {
        let names = TerminalStyle.allCases.filter { $0 != .mono }.compactMap { AppIconManager.iconName(for: $0) }
        #expect(names.count == TerminalStyle.allCases.count - 1)
        #expect(Set(names) == Self.alternateIconNames)
    }

    @Test func newFontsArePickable() {
        for font in [TerminalFont.commit, .martian, .victor, .monaspace] {
            #expect(TerminalFont.allCases.contains(font))
        }
        #expect(TerminalFont.victor.disablesLigatures)
        #expect(!TerminalFont.commit.disablesLigatures)
    }
}
