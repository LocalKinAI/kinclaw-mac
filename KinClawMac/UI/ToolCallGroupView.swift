import SwiftUI

/// Header row for a folded run of tool calls — "Ran 6 tools", or while
/// the turn streams "6 tools · web_fetch running…" — with a failure
/// count and a chevron. Shared by the Cowork and Code panes; the same
/// shape as Claude Desktop's "Ran 6 commands ›".
struct ToolFoldHeader: View {
    let count: Int
    let runningName: String?
    let errors: Int
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                if runningName != nil {
                    StreamingDots(color: .secondary, size: 4, spacing: 3)
                } else {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                if errors > 0 {
                    Text("\(errors) failed")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.85))
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.platformTertiaryBackground.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(expanded ? "Collapse tool calls" : "Show every tool call")
    }

    private var label: String {
        if let r = runningName { return "\(count) tools · \(r) running…" }
        return "Ran \(count) tools"
    }
}

/// Cowork: a turn's tool calls, folded once there are `foldAt` or more.
/// While the turn streams, the call in flight stays visible under the
/// header so the user still sees what the agent is doing right now;
/// when the turn ends it folds into the one-line summary.
struct ToolCallGroupView: View {
    let calls: [ToolCall]
    let streaming: Bool
    var foldAt = 3

    @State private var expanded = false

    private var running: ToolCall? {
        streaming ? calls.last(where: { $0.output == nil }) : nil
    }

    /// Same heuristic ToolCallView uses for its red dot.
    private var errors: Int {
        calls.filter { c in
            guard let out = c.output?.lowercased() else { return false }
            return out.contains("error") || out.hasPrefix("err ")
        }.count
    }

    var body: some View {
        if calls.count < foldAt {
            ForEach(calls) { ToolCallView(call: $0) }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ToolFoldHeader(count: calls.count, runningName: running?.name,
                               errors: errors, expanded: $expanded)
                if expanded {
                    ForEach(calls) { ToolCallView(call: $0) }
                } else if let cur = running {
                    ToolCallView(call: cur)
                }
            }
        }
    }
}
