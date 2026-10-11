import AppKit
import Foundation
import ImageIO

// The cloud side of MediaPlaces: one client per provider, each turning a
// capability into that provider's request and handing back what the box's
// servers hand back — picture bytes, clip bytes, WAV bytes, text — so the
// callers (DiffuserClient, SpeechSynthesizer, VoiceRecorder) keep doing
// what they did with them.

// MARK: - Shared

enum MediaCloudHTTP {
    /// A non-2xx answer, as a sentence: the provider's own message when it
    /// sent one (OpenAI-style `{"error": {"message"}}`, fal's `{"detail"}`,
    /// DashScope's `{"code", "message"}`), else the status.
    static func check(_ response: URLResponse, _ data: Data, _ place: MediaPlace, what: String) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200...299).contains(code) else { return }
        var said = ""
        if let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = answer["error"] as? [String: Any], let message = error["message"] as? String {
                said = message
            } else if let message = answer["message"] as? String {
                said = [answer["code"] as? String, message].compactMap { $0 }.joined(separator: "：")
            } else if let detail = answer["detail"] {
                said = (detail as? String) ?? "\(detail)"
            }
        }
        if said.isEmpty { said = String(data: data.prefix(240), encoding: .utf8) ?? "" }
        let hint = code == 401 || code == 403 ? "（key 不对或没有权限）" : code == 429 ? "（额度或频率到顶了）" : ""
        throw MediaCloudError.message("\(place.title) \(what)失败（HTTP \(code)）\(hint)：\(String(said.prefix(240)))")
    }

    static func multipart(fields: [String: String], file: (name: String, url: URL, type: String)) throws -> (String, Data) {
        let boundary = "kinclaw-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.url.lastPathComponent)\"\r\nContent-Type: \(file.type)\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: file.url))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return (boundary, body)
    }
}

// MARK: - OpenAI-compatible voice

/// Speech and transcription through OpenAI's audio API — OpenAI itself, or
/// any server that speaks it (the base is a setting). The box's own kin audio
/// speaks it too (`/v1/audio/speech` on 8101, `/v1/audio/transcriptions` on
/// 8100, checked 2026-10-10), so one client could serve every place; the box
/// keeps its own `/synthesize` path for now, untouched.
enum OpenAIVoice {
    static let baseKey = "kinclaw.cloud.openai.base"
    static let voiceKey = "kinclaw.cloud.openai.voice"
    static let speechModelKey = "kinclaw.cloud.openai.tts.model"
    static let listenModelKey = "kinclaw.cloud.openai.stt.model"

    static let defaultBase = "https://api.openai.com/v1"
    static let defaultVoice = "marin"
    static let defaultSpeechModel = "gpt-4o-mini-tts"
    static let defaultListenModel = "gpt-4o-mini-transcribe"

    private static func setting(_ key: String, _ fallback: String) -> String {
        let value = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }

    static var base: String { setting(baseKey, defaultBase).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    static var voice: String { setting(voiceKey, defaultVoice) }
    static var speechModel: String { setting(speechModelKey, defaultSpeechModel) }
    static var listenModel: String { setting(listenModelKey, defaultListenModel) }

    /// One stretch of text, spoken: WAV bytes. `instructions` is how to say
    /// it (tone, pace), for the models that take it.
    static func speak(_ text: String, instructions: String? = nil, asking: Bool = false) async throws -> Data {
        let key = try CloudKey.required(.openai, asking: asking)
        guard let url = URL(string: base + "/audio/speech") else {
            throw MediaCloudError.message("OpenAI 兼容的地址不对：\(base)")
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": speechModel, "input": text, "voice": voice, "response_format": "wav"]
        if let instructions, !instructions.isEmpty { body["instructions"] = instructions }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .openai, what: "说话")
        guard data.count > 44 else { throw MediaCloudError.message("OpenAI 兼容 说话返回的不是声音（\(data.count) 字节）") }
        return data
    }

    /// What a recording says.
    static func transcribe(_ file: URL, language: String? = nil, asking: Bool = false) async throws -> String {
        let key = try CloudKey.required(.openai, asking: asking)
        guard let url = URL(string: base + "/audio/transcriptions") else {
            throw MediaCloudError.message("OpenAI 兼容的地址不对：\(base)")
        }
        var fields = ["model": listenModel, "response_format": "json"]
        if let language, !language.isEmpty { fields["language"] = language }
        let type = file.pathExtension.lowercased() == "m4a" ? "audio/mp4" : "audio/wav"
        let (boundary, body) = try MediaCloudHTTP.multipart(fields: fields, file: (name: "file", url: file, type: type))
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .openai, what: "听写")
        struct Reply: Decodable { let text: String }
        return try JSONDecoder().decode(Reply.self, from: data).text
    }

