import AVFoundation
import Foundation

/// One sentence in, a short film out — on the user's own machines.
///
/// This is the shape of Sora, not its model. What the box can do is a
/// four-second clip at 704 pixels in about eighty seconds; what that cannot
/// be is a twenty-second take with convincing physics. So a film here is
/// what a film has always been: a list of short shots, cut together.
///
///   1. **A storyboard** — a title, a look that every frame shares, and a
///      few shots, each a frame to draw and what moves in it. Written by a
///      language model: the brain that calls `film_make`, or the local one
///      when the idea comes from the tab.
///   2. **A still per shot.** When she is in it, the still is an *edit* of
///      her anchor portrait, which is the only thing that has ever kept a
///      generated person the same person from one picture to the next.
///      Otherwise it is drawn from the description.
///   3. **The still, filmed.** Image-to-video, so the clip is that frame
///      moving; the model writes the sound along with the picture.
///   4. **The cut**, with AVFoundation rather than ffmpeg — the app has no
///      ffmpeg to call — shots overlapped by a short dissolve, sound faded
///      across it.
///
/// Every step is written to `film.json` as it happens, so a film survives
/// the app being quit half way, and one shot can be redone without the rest.
@MainActor
final class FilmStudio: ObservableObject {
    static let shared = FilmStudio()

    struct Shot: Codable, Identifiable, Equatable {
        var id: Int
        /// The frame: subject, place, light, framing. English, for the models.
        var still: String
        /// What moves in it, and what it sounds like.
        var motion: String
        var state: State = .waiting
        var note: String?
        /// Filmed (or to be filmed) on the high-quality model.
        var hq: Bool? = nil
        /// A line of voice-over, spoken by the user's own TTS over this shot.
        var narration: String? = nil

        enum State: String, Codable { case waiting, drawing, filming, done, failed }
    }

    struct Film: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var idea: String
        /// What every frame shares: stock, light, palette.
        var look: String
        /// What she is wearing, said once. Each still is an edit of its own,
        /// and left to themselves they dress her differently every time — a
        /// white dress on the sand, a beige one at the water's edge — which
        /// reads as two women or two days.
        var wears: String? = nil
        /// She is the lead, so every still is an edit of her anchor.
        var lead: Bool
        var seconds: Double
        var shots: [Shot]
        var state: State = .waiting
        var note: String?
        var created = Date()

        enum State: String, Codable { case waiting, shooting, cutting, done, failed }

        // Where it lives depends on where her art lives, which is the main
        // actor's to say.
        @MainActor var folder: URL { FilmStudio.root.appendingPathComponent(id) }
        @MainActor var file: URL { folder.appendingPathComponent("film.mp4") }
        @MainActor func still(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.png", shot)) }
        @MainActor func clip(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.mp4", shot)) }
        @MainActor func voice(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.wav", shot)) }
        var finished: Int { shots.filter { $0.state == .done }.count }
    }

    /// `<art folder>/films/` — beside her pictures, on whatever disk those are.
    static var root: URL { CompanionArt.folder.appendingPathComponent("films") }

    @Published private(set) var films: [Film] = []
    /// The film in production. One at a time: there is one video server.
    @Published private(set) var shooting: String?

    init() {
        reload()
        // A film that was being shot when the app last quit is still half
        // made on disk, and every finished shot in it is still good. It is
        // picked up where it stopped rather than left saying "shooting"
        // forever to nobody.
        if let unfinished = films.first(where: { $0.state == .shooting || $0.state == .cutting }) {
            produce(unfinished.id)
        }
    }

    func reload() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: Self.root.path)) ?? []
        films = names.compactMap { name -> Film? in
            let file = Self.root.appendingPathComponent(name).appendingPathComponent("film.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? Self.decoder.decode(Film.self, from: data)
        }.sorted { $0.created > $1.created }
    }

    // MARK: - Making one

