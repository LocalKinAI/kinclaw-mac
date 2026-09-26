import SwiftUI

/// The top bar: what the panel is for right now.
///
/// Nine modes, shown as four groups (`ModeGroup`). The open group is a
/// segmented track with its members in it, the chosen one raised; every
/// other group is its icon and one word, and a click on it goes back to the
/// member of it that was used last. Right-click a group to go straight to
/// any of its members.
///
/// Drawn by hand rather than with `Picker(.segmented)`: an NSSegmentedControl
/// is opaque and fights the window's blur, and has no room for a group that
/// opens.
struct ModeBar: View {
    @Binding var mode: ChatMode

    /// 1.0 = full intensity; bar fades to ~0.4 when not focused so
    /// it doesn't compete with the chat content for attention.
    var emphasis: Double = 1.0

    var body: some View {
        // Full words while they fit; closed groups down to their icons when
        // the panel is narrow; then everything down to icons.
        ViewThatFits(in: .horizontal) {
            row(closedWords: true, openWords: true)
            row(closedWords: false, openWords: true)
            row(closedWords: false, openWords: false)
        }
        .opacity(emphasis)
    }

    private func row(closedWords: Bool, openWords: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(ModeGroup.allCases) { group in
                if group == ModeGroup.of(mode) {
                    open(group, words: openWords)
                } else {
                    closed(group, words: closedWords)
                }
            }
        }
        .fixedSize()
    }

    /// The group in use: a track with its members, the current one raised.
    private func open(_ group: ModeGroup, words: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(group.members) { item in
                Segment(item: item, on: item == mode, words: words) { pick(item) }
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.well))
    }

    private func closed(_ group: ModeGroup, words: Bool) -> some View {
        Closed(group: group, words: words) { pick(group.last) }
            .contextMenu {
                if group.members.count > 1 {
                    ForEach(group.members) { item in
                        Button { pick(item) } label: { Label(item.title, systemImage: item.symbol) }
                    }
                }
            }
    }

    private func pick(_ item: ChatMode) {
        // Persist on every change; cheap (single UserDefaults write) and
        // means the mode — and which member each group opens on — survives
        // a relaunch.
        withAnimation(.easeInOut(duration: 0.16)) { mode = item }
        item.persist()
    }

    private struct Segment: View {
        let item: ChatMode
        let on: Bool
        let words: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: item.symbol).font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(on ? Theme.accent : Color.secondary)
                    if words {
                        Text(item.title).font(.system(size: 12, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.primary : Color.secondary)
                    }
                }
                .padding(.horizontal, words ? 10 : 7).frame(height: 20)
                .background(
                    Capsule().fill(on ? Theme.card : hovering ? Theme.hover : .clear)
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, y: 0.5)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(item.help)
        }
    }

    private struct Closed: View {
        let group: ModeGroup
        let words: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: group.symbol).font(.system(size: 10.5, weight: .medium))
                    if words { Text(group.title).font(.system(size: 12)) }
                }
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .padding(.horizontal, words ? 10 : 7).frame(height: 24)
                .background(Capsule().fill(hovering ? Theme.hover : .clear))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(group.members.count > 1
                  ? "\(group.members.map(\.title).joined(separator: " · "))（右键直接去其中一个）"
                  : group.members[0].help)
        }
    }
}
