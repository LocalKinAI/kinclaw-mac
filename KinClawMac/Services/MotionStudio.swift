import AVFoundation
import Foundation

/// A movement taken from a real performance, performed by her.
///
/// An evening went into asking a video model for tai chi in words — literal
/// poses, mid-movement stills, a reviewer that sent shots back for "no bent
/// knees, no shift of weight" — and what came back was a woman moving her arms.
/// The model cannot invent choreography. It can *follow* it: LTX's IC-LoRA
/// takes a control video, and a pose skeleton is one. So the movement comes
/// from somebody who can actually do it:
///
///   1. **A reference video** — the user's own, or one whose licence allows it
///      (the first was a Creative Commons tai chi form from YouTube). Only the
///      skeleton is taken from it (`MotionPose`): how a body moved, not whose
///      body, clothes or garden.
///   2. **Her starting still** — an edit of her anchor, shown the reference's
///      first frame for the pose and the distance, in her own place and
///      clothes; then her face is put back (`FilmReference`), because at
///      full length it is forty pixels wide.
///   3. **The skeleton is fitted onto her** in that still, and drawn as the
///      control video.
///   4. **Filmed in ten-second takes**, each one starting on the last frame of
///      the one before and following the next ten seconds of the same
///      performance — so the joins are continuous in picture *and* in motion,
///      and the whole can be as long as the reference. Measured: 4 s in 97 s,
///      10 s in 273 s, on the everyday q4 model; two tens joined with no
///      visible seam.
@MainActor
final class MotionStudio: ObservableObject {
    static let shared = MotionStudio()

    struct Segment: Codable, Identifiable, Equatable {
        var id: Int
        var state: State = .waiting
        var note: String?
        enum State: String, Codable { case waiting, filming, done, failed }
    }

    struct Take: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        /// The reference video's file name inside the take's folder.
        var source: String
        /// Where the movement came from — title, author, address, licence — so
        /// that anything published can say so. Creative Commons asks for it.
        var credit: String?
        var start: Double
        var seconds: Double
        /// Where she is and what she wears, in one sentence.
        var scene: String
        /// Length of one filmed segment, in seconds.
        var stretch: Double
        var segments: [Segment]
        var state: State = .waiting
        var note: String?
        /// The square of the source the body was tracked in: x, y, side.
        var cut: [Double]?
        /// Scale and shift that lay the skeleton over her: a, tx, ty.
        var fit: [Double]?
        var created = Date()

        enum State: String, Codable { case waiting, tracking, drawing, filming, joining, done, failed }

