import SwiftUI
import WebKit

/// The companion with a body: the VRM stage in a web view, transparent, with
/// the panel's own background behind her.
///
/// Why a web view again rather than SceneKit or RealityKit: the characters and
/// their clothes come from VRoid Hub as VRM files, and the renderer that reads
/// VRM — spring bones for hair, MToon for the toon shading, the standard
/// expressions — is `@pixiv/three-vrm`. Writing a second one in Swift would
/// mean re-deriving somebody's hair physics to save a WebGL context. The app
/// already runs a web view for the digital human; this is the same bargain.
///
/// Driving it is four calls: `load`, `expression`, `mouth`, `talking`. The
/// mouth is deliberately not lip-synced from the audio here — the voice's own
/// level opens it, because that pipeline (sentence streaming, barge-in, trimmed
/// silence) lives on the Swift side and pushing the bytes into JavaScript to
/// re-analyse them would be two implementations of one thing.
struct VRMStageView: NSViewRepresentable {
    /// Base URL of the local stage server, e.g. http://127.0.0.1:52341/
    let base: URL
    let onReady: (VRMWebView) -> Void

    func makeNSView(context: Context) -> VRMWebView {
        let v = VRMWebView()
        v.load(base)
        onReady(v)
        return v
    }

    func updateNSView(_ v: VRMWebView, context: Context) {
        if v.loadedBase != base { v.load(base) }
    }
}

/// The stage's web view, a class so the panel can talk to it from outside
/// SwiftUI's update cycle — a mood arriving mid-reply, a level 30 times a
/// second — without rebuilding anything.
final class VRMWebView: NSView, WKNavigationDelegate {

