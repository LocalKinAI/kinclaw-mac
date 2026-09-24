import AVFoundation
import Foundation

/// What a film sounds like besides its own shots: who tells it, and the music
/// under it.
///
/// Until now the voice-over was read by her voice — the companion's, bright
/// and young, over the feeding of the five thousand — and there was no music
/// at all: four clips of wind and water and a sentence each. The box's
/// kin audio has both. Its voice server takes a speaker and an `instruct`
/// (a way of speaking, in words: "用低沉、庄重、缓慢的语气"), and it has
/// MusicGen. So each film is given a narrator and a score once, by the same
/// writer that wrote its shots, from what the film is about.
extension FilmStudio {
    /// Who reads the voice-over, and how.
    struct Narrator: Codable, Equatable {
        var speaker: String
        var language: String?
        var instruct: String?
        /// A voice made from words, for the film narrator service (a voice-
        /// design model): "中年男性纪录片旁白，嗓音浑厚温暖……". When set, it is
        /// the whole instruction and `speaker` is not used.
        var voice: String? = nil
    }

    static let musicKey = "kinclaw.film.music"
    /// "minimax3" (MiniMax Music 3 through ComfyUI on the box: stereo, up to
    /// five minutes, a structured description) or "musicgen" (kin audio).
    static let musicEngineKey = "kinclaw.film.music.engine"
    static var musicEngine: String { UserDefaults.standard.string(forKey: musicEngineKey) ?? "minimax3" }
    static var musicOn: Bool { UserDefaults.standard.object(forKey: musicKey) as? Bool ?? true }
    /// MusicGen writes at most thirty seconds; a longer film loops it.
    static let musicModel = "musicgen:medium"

    struct Voice { let id: String; let name: String; let language: String; let gender: String }

