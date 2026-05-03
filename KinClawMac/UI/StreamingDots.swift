import SwiftUI

/// Three-dot streaming indicator that pulses sequentially. Replaces
/// the stock `ProgressView` spinner during streaming — feels more
/// "designed", reads as "agent thinking" rather than "loading".
///
/// Driven by TimelineView at 30Hz so it animates without a standing
/// Timer and doesn't trigger broader view re-renders.
struct StreamingDots: View {
    var color: Color = .secondary
    var size: CGFloat = 5
    var spacing: CGFloat = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = CGFloat(i) * 0.5
                    let t = context.date.timeIntervalSinceReferenceDate
                    let wave = (sin(t * 4 - phase) + 1) / 2
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .opacity(0.3 + Double(wave) * 0.7)
                        .scaleEffect(0.85 + wave * 0.25)
                }
            }
        }
    }
}
