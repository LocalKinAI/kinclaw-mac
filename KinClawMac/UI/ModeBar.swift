import SwiftUI

/// Three-pill segmented switcher: Chat / Cowork / Code. Sits below
/// the agent picker header, above the conversation surface.
///
/// Renders as a single horizontal row of pills, ~22pt tall. Active
/// pill gets a green-accent fill (matches the SettingsView pill
/// strip we already ship); inactive pills are translucent over the
/// glass blur, so the bar stays visually quiet on first paint and
/// only "pops" when the user is hovering / on the active surface.
///
/// Why pills instead of SwiftUI's `Picker(.segmented)`:
/// - Picker(.segmented) renders an opaque NSSegmentedControl-shaped
///   bar that fights the panel's glass blur; pills sit on top of
///   the blur cleanly.
/// - We want to show an SF Symbol + label per segment, not just a
///   label — pills give us the layout freedom.
struct ModeBar: View {
    @Binding var mode: ChatMode

    /// 1.0 = full intensity; bar fades to ~0.4 when not focused so
    /// it doesn't compete with the chat content for attention.
    var emphasis: Double = 1.0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ChatMode.allCases) { item in
                pill(for: item)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .opacity(emphasis)
    }

    @ViewBuilder
    private func pill(for item: ChatMode) -> some View {
        let isActive = (mode == item)
        Button {
            // Persist on every change; cheap (single UserDefaults
            // write) and means the mode survives a relaunch.
            withAnimation(.easeInOut(duration: 0.15)) {
                mode = item
            }
            item.persist()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(item.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive
                          ? Color.green.opacity(0.65)
                          : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive
                            ? Color.green.opacity(0.0)
                            : Color.white.opacity(0.08),
                            lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(item.help)
    }
}
