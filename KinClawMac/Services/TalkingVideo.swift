import AppKit
import AVFoundation
import Foundation
import ImageIO

/// 说话视频: a photograph saying a script in a voice — what HeyGen sells, made on
/// the box. 「找开源啊，用我们的盒子把他们平替了」(2026-10-02).
///
/// The text is spoken sentence by sentence by the box's voices (one of the voice
/// server's speakers, or a voice designed from words), packed into pieces of up
/// to about six seconds, and each piece is filmed from the photograph with its
/// speech as the soundtrack the face must say:
///   - H3: the speech anchored in the clip (AddGuide audio) and the
///     photograph pinned as the first and the last frame, so every piece starts
///     and ends on the same picture and they join without a jump. 9.7 minutes
///     for 6.6 s at 640×640 in the four-step draft; lively — she smiles, blinks,
///     tilts her head.
///   - LTX-2.3 q8 audio-to-video: steadier and calmer; 7 minutes for 4 s.
///   - Ditto (default since 2026-10-04 — 「效果真个很不错啊」; Ant Group, Apache-2.0;
///     kin_ditto_talk.py on the box): the face and head from the voice, the rest of
///     the picture still, in one take at about 6.5 frames a second — ten seconds
///     of speech in a minute, voice included, where H3 takes fifteen.
/// A song instead of words (`song`): its singing voice is separated on the box
/// (Demucs, kin_separate.py — seconds) and moves the face, and the whole song
/// plays under the video — the accompaniment would move the mouth through the
/// intro and the solo (2026-10-04, 「一步到位吧，接进说话视频」).
/// A recording's voice instead (`voiceSample`): every sentence spoken in it by
/// the box's clone (Qwen3-TTS 1.7B Base, 8103) — a photograph and a few seconds of
/// someone talking make that person say anything (2026-10-04).
/// The pieces are cut together over the clean speech. Measured on 2026-10-02 with
/// the companion's portrait: both kept her face through the clip; the voice is
/// the box's own, so the lips follow what is actually said.
@MainActor
final class TalkingVideo: ObservableObject {
    static let shared = TalkingVideo()
    static var root: URL { CompanionArt.folder.appendingPathComponent("talking") }

    struct Job: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var image: String
        var text: String?
        var audio: String?
        var voice: String?
        var voiceDescription: String?
        /// A recording whose voice says the text, and what it says (heard on the box when not given).
        var voiceSample: String?
        var voiceSampleText: String?
        /// A song to sing: its voice drives the face, the whole of it is the soundtrack.
        var song: String?
        /// Ditto: how far the face moves from the photograph's (1 as Ditto drives it;
        /// singing wants more, 1.2–1.4).
        var expression: Double?
        var engine: String
        var quality: String
        var look: String?
        var width: Int
        var height: Int
        var state: String            // speaking | held | filming | joining | done | failed
        var note: String?
        var pieces: [Piece] = []
        var started: Date
        var finished: Date?
        var output: String?

        struct Piece: Codable, Equatable {
            var text: String
            var speech: String       // the piece's speech, 24 kHz mono
            var seconds: Double
            var video: String?
        }

