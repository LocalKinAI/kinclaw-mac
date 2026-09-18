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

    private static func url(_ path: String) -> URL? {
        URL(string: host.hasSuffix("/") ? host + path : host + "/" + path)
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

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }
}