    /// Does the key work? `GET /models` — free, and it fails the same way a
    /// real call would for a wrong key or base.
    static func check(asking: Bool = true) async throws -> String {
        let key = try CloudKey.required(.openai, asking: asking)
        guard let url = URL(string: base + "/models") else {
            throw MediaCloudError.message("OpenAI 兼容的地址不对：\(base)")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .openai, what: "验证")
        let count = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [Any])?.count ?? 0
        return "通了：\(base) 有 \(count) 个模型"
    }
}

// MARK: - Pictures and clips: the dispatch

/// 画 · 改 · 拍 on whichever cloud they are placed on (MediaPlacement).
enum MediaCloud {
    static func draw(prompt: String, width: Int, height: Int, seed: Int?, on place: MediaPlace) async throws -> Data {
        switch place {
        case .fal:     return try await FalClient.draw(prompt: prompt, width: width, height: height, seed: seed)
        case .bailian: return try await BailianClient.draw(prompt: prompt, width: width, height: height, seed: seed)
        case .openai:  return try await OpenAIImages.draw(prompt: prompt, width: width, height: height)
        case .google:  return try await GoogleImages.draw(prompt: prompt, width: width, height: height)
        case .xai:     return try await XAIImages.draw(prompt: prompt, width: width, height: height)
        case .box:     throw MediaCloudError.message("盒子不走这里")
        }
    }

    /// `images[0]` is the picture being changed; the rest are references.
    static func edit(prompt: String, images: [URL], seed: Int?, on place: MediaPlace) async throws -> Data {
        switch place {
        case .fal:     return try await FalClient.edit(prompt: prompt, images: images, seed: seed)
        case .bailian: return try await BailianClient.edit(prompt: prompt, images: images, seed: seed)
        case .openai:  return try await OpenAIImages.edit(prompt: prompt, images: images)
        case .google:  return try await GoogleImages.edit(prompt: prompt, images: images)
        case .xai:     return try await XAIImages.edit(prompt: prompt, images: images)
        case .box:     throw MediaCloudError.message("盒子不走这里")
        }
    }

    static func film(prompt: String, image: URL?, seconds: Double, width: Int, height: Int, on place: MediaPlace) async throws -> Data {
        switch place {
        case .fal: return try await FalClient.film(prompt: prompt, image: image, seconds: seconds, width: width, height: height)
        default:   throw MediaCloudError.message("\(place.title) 不拍视频")
        }
    }

    /// One stretch of text, spoken, wherever 声音 is placed in the cloud.
    static func speak(_ text: String, on place: MediaPlace) async throws -> Data {
        switch place {
        case .openai:  return try await OpenAIVoice.speak(text)
        case .bailian: return try await BailianClient.speak(text)
        default:       throw MediaCloudError.message("\(place.title) 不说话")
        }
    }

    /// What a recording says, wherever 声音 is placed in the cloud.
    static func transcribe(_ file: URL, on place: MediaPlace) async throws -> String {
        switch place {
        case .openai:  return try await OpenAIVoice.transcribe(file)
        case .bailian: return try await BailianClient.transcribe(file)
        default:       throw MediaCloudError.message("\(place.title) 不听写")
        }
    }

    /// Does the key work — without spending anything where that can be done.
    static func check(_ place: MediaPlace) async throws -> String {
        switch place {
        case .openai:  return try await OpenAIVoice.check()
        case .fal:     return try await FalClient.check()
        case .bailian: return try await BailianClient.check()
        case .google:  return try await GoogleImages.check()
        case .xai:     return try await XAIImages.check()
        case .box:     return "盒子不用 key"
        }
    }

    // MARK: Shared pieces

