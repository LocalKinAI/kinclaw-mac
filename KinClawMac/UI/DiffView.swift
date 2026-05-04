import SwiftUI

/// Renders kincode's `file_edit` tool output as a colored unified diff.
///
/// kincode's tool_result for file_edit has the shape:
///
///     replaced 1 occurrence in src/main.go
///     <ESC>[90m unchanged context line<ESC>[0m
///     <ESC>[31m-removed line<ESC>[0m
///     <ESC>[32m+added line<ESC>[0m
///     <ESC>[90m unchanged context line<ESC>[0m
///
/// We strip the ANSI escapes (kincode emits them so the terminal REPL
/// shows colors; the Mac UI does its own coloring), parse the +/-/space
/// prefix, and render each line with a background tint matching git's
/// terminal diff palette.
struct DiffView: View {

    /// Raw tool_result body (with ANSI codes).
    let raw: String

    var body: some View {
        let parsed = Self.parse(raw)
        VStack(alignment: .leading, spacing: 0) {
            header(summary: parsed.summary,
                   added: parsed.added,
                   removed: parsed.removed)
            if !parsed.lines.isEmpty {
                ForEach(Array(parsed.lines.enumerated()), id: \.offset) {
                    _, line in
                    row(line)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func header(summary: String, added: Int, removed: Int) -> some View {
        HStack(spacing: 6) {
            if !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if added + removed > 0 {
                if added > 0 {
                    Text("+\(added)")
                        .font(.system(size: 10, weight: .semibold,
                                      design: .monospaced))
                        .foregroundColor(.green.opacity(0.85))
                }
                if removed > 0 {
                    Text("−\(removed)")
                        .font(.system(size: 10, weight: .semibold,
                                      design: .monospaced))
                        .foregroundColor(.red.opacity(0.85))
                }
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row(_ line: ParsedLine) -> some View {
        HStack(spacing: 0) {
            Text(line.marker)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(line.kind.markerColor)
                .frame(width: 10, alignment: .leading)
            Text(line.body)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(line.kind.textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .background(line.kind.background)
    }

    // MARK: - Parsing

    enum LineKind {
        case context, added, removed

        var background: Color {
            switch self {
            case .context: return .clear
            case .added:   return Color.green.opacity(0.10)
            case .removed: return Color.red.opacity(0.10)
            }
        }
        var markerColor: Color {
            switch self {
            case .context: return .secondary.opacity(0.5)
            case .added:   return .green.opacity(0.85)
            case .removed: return .red.opacity(0.85)
            }
        }
        var textColor: Color {
            switch self {
            case .context: return .secondary
            case .added:   return .primary
            case .removed: return .primary
            }
        }
    }

    struct ParsedLine {
        let kind: LineKind
        let marker: String
        let body: String
    }

    struct Parsed {
        let summary: String       // first line, e.g. "replaced 1 occurrence in foo.go"
        let lines: [ParsedLine]
        let added: Int
        let removed: Int
    }

    /// Strip ANSI color codes and split into typed diff lines. Public
    /// (well, internal) so it's testable; the View itself just calls
    /// this once at render time.
    static func parse(_ raw: String) -> Parsed {
        let stripped = stripANSI(raw)
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }

        var summary = ""
        var parsed: [ParsedLine] = []
        var added = 0
        var removed = 0

        // First non-empty line is the "replaced N occurrences in PATH"
        // summary; everything after is diff body.
        var startIdx = 0
        for (i, line) in lines.enumerated() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                summary = line
                startIdx = i + 1
                break
            }
        }

        for line in lines[startIdx...] {
            // Diff lines are " ctx", "-old", "+new". Lines that don't
            // match any prefix get treated as context (defensive — tool
            // output occasionally has trailing summary noise).
            if line.hasPrefix("+") {
                added += 1
                parsed.append(.init(kind: .added,
                                    marker: "+",
                                    body: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                removed += 1
                parsed.append(.init(kind: .removed,
                                    marker: "-",
                                    body: String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                parsed.append(.init(kind: .context,
                                    marker: " ",
                                    body: String(line.dropFirst())))
            } else if line.isEmpty {
                // Skip blank lines — kincode's diff doesn't emit them
                // intentionally; any blanks are formatting artifacts.
                continue
            } else {
                parsed.append(.init(kind: .context, marker: " ", body: line))
            }
        }

        return Parsed(summary: summary,
                      lines: parsed,
                      added: added,
                      removed: removed)
    }

    /// Strip ANSI CSI sequences. We only need to handle SGR (color)
    /// codes — `\u{1b}[...m`. Defensive: also drops other CSI like
    /// cursor moves in case some tool sneaks them in.
    private static func stripANSI(_ s: String) -> String {
        // Single-pass scan; faster than regex for the typical short
        // diff outputs (a few hundred bytes).
        var out = ""
        out.reserveCapacity(s.count)
        var iter = s.unicodeScalars.makeIterator()
        while let c = iter.next() {
            if c.value == 0x1B { // ESC
                guard let next = iter.next(), next == "[" else { continue }
                // Consume until a letter (the final byte of CSI).
                while let n = iter.next() {
                    let v = n.value
                    if (0x40...0x7E).contains(v) { break }
                }
                continue
            }
            out.unicodeScalars.append(c)
        }
        return out
    }
}