    private(set) var loadedBase: URL?
    private(set) var wearing: String?
    private var web: WKWebView!
    private var ready = false
    /// What was asked for before the page finished loading. A mood can arrive
    /// in the second the view appears, and a companion who blinks in wearing
    /// nothing because the load had not finished is worse than one who waits.
    private var pendingModel: String?
    private var pendingExpression: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: bounds, configuration: cfg)
        web.navigationDelegate = self
        web.autoresizingMask = [.width, .height]
        // The canvas is transparent and so is this: the companion's background
        // is the panel's, and a white page behind her would be a white box.
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        addSubview(web)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unused") }

    func load(_ base: URL) {
        loadedBase = base
        ready = false
        loadCount += 1
        // Whatever she had on goes back on when the new page is up.
        if pendingModel == nil { pendingModel = wearing }
        web.load(URLRequest(url: base.appendingPathComponent("stage.html")))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        awaitStage(attempt: 0, of: loadCount)
    }

    /// Bumped by every `load`, so a poll started for one page does not
    /// declare the next one ready.
    private var loadCount = 0

    /// The page is ready when `window.kin` exists, not when the navigation
    /// finishes. The stage is an ES module with a megabyte of imports, and
    /// `didFinish` can arrive before it has run to the line that publishes
    /// `kin` — at which point every call here, guarded with `window.kin &&`,
    /// does nothing and says nothing. She was "wearing Vivi" as far as this
    /// side knew, on a page that had never been asked to load anybody.
    private func awaitStage(attempt: Int, of load: Int) {
        guard load == loadCount else { return }
        web.evaluateJavaScript("typeof window.kin === 'object' && typeof window.kin.load === 'function'") { [weak self] result, _ in
            guard let self, load == self.loadCount else { return }
            if (result as? Bool) == true {
                self.stageIsUp()
            } else if attempt < 100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.awaitStage(attempt: attempt + 1, of: load)
                }
            }
        }
    }

    private func stageIsUp() {
        ready = true
        if let model = pendingModel { pendingModel = nil; wear(model) }
        if let expression = pendingExpression { pendingExpression = nil; express(expression) }
        // A fresh page has studio lights and a full-length frame; where she
        // is standing is the panel's knowledge, so it is said again.
        if let placement { run(placement) }
    }

    /// What this side believes, for the diagnostics tool.
    var bridgeState: String {
        "页面加载完=\(ready)｜等着穿=\(pendingModel ?? "无")｜已穿=\(wearing ?? "无")｜站位=\(placement == nil ? "无" : "有")"
    }

    /// The last framing-and-light instruction, kept so a reloaded page gets it.
    private var placement: String?

    /// Stand her in a place or take her out of one.
    ///
    /// With a wide plate the page draws the place itself and she can walk
    /// around in it; with only a tone she stands waist up in front of
    /// whatever the panel is showing, lit like it; with neither she is back
    /// on the bare stage.
    func place(_ tone: PlateTone?, wide: String? = nil, far: Double = 6.5) {
        let light = tone.map {
            String(format: "{r:%.3f,g:%.3f,b:%.3f,level:%.3f,side:%.3f}", $0.r, $0.g, $0.b, $0.level, $0.side)
        } ?? "null"
        let js: String
        if let wide {
            let path = wide.replacingOccurrences(of: "'", with: "%27")
            js = "window.kin && window.kin.place({plate:'\(path)',horizon:0.5,far:\(far),tone:\(light)})"
        } else if tone != nil {
            js = "window.kin && (window.kin.place(null), window.kin.framing('portrait'), window.kin.light(\(light)))"
        } else {
            js = "window.kin && (window.kin.place(null), window.kin.framing('full'), window.kin.light(null))"
        }
        placement = js
        if ready { run(js) }
    }

    /// Somebody wants her (she walks up to the lens) or nobody does (she is
    /// free to wander off into the place).
    func attend(_ on: Bool) {
        guard ready else { return }
        run("window.kin && window.kin.attend(\(on))")
    }

    func walk(depth: Double, across: Double) {
        guard ready else { return }
        run("window.kin && window.kin.walk(\(depth), \(across))")
    }

    func play(_ name: String) {
        guard ready else { return }
        let safe = name.filter { $0.isLetter }
        run("window.kin && window.kin.play('\(safe)')")
    }

    func hold(_ name: String?) {
        guard ready else { return }
        let safe = (name ?? "").filter { $0.isLetter }
        run("window.kin && window.kin.hold(\(safe.isEmpty ? "null" : "'\(safe)'"))")
    }

    func sit(_ how: String?) {
        guard ready else { return }
        let safe = (how ?? "").filter { $0.isLetter }
        run("window.kin && window.kin.sit(\(safe.isEmpty ? "null" : "'\(safe)'"))")
    }

    /// Play a motion written in the pose language, and hand back what the
    /// stage made of it: how long it runs, which sliders it used, and which
    /// words it did not know.
    func compose(json: String, done: @escaping ([String: Any]) -> Void) {
        guard ready else { return done(["ok": false, "error": "3D 形象还没准备好"]) }
        web.evaluateJavaScript("JSON.stringify(window.kin ? window.kin.compose(\(json)) : {ok:false,error:'no stage'})") { result, _ in
            let text = (result as? String) ?? "{}"
            done(((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]) ?? [:])
        }
    }

    // MARK: Driving her

    /// Put on a model by file name — it is served from the wardrobe folder
    /// under `models/` — and, if she has a repainted outfit remembered for
    /// that model, that too, as soon as the model is in.
    func wear(_ file: String) {
        guard ready else { pendingModel = file; return }
        wearing = file
        let escaped = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        let paints = VRMOutfits.remembered(for: file).map { VRMOutfits.paintsJSON(model: file, outfit: $0) } ?? "null"
        run("window.kin && window.kin.load('models/\(escaped)').then(() => window.kin.dress(\(paints)))")
    }

    /// Her clothing textures, as PNGs no larger than `max` on a side.
    func textures(max: Int = 1024, done: @escaping ([(name: String, png: Data)]) -> Void) {
        guard ready else { return done([]) }
        let js = "JSON.stringify((window.kin ? window.kin.wardrobe() : []).map(c => ({name: c.name, png: window.kin.texture(c.name, \(max))})))"
        web.evaluateJavaScript(js) { result, _ in
            let list = (try? JSONSerialization.jsonObject(with: Data(((result as? String) ?? "[]").utf8))) as? [[String: Any]] ?? []
            done(list.compactMap { item in
                guard let name = item["name"] as? String, let url = item["png"] as? String,
                      let comma = url.firstIndex(of: ","),
                      let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
                return (name, data)
            })
        }
    }

    /// Whether a repaint kept the atlas's layout (see `kin.fits`).
    func fits(material: String, url: String, done: @escaping (Bool, Double) -> Void) {
        guard ready else { return done(false, -1) }
        let js = "window.kin.fits(\(Self.quoted(material)), \(Self.quoted(url))).then(r => JSON.stringify(r))"
        web.callAsyncJavaScript("return await " + js, arguments: [:], in: nil, in: .page) { result in
            let text = (try? result.get() as? String) ?? "{}"
            let verdict = (try? JSONSerialization.jsonObject(with: Data((text ?? "{}").utf8))) as? [String: Any]
            done((verdict?["ok"] as? Bool) ?? false, (verdict?["spread"] as? Double) ?? -1)
        }
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }

    /// The original texture of one piece recoloured (see `kin.tinted`), as PNG data.
    func tinted(material: String, rgb: [Int], done: @escaping (Data?) -> Void) {
        guard ready else { return done(nil) }
        let js = "window.kin.tinted(\(Self.quoted(material)), [\(rgb.map(String.init).joined(separator: ","))])"
        web.evaluateJavaScript(js) { result, _ in
            guard let url = result as? String, let comma = url.firstIndex(of: ",") else { return done(nil) }
            done(Data(base64Encoded: String(url[url.index(after: comma)...])))
        }
    }

    /// Put a repainted outfit on, or (nil) take it off.
    func dress(paintsJSON: String?) {
        guard ready else { return }
        run(paintsJSON.map { "window.kin && window.kin.dress(\($0))" } ?? "window.kin && window.kin.undress()")
    }

    /// How she feels — happy, gentle, curious, sleepy, worried, or "" for
    /// nothing in particular. The stage turns it into a face, a way of
    /// standing and the things that mood makes her do.
    func express(_ name: String) {
        guard ready else { pendingExpression = name; return }
        let safe = name.filter { $0.isLetter }
        run("window.kin && window.kin.mood('\(safe)')")
    }

    /// 0…1. Sent while a reply is being spoken; the page decays it on its own.
    func mouth(_ level: Double) {
        guard ready else { return }
        run("window.kin && window.kin.mouth(\(String(format: "%.3f", max(0, min(1, level)))))")
    }

    /// Play a motion: a `.vrma` file name from the motions folder, or
    /// "dance" for the built-in one, or "" to stop.
    func motion(_ name: String, loops: Int = 1) {
        guard ready else { return }
        let safe = name.replacingOccurrences(of: "'", with: "")
        run("window.kin && window.kin.motion('\(safe)',\(loops))")
    }

    /// Where to look, in -1…1 with the origin between her eyes. The page has
    /// its own `mousemove` listener, but a figure on the desktop never
    /// receives one — the window has to swallow the mouse so it can be
    /// dragged — so the pointer is followed from outside instead.
    func look(x: Double, y: Double) {
        guard ready else { return }
        run(String(format: "window.kin && window.kin.look(%.3f,%.3f)",
                   max(-1, min(1, x)), max(-1, min(1, y))))
    }

    /// One of the five VRM mouth shapes, from the track read off the audio.
    func viseme(_ name: String, _ weight: Double) {
        guard ready else { return }
        run("window.kin && window.kin.viseme('\(name)',\(String(format: "%.3f", max(0, min(1, weight)))))")
    }

    func talking(_ on: Bool) {
        guard ready else { return }
        run("window.kin && window.kin.talking(\(on))")
    }

    /// What the stage says about itself — a model loaded, or why it did not.
    /// The panel shows the error; the tests read the whole thing.
    func status(_ done: @escaping ([String: Any]) -> Void) {
        guard ready else { done(["ready": false, "error": "页面还没加载完"]); return }
        web.evaluateJavaScript("JSON.stringify(window.kin ? window.kin.status() : {})") { result, _ in
            let text = (result as? String) ?? "{}"
            let parsed = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
            done(parsed ?? [:])
        }
    }

    private func run(_ js: String) {
        web.evaluateJavaScript(js, completionHandler: nil)
    }
}

