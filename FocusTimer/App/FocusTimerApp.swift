import SwiftData
import SwiftUI

@main
struct FocusTimerApp: App {
    private let container: ModelContainer
    @State private var engine: PomodoroEngine
    @State private var sync: SyncCoordinator

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: TaskItem.self, FocusSessionRecord.self)
        } catch {
            fatalError("Could not open local store: \(error)")
        }
        self.container = container

        // Launch with `-fastTimer` (Xcode scheme argument) for 10s/5s cycles while testing.
        let fast = ProcessInfo.processInfo.arguments.contains("-fastTimer")
        _engine = State(initialValue: PomodoroEngine(durations: fast ? .fast : .standard))
        _sync = State(initialValue: SyncCoordinator(
            context: container.mainContext,
            service: SupabaseService.fromInfoPlist()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(sync)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
