import Darwin
import Foundation

/// Queries the user's local Ollama install (default :11434) for the
/// chat-capable models they have pulled, and surfaces them as
/// `BrainPreset` rows for the Code-mode brain dropdown + Settings →
/// Backend → Default brain.
///
/// Why dynamic: every Ollama install has a different set of models —
/// hardcoding "Kimi K2.6" / "GPT-4o" / "Claude" lies if the user
/// doesn't have them, and misses what they actually pulled (the cloud
/// catalog evolves weekly). One HTTP call to /api/tags returns the
/// real list, including Ollama Cloud models with the `:cloud` suffix.
///
/// Filters out embedding-only models (bge-*, *-embedding-*) since
/// those can't drive a chat agent. Vision models (qwen3-vl etc.)
/// stay — they can do text and might be useful for inspecting
/// screenshots later.
enum OllamaCatalog {

    /// Default Ollama endpoint base (no path, no trailing slash).
    static let defaultBaseURL = "http://localhost:11434"

    /// UserDefaults key for the Ollama host (Settings → Backend).
    static let hostKey = "kinclaw.ollama.host"

    /// The Ollama the dropdowns list models from and brain switches
    /// point at — the laptop's own by default, or a box on the LAN
    /// (`http://192.168.0.21:11434`). Normalized: scheme added if
    /// missing, trailing slash and any path dropped.
    static var baseURL: String {
        let raw = (UserDefaults.standard.string(forKey: hostKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return defaultBaseURL }
        var s = raw
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "http://" + s }
        if let comps = URLComponents(string: s), let host = comps.host {
            let port = comps.port.map { ":\($0)" } ?? ":11434"
            return "\(comps.scheme ?? "http")://\(host)\(port)"
        }
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    /// True when models come from somewhere other than this Mac.
    static var isRemote: Bool { baseURL != defaultBaseURL }

    /// UserDefaults key for remembered remote hosts (the source picker).
    static let hostsKey = "kinclaw.ollama.hosts"

    /// This Mac first, then every remote host ever set — the rows of the
    /// "Source" section in both brain menus.
    static var knownHosts: [String] {
        var out = [defaultBaseURL]
        let saved = UserDefaults.standard.stringArray(forKey: hostsKey) ?? []
        for h in saved + [baseURL] where !out.contains(h) && h != defaultBaseURL {
            out.append(h)
        }
        return out
    }

    /// Remember a host without switching to it — what a LAN scan does
    /// with what it finds.
    static func remember(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, h != defaultBaseURL else { return }
        var saved = UserDefaults.standard.stringArray(forKey: hostsKey) ?? []
        guard !saved.contains(h) else { return }
        saved.append(h)
        UserDefaults.standard.set(saved, forKey: hostsKey)
    }

    /// Forget a remembered host. Switches back to this Mac if it was
    /// the active one, so removing the box you are using does not leave
    /// the dropdowns pointing at nothing.
    static func forget(_ host: String) {
        var saved = UserDefaults.standard.stringArray(forKey: hostsKey) ?? []
        saved.removeAll { $0 == host }
        UserDefaults.standard.set(saved, forKey: hostsKey)
        if baseURL == host { setHost("") }
    }

    // MARK: - Is it there?

    /// What a probe found: reachable, and how many chat models it has.
    struct Health: Equatable {
        let reachable: Bool
        let models: Int
        /// nil until probed — the row shows nothing rather than
        /// claiming a host is down before anyone has looked.
        static let unknown: Health? = nil
    }

    private static var healthCache: [String: (Health, Date)] = [:]

    /// The last known health of a host, if it was probed recently.
    static func cachedHealth(_ host: String) -> Health? {
        guard let (h, at) = healthCache[host], Date().timeIntervalSince(at) < 30 else { return nil }
        return h
    }

    /// Ask a host whether it is there. Short timeout: this runs for
    /// every row of a menu that is about to open, and a menu that waits
    /// on a dead LAN box is worse than a menu with no dots.
    @discardableResult
    static func probe(_ host: String) async -> Health {
        var h = Health(reachable: false, models: 0)
        if let url = URL(string: "\(host)/api/tags") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 1.5
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = root["models"] as? [[String: Any]] {
                let names = models.compactMap { $0["name"] as? String }
                h = Health(reachable: true, models: names.filter { isChatCapable($0) }.count)
            }
        }
        healthCache[host] = (h, Date())
        return h
    }

    /// Probe every remembered host at once.
    static func probeAll() async {
        await withTaskGroup(of: Void.self) { group in
            for host in knownHosts {
                group.addTask { _ = await probe(host) }
            }
        }
    }

    // MARK: - Finding a box you did not know about

