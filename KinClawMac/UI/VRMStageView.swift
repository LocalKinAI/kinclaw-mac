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
        web.load(URLRequest(url: base.appendingPathComponent("stage.html")))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        if let model = pendingModel { pendingModel = nil; wear(model) }
        if let expression = pendingExpression { pendingExpression = nil; express(expression) }
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

    func voice(level: Double, speaking: Bool) {
        web?.talking(speaking)
        if speaking { web?.mouth(level) }
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
