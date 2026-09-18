import AppKit
import Foundation

/// Pictures made to order, from an OllamaDiffuser on the network.
///
/// The companion's art has been downloaded stock until now: a search, somebody
/// else's photograph, and whatever it happens to show. A diffuser on the box
/// answers the other way round — you say what you want and it makes that. Which
/// is the difference between a picture *of* a cafe and a picture of *her* in
/// one.
///
/// It talks to OllamaDiffuser's REST API (`/api/generate`, `/api/models`), the
/// same one `ollamadiffuser run` serves. Measured on the box with
/// Boogu-Image-Turbo: 14s for 768×768 at 4 steps.
@MainActor
final class DiffuserClient: ObservableObject {
    static let shared = DiffuserClient()

    static let hostKey = "kinclaw.diffuser.host"
    /// The box, where the models and the memory are. A laptop can serve this
    /// too — the setting is one field in the picker.
    static let defaultHost = "http://192.168.0.21:8000"

    /// Video is a different model, and OllamaDiffuser serves one model per
    /// process — so it is a second server, on the next port, rather than a
    /// flag on this one. Unset means "same machine, 8001".
    static let videoHostKey = "kinclaw.diffuser.video.host"
    static let defaultVideoHost = "http://192.168.0.21:8001"

    /// What the server says it has loaded, and whether it answered at all.
    struct Status: Equatable {
        var reachable = false
        var model: String?
        var note: String?
    }

    @Published private(set) var status = Status()
    @Published private(set) var busy = false
    /// The last picture made, for a view that wants to show it straight away.
    @Published private(set) var lastImage: URL?

