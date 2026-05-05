import SwiftUI

/// One row from the agent's `todo_write` tool. JSON shape matches
/// kincode's `TodoItem` struct in pkg/tools/todo_write.go — same
/// field names, same enum values for status.
struct TodoItem: Codable, Hashable {
    let content: String
    let activeForm: String
    let status: String  // "pending" | "in_progress" | "completed"
}

/// Renders a kincode `todo_write` tool call as a checklist UI inline
/// in the Code mode message stream — replaces the generic blue
/// tool-call pill so the user can see the agent's plan + progress
/// at a glance.
///
/// Layout per row:
///   ☐  pending   — outline circle, primary text
///   ◐  active    — half-filled circle, accent color, uses activeForm
///                   ("Building ..." instead of "Build ...") for
///                   present-continuous reading
///   ☑  completed — filled green circle + strikethrough
///
/// Header shows count + ratio (3/7 done) so progress is visible at
/// a glance for long lists.
struct TodoChecklistView: View {
    let items: [TodoItem]

    private var completedCount: Int {
        items.filter { $0.status == "completed" }.count
    }

    private var inProgressIndex: Int? {
        items.firstIndex(where: { $0.status == "in_progress" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                row(item, isActive: idx == inProgressIndex)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blue.opacity(0.85))
            Text("Plan")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.blue.opacity(0.85))
            Spacer()
            Text("\(completedCount)/\(items.count) done")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(_ item: TodoItem, isActive: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            statusIcon(for: item.status)
                .frame(width: 12)
            Text(isActive ? item.activeForm : item.content)
                .font(.system(size: 11))
                .foregroundColor(textColor(for: item.status))
                .strikethrough(item.status == "completed",
                               color: .secondary.opacity(0.5))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.green.opacity(0.85))
        case "in_progress":
            // Half-filled circle indicates "currently working on this".
            // SF Symbols' "circle.lefthalf.filled" renders the same
            // shape across macOS versions.
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.9))
        default:  // "pending" or unknown
            Image(systemName: "circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    private func textColor(for status: String) -> Color {
        switch status {
        case "completed":
            return .secondary
        case "in_progress":
            return .primary
        default:
            return .primary.opacity(0.85)
        }
    }
}
