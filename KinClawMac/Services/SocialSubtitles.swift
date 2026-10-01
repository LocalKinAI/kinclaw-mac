import AVFoundation
import Foundation

/// Easel's auto-subtitle and subtitle-translate, on this Mac: batch two of
/// Jacky's 「开干吧」 (2026-09-30).
///
/// mlx_whisper (the medium model, already in this Mac's Hugging Face cache —
/// nothing is fetched) hears the video. Told the script when there is one, it
/// gets the names right: on 米迦勒's narration it heard 米加勒, 生骨 and 生胖的日子
/// without it, and every word right with it. The words' own times cut what it
/// heard into lines a phone can read; the agent reads them back and corrects
/// them; ffmpeg's libass burns them in. A second language under each line is
/// the agent's own translation — subtitle-translate, done by the one who
/// writes the post.
enum SocialSubtitles {
    struct Line: Codable, Equatable {
        var start: Double
        var end: Double
        var text: String
        /// The translation, shown smaller under `text`.
        var second: String?
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    static let model = "mlx-community/whisper-medium-mlx"

    @MainActor static var folder: URL { SocialStudio.root.appendingPathComponent("subtitles") }

    // MARK: Hearing

    /// What the video says, as lines of at most `longest` characters (16 for
    /// Chinese, 42 for anything else), kept in `into`/lines.json with what was
    /// heard word by word beside it (heard.json).
    static func hear(_ video: URL, language: String?, script: String?, longest: Int?, into folder: URL) async throws -> [Line] {
        guard let whisper = locate("mlx_whisper", pyenv: true) else {
            throw Failure.message("这台 Mac 上没找到 mlx_whisper（pip install mlx-whisper）")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var arguments = [video.path, "--model", model, "--output-format", "json", "--word-timestamps", "True",
                         "--verbose", "False", "--output-dir", folder.path, "--output-name", "heard"]
        let tongue = language?.trimmingCharacters(in: .whitespaces).lowercased()
        if let tongue, !tongue.isEmpty, tongue != "auto" { arguments += ["--language", tongue == "中文" ? "zh" : tongue] }
        // Whisper takes its prompt as the text that came before: the script
        // there makes it spell the names as the script does, and a Chinese one
        // in 简体 keeps it from writing 繁體.
        let prompt = [tongue == "zh" || tongue == "中文" ? "以下是普通话。" : "", script ?? ""].joined()
        if !prompt.isEmpty { arguments += ["--initial-prompt", String(prompt.prefix(600))] }
        _ = try await run(whisper, arguments, environment: ["HF_HUB_OFFLINE": "1"])
        let heard = folder.appendingPathComponent("heard.json")
        guard let data = try? Data(contentsOf: heard),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let segments = json["segments"] as? [[String: Any]] else {
            throw Failure.message("mlx_whisper 没留下 heard.json")
        }
        let spoken = (json["language"] as? String) ?? tongue ?? ""
        let chinese = spoken.hasPrefix("zh") || spoken == "yue"
        var words: [(start: Double, end: Double, text: String)] = []
        for segment in segments {
            let found = (segment["words"] as? [[String: Any]] ?? []).compactMap { word -> (Double, Double, String)? in
                guard let start = word["start"] as? Double, let end = word["end"] as? Double, let text = word["word"] as? String else { return nil }
                return (start, end, text)
            }
            if found.isEmpty, let start = segment["start"] as? Double, let end = segment["end"] as? Double, let text = segment["text"] as? String {
                words.append((start, end, text))
            } else {
                words += found
            }
        }
        if chinese { words = words.map { ($0.start, $0.end, simplified($0.text)) } }
        let lines = cut(words, longest: longest ?? (chinese ? 16 : 42), chinese: chinese)
        try save(lines, in: folder)
        return lines
    }

    static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform(rawValue: "Hant-Hans"), reverse: false) ?? text
    }

