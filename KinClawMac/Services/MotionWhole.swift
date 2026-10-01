import Accelerate
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The fourth route, 整场白模 — Jacky, 2026-09-30: 「motion一种玩法是变成白模，然后上人物和场景，
/// 白模不只是动作的捕捉，还有整个场景」. The reference video's WHOLE scene becomes a grey model —
/// the performer and the floor, the walls, every pot and frame — and new people in a new place
/// are painted over it.
///
///   1. MoGe-2 on the box's ComfyUI reads the geometry of every frame; its normals and depth
///      come back as videos. The normals shaded as clay are the 白模 the person looks at; the
///      depth is what H3 follows.
///   2. Two reference pictures: who (her anchor, or a full-length portrait drawn from words)
///      and where (the place drawn empty, the reference's layout told object for object).
///   3. H3 films over the depth with both pictures as references — who and where from the
///      pictures, how they move and where everything stands from the model. Stretches of five
///      to ten seconds, each after the first pinned to the last frame of the one before.
///
/// Measured on three seconds of a tai chi clip: the model in 6 min (MoGe level 9), the
/// pictures in 2, H3 in 5½ (draft). Not by an edited first frame: the image editor gave the
/// reference's photograph back unchanged, and painted the clay as "a photograph of a grey clay
/// statue" — the look has to come from references.
@MainActor
enum MotionWhole {
    /// MoGe's detail, 0–9. Level 9 took ~5 s a frame on the box.
    static let levelKey = "kinclaw.motion.whole.level"
    static var level: Int { UserDefaults.standard.object(forKey: levelKey) as? Int ?? 6 }

    /// The size the take is filmed at: the reference's shape on H3's 32-pixel grid at ~0.4 MP.
    static func size(of reference: URL) async -> (width: Int, height: Int) {
        let asset = AVURLAsset(url: reference)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (natural, turn) = try? await track.load(.naturalSize, .preferredTransform) else { return (864, 480) }
        let shown = natural.applying(turn)
        let aspect = abs(shown.width) / max(1, abs(shown.height))
        if aspect > 1.25 { return (864, 480) }
        if aspect < 0.8 { return (480, 864) }
        return (640, 640)
    }

    // MARK: The reference, cut