    /// The bytes behind a result URL. Providers keep results for hours, not
    /// for ever, so they are fetched at once.
    static func download(_ url: URL, _ place: MediaPlace, timeout: TimeInterval = 300) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, place, what: "取结果")
        return data
    }

    /// A local picture as a data URI, for the APIs that take one in place of
    /// a URL (nothing of the user's is put anywhere public to be fetched).
    /// PNG when it has transparency — a texture atlas's empty background has
    /// to stay empty — JPEG otherwise; sides over 2048 are scaled down first,
    /// which keeps a request well under the providers' size limits.
    static func dataURI(_ file: URL, maxSide: CGFloat = 2048) throws -> String {
        let (type, base64) = try encoded(file, maxSide: maxSide)
        return "data:\(type);base64,\(base64)"
    }

    /// The same picture as its media type and bare base64, for the APIs that
    /// take the two apart (Gemini's inline data).
    static func encoded(_ file: URL, maxSide: CGFloat = 2048) throws -> (type: String, base64: String) {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MediaCloudError.message("读不了这张图：\(file.lastPathComponent)")
        }
        let side = CGFloat(max(image.width, image.height))
        if side > maxSide, let smaller = scaled(image, by: maxSide / side) { image = smaller }
        let alpha = image.alphaInfo
        let transparent = !(alpha == .none || alpha == .noneSkipLast || alpha == .noneSkipFirst)
        let rep = NSBitmapImageRep(cgImage: image)
        let (type, data): (String, Data?) = transparent
            ? ("image/png", rep.representation(using: .png, properties: [:]))
            : ("image/jpeg", rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]))
        guard let data else { throw MediaCloudError.message("这张图编码不了：\(file.lastPathComponent)") }
        return (type, data.base64EncodedString())
    }

    /// The aspect ratio, out of those a model takes ("16:9", "1:1"…), nearest
    /// to the size asked — for the APIs that are told a shape rather than
    /// pixels. The picture is cut to the exact size afterwards anyway.
    static func nearestRatio(width: Int, height: Int, among ratios: [String]) -> String {
        let wanted = log(Double(max(width, 1)) / Double(max(height, 1)))
        return ratios.min { a, b in abs(log(ratio(a)) - wanted) < abs(log(ratio(b)) - wanted) } ?? "1:1"
    }

    private static func ratio(_ text: String) -> Double {
        let sides = text.split(separator: ":").compactMap { Double($0) }
        return sides.count == 2 && sides[1] > 0 ? sides[0] / sides[1] : 1
    }

    /// A picture that came back as base64 (bare, or as a data URI).
    static func decoded(_ base64: String, _ place: MediaPlace) throws -> Data {
        var text = base64
        if text.hasPrefix("data:"), let comma = text.firstIndex(of: ",") { text = String(text[text.index(after: comma)...]) }
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else {
            throw MediaCloudError.message("\(place.title) 返回的图解不开")
        }
        return data
    }

    private static func scaled(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = Int((CGFloat(image.width) * factor).rounded()), height = Int((CGFloat(image.height) * factor).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Ask again until `done` has an answer: a cloud clip takes minutes, a
    /// picture seconds. The wait between asks grows to `longest`; `limit`
    /// is how long anybody waits before calling it lost.
    static func poll<T>(every first: TimeInterval = 2, longest: TimeInterval = 10, limit: TimeInterval,
                        _ place: MediaPlace, _ done: () async throws -> T?) async throws -> T {
        let started = Date()
        var wait = first
        while Date().timeIntervalSince(started) < limit {
            try Task.checkCancellation()
            if let answer = try await done() { return answer }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            wait = min(longest, wait * 1.5)
        }
        throw MediaCloudError.message("\(place.title) 等了 \(Int(limit)) 秒还没好，放弃了")
    }
}

// MARK: - fal.ai

/// One key for open models: Qwen-Image to draw and edit — the family the box
/// runs — and Wan for clips. Pictures come back from the synchronous call in
/// seconds; a clip goes through the queue (submit, ask, fetch), since a sync
/// call has no stated timeout. Facts from fal's docs, 2026-10-10.
enum FalClient {
    static let drawModelKey = "kinclaw.cloud.fal.draw.model"
    static let editModelKey = "kinclaw.cloud.fal.edit.model"
    static let filmModelKey = "kinclaw.cloud.fal.film.model"
    static let baseKey = "kinclaw.cloud.fal.base"
    static let queueKey = "kinclaw.cloud.fal.queue"

    /// $0.02 a megapixel; Chinese and English lettering.
    static let defaultDrawModel = "fal-ai/qwen-image-2512"
    /// $0.03 a megapixel; several references; keeps the input's size.
    static let defaultEditModel = "fal-ai/qwen-image-edit-2511"
    /// 720p, 2–15 s, $0.10 a second.
    static let defaultFilmModel = "fal-ai/wan/v2.7/image-to-video"

    fileprivate static func setting(_ key: String, _ fallback: String) -> String {
        let value = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
    static var base: String { setting(baseKey, "https://fal.run").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    static var queueBase: String { setting(queueKey, "https://queue.fal.run").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    /// Which model fal draws and edits with: one key, four families. The
    /// endpoints and fields are each family's own on fal (2026-10-10).
    enum Family: String, CaseIterable, Identifiable {
        case qwen, gpt, grok, nano
        var id: String { rawValue }
        var title: String {
            switch self {
            case .qwen: return "Qwen-Image"
            case .gpt:  return "GPT Image 2.5"
            case .grok: return "Grok Imagine 2.0"
            case .nano: return "Nano Banana 2.1"
            }
        }
        var drawEndpoint: String {
            switch self {
            case .qwen: return FalClient.setting(FalClient.drawModelKey, FalClient.defaultDrawModel)
            case .gpt:  return "openai/gpt-image-2.5/flare/text-to-image"
            case .grok: return "xai/grok-imagine-image/v2.0/text-to-image"
            case .nano: return "google/nano-banana-2.1"
            }
        }
        var editEndpoint: String {
            switch self {
            case .qwen: return FalClient.setting(FalClient.editModelKey, FalClient.defaultEditModel)
            case .gpt:  return "openai/gpt-image-2.5/sunburst/edit"
            case .grok: return "xai/grok-imagine-image/v2.0/edit"
            case .nano: return "google/nano-banana-2.1/edit"
            }
        }
        /// How many pictures an edit takes.
        var mostPictures: Int {
            switch self {
            case .qwen: return 4
            case .gpt:  return 16
            case .grok: return 5
            case .nano: return 14
            }
        }
        /// The shape fields: pixels for some, a ratio and a resolution for others.
        func shape(width: Int, height: Int) -> [String: Any] {
            switch self {
            case .qwen, .gpt:
                return ["image_size": ["width": width, "height": height]]
            case .grok:
                let ratios = ["1:1", "3:4", "4:3", "9:16", "16:9", "2:3", "3:2", "9:19.5", "19.5:9", "9:20", "20:9", "1:2", "2:1"]
                return ["aspect_ratio": MediaCloud.nearestRatio(width: width, height: height, among: ratios),
                        "resolution": max(width, height) > 1400 ? "2k" : "1k"]
            case .nano:
                return ["aspect_ratio": MediaCloud.nearestRatio(width: width, height: height, among: GoogleImages.ratios),
                        "resolution": max(width, height) > 1400 ? "2K" : "1K"]
            }
        }
        /// Fields beyond the prompt and the shape.
        var extras: [String: Any] {
            switch self {
            case .qwen: return [:]
            case .gpt:  return ["quality": OpenAIImages.quality]   // fal's own default is high
            case .grok: return ["quality": "medium"]
            case .nano: return [:]
            }
        }
        /// Does the family take a seed? GPT Image and Grok have none.
        var seeded: Bool { self == .qwen || self == .nano }
    }

    static let familyKey = "kinclaw.cloud.fal.image.family"
    static var family: Family { Family(rawValue: setting(familyKey, Family.qwen.rawValue)) ?? .qwen }

    static func draw(prompt: String, width: Int, height: Int, seed: Int?) async throws -> Data {
        let family = family
        var input: [String: Any] = ["prompt": prompt, "num_images": 1, "output_format": "png"]
        input.merge(family.shape(width: width, height: height)) { _, new in new }
        input.merge(family.extras) { _, new in new }
        if let seed, family.seeded { input["seed"] = seed }
        let output = try await call(family.drawEndpoint, input, what: "画图")
        return try await firstImage(output)
    }

    /// Image 1 and the references as data URIs (fal takes one wherever it
    /// takes a file), sides kept to 1536 so each stays around a megabyte.
    static func edit(prompt: String, images: [URL], seed: Int?) async throws -> Data {
        let family = family
        let urls = try images.prefix(family.mostPictures).map { try MediaCloud.dataURI($0, maxSide: 1536) }
        var input: [String: Any] = ["prompt": prompt, "image_urls": urls, "output_format": "png"]
        input.merge(family.extras) { _, new in new }
        if let seed, family.seeded { input["seed"] = seed }
        let output = try await call(family.editEndpoint, input, what: "改图")
        return try await firstImage(output)
    }

    static func film(prompt: String, image: URL?, seconds: Double, width: Int, height: Int) async throws -> Data {
        guard let image else { throw MediaCloudError.message("fal.ai 拍视频要一张起始的图") }
        let input: [String: Any] = ["prompt": prompt, "image_url": try MediaCloud.dataURI(image, maxSide: 1536),
                                    "resolution": "720p", "duration": min(15, max(2, Int(seconds.rounded())))]
        let output = try await queued(setting(filmModelKey, defaultFilmModel), input, what: "拍视频", limit: 1200)
        guard let video = output["video"] as? [String: Any], let link = video["url"] as? String, let url = URL(string: link) else {
            throw MediaCloudError.message("fal.ai 拍视频的结果里没有视频")
        }
        return try await MediaCloud.download(url, .fal, timeout: 600)
    }

    /// Is the key accepted? Asking the queue about a request that does not
    /// exist costs nothing: a key it does not know is turned away (401/403),
    /// one it knows hears that there is no such request.
    static func check() async throws -> String {
        let key = try CloudKey.required(.fal, asking: true)
        guard let url = URL(string: queueBase + "/" + defaultDrawModel + "/requests/00000000-0000-0000-0000-000000000000/status") else {
            throw MediaCloudError.message("fal.ai 的地址不对：\(queueBase)")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { try MediaCloudHTTP.check(response, data, .fal, what: "验证") }
        return "通了：fal.ai 认这个 key（没出图，不花钱）"
    }

    // MARK: Calls

    private static func request(_ url: URL, key: String, body: [String: Any]?, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func json(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaCloudError.message("fal.ai 的回答不是 JSON")
        }
        return object
    }

    /// The synchronous call: the model's output is the answer.
    private static func call(_ model: String, _ input: [String: Any], what: String) async throws -> [String: Any] {
        let key = try CloudKey.required(.fal)
        guard let url = URL(string: base + "/" + model) else { throw MediaCloudError.message("fal.ai 的模型名不对：\(model)") }
        let (data, response) = try await URLSession.shared.data(for: try request(url, key: key, body: input, timeout: 300))
        try MediaCloudHTTP.check(response, data, .fal, what: what)
        return try json(data)
    }

    /// The queue: submit, ask until it says COMPLETED, fetch. The URLs to ask
    /// and fetch are the ones the submit answers with.
    private static func queued(_ model: String, _ input: [String: Any], what: String, limit: TimeInterval) async throws -> [String: Any] {
        let key = try CloudKey.required(.fal)
        guard let url = URL(string: queueBase + "/" + model) else { throw MediaCloudError.message("fal.ai 的模型名不对：\(model)") }
        let (data, response) = try await URLSession.shared.data(for: try request(url, key: key, body: input, timeout: 120))
        try MediaCloudHTTP.check(response, data, .fal, what: what)
        let submitted = try json(data)
        guard let statusLink = submitted["status_url"] as? String, let statusURL = URL(string: statusLink),
              let resultLink = submitted["response_url"] as? String, let resultURL = URL(string: resultLink) else {
            throw MediaCloudError.message("fal.ai 排队的回答里没有 status_url / response_url")
        }
        try await MediaCloud.poll(every: 3, longest: 10, limit: limit, .fal) { () -> Bool? in
            let (data, response) = try await URLSession.shared.data(for: try request(statusURL, key: key, body: nil, timeout: 30))
            try MediaCloudHTTP.check(response, data, .fal, what: what)
            let status = try json(data)
            if let error = status["error"] as? String, !error.isEmpty {
                throw MediaCloudError.message("fal.ai \(what)失败：\(error)")
            }
            return (status["status"] as? String) == "COMPLETED" ? true : nil
        }
        let (result, resultResponse) = try await URLSession.shared.data(for: try request(resultURL, key: key, body: nil, timeout: 60))
        try MediaCloudHTTP.check(resultResponse, result, .fal, what: what)
        return try json(result)
    }

    /// `images[0].url` — a link to fetch, or with sync_mode a data URI.
    private static func firstImage(_ output: [String: Any]) async throws -> Data {
        guard let images = output["images"] as? [[String: Any]], let link = images.first?["url"] as? String else {
            throw MediaCloudError.message("fal.ai 的结果里没有图")
        }
        if link.hasPrefix("data:"), let comma = link.firstIndex(of: ","),
           let data = Data(base64Encoded: String(link[link.index(after: comma)...])) {
            return data
        }
        guard let url = URL(string: link) else { throw MediaCloudError.message("fal.ai 给的图地址不对：\(link.prefix(80))") }
        return try await MediaCloud.download(url, .fal)
    }
}

// MARK: - Alibaba Cloud Bailian (DashScope)

/// Qwen-Image on Alibaba's own cloud — strong Chinese lettering, and the
/// family the box runs. Drawing and editing are one synchronous endpoint: a
/// user message with up to three pictures and one text. Results are links,
/// good for 24 hours, fetched at once. Facts from Model Studio's docs,
/// 2026-10-10: the dashscope hosts still work; Alibaba says new features go
/// only to workspace hosts after 2026-09-30, so a workspace host can be set.
enum BailianClient {
    static let regionKey = "kinclaw.cloud.bailian.region"
    static let hostKey = "kinclaw.cloud.bailian.host"
    static let drawModelKey = "kinclaw.cloud.bailian.draw.model"
    static let editModelKey = "kinclaw.cloud.bailian.edit.model"
    static let defaultRegion = "cn"
    /// $0.03 an image (Singapore price list).
    static let defaultModel = "qwen-image-3.0"
    /// What qwen-image-3.0 takes in one message.
    static let mostPictures = 3

    private static func setting(_ key: String) -> String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var host: String {
        let chosen = setting(hostKey)
        if !chosen.isEmpty { return chosen.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return setting(regionKey) == "intl" ? "https://dashscope-intl.aliyuncs.com" : "https://dashscope.aliyuncs.com"
    }
    private static var endpoint: String { host + "/api/v1/services/aigc/multimodal-generation/generation" }

    static func draw(prompt: String, width: Int, height: Int, seed: Int?) async throws -> Data {
        let model = setting(drawModelKey).isEmpty ? defaultModel : setting(drawModelKey)
        return try await generate(model: model, content: [["text": prompt]], size: "\(width)*\(height)", seed: seed, what: "画图")
    }

    /// Image 1 first, then references — as many as the model takes; the
    /// prompt calls them image 1, image 2… as it does on the box.
    static func edit(prompt: String, images: [URL], seed: Int?) async throws -> Data {
        let model = setting(editModelKey).isEmpty ? defaultModel : setting(editModelKey)
        let pictures = try images.prefix(mostPictures).map { ["image": try MediaCloud.dataURI($0)] }
        return try await generate(model: model, content: pictures + [["text": prompt]], size: nil, seed: seed, what: "改图")
    }

    /// Is the key accepted? An empty request is turned away for what it is —
    /// a key Alibaba does not know with 401/403, one it knows with 400 — and
    /// draws nothing.
    static func check() async throws -> String {
        let key = try CloudKey.required(.bailian, asking: true)
        guard let url = URL(string: endpoint) else { throw MediaCloudError.message("阿里百炼的地址不对：\(host)") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": defaultModel, "input": ["messages": [] as [Any]]])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { try MediaCloudHTTP.check(response, data, .bailian, what: "验证") }
        return "通了：阿里百炼（\(host)）认这个 key（没出图，不花钱）"
    }

    // MARK: Voice

    static let voiceKey = "kinclaw.cloud.bailian.voice"
    static let defaultVoice = "Cherry"
    static let speechModel = "qwen3-tts-flash"
    static let listenModel = "qwen3-asr-flash"
    static var voice: String { setting(voiceKey).isEmpty ? defaultVoice : setting(voiceKey) }

    /// One stretch of text, spoken by qwen3-tts-flash — the family of the
    /// box's own voice. The answer is a link to the audio, good for 24 hours,
    /// fetched at once.
    static func speak(_ text: String) async throws -> Data {
        let key = try CloudKey.required(.bailian)
        guard let url = URL(string: endpoint) else { throw MediaCloudError.message("阿里百炼的地址不对：\(host)") }
        let body: [String: Any] = ["model": speechModel,
                                   "input": ["text": text, "voice": voice, "language_type": "Auto"]]
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .bailian, what: "说话")
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = answer["output"] as? [String: Any],
              let audio = output["audio"] as? [String: Any],
              let link = audio["url"] as? String, let audioURL = URL(string: link) else {
            throw MediaCloudError.message("阿里百炼说话的结果里没有声音")
        }
        return try await MediaCloud.download(audioURL, .bailian, timeout: 60)
    }

    /// What a recording says, by qwen3-asr-flash — the family of the box's
    /// own ear — through Alibaba's OpenAI-compatible chat endpoint: the audio
    /// goes in as a data URI (up to 10 MB, five minutes).
    static func transcribe(_ file: URL) async throws -> String {
        let key = try CloudKey.required(.bailian)
        guard let url = URL(string: host + "/compatible-mode/v1/chat/completions") else {
            throw MediaCloudError.message("阿里百炼的地址不对：\(host)")
        }
        let audio = try Data(contentsOf: file)
        guard audio.count <= 10_000_000 else { throw MediaCloudError.message("阿里百炼听写一次最多 10 MB，这段有 \(audio.count / 1_000_000) MB") }
        let type = ["m4a": "audio/mp4", "mp3": "audio/mpeg"][file.pathExtension.lowercased()] ?? "audio/wav"
        let part: [String: Any] = ["type": "input_audio",
                                   "input_audio": ["data": "data:\(type);base64,\(audio.base64EncodedString())"]]
        let body: [String: Any] = ["model": listenModel, "stream": false,
                                   "messages": [["role": "user", "content": [part]]]]
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .bailian, what: "听写")
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = answer["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw MediaCloudError.message("阿里百炼听写的结果里没有字")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Calls

    private static func generate(model: String, content: [[String: String]], size: String?, seed: Int?, what: String) async throws -> Data {
        let key = try CloudKey.required(.bailian)
        guard let url = URL(string: endpoint) else { throw MediaCloudError.message("阿里百炼的地址不对：\(host)") }
        // Rewriting the prompt is off: what an agent wrote — the counts in a
        // shot, "keep her face" — is meant as written.
        var parameters: [String: Any] = ["n": 1, "watermark": false, "prompt_extend": false]
        if let size { parameters["size"] = size }
        if let seed { parameters["seed"] = max(0, min(seed, 2_147_483_647)) }
        let body: [String: Any] = ["model": model,
                                   "input": ["messages": [["role": "user", "content": content]]],
                                   "parameters": parameters]
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .bailian, what: what)
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = answer["output"] as? [String: Any],
              let choices = output["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let parts = message["content"] as? [[String: Any]],
              let link = parts.compactMap({ $0["image"] as? String }).first,
              let imageURL = URL(string: link) else {
            throw MediaCloudError.message("阿里百炼\(what)的结果里没有图")
        }
        return try await MediaCloud.download(imageURL, .bailian)
    }
}

// MARK: - OpenAI images (GPT Image 2.5)

/// GPT Image 2.5 through OpenAI's Image API, on the same key and base as the
/// voice. It ships as two models: flare (fast, everyday) draws, sunburst (the
/// most capable, best at precise edits) edits. Answers are always base64.
/// Facts from OpenAI's docs, 2026-10-10. An organisation may have to verify
/// itself with OpenAI before GPT Image models answer.
enum OpenAIImages {
    static let drawModelKey = "kinclaw.cloud.openai.draw.model"
    static let editModelKey = "kinclaw.cloud.openai.edit.model"
    static let qualityKey = "kinclaw.cloud.openai.image.quality"
    static let defaultDrawModel = "gpt-image-2.5-flare"
    static let defaultEditModel = "gpt-image-2.5-sunburst"
    /// low | medium | high | xhigh | max — medium is about $0.013 at 1024².
    static let defaultQuality = "medium"

    private static func setting(_ key: String, _ fallback: String) -> String {
        let value = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
    static var quality: String { setting(qualityKey, defaultQuality) }

    /// One of the sizes it always takes, by shape: the picture is cut to the
    /// asked size afterwards, and these clear its pixel minimum.
    static func size(width: Int, height: Int) -> String {
        let shape = Double(width) / Double(max(height, 1))
        return shape > 1.2 ? "1536x1024" : shape < 0.83 ? "1024x1536" : "1024x1024"
    }

    static func draw(prompt: String, width: Int, height: Int) async throws -> Data {
        try await post("/images/generations", what: "画图",
                       ["model": setting(drawModelKey, defaultDrawModel), "prompt": prompt, "n": 1,
                        "size": size(width: width, height: height), "quality": quality, "output_format": "png"])
    }

    /// Up to 16 pictures as data URIs, in the JSON form of the edit call.
    static func edit(prompt: String, images: [URL]) async throws -> Data {
        let pictures = try images.prefix(16).map { ["image_url": try MediaCloud.dataURI($0)] }
        return try await post("/images/edits", what: "改图",
                              ["model": setting(editModelKey, defaultEditModel), "prompt": prompt, "images": pictures,
                               "quality": quality, "output_format": "png"])
    }

    private static func post(_ path: String, what: String, _ body: [String: Any]) async throws -> Data {
        let key = try CloudKey.required(.openai)
        guard let url = URL(string: OpenAIVoice.base + path) else { throw MediaCloudError.message("OpenAI 的地址不对：\(OpenAIVoice.base)") }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .openai, what: what)
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = answer["data"] as? [[String: Any]], let base64 = items.first?["b64_json"] as? String else {
            throw MediaCloudError.message("OpenAI \(what)的结果里没有图")
        }
        return try MediaCloud.decoded(base64, .openai)
    }
}

// MARK: - Google (Nano Banana 2.1)

/// Nano Banana 2.1 through the Gemini API's generateContent — still fully
/// supported, though Google points new projects at its Interactions API. Up
/// to 14 reference pictures inline (20 MB a request in all); the answer's
/// image is base64 in a part, after up to two "thought" images that are
/// skipped. Facts from Google's docs, 2026-10-10.
enum GoogleImages {
    static let baseKey = "kinclaw.cloud.google.base"
    static let modelKey = "kinclaw.cloud.google.image.model"
    static let defaultModel = "gemini-nano-banana-2.1"
    static let ratios = ["1:1", "1:4", "4:1", "1:8", "8:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]

    private static func setting(_ key: String, _ fallback: String) -> String {
        let value = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
    static var base: String {
        setting(baseKey, "https://generativelanguage.googleapis.com/v1beta").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func draw(prompt: String, width: Int, height: Int) async throws -> Data {
        try await generate([["text": prompt]], width: width, height: height, what: "画图")
    }

    static func edit(prompt: String, images: [URL]) async throws -> Data {
        var parts: [[String: Any]] = [["text": prompt]]
        for file in images.prefix(14) {
            let (type, base64) = try MediaCloud.encoded(file)
            parts.append(["inlineData": ["mimeType": type, "data": base64]])
        }
        let size = images.first.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let width = size?[kCGImagePropertyPixelWidth] as? Int ?? 1024, height = size?[kCGImagePropertyPixelHeight] as? Int ?? 1024
        return try await generate(parts, width: width, height: height, what: "改图")
    }

    /// Does the key work? Listing the models costs nothing.
    static func check() async throws -> String {
        let key = try CloudKey.required(.google, asking: true)
        guard let url = URL(string: base + "/models") else { throw MediaCloudError.message("Google 的地址不对：\(base)") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .google, what: "验证")
        let count = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["models"] as? [Any])?.count ?? 0
        return "通了：Gemini API 有 \(count) 个模型（只读了列表，不花钱）"
    }

    private static func generate(_ parts: [[String: Any]], width: Int, height: Int, what: String) async throws -> Data {
        let key = try CloudKey.required(.google)
        let model = setting(modelKey, defaultModel)
        guard let url = URL(string: base + "/models/\(model):generateContent") else {
            throw MediaCloudError.message("Google 的地址不对：\(base)")
        }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["responseModalities": ["IMAGE"],
                                 "imageConfig": ["aspectRatio": MediaCloud.nearestRatio(width: width, height: height, among: ratios),
                                                 "imageSize": max(width, height) > 1400 ? "2K" : "1K"]],
        ]
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .google, what: what)
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = answer["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let answerParts = content["parts"] as? [[String: Any]] else {
            throw MediaCloudError.message("Google \(what)没有返回内容（可能被安全过滤拦下了）")
        }
        // The picture, not one of the model's interim "thought" pictures.
        for part in answerParts where (part["thought"] as? Bool) != true {
            let inline = (part["inlineData"] ?? part["inline_data"]) as? [String: Any]
            if let base64 = inline?["data"] as? String { return try MediaCloud.decoded(base64, .google) }
        }
        throw MediaCloudError.message("Google \(what)的结果里没有图")
    }
}

// MARK: - xAI (Grok Imagine 2.0)

/// Grok Imagine 2.0 through xAI's API. Drawing is OpenAI-shaped; editing is
/// JSON only (up to five pictures, called <IMAGE_0>, <IMAGE_1>… in the
/// prompt). Shapes are aspect ratios and 1k/2k, not pixels. Facts from xAI's
/// docs, 2026-10-10.
enum XAIImages {
    static let baseKey = "kinclaw.cloud.xai.base"
    static let modelKey = "kinclaw.cloud.xai.image.model"
    static let defaultModel = "grok-imagine-image-2.0"
    static let ratios = ["1:1", "3:4", "4:3", "9:16", "16:9", "2:3", "3:2", "9:19.5", "19.5:9", "9:20", "20:9", "1:2", "2:1", "21:9", "5:2"]

    private static func setting(_ key: String, _ fallback: String) -> String {
        let value = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
    static var base: String { setting(baseKey, "https://api.x.ai/v1").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    static func draw(prompt: String, width: Int, height: Int) async throws -> Data {
        try await post("/images/generations", what: "画图",
                       ["model": setting(modelKey, defaultModel), "prompt": prompt, "n": 1,
                        "aspect_ratio": MediaCloud.nearestRatio(width: width, height: height, among: ratios),
                        "resolution": max(width, height) > 1400 ? "2k" : "1k", "quality": "medium",
                        "response_format": "b64_json"])
    }

    /// The prompt says 图1, 图2 (image 1, 2) as the box's editors read them;
    /// a line maps those to xAI's own <IMAGE_n> names.
    static func edit(prompt: String, images: [URL]) async throws -> Data {
        let pictures = try images.prefix(5).map { ["url": try MediaCloud.dataURI($0)] }
        var words = prompt
        if pictures.count > 1 {
            words += "\n(" + (0..<pictures.count).map { "图\($0 + 1) / image \($0 + 1) = <IMAGE_\($0)>" }.joined(separator: ", ") + ")"
        }
        var body: [String: Any] = ["model": setting(modelKey, defaultModel), "prompt": words, "n": 1,
                                   "quality": "medium", "response_format": "b64_json"]
        if pictures.count == 1 { body["image"] = pictures[0] } else { body["images"] = pictures }
        return try await post("/images/edits", what: "改图", body)
    }

    /// Does the key work? Listing the models costs nothing.
    static func check() async throws -> String {
        let key = try CloudKey.required(.xai, asking: true)
        guard let url = URL(string: base + "/models") else { throw MediaCloudError.message("xAI 的地址不对：\(base)") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .xai, what: "验证")
        let count = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [Any])?.count ?? 0
        return "通了：xAI 有 \(count) 个模型（只读了列表，不花钱）"
    }

    private static func post(_ path: String, what: String, _ body: [String: Any]) async throws -> Data {
        let key = try CloudKey.required(.xai)
        guard let url = URL(string: base + path) else { throw MediaCloudError.message("xAI 的地址不对：\(base)") }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try MediaCloudHTTP.check(response, data, .xai, what: what)
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = answer["data"] as? [[String: Any]], let first = items.first else {
            throw MediaCloudError.message("xAI \(what)的结果里没有图")
        }
        if let base64 = first["b64_json"] as? String { return try MediaCloud.decoded(base64, .xai) }
        if let link = first["url"] as? String, let url = URL(string: link) { return try await MediaCloud.download(url, .xai) }
        throw MediaCloudError.message("xAI \(what)的结果里没有图")
    }
}
