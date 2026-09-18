import AppKit
import SwiftUI
import WebKit

// MARK: - Tabs

/// The Web tab's browser: pages in the panel, beside the agent.
///
/// Why one here at all, with Safari a ⌘-tab away: the page you are signed into
/// is the one worth asking about, and a fetch from the kernel does not have
/// your session. 「给 agent 看这页」 hands over the text this browser rendered —
/// logged in, after the JavaScript ran — as a file the local soul reads, with
/// the URL alongside for the agent that would rather fetch it itself.
///
/// The web views live here rather than in the view tree, for the reason the
/// terminals do: SwiftUI tears a view down when its tab leaves the hierarchy,
/// and a browser torn down loses the page, the scroll position and the form
/// half-filled in. Held here, a tab survives a trip through Cowork and back.
///
/// Cookies are `WKWebsiteDataStore.default()`, so a sign-in lasts across
/// launches — the same bargain any browser makes, in an app that already holds
/// the screen and the keyboard.
@MainActor
final class BrowserTabs: ObservableObject {
    static let shared = BrowserTabs()

    struct Tab: Identifiable, Codable, Equatable {
        var id = UUID()
        /// Where the tab was last, and where it goes when restored.
        var url: String
        var title: String
    }

    /// What the toolbar shows: the live state of one tab's web view.
    struct Live: Equatable {
        var url = ""
        var title = ""
        var loading = false
        var progress = 0.0
        var canGoBack = false
        var canGoForward = false
        var error: String?
    }

    /// A page on its way to the chat: the text this browser rendered, written
    /// where a local soul can read it.
    struct Handoff: Equatable {
        let title: String
        let url: String
        let file: URL?
        let serial: Int
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedID: UUID? { didSet { save() } }
    @Published private(set) var live: [UUID: Live] = [:]
    @Published private(set) var handoff: Handoff?

    /// Where a typed word goes when it is not a URL. The kernel's own
    /// SEARXNG_ENDPOINT when it has one — searching the same index the agent
    /// searches beats sending the browser somewhere else — DuckDuckGo when not.
    @Published private(set) var searchPrefix = "https://duckduckgo.com/?q="

    private var views: [UUID: WKWebView] = [:]
    private var relays: [UUID: NavRelay] = [:]
    private var watchers: [UUID: [NSKeyValueObservation]] = [:]
    private var serial = 0

    private static let tabsKey = "kinclaw.web.tabs"
    private static let selectedKey = "kinclaw.web.selected"

    private init() { load() }

    var selected: Tab? { tabs.first { $0.id == selectedID } ?? tabs.first }

    func liveState(_ id: UUID) -> Live { live[id] ?? Live() }

    // MARK: Tabs

    @discardableResult
    func newTab(_ url: String = "") -> Tab {
        let tab = Tab(url: url, title: "")
        tabs.append(tab)
        selectedID = tab.id
        save()
        return tab
    }

    /// Open a page in a tab of its own — a link asking for a new window, or the
    /// Web tab being handed a URL from elsewhere in the app.
    func open(_ url: String) {
        let tab = newTab(url)
        _ = view(for: tab)
    }

    func close(_ id: UUID) {
        if let v = views[id] {
            v.stopLoading()
            v.navigationDelegate = nil
            v.uiDelegate = nil
        }
        watchers[id] = nil
        relays[id] = nil
        views[id] = nil
        live[id] = nil
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: i)
        if selectedID == id {
            selectedID = tabs.isEmpty ? nil : tabs[min(i, tabs.count - 1)].id
        }
        save()
    }

    // MARK: Web views

    /// The web view for a tab, built the first time the tab is shown — so tabs
    /// restored at launch do not all fetch at once.
    func view(for tab: Tab) -> WKWebView {
        if let existing = views[tab.id] { return existing }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = make(config: config, id: tab.id)
        views[tab.id] = view
        if let url = Self.address(tab.url) {
            view.load(URLRequest(url: url))
        }
        return view
    }

    /// A web view for a page that asked for a window of its own. It has to be
    /// built with the configuration WebKit handed us, which is why this is not
    /// `open(_:)`.
    func viewForNewWindow(config: WKWebViewConfiguration) -> WKWebView {
        let tab = Tab(url: "", title: "")
        tabs.append(tab)
        selectedID = tab.id
        save()
        let view = make(config: config, id: tab.id)
        views[tab.id] = view
        return view
    }

