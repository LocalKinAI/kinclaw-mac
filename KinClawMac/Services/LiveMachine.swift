import AppKit
import SwiftUI
import UserNotifications
import WebKit

/// 「做成一台机器」: 画给我看's second way (「做吧，接成第二种画法」, 2026-10-10). Instead of huashu's few
/// seconds of moving painting, Claude builds with anatomy (github.com/wheresryan22/anatomy, MIT, carried in
/// the app) a small isometric machine whose working is the idea — dozens of precise parts, a readout that
/// is true, things to press, turn and drag — as one standalone page. It takes a quarter to half an hour,
/// in the background; the person is told when it is made and touches it right there in the conversation.
///
/// Claude works in the machine's own folder (<art>/live/<id>/machine), reads anatomy from the copy kept
/// beside the drawings (<art>/live/_anatomy-<commit>, made once from the app's), builds the page with
/// `node build.mjs`, and looks at it with machine_check — anatomy's drive.mjs and line check, in the
/// WebKit the person will use it in — instead of the headless Chrome anatomy's own scripts start.
@MainActor
final class LiveMachine: ObservableObject {
    static let shared = LiveMachine()

    /// One machine kept on this Mac (<art>/live/<id>/machine.json).
    struct Machine: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var question: String?
        var made: Date?
        /// How tall it stands in a conversation, 640 px wide (its poster's height).
        var height: Double?
    }

    @Published private(set) var machines: [Machine] = []
    /// The machine in a conversation that can be touched now — one at a time; the others show a still.
    @Published private(set) var active: String?
    /// The one the window shows.
    @Published private(set) var current: Machine?
    let inline = MachinePage(embedded: true)
    let page = MachinePage(embedded: false)
    let checker = MachineCheck()
    private var window: NSWindow?

    private init() { reload() }

    static func folder(_ id: String) -> URL { LiveFilm.folder.appendingPathComponent(id) }
    /// Where Claude works: its model, its build script, the page it builds (index.html), its title.
    static func work(_ id: String) -> URL { folder(id).appendingPathComponent("machine") }
    static func page(_ id: String) -> URL { work(id).appendingPathComponent("index.html") }
    static func poster(_ id: String) -> URL { folder(id).appendingPathComponent("poster.png") }

    // MARK: - anatomy

    /// The skill inside the app, and the commit it is (SOURCE's second line).
    private static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("anatomy") }

    private static var commit: String {
        let source = bundled.flatMap { try? String(contentsOf: $0.appendingPathComponent("SOURCE"), encoding: .utf8) } ?? ""
        let sha = source.range(of: #"commit ([0-9a-f]{7,40})"#, options: .regularExpression)
            .map { String(source[$0].dropFirst("commit ".count)) } ?? "local"
        return String(sha.prefix(7))
    }

    /// anatomy where Claude reads it and its build scripts import it: a copy beside the drawings, one per
    /// commit — a machine made with this one rebuilds with it even after the app carries a newer one —
    /// and read-only, so nothing writes into it by mistake.
    static func skill() throws -> URL {
        let kept = LiveFilm.folder.appendingPathComponent("_anatomy-\(commit)")
        let files = FileManager.default
        if files.fileExists(atPath: kept.appendingPathComponent("SKILL.md").path) { return kept }
        guard let bundled, files.fileExists(atPath: bundled.appendingPathComponent("SKILL.md").path) else {
            throw LiveFilm.Failure.message("这个 App 里没有 anatomy（Contents/Resources/anatomy）")
        }
        let partial = LiveFilm.folder.appendingPathComponent("_anatomy-\(commit).partial-\(UUID().uuidString.prefix(6))")
        try files.createDirectory(at: LiveFilm.folder, withIntermediateDirectories: true)
        try files.copyItem(at: bundled, to: partial)
        if let walk = files.enumerator(at: partial, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let item as URL in walk {
                let folder = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if !folder { try? files.setAttributes([.posixPermissions: 0o444], ofItemAtPath: item.path) }
            }
        }
        try files.moveItem(at: partial, to: kept)
        return kept
    }

    /// anatomy's line check (scripts/line-ends.mjs): the function, without its export.
    private lazy var lineEnds: String? = {
        guard let skill = try? Self.skill(),
              let source = try? String(contentsOf: skill.appendingPathComponent("scripts/line-ends.mjs"), encoding: .utf8) else { return nil }
        return source.components(separatedBy: "\n").filter { !$0.hasPrefix("export const LINE_ENDS") }.joined(separator: "\n")
    }()

    /// Node, which builds the page (anatomy wants 20.10 or later), on the PATH Claude's shell gets: its
    /// path, or why not.
    private var nodeChecked: Result<String, LiveFilm.Failure>?

    func node(on path: String) async -> Result<String, LiveFilm.Failure> {
        if let nodeChecked, case .success = nodeChecked { return nodeChecked }
        let path = path.split(separator: ":").map { "\($0)/node" }.first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let path else {
            let missing = Result<String, LiveFilm.Failure>.failure(.message("做成一台机器要用 Node 搭（20.10 以上）：这台 Mac 上没找到 node"))
            nodeChecked = missing
            return missing
        }
        let (status, said) = await LiveFilm.copy(path, ["--version"])
        let parts = said.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst().split(separator: ".").compactMap { Int($0) }
        let new = status == 0 && parts.count >= 2 && (parts[0] > 20 || (parts[0] == 20 && parts[1] >= 10))
        let checked: Result<String, LiveFilm.Failure> = new ? .success(path)
            : .failure(.message("做成一台机器要 Node 20.10 以上，这台 Mac 上的是 \(said.trimmingCharacters(in: .whitespacesAndNewlines))"))
        nodeChecked = checked
        return checked
    }

    // MARK: - The machines kept

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: LiveFilm.folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        machines = folders.compactMap { folder in
            (try? Data(contentsOf: folder.appendingPathComponent("machine.json"))).flatMap { try? decoder.decode(Machine.self, from: $0) }
        }
        .sorted { ($0.made ?? .distantPast) > ($1.made ?? .distantPast) }
    }

    /// By its id or a piece of its title; nil: the one in the window, else the last made.
    func machine(named name: String?) -> Machine? {
        reload()
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return current ?? machines.first }
        return machines.first { $0.id == name } ?? machines.first { $0.title.localizedCaseInsensitiveContains(name) }
    }

    /// A machine Claude has built: its still as it sits in a conversation, kept with its name. Nil when its
    /// page does not open.
    func made(_ id: String, title: String, question: String) async -> Machine? {
        guard let height = await checker.poster(Self.page(id), width: 640, to: Self.poster(id)) else { return nil }
        let machine = Machine(id: id, title: title, question: question, made: Date(), height: height)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard (try? encoder.encode(machine).write(to: Self.folder(id).appendingPathComponent("machine.json"), options: .atomic)) != nil else { return nil }
        reload()
        if active == id { inline.load(Self.page(id)) }
        if current?.id == id { current = machine; page.load(Self.page(id)) }
        return machine
    }

    // MARK: - Touching it

    /// The machine comes alive in its card; the one that was alive goes back to its still.
    func activate(_ id: String) {
        guard FileManager.default.fileExists(atPath: Self.page(id).path) else { return }
        active = id
        inline.load(Self.page(id))
    }

    /// The machine in a window of its own (`name`: its id or a piece of its title).
    func show(_ name: String? = nil) {
        guard let machine = machine(named: name) else { return }
        if window == nil { makeWindow() }
        current = machine
        window?.title = "机器 · \(machine.title)"
        page.load(Self.page(machine.id))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// In the browser: the page stands alone, so it can be kept, sent or printed from there.
    func openInBrowser(_ id: String) {
        NSWorkspace.shared.open(Self.page(id))
    }

    private func makeWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1000, screen.width - 80), height: min(980, screen.height - 60))
        let made = NSWindow(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        made.isReleasedWhenClosed = false
        made.contentMinSize = NSSize(width: 420, height: 420)
        made.contentView = NSHostingView(rootView: MachineWindowView())
        window = made
    }

    /// Made in the background: the person hears of it unless they are looking at the panel.
    func tell(_ title: String) {
        if NSApp.isActive, (NSApp.delegate as? AppDelegate)?.spotlightWindow.isVisible == true { return }
        let content = UNMutableNotificationContent()
        content.title = "机器做好了"
        content.body = "「\(title)」：在对话里点开就能摸"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - The check

    /// machine_check: the machine's page driven in WebKit (MachineCheck), what each step saw, and the
    /// pictures — the first six as image:// lines, the rest named so they can be read.
    func check(_ id: String, steps: [[Any]]?, options: MachineCheck.Options) async -> (String, Bool) {
        guard id.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil,
              FileManager.default.fileExists(atPath: Self.page(id).path) else {
            return ("没有这台机器的页面：\(Self.page(id).path) 不在（先 node build.mjs）", true)
        }
        let out = await checker.run(Self.page(id), steps: steps, options: options,
                                    shots: Self.work(id).appendingPathComponent("check"), lineEnds: lineEnds)
        var lines = out.lines
        lines.append(out.problems == 0 ? "没有发现问题" : "问题：\(out.problems)")
        // Four pictures come back as images: each is read again at every later turn of the
        // conversation, so the rest are named, to Read only if they matter.
        if out.pictures.count > 4 {
            lines.append("图多于四张，后面的在这里，要看就 Read：" + out.pictures.dropFirst(4).map(\.path).joined(separator: "、"))
        }
        lines += out.pictures.prefix(4).map { "image://" + $0.path }
        return (lines.joined(separator: "\n"), false)
    }

    /// The line for the tools.
    func report() -> String {
        reload()
        guard !machines.isEmpty else { return "还没有做好的机器" }
        return "做好的机器：" + machines.prefix(12).map { "「\($0.title)」（\($0.id)）" }.joined(separator: "、")
    }

    // MARK: - What Claude is told

    nonisolated static func ask(question: String, answer: String) -> String {
        """
        他们问：\(question)

        回答（他们刚读到的）：
        \(answer.prefix(4000))

        做成一台机器：把这个回答里最要紧的那个道理，做成一台能摸的小机器——一台真的、做工精细的东西，它怎么动，就是这个道理；\
        读数是真的，能按、能拧、能拖。不要方框和箭头，不要图表。
        """
    }

    nonisolated static func brief(id: String, skill: String) -> String {
        """
        You make the answer to a person's question into a machine they can touch — 做成一台机器 — with the anatomy \
        skill: one interactive isometric figure, a real, well-made physical object whose working *is* the idea, in a \
        framed card with a live readout. It is shown in their app (WebKit) right under the answer they read, about \
        600 px wide, and in a window of its own. It is made in one go, in the background: one direction — no options, \
        no questions back, no asking about the size.

        Where things are
        - The working directory is this machine, id "\(id)". Write only here.
        - anatomy, to read and never to change: \(skill). Its SKILL.md is the method: read it first. Then build from \
        examples/dial-indicator/build.mjs — the smallest whole figure — and look up only what you call: Grep \
        kit/iso-kit.mjs (or lathe.mjs, tube.mjs) for a function's signature, and read the one section of \
        references/craft.md, kit.md or motion.md you need, not whole files. Everything you read is read again at every \
        later turn: read little, and work in few, large steps — write a file whole, fix several things in one edit. \
        Don't build the examples: that folder is read-only.

        The size: always a Figure — one mechanism, 40–80 parts, SVG only: no WebGL layer and no 3D mode. Have a \
        working page within the first ten minutes, then deepen it; about half an hour in all.

        What to write
        - model.mjs: the truth — the real numbers and behaviour as a small pure module that the readout, the motion \
        and the caption all come from (SKILL.md, "Truth first").
        - build.mjs: imports the kit by absolute path — import * as K from "\(skill)/kit/iso-kit.mjs"; import { \
        kitScript } from "\(skill)/scripts/inline-kit.mjs"; lathe.mjs, tube.mjs and audit.mjs the same way when you \
        need them — and writes one standalone page, index.html, next to itself: pageHtml({ title, theme: "light", \
        body, script: kitScript() + live }). The light theme only, and nothing from the network (no fonts, no CDN).
        - title.txt: one short line naming the machine, in their language.

        Words: everything on the page — the card's title, hint and readout, its buttons, the legend and the caption \
        — in the language they wrote in; for Chinese set <html lang="zh-CN"> (pageHtml writes lang="en": replace \
        it). It must read at 390 px wide as well as at 1440, and the card fills the width it is given: nothing sized \
        to the window's height.

        The shell: the one command is `node build.mjs`, with any flags your build takes (--audit, --test …), run \
        here, without cd — no other node, no python, no scripts elsewhere: look things up in the kit with Read and \
        Grep, change files with Edit and Write, and put any test or probe in build.mjs behind a flag. anatomy's own \
        scripts that drive Chrome — capture.mjs, drive.mjs, lines.mjs — are not used here: machine_check does what \
        they do, in the WebKit the person will use.

        Check, then fix: call machine_check with id "\(id)" — four times at most, each call doing many steps. It \
        loads index.html in that WebKit and runs `steps`, drive.mjs's actions with a picture's name instead of its \
        path: ["wait", ms], ["scroll", sel], ["move", sel, fx, fy], ["click", sel, fx?, fy?], ["drag", sel, fx0, fy0, \
        fx1, fy1, steps?], ["key", key, sel?, code?], ["slow", factor], ["until", js, ms?], ["eval", js], ["shot", \
        name, sel?, scale?, [x, y, w, h]?], ["sheet", name, every, count, sel?, scale?, [x, y, w, h]?, columns?], \
        ["lines", name?, sel?, { tolerance }?]; `width` 1440 (default) or 390 for a phone; `nowebgl`, `reduced`, \
        `preload` as drive.mjs's flags. Without steps: a picture of the card and the line check. It answers with the \
        readout after each picture, the line ends that float, the console's errors, whether the page scrolls \
        sideways, and the pictures — the first four as images, the rest in check/ to Read. Its events are the page's \
        own (PointerEvent, KeyboardEvent), so CSS :hover does not follow them. A good order: first, once it builds — \
        the card at 1440, the line check, each control pressed and its readout read; then, after fixing — the same \
        again with 390 wide; the last calls only for what is still wrong, with 4× close-ups (["shot", "joint", null, \
        4, [x, y, w, h]]) only where something looks off. Before you finish: line ends at 0, the console clean, \
        `node build.mjs --audit` passing when it has pipes, cables or round parts. Look at every picture as the critic \
        who zooms in.

        Then answer with one line: the title.
        """
    }
}

