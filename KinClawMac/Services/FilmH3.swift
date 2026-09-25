import Foundation

/// Story films shot on MiniMax H3, through ComfyUI on the box.
///
/// What the other video model could not do was keep a person. Every still was
/// drawn on its own, so the man breaking bread in shot 3 was not the man in
/// shot 5, and the story briefs learned to hide faces — hands, backs,
/// silhouettes — because a face that changes is worse than none. H3 films
/// from references: a picture of each person and a picture of the place,
/// labelled in the prompt, and it keeps the faces and the clothes. So an H3
/// film is cast first — each person who matters written once and drawn once,
/// a plain portrait — every shot's still is drawn as the empty set, and each
/// shot is filmed from the portraits of who is in it and the set it happens in.
///
/// Measured on the box (M3 Ultra, 96 GB): three seconds at 480×864 with the
/// 4-step LoRA, 257 s, a fisherman from one picture walking into the scene of
/// another and kneeling by the basket, same face, stereo sound.
extension FilmStudio {
    enum Engine: String, Codable, CaseIterable {
        case ltx, h3
        var title: String {
            switch self { case .ltx: return "LTX（快）"; case .h3: return "H3（人物一致）" }
        }
    }

    /// A person in the film: what they are called in the story and what they
    /// look like, in English, once — the portrait is drawn from it.
    struct Cast: Codable, Equatable {
        var name: String
        var look: String
    }

    static let h3MegapixelsKey = "kinclaw.film.h3.megapixels"

    // MARK: - Casting

    /// Who is in it, and in which shots. People who appear in one shot and are
    /// nobody (a crowd, a passer-by) are not cast; the story's people are.
    static func castFilm(_ film: Film) async -> (cast: [Cast], who: [Int: [String]])? {
        guard let writer = await writer(), let url = URL(string: writer.host + "/api/chat") else { return nil }
        let list = film.shots.map { shot in
            "{\"id\": \(shot.id), \"camera\": \(quoted(shot.framing ?? "")), \"shows\": \(quoted(shot.pose)), \"moves\": \(quoted(shot.action)), \"the_moment\": \(quoted(shot.narration ?? ""))}"
        }.joined(separator: ",\n")
        let ask = """
            A short film about: "\(film.idea)".
            \(film.source.map { "It follows: \($0).\n" } ?? "")Shared look: \(film.look)
            The shots: [\(list)]

            Cast it. The people this story is about — at most four, the ones who matter or come back — each get \
            one reference portrait, and the video model keeps them looking the same in every shot from it. Crowds \
            and passers-by are not cast.
            For each: `name` as the story calls them, in English ("Jesus", "the boy", "Peter"); `look` — 40 to 70 \
            words, in English, of what a camera sees: age, face, hair and beard, build, and what they wear, true \
            to the time and place of the story (plain undyed wool, a head cloth, sandals — nothing modern). No pose, \
            no expression, no setting.
            Then for each shot, `who` — the cast members who appear in it (none for a shot of a thing or a place).
            Answer with JSON only: {"cast": [{"name": "...", "look": "..."}], "shots": [{"id": 1, "who": ["..."]}]}
            """
        guard let object = await askJSON(ask, host: url, model: writer.model) else { return nil }
        let cast = (object["cast"] as? [[String: Any]] ?? []).compactMap { row -> Cast? in
            guard let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let look = (row["look"] as? String)?.trimmingCharacters(in: .whitespaces), look.count > 20 else { return nil }
            return Cast(name: name, look: look)
        }
        var who: [Int: [String]] = [:]
        for row in object["shots"] as? [[String: Any]] ?? [] {
            guard let id = row["id"] as? Int else { continue }
            who[id] = (row["who"] as? [String] ?? []).filter { name in cast.contains { $0.name == name } }
        }
        return (Array(cast.prefix(4)), who)
    }