    /// `frames` frames of `reference` from `start`, at 24 a second, filling `size` (cropped to
    /// its shape from the middle), written as an H.264 video.
    static func cut(_ reference: URL, from start: Double, frames: Int, size: (width: Int, height: Int), to out: URL) async throws {
        let asset = AVURLAsset(url: reference)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 48)
        let length = try await asset.load(.duration).seconds
        guard start + Double(frames) / 24 <= length + 0.05 else {
            throw FilmStudio.Failure.message("参考视频从第 \(Int(start)) 秒起不够 \(String(format: "%.1f", Double(frames) / 24)) 秒")
        }
        var pictures: [CGImage] = []
        for index in 0..<frames {
            let at = CMTime(seconds: min(start + Double(index) / 24, max(0, length - 0.02)), preferredTimescale: 600)
            let image = try await generator.image(at: at).image
            pictures.append(fill(image, size))
        }
        try await write(pictures, size: size, to: out)
    }

    /// A picture scaled to cover `size`, the overflow cut off evenly.
    nonisolated static func fill(_ image: CGImage, _ size: (width: Int, height: Int)) -> CGImage {
        let (w, h) = (CGFloat(size.width), CGFloat(size.height))
        let scale = max(w / CGFloat(image.width), h / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (w - drawn.width) / 2, y: (h - drawn.height) / 2, width: drawn.width, height: drawn.height))
        return context.makeImage() ?? image
    }

    /// Frames to an H.264 file at 24 a second.
    nonisolated static func write(_ pictures: [CGImage], size: (width: Int, height: Int), to out: URL) async throws {
        try? FileManager.default.removeItem(at: out)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FilmStudio.Failure.message("写不了视频：\(out.lastPathComponent)") }
        writer.startSession(atSourceTime: .zero)
        for (index, picture) in pictures.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size.width, height: size.height,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                context.draw(picture, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 24))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? FilmStudio.Failure.message("视频没写完：\(out.lastPathComponent)") }
    }

    // MARK: The model

    /// MoGe-2 over one cut segment on the box: its normals and its depth, as videos beside
    /// `source`; the depth also left in ComfyUI's input as `depthName` for H3 to follow.
    static func model(_ source: URL, normal: URL, depth: URL, depthName: String, id: String) async throws {
        guard await BoxServices.shared.ensure(.comfy) else { throw FilmStudio.Failure.message("盒子上的 ComfyUI 起不来") }
        let base = BoxServices.base(.comfy)
        let name = try await FilmStudio.upload(source, as: "kinclaw-motion-\(id.prefix(40))-\(source.lastPathComponent)", to: base)
        func node(_ type: String, _ inputs: [String: Any]) -> [String: Any] { ["class_type": type, "inputs": inputs] }
        let graph: [String: Any] = [
            "1": node("LoadVideo", ["file": name]),
            "2": node("GetVideoComponents", ["video": ["1", 0]]),
            "3": node("LoadMoGeModel", ["model_name": "moge_2_vitl_normal_fp16.safetensors"]),
            "4": node("MoGeInference", ["moge_model": ["3", 0], "image": ["2", 0], "resolution_level": level, "fov_x_degrees": 0.0,
                                        "batch_size": 8, "force_projection": true, "apply_mask": true, "refine_steps": 0]),
            "5": node("MoGeRender", ["moge_geometry": ["4", 0], "output": "normal_opengl"]),
            "6": node("CreateVideo", ["images": ["5", 0], "fps": 24]),
            "7": node("SaveVideo", ["video": ["6", 0], "filename_prefix": "video/kinclaw-whole-normal", "format": "mp4", "codec": "h264"]),
            "8": node("MoGeRender", ["moge_geometry": ["4", 0], "output": "depth"]),
            "9": node("CreateVideo", ["images": ["8", 0], "fps": 24]),
            "10": node("SaveVideo", ["video": ["9", 0], "filename_prefix": "video/kinclaw-whole-depth", "format": "mp4", "codec": "h264"]),
        ]
        let files = try await outputs(graph, nodes: ["7", "10"], base: base, what: "白模", deadline: 3600)
        guard let normals = files["7"], let depths = files["10"] else { throw FilmStudio.Failure.message("白模跑完了但没存下来") }
        try normals.write(to: normal)
        try depths.write(to: depth)
        _ = try await FilmStudio.upload(depth, as: depthName, to: base)
    }

    /// Queue a graph and bring back the first file each of `nodes` saved.
    static func outputs(_ graph: [String: Any], nodes: [String], base: String, what: String,
                        deadline seconds: TimeInterval) async throws -> [String: Data] {
        guard let url = URL(string: base + "/prompt") else { throw FilmStudio.Failure.message("ComfyUI 地址不对") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": graph, "client_id": "kinclaw-motion"])
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let id = answer["prompt_id"] as? String else {
            throw FilmStudio.Failure.message("ComfyUI 不接这个\(what)：\(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
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
                    throw FilmStudio.Failure.message("\(what)出错：" + (messages.compactMap { $0["exception_message"] as? String }.first ?? "看盒子上的 comfy.log").prefix(300))
                }
                guard status?["completed"] as? Bool == true else { continue }
                var found: [String: Data] = [:]
                for node in nodes {
                    let saved = ((entry["outputs"] as? [String: Any])?[node] as? [String: Any])?["images"] as? [[String: Any]] ?? []
                    guard let file = saved.first, let name = file["filename"] as? String else { continue }
                    var parts = URLComponents(string: base + "/view")
                    parts?.queryItems = [URLQueryItem(name: "filename", value: name),
                                         URLQueryItem(name: "subfolder", value: file["subfolder"] as? String ?? ""),
                                         URLQueryItem(name: "type", value: "output")]
                    guard let view = parts?.url else { continue }
                    let (bytes, _) = try await URLSession.shared.data(from: view)
                    if bytes.count > 1000 { found[node] = bytes }
                }
                return found
            }
            throw FilmStudio.Failure.message("\(what)跑了 \(Int(seconds / 60)) 分钟还没好")
        } catch {
            if Task.isCancelled, let stop = URL(string: base + "/interrupt") {
                var request = URLRequest(url: stop, timeoutInterval: 5)
                request.httpMethod = "POST"
                _ = try? await URLSession.shared.data(for: request)
            }
            throw error
        }
    }

    // MARK: Clay

    /// The normals shaded as grey clay, lit from the upper left and the front: the white
    /// model as a person sees it. Where MoGe found no surface (the sky) is a light grey.
    /// Also its first frame, as a picture, for the stop and the agent.
    static func clay(from normals: URL, to out: URL, first: URL) async throws {
        let asset = AVURLAsset(url: normals)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw FilmStudio.Failure.message("白模视频是空的") }
        let natural = try await track.load(.naturalSize)
        let size = (width: Int(natural.width), height: Int(natural.height))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? FilmStudio.Failure.message("读不了白模视频") }
        var pictures: [CGImage] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            if let picture = shade(buffer) { pictures.append(picture) }
        }
        guard let opening = pictures.first else { throw FilmStudio.Failure.message("白模视频是空的") }
        try write(png: opening, to: first)
        try await write(pictures, size: size, to: out)
    }

    /// One frame of normals (BGRA) to clay — in Accelerate's vector operations, because the
    /// app is built for debugging and a plain loop over a hundred million pixels is minutes.
    nonisolated static func shade(_ buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), count = width * height
        var source = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                   rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        // BGRA into four planes of bytes (four arrays: one array's elements cannot be lent out
        // together), then the three colours into floats.
        var blue = [UInt8](repeating: 0, count: count), green = blue, red = blue, alpha = blue
        var ok = true
        blue.withUnsafeMutableBytes { p0 in green.withUnsafeMutableBytes { p1 in
            red.withUnsafeMutableBytes { p2 in alpha.withUnsafeMutableBytes { p3 in
                var b0 = vImage_Buffer(data: p0.baseAddress, height: source.height, width: source.width, rowBytes: width)
                var b1 = vImage_Buffer(data: p1.baseAddress, height: source.height, width: source.width, rowBytes: width)
                var b2 = vImage_Buffer(data: p2.baseAddress, height: source.height, width: source.width, rowBytes: width)
                var b3 = vImage_Buffer(data: p3.baseAddress, height: source.height, width: source.width, rowBytes: width)
                ok = vImageConvert_ARGB8888toPlanar8(&source, &b0, &b1, &b2, &b3, vImage_Flags(kvImageNoFlags)) == kvImageNoError
            } }
        } }
        guard ok else { return nil }
        let n = vDSP_Length(count)
        func floats(_ bytes: [UInt8]) -> [Float] {
            var out = [Float](repeating: 0, count: count)
            vDSP_vfltu8(bytes, 1, &out, 1, n)
            return out
        }
        // A normal is (R, G, B) / 127.5 − 1. Every step writes a new array: Swift will not lend
        // one array as both input and output of a call.
        func fresh() -> [Float] { [Float](repeating: 0, count: count) }
        let r = floats(red), g = floats(green), b = floats(blue)
        var rg = fresh(), sum = fresh()
        vDSP_vadd(r, 1, g, 1, &rg, 1, n)
        vDSP_vadd(rg, 1, b, 1, &sum, 1, n)
        var scale: Float = 1 / 127.5, shift: Float = -1
        var nx = fresh(), ny = fresh(), nz = fresh()
        vDSP_vsmsa(r, 1, &scale, &shift, &nx, 1, n)
        vDSP_vsmsa(g, 1, &scale, &shift, &ny, 1, n)
        vDSP_vsmsa(b, 1, &scale, &shift, &nz, 1, n)
        // Light from the upper left, toward the camera.
        var lx: Float = -0.4685, ly: Float = 0.5727, lz: Float = 0.7290
        var d1 = fresh(), d2 = fresh(), dot = fresh()
        vDSP_vsmul(nx, 1, &lx, &d1, 1, n)
        vDSP_vsma(ny, 1, &ly, d1, 1, &d2, 1, n)
        vDSP_vsma(nz, 1, &lz, d2, 1, &dot, 1, n)
        var qx = fresh(), qy = fresh(), qz = fresh(), qxy = fresh(), squared = fresh(), root = fresh()
        vDSP_vsq(nx, 1, &qx, 1, n)
        vDSP_vsq(ny, 1, &qy, 1, n)
        vDSP_vsq(nz, 1, &qz, 1, n)
        vDSP_vadd(qx, 1, qy, 1, &qxy, 1, n)
        vDSP_vadd(qxy, 1, qz, 1, &squared, 1, n)
        var counted = Int32(count)
        vvsqrtf(&root, squared, &counted)
        var floor: Float = 1e-3
        var safe = fresh(), ratio = fresh(), lit = fresh()
        vDSP_vthr(root, 1, &floor, &safe, 1, n)                     // never divide by nothing
        vDSP_vdiv(safe, 1, dot, 1, &ratio, 1, n)                    // dot / length
        var zero: Float = 0
        vDSP_vthres(ratio, 1, &zero, &lit, 1, n)                    // turned away → unlit
        var gain: Float = 0.78 * 255, lift: Float = 0.22 * 255
        var shaded = fresh()
        vDSP_vsmsa(lit, 1, &gain, &lift, &shaded, 1, n)
        // Where MoGe found no surface — black, or no real normal — a light grey instead.
        var dark: Float = 12, one: Float = 1, weak: Float = 0.3, half: Float = 0.5
        var surface = fresh(), real = fresh(), surface01 = fresh(), real01 = fresh(), mask = fresh()
        vDSP_vlim(sum, 1, &dark, &one, &surface, 1, n)              // +1 surface, −1 none
        vDSP_vlim(root, 1, &weak, &one, &real, 1, n)
        vDSP_vsmsa(surface, 1, &half, &half, &surface01, 1, n)      // → 1 or 0
        vDSP_vsmsa(real, 1, &half, &half, &real01, 1, n)
        vDSP_vmul(surface01, 1, real01, 1, &mask, 1, n)
        var light: Float = 237
        var back = fresh(), lifted = fresh(), kept = fresh(), grey = fresh(), clipped = fresh()
        vDSP_vfill(&light, &back, 1, n)
        vDSP_vsub(back, 1, shaded, 1, &lifted, 1, n)                // shaded − 237
        vDSP_vmul(lifted, 1, mask, 1, &kept, 1, n)                  // × mask
        vDSP_vadd(kept, 1, back, 1, &grey, 1, n)                    // + 237
        var low: Float = 0, high: Float = 255
        vDSP_vclip(grey, 1, &low, &high, &clipped, 1, n)
        var bytes = [UInt8](repeating: 0, count: count)
        vDSP_vfixu8(clipped, 1, &bytes, 1, n)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    nonisolated static func write(png image: CGImage, to file: URL) throws {
        guard let out = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FilmStudio.Failure.message("存不下 \(file.lastPathComponent)")
        }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { throw FilmStudio.Failure.message("存不下 \(file.lastPathComponent)") }
    }

    // MARK: The references and the words

    /// How the person and the place are put to the models in English. `looks` is written as
    /// what each thing becomes ("the brown brick wall becomes a white plastered wall"), and
    /// told so the image model drew the brick wall too: only what things become is kept, where
    /// they stood (2026-09-30).
    static let whoRole = "the person who performs, how they look and what they wear"
    static let placeRole = "place as it is to look now — for each \"A becomes B\" write only B, standing where A stood, and never name A —"

    /// A rewritten phrase without its closing stop, to go inside a sentence.
    static func inner(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".。")))
    }

    /// Who, as a picture: her anchor when the take is hers, else a full-length portrait drawn
    /// from the words — plain background, the whole figure, nothing of the place.
    static func drawWho(_ who: String, to file: URL, seed: Int) async throws {
        let english = inner(await FilmStudio.english(who, as: whoRole))
        let words = "Full-length photograph of \(english), standing upright facing the camera, the whole body from head to feet "
            + "in the frame, arms relaxed, plain soft grey background, soft daylight, photographic detail. Nobody else."
        let made = try await DiffuserClient.shared.generate(prompt: words, into: file.deletingLastPathComponent(),
                                                            width: 480, height: 864, seed: seed)
        try keep(made, as: file, words: words)
    }

    /// Where, as a picture: the place drawn empty at the take's size, the reference's layout
    /// told object for object in `looks`.
    static func drawPlace(_ looks: String, size: (width: Int, height: Int), to file: URL, seed: Int) async throws {
        let english = inner(await FilmStudio.english(looks, as: placeRole))
        let words = "Eye-level photograph of an empty place: \(english). Nobody in it, the same framing as a film set seen from "
            + "where the camera stands. Natural light, photographic detail."
        let made = try await DiffuserClient.shared.generate(prompt: words, into: file.deletingLastPathComponent(),
                                                            width: size.width, height: size.height, seed: seed)
        try keep(made, as: file, words: words)
    }

    /// A drawn picture under the take's own name, with its words beside it — the drawing
    /// service's own note goes with it rather than staying behind under the old name.
    private static func keep(_ made: URL, as file: URL, words: String) throws {
        let fm = FileManager.default
        let note = file.appendingPathExtension("txt")
        if fm.fileExists(atPath: file.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let old = file.deletingPathExtension().lastPathComponent + ".before-\(stamp)"
            try? fm.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent(old + ".png"))
            try? fm.moveItem(at: note, to: file.deletingLastPathComponent().appendingPathComponent(old + ".png.txt"))
        }
        try fm.moveItem(at: made, to: file)
        try? fm.moveItem(at: URL(fileURLWithPath: made.path + ".txt"), to: note)
        if !fm.fileExists(atPath: note.path) { try? words.write(to: note, atomically: true, encoding: .utf8) }
    }

    /// H3's words when the agent gave none: MiniMax's full-reference form, six sections, the
    /// person and the place from the two pictures, the movement from the control.
    static func words(who: String, place: String, seconds: Double, hers: Bool) async -> String {
        let person = hers ? "the woman in <Picture 1>: her exact face, hair and clothes"
            : "the person in <Picture 1>: " + inner(await FilmStudio.english(who, as: whoRole))
        let where_ = inner(await FilmStudio.english(place, as: placeRole))
        return """
            subject_definitions:
            <Subject 1> is \(person).
            <Subject 2> is the place in <Picture 2>: \(where_).

            summary:
            Reference-to-video: <Subject 1> moves in <Subject 2>. One shot, \(String(format: "%.1f", seconds)) seconds, the camera \
            as in the control video.

            retention_analysis:
            <Subject 1> keeps the face, hair and clothes of <Picture 1> throughout. <Subject 2> keeps everything in <Picture 2>; \
            <Subject 1> stands and moves where the figure is in the control video.

            detailed_description:
            [Shot 1] <Subject 1> in <Subject 2>, the whole body in view. <Subject 1> performs the movement slowly and \
            continuously, every step, turn and gesture exactly as the control video shows, the clothes moving with the body. \
            Everything in <Subject 2> stays where it is. Natural light.

            overall_soundscape:
            The place's own quiet sound and the soft sound of the movement.

            non_diegetic_music:
            None.
            """
    }
}
