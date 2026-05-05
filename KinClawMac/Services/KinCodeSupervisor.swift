import Foundation
import AppKit

/// Manages the local `kincode -serve` subprocess so KinClaw Mac's
/// Code mode is self-contained — the user doesn't have to start
/// kincode separately.
///
/// Mirrors `KinClawSupervisor` (kinclaw on :5001) but for kincode on
/// :5002. Same lifecycle shape:
///
///   applicationDidFinishLaunching → Task { await kincode.start() }
///   applicationWillTerminate      →             kincode.stop()
///
/// Differences from KinClawSupervisor:
///
/// - Ready probe is `GET /api/health` (kincode shipped this in the
///   Stage 1 server). KinClawSupervisor pings `/api/souls` because
///   kinclaw is soul-driven; kincode has no souls so health is the
///   right liveness check.
/// - No `-soul` flag / no `souls/` directory — kincode is a plain
///   coding agent; the system prompt is built-in.
/// - No working-dir gymnastics needed — kincode reads no relative
///   paths at boot. The agent's repo cwd is set later via
///   `POST /api/repo` once the user picks one in Code mode.
/// - Optional via `UserDefaults("kinclaw.kincode.autostart")`. Default
///   true (eager spawn), so Code mode is one-click; power users with
///   slow drives or memory pressure can disable.
@MainActor
final class KinCodeSupervisor: ObservableObject {

    /// UserDefaults key — write false to skip the eager spawn.
    static let autostartKey = "kinclaw.kincode.autostart"

    /// Where kincode could be installed. First found wins.
    /// Resources/ branch will get populated when M6 ships an embedded
    /// binary (matches kinclaw's pattern); for now it's harmless to
    /// look there.
    private static var candidatePaths: [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []

        // 1. Embedded inside the .app (future)
        if let bundled = Bundle.main.url(forResource: "kincode",
                                          withExtension: nil) {
            paths.append(bundled.path)
        }

        // 2. Local dev repo — most common case for KinClaw devs
        paths.append("\(home)/Documents/Workspace/kincode/kincode")

        // 3. Homebrew (Apple Silicon)
        paths.append("/opt/homebrew/bin/kincode")

        // 4. Homebrew (Intel) / manual install
        paths.append("/usr/local/bin/kincode")

        // 5. `go install`
        paths.append("\(home)/go/bin/kincode")

        return paths
    }

    enum State: Equatable {
        case stopped
        case disabled            // user opted out via Settings
        case starting
        case running(pid: Int32)
        case adoptedExternal     // someone was already serving on :5002
        case notInstalled
        case crashed(message: String)
    }

    @Published private(set) var state: State = .stopped

    private let port: Int
    private var process: DisclaimedProcess?
    private var hasAttemptedRestart = false

    init(port: Int = 5002) {
        self.port = port
    }

    /// Convenience for the UI: reads the autostart pref. Returns true
    /// when the pref is unset (eager-spawn default).
    static var autostartEnabled: Bool {
        // UserDefaults.bool returns false for missing keys; we want
        // missing-key to mean "yes, default on", so we read the
        // object explicitly and treat nil as true.
        if let v = UserDefaults.standard.object(forKey: autostartKey) as? Bool {
            return v
        }
        return true
    }

    // MARK: - Public API

