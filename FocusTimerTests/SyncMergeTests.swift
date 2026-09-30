import Foundation
import Testing
@testable import FocusTimer

struct SyncMergeTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func remote(updatedAt: Date, deleted: Bool = false) -> TaskDTO {
        TaskDTO(id: UUID(), title: "t", isDone: false, isActive: false, sortIndex: 0,
                createdAt: t0, updatedAt: updatedAt, deletedAt: deleted ? updatedAt : nil)
    }

    @Test func unknownRowIsInserted() {
        #expect(SyncMerge.action(localUpdatedAt: nil, remote: remote(updatedAt: t0)) == .insert)
    }

    @Test func unknownTombstoneIsIgnored() {
        #expect(SyncMerge.action(localUpdatedAt: nil, remote: remote(updatedAt: t0, deleted: true)) == .ignore)
    }

    @Test func newerRemoteWins() {
        let r = remote(updatedAt: t0.addingTimeInterval(5))
        #expect(SyncMerge.action(localUpdatedAt: t0, remote: r) == .update)
    }

    @Test func newerLocalWins() {
        let r = remote(updatedAt: t0)
        #expect(SyncMerge.action(localUpdatedAt: t0.addingTimeInterval(5), remote: r) == .ignore)
    }

    @Test func equalTimestampsAreNoOp() {
        #expect(SyncMerge.action(localUpdatedAt: t0, remote: remote(updatedAt: t0)) == .ignore)
    }

    @Test func newerRemoteDeletionDeletesLocal() {
        let r = remote(updatedAt: t0.addingTimeInterval(5), deleted: true)
        #expect(SyncMerge.action(localUpdatedAt: t0, remote: r) == .delete)
    }

    @Test func dtoUsesSnakeCaseColumns() throws {
        let data = try JSONEncoder().encode(remote(updatedAt: t0))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"is_done\""))
        #expect(json.contains("\"updated_at\""))
        #expect(json.contains("\"sort_index\""))
        #expect(!json.contains("user_id"))
    }
}
