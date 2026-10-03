import Foundation
import Observation
import SwiftData

/// Offline-first sync: SwiftData is the source of truth on device; dirty rows are
/// pushed to Supabase and remote changes pulled back with last-write-wins.
@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case localOnly
        case idle
        case syncing
        case synced
        case offline
    }

    private(set) var status: Status
    private(set) var lastError: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let service: SupabaseService?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let lastPulledKey = "sync.tasks.lastPulledAt"

    init(context: ModelContext, service: SupabaseService?, defaults: UserDefaults = .standard) {
        self.context = context
        self.service = service
        self.defaults = defaults
        self.status = service == nil ? .localOnly : .idle
    }

    /// Saves local edits and syncs shortly after (debounced so rapid edits batch together).
    func scheduleSync(after delay: Duration = .seconds(1)) {
        guard service != nil else {
            purgeTombstones()
            try? context.save()
            return
        }
        try? context.save()
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let service, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        status = .syncing
        do {
            try await service.ensureSignedIn()
            try await pushTasks(service)
            try await pushSessions(service)
            try await pullTasks(service)
            try context.save()
            status = .synced
            lastError = nil
        } catch {
            status = .offline
            lastError = error.localizedDescription
        }
    }

    func record(_ segment: CompletedSegment, taskID: UUID?) {
        context.insert(FocusSessionRecord(
            taskID: taskID,
            mode: segment.mode,
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            durationSec: Int(segment.duration)
        ))
        scheduleSync()
    }

    // MARK: Push

    private func pushTasks(_ service: SupabaseService) async throws {
        let dirty = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.needsSync == true }))
        guard !dirty.isEmpty else { return }
        let sent = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })

        try await service.upsertTasks(dirty.map(\.dto))

        // Rows edited again while the request was in flight stay dirty for the next round.
        for task in dirty where sent[task.id] == task.updatedAt {
            task.needsSync = false
            if task.deletedAt != nil { context.delete(task) }
        }
    }

    private func pushSessions(_ service: SupabaseService) async throws {
        let dirty = try context.fetch(FetchDescriptor<FocusSessionRecord>(predicate: #Predicate { $0.needsSync == true }))
        guard !dirty.isEmpty else { return }
        try await service.insertSessions(dirty.map(\.dto))
        for session in dirty { session.needsSync = false }
    }

    // MARK: Pull

    private func pullTasks(_ service: SupabaseService) async throws {
        let since = defaults.object(forKey: lastPulledKey) as? Date
        let rows = try await service.fetchTasks(updatedAfter: since)

        for row in rows {
            let id = row.id
            var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let local = try context.fetch(descriptor).first

            switch SyncMerge.action(localUpdatedAt: local?.updatedAt, remote: row) {
            case .insert: context.insert(TaskItem.make(from: row))
            case .update: local?.apply(row)
            case .delete: if let local { context.delete(local) }
            case .ignore: break
            }
        }

        if let newest = rows.map(\.updatedAt).max() {
            defaults.set(newest, forKey: lastPulledKey)
        }
    }

    // MARK: Account switching (see `AccountService`)

    /// The Supabase connection, or nil in local-only mode.
    var supabase: SupabaseService? { service }

    /// Forgets how far the last pull got, so the next sync downloads every row again.
    func resetPullCursor() {
        defaults.removeObject(forKey: lastPulledKey)
    }

    /// Waits for a sync in flight to finish (and drops a scheduled one) before the signed-in user changes.
    func waitUntilIdle() async {
        pending?.cancel()
        pending = nil
        while isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// After logging in to an existing account: local rows were uploaded under the previous (guest)
    /// user, whose ids the account can't write to (RLS). Gives them fresh ids and marks them dirty so
    /// the next sync pushes them under the account. Tasks the account already has (same title and
    /// creation time, e.g. after signing out and back in) are dropped locally; the pull brings them back.
    func adoptLocalData() async {
        await waitUntilIdle()
        guard let service else { return }
        let remote = (try? await service.fetchTasks(updatedAfter: nil)) ?? []
        var remoteByKey: [String: UUID] = [:]
        for row in remote where row.deletedAt == nil {
            remoteByKey[Self.matchKey(title: row.title, createdAt: row.createdAt)] = row.id
        }

        var newIDs: [UUID: UUID] = [:]
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in tasks {
            if task.deletedAt != nil {
                context.delete(task)
            } else if let existing = remoteByKey[Self.matchKey(title: task.title, createdAt: task.createdAt)] {
                newIDs[task.id] = existing
                context.delete(task)
            } else {
                let fresh = UUID()
                newIDs[task.id] = fresh
                task.id = fresh
                task.needsSync = true
            }
        }
        let sessions = (try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? []
        for session in sessions {
            session.id = UUID()
            session.taskID = session.taskID.map { newIDs[$0] ?? $0 }
            session.needsSync = true
        }
        try? context.save()
        resetPullCursor()
    }

    /// Before signing out to a fresh guest: keeps every task on the device (with fresh ids, so the
    /// new guest can back them up) and drops session records that are already saved in the account.
    func prepareForSignOut() async {
        await waitUntilIdle()
        var newIDs: [UUID: UUID] = [:]
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in tasks {
            if task.deletedAt != nil {
                context.delete(task)
            } else {
                let fresh = UUID()
                newIDs[task.id] = fresh
                task.id = fresh
                task.needsSync = true
            }
        }
        let sessions = (try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? []
        for session in sessions {
            if session.needsSync {
                session.taskID = session.taskID.map { newIDs[$0] ?? $0 }
            } else {
                context.delete(session)
            }
        }
        try? context.save()
        resetPullCursor()
    }

    private static func matchKey(title: String, createdAt: Date) -> String {
        "\(title)|\(Int((createdAt.timeIntervalSince1970 * 1000).rounded()))"
    }

    // MARK: Local-only mode

    private func purgeTombstones() {
        let tombstones = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
        for task in tombstones { context.delete(task) }
    }
}
