import AppKit
import Foundation

/// Who she is, kept as one anchor image and the words that made it.
///
/// A companion built out of text-to-image calls is a different woman in every
/// picture: the same prompt and the same seed drift the moment the scene
/// changes, and a four-step turbo model drifts hardest. So identity does not
/// live in the prompt here. It lives in one file.
///
/// The pipeline, and why each step uses the model it does:
///
///   1. **Candidates** — the text-to-image server (Boogu Image Turbo, 14s a
///      picture) draws several faces from one description, different seeds.
///      Cheap enough to be picky, which matters: this is the only step where
///      you get to choose what she looks like.
///   2. **The anchor** — the chosen candidate goes through the edit server
///      once ("same woman, neutral background") and *that* is the anchor.
///      Without this pass the anchor is Boogu's rendering while every scene
///      is Kontext's, and her skin and light change between pictures even
///      though her face does not.
///   3. **Scenes** — every later picture is an instruction edit of the
///      anchor: somewhere else, wearing something else, another time of day.
///      Identity comes from the input image, not from the words.
///   4. **Clips** — LTX-2 animates a scene image (image-to-video), so the
///      person who moves is the person in the picture.
///
/// Her sheet and her anchor live inside the art folder, so pointing that at
/// an external disk moves her with it, and under a dot-prefixed folder, which
/// the art rotation skips — the anchor is a working file, not a background.
@MainActor
final class CompanionCharacter: ObservableObject {
    static let shared = CompanionCharacter()

    /// Everything that decides how she looks, in one place. English, because
    /// that is what the models were trained on; the name is for the user.
    struct Sheet: Codable, Equatable {
        var name = ""
        /// The identity clause. One sentence, and then never changed —
        /// editing it is editing who she is, which is what the anchor is for.
        var look = ""
        /// Relative to the art folder, so the drive can move.
        var anchor: String?
        var seed: Int?
        var style = "photograph, natural light, 50mm, shallow depth of field"
        var negative = "cartoon, 3d render, illustration, extra fingers, text, watermark"

        var isReady: Bool { anchor != nil }
    }

    @Published private(set) var sheet = Sheet()
    @Published private(set) var candidates: [URL] = []
    @Published private(set) var busy = false
    /// What just happened, for the row in the picker.
    @Published private(set) var note: String?

    private init() { load() }

    // MARK: - Where she is kept

    /// Hidden from the art rotation, which skips dot-prefixed names.
    static var home: URL { CompanionArt.folder.appendingPathComponent(".her") }
    static var sheetFile: URL { home.appendingPathComponent("character.json") }
    static var candidatesFolder: URL { home.appendingPathComponent("candidates") }

    var anchorURL: URL? {
        sheet.anchor.map { CompanionArt.folder.appendingPathComponent($0) }
    }

