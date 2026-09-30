import SwiftData
import SwiftUI

struct TasksSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.createdAt)
    private var tasks: [TaskItem]

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var activeID: UUID? {
        tasks.filter { $0.isActive && !$0.isDone }.max { $0.updatedAt < $1.updatedAt }?.id
    }

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

                Section {
                    ForEach(tasks) { task in
                        row(task)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { tasks[$0] }
                        mutate { doomed.forEach(TaskActions.delete) }
                    }
                } footer: {
                    if !tasks.isEmpty {
                        Text("Tap a task to focus on it. Swipe to delete.")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ task: TaskItem) -> some View {
        let isActive = task.id == activeID
        return HStack(spacing: 12) {
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
                .fontWeight(isActive ? .semibold : .regular)

            Spacer(minLength: 0)

            if isActive {
                Text("Focusing")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.primary.opacity(0.1), in: .capsule)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(.rect)
        .onTapGesture { mutate { TaskActions.toggleActive(task, among: tasks) } }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(isActive ? "Tap to stop focusing on this task." : "Tap to focus on this task.")
    }

    private func add() {
        mutate { TaskActions.add(draft, in: context) }
        draft = ""
        inputFocused = true
    }

    private func mutate(_ change: () -> Void) {
        withAnimation(.snappy) { change() }
        sync.scheduleSync()
    }
}