        var folder: URL { URL(fileURLWithPath: image).deletingLastPathComponent() }
        var spoken: Double { pieces.reduce(0) { $0 + $1.seconds } }
    }

    @Published private(set) var jobs: [Job] = []
    private var working: String?

    private init() {
        load()
        // One cut off by the app going away, its speech already made, goes on by itself from the
        // first piece not filmed — as a film does — instead of waiting for talking_video_continue.
        // A piece still rendering on the box is taken up there (ComfyJob), not filmed twice.
        if let cut = jobs.first(where: { $0.state == "failed" && $0.note?.hasPrefix(Self.cutNote) == true && !$0.pieces.isEmpty }) {
            _ = resume(cut.id)
        }
    }

    private static let cutNote = "app 重启时还没做完"

    // MARK: - Asking

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    /// Start one. Everything given is used as written; what is left out is filled
    /// in: the companion's voice, Ditto, the draft, the photograph's own shape.
    func make(image: URL, text: String?, audio: URL?, voice: String?, voiceDescription: String?,
              voiceSample: URL? = nil, voiceSampleText: String? = nil, song: URL? = nil, expression: Double? = nil,
              engine: String?, quality: String?, look: String?, shape: String?, title: String?,
              holdAfterSpeech: Bool) -> Result<Job, Failure> {
        guard working == nil else { return .failure(.message("正在做「\(working!)」，等它做完（talking_video_status）")) }
        guard FileManager.default.fileExists(atPath: image.path) else { return .failure(.message("找不到照片：\(image.path)")) }
        let words = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !words.isEmpty || audio != nil || song != nil else {
            return .failure(.message("要 text（她说什么）、audio（一段录音）或 song（一首歌）"))
        }
        if let song, !FileManager.default.fileExists(atPath: song.path) { return .failure(.message("找不到这首歌：\(song.path)")) }
        if let audio, !FileManager.default.fileExists(atPath: audio.path) { return .failure(.message("找不到录音：\(audio.path)")) }
        if let voiceSample, !FileManager.default.fileExists(atPath: voiceSample.path) {
            return .failure(.message("找不到要克隆的声音：\(voiceSample.path)"))
        }
        let engine = ["ltx", "h3"].contains((engine ?? "").lowercased()) ? engine!.lowercased() : "ditto"
        if let trouble = CompanionArt.unreachableVolume(Self.root) { return .failure(.message(trouble)) }

        let title = title ?? song.map { $0.deletingPathExtension().lastPathComponent }
        let name = Self.slug(title ?? String(words.prefix(16))) + "-" + String(Int(Date().timeIntervalSince1970))
        let folder = Self.root.appendingPathComponent(name)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            return .failure(.message("建不了文件夹：\(error.localizedDescription)"))
        }
        let photo = folder.appendingPathComponent("photo." + (image.pathExtension.isEmpty ? "png" : image.pathExtension.lowercased()))
        try? FileManager.default.copyItem(at: image, to: photo)
        let (width, height) = Self.size(of: photo, shape: shape, engine: engine)
        let job = Job(id: name, title: title ?? String(words.prefix(16)), image: photo.path,
                      text: words.isEmpty ? nil : words, audio: audio?.path, voice: voice, voiceDescription: voiceDescription,
                      voiceSample: voiceSample?.path, voiceSampleText: voiceSampleText,
                      song: song?.path, expression: expression,
                      engine: engine, quality: quality == "full" ? "full" : "draft", look: look,
                      width: width, height: height, state: "speaking", started: Date())
        jobs.insert(job, at: 0)
        save(job)
        working = job.id
        Task { await run(job.id, hold: holdAfterSpeech) }
        return .success(job)
    }

    /// Film one that stopped after its speech.
    func resume(_ id: String) -> Result<Job, Failure> {
        guard working == nil else { return .failure(.message("正在做「\(working!)」，等它做完")) }
        guard let job = find(id) else { return .failure(.message("没有这个说话视频：\(id)")) }
        guard job.state == "held" || job.state == "failed", !job.pieces.isEmpty else {
            return .failure(.message("「\(job.title)」现在是\(job.state)，不用接着拍"))
        }
        working = job.id
        Task { await run(job.id, hold: false) }
        return .success(job)
    }

    func find(_ id: String) -> Job? { jobs.first { $0.id == id || $0.title == id } }

    /// One line each, newest first — the answer to talking_video_status.
    func report(_ id: String? = nil) -> String {
        let shown = id.flatMap(find).map { [$0] } ?? Array(jobs.prefix(5))
        guard !shown.isEmpty else { return "还没做过说话视频（talking_video）" }
        return shown.map(Self.line).joined(separator: "\n")
    }

    static func line(_ job: Job) -> String {
        let took = Int((job.finished ?? Date()).timeIntervalSince(job.started))
        let clock = String(format: "%d:%02d", took / 60, took % 60)
        let head = "「\(job.title)」\(job.id) · \(engineTitle(job)) · \(job.width)×\(job.height)"
        switch job.state {
        case "speaking": return head + (job.song == nil ? "：在配音（\(clock)）" : "：在盒子上分出歌里的人声（\(clock)）")
        case "held":
            let files = job.pieces.map(\.speech).joined(separator: "、")
            return head + "：声音做好了，\(job.pieces.count) 段共 \(String(format: "%.1f", job.spoken)) 秒，停在这里等你听（\(files)）。"
                + "talking_video_continue 开拍，预计 \(estimate(job)) 分钟"
        case "filming":
            let done = job.pieces.filter { $0.video != nil }.count
            return head + "：在拍第 \(min(done + 1, job.pieces.count))/\(job.pieces.count) 段（\(clock)，全部约 \(estimate(job)) 分钟）"
        case "joining": return head + "：在拼成一条（\(clock)）"
        case "done": return head + "：做好了，\(String(format: "%.1f", job.spoken)) 秒，用时 \(clock) → \(job.output ?? "")"
        default: return head + "：没做成（\(clock)）：\(job.note ?? "")"
        }
    }

    static func engineTitle(_ job: Job) -> String {
        switch job.engine {
        case "ltx": return "LTX"
        case "ditto": return "Ditto"
        default: return job.quality == "full" ? "H3 精细" : "H3"
        }
    }

    /// Minutes, from what was measured: H3 draft about 1.5 a second of speech
    /// (9.7 for 6.6 s), full about 3.5 times that; LTX q8 about 1.8; Ditto 25
    /// frames a second of speech at 6.5 a second, and half a minute to load.
    static func estimate(_ job: Job) -> Int {
        let seconds = max(1, job.spoken)
        if job.engine == "ditto" { return Int((seconds * 25 / 6.5 / 60 + 0.5).rounded(.up)) }
        let rate = job.engine == "ltx" ? 1.8 : job.quality == "full" ? 5.2 : 1.5
        return Int((seconds * rate * Double(job.width * job.height) / 409_600).rounded(.up))
    }

    // MARK: - Doing

    private func run(_ id: String, hold: Bool) async {
        defer { working = nil }
        guard var job = find(id) else { return }
        do {
            if job.pieces.isEmpty {
                job.state = "speaking"
                update(job)
                job.pieces = try await speak(job)
                if hold {
                    job.state = "held"
                    update(job)
                    return
                }
            }
            job.state = "filming"
            job.note = nil
            update(job)
            for index in job.pieces.indices where job.pieces[index].video == nil {
                let out = job.folder.appendingPathComponent(String(format: "piece-%02d.mp4", index + 1))
                if job.engine == "ltx" {
                    try await filmLTX(job, job.pieces[index], to: out)
                } else if job.engine == "ditto" {
                    try await filmDitto(job, job.pieces[index], index: index, to: out)
                } else {
                    try await filmH3(job, job.pieces[index], index: index, to: out)
                }
                job.pieces[index].video = out.path
                update(job)
            }
            job.state = "joining"
            update(job)
            let out = job.folder.appendingPathComponent("talk.mp4")
            try await join(job, to: out)
            job.output = out.path
            job.state = "done"
            job.finished = Date()
            update(job)
        } catch {
            job.state = "failed"
            job.note = error.localizedDescription
            job.finished = Date()
            update(job)
        }
    }

    // MARK: Speech

    /// The words, a sentence at a time, packed into pieces of at most 6.4 s —
    /// just under H3's 158 frames — or the recording, cut at its quietest places.
    /// Ditto takes any length: one piece, the whole of it.
    private func speak(_ job: Job) async throws -> [Job.Piece] {
        let whole = job.engine == "ditto"
        var recording = job.audio.map { URL(fileURLWithPath: $0) }
        if job.song != nil { recording = try await vocals(job) }
        if let recording {
            let samples = try Self.read(recording)
            // A song on H3 is cut at H3's own lengths, not at its quiet places: each
            // piece is filmed exactly as long as its voice, so the joined pieces stay
            // on the whole song's beat — padded ones would drift seconds off it.
            if job.song != nil, job.engine == "h3" { return try Self.exact(samples, into: job.folder) }
            guard whole else { return try Self.cut(samples, into: job.folder) }
            let file = job.folder.appendingPathComponent("speech-01.wav")
            try Self.write(samples, to: file)
            return [Job.Piece(text: "", speech: file.path, seconds: Double(samples.count) / Self.rate)]
        }
        let sentences = Self.sentences(job.text ?? "")
        let sample = job.voiceSample == nil ? nil : try await reference(job)
        var made: [(text: String, samples: [Float])] = []
        for (i, sentence) in sentences.enumerated() {
            let spoken = if let sample { await Self.cloned(sentence, like: sample) }
                else { await Self.voice(sentence, voice: job.voice, description: job.voiceDescription) }
            guard let data = spoken else {
                throw Failure.message("第 \(i + 1) 句配不出音：「\(sentence)」——盒子上的"
                                      + (sample == nil ? "语音服务（8101，或旁白 8102）" : "克隆声音（8103）") + "在不在？")
            }
            let file = job.folder.appendingPathComponent(String(format: "line-%02d.wav", i + 1))
            try data.write(to: file)
            made.append((sentence, try Self.read(file)))
        }
        // Pack whole sentences, with a short breath between them.
        let breath = [Float](repeating: 0, count: Int(0.18 * Self.rate))
        var pieces: [Job.Piece] = []
        var text = "", samples: [Float] = []
        func flush() throws {
            guard !samples.isEmpty else { return }
            let file = job.folder.appendingPathComponent(String(format: "speech-%02d.wav", pieces.count + 1))
            try Self.write(samples, to: file)
            pieces.append(Job.Piece(text: text, speech: file.path, seconds: Double(samples.count) / Self.rate))
            text = ""; samples = []
        }
        for line in made {
            let next = samples.isEmpty ? line.samples : samples + breath + line.samples
            if !whole, !samples.isEmpty, Double(next.count) / Self.rate > 6.4 { try flush() }
            samples = samples.isEmpty ? line.samples : samples + breath + line.samples
            text += line.text
        }
        try flush()
        return pieces
    }

    /// A voice id from the voice server (`/synthesize`, the companion's own
    /// request), or a voice designed from words by the film narrator service.
    static func voice(_ text: String, voice: String?, description: String?) async -> Data? {
        if let description, !description.isEmpty {
            let chinese = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            let narrator = FilmStudio.Narrator(speaker: "", language: chinese ? "zh" : "en", instruct: nil, voice: description)
            return await FilmStudio.readVoiceover(text, narrator: narrator)
        }
        let chosen = UserDefaults.standard.string(forKey: "kinclaw.backend.tts") ?? ""
        let base = chosen.isEmpty ? "http://localhost:8001" : chosen.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/synthesize") else { return nil }
        let usual = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? ""
        let speaker = voice ?? ((usual.isEmpty || usual == "auto") ? "vivian" : usual)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "speaker": speaker, "language": "", "speed": 1.0])
        for _ in 0..<2 {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, data.count > 44 {
                return WAVTrim.trim(data)
            }
        }
        return nil
    }

    /// A song's singing voice, separated on the box by Demucs (kin_separate.py in
    /// ~/kin-avatar/demucs): the song goes up through ComfyUI's input folder and
    /// the voice — mono at 24 kHz, all the face needs — comes back through its
    /// output, as the pictures do. 40 s of song in two seconds there.
    private func vocals(_ job: Job) async throws -> URL {
        let base = BoxServices.base(.comfy)
        guard await BoxServices.shared.ensure(.comfy) else { throw Failure.message("盒子上的 ComfyUI 不在（歌从它那里传上去）") }
        let song = URL(fileURLWithPath: job.song ?? "")
        let kind = song.pathExtension.isEmpty ? "wav" : song.pathExtension.lowercased()
        let uploaded = try await FilmStudio.upload(song, as: "kinclaw-talking-\(job.id)-song.\(kind)", to: base)
        let stems = "audio/kinclaw-talking-\(job.id)-stems"
        let log = "$HOME/kin-avatar/logs/talking-separate.log"
        let command = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; mkdir -p $HOME/kin-avatar/logs; "
            + "cd $HOME/kin-avatar/demucs && PYTORCH_ENABLE_MPS_FALLBACK=1 .venv/bin/python kin_separate.py "
            + "\"$HOME/ComfyUI/input/\(uploaded)\" \"$HOME/ComfyUI/output/\(stems)\" > \(log) 2>&1 "
            + "&& ffmpeg -v error -y -i \"$HOME/ComfyUI/output/\(stems)/vocals.wav\" -ac 1 -ar 24000 \"$HOME/ComfyUI/output/\(stems)/vocals-24k.wav\" "
            + "|| { tail -6 \(log); exit 1; }"
        let (status, said) = await BoxServices.run(command)
        guard status == 0 else {
            throw Failure.message("分不出歌里的人声（盒子上 ~/kin-avatar/demucs）：" + said.suffix(400))
        }
        var parts = URLComponents(string: base + "/view")
        parts?.queryItems = [URLQueryItem(name: "filename", value: "vocals-24k.wav"), URLQueryItem(name: "subfolder", value: stems),
                             URLQueryItem(name: "type", value: "output")]
        guard let view = parts?.url, let (bytes, _) = try? await URLSession.shared.data(from: view), bytes.count > 1000 else {
            throw Failure.message("人声分好了，取不回来：盒子上 ~/ComfyUI/output/\(stems)/vocals.wav")
        }
        let file = job.folder.appendingPathComponent("vocals.wav")
        try bytes.write(to: file)
        return file
    }

    /// The recording to clone from, as the clone wants it: at most ten seconds
    /// (it works from three to twelve) and what is said in them — as given when
    /// the whole recording is kept, else heard by the box's Qwen3-ASR.
    private func reference(_ job: Job) async throws -> (audio: String, text: String) {
        let samples = try Self.read(URL(fileURLWithPath: job.voiceSample ?? ""))
        guard samples.count >= Int(3 * Self.rate) else { throw Failure.message("要克隆的声音太短：至少 3 秒") }
        let kept = samples.count > Int(12 * Self.rate) ? Array(samples.prefix(Int(10 * Self.rate))) : samples
        let file = job.folder.appendingPathComponent("voice-sample.wav")
        try Self.write(kept, to: file)
        var text = kept.count == samples.count ? (job.voiceSampleText ?? "") : ""
        if text.isEmpty { text = await Self.hear(file) ?? "" }
        return (try Data(contentsOf: file).base64EncodedString(), text)
    }

    /// One sentence in the recording's voice. The language is the server's to
    /// tell from the text.
    private static func cloned(_ text: String, like sample: (audio: String, text: String)) async -> Data? {
        guard await BoxServices.shared.ensure(.clone),
              let url = URL(string: BoxServices.base(.clone) + "/synthesize") else { return nil }
        var body: [String: Any] = ["text": text, "speed": 1.0, "reference_audio": sample.audio]
        if !sample.text.isEmpty { body["reference_text"] = sample.text }
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        for _ in 0..<2 {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, data.count > 44 {
                return WAVTrim.trim(data)
            }
        }
        return nil
    }

    /// What a recording says, by the box's Qwen3-ASR (8100, beside the clone).
    private static func hear(_ file: URL) async -> String? {
        guard var parts = URLComponents(string: BoxServices.base(.clone)), let audio = try? Data(contentsOf: file) else { return nil }
        parts.port = 8100
        parts.path = "/transcribe"
        guard let url = parts.url else { return nil }
        let boundary = "kinclaw-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"sample.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (answer["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = [], current = ""
        for ch in text {
            if ch == "\n" { if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }; current = ""; continue }
            current.append(ch)
            if "。！？!?；;…".contains(ch) || (ch == "." && current.count > 12) {
                out.append(current); current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: Filming

    private func filmH3(_ job: Job, _ piece: Job.Piece, index: Int, to out: URL) async throws {
        let base = BoxServices.base(.comfy)
        guard await BoxServices.shared.ensure(.comfy) else { throw Failure.message("盒子上的 ComfyUI 不在") }
        let photo = try await FilmStudio.upload(URL(fileURLWithPath: job.image), as: "kinclaw-talking-\(job.id).png", to: base)
        let speech = try await FilmStudio.upload(URL(fileURLWithPath: piece.speech), as: "kinclaw-talking-\(job.id)-\(index + 1).wav", to: base)
        let full = job.quality == "full"
        // Speech gets a breath at the end; a song's piece is already an H3 length.
        let frames = FilmStudio.h3Frames(job.song != nil ? piece.seconds : piece.seconds + 0.25)
        let behaviour = job.look.map { "\($0). " } ?? ""
        // Singing, H3 moves the whole body — and, told only "static camera", let her
        // drift half out of the frame and invented the room behind her. Held by the
        // photograph in the middle of the piece too and told so, she sings — eyes
        // closing on the long notes, head and hair moving — but still drifts: on every
        // frame (Vision's face boxes) her face crossed 40 % of the frame within a piece,
        // where Ditto's stays within 4 % (2026-10-08; 「h3那个镜头不要跑」 is not met yet).
        let singing = job.song != nil
        let prompt = singing
            ? behaviour + (job.look == nil ? "She stays in the center of the frame, facing the camera; only her head tilts and her "
                + "shoulders sway a little with the music, her hair moves softly, her eyes close gently on the long notes and "
                + "open again. " : "")
                + "The person in the picture sings to the camera with feeling, lips moving with the singing, breathing between "
                + "the lines. Locked-off static camera on a tripod: the framing never changes, she never leaves the center, the "
                + "background stays exactly the same."
            : behaviour + "The person in the picture looks into the camera and says: \"\(piece.text)\". "
                + "Natural expressions that follow the words, blinking, small head movements, lips moving with the speech. Static camera."
        func n(_ type: String, _ inputs: [String: Any]) -> [String: Any] { ["class_type": type, "inputs": inputs] }
        var graph: [String: Any] = [
            "1": n("UNETLoader", ["unet_name": "minimax_h3_ref2va_pruned_int8_convrot.safetensors", "weight_dtype": "default"]),
            "2": n("CLIPLoader", ["clip_name": "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors", "type": "minimax", "device": "default"]),
            "3": n("VAELoader", ["vae_name": "minimax_h3_video_vae_fp16.safetensors"]),
            "4": n("VAELoader", ["vae_name": "minimax_h3_audio_vae_fp32.safetensors"]),
            "100": n("LoadImage", ["image": photo]),
            "101": n("LoadAudio", ["audio": speech]),
            "6": n("MiniMaxH3ReferenceToVideo", ["prompt": prompt, "clip": ["2", 0], "vae": ["3", 0], "audio_vae": ["4", 0],
                                                 "width": job.width, "height": job.height, "length": frames,
                                                 "ref_image_size": "match", "ref_images.ref_image_0": ["100", 0]]),
            // The words at the start, and the photograph first and last.
            "300": n("MiniMaxH3AddGuide", ["positive": ["6", 0], "latent": ["6", 1], "vae": ["3", 0], "audio_vae": ["4", 0],
                                           "image": ["100", 0], "audio": ["101", 0], "frame_idx": 0]),
            "301": n("MiniMaxH3AddGuide", ["positive": [singing ? "302" : "300", 0], "latent": ["6", 1], "vae": ["3", 0], "audio_vae": ["4", 0],
                                           "image": ["100", 0], "frame_idx": -1]),
            "7": n("RandomNoise", ["noise_seed": 7 + index]),
            "8": n("KSamplerSelect", ["sampler_name": "res_multistep"]),
            "12": n("VAEDecode", ["vae": ["3", 0], "samples": ["11", 0]]),
            "13": n("VAEDecodeAudio", ["vae": ["4", 0], "samples": ["11", 0]]),
            "14": n("CreateVideo", ["images": ["12", 0], "audio": ["13", 0], "fps": 24.0]),
            "15": n("SaveVideo", ["video": ["14", 0], "filename_prefix": "video/kinclaw-talking", "format": "auto", "codec": "auto"]),
        ]
        if singing {
            graph["302"] = n("MiniMaxH3AddGuide", ["positive": ["300", 0], "latent": ["6", 1], "vae": ["3", 0], "audio_vae": ["4", 0],
                                                   "image": ["100", 0], "frame_idx": frames / 2])
        }
        var model: [Any] = ["1", 0]
        if !full {
            graph["5"] = n("LoraLoaderModelOnly", ["lora_name": "minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors",
                                                    "strength_model": 1.0, "model": ["1", 0]])
            model = ["5", 0]
        }
        if await FilmStudio.boxHas("KinClawPytorchAttention", at: base) {
            graph["24"] = n("KinClawPytorchAttention", ["model": model])
            model = ["24", 0]
        }
        graph["9"] = n("BasicScheduler", ["scheduler": "simple", "steps": full ? 20 : 4, "denoise": 1.0, "model": model])
        graph["10"] = n("BasicGuider", ["model": model, "conditioning": ["301", 0]])
        graph["11"] = n("SamplerCustomAdvanced", ["noise": ["7", 0], "guider": ["10", 0], "sampler": ["8", 0],
                                                  "sigmas": ["9", 0], "latent_image": ["6", 1]])
        let what = "说话视频 \(index + 1)/\(job.pieces.count)"
        let video = try await FilmStudio.comfyResult(graph, node: "15", base: base, what: what,
                                                     deadline: full ? 7200 : 3600, client: "kinclaw-talking")
        try? FileManager.default.removeItem(at: out)
        try video.write(to: out)
    }

    private func filmLTX(_ job: Job, _ piece: Job.Piece, to out: URL) async throws {
        let behaviour = job.look.map { "\($0). " } ?? ""
        let prompt = behaviour + (job.song != nil
            ? "The person in the picture sings to the camera with feeling. "
            : "The person in the picture talks to the camera, saying: \"\(piece.text)\". ")
            + "Natural expressions, blinking, small head movements. Static camera."
        // LTX wants 8k+1 frames at 24 fps; the speech decides how many.
        let frames = max(25, Int((piece.seconds * 24 / 8).rounded(.up)) * 8 + 1)
        try await DiffuserClient.shared.generateVideo(prompt: prompt, to: out, width: job.width, height: job.height,
                                                      seed: 7, from: URL(fileURLWithPath: job.image),
                                                      speech: URL(fileURLWithPath: piece.speech), frames: frames,
                                                      hq: true, timeout: 3600)
    }

    /// Ditto on the box, through kin_ditto_talk.py in its own venv. The photograph
    /// (cut to the job's size: Ditto draws at the size it is given) and the speech
    /// go up through ComfyUI's input folder, and the video comes back through its
    /// output, as everything else made there does.
    private func filmDitto(_ job: Job, _ piece: Job.Piece, index: Int, to out: URL) async throws {
        let base = BoxServices.base(.comfy)
        guard await BoxServices.shared.ensure(.comfy) else { throw Failure.message("盒子上的 ComfyUI 不在") }
        let fitted = job.folder.appendingPathComponent("photo-\(job.width)x\(job.height).png")
        try Self.fit(URL(fileURLWithPath: job.image), width: job.width, height: job.height, to: fitted)
        let photo = try await FilmStudio.upload(fitted, as: "kinclaw-talking-\(job.id).png", to: base)
        let speech = try await FilmStudio.upload(URL(fileURLWithPath: piece.speech), as: "kinclaw-talking-\(job.id)-\(index + 1).wav", to: base)
        let name = "kinclaw-talking-\(job.id)-\(index + 1)-ditto.mp4"
        let log = "$HOME/kin-avatar/logs/talking-ditto.log"
        let command = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; mkdir -p $HOME/kin-avatar/logs; "
            + "cd $HOME/kin-avatar/ditto/ditto-talkinghead && .venv312/bin/python kin_ditto_talk.py "
            + "./checkpoints/ditto_cfg/v0.4_hubert_cfg_pytorch.pkl \"$HOME/ComfyUI/input/\(photo)\" \"$HOME/ComfyUI/input/\(speech)\" "
            + "\"$HOME/ComfyUI/output/video/\(name)\""
            + (job.expression.map { $0 == 1 ? "" : String(format: " --expression %.2f", min(2, max(0.3, $0))) } ?? "")
            + " > \(log) 2>&1 || { tail -6 \(log); exit 1; }"
        let (status, said) = await BoxServices.run(command)
        guard status == 0 else { throw Failure.message("Ditto 没拍成：" + said.suffix(400)) }
        var parts = URLComponents(string: base + "/view")
        parts?.queryItems = [URLQueryItem(name: "filename", value: name), URLQueryItem(name: "subfolder", value: "video"),
                             URLQueryItem(name: "type", value: "output")]
        guard let view = parts?.url, let (bytes, _) = try? await URLSession.shared.data(from: view), bytes.count > 1000 else {
            throw Failure.message("Ditto 拍好了，取不回来：盒子上 ~/ComfyUI/output/video/\(name)")
        }
        try? FileManager.default.removeItem(at: out)
        try bytes.write(to: out)
    }

    // MARK: Joining

    /// The pieces one after another over the clean speech. H3 pieces run whole —
    /// each ends on the photograph, which is what makes the joins seamless — so
    /// each piece's speech is padded with silence to its clip; LTX and Ditto
    /// pieces are cut to their speech.
    private func join(_ job: Job, to out: URL) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.message("拼不起来") }
        var at = CMTime.zero
        var soundtrack: [Float] = []
        for piece in job.pieces {
            guard let path = piece.video else { throw Failure.message("有一段没拍出来") }
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.message("\(path) 里没有画面") }
            let length = try await asset.load(.duration)
            let keep = job.engine != "h3" ? CMTimeMinimum(length, CMTime(seconds: piece.seconds + 0.1, preferredTimescale: 600)) : length
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: keep), of: source, at: at)
            if at == .zero { videoTrack.preferredTransform = try await source.load(.preferredTransform) }
            at = at + keep
            var speech = try Self.read(URL(fileURLWithPath: piece.speech))
            let room = Int(keep.seconds * Self.rate)
            if speech.count < room { speech += [Float](repeating: 0, count: room - speech.count) }
            soundtrack += speech.prefix(room)
        }
        let track = job.folder.appendingPathComponent("soundtrack.wav")
        if let song = job.song {
            // The whole song under the face its voice moved.
            try FilmStudio.copyAudio(URL(fileURLWithPath: song), to: track)
        } else {
            try Self.write(soundtrack, to: track)
        }
        let sound = AVURLAsset(url: track)
        if let source = try await sound.loadTracks(withMediaType: .audio).first {
            let length = try await sound.load(.duration)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, at)), of: source, at: .zero)
        }
        try? FileManager.default.removeItem(at: out)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.message("导不出来")
        }
        // A song ends where the song ends: the last piece's padding is cut off.
        if job.song != nil, let source = try? await AVURLAsset(url: track).load(.duration), source < at {
            export.timeRange = CMTimeRange(start: .zero, duration: source)
        }
        export.outputURL = out
        export.outputFileType = .mp4
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in export.exportAsynchronously { done.resume() } }
        guard export.status == .completed else {
            throw Failure.message("导出失败：\(export.error?.localizedDescription ?? "不知道为什么")")
        }
    }

    // MARK: - Sound files

    static let rate = 24_000.0

    /// Any audio file as mono float samples at 24 kHz.
    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: input)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { return [] }
        converter.downmix = true
        let capacity = AVAudioFrameCount(Double(input.frameLength) * rate / source.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard let channel = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    /// 16-bit mono WAV at 24 kHz.
    static func write(_ samples: [Float], to url: URL) throws {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-1, min(1, s)) * 32767).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        let r = UInt32(rate)
        header.append(contentsOf: Array("RIFF".utf8)); put32(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1); put32(r); put32(r * 2); put16(2); put16(16)
        header.append(contentsOf: Array("data".utf8)); put32(UInt32(pcm.count))
        try (header + pcm).write(to: url)
    }

    /// A recording cut into pieces of exactly 158 frames (H3's 17k + 5, 6.58 s),
    /// the last one padded with silence to the next length H3 takes.
    static func exact(_ samples: [Float], into folder: URL) throws -> [Job.Piece] {
        let step = Int(158.0 / 24 * rate)
        var pieces: [Job.Piece] = [], start = 0
        while start < samples.count {
            var piece = Array(samples[start..<min(samples.count, start + step)])
            let frames = FilmStudio.h3Frames(Double(piece.count) / rate)
            piece += [Float](repeating: 0, count: max(0, Int(Double(frames) / 24 * rate) - piece.count))
            let file = folder.appendingPathComponent(String(format: "speech-%02d.wav", pieces.count + 1))
            try write(piece, to: file)
            pieces.append(Job.Piece(text: "", speech: file.path, seconds: Double(frames) / 24))
            start += step
        }
        return pieces
    }

    /// A recording cut into pieces of about six seconds at its quietest moments.
    static func cut(_ samples: [Float], into folder: URL) throws -> [Job.Piece] {
        let target = Int(6.0 * rate), window = Int(0.1 * rate)
        var pieces: [Job.Piece] = [], start = 0
        while start < samples.count {
            var end = min(samples.count, start + target)
            if samples.count - start > Int(6.6 * rate) {
                // The quietest 100 ms between 4.5 and 6.4 s in.
                var best = end, quietest = Float.greatestFiniteMagnitude
                var at = start + Int(4.5 * rate)
                while at + window < min(samples.count, start + Int(6.4 * rate)) {
                    let energy = samples[at..<(at + window)].reduce(0) { $0 + $1 * $1 }
                    if energy < quietest { quietest = energy; best = at + window / 2 }
                    at += window / 2
                }
                end = best
            } else {
                end = samples.count
            }
            let file = folder.appendingPathComponent(String(format: "speech-%02d.wav", pieces.count + 1))
            try write(Array(samples[start..<end]), to: file)
            pieces.append(Job.Piece(text: "", speech: file.path, seconds: Double(end - start) / rate))
            start = end
        }
        return pieces
    }

    // MARK: - Small things

    /// H3 at about 0.41 MP in the photograph's shape (or the one asked for);
    /// LTX the same, both in multiples of 32.
    static func size(of photo: URL, shape: String?, engine: String) -> (Int, Int) {
        var aspect = 1.0
        if let image = NSImage(contentsOf: photo), image.size.height > 0 { aspect = image.size.width / image.size.height }
        switch shape {
        case "square": aspect = 1
        case "portrait": aspect = 9.0 / 16
        case "landscape": aspect = 16.0 / 9
        default: break
        }
        let area = 409_600.0
        let height = (area / aspect).squareRoot()
        let round = { (v: Double) in max(256, Int((v / 32).rounded()) * 32) }
        return (round(height * aspect), round(height))
    }

    /// The photograph filling width × height (cut at the sides or top and bottom
    /// if its shape differs), the right way up, as a PNG.
    static func fit(_ photo: URL, width: Int, height: Int, to out: URL) throws {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 8192]
        guard let source = CGImageSourceCreateWithURL(photo as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.message("照片读不出来：\(photo.path)") }
        let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let w = Double(image.width) * scale, h = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
        guard let fitted = context.makeImage(),
              let target = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else {
            throw Failure.message("照片缩不了")
        }
        CGImageDestinationAddImage(target, fitted, nil)
        guard CGImageDestinationFinalize(target) else { throw Failure.message("照片存不下：\(out.path)") }
    }

    static func slug(_ text: String) -> String {
        let kept = text.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(kept).split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "talk" : String(joined.prefix(24))
    }

    private func update(_ job: Job) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index] = job }
        save(job)
    }

    private func save(_ job: Job) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(job) { try? data.write(to: job.folder.appendingPathComponent("job.json")) }
    }

    /// What is on disk, so a relaunch still knows its jobs; one that was
    /// running when the app went away is marked so.
    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        jobs = folders.compactMap { folder -> Job? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("job.json")),
                  var job = try? decoder.decode(Job.self, from: data) else { return nil }
            if ["speaking", "filming", "joining"].contains(job.state) {
                job.state = "failed"
                job.note = job.pieces.isEmpty ? Self.cutNote + "（说的那步被打断了，要重新做）"
                                              : Self.cutNote + "：接着拍没拍完的那几段"
            }
            return job
        }.sorted { $0.started > $1.started }
    }
}
