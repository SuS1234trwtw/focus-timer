import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    /// Legacy "focusing" flag, still synced for older builds; the current task is now the first open one by order.
    var isActive: Bool
    /// User order, ascending. New tasks get the lowest value so they appear on top.
    var sortIndex: Double = 0
    var createdAt: Date
    var updatedAt: Date
    /// Tombstone: deleted locally, kept until the deletion has been pushed.
    var deletedAt: Date?
    var needsSync: Bool

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        isActive: Bool = false,
        sortIndex: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.isActive = isActive
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.needsSync = needsSync
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
    /// Adds a task on top of the list, so the newest task is the one shown under the timer.
    static func add(_ rawTitle: String, in context: ModelContext, above tasks: [TaskItem]) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        context.insert(TaskItem(title: String(title.prefix(500)), sortIndex: topIndex(above: tasks)))
    }

    static func toggleDone(_ task: TaskItem) {
        task.isDone.toggle()
        task.isActive = false
        task.touch()
    }

    /// Puts a task first (reopening it if it was done), making it the current task.
    static func moveToTop(_ task: TaskItem, among tasks: [TaskItem]) {
        task.sortIndex = topIndex(above: tasks.filter { $0.id != task.id })
        task.isDone = false
        task.touch()
    }

    /// Persists a new user order; only rows whose position changed are marked dirty.
    static func reorder(_ ordered: [TaskItem]) {
        for (index, task) in ordered.enumerated() where task.sortIndex != Double(index) {
            task.sortIndex = Double(index)
            task.touch()
        }
    }

    static func delete(_ task: TaskItem) {
        task.isActive = false
        task.deletedAt = .now
        task.touch()
    }

    static func topIndex(above tasks: [TaskItem]) -> Double {
        (tasks.map(\.sortIndex).min() ?? 1) - 1
    }
}