/// The stage, held outside the view tree.
///
/// Companion mode comes and goes — ⇧⌘M, the menubar, a mode switch — and a
/// character who reloads on every visit is a character who pops in a second
/// late, wearing the default, having forgotten where she was looking. One web
/// view, kept here, for as long as the app runs.
@MainActor
final class VRMStage: ObservableObject {
    static let shared = VRMStage()

    @Published private(set) var note: String?
    private(set) weak var web: VRMWebView?

    func attach(_ view: VRMWebView) {
        web = view
        if let outfit = VRMWardrobe.chosen { view.wear(outfit.id) }
        // A new web view — the panel's, after she was on the desktop — knows
        // nothing about the place she was in.
        if let roomy { view.place(roomy.tone, wide: roomy.path, far: roomy.far) }
        else { view.place(placedIn.flatMap(PlateTone.init(measuring:))) }
    }

    /// The plate she is standing in front of, so the same one is not
    /// measured again on every state change.
    private var placedIn: URL?

    /// Stand her in a place, or — with nil — back on the bare stage. The
    /// plate is a photograph of the place with nobody in it; she is framed
    /// the way it was and lit the way it is.
    func place(plate: URL?) {
        guard plate != placedIn || plate == nil else { return }
        placedIn = plate
        roomy = nil
        web?.place(plate.flatMap(PlateTone.init(measuring:)))
    }

