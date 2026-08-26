import Foundation

/// Backs the Harvest settings tab: which skill sources are configured, what
/// they've staged, and whether the nightly job is actually scheduled.
///
/// Source config is read through the kernel rather than parsed here — the
/// manifest is TOML, and Go already has a validated parser for it. Duplicating
/// that in Swift would mean two parsers to keep in agreement over a file the
/// user hand-edits.
@MainActor
final class HarvestStore: ObservableObject {

    struct Source: Codable, Identifiable, Equatable {
        var name: String
        var url: String
        var skillPaths: [String]?
        var licenseAllow: [String]?
        var branch: String?
        var staged: Int

        var id: String { name }
    }

    struct Candidate: Codable, Identifiable, Equatable {
        var source: String
        var name: String
        var verdict: String
        var reason: String
        var domain: String?
        var stagedAt: String?

        var id: String { "\(source)/\(name)" }
    }

    struct Status: Codable {
        var manifestPath: String
        var sources: [Source]
        var candidates: [Candidate]
        var cachedVerdicts: Int
        var error: String?
    }

    /// One in-flight or finished forge, keyed by candidate id.
    struct AcceptJob: Codable, Equatable {
        var id: String
        var skillId: String
        var status: String          // running / done / failed
        var verdict: String?        // forged / library / duplicate / error
        var destPath: String?
        var forgedName: String?
        var reason: String?
        var error: String?

        var isRunning: Bool { status == "running" }
        var succeeded: Bool { status == "done" && verdict == "forged" }
    }

    @Published private(set) var jobs: [String: AcceptJob] = [:]
    @Published private(set) var status: Status?
    @Published private(set) var fetchFailed = false
    /// Whether the nightly LaunchAgent is loaded, and what it will run.
    @Published private(set) var scheduled = false
    @Published private(set) var scheduleSummary = ""

    static let launchAgentPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.localkin.kinclaw-harvest.plist")

    var manifestURL: URL? {
        guard let p = status?.manifestPath, !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p)
    }

    /// Candidates the curator said yes to, then maybe — the order a reviewer
    /// wants them in.
    var sortedCandidates: [Candidate] {
        (status?.candidates ?? []).sorted {
            if $0.verdict != $1.verdict { return rank($0.verdict) < rank($1.verdict) }
            return $0.id < $1.id
        }
    }

    private func rank(_ verdict: String) -> Int {
        switch verdict.lowercased() {
        case "yes": return 0
        case "maybe": return 1
        default: return 2
        }
    }

    /// Sources that have never produced a staged candidate.
    ///
    /// Worth calling out on its own: a source costs a git clone and a scan on
    /// every run, and several of these produce nothing because their skills
    /// are prompt templates rather than command wrappers — a mismatch no
    /// amount of re-scanning will fix.
    var barrenSources: [Source] {
        (status?.sources ?? []).filter { $0.staged == 0 }
    }

    func refresh(port: Int = 5001) async {
        await fetchStatus(port: port)
        readSchedule()
    }

    private func fetchStatus(port: Int) async {
        guard let url = URL(string: "http://localhost:\(port)/api/harvest") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                fetchFailed = true
                return
            }
            status = try JSONDecoder().decode(Status.self, from: data)
            fetchFailed = false
        } catch {
            // Kernel not up yet is routine at launch; keep any prior data.
            fetchFailed = true
        }
    }

    /// Read the LaunchAgent directly rather than shelling out to launchctl.
    ///
    /// What matters here isn't only "is it loaded" but *what arguments it
    /// runs*: a `--no-judge` entry looks perfectly healthy in `launchctl list`
    /// while doing only half the job, which is exactly how this went unnoticed
    /// for three months.
    private func readSchedule() {
        scheduled = false
        scheduleSummary = ""
        let path = Self.launchAgentPath
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any]
        else { return }

        scheduled = true
        let args = (plist["ProgramArguments"] as? [String]) ?? []
        var parts: [String] = []

        if let cal = plist["StartCalendarInterval"] as? [String: Any],
           let h = cal["Hour"] as? Int {
            let m = (cal["Minute"] as? Int) ?? 0
            parts.append(String(format: "daily %02d:%02d", h, m))
        }
        if args.contains("--no-judge") {
            parts.append("⚠ --no-judge (fetches but never triages)")
        }
        scheduleSummary = parts.joined(separator: " · ")
    }
}

// MARK: - Accepting candidates

extension HarvestStore {

    /// Start forging a staged candidate.
    ///
    /// This writes code into the user's repo — the coder agent rewrites the
    /// external skill into KinClaw's exec form and the result lands in
    /// `skills/`. It is the only write in the settings surface, which is why
    /// the UI gates it behind a confirmation rather than a bare button.
    ///
    /// Returns immediately; the forge runs for up to four minutes and is
    /// followed with `pollJob`.
    func accept(_ candidate: Candidate, port: Int = 5001) async {
        guard let url = URL(string: "http://localhost:\(port)/api/harvest/accept") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["skillId": candidate.id])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 409 {
                // Already forging this one — surface it rather than starting a
                // second coder against the same destination directory.
                jobs[candidate.id] = AcceptJob(
                    id: "-", skillId: candidate.id, status: "running",
                    reason: "already forging")
                return
            }
            guard http.statusCode == 202 else {
                jobs[candidate.id] = AcceptJob(
                    id: "-", skillId: candidate.id, status: "failed",
                    error: "server returned \(http.statusCode)")
                return
            }
            let job = try JSONDecoder().decode(AcceptJob.self, from: data)
            jobs[candidate.id] = job
            await pollJob(job, candidateID: candidate.id, port: port)
        } catch {
            jobs[candidate.id] = AcceptJob(
                id: "-", skillId: candidate.id, status: "failed",
                error: error.localizedDescription)
        }
    }

    /// Follow a forge to completion.
    ///
    /// Polls rather than holding a long request open: the kernel may be
    /// restarted mid-forge, and a dropped connection shouldn't lose the job.
    private func pollJob(_ job: AcceptJob, candidateID: String, port: Int) async {
        guard let url = URL(string:
            "http://localhost:\(port)/api/harvest/accept/status?id=\(job.id)") else { return }

        // Coder's own timeout is 240s; give it a margin and then stop rather
        // than polling forever against a job that will never resolve.
        let deadline = Date().addingTimeInterval(330)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let updated = try? JSONDecoder().decode(AcceptJob.self, from: data)
            else { continue }

            jobs[candidateID] = updated
            if !updated.isRunning {
                // A forged skill changes what the kernel *would* load, so the
                // candidate list is stale from here on.
                await refresh(port: port)
                return
            }
        }
        jobs[candidateID] = AcceptJob(
            id: job.id, skillId: job.skillId, status: "failed",
            error: "timed out waiting for the forge to finish")
    }

    func job(for candidate: Candidate) -> AcceptJob? { jobs[candidate.id] }
}
