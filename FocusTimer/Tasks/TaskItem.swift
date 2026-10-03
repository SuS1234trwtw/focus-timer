import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Tombstone: deleted locally, kept until the deletion has been pushed.
    var deletedAt: Date?
    var needsSync: Bool
    /// User-defined order; lowest first (see `TaskOrdering`). Defaulted for lightweight migration.
    var sortIndex: Double = 0

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        isActive: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        needsSync: Bool = true,
        sortIndex: Double = 0
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.needsSync = needsSync
        self.sortIndex = sortIndex
    }

    /// Marks a local edit so the next sync pushes it.
    func touch(_ date: Date = .now) {
        updatedAt = date
        needsSync = true
    }
}

@Model
final class FocusSessionRecord {
    @Attribute(.unique) var id: UUID
    var taskID: UUID?
    var mode: String
    var startedAt: Date
    var endedAt: Date
    var durationSec: Int
    var needsSync: Bool

    init(id: UUID = UUID(), taskID: UUID?, mode: TimerMode, startedAt: Date, endedAt: Date, durationSec: Int) {
        self.id = id
        self.taskID = taskID
        self.mode = mode.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSec = durationSec
        self.needsSync = true
    }
}

/// Task mutations used by the UI. Each one marks rows dirty for sync; the caller saves and schedules a sync.
@MainActor
enum TaskActions {
    static func add(_ rawTitle: String, in context: ModelContext) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        context.insert(TaskItem(title: String(title.prefix(500)), sortIndex: TaskOrdering.topIndex(existing)))
    }

    static func toggleDone(_ task: TaskItem) {
        task.isDone.toggle()
        if task.isDone { task.isActive = false }
        task.touch()
    }

    /// Makes `task` the single active task, or clears it if it already was.
    static func toggleActive(_ task: TaskItem, among tasks: [TaskItem]) {
        let activate = !task.isActive
        for other in tasks where other.isActive && other.id != task.id {
            other.isActive = false
            other.touch()
        }
        task.isActive = activate
        if activate {
            task.isDone = false
            task.sortIndex = TaskOrdering.topIndex(tasks)
        }
        task.touch()
    }

    static func moveToTop(_ task: TaskItem, among tasks: [TaskItem]) {
        task.sortIndex = TaskOrdering.topIndex(tasks)
        task.touch()
    }

    static func delete(_ task: TaskItem) {
        task.isActive = false
        task.deletedAt = .now
        task.touch()
    }
}

/// Display order: open tasks first, then done; each by `sortIndex` ascending, newest first on ties.
@MainActor
enum TaskOrdering {
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt > b.createdAt
        }
    }

    /// A sortIndex that sorts above every task in `tasks`.
    static func topIndex(_ tasks: [TaskItem]) -> Double {
        (tasks.map(\.sortIndex).min() ?? 1) - 1
    }

    /// Moves `id` just before `targetID` within its own section (open or done); nil = end of that section.
    /// Changed tasks are touched so they sync.
    static func reorder(_ tasks: [TaskItem], moving id: UUID, before targetID: UUID?) {
        guard id != targetID, let moving = tasks.first(where: { $0.id == id }) else { return }
        var group = sorted(tasks).filter { $0.isDone == moving.isDone && $0.id != id }
        let index = targetID.flatMap { target in group.firstIndex { $0.id == target } } ?? group.count
        let prev = index > 0 ? group[index - 1].sortIndex : nil
        let next = index < group.count ? group[index].sortIndex : nil

        let value: Double
        switch (prev, next) {
        case let (p?, n?): value = (p + n) / 2
        case let (p?, nil): value = p + 1
        case let (nil, n?): value = n - 1
        case (nil, nil): return
        }

        // Ties (e.g. every task migrated at 0) or a worn-out gap: renumber the section with step 1.
        if let p = prev, let n = next, !(p < value && value < n) {
            group.insert(moving, at: index)
            for (i, task) in group.enumerated() where task.sortIndex != Double(i) {
                task.sortIndex = Double(i)
                task.touch()
            }
            return
        }
        guard moving.sortIndex != value else { return }
        moving.sortIndex = value
        moving.touch()
    }
}
