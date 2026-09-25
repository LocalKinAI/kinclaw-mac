import AppKit
import AVFoundation
import CoreImage
import CoreText
import Foundation

/// What a director does between the first cut and the one that is shown, as
/// things an agent can do: look at a shot second by second, count what the
/// story counts, change a picture to match another shot's, film a shot another
/// way, even out a shot's light, and master the sound.
///
/// Every one of these was first done by hand, on 五饼二鱼 (2026-09-24), after
/// its owner watched the automatic cut and listed what was wrong: six or seven
/// loaves in the basket instead of five, a thirteenth basket at the end, one
/// shot brighter than the rest, a square slice of bread, music too quiet — and
/// then "shot 7's bread is not shot 4's". The reviewer had passed every one of
/// those takes with a ten. What fixed them, and what did not:
///
///   - A number holds when the SET has it. The set drawn with exactly five
///     loaves gave five; five said only in words gave six and seven. So a
///     counted thing is counted in the set before a shot is filmed.
///   - H3 keeps faces, not things. It panned a shot asked to hold still and
///     invented baskets as the camera went; given shot 4's loaves as a
///     reference picture, it still tore white fuzz. What held the bread was
///     changing the first frame itself (Qwen-Image edit, shot 4's frame beside
///     it) and filming from that frame on LTX; what held the count was no video
///     model at all — the camera gliding over the counted picture.
///   - Counting is done one frame at a time, at full size. From a grid of small
///     frames the model that can see said ten baskets where there were twelve;
///     from one frame, counting row by row, it said twelve.
extension FilmStudio {

    // MARK: - What a shot can say about itself

    /// How a shot is filmed when it is not the film's own way.
    enum Method: String, Codable, CaseIterable {
        /// MiniMax H3, from the cast's portraits and the set (H3 films).
        case h3
        /// LTX from one picture: the shot's first frame is that picture, and
        /// what is in it moves. What the picture shows is what the shot shows.
        case animate
        /// No video model: the camera glides over the picture. Nothing in it can
        /// change, which is the only way a count is sure to stay right.
        case move

        var title: String {
            switch self { case .h3: return "H3"; case .animate: return "从图动"; case .move: return "运镜" }
        }
    }

    /// Where the camera goes in a `move` shot.
    enum Glide: String, Codable, CaseIterable {
        case pushIn = "push_in", pullOut = "pull_out", panLeft = "pan_left", panRight = "pan_right", rise, fall, hold

        var title: String {
            switch self {
            case .pushIn: return "推近"; case .pullOut: return "拉远"; case .panLeft: return "左摇"
            case .panRight: return "右摇"; case .rise: return "升"; case .fall: return "降"; case .hold: return "定"
            }
        }
    }

    /// A thing whose number the story turns on: five loaves, twelve baskets.
    struct Check: Codable, Equatable {
        var thing: String
        var count: Int
    }

    /// A thing that must look in this shot as it does in another: shot 7's
    /// bread as the loaves in shot 4.
    struct Match: Codable, Equatable {
        var thing: String
        var like: Int
    }

    /// A shot's light and colour, brought into line with the rest.
    struct Grade: Codable, Equatable {
        /// Stops of exposure: the light times 2^exposure.
        var exposure: Double
        /// Colourfulness; 1 leaves it as it was.
        var saturation: Double
        /// Set by the cut (a shot brighter or darker than both its neighbours),
        /// and so set again at every cut. Nil or false: somebody chose it.
        var auto: Bool? = nil

        var neutral: Bool { abs(exposure) < 0.01 && abs(saturation - 1) < 0.01 }
    }

    // MARK: - Looking

