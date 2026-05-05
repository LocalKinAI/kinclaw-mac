import Foundation
import Darwin

/// macOS private SPI: marks a posix_spawn'd subprocess as
/// "responsible for itself" in the TCC permission chain. By default
/// when an .app spawns a subprocess, the .app is the "responsible
/// party" and TCC checks attribute back to the .app's bundle id.
/// Calling this with disclaim=1 flips that — the subprocess takes
/// on its own TCC identity.
///
/// Why we need this: KinClaw Mac spawns kinclaw + kincode as
/// subprocesses. Without disclaim, when kinclaw asks the kernel
/// "can I do AX queries?", macOS asks "who's responsible for the
/// kinclaw process?" → "KinClawMac.app" → "does KinClawMac.app have
/// AX permission?" → "no" → denied. Even though the user granted
/// kinclaw itself accessibility (e.g. from a previous Terminal
/// run), it doesn't help because TCC isn't asking about kinclaw.
///
/// With disclaim, kinclaw is its own responsible party. TCC asks
/// "does kinclaw have AX permission?" → "yes (granted via Terminal
/// run)" → allowed. CLI users and Mac-app users converge on the
/// same TCC identity for the same binary.
///
/// This SPI is declared in <sys/spawn_internal.h>, used by Apple
/// itself in launchd / helper-app patterns. Not App Store safe but
/// fine for OSS distribution.
@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(
    _ attrs: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ disclaim: Int32
) -> Int32

/// Foundation.Process replacement that uses posix_spawn directly
/// so we can disclaim TCC responsibility on the child. Keeps the
/// Process-shaped surface (terminate, isRunning, terminationHandler,
/// processIdentifier) so callers don't have to learn a new API.
///
/// What we DON'T support that Process does (and our supervisors
/// don't use): standardInput piping, Pipe-based stdout/stderr
/// capture (we just inherit the parent's fds), waitUntilExit
/// blocking call. None of that is needed for the supervisor's
/// "fire-and-forget with terminationHandler" pattern.
final class DisclaimedProcess {

    private(set) var processIdentifier: pid_t = 0
    private(set) var terminationStatus: Int32 = 0
    private(set) var terminationReason: Process.TerminationReason = .exit
    var terminationHandler: ((DisclaimedProcess) -> Void)?

    private var didTerminate: Bool = false
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        if didTerminate { return false }
        // kill(pid, 0) returns 0 if process exists, -1 with ESRCH otherwise.
        return kill(processIdentifier, 0) == 0
    }

    /// Spawn the executable with disclaimed TCC responsibility.
    /// Inherits the parent's stdout/stderr (so kinclaw's logs show
    /// up in our log stream alongside ours).
    static func spawn(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) throws -> DisclaimedProcess {

        // Initialize spawn attrs.
        var attrs: posix_spawnattr_t?
        guard posix_spawnattr_init(&attrs) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "posix_spawnattr_init failed"])
        }
        defer { posix_spawnattr_destroy(&attrs) }

        // The point of this whole class: tell TCC the child is its
        // own responsible party. Best-effort — if the SPI fails
        // (unsupported macOS, sandbox restriction), we still spawn,
        // just without disclaim.
        let disclaimResult = responsibility_spawnattrs_setdisclaim(&attrs, 1)
        if disclaimResult != 0 {
            print("[DisclaimedProcess] disclaim failed (\(disclaimResult)), spawning normally")
        }

        // Build argv (C-strings, NULL-terminated).
        let argvStrings = ([executablePath] + arguments).map { strdup($0) }
        defer { argvStrings.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = argvStrings + [nil]

        // Build envp.
        let envDict = environment ?? ProcessInfo.processInfo.environment
        let envStrings = envDict.map { strdup("\($0.key)=\($0.value)") }
        defer { envStrings.forEach { free($0) } }
        var envp: [UnsafeMutablePointer<CChar>?] = envStrings + [nil]

        // Optional chdir before spawn. We change the parent's cwd,
        // which posix_spawn inherits, then restore. Same approach
        // Foundation.Process uses internally.
        let savedCwd = getcwd(nil, 0)
        if let cwd = currentDirectory {
            chdir(cwd)
        }
        defer {
            if let savedCwd = savedCwd {
                chdir(savedCwd)
                free(savedCwd)
            }
        }

        var pid: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { argvBuf in
            envp.withUnsafeMutableBufferPointer { envpBuf in
                posix_spawn(&pid, executablePath, nil, &attrs,
                            argvBuf.baseAddress, envpBuf.baseAddress)
            }
        }

        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey:
                                     "posix_spawn \(executablePath) failed: \(String(cString: strerror(result)))"])
        }

        let proc = DisclaimedProcess()
        proc.processIdentifier = pid
        proc.startReaper()
        return proc
    }

    /// Background thread that waitpid()s on the child and fires the
    /// terminationHandler on the main queue when it exits. Mirrors
    /// the way Foundation.Process delivers terminationHandler.
    private func startReaper() {
        let pid = self.processIdentifier
        DispatchQueue.global(qos: .background).async { [weak self] in
            var status: Int32 = 0
            let result = waitpid(pid, &status, 0)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.lock.lock()
                self.didTerminate = true
                if result == pid {
                    if (status & 0x7f) == 0 {
                        // Normal exit — high byte holds exit code.
                        self.terminationStatus = (status >> 8) & 0xff
                        self.terminationReason = .exit
                    } else {
                        // Killed by signal.
                        self.terminationStatus = status & 0x7f
                        self.terminationReason = .uncaughtSignal
                    }
                }
                self.lock.unlock()
                self.terminationHandler?(self)
            }
        }
    }

    /// Send SIGTERM. Same shape as Process.terminate(). The child's
    /// reaper will fire the terminationHandler once it actually
    /// exits.
    func terminate() {
        kill(processIdentifier, SIGTERM)
    }
}