    /// Start (or adopt) a local kincode -serve. No-op if disabled
    /// via Settings, or if already running.
    func start() async {
        guard Self.autostartEnabled else {
            state = .disabled
            print("[KinCodeSupervisor] autostart disabled by user pref")
            return
        }
        guard state != .starting else { return }
        if case .running = state { return }
        if state == .adoptedExternal, await ping() { return }

        // 1. Adoption — if someone is already serving on :5002 and
        //    answers /api/health, that's a kincode (or close enough)
        //    and we use it.
        if await ping() {
            state = .adoptedExternal
            print("[KinCodeSupervisor] adopted external kincode on :\(port)")
            return
        }

        // 2. Locate binary.
        guard let binary = Self.findBinary() else {
            state = .notInstalled
            print("[KinCodeSupervisor] kincode binary not found.")
            return
        }
        print("[KinCodeSupervisor] binary: \(binary)")

        // 3. Spawn — DisclaimedProcess so the kincode subprocess
        // owns its own TCC identity (same disclaim trick as
        // KinClawSupervisor). kincode itself doesn't currently use
        // AX/screen-recording APIs, but going through the same code
        // path keeps both supervisors symmetric and future-proofs
        // for any kincode tool that DOES need OS permissions later
        // (e.g. an MCP server it spawns).
        state = .starting
        var args = [
            "-serve",
            "-port", "\(port)",
        ]
        if let soulPath = Self.defaultSoulPath() {
            args.append(contentsOf: ["-soul", soulPath])
            print("[KinCodeSupervisor] soul: \(soulPath)")
        } else {
            print("[KinCodeSupervisor] no soul found — kincode will use built-in default prompt")
        }

        do {
            let p = try DisclaimedProcess.spawn(
                executablePath: binary,
                arguments: args,
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: nil
            )
            p.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.handleTermination(proc)
                }
            }
            process = p
            print("[KinCodeSupervisor] spawned kincode pid=\(p.processIdentifier) on :\(port) (TCC disclaimed)")
        } catch {
            state = .crashed(message: "spawn failed: \(error.localizedDescription)")
            return
        }

        // 4. Wait for /api/health.
        let ready = await waitForReady(timeout: 10)
        if ready, let pid = process?.processIdentifier {
            state = .running(pid: pid)
        } else {
            stop()
            state = .crashed(message: "kincode failed to bind :\(port) within 10s")
        }
    }

    /// Stop the subprocess if we own it. No-op for adopted externals.
    func stop() {
        guard let p = process else {
            if state == .adoptedExternal {
                state = .stopped
            }
            return
        }
        if p.isRunning {
            p.terminate()
        }
        process = nil
        state = .stopped
    }

    // MARK: - Internals

    private func handleTermination(_ proc: DisclaimedProcess) {
        let exitCode = proc.terminationStatus
        let reason = proc.terminationReason
        print("[KinCodeSupervisor] kincode exited code=\(exitCode) reason=\(reason.rawValue)")

        // We initiated shutdown if process is already nil.
        guard process != nil else { return }
        process = nil

        if hasAttemptedRestart {
            state = .crashed(message: "kincode crashed twice in a row (exit \(exitCode))")
            return
        }
        hasAttemptedRestart = true
        print("[KinCodeSupervisor] attempting one restart…")
        Task { @MainActor in
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
            if await ping() { return true }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
    }

    /// Hit `/api/health` and treat any 2xx as alive. Doesn't validate
    /// the response body — kincode's health is intentionally trivial,
    /// we just want a liveness signal.
    private func ping() async -> Bool {
        guard let url = URL(string: "http://localhost:\(port)/api/health") else {
            return false
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                return true
            }
        } catch {
            // Connection refused / timeout — server isn't up. Normal
            // during the boot window.
        }
        return false
    }

    private static func findBinary() -> String? {
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Locate the canonical kincode soul (`coder.soul.md`). Mirrors
    /// the binary-search order — first found wins. Returns nil if no
    /// soul is reachable, in which case kincode uses its built-in
    /// defaultSystemPrompt and the auto-fallback ollama brain.
    ///
    /// The soul is the source of truth for kincode's persona AND its
    /// default brain (provider=ollama, model=kimi-k2.5:cloud). Without
    /// it kincode boots with a bare prompt and hardcoded fallback —
    /// works, but loses the "rules" that make replies tight.
    private static func defaultSoulPath() -> String? {
        let home = NSHomeDirectory()
        let candidates: [String] = [
            // 1. Embedded inside the .app bundle (M6 will populate)
            Bundle.main.url(forResource: "coder", withExtension: "soul.md")?.path,
            // 2. Local dev repo — most common during development
            "\(home)/Documents/Workspace/kincode/souls/coder.soul.md",
            // 3. Homebrew (Apple Silicon)
            "/opt/homebrew/share/kincode/souls/coder.soul.md",
            // 4. Homebrew (Intel) / manual install
            "/usr/local/share/kincode/souls/coder.soul.md",
            // 5. User-level (~/.kincode/souls/) — for hand-installed
            //    or hand-customized copies
            "\(home)/.kincode/souls/coder.soul.md",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}
