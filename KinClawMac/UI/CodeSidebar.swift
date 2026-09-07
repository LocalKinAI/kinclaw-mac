import SwiftUI
import AppKit

/// Code's left column: the folders you work in, each expanding to the
/// conversations you have had about it, plus the active folder's files.
///
/// The Code tab has always stored sessions per repo — one directory per
/// repo hash, many session files inside — but the UI only ever resumed
/// the newest one, so switching repos silently buried the rest. This
/// makes the shape on disk the shape on screen: folders at the top,
/// their sessions nested under them, files of the active folder below.
struct CodeSidebar: View {
    let activeRepo: String
    let activeSessionID: UUID
    /// Folders the user picked but that may have no sessions yet.
    let recents: [String]
    /// Files touched in the current conversation.
    let touched: [TouchedFile]
    /// Bumped by CodePane after each turn / repo change to reload.
    let refreshToken: Int

    let onOpenSession: (CodeSessionStore.Summary) -> Void
    let onNewSession: (String) -> Void
    let onOpenFolder: (String) -> Void
    let onAddFolder: () -> Void
    let onRemoveFolder: (String) -> Void
    let onDeleteSession: (CodeSessionStore.Summary) -> Void
    let onCollapse: () -> Void

    @State private var folders: [FolderRow] = []
    @State private var expanded: Set<String> = []
    @State private var showFiles = true

    struct FolderRow: Identifiable, Equatable {
        let path: String
        let sessions: [CodeSessionStore.Summary]
        var id: String { path }
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.15)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(folders) { folder in
                        folderRow(folder)
                        if expanded.contains(folder.path) {
                            ForEach(folder.sessions) { s in
                                sessionRow(s, in: folder)
                            }
                            newSessionRow(folder)
                        }
                    }
                    if !activeRepo.isEmpty {
                        Divider().opacity(0.12).padding(.vertical, 6)
                        filesSection
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.platformSecondaryBackground.opacity(0.35))
        .onAppear(perform: reload)
        .onChange(of: refreshToken) { _, _ in reload() }
        .onChange(of: activeRepo) { _, _ in reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Text("FOLDERS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
            Button(action: onAddFolder) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a folder")
            Button(action: onCollapse) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide the folder pane (⇧⌘L)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Rows

    private func folderRow(_ f: FolderRow) -> some View {
        let isActive = f.path == activeRepo
        return Button {
            toggle(f.path)
            if !isActive { onOpenFolder(f.path) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: expanded.contains(f.path) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Image(systemName: isActive ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .green.opacity(0.85) : .secondary)
                Text(f.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if !f.sessions.isEmpty {
                    Text("\(f.sessions.count)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? Color.green.opacity(0.10) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(f.path)
        .contextMenu {
            Button("Open") { onOpenFolder(f.path) }
            Button("New session here") { onNewSession(f.path) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)])
            }
            Divider()
            Button("Remove from list", role: .destructive) { onRemoveFolder(f.path) }
        }
    }

    private func sessionRow(_ s: CodeSessionStore.Summary, in f: FolderRow) -> some View {
        let isActive = (s.id == activeSessionID && f.path == activeRepo)
        return Button {
            onOpenSession(s)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 9))
                    .foregroundColor(isActive ? .green.opacity(0.85) : .secondary.opacity(0.7))
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.title)
                        .font(.system(size: 11, weight: isActive ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(relative(s.updatedAt))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 26)
            .padding(.trailing, 8)
            .padding(.vertical, 2)
            .background(isActive ? Color.green.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(s.title)\n\(s.messageCount) messages")
        .contextMenu {
            Button("Open") { onOpenSession(s) }
            Button("Delete", role: .destructive) { onDeleteSession(s) }
        }
    }

    private func newSessionRow(_ f: FolderRow) -> some View {
        Button {
            onNewSession(f.path)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("New session")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
                Spacer(minLength: 0)
            }
            .padding(.leading, 26)
            .padding(.trailing, 8)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Files of the active folder

    @ViewBuilder
    private var filesSection: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { showFiles.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showFiles ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("FILES")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if showFiles {
            // The tree and the touched-file list already exist as one
            // component; reuse it headerless so Code shows the same
            // thing Cowork does under its own folder list.
            WorkspaceSidebar(workspace: activeRepo,
                             touched: touched,
                             refreshToken: refreshToken,
                             onPick: {},
                             showHeader: false)
                .frame(maxHeight: 400)
        }
    }

    // MARK: Behaviour

    private func toggle(_ path: String) {
        if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) }
    }

    /// Folders with stored sessions, merged with folders the user has
    /// picked but not yet talked to (so a freshly added repo shows up).
    private func reload() {
        var rows = CodeSessionStore.folders().map {
            FolderRow(path: $0.path, sessions: CodeSessionStore.sessions(repoPath: $0.path))
        }
        let known = Set(rows.map { $0.path })
        for p in ([activeRepo] + recents) where !p.isEmpty && !known.contains(p) {
            rows.insert(FolderRow(path: p, sessions: []), at: 0)
        }
        // Dedupe while keeping order (activeRepo may also be in recents).
        var seen = Set<String>()
        folders = rows.filter { seen.insert($0.path).inserted }
        if !activeRepo.isEmpty { expanded.insert(activeRepo) }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