    /// Frames of a clip at the given seconds, no larger than `largest` a side.
    nonisolated static func frames(of clip: URL, at seconds: [Double], largest: CGFloat) async -> [(second: Double, image: CGImage)] {
        let asset = AVURLAsset(url: clip)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: largest, height: largest)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 48)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 48)
        var made: [(Double, CGImage)] = []
        for second in seconds {
            let at = min(max(second, 0), max(0, duration - 0.05))
            if let frame = try? await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)).image {
                made.append((at, frame))
            }
        }
        return made
    }

    /// Moments `every` seconds apart through a clip, and its last frame.
    nonisolated static func moments(in clip: URL, every: Double, most: Int = 12) async -> [Double] {
        guard let duration = try? await AVURLAsset(url: clip).load(.duration).seconds, duration > 0 else { return [] }
        // Never more than `most` frames: a long clip is looked at more sparsely.
        let step = max(every, duration / Double(most - 1), 0.25)
        var at = Array(stride(from: 0.0, to: duration - 0.3, by: step))
        at.append(max(0, duration - 0.05))
        return at
    }

    nonisolated static func picture(_ file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    nonisolated static func jpeg(_ image: CGImage, largest: Int? = nil, quality: Double = 0.85) -> Data? {
        var picture = image
        if let largest, max(image.width, image.height) > largest {
            let scale = Double(largest) / Double(max(image.width, image.height))
            let width = Int(Double(image.width) * scale), height = Int(Double(image.height) * scale)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let smaller = context.makeImage() else { return nil }
            picture = smaller
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, picture, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Pictures side by side, each with its label in the corner: a whole shot
    /// in one image, which is what a model that can see is given to look at.
    /// The labels are English because they are read by the model, not by
    /// the user.
    nonisolated static func contactSheet(_ cells: [(label: String, image: CGImage)], columns: Int = 3,
                                         width: Int = 480, to out: URL) -> Bool {
        guard let first = cells.first?.image, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let cellHeight = Int((Double(width) * Double(first.height) / Double(first.width)).rounded())
        let gap = 6
        let across = min(columns, cells.count)
        let down = (cells.count + across - 1) / across
        let canvasWidth = across * width + (across + 1) * gap
        let canvasHeight = down * cellHeight + (down + 1) * gap
        guard let context = CGContext(data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .high
        context.textMatrix = .identity
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 17, nil)
        for (i, cell) in cells.enumerated() {
            let column = i % across, row = i / across
            let box = CGRect(x: gap + column * (width + gap), y: canvasHeight - (gap + row * (cellHeight + gap)) - cellHeight,
                             width: width, height: cellHeight)
            // Fitted, not filled: a still of another shape is shown whole.
            let scale = min(box.width / CGFloat(cell.image.width), box.height / CGFloat(cell.image.height))
            let drawn = CGSize(width: CGFloat(cell.image.width) * scale, height: CGFloat(cell.image.height) * scale)
            context.draw(cell.image, in: CGRect(x: box.midX - drawn.width / 2, y: box.midY - drawn.height / 2,
                                                width: drawn.width, height: drawn.height))
            var attributes: [NSAttributedString.Key: Any] = [:]
            attributes[NSAttributedString.Key(kCTFontAttributeName as String)] = font
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = CGColor(gray: 1, alpha: 1)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: cell.label, attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, [])
            let pad: CGFloat = 5
            let tag = CGRect(x: box.minX + 6, y: box.maxY - 6 - bounds.height - 2 * pad,
                             width: bounds.width + 2 * pad, height: bounds.height + 2 * pad)
            context.setFillColor(CGColor(gray: 0, alpha: 0.62))
            context.addPath(CGPath(roundedRect: tag, cornerWidth: 5, cornerHeight: 5, transform: nil))
            context.fillPath()
            context.textPosition = CGPoint(x: tag.minX + pad - bounds.minX, y: tag.minY + pad - bounds.minY)
            CTLineDraw(line, context)
        }
        guard let image = context.makeImage(), let data = jpeg(image, quality: 0.82) else { return false }
        return (try? data.write(to: out, options: .atomic)) != nil
    }

    // MARK: - Counting

    /// The model that counts: kimi-k3 where it is — asked to put a box on every
    /// object, it counted five loaves and twelve baskets right in every frame it
    /// was shown, twice, in two to eight seconds; kimi-k2.6, asked the same, said
    /// four for five and sometimes took a minute. `kinclaw.film.counter` names
    /// another; without either, whoever reviews the takes counts.
    static func counter() async -> (host: String, model: String)? {
        let chosen = UserDefaults.standard.string(forKey: "kinclaw.film.counter") ?? "kimi-k3:cloud"
        for entry in await candidates() where entry.models.contains(chosen) { return (entry.host, chosen) }
        return await seer()
    }

    /// How many `thing` a picture shows: the number of boxes the counter puts
    /// on them. Asked for a number instead ("count them, row by row"), models
    /// counted one loaf twice as often as not; one box per object keeps each
    /// object once. Where the boxes are is not used — kimi-k3 put twelve boxes
    /// on twelve baskets a hundred pixels above them.
    static func count(_ thing: String, in picture: Data) async -> Int? {
        guard let counter = await counter(), let url = URL(string: counter.host + "/api/chat") else { return nil }
        let ask = """
            Find every \(thing) in this picture and give each one's bounding box. One box per object, never two \
            boxes on the same object; include ones partly hidden or cut off by the edge. Answer with a JSON list \
            only: [{"bbox_2d": [x1, y1, x2, y2], "label": "\(thing)"}]
            """
        let body: [String: Any] = ["model": counter.model, "stream": false, "think": false,
                                   "messages": [["role": "user", "content": ask, "images": [picture.base64EncodedString()]]]]
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        // Twice: now and then an answer comes back with nothing in it.
        for _ in 0..<2 {
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let words = (reply["message"] as? [String: Any])?["content"] as? String,
                  let close = words.lastIndex(of: "]") else { continue }
            // The outermost list: the last "[" that parses to the end is it
            // (the ones after it open a box's four numbers).
            var open = close
            while let earlier = words[..<open].lastIndex(of: "[") {
                if let list = try? JSONSerialization.jsonObject(with: Data(words[earlier...close].utf8)) as? [Any],
                   list.allSatisfy({ $0 is [String: Any] || $0 is [Any] }) {
                    return list.count
                }
                open = earlier
            }
        }
        return nil
    }

    /// Counted again where the first count is off: a take costs minutes, and
    /// is only called wrong when a second count does not come out right either.
    static func tally(_ check: Check, in picture: Data) async -> Int? {
        guard let first = await count(check.thing, in: picture) else { return nil }
        guard first != check.count, let again = await count(check.thing, in: picture) else { return first }
        return again == check.count ? again : first
    }

    /// Every check against the pictures, all at once: one sentence naming the
    /// wrong numbers and where, or nil when there is nothing wrong.
    ///
    /// `exact` is for the picture a shot is filmed from, which must show all of
    /// them. In a take a frame with fewer is not a fault — a hand over a loaf,
    /// a basket not yet in the frame (the first frame of 五饼二鱼's shot 4 shows
    /// two loaves, truthfully) — so a take is wrong only where there are more,
    /// in at least two of its frames: what H3 does is add.
    static func miscounted(_ checks: [Check], in pictures: [(second: Double?, data: Data)], exact: Bool) async -> String? {
        var wrong: [String] = []
        for check in checks {
            let counted = await withTaskGroup(of: (Int, Int?).self) { group -> [Int: Int] in
                for (i, picture) in pictures.enumerated() {
                    group.addTask { (i, await Self.tally(check, in: picture.data)) }
                }
                var got: [Int: Int] = [:]
                for await (i, n) in group { if let n { got[i] = n } }
                return got
            }
            // Nobody counted is not the same as right.
            if counted.isEmpty { return Self.uncounted + "：\(check.thing)（数数的模型没答上来）" }
            let off = pictures.indices.filter { i in
                guard let n = counted[i] else { return false }
                return exact ? n != check.count : n > check.count
            }
            guard exact ? !off.isEmpty : off.count >= min(2, pictures.count) else { continue }
            let said = off.map { i -> String in
                let when = pictures[i].second.map { "第 \(String(format: "%.1f", $0)) 秒" } ?? "画面里"
                return "\(when)数到 \(counted[i]!)"
            }
            wrong.append("\(check.thing) 应该是 \(check.count)，" + said.joined(separator: "、"))
        }
        return wrong.isEmpty ? nil : "数不对：" + wrong.joined(separator: "；")
    }

    /// How `miscounted` begins when it could not count at all.
    static let uncounted = "数不出来"

    /// Five moments of a take, at full size, for counting.
    static func countingFrames(of clip: URL, every: Double? = nil) async -> [(second: Double?, data: Data)] {
        guard let duration = try? await AVURLAsset(url: clip).load(.duration).seconds, duration > 0 else { return [] }
        var at = [0.05, 0.25, 0.5, 0.75, 0.98].map { $0 * duration }
        if let every { at = await moments(in: clip, every: every, most: 8) }
        return await frames(of: clip, at: at, largest: 1024).compactMap { frame in
            jpeg(frame.image).map { (Optional(frame.second), $0) }
        }
    }

    /// A take's counts, a frame every second: nil when the shot counts nothing
    /// or every count is right. Every second, not five fixed moments: a pinned
    /// shot of twelve baskets wandered off to a slope with fourteen at two
    /// seconds and at four, and was counted right at 1.3, 2.6 and 3.9.
    static func recount(_ shot: Shot, in film: Film) async -> String? {
        guard let checks = shot.checks, !checks.isEmpty else { return nil }
        let pictures = await countingFrames(of: film.clip(shot.id), every: 1)
        guard !pictures.isEmpty else { return nil }
        let said = await miscounted(checks, in: pictures, exact: false)
        return said?.hasPrefix(uncounted) == true ? nil : said
    }

    /// A verdict with a wrong count folded in: whatever the reviewer thought of
    /// the take, a basket too many is a take to do again.
    static func miscount(_ verdict: Verdict, _ problem: String) -> Verdict {
        var failed = verdict
        failed.ok = false
        failed.score = min(verdict.score, 4)
        failed.problem = problem
        failed.fix = .clip
        return failed
    }

    /// "exactly five (5) round flat barley loaves, each whole and separate",
    /// for the words a picture is drawn from.
    static func counted(_ checks: [Check]?) -> String? {
        guard let checks, !checks.isEmpty else { return nil }
        return checks.map { "Exactly \($0.count) \($0.thing) — \($0.count), no more and no fewer — each one whole, separate and clearly visible" }
            .joined(separator: ". ") + "."
    }

    /// Before a shot with counted things is filmed, its picture is counted, and
    /// a picture with the wrong number is repainted to the right one, twice at
    /// most. What the set shows is what H3 keeps.
    func settle(_ film: inout Film, _ index: Int) async {
        guard let checks = film.shots[index].checks, !checks.isEmpty else { return }
        let id = film.shots[index].id
        let fm = FileManager.default
        for attempt in 0..<3 {
            let still = film.still(id)
            guard let image = Self.picture(still), let data = Self.jpeg(image, largest: 1024) else { return }
            guard let wrong = await Self.miscounted(checks, in: [(nil, data)], exact: true) else {
                if attempt > 0 { film.note = nil; save(film) }
                return
            }
            if wrong.hasPrefix(Self.uncounted) {
                film.shots[index].note = "布景\(wrong)，没改它"
                save(film)
                return
            }
            guard attempt < 2 else {
                film.shots[index].note = "布景\(wrong)（改了两次还不对）"
                save(film)
                return
            }
            // A repaint keeps the picture's layout, crowding and all: the
            // second time round the set is drawn fresh, with room to count.
            if attempt == 1, let words = film.shots[index].picture {
                film.note = "第 \(id) 镜的布景\(wrong)，重新画几张挑数目对的"
                save(film)
                let out = film.folder.appendingPathComponent(String(format: "shot-%02d.counted.png", id))
                do {
                    let left = try await Self.drawCounted(words, checks: checks, size: film.size, tries: 3, to: out,
                                                          tag: "\(film.id)-\(id)")
                    try? fm.moveItem(at: still, to: film.take(id, "miscount-\(Int(Date().timeIntervalSince1970))", "png"))
                    try fm.moveItem(at: out, to: still)
                    FilmReference.reshape(still, to: film.size)
                    if let left { film.shots[index].note = "布景重画了三张，最接近的一张还是\(left)" }
                    film.note = nil
                    save(film)
                } catch {
                    film.shots[index].note = "布景\(wrong)，重画没成：\(error.localizedDescription)"
                    film.note = nil
                    save(film)
                }
                return
            }
            film.note = "第 \(id) 镜的布景\(wrong)，在改"
            save(film)
            let numbers = checks.map { "exactly \($0.count) \($0.thing)" }.joined(separator: " and ")
            let instruction = """
                Change only how many there are: the picture must show \(numbers) — each one whole, separate and easy \
                to count, none cut off by the edge of the frame, none hidden behind another. Keep everything else \
                exactly as it is: the place, the light, the framing, the style.
                """
            let out = film.folder.appendingPathComponent(String(format: "shot-%02d.counted.png", id))
            do {
                try await Self.repaint(still, like: [], instruction: instruction,
                                       seed: CompanionCharacter.seed(for: film.id + String(id) + "count" + String(attempt)),
                                       to: out, tag: "\(film.id)-\(id)")
                try? fm.moveItem(at: still, to: film.take(id, "miscount-\(Int(Date().timeIntervalSince1970))", "png"))
                try fm.moveItem(at: out, to: still)
            } catch {
                film.shots[index].note = "布景\(wrong)，改图没成：\(error.localizedDescription)"
                film.note = nil
                save(film)
                return
            }
        }
    }

    // MARK: - Changing a picture

    /// A picture changed by words, with other pictures to go by: Qwen-Image
    /// 2.1's edit, through ComfyUI on the box. Image 1 is the one changed; the
    /// pictures in `like` are Image 2, 3… — what the words can tell it to match.
    ///
    /// Not the edit server the stills are drawn with: told to make shot 7's
    /// bread look like the loaves in a frame of shot 4, this gave the same
    /// smooth tan loaves (the second time — "dark, cracked" had described
    /// them wrong), with the three men untouched. It keeps the size of image 1.
    static func repaint(_ source: URL, like references: [URL], instruction: String, seed: Int,
                        to out: URL, tag: String) async throws {
        guard await BoxServices.shared.ensure(.comfy) else { throw Failure.message("盒子上的 ComfyUI 起不来") }
        let base = BoxServices.base(.comfy)
        var names: [String] = []
        for (i, file) in ([source] + references).prefix(8).enumerated() {
            names.append(try await upload(file, as: "kinclaw-\(tag.prefix(48))-edit\(i + 1).png", to: base))
        }
        var encode: [String: Any] = ["prompt": instruction, "negative_prompt": "", "resolution": 0,
                                     "clip": ["2", 0], "vae": ["3", 0]]
        var graph: [String: Any] = [
            "1": node("UNETLoader", ["unet_name": "qwen_image_2.1_int8_convrot.safetensors", "weight_dtype": "default"]),
            "2": node("CLIPLoader", ["clip_name": "qwen3vl_8b_int8_convrot.safetensors", "type": "qwen_image", "device": "default"]),
            "3": node("VAELoader", ["vae_name": "qwen_image_2.1_vae_bf16.safetensors"]),
            "4": node("QwenImage21Cache", ["device": "auto", "dtype": "default", "model": ["1", 0]]),
            "6": node("KSampler", ["seed": seed, "steps": 25, "cfg": 1, "sampler_name": "euler", "scheduler": "simple",
                                   "denoise": 1, "model": ["4", 0], "positive": ["5", 0], "negative": ["5", 1],
                                   "latent_image": ["5", 2]]),
            "7": node("VAEDecode", ["samples": ["6", 0], "vae": ["3", 0]]),
            "8": node("SaveImage", ["filename_prefix": "kinclaw-film/edit", "images": ["7", 0]]),
        ]
        for (i, name) in names.enumerated() {
            graph["\(100 + i)"] = node("LoadImage", ["image": name])
            encode["images.image_\(i + 1)"] = ["\(100 + i)", 0]
        }
        graph["5"] = node("TextEncodeQwenImage21", encode)
        let picture = try await comfyResult(graph, node: "8", base: base, what: "改图", deadline: 900)
        try? FileManager.default.removeItem(at: out)
        try picture.write(to: out)
    }

    /// Pictures drawn fresh from words — Qwen-Image 2.1 through ComfyUI, the
    /// shape of the film — until one shows the right number of everything
    /// counted. Changing a picture keeps its layout, crowded layout included:
    /// asked four times for exactly twelve baskets, the edit gave fourteen,
    /// fourteen, fifteen. Drawn fresh, with room around each basket, the third
    /// of three was right. Returns the counted sentence of the one kept, nil
    /// when it is right; the closest is kept when none is.
    static func drawCounted(_ words: String, checks: [Check], size: CGSize, tries: Int, to out: URL,
                            tag: String) async throws -> String? {
        guard await BoxServices.shared.ensure(.comfy) else { throw Failure.message("盒子上的 ComfyUI 起不来") }
        let base = BoxServices.base(.comfy)
        let room = checks.isEmpty ? "" : " Everything that is counted stands apart, with a clear gap around each one, well inside "
            + "the frame — none cut off by the edge, none hidden behind another."
        let prompt = [words, counted(checks), room].compactMap { $0 }.joined(separator: " ")
        // About a megapixel, the film's shape, in steps of 16.
        let scale = (1_000_000 / Double(size.width * size.height)).squareRoot()
        let width = Int((Double(size.width) * scale / 16).rounded()) * 16
        let height = Int((Double(size.height) * scale / 16).rounded()) * 16
        var best: (off: Int, said: String?, data: Data)?
        for attempt in 0..<max(1, tries) {
            let graph: [String: Any] = [
                "1": node("UNETLoader", ["unet_name": "qwen_image_2.1_int8_convrot.safetensors", "weight_dtype": "default"]),
                "2": node("CLIPLoader", ["clip_name": "qwen3vl_8b_int8_convrot.safetensors", "type": "qwen_image", "device": "default"]),
                "3": node("VAELoader", ["vae_name": "qwen_image_2.1_vae_bf16.safetensors"]),
                "4": node("TextEncodeQwenImage21", ["prompt": prompt, "negative_prompt": "", "resolution": 1024, "clip": ["2", 0]]),
                "5": node("EmptyLatentImage", ["width": width, "height": height, "batch_size": 1]),
                "6": node("KSampler", ["seed": Int.random(in: 1...2_000_000_000), "steps": 25, "cfg": 1, "sampler_name": "euler",
                                       "scheduler": "simple", "denoise": 1, "model": ["1", 0], "positive": ["4", 0],
                                       "negative": ["4", 1], "latent_image": ["5", 0]]),
                "7": node("VAEDecode", ["samples": ["6", 0], "vae": ["3", 0]]),
                "8": node("SaveImage", ["filename_prefix": "kinclaw-film/draw-\(tag.prefix(40))-\(attempt)", "images": ["7", 0]]),
            ]
            let data = try await comfyResult(graph, node: "8", base: base, what: "画图", deadline: 900)
            guard !checks.isEmpty else { best = (0, nil, data); break }
            guard let image = NSBitmapImageRep(data: data)?.cgImage, let shown = jpeg(image, largest: 1024) else { continue }
            let said = await miscounted(checks, in: [(nil, shown)], exact: true)
            // How far off: the sum over the checks, each counted once more.
            var off = 0
            if said != nil {
                for check in checks { off += abs((await count(check.thing, in: shown) ?? 0) - check.count) }
            }
            if best == nil || off < best!.off { best = (off, said, data) }
            if said == nil { break }
        }
        guard let best else { throw Failure.message("一张也没画出来") }
        try? FileManager.default.removeItem(at: out)
        try best.data.write(to: out)
        return best.said
    }

    // MARK: - Pinning the first frame

    static let pinKey = "kinclaw.film.h3.pin"
    /// H3 films are filmed from a first frame made beforehand, unless this is
    /// turned off in the tab.
    static var pinOn: Bool { UserDefaults.standard.object(forKey: pinKey) as? Bool ?? true }

    /// A picture cut and scaled to fill exactly `width` × `height`, as PNG:
    /// a pinned frame has to be the size the shot is filmed at.
    nonisolated static func filling(_ file: URL, width: Int, height: Int) -> Data? {
        guard let image = picture(file), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let drawn = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(width) - drawn.width) / 2, y: (Double(height) - drawn.height) / 2,
                                       width: drawn.width, height: drawn.height))
        guard let filled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, filled, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Where an H3 shot is pinned: its first frame — the one made for it with
    /// its people in it, else its set — at frame 0. A shot that counts things
    /// with nobody in it is pinned at its middle and its end as well: pinned
    /// only at both ends, the twelve baskets wandered off to another slope in
    /// between (fourteen of them there) and came back, twice; pinned three
    /// times the shot held — twelve at every half second, the mist moving over
    /// the lake and the light changing, which the camera moved over a still
    /// never does. The boy's shot, pinned at its start, kept its five loaves.
    func pins(for shot: Shot, in film: Film) -> [(picture: URL, frame: Int)] {
        guard Self.pinOn, film.engine == .h3 else { return [] }
        let first = film.opening(shot.id)
        guard FileManager.default.fileExists(atPath: first.path) else { return [] }
        let held = (shot.who ?? []).isEmpty && !(shot.checks ?? []).isEmpty
        return [(first, 0)] + (held ? [(first, Self.h3Frames(film.seconds) / 2), (first, -1)] : [])
    }

    /// The first frame of an H3 shot with people in it, made before it is
    /// filmed: the set as image 1, the portraits of who is in it after it, and
    /// the storyboard's picture of the moment — so the people stand where the
    /// shot starts, holding what they hold, before H3 moves anything. Made in
    /// 141 s for 五饼二鱼's shot 4 and right the first time: the boy's face, five
    /// loaves, two fish, the hands coming in from the right.
    func composeFirst(_ film: inout Film, _ index: Int, attempt: Int = 0) async throws {
        let shot = film.shots[index]
        let fm = FileManager.default
        let names = (shot.who ?? []).filter { name in film.cast?.contains { $0.name == name } == true }
        let portraits = names.compactMap { name in film.cast?.firstIndex { $0.name == name } }
            .map { film.castPicture($0) }.filter { fm.fileExists(atPath: $0.path) }
        guard !portraits.isEmpty, fm.fileExists(atPath: film.still(shot.id).path) else { return }
        film.note = "第 \(shot.id) 镜：先做第一帧"
        save(film)
        let told = ["Image 1 is the place and what is in it."]
            + names.prefix(portraits.count).enumerated().map { "Image \($0.offset + 2) is \($0.element)." }
        let instruction = (told + [
            "Make one photograph of them together — the first frame of a film shot: \(shot.framing ?? "a medium shot").",
            Self.literal(shot.pose),
            "\(names.joined(separator: " and ")) keep exactly the faces, hair and clothes of their pictures. Nobody else is added close to the camera.",
            Self.counted(shot.checks) ?? "",
            film.tone ?? "",
            "Everything belongs to the time and place of the story: nothing modern, no text.",
            "Photorealistic film still, natural proportions, high micro detail.",
        ]).filter { !$0.isEmpty }.joined(separator: " ")
        let made = film.folder.appendingPathComponent(String(format: "shot-%02d.first.png", shot.id))
        try await Self.repaint(film.still(shot.id), like: portraits, instruction: instruction,
                               seed: CompanionCharacter.seed(for: film.id + String(shot.id) + "first" + String(attempt)),
                               to: made, tag: "\(film.id)-\(shot.id)")
        FilmReference.reshape(made, to: film.size)
        if fm.fileExists(atPath: film.start(shot.id).path) {
            try? fm.moveItem(at: film.start(shot.id), to: film.take(shot.id, "start-\(Int(Date().timeIntervalSince1970))", "png"))
        }
        try fm.moveItem(at: made, to: film.start(shot.id))
        film.note = nil
        save(film)
    }

    /// A first frame with too many of something is made again — changed once
    /// for the count, then composed afresh once — and said if it still has.
    /// Only too many: in a frame with people in it a hand covers a loaf and
    /// two fish lie one on the other — the boy's first frame, right, was
    /// counted as one fish three times running and made again for nothing.
    func settleFirst(_ film: inout Film, _ index: Int) async {
        guard let checks = film.shots[index].checks, !checks.isEmpty else { return }
        let id = film.shots[index].id
        let fm = FileManager.default
        for attempt in 0..<3 {
            guard let image = Self.picture(film.start(id)), let data = Self.jpeg(image, largest: 1024) else { return }
            guard let wrong = await Self.miscounted(checks, in: [(nil, data)], exact: false) else { return }
            if wrong.hasPrefix(Self.uncounted) { return }
            guard attempt < 2 else {
                film.shots[index].note = "第一帧\(wrong)（做了三次还不对）"
                save(film)
                return
            }
            do {
                if attempt == 0 {
                    let numbers = checks.map { "exactly \($0.count) \($0.thing)" }.joined(separator: " and ")
                    let out = film.folder.appendingPathComponent(String(format: "shot-%02d.first.png", id))
                    try await Self.repaint(film.start(id), like: [], instruction: """
                        Change only how many there are: the picture must show \(numbers) — each one whole, separate and \
                        easy to count. Keep everything else exactly as it is: the people, their faces and hands, the \
                        place, the light, the framing.
                        """, seed: CompanionCharacter.seed(for: film.id + String(id) + "firstcount"), to: out,
                        tag: "\(film.id)-\(id)")
                    try? fm.moveItem(at: film.start(id), to: film.take(id, "miscount-\(Int(Date().timeIntervalSince1970))", "png"))
                    try fm.moveItem(at: out, to: film.start(id))
                } else {
                    try await composeFirst(&film, index, attempt: attempt)
                }
            } catch {
                film.shots[index].note = "第一帧\(wrong)，重做没成：\(error.localizedDescription)"
                save(film)
                return
            }
        }
    }

    // MARK: - Making a thing match another shot

    /// What a thing looks like in a picture, in one sentence of a prop maker's
    /// words — read off the other shot's own frame rather than written from
    /// memory: written by hand as "dark, cracked", shot 4's smooth tan loaves
    /// came out wrong the first time.
    static func describeLook(_ thing: String, in picture: Data) async -> String? {
        let ask = """
            Describe the \(thing) in this picture in one short sentence, the way a prop maker would who has to make \
            another one exactly like it: colour, shape, size, surface. Only what is seen. Answer with ONE JSON object \
            and nothing else: {"looks": "..."}
            """
        guard let answer = await look(ask, at: [picture]),
              let looks = (answer["looks"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !looks.isEmpty else { return nil }
        return looks
    }

    /// The first frame of a shot whose `match` says a thing in it must look as
    /// it does in another shot: a frame from the start of its take, with that
    /// thing changed to the other shot's — which is how shot 7's bread came to
    /// be shot 4's loaves, after H3 with the loaves as a reference picture had
    /// torn white fuzz twice. It is filmed from on LTX, so the shot shows what
    /// the frame shows.
    func prepareMatch(_ film: inout Film, _ index: Int) async throws {
        let shot = film.shots[index]
        guard let match = shot.match else { return }
        let fm = FileManager.default
        let start = film.start(shot.id)
        guard !fm.fileExists(atPath: start.path) else { return }
        let ours = fm.fileExists(atPath: film.clip(shot.id).path) ? film.clip(shot.id) : Self.lastTake(of: shot.id, in: film)
        guard let ours, let length = try? await AVURLAsset(url: ours).load(.duration).seconds,
              let frame = await Self.frames(of: ours, at: [length * 0.05], largest: 4096).first else {
            throw Failure.message("第 \(shot.id) 镜还没有拍好的镜头，取不出要改的第一帧")
        }
        let theirs = film.clip(match.like)
        guard let theirLength = try? await AVURLAsset(url: theirs).load(.duration).seconds,
              let reference = await Self.frames(of: theirs, at: [theirLength * 0.3], largest: 4096).first else {
            throw Failure.message("第 \(match.like) 镜还没拍，没有可以照着的\(match.thing)")
        }
        let first = film.folder.appendingPathComponent(String(format: "shot-%02d.frame.png", shot.id))
        let model = film.folder.appendingPathComponent(String(format: "shot-%02d.like-%02d.png", shot.id, match.like))
        guard Self.png(frame.image, to: first), Self.png(reference.image, to: model) else { throw Failure.message("存不下要改的画面") }
        film.note = "第 \(shot.id) 镜：照第 \(match.like) 镜改\(match.thing)"
        save(film)
        var looks: String?
        if let shown = Self.jpeg(reference.image, largest: 1024) { looks = await Self.describeLook(match.thing, in: shown) }
        let instruction = [
            "Image 2 is a frame from another shot of the same film.",
            "Edit image 1. Make every \(match.thing) in image 1 look exactly like the \(match.thing) in image 2"
                + (looks.map { " — \($0)" } ?? "") + " — the same colour, shape, size and surface.",
            "Keep everything else in image 1 exactly as it is — the people, their faces, hair, clothes and hands, the poses, the place, the light, the framing.",
            "Photorealistic film still.",
        ].joined(separator: " ")
        try await Self.repaint(first, like: [model], instruction: instruction,
                               seed: CompanionCharacter.seed(for: film.id + String(shot.id) + "match"), to: start,
                               tag: "\(film.id)-\(shot.id)")
        film.note = nil
        save(film)
    }

    // MARK: - Filming another way

    /// A shot filmed other than the film's own way — on LTX from one picture, or
    /// by the camera gliding over it — into the shot's clip.
    func filmOtherwise(_ film: inout Film, _ index: Int) async throws {
        let shot = film.shots[index]
        if shot.method != .move { try await prepareMatch(&film, index) }
        let picture = film.opening(shot.id)
        guard FileManager.default.fileExists(atPath: picture.path) else {
            throw Failure.message("第 \(shot.id) 镜没有能拍的画面（布景或起始画面）")
        }
        let seconds = film.engine == .h3 ? Self.h3Seconds(film.seconds) : film.seconds
        if shot.method == .move {
            let size = await Self.clipSize(film) ?? film.size
            try await Self.glide(picture, shot.glide ?? .pushIn, seconds: seconds, size: size,
                                 sound: Self.lastTake(of: shot.id, in: film), to: film.clip(shot.id))
        } else {
            try await prepareMatch(&film, index)
            // LTX and whatever ComfyUI last loaded do not both fit beside H3.
            await ComfyStudio.yieldMemory()
            try await DiffuserClient.shared.generateVideo(prompt: Self.literal(shot.action), to: film.clip(shot.id),
                                                          seconds: seconds, width: Int(film.size.width),
                                                          height: Int(film.size.height), from: picture, timeout: 1800)
        }
    }

    /// When the video model will not keep a number — its camera wanders and
    /// finds a thirteenth basket — and nobody is in the shot, the camera glides
    /// over the counted set instead. The take is kept aside and its sound used.
    func glideInstead(_ film: inout Film, _ index: Int, because wrong: String) async {
        let id = film.shots[index].id
        let fm = FileManager.default
        // Only over a picture that is itself right.
        if let checks = film.shots[index].checks, let image = Self.picture(film.opening(id)),
           let data = Self.jpeg(image, largest: 1024), await Self.miscounted(checks, in: [(nil, data)], exact: true) != nil { return }
        let take = film.take(id, "miscount-\(Int(Date().timeIntervalSince1970))", "mp4")
        try? fm.moveItem(at: film.clip(id), to: take)
        let was = (film.shots[index].method, film.shots[index].glide)
        film.shots[index].method = .move
        if film.shots[index].glide == nil { film.shots[index].glide = .pushIn }
        do {
            try await filmOtherwise(&film, index)
            film.shots[index].score = nil
            film.shots[index].review = await Self.recount(film.shots[index], in: film) ?? ""
            film.shots[index].note = "\(wrong)。改成在数过的布景上运镜"
        } catch {
            try? fm.moveItem(at: take, to: film.clip(id))
            (film.shots[index].method, film.shots[index].glide) = was
            film.shots[index].note = "\(wrong)。想改成运镜，没成：\(error.localizedDescription)"
        }
        save(film)
    }

    /// The size the other shots of the film came out at, so a shot made here
    /// matches them.
    static func clipSize(_ film: Film) async -> CGSize? {
        for shot in film.shots where shot.state == .done && shot.method != .move {
            let clip = film.clip(shot.id)
            guard FileManager.default.fileExists(atPath: clip.path),
                  let track = try? await AVURLAsset(url: clip).loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize), size.width > 0 else { continue }
            return size
        }
        return nil
    }

    /// The most recently filmed take set aside for a shot: whose sound a shot
    /// made without a video model borrows.
    static func lastTake(of shot: Int, in film: Film) -> URL? {
        let prefix = String(format: "shot-%02d.take-", shot)
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: film.folder.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".mp4") }
            .map { film.folder.appendingPathComponent($0) }
            .max { (modified($0) ?? .distantPast) < (modified($1) ?? .distantPast) }
    }

    /// A shot made without a video model: the camera glides over one picture,
    /// eased in and out the way a dolly starts and stops, at twelve per cent of
    /// the frame — enough to be a camera move, not enough to show the edges.
    /// Nothing in the picture moves, and nothing can be added to it.
    nonisolated static func glide(_ picture: URL, _ move: Glide, seconds: Double, size: CGSize, sound: URL?,
                                  to out: URL) async throws {
        guard let source = self.picture(picture) else { throw Failure.message("读不了这张图：\(picture.lastPathComponent)") }
        let image = CIImage(cgImage: source)
        let width = Int(size.width) / 2 * 2, height = Int(size.height) / 2 * 2
        let count = max(24, Int((seconds * 24).rounded()))
        // At rest, the frame is the largest rectangle of the output's shape in
        // the middle of the picture.
        let whole = image.extent
        let shape = Double(width) / Double(height)
        let restWidth = min(whole.width, whole.height * shape), restHeight = restWidth / shape
        let travel = 0.12
        func frame(_ progress: Double) -> CGRect {
            let e = progress * progress * (3 - 2 * progress)
            var zoom = 1.0, dx = 0.0, dy = 0.0      // dx, dy: -1…1 of the room there is to move in
            switch move {
            case .pushIn: zoom = 1 + travel * e
            case .pullOut: zoom = 1 + travel * (1 - e)
            case .panLeft: zoom = 1 + travel; dx = 1 - 2 * e
            case .panRight: zoom = 1 + travel; dx = -1 + 2 * e
            case .rise: zoom = 1 + travel; dy = -1 + 2 * e
            case .fall: zoom = 1 + travel; dy = 1 - 2 * e
            case .hold: zoom = 1
            }
            let w = restWidth / zoom, h = restHeight / zoom
            let roomX = (whole.width - w) / 2, roomY = (whole.height - h) / 2
            return CGRect(x: whole.midX - w / 2 + dx * roomX, y: whole.midY - h / 2 + dy * roomY, width: w, height: h)
        }

        let fm = FileManager.default
        let silent = out.deletingLastPathComponent().appendingPathComponent(out.deletingPathExtension().lastPathComponent + ".glide.mp4")
        try? fm.removeItem(at: silent)
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000,
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
        let context = CIContext()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Failure.message("没有 sRGB") }
        let clamped = image.clampedToExtent()
        for i in 0..<count {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw Failure.message("写视频的缓冲没有了") }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let buffer = made else { throw Failure.message("写视频的缓冲没有了") }
            let rect = frame(count == 1 ? 0 : Double(i) / Double(count - 1))
            let scale = Double(width) / rect.width
            let shown = clamped.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)))
            context.render(shown, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: space)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 24))
        }
        input.markAsFinished()
        let length = CMTime(value: CMTimeValue(count), timescale: 24)
        writer.endSession(atSourceTime: length)
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure.message("视频没写完：\(writer.error?.localizedDescription ?? "")") }

        // The sound of the take this replaces, under the new picture: the
        // place's own wind and voices, which a still has none of.
        guard let sound, let heard = try? await AVURLAsset(url: sound).loadTracks(withMediaType: .audio).first,
              let heardLength = try? await AVURLAsset(url: sound).load(.duration) else {
            try? fm.removeItem(at: out)
            try fm.moveItem(at: silent, to: out)
            return
        }
        let composition = AVMutableComposition()
        guard let seen = try await AVURLAsset(url: silent).loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.message("配不上声音")
        }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: seen, at: .zero)
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, heardLength)), of: heard, at: .zero)
        let joined = out.deletingLastPathComponent().appendingPathComponent(out.deletingPathExtension().lastPathComponent + ".joined.mp4")
        try await export(composition, preset: AVAssetExportPresetPassthrough, to: joined)
        try? fm.removeItem(at: silent)
        try? fm.removeItem(at: out)
        try fm.moveItem(at: joined, to: out)
    }

    /// Export, and say why when it does not finish.
    nonisolated static func export(_ asset: AVAsset, preset: String, video: AVVideoComposition? = nil,
                                   to out: URL) async throws {
        try? FileManager.default.removeItem(at: out)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.message("这台机器导不出视频")
        }
        session.outputURL = out
        session.outputFileType = .mp4
        if let video { session.videoComposition = video }
        await session.export()
        guard session.status == .completed else {
            throw Failure.message(session.error?.localizedDescription ?? "导出没完成")
        }
    }

    // MARK: - Light

    /// How bright and how colourful a clip is: the mean luma (0–255, Rec. 709
    /// weights) and mean chroma over five frames.
    nonisolated static func measure(_ clip: URL) async -> (luma: Double, chroma: Double)? {
        guard let duration = try? await AVURLAsset(url: clip).load(.duration).seconds, duration > 0 else { return nil }
        let taken = await frames(of: clip, at: [0.1, 0.3, 0.5, 0.7, 0.9].map { $0 * duration }, largest: 192)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = 96, height = 54
        var luma = 0.0, chroma = 0.0, pixels = 0.0
        for (_, image) in taken {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let _ = Optional(context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))),
                  let raw = context.data else { continue }
            let p = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
            for i in 0..<(width * height) {
                let r = Double(p[i * 4]), g = Double(p[i * 4 + 1]), b = Double(p[i * 4 + 2])
                luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
                let u = -0.1146 * r - 0.3854 * g + 0.5 * b, v = 0.5 * r - 0.4542 * g - 0.0458 * b
                chroma += (u * u + v * v).squareRoot()
                pixels += 1
            }
        }
        return pixels > 0 ? (luma / pixels, chroma / pixels) : nil
    }

    /// The grade that brings `clip`'s mean luma and chroma to `target`'s.
    nonisolated static func grade(from measured: (luma: Double, chroma: Double),
                                  to target: (luma: Double, chroma: Double), auto: Bool? = nil) -> Grade {
        // Exposure works on linear light and the mean is of encoded values,
        // which go as light to the 1/2.2.
        let exposure = measured.luma > 1 ? 2.2 * log2(target.luma / measured.luma) : 0
        let ratio = measured.chroma > 1 ? target.chroma / measured.chroma : 1
        let saturation = abs(ratio - 1) > 0.08 ? min(max(ratio, 0.8), 1.25) : 1
        return Grade(exposure: min(max(exposure, -1.5), 1.5), saturation: saturation, auto: auto)
    }

    /// A clip with a grade applied, written beside it.
    nonisolated static func regrade(_ clip: URL, _ grade: Grade, to out: URL) async throws {
        let asset = AVURLAsset(url: clip)
        let exposure = grade.exposure, saturation = grade.saturation
        let look = try await AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
            let lit = request.sourceImage.clampedToExtent()
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation,
                                                                kCIInputBrightnessKey: 0, kCIInputContrastKey: 1])
                .cropped(to: request.sourceImage.extent)
            request.finish(with: lit, context: nil)
        })
        let partial = out.deletingLastPathComponent().appendingPathComponent(out.deletingPathExtension().lastPathComponent + ".partial.mp4")
        try await export(asset, preset: AVAssetExportPresetHighestQuality, video: look, to: partial)
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: partial, to: out)
    }

    /// A shot plainly brighter or darker than both the shots around it, when
    /// those two agree with each other, is brought to them — shot 3 of 五饼二鱼
    /// was "a little brighter than the rest". A change that carries on (evening
    /// falling over the last shots) is not a spike and is left alone, and so is
    /// the first or last shot, which has only one neighbour to go by. A grade
    /// somebody chose is never touched.
    func matchSpikes(_ film: inout Film) async {
        let done = film.shots.indices.filter { film.shots[$0].state == .done }
        var measured: [Int: (luma: Double, chroma: Double)] = [:]
        for index in done {
            if let m = await Self.measure(film.clip(film.shots[index].id)) { measured[index] = m }
        }
        for (k, index) in done.enumerated() where film.shots[index].grade == nil || film.shots[index].grade?.auto == true {
            film.shots[index].grade = nil
            guard k > 0, k + 1 < done.count, let x = measured[index],
                  let a = measured[done[k - 1]], let b = measured[done[k + 1]] else { continue }
            let fromA = x.luma - a.luma, fromB = x.luma - b.luma
            guard abs(a.luma - b.luma) <= 6, fromA * fromB > 0,
                  min(abs(fromA), abs(fromB)) >= 4, max(abs(fromA), abs(fromB)) <= 30 else { continue }
            film.shots[index].grade = Self.grade(from: x, to: ((a.luma + b.luma) / 2, (a.chroma + b.chroma) / 2), auto: true)
        }
    }

    // MARK: - The cut, graded and mastered

    /// The shots that are done, cut: each as graded, the voice and the music
    /// under them, and the whole mastered. Every road to a film ends here.
    func assemble(_ film: inout Film, music: Bool = true) async throws {
        await matchSpikes(&film)
        let done = film.shots.filter { $0.state == .done }
        var clips: [URL] = []
        for shot in done {
            let raw = film.clip(shot.id)
            if let grade = shot.grade, !grade.neutral, FileManager.default.fileExists(atPath: raw.path) {
                do {
                    try await Self.regrade(raw, grade, to: film.graded(shot.id))
                    clips.append(film.graded(shot.id))
                    continue
                } catch {
                    NSLog("film: grading shot \(shot.id) failed, cut ungraded: \(error.localizedDescription)")
                }
            }
            clips.append(raw)
        }
        try await Self.cut(clips, voices: done.map { film.voice($0.id) },
                           voiceover: film.voiceover == nil ? nil : film.voiceoverFile,
                           music: music && Self.musicOn ? film.music : nil, to: film.file)
        do {
            film.loudness = try await Self.master(film.file, keeping: film.premaster)
        } catch {
            NSLog("film: mastering failed, the cut is as it came out: \(error.localizedDescription)")
        }
    }

    // MARK: - Mastering

    /// The cut brought to one loudness: −16 LUFS integrated (ITU-R BS.1770,
    /// gated), what a phone or a laptop plays comfortably, with peaks held
    /// under −1.5 dBFS by a look-ahead limiter. Done by hand for 五饼二鱼 with
    /// ffmpeg's loudnorm on the box; this Mac's ffmpeg does not run, and a
    /// stereo track needs nothing it lacks. The cut as it came out is kept as
    /// `premaster`. Returns the loudness after.
    nonisolated static func master(_ file: URL, keeping premaster: URL, target: Double = -16) async throws -> Double? {
        let asset = AVURLAsset(url: file)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let format = try await track.load(.formatDescriptions).first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return nil }
        let rate = basic.mSampleRate, channels = Int(basic.mChannelsPerFrame)
        guard rate > 0, channels > 0 else { return nil }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw Failure.message("读不了成片的声音") }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: length / 4))
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress! + start * 4)
            }
        }
        guard reader.status == .completed, samples.count > channels * Int(rate),
              let before = loudness(samples, channels: channels, rate: rate) else { return nil }

        var gain = pow(10, (target - before) / 20)
        var mastered = limited(samples, gain: gain, channels: channels, rate: rate)
        // The limiter takes a little off a loud film; once more makes it up.
        if let first = loudness(mastered, channels: channels, rate: rate), abs(first - target) > 0.3 {
            gain *= pow(10, (target - first) / 20)
            mastered = limited(samples, gain: gain, channels: channels, rate: rate)
        }
        let after = loudness(mastered, channels: channels, rate: rate)

        let folder = file.deletingLastPathComponent()
        let sound = folder.appendingPathComponent("film.master.m4a")
        let fm = FileManager.default
        try? fm.removeItem(at: sound)
        do {
            let written = try AVAudioFile(forWriting: sound, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 192_000,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            let frames = mastered.count / channels
            var at = 0
            while at < frames {
                let n = min(32_768, frames - at)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: written.processingFormat, frameCapacity: AVAudioFrameCount(n)),
                      let lanes = buffer.floatChannelData else { throw Failure.message("写不了母带的声音") }
                buffer.frameLength = AVAudioFrameCount(n)
                mastered.withUnsafeBufferPointer { all in
                    for c in 0..<channels {
                        let lane = lanes[c]
                        for i in 0..<n { lane[i] = all[(at + i) * channels + c] }
                    }
                }
                try written.write(from: buffer)
                at += n
            }
        }   // the file is closed here, when `written` goes

        // The same picture, the new sound.
        let composition = AVMutableComposition()
        for seen in try await asset.loadTracks(withMediaType: .video) {
            let range = try await seen.load(.timeRange)
            let lane = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try lane?.insertTimeRange(range, of: seen, at: range.start)
        }
        let heard = AVURLAsset(url: sound)
        guard let line = try await heard.loadTracks(withMediaType: .audio).first else { throw Failure.message("母带的声音是空的") }
        let lineLength = try await heard.load(.duration)
        let whole = try await asset.load(.duration)
        let lane = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try lane?.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(lineLength, whole)), of: line, at: .zero)
        let partial = folder.appendingPathComponent("film.mastered.partial.mp4")
        try await export(composition, preset: AVAssetExportPresetPassthrough, to: partial)
        try? fm.removeItem(at: premaster)
        try fm.moveItem(at: file, to: premaster)
        try fm.moveItem(at: partial, to: file)
        try? fm.removeItem(at: sound)
        return after
    }

    /// Integrated loudness, ITU-R BS.1770-4: K-weighted, mean square over 400 ms
    /// blocks every 100 ms, gated at −70 LUFS and then 10 LU under the mean of
    /// what passed. Filters from libebur128, which work at any sample rate.
    nonisolated static func loudness(_ samples: [Float], channels: Int, rate: Double) -> Double? {
        let frames = samples.count / channels
        let block = Int(rate * 0.4), hop = Int(rate * 0.1)
        guard frames > block, hop > 0 else { return nil }
        // Pre-filter: a high shelf of about +4 dB above 1.5 kHz (the head).
        var k = tan(Double.pi * 1681.974450955533 / rate)
        let vh = pow(10, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416), q1 = 0.7071752369554196
        var a0 = 1 + k / q1 + k * k
        let shelf = (b0: (vh + vb * k / q1 + k * k) / a0, b1: 2 * (k * k - vh) / a0, b2: (vh - vb * k / q1 + k * k) / a0,
                     a1: 2 * (k * k - 1) / a0, a2: (1 - k / q1 + k * k) / a0)
        // RLB: a high-pass at about 38 Hz.
        k = tan(Double.pi * 38.13547087602444 / rate)
        let q2 = 0.5003270373238773
        a0 = 1 + k / q2 + k * k
        let pass = (b0: 1.0, b1: -2.0, b2: 1.0, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q2 + k * k) / a0)

        // Every channel through both filters, and the squares summed across
        // channels (left and right weigh the same).
        var energy = [Double](repeating: 0, count: frames)
        samples.withUnsafeBufferPointer { all in
            energy.withUnsafeMutableBufferPointer { sum in
                for c in 0..<channels {
                    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0, w1 = 0.0, w2 = 0.0, z1 = 0.0, z2 = 0.0
                    for n in 0..<frames {
                        let x = Double(all[n * channels + c])
                        let y = shelf.b0 * x + shelf.b1 * x1 + shelf.b2 * x2 - shelf.a1 * y1 - shelf.a2 * y2
                        x2 = x1; x1 = x; y2 = y1; y1 = y
                        let z = pass.b0 * y + pass.b1 * w1 + pass.b2 * w2 - pass.a1 * z1 - pass.a2 * z2
                        w2 = w1; w1 = y; z2 = z1; z1 = z
                        sum[n] += z * z
                    }
                }
            }
        }
        var prefix = [Double](repeating: 0, count: frames + 1)
        for n in 0..<frames { prefix[n + 1] = prefix[n] + energy[n] }
        var blocks: [Double] = []
        var start = 0
        while start + block <= frames {
            blocks.append((prefix[start + block] - prefix[start]) / Double(block))
            start += hop
        }
        func lufs(_ power: Double) -> Double { -0.691 + 10 * log10(power) }
        let loud = blocks.filter { $0 > 0 && lufs($0) > -70 }
        guard !loud.isEmpty else { return nil }
        let floor = lufs(loud.reduce(0, +) / Double(loud.count)) - 10
        let gated = loud.filter { lufs($0) > floor }
        guard !gated.isEmpty else { return nil }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }

    /// `samples` times `gain`, with a look-ahead limiter keeping every sample
    /// under `ceiling` dBFS: the gain comes down smoothly over the 5 ms before
    /// a peak and goes back up over about 80 ms after it. Half a decibel under
    /// the −1.5 wanted, for the peaks between samples.
    nonisolated static func limited(_ samples: [Float], gain: Double, channels: Int, rate: Double,
                                    ceiling: Double = -2.0) -> [Float] {
        let frames = samples.count / channels
        guard frames > 0 else { return samples }
        let top = pow(10, ceiling / 20)
        let ahead = max(1, Int(rate * 0.005))
        let release = 1 - exp(-1 / (rate * 0.08))
        var result = [Float](repeating: 0, count: samples.count)
        samples.withUnsafeBufferPointer { all in
            // What each moment needs: the gain that keeps its loudest channel under the top.
            var need = [Double](repeating: 1, count: frames)
            for n in 0..<frames {
                var peak = 0.0
                for c in 0..<channels { peak = max(peak, abs(Double(all[n * channels + c])) * gain) }
                if peak > top { need[n] = top / peak }
            }
            // The least of it over the next `ahead` moments: a sliding minimum.
            var lowest = [Double](repeating: 1, count: frames)
            var queue: [Int] = []
            var head = 0
            let span = ahead + 1
            for j in 0..<frames {
                while queue.count > head, need[queue[queue.count - 1]] >= need[j] { queue.removeLast() }
                queue.append(j)
                if queue[head] <= j - span { head += 1 }
                let n = j - ahead
                if n >= 0 { lowest[n] = need[queue[head]] }
            }
            // The last few moments look ahead into nothing: the tail's minimum does.
            var tail = 1.0
            for n in stride(from: frames - 1, through: max(0, frames - ahead), by: -1) {
                tail = min(tail, need[n])
                lowest[n] = tail
            }
            // Averaged over the moments before: the gain slides down to each
            // peak instead of stepping, and never exceeds what the peak needs
            // (every moment averaged saw that peak in its look-ahead).
            var running = 0.0
            var smooth = 1.0
            result.withUnsafeMutableBufferPointer { out in
                for n in 0..<frames {
                    running += lowest[n]
                    if n >= span { running -= lowest[n - span] }
                    let average = running / Double(min(n + 1, span))
                    smooth = min(average, smooth + (1 - smooth) * release)
                    let g = Float(gain * smooth)
                    for c in 0..<channels { out[n * channels + c] = all[n * channels + c] * g }
                }
            }
        }
        return result
    }
}