    /// The voices the box's TTS server has, as it describes them.
    static func voices() async -> [Voice] {
        let chosen = UserDefaults.standard.string(forKey: "kinclaw.backend.tts") ?? ""
        let base = chosen.isEmpty ? "http://localhost:8001" : chosen.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/voices"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return (object["voices"] as? [[String: Any]] ?? []).compactMap { v in
            guard let id = v["id"] as? String else { return nil }
            return Voice(id: id, name: v["name"] as? String ?? id, language: v["language"] as? String ?? "",
                         gender: v["gender"] as? String ?? "")
        }
    }

    /// One call: the narrator — a voice from the server's list and how it
    /// speaks — and a description of the music, for MusicGen.
    static func planSound(_ film: Film, seconds: Double = 0) async -> (narrator: Narrator?, music: String?, voiceover: String?) {
        guard let writer = await writer(), let url = URL(string: writer.host + "/api/chat") else { return (nil, nil, nil) }
        // The film narrator service when it can be had: a voice designed for
        // this film, reading one continuous passage. Listened to side by side,
        // one flowing passage read in one go beat four short lines stitched
        // together — the intonation carries, and it reads like narration.
        let designed = await BoxServices.shared.ensure(.narrator)
        let offered = designed ? [] : await voices()
        let lines = film.shots.compactMap(\.narration).filter { !$0.isEmpty }
        let voiceList = offered.map { "\($0.id) — \($0.name) (\($0.language), \($0.gender))" }.joined(separator: "\n")
        let ask = """
            A short film: "\(film.idea)". \(film.about.map { "It is \($0). " } ?? "")\(film.source.map { "It follows \($0). " } ?? "")
            Look: \(film.look)
            \(lines.isEmpty ? "It has no voice-over." : "Its voice-over, line by line:\n" + lines.joined(separator: "\n"))

            1. \(lines.isEmpty ? "No narrator is needed: answer null for narrator and voiceover." : designed ? """
            The narrator is a voice you DESIGN in words, for a voice-design model. Write `voice`, in the language of \
            the lines, one or two sentences: who is speaking (age, sex), the timbre, the pace, the feeling — for \
            scripture or history something like "中年男性纪录片旁白，嗓音浑厚温暖、略带沙哑的磁性，语速沉稳，吐字清晰，\
            停顿自然，带着敬畏和庄重，像在讲述古老的经文". Answer narrator as {"voice": "..."}.
            Then write `voiceover`: ONE continuous passage of narration for the whole film, in the language of the \
            lines above, told in the order of the shots, as a documentary narrator would tell it — full, flowing \
            sentences, not captions ("很久以前，在加利利海边的山坡上……"), with the story's own words where it has \
            them. It is read aloud over the film at a calm pace, so it must fit: about \(Self.narrationBudget(seconds, lines: lines)).
            """ : offered.isEmpty ? "No narrator is available: answer null for narrator." : """
            Choose who reads the voice-over, from these voices (use the id exactly):
            \(voiceList)
            Pick the voice that suits the story and is in the language of the lines — a mature, grave voice for \
            scripture or history, a warm one for a children's tale. Then write `instruct`: how it should be read, \
            in the language of the lines, one short sentence ("用低沉、庄重、缓慢的语气，像在讲述古老的经文").
            """)
            2. Write the music for under the whole film, for MusicGen, in English, 15 to 35 words: the genre and \
            the era it belongs to, the instruments, the tempo, the mood — and "instrumental, no vocals". Music of \
            the story's own time and place where it has one (first-century Galilee: oud, ney flute, frame drum, \
            drone), never modern pop. Quiet enough to sit under a voice.
            Answer with JSON only: {"narrator": \(designed ? "{\"voice\": \"...\"}" : "{\"speaker\": \"...\", \"instruct\": \"...\"}") or null, \(designed ? "\"voiceover\": \"...\", " : "")"music": "..."}
            """
        let body: [String: Any] = ["model": writer.model, "stream": false, "think": false,
                                   "messages": [["role": "user", "content": ask]]]
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let said = (reply["message"] as? [String: Any])?["content"] as? String,
              let open = said.firstIndex(of: "{"), let close = said.lastIndex(of: "}"), open < close,
              let object = (try? JSONSerialization.jsonObject(with: Data(said[open...close].utf8))) as? [String: Any]
        else { return (nil, nil, nil) }
        var narrator: Narrator?
        var voiceover: String?
        let chinese = lines.joined().unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        if designed, let n = object["narrator"] as? [String: Any],
           let voice = (n["voice"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), voice.count > 6 {
            narrator = Narrator(speaker: "", language: chinese ? "zh" : "en", instruct: nil, voice: voice)
            let passage = (object["voiceover"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            voiceover = (passage?.count ?? 0) > 8 ? passage : nil
        } else if let n = object["narrator"] as? [String: Any], let speaker = n["speaker"] as? String,
           let voice = offered.first(where: { $0.id == speaker }) {
            let instruct = (n["instruct"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            narrator = Narrator(speaker: voice.id, language: voice.language.isEmpty ? nil : voice.language,
                                instruct: (instruct?.isEmpty ?? true) ? nil : instruct)
        }
        let music = (object["music"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (narrator, (music?.count ?? 0) > 10 ? music : nil, voiceover)
    }

    /// How much narration fits a film this long, said the way the writer can
    /// count it. Measured: the designed narrator reads Chinese at about 3.8
    /// characters a second; a little under that leaves room to breathe.
    static func narrationBudget(_ seconds: Double, lines: [String]) -> String {
        let chinese = lines.joined().unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let usable = max(6, seconds - 1.5)
        // Measured again on the designed narrator: 70 characters took 20.2 s
        // (3.5 a second), and the writer ran past the 59 it was given.
        return chinese ? "\(Int(usable * 3.0)) Chinese characters — count them; never more" : "\(Int(usable * 2.0)) English words — count them; never more"
    }

    /// The whole voice-over, read in one go by the film narrator service.
    static func readVoiceover(_ text: String, narrator: Narrator) async -> Data? {
        guard await BoxServices.shared.ensure(.narrator),
              let url = await URL(string: BoxServices.base(.narrator) + "/synthesize") else { return nil }
        var body: [String: Any] = ["text": text, "speed": 1.0]
        if let language = narrator.language { body["language"] = language }
        if let voice = narrator.voice { body["instruct"] = voice }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        for _ in 0..<2 {     // a kept-alive connection the server closed kills the first POST
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, data.count > 44 {
                return WAVTrim.trim(data)
            }
        }
        return nil
    }

    /// The score by MiniMax Music 3, through ComfyUI on the box: the graph its
    /// official template makes, written directly. The description is used as
    /// its caption; an instrumental piece is asked for with section tags only.
    static func composeMiniMax(_ description: String, seconds: Double, for film: String, to out: URL) async throws {
        guard await BoxServices.shared.ensure(.comfy) else { throw Failure.message("盒子上的 ComfyUI 起不来") }
        let base = await BoxServices.base(.comfy)
        let caption = description.contains("Global Metadata") ? description : """
            Global Metadata: \(description)

            Vocal Details: Instrumental. No vocals, no choir words.

            Arrangement: Quiet opening, a gentle build in the middle, a peaceful ending that fades out.
            """
        let seed = Int.random(in: 0..<1_000_000)
        func node(_ type: String, _ inputs: [String: Any]) -> [String: Any] { ["class_type": type, "inputs": inputs] }
        let graph: [String: Any] = [
            "1": node("UNETLoader", ["unet_name": "minimax_music3_dit_fp16.safetensors", "weight_dtype": "default"]),
            "2": node("CLIPLoader", ["clip_name": "minimax_music3_text_encoder_pruned_int8_convrot.safetensors", "type": "minimax", "device": "default"]),
            "3": node("VAELoader", ["vae_name": "minimax_music3_dav.safetensors"]),
            "4": node("MiniMaxMusic3TextEncode", ["clip": ["2", 0], "caption": caption, "lyrics": "[intro]\n\n[instrumental]\n\n[outro]",
                                                  "seed": seed, "max_duration": min(300, max(10, seconds + 2)), "cfg_scale": 1.7, "top_k": 50]),
            "5": node("ConditioningZeroOut", ["conditioning": ["4", 0]]),
            "6": node("EmptyMiniMaxMusic3LatentAudio", ["seconds": ["4", 1], "batch_size": 1]),
            "7": node("KSampler", ["model": ["1", 0], "seed": seed, "steps": 30, "cfg": 1.7, "sampler_name": "euler",
                                   "scheduler": "simple", "positive": ["4", 0], "negative": ["5", 0], "latent_image": ["6", 0], "denoise": 1.0]),
            "8": node("VAEDecodeAudio", ["samples": ["7", 0], "vae": ["3", 0]]),
            "9": node("SaveAudioAdvanced", ["audio": ["8", 0], "filename_prefix": "audio/kinclaw-score", "format": "flac"]),
        ]
        guard let url = URL(string: base + "/prompt") else { throw Failure.message("ComfyUI 地址不对") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": graph, "client_id": "kinclaw-film"])
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let id = answer["prompt_id"] as? String else {
            throw Failure.message("ComfyUI 不接配乐：\(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
        }
        // MiniMax Music 3's text stage is ~2.7 s a token on the box and a 45 s
        // piece is over a thousand tokens: fifty minutes. Thirty was too few.
        let deadline = Date().addingTimeInterval(3 * 3600)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 4_000_000_000)
            guard let hurl = URL(string: base + "/history/\(id)"),
                  let (hdata, _) = try? await URLSession.shared.data(from: hurl),
                  let history = (try? JSONSerialization.jsonObject(with: hdata)) as? [String: Any],
                  let entry = history[id] as? [String: Any] else { continue }
            let status = entry["status"] as? [String: Any]
            if status?["status_str"] as? String == "error" { throw Failure.message("配乐出错（MiniMax Music 3）") }
            guard status?["completed"] as? Bool == true else { continue }
            let saved = ((entry["outputs"] as? [String: Any])?["9"] as? [String: Any]).flatMap { $0["audio"] as? [[String: Any]] ?? $0["images"] as? [[String: Any]] } ?? []
            guard let file = saved.first, let name = file["filename"] as? String else { throw Failure.message("配乐跑完了但没存下来") }
            var parts = URLComponents(string: base + "/view")
            parts?.queryItems = [URLQueryItem(name: "filename", value: name),
                                 URLQueryItem(name: "subfolder", value: file["subfolder"] as? String ?? ""),
                                 URLQueryItem(name: "type", value: "output")]
            guard let view = parts?.url else { throw Failure.message("取不回配乐") }
            let (bytes, _) = try await URLSession.shared.data(from: view)
            guard bytes.count > 1000 else { throw Failure.message("取回来的配乐是空的") }
            // FLAC from ComfyUI, WAV for the cut: decoded here with AVAudioFile
            // rather than trusting a mixer to sniff FLAC inside a .wav name.
            let flac = out.deletingPathExtension().appendingPathExtension("flac")
            try? FileManager.default.removeItem(at: flac)
            try bytes.write(to: flac)
            try flacToWAV(flac, out)
            return
        }
        throw Failure.message("配乐三个小时还没好")
    }

    private static func flacToWAV(_ input: URL, _ output: URL) throws {
        let source = try AVAudioFile(forReading: input)
        let format = source.processingFormat
        try? FileManager.default.removeItem(at: output)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let target = try AVAudioFile(forWriting: output, settings: settings, commonFormat: format.commonFormat,
                                     interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536) else { throw Failure.message("配乐转不了格式") }
        while source.framePosition < source.length {
            try source.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try target.write(from: buffer)
        }
    }

    /// The score, made on the box by kin audio's MusicGen and brought back.
    /// The first run downloads the model there (about 4 GB, once).
    static func compose(_ description: String, seconds: Double, for film: String, to out: URL) async throws {
        let words = description.filter { !"\"'`$\\;&|<>\n".contains($0) }
        let length = Int(min(30, max(10, seconds.rounded(.up))))
        let name = film.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(60)
        let remote = "~/.kinclaw/music/\(name).wav"
        let (code, output) = await BoxServices.run("""
            mkdir -p ~/.kinclaw/music ~/Library/Logs/kinclaw; cd ~/localkin-service-audio && \
            PATH=/opt/homebrew/bin:/usr/local/bin:$PATH .venv/bin/kin audio music generate "\(words)" \
            --model \(musicModel) --duration \(length) -o \(remote) --device mps --no-play \
            >> ~/Library/Logs/kinclaw/music.log 2>&1; ls -l \(remote) >/dev/null 2>&1 && echo MADE || { echo FAILED; tail -c 400 ~/Library/Logs/kinclaw/music.log; }
            """)
        guard code == 0, output.contains("MADE") else {
            throw Failure.message("配乐没做出来：\(output.suffix(300))")
        }
        let (fetched, encoded) = await BoxServices.run("base64 -i \(remote)")
        guard fetched == 0, let bytes = Data(base64Encoded: encoded.filter { !$0.isWhitespace }), bytes.count > 1000 else {
            throw Failure.message("配乐做好了但取不回来")
        }
        try bytes.write(to: out, options: .atomic)
    }
}
