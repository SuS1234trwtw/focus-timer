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

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        isActive: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.isActive = isActive
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
    static func add(_ rawTitle: String, in context: ModelContext) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        context.insert(TaskItem(title: String(title.prefix(500))))
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
        if activate { task.isDone = false }
        task.touch()
    }

    static func delete(_ task: TaskItem) {
        task.isActive = false
        task.deletedAt = .now
        task.touch()
    }
}
