import Foundation
import AppKit

/// Manages the local `kinclaw serve` subprocess so KinClaw Mac is
/// self-contained — the user doesn't have to run kinclaw separately.
///
/// Lifecycle (driven from AppDelegate):
///
///   applicationDidFinishLaunching  →  Task { await supervisor.start() }
///   applicationWillTerminate       →                supervisor.stop()
///
/// The supervisor first probes the configured port (default 5001).
/// If something is already serving — typically the user's manually-
/// started kinclaw — we adopt it and don't fight for the port.
/// Otherwise we locate the kinclaw binary (Resources/ → Homebrew →
/// /usr/local → ~/go/bin) and spawn it ourselves.
///
/// State is `@Published` so the M5 Settings UI can show health at a
/// glance. M4 keeps the recovery story minimal: one auto-restart on
/// crash, then surface the error. Smarter backoff comes later.
@MainActor
final class KinClawSupervisor: ObservableObject {

    /// Where kinclaw could be installed. First match wins.
    /// `Resources/` will get populated in M6 when we ship the
    /// embedded binary inside the .app bundle.
    private static let candidatePaths: [String] = {
        var paths = [String]()
        if let bundled = Bundle.main.url(forResource: "kinclaw", withExtension: nil) {
            paths.append(bundled.path)
        }
        paths.append("/opt/homebrew/bin/kinclaw")
        paths.append("/usr/local/bin/kinclaw")
        paths.append((NSHomeDirectory() as NSString).appendingPathComponent("go/bin/kinclaw"))
        return paths
    }()

    enum State: Equatable {
        case stopped
        case starting
        /// Subprocess we own — we'll kill it on app quit.
        case running(pid: Int32)
        /// Existing kinclaw was serving when we started; we adopted
        /// it. Don't kill on quit (user owns it).
        case adoptedExternal
        case notInstalled
        case crashed(message: String)
    }

    @Published private(set) var state: State = .stopped

    private let client: KinClawAPIClient
    private let port: Int
    private var process: Process?
    private var hasAttemptedRestart = false

    init(port: Int = 5001) {
        self.port = port
        self.client = KinClawAPIClient(
            baseURL: URL(string: "http://localhost:\(port)")!
        )
    }

    // MARK: - Public API

    /// Start (or adopt) a local kinclaw serve. No-op if already
    /// running. Logs go to stdout / stderr inherited from the .app.
    func start() async {
        guard state != .starting else { return }
        if case .running = state { return }
        if state == .adoptedExternal, await client.ping() { return }

        // 1. Adoption path — if someone is already serving on our
        //    port and answers /api/souls, that's a kinclaw and we
        //    use it. Saves the user from "port in use" headaches
        //    when they ran `kinclaw serve` themselves.
        if await client.ping() {
            state = .adoptedExternal
            print("[KinClawSupervisor] adopted external kinclaw on :\(port)")
            return
        }

        // 2. Locate the binary.
        guard let binaryPath = Self.findKinClawBinary() else {
            state = .notInstalled
            print("[KinClawSupervisor] kinclaw binary not found in:")
            for p in Self.candidatePaths { print("  - \(p)") }
            return
        }
        print("[KinClawSupervisor] using binary at \(binaryPath)")

        // 3. Spawn.
        state = .starting
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = [
            "serve",
            "-port", "\(port)",
            // -no-record: don't write JSONL session log; user can
            // opt into recording via Settings (M5+) if they want.
            "-no-record",
        ]
        // Pipe stdout / stderr through to ours so the dev sees
        // kinclaw's logs in Console / Terminal during development.
        p.standardOutput = FileHandle.standardOutput
        p.standardError = FileHandle.standardError
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleTermination(proc)
            }
        }

        do {
            try p.run()
            process = p
            print("[KinClawSupervisor] spawned kinclaw pid=\(p.processIdentifier) on :\(port)")
        } catch {
            state = .crashed(message: "spawn failed: \(error.localizedDescription)")
            return
        }

        // 4. Wait until /api/souls answers (server initialization
        //    can take a beat — soul loading + brain client warmup).
        let ready = await waitForReady(timeout: 15)
        if ready, let pid = process?.processIdentifier {
            state = .running(pid: pid)
        } else {
            // Started but never came up — kill it and surface error.
            stop()
            state = .crashed(message: "kinclaw failed to bind :\(port) within 15s")
        }
    }

    /// Stop the subprocess if we own it. No-op if we adopted an
    /// external kinclaw (don't kill someone else's daemon).
    func stop() {
        guard let p = process else {
            if state == .adoptedExternal {
                // Just forget about it; the external process keeps
                // running.
                state = .stopped
            }
            return
        }
        if p.isRunning {
            p.terminate()
            // SIGTERM should be enough; give it a beat to flush.
            // For a clean ".app quitting" path we don't aggressively
            // SIGKILL — kinclaw's own ctx-cancel shutdown is graceful.
        }
        process = nil
        state = .stopped
    }

    // MARK: - Internals

    /// Called when the spawned kinclaw exits (clean or otherwise).
    private func handleTermination(_ proc: Process) {
        let exitCode = proc.terminationStatus
        let reason = proc.terminationReason
        print("[KinClawSupervisor] kinclaw exited code=\(exitCode) reason=\(reason.rawValue)")

        // Distinguish "we asked it to stop" from "it crashed". When
        // we call stop() the terminationReason is .uncaughtSignal
        // (SIGTERM), but `process` has already been nil'd. So the
        // simplest tell: process == nil → we did it.
        guard process != nil else {
            // We initiated shutdown — already in .stopped state.
            return
        }

        process = nil

        if hasAttemptedRestart {
            state = .crashed(message: "kinclaw crashed twice in a row (exit \(exitCode))")
            return
        }
        hasAttemptedRestart = true
        print("[KinClawSupervisor] attempting one restart…")
        Task { @MainActor in
            // Reset the flag after a successful 30s run.
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self.hasAttemptedRestart = false
        }
        Task { @MainActor in
            await self.start()
        }
    }

    private func waitForReady(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await client.ping() { return true }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
    }

    /// First-match search through the candidate paths. The kinclaw
    /// binary needs to be executable, so we check the access bit
    /// rather than just existence.
    private static func findKinClawBinary() -> String? {
        let fm = FileManager.default
        for path in candidatePaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
