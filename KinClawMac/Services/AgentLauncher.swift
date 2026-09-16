import Darwin
import Foundation

/// Opens a third-party agent in a terminal, pointed at the Ollama the
/// model menu is currently using — the trick `ollama launch` plays, with
/// the host and the model taken from what you picked here instead of
/// assumed to be this Mac's.
///
/// Why a script plus `open` rather than a pane of our own: these are
/// interactive terminal programs, with their own approval prompts, their
/// own scrollback and their own ^C. Swallowing one into a pane means
/// re-implementing all of that, and `claude -p`'s JSON mode has no
/// approval callback to hang our cards on. So: your terminal, our
/// environment.
enum AgentLauncher {

    /// The API dialect a host has to serve for an agent to work against
    /// it. Ollama serves all three; kinfer, today, only the chat one.
    enum Dialect {
        /// Anthropic's Messages API, `/v1/messages`.
        case anthropicMessages
        /// OpenAI's Responses API, `/v1/responses`.
        case openAIResponses
    }

    /// An agent we know how to point at an Ollama.
    struct Integration {
        let id: String
        let label: String
        /// Binary names to look for, in order.
        let binaries: [String]
        /// The environment that aims the agent at `host`.
        let env: (_ host: String) -> [String: String]
        /// Arguments that aim it at `host` and pin `model` — not every
        /// agent takes its endpoint from the environment.
        let args: (_ host: String, _ model: String) -> [String]
        /// What the host must speak. Shown before it fails, not after.
        let dialect: Dialect
    }

    /// An integration whose binary is actually on this Mac.
    struct Installed: Identifiable {
        let integration: Integration
        let binary: String
        var id: String { integration.id }
    }

    /// Claude Code speaks Anthropic's Messages API, and Ollama serves it
    /// at /v1/messages — measured on 0.34.0 and 0.34.1: a proper
    /// message_start / content_block_delta stream, `thinking` blocks and
    /// all. Which makes two environment variables the whole integration:
    /// no config file to patch, nothing to restore afterwards.
    static let claudeCode = Integration(
        id: "claude",
        label: "Claude Code",
        binaries: ["claude"],
        env: { host in
            [
                "ANTHROPIC_BASE_URL": host,
                // Any non-empty token. Ollama ignores it; Claude Code
                // will not start without one.
                "ANTHROPIC_AUTH_TOKEN": "ollama",
            ]
        },
        args: { _, model in ["--model", model] },
        dialect: .anthropicMessages
    )

    /// Codex takes its endpoint as config overrides — `-c key=value` —
    /// which beats rewriting somebody's ~/.codex/config.toml, because a
    /// rewrite needs an undo.
    ///
    /// Three things learned by trying it (0.154.0):
    ///   - `wire_api = "chat"` is refused outright now: "set wire_api =
    ///     \"responses\"". Ollama does serve /v1/responses — measured,
    ///     200 with a proper Responses body — so this works anyway.
    ///   - the built-in `ollama` provider cannot have its base_url
    ///     overridden ("Built-in providers cannot be overridden"), hence
    ///     a provider of our own. Which is also what lets Codex point at
    ///     the box on the LAN and not just this Mac.
    ///   - Codex opens with a ~7-9K token prompt, so a 4K-context model
    ///     cannot run it at all.
    static let codex = Integration(
        id: "codex",
        label: "Codex",
        binaries: ["codex"],
        env: { _ in [:] },
        args: { host, model in
            [
                "-c", "model_provider=kinhost",
                "-c", "model_providers.kinhost.name=\"KinClaw host\"",
                "-c", "model_providers.kinhost.base_url=\"\(host)/v1\"",
                "-c", "model_providers.kinhost.wire_api=\"responses\"",
                "--model", model,
            ]
        },
        dialect: .openAIResponses
    )

    /// Agents that want somebody else's config file rewritten (Cline's
    /// VS Code settings) are still out: a different promise from a flag,
    /// and it needs an undo.
    static let all: [Integration] = [claudeCode, codex]

    /// The ones installed here. Resolved once: this is read while a menu
    /// is being built.
    static let available: [Installed] = all.compactMap { integration in
        guard let path = locate(integration.binaries) else { return nil }
        return Installed(integration: integration, binary: path)
    }