    /// Start a film. Returns at once; the work runs for minutes.
    func make(title: String, idea: String, look: String, wears: String = "", lead: Bool, seconds: Double,
              shots: [(still: String, motion: String)], narration: [String] = []) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        let wanted = shots.filter { !$0.still.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !wanted.isEmpty else { return .failure(.message("分镜是空的：每个镜头要有 still（画面）和 motion（动作）")) }
        guard wanted.count <= 12 else { return .failure(.message("一次最多 12 个镜头")) }
        if let trouble = CompanionArt.unreachableVolume(Self.root) { return .failure(.message(trouble)) }
        if lead, CompanionCharacter.shared.anchorURL == nil {
            return .failure(.message("她还没有锚图，没法当主角；先 character_new 定一张脸，或者 lead 填 false"))
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let slug = Self.slug(title.isEmpty ? idea : title)
        var film = Film(id: "\(slug)-\(stamp)", title: title.isEmpty ? String(idea.prefix(24)) : title,
                        idea: idea, look: look, lead: lead, seconds: min(max(seconds, 2), 10),
                        shots: wanted.enumerated().map { Shot(id: $0.offset + 1, still: $0.element.still, motion: $0.element.motion) })
        film.wears = wears.trimmingCharacters(in: .whitespaces).isEmpty ? nil : wears
        for (index, line) in narration.enumerated() where index < film.shots.count {
            let said = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !said.isEmpty { film.shots[index].narration = said }
        }
        film.state = .shooting
        do {
            try FileManager.default.createDirectory(at: film.folder, withIntermediateDirectories: true)
        } catch { return .failure(.message("建不了片子的文件夹：\(error.localizedDescription)")) }
        save(film)
        produce(film.id)
        return .success(film)
    }

    /// A storyboard being written, and what went wrong with the last one: the
    /// half minute before there is a film to show progress on.
    @Published private(set) var writing: String?
    @Published private(set) var trouble: String?

    /// From one sentence: the local brain writes the storyboard, then it is
    /// made. What the tab's button does, and what `film_make` does when it is
    /// given an idea and no shots.
    func make(from idea: String, shots: Int, lead: Bool, then done: ((Result<Film, Failure>) -> Void)? = nil) {
        guard writing == nil else { done?(.failure(.message("还在给「\(writing!)」写分镜"))); return }
        writing = idea
        trouble = nil
        Task { @MainActor in
            defer { writing = nil }
            let result: Result<Film, Failure>
            do {
                let board = try await Self.storyboard(for: idea, shots: min(max(shots, 2), 8), lead: lead,
                                                      model: Self.writerModel)
                result = make(title: board.title, idea: idea, look: board.look, wears: board.wears, lead: lead,
                              seconds: 4, shots: board.shots, narration: board.narration)
            } catch {
                result = .failure(.message("分镜没写出来：\(error.localizedDescription)"))
            }
            if case .failure(let failure) = result { trouble = failure.localizedDescription }
            done?(result)
        }
    }

    /// Redo one shot — a new frame, a new take, or both — and cut again.
    func reshoot(film id: String, shot number: Int, still: String?, motion: String?, hq: Bool = false) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        guard var film = films.first(where: { $0.id == id || $0.title == id }) else {
            return .failure(.message("没有这部片子：\(id)"))
        }
        guard let index = film.shots.firstIndex(where: { $0.id == number }) else {
            return .failure(.message("「\(film.title)」没有第 \(number) 个镜头，它有 \(film.shots.count) 个"))
        }
        // The old take is kept beside the new one rather than thrown away.
        let stamp = Int(Date().timeIntervalSince1970)
        let fm = FileManager.default
        let newFrame = still.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        if newFrame {
            film.shots[index].still = still!
            try? fm.moveItem(at: film.still(number), to: film.folder.appendingPathComponent(String(format: "shot-%02d.take-\(stamp).png", number)))
        }
        if let motion, !motion.trimmingCharacters(in: .whitespaces).isEmpty { film.shots[index].motion = motion }
        try? fm.moveItem(at: film.clip(number), to: film.folder.appendingPathComponent(String(format: "shot-%02d.take-\(stamp).mp4", number)))
        try? fm.moveItem(at: film.file, to: film.folder.appendingPathComponent("film.cut-\(stamp).mp4"))
        film.shots[index].state = .waiting
        film.shots[index].note = nil
        film.shots[index].hq = hq ? true : nil
        film.state = .shooting
        save(film)
        produce(film.id)
        return .success(film)
    }

