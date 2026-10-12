import AppKit
import CoreImage
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
/// Qwen-Image-2.1-Turbo (bf16, float16 compute, its own 8 steps): 22s for
/// 768×768, 37s for 1024×1024. Boogu-Image-Turbo was 17s for 768×768 but
/// wrote Chinese twice over and lost the layout.
@MainActor
final class DiffuserClient: ObservableObject {
    static let shared = DiffuserClient()

    static let hostKey = "kinclaw.diffuser.host"
    /// The box, where the models and the memory are. A laptop can serve this
    /// too — the setting is one field in the picker.
    static let defaultHost = "http://192.168.0.21:8000"

    /// Video is a different model, and OllamaDiffuser serves one model per
    /// process — so it is a second server, on the next port, rather than a
    /// flag on this one. Unset means "same machine, 8001".
    static let videoHostKey = "kinclaw.diffuser.video.host"
    static let defaultVideoHost = "http://192.168.0.21:8001"

    /// And a third: editing an existing picture is a different model again.
    /// Text-to-image models cannot do it at all — Boogu, Krea, ERNIE, Lens and
    /// Ideogram ship only a txt2img path — so "her, but in a cafe" needs an
    /// editor, which takes the picture as its input and keeps the face: now
    /// Qwen-Image-2.1-Turbo's own editor on the same weights (48–60s at
    /// 1024×1024; it changes the lettering on a poster and leaves the rest).
    /// That is the whole trick behind a companion who stays the same person.
    static let editHostKey = "kinclaw.diffuser.edit.host"
    static let defaultEditHost = "http://192.168.0.21:8002"

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

