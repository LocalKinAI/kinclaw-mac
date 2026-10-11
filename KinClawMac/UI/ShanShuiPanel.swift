import SwiftUI

/// 活山水 beside her: the painting that follows the conversation, its knobs to play with (画题, 天气, 季节,
/// 时辰, 风, 回眸), and a way to fold it away to a chip.
struct ShanShuiPanel: View {
    @ObservedObject private var scroll = ShanShui.shared
    @ObservedObject private var player = ShanShui.shared.player

    var body: some View {
        if scroll.shown {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Color.black
                        LivePlayerView(player: player)
                        if !player.ready { ProgressView().controlSize(.small) }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button {
                        scroll.shown = false
                        scroll.pause()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .help("收起活山水")
                }
                if player.ready { LiveOptions(player: player, full: false, stacked: true) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card.opacity(0.92)))
            .onAppear { scroll.start() }
            .onDisappear { scroll.pause() }
        } else {
            Button {
                scroll.shown = true
                scroll.start()
            } label: { ChipLabel(title: "活山水", symbol: "paintbrush.pointed") }
            .buttonStyle(.plain)
            .help("她旁边那幅跟着话题变的水墨画")
        }
    }
}
