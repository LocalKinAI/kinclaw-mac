import Foundation
import AppKit

/// Polling client for kinclaw's "agent's eyes" feed. The kinclaw
/// kernel exposes:
///
///   GET /api/screen/current.jpg  → JPEG capture of the user's screen
///                                  (cached 800ms server-side)
///   GET /api/screen/info         → {"tracked_app":"Reminders"} label
///
/// Cowork mode renders both inline above the message stream so the
/// user and the agent are looking at the same desktop frame as the
/// conversation unfolds.
///
/// Polling cadence: 1.5s for the image, 5s for the label. The server
/// already absorbs faster polls via its 800ms cache so this is the
/// effective floor for fresh frames; faster polling just wastes work
/// on both sides.
@MainActor
final class ScreenFeedClient: ObservableObject {

    /// Most recent capture, ready to draw via `Image(nsImage:)`.
    /// nil during the first poll or when the feed isn't reachable.
    @Published private(set) var image: NSImage?

    /// True after at least one successful image fetch. Lets the UI
    /// show a "connecting…" placeholder until the first frame lands
    /// instead of a misleading "feed offline" message during boot.
    @Published private(set) var hasFirstFrame: Bool = false

    /// Set when the most recent fetch failed. Cleared on next success.
    /// Surface in the UI as a small banner ("📷 feed offline — kinclaw
    /// not running?") so the user knows the agent isn't currently
    /// seeing anything.
    @Published private(set) var lastError: String?

    private let baseURL: URL
    private var imageTask: Task<Void, Never>?

    init(port: Int = 5001) {
        self.baseURL = URL(string: "http://localhost:\(port)")!
    }

    /// Start polling. Idempotent — calling twice doesn't double the
    /// load, the second call observes existing tasks and returns.
    func start() {
        if imageTask != nil { return }
        imageTask = Task { [weak self] in
            await self?.imageLoop()
        }
    }

    /// Stop polling. Called when the user leaves Cowork mode (back
    /// to Chat / Code) so we're not pinging kinclaw for screencaps
    /// the user can't see.
    func stop() {
        imageTask?.cancel()
        imageTask = nil
    }

    deinit {
        // Task captures self weakly so deinit doesn't hang on it —
        // it observes the cancellation flag set by .cancel().
        imageTask?.cancel()
    }

    // MARK: - Polling loops

    private func imageLoop() async {
        while !Task.isCancelled {
            await fetchOnce()
            // Server caches 800ms; 1.5s leaves headroom for actual
            // capture variance + network round trip.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func fetchOnce() async {
        // Cache-buster: server sets no-store but we add ?t= as
        // belt-and-suspenders against any intermediate proxy.
        let url = baseURL
            .appendingPathComponent("/api/screen/current.jpg")
            .appending(queryItems: [URLQueryItem(
                name: "t",
                value: "\(Int(Date().timeIntervalSince1970 * 1000))"
            )])
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let nsimg = NSImage(data: data) {
                image = nsimg
                hasFirstFrame = true
                lastError = nil
            } else if let http = response as? HTTPURLResponse,
                      http.statusCode == 501 {
                lastError = "screen claw not wired (macOS only)"
            } else {
                lastError = "feed unreachable"
            }
        } catch {
            // .cancelled is normal when stop() fires mid-fetch — don't
            // log it as a user-visible error.
            if (error as NSError).code != NSURLErrorCancelled {
                lastError = "feed offline"
            }
        }
    }

}

// URL.appending(queryItems:) is iOS 16+ / macOS 13+. Mac is on 14+
// per project.yml so this is fine, no compat shim needed.
