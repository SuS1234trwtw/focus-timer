import SwiftUI

/// Settings → updates: shows whether a newer build is published and how to install it.
/// A `Section` meant to sit inside `SettingsSheet`'s `Form`, styled the same way.
struct UpdateSettingsSection: View {
    /// The sheet's palette (its `style` picks the header format).
    let palette: Palette

    @Environment(\.openURL) private var openURL

    private var checker: UpdateChecker { UpdateChecker.shared }

    private static let guideURL = URL(string: "https://sus1234trwtw.github.io/install.html")!

    var body: some View {
        Section {
            if let update = checker.available {
                VStack(alignment: .leading, spacing: 4) {
                    Text("update available: \(update.version) (\(update.build))")
                        .foregroundStyle(palette.accent)
                    if !update.notes.isEmpty {
                        Text(update.notes)
                            .font(palette.mono(11, relativeTo: .caption))
                            .foregroundStyle(palette.dim)
                            .lineLimit(4)
                    }
                }
                Button {
                    Feedback.play(.tap)
                    openURL(update.downloadURL)
                } label: {
                    Label("download ipa", systemImage: "arrow.down.circle")
                        .foregroundStyle(palette.accent)
                }
                Button {
                    Feedback.play(.tap)
                    openURL(UpdateChecker.sideStoreURL())
                } label: {
                    Label("add to sidestore", systemImage: "plus.app")
                        .foregroundStyle(palette.accent)
                }
            } else {
                Text("you're on the latest build")
                    .foregroundStyle(palette.dim)
            }
            Button {
                Feedback.play(.tap)
                Task { await checker.checkNow() }
            } label: {
                HStack(spacing: 8) {
                    Label("check now", systemImage: "arrow.clockwise")
                        .foregroundStyle(palette.accent)
                    Spacer(minLength: 8)
                    if checker.isChecking {
                        ProgressView()
                            .tint(palette.accent)
                    }
                }
                .contentShape(.rect)
            }
            .disabled(checker.isChecking)
            if let lastChecked = checker.lastChecked {
                Text("last checked \(lastChecked.formatted(.relative(presentation: .named)))")
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(palette.dim)
            }
        } header: {
            Text(palette.style.sectionHeader("updates"))
                .font(palette.mono(12, .bold, relativeTo: .caption))
                .foregroundStyle(palette.accent)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("iPhones can't update apps by themselves. Install the new IPA with iloader, or add Focus to SideStore for one-tap updates.")
                HStack(spacing: 0) {
                    Text("Guide: ")
                    Link("sus1234trwtw.github.io/install.html", destination: Self.guideURL)
                        .foregroundStyle(palette.accent)
                }
            }
            .font(palette.mono(11, relativeTo: .caption))
            .foregroundStyle(palette.dim)
        }
        .listRowBackground(palette.surface)
    }
}
