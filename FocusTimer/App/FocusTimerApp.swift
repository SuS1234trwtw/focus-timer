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

        #if DEBUG
        // Launch with `-seedDemo` to fill an empty store with sample tasks (used for CI screenshots).
        if ProcessInfo.processInfo.arguments.contains("-seedDemo"),
           (try? container.mainContext.fetchCount(FetchDescriptor<TaskItem>())) == 0 {
            let context = container.mainContext
            context.insert(TaskItem(title: "Wire up Supabase sync", sortIndex: 0))
            context.insert(TaskItem(title: "Inbox zero", sortIndex: 1))
            context.insert(TaskItem(title: "Plan tomorrow", sortIndex: 2))
            context.insert(TaskItem(title: "Review the timer PR", isDone: true, sortIndex: 3))
            try? context.save()
        }
        #endif

        // Launch with `-fastTimer` (Xcode scheme argument) to make each "minute" one second while testing.
        let fast = ProcessInfo.processInfo.arguments.contains("-fastTimer")
        _engine = State(initialValue: PomodoroEngine(unit: fast ? 1 : 60))
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
        }
        .modelContainer(container)
    }
}
