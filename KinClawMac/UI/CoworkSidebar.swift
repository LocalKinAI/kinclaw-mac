import SwiftUI
import AppKit

/// Cowork's left column: the folders Pilot has worked in, each
/// expanding to the conversations that happened there, plus the active
/// folder's files.
///
/// Cowork sessions are stored per agent, not per folder, so the grouping
/// key is the `workspace` recorded on each session. Conversations from
/// before that field existed group under "No folder" — they are still
/// yours, they just predate the folder.
struct CoworkSidebar: View {
    let activeWorkspace: String
    let activeSessionID: UUID
    let activeAgentSlug: String
    /// Slugs of the local KinClaw souls. Conversations with cloud agents
    /// live in the Chat tab and have no folder; showing them here would
    /// make the folder pane a list of everything the user has ever said.
    let localAgentSlugs: Set<String>
    let touched: [TouchedFile]
    let refreshToken: Int

    let onOpenSession: (ChatSession) -> Void
    let onNewSession: (String) -> Void
    let onOpenFolder: (String) -> Void
    let onPickFolder: () -> Void
    let onDeleteSession: (ChatSession) -> Void
    let onCollapse: () -> Void

    @State private var groups: [Group] = []
    @State private var expanded: Set<String> = []
    /// Groups the user asked to see in full. A folder worked in for
    /// months has hundreds of conversations; the pane shows the newest
    /// `pageSize` and offers the rest behind one row.
    @State private var fullyShown: Set<String> = []

    private let pageSize = 15

    struct Group: Identifiable, Equatable {
        let workspace: String
        let sessions: [ChatSession]
        var id: String { workspace }
        var name: String {
            workspace.isEmpty ? "No folder"
                : URL(fileURLWithPath: workspace).lastPathComponent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.15)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(groups) { g in
                        folderRow(g)
                        if expanded.contains(g.workspace) {
                            let shown = fullyShown.contains(g.workspace)
                                ? g.sessions : Array(g.sessions.prefix(pageSize))
                            ForEach(shown) { s in
                                sessionRow(s, in: g)
                            }
                            if g.sessions.count > shown.count {
                                moreRow(g)
                            }
                            if !g.workspace.isEmpty {
                                newSessionRow(g.workspace)
                            }
                        }
                    }
                    // The file tree used to hang here. It was IDE
                    // furniture in a window where you talk to something
                    // that reads files for you, and Finder does it
                    // better. What the agent touched moved to a line
                    // above the composer, where it is read.
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.platformSecondaryBackground.opacity(0.35))
        .onAppear(perform: reload)
        .onChange(of: refreshToken) { _, _ in reload() }
        .onChange(of: activeWorkspace) { _, _ in reload() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("FOLDERS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
            Button(action: onPickFolder) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose the folder Pilot works in")
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

    private func folderRow(_ g: Group) -> some View {
        let isActive = g.workspace == activeWorkspace && !g.workspace.isEmpty
        return Button {
            toggle(g.workspace)
            if !isActive && !g.workspace.isEmpty { onOpenFolder(g.workspace) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: expanded.contains(g.workspace) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Image(systemName: g.workspace.isEmpty ? "tray"
                      : (isActive ? "folder.fill" : "folder"))
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .green.opacity(0.85) : .secondary)
                Text(g.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text("\(g.sessions.count)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? Color.green.opacity(0.10) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(g.workspace.isEmpty
              ? "Conversations from before the workspace existed"
              : g.workspace)
        .contextMenu {
            if !g.workspace.isEmpty {
                Button("Work here") { onOpenFolder(g.workspace) }
                Button("New session here") { onNewSession(g.workspace) }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: g.workspace)])
                }
            }
        }
    }

    private func sessionRow(_ s: ChatSession, in g: Group) -> some View {
        let isActive = (s.id == activeSessionID)
        // The agent is worth showing only when it isn't the one you are
        // talking to — otherwise it is the same lobster on every row.
        let otherAgent = s.agentSlug != activeAgentSlug ? s.agentSlug : nil
        return Button {
            onOpenSession(s)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 9))
                    .foregroundColor(isActive ? .green.opacity(0.85) : .secondary.opacity(0.7))
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.displayTitle)
                        .font(.system(size: 11, weight: isActive ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text(relative(s.updatedAt))
                        if let a = otherAgent {
                            Text("· \(a)").lineLimit(1).truncationMode(.tail)
                        }
                    }
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
        .help("\(s.displayTitle)\n\(s.messages.count) messages · \(s.agentSlug)")
        .contextMenu {
            Button("Open") { onOpenSession(s) }
            Button("Delete", role: .destructive) { onDeleteSession(s) }
        }
    }

    private func moreRow(_ g: Group) -> some View {
        Button {
            fullyShown.insert(g.workspace)
        } label: {
            Text("… \(g.sessions.count - pageSize) older")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.leading, 26)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func newSessionRow(_ workspace: String) -> some View {
        Button {
            onNewSession(workspace)
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

    private func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    private func reload() {
        var g = ChatSessionStore.byWorkspace().compactMap { entry -> Group? in
            // A session with a folder was had in Cowork by construction.
            // One without predates the folder, so fall back to asking
            // whether its agent is a local soul.
            let kept = entry.workspace.isEmpty
                ? entry.sessions.filter { localAgentSlugs.contains($0.agentSlug) }
                : entry.sessions
            return kept.isEmpty ? nil : Group(workspace: entry.workspace, sessions: kept)
        }
        // The folder you are in belongs on the list even before its
        // first conversation is saved.
        if !activeWorkspace.isEmpty && !g.contains(where: { $0.workspace == activeWorkspace }) {
            g.insert(Group(workspace: activeWorkspace, sessions: []), at: 0)
        }
        groups = g
        if !activeWorkspace.isEmpty { expanded.insert(activeWorkspace) }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
