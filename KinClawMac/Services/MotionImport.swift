import Foundation

/// A reference video from an address instead of a file: YouTube, TikTok and
/// whatever else the user's own `yt-dlp` can read.
///
/// Two things are done on purpose. **The licence is looked at first** — the
/// metadata is read before a byte of video is, and what it says is shown: a
/// Creative Commons video may be fetched; anything else is somebody's work
/// under the site's standard terms, which do not allow taking it and making
/// something from it, so it is fetched only after the user says they have the
/// right to (their own upload, a licence, permission). And **where it came from
/// is written down** — title, author, address, licence — and travels with the
/// take, because CC BY asks to be named and because a year from now nobody
/// remembers where a movement was borrowed.
///
/// The app installs nothing. It runs the `yt-dlp` already on the Mac, and when
/// that one is too old for the site (YouTube breaks old ones every few months:
/// "HTTP Error 403") it says so, with the one line that fixes it.
enum MotionImport {

    struct Info: Equatable {
        var id: String
        var title: String
        var author: String
        var address: String
        var licence: String
        var seconds: Double
        /// Creative Commons, by the site's own word for it.
        var open: Bool { licence.lowercased().contains("creative commons") }
        var credit: String {
            [title, author, address, licence.isEmpty ? "standard licence" : licence].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    enum Failure: LocalizedError {
        case missing, refused(String)
        var errorDescription: String? {
            switch self {
            case .missing:
                return "这台 Mac 上没找到 yt-dlp。装一个：brew install yt-dlp（或 pip install yt-dlp），或者先把视频下载好再拖进来"
            case .refused(let why): return why
            }
        }
    }

    static let pathKey = "kinclaw.motion.ytdlp"

    /// The user's yt-dlp: the one they named, else the usual places.
    static func locate() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let named = UserDefaults.standard.string(forKey: pathKey) ?? ""
        let places = [named, "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "\(home)/.local/bin/yt-dlp",
                      "\(home)/.kinclaw/tools/yt-dlp/bin/yt-dlp", "\(home)/.pyenv/shims/yt-dlp"]
        return places.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// What the address is, without taking any of it.
    static func look(_ address: String) async throws -> Info {
        let out = try await run(["-J", "--no-playlist", "--no-warnings", address])
        guard let start = out.firstIndex(of: "{"),
              let json = try? JSONSerialization.jsonObject(with: Data(out[start...].utf8)) as? [String: Any] else {
            throw Failure.refused("读不出这个链接的信息：\(out.suffix(200))")
        }
        func text(_ key: String) -> String { (json[key] as? String) ?? "" }
        return Info(id: text("id").isEmpty ? String(abs(address.hashValue)) : text("id"), title: text("title"),
                    author: text("channel").isEmpty ? text("uploader") : text("channel"),
                    address: text("webpage_url").isEmpty ? address : text("webpage_url"),
                    licence: text("license"), seconds: (json["duration"] as? Double) ?? Double((json["duration"] as? Int) ?? 0))
    }

    /// Fetch it: picture only, 480 lines at most, an mp4 that needs no merging
    /// (so no ffmpeg) — a skeleton does not need more, and a pose was found in
    /// every frame of a 360-line video with the performer 144 pixels tall.
    static func fetch(_ info: Info, into folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(info.id).mp4")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        _ = try await run(["-f", "bv*[height<=480][ext=mp4]/b[height<=480][ext=mp4]/bv*[ext=mp4]/b[ext=mp4]",
                           "--no-playlist", "--no-warnings", "-q", "-o", file.path, info.address])
        guard FileManager.default.fileExists(atPath: file.path) else { throw Failure.refused("下载完了但文件不在：\(file.path)") }
        try? info.credit.write(to: file.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        return file
    }

    static func run(_ arguments: [String]) async throws -> String {
        guard let tool = locate() else { throw Failure.missing }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                // A pyenv shim needs pyenv, and an app launched from the Dock has almost no PATH.
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.pyenv/bin:\(home)/.pyenv/shims:\(home)/.local/bin:/usr/bin:/bin"
                process.environment = environment
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do { try process.run() } catch { continuation.resume(throwing: Failure.refused("yt-dlp 起不来：\(error.localizedDescription)")); return }
                let said = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let complaint = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                if process.terminationStatus == 0 { continuation.resume(returning: said); return }
                let last = complaint.split(separator: "\n").last.map(String.init) ?? "yt-dlp 失败（\(process.terminationStatus)）"
                // The one failure with a known cure.
                if last.contains("403") || last.lowercased().contains("sign in") || last.contains("nsig") {
                    continuation.resume(throwing: Failure.refused("\(last)\n多半是 yt-dlp 太旧了，网站每隔几个月就让旧版失效。更新一下再试：pip install -U yt-dlp（或 brew upgrade yt-dlp）"))
                } else {
                    continuation.resume(throwing: Failure.refused(last))
                }
            }
        }
    }
}
