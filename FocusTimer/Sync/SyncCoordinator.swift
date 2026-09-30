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

    // MARK: Local-only mode

    private func purgeTombstones() {
        let tombstones = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
        for task in tombstones { context.delete(task) }
    }
}