    /// The portrait a cast member is drawn as: plain, front on, the face sharp
    /// — a reference, not a scene. The period goes in because the clothes are
    /// what H3 carries over most faithfully, wrong ones included.
    static func portrait(of member: Cast, in film: Film) -> String {
        // Tight on the face: twice now a "waist-up" portrait came back head to
        // toe (the description mentions sandals and the model shows them), and
        // the face — what H3 has to keep — was a few dozen pixels high. Not the
        // film's look line either, which carries the setting.
        """
        Tight head-and-shoulders character reference portrait of \(member.name), framed from mid-chest to just \
        above the head, the face filling about a third of the frame, looking straight into the camera: \
        \(member.look) \
        Neutral, calm expression. Soft even daylight from the front, plain light grey studio backdrop and nothing \
        else — no landscape, no other people, no text. Natural adult proportions. Sharp focus on the eyes, natural \
        skin texture with pores and fine lines, photorealistic, 85mm portrait lens.
        """
    }

    /// Each shot's picture with every person taken out of it — the set. Only
    /// the pictures that had someone in them come back.
    static func emptySets(_ film: Film) async -> [Int: String]? {
        guard let writer = await writer(), let url = URL(string: writer.host + "/api/chat") else { return nil }
        let list = film.shots.filter { $0.state != .done && ($0.picture ?? "").count > 40 }
            .map { "{\"id\": \($0.id), \"subject\": \"\($0.of.rawValue)\", \"picture\": \(quoted($0.picture ?? ""))}" }
            .joined(separator: ",\n")
        guard !list.isEmpty else { return [:] }
        let ask = """
            These describe frames of a film for an image model. The people in them will be put in later by \
            another model, from their own portraits — so each frame has to be drawn as the PLACE ALONE, the way \
            it looks before anyone arrives.
            [\(list)]

            For every description that has a person or any part of one in it, write a new one of the same frame \
            as the place alone: keep the camera, lens and framing; describe the ground, what is behind, the \
            things that belong there (the loaves and fish on a cloth on a rock, a basket in the grass), the light, \
            the grade, the period and its exclusions. Write it as if nobody had ever been there.
            Never mention: people, bodies or any part of one, clothes, robes or belts, posts or stands to hang \
            them on, mannequins, "absent", "where someone would be", "empty space for". Those words get drawn.
            A "place" shot may keep a crowd only as tiny distant shapes.
            Return only the ones you rewrote. Answer with JSON only: [{"id": 2, "picture": "..."}]
            """
        guard let rows = await askJSONArray(ask, host: url, model: writer.model) else { return nil }
        var out: [Int: String] = [:]
        for row in rows {
            guard let id = row["id"] as? Int, let text = (row["picture"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.count > 60 else { continue }
            out[id] = text
        }
        return out
    }

    // MARK: - Prompts in H3's own form

    /// Each shot's H3 prompt, written against MiniMax's official guide for the
    /// reference mode. The pictures are labelled per shot: the portraits of
    /// who is in it, in cast order, then the set.
    static func writeH3(_ film: Film, only: [Int]? = nil) async -> [Int: String]? {
        guard let writer = await writer(), let url = URL(string: writer.host + "/api/chat") else { return nil }
        let guide = await h3Guide()
        let seconds = String(format: "%.1f", h3Seconds(film.seconds))
        let shots = film.shots.filter { only?.contains($0.id) ?? true }
        let list = shots.map { shot -> String in
            let people = (shot.who ?? []).enumerated().map { "<Picture \($0.offset + 1)> is \($0.element) (a portrait: face and clothes)" }
            let things = (shot.props ?? []).enumerated().map { "<Picture \(people.count + $0.offset + 1)> shows an object as it looks elsewhere in the film (\($0.element)): the same object here must look exactly like it" }
            let labels = people + things + ["<Picture \(people.count + things.count + 1)> is the set of this shot (the place, the props, the light and the framing, with nobody in it yet)"]
            return "{\"id\": \(shot.id), \"pictures\": \(quoted(labels.joined(separator: "; "))), \"camera\": \(quoted(shot.framing ?? "")), \"shows\": \(quoted(shot.pose)), \"moves\": \(quoted(shot.action)), \"the_moment\": \(quoted(shot.narration ?? ""))\(shot.wish.map { ", \"direction\": \(quoted($0))" } ?? "")\(counted(shot.checks).map { ", \"counts\": \(quoted($0))" } ?? "")}"
        }.joined(separator: ",\n")
        let cast = (film.cast ?? []).map { "\($0.name): \($0.look)" }.joined(separator: "\n")
        let ask = """
            You write prompts for MiniMax H3's full-reference mode (reference pictures → video with sound), \
            following its official guide exactly: the six sections in its order and with its field names, labels \
            used the same way in every section.
            \(guide.map { "The official guide:\n<<<\n\($0)\n>>>\n" } ?? "")
            The film: "\(film.idea)". \(film.source.map { "It follows \($0). " } ?? "")Look: \(film.look)\(film.tone.map { "\n\($0) — every shot has this look; say it in each prompt." } ?? "")
            \(film.place.map { "Where: \($0)\n" } ?? "")\(cast.isEmpty ? "" : "The cast:\n\(cast)\n")
            The shots — each is ONE continuous take of \(seconds) seconds, filmed on its own:
            [\(list)]

            For EACH shot write the full prompt. Rules:
            - One shot only: [Shot 1], no cuts, no timestamps beyond it; the length is \(seconds) seconds.
            - The set picture is where it happens: keep its place, light and framing. The people in a shot are \
            exactly the ones with portraits in its "pictures" — nobody else. Where "shows" or "moves" speaks of \
            hands or a figure ("a man's weathered hands"), those are the cast member's. Keep their faces and \
            clothes from the portraits and do not describe them differently; faces may be seen.
            - "moves" is what happens — make it a clear action that plainly changes the frame, carried by "the \
            moment"; the camera as "camera" says, and still whenever the people move.
            - Where a shot has "counts", say each exact number ("exactly five round loaves") and never more or \
            fewer; the set already holds that many — they stay as they are, and the camera holds still, because a \
            moving camera finds more of them.
            - Everything belongs to the time and place of the story: nothing modern, no text on screen.
            - Nobody speaks (the narration is added later as a voice-over); overall_soundscape is the place's \
            own sound; non_diegetic_music is none.
            Answer with JSON only: [{"id": 1, "prompt": "subject_definitions:\\n..."}]
            """
        guard let rows = await askJSONArray(ask, host: url, model: writer.model) else { return nil }
        var out: [Int: String] = [:]
        for row in rows {
            guard let id = row["id"] as? Int, let prompt = (row["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  prompt.count > 80 else { continue }
            out[id] = prompt
        }
        return out.isEmpty ? nil : out
    }

    /// MiniMax's prompting guide for H3's reference mode, fetched from their
    /// repository once and kept beside the Comfy tab's — theirs, not shipped.
    static func h3Guide() async -> String? {
        let cache = ComfyStudio.root.appendingPathComponent("guides/ref-en.txt")
        if let kept = try? String(contentsOf: cache, encoding: .utf8), !kept.isEmpty { return kept }
        guard let url = URL(string: "https://raw.githubusercontent.com/MiniMax-AI/MiniMax-H3/main/skills/h3-prompt-writing/references/ref-en.txt"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else { return nil }
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cache)
        return text
    }

    /// H3 was trained on 124 frames and up (about five seconds); shorter
    /// clips are asked for as that.
    static func h3Frames(_ seconds: Double) -> Int {
        var n = max(124, Int((seconds * 24).rounded()))
        n += (5 - n % 17 + 17) % 17          // H3 wants 17k + 5 frames
        return n
    }
    static func h3Seconds(_ seconds: Double) -> Double { Double(h3Frames(seconds)) / 24 }

    // MARK: - Filming

    /// Film one shot on H3: the references uploaded, the graph built, run,
    /// and the mp4 brought back to `out`. The graph is the one ComfyUI's own
    /// template turns into (reference-to-video with its 4-step LoRA), written
    /// here directly so a film does not wait on ComfyUI's web page.
    static func renderH3(prompt: String, references: [URL], seconds: Double, size: CGSize, seed: Int,
                         full: Bool, pins: [(picture: URL, frame: Int)] = [], to out: URL, film: String,
                         shot: Int) async throws {
        guard await BoxServices.shared.ensure(.comfy) else { throw Failure.message("盒子上的 ComfyUI 起不来") }
        let base = await BoxServices.base(.comfy)
        // Upload each reference under a name that says whose it is.
        var names: [String] = []
        for (i, file) in references.prefix(9).enumerated() {
            let name = "kinclaw-\(film.prefix(40))-shot\(shot)-ref\(i + 1).png"
            names.append(try await upload(file, as: name, to: base))
        }
        let megapixels = UserDefaults.standard.object(forKey: h3MegapixelsKey) as? Double ?? 0.4
        let scale = (megapixels * 1_000_000 / Double(size.width * size.height)).squareRoot()
        let width = max(256, Int((Double(size.width) * scale / 32).rounded()) * 32)
        let height = max(256, Int((Double(size.height) * scale / 32).rounded()) * 32)
        var graph: [String: Any] = [
            "1": node("UNETLoader", ["unet_name": "minimax_h3_ref2va_pruned_int8_convrot.safetensors", "weight_dtype": "default"]),
            "2": node("CLIPLoader", ["clip_name": "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors", "type": "minimax", "device": "default"]),
            "3": node("VAELoader", ["vae_name": "minimax_h3_video_vae_fp16.safetensors"]),
            "4": node("VAELoader", ["vae_name": "minimax_h3_audio_vae_fp32.safetensors"]),
            "5": node("LoraLoaderModelOnly", ["lora_name": "minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors",
                                              "strength_model": 1, "model": ["1", 0]]),
            "7": node("RandomNoise", ["noise_seed": seed]),
            "8": node("KSamplerSelect", ["sampler_name": "res_multistep"]),
            "9": node("BasicScheduler", ["scheduler": "simple", "steps": full ? 20 : 4, "denoise": 1,
                                         "model": full ? ["1", 0] : ["5", 0]]),
            "11": node("SamplerCustomAdvanced", ["noise": ["7", 0], "guider": ["10", 0], "sampler": ["8", 0],
                                                 "sigmas": ["9", 0], "latent_image": ["6", 1]]),
            "12": node("VAEDecode", ["samples": ["11", 0], "vae": ["3", 0]]),
            "13": node("VAEDecodeAudio", ["samples": ["11", 0], "vae": ["4", 0]]),
            "14": node("CreateVideo", ["fps": 24, "bit_depth": 8, "color_space": "sRGB", "codec": "none",
                                       "images": ["12", 0], "audio": ["13", 0]]),
            "15": node("SaveVideo", ["filename_prefix": "video/kinclaw-film", "format": "auto", "codec": "auto",
                                     "format.codec": "auto", "video": ["14", 0]]),
        ]
        var reference: [String: Any] = [
            "prompt": prompt, "width": width, "height": height, "length": h3Frames(seconds), "ref_image_size": "match",
            "clip": ["2", 0], "vae": ["3", 0], "audio_vae": ["4", 0],
        ]
        for (i, name) in names.enumerated() {
            graph["\(100 + i)"] = node("LoadImage", ["image": name])
            reference["ref_images.ref_image_\(i)"] = ["\(100 + i)", 0]
        }
        graph["6"] = node("MiniMaxH3ReferenceToVideo", reference)
        // Pinned frames: pictures the shot must pass through exactly — its
        // first frame, made and checked beforehand — chained onto the
        // conditioning, each at the size the shot is filmed at.
        var conditioning: [Any] = ["6", 0]
        for (i, pin) in pins.enumerated() {
            guard let sized = FilmStudio.filling(pin.picture, width: width, height: height) else {
                throw Failure.message("读不了要钉的画面：\(pin.picture.lastPathComponent)")
            }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("kinclaw-pin-\(UUID().uuidString).png")
            try sized.write(to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let name = try await upload(temporary, as: "kinclaw-\(film.prefix(40))-shot\(shot)-pin\(i + 1).png", to: base)
            graph["\(200 + i)"] = node("LoadImage", ["image": name])
            graph["\(300 + i)"] = node("MiniMaxH3AddGuide", ["positive": conditioning, "latent": ["6", 1], "frame_idx": pin.frame,
                                                            "vae": ["3", 0], "audio_vae": ["4", 0], "image": ["\(200 + i)", 0]])
            conditioning = ["\(300 + i)", 0]
        }
        graph["10"] = node("BasicGuider", ["model": full ? ["1", 0] : ["5", 0], "conditioning": conditioning])

        let video = try await comfyResult(graph, node: "15", base: base, what: "H3 镜头", deadline: 3600)
        try? FileManager.default.removeItem(at: out)
        try video.write(to: out)
    }

    /// Queue a graph on the box's ComfyUI and bring back the first file its
    /// `node` saved. Stopped here, it is stopped there too, or the box keeps
    /// rendering something nobody will see for another few minutes.
    static func comfyResult(_ graph: [String: Any], node: String, base: String, what: String,
                            deadline seconds: TimeInterval) async throws -> Data {
        guard let url = URL(string: base + "/prompt") else { throw Failure.message("ComfyUI 地址不对") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": graph, "client_id": "kinclaw-film"])
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let id = answer["prompt_id"] as? String else {
            throw Failure.message("ComfyUI 不接这个\(what)：\(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
        }
        do {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                guard let hurl = URL(string: base + "/history/\(id)"),
                      let (hdata, _) = try? await URLSession.shared.data(from: hurl),
                      let history = (try? JSONSerialization.jsonObject(with: hdata)) as? [String: Any],
                      let entry = history[id] as? [String: Any] else { continue }
                let status = entry["status"] as? [String: Any]
                if status?["status_str"] as? String == "error" {
                    let messages = (status?["messages"] as? [[Any]] ?? []).compactMap { $0.count > 1 ? $0[1] as? [String: Any] : nil }
                    throw Failure.message("\(what)出错：" + (messages.compactMap { $0["exception_message"] as? String }.first ?? "看盒子上的 comfy.log").prefix(300))
                }
                guard status?["completed"] as? Bool == true else { continue }
                let saved = ((entry["outputs"] as? [String: Any])?[node] as? [String: Any])?["images"] as? [[String: Any]] ?? []
                guard let file = saved.first, let name = file["filename"] as? String else { throw Failure.message("\(what)跑完了但没存下来") }
                var parts = URLComponents(string: base + "/view")
                parts?.queryItems = [URLQueryItem(name: "filename", value: name),
                                     URLQueryItem(name: "subfolder", value: file["subfolder"] as? String ?? ""),
                                     URLQueryItem(name: "type", value: "output")]
                guard let view = parts?.url else { throw Failure.message("取不回\(what)") }
                let (bytes, _) = try await URLSession.shared.data(from: view)
                guard bytes.count > 1000 else { throw Failure.message("取回来的\(what)是空的") }
                return bytes
            }
            throw Failure.message("\(what)跑了 \(Int(seconds / 60)) 分钟还没好")
        } catch {
            if Task.isCancelled, let stop = URL(string: base + "/interrupt") {
                var request = URLRequest(url: stop, timeoutInterval: 5)
                request.httpMethod = "POST"
                _ = try? await URLSession.shared.data(for: request)
            }
            throw error
        }
    }

    static func node(_ type: String, _ inputs: [String: Any]) -> [String: Any] {
        ["class_type": type, "inputs": inputs]
    }

    static func upload(_ file: URL, as name: String, to base: String) async throws -> String {
        guard let url = URL(string: base + "/upload/image") else { throw Failure.message("ComfyUI 地址不对") }
        let bytes = try Data(contentsOf: file)
        let boundary = "kinclaw-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(name)\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(bytes)
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let saved = answer["name"] as? String else { throw Failure.message("参考图传不到 ComfyUI") }
        let sub = answer["subfolder"] as? String ?? ""
        return sub.isEmpty ? saved : sub + "/" + saved
    }

    // MARK: - Small things

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }

    private static func chat(_ ask: String, host url: URL, model: String) async -> String? {
        let body: [String: Any] = ["model": model, "stream": false, "think": false,
                                   "messages": [["role": "user", "content": ask]]]
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (reply["message"] as? [String: Any])?["content"] as? String
    }

    private static func askJSON(_ ask: String, host url: URL, model: String) async -> [String: Any]? {
        guard let said = await chat(ask, host: url, model: model),
              let open = said.firstIndex(of: "{"), let close = said.lastIndex(of: "}"), open < close else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(said[open...close].utf8))) as? [String: Any]
    }

    private static func askJSONArray(_ ask: String, host url: URL, model: String) async -> [[String: Any]]? {
        guard let said = await chat(ask, host: url, model: model),
              let open = said.firstIndex(of: "["), let close = said.lastIndex(of: "]"), open < close else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(said[open...close].utf8))) as? [[String: Any]]
    }
}