    /// The wide plate she is walking around in, if she is in one.
    private var roomy: (path: String, far: Double, tone: PlateTone?)?

    /// Stand her in one of her places. With a wide plate she gets the whole
    /// place to walk in; with only the close one she stands in front of it.
    func place(in scene: CompanionArt.Scene?) {
        guard let scene, let wide = scene.wide else { return place(plate: scene?.plate) }
        guard wide != placedIn else { return }
        placedIn = wide
        let path = VRMWardrobe.stagePath(scene: scene.name, file: wide.lastPathComponent)
        roomy = (path, scene.isOutdoors ? 10.5 : 6.5, PlateTone(measuring: wide))
        web?.place(roomy?.tone, wide: path, far: roomy?.far ?? 6.5)
    }

    /// True when she has a place to walk around in.
    var canWalk: Bool { roomy != nil }

    func attend(_ on: Bool) { web?.attend(on) }

    /// "过来" / "走远点" / "去左边": a walk by name rather than by number,
    /// which is how anybody asks for one.
    func walk(_ where_: String) -> String {
        guard web != nil else { return "3D 形象没开" }
        guard canWalk else { return "这个地方还没有能走的远景，等它拍好（十几秒）" }
        let spots: [String: (Double, Double)] = [
            "come": (0, 0), "near": (4.3, 0), "far": (9, 0),
            "left": (5, -0.8), "right": (5, 0.8), "around": (6, 0.5),
        ]
        guard let (depth, across) = spots[where_] else {
            return "能去的地方：" + spots.keys.sorted().joined(separator: "、")
        }
        web?.walk(depth: depth, across: across)
        return where_ == "come" ? "她走过来了" : "她走过去了"
    }

    /// The outfit being painted, if one is.
    @Published private(set) var painting: String?

