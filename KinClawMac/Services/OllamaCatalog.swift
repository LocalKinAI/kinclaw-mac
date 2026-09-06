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
