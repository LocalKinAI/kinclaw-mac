import SwiftUI

/// A photograph of an animal, rendered so that it is present.
///
/// Nothing here is lip sync. A dog that mouthed words would be a
/// cartoon, and an uncanny one. What makes an animal feel like it is in
/// the room is attention, and attention is four things: it breathes, it
/// blinks, its ears move when you start talking, and it looks at you —
/// leaning in while it listens, tilting its head when it does not
/// follow.
///
/// All of it is the same picture, drawn twice: once whole, and once as
/// a soft-edged disc over the head that is allowed to move. Because the
/// disc is the same pixels with a feathered mask, a few degrees of
/// rotation reads as the head turning rather than as a cut-out sliding
/// around. Blinks are two smaller discs at the eyes, squashed for a
/// tenth of a second.
///
/// Everything is small on purpose. The line between alive and
/// animatronic is a couple of degrees.
struct AnimalPuppetView: View {
    let image: NSImage
    let rig: PuppetRig
    /// The mic is open — it leans in and its ears come up.
    let isListening: Bool
    /// It is working — the head tilt every dog owner knows.
    let isThinking: Bool
    /// It is answering — a slow sway, so speech is not a still frame.
    let isSpeaking: Bool
    /// Your voice, 0…1. Ears follow it while listening.
    let audioLevel: Double

    /// Blink timing is generated once per view: a periodic blink reads
    /// as a metronome, and the eye is very good at spotting one.
    @State private var nextBlink = Date().addingTimeInterval(2.5)
    @State private var blinkStart: Date?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let s = geo.size
                let level = min(1, max(0, audioLevel))

                // Breathing: always, and barely. This is what stops a
                // still photograph from reading as a still photograph,
                // and it works precisely because nobody notices it.
                let breath = 1 + 0.007 * sin(t * 0.9)

                // Attention. Listening leans in a little; speaking
                // sways; thinking tilts, which on a dog is unmistakable.
                let lean = isListening ? 0.012 + level * 0.010 : 0
                let sway = isSpeaking ? sin(t * 1.7) * 0.006 : 0
                let tilt: Double = isThinking ? 9 * sin(t * 0.55) : (isSpeaking ? 2.0 * sin(t * 1.3) : 0)
                // Ears ride your voice while the mic is open.
                let ears = isListening ? 1 + level * 0.05 : 1

                ZStack {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                        .frame(width: s.width, height: s.height)
                        .clipped()

                    // The head, free to move.
                    headLayer(size: s)
                        .rotationEffect(.degrees(tilt), anchor: anchor)
                        .scaleEffect(1 + lean, anchor: anchor)
                        .offset(x: s.width * sway, y: -s.height * lean * 0.35)

                    // The ears, riding on top of the head's own motion.
                    if ears > 1.001 {
                        earLayer(size: s)
                            .scaleEffect(ears, anchor: anchor)
                            .rotationEffect(.degrees(tilt), anchor: anchor)
                            .offset(x: s.width * sway, y: -s.height * lean * 0.35)
                    }

                    // Blinks.
                    if let closed = blinkAmount(at: ctx.date) {
                        eyeLayer(size: s, squash: closed)
                            .rotationEffect(.degrees(tilt), anchor: anchor)
                            .offset(x: s.width * sway, y: -s.height * lean * 0.35)
                    }
                }
                .scaleEffect(breath)
                .frame(width: s.width, height: s.height)
                .clipped()
                .onChange(of: ctx.date) { _, now in schedule(now) }
            }
        }
    }

    private var anchor: UnitPoint {
        UnitPoint(x: rig.headCenter.x, y: rig.headCenter.y)
    }

    /// The same picture, masked to a soft disc over the head. Feathered
    /// hard — a crisp edge would read as a sticker.
    private func headLayer(size s: CGSize) -> some View {
        layer(size: s,
              center: rig.headCenter,
              radius: rig.headRadius,
              softness: 0.55)
    }

    private func earLayer(size s: CGSize) -> some View {
        let c = CGPoint(x: (rig.earLeft.x + rig.earRight.x) / 2,
                        y: (rig.earLeft.y + rig.earRight.y) / 2)
        let r = max(0.06, hypot(rig.earLeft.x - rig.earRight.x,
                                rig.earLeft.y - rig.earRight.y) * 0.75)
        return layer(size: s, center: c, radius: r, softness: 0.7)
    }

    /// Both eyes, squashed vertically. `squash` is 1 open, 0 shut.
    private func eyeLayer(size s: CGSize, squash: Double) -> some View {
        ZStack {
            eye(size: s, at: rig.eyeLeft, squash: squash)
            eye(size: s, at: rig.eyeRight, squash: squash)
        }
    }

    private func eye(size s: CGSize, at p: CGPoint, squash: Double) -> some View {
        layer(size: s, center: p, radius: rig.eyeSize, softness: 0.8)
            .scaleEffect(x: 1, y: squash, anchor: UnitPoint(x: p.x, y: p.y))
    }

    /// One masked copy of the picture. The gradient stop positions are
    /// the whole trick: opaque in the middle, gone by the rim, so the
    /// moving copy melts into the still one underneath.
    private func layer(size s: CGSize, center: CGPoint, radius: CGFloat,
                       softness: Double) -> some View {
        Image(nsImage: image)
            .resizable().scaledToFill()
            .frame(width: s.width, height: s.height)
            .clipped()
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: max(0.05, 1 - softness)),
                        .init(color: .clear, location: 1),
                    ],
                    center: UnitPoint(x: center.x, y: center.y),
                    startRadius: 0,
                    endRadius: max(s.width, s.height) * radius
                )
            )
    }

    // MARK: Blinking

    /// Irregular on purpose: a blink every N seconds is a tell.
    private func schedule(_ now: Date) {
        if let start = blinkStart, now.timeIntervalSince(start) > 0.16 {
            blinkStart = nil
            nextBlink = now.addingTimeInterval(Double.random(in: 2.2...6.5))
        }
        if blinkStart == nil, now >= nextBlink {
            blinkStart = now
        }
    }

    /// 1 while open, dipping toward 0.15 at the middle of a blink.
    private func blinkAmount(at now: Date) -> Double? {
        guard let start = blinkStart else { return nil }
        let p = now.timeIntervalSince(start) / 0.16
        guard p >= 0, p <= 1 else { return nil }
        // Down and back up.
        return 1 - 0.85 * sin(p * .pi)
    }
}
