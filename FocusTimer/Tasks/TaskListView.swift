import SwiftData
import SwiftUI

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    let palette: Palette
    let tasks: [TaskItem]
    let activeID: UUID?

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var openCount: Int { tasks.filter { !$0.isDone }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(palette.style.tasksCommand)
                    .foregroundStyle(palette.dim)
                Spacer()
                Text("\(openCount) open")
                    .foregroundStyle(palette.dim)
                    .contentTransition(.numericText())
            }
            .font(palette.mono(13, .bold, relativeTo: .footnote))

            input

            if tasks.isEmpty {
                Text(palette.style.emptyTasks)
                    .font(palette.mono(13, relativeTo: .footnote))
                    .foregroundStyle(palette.dim)
                    .padding(.vertical, 8)
            }

            ForEach(tasks) { task in
                TaskRow(
                    task: task,
                    isActive: task.id == activeID,
                    palette: palette,
                    onToggleDone: {
                        Feedback.play(task.isDone ? .taskUndo : .taskDone)
                        mutate { TaskActions.toggleDone(task) }
                    },
                    onToggleActive: {
                        Feedback.play(.taskFocus)
                        mutate { TaskActions.toggleActive(task, among: tasks) }
                    },
                    onDelete: {
                        Feedback.play(.taskDelete)
                        mutate { TaskActions.delete(task) }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var input: some View {
        HStack(spacing: 10) {
            Text(">").foregroundStyle(palette.accent)
            TextField("", text: $draft, prompt: Text("add a task…").foregroundStyle(palette.dim))
                .foregroundStyle(palette.text)
                .tint(palette.accent)
                .focused($inputFocused)
                .submitLabel(.return)
                .autocorrectionDisabled()
                .onSubmit(add)
            if !draft.isEmpty {
                Button(action: add) {
                    Image(systemName: "return")
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add task")
            }
        }
        .font(palette.mono(16, relativeTo: .body))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.surface.opacity(0.55), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1))
    }

    private func add() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Feedback.play(.taskAdd)
        mutate { TaskActions.add(draft, in: context) }
        draft = ""
        inputFocused = true
    }

    private func mutate(_ change: () -> Void) {
        withAnimation(.snappy) { change() }
        sync.scheduleSync()
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isActive: Bool
    let palette: Palette
    let onToggleDone: () -> Void
    let onToggleActive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleDone) {
                Text(task.isDone ? "[x]" : "[ ]")
                    .foregroundStyle(task.isDone ? palette.accent : palette.dim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            Button(action: onToggleActive) {
                HStack(spacing: 8) {
                    if isActive {
                        Text("▶").foregroundStyle(palette.accent)
                    }
                    Text(task.title)
                        .foregroundStyle(task.isDone ? palette.dim : palette.text)
                        .strikethrough(task.isDone, color: palette.dim)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isActive ? "Active task. Tap to clear." : "Tap to focus on this task.")

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(task.title)")
        }
        .font(palette.mono(15, isActive ? .bold : .regular, relativeTo: .body))
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(isActive ? palette.accent.opacity(0.10) : palette.surface.opacity(0.4), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? palette.accent : palette.border, lineWidth: isActive ? 1.5 : 1)
        )
        .animation(.snappy, value: isActive)
        .contextMenu {
            Button(isActive ? "Clear active" : "Set active", systemImage: "scope", action: onToggleActive)
            Button(task.isDone ? "Mark not done" : "Mark done", systemImage: "checkmark", action: onToggleDone)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}
