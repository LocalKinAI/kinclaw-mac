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
        ZStack(alignment: .topLeading) {
            // Image fills the available frame, aspect-fit so the user
            // always sees the full captured rect (letterbox top/bottom
            // when the panel is wider than 16:9).
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

            // Label overlay — top-left, "🔴 LIVE · App". Mirrors the
            // browser UI that ships with kinclaw so users coming from
            // the web client recognize it.
            label
        }
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

    private var label: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red.opacity(client.hasFirstFrame ? 0.85 : 0.3))
                .frame(width: 6, height: 6)
            Text(labelText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .padding(8)
    }

    private var labelText: String {
        let app = client.trackedApp
        if app.isEmpty {
            return client.hasFirstFrame ? "LIVE" : "Connecting"
        }
        return "LIVE · \(app)"
    }
}
