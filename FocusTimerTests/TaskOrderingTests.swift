import Foundation
import SwiftData
import Testing
@testable import FocusTimer

@MainActor
struct TaskOrderingTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func task(_ title: String, sort: Double = 0, done: Bool = false, age: TimeInterval = 0) -> TaskItem {
        TaskItem(title: title, isDone: done, createdAt: t0.addingTimeInterval(-age), updatedAt: t0, needsSync: false, sortIndex: sort)
    }

    func titles(_ tasks: [TaskItem]) -> [String] { TaskOrdering.sorted(tasks).map(\.title) }

    @Test func openFirstThenSortIndexThenNewest() {
        let tasks = [
            task("done", sort: -10, done: true),
            task("old", age: 100),
            task("new", age: 1),
            task("pinned", sort: -1, age: 500),
        ]
        #expect(titles(tasks) == ["pinned", "new", "old", "done"])
    }

    @Test func newTaskGoesToTop() throws {
        let container = try ModelContainer(for: TaskItem.self, FocusSessionRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(task("a", sort: 3))
        context.insert(task("b", sort: -2))
        TaskActions.add("c", in: context)
        let all = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(all.first { $0.title == "c" }?.sortIndex == -3)
    }

    @Test func focusingMovesToTop() {
        let a = task("a", sort: 0), b = task("b", sort: 1)
        TaskActions.toggleActive(b, among: [a, b])
        #expect(b.sortIndex == -1)
        #expect(titles([a, b]) == ["b", "a"])
        #expect(b.needsSync)
    }

    @Test func reorderUsesMidpoint() {
        let a = task("a", sort: 0), b = task("b", sort: 1), c = task("c", sort: 2)
        TaskOrdering.reorder([a, b, c], moving: c.id, before: b.id)
        #expect(c.sortIndex == 0.5)
        #expect(titles([a, b, c]) == ["a", "c", "b"])
        #expect(c.needsSync && !a.needsSync && !b.needsSync)
    }

    @Test func reorderToEndAndStart() {
        let a = task("a", sort: 0), b = task("b", sort: 1), c = task("c", sort: 2)
        TaskOrdering.reorder([a, b, c], moving: a.id, before: nil)
        #expect(titles([a, b, c]) == ["b", "c", "a"])
        TaskOrdering.reorder([a, b, c], moving: a.id, before: b.id)
        #expect(titles([a, b, c]) == ["a", "b", "c"])
    }

    @Test func tiesAreRenumbered() {
        // Everything migrated at 0: order comes from createdAt (newest first).
        let a = task("a", age: 1), b = task("b", age: 2), c = task("c", age: 3)
        TaskOrdering.reorder([a, b, c], moving: a.id, before: c.id)
        #expect(titles([a, b, c]) == ["b", "a", "c"])
        #expect([b.sortIndex, a.sortIndex, c.sortIndex] == [0, 1, 2])
    }

    @Test func doneTasksStayBelowOpen() {
        let a = task("a", sort: 0), d = task("d", sort: -5, done: true)
        TaskOrdering.reorder([a, d], moving: d.id, before: a.id)
        #expect(titles([a, d]) == ["a", "d"])
    }
}