    /// Repaint what she is wearing from a description, and put it on.
    ///
    /// A VRM's clothes are a mesh and a painted texture. The mesh is what it
    /// is; the paint goes to the edit model as a flat atlas with the
    /// instruction to change colour, fabric and pattern and leave every shape
    /// where it is — which it does, so the result maps straight back onto
    /// her. About half a minute, in the background: the answer comes back at
    /// once and she changes when it lands.
    func repaint(_ instruction: String, shoes: String = "", name raw: String) -> (String, Bool) {
        guard let web, let model = web.wearing else { return ("3D 形象没开", true) }
        guard painting == nil else { return ("还在换「\(painting!)」，等她换好", true) }
        let words = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return ("换成什么样？repaint 是空的", true) }
        let name = Self.motionName(raw.isEmpty ? String(words.prefix(24)) : raw)
        guard !name.isEmpty, name != "original" else { return ("给这身起个名字（name）", true) }
        painting = name
        note = "在换「\(name)」…（半分钟上下）"
        Task { @MainActor in
            defer { painting = nil }
            let textures = await withCheckedContinuation { continuation in
                web.textures { continuation.resume(returning: $0) }
            }
            guard !textures.isEmpty else { note = "这个模型上没找到能重画的衣服"; return }
            let folder = VRMOutfits.folder(model: model, outfit: name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? words.write(to: folder.appendingPathComponent("about.txt"), atomically: true, encoding: .utf8)
                var kept: [String] = [], refused: [String] = []
                for (material, png) in textures {
                    // Each atlas only hears about itself. Told about boots
                    // while it was looking at a dress, the model painted boots
                    // into the dress.
                    let isShoes = material.lowercased().contains("shoe")
                    let wanted = isShoes ? shoes.trimmingCharacters(in: .whitespacesAndNewlines) : words
                    guard !wanted.isEmpty else { continue }
                    let source = folder.appendingPathComponent("\(material).src.png")
                    try png.write(to: source, options: .atomic)
                    let painted = folder.appendingPathComponent("\(material).png")
                    // An earlier painting under this outfit's name is set aside
                    // first: if this one is refused she must not be left in the
                    // old one, which may be the very thing being redone.
                    if FileManager.default.fileExists(atPath: painted.path) {
                        let aside = folder.appendingPathComponent("\(material).previous-\(Int(Date().timeIntervalSince1970)).png")
                        try? FileManager.default.moveItem(at: painted, to: aside)
                    }
                    var accepted = false
                    for attempt in 0..<2 where !accepted {
                        let made = try await DiffuserClient.shared.edit(
                            prompt: "this is a flat UV texture atlas of \(isShoes ? "a pair of shoes" : "a garment") for a 3D "
                                  + "character: unfolded pieces laid out on an empty background. recolour and repaint "
                                  + "the existing pieces as: \(wanted). keep every piece, outline and position exactly "
                                  + "where it is, and keep the empty background empty — do not draw, add or move "
                                  + "anything, only change colours, fabric and pattern inside the existing pieces. "
                                  + "pieces that come in pairs must be painted identically",
                            from: source, into: folder,
                            seed: CompanionCharacter.seed(for: name + material) + attempt * 7919)
                        let url = "models/" + ("outfits/\((model as NSString).deletingPathExtension)/\(name)/\(made.lastPathComponent)"
                            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
                        let (fits, spread) = await withCheckedContinuation { continuation in
                            web.fits(material: material, url: url) { continuation.resume(returning: ($0, $1)) }
                        }
                        if fits {
                            if FileManager.default.fileExists(atPath: painted.path) {
                                _ = try? FileManager.default.replaceItemAt(painted, withItemAt: made)
                            } else {
                                try FileManager.default.moveItem(at: made, to: painted)
                            }
                            accepted = true
                        } else {
                            // Kept beside the others under a name that says what
                            // it is, for whoever wants to see what went wrong.
                            let aside = folder.appendingPathComponent("\(material).refused-\(attempt).png")
                            try? FileManager.default.moveItem(at: made, to: aside)
                            note = "「\(material)」画走样了（空白处的杂色 \(spread)），再来一次…"
                        }
                    }
                    // What could not be repainted can still be recoloured: the
                    // original's own shading in the colour the words name.
                    if !accepted, let rgb = VRMOutfits.colour(in: wanted) {
                        let data = await withCheckedContinuation { continuation in
                            web.tinted(material: material, rgb: rgb) { continuation.resume(returning: $0) }
                        }
                        if let data, (try? data.write(to: painted, options: .atomic)) != nil { accepted = true }
                    }
                    if accepted { kept.append(material) } else { refused.append(material) }
                }
                guard !kept.isEmpty else {
                    note = "没换成「\(name)」：画出来的贴图都走了样，她还穿着原来的"
                    return
                }
                VRMOutfits.remember(name, for: model)
                web.dress(paintsJSON: VRMOutfits.paintsJSON(model: model, outfit: name))
                note = refused.isEmpty ? "换上「\(name)」了"
                                       : "换上「\(name)」了（\(refused.count) 件画走了样，保持原样）"
            } catch {
                note = "没换成「\(name)」：\(error.localizedDescription)"
            }
        }
        return ("在换了：「\(name)」，半分钟左右她就穿上。以后 outfit: \"\(name)\" 直接换回这身", false)
    }

    /// Put on an outfit she already has, or "original" for what she came in.
    func dress(in wanted: String) -> String? {
        guard let web, let model = web.wearing else { return nil }
        let name = wanted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["original", "原来", "原装", "原来的", "default"].contains(name) {
            VRMOutfits.remember(nil, for: model)
            web.dress(paintsJSON: nil)
            return "换回原来那身了"
        }
        guard let outfit = VRMOutfits.names(for: model).first(where: { $0 == name || $0.contains(name) }) else { return nil }
        VRMOutfits.remember(outfit, for: model)
        web.dress(paintsJSON: VRMOutfits.paintsJSON(model: model, outfit: outfit))
        return "换上「\(outfit)」了"
    }

