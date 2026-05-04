import SwiftUI

/// Renders the kinclaw "agent's eyes" feed — a rolling JPEG capture
/// of the user's screen with a small label saying which app the
/// kernel thinks it's tracking.
///
/// Driven by ScreenFeedClient; this view is purely presentational.
/// Lifecycle: client starts when this view appears and stops when
/// it goes away. Pushing the lifecycle down here means parent views
/// (CoworkPane, debug panels later) don't have to remember to
/// start/stop the polling.
struct ScreenFeedView: View {

    @StateObject private var client: ScreenFeedClient

    init(port: Int = 5001) {
        // StateObject must be initialized once per host view; we
        // use the port to construct the client up front.
        _client = StateObject(wrappedValue: ScreenFeedClient(port: port))
    }

    var body: some View {
        // Image fills the available frame, aspect-fit so the user
        // always sees the full captured rect (letterbox top/bottom
        // when the panel is wider than 16:9). No overlay label —
        // the screen frame itself is sufficient signal that we're
        // showing the desktop; the red "🔴 LIVE · App" tag was noise
        // borrowed from video-conferencing UI conventions and didn't
        // earn its space in a desktop chat panel.
        Group {
            if let img = client.image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(height: 220)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .onAppear { client.start() }
        .onDisappear { client.stop() }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let err = client.lastError, !client.hasFirstFrame {
            VStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.secondary)
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Connecting to kinclaw…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