    /// Scan this machine's /24 for Ollama.
    ///
    /// The source picker used to be a menu with one row in it — this
    /// Mac — because a remote host only appeared after you typed its
    /// full URL into Settings and pressed Return. Which means the
    /// feature was only usable by someone who already knew the IP, and
    /// silently did nothing for everyone else.
    ///
    /// On demand only, never on launch: scanning somebody's network
    /// because an app felt like it is not a thing to do quietly.
    static func discover() async -> [String] {
        guard let prefix = subnetPrefix() else { return [] }
        var found: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for i in 1...254 {
                let host = "http://\(prefix).\(i):11434"
                group.addTask {
                    guard let url = URL(string: "\(host)/api/tags") else { return nil }
                    var req = URLRequest(url: url)
                    // Generous enough for a busy box on wifi, short
                    // enough that 254 of them finish in a couple of
                    // seconds.
                    req.timeoutInterval = 1.2
                    guard let (data, resp) = try? await URLSession.shared.data(for: req),
                          (resp as? HTTPURLResponse)?.statusCode == 200,
                          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          root["models"] != nil else { return nil }
                    return host
                }
            }
            for await host in group {
                if let host { found.append(host) }
            }
        }
        // This Mac answers on its own LAN address only if Ollama was
        // told to bind beyond loopback; either way it is already the
        // first row as "This Mac", so drop the duplicate.
        let mine = myAddresses().map { "http://\($0):11434" }
        found.removeAll { mine.contains($0) }
        return found.sorted()
    }

    /// The first three octets of this machine's LAN address.
    private static func subnetPrefix() -> String? {
        for a in myAddresses() {
            let parts = a.split(separator: ".")
            if parts.count == 4 { return parts.prefix(3).joined(separator: ".") }
        }
        return nil
    }

    /// This machine's IPv4 addresses, loopback excluded.
    private static func myAddresses() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return out }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let a = String(cString: host)
                if !a.isEmpty, !a.contains(":") { out.append(a) }
            }
        }
        return out
    }

    /// Make `host` the active Ollama (normalized) and remember it.
    /// Passing the default (or "") switches back to this Mac.
    static func setHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultBaseURL {
            UserDefaults.standard.removeObject(forKey: hostKey)
            return
        }
        UserDefaults.standard.set(trimmed, forKey: hostKey)
        let normalized = baseURL
        var saved = UserDefaults.standard.stringArray(forKey: hostsKey) ?? []
        if !saved.contains(normalized) {
            saved.append(normalized)
            UserDefaults.standard.set(saved, forKey: hostsKey)
        }
    }

    /// "This Mac" or "192.168.0.21" — the row label for a host.
    static func hostLabel(_ host: String) -> String {
        if host == defaultBaseURL { return "This Mac" }
        if let c = URLComponents(string: host), let h = c.host {
            return c.port.map { $0 == 11434 ? h : "\(h):\($0)" } ?? h
        }
        return host
    }

    /// Short badge for the current source in the brain label.
    static var sourceBadge: String { isRemote ? hostLabel(baseURL) : "local" }

    /// The endpoint kincode wants for an Ollama brain (full chat URL).
    static var kincodeEndpoint: String { baseURL + "/v1/chat/completions" }

    /// Fetch installed models and map to BrainPreset rows. Returns an
    /// empty array if Ollama is unreachable or no models match the
    /// chat filter — caller can decide what to fall back to. Never
    /// throws; network failures surface as empty result + a printed
    /// note (Ollama might just not be running).
    static func loadPresets(baseURL: String = OllamaCatalog.baseURL) async -> [BrainPreset] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return decoded.models
                .filter { isChatCapable($0.name) }
                .map { BrainPreset(
                    provider: "ollama",
                    model: $0.name,
                    label: prettyLabel(for: $0.name),
                    needsEnv: nil
                ) }
                .sorted { lhs, rhs in
                    // Cloud models first (faster + more capable),
                    // alphabetical within each tier.
                    let lhsCloud = lhs.model.hasSuffix(":cloud")
                    let rhsCloud = rhs.model.hasSuffix(":cloud")
                    if lhsCloud != rhsCloud { return lhsCloud }
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
        } catch {
            // Ollama not running, network glitch, or JSON shape changed.
            // Empty list lets caller fall back to a static minimum.
            print("[OllamaCatalog] could not fetch /api/tags: \(error.localizedDescription)")
            return []
        }
    }

    /// Skip embedding models — they can't drive a chat agent. Match
    /// substrings rather than exact names so `bge-m3:latest`,
    /// `qwen3-embedding:4b`, `nomic-embed-text:latest` etc. all get
    /// caught regardless of version tag.
    private static func isChatCapable(_ name: String) -> Bool {
        let lower = name.lowercased()
        let nonChatMarkers = ["embed", "bge-", "rerank"]
        for marker in nonChatMarkers {
            if lower.contains(marker) { return false }
        }
        return true
    }

    /// Compact label for the dropdown row. Strip the `:tag` suffix
    /// for display when it's just `:latest` (noisy default), keep
    /// `:cloud` and version tags (informative).
    ///
    ///   "kimi-k2.6:cloud"     → "kimi-k2.6 (cloud)"
    ///   "qwen3.5:9b"          → "qwen3.5 (9b)"
    ///   "qwen3-vl:8b"         → "qwen3-vl (8b)"
    ///   "bge-m3:latest"       → (filtered out)
    ///   "gemini-3-pro:latest" → "gemini-3-pro"
    private static func prettyLabel(for modelName: String) -> String {
        let parts = modelName.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            let base = parts[0]
            let tag = parts[1]
            if tag == "latest" {
                return base
            }
            return "\(base) (\(tag))"
        }
        return modelName
    }
}

/// Shape of `/api/tags` JSON response. Only the fields we care about.
private struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

private struct OllamaModel: Codable {
    let name: String
}
