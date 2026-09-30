import SwiftData
import SwiftUI

@main
struct FocusTimerApp: App {
    private let model: AppModel

    init() {
        FontRegistry.registerBundledFonts()
        FontChoices.migrate()
        Feedback.prepare()
        model = AppModel.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model.engine)
                .environment(model.sync)
                .environment(model.spotify)
        }
        .modelContainer(model.container)
    }
}
