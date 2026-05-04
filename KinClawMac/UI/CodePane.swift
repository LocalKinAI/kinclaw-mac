import SwiftUI

/// "Code" mode: repo-aware coding agent driven by kincode on :5002.
///
/// Stage 2 ships the *placeholder*. The real surface lands in Stage 4
/// (3-4 days):
///
///   ┌──────────────────────────────────────────┐
///   │ 📁 ~/Documents/Workspace/kincode  ▾      │  ← repo picker
///   ├──────┬───────────────────────────────────┤
///   │ tree │ chat / diff viewer                │
///   │      │                                   │
///   │      │  user: refactor pkg/server        │
///   │      │  kincode: I'll edit server.go ... │
///   │      │  [diff: server.go +12 -3]         │
///   └──────┴───────────────────────────────────┘
///
/// Stage 1 already shipped the kincode HTTP+SSE server (`kincode -serve`,
/// :5002) so this UI just plugs into the same SSEClient we already
/// have for kinclaw — same event shapes (text_delta / tool_call /
/// tool_result / turn_done) just on a different port.
struct CodePane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.secondary)

            Text("Code mode")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text("Repo-aware coding agent — kincode on :5002.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Server is live (Stage 1 ✓). UI lands in Stage 4:\nrepo picker + file tree + diff viewer.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}