    /// Everything that is not done yet, shot by shot, then the cut.
    private func produce(_ id: String) {
        shooting = id
        Task { @MainActor in
            defer { shooting = nil }
            guard var film = films.first(where: { $0.id == id }) else { return }
            let client = DiffuserClient.shared
            let fm = FileManager.default
            let sheet = CompanionCharacter.shared.sheet
            for index in film.shots.indices where film.shots[index].state != .done {
                let shot = film.shots[index]
                do {
                    if !fm.fileExists(atPath: film.still(shot.id).path) {
                        update(&film, index, .drawing)
                        let dressed = film.lead ? film.wears.map { "she is wearing \($0)" } : nil
                        let frame = [shot.still, dressed, film.look].compactMap { $0 }.filter { !$0.isEmpty }
                            .joined(separator: ". ")
                        let made: URL
                        if film.lead, let anchor = CompanionCharacter.shared.anchorURL {
                            made = try await client.edit(
                                prompt: "keep this exact woman, same face. \(frame). \(sheet.style)",
                                from: anchor, into: film.folder,
                                seed: CompanionCharacter.seed(for: film.id + shot.still))
                        } else {
                            made = try await client.generate(prompt: frame, into: film.folder, width: 768, height: 768)
                        }
                        try? fm.moveItem(at: URL(fileURLWithPath: made.path + ".txt"),
                                         to: URL(fileURLWithPath: film.still(shot.id).path + ".txt"))
                        try fm.moveItem(at: made, to: film.still(shot.id))
                    }
                    update(&film, index, .filming)
                    let fine = shot.hq == true
                    if fine, let crowded = await BoxServices.shared.roomForHQ() {
                        throw Failure.message(crowded)
                    }
                    _ = try await client.generateVideo(
                        prompt: shot.motion, to: film.clip(shot.id), seconds: film.seconds,
                        width: 704, height: 704, from: film.still(shot.id), hq: fine,
                        timeout: fine ? 3600 : 1800)
                    await speak(film, film.shots[index])
                    update(&film, index, .done)
                } catch {
                    // A server that is not there fails every shot after this
                    // one too, in two seconds, and what gets cut is a one-shot
                    // "film". (It happened: the edit server died under the
                    // box's memory load after the first still.) So the film
                    // stops here, says what it could not reach, keeps the
                    // shots it has, and can be carried on when the service is
                    // back — nothing is marked failed that was never tried.
                    if Self.isUnreachable(error) {
                        let stage = film.shots[index].state == .drawing ? "出图/改图服务" : "出片服务"
                        film.shots[index].state = .waiting
                        film.state = .failed
                        film.note = "\(stage)连不上（\(error.localizedDescription)）。服务起来后接着拍：film_reshoot 不带 shot，或片场里点「接着拍」"
                        save(film)
                        return
                    }
                    film.shots[index].note = error.localizedDescription
                    update(&film, index, .failed)
                }
            }
            // Cut whatever was shot: three good shots and a failed one is
            // still a film, and a better answer than nothing after ten minutes.
            let finished = film.shots.filter { $0.state == .done }
            let clips = finished.map { film.clip($0.id) }
            let voices = finished.map { film.voice($0.id) }
            guard !clips.isEmpty else {
                film.state = .failed
                film.note = "一个镜头都没拍成：" + (film.shots.first?.note ?? "")
                save(film)
                return
            }
            film.state = .cutting
            save(film)
            do {
                try await Self.cut(clips, voices: voices, to: film.file)
                film.state = .done
                let failed = film.shots.count - clips.count
                film.note = failed == 0 ? nil : "\(failed) 个镜头没拍成，剪的是其余的"
            } catch {
                film.state = .failed
                film.note = "剪不出来：\(error.localizedDescription)"
            }
            save(film)
        }
    }

    /// The shot's line, spoken by the TTS on this Mac and kept beside the clip.
    /// A film is still a film without it: if the service is not there the
    /// line is simply left unsaid.
    private func speak(_ film: Film, _ shot: Shot) async {
        guard let line = shot.narration, !line.isEmpty,
              !FileManager.default.fileExists(atPath: film.voice(shot.id).path),
              let audio = await Self.synthesize(line) else { return }
        try? audio.write(to: film.voice(shot.id), options: .atomic)
    }

