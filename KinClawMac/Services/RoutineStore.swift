import Foundation

/// Backs the Routines settings tab: scheduled one-shot kinclaw runs, read
/// and written through the kernel's /api/routines so the CLI, the app and
/// launchd all see one registry (~/.kinclaw/routines.json).
@MainActor
final class RoutineStore: ObservableObject {

    struct Routine: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var prompt: String
        var soul: String?
        var schedule: String
        var schedule_raw: String
        var enabled: Bool
        var installed: Bool
        var last_run: String?
        var log_path: String
        var created_at: String

        var lastRunText: String {
            guard let s = last_run, let d = ISO8601DateFormatter().date(from: s) else { return "never" }
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f.localizedString(for: d, relativeTo: Date())
        }
    }

    @Published private(set) var routines: [Routine] = []
    @Published private(set) var fetchFailed = false
    @Published var lastError: String?
    @Published private(set) var logText: [String: String] = [:]

    private let base: URL

    init(port: Int = 5001) {
        base = URL(string: "http://localhost:\(port)")!
    }

    func refresh() async {
        do {
            let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("api/routines"))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { fetchFailed = true; return }
            struct Reply: Decodable { let routines: [Routine] }
            routines = try JSONDecoder().decode(Reply.self, from: data).routines
            fetchFailed = false
        } catch {
            fetchFailed = true
        }
    }

    /// Returns nil on success, or the warning/error text.
    func add(name: String, prompt: String, schedule: String) async -> String? {
        var req = URLRequest(url: base.appendingPathComponent("api/routines"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["name": name, "prompt": prompt, "schedule": schedule])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            struct Reply: Decodable { let warning: String?; let error: String? }
            let r = try? JSONDecoder().decode(Reply.self, from: data)
            await refresh()
            if code == 201 { return nil }
            return r?.warning ?? r?.error ?? "HTTP \(code)"
        } catch {
            return error.localizedDescription
        }
    }

    func remove(id: String) async {
        var comps = URLComponents(url: base.appendingPathComponent("api/routines"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: id)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: req)
        await refresh()
    }

    func runNow(id: String) async {
        await post("api/routines/run", body: ["id": id])
        try? await Task.sleep(nanoseconds: 800_000_000)
        await refresh()
    }

    func setEnabled(id: String, on: Bool) async {
        await post("api/routines/enable", body: ["id": id, "enabled": on])
        await refresh()
    }

    func loadLog(id: String) async {
        var comps = URLComponents(url: base.appendingPathComponent("api/routines/log"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: id)]
        if let (data, _) = try? await URLSession.shared.data(from: comps.url!) {
            logText[id] = String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func post(_ path: String, body: [String: Any]) async {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 300 {
                lastError = String(data: data, encoding: .utf8)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
