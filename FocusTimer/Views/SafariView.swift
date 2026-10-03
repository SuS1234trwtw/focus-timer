import SafariServices
import SwiftUI

/// An in-app Safari sheet for the website, legal pages and the repo.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var tint: Color?

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        if let tint { controller.preferredControlTintColor = UIColor(tint) }
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

enum FocusLinks {
    static let website = URL(string: "https://sus1234trwtw.github.io/")!
    static let privacy = URL(string: "https://sus1234trwtw.github.io/privacy.html")!
    static let terms = URL(string: "https://sus1234trwtw.github.io/terms.html")!
    static let install = URL(string: "https://sus1234trwtw.github.io/install.html")!
    static let license = URL(string: "https://github.com/SuS1234trwtw/focus-timer/blob/main/LICENSE")!
    static let source = URL(string: "https://github.com/SuS1234trwtw/focus-timer")!
    static let issues = URL(string: "https://github.com/SuS1234trwtw/focus-timer/issues")!
    static let tiktok = URL(string: "https://www.tiktok.com/@notanlee1")!
}
