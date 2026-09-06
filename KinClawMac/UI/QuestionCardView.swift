import SwiftUI

/// One `ask_user` question from the kernel (`question` SSE event). The
/// turn is parked until the user answers via POST /api/answer.
struct PendingQuestion: Identifiable, Equatable {
    let id: String
    let text: String
    let options: [String]
}

/// The agent asked a question — Claude Code's AskUserQuestion, inline.
/// Options render as chips (one click answers); a text field takes
/// anything else. ⌘⏎ sends the typed answer.
struct QuestionCardView: View {
    let question: PendingQuestion
    let onAnswer: (String) -> Void

    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.cyan)
                Text("Pilot asks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(question.text)
                .font(.system(size: 12, weight: .medium))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !question.options.isEmpty {
                // Chips wrap onto as many rows as needed.
                FlowLayout(spacing: 6) {
                    ForEach(question.options, id: \.self) { opt in
                        Button(opt) { onAnswer(opt) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.cyan)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField(question.options.isEmpty ? "Your answer…" : "Or type something else…",
                          text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { send() }
                Button("Send") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.small)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(Color.cyan.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { if question.options.isEmpty { focused = true } }
    }

    private func send() {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onAnswer(t)
    }
}

/// Minimal wrapping HStack for option chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