        @MainActor var folder: URL { MotionStudio.root.appendingPathComponent(id) }
        @MainActor var file: URL { folder.appendingPathComponent("take.mp4") }
        @MainActor var reference: URL { folder.appendingPathComponent(source) }
        @MainActor var still: URL { folder.appendingPathComponent("start.png") }
        @MainActor var sourceFirst: URL { folder.appendingPathComponent("source-first.png") }
        @MainActor var track: URL { folder.appendingPathComponent("track.json") }
        @MainActor func clip(_ n: Int) -> URL { folder.appendingPathComponent(String(format: "seg-%02d.mp4", n)) }
        @MainActor func pose(_ n: Int) -> URL { folder.appendingPathComponent(String(format: "pose-%02d.mp4", n)) }
        @MainActor func last(_ n: Int) -> URL { folder.appendingPathComponent(String(format: "seg-%02d.last.png", n)) }
        var finished: Int { segments.filter { $0.state == .done }.count }
        /// Frames in one segment: on the video model's 8k+1 grid, at 24 a second.
        var frames: Int { max(1, Int((stretch * 24 / 8).rounded())) * 8 + 1 }
    }

    /// `<art folder>/motion/` — beside her films.
    static var root: URL { CompanionArt.folder.appendingPathComponent("motion") }

    @Published private(set) var takes: [Take] = []
    @Published private(set) var working: String?
    /// What the work in hand is doing, for the tab: "在提取动作 120/481".
    @Published private(set) var progress: String?
    /// When the step in hand began. A ten-second stretch is five minutes of
    /// one unchanging sentence, and a spinner that says nothing for five
    /// minutes reads as stuck ("是不是卡住了啊"): the tab counts up from this.
    @Published private(set) var since: Date?
    /// How long a stretch has been taking, in seconds, from the ones done so far.
    @Published private(set) var usual: Double?

    init() {
        reload()
        if let unfinished = takes.first(where: { ![.done, .failed, .waiting].contains($0.state) }) { produce(unfinished.id) }
    }

    func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.root.path)) ?? []
        takes = names.compactMap { name -> Take? in
            let file = Self.root.appendingPathComponent(name).appendingPathComponent("motion.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? Self.decoder.decode(Take.self, from: data)
        }.sorted { $0.created > $1.created }
    }

    // MARK: - Making one

    /// Start a take. Returns at once; the work runs for minutes.
    func make(video: URL, title: String, start: Double, seconds: Double, scene: String, credit: String? = nil)
        -> Result<Take, FilmStudio.Failure> {
        guard working == nil else { return .failure(.message("正在拍「\(working!)」，等它拍完")) }
        guard FilmStudio.shared.shooting == nil else { return .failure(.message("片场正在拍片，两边用的是同一个出片服务，等它拍完")) }
        guard FileManager.default.fileExists(atPath: video.path) else { return .failure(.message("找不到这段视频：\(video.path)")) }
        guard CompanionCharacter.shared.anchorURL != nil else { return .failure(.message("她还没有锚图：先 character_new 定一张脸")) }
        if let trouble = CompanionArt.unreachableVolume(Self.root) { return .failure(.message(trouble)) }
        let length = min(max(seconds, 2), 120)
        let stretch = min(length, 10)
        let count = Int((length / stretch).rounded(.up))
        let stamp = Int(Date().timeIntervalSince1970)
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? video.deletingPathExtension().lastPathComponent : title
        var take = Take(id: "\(Self.slug(name))-\(stamp)", title: name, source: "source." + (video.pathExtension.isEmpty ? "mp4" : video.pathExtension),
                        credit: credit, start: max(start, 0), seconds: length, scene: scene, stretch: stretch,
                        segments: (1...count).map { Segment(id: $0) })
        do {
            try FileManager.default.createDirectory(at: take.folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: video, to: take.reference)
        } catch { return .failure(.message("存不下参考视频：\(error.localizedDescription)")) }
        take.state = .tracking
        save(take)
        produce(take.id)
        return .success(take)
    }

    /// Carry on with a take that stopped.
    func resume(_ id: String) -> Result<Take, FilmStudio.Failure> {
        guard working == nil else { return .failure(.message("正在拍「\(working!)」，等它拍完")) }
        guard var take = takes.first(where: { $0.id == id || $0.title == id }) else { return .failure(.message("没有这一条：\(id)")) }
        for index in take.segments.indices where take.segments[index].state != .done {
            take.segments[index].state = .waiting
            take.segments[index].note = nil
        }
        take.state = .tracking
        take.note = nil
        save(take)
        produce(take.id)
        return .success(take)
    }

    private func produce(_ id: String) {
        working = id
        Task { @MainActor in
            defer { working = nil; progress = nil; since = nil }
            guard var take = takes.first(where: { $0.id == id }) else { return }
            let fm = FileManager.default
            let client = DiffuserClient.shared
            do {
                // 1. The movement. Kept on disk: a carried-on take should not track again.
                let total = take.segments.count * (take.frames - 1) + 1
                var frames: [[CGPoint?]]
                if let kept = Self.readTrack(take.track), kept.count >= total {
                    frames = kept
                } else {
                    take.state = .tracking; save(take)
                    let fixed = take.cut.flatMap { $0.count == 3 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[2]) : nil }
                    let reference = take.reference, start = take.start
                    let tracked = try await MotionPose.track(reference, from: start, frames: total, cut: fixed) { done in
                        Task { @MainActor in MotionStudio.shared.progress = "在提取动作 \(done)/\(total)" }
                    }
                    frames = tracked.frames
                    take.cut = [tracked.cut.minX, tracked.cut.minY, tracked.cut.width].map { Double($0) }
                    if let first = tracked.first { MotionPose.write(first, to: take.sourceFirst) }
                    Self.writeTrack(frames, to: take.track)
                    save(take)
                }
                guard frames.count >= take.frames else {
                    throw FilmStudio.Failure.message("参考视频从第 \(Int(take.start)) 秒起不够 \(Int(take.stretch)) 秒")
                }

                // 2. Her, where the performer was standing, as the performer stood.
                if !fm.fileExists(atPath: take.still.path) {
                    take.state = .drawing; save(take)
                    progress = "在画她的起始画面"
                    guard let anchor = CompanionCharacter.shared.anchorURL else { throw FilmStudio.Failure.message("她还没有锚图") }
                    let scene = await FilmStudio.english(take.scene, as: "place she is in and what she is wearing")
                    let prompt = """
                        Full-length shot, her whole body visible, at the same camera distance and the same position in the \
                        frame as image 2. Image 1 is the woman: keep her exact face and hair. Image 2 shows only the body \
                        pose to copy exactly: the same stance, the same bend of the knees, the same lean of the torso, the \
                        same arm positions, seen from the same side. It is a different person: do not copy their face, \
                        their clothes or their surroundings. \(scene). \(CompanionCharacter.shared.sheet.style)
                        """
                    let made = try await client.edit(prompt: prompt, from: anchor, also: [take.sourceFirst], into: take.folder,
                                                     seed: CompanionCharacter.seed(for: take.id))
                    try? fm.moveItem(at: URL(fileURLWithPath: made.path + ".txt"), to: URL(fileURLWithPath: take.still.path + ".txt"))
                    try fm.moveItem(at: made, to: take.still)
                    await restoreFace(in: take)
                }

                // 3. The skeleton, laid over her.
                if take.fit == nil, let body = MotionPose.body(in: take.still), let opening = frames.first {
                    let fit = MotionPose.fit(opening, onto: body)
                    take.fit = [fit.a, fit.tx, fit.ty].map { Double($0) }
                    save(take)
                }
                let fit = take.fit.map { CGAffineTransform(a: CGFloat($0[0]), b: 0, c: 0, d: CGFloat($0[0]), tx: CGFloat($0[1]), ty: CGFloat($0[2])) } ?? .identity

                // 4. Filmed, a stretch at a time, each from where the last one stopped.
                take.state = .filming; save(take)
                await BoxServices.shared.refreshMemory()       // so that boxHasRoom is about now
                let scene = await FilmStudio.english(take.scene, as: "place she is in and what she is wearing")
                let words = "\(scene). She follows the reference movement exactly, slowly and continuously, her whole body taking "
                    + "part. She stays in the frame. Static camera. Ambient sound only: wind, birds, her breath."
                for index in take.segments.indices where take.segments[index].state != .done {
                    let number = take.segments[index].id
                    progress = "在拍第 \(number)/\(take.segments.count) 段"
                    since = Date()
                    take.segments[index].state = .filming; save(take)
                    let from = index * (take.frames - 1)
                    guard from + take.frames <= frames.count else { throw FilmStudio.Failure.message("动作不够长了") }
                    try await MotionPose.render(Array(frames[from..<(from + take.frames)]), fitted: fit, to: take.pose(number))
                    let opening: URL
                    if index == 0 { opening = take.still } else {
                        opening = try await FilmStudio.lastFrame(of: take.clip(take.segments[index - 1].id),
                                                                 to: take.last(take.segments[index - 1].id), fresh: true)
                    }
                    if fm.fileExists(atPath: take.clip(number).path) {
                        try? fm.moveItem(at: take.clip(number), to: take.folder.appendingPathComponent(
                            String(format: "seg-%02d.take-\(Int(Date().timeIntervalSince1970)).mp4", number)))
                    }
                    _ = try await client.generateVideo(prompt: words, to: take.clip(number), seconds: take.stretch,
                                                       width: 704, height: 704, from: opening, following: take.pose(number),
                                                       lowRAM: Self.boxHasRoom ? false : nil, timeout: 3600)
                    if let began = since { usual = Date().timeIntervalSince(began) }
                    take.segments[index].state = .done; save(take)
                }

                // 5. Joined end to end. No dissolves: the joins are continuous already.
                take.state = .joining; save(take)
                progress = "在接起来"
                if fm.fileExists(atPath: take.file.path) {
                    try? fm.moveItem(at: take.file, to: take.folder.appendingPathComponent("take.cut-\(Int(Date().timeIntervalSince1970)).mp4"))
                }
                try await Self.join(take.segments.map { take.clip($0.id) }, to: take.file)
                take.state = .done
                take.note = nil
            } catch {
                take.state = .failed
                take.note = FilmStudio.isUnreachable(error)
                    ? "盒子上的服务连不上（\(error.localizedDescription)）。起来之后点「接着拍」"
                    : error.localizedDescription
                for index in take.segments.indices where take.segments[index].state == .filming { take.segments[index].state = .waiting }
            }
            save(take)
        }
    }

    /// Her face, put back: at full length it is forty pixels across and an
    /// editor's forty-pixel face is nobody's. Same pass the Film tab uses.
    private func restoreFace(in take: Take) async {
        guard let anchor = CompanionCharacter.shared.anchorURL else { return }
        let head = take.folder.appendingPathComponent("start.head.png")
        guard let found = FilmReference.head(of: take.still, to: head),
              let answer = try? await DiffuserClient.shared.edit(prompt: FilmReference.headPrompt, from: head, also: [anchor],
                                                                 into: take.folder, seed: CompanionCharacter.seed(for: take.id + "head"))
        else { return }
        let fixed = take.folder.appendingPathComponent("start.faced.png")
        let fm = FileManager.default
        if FilmReference.inlay(answer, into: take.still, at: found.face, as: fixed),
           (try? fm.moveItem(at: take.still, to: take.folder.appendingPathComponent("start.drawn.png"))) != nil {
            try? fm.moveItem(at: fixed, to: take.still)
        }
        try? fm.moveItem(at: answer, to: take.folder.appendingPathComponent("start.head-answer.png"))
        try? fm.moveItem(at: URL(fileURLWithPath: answer.path + ".txt"), to: take.folder.appendingPathComponent("start.head-answer.png.txt"))
    }

    /// Segments end to end, picture and sound. Each after the first starts one
    /// frame in: its first frame *is* the last frame of the one before.
    static func join(_ clips: [URL], to out: URL) async throws {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw FilmStudio.Failure.message("建不了剪辑轨道") }
        var cursor = CMTime.zero
        for (index, clip) in clips.enumerated() {
            let asset = AVURLAsset(url: clip)
            let length = try await asset.load(.duration)
            let skip = index == 0 ? CMTime.zero : CMTime(value: 1, timescale: 24)
            let range = CMTimeRange(start: skip, duration: CMTimeSubtract(length, skip))
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                try video.insertTimeRange(range, of: track, at: cursor)
            }
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                try? audio.insertTimeRange(range, of: track, at: cursor)
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw FilmStudio.Failure.message("导不出来")
        }
        export.outputURL = out
        export.outputFileType = .mp4
        await export.export()
        if export.status != .completed { throw export.error ?? FilmStudio.Failure.message("导不出来") }
    }

    // MARK: - Small things

    /// Whether the box can afford to hold the whole model in memory rather
    /// than stream it from disk: more than a third of its memory free, as of
    /// the last time the box was asked.
    static var boxHasRoom: Bool { (BoxServices.shared.memoryFree ?? 0) >= 35 }

    private static func writeTrack(_ frames: [[CGPoint?]], to file: URL) {
        let plain = frames.map { $0.map { point -> [Double] in point.map { [Double($0.x), Double($0.y)] } ?? [] } }
        if let data = try? JSONSerialization.data(withJSONObject: plain) { try? data.write(to: file, options: .atomic) }
    }

    private static func readTrack(_ file: URL) -> [[CGPoint?]]? {
        guard let data = try? Data(contentsOf: file),
              let plain = try? JSONSerialization.jsonObject(with: data) as? [[[Double]]] else { return nil }
        return plain.map { $0.map { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } }
    }

    private func save(_ take: Take) {
        if let at = takes.firstIndex(where: { $0.id == take.id }) { takes[at] = take } else { takes.insert(take, at: 0) }
        if let data = try? Self.encoder.encode(take) {
            try? data.write(to: take.folder.appendingPathComponent("motion.json"), options: .atomic)
        }
    }

    private static func slug(_ text: String) -> String {
        let kept = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(kept).split(separator: "-").joined(separator: "-")
        return String(joined.prefix(32)).isEmpty ? "take" : String(joined.prefix(32))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
