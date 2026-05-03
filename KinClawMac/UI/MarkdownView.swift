import SwiftUI

/// Lightweight block-level markdown renderer for chat bubbles.
///
/// SwiftUI's `Text(LocalizedStringKey(...))` handles inline markdown
/// (**bold** / *italic* / `code` / [links]) but ignores everything
/// block-level — headings collapse, lists print as raw "- " text,
/// fenced code blocks render with backticks visible. This view does
/// just enough block parsing to make assistant replies legible
/// without pulling in a full markdown library.
///
/// Blocks supported:
///   - Fenced code blocks (```)        → mono font, surface bg
///   - ATX headings (#, ##, ###)        → font weight + size
///   - Unordered lists (- or *)         → bullets, hanging indent
///   - Ordered lists (1.)                → numbers, hanging indent
///   - Blockquotes (>)                  → left rule + dim text
///   - Paragraphs                       → inline markdown via
///                                        LocalizedStringKey
///
/// Not supported (yet): tables, nested lists, images, footnotes,
/// task lists. The default text path covers everything else
/// reasonably enough.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) {
                _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let s):
            Text(LocalizedStringKey(s))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let s):
            let size: CGFloat = level == 1 ? 18 : level == 2 ? 16 : 14
            Text(LocalizedStringKey(s))
                .font(.system(size: size, weight: .bold))
                .padding(.top, 2)

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(LocalizedStringKey(item))
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .codeBlock(let lang, let body):
            CodeBlockView(language: lang, content: body)

        case .blockquote(let s):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 2)
                Text(LocalizedStringKey(s))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Code block (mono surface)

private struct CodeBlockView: View {
    let language: String?
    let content: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    copy()
                } label: {
                    Image(systemName: copied ? "checkmark"
                                              : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.platformTertiaryBackground.opacity(0.4))

            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary.opacity(0.95))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color.platformTertiaryBackground.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }
}

// MARK: - Block model + parser

enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, String)
    /// items, ordered? — items are already-stripped of the bullet/
    /// number prefix.
    case list(items: [String], ordered: Bool)
    case codeBlock(language: String?, body: String)
    case blockquote(String)
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block (```lang ... ```)
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var bodyLines: [String] = []
                i += 1
                while i < lines.count {
                    let inner = lines[i]
                    if inner.trimmingCharacters(in: .whitespaces) == "```" {
                        break
                    }
                    bodyLines.append(inner)
                    i += 1
                }
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    body: bodyLines.joined(separator: "\n")
                ))
                i += 1 // skip closing ```
                continue
            }

            // Heading
            if let hash = trimmed.range(of: "^#{1,6} ", options: .regularExpression) {
                let level = trimmed.distance(from: trimmed.startIndex,
                                              to: hash.upperBound) - 1
                let title = String(trimmed[hash.upperBound...])
                blocks.append(.heading(level: level, title))
                i += 1
                continue
            }

            // Blockquote — collect contiguous `> ` lines
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    let stripped = t
                        .replacingOccurrences(of: "^> ?",
                                              with: "",
                                              options: .regularExpression)
                    quoteLines.append(stripped)
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            // List — unordered (- / *) or ordered (1. / 2.)
            if isUnorderedListLine(trimmed) || isOrderedListLine(trimmed) {
                let ordered = isOrderedListLine(trimmed)
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if ordered ? isOrderedListLine(t) : isUnorderedListLine(t) {
                        items.append(stripListPrefix(t))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(items: items, ordered: ordered))
                continue
            }

            // Empty line — paragraph separator
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Paragraph — collect contiguous non-empty, non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty
                    || t.hasPrefix("```")
                    || t.hasPrefix(">")
                    || t.hasPrefix("# ") || t.hasPrefix("## ") || t.hasPrefix("### ")
                    || isUnorderedListLine(t) || isOrderedListLine(t) {
                    break
                }
                paraLines.append(lines[i])
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    private static func isUnorderedListLine(_ t: String) -> Bool {
        t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }

    private static func isOrderedListLine(_ t: String) -> Bool {
        t.range(of: "^\\d+\\. ", options: .regularExpression) != nil
    }

    private static func stripListPrefix(_ t: String) -> String {
        if let m = t.range(of: "^(- |\\* |\\+ |\\d+\\. )",
                           options: .regularExpression) {
            return String(t[m.upperBound...])
        }
        return t
    }
}