    static var videoHost: String {
        get {
            let stored = UserDefaults.standard.string(forKey: videoHostKey) ?? ""
            return stored.isEmpty ? defaultVideoHost : stored
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: videoHostKey)
        }
    }

    static var editHost: String {
        get {
            let stored = UserDefaults.standard.string(forKey: editHostKey) ?? ""
            return stored.isEmpty ? defaultEditHost : stored
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: editHostKey)
        }
    }

    // MARK: - Multipart

    /// One multipart body. Text parts and file parts, in the order given.
    ///
    /// Written out by hand because URLSession has no multipart of its own and
    /// the alternative is a dependency for forty lines.
    private static func multipart(fields: [String: String],
                                  files: [(name: String, url: URL)]) throws -> (String, Data) {
        let boundary = "kinclaw-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                .data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        for file in files {
            let data = try Data(contentsOf: file.url)
            let type = ["png": "image/png", "mp4": "video/mp4", "wav": "audio/wav"][file.url.pathExtension.lowercased()]
                ?? "image/jpeg"
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("""
                Content-Disposition: form-data; name="\(file.name)"; \
                filename="\(file.url.lastPathComponent)"\r\n\
                Content-Type: \(type)\r\n\r\n
                """.data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return (boundary, body)
    }

    // MARK: - One picture at a time

    /// The drawing and the editing server take turns on the box: each holds all
    /// of Qwen-Image-2.1-Turbo, 29–30 GB once it has made a picture, and the box
    /// cannot keep both beside ComfyUI and a language model, so BoxServices lets
    /// one go when the other is wanted. A drawing and an edit from here must then
    /// never be in flight together, or starting one would cut the other off:
    /// pictures are made one at a time, in the order asked.
    private var making = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func takeTurn() async {
        guard making else { making = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func endTurn() {
        if waiting.isEmpty { making = false } else { waiting.removeFirst().resume() }
    }

    /// What the server said when it refused. Since OllamaDiffuser 2.3.0 a
    /// failure is an HTTP error with a `detail` — a missing input, or too little
    /// memory free to load the model — instead of a 200 with an error card.
    private static func refusal(_ data: Data) -> String {
        guard let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = answer["detail"] else { return "" }
        return "。服务说：" + String(((detail as? String) ?? "\(detail)").prefix(240))
    }

    // MARK: - Changing one

    /// Edit `source` by instruction and write the result into `folder`.
    ///
    /// This is the same person in a different place, wearing something else,
    /// at another time of day — which is a different operation from drawing a
    /// person who matches a description, and the reason a companion made of
    /// text-to-image calls is a different woman in every picture.
    ///
    /// An editor wants an instruction rather than a caption: "change her coat to
    /// a red one", not "a woman in a red coat".
    @discardableResult
    func edit(prompt: String, from source: URL, also references: [URL] = [], into folder: URL,
              steps: Int? = nil, guidance: Double? = nil, seed: Int? = nil,
              timeout: TimeInterval = 900) async throws -> URL {
        guard let url = Self.url("api/generate/img2img", on: Self.editHost) else {
            throw Failure.message("改图服务地址不对：\(Self.editHost)")
        }
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw Failure.message("要改成什么样？指令是空的") }
        let place = MediaPlacement.place(.edit)
        if place.isCloud {
            return try await editInCloud(cleaned, from: source, also: references, into: folder, seed: seed, on: place)
        }
        await takeTurn()
        defer { endTurn() }
        _ = await BoxServices.shared.ensure(.edit)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw Failure.message("找不到要改的那张图：\(source.path)")
        }
        if let trouble = CompanionArt.unreachableVolume(folder) {
            throw Failure.message("改好了，但存不下：" + trouble)
        }

        busy = true
        defer { busy = false }

        var fields = ["prompt": cleaned]
        if let steps { fields["num_inference_steps"] = String(steps) }
        if let guidance { fields["guidance_scale"] = String(guidance) }
        if let seed { fields["seed"] = String(seed) }
        // `image` is image 1 and sets the size; `images` are 2, 3… in order.
        // One picture for who and another for where is what keeps a film in
        // one place — see FilmStudio.recipe. A reference that has gone
        // missing is left out rather than failing the edit.
        let extras = references.filter { FileManager.default.fileExists(atPath: $0.path) }
        // Qwen-Image-2.1 makes only sizes whose sides are multiples of 32 and
        // refuses any other, and the answer is the size of image 1. So image 1
        // of another size goes over stretched to the nearest such size, and the
        // answer is stretched back: a few percent either way, and it still lines
        // up with the picture it was made from. The others the model resizes itself.
        let sent = Self.aligned(source)
        defer { if let sent { try? FileManager.default.removeItem(at: sent.file) } }
        let (boundary, body) = try Self.multipart(
            fields: fields, files: [(name: "image", url: sent?.file ?? source)] + extras.map { (name: "images", url: $0) })

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw Failure.message("改图失败（HTTP \(code)）：\(Self.editHost)" + Self.refusal(data))
        }
        guard data.count > 20_000, NSImage(data: data) != nil else {
            throw Failure.message("改图服务返回的不是一张正常的图（\(data.count) 字节），看它的日志")
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(Self.fileName(for: cleaned))
        try data.write(to: file)
        if let sent { Self.stretch(file, to: sent.size) }
        try? cleaned.write(to: file.appendingPathExtension("txt"),
                           atomically: true, encoding: .utf8)
        lastImage = file
        return file
    }

    // MARK: - In the cloud

    /// 画 placed on a cloud API (MediaPlaces). The provider draws at a size of
    /// its own choosing near the one asked; the picture is cut to the asked
    /// shape and scaled to it, the way a film reshapes its stills, so a caller
    /// gets the size it asked for wherever it was drawn.
    private func drawInCloud(_ prompt: String, into folder: URL, width: Int, height: Int,
                             seed: Int?, on place: MediaPlace) async throws -> URL {
        if let trouble = CompanionArt.unreachableVolume(folder) {
            throw Failure.message("画不了，存不下：" + trouble)
        }
        busy = true
        defer { busy = false }
        let data = try await MediaCloud.draw(prompt: prompt, width: width, height: height, seed: seed, on: place)
        let file = try keep(data, prompt: prompt, in: folder)
        FilmReference.reshape(file, to: CGSize(width: width, height: height))
        return file
    }

    /// 改 placed on a cloud API: image 1 and the references go up, the answer
    /// comes back the shape and size of image 1, as the box's editor's does.
    private func editInCloud(_ prompt: String, from source: URL, also references: [URL], into folder: URL,
                             seed: Int?, on place: MediaPlace) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw Failure.message("找不到要改的那张图：\(source.path)")
        }
        if let trouble = CompanionArt.unreachableVolume(folder) {
            throw Failure.message("改不了，存不下：" + trouble)
        }
        busy = true
        defer { busy = false }
        let extras = references.filter { FileManager.default.fileExists(atPath: $0.path) }
        let data = try await MediaCloud.edit(prompt: prompt, images: [source] + extras, seed: seed, on: place)
        let file = try keep(data, prompt: prompt, in: folder)
        if let size = CIImage(contentsOf: source)?.extent.size, size.width > 0, size.height > 0 {
            FilmReference.reshape(file, to: size)
        }
        return file
    }

    /// A picture from anywhere, written the way the box's are: named after
    /// its prompt, the prompt beside it (the art matcher reads these).
    private func keep(_ data: Data, prompt: String, in folder: URL) throws -> URL {
        guard data.count > 1_000, NSImage(data: data) != nil else {
            throw Failure.message("云端返回的不是一张图（\(data.count) 字节）")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(Self.fileName(for: prompt))
        // Whatever the provider encoded it as, the file is a PNG, as its name says.
        if let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            try png.write(to: file)
        } else {
            try data.write(to: file)
        }
        try? prompt.write(to: file.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        lastImage = file
        return file
    }

    /// A copy of `source` stretched to the nearest size whose sides are
    /// multiples of 32, and the size it had. Nil when it already is one, or
    /// cannot be read — then it goes as it is.
    private static func aligned(_ source: URL) -> (file: URL, size: CGSize)? {
        guard let picture = CIImage(contentsOf: source) else { return nil }
        let have = picture.extent.size
        let want = CGSize(width: nearest32(have.width), height: nearest32(have.height))
        guard want != have else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("kinclaw-edit-\(UUID().uuidString).png")
        return write(picture, at: want, to: file) ? (file, have) : nil
    }

    /// The nearest side Qwen-Image-2.1 will make: a multiple of 32.
    private static func nearest32(_ side: CGFloat) -> CGFloat { max(32, (side / 32).rounded() * 32) }

    /// The picture in `file` stretched to exactly `size`, in place.
    @discardableResult
    private static func stretch(_ file: URL, to size: CGSize) -> Bool {
        guard let picture = CIImage(contentsOf: file), picture.extent.size != size else { return false }
        return write(picture, at: size, to: file)
    }

    private static func write(_ picture: CIImage, at size: CGSize, to file: URL) -> Bool {
        let extent = picture.extent
        guard extent.width > 0, extent.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let made = picture
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: size.width / extent.width, y: size.height / extent.height))
            .cropped(to: CGRect(origin: .zero, size: size))
        return (try? CIContext().writePNGRepresentation(of: made, to: file, format: .RGBA8, colorSpace: space)) != nil
    }

    private static func url(_ path: String, on base: String? = nil) -> URL? {
        let root = base ?? host
        return URL(string: root.hasSuffix("/") ? root + path : root + "/" + path)
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
    /// The size defaults to 768×768. Qwen-Image-2.1 makes only sides that are
    /// multiples of 32 — the app's own sizes all are, a tool's may not be — so
    /// another size is drawn at the nearest one and stretched to what was
    /// asked. The timeout is generous because the first request after a model
    /// loads can be minutes.
    @discardableResult
    /// `steps` nil lets the server use the model's own — 8 on the schedule that
    /// ships with Qwen-Image-2.1-Turbo, 4 for boogu's turbo, 25 for the base
    /// Qwen-Image-2.1. A fixed 4 sent to every model was boogu's number, and
    /// Qwen asked for four steps draws a smudge.
    func generate(prompt: String, into folder: URL, steps: Int? = nil,
                  width: Int = 768, height: Int = 768,
                  seed: Int? = nil, timeout: TimeInterval = 600) async throws -> URL {
        guard let url = Self.url("api/generate") else {
            throw Failure.message("出图服务地址不对：\(Self.host)")
        }
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw Failure.message("要画什么？提示词是空的") }
        let place = MediaPlacement.place(.draw)
        if place.isCloud {
            return try await drawInCloud(cleaned, into: folder, width: width, height: height, seed: seed, on: place)
        }
        await takeTurn()
        defer { endTurn() }
        _ = await BoxServices.shared.ensure(.draw)

        busy = true
        defer { busy = false }

        let asked = CGSize(width: width, height: height)
        let drawn = CGSize(width: Self.nearest32(asked.width), height: Self.nearest32(asked.height))
        var body: [String: Any] = [
            "prompt": cleaned, "width": Int(drawn.width), "height": Int(drawn.height),
        ]
        if let seed { body["seed"] = seed }
        if let steps { body["steps"] = steps }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw Failure.message("出图失败（HTTP \(code)）：\(Self.host)" + Self.refusal(data))
        }
        // Before OllamaDiffuser 2.3.0 a model that failed mid-generation still
        // answered 200 with a small error image drawn by the server, so the
        // size is the tell.
        guard data.count > 20_000, NSImage(data: data) != nil else {
            throw Failure.message("服务返回的不是一张正常的图（\(data.count) 字节），看看它的日志")
        }

        if let trouble = CompanionArt.unreachableVolume(folder) {
            throw Failure.message("画好了，但存不下：" + trouble)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(Self.fileName(for: cleaned))
        try data.write(to: file)
        if drawn != asked { Self.stretch(file, to: asked) }
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

    // MARK: - Moving ones

    /// Generate a short clip and write it into `folder`.
    ///
    /// The companion already treats an mp4 in her art folder as a background
    /// loop, so this needs no new plumbing to show up: a clip made under 开心
    /// is one she stands in front of when she is happy.
    ///
    /// Minutes, not seconds — LTX-2 denoises every frame — so the default
    /// timeout is half an hour and the caller is expected to say so.
    @discardableResult
    func generateVideo(prompt: String, into folder: URL, seconds: Double = 4,
                       width: Int = 704, height: Int = 480,
                       seed: Int? = nil, mode: String? = nil, from image: URL? = nil,
                       timeout: TimeInterval = 1800) async throws -> URL {
        let name = Self.fileName(for: prompt).replacingOccurrences(of: ".png", with: ".mp4")
        return try await generateVideo(prompt: prompt, to: folder.appendingPathComponent(name),
                                       seconds: seconds, width: width, height: height,
                                       seed: seed, mode: mode, from: image, timeout: timeout)
    }

    /// The same, into a file whose name the caller already knows — which is
    /// what makes a job announceable before it finishes.
    @discardableResult
    func generateVideo(prompt: String, to file: URL, seconds: Double = 4,
                       width: Int = 704, height: Int = 480,
                       seed: Int? = nil, mode: String? = nil, from image: URL? = nil,
                       following control: URL? = nil,
                       speech: URL? = nil, frames: Int? = nil,
                       lowRAM: Bool? = nil,
                       hq: Bool = false,
                       timeout: TimeInterval = 1800) async throws -> URL {
        // `hq` is the q8 two-stage model on its own server: measured against
        // the everyday one on the same still, prompt and seed, a little
        // cleaner in faces and fabric, the same composition and motion, and
        // five times as long — 519 seconds against 104. A finishing pass for
        // a shot already approved, never the way a draft is made.
        let service: BoxServices.Kind = hq ? .filmHQ : .film
        let host = BoxServices.base(service)
        guard let url = Self.url("api/generate/video", on: host) else {
            throw Failure.message("视频服务地址不对：\(host)")
        }
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw Failure.message("要拍什么？提示词是空的") }
        let place = MediaPlacement.place(.film)
        if place.isCloud {
            // A cloud clip is a picture (or words) set moving. A pose to
            // follow, speech for the mouth, the q8 finish and an exact frame
            // count are the box's LTX servers' own.
            if control != nil || speech != nil || hq || frames != nil {
                throw Failure.message("动作参考、说话视频、精修和指定帧数只能在盒子上拍：设置 → 画·改·拍·声音 里把「拍」放回盒子")
            }
            if let image, !FileManager.default.fileExists(atPath: image.path) {
                throw Failure.message("找不到要动起来的那张图：\(image.path)")
            }
            // A cloud clip starts from a picture. Without one, the first frame
            // is drawn first — wherever 画 is placed — and set moving.
            var still = image
            if still == nil {
                still = try await generate(prompt: cleaned, into: file.deletingLastPathComponent(),
                                           width: width, height: height, seed: seed)
            }
            let clip = try await MediaCloud.film(prompt: cleaned, image: still, seconds: seconds,
                                                 width: width, height: height, on: place)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try clip.write(to: file)
            return file
        }
        _ = await BoxServices.shared.ensure(service)

        // No `busy` here: a clip runs for minutes, and the jobs list is
        // what says so. Blocking the picture button that long would be a
        // worse lie than no spinner at all.

        // An image turns this into image-to-video, which is the only way a
        // clip is the same person as the picture: LTX animates what it is
        // given rather than inventing someone who matches the words.
        var fields: [String: String] = [
            "prompt": cleaned, "seconds": String(seconds),
            "width": String(width), "height": String(height),
        ]
        if let seed { fields["seed"] = String(seed) }
        if let mode { fields["mode"] = mode }
        // The q4 pack's registry entry streams the transformer from disk
        // (`--low-ram`) so that it fits a 16 GB Mac. On a box with memory to
        // spare that is time spent for nothing, and a caller that knows says so.
        if let lowRAM { fields["low_ram"] = lowRAM ? "true" : "false" }
        var files: [(name: String, url: URL)] = []
        if let image {
            guard FileManager.default.fileExists(atPath: image.path) else {
                throw Failure.message("找不到要动起来的那张图：\(image.path)")
            }
            files.append((name: "image", url: image))
        }
        // A control video — a pose skeleton — makes this motion transfer: the
        // still says who and where, the skeleton says how she moves. It is
        // how a movement no sentence can describe gets filmed; see
        // MotionStudio.
        if let control {
            guard FileManager.default.fileExists(atPath: control.path) else {
                throw Failure.message("找不到动作参考：\(control.path)")
            }
            files.append((name: "control", url: control))
        }
        // Speech makes it audio-to-video: the face says these words (a talking
        // video, TalkingVideo). Only the q8 pack has the dev transformer the
        // a2v pipeline guides with, so callers ask for `hq`; the length is the
        // speech's, in 8k+1 frames, and replaces `seconds`.
        if let speech {
            guard FileManager.default.fileExists(atPath: speech.path) else {
                throw Failure.message("找不到要说的那段声音：\(speech.path)")
            }
            files.append((name: "audio", url: speech))
        }
        if let frames {
            fields["frames"] = String(frames)
            fields.removeValue(forKey: "seconds")
        }
        let (boundary, body) = try Self.multipart(fields: fields, files: files)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            // The server answers 400 with a sentence for everything a caller
            // can fix — no model loaded, an image model, a frame count off
            // the grid — so show that sentence rather than the number.
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
                .flatMap { $0["detail"] as? String }
            throw Failure.message(detail ?? "出视频失败（HTTP \(http?.statusCode ?? 0)）：\(Self.videoHost)")
        }
        guard data.count > 100_000 else {
            throw Failure.message("服务返回的不像一段视频（\(data.count) 字节），看看它的日志")
        }

        let home = file.deletingLastPathComponent()
        if let trouble = CompanionArt.unreachableVolume(home) {
            throw Failure.message("拍好了，但存不下：" + trouble)
        }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try data.write(to: file)
        try? cleaned.write(to: file.appendingPathExtension("txt"),
                           atomically: true, encoding: .utf8)
        lastImage = file
        return file
    }

    // MARK: - Jobs

    /// A clip being made. Minutes long, so it is something to look in on
    /// rather than something to wait for.
    struct VideoJob: Identifiable, Equatable {
        var id: URL { file }
        let file: URL
        let prompt: String
        let started = Date()
        var finished: Date?
        var error: String?

        var done: Bool { finished != nil && error == nil }
        var elapsed: TimeInterval { (finished ?? Date()).timeIntervalSince(started) }
        var line: String {
            let secs = Int(elapsed.rounded())
            if let error { return "「\(prompt)」失败了（\(secs)s）：\(error)" }
            if finished != nil { return "「\(prompt)」拍好了，\(secs)s：\(file.path)" }
            return "「\(prompt)」在拍，已经 \(secs)s → \(file.path)"
        }
    }

    /// Newest first, and only the last handful: this is a status line, not a
    /// history.
    @Published private(set) var videoJobs: [VideoJob] = []

    /// Start a clip and return where it will land.
    ///
    /// The kernel's MCP client gives a tool call 60 seconds and closes the
    /// connection when one overruns — which would take every other panel tool
    /// down with it. A generation is minutes. So the tool that starts one
    /// answers with the path and a job to ask about, rather than holding the
    /// line open and losing the panel.
    @discardableResult
    func startVideo(prompt: String, into folder: URL, seconds: Double = 4,
                    width: Int = 704, height: Int = 480,
                    seed: Int? = nil, mode: String? = nil, from image: URL? = nil) -> URL {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = Self.fileName(for: cleaned).replacingOccurrences(of: ".png", with: ".mp4")
        let file = folder.appendingPathComponent(name)
        videoJobs.insert(VideoJob(file: file, prompt: cleaned), at: 0)
        videoJobs = Array(videoJobs.prefix(6))

        Task { @MainActor in
            do {
                _ = try await generateVideo(prompt: cleaned, to: file, seconds: seconds,
                                            width: width, height: height,
                                            seed: seed, mode: mode, from: image)
                finish(file, error: nil)
            } catch {
                // The clip comes back in the answer to one long request: a connection lost on the
                // way is not the box failing to film it, but the clip is out of reach all the same.
                finish(file, error: BoxTrouble.isTransient(error)
                       ? "和盒子的连接断了（\(error.localizedDescription)），不是拍失败；这一段拿不回来，再拍一次"
                       : error.localizedDescription)
            }
        }
        return file
    }

    private func finish(_ file: URL, error: String?) {
        guard let index = videoJobs.firstIndex(where: { $0.file == file }) else { return }
        videoJobs[index].finished = Date()
        videoJobs[index].error = error
    }

    /// What the jobs are doing, as a sentence each — the answer to a
    /// `video_status` call and to the row in the picker.
    var videoReport: String {
        videoJobs.isEmpty ? "还没拍过" : videoJobs.map(\.line).joined(separator: "\n")
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }
}
