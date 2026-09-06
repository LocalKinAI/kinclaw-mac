import SwiftUI

/// One approval request from the kinclaw kernel's permission gate
/// (`permission_request` SSE event). Lives on SpotlightContentView as
/// `pendingPermission` while the turn is parked waiting for the human.
struct PermissionRequest: Identifiable, Equatable {
    let id: String
    let skill: String
    /// One-line rendering of the call, e.g. "shell: rm -rf ./build".
    let summary: String
    /// Why the gate stopped: which rule matched, or "looks irreversible".
    let reason: String
    let params: [String: String]
}

/// The approval card — the Cowork equivalent of Claude Desktop's
/// "Allow this tool?" sheet, inline above the composer so the user's
/// eyes don't have to leave the conversation.
///
/// Three answers, same as Claude Code: allow this once, allow this
/// skill for the rest of the session, or deny (the model gets told and
/// adapts instead of retrying). Esc denies; ⌘⏎ allows once.
struct PermissionCardView: View {
    let request: PermissionRequest
    /// "allow" | "allow_session" | "deny"
    let onDecision: (String) -> Void

    @State private var showParams = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("Pilot wants to run")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if !request.params.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) { showParams.toggle() }
                    } label: {
                        Text(showParams ? "hide details" : "details")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(request.summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !request.reason.isEmpty {
                Text(request.reason)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if showParams {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(request.params.keys.sorted()), id: \.self) { k in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(k):")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(request.params[k] ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(6)
                        }
                    }
                }
                .padding(8)
                .background(Color.platformTertiaryBackground.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Button("Deny") { onDecision("deny") }
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Refuse — the agent is told and will adapt (Esc)")
                Spacer()
                Button("Always this session") { onDecision("allow_session") }
                    .help("Approve every \(request.skill) call until the helper restarts")
                Button("Allow") { onDecision("allow") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help("Run this one call (⌘⏎)")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// "62% of context" — a capsule bar with the number, fed by the
/// kernel's `usage` events. Turns amber past the compaction threshold
/// so the user knows a fold is about to happen (or why it just did).
struct ContextMeterView: View {
    let used: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }

    private var color: Color {
        if fraction >= 0.75 { return .orange }
        if fraction >= 0.5 { return .yellow }
        return .green
    }

    var body: some View {
        HStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(color.opacity(0.75))
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(width: 36, height: 4)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .help("Context: \(used.formatted()) of \(total.formatted()) tokens — the kernel compacts older turns automatically past 75%")
    }
}

/// Banner shown while plan mode is on — the agent can look but not act.
struct PlanModeBannerView: View {
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("Plan mode — the agent investigates and proposes; nothing on your screen changes until you turn this off.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button("Act") { onExit() }
                .controlSize(.mini)
                .help("Leave plan mode and let the agent execute (⇧⌘P)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
