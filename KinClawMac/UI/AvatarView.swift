import SwiftUI
import WebKit

/// The living face: a web view running the digital human, transparent
/// so the companion's own background shows through behind it.
///
/// The character is a green-screen video and the page chroma-keys it,
/// which is what makes this composable rather than a second background.
/// Their own page also stacks a city-window video behind the figure and
/// a chat bar under it — both are theirs, neither is ours, and both are
/// hidden on load.
///
/// Audio is not played here. KinClaw plays it, because everything built
/// around speech — the sentence-at-a-time streaming, barge-in, the
/// trimmed silence — lives on that side and reproducing it in
/// JavaScript would be two implementations of one thing. The web view
/// is handed the same bytes purely to drive the mouth.
struct AvatarView: NSViewRepresentable {
    /// Base URL of the local server, e.g. http://127.0.0.1:52341/
    let base: URL
    /// Set by the parent so it can push audio; called once the view exists.
    let onReady: (AvatarWebView) -> Void

    func makeNSView(context: Context) -> AvatarWebView {
        let v = AvatarWebView()
        v.load(base)
        onReady(v)
        return v
    }

    func updateNSView(_ v: AvatarWebView, context: Context) {
        if v.loadedBase != base { v.load(base) }
    }

    static func dismantleNSView(_ v: AvatarWebView, coordinator: ()) {
        v.teardown()
    }
}

/// The web view itself, kept as a class so audio can be pushed into it
/// from outside SwiftUI's update cycle.
final class AvatarWebView: NSView, WKNavigationDelegate {

    private(set) var loadedBase: URL?
    private var web: WKWebView!
    private var ready = false
    /// Clips that arrived before the page finished loading. A reply can
    /// begin in the second the view appears, and dropping its first
    /// sentence would make the mouth start late on exactly the sentence
    /// people notice.
    private var pending: [Data] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        let cfg = WKWebViewConfiguration()
        cfg.suppressesIncrementalRendering = false
        web = WKWebView(frame: bounds, configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        // Transparent, so the companion's background is the background.
        web.setValue(false, forKey: "drawsBackground")
        addSubview(web)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func load(_ base: URL) {
        loadedBase = base
        ready = false
        web.load(URLRequest(url: base.appendingPathComponent("MiniLive.html")))
    }

    func teardown() {
        web.stopLoading()
        web.loadHTMLString("", baseURL: nil)
    }

    // MARK: Speaking

    /// Hand one clip to the lip-sync. Same call their own page makes:
    /// copy the WAV into the WASM heap and let it read the mouth shapes
    /// out of the audio.
    func speak(_ wav: Data) {
        guard ready else {
            // Keep only a little: if the page is slow, the first
            // sentence is worth catching up on, the tenth is not.
            pending.append(wav)
            if pending.count > 3 { pending.removeFirst() }
            return
        }
        push(wav)
    }

    /// The reply was cut off — stop the mouth rather than letting it
    /// finish a sentence nobody is hearing.
    func stopSpeaking() {
        pending.removeAll()
        guard ready else { return }
        web.evaluateJavaScript("window.Module && window.Module._clearAudio && window.Module._clearAudio();")
    }

    private func push(_ wav: Data) {
        let b64 = wav.base64EncodedString()
        let js = """
        (function(b64){
          var M = window.Module;
          if (!M || !M._setAudioBuffer) return 'not-ready';
          var bin = atob(b64), n = bin.length, bytes = new Uint8Array(n);
          for (var i = 0; i < n; i++) bytes[i] = bin.charCodeAt(i);
          var p = M._malloc(n);
          M.HEAPU8.set(bytes, p);
          M._setAudioBuffer(p, n);
          M._free(p);
          return 'ok';
        })("\(b64)");
        """
        web.evaluateJavaScript(js)
    }

    // MARK: Load

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Their page brings its own background video and chat bar. Ours
        // is behind this view and ours is the one that follows the
        // conversation, so theirs goes.
        let tidy = """
        (function(){
          var bg = document.getElementById('background_video');
          if (bg) { try { bg.pause(); } catch(e) {} bg.style.display = 'none'; }
          var chat = document.getElementById('screen2');
          if (chat) chat.style.display = 'none';
          var msg = document.getElementById('startMessage');
          if (msg) msg.style.display = 'none';
          var spin = document.getElementById('loadingSpinner');
          if (spin) spin.style.display = 'none';
          document.body.style.background = 'transparent';
          document.documentElement.style.background = 'transparent';
          var c = document.getElementById('canvas_video');
          if (c) c.style.border = 'none';
          return 'tidied';
        })();
        """
        webView.evaluateJavaScript(tidy)

        // The WASM finishes after the document does. Poll briefly for
        // the export rather than guessing a delay.
        waitForModule(attempt: 0)
    }

    private func waitForModule(attempt: Int) {
        guard attempt < 60 else { return }
        web.evaluateJavaScript("!!(window.Module && window.Module._setAudioBuffer)") { [weak self] result, _ in
            guard let self else { return }
            if (result as? Bool) == true {
                self.ready = true
                let queued = self.pending
                self.pending.removeAll()
                for clip in queued { self.push(clip) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.waitForModule(attempt: attempt + 1)
            }
        }
    }
}
