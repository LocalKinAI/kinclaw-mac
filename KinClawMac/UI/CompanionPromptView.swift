import SwiftUI

/// The two things that park a turn — the permission gate and
/// `ask_user` — shown over the companion's picture.
///
/// Companion mode reads them out loud, and that is the fast path: you
/// answer without looking. But a voice-only prompt is invisible if you
/// stepped away while it was speaking, and a question with four options
/// is not something anyone wants recited. So the same prompt also docks
/// at the bottom of the picture, the way Claude Desktop puts its
/// approval sheet at the bottom of the conversation: options you can
/// click, and a field for anything else.
///
/// Styled for a photograph rather than a window — dark, translucent,
/// high-contrast text — because whatever is behind it is somebody's
/// dog.
struct CompanionPromptView: View {

    enum Prompt: Equatable {
        case permission(PermissionRequest)
        case question(PendingQuestion)
    }

    let prompt: Prompt
    /// Permission: "allow" | "allow_session" | "deny".
    let onDecision: (String) -> Void
    /// Question: the answer text.
    let onAnswer: (String) -> Void

    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch prompt {
            case .permission(let req):
                Text(req.summary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !req.reason.isEmpty {
                    Text(req.reason)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    choice("可以", tint: .green) { onDecision("allow") }
                    choice("一直可以", tint: .green.opacity(0.7)) { onDecision("allow_session") }
                    choice("不要", tint: .red.opacity(0.8)) { onDecision("deny") }
                    Spacer(minLength: 0)
                }
            case .question(let q):
                Text(q.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !q.options.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(q.options, id: \.self) { opt in
                            choice(opt, tint: .cyan) { onAnswer(opt) }
                        }
                    }
                }
                HStack(spacing: 6) {
                    TextField(q.options.isEmpty ? "说，或者打字…" : "或者自己写一个…",
                              text: $typed)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .focused($focused)
                        .onSubmit { send() }
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(typed.trimmingCharacters(in: .whitespaces).isEmpty
                                             ? .white.opacity(0.25) : .cyan)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.5), lineWidth: 1)
                )
        )
        .frame(maxWidth: 460)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var accent: Color {
        if case .permission = prompt { return .orange }
        return .cyan
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: {
                if case .permission = prompt { return "hand.raised.fill" }
                return "questionmark.bubble.fill"
            }())
            .font(.system(size: 11))
            .foregroundColor(accent)
            Text({
                if case .permission = prompt { return "要不要让我做这个" }
                return "想问你一下"
            }())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text("说话也行")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    /// One tappable answer. Big enough to hit from across a desk, which
    /// is the distance companion mode is used from.
    private func choice(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(tint.opacity(0.85)))
        }
        .buttonStyle(.plain)
    }

    private func send() {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        typed = ""
        onAnswer(t)
    }
}
