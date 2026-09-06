import SwiftUI

/// Inline collapsible widget for a single `tool_call` + matching
/// `tool_result` event pair from a local kinclaw turn. Renders below
/// the assistant text so the conversational thread reads cleanly,
/// with the tool detail expandable on demand.
///
/// Default state: collapsed. Header shows the tool name + a status
/// dot (yellow = running, green = done, red = error from output).
/// Click the header to toggle the expanded body, which shows
/// params (key=value lines) and output (mono code block).
struct ToolCallView: View {
    let call: ToolCall

    @State private var expanded: Bool

    init(call: ToolCall) {
        self.call = call
        // File edits open expanded: the diff IS the information the
        // user wants to see, the same way Claude Desktop shows edits.
        _expanded = State(initialValue: Self.isFileEdit(call.name))
    }

    private static func isFileEdit(_ name: String) -> Bool {
        name == "file_edit" || name == "file_write"
    }

    private var status: Status {
        guard let out = call.output else { return .running }
        let lower = out.lowercased()
        if lower.contains("error") || lower.hasPrefix("err ") {
            return .error
        }
        return .done
    }

    enum Status {
        case running, done, error

        var color: Color {
            switch self {
            case .running: return .yellow
            case .done:    return .green
            case .error:   return .red
            }
        }

        var label: String {
            switch self {
            case .running: return "running…"
            case .done:    return "done"
            case .error:   return "error"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, click to toggle
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down"
                                                : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(call.name)
                        .font(.system(size: 11, weight: .semibold,
                                      design: .monospaced))
                    Circle()
                        .fill(status.color)
                        .frame(width: 5, height: 5)
                    Text(status.label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !expanded, let out = call.output, !out.isEmpty {
                        Text(out
                            .replacingOccurrences(of: "\n", with: " ")
                            .prefix(40))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                expandedBody
                    .transition(.opacity)
            }
        }
        .background(Color.platformTertiaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !call.params.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(call.params.keys.sorted()), id: \.self) { k in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(k):")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(call.params[k] ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            if let out = call.output, !out.isEmpty {
                renderedOutput(out)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.platformTertiaryBackground.opacity(0.7))
            }
        }
    }

    /// Pick rendering based on the shape of the output. Many kinclaw
    /// tools emit structured strings (markdown tables, fenced code,
    /// JSON) that read better as rich text than as a mono dump;
    /// other tools (raw stdout, AX trees, file paths) want mono.
    @ViewBuilder
    private func renderedOutput(_ out: String) -> some View {
        if Self.isFileEdit(call.name), looksLikeDiff(out) {
            // kinclaw ≥ 1.18 appends a coloured unified diff to file_edit /
            // file_write results, in kincode's format — DiffView parses both.
            DiffView(raw: out)
        } else if looksLikeMarkdown(out) {
            MarkdownView(text: out)
                .textSelection(.enabled)
        } else {
            // Treat as plain mono. Trim trailing whitespace; nothing
            // worse than a giant blank tail in a code surface.
            Text(out.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary.opacity(0.9))
                .textSelection(.enabled)
        }
    }

    /// The kernel's diff lines carry ANSI colour codes (red/green/gray).
    private func looksLikeDiff(_ out: String) -> Bool {
        out.contains("\u{1B}[31m") || out.contains("\u{1B}[32m")
    }

    /// Heuristic for "this looks like rich content, not raw stdout":
    /// has at least one of — fenced code block, table, list, or
    /// heading. Avoids running raw tool dumps (AX trees, JSON blobs)
    /// through the markdown parser where they'd render unrelated.
    private func looksLikeMarkdown(_ out: String) -> Bool {
        if out.contains("```") { return true }
        if out.range(of: "^\\|.*\\|$",
                     options: [.regularExpression, .anchored]) != nil
            && out.contains("---") {
            return true
        }
        // Lists / headings — at least 2 lines starting with the prefix
        let listLines = out.split(separator: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") || t.hasPrefix("* ")
                || t.hasPrefix("# ") || t.hasPrefix("## ")
                || t.range(of: "^\\d+\\. ",
                           options: .regularExpression) != nil
        }
        return listLines.count >= 2
    }
}
