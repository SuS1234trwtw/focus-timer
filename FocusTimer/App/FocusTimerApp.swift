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
            context.insert(TaskItem(title: "wire up supabase sync", isActive: true, createdAt: .now.addingTimeInterval(-30)))
            context.insert(TaskItem(title: "review the timer PR", isDone: true, createdAt: .now.addingTimeInterval(-20)))
            context.insert(TaskItem(title: "inbox zero", createdAt: .now.addingTimeInterval(-10)))
            try? context.save()
        }
        #endif

        // Launch with `-fastTimer` (Xcode scheme argument) for 10s/5s cycles while testing.
        let fast = ProcessInfo.processInfo.arguments.contains("-fastTimer")
        let defaults = UserDefaults.standard
        let custom = PomodoroDurations(
            focusMinutes: defaults.object(forKey: "focusMinutes") as? Int ?? 25,
            restMinutes: defaults.object(forKey: "restMinutes") as? Int ?? 5
        )
        _engine = State(initialValue: PomodoroEngine(durations: fast ? .fast : custom))
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