    func load() {
        candidates = (try? FileManager.default.contentsOfDirectory(
            at: Self.candidatesFolder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard let data = try? Data(contentsOf: Self.sheetFile),
              let loaded = try? JSONDecoder().decode(Sheet.self, from: data) else { return }
        sheet = loaded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.home, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(sheet).write(to: Self.sheetFile)
    }

    func rename(_ name: String) {
        sheet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    // MARK: - 1. Candidates

    /// The prompt that draws her: her own description, then the house style.
    /// Adult and fictional, said out loud in the prompt rather than assumed.
    private func portraitPrompt(_ look: String) -> String {
        "portrait of an adult woman, \(look), \(sheet.style), looking at the camera"
    }

    /// Draw `count` faces from one description. Sequential: the server holds
    /// one model and answers one request at a time.
    func makeCandidates(look rawLook: String, count: Int = 4) {
        guard !busy else { return }
        let look = rawLook.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !look.isEmpty else { note = "先写一句她长什么样"; return }
        busy = true
        note = "在画 \(count) 张候选…（每张约 15 秒）"
        sheet.look = look
        save()

        Task { @MainActor in
            let client = DiffuserClient.shared
            try? FileManager.default.createDirectory(
                at: Self.candidatesFolder, withIntermediateDirectories: true)
            var made: [URL] = []
            var failure: String?
            for index in 0..<count {
                let seed = Int.random(in: 1_000...90_000)
                do {
                    let file = try await client.generate(
                        prompt: portraitPrompt(look), into: Self.candidatesFolder,
                        width: 768, height: 768, seed: seed)
                    // The seed is how a candidate can be redrawn bigger later.
                    let named = Self.candidatesFolder
                        .appendingPathComponent("cand-\(seed).png")
                    try? FileManager.default.moveItem(at: file, to: named)
                    try? FileManager.default.removeItem(at: file.appendingPathExtension("txt"))
                    made.append(named)
                    note = "画了 \(made.count)/\(count) 张"
                } catch {
                    failure = error.localizedDescription
                    break
                }
                _ = index
            }
            candidates = ((try? FileManager.default.contentsOfDirectory(
                at: Self.candidatesFolder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            busy = false
            note = failure.map { "画候选失败：\($0)" }
                ?? "\(made.count) 张候选画好了，挑一张"
        }
    }

    // MARK: - 2. The anchor

    /// Adopt a candidate: one normalising pass through the edit server, and
    /// the result becomes the anchor every scene is edited from.
    ///
    /// The pass is not cosmetic. It moves her into the rendering of the model
    /// that will draw every later picture, so the anchor and the scenes agree
    /// about her skin and the light, not only about her face.
    func adopt(_ candidate: URL) {
        guard !busy else { return }
        busy = true
        note = "在定妆…（一次编辑，约一分钟）"

        Task { @MainActor in
            let client = DiffuserClient.shared
            let seed = Int(candidate.deletingPathExtension().lastPathComponent
                .components(separatedBy: "-").last ?? "") 
            do {
                let normalised = try await client.edit(
                    prompt: "keep this exact woman, same face, neutral light grey background, "
                          + "natural soft light, head and shoulders, sharp focus",
                    from: candidate, into: Self.home,
                    seed: Self.seed(for: candidate.lastPathComponent))
                let anchor = Self.home.appendingPathComponent("anchor.png")
                try? FileManager.default.removeItem(at: anchor)
                try FileManager.default.moveItem(at: normalised, to: anchor)
                try? FileManager.default.removeItem(at: normalised.appendingPathExtension("txt"))
                sheet.anchor = ".her/anchor.png"
                sheet.seed = seed
                save()
                note = "定妆好了，以后每张都是她"
            } catch {
                // Worth saying plainly: without the edit server there is no
                // consistency to be had, only a similar-looking stranger.
                note = "定妆失败：\(error.localizedDescription)"
            }
            busy = false
        }
    }

    /// Take a candidate as-is, without the normalising pass — for when the
    /// edit server is not up and a face now beats a consistent face later.
    func adoptRaw(_ candidate: URL) {
        let anchor = Self.home.appendingPathComponent("anchor.png")
        try? FileManager.default.createDirectory(at: Self.home, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: anchor)
        guard (try? FileManager.default.copyItem(at: candidate, to: anchor)) != nil else {
            note = "存不下锚图：\(anchor.path)"
            return
        }
        sheet.anchor = ".her/anchor.png"
        save()
        note = "用了这张当锚图（没过定妆，风格以后可能跳一次）"
    }

    /// A small, stable seed for an instruction.
    ///
    /// Two reasons it is not random. The same instruction should give the
    /// same picture — "her in the kitchen" is a thing she has, not a dice
    /// roll — and big random seeds are where the editor was seen returning
    /// undenoised latents: measured on FLUX.1-Kontext int8, seed 1234 drew
    /// the portrait and seed 473366517 drew coloured static, same weights
    /// and same prompt. The server catches that now and retries; staying in
    /// a small range means it rarely has to.
    static func seed(for text: String) -> Int {
        var hash: UInt64 = 5381
        for byte in text.utf8 { hash = (hash << 5) &+ hash &+ UInt64(byte) }
        return Int(hash % 89_000) + 1_000
    }

    // MARK: - 3. Scenes

    /// Put her somewhere, or in something else. An instruction, not a caption.
    ///
    /// The picture lands in the mood's folder with the instruction as its
    /// sidecar, which is what lets her show it when the conversation turns
    /// that way — the art matcher reads both.
    @discardableResult
    func scene(_ instruction: String, mood: String? = nil) async -> Result<URL, Error> {
        guard let anchor = anchorURL,
              FileManager.default.fileExists(atPath: anchor.path) else {
            let error = DiffuserClient.Failure.message("还没有锚图——先画候选、定妆")
            note = error.localizedDescription
            return .failure(error)
        }
        let folder = (mood?.isEmpty == false)
            ? CompanionArt.folder.appendingPathComponent(mood!)
            : CompanionArt.folder
        note = "在改：\(instruction)"
        do {
            let file = try await DiffuserClient.shared.edit(
                prompt: "keep this exact woman, same face. \(instruction). \(sheet.style)",
                from: anchor, into: folder, seed: Self.seed(for: instruction))
            note = "有了：\(file.lastPathComponent)"
            NotificationCenter.default.post(name: .kinclawCompanionArtGrew, object: nil)
            return .success(file)
        } catch {
            note = "改不出来：\(error.localizedDescription)"
            return .failure(error)
        }
    }

    // MARK: - Somewhere she has never been

    /// The place being made, if one is.
    @Published private(set) var building: String?
    /// Subjects already attempted this session, so a topic that keeps coming
    /// up does not queue the same three minutes of work again.
    private var asked: Set<String> = []

    /// Build a scene for a subject the conversation named and she has no
    /// place for.
    ///
    /// Returns at once. The scene takes about three minutes — one edit for
    /// the still, two clips for waiting and for talking — and until it lands
    /// she stays where she was, which is the whole point: a companion who
    /// blanks out while a picture renders is worse than one who keeps talking
    /// to you in her kitchen. When it lands she is simply there the next time
    /// the subject comes up.
    func wantScene(_ subject: String) {
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard name.count >= 3, building == nil, !asked.contains(name),
              let anchor = anchorURL else { return }
        let folder = CompanionArt.folder.appendingPathComponent("scenes/\(name)")
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        asked.insert(name)
        building = name
        note = "在给「\(name)」造场景…（三分钟上下，先在原地陪着你）"

        Task { @MainActor in
            defer { building = nil }
            let client = DiffuserClient.shared
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // The subject arrives as one English word — the reply's tag
                // rule asks for exactly that — so it is a place, not a caption.
                let made = try await client.edit(
                    prompt: "keep this exact woman, same face. put her in a real \(name) scene, "
                          + "waist up, natural light. \(sheet.style)",
                    from: anchor, into: folder, seed: Self.seed(for: name))
                let still = folder.appendingPathComponent("still.png")
                try? FileManager.default.removeItem(at: still)
                try FileManager.default.moveItem(at: made, to: still)
                try? name.write(to: folder.appendingPathComponent("about.txt"),
                                atomically: true, encoding: .utf8)
                for (role, motion) in [
                    ("wait", "she looks at the camera, a soft smile, tiny natural movements"),
                    ("talk", "she talks to the camera, speaking naturally, mouth moving, small gestures"),
                ] {
                    _ = try await client.generateVideo(
                        prompt: motion, to: folder.appendingPathComponent("\(role).mp4"),
                        seconds: 4, width: 704, height: 704, from: still)
                    NotificationCenter.default.post(name: .kinclawCompanionArtGrew, object: nil)
                }
                note = "「\(name)」这个地方做好了"
            } catch {
                // Leave the folder: a half-made scene has no wait or talk clip,
                // so the scanner ignores it and nothing shows a broken place.
                note = "造不出「\(name)」：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 4. Clips

    /// Animate one of her pictures. Image-to-video, so it is her that moves.
    @discardableResult
    func clip(from image: URL, seconds: Double = 4, mood: String? = nil,
              motion: String = "she smiles softly and looks at the camera, "
                             + "gentle natural movement") -> URL {
        let folder = (mood?.isEmpty == false)
            ? CompanionArt.folder.appendingPathComponent(mood!)
            : CompanionArt.folder
        return DiffuserClient.shared.startVideo(
            prompt: motion, into: folder, seconds: seconds, from: image)
    }

    /// A day's worth of her, generated in the background.
    ///
    /// The scenes are ordinary life rather than a photoshoot, and each one is
    /// filed under the mood it belongs to, because the companion picks art by
    /// mood first and by subject second.
    static let dailyScenes: [(mood: String, instruction: String)] = [
        ("开心", "she is in a sunny kitchen making coffee, wearing an oversized white shirt, morning"),
        ("开心", "she is walking in a park in autumn, wearing a beige coat and a scarf"),
        ("温柔", "she is reading on a sofa under a warm lamp in the evening, wearing a knitted sweater"),
        ("温柔", "she is by a rainy window holding a mug, soft grey light"),
        ("好奇", "she is in a bookshop looking at a shelf, wearing a denim jacket"),
        ("好奇", "she is at a night market, warm lantern light, wearing a light jacket"),
        ("困", "she is on a bed in the early morning, hair a little messy, soft light, pyjamas"),
        ("担心", "she is waiting at a bus stop in the rain, looking down the street"),
    ]

    /// Fill the mood folders with `dailyScenes`, one at a time.
    func growLibrary(_ scenes: [(mood: String, instruction: String)] = dailyScenes) {
        guard !busy else { return }
        guard anchorURL != nil else { note = "先定妆，再长场景"; return }
        busy = true
        note = "在长场景库（\(scenes.count) 张，一张一分钟上下）"

        Task { @MainActor in
            var done = 0
            for spec in scenes {
                if case .failure = await scene(spec.instruction, mood: spec.mood) { break }
                done += 1
                note = "场景库 \(done)/\(scenes.count)"
            }
            NotificationCenter.default.post(name: .kinclawCompanionArtGrew, object: nil)
            busy = false
            note = "场景库长了 \(done) 张"
        }
    }
}
