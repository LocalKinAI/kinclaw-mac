import SwiftUI

/// "Cowork" mode: chat alongside an inline live-screen feed.
///
/// Stage 2 ships the *placeholder*. The real surface lands in Stage 3
/// (chat + the kinclaw kernel's /api/screen/current.jpg feed embedded
/// above the message stream so the agent and the user are looking at
/// the same desktop frame as the conversation unfolds).
///
/// Until then we render an explanatory empty state so the mode switch
/// is visible — clicking the Cowork pill flips to this view, the user
/// sees what's coming, and goes back to Chat.
struct CoworkPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.secondary)

            Text("Cowork mode")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text("Chat with an agent that's watching your screen.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Shipping in Stage 3 — wires the kinclaw screen claw\nfeed inline above the message stream.")
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