    private func make(config: WKWebViewConfiguration, id: UUID) -> WKWebView {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), configuration: config)
        view.allowsBackForwardNavigationGestures = true
        // What shows around and behind the page — a blank tab and the rubber
        // band at the end of a scroll. Dark, like the panel; the default white
        // flashes on every load.
        view.underPageBackgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        let relay = NavRelay(id: id)
        view.navigationDelegate = relay
        view.uiDelegate = relay
        relays[id] = relay
        watchers[id] = [
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] v, _ in
                Task { @MainActor in self?.touch(id) { $0.progress = v.estimatedProgress } }
            },
            view.observe(\.title, options: [.new]) { [weak self] v, _ in
                Task { @MainActor in self?.record(id, title: v.title ?? "") }
            },
            view.observe(\.url, options: [.new]) { [weak self] v, _ in
                Task { @MainActor in self?.record(id, url: v.url?.absoluteString ?? "") }
            },
            view.observe(\.isLoading, options: [.new]) { [weak self] v, _ in
                Task { @MainActor in
                    self?.touch(id) {
                        $0.loading = v.isLoading
                        $0.canGoBack = v.canGoBack
                        $0.canGoForward = v.canGoForward
                    }
                }
            },
        ]
        return view
    }

    // MARK: Driving one tab

    /// What the address bar does with what you typed: load it if it is an
    /// address, search for it if it is not.
    func load(_ id: UUID, text: String) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let view = views[id], !typed.isEmpty else { return }
        touch(id) { $0.error = nil }
        if let url = Self.address(typed) {
            view.load(URLRequest(url: url))
            return
        }
        let query = typed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? typed
        if let url = URL(string: searchPrefix + query) {
            view.load(URLRequest(url: url))
        }
    }

    func goBack(_ id: UUID) { views[id]?.goBack() }
    func goForward(_ id: UUID) { views[id]?.goForward() }

    func reloadOrStop(_ id: UUID) {
        guard let view = views[id] else { return }
        if view.isLoading { view.stopLoading() } else { view.reload() }
    }

    /// Hand the current page to the chat: its text as a file, its URL as a
    /// line. Both, deliberately — a soul with the kinbrowser skill may rather
    /// fetch the URL itself, and a page behind a sign-in it cannot.
    func sendToAgent(_ id: UUID) {
        guard let view = views[id] else { return }
        let state = liveState(id)
        let title = state.title.isEmpty ? (state.url.isEmpty ? "这一页" : state.url) : state.title
        view.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
            let text = (result as? String) ?? ""
            Task { @MainActor in
                self?.publish(title: title, url: state.url, text: text)
            }
        }
    }

    private func publish(title: String, url: String, text: String) {
        serial += 1
        handoff = Handoff(title: title, url: url, file: Self.writePage(title: title, url: url, text: text),
                          serial: serial)
    }

    /// The page as a file under Caches, named after the page, with its URL at
    /// the top so the agent knows what it is reading.
    private static func writePage(title: String, url: String, text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/kinclaw/pages")
        var slug = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        if slug.isEmpty { slug = "page" }
        let file = folder.appendingPathComponent(String(slug.prefix(60)) + "-"
            + String(Int(Date().timeIntervalSince1970)) + ".md")
        let body = "# \(title)\n\n<\(url)>\n\n---\n\n" + text
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try body.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        sweep(folder)
        return file
    }

    /// Yesterday's pages, which nothing is reading any more.
    private static func sweep(_ folder: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-86_400)
        for url in entries where url.pathExtension == "md" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            if modified < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: State from the web views

    fileprivate func touch(_ id: UUID, _ change: (inout Live) -> Void) {
        var state = live[id] ?? Live()
        change(&state)
        guard state != live[id] else { return }
        live[id] = state
    }

    fileprivate func record(_ id: UUID, url: String? = nil, title: String? = nil, error: String? = nil) {
        touch(id) {
            if let url { $0.url = url }
            if let title { $0.title = title }
            $0.error = error
        }
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let url, !url.isEmpty { tabs[i].url = url }
        if let title { tabs[i].title = title }
        save()
    }

    fileprivate func openInNewTab(_ url: URL) { open(url.absoluteString) }

    // MARK: What the agent's tools need

    /// Make sure a tab has a web view even if its pane was never shown — an
    /// agent may open a page before the user has ever clicked Web.
    func ensureView(_ id: UUID) {
        guard views[id] == nil, let tab = tabs.first(where: { $0.id == id }) else { return }
        _ = view(for: tab)
    }

    /// Wait for the tab to finish loading. False when it is still going after
    /// `seconds` — the caller returns what there is rather than nothing.
    func waitForLoad(_ id: UUID, seconds: Double) async -> Bool {
        // A load takes a moment to even start, and `loading` is false until it
        // does; without this pause the first look would call it finished.
        try? await Task.sleep(nanoseconds: 400_000_000)
        var waited = 0.4
        while waited < seconds {
            let state = liveState(id)
            if state.error != nil { return true }
            if !state.loading, !state.url.isEmpty { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
            waited += 0.2
        }
        return false
    }

    /// The page as text, the way 给 agent 看这页 sends it.
    func pageText(_ id: UUID, limit: Int) async -> String {
        guard let view = views[id] else { return "" }
        let text: String = await withCheckedContinuation { cont in
            view.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
                cont.resume(returning: (result as? String) ?? "")
            }
        }
        return String(text.prefix(limit))
    }

    /// The open tabs, numbered the way the tools take them.
    func summary() -> String {
        guard !tabs.isEmpty else { return "面板的 Web 标签里没有打开的页面" }
        return tabs.enumerated().map { i, tab in
            let state = liveState(tab.id)
            let mark = tab.id == selected?.id ? "→" : " "
            let title = state.title.isEmpty ? tab.title : state.title
            let url = state.url.isEmpty ? tab.url : state.url
            return "\(mark) \(i + 1). \(title.isEmpty ? "(新标签页)" : title)  \(url)"
        }.joined(separator: "\n")
    }

    // MARK: Search engine

    /// Ask the kernel which search endpoint it uses, so a word typed in the
    /// address bar goes where `web_search` goes.
    func refreshSearchEngine() async {
        struct Status: Decodable { let endpoint: String? }
        guard let url = URL(string: "http://localhost:5001/api/search/status") else { return }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let status = try? JSONDecoder().decode(Status.self, from: data),
              let endpoint = status.endpoint?.trimmingCharacters(in: .whitespaces),
              !endpoint.isEmpty else { return }
        searchPrefix = endpoint.hasSuffix("/") ? endpoint + "search?q=" : endpoint + "/search?q="
    }

    /// What counts as an address rather than something to search for: a scheme
    /// we can load, or a hostname with no spaces in it.
    static func address(_ typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("about:")
            || text.hasPrefix("file://") {
            return URL(string: text)
        }
        let head = text.split(separator: "/").first.map(String.init) ?? text
        guard head.contains("."), !head.hasSuffix("."),
              head.rangeOfCharacter(from: CharacterSet(charactersIn: "@ ")) == nil else { return nil }
        return URL(string: "https://" + text)
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(tabs) else { return }
        UserDefaults.standard.set(data, forKey: Self.tabsKey)
        UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.tabsKey),
           let saved = try? JSONDecoder().decode([Tab].self, from: data) {
            tabs = saved
        }
        if let raw = defaults.string(forKey: Self.selectedKey), let id = UUID(uuidString: raw),
           tabs.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = tabs.first?.id
        }
    }
}

