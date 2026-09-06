import SwiftUI
import AppKit

/// A file the agent touched this session, derived from file_read /
/// file_write / file_edit tool calls in the transcript.
struct TouchedFile: Identifiable, Equatable {
    let path: String
    /// "read" | "write" | "edit" — writes win over reads for the same path.
    let action: String
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// Cowork's left column — Claude Desktop's folder pane: the working
/// folder (click to change), the files the agent read or changed this
/// session, and the folder's contents. Everything is a click away from
/// Finder, so "where is it working" is never a question.
struct WorkspaceSidebar: View {
    let workspace: String
    let touched: [TouchedFile]
    /// Bumped by the owner after every turn so the listing reloads.
    let refreshToken: Int
    let onPick: () -> Void
    /// Hides the pane (the ‹ button in the header). ⇧⌘L and the toolbar
    /// icon do the same; this one is the discoverable one.
    var onCollapse: (() -> Void)? = nil

    struct FileEntry: Identifiable, Equatable {
        let path: String
        let name: String
        let isDir: Bool
        var id: String { path }
    }

    @State private var entries: [FileEntry] = []
    @State private var children: [String: [FileEntry]] = [:]
    @State private var expandedDirs: Set<String> = []

    private var touchedSet: Set<String> { Set(touched.map { $0.path }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.15)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !touched.isEmpty {
                        sectionLabel("This session")
                        ForEach(touched) { f in
                            touchedRow(f)
                        }
                        Divider().opacity(0.12).padding(.vertical, 4)
                    }
                    sectionLabel("Files")
                    if entries.isEmpty {
                        Text(workspace.isEmpty ? "No workspace yet" : "Empty folder")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    ForEach(rows) { r in
                        fileRow(r.entry, depth: r.depth)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.platformSecondaryBackground.opacity(0.35))
        .onAppear(perform: reload)
        .onChange(of: workspace) { _, _ in
            expandedDirs = []
            children = [:]
            reload()
        }
        .onChange(of: refreshToken) { _, _ in reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onPick) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(workspace.isEmpty ? "Choose folder…"
                             : URL(fileURLWithPath: workspace).lastPathComponent)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if !workspace.isEmpty {
                            Text(abbreviated(workspace))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(workspace.isEmpty ? "Choose the folder Pilot works in" : "\(workspace)\nClick to change the workspace")

            if let collapse = onCollapse {
                Button(action: collapse) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide the folder pane (⇧⌘L)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Rows

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func touchedRow(_ f: TouchedFile) -> some View {
        let (icon, color): (String, Color) = {
            switch f.action {
            case "write": return ("plus.circle.fill", .green)
            case "edit":  return ("pencil.circle.fill", .orange)
            default:      return ("eye.circle", .secondary)
            }
        }()
        return Button {
            reveal(f.path)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(f.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(f.path)\n\(f.action) — click to reveal in Finder")
        .contextMenu { fileMenu(f.path) }
    }

    /// The tree flattened into rows (entry + depth) following the
    /// expanded folders — a recursive view would define its opaque
    /// type in terms of itself, and a flat list scrolls better anyway.
    private struct Row: Identifiable {
        let entry: FileEntry
        let depth: Int
        var id: String { entry.path }
    }

    private var rows: [Row] {
        var out: [Row] = []
        func walk(_ list: [FileEntry], _ depth: Int) {
            for e in list {
                out.append(Row(entry: e, depth: depth))
                if e.isDir, expandedDirs.contains(e.path) {
                    walk(children[e.path] ?? [], depth + 1)
                }
            }
        }
        walk(entries, 0)
        return out
    }

    private func fileRow(_ e: FileEntry, depth: Int) -> some View {
        let isTouched = touchedSet.contains(e.path)
        return Button {
            if e.isDir { toggle(e) } else { reveal(e.path) }
        } label: {
            HStack(spacing: 4) {
                if e.isDir {
                    Image(systemName: expandedDirs.contains(e.path) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                } else {
                    Color.clear.frame(width: 10)
                }
                Image(systemName: e.isDir ? "folder" : "doc")
                    .font(.system(size: 10))
                    .foregroundColor(e.isDir ? .green.opacity(0.75) : .secondary)
                Text(e.name)
                    .font(.system(size: 11, weight: isTouched ? .semibold : .regular))
                    .foregroundColor(isTouched ? .primary : .primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isTouched {
                    Circle().fill(Color.orange.opacity(0.8)).frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(10 + depth * 12))
            .padding(.trailing, 8)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(e.path)
        .contextMenu { fileMenu(e.path) }
    }

    @ViewBuilder
    private func fileMenu(_ path: String) -> some View {
        Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        Button("Reveal in Finder") { reveal(path) }
        Button("Copy path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }

    // MARK: Behaviour

    private func toggle(_ e: FileEntry) {
        if expandedDirs.contains(e.path) {
            expandedDirs.remove(e.path)
        } else {
            expandedDirs.insert(e.path)
            if children[e.path] == nil { children[e.path] = Self.list(e.path) }
        }
    }

    private func reload() {
        guard !workspace.isEmpty else { entries = []; return }
        entries = Self.list(workspace)
        for dir in expandedDirs {
            children[dir] = Self.list(dir)
        }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Directory listing: folders first, then files, hidden entries and
    /// the usual dependency dirs skipped, capped so a node_modules-sized
    /// folder can't freeze the panel.
    static func list(_ dir: String) -> [FileEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let skip: Set<String> = ["node_modules", ".git", ".venv", "__pycache__", "DerivedData", ".build"]
        var out: [FileEntry] = []
        for n in names where !n.hasPrefix(".") && !skip.contains(n) {
            let p = (dir as NSString).appendingPathComponent(n)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: p, isDirectory: &isDir)
            out.append(FileEntry(path: p, name: n, isDir: isDir.boolValue))
        }
        out.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        if out.count > 200 { out = Array(out.prefix(200)) }
        return out
    }
}


/// The collapsed state: a slim strip on the left edge with one button
/// that brings the pane back, so it never disappears without a trace.
struct WorkspaceSidebarHandle: View {
    let onExpand: () -> Void

    var body: some View {
        VStack {
            Button(action: onExpand) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the folder pane (⇧⌘L)")
            Spacer()
        }
        .frame(width: 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.platformSecondaryBackground.opacity(0.2))
    }
}
