import SwiftUI

/// 5-bar audio level meter that animates smoothly with the live mic
/// `audioLevel` (0...1). Designed to slot into the input bar in
/// place of the static mic glyph while recording.
///
/// Each bar staggered by a small phase offset so even with constant
/// volume the meter pulses lightly — reads as "alive" rather than
/// "frozen at one height". Color modulates from secondary → red as
/// level rises (silence vs loud speech).
struct AudioLevelMeter: View {
    /// Live level 0...1 from VoiceRecorder.audioLevel
    let level: Double

    private let barCount = 5
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2
    private let maxHeight: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = CGFloat(i) * 0.18
                    let t = context.date.timeIntervalSinceReferenceDate
                    let wobble = (sin(t * 6 + phase) + 1) / 2 * 0.25
                    let height = max(2,
                        CGFloat(level) * maxHeight * (0.6 + wobble))
                    Capsule()
                        .fill(barColor(level))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: CGFloat(barCount) * (barWidth + barSpacing),
                   height: maxHeight)
        }
    }

    private func barColor(_ l: Double) -> Color {
        // Quiet → secondary (won't fight the dock chrome).
        // Mid     → green (matches accent + reads as "active").
        // Hot     → red ("you're peaking").
        if l < 0.15 { return .secondary }
        if l < 0.55 { return .green }
        return .red
    }
}