/// One tab's navigation and window events. `navigationDelegate` is weak, so the
/// tabs hold these.
private final class NavRelay: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID

    init(id: UUID) { self.id = id }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let id = self.id
        Task { @MainActor in
            BrowserTabs.shared.record(id, url: webView.url?.absoluteString,
                                      title: webView.title ?? "")
            BrowserTabs.shared.touch(id) {
                $0.canGoBack = webView.canGoBack
                $0.canGoForward = webView.canGoForward
                $0.loading = false
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        report(error)
    }

    private func report(_ error: Error) {
        // A cancelled load is what a new address typed mid-load looks like.
        if (error as NSError).code == NSURLErrorCancelled { return }
        let id = self.id
        let message = error.localizedDescription
        Task { @MainActor in
            BrowserTabs.shared.touch(id) { $0.error = message; $0.loading = false }
        }
    }

    /// A link that wants a window of its own gets a tab of its own.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        MainActor.assumeIsolated {
            let view = BrowserTabs.shared.viewForNewWindow(config: configuration)
            if let url = navigationAction.request.url {
                view.load(URLRequest(url: url))
            }
            return view
        }
    }
}

// MARK: - The tab

/// The Web tab: tabs, an address bar, and a button that hands the page to the
/// agent. Not a replacement for Safari — no downloads, no extensions, no
/// bookmarks — a place to put the page you are asking about.
struct WebPane: View {
    @ObservedObject private var browser = BrowserTabs.shared

