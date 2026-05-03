import SwiftUI

/// Session-history list shown as a popover when the user clicks the
/// 📚 button in the chat header. Lists all saved sessions for the
/// currently-selected agent, newest-first. Each row supports:
///   - click → load that session
///   - hover → 🗑 delete button appears
/// Top of the list has a "+ New chat" action.
struct SessionHistoryPopover: View {
    let agentSlug: String
    let activeSessionID: UUID?
    let onPick: (ChatSession) -> Void
    let onNew: () -> Void
    let onDelete: (ChatSession) -> Void

    @State private var sessions: [ChatSession] = []
    @State private var hoveredID: UUID?
    @State private var pendingDeletionID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header / new-chat row
            Button {
                onNew()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text("New chat")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().opacity(0.2)

            // Session list — scroll if many, capped at ~360pt tall
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if sessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(sessions) { session in
                            sessionRow(session)
                                .background(
                                    activeSessionID == session.id
                                    ? Color.green.opacity(0.08)
                                    : (hoveredID == session.id
                                       ? Color.platformSecondaryBackground
                                            .opacity(0.6)
                                       : Color.clear)
                                )
                                .onHover { hovering in
                                    hoveredID = hovering ? session.id : nil
                                }
                            Divider().opacity(0.12)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .onAppear { reload() }
    }

    // MARK: - Row

    @ViewBuilder
    private func sessionRow(_ session: ChatSession) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(relativeFormatter.localizedString(
                        for: session.updatedAt, relativeTo: Date()))
                    Text("·")
                    Text("\(session.messages.count) msg")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)

            // Delete button — visible only on hover
            if hoveredID == session.id {
                Button {
                    pendingDeletionID = session.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Delete this session")
                .alert(
                    "Delete this session?",
                    isPresented: Binding(
                        get: { pendingDeletionID == session.id },
                        set: { if !$0 { pendingDeletionID = nil } }
                    )
                ) {
                    Button("Delete", role: .destructive) {
                        onDelete(session)
                        sessions.removeAll { $0.id == session.id }
                        pendingDeletionID = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingDeletionID = nil
                    }
                } message: {
                    Text(session.displayTitle)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onPick(session)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No saved chats yet")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Send a message to start one.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Loading

    private func reload() {
        sessions = ChatSessionStore.list(for: agentSlug)
    }

    // MARK: - Helpers

    private var relativeFormatter: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }
}
