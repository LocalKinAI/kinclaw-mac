import AppKit
import AVFoundation
import ImageIO

/// What a live film becomes besides itself (「都做吧，讲给我听和存成视频」, 2026-10-08):
///
/// 讲给我听 — Claude reads the drawing's own code (when each thing appears is written there: MO.seg,
/// ss) and writes a few lines for the moments things appear; the companion's own voice (the voice
/// server's speaker, the same one for every line) says each, and they are laid on one track at their
/// moments. That track is the film's song: it plays in step with the picture, scrubbed and slowed
/// with it, and when it runs past the pictures the last shot holds.
///
/// 存成视频 — drawn frame by frame here, in the same WebKit the person watches it in, with the knobs
/// and the lettering as they left them; 1920×1080, 60 frames a second, H.264, its song or voice under it.
@MainActor
final class LiveOut: ObservableObject {
    static let shared = LiveOut()

    /// Film id → what 讲给我听 is doing.
    @Published private(set) var narrating: [String: String] = [:]
    /// Film id → how far 存成视频 has got (0–1).
    @Published private(set) var exporting: [String: Double] = [:]
    /// Film id → the video it made last.
    @Published private(set) var exported: [String: URL] = [:]
    @Published private(set) var trouble: [String: String] = [:]

    private init() {}

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    // MARK: - 讲给我听

    /// Lines for a film, its voice, and the film reloaded wherever it plays.
    @discardableResult
    func narrate(_ id: String) async throws -> [LiveFilm.Line] {
        guard narrating[id] == nil else { throw Failure.message("正在给它写解说") }
        guard var film = LiveFilm.shared.film(named: id), film.id == id else { throw Failure.message("没有这部活画：\(id)") }
        trouble[id] = nil
        defer { narrating[id] = nil }
        do {
            narrating[id] = "看它画了什么"
            let probe = LivePlayer()
            defer { probe.discard() }
            probe.shelve()
            LiveFilm.load(LiveFilm.Film(id: film.id, title: film.title, film: film.film, base: film.base), into: probe)
            await probe.untilReady(seconds: 40)
            guard probe.ready else { throw Failure.message("它跑不起来：\(probe.errors.first ?? "不知道为什么")") }
            let total = probe.total, eras = probe.eras

            narrating[id] = "写解说词"
            let lines = try await Self.write(film, total: total, eras: eras)
            guard !lines.isEmpty else { throw Failure.message("Claude 没写出解说词") }

            var takes: [(t: Double, buffer: AVAudioPCMBuffer)] = []
            for (index, line) in lines.enumerated() {
                narrating[id] = "念第 \(index + 1)/\(lines.count) 句"
                guard let wav = await TalkingVideo.voice(line.text, voice: nil, description: nil),
                      let buffer = Self.buffer(wav) else {
                    throw Failure.message("语音服务没念出来（盒子面板里的语音服务在不在？）")
                }
                takes.append((line.t, buffer))
            }
            narrating[id] = "拼成一条"
            let (track, placed, end) = try Self.lay(takes)
            let folder = LiveFilm.folder.appendingPathComponent(id)
            try track.write(to: folder.appendingPathComponent("voice.wav"), options: .atomic)
            film.song = "voice.wav"
            film.lines = zip(lines, placed).map { LiveFilm.Line(t: ($1 * 100).rounded() / 100, text: $0.text) }
            film.length = end + 0.6 > total ? ((end + 0.6) * 100).rounded() / 100 : nil
            try LiveFilm.write(film)
            LiveFilm.shared.reload()
            reloadPlayers(film)
            return film.lines ?? []
        } catch {
            trouble[id] = error.localizedDescription
            throw error
        }
    }

    /// Wherever it plays — 活画's window, its card in a conversation — it plays again with its voice.
    private func reloadPlayers(_ film: LiveFilm.Film) {
        if LiveFilm.shared.current?.id == film.id { LiveFilm.load(film, into: LiveFilm.shared.player) }
        if LiveDraw.shared.playing == film.id { LiveDraw.shared.activate(film.id) }
    }