    /// Where the agent should start: the folder Code is pointed at, if
    /// there is one — that is where a coding agent is any use.
    static var defaultDirectory: String {
        let repo = UserDefaults.standard.string(forKey: "kinclaw.kincode.repo") ?? ""
        if !repo.isEmpty, FileManager.default.fileExists(atPath: repo) { return repo }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// The user's login shell, from the user record rather than the
    /// environment — launchd does not reliably hand a GUI app a SHELL.
    static var loginShell: String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    /// PATH for a child this app spawns itself.
    ///
    /// A GUI app inherits launchd's PATH — /usr/bin:/bin:/usr/sbin:/sbin
    /// — which is how the Term tab first died with `env: node: No such
    /// file or directory`: the agent was found by absolute path, but the
    /// MCP servers and hooks *it* starts were not. The login shell the
    /// terminal runs rebuilds PATH properly (this Mac keeps nvm and the
    /// rest in .zshrc); this is the floor under that.
    static func childPath(for binary: String) -> String {
        var dirs = [(binary as NSString).deletingLastPathComponent,
                    "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
                    NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/bin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let inherited = ProcessInfo.processInfo.environment["PATH"] {
            dirs += inherited.split(separator: ":").map(String.init)
        }
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    /// Open `item` in a terminal against `host` and `model`. Returns nil
    /// when the window is on its way, or a sentence to put in the menu.
    @discardableResult
    static func launch(_ item: Installed, host: String, model: String,
                       directory: String? = nil) -> String? {
        guard isTame(model) else { return "模型名里有意外的字符，没敢拼进命令：\(model)" }
        guard isTame(host) else { return "地址里有意外的字符，没敢拼进命令：\(host)" }

        let dir = directory ?? defaultDirectory
        var lines = [
            "#!/bin/sh",
            "# Written by KinClaw Mac: \(item.integration.label) against the Ollama",
            "# picked in the model menu. Safe to delete.",
            "#",
            "# If this model's window is smaller than Claude Code assumes:",
            "#   export CLAUDE_CODE_MAX_CONTEXT_TOKENS=32768",
            "cd \(shellQuoted(dir)) || exit 1",
        ]
        for (key, value) in item.integration.env(host).sorted(by: { $0.key < $1.key }) {
            lines.append("export \(key)=\(shellQuoted(value))")
        }
        lines.append("echo \"→ \(item.integration.label) · \(model) · \(host)\"")
        let args = item.integration.args(host, model).map(shellQuoted).joined(separator: " ")
        lines.append("exec \(shellQuoted(item.binary)) \(args)")

        let folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/kinclaw/launch")
        let script = folder.appendingPathComponent(
            "\(item.integration.id)-\(Int(Date().timeIntervalSince1970)).command")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: script.path)
        } catch {
            return "写启动脚本失败：\(error.localizedDescription)"
        }

        // `open` hands the .command to whichever terminal owns the
        // extension — Terminal, iTerm, Ghostty — and the window becomes
        // launchd's child rather than ours, so the agent does not inherit
        // this app's TCC responsibility.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = [script.path]
        do {
            try proc.run()
        } catch {
            return "打不开终端：\(error.localizedDescription)"
        }
        sweep(folder)
        return nil
    }

    /// Model names and URLs only ever contain these. Everything is
    /// shell-quoted anyway; this is the second lock on the same door.
    private static func isTame(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"
                         + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:/_@+-").contains($0)
        }
    }

    /// Single-quote a word for a shell command line.
    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A GUI app's PATH is whatever launchd gave it — usually not the one
    /// with Homebrew in it — so the usual places are named outright.
    private static func locate(_ names: [String]) -> String? {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                    NSHomeDirectory() + "/.local/bin",
                    NSHomeDirectory() + "/bin",
                    NSHomeDirectory() + "/.claude/local"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        for name in names {
            for dir in dirs where FileManager.default.isExecutableFile(atPath: dir + "/" + name) {
                return dir + "/" + name
            }
        }
        return nil
    }

    /// Yesterday's launch scripts, which nothing is reading any more.
    private static func sweep(_ folder: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-86_400)
        for url in entries where url.pathExtension == "command" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            if modified < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }
}