/// A machine's page shown to the person: in a conversation (`embedded`: no margins round the card, its
/// height told as it changes so the card fits it), or in the machine's window.
@MainActor
final class MachinePage: NSObject, ObservableObject {
    /// The page's height at the width it has, in px (embedded only); 0 until it has said.
    @Published private(set) var height: Double = 0
    @Published private(set) var shown: URL?
    let view: WKWebView
    private let relay = MachinePageRelay()

    init(embedded: Bool) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        if embedded {
            config.userContentController.addUserScript(WKUserScript(source: """
                (() => {
                  const s = document.createElement('style'); s.textContent = \(Self.quoted(MachineCheck.embeddedCSS)); document.head.appendChild(s);
                  const tell = () => window.webkit.messageHandlers.machinePage.postMessage(Math.ceil(document.body.getBoundingClientRect().height));
                  new ResizeObserver(tell).observe(document.body); tell();
                })();
                """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 600), configuration: config)
        // anatomy's light page, so nothing flashes white or black around it while it loads.
        view.underPageBackgroundColor = NSColor(srgbRed: 0xf2 / 255, green: 0xf2 / 255, blue: 0xef / 255, alpha: 1)
        super.init()
        config.userContentController.add(relay, name: "machinePage")
        relay.owner = self
    }