    /// The lines, by Claude when it is here (else the Studio's writer), from the film's own code.
    private static func write(_ film: LiveFilm.Film, total: Double, eras: [LivePlayer.Era]) async throws -> [LiveFilm.Line] {
        let folder = LiveFilm.engine(film)
        var code = (try? String(contentsOf: folder.appendingPathComponent("eras_\(film.film).js"), encoding: .utf8)) ?? ""
        for era in eras {
            let file = folder.appendingPathComponent("scenes/\(era.id).js")
            if let text = try? String(contentsOf: file, encoding: .utf8) { code += "\n\n// ---- scenes/\(era.id).js\n" + text }
        }
        code = String(code.prefix(45_000))
        let chinese = (film.question ?? film.title).unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let system = """
            You write the voice-over for a short animation drawn in code (huashu-art-motion's engine). From its code \
            you can tell what is on screen at every moment: ERAS gives each shot's length, and inside a shot the \
            times in MO.seg / ss / clamp((lt - a) / b) say when each thing starts and ends. Write lines a warm, clear \
            voice says as the picture unfolds — each starting a moment before what it talks about appears, saying \
            what it means rather than reading the labels out. \(chinese ? "In Chinese, about 4.5 characters a second; at most 20 characters a line." : "In the language of the title, about 2.5 words a second; at most 14 words a line.") \
            Two to five lines; a line ends before the next begins; the last may run up to two seconds past the end \
            (the last picture holds). No greeting, no "in this animation", nothing that is not on screen.
            """
        let ask = """
            \(film.question.map { "它回答的问题：\($0)\n" } ?? "")标题：\(film.title)
            全长 \(String(format: "%.1f", total)) 秒；各镜：\(eras.map { String(format: "%@ %.1f–%.1f", $0.id, $0.t0, $0.t1) }.joined(separator: "，"))

            代码：
            \(code)
            """
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["lines": ["type": "array", "items": [
                "type": "object", "properties": ["t": ["type": "number"], "text": ["type": "string"]], "required": ["t", "text"],
            ]]],
            "required": ["lines"],
        ]
        let host: (host: String, model: String)?
        if let claude = ClaudeWriter.host() { host = (claude, ClaudeWriter.model) } else { host = await FilmStudio.writer(claude: true) }
        guard let host, let url = URL(string: host.host + "/api/chat") else { throw Failure.message("没有能写解说的模型（Claude Code 或 Studio 的写手）") }
        let body: [String: Any] = ["model": host.model, "stream": false, "think": false, "format": schema,
                                   "messages": [["role": "system", "content": system], ["role": "user", "content": ask]]]
        var request = URLRequest(url: url, timeoutInterval: 240)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let content = (reply["message"] as? [String: Any])?["content"] as? String,
              let open = content.firstIndex(of: "{"), let close = content.lastIndex(of: "}"),
              let parsed = (try? JSONSerialization.jsonObject(with: Data(content[open...close].utf8))) as? [String: Any],
              let items = parsed["lines"] as? [[String: Any]] else {
            throw Failure.message("解说词没写成")
        }
        return items.compactMap { item in
            guard let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let t = (item["t"] as? Double) ?? (item["t"] as? Int).map(Double.init) ?? 0
            return LiveFilm.Line(t: max(0, min(t, total)), text: text)
        }
        .sorted { $0.t < $1.t }
    }

    /// A WAV from the voice server, as samples.
    nonisolated private static func buffer(_ wav: Data) -> AVAudioPCMBuffer? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("kinclaw-voice-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? wav.write(to: file)) != nil, let audio = try? AVAudioFile(forReading: file),
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)),
              (try? audio.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// The takes laid on one track at their moments — a take that would start before the last one ended
    /// waits for it (a breath between). The track as WAV, where each take landed, and where the voice ends.
    nonisolated private static func lay(_ takes: [(t: Double, buffer: AVAudioPCMBuffer)]) throws -> (Data, [Double], Double) {
        guard let first = takes.first?.buffer else { throw Failure.message("没有声音") }
        let rate = first.format.sampleRate
        var placed: [Double] = [], cursor = 0.0
        for take in takes {
            let start = max(take.t, cursor > 0 ? cursor + 0.2 : 0)
            placed.append(start)
            cursor = start + Double(take.buffer.frameLength) / take.buffer.format.sampleRate
        }
        let count = Int((cursor + 0.3) * rate)
        var samples = [Float](repeating: 0, count: count)
        for (take, start) in zip(takes, placed) {
            guard let channel = take.buffer.floatChannelData?[0] else { continue }
            let offset = Int(start * rate), length = Int(take.buffer.frameLength)
            for i in 0..<length where offset + i < count { samples[offset + i] += channel[i] }
        }
        // 16-bit mono WAV
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; data.append(Data(bytes: &little, count: MemoryLayout<T>.size)) }
        let bytes = UInt32(count * 2)
        data.append(Data("RIFF".utf8)); put(UInt32(36) + bytes); data.append(Data("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        data.append(Data("data".utf8)); put(bytes)
        data.reserveCapacity(data.count + count * 2)
        for sample in samples { put(Int16(max(-1, min(1, sample)) * 32767)) }
        return (data, placed, cursor)
    }

    // MARK: - 存成视频

    /// The film as an MP4 in its folder: drawn frame by frame here, knobs and lettering as given.
    @discardableResult
    func export(_ id: String, knobs: [String: Double] = [:], lettering: Bool = true) async throws -> URL {
        guard exporting[id] == nil else { throw Failure.message("正在存这一部") }
        guard let film = LiveFilm.shared.film(named: id), film.id == id else { throw Failure.message("没有这部活画：\(id)") }
        trouble[id] = nil
        exporting[id] = 0
        defer { exporting[id] = nil }
        do {
            let renderer = LivePlayer()
            defer { renderer.discard() }
            renderer.shelve()
            LiveFilm.load(film, into: renderer)
            await renderer.untilReady(seconds: 60)
            guard renderer.ready else { throw Failure.message("它跑不起来：\(renderer.errors.first ?? "不知道为什么")") }
            for (knob, value) in knobs { renderer.setKnob(knob, value) }
            renderer.setLettering(lettering)

            let fps = 60, width = 1920, height = 1080
            let count = Int((renderer.total * Double(fps)).rounded())
            let folder = LiveFilm.folder.appendingPathComponent(id)
            let stamp = Int(Date().timeIntervalSince1970)
            let picture = folder.appendingPathComponent(".picture-\(stamp).mp4")
            let out = folder.appendingPathComponent("\(TalkingVideo.slug(film.title))-\(stamp).mp4")
            defer { try? FileManager.default.removeItem(at: picture) }

            let writer = try AVAssetWriter(outputURL: picture, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000, AVVideoExpectedSourceFrameRateKey: fps,
                                                  AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            ])
            writer.add(input)
            guard writer.startWriting() else { throw Failure.message("写不了视频：\(writer.error?.localizedDescription ?? "")") }
            writer.startSession(atSourceTime: .zero)
            for index in 0..<count {
                let jpeg = try await renderer.jpeg(at: Double(index) / Double(fps))
                guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.message("第 \(index) 帧读不出来") }
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
                guard let pool = adaptor.pixelBufferPool else { throw Failure.message("视频写不下去：\(writer.error?.localizedDescription ?? "")") }
                var made: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
                guard let buffer = made else { throw Failure.message("没有画布") }
                CVPixelBufferLockBaseAddress(buffer, [])
                let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))) else {
                    throw Failure.message("视频写不下去：\(writer.error?.localizedDescription ?? "")")
                }
                if index % 30 == 0 { exporting[id] = Double(index) / Double(max(1, count)) }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw Failure.message("视频没写完：\(writer.error?.localizedDescription ?? "")") }
            exporting[id] = 1
            if let song = LiveFilm.song(film), FileManager.default.fileExists(atPath: song.path) {
                try await Self.lay(song, under: picture, into: out)
            } else {
                try FileManager.default.moveItem(at: picture, to: out)
            }
            exported[id] = out
            return out
        } catch {
            trouble[id] = error.localizedDescription
            throw error
        }
    }

    /// The picture with the film's song (or voice) under it.
    nonisolated private static func lay(_ song: URL, under picture: URL, into out: URL) async throws {
        let video = AVURLAsset(url: picture), sound = AVURLAsset(url: song)
        guard let pictureTrack = try await video.loadTracks(withMediaType: .video).first,
              let soundTrack = try await sound.loadTracks(withMediaType: .audio).first else {
            throw Failure.message("画面或声音读不出来")
        }
        let length = try await video.load(.duration)
        let soundLength = try await sound.load(.duration)
        let mix = AVMutableComposition()
        guard let v = mix.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let a = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.message("拼不起来")
        }
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: pictureTrack, at: .zero)
        try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, soundLength)), of: soundTrack, at: .zero)
        try? FileManager.default.removeItem(at: out)
        guard let export = AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.message("导不出来")
        }
        export.outputURL = out
        export.outputFileType = .mp4
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in export.exportAsynchronously { done.resume() } }
        guard export.status == .completed else { throw Failure.message("配上声音时失败：\(export.error?.localizedDescription ?? "不知道为什么")") }
    }

    /// The line for the tools.
    func report(_ id: String) -> String {
        if let step = narrating[id] { return "讲给我听：\(step)" }
        if let done = exporting[id] { return String(format: "存成视频：%.0f%%", done * 100) }
        if let trouble = trouble[id] { return "上次的问题：\(trouble)" }
        return exported[id].map { "存好了：\($0.path)" } ?? ""
    }
}
