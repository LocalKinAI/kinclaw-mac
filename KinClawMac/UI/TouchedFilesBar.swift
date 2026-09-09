import SwiftUI
import AppKit

/// What the agent just touched, as one line above the composer.
///
/// This used to be a section of a file-tree sidebar, which put it next
/// to a thing it has nothing to do with. A file browser is IDE
/// furniture — you are not browsing, you are talking to something that
/// browses for you, and Finder is one ⌘-tab away and better at it. But
/// "which files did it change" is not browsing, it is the diff, and it
/// is the first thing worth knowing when a turn ends.
///
/// So it lives in the flow instead: nothing at all until the agent
/// touches something, then one quiet line that opens into the list.
struct TouchedFilesBar: View {
    let files: [TouchedFile]
    @State private var expanded = false

    private var written: [TouchedFile] { files.filter { $0.action != "read" } }

    var body: some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        Image(systemName: written.isEmpty ? "eye" : "pencil")
                            .font(.system(size: 10))
                        Text(summary)
                            .font(.system(size: 11))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(files) { f in
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: f.path)])
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: icon(for: f.action))
                                    .font(.system(size: 9))
                                    .foregroundColor(color(for: f.action))
                                Text(URL(fileURLWithPath: f.path).lastPathComponent)
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineLimit(1)
                                Text(f.path)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("在 Finder 里显示 \(f.path)")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    /// Reads are worth a count, writes are worth naming — those are the
    /// ones you may want to undo.
    private var summary: String {
        if written.isEmpty {
            return "这轮读了 \(files.count) 个文件"
        }
        if written.count == 1 {
            return "改了 \(URL(fileURLWithPath: written[0].path).lastPathComponent)"
        }
        return "改了 \(written.count) 个文件" + (files.count > written.count
            ? "，读了 \(files.count - written.count) 个" : "")
    }

    private func icon(for action: String) -> String {
        switch action {
        case "write": return "plus.circle"
        case "edit":  return "pencil.circle"
        default:      return "eye.circle"
        }
    }

    private func color(for action: String) -> Color {
        action == "read" ? .secondary : .orange
    }
}