    func load(_ page: URL) {
        height = 0
        shown = page
        var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "v", value: String(UUID().uuidString.prefix(8)))]
        view.loadFileURL(parts?.url ?? page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    fileprivate func told(_ height: Double) {
        if height > 0, abs(height - self.height) >= 1 { self.height = height }
    }

    private static func quoted(_ text: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [text])).flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "''"
    }
}

private final class MachinePageRelay: NSObject, WKScriptMessageHandler {
    weak var owner: MachinePage?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let height = MachineCheck.number(message.body) else { return }
        Task { @MainActor [weak owner] in owner?.told(height) }
    }
}

/// A machine page's web view, where SwiftUI wants it.
struct MachinePageView: NSViewRepresentable {
    let page: MachinePage

    func makeNSView(context: Context) -> WKWebView { page.view }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// The machine's window: the page, and under it which one, another, the browser, the folder.
struct MachineWindowView: View {
    @ObservedObject private var machines = LiveMachine.shared

    var body: some View {
        VStack(spacing: 0) {
            MachinePageView(page: machines.page)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            HStack(spacing: 12) {
                Text(machines.current?.title ?? "").font(.kinLabel.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if machines.machines.count > 1 {
                    Menu {
                        ForEach(machines.machines) { machine in
                            Button(machine.title) { machines.show(machine.id) }
                        }
                    } label: { Label("换一台", systemImage: "square.stack.3d.up") }
                    .menuStyle(.button).buttonStyle(.plain)
                    .fixedSize()
                }
                if let id = machines.current?.id {
                    Button { machines.openInBrowser(id) } label: { Label("在浏览器里打开", systemImage: "safari") }
                        .buttonStyle(.quiet)
                        .help("这一页不靠别的文件，可以存下来、发给别人")
                    Button { NSWorkspace.shared.activateFileViewerSelecting([LiveMachine.page(id)]) } label: {
                        Label("文件夹", systemImage: "folder")
                    }
                    .buttonStyle(.quiet)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.sidebar)
        }
    }
}