    static let props = ["mug", "book", "phone", "umbrella", "flower"]

    /// Put something in her hand, or ("none") take it away.
    func hold(_ what: String) -> String {
        guard web != nil else { return "3D 形象没开" }
        let name = what.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["none", "nothing", "", "放下"].contains(name) { web?.hold(nil); return "放下了" }
        guard Self.props.contains(name) else { return "她能拿的：" + Self.props.joined(separator: "、") + "；none 是放下" }
        web?.hold(name)
        return "拿着「\(name)」了"
    }

    /// Sit on a stool, kneel on the floor, or stand up.
    func sit(_ how: String) -> String {
        guard web != nil else { return "3D 形象没开" }
        switch how.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "stool", "chair", "sit", "坐": web?.sit("stool"); return "她坐下了"
        case "floor", "kneel", "跪坐", "地上": web?.sit("floor"); return "她在地上跪坐下了"
        case "stand", "up", "none", "起来", "站": web?.sit(nil); return "她站起来了"
        default: return "sit 填 stool（坐凳子）、floor（跪坐）或 stand（站起来）"
        }
    }

    static let plays = ["wave", "stretch", "spin", "jump", "pick", "look", "dance"]

    /// Motions she has made up and kept, by name — JSON in the pose language,
    /// beside the .vrma files.
    nonisolated static var composedNames: [String] {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kinclaw/vrm/motions")
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    nonisolated private static func composedFile(_ name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/vrm/motions/\(name).json")
    }

    /// A name that is safe as a file name and the same however it was typed.
    nonisolated static func motionName(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(String(cleaned).split(separator: "-").joined(separator: "-").prefix(40))
    }

    func play(_ name: String) async -> String {
        guard web != nil else { return "3D 形象没开" }
        if Self.plays.contains(name) { web?.play(name); return "好" }
        let kept = Self.motionName(name)
        if let data = try? Data(contentsOf: Self.composedFile(kept)), let json = String(data: data, encoding: .utf8) {
            let result = await composeOnStage(json)
            return (result["ok"] as? Bool) == true ? "好" : "放不了「\(kept)」：\(result["error"] as? String ?? "未知")"
        }
        let all = Self.plays + Self.composedNames
        return "没有「\(name)」。她会的：" + all.joined(separator: "、") + "。没有的可以用 compose 现编一个"
    }

    private func composeOnStage(_ json: String) async -> [String: Any] {
        guard let web else { return ["ok": false, "error": "3D 形象没开"] }
        return await withCheckedContinuation { continuation in
            web.compose(json: json) { continuation.resume(returning: $0) }
        }
    }

    /// Make a motion up, play it, and keep it under its name.
    ///
    /// Kept only if the stage accepted it, and whatever it said about words
    /// it did not recognise goes back to the writer — a language model, which
    /// will use the right word next time if told which one was wrong.
    func compose(name raw: String, frames: [[String: Any]], loops: Int) async -> (String, Bool) {
        guard web != nil else { return ("3D 形象没开", true) }
        let name = Self.motionName(raw)
        guard !name.isEmpty else { return ("给这个动作起个名字（name），以后好再做", true) }
        guard !Self.plays.contains(name) else { return ("「\(name)」是她本来就会的，换个名字", true) }
        let spec: [String: Any] = ["name": name, "loops": loops, "frames": frames]
        guard JSONSerialization.isValidJSONObject(spec),
              let data = try? JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return ("frames 不是合法的 JSON", true) }
        let result = await composeOnStage(json)
        guard (result["ok"] as? Bool) == true else {
            return ("没做成：\(result["error"] as? String ?? "未知")", true)
        }
        let file = Self.composedFile(name)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        var answer = "她做了「\(name)」（\(result["seconds"] ?? "?") 秒），记下了，以后 play: \"\(name)\" 就能再做"
        if let ignored = result["ignored"] as? [String], !ignored.isEmpty {
            answer += "。不认识的词被忽略了：" + ignored.joined(separator: "、")
        }
        return (answer, false)
    }

    /// Change clothes: remember the choice, and put it on if she is on screen.
    func wear(_ outfit: VRMWardrobe.Outfit) {
        VRMWardrobe.wear(outfit)
        web?.wear(outfit.id)
        note = nil
    }

    /// What the mood tag means on a face that has the five VRM expressions.
    func express(_ mood: CompanionMood?) {
        web?.express(mood?.rawValue ?? "")
    }

    /// Dance, or play one of the motion files. Answers with what it did, for
    /// a tool that has to say something.
    func move(_ name: String, loops: Int = 1) -> String {
        guard web != nil else { return "3D 形象没开" }
        web?.motion(name, loops: loops)
        if name.isEmpty { return "停了" }
        return name == "dance" ? "她跳起来了" : "在放「\(name)」"
    }

    /// Every motion file on disk, for the picker and the tools.
    nonisolated static var motions: [String] {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/vrm/motions")
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".vrma") }.sorted()
    }

    /// Follow the pointer. Called from the desktop overlay's global monitor.
    func look(x: Double, y: Double) { web?.look(x: x, y: y) }

    func voice(level: Double, speaking: Bool) {
        web?.talking(speaking)
        // The track wins while it is playing; the level is the fallback.
        if speaking, ticker == nil { web?.mouth(level) }
    }

    // MARK: - Lip sync

    private var ticker: Timer?
    private var trackStarted = Date()
    private var track: VisemeTrack?

    /// A clip is about to be heard: read its mouth shapes and play them
    /// alongside it.
    ///
    /// Alongside rather than from the player's clock, because the clip is
    /// handed over as it starts and a 20ms grid does not need sample-accurate
    /// alignment — what matters is that the shape changes when the sound
    /// does, which a wall clock started at the same moment gives.
    func speak(_ wav: Data) {
        guard let built = VisemeTrack(wav: wav) else { return }
        track = built
        trackStarted = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: VisemeTrack.hop, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    /// Stop feeding shapes — the page decays what is left, so a mouth caught
    /// mid-vowel closes rather than sticking.
    func stopSpeaking() {
        ticker?.invalidate()
        ticker = nil
        track = nil
        web?.viseme("", 0)
    }

    private func step() {
        guard let track else { return }
        let elapsed = Date().timeIntervalSince(trackStarted)
        guard let frame = track.frame(at: elapsed) else {
            // Past the end of this clip: the next one will restart the ticker.
            stopSpeaking()
            return
        }
        web?.viseme(frame.viseme, frame.weight)
    }

    /// What the stage says about itself, awaited.
    ///
    /// The panel's note is a one-line summary for a person; this is the whole
    /// dictionary for whoever is debugging why nobody is on screen — model,
    /// error, expression count, and the canvas size, which is the one that
    /// catches a view that was never given any room.
    func snapshot() async -> [String: Any] {
        guard let web else { return ["ready": false, "error": "3D 形象没开"] }
        var status = await withCheckedContinuation { continuation in
            web.status { continuation.resume(returning: $0) }
        }
        // This side of the bridge too. "The page is up and nobody asked it to
        // load her" looks, from the page alone, exactly like a slow load.
        status["bridge"] = web.bridgeState
        return status
    }

    /// Ask the stage how it is doing, for the panel's note and for tests.
    func refreshNote() {
        guard let web else { note = nil; return }
        web.status { [weak self] status in
            Task { @MainActor in
                let error = (status["error"] as? String) ?? ""
                self?.note = error.isEmpty ? nil : error
            }
        }
    }
}