    @State private var address = ""
    @State private var editing = false
    @FocusState private var addressFocused: Bool

    private typealias Tab = BrowserTabs.Tab

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().opacity(0.15)
            if let tab = browser.selected {
                toolbar(tab)
                progress(tab)
                Divider().opacity(0.15)
                WebViewSlot(view: browser.view(for: tab))
                    .id(tab.id)
            } else {
                noTabs
            }
        }
        .background(Color.black.opacity(0.28))
        .task {
            // A browser opens with a tab, the way a browser does.
            if browser.tabs.isEmpty {
                browser.newTab()
                addressFocused = true
            }
            await browser.refreshSearchEngine()
        }
        .onChange(of: browser.selected?.id) { syncAddress() }
        .onChange(of: browser.selected.map { browser.liveState($0.id).url } ?? "") { syncAddress() }
        .onAppear { syncAddress() }
    }

    // MARK: Tab strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(browser.tabs) { tab in strip(tab) }
                }
                .padding(.horizontal, 8)
            }
            Button {
                browser.newTab()
                addressFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("t", modifiers: .command)
            .padding(.horizontal, 10)
            .help("新开一个网页标签（⌘T）")
        }
        .padding(.vertical, 5)
    }

    private func strip(_ tab: Tab) -> some View {
        let active = tab.id == browser.selected?.id
        let state = browser.liveState(tab.id)
        let title = state.title.isEmpty
            ? (tab.title.isEmpty ? host(of: state.url.isEmpty ? tab.url : state.url) : tab.title)
            : state.title
        return HStack(spacing: 5) {
            if state.loading {
                Circle().fill(Color.blue.opacity(0.8)).frame(width: 5, height: 5)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Text(title.isEmpty ? "新标签页" : title)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
            Button {
                browser.close(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("关掉这个标签")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(active ? Color.white.opacity(0.10) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { browser.selectedID = tab.id }
        .help(state.url.isEmpty ? tab.url : state.url)
    }

    // MARK: Toolbar

    private func toolbar(_ tab: Tab) -> some View {
        let state = browser.liveState(tab.id)
        return HStack(spacing: 8) {
            Button { browser.goBack(tab.id) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(!state.canGoBack)
                .help("后退")
            Button { browser.goForward(tab.id) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(!state.canGoForward)
                .help("前进")
            Button {
                browser.reloadOrStop(tab.id)
            } label: {
                Image(systemName: state.loading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)
            .help(state.loading ? "停止" : "重新载入（⌘R）")

            TextField("网址，或者要搜的词", text: $address)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08)))
                .focused($addressFocused)
                .onSubmit {
                    browser.load(tab.id, text: address)
                    addressFocused = false
                }
                .onChange(of: addressFocused) { _, focused in editing = focused }

            Button {
                browser.sendToAgent(tab.id)
            } label: {
                Image(systemName: "paperplane")
            }
            .buttonStyle(.borderless)
            .help("把这一页交给 agent —— 正文存成文件，链接一起发过去")

            Button {
                if let url = URL(string: state.url.isEmpty ? tab.url : state.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("在默认浏览器里打开这一页")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func progress(_ tab: Tab) -> some View {
        let state = browser.liveState(tab.id)
        if let error = state.error {
            Text(error)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        } else if state.loading {
            ProgressView(value: max(state.progress, 0.02))
                .progressViewStyle(.linear)
                .frame(height: 2)
                .padding(.horizontal, 12)
        }
    }

    private var noTabs: some View {
        VStack(spacing: 10) {
            Text("没有打开的网页")
                .font(.system(size: 13))
            Button("开一个") {
                browser.newTab()
                addressFocused = true
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Bits

    /// The address bar follows the page, except while it is being typed in.
    private func syncAddress() {
        guard let tab = browser.selected else { address = ""; return }
        guard !editing else { return }
        let live = browser.liveState(tab.id).url
        address = live.isEmpty ? tab.url : live
    }

    private func host(of url: String) -> String {
        URL(string: url)?.host ?? url
    }
}

/// Shows a web view the tabs own. The container is SwiftUI's to create and
/// destroy; the web view inside it is not, which is what lets a page survive
/// its tab being out of sight.
private struct WebViewSlot: NSViewRepresentable {
    let view: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        mount(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if view.superview !== container { mount(in: container) }
    }

    private func mount(in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
