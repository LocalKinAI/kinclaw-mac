import SwiftUI
import AVFoundation

/// A muted, endlessly looping clip that fills its frame — the moving
/// version of a background picture. `AVPlayerLooper` handles the seam;
/// the decode is hardware, so a 1080p loop of a sleeping cat costs
/// about nothing.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.load(url)
        return v
    }

    func updateNSView(_ v: PlayerView, context: Context) {
        if v.url != url { v.load(url) }
    }

    static func dismantleNSView(_ v: PlayerView, coordinator: ()) {
        v.unload()
    }

    final class PlayerView: NSView {
        private(set) var url: URL?
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            player.isMuted = true
            player.actionAtItemEnd = .none
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            // The layer must track the view exactly, without the implicit
            // animation that would show the old size for a beat on resize.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        func load(_ url: URL) {
            self.url = url
            looper = nil
            player.removeAllItems()
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.play()
        }

        func unload() {
            looper = nil
            player.pause()
            player.removeAllItems()
        }
    }
}
