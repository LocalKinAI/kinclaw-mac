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

    /// Where kinclaw could be installed, plus the matching working
    /// directory and souls/ location for each. First found wins.
    /// `Resources/` will get populated in M6 when we ship the
    /// embedded binary inside the .app bundle.
    struct KinClawInstall {
        let binary: String
        let workingDir: String?    // for relative `souls/...` paths
        let soulsDir: String?
    }

    private static var candidates: [KinClawInstall] {
        let home = NSHomeDirectory()
        var c = [KinClawInstall]()

        // 1. Embedded inside the .app (M6 will populate after codesign).
        if let bundled = Bundle.main.url(forResource: "kinclaw",
                                          withExtension: nil) {
            c.append(.init(
                binary: bundled.path,
                workingDir: bundled.deletingLastPathComponent().path,
                soulsDir: bundled.deletingLastPathComponent()
                    .appendingPathComponent("souls").path))
        }

        // 2. ~/.localkin/bin/kinclaw — STABLE INSTALLED BINARY.
        // The dev's `scripts/install.sh` copies the freshly-built
        // kinclaw here and ad-hoc-codesigns it with a stable
        // identifier. macOS TCC re-prompts on every cdhash change for
        // unsigned binaries; the installed-and-signed copy at this
        // path keeps the signed identifier stable across rebuilds, so
        // re-auth pain drops dramatically. The dev path below is
        // kept as a fallback for users without an installed copy yet.
        //
        // Souls path: prefer ~/.localkin/souls/ (LocalKin family
        // shared dir per kinclaw v1.10.0 storage cleanup), fall back
        // to the dev repo's souls/ if the family dir is empty.
        let installedBin = "\(home)/.localkin/bin/kinclaw"
        if FileManager.default.isExecutableFile(atPath: installedBin) {
            // Soul lookup is opinionated: we want pilot.soul.md
            // specifically (KinClaw Mac's marquee soul). install.sh
            // copies the kinclaw-repo souls into ~/.localkin/souls/
            // so post-install the family dir wins. Pre-install (or
            // if user nuked the family dir), fall back to the dev
            // repo's souls/ directly.
            let familySouls = "\(home)/.localkin/souls"
            let devSouls = "\(home)/Documents/Workspace/kinclaw/souls"
            var souls: String? = nil
            if FileManager.default.fileExists(atPath: "\(familySouls)/pilot.soul.md") {
                souls = familySouls
            } else if FileManager.default.fileExists(atPath: "\(devSouls)/pilot.soul.md") {
                souls = devSouls
            } else if FileManager.default.fileExists(atPath: familySouls) {
                souls = familySouls  // last-resort: any souls dir is better than none
            }
            c.append(.init(
                binary: installedBin,
                workingDir: nil,
                soulsDir: souls))
        }

        // 3. Local dev repo — fallback for devs who haven't run
        //    install.sh yet. Re-authorizes on every rebuild; that's
        //    why install.sh exists.
        let devRepo = "\(home)/Documents/Workspace/kinclaw"
        if FileManager.default.isExecutableFile(atPath: "\(devRepo)/kinclaw") {
            c.append(.init(
                binary: "\(devRepo)/kinclaw",
                workingDir: devRepo,
                soulsDir: "\(devRepo)/souls"))
        }

        // 4. Homebrew (Apple Silicon)
        if FileManager.default.isExecutableFile(
            atPath: "/opt/homebrew/bin/kinclaw") {
            c.append(.init(
                binary: "/opt/homebrew/bin/kinclaw",
                workingDir: nil,
                soulsDir: "/opt/homebrew/share/kinclaw/souls"))
        }

        // 5. Homebrew (Intel) / manual install
        if FileManager.default.isExecutableFile(
            atPath: "/usr/local/bin/kinclaw") {
            c.append(.init(
                binary: "/usr/local/bin/kinclaw",
                workingDir: nil,
                soulsDir: "/usr/local/share/kinclaw/souls"))
        }

        // 6. `go install` — requires souls to exist somewhere else
        let goBin = "\(home)/go/bin/kinclaw"
        if FileManager.default.isExecutableFile(atPath: goBin) {
            c.append(.init(
                binary: goBin,
                workingDir: nil,
                soulsDir: "\(home)/.localkin/souls"))
        }

        return c
    }

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
    private var process: DisclaimedProcess?
    /// Crash count for backoff calculation. Reset to 0 once the
    /// supervisor confirms the spawn is healthy (state moves to
    /// .running with /api/souls answering). A short transient
    /// outage racks up 1-2; a chronic problem (missing AX,
    /// permanent port conflict) keeps growing until it caps at 30s
    /// retry intervals.
    private var consecutiveCrashes: Int = 0

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
        //
        // Race hazard: the existing kinclaw might be a dying orphan
        // from a previous KinClawMac (e.g. left by sign-app.sh's
        // smoke test). It answers /api/souls now but exits ~1s later
        // when its orphan-watch ticks. To avoid getting stuck in
        // .adoptedExternal pointing at a corpse, ping again after a
        // short delay; only adopt if it's still alive on the second
        // check. If the second ping fails, fall through to spawning
        // our own.
        if await client.ping() {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            if await client.ping() {
                state = .adoptedExternal
                print("[KinClawSupervisor] adopted external kinclaw on :\(port)")
                startAdoptionWatchdog()
                return
            }
            print("[KinClawSupervisor] external kinclaw vanished after first ping (probably a dying orphan); spawning our own")
        }

        // 2. Locate a kinclaw install (binary + matching souls dir).
        guard let install = Self.findInstall() else {
            state = .notInstalled
            print("[KinClawSupervisor] kinclaw binary not found.")
            return
        }
        print("[KinClawSupervisor] install: \(install.binary)")
        if let wd = install.workingDir {
            print("[KinClawSupervisor] working dir: \(wd)")
        }
        if let sd = install.soulsDir {
            print("[KinClawSupervisor] souls dir: \(sd)")
        }

        // 3. Spawn — DisclaimedProcess instead of Foundation.Process.
        // The disclaim is critical: without it, TCC attributes
        // kinclaw's AX/Screen-Recording/Automation calls back to
        // KinClawMac.app's bundle id (which has no permissions),
        // making the 5 claws unusable. With disclaim, kinclaw is
        // its own TCC identity — same identity as when the user
        // runs kinclaw from Terminal, so the existing user grant
        // applies. Same problem Slack / Tailscale / Karabiner
        // helper apps solve via the same SPI.
        state = .starting

        var args = [
            "serve",
            "-port", "\(port)",
            // -no-record: don't write JSONL session log; user can
            // opt into recording via Settings (M5+) if they want.
            "-no-record",
        ]
        // -soul: pick the default Pilot soul if we can find one.
        // Looks in the install's souls/ dir first, then ~/.localkin/
        // souls/ as a user-level fallback.
        if let soulPath = Self.defaultSoulPath(install: install) {
            args.append(contentsOf: ["-soul", soulPath])
            print("[KinClawSupervisor] soul: \(soulPath)")
        }

        // Inherit env, then layer our defaults. SEARXNG_ENDPOINT is
        // the big one — when running .app via Launch Services,
        // shell-set env vars don't propagate, so users were having
        // to start kinclaw serve manually with the env to get
        // web_search working through SearXNG.
        var env = ProcessInfo.processInfo.environment
        if env["SEARXNG_ENDPOINT"] == nil {
            // Container at :8080 is the conventional default; if it's
            // not running, kinclaw's web_search falls back to DDG.
            env["SEARXNG_ENDPOINT"] = "http://localhost:8080"
        }

        do {
            let p = try DisclaimedProcess.spawn(
                executablePath: install.binary,
                arguments: args,
                environment: env,
                currentDirectory: install.workingDir
            )
            p.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.handleTermination(proc)
                }
            }
            process = p
            print("[KinClawSupervisor] spawned kinclaw pid=\(p.processIdentifier) on :\(port) (TCC disclaimed)")
        } catch {
            state = .crashed(message: "spawn failed: \(error.localizedDescription)")
            return
        }

        // 4. Wait until /api/souls answers (server initialization
        //    can take a beat — soul loading + brain client warmup).
        let ready = await waitForReady(timeout: 15)
        if ready, let pid = process?.processIdentifier {
            state = .running(pid: pid)
            // Spawn is healthy. Reset crash counter so the next
            // unrelated crash (hours later) starts at 1s backoff,
            // not the cap. Without this, a long-running session that
            // had transient failures early would keep hitting the
            // 30s ceiling on later (unrelated) crashes.
            consecutiveCrashes = 0
        } else {
            // Started but never came up. Kill our process (which
            // bypasses handleTermination's retry path because stop()
            // nils out `process`), then schedule our own backoff
            // retry — keeps the failure case on the same recovery
            // ladder as a runtime crash.
            stop()
            consecutiveCrashes += 1
            let delays: [UInt64] = [1, 2, 4, 8, 16, 30]
            let idx = min(consecutiveCrashes - 1, delays.count - 1)
            let delaySec = delays[idx]
            state = .crashed(message: "kinclaw failed to bind :\(port) within 15s; retry in \(delaySec)s")
            print("[KinClawSupervisor] bind timeout, retrying in \(delaySec)s (attempt #\(consecutiveCrashes))")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
                if case .stopped = state { return }
                if case .running = state { return }
                await self.start()
            }
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

    /// Watchdog for .adoptedExternal state. Pings /api/souls every
    /// 5s; if it stops answering, transition state out of .adopted
    /// and call start() to spawn our own kinclaw. Without this, an
    /// adopted external that quietly dies (e.g. user kills their
    /// `kinclaw serve` from another terminal) leaves the supervisor
    /// stuck pointing at a dead port — the symptom Jacky hit after
    /// every `make run`.
    private func startAdoptionWatchdog() {
        Task { @MainActor in
            while case .adoptedExternal = state {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .adoptedExternal = state {
                    if !(await client.ping()) {
                        print("[KinClawSupervisor] adopted external died; respawning our own")
                        state = .stopped  // clear adoption so start() proceeds to spawn
                        await start()
                        return  // start() either succeeded (now .running) or failed (now .crashed); either way watchdog's job is done
                    }
                } else {
                    // State changed out from under us (e.g. user
                    // called stop()), exit watchdog.
                    return
                }
            }
        }
    }

    /// Called when the spawned kinclaw exits (clean or otherwise).
    ///
    /// Strategy: never give up permanently — instead, exponentially
    /// back off restart attempts. The previous "two crashes = .crashed
    /// forever" rule left users in stuck states where the only way
    /// out was relaunching the whole app. Now the supervisor keeps
    /// trying every 1s → 2s → 4s → 8s → 16s → 30s (capped), so
    /// transient failures (port briefly busy, soul file race, AX
    /// dialog blocking startup) self-heal once the underlying issue
    /// clears.
    private func handleTermination(_ proc: DisclaimedProcess) {
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
        consecutiveCrashes += 1

        // Backoff schedule (seconds): 1, 2, 4, 8, 16, 30 (cap).
        // Past the cap we keep trying every 30s indefinitely so a
        // recovered upstream (e.g. user finally clicked Allow on the
        // AX prompt, or freed up :5001) gets picked up automatically.
        let delays: [UInt64] = [1, 2, 4, 8, 16, 30]
        let idx = min(consecutiveCrashes - 1, delays.count - 1)
        let delaySec = delays[idx]

        state = .crashed(message: "kinclaw exited (code \(exitCode)); retry in \(delaySec)s (attempt \(consecutiveCrashes))")
        print("[KinClawSupervisor] retrying in \(delaySec)s (attempt #\(consecutiveCrashes))")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
            // Bail if user manually stopped, or someone else already
            // got us running (e.g. external kinclaw bound :5001).
            if case .stopped = state { return }
            if case .running = state { return }
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

    /// First-match search through known install layouts. Each
    /// candidate carries its expected workingDir + souls dir so the
    /// spawned subprocess gets the right context.
    private static func findInstall() -> KinClawInstall? {
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c.binary) {
                return c
            }
        }
        return nil
    }

    /// Resolve a sensible default `-soul` path for the given install.
    /// Looks for Pilot first (the dock's marquee soul), then any
    /// soul in the install's souls/ dir, then user-level
    /// ~/.localkin/souls/. nil means "let kinclaw use its built-in
    /// default", which is also fine.
    private static func defaultSoulPath(install: KinClawInstall) -> String? {
        let fm = FileManager.default
        let userSouls = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".localkin/souls")
        let dirs = [install.soulsDir, userSouls].compactMap { $0 }
        for dir in dirs {
            let pilot = "\(dir)/pilot.soul.md"
            if fm.fileExists(atPath: pilot) { return pilot }
        }
        return nil
    }
}
