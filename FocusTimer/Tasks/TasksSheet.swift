import SwiftData
import SwiftUI

struct TasksSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<TaskItem> { $0.deletedAt == nil },
        sort: [SortDescriptor(\TaskItem.sortIndex), SortDescriptor(\TaskItem.createdAt, order: .reverse)]
    )
    private var tasks: [TaskItem]

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var open: [TaskItem] { tasks.filter { !$0.isDone } }
    private var done: [TaskItem] { tasks.filter(\.isDone) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New task", text: $draft)
                            .focused($inputFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                        if !draft.isEmpty {
                            Button("Add", systemImage: "plus.circle.fill", action: add)
                                .labelStyle(.iconOnly)
                                .font(.title3)
                        }
                    }
                }

                if !open.isEmpty {
                    Section {
                        ForEach(open) { task in
                            row(task, isCurrent: task.id == open.first?.id)
                        }
                        .onMove(perform: move)
                        .onDelete { offsets in delete(offsets.map { open[$0] }) }
                    } header: {
                        Text("Up next")
                    } footer: {
                        Text("The top task shows under the timer. Drag to reorder, tap to move a task to the top.")
                    }
                }

                if !done.isEmpty {
                    Section("Done") {
                        ForEach(done) { task in
                            row(task, isCurrent: false)
                        }
                        .onDelete { offsets in delete(offsets.map { done[$0] }) }
                    }
                }
            }
            .overlay {
                if tasks.isEmpty {
                    ContentUnavailableView("No tasks", systemImage: "checklist", description: Text("Add what you want to focus on."))
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if open.count > 1 { EditButton() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: open.map(\.id))
    }

    private func row(_ task: TaskItem, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                mutate { TaskActions.toggleDone(task) }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            Text(task.title)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .fontWeight(isCurrent ? .semibold : .regular)

            Spacer(minLength: 0)

            if isCurrent {
                Text("Now")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.primary.opacity(0.1), in: .capsule)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity)
                            .animation(.timingCurve(0.34, 1.36, 0.64, 1, duration: 0.5)),
                        removal: .opacity.animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15))
                    ))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            guard !isCurrent else { return }
            mutate { TaskActions.moveToTop(task, among: tasks) }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityHint(isCurrent ? "Shown under the timer." : "Tap to focus on this task next.")
    }

    private func add() {
        mutate { TaskActions.add(draft, in: context, above: tasks) }
        draft = ""
        inputFocused = true
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = open
        ordered.move(fromOffsets: source, toOffset: destination)
        mutate { TaskActions.reorder(ordered) }
    }

    private func delete(_ doomed: [TaskItem]) {
        mutate { doomed.forEach(TaskActions.delete) }
    }

    private func mutate(_ change: () -> Void) {
        withAnimation(.snappy) { change() }
        sync.scheduleSync()
    }
}
