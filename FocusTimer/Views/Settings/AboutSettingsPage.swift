import SwiftUI
import UIKit

/// Settings → about: version, legal pages, links and how to reach the maker.
struct AboutSettingsPage: View {
    let palette: Palette

    @State private var safariURL: URL?
    @State private var copied = false

    /// e.g. "1.9.2 (23)", read from the app bundle so it always matches the installed build.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(">_ focus \(versionString)")
                        .font(palette.mono(15, .bold, relativeTo: .body))
                        .foregroundStyle(palette.accent)
                        .textSelection(.enabled)
                    Text("made by An Le aka アン, 51")
                    Text("a minimal Pomodoro timer and task list with a terminal look.")
                        .font(palette.mono(12, relativeTo: .caption))
                        .foregroundStyle(palette.dim)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(palette.surface)

            Section {
                linkRow("privacy policy", FocusLinks.privacy)
                linkRow("terms of service", FocusLinks.terms)
                linkRow("license", FocusLinks.license)
            } header: {
                header("legal")
            }
            .listRowBackground(palette.surface)

            Section {
                linkRow("website", FocusLinks.website)
                linkRow("install guide", FocusLinks.install)
                linkRow("source code", FocusLinks.source)
            } header: {
                header("more")
            }
            .listRowBackground(palette.surface)

            Section {
                Button {
                    UIPasteboard.general.string = "notanlee"
                    Feedback.play(.tap)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    HStack {
                        Text("discord")
                        Spacer()
                        Text(copied ? "copied" : "notanlee")
                            .foregroundStyle(copied ? palette.accent : palette.dim)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(palette.dim)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Discord name copied" : "Copy Discord name notanlee")

                Link(destination: FocusLinks.tiktok) {
                    rowLabel("tiktok", detail: "@notanlee1")
                }
                .buttonStyle(.plain)

                linkRow("report a bug", FocusLinks.issues)
            } header: {
                header("contact")
            } footer: {
                Text("© 2026 An Le aka アン, 51 · all rights reserved. not affiliated with Apple, Google or Spotify.")
                    .font(palette.mono(11, relativeTo: .caption))
                    .foregroundStyle(palette.dim)
            }
            .listRowBackground(palette.surface)
        }
        .font(palette.mono(15, relativeTo: .body))
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("about")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
            if let safariURL {
                SafariView(url: safariURL, tint: palette.accent)
                    .ignoresSafeArea()
            }
        }
    }

    /// A row that opens `url` in the in-app Safari sheet.
    private func linkRow(_ title: String, _ url: URL) -> some View {
        Button {
            Feedback.play(.tap)
            safariURL = url
        } label: {
            rowLabel(title, detail: nil)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let detail {
                Text(detail).foregroundStyle(palette.dim)
            }
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.dim)
        }
        .contentShape(.rect)
    }

    private func header(_ name: String) -> some View {
        Text(palette.style.sectionHeader(name))
            .font(palette.mono(12, .bold, relativeTo: .caption))
            .foregroundStyle(palette.accent)
    }
}
