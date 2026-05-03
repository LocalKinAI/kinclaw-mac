import Foundation

/// Manages auth tokens - fetches from remote config, falls back to cached/defaults
actor TokenManager {
    static let shared = TokenManager()

    private var coreToken: String = "lk2026"
    private var fleetToken: String = "lk2026-internal"
    private var lastFetch: Date?

    /// Get the auth token for a given hostname
    func token(for hostname: String) -> String {
        // Fleet agents have f- prefix
        if hostname.hasPrefix("f-") {
            return fleetToken
        }
        return coreToken
    }

    /// Fetch tokens from remote config (call on app launch)
    func refreshFromRemote() async {
        // Don't fetch more than once per hour
        if let last = lastFetch, Date().timeIntervalSince(last) < 3600 {
            return
        }

        do {
            let url = URL(string: "https://www.localkin.dev/api/app-config")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)

            if let core = config.coreToken, !core.isEmpty {
                coreToken = core
                UserDefaults.standard.set(core, forKey: "remote_core_token")
            }
            if let fleet = config.fleetToken, !fleet.isEmpty {
                fleetToken = fleet
                UserDefaults.standard.set(fleet, forKey: "remote_fleet_token")
            }
            lastFetch = Date()
        } catch {
            // Fall back to cached tokens
            if let cached = UserDefaults.standard.string(forKey: "remote_core_token") {
                coreToken = cached
            }
            if let cached = UserDefaults.standard.string(forKey: "remote_fleet_token") {
                fleetToken = cached
            }
        }
    }

    private struct AppConfig: Codable {
        let coreToken: String?
        let fleetToken: String?

        enum CodingKeys: String, CodingKey {
            case coreToken = "core_token"
            case fleetToken = "fleet_token"
        }
    }
}
