import SwiftUI
import AppKit

/// Lightweight repo file tree for Code mode's left sidebar.
///
/// Lazy: directories load their children on expand (not on view
/// construction) so a 10k-file repo doesn't stall the panel. Hidden
/// entries (dot-prefixed) and well-known noise dirs (node_modules,
/// .git, build/) are filtered by default; the eye icon toggles to
/// show everything.
///
/// Click-to-mention: clicking a file inserts its repo-relative path
/// into the next chat message via the `onPick` callback. Lets the
/// user say "explain this" without typing the path manually.
struct FileTreeView: View {

    /// Repo root — empty string means "no repo picked yet".
    let rootPath: String

    /// Called when the user clicks a file. Path is absolute; the
    /// caller is responsible for repo-relativizing if it cares.
    var onPick: (String) -> Void

    @State private var showHidden: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            Divider().opacity(0.15)

            if rootPath.isEmpty {
                Spacer()
                Text("Pick a repo")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        FileTreeNode(
                            url: URL(fileURLWithPath: rootPath),
                            depth: 0,
                            showHidden: showHidden,
                            initiallyExpanded: true,
                            onPick: onPick
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 140)
        .background(Color.white.opacity(0.02))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Files")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                showHidden.toggle()
            } label: {
                Image(systemName: showHidden ? "eye" : "eye.slash")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(showHidden ? "Hide dotfiles + build dirs" : "Show all files")
        }
    }
}

/// One row in the tree — either a leaf file or an expandable folder.
/// Recursion stops when a folder's children load. All file I/O hops
/// off the main thread via Task to keep typing responsive.
private struct FileTreeNode: View {
    let url: URL
    let depth: Int
    let showHidden: Bool
    let initiallyExpanded: Bool
    let onPick: (String) -> Void

    @State private var expanded: Bool = false
    @State private var children: [URL]?
    @State private var loading: Bool = false

    private static let noisyDirs: Set<String> = [
        "node_modules", ".git", ".build", "build", "dist",
        ".next", "target", "DerivedData", ".DS_Store",
        "__pycache__", ".venv", "venv",
    ]

    private var isDirectory: Bool {
        var b: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &b)
        return b.boolValue
    }

    private var name: String { url.lastPathComponent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if expanded, let kids = children {
                ForEach(kids, id: \.self) { kid in
                    FileTreeNode(
                        url: kid,
                        depth: depth + 1,
                        showHidden: showHidden,
                        initiallyExpanded: false,
                        onPick: onPick
                    )
                }
            }
        }
        .onAppear {
            if initiallyExpanded && !expanded { toggle() }
        }
        // Re-filter when the visibility toggle flips at the root.
        .onChange(of: showHidden) { _, _ in
            if expanded { Task { await load() } }
        }
    }

    private var row: some View {
        HStack(spacing: 4) {
            // Indent per depth — 10pt is comfortable for the
            // 140pt-min sidebar without truncating filenames hard.
            Color.clear.frame(width: CGFloat(depth) * 10, height: 1)

            if isDirectory {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Image(systemName: "folder.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            } else {
                // Spacer where the chevron would be, so file names
                // align with directory names.
                Color.clear.frame(width: 10)
                Image(systemName: iconForFile(name))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Text(name)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if isDirectory { toggle() }
            else { onPick(url.path) }
        }
    }

    private func toggle() {
        expanded.toggle()
        if expanded && children == nil {
            Task { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let kids = await Task.detached(priority: .userInitiated) {
            let mgr = FileManager.default
            guard let entries = try? mgr.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsSubdirectoryDescendants]
            ) else { return [URL]() }

            var filtered = entries.filter { entry in
                let n = entry.lastPathComponent
                if !showHidden {
                    if n.hasPrefix(".") { return false }
                    if FileTreeNode.noisyDirs.contains(n) { return false }
                }
                return true
            }

            // Directories first, alphabetical within each group.
            filtered.sort { a, b in
                let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if aIsDir != bIsDir { return aIsDir }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
            return filtered
        }.value
        await MainActor.run { self.children = kids }
    }

    /// SF Symbol for a leaf file based on its extension. Coarse —
    /// covers the common cases for a coding sidebar (Swift / Go / TS
    /// / Markdown / config) and falls through to a generic doc.
    private func iconForFile(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".swift") || lower.hasSuffix(".go") ||
           lower.hasSuffix(".ts") || lower.hasSuffix(".tsx") ||
           lower.hasSuffix(".js") || lower.hasSuffix(".jsx") ||
           lower.hasSuffix(".py") || lower.hasSuffix(".rs") ||
           lower.hasSuffix(".rb") || lower.hasSuffix(".c") ||
           lower.hasSuffix(".cpp") || lower.hasSuffix(".h") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if lower.hasSuffix(".md") || lower.hasSuffix(".txt") {
            return "doc.text"
        }
        if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") ||
           lower.hasSuffix(".yml") || lower.hasSuffix(".toml") {
            return "list.bullet.indent"
        }
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") ||
           lower.hasSuffix(".jpeg") || lower.hasSuffix(".gif") ||
           lower.hasSuffix(".webp") {
            return "photo"
        }
        return "doc"
    }
}
