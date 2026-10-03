import Foundation

/// Row shape of `public.tasks`. `user_id` is omitted: the column defaults to `auth.uid()`.
struct TaskDTO: Codable, Sendable, Equatable {
    let id: UUID
    let title: String
    let isDone: Bool
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    var sortIndex: Double = 0

    enum CodingKeys: String, CodingKey {
        case id, title
        case isDone = "is_done"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case sortIndex = "sort_index"
    }
}

extension TaskDTO {
    /// `sort_index` is optional on the wire so a database without migration 0002 still syncs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        sortIndex = try c.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
    }
}

/// Row shape of `public.focus_sessions`.
struct FocusSessionDTO: Codable, Sendable, Equatable {
    let id: UUID
    let taskId: UUID?
    let mode: String
    let startedAt: Date
    let endedAt: Date
    let durationSec: Int

    enum CodingKeys: String, CodingKey {
        case id, mode
        case taskId = "task_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSec = "duration_sec"
    }
}

enum MergeAction: Equatable {
    case insert
    case update
    case delete
    case ignore
}

/// Last-write-wins merge of a pulled remote row against the local copy.
enum SyncMerge {
    static func action(localUpdatedAt: Date?, remote: TaskDTO) -> MergeAction {
        guard let localUpdatedAt else {
            return remote.deletedAt == nil ? .insert : .ignore
        }
        guard remote.updatedAt > localUpdatedAt else { return .ignore }
        return remote.deletedAt == nil ? .update : .delete
    }
}

extension TaskItem {
    var dto: TaskDTO {
        TaskDTO(id: id, title: title, isDone: isDone, isActive: isActive,
                createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt, sortIndex: sortIndex)
    }

    static func make(from dto: TaskDTO) -> TaskItem {
        TaskItem(id: dto.id, title: dto.title, isDone: dto.isDone, isActive: dto.isActive,
                 createdAt: dto.createdAt, updatedAt: dto.updatedAt, needsSync: false, sortIndex: dto.sortIndex)
    }

    func apply(_ dto: TaskDTO) {
        title = dto.title
        isDone = dto.isDone
        isActive = dto.isActive
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
        sortIndex = dto.sortIndex
        needsSync = false
    }
}

extension FocusSessionRecord {
    var dto: FocusSessionDTO {
        FocusSessionDTO(id: id, taskId: taskID, mode: mode, startedAt: startedAt,
                        endedAt: endedAt, durationSec: durationSec)
    }
}
