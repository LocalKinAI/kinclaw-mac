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

    // MARK: Driving her

    /// Put on a model by file name — it is served from the wardrobe folder
    /// under `models/`.
    func wear(_ file: String) {
        guard ready else { pendingModel = file; return }
        wearing = file
        let escaped = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        run("window.kin && window.kin.load('models/\(escaped)')")
    }

    /// A VRM standard expression name, or "" for a neutral face.
    func express(_ name: String) {
        guard ready else { pendingExpression = name; return }
        run("window.kin && window.kin.expression('\(name)')")
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

    static let plays = ["wave", "stretch", "spin", "jump", "pick", "look", "dance"]

    func play(_ name: String) -> String {
        guard web != nil else { return "3D 形象没开" }
        guard Self.plays.contains(name) else { return "她会的：" + Self.plays.joined(separator: "、") }
        web?.play(name)
        return "好"
    }

    /// Change clothes: remember the choice, and put it on if she is on screen.
    func wear(_ outfit: VRMWardrobe.Outfit) {
        VRMWardrobe.wear(outfit)
        web?.wear(outfit.id)
        note = nil
    }

    /// What the mood tag means on a face that has the five VRM expressions.
    func express(_ mood: CompanionMood?) {
        web?.express(mood?.vrmExpression ?? "")
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
