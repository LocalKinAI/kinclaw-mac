import SwiftUI
import AVFoundation

/// A muted, endlessly looping clip that fills its frame — the moving
/// version of a background picture. The decode is hardware, so a 1080p
/// loop of a sleeping cat costs about nothing.
///
/// The seam is the view's job, not the clip's. A generated clip ends
/// somewhere other than where it began — she has drifted a hand's width to
/// the right by the fourth second — and played end to start that is a jump
/// cut every four seconds, in a feature whose whole point is that nothing
/// reads as a cut. The first eight scenes had the seam dissolved into the
/// file by ffmpeg; a place she has built for herself has been through no
/// such thing, and the app has no ffmpeg to give it one. So two players
/// take turns: half a second before one runs out, the other starts from
/// the top and fades in over it. Any clip loops cleanly, whoever made it.
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
        private let players = [AVPlayer(), AVPlayer()]
        private let layers = [AVPlayerLayer(), AVPlayerLayer()]
        private var boundaries: [Any?] = [nil, nil]
        private var ends: [NSObjectProtocol] = []
        /// Which of the two is on screen.
        private var front = 0
        /// Bumped on every load: a duration that arrives late must not arm
        /// a view that has moved on to another clip.
        private var generation = 0
        /// How long one hands over to the other.
        private static let fade = 0.5

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for i in 0..<2 {
                players[i].isMuted = true
                players[i].actionAtItemEnd = .pause
                layers[i].player = players[i]
                layers[i].videoGravity = .resizeAspectFill
                layer?.addSublayer(layers[i])
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            // The layers must track the view exactly, without the implicit
            // animation that would show the old size for a beat on resize.
            quietly { for l in layers { l.frame = bounds } }
        }

        func load(_ url: URL) {
            unload()
            self.url = url
            generation += 1
            let mine = generation
            let asset = AVURLAsset(url: url)
            for p in players { p.replaceCurrentItem(with: AVPlayerItem(asset: asset)) }
            front = 0
            quietly {
                layers[0].opacity = 1; layers[0].zPosition = 0
                layers[1].opacity = 0; layers[1].zPosition = 1
            }
            players[0].play()
            // Whatever else happens, a clip that reaches its end starts over.
            // The handover below normally gets there first; this is what
            // keeps a very short clip, or one whose duration never loads,
            // from stopping on its last frame.
            for i in 0..<2 {
                ends.append(NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: players[i].currentItem,
                    queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.ranOut(i) }
                    })
            }
            Task { @MainActor [weak self] in
                guard let seconds = try? await asset.load(.duration).seconds,
                      let self, self.generation == mine else { return }
                self.arm(duration: seconds)
            }
        }

        func unload() {
            for i in 0..<2 {
                if let b = boundaries[i] { players[i].removeTimeObserver(b) }
                boundaries[i] = nil
                players[i].pause()
                players[i].replaceCurrentItem(with: nil)
            }
            for e in ends { NotificationCenter.default.removeObserver(e) }
            ends = []
            url = nil
        }

        /// Half a second before either player runs out, the other takes over.
        private func arm(duration: Double) {
            guard duration.isFinite, duration > Self.fade * 3 else { return }
            let mark = NSValue(time: CMTime(seconds: duration - Self.fade, preferredTimescale: 600))
            for i in 0..<2 {
                boundaries[i] = players[i].addBoundaryTimeObserver(forTimes: [mark], queue: .main) { [weak self] in
                    MainActor.assumeIsolated { self?.handOver(from: i) }
                }
            }
        }

        private func handOver(from old: Int) {
            guard old == front else { return }
            let new = 1 - old
            front = new
            players[new].seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            players[new].play()
            quietly {
                layers[new].zPosition = 1
                layers[old].zPosition = 0
            }
            let rise = CABasicAnimation(keyPath: "opacity")
            rise.fromValue = 0
            rise.toValue = 1
            rise.duration = Self.fade
            layers[new].add(rise, forKey: "rise")
            quietly { layers[new].opacity = 1 }
            // The old one plays out underneath and pauses at its own end; it
            // is hidden only once the new one fully covers it.
            let mine = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fade + 0.05) { [weak self] in
                guard let self, self.generation == mine, self.front == new else { return }
                self.quietly { self.layers[old].opacity = 0 }
                self.players[old].pause()
                self.players[old].seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }

        private func ranOut(_ i: Int) {
            guard i == front else { return }
            players[i].seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            players[i].play()
        }

        private func quietly(_ change: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            change()
            CATransaction.commit()
        }
    }
}
