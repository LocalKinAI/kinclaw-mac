import Foundation

/// Reads and writes ~/.localkin/mcp.json, and asks the running kinclaw kernel
/// what actually happened to those servers.
///
/// Two sources on purpose. The file says what the user asked for; the kernel
/// says whether it worked. A settings screen built on the file alone can show
/// a server that has been failing to start for a week and look perfectly
/// healthy doing it.
@MainActor
final class MCPConfigStore: ObservableObject {

    /// One server as stored in mcp.json.
    ///
    /// Field names match the ecosystem-standard `mcpServers` block used by
    /// Claude Desktop and kincode, so a config can be copied between them and
    /// a server's published install snippet pasted in unchanged.
    struct ServerConfig: Codable, Equatable {
        var command: String
        var args: [String]?
        var env: [String: String]?
        var disabled: Bool?
    }

    struct ConfigFile: Codable {
        var mcpServers: [String: ServerConfig]
    }

    /// Runtime state from GET /api/mcp, merged with the config by the kernel.
    struct ServerStatus: Codable, Identifiable, Equatable {
        var name: String
        var command: String
        var args: [String]?
        var disabled: Bool
        var connected: Bool
        var toolCount: Int
        var error: String?
        var logPath: String?
        var tools: [String]?

        var id: String { name }
    }

    @Published private(set) var statuses: [ServerStatus] = []
    @Published private(set) var config: ConfigFile = ConfigFile(mcpServers: [:])
    @Published private(set) var loadError: String?
    /// Set once the file has been edited, cleared after the kernel restarts.
    /// Servers are launched at kernel start, so an edit made now is invisible
    /// until then — and a settings screen that silently does nothing is worse
    /// than one that says so.
    @Published var needsRestart = false

    static let configPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".localkin/mcp.json")

    // MARK: - Config file

    func loadConfig() {
        loadError = nil
        let url = Self.configPath
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Absence is the normal state for anyone not using MCP; it must
            // not read as an error.
            config = ConfigFile(mcpServers: [:])
            return
        }
        do {
            let data = try Data(contentsOf: url)
            config = try JSONDecoder().decode(ConfigFile.self, from: data)
        } catch {
            // Keep whatever was loaded before and surface the message: a
            // hand-edited file with a trailing comma should say "invalid
            // JSON", not silently appear empty and invite the user to
            // re-enter everything.
            loadError = "mcp.json: \(error.localizedDescription)"
        }
    }

    func saveConfig() {
        do {
            let dir = Self.configPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            // Sorted + pretty because this file is meant to stay hand-editable;
            // it is also the format people paste snippets into.
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: Self.configPath, options: .atomic)
            needsRestart = true
            loadError = nil
        } catch {
            loadError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func setDisabled(_ disabled: Bool, for name: String) {
        guard var srv = config.mcpServers[name] else { return }
        // Written as nil rather than false when enabling, so an untouched
        // config stays byte-identical to what the user (or an install
        // snippet) wrote.
        srv.disabled = disabled ? true : nil
        config.mcpServers[name] = srv
        saveConfig()
    }

    func remove(_ name: String) {
        config.mcpServers.removeValue(forKey: name)
        saveConfig()
    }

    /// Add or replace a server. Returns an error message on invalid input.
    @discardableResult
    func upsert(name: String, command: String, argsText: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCmd = command.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return "Name is required" }
        guard !trimmedCmd.isEmpty else { return "Command is required" }

        // One argument per line. Shell-style splitting on spaces would break
        // every path containing one, and MCP args are usually paths.
        let args = argsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var srv = config.mcpServers[trimmedName] ?? ServerConfig(command: trimmedCmd)
        srv.command = trimmedCmd
        srv.args = args.isEmpty ? nil : args
        config.mcpServers[trimmedName] = srv
        saveConfig()
        return nil
    }

    // MARK: - Runtime status

    /// Fetch live status from the local kinclaw kernel.
    ///
    /// Failure here is not surfaced as an error: the kernel may simply not be
    /// running yet, which is routine at launch. The config list still renders;
    /// it just shows no connection state.
    func refreshStatus(port: Int = 5001) async {
        guard let url = URL(string: "http://localhost:\(port)/api/mcp") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode([ServerStatus].self, from: data)
            statuses = decoded
            // The kernel reporting the same set the file describes means it
            // has been restarted since the edit.
            if Set(decoded.map(\.name)) == Set(config.mcpServers.keys) {
                needsRestart = false
            }
        } catch {
            // Kernel down or still starting — leave prior statuses in place.
        }
    }

    func status(for name: String) -> ServerStatus? {
        statuses.first { $0.name == name }
    }

    /// Server names in display order.
    var serverNames: [String] {
        config.mcpServers.keys.sorted()
    }
}