extension CompanionMood {
    /// The VRM standard expressions are happy, angry, sad, relaxed and
    /// surprised — five, like the moods, but not the same five: there is no
    /// "curious" on a VRM face, and "sleepy" is a relaxed one with the eyes
    /// half closed, which is the blink the stage already owns.
    var vrmExpression: String {
        switch self {
        case .happy:   return "happy"
        case .gentle:  return "relaxed"
        case .curious: return "surprised"
        case .sleepy:  return "relaxed"
        case .worried: return "sad"
        }
    }
}


/// How a place is lit, read off its plate: the average colour, how bright it
/// is, and which side the light comes from.
///
/// A character rendered under white studio lights and laid over a sunset is
/// a sticker. The same character tinted orange, dimmed a little and lit from
/// the side the sun is on is standing on the beach — and all of that is in
/// the picture already, a few dozen pixels' worth.
struct PlateTone {
    let r, g, b: Double
    /// Perceived brightness of the whole plate, 0…1.
    let level: Double
    /// −1 light from the left … 1 from the right.
    let side: Double

    init?(measuring url: URL) {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Eight columns by four rows is plenty: this is asking where the
        // window is, not what is on the counter.
        let w = 8, h = 4
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = (r: 0.0, g: 0.0, b: 0.0), left = 0.0, right = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let (r, g, b) = (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
                sum.r += r; sum.g += g; sum.b += b
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if x < w / 2 { left += luma } else { right += luma }
            }
        }
        let n = Double(w * h)
        self.r = sum.r / n; self.g = sum.g / n; self.b = sum.b / n
        self.level = 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b
        // A window on one side is a difference of a fifth or so between the
        // halves; tripled, that swings the key light most of the way over.
        let total = max(left + right, 0.001)
        self.side = max(-1, min(1, (right - left) / total * 3))
    }
}


