import SwiftUI

/// Inline collapsible widget for one kincode tool invocation. Shows
/// the matched `tool_call` + `tool_result` pair as a single row that
/// flips from "running…" → "done" / "error" when the result lands.
///
/// Mirrors Cowork mode's `ToolCallView` — same visual rhythm — but
/// kept separate so kincode-specific rendering can layer in: the
/// expanded body for `file_edit` shows a `DiffView`, for any other
/// tool a mono / markdown text block of the output.
///
/// Default state: collapsed. Header shows the tool name + a status
/// dot (yellow = running, green = done, red = error) + a 1-line
/// preview of the output (when collapsed and result is in). Click
/// the header to toggle the expanded body, which shows params
/// (key=value lines) and the full output.
struct CodeToolInvocationView: View {
    /// The toolCall row from CodePane's message stream. Read-only —
    /// CodePane mutates it in place when tool_result arrives, and
    /// SwiftUI re-renders us when the row changes.
    let msg: CodeMessage

    @State private var expanded = false

    private var status: Status {
        if msg.toolError != nil { return .error }
        guard msg.toolOutput != nil else { return .running }
        // Heuristic: tool_result with the substring "Error" / "Tool
        // error" is a soft failure (the tool ran but its output
        // signaled trouble). Surface it red so the user notices,
        // even if msg.toolError is nil.
        let lower = (msg.toolOutput ?? "").lowercased()
        if lower.hasPrefix("error:") || lower.hasPrefix("tool error:") {
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
            header
            if expanded {
                expandedBody
                    .transition(.opacity)
            }
        }
        .background(Color.platformTertiaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var header: some View {
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
                    .foregroundColor(.blue.opacity(0.85))
                Text(msg.toolName ?? "tool")
                    .font(.system(size: 11, weight: .semibold,
                                  design: .monospaced))
                    .foregroundColor(.blue.opacity(0.95))
                if !msg.text.isEmpty {
                    Text(msg.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Circle()
                    .fill(status.color)
                    .frame(width: 5, height: 5)
                Text(status.label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                // Collapsed preview of the output's first line, so
                // users can see "test passed" / "12 lines changed"
                // without having to expand. Hidden while running and
                // when expanded (the body shows it in full there).
                if !expanded,
                   let out = msg.toolOutput,
                   !out.isEmpty
                {
                    Text(firstLineSummary(of: out))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 200, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let params = msg.toolParams, !params.isEmpty {
                paramsBlock(params)
            }
            if let err = msg.toolError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }
            if let out = msg.toolOutput, !out.isEmpty {
                outputBlock(out)
            } else if msg.toolOutput == nil {
                // Still running. Show a faint hint so the body isn't
                // empty when expanded mid-execution.
                Text("waiting for output…")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private func paramsBlock(_ params: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(params.keys.sorted(), id: \.self) { k in
                HStack(alignment: .top, spacing: 4) {
                    Text("\(k):")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(params[k] ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(5)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    /// Output rendering picks the right surface per tool:
    ///   - file_edit (no error): DiffView so additions / deletions
    ///     read at a glance instead of as a wall of context lines.
    ///   - everything else: mono code block, markdown when the output
    ///     looks like rich content (fenced code, tables, lists).
    @ViewBuilder
    private func outputBlock(_ out: String) -> some View {
        if msg.toolName == "file_edit" && msg.toolError == nil {
            DiffView(raw: out)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.platformTertiaryBackground.opacity(0.7))
        } else if looksLikeMarkdown(out) {
            MarkdownView(text: out)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.platformTertiaryBackground.opacity(0.7))
        } else {
            ScrollView {
                Text(out.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)  // cap tall outputs (long bash dumps)
            .padding(8)
            .background(Color.platformTertiaryBackground.opacity(0.7))
        }
    }

    /// First non-empty line of the output, trimmed and capped. Lets
    /// the collapsed header give a hint of what came back without
    /// dominating the row.
    private func firstLineSummary(of out: String) -> String {
        let line = out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? out
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(60))
    }

    /// Same heuristic as Cowork's ToolCallView: fenced code, table,
    /// list, or heading → run through the markdown view. Avoids
    /// running raw stdout / JSON / AX trees through the parser
    /// where they'd render unrelated.
    private func looksLikeMarkdown(_ out: String) -> Bool {
        if out.contains("```") { return true }
        if out.range(of: "^\\|.*\\|$",
                     options: [.regularExpression, .anchored]) != nil
            && out.contains("---") {
            return true
        }
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
