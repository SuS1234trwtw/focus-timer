import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import FocusTimer

@MainActor
struct TaskOrderingTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: TaskItem.self, FocusSessionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func ordered() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt, order: .reverse)]))
    }

    @Test func newestTaskGoesOnTop() throws {
        TaskActions.add("first", in: context, above: try ordered())
        TaskActions.add("second", in: context, above: try ordered())
        TaskActions.add("  third  ", in: context, above: try ordered())
        #expect(try ordered().map(\.title) == ["third", "second", "first"])
    }

    @Test func blankTitlesAreIgnored() throws {
        TaskActions.add("   ", in: context, above: try ordered())
        #expect(try ordered().isEmpty)
    }

    @Test func moveToTopReopensAndLeads() throws {
        for title in ["a", "b", "c"] { TaskActions.add(title, in: context, above: try ordered()) }
        let a = try #require(try ordered().last)
        TaskActions.toggleDone(a)
        TaskActions.moveToTop(a, among: try ordered())
        #expect(try ordered().first?.title == "a")
        #expect(a.isDone == false)
    }

    @Test func reorderOnlyDirtiesMovedRows() throws {
        for title in ["a", "b", "c"] { TaskActions.add(title, in: context, above: try ordered()) }
        var list = try ordered()          // c, b, a
        TaskActions.reorder(list)         // normalise to 0, 1, 2
        list.forEach { $0.needsSync = false }
        list.move(fromOffsets: IndexSet(integer: 1), toOffset: 3)  // c, a, b
        TaskActions.reorder(list)
        #expect(try ordered().map(\.title) == ["c", "a", "b"])
        #expect(list.filter(\.needsSync).map(\.title) == ["a", "b"])
    }
}
