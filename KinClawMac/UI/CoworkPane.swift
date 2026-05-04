import SwiftUI

/// "Cowork" mode: chat with an agent that's watching your screen.
///
/// Layout:
///
///   ┌──────────────────────────────────┐
///   │  🔴 LIVE · Reminders              │  ← screen feed (fixed 220pt)
///   │  [JPEG capture from kinclaw]      │
///   │                                    │
///   ├──────────────────────────────────┤
///   │  user: did I miss anything?        │
///   │  Pilot: looks like you have...     │  ← chat (existing surface)
///   ├──────────────────────────────────┤
///   │  [input bar]                       │
///   └──────────────────────────────────┘
///
/// The screen feed is driven by ScreenFeedView, which polls
/// kinclaw's `/api/screen/current.jpg` (cached 800ms server-side).
/// The chat surface is the same `chatBody` from SpotlightContentView
/// — we render Cowork as a vertical composition rather than forking
/// a parallel chat stack, so messages, agent picker, attachments,
/// voice, and history all keep working without duplication.
///
/// Stage 3 ships the basic vertical layout. Future polish:
///   - Drag the divider between feed and chat to resize
///   - Click the feed to enlarge to full panel (push chat off-screen)
///   - "Use this frame as context" button to inline the current
///     capture as an attachment to the next message
struct CoworkPane<Chat: View>: View {

    /// kinclaw kernel port. Defaults match KinClawSupervisor's default.
    let kinclawPort: Int

    /// The shared chat surface — passed in from the parent so we
    /// don't fork conversation state.
    let chat: Chat

    init(kinclawPort: Int = 5001, @ViewBuilder chat: () -> Chat) {
        self.kinclawPort = kinclawPort
        self.chat = chat()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenFeedView(port: kinclawPort)

            Divider()
                .opacity(0.15)
                .padding(.top, 8)

            chat
        }
    }
}
