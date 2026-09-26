import AppKit
import Foundation
import WebKit

/// OpenMontage on the box, as a tab.
///
/// OpenMontage (github.com/calesthio/OpenMontage) is a video studio that a
/// coding agent drives: it writes the brief and the script, makes the
/// pictures, clips, narration and music with its tools, and cuts the film with
/// Remotion. It lives on the box at ~/OpenMontage, beside its Python, ffmpeg
/// and Remotion, and three tools of ours plug it into the box's own ComfyUI —
/// Qwen-Image 2.1, MiniMax H3, MiniMax Music 3 (scripts/openmontage). Installed
/// and tested, it was still invisible: nothing on this Mac said it was there,
/// and "ssh in and start an agent" is not a way anybody makes a film. So:
///
///   - the Studio's one agent (`StudioAgent`), standing on the left of this
///     tab as of every Studio tab: it runs on the Mac and works OpenMontage
///     on the box through a bridge over ssh, asked for a film in a sentence
///     and stopping in its terminal for the approvals OpenMontage insists on;
///   - Backlot, OpenMontage's own board — this: the production as it happens,
///     stages, script, scene cards, takes, renders. It is served on the box at
///     127.0.0.1:4750 only, and reaches this Mac through an ssh tunnel to the
///     same port here.
@MainActor
final class MontageStudio: ObservableObject {
    static let shared = MontageStudio()

    static let port = 4750

    enum Board: Equatable { case idle, starting, up, down(String) }
    @Published private(set) var board: Board = .idle
    /// The production the board should show: the project the agent is
    /// working in, once there is one. nil is the library of all of them.
    @Published private(set) var project: String?

    private var tunnel: Process?
    private var watcher: Task<Void, Never>?

    /// The board's web view, for back, home and reload above it; and whether
    /// there is a page to go back to.
    weak var web: WKWebView?
    @Published var canGoBack = false

    static var boardURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    // MARK: The board

    /// The server on the box if it is not up, then the tunnel to it.
    func openBoard() async {
        if case .starting = board { return }
        if await answering() { board = .up; return }
        guard !BoxServices.ssh.isEmpty else { board = .down("先在 设置 → Backend 里填盒子的 SSH（user@地址）"); return }
        board = .starting
        let (code, out) = await BoxServices.run("""
            cd ~/OpenMontage 2>/dev/null || { echo NO-OPENMONTAGE; exit 3; }
            curl -sf -m 2 http://127.0.0.1:\(Self.port)/api/health >/dev/null && { echo UP; exit 0; }
            mkdir -p ~/Library/Logs/kinclaw
            nohup .venv/bin/python -m backlot serve --port \(Self.port) >> ~/Library/Logs/kinclaw/backlot.log 2>&1 < /dev/null &
            for i in $(seq 1 40); do
              sleep 0.5
              curl -sf -m 1 http://127.0.0.1:\(Self.port)/api/health >/dev/null && { echo UP; exit 0; }
            done
            echo SLOW; exit 4
            """)
        guard code == 0, out.contains("UP") else {
            board = .down(out.contains("NO-OPENMONTAGE") ? "盒子上没有 ~/OpenMontage"
                          : "盒子上的看板没起来（~/Library/Logs/kinclaw/backlot.log）：\(out.suffix(160))")
            return
        }
        startTunnel()
        for _ in 0..<24 {
            if await answering() { board = .up; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        board = .down("连不上盒子上的看板：ssh 隧道没通到 \(Self.port) 端口")
    }

    /// Whether the board answers here, through whatever tunnel there is — one
    /// left from an earlier launch of the app does the job as well as a new one.
    private func answering() async -> Bool {
        var request = URLRequest(url: Self.boardURL.appendingPathComponent("api/health"))
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func startTunnel() {
        if let tunnel, tunnel.isRunning { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-N", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                             "-o", "ServerAliveInterval=30", "-o", "ConnectTimeout=6",
                             "-L", "127.0.0.1:\(Self.port):127.0.0.1:\(Self.port)", BoxServices.ssh]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tunnel = nil
                if self.board == .up { self.board = .down("到盒子的隧道断了") }
            }
        }
        do { try process.run(); tunnel = process } catch {
            board = .down("ssh 起不来：\(error.localizedDescription)")
        }
    }

    /// When the app quits: the agent and the tunnel go with it.
    func shutdown() {
        unfollow()
        tunnel?.terminate()
        tunnel = nil
    }

    // MARK: Following the agent's project

    /// While the agent runs: the newest project under projects/ that has
    /// changed since it started is the one it is working in, and the board
    /// follows it.
    func follow() {
        watcher?.cancel()
        project = nil
        let since = Int(Date().timeIntervalSince1970) - 5
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                let (code, out) = await BoxServices.run(
                    "cd ~/OpenMontage/projects 2>/dev/null && for d in $(ls -t); do [ -f \"$d/project.json\" ] && [ $(stat -f %m \"$d\") -ge \(since) ] && { echo \"$d\"; break; }; done")
                let name = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard code == 0, !name.isEmpty, !name.contains("/"), !name.contains(" ") else { continue }
                await MainActor.run {
                    guard let self, self.project != name else { return }
                    self.project = name
                }
            }
        }
    }

    func unfollow() {
        watcher?.cancel()
        watcher = nil
    }

    // MARK: For the panel's tools

    var report: String {
        let boardLine: String
        switch board {
        case .idle: boardLine = "看板：还没打开"
        case .starting: boardLine = "看板：在起"
        case .up: boardLine = "看板：\(Self.boardURL.absoluteString)" + (project.map { "p/\($0)（跟着 agent 的项目）" } ?? "（全部项目）")
        case .down(let why): boardLine = "看板：打不开 —— \(why)"
        }
        return boardLine + "\n" + StudioAgent.montage.report
    }
}