    static var host: String {
        get {
            let stored = UserDefaults.standard.string(forKey: hostKey) ?? ""
            return stored.isEmpty ? defaultHost : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: hostKey)
        }
    }

    static var videoHost: String {
        get {
            let stored = UserDefaults.standard.string(forKey: videoHostKey) ?? ""
            return stored.isEmpty ? defaultVideoHost : stored
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: videoHostKey)
        }
    }

    private static func url(_ path: String, on base: String? = nil) -> URL? {
        let root = base ?? host
        return URL(string: root.hasSuffix("/") ? root + path : root + "/" + path)
    }

    // MARK: - Is anything there

    /// Ask the server what it has loaded. Cheap, and the answer is what the
    /// picker shows instead of a spinner that means nothing.
    @discardableResult
    func refresh() async -> Status {
        guard let url = Self.url("api/models") else {
            status = Status(reachable: false, note: "地址不对：\(Self.host)")
            return status
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                status = Status(reachable: false, note: "\(Self.host) 回了个错误")
                return status
            }
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            // The server reports `loaded` (or `current`) plus everything it could load.
            let loaded = (parsed?["loaded"] ?? parsed?["current"]) as? String
            status = Status(reachable: true, model: loaded,
                            note: loaded == nil ? "服务在，但没有加载模型" : nil)
        } catch {
            status = Status(reachable: false, note: "连不上 \(Self.host)")
        }
        return status
    }

    // MARK: - Making one

    /// Generate a picture and write it into `folder`, named after the prompt.
    ///
    /// Steps and size default to what a 4-step turbo model wants; a slower
    /// model just takes longer. The timeout is generous because the first
    /// request after a model loads can be minutes.
    @discardableResult
    func generate(prompt: String, into folder: URL, steps: Int = 4,
                  width: Int = 768, height: Int = 768,
                  seed: Int? = nil, timeout: TimeInterval = 600) async throws -> URL {
        guard let url = Self.url("api/generate") else {
            throw Failure.message("出图服务地址不对：\(Self.host)")
        }
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw Failure.message("要画什么？提示词是空的") }

        busy = true
        defer { busy = false }

        var body: [String: Any] = [
            "prompt": cleaned, "steps": steps, "width": width, "height": height,
        ]
        if let seed { body["seed"] = seed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw Failure.message("出图失败（HTTP \(code)）：\(Self.host)")
        }
        // A model that fails mid-generation still answers 200 with a small
        // error image drawn by the server, so the size is the tell.
        guard data.count > 20_000, NSImage(data: data) != nil else {
            throw Failure.message("服务返回的不是一张正常的图（\(data.count) 字节），看看它的日志")
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(Self.fileName(for: cleaned))
        try data.write(to: file)
        // The prompt is the picture's description, and the companion's art
        // matcher reads these sidecars when it picks by subject.
        try? cleaned.write(to: file.appendingPathExtension("txt"),
                           atomically: true, encoding: .utf8)
        lastImage = file
        return file
    }

    /// A file name from the prompt: readable, unique, and matchable — the
    /// companion picks art by keywords in the file name.
    static func fileName(for prompt: String) -> String {
        let words = prompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
        let slug = words.isEmpty ? "made" : words.joined(separator: "-")
        return "\(String(slug.prefix(60)))-\(Int(Date().timeIntervalSince1970)).png"
    }

    // MARK: - Moving ones

    /// Generate a short clip and write it into `folder`.
    ///
    /// The companion already treats an mp4 in her art folder as a background
    /// loop, so this needs no new plumbing to show up: a clip made under 开心
    /// is one she stands in front of when she is happy.
    ///
    /// Minutes, not seconds — LTX-2 denoises every frame — so the default
    /// timeout is half an hour and the caller is expected to say so.
    @discardableResult
    func generateVideo(prompt: String, into folder: URL, seconds: Double = 4,
                       width: Int = 704, height: Int = 480,
                       seed: Int? = nil, mode: String? = nil,
                       timeout: TimeInterval = 1800) async throws -> URL {
        let name = Self.fileName(for: prompt).replacingOccurrences(of: ".png", with: ".mp4")
        return try await generateVideo(prompt: prompt, to: folder.appendingPathComponent(name),
                                       seconds: seconds, width: width, height: height,
                                       seed: seed, mode: mode, timeout: timeout)
    }

    /// The same, into a file whose name the caller already knows — which is
    /// what makes a job announceable before it finishes.
    @discardableResult
    func generateVideo(prompt: String, to file: URL, seconds: Double = 4,
                       width: Int = 704, height: Int = 480,
                       seed: Int? = nil, mode: String? = nil,
                       timeout: TimeInterval = 1800) async throws -> URL {
        guard let url = Self.url("api/generate/video", on: Self.videoHost) else {
            throw Failure.message("视频服务地址不对：\(Self.videoHost)")
        }
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw Failure.message("要拍什么？提示词是空的") }

        // No `busy` here: a clip runs for minutes, and the jobs list is
        // what says so. Blocking the picture button that long would be a
        // worse lie than no spinner at all.

        // Multipart because the endpoint also takes a reference image and an
        // audio track; neither is sent here, and the parts are all text.
        var fields: [String: String] = [
            "prompt": cleaned, "seconds": String(seconds),
            "width": String(width), "height": String(height),
        ]
        if let seed { fields["seed"] = String(seed) }
        if let mode { fields["mode"] = mode }

        let boundary = "kinclaw-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                .data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            // The server answers 400 with a sentence for everything a caller
            // can fix — no model loaded, an image model, a frame count off
            // the grid — so show that sentence rather than the number.
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
                .flatMap { $0["detail"] as? String }
            throw Failure.message(detail ?? "出视频失败（HTTP \(http?.statusCode ?? 0)）：\(Self.videoHost)")
        }
        guard data.count > 100_000 else {
            throw Failure.message("服务返回的不像一段视频（\(data.count) 字节），看看它的日志")
        }

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        try? cleaned.write(to: file.appendingPathExtension("txt"),
                           atomically: true, encoding: .utf8)
        lastImage = file
        return file
    }

    // MARK: - Jobs

    /// A clip being made. Minutes long, so it is something to look in on
    /// rather than something to wait for.
    struct VideoJob: Identifiable, Equatable {
        var id: URL { file }
        let file: URL
        let prompt: String
        let started = Date()
        var finished: Date?
        var error: String?

        var done: Bool { finished != nil && error == nil }
        var elapsed: TimeInterval { (finished ?? Date()).timeIntervalSince(started) }
        var line: String {
            let secs = Int(elapsed.rounded())
            if let error { return "「\(prompt)」失败了（\(secs)s）：\(error)" }
            if finished != nil { return "「\(prompt)」拍好了，\(secs)s：\(file.path)" }
            return "「\(prompt)」在拍，已经 \(secs)s → \(file.path)"
        }
    }

    /// Newest first, and only the last handful: this is a status line, not a
    /// history.
    @Published private(set) var videoJobs: [VideoJob] = []

    /// Start a clip and return where it will land.
    ///
    /// The kernel's MCP client gives a tool call 60 seconds and closes the
    /// connection when one overruns — which would take every other panel tool
    /// down with it. A generation is minutes. So the tool that starts one
    /// answers with the path and a job to ask about, rather than holding the
    /// line open and losing the panel.
    @discardableResult
    func startVideo(prompt: String, into folder: URL, seconds: Double = 4,
                    width: Int = 704, height: Int = 480,
                    seed: Int? = nil, mode: String? = nil) -> URL {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = Self.fileName(for: cleaned).replacingOccurrences(of: ".png", with: ".mp4")
        let file = folder.appendingPathComponent(name)
        videoJobs.insert(VideoJob(file: file, prompt: cleaned), at: 0)
        videoJobs = Array(videoJobs.prefix(6))

        Task { @MainActor in
            do {
                _ = try await generateVideo(prompt: cleaned, to: file, seconds: seconds,
                                            width: width, height: height,
                                            seed: seed, mode: mode)
                finish(file, error: nil)
            } catch {
                finish(file, error: error.localizedDescription)
            }
        }
        return file
    }

    private func finish(_ file: URL, error: String?) {
        guard let index = videoJobs.firstIndex(where: { $0.file == file }) else { return }
        videoJobs[index].finished = Date()
        videoJobs[index].error = error
    }

    /// What the jobs are doing, as a sentence each — the answer to a
    /// `video_status` call and to the row in the picker.
    var videoReport: String {
        videoJobs.isEmpty ? "还没拍过" : videoJobs.map(\.line).joined(separator: "\n")
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }
}