/// Repainted outfits, on disk: `~/.kinclaw/avatars/outfits/<model>/<outfit>/`
/// holds one PNG per clothing material and the words it was painted from.
/// Under the avatars folder because that is what the stage serves as
/// `models/`, so a texture is a URL away.
enum VRMOutfits {
    private static func stem(_ model: String) -> String { (model as NSString).deletingPathExtension }

    static func folder(model: String, outfit: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/avatars/outfits/\(stem(model))/\(outfit)")
    }

    static func names(for model: String) -> [String] {
        let root = folder(model: model, outfit: "").deletingLastPathComponent()
            .appendingPathComponent(stem(model))
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
    }

    /// `{ "<material>": "models/outfits/<model>/<outfit>/<material>.png" }` for the stage.
    static func paintsJSON(model: String, outfit: String) -> String {
        let dir = folder(model: model, outfit: outfit)
        // `<material>.png` and nothing else: sources, refusals and earlier
        // paintings live beside them under longer names.
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".png") && !$0.dropLast(4).contains(".") }
        var map: [String: String] = [:]
        for file in files {
            let path = "outfits/\(stem(model))/\(outfit)/\(file)"
            map[String(file.dropLast(4))] = "models/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
        }
        let data = (try? JSONSerialization.data(withJSONObject: map)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// The first colour a description names, as RGB — for recolouring what
    /// cannot be repainted.
    static func colour(in words: String) -> [Int]? {
        let table: [(String, [Int])] = [
            ("black", [28, 28, 32]), ("white", [238, 236, 232]), ("ivory", [236, 228, 208]), ("cream", [236, 226, 200]),
            ("grey", [128, 130, 136]), ("gray", [128, 130, 136]), ("silver", [176, 180, 188]),
            ("dark brown", [74, 48, 32]), ("brown", [112, 72, 44]), ("tan", [176, 132, 88]), ("beige", [208, 188, 156]),
            ("burgundy", [110, 22, 40]), ("wine", [110, 22, 40]), ("crimson", [170, 24, 44]), ("red", [186, 32, 40]),
            ("pink", [236, 150, 176]), ("orange", [226, 124, 44]), ("gold", [212, 170, 72]), ("yellow", [232, 204, 72]),
            ("olive", [108, 112, 56]), ("green", [64, 132, 80]), ("teal", [40, 128, 128]), ("navy", [30, 42, 86]),
            ("sky blue", [120, 176, 226]), ("blue", [52, 96, 176]), ("purple", [112, 64, 160]), ("violet", [128, 84, 180]),
        ]
        let text = words.lowercased()
        return table.filter { text.contains($0.0) }
            .min { text.range(of: $0.0)!.lowerBound < text.range(of: $1.0)!.lowerBound }?.1
    }

    private static func key(_ model: String) -> String { "kinclaw.companion.vrm.outfit." + stem(model) }

    static func remembered(for model: String) -> String? {
        guard let name = UserDefaults.standard.string(forKey: key(model)), !name.isEmpty,
              FileManager.default.fileExists(atPath: folder(model: model, outfit: name).path) else { return nil }
        return name
    }

    static func remember(_ outfit: String?, for model: String) {
        UserDefaults.standard.set(outfit ?? "", forKey: key(model))
    }
}