    /// Change what is said over a shot — or, with an empty line, say nothing —
    /// and cut again. Nothing is filmed: a voice-over is a second and a half
    /// of work, and re-rolling a shot to reword a sentence would be absurd.
    func narrate(film id: String, shot number: Int, line: String) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        guard var film = films.first(where: { $0.id == id || $0.title == id }),
              let index = film.shots.firstIndex(where: { $0.id == number }) else {
            return .failure(.message("没有这部片子或这个镜头"))
        }
        let said = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = Int(Date().timeIntervalSince1970)
        let fm = FileManager.default
        try? fm.moveItem(at: film.voice(number), to: film.folder.appendingPathComponent(String(format: "shot-%02d.take-\(stamp).wav", number)))
        film.shots[index].narration = said.isEmpty ? nil : said
        film.state = .cutting
        save(film)
        shooting = film.id
        Task { @MainActor in
            defer { shooting = nil }
            await speak(film, film.shots[index])
            try? fm.moveItem(at: film.file, to: film.folder.appendingPathComponent("film.cut-\(stamp).mp4"))
            let done = film.shots.filter { $0.state == .done }
            do {
                try await Self.cut(done.map { film.clip($0.id) }, voices: done.map { film.voice($0.id) }, to: film.file)
                film.state = .done
            } catch {
                film.state = .failed
                film.note = "剪不出来：\(error.localizedDescription)"
            }
            save(film)
        }
        return .success(film)
    }

    /// One line through the user's own Kokoro. The request is the one the
    /// companion's voice uses, field for field — `speaker` and `language`,
    /// not `voice`, or it reads Chinese out as "Chinese letter, Chinese
    /// letter" — and the padding Kokoro puts round every clip is trimmed.
    static func synthesize(_ text: String) async -> Data? {
        let chosen = UserDefaults.standard.string(forKey: "kinclaw.backend.tts") ?? ""
        let base = chosen.isEmpty ? "http://localhost:8001" : chosen.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/synthesize") else { return nil }
        let preferred = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
        let chinese = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let speaker = (preferred.isEmpty || preferred == "auto") ? (chinese ? "zf_xiaoxiao" : "af_bella") : preferred
        let speed = UserDefaults.standard.double(forKey: "kinclaw.voice.tts.speed")
        let body: [String: Any] = ["text": text, "speaker": speaker,
                                   "language": TextSegmenter.language(forVoice: speaker),
                                   "speed": speed > 0 ? speed : 1.0]
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 44 else { return nil }
        return WAVTrim.trim(data)
    }

    /// Carry on with a film that stopped: everything not finished is tried
    /// again, finished shots are left alone, and it is cut at the end.
    func resume(film id: String) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        guard var film = films.first(where: { $0.id == id || $0.title == id }) else {
            return .failure(.message("没有这部片子：\(id)"))
        }
        guard film.shots.contains(where: { $0.state != .done }) else {
            return .failure(.message("「\(film.title)」的镜头都拍好了；要重拍哪个，给 shot"))
        }
        for index in film.shots.indices where film.shots[index].state != .done {
            film.shots[index].state = .waiting
            film.shots[index].note = nil
        }
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(at: film.file, to: film.folder.appendingPathComponent("film.cut-\(stamp).mp4"))
        film.state = .shooting
        film.note = nil
        save(film)
        produce(film.id)
        return .success(film)
    }

    /// The service is not there, as opposed to having refused the work.
    private static func isUnreachable(_ error: Error) -> Bool {
        if let url = error as? URLError {
            return [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet,
                    .timedOut, .dnsLookupFailed].contains(url.code)
        }
        let text = error.localizedDescription.lowercased()
        return ["could not connect", "连不上", "connection refused", "network connection was lost",
                "timed out", "offline"].contains { text.contains($0) }
    }

    private func update(_ film: inout Film, _ index: Int, _ state: Shot.State) {
        film.shots[index].state = state
        save(film)
    }

    private func save(_ film: Film) {
        if let at = films.firstIndex(where: { $0.id == film.id }) { films[at] = film } else { films.insert(film, at: 0) }
        if let data = try? Self.encoder.encode(film) {
            try? data.write(to: film.folder.appendingPathComponent("film.json"), options: .atomic)
        }
    }

    // MARK: - The cut

    /// Shots end to end, each dissolving into the next, sound faded across.
    ///
    /// Two video tracks and two audio tracks, the shots dealt alternately
    /// between them, because a dissolve needs both pictures to exist at once
    /// and a single track cannot overlap itself.
    ///
    /// `voices` runs alongside `clips`: where a shot has a spoken line, it
    /// goes on a track of its own a quarter of a second into the shot, and
    /// the shot's own sound sits at a third under it — waves under a
    /// sentence, not against it.
    static func cut(_ clips: [URL], voices: [URL] = [], fade: Double = 0.4, to out: URL) async throws {
        let composition = AVMutableComposition()
        let video = (0..<2).compactMap { _ in composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) }
        let audio = (0..<2).compactMap { _ in composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
        guard video.count == 2, audio.count == 2 else { throw Failure.message("建不了剪辑轨道") }

        let overlap = CMTime(seconds: fade, preferredTimescale: 600)
        var cursor = CMTime.zero
        var spans: [(track: Int, range: CMTimeRange)] = []
        var size = CGSize(width: 704, height: 704)
        for (index, url) in clips.enumerated() {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            if index == 0 { size = try await source.load(.naturalSize) }
            let lane = index % 2
            let range = CMTimeRange(start: .zero, duration: duration)
            try video[lane].insertTimeRange(range, of: source, at: cursor)
            if let sound = try await asset.loadTracks(withMediaType: .audio).first {
                try audio[lane].insertTimeRange(range, of: sound, at: cursor)
            }
            spans.append((lane, CMTimeRange(start: cursor, duration: duration)))
            cursor = CMTimeSubtract(CMTimeAdd(cursor, duration), overlap)
        }
        guard !spans.isEmpty else { throw Failure.message("没有能剪的镜头") }

        // One instruction per stretch of time: a shot alone, or two dissolving.
        // The spoken lines, and how loud each shot's own sound is allowed to be.
        let narration = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var level = [Float](repeating: 1, count: spans.count)
        for (index, span) in spans.enumerated() where index < voices.count {
            guard FileManager.default.fileExists(atPath: voices[index].path) else { continue }
            let asset = AVURLAsset(url: voices[index])
            guard let line = try? await asset.loadTracks(withMediaType: .audio).first,
                  let length = try? await asset.load(.duration) else { continue }
            let start = CMTimeAdd(span.range.start, CMTime(seconds: 0.25, preferredTimescale: 600))
            // A line that runs past the end of the film is cut there.
            let room = CMTimeSubtract(spans.last!.range.end, start)
            let use = CMTimeCompare(length, room) > 0 ? room : length
            guard CMTimeCompare(use, .zero) > 0 else { continue }
            try? narration?.insertTimeRange(CMTimeRange(start: .zero, duration: use), of: line, at: start)
            level[index] = 0.32
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        let mix = AVMutableAudioMix()
        var volumes: [AVMutableAudioMixInputParameters] = audio.map { AVMutableAudioMixInputParameters(track: $0) }
        volumes[spans[0].track].setVolume(level[0], at: .zero)
        for (index, span) in spans.enumerated() {
            let next = index + 1 < spans.count ? spans[index + 1] : nil
            let soloStart = index == 0 ? span.range.start : CMTimeAdd(span.range.start, overlap)
            let soloEnd = next == nil ? span.range.end : next!.range.start
            if CMTimeCompare(soloEnd, soloStart) > 0 {
                let alone = AVMutableVideoCompositionInstruction()
                alone.timeRange = CMTimeRange(start: soloStart, end: soloEnd)
                alone.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: video[span.track])]
                instructions.append(alone)
            }
            if let next {
                let dissolve = CMTimeRange(start: next.range.start, end: span.range.end)
                let both = AVMutableVideoCompositionInstruction()
                both.timeRange = dissolve
                let leaving = AVMutableVideoCompositionLayerInstruction(assetTrack: video[span.track])
                leaving.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: dissolve)
                let arriving = AVMutableVideoCompositionLayerInstruction(assetTrack: video[next.track])
                both.layerInstructions = [leaving, arriving]
                instructions.append(both)
                volumes[span.track].setVolumeRamp(fromStartVolume: level[index], toEndVolume: 0, timeRange: dissolve)
                volumes[next.track].setVolumeRamp(fromStartVolume: 0, toEndVolume: level[index + 1], timeRange: dissolve)
            }
        }
        if let narration { volumes.append(AVMutableAudioMixInputParameters(track: narration)) }
        mix.inputParameters = volumes
        let frame = AVMutableVideoComposition()
        frame.instructions = instructions
        frame.renderSize = size
        frame.frameDuration = CMTime(value: 1, timescale: 24)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.message("这台机器导不出视频")
        }
        let partial = out.deletingLastPathComponent().appendingPathComponent("film.partial.mp4")
        try? FileManager.default.removeItem(at: partial)
        export.outputURL = partial
        export.outputFileType = .mp4
        export.videoComposition = frame
        export.audioMix = mix
        await export.export()
        guard export.status == .completed else {
            throw Failure.message(export.error?.localizedDescription ?? "导出没完成")
        }
        if FileManager.default.fileExists(atPath: out.path) {
            _ = try FileManager.default.replaceItemAt(out, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: out)
        }
    }

    // MARK: - A storyboard from one sentence

    /// What a storyboard has to be, for whoever writes one.
    static let brief = """
        You are a film director writing a storyboard for a very short film made of 4-second shots. \
        Each shot is ONE still frame that is then animated, so: `still` describes a single photograph — \
        subject, place, light, framing — in concrete English; `motion` says what moves during those four \
        seconds (one simple action and one camera move at most: slow push in, pan, handheld drift) and ends \
        with what it sounds like ("sound of waves and distant gulls"). Keep motion simple: walking, turning, \
        looking, wind, water, light — not fights, not hands doing fine work, not text. `look` is what every \
        frame shares (film stock, palette, time of day). When the lead is "her", write `still` as "she is …" \
        and never describe her face or hair — she already has one — and say what she is wearing ONCE, in \
        `wears`, not in the shots: one line, head to foot, chosen for THIS story and its weather (a summer \
        dress for a beach, a coat and boots for a rainy street). It is added to every frame so she is \
        dressed the same throughout. Vary the framing from shot to shot: wide, medium, close. `narration` is \
        an optional line of voice-over for the shot, in the language the idea was written in: a storyteller's \
        sentence, not a description of the picture, and short enough to say in three seconds — a dozen \
        Chinese characters or eight English words. Leave it out where the shot should be left to breathe.
        """

    /// Ask the local brain for a storyboard. JSON in, JSON out.
    static func storyboard(for idea: String, shots: Int, lead: Bool, model _: String = "") async throws
        -> (title: String, look: String, wears: String, shots: [(still: String, motion: String)], narration: [String]) {
        guard let writer = await writer() else {
            throw Failure.message("找不到能写分镜的模型：\(OllamaCatalog.baseURL) 和本机 Ollama 上都没有可用的对话模型")
        }
        let model = writer.model
        guard let url = URL(string: writer.host + "/api/chat") else { throw Failure.message("Ollama 地址不对") }
        let ask = """
            Idea: \(idea)
            Lead: \(lead ? "her (the same woman in every shot)" : "none — nobody needs to recur")
            Shots: \(shots)
            Answer with JSON only: {"title": "...", "look": "...", "wears": "...", "shots": [{"still": "...", "motion": "...", "narration": "..."}]}
            """
        // Thinking off, and no JSON mode. Measured on kimi: with both on, this
        // request had not answered after three minutes — a model that reasons
        // first does all of it before the first byte when nothing is streamed,
        // and constrained decoding on top of that is slower still. With
        // thinking off and the shape merely asked for, sixteen seconds and a
        // better storyboard than the one written to test the pipeline.
        let body: [String: Any] = [
            "model": model, "stream": false, "think": false,
            "messages": [["role": "system", "content": brief], ["role": "user", "content": ask]],
        ]
        var request = URLRequest(url: url, timeoutInterval: 150)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        // What the server said, not "no usable storyboard": the first failure
        // here was a model the configured host does not have, and the message
        // that hid it cost a round of guessing.
        if let refusal = reply?["error"] as? String {
            throw Failure.message("\(model) @ \(writer.host)：\(refusal.prefix(160))")
        }
        guard let reply,
              let message = reply["message"] as? [String: Any],
              let text = message["content"] as? String,
              // Whatever is between the outermost braces: asked for JSON only,
              // a model still sometimes wraps it in a fence or a sentence.
              let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let board = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any],
              let list = board["shots"] as? [[String: Any]] else {
            throw Failure.message("大脑没给出能用的分镜")
        }
        let written = list.compactMap { item -> (String, String)? in
            guard let still = item["still"] as? String else { return nil }
            return (still, (item["motion"] as? String) ?? "gentle natural movement")
        }
        guard !written.isEmpty else { throw Failure.message("分镜是空的") }
        let lines = list.filter { $0["still"] is String }.map { ($0["narration"] as? String) ?? "" }
        return ((board["title"] as? String) ?? "", (board["look"] as? String) ?? "",
                (board["wears"] as? String) ?? "", written, lines)
    }

    /// Kept for callers that still pass a model; the writer is discovered.
    static var writerModel: String { UserDefaults.standard.string(forKey: "kinclaw.film.writer") ?? "" }

    /// Who writes storyboards: a capable chat model on the Ollama (or kinfer)
    /// the app is pointed at, else on this Mac's own.
    ///
    /// Discovered rather than assumed. There is no one "current brain" to
    /// read — the kernel holds that per soul — and the obvious default, kimi
    /// on this Mac, is not there at all when the app is pointed at a box on
    /// the LAN. So the host is asked what it has. `kinclaw.film.writer` names
    /// one outright for anybody who wants to.
    /// Every host that might have a writer, and what each has that could be one.
    static func candidates() async -> [(host: String, models: [String])] {
        var found: [(String, [String])] = []
        for host in hosts {
            let usable = await models(on: host).filter { name in !never.contains { name.lowercased().contains($0) } }
            if !usable.isEmpty { found.append((host, usable.sorted())) }
        }
        return found
    }

    private static var hosts: [String] {
        var list = [OllamaCatalog.baseURL]
        if !list.contains(OllamaCatalog.defaultBaseURL) { list.append(OllamaCatalog.defaultBaseURL) }
        return list
    }

    // Not an embedding model, not a toy, and not the one that starves the box
    // of the memory the video model needs.
    private static let never = ["embed", "bge", "nomic", "0.5b", "bench", "flash-next", "exp-local", "whisper"]

    private static func models(on host: String) async -> [String] {
        guard let url = URL(string: host + "/api/tags") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = list["models"] as? [[String: Any]] else { return [] }
        return entries.compactMap { $0["name"] as? String }
    }

    static func writer() async -> (host: String, model: String)? {
        let named = writerModel
        // Pinned to a host as well as a model: the same name can exist on two
        // machines, and only one of them is the one that was chosen.
        let pinned = UserDefaults.standard.string(forKey: "kinclaw.film.writer.host") ?? ""
        if !named.isEmpty, !pinned.isEmpty, await models(on: pinned).contains(named) { return (pinned, named) }
        var hosts = [OllamaCatalog.baseURL]
        if !hosts.contains(OllamaCatalog.defaultBaseURL) { hosts.append(OllamaCatalog.defaultBaseURL) }
        // Best first. Not an embedding model, not a toy, and not the one that
        // starves the box of the memory the video model needs.
        let ranks = ["kimi", "glm", "deepseek", "ornith", "qwen", "llama", "gemma", "mistral"]
        for host in hosts {
            guard let url = URL(string: host + "/api/tags") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "GET"
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let models = list["models"] as? [[String: Any]] else { continue }
            let names = models.compactMap { $0["name"] as? String }
            if !named.isEmpty, names.contains(named) { return (host, named) }
            let usable = names.filter { name in !never.contains { name.lowercased().contains($0) } }
            for family in ranks {
                if let pick = usable.first(where: { $0.lowercased().contains(family) }) { return (host, pick) }
            }
            if let any = usable.first { return (host, any) }
        }
        return nil
    }

    // MARK: - Small things

    enum Failure: Error, LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private static func slug(_ text: String) -> String {
        let kept = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(kept).split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "film" : String(joined.prefix(32))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