// MARK: - Where a director's things are kept

extension FilmStudio.Film {
    /// A first frame made for a shot — a frame of its take, changed — which it
    /// is filmed from instead of its set when it is filmed from one picture.
    @MainActor func start(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.start.png", shot)) }
    /// The take as graded, which is what the cut uses when there is a grade.
    @MainActor func graded(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.graded.mp4", shot)) }
    /// What an agent was last shown of the shot.
    @MainActor func sheet(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.sheet.jpg", shot)) }
    /// The cut as it came out, before mastering.
    @MainActor var premaster: URL { folder.appendingPathComponent("film.premaster.mp4") }
    /// The picture a shot filmed from one picture starts from.
    @MainActor func opening(_ shot: Int) -> URL {
        FileManager.default.fileExists(atPath: start(shot).path) ? start(shot) : still(shot)
    }
}

// MARK: - For an agent

extension FilmStudio {
    /// Where a changed picture comes from: the set a shot is filmed in, a frame
    /// of its take (people and all), or a first frame made before.
    enum Source: String { case set, take, start, new }

    func film(named id: String) -> Film? {
        films.first(where: { $0.id == id || $0.title == id }) ?? films.first(where: { $0.id.hasPrefix(id) })
    }

    /// One shot in one picture, for an agent to look at: frames `every`
    /// seconds apart with the time on each, or the pictures it is filmed from,
    /// and a frame of each shot in `like` to compare with.
    func inspect(film id: String, shot number: Int, every: Double = 1, like: [Int] = [],
                 picture: Bool = false) async -> Result<(sheet: URL, said: String), Failure> {
        guard let film = film(named: id) else { return .failure(.message("没有这部片子：\(id)")) }
        guard let shot = film.shots.first(where: { $0.id == number }) else {
            return .failure(.message("「\(film.title)」没有第 \(number) 个镜头，它有 \(film.shots.count) 个"))
        }
        let fm = FileManager.default
        let clip = film.clip(number)
        let filmed = fm.fileExists(atPath: clip.path)
        var cells: [(label: String, image: CGImage)] = []
        if picture || !filmed {
            if let set = Self.picture(film.still(number)) {
                cells.append(("shot \(number) · \(film.engine == .h3 ? "set" : "still")", set))
            }
            if fm.fileExists(atPath: film.start(number).path), let first = Self.picture(film.start(number)) {
                cells.append(("shot \(number) · first frame", first))
            }
        } else {
            for frame in await Self.frames(of: clip, at: await Self.moments(in: clip, every: every), largest: 640) {
                cells.append(("shot \(number) · \(String(format: "%.1f", frame.second))s", frame.image))
            }
        }
        for other in like where other != number {
            let theirs = film.clip(other)
            if fm.fileExists(atPath: theirs.path), let length = try? await AVURLAsset(url: theirs).load(.duration).seconds,
               let frame = await Self.frames(of: theirs, at: [length * 0.3], largest: 640).first {
                cells.append(("shot \(other) · to compare", frame.image))
            } else if let still = Self.picture(film.still(other)) {
                cells.append(("shot \(other) · to compare (still)", still))
            }
        }
        guard !cells.isEmpty else { return .failure(.message("第 \(number) 镜还没有画面")) }
        guard Self.contactSheet(cells, to: film.sheet(number)) else { return .failure(.message("拼不出这张图")) }
        var said = ["「\(film.title)」第 \(number) 镜，\(cells.count) 格，从左到右、从上到下：" + cells.map(\.label).joined(separator: " | ")]
        if !filmed { said.append("（还没拍，给的是它要从哪张图拍）") }
        said.append("画面计划：\(shot.pose.prefix(240))")
        said.append("动作：\(shot.action.prefix(240))")
        if let checks = shot.checks, !checks.isEmpty {
            said.append("要数的：" + checks.map { "\($0.thing) \($0.count)" }.joined(separator: "，") + "（用 film_count 数，别凭这张小图数）")
        }
        if let method = shot.method { said.append("拍法：\(method.title)\(shot.glide.map { " · \($0.title)" } ?? "")") }
        return .success((film.sheet(number), said.joined(separator: "\n")))
    }

    /// Count a thing frame by frame — in the take, or in the picture the shot
    /// is filmed from — and, given the number it should be, say where it is not.
    func countThings(film id: String, shot number: Int, thing: String, expected: Int?, picture: Bool,
                     every: Double?) async -> Result<String, Failure> {
        guard let film = film(named: id) else { return .failure(.message("没有这部片子：\(id)")) }
        guard film.shots.contains(where: { $0.id == number }) else { return .failure(.message("没有第 \(number) 个镜头")) }
        let fm = FileManager.default
        let filmed = fm.fileExists(atPath: film.clip(number).path)
        var pictures: [(label: String, data: Data)] = []
        if picture || !filmed {
            for (label, file) in [("布景", film.still(number)), ("起始画面", film.start(number))] where fm.fileExists(atPath: file.path) {
                if let image = Self.picture(file), let data = Self.jpeg(image, largest: 1024) { pictures.append((label, data)) }
            }
        } else {
            let clip = film.clip(number)
            for frame in await Self.frames(of: clip, at: await Self.moments(in: clip, every: every ?? 1, most: 8), largest: 1024) {
                if let data = Self.jpeg(frame.image) { pictures.append(("\(String(format: "%.1f", frame.second)) 秒", data)) }
            }
        }
        guard !pictures.isEmpty else { return .failure(.message("第 \(number) 镜没有能数的画面")) }
        // One count a frame: a tool has under a minute, and the agent looks too.
        let counted = await withTaskGroup(of: (Int, Int?).self) { group -> [Int: Int] in
            for (i, shown) in pictures.enumerated() {
                group.addTask { (i, await Self.count(thing, in: shown.data)) }
            }
            var got: [Int: Int] = [:]
            for await (i, n) in group { if let n { got[i] = n } }
            return got
        }
        guard !counted.isEmpty else { return .failure(.message("数数的模型没答上来（\(await Self.counter()?.model ?? "找不到能看图的模型")）")) }
        var lines: [String] = []
        var more = 0, fewer = 0
        for (i, shown) in pictures.enumerated() {
            guard let n = counted[i] else { lines.append("  \(shown.label)：没数出来"); continue }
            if let expected, n > expected { more += 1 }
            if let expected, n < expected { fewer += 1 }
            lines.append("  \(shown.label)：\(n)\(expected.map { n == $0 ? " ✓" : n > $0 ? " ✗ 多了" : " · 少了" } ?? "")")
        }
        var head = "第 \(number) 镜里的 \(thing)（\(await Self.counter()?.model ?? "")数的，每帧数一次）"
        if let expected {
            head += more == 0 && fewer == 0 ? "：每一处都是 \(expected)" : "：应该是 \(expected)"
            if picture || !filmed {
                // The picture a shot is filmed from has to show every one of them.
                if more + fewer > 0 { head += "；要拍的画面里数目不对，拍之前先改好（film_fix_picture 再数），画里有几个，拍出来就是几个" }
            } else {
                if more > 0 { head += "；\(more) 帧多了 —— 多出来是真问题（两帧以上多就该修），可以再数一次确认" }
                if fewer > 0 { head += "；\(fewer) 帧少了 —— 在拍好的镜头里多半是被手挡住、叠在一起或刚入画，先看 film_frames 再说" }
            }
        }
        return .success(([head] + lines).joined(separator: "\n"))
    }

    /// Change a shot's picture with words, in the background (about two
    /// minutes): its set, a frame of its take — which becomes the first frame
    /// it is filmed from — or that first frame again. The shots in `like` are
    /// shown to the editor as Image 2, 3… The old picture is kept.
    func fixPicture(film id: String, shot number: Int, instruction: String, from given: Source?,
                    at second: Double?, like: [Int], counts: [Check]? = nil) -> Result<Film, Failure> {
        guard shooting == nil, revising == nil else { return .failure(.message("片场正忙（\(shooting ?? revising ?? "")），等它完了")) }
        guard var film = film(named: id) else { return .failure(.message("没有这部片子：\(id)")) }
        guard let index = film.shots.firstIndex(where: { $0.id == number }) else { return .failure(.message("没有第 \(number) 个镜头")) }
        // What the shot counts, said here: kept on the shot, so the new
        // picture is drawn and checked to it and so is every take after.
        if let counts {
            film.shots[index].checks = counts.isEmpty ? nil : counts
            save(film)
        }
        let words = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return .failure(.message("要怎么改？instruction 是空的")) }
        let fm = FileManager.default
        let from = given ?? (fm.fileExists(atPath: film.start(number).path) ? .start : .set)
        switch from {
        case .take where !fm.fileExists(atPath: film.clip(number).path):
            return .failure(.message("第 \(number) 镜还没拍，没有能取的画面；用 from: set 改布景"))
        case .start where !fm.fileExists(atPath: film.start(number).path):
            return .failure(.message("第 \(number) 镜还没有起始画面；用 from: take 从拍好的镜头里取一帧"))
        case .set where !fm.fileExists(atPath: film.still(number).path):
            return .failure(.message("第 \(number) 镜还没有布景"))
        default: break
        }
        if from == .new { return drawSet(film: film, shot: number, words: words) }
        let what = from == .set ? "布景" : "起始画面"
        revising = "改第 \(number) 镜的\(what)"
        work = Task { @MainActor in
            defer { revising = nil; work = nil }
            let stamp = Int(Date().timeIntervalSince1970)
            var latest = self.film(named: film.id) ?? film
            do {
                let source: URL
                switch from {
                case .set, .new: source = film.still(number)      // .new went to drawSet before this
                case .start: source = film.start(number)
                case .take:
                    source = film.folder.appendingPathComponent(String(format: "shot-%02d.frame.png", number))
                    guard let frame = await Self.frames(of: film.clip(number), at: [second ?? 0.2], largest: 4096).first,
                          Self.png(frame.image, to: source) else { throw Failure.message("取不出第 \(number) 镜的画面") }
                }
                var references: [URL] = []
                var told: [String] = []
                for other in like where other != number {
                    let reference = film.folder.appendingPathComponent(String(format: "shot-%02d.like-%02d.png", number, other))
                    let theirs = film.clip(other)
                    if fm.fileExists(atPath: theirs.path), let length = try? await AVURLAsset(url: theirs).load(.duration).seconds,
                       let frame = await Self.frames(of: theirs, at: [length * 0.3], largest: 4096).first,
                       Self.png(frame.image, to: reference) {
                        references.append(reference)
                    } else if fm.fileExists(atPath: film.still(other).path) {
                        try? fm.removeItem(at: reference)
                        try fm.copyItem(at: film.still(other), to: reference)
                        references.append(reference)
                    } else { continue }
                    told.append("Image \(references.count + 1) is a frame from shot \(other) of the same film.")
                }
                let prompt = (told + [
                    "Edit image 1. \(words)",
                    "Keep everything else in image 1 exactly as it is — the people, their faces, hair, clothes and hands, the poses, the place, the light, the framing.",
                    "Photorealistic film still.",
                ]).joined(separator: " ")
                let out = film.folder.appendingPathComponent(String(format: "shot-%02d.fixed.png", number))
                try await Self.repaint(source, like: references, instruction: prompt,
                                       seed: Int.random(in: 1...1_000_000_000), to: out, tag: "\(film.id)-\(number)")
                let target = from == .set ? film.still(number) : film.start(number)
                if fm.fileExists(atPath: target.path) {
                    try? fm.moveItem(at: target, to: film.take(number, (from == .set ? "fix-" : "startfix-") + "\(stamp)", "png"))
                }
                try fm.moveItem(at: out, to: target)
                latest = self.film(named: film.id) ?? latest
                latest.note = "第 \(number) 镜的\(what)改好了：\(target.path)"
                // Counted at once, so whoever asked knows without asking again.
                if let checks = latest.shots.first(where: { $0.id == number })?.checks, !checks.isEmpty,
                   let image = Self.picture(target), let data = Self.jpeg(image, largest: 1024) {
                    latest.note! += await Self.miscounted(checks, in: [(nil, data)], exact: true).map { "。数了一遍，还不对：\($0)" }
                        ?? "。数了一遍：" + checks.map { "\($0.thing) \($0.count) ✓" }.joined(separator: "，")
                }
            } catch {
                latest = self.film(named: film.id) ?? latest
                latest.note = "第 \(number) 镜改图没成：\(error.localizedDescription)"
            }
            save(latest)
        }
        return .success(film)
    }

    /// The set drawn fresh from words — three tries, the first that counts
    /// right kept — in the background. For a set whose numbers a repaint keeps
    /// getting wrong.
    private func drawSet(film: Film, shot number: Int, words: String) -> Result<Film, Failure> {
        let checks = film.shots.first(where: { $0.id == number })?.checks ?? []
        revising = "重画第 \(number) 镜的布景"
        work = Task { @MainActor in
            defer { revising = nil; work = nil }
            let fm = FileManager.default
            var latest = self.film(named: film.id) ?? film
            let out = film.folder.appendingPathComponent(String(format: "shot-%02d.drawn-new.png", number))
            do {
                let left = try await Self.drawCounted(words, checks: checks, size: film.size, tries: checks.isEmpty ? 1 : 3,
                                                      to: out, tag: "\(film.id)-\(number)")
                if fm.fileExists(atPath: film.still(number).path) {
                    try? fm.moveItem(at: film.still(number), to: film.take(number, "redraw-\(Int(Date().timeIntervalSince1970))", "png"))
                }
                try fm.moveItem(at: out, to: film.still(number))
                FilmReference.reshape(film.still(number), to: film.size)
                latest = self.film(named: film.id) ?? latest
                latest.note = "第 \(number) 镜的布景重画好了：\(film.still(number).path)"
                    + (checks.isEmpty ? "（这一镜没有要数的，只画了一张；要数就先在 film_reshoot 里给 counts）"
                       : left.map { "；画了三张，最接近的一张还是\($0)" } ?? "；数目对了")
            } catch {
                latest = self.film(named: film.id) ?? latest
                latest.note = "第 \(number) 镜重画没成：\(error.localizedDescription)"
            }
            save(latest)
        }
        return .success(film)
    }

    /// Whether a shot's set already shows the right numbers — counted, not
    /// assumed. Asked before a set is changed for its counts: a set that was
    /// right, changed anyway, came back with six loaves and a different bread.
    func setIsRight(film id: String, shot number: Int, checks: [Check]) async -> Bool {
        guard let film = film(named: id), let image = Self.picture(film.still(number)),
              let data = Self.jpeg(image, largest: 1024) else { return false }
        return await Self.miscounted(checks, in: [(nil, data)], exact: true) == nil
    }

    nonisolated static func png(_ image: CGImage, to file: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Light and colour: without a shot, every shot measured; with one, its
    /// grade set — to match another shot, by numbers, or off — and the film
    /// cut again.
    func regrade(film id: String, shot number: Int?, like: Int?, exposure: Double?, saturation: Double?,
                 off: Bool) async -> Result<String, Failure> {
        guard var film = film(named: id) else { return .failure(.message("没有这部片子：\(id)")) }
        guard let number else {
            var lines = ["「\(film.title)」每个镜头的亮度（0–255）和色彩浓度："]
            for shot in film.shots where shot.state == .done {
                guard let m = await Self.measure(film.clip(shot.id)) else { continue }
                let graded = shot.grade.map { $0.neutral ? "" : "，调色 \(String(format: "%+.2f", $0.exposure)) EV、饱和 ×\(String(format: "%.2f", $0.saturation))\($0.auto == true ? "（剪辑时自动加的）" : "")" } ?? ""
                lines.append("  \(shot.id). 亮度 \(String(format: "%.1f", m.luma)) · 色彩 \(String(format: "%.1f", m.chroma))\(graded)")
            }
            return .success(lines.joined(separator: "\n"))
        }
        guard shooting == nil, revising == nil else { return .failure(.message("片场正忙，等它完了")) }
        guard let index = film.shots.firstIndex(where: { $0.id == number }) else { return .failure(.message("没有第 \(number) 个镜头")) }
        if off {
            film.shots[index].grade = Grade(exposure: 0, saturation: 1, auto: false)
        } else if let like {
            guard let mine = await Self.measure(film.clip(number)), let theirs = await Self.measure(film.clip(like)) else {
                return .failure(.message("量不了第 \(number) 或第 \(like) 镜"))
            }
            film.shots[index].grade = Self.grade(from: mine, to: theirs)
        } else if exposure != nil || saturation != nil {
            film.shots[index].grade = Grade(exposure: min(max(exposure ?? 0, -1.5), 1.5), saturation: min(max(saturation ?? 1, 0.5), 1.5))
        } else {
            return .failure(.message("给 like（照哪个镜头调）、exposure / saturation，或者 off"))
        }
        save(film)
        let grade = film.shots[index].grade!
        switch recut(film: film.id) {
        case .success:
            return .success(grade.neutral ? "第 \(number) 镜不调色了，剪辑时也不会再自动调；在重新剪"
                            : "第 \(number) 镜：\(String(format: "%+.2f", grade.exposure)) EV、饱和 ×\(String(format: "%.2f", grade.saturation))，在重新剪（一分钟左右）")
        case .failure(let failure): return .failure(failure)
        }
    }

    /// How to take a film from its first cut to one worth showing — for the
    /// agent, which reads it once before judging or fixing a film.
    static let guide = """
        导演手册 —— 从第一版到能给人看的那一版

        一、拍之前
        - 故事片用 film_make，engine: h3（人物前后一致）。H3 片默认钉帧：有人的镜头先用定妆照和布景合成第一帧、数过，再钉在开头拍；没人的镜头从布景拍；没人又要数的镜头开头、中间、结尾都钉同一张，场景定住、只有光和雾在动。第一帧在 film_frames(picture: true) 里能看到。故事里要"数"的东西（五个饼、两条鱼、十二个篮子），写进那个镜头的 counts：[{"thing": "round flat barley loaves", "count": 5}]。布景画好后会先数一遍，不对就改图，再拍。
        - 也可以在拍之前先看布景：film_frames(picture: true)，数：film_count(picture: true)。布景对了，H3 才会对；H3 只守得住布景里有的东西。

        二、拍完，自己看，一个镜头一个镜头地看
        - film_frames(shot) 每秒一帧拼成一张图给你看。对照故事和原文看：人对不对、东西对不对、前后镜头是不是同一样东西（同一个篮子、同样的饼）、有没有现代的东西和文字、亮度是不是突然跳一下。
        - 要比两个镜头里的东西是不是一样，用 like：film_frames(shot: 7, like: [4])。
        - 数量别凭小图数：film_count(shot, thing, expected) 一帧一帧放大数（每个东西框一次再数框）。多出来的才是真问题（H3 会"长"东西），两帧以上多了就该修；少了多半是被手挡住、叠在一起或刚入画，先看画面再下结论。
        - 评审模型打 10 分不代表对（五饼二鱼里多出来的饼和篮子都拿过 10 分）。说片子好之前，每个镜头都要自己看过。

        三、哪里不对，怎么修
        1. 数目不对（饼、篮子）→ 直接 film_reshoot(shot, counts: [{"thing": "small round barley loaves", "count": 5}])。counts 只给故事定死了数目、整个镜头里都不变的东西（孩子篮子里的五个饼、最后那十二个篮子）；掰饼、分饼的镜头里饼的数目一直在变，别给 counts，不然片场会把布景改成"正好五个"。片场自己会：先数布景，不对就改图，改不对就重画三张挑对的；再拍；拍完一帧一帧数，多了自动重拍一次；镜头里没人、还是不对，就改成在数过的布景上运镜。你不用自己一遍遍改布景 —— 等它拍完（film_status wait），用 film_frames 看、film_count 数，核对结果。
           只有它说布景改不对时，才自己改：film_fix_picture(from: "set", counts: …) 改完会自己数一遍告诉你。差一两个就说具体删哪个、加在哪（"去掉后排最左边那个篮子，别的都不动"）；差得多就 from: "new" 带上整张布景的完整描述重画（画三张、留数目对的）。布景数对了就别再动它：重画会换掉东西的样子（金黄的饼变成白的薄饼），前后镜头就对不上了；重画时把别的镜头里它的样子写进描述。
        2. 第一帧就不对（人站错、东西不对）→ film_fix_picture(from: "start", instruction: "…") 改第一帧 → film_frames(picture: true) 看 → film_reshoot(shot) 从改好的第一帧重拍。改布景或画面描述时第一帧会自动重做。
        3. 人对、东西的样子和别的镜头不一样（第 7 镜的饼和第 4 镜的不一样）→ H3 给了参考图也守不住东西。直接 film_reshoot(shot: 7, match: {"thing": "bread", "like": 4}, motion: "他掰开饼放进篮子……")：片场会从这一镜开头取一帧，先让看图的模型描述第 4 镜里饼的样子，照着把这一帧里的饼改成一样的，再用 LTX 从这一帧拍（约 5 分钟）。画里是什么，拍出来就是什么。拍完 film_frames(shot: 7, like: [4]) 并排对比。
           要自己动手也行：film_fix_picture(from: "take", at: 0.2, like: [4], instruction: "…") → film_frames(picture: true) 看 → film_reshoot(shot: 7, method: "animate")。描述要照参照镜头里它真实的样子写：写错了（"深色、有裂纹"）会改成错的样子。
        4. 数目必须一直对、镜头里没人，钉帧还守不住 → film_reshoot(shot, method: "move", glide: "pull_out") 在数过的布景上运镜：不用视频模型，东西不会多也不会少，但画面是死的，只当最后一招。
        5. 某一镜太亮、太暗、颜色不一样 → film_grade() 先量每一镜，再 film_grade(shot, like: 旁边的镜头)。比前后两镜都亮（或暗）一截的镜头，剪辑时会自动拉回来。
        6. 旁白、配乐 → film_rescore；只重剪 → film_recut。每次剪完都会自动做母带，响度 -16 LUFS。
        要重拍好几个镜头：前面的都加 later: true，最后一个不加（或者最后调一次 film_reshoot 不带 shot），一次拍完——H3 的先拍，其余的后拍，只要等一轮。

        四、每修一处都要再看
        - 重拍完 film_frames 看新的这一镜，要数的再 film_count 一遍。别说"修好了"，除非你看过、数过。
        - 改图、重拍都在后台跑，film_status 看进度和结果；一次只能做一件事，别重复发起。
        - 换下来的镜头和图都留在片子文件夹里（shot-NN.take-*），没有删。
        """
}