    private static let stops: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "…"]
    private static let pauses: Set<Character> = ["，", ",", "、", "：", ":", "—"]

    /// Words into lines: a line ends at the end of a sentence, at a pause once
    /// it is half full, before a silence of 0.6 s, and before it would pass
    /// `longest`. Chinese lines lose their punctuation, as Chinese subtitles
    /// do: a pause inside a line becomes a space.
    static func cut(_ words: [(start: Double, end: Double, text: String)], longest: Int, chinese: Bool) -> [Line] {
        var lines: [Line] = []
        var current: [(start: Double, end: Double, text: String)] = []
        func length(_ text: String) -> Int { text.filter { !stops.contains($0) && !pauses.contains($0) && !$0.isWhitespace }.count }
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            var text = current.map(\.text).joined()
            if chinese {
                text = String(text.map { pauses.contains($0) || stops.contains($0) ? " " : $0 })
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            }
            text = text.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lines.append(Line(start: first.start, end: last.end, text: text)) }
            current = []
        }
        for word in words {
            let piece = word.text
            if let last = current.last,
               word.start - last.end > 0.6 || length(current.map(\.text).joined() + piece) > longest {
                flush()
            }
            current.append(word)
            let said = current.map(\.text).joined()
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if let end = trimmed.last {
                if stops.contains(end) || (pauses.contains(end) && length(said) * 2 >= longest) { flush() }
            }
        }
        flush()
        // Held long enough to read (0.8 s), never over the next line.
        for index in lines.indices {
            let next = index + 1 < lines.count ? lines[index + 1].start : .infinity
            lines[index].end = min(max(lines[index].end, lines[index].start + 0.8), next)
        }
        return lines
    }

    static func save(_ lines: [Line], in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(lines).write(to: folder.appendingPathComponent("lines.json"))
        try srt(lines).write(to: folder.appendingPathComponent("lines.srt"), atomically: true, encoding: .utf8)
    }

    static func load(from folder: URL) -> [Line]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("lines.json")) else { return nil }
        return try? JSONDecoder().decode([Line].self, from: data)
    }

    // MARK: Writing

    static func srt(_ lines: [Line]) -> String {
        func stamp(_ seconds: Double) -> String {
            let ms = Int((seconds * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return lines.enumerated().map { index, line in
            "\(index + 1)\n\(stamp(line.start)) --> \(stamp(line.end))\n\(line.text)" + (line.second.map { "\n\($0)" } ?? "") + "\n"
        }.joined(separator: "\n")
    }

    struct Style {
        /// Font size in pixels of the video; 0 = from its size.
        var size: Double = 0
        /// Distance from the bottom, as a fraction of the height; 0 = from its shape.
        var lift: Double = 0
        var font = "PingFang SC"
    }

    /// The lines as an ASS script sized to the video, so a size is a pixel:
    /// white on a dark outline, the translation under it at 70 %.
    static func ass(_ lines: [Line], width: Int, height: Int, style: Style) -> String {
        let tall = height > width
        // A phone's feed puts its own buttons and caption over the bottom
        // fifth of a vertical video; a wide one keeps only its edge.
        let lift = style.lift > 0 ? style.lift : (tall ? 0.2 : 0.07)
        let size = style.size > 0 ? style.size : Double(min(width, height)) * (tall ? 0.058 : 0.052)
        let outline = max(2, size / 16)
        func stamp(_ seconds: Double) -> String {
            let cs = Int((seconds * 100).rounded())
            return String(format: "%d:%02d:%02d.%02d", cs / 360_000, cs / 6000 % 60, cs / 100 % 60, cs % 100)
        }
        func clean(_ text: String) -> String {
            text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
        }
        let events = lines.map { line -> String in
            var text = clean(line.text)
            if let second = line.second, !second.isEmpty { text += "\\N{\\fs\(Int(size * 0.7))}" + clean(second) }
            return "Dialogue: 0,\(stamp(line.start)),\(stamp(line.end)),Main,,0,0,0,,\(text)"
        }
        return """
            [Script Info]
            ScriptType: v4.00+
            PlayResX: \(width)
            PlayResY: \(height)
            WrapStyle: 0
            ScaledBorderAndShadow: yes

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
            Style: Main,\(style.font),\(Int(size)),&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,\(String(format: "%.1f", outline)),0,2,\(width / 12),\(width / 12),\(Int(Double(height) * lift)),1

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            \(events.joined(separator: "\n"))

            """
    }

    /// Burn `lines` into a copy of `video`: `into`/<name>.mp4, the picture
    /// re-encoded (H.264, CRF 18), the sound as it was.
    static func burn(_ video: URL, lines: [Line], style: Style, into folder: URL, name: String) async throws -> URL {
        guard let ffmpeg = locate("ffmpeg", pyenv: false) else { throw Failure.message("没找到 ffmpeg（brew install ffmpeg）") }
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.message("这个文件里没有画面：\(video.path)") }
        let (natural, turn) = try await track.load(.naturalSize, .preferredTransform)
        let shown = natural.applying(turn)
        let (width, height) = (Int(abs(shown.width)), Int(abs(shown.height)))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try save(lines, in: folder)
        let script = folder.appendingPathComponent("lines.ass")
        try ass(lines, width: width, height: height, style: style).write(to: script, atomically: true, encoding: .utf8)
        let out = folder.appendingPathComponent(name + ".mp4")
        // libass reads the filter's own syntax: a path's ':' ',' '\' and quotes escaped.
        let path = script.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: ",", with: "\\,")
        _ = try await run(ffmpeg, ["-v", "error", "-y", "-i", video.path, "-vf", "subtitles=\(path)",
                                   "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p",
                                   "-c:a", "copy", "-movflags", "+faststart", out.path])
        guard FileManager.default.fileExists(atPath: out.path) else { throw Failure.message("ffmpeg 没写出 \(out.lastPathComponent)") }
        return out
    }

    /// One frame of `video` at `second`, for looking at a line as it is shown.
    static func still(_ video: URL, at second: Double, to file: URL) async throws {
        guard let ffmpeg = locate("ffmpeg", pyenv: false) else { throw Failure.message("没找到 ffmpeg") }
        _ = try await run(ffmpeg, ["-v", "error", "-y", "-ss", String(format: "%.2f", second), "-i", video.path,
                                   "-frames:v", "1", "-vf", "scale='min(1080,iw)':-2", file.path])
    }

    // MARK: Running things

    /// A tool by name where an app launched from the Dock can find it: Homebrew,
    /// ~/.local/bin, and — for a Python one — every pyenv version's bin.
    static func locate(_ name: String, pyenv: Bool) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var places = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
        if pyenv {
            let versions = "\(home)/.pyenv/versions"
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: versions)) ?? []).sorted(by: >)
            places = names.map { "\(versions)/\($0)/bin" } + places
        }
        return places.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Run a tool to its end. Its output goes to files, not pipes: ffmpeg and a
    /// progress bar can say more than a pipe holds, and a full pipe stops the
    /// program that is writing to it.
    static func run(_ tool: String, _ arguments: [String], environment extra: [String: String] = [:]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kinclaw-subtitles-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                let outFile = scratch.appendingPathComponent("out"), errFile = scratch.appendingPathComponent("err")
                FileManager.default.createFile(atPath: outFile.path, contents: nil)
                FileManager.default.createFile(atPath: errFile.path, contents: nil)
                defer { try? FileManager.default.removeItem(at: scratch) }
                guard let out = try? FileHandle(forWritingTo: outFile), let err = try? FileHandle(forWritingTo: errFile) else {
                    continuation.resume(throwing: Failure.message("临时文件写不了")); return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:/usr/bin:/bin"
                environment.merge(extra) { $1 }
                process.environment = environment
                process.standardOutput = out
                process.standardError = err
                do { try process.run() } catch {
                    continuation.resume(throwing: Failure.message("\((tool as NSString).lastPathComponent) 起不来：\(error.localizedDescription)")); return
                }
                process.waitUntilExit()
                try? out.close(); try? err.close()
                let said = (try? String(contentsOf: outFile, encoding: .utf8)) ?? ""
                if process.terminationStatus == 0 { continuation.resume(returning: said); return }
                let complaint = ((try? String(contentsOf: errFile, encoding: .utf8)) ?? "")
                    .split(whereSeparator: \.isNewline).suffix(3).joined(separator: " / ")
                continuation.resume(throwing: Failure.message("\((tool as NSString).lastPathComponent) 失败（\(process.terminationStatus)）：\(complaint.suffix(400))"))
            }
        }
    }
}
