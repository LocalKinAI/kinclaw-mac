import Foundation
import WebKit

/// ComfyUI on the box, for somebody who does not build node graphs.
///
/// Three ways in, all on one graph:
///   · a template — ComfyUI ships some three hundred ready workflows, each a
///     graph somebody who does know built and tested; pick one, fill the form,
///     run it;
///   · words — say what you want and the writer model picks the template and
///     fills the form (or, with a workflow open, changes what you asked for);
///   · the real editor — the same graph in ComfyUI's own page, for when the
///     form is not enough. Whatever is changed there is what the form shows
///     when it closes, because it is the same graph.
///
/// The graph lives in ComfyUI's own frontend, loaded in a WKWebView that is
/// usually not on screen. That is deliberate: a template is a *UI* workflow
/// (nodes, subgraphs, widgets promoted out of subgraphs), and what the server
/// runs is an *API* prompt; turning one into the other is several thousand
/// lines of the frontend's own code, which is already on the box and always
/// the version that matches the server. So the page is asked — for the form's
/// fields, to set a value, for the prompt — rather than imitated.
@MainActor
final class ComfyStudio: NSObject, ObservableObject {
    static let shared = ComfyStudio()

    struct Template: Identifiable, Hashable {
        let name: String
        let title: String
        let description: String
        let category: String
        let mediaType: String
        let mediaSubtype: String
        let tags: [String]
        let models: [String]
        let size: Int64?
        /// Runs on the box. The rest call a paid cloud API through ComfyUI's
        /// account and are listed only when asked for.
        let local: Bool
        /// A workflow the user saved, not one of ComfyUI's.
        var saved: URL? = nil
        /// Categories a saved workflow also belongs in, from what it uses:
        /// one that asks Ollama is listed under LLM beside ComfyUI's own.
        var also: [String] = []
        func belongs(to name: String) -> Bool { category == name || also.contains(name) }
        var id: String { saved?.path ?? name }

        @MainActor var thumbnail: URL? {
            saved == nil ? URL(string: ComfyStudio.base + "/templates/\(name)-1.\(mediaSubtype)") : nil
        }
    }

    struct Field: Identifiable, Equatable {
        let node: String
        let nodeTitle: String
        let nodeType: String
        let name: String
        /// The frontend's widget type: number, combo, toggle, text, customtext, …
        let kind: String
        var value: String
        var options: [String]?
        let min: Double?
        let max: Double?
        let step: Double?
        var id: String { node + "/" + name }

        var isSeed: Bool { kind == "number" && (name == "seed" || name == "noise_seed" || name.hasSuffix("_seed")) }
        /// A picture, video or sound the workflow starts from: filled by uploading.
        var isFile: Bool {
            ComfyStudio.loaders.contains(nodeType) && ["image", "video", "audio", "file"].contains(name)
        }
        /// A loader still naming the template's sample file, which is not on
        /// the box: the workflow cannot run until it is given one of yours.
        var needsInput: Bool { isFile && (options.map { !$0.contains(value) } ?? false) }
        var isLong: Bool { kind == "customtext" || name.contains("prompt") || name == "text" }
    }

    struct Missing: Identifiable, Equatable {
        let name: String
        let directory: String
        let url: String
        var bytes: Int64?
        /// The same file already on the box, for another program — linked
        /// into ComfyUI's folder instead of downloaded again.
        var onBox: String? = nil
        /// A download that stopped part way: the file is there under its
        /// name, this many bytes of it. Resumed, not restarted.
        var partial: Int64? = nil
        var id: String { directory + "/" + name }
    }

    struct Run: Identifiable, Equatable {
        let folder: URL
        let title: String
        let when: Date
        let outputs: [URL]
        var id: String { folder.path }
    }

    @Published private(set) var templates: [Template] = []
    @Published private(set) var saved: [Template] = []
    @Published private(set) var current: Template?
    @Published var fields: [Field] = []
    @Published private(set) var notes: [String] = []
    @Published private(set) var missing: [Missing] = []
    /// Node types the open workflow uses that the box's ComfyUI does not have
    /// (a community workflow's custom nodes). Nothing here installs them.
    @Published private(set) var missingNodes: [String] = []

    /// Whether each template can run with what is on the box, by name.
    struct Readiness: Equatable {
        let models: Int
        let lacking: Int
        let nodes: [String]
        var runs: Bool { lacking == 0 && nodes.isEmpty }
    }
    @Published private(set) var readiness: [String: Readiness] = [:]
    @Published private(set) var scanning = false
    @Published private(set) var fetching: [String: String] = [:]
    @Published private(set) var runs: [Run] = []
    /// Non-nil while something is happening, saying what.
    @Published private(set) var working: String?
    @Published private(set) var progress: Double?
    @Published private(set) var note: String?
    @Published private(set) var since: Date?
    /// Keep the seed that is in the form, instead of a new one every run.
    @Published var keepSeed = false

    nonisolated static let loaders: Set<String> = ["LoadImage", "LoadImageMask", "LoadVideo", "LoadAudio", "LoadImageOutput", "VHS_LoadVideo"]
    /// Nodes whose widgets are nobody's business in a form.
    private static let quiet = ["Note", "MarkdownNote", "PrimitiveNode", "Reroute", "PreviewImage", "PreviewAny", "ImageCompare"]

    let web: WKWebView
    private var loadedBase: String?
    private var work: Task<Void, Never>?
    private var promptID: String?
    private let client = UUID().uuidString

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900), configuration: config)
        super.init()
        loadRuns()
        loadSaved()
    }

    static var base: String { BoxServices.base(.comfy) }
    static var root: URL { CompanionArt.folder.appendingPathComponent("comfy") }
    static var savedFolder: URL { root.appendingPathComponent("workflows") }

    // MARK: - Templates

    func refresh() async {
        guard await BoxServices.shared.ensure(.comfy) else { note = "ComfyUI 没起来：Settings → Backend → 盒子上的服务 里看一下"; return }
        for index in ["index.zh.json", "index.json"] {
            guard let url = URL(string: Self.base + "/templates/" + index),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let groups = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { continue }
            var list: [Template] = []
            for group in groups {
                let category = group["title"] as? String ?? ""
                for t in group["templates"] as? [[String: Any]] ?? [] {
                    guard let name = t["name"] as? String else { continue }
                    let open = t["openSource"] as? Bool
                    list.append(Template(
                        name: name, title: t["title"] as? String ?? name,
                        description: t["description"] as? String ?? "", category: category,
                        mediaType: t["mediaType"] as? String ?? "image", mediaSubtype: t["mediaSubtype"] as? String ?? "webp",
                        tags: t["tags"] as? [String] ?? [], models: t["models"] as? [String] ?? [],
                        size: (t["size"] as? NSNumber)?.int64Value,
                        local: open != false && !name.hasPrefix("api_")))
                }
            }
            templates = list
            note = nil
            // The page takes a while over the LAN; start it now, so it is ready
            // by the time a workflow is clicked.
            Task { _ = await self.page() }
            await scan()
            return
        }
        note = "ComfyUI 答应了，但拿不到模板目录（\(Self.base)/templates/index.zh.json）"
    }

    var categories: [String] {
        var seen: [String] = []
        for t in templates where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }

    private func loadSaved() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.savedFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        saved = files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { file in
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            var also: [String] = []
            if text.contains("\"OllamaChat\"") { also.append("LLM") }
            let video = ["\"OllamaDiffuserVideo\"", "\"SaveVideo\"", "\"CreateVideo\""].contains(where: text.contains)
            if video { also.append("视频") }
            else if ["\"OllamaDiffuserTextToImage\"", "\"OllamaDiffuserEditImage\"", "\"SaveImage\""].contains(where: text.contains) { also.append("图像") }
            let uses = [text.contains("\"OllamaChat\"") ? "Ollama" : nil,
                        text.contains("\"OllamaDiffuser") ? "ollamadiffuser" : nil].compactMap { $0 }
            return Template(name: file.deletingPathExtension().lastPathComponent, title: file.deletingPathExtension().lastPathComponent,
                            description: uses.isEmpty ? "自己存的" : "用盒子上的 " + uses.joined(separator: " 和 ") + "，不另外下模型",
                            category: "我的", mediaType: video ? "video" : "image", mediaSubtype: "png",
                            tags: [], models: uses, size: nil, local: true, saved: file, also: also)
        }
    }

    // MARK: - The page

    /// ComfyUI's own frontend, loaded and ready to be asked things.
    private func page() async -> Bool {
        guard await BoxServices.shared.ensure(.comfy) else { note = "ComfyUI 没起来"; return false }
        if loadedBase != Self.base || web.url == nil {
            guard let url = URL(string: Self.base + "/") else { return false }
            web.load(URLRequest(url: url))
            loadedBase = Self.base
        }
        // Reloaded only when loading has stalled — nothing new fetched for 20
        // seconds. A reload on a timer was worse than none: with the box's
        // network busy (a 36 GB download) the page takes longer than the timer
        // to load, and every reload started it over, so it never finished.
        var fetched = -1
        var still = 0
        for _ in 1...120 {
            let state = (try? await js("""
                if (window.app && window.app.graph) return 'ready';
                return String(performance.getEntriesByType('resource').length);
                """)) ?? ""
            if state == "ready" { return true }
            let count = Int(state) ?? -1
            if count == fetched { still += 1 } else { still = 0; fetched = count }
            if still >= 20, let url = URL(string: Self.base + "/") {
                web.load(URLRequest(url: url))
                still = 0
                fetched = -1
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        note = "ComfyUI 的页面 2 分钟没准备好（盒子忙？）"
        loadedBase = nil
        return false
    }

    /// Run a function body in the page; it must return a string.
    @discardableResult
    private func js(_ body: String, _ arguments: [String: Any] = [:]) async throws -> String {
        let value = try await web.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
        return value as? String ?? ""
    }

    // MARK: - Opening

    /// Which open is the latest. Two can overlap (a click while the agent is
    /// opening one), and each is several awaits long; the one started last
    /// wins, and the others stop at their next step instead of mixing their
    /// fields and models into it.
    private var opening = 0

    func open(_ template: Template) async {
        guard work == nil else { note = "正在跑，跑完再换工作流"; return }
        opening += 1
        let mine = opening
        working = "打开"
        defer { if opening == mine { working = nil } }
        let data: Data?
        if let file = template.saved {
            data = try? Data(contentsOf: file)
        } else if let url = URL(string: Self.base + "/templates/\(template.name).json") {
            data = try? await URLSession.shared.data(from: url).0
        } else { data = nil }
        guard let data, let text = String(data: data, encoding: .utf8) else { note = "拿不到 \(template.name) 的工作流"; return }
        working = "打开（等 ComfyUI 的页面）"
        guard await page(), opening == mine else { return }
        do {
            // A UI workflow has "nodes"; an API prompt (all some pictures and
            // sites carry) is loaded by the frontend's other door.
            try await js("""
                const g = JSON.parse(wf);
                if (Array.isArray(g.nodes)) {
                  await window.app.loadGraphData(g, true, true, null,
                      {showMissingModelsDialog: false, showMissingNodesDialog: false});
                } else {
                  await window.app.loadApiJson(g, name);
                }
                return 'ok';
                """, ["wf": text, "name": template.name])
        } catch {
            note = "ComfyUI 读不了这个工作流：\(error.localizedDescription)"
            return
        }
        guard opening == mine else { return }
        current = template
        note = nil
        missing = []
        missingNodes = []
        await readFields()
        guard opening == mine else { return }
        await checkModels(in: data, for: mine)
    }

    /// Put a prompt into the open workflow — its main prompt field, never the
    /// negative one. False, and said, when the workflow has none.
    @discardableResult
    func usePrompt(_ text: String) async -> Bool {
        let long = fields.filter { $0.isLong && !$0.name.lowercased().contains("negative") && !$0.isFile }
        guard let target = long.first(where: { $0.name.lowercased().contains("prompt") || $0.name.lowercased() == "caption" })
                ?? long.first(where: { $0.nodeType.hasPrefix("PrimitiveString") })
                ?? long.first else {
            note = "这个工作流没有写提示词的地方"
            return false
        }
        await set(target, to: text)
        note = "提示词放进了「\(target.nodeTitle) · \(target.name)」"
        return true
    }

    /// Open a template by name and put a prompt into it.
    func open(templateNamed name: String, prompt: String) async {
        if templates.isEmpty { await refresh() }
        guard let t = template(named: name) else { note = "没有模板 \(name)"; return }
        await open(t)
        guard current?.id == t.id else { return }
        await usePrompt(prompt)
    }

    func close() {
        guard work == nil else { return }
        current = nil
        fields = []
        notes = []
        missing = []
    }

    /// The form: every widget a person might want to change, in the order the
    /// graph has them. Notes are kept apart — they are the template author's
    /// instructions, and worth showing as such.
    func readFields() async {
        guard let text = try? await js("""
            const quiet = new Set(\(Self.jsList(Self.quiet)));
            const fields = [], notes = [];
            for (const n of window.app.graph.nodes) {
              if (n.mode === 2 || n.mode === 4) continue;           // muted or bypassed
              if (n.type === 'MarkdownNote' || n.type === 'Note') {
                const w = (n.widgets || [])[0]; if (w && w.value) notes.push(String(w.value)); continue;
              }
              if (quiet.has(n.type)) continue;
              for (const w of (n.widgets || [])) {
                if (w.name === 'control_after_generate' || w.name === 'upload' || w.type === 'button') continue;
                if (w.hidden || (w.options && w.options.hidden)) continue;
                if ((n.inputs || []).find(i => i.widget && i.widget.name === w.name && i.link != null)) continue;
                const v = w.value;
                if (v !== null && typeof v === 'object') continue;    // previews, canvases
                const values = w.options && Array.isArray(w.options.values) ? w.options.values.slice(0, 400).map(String) : null;
                fields.push({node: String(n.id), title: n.title || n.type, type: n.type, name: w.name, kind: String(w.type),
                  value: v === undefined || v === null ? '' : String(v), values,
                  min: w.options?.min ?? null, max: w.options?.max ?? null, step: w.options?.step2 ?? null});
              }
            }
            return JSON.stringify({fields, notes});
            """),
              let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return }
        notes = object["notes"] as? [String] ?? []
        fields = (object["fields"] as? [[String: Any]] ?? []).map { f in
            Field(node: f["node"] as? String ?? "", nodeTitle: f["title"] as? String ?? "", nodeType: f["type"] as? String ?? "",
                  name: f["name"] as? String ?? "", kind: f["kind"] as? String ?? "", value: f["value"] as? String ?? "",
                  options: f["values"] as? [String], min: (f["min"] as? NSNumber)?.doubleValue,
                  max: (f["max"] as? NSNumber)?.doubleValue, step: (f["step"] as? NSNumber)?.doubleValue)
        }
    }

    /// Change one value, in the page and in the form.
    func set(_ field: Field, to value: String) async {
        guard let index = fields.firstIndex(where: { $0.id == field.id }) else { return }
        fields[index].value = value
        _ = try? await js("""
            const n = window.app.graph.getNodeById(Number(node)) || window.app.graph.nodes.find(x => String(x.id) === node);
            const w = n && (n.widgets || []).find(x => x.name === name);
            if (!w) return 'missing';
            let v = value;
            if (kind === 'number' || kind === 'slider') v = Number(value);
            if (kind === 'toggle' || kind === 'boolean') v = (value === 'true');
            // A dropdown's options can be numbers (bit depth 8 | 10); the form
            // holds text, and ComfyUI rejects '8' where 8 was offered.
            const opts = w.options && Array.isArray(w.options.values) ? w.options.values : null;
            if (opts) { const hit = opts.find(o => String(o) === value); if (hit !== undefined) v = hit; }
            w.value = v; if (w.callback) w.callback(v);
            window.app.graph.setDirtyCanvas(true, true);
            return 'ok';
            """, ["node": field.node, "name": field.name, "value": value, "kind": field.kind])
    }

    /// The form is edited locally as it is typed; this puts all of it into the
    /// page — before a run, and before the editor is shown.
    func pushAll() async {
        for field in fields { await set(field, to: field.value) }
    }

    /// Put a local file where the workflow reads one from: upload it to the
    /// box's ComfyUI input folder, then name it in the loader.
    func upload(_ file: URL, into field: Field) async {
        guard let url = URL(string: Self.base + "/upload/image"), let bytes = try? Data(contentsOf: file) else { return }
        let boundary = "kinclaw-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(bytes)
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = answer["name"] as? String else { note = "传不上去：\(file.lastPathComponent)"; return }
        let sub = answer["subfolder"] as? String ?? ""
        let value = sub.isEmpty ? name : sub + "/" + name
        // The loader's list of files was read before this one was there.
        if let i = fields.firstIndex(where: { $0.id == field.id }), fields[i].options?.contains(value) == false {
            fields[i].options?.append(value)
        }
        _ = try? await js("""
            const n = window.app.graph.getNodeById(Number(node));
            const w = n && (n.widgets || []).find(x => x.name === name);
            if (w && w.options && Array.isArray(w.options.values) && !w.options.values.includes(value)) w.options.values.push(value);
            return 'ok';
            """, ["node": field.node, "name": field.name, "value": value])
        await set(field, to: value)
    }

    // MARK: - Models

    /// What a workflow needs: the model files it names (with the folder they
    /// go in and where they come from) and the node types it uses. Templates
    /// declare their models on the loader nodes; that is what is read.
    typealias Needs = (models: [Missing], types: Set<String>, files: Set<String>)

    /// A value that names a model file.
    nonisolated private static func isModelFile(_ value: Any) -> String? {
        guard let text = value as? String, text.count < 300 else { return nil }
        let lower = text.lowercased()
        return [".safetensors", ".gguf", ".ckpt", ".pth", ".pt", ".bin", ".sft", ".onnx"].contains(where: lower.hasSuffix) ? text : nil
    }

    nonisolated private static func requirements(of workflow: Data) -> Needs? {
        guard let graph = (try? JSONSerialization.jsonObject(with: workflow)) as? [String: Any] else { return nil }
        guard var nodes = graph["nodes"] as? [[String: Any]] else {
            // An API prompt (what ComfyUI's pictures carry as "prompt"): no
            // declared models — the file names in its inputs are what it needs.
            let entries = graph.values.compactMap { $0 as? [String: Any] }
            let types = entries.compactMap { $0["class_type"] as? String }
            let files = entries.flatMap { ($0["inputs"] as? [String: Any] ?? [:]).values.compactMap(isModelFile) }
            return ([], Set(types), Set(files))
        }
        let subs = (graph["definitions"] as? [String: Any])?["subgraphs"] as? [[String: Any]] ?? []
        let inner = Set(subs.compactMap { $0["id"] as? String })
        for sub in subs { nodes += sub["nodes"] as? [[String: Any]] ?? [] }
        var models: [Missing] = []
        var types: Set<String> = []
        var files: Set<String> = []
        for node in nodes where node["mode"] as? Int != 4 && node["mode"] as? Int != 2 {
            if let type = node["type"] as? String, !inner.contains(type) { types.insert(type) }
            // Community workflows rarely declare their models; the loaders'
            // values name them all the same.
            let values = node["widgets_values"] as? [Any] ?? Array((node["widgets_values"] as? [String: Any] ?? [:]).values)
            files.formUnion(values.compactMap(isModelFile))
            for m in (node["properties"] as? [String: Any])?["models"] as? [[String: Any]] ?? [] {
                guard let name = m["name"] as? String, let dir = m["directory"] as? String else { continue }
                let item = Missing(name: name, directory: dir, url: m["url"] as? String ?? "")
                if !models.contains(item) { models.append(item) }
            }
        }
        return (models, types, files.subtracting(models.map(\.name)))
    }

    /// Nodes that exist only in the editor, never on the server.
    private static let frontendOnly: Set<String> = ["Note", "MarkdownNote", "Reroute", "PrimitiveNode", "Comment", "Label"]

    private var modelFiles: [String: Set<String>] = [:]
    private var nodeTypes: Set<String>?
    /// Every file name any loader on the server can choose, from /object_info.
    private var choosable: Set<String> = []

    private func files(in dir: String) async -> Set<String>? {
        if let known = modelFiles[dir] { return known }
        guard let url = URL(string: Self.base + "/models/" + dir),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let names = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return nil }
        let set = Set(names.map { ($0 as NSString).lastPathComponent })
        modelFiles[dir] = set
        return set
    }

    private func knownNodes() async -> Set<String>? {
        if let known = nodeTypes { return known }
        guard let url = URL(string: Self.base + "/object_info"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        nodeTypes = Set(info.keys)
        var names: Set<String> = []
        for case let node as [String: Any] in info.values {
            let input = node["input"] as? [String: Any] ?? [:]
            for section in ["required", "optional"] {
                for case let spec as [Any] in (input[section] as? [String: Any] ?? [:]).values {
                    for case let option as String in spec.first as? [Any] ?? [] where Self.isModelFile(option) != nil {
                        names.insert(option)
                        names.insert((option as NSString).lastPathComponent)
                    }
                }
            }
        }
        choosable = names
        return nodeTypes
    }

    /// "dir/name" → bytes on disk, for files shorter than their own header
    /// says they are. A download that broke off leaves one of these under the
    /// final name (curl -o writes there as it goes), which a listing of names
    /// counts as present and ComfyUI cannot load.
    private var truncated: [String: Int64] = [:]

    private func verify(_ models: [Missing]) async {
        var present: [Missing] = []
        for m in models where m.name.hasSuffix(".safetensors") {
            if let have = await files(in: m.directory), have.contains(m.name) { present.append(m) }
        }
        for m in present { truncated[m.id] = nil }
        guard !present.isEmpty else { return }
        let list = present.map { "'\(Self.shellSafe($0.directory))/\(Self.shellSafe($0.name))'" }.joined(separator: " ")
        let (code, output) = await BoxServices.run("""
            cd ~/ComfyUI/models && python3 - \(list) <<'PY'
            import json, os, struct, sys
            for rel in sys.argv[1:]:
                try:
                    size = os.path.getsize(rel)
                    with open(rel, "rb") as f:
                        n = struct.unpack("<Q", f.read(8))[0]
                        head = json.loads(f.read(n))
                    need = 8 + n + max([v["data_offsets"][1] for k, v in head.items() if k != "__metadata__"] or [0])
                    if size < need: print(rel + "\t" + str(size))
                except Exception:
                    print(rel + "\t" + str(os.path.getsize(rel) if os.path.exists(rel) else 0))
            PY
            """)
        guard code == 0 else { return }
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count == 2, let bytes = Int64(parts[1]) { truncated[String(parts[0])] = bytes }
        }
    }

    private func lacking(_ needs: Needs, verifying: Bool = true) async -> (models: [Missing], nodes: [String]) {
        if verifying { await verify(needs.models) }
        var gone: [Missing] = []
        for model in needs.models {
            if let have = await files(in: model.directory), !have.contains(model.name) {
                gone.append(model)
            } else if let bytes = truncated[model.id] {
                var half = model
                half.partial = bytes
                gone.append(half)
            }
        }
        var nodes: [String] = []
        if let known = await knownNodes() {
            nodes = needs.types.subtracting(known).subtracting(Self.frontendOnly).sorted()
            // Files named by value only: no folder, no link — missing, and said so.
            for file in needs.files.sorted() where !choosable.contains(file) && !choosable.contains((file as NSString).lastPathComponent) {
                gone.append(Missing(name: (file as NSString).lastPathComponent, directory: "?", url: ""))
            }
        }
        return (gone, nodes)
    }

    /// Which templates can run on the box as it is. Every local template's
    /// graph is read (about 240, five seconds on the LAN) — the index only
    /// names the models for people, not the files.
    func scan() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        modelFiles = [:]
        nodeTypes = nil
        _ = await knownNodes()
        let base = Self.base
        let names = templates.filter(\.local).map(\.name)
        var needs: [String: Needs] = [:]
        await withTaskGroup(of: (String, Needs?).self) { group in
            for name in names {
                group.addTask {
                    guard let url = URL(string: base + "/templates/\(name).json"),
                          let (data, _) = try? await URLSession.shared.data(from: url) else { return (name, nil) }
                    return (name, Self.requirements(of: data))
                }
            }
            for await (name, need) in group { if let need { needs[name] = need } }
        }
        for t in saved {
            if let file = t.saved, let data = try? Data(contentsOf: file), let need = Self.requirements(of: data) { needs[t.name] = need }
        }
        var every: [Missing] = []
        for need in needs.values { for m in need.models where !every.contains(m) { every.append(m) } }
        await verify(every)
        var result: [String: Readiness] = [:]
        for (name, need) in needs {
            let gone = await lacking(need, verifying: false)
            result[name] = Readiness(models: need.models.count + need.files.count, lacking: gone.models.count, nodes: gone.nodes)
        }
        readiness = result
    }

    /// For the open workflow: what is missing, with sizes, for the banner.
    private func checkModels(in workflow: Data, for mine: Int) async {
        guard let needs = Self.requirements(of: workflow) else { return }
        modelFiles = [:]
        var gone = await lacking(needs)
        for i in gone.models.indices { gone.models[i].bytes = await Self.size(of: gone.models[i].url) }
        let found = await Self.findOnBox(gone.models.map(\.name))
        for i in gone.models.indices where gone.models[i].directory != "?" { gone.models[i].onBox = found[gone.models[i].name] }
        guard opening == mine else { return }
        missing = gone.models
        missingNodes = gone.nodes
    }

    private static func size(of address: String) async -> Int64? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let length = http.expectedContentLength
        return length > 0 ? length : nil
    }

    /// Where other programs on the box keep model files. ollamadiffuser's own
    /// models are MLX conversions ComfyUI cannot read, but what it keeps in
    /// the original format (the LTX LoRAs) and whatever Hugging Face's cache
    /// holds as single files, ComfyUI can use as they are.
    private static let elsewhere = ["~/.ollamadiffuser/models", "~/.cache/huggingface/hub"]

    /// Same-named files already on the box, by name → real path.
    private static func findOnBox(_ names: [String]) async -> [String: String] {
        let wanted = names.map(shellSafe).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return [:] }
        let test = wanted.map { "-name \"\($0)\"" }.joined(separator: " -o ")
        let (code, output) = await BoxServices.run(
            "find -L \(elsewhere.joined(separator: " ")) -type f \\( \(test) \\) 2>/dev/null | head -50 | while read f; do realpath \"$f\"; done")
        guard code == 0 else { return [:] }
        var found: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let path = String(line)
            let name = (path as NSString).lastPathComponent
            if found[name] == nil { found[name] = path }
        }
        return found
    }

    /// Get a missing model onto the box — only ever after the person said yes
    /// to its name and size. Linked if the box already has it elsewhere;
    /// otherwise the box downloads it itself (nothing passes through this
    /// Mac), resuming a partial file, with the box's own Hugging Face login
    /// for gated repos — read there, never sent here.
    func fetch(_ model: Missing) async {
        guard fetching[model.id] == nil else { return }
        let dir = Self.shellSafe(model.directory), name = Self.shellSafe(model.name), url = Self.shellSafe(model.url)
        guard !dir.isEmpty, !name.isEmpty else { return }
        if let path = model.onBox.map(Self.shellSafe) {
            fetching[model.id] = "链接"
            let (code, output) = await BoxServices.run(
                "mkdir -p ~/ComfyUI/models/\(dir) && ln -sfn \"\(path)\" ~/ComfyUI/models/\(dir)/\"\(name)\" && echo ok")
            fetching[model.id] = nil
            guard code == 0 else { note = "链接不上：\(output.suffix(160))"; return }
            await arrived(model)
            return
        }
        guard url.hasPrefix("https://") else { note = "\(model.name) 没有下载地址"; return }
        fetching[model.id] = "开始"
        if let bytes = model.bytes.map({ $0 - (model.partial ?? 0) }), let free = await boxFreeBytes(), free < bytes + 5_000_000_000 {
            fetching[model.id] = nil
            note = "盒子上只剩 \(Self.gigabytes(free))，放不下 \(model.name)（\(Self.gigabytes(bytes))）"
            return
        }
        let log = "~/Library/Logs/kinclaw/comfy-get-\(name).log"
        // A file cut off part way is carried on from where it stopped: moved
        // back to .part, which curl -C - resumes.
        let resume = model.partial != nil ? "[ -f \"\(name)\" ] && mv -f \"\(name)\" \"\(name).part\"; " : ""
        let (code, output) = await BoxServices.run("""
            mkdir -p ~/ComfyUI/models/\(dir) ~/Library/Logs/kinclaw; cd ~/ComfyUI/models/\(dir); \(resume)\
            case "\(url)" in https://huggingface.co/*) HF_T=$(cat ~/.cache/huggingface/token 2>/dev/null);; *) HF_T="";; esac; \
            HF_T="$HF_T" nohup sh -c 'curl -fL --retry 3 -C - ${HF_T:+-H "Authorization: Bearer $HF_T"} -o "\(name).part" "\(url)" && mv "\(name).part" "\(name)"' \
            > \(log) 2>&1 & echo started
            """)
        guard code == 0 else { fetching[model.id] = nil; note = "下载起不来：\(output.suffix(160))"; return }
        while true {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let (_, state) = await BoxServices.run("""
                cd ~/ComfyUI/models/\(dir); if [ -f "\(name)" ]; then echo done; \
                elif pgrep -f "\(name).part" >/dev/null; then stat -f %z "\(name).part" 2>/dev/null || echo 0; \
                else echo failed; tail -c 200 \(log); fi
                """)
            let answer = state.trimmingCharacters(in: .whitespacesAndNewlines)
            if answer == "done" {
                fetching[model.id] = nil
                await arrived(model)
                return
            }
            if answer.hasPrefix("failed") {
                fetching[model.id] = nil
                let gated = answer.contains("403") || answer.contains("401")
                note = "\(model.name) 没下下来\(gated ? "：要先在 Hugging Face 上点同意（盒子上登录的那个账号）" : "")：\(answer.dropFirst(6).suffix(160))"
                return
            }
            if let got = Int64(answer) {
                fetching[model.id] = model.bytes.map { "\(got * 100 / max($0, 1))%" } ?? Self.gigabytes(got)
            }
        }
    }

    /// Everything the open workflow lacks, one after another.
    func fetchAll() async {
        for model in missing where fetching[model.id] == nil { await fetch(model) }
    }

    /// A model landed: the open workflow's lists and the readiness badges
    /// learn about it, and so does the page (its dropdowns were read before).
    private func arrived(_ model: Missing) async {
        missing.removeAll { $0.id == model.id }
        truncated[model.id] = nil
        _ = try? await js("if (window.app && window.app.refreshComboInNodes) await window.app.refreshComboInNodes(); return 'ok';")
        await scan()
    }

    @Published private(set) var boxFree: Int64?

    func boxFreeBytes() async -> Int64? {
        let (code, output) = await BoxServices.run("df -k ~ | tail -1 | awk '{print $4}'")
        guard code == 0, let kb = Int64(output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        boxFree = kb * 1024
        return boxFree
    }

    // MARK: - Pulling any model

    /// ComfyUI's model folders, as the server lists them.
    func folders() async -> [String] {
        guard let url = URL(string: Self.base + "/models"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let names = (try? JSONSerialization.jsonObject(with: data)) as? [String] else {
            return ["checkpoints", "diffusion_models", "text_encoders", "vae", "loras", "upscale_models", "controlnet", "clip_vision"]
        }
        return names.filter { !["custom_nodes", "configs"].contains($0) }
    }

    /// A Hugging Face file link, understood: the direct address, the file's
    /// name, and the folder it most likely goes in. Comfy-Org's repos keep
    /// their files in folders named after ComfyUI's, so the path usually says.
    static func understand(_ link: String, folders: [String]) -> (url: String, name: String, folder: String)? {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "/blob/", with: "/resolve/")
        if text.hasSuffix("?download=true") { text = String(text.dropLast("?download=true".count)) }
        guard let url = URL(string: text), url.scheme == "https", url.pathExtension.count > 1 else { return nil }
        let name = url.lastPathComponent
        let parts = url.pathComponents.map { $0.lowercased() }
        if let hit = parts.dropLast().last(where: { folders.contains($0) }) { return (text, name, hit) }
        let lower = name.lowercased()
        let folder = lower.contains("lora") ? "loras"
            : lower.contains("vae") ? "vae"
            : ["clip", "t5", "umt5", "text_encoder", "qwen_2.5_vl", "qwen3", "gemma", "llava"].contains(where: lower.contains) ? "text_encoders"
            : lower.contains("upscal") || lower.contains("esrgan") ? "upscale_models"
            : lower.contains("controlnet") ? "controlnet"
            : "diffusion_models"
        return (text, name, folders.contains(folder) ? folder : "checkpoints")
    }

    /// Size of a file on Hugging Face, when it is public. Gated ones answer
    /// 401 to this Mac, which has no login — the box has, and downloads anyway.
    static func sizeOf(_ address: String) async -> Int64? { await size(of: address) }

    /// Pull one model the person named, into the folder they chose.
    func pull(_ link: String, into folder: String) async {
        guard let known = Self.understand(link, folders: [folder]) else { note = "看不懂这个链接：要指向一个模型文件"; return }
        var model = Missing(name: known.name, directory: folder, url: known.url)
        model.bytes = await Self.size(of: known.url)
        model.onBox = await Self.findOnBox([known.name])[known.name]
        if let have = await files(in: folder), have.contains(known.name) { note = "盒子上已经有 \(folder)/\(known.name)"; return }
        pulls.append(model)
        await fetch(model)
        pulls.removeAll { $0.id == model.id }
        modelFiles[folder] = nil
        if let have = await files(in: folder), have.contains(known.name) { note = "拉好了：\(folder)/\(known.name)" }
    }

    /// Models being pulled by name, not for the open workflow.
    @Published private(set) var pulls: [Missing] = []

    // MARK: - Running

    var busyElsewhere: String? {
        if let film = FilmStudio.shared.shooting { return "Film 在拍「\(film)」，盒子的内存在它那里" }
        if MotionStudio.shared.working != nil { return "Motion 在拍，盒子的内存在它那里" }
        return nil
    }

    var running: Bool { work != nil }

    func template(named name: String) -> Template? {
        saved.first { $0.name == name } ?? templates.first { $0.name == name }
            ?? templates.first { $0.title == name } ?? saved.first { $0.title == name }
    }

    /// Why the open workflow cannot run as it stands, if it cannot.
    var blocked: String? {
        let inputs = fields.filter(\.needsInput)
        if !inputs.isEmpty {
            return "先给这些换上你的文件（现在是模板的示例，盒子上没有）：" + inputs.map { "\($0.nodeTitle) · \($0.name)" }.joined(separator: "、")
        }
        if !missingNodes.isEmpty {
            return "盒子上的 ComfyUI 没有这些节点（社区插件）：\(missingNodes.prefix(6).joined(separator: "、"))\(missingNodes.count > 6 ? " 等 \(missingNodes.count) 个" : "")。要先在盒子上装对应的 custom_nodes"
        }
        if !missing.isEmpty { return "盒子上缺 \(missing.count) 个模型，先下载" }
        return nil
    }

    /// `keepSeed`: keep the seeds that are in the form for this run — an agent
    /// that set one meant it; nil follows the tab's 固定 box.
    func run(keepSeed keep: Bool? = nil) {
        guard work == nil, current != nil else { return }
        if let busy = busyElsewhere { note = busy + "。等它拍完再跑"; return }
        if let why = blocked { note = why; return }
        work = Task { @MainActor in
            await self.perform(keepSeed: keep ?? self.keepSeed)
            self.work = nil
        }
    }

    private func perform(keepSeed: Bool) async {
        guard let template = current else { return }
        working = "准备"
        since = Date()
        progress = nil
        note = nil
        defer { working = nil; progress = nil; promptID = nil }
        // The diffusion servers the Film tab uses hold their models once they
        // have drawn; ComfyUI loads its own copy. Both at once is how a 64 GB
        // box swaps. They come back by themselves the next time a film needs them.
        for kind in [BoxServices.Kind.draw, .edit] where BoxServices.shared.states[kind] == .up {
            working = "先让出画图服务的内存"
            await BoxServices.shared.stop(kind)
        }
        guard await page() else { return }
        await pushAll()
        if !keepSeed {
            for field in fields where field.isSeed {
                await set(field, to: String(UInt64.random(in: 0..<(1 << 48))))
            }
        }
        working = "交给 ComfyUI"
        guard let prompt = try? await js("const p = await window.app.graphToPrompt(); return JSON.stringify(p.output);"),
              let graph = try? await js("return JSON.stringify(window.app.graph.serialize());"),
              let output = try? JSONSerialization.jsonObject(with: Data(prompt.utf8)),
              let url = URL(string: Self.base + "/prompt") else { note = "工作流转不成 ComfyUI 能跑的样子"; return }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": output, "client_id": client])
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { note = "ComfyUI 没应答"; return }
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let id = answer["prompt_id"] as? String else {
            note = "ComfyUI 不接：" + Self.explain(answer)
            return
        }
        promptID = id
        working = "在跑"
        let socket = watch(id)
        defer { socket?.cancel(with: .normalClosure, reason: nil) }
        // Done when the history has it. Video workflows run for many minutes.
        var outputs: [[String: Any]] = []
        var status = ""
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let hurl = URL(string: Self.base + "/history/\(id)"),
                  let (hdata, _) = try? await URLSession.shared.data(from: hurl),
                  let history = (try? JSONSerialization.jsonObject(with: hdata)) as? [String: Any],
                  let entry = history[id] as? [String: Any] else { continue }
            let state = entry["status"] as? [String: Any]
            status = state?["status_str"] as? String ?? ""
            guard state?["completed"] as? Bool == true || status == "error" else { continue }
            for (_, node) in entry["outputs"] as? [String: Any] ?? [:] {
                for (_, list) in node as? [String: Any] ?? [:] {
                    for item in list as? [[String: Any]] ?? [] where item["filename"] != nil { outputs.append(item) }
                }
            }
            if status == "error" {
                let messages = (state?["messages"] as? [[Any]] ?? []).compactMap { $0.count > 1 ? $0[1] as? [String: Any] : nil }
                let error = messages.compactMap { $0["exception_message"] as? String }.first ?? "看盒子上的 ~/Library/Logs/kinclaw/comfy.log"
                note = "ComfyUI 跑出错了：" + error.prefix(300)
            }
            break
        }
        if Task.isCancelled { note = "停下了"; return }
        // What was saved, not the previews along the way — unless previews are all there is.
        let saved = outputs.filter { $0["type"] as? String == "output" }
        let keep = saved.isEmpty ? outputs : saved
        working = "取回来"
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let folder = Self.root.appendingPathComponent("\(stamp)-\(template.name)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(graph.utf8).write(to: folder.appendingPathComponent("workflow.json"))
        try? Data(prompt.utf8).write(to: folder.appendingPathComponent("prompt.json"))
        var files: [URL] = []
        for item in keep {
            guard let name = item["filename"] as? String else { continue }
            var parts = URLComponents(string: Self.base + "/view")
            parts?.queryItems = [URLQueryItem(name: "filename", value: name),
                                 URLQueryItem(name: "subfolder", value: item["subfolder"] as? String ?? ""),
                                 URLQueryItem(name: "type", value: item["type"] as? String ?? "output")]
            guard let url = parts?.url, let (bytes, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, !bytes.isEmpty else { continue }
            let file = folder.appendingPathComponent((name as NSString).lastPathComponent)
            if (try? bytes.write(to: file)) != nil { files.append(file) }
        }
        let seconds = Int(Date().timeIntervalSince(since ?? Date()))
        let meta: [String: Any] = ["template": template.name, "title": template.title, "seconds": seconds, "status": status,
                                   "fields": fields.map { ["node": $0.node, "name": $0.name, "value": $0.value] }]
        if let json = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: folder.appendingPathComponent("run.json"))
        }
        if files.isEmpty {
            if note == nil { note = "跑完了，但没有拿到输出（这个工作流可能只预览不保存）" }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("prompt.json"))
        } else {
            note = "好了：\(files.count) 个文件，\(seconds) 秒"
        }
        loadRuns()
    }

    /// Step-by-step progress from ComfyUI's websocket. Only for the bar — the
    /// history is what says it is finished.
    private func watch(_ id: String) -> URLSessionWebSocketTask? {
        guard var parts = URLComponents(string: Self.base + "/ws") else { return nil }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.queryItems = [URLQueryItem(name: "clientId", value: client)]
        guard let url = parts.url else { return nil }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        func next() {
            socket.receive { [weak self] result in
                guard case .success(let message) = result else { return }
                if case .string(let text) = message,
                   let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
                   let data = object["data"] as? [String: Any], data["prompt_id"] as? String == id {
                    let type = object["type"] as? String
                    Task { @MainActor in
                        guard let self else { return }
                        if type == "progress", let value = (data["value"] as? NSNumber)?.doubleValue,
                           let max = (data["max"] as? NSNumber)?.doubleValue, max > 0 {
                            self.progress = value / max
                        } else if type == "executing", let node = data["node"] as? String,
                                  let title = self.fields.first(where: { $0.node == node.split(separator: ":").first.map(String.init) })?.nodeTitle {
                            self.working = "在跑 · \(title)"
                        }
                    }
                }
                next()
            }
        }
        next()
        return socket
    }

    func stop() {
        guard work != nil else { return }
        work?.cancel()
        Task {
            if let url = URL(string: Self.base + "/interrupt") {
                var request = URLRequest(url: url, timeoutInterval: 5)
                request.httpMethod = "POST"
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

    /// Have ComfyUI let go of the models it is holding, for the Film and
    /// Motion tabs about to need the memory. Quietly nothing when it is not running.
    nonisolated static func yieldMemory() async {
        guard let url = await URL(string: base + "/free") else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"unload_models": true, "free_memory": true}"#.utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Importing

    /// A workflow from somewhere else — a .json, or a picture ComfyUI made
    /// (it writes the graph into the PNG) — kept in 我的.
    func importWorkflow(from file: URL) async {
        guard let data = try? Data(contentsOf: file) else { note = "读不了 \(file.lastPathComponent)"; return }
        await keep(data, named: file.deletingPathExtension().lastPathComponent)
    }

    /// Same, from a link to a .json or a .png (GitHub raw, ComfyUI's example pages).
    func importWorkflow(from link: String) async {
        let address = link.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "://github.com/", with: "://raw.githubusercontent.com/")
            .replacingOccurrences(of: "/blob/", with: "/")
        guard let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { note = "这不是一个网址"; return }
        working = "下载工作流"
        defer { working = nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { note = "下不来：\(address)"; return }
        let name = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "导入的工作流"
        await keep(data, named: name)
    }

    private func keep(_ data: Data, named name: String) async {
        let graph: Data
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            guard let text = Self.pngText(data, key: "workflow") ?? Self.pngText(data, key: "prompt") else {
                note = "这张图里没有 ComfyUI 的工作流"; return
            }
            graph = Data(text.utf8)
        } else {
            graph = data
        }
        guard let object = (try? JSONSerialization.jsonObject(with: graph)) as? [String: Any], !object.isEmpty else {
            note = "看不懂：不是 ComfyUI 的工作流 JSON（网页的话要直接指向 .json 文件）"; return
        }
        try? FileManager.default.createDirectory(at: Self.savedFolder, withIntermediateDirectories: true)
        var file = Self.savedFolder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-") + ".json")
        var n = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = Self.savedFolder.appendingPathComponent("\(name) \(n).json"); n += 1
        }
        try? graph.write(to: file)
        loadSaved()
        if let t = saved.first(where: { $0.saved == file }) {
            await open(t)
            if let need = Self.requirements(of: graph) {
                let gone = await lacking(need)
                readiness[t.name] = Readiness(models: need.models.count + need.files.count, lacking: gone.models.count, nodes: gone.nodes)
            }
        }
    }

    /// A tEXt or iTXt chunk of a PNG, by keyword.
    private static func pngText(_ data: Data, key: String) -> String? {
        let bytes = [UInt8](data)
        var i = 8
        while i + 8 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            let type = String(bytes: bytes[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            let start = i + 8, end = start + length
            guard end <= bytes.count else { return nil }
            if type == "tEXt" || type == "iTXt", let zero = bytes[start..<end].firstIndex(of: 0),
               String(bytes: bytes[start..<zero], encoding: .isoLatin1) == key {
                var body = zero + 1
                if type == "iTXt" {
                    // compression flag, method, language tag \0, translated keyword \0
                    guard bytes[body] == 0 else { return nil }
                    body += 2
                    for _ in 0..<2 { if let z = bytes[body..<end].firstIndex(of: 0) { body = z + 1 } }
                }
                return String(bytes: bytes[body..<end], encoding: type == "iTXt" ? .utf8 : .isoLatin1)
            }
            if type == "IEND" { return nil }
            i = end + 4
        }
        return nil
    }

    // MARK: - Saving and past runs

    func save(as name: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, await page(), let graph = try? await js("return JSON.stringify(window.app.graph.serialize());") else { return }
        try? FileManager.default.createDirectory(at: Self.savedFolder, withIntermediateDirectories: true)
        let file = Self.savedFolder.appendingPathComponent(clean + ".json")
        try? Data(graph.utf8).write(to: file)
        loadSaved()
        current = saved.first { $0.saved == file } ?? current
        note = "存好了：我的 → \(clean)"
    }

    func loadRuns() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? []
        runs = folders.filter { folder in
            !["workflows", "guides"].contains(folder.lastPathComponent)
                && (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.compactMap { folder in
            let outputs = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { !["json"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !outputs.isEmpty else { return nil }
            let meta = (try? Data(contentsOf: folder.appendingPathComponent("run.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let when = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return Run(folder: folder, title: meta?["title"] as? String ?? folder.lastPathComponent, when: when, outputs: outputs)
        }.sorted { $0.when > $1.when }
    }

    /// Open a past run's exact graph again, to run it with a change.
    func reopen(_ run: Run) async {
        let file = run.folder.appendingPathComponent("workflow.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        await open(Template(name: run.folder.lastPathComponent, title: run.title, description: "上次跑的", category: "作品",
                            mediaType: "image", mediaSubtype: "png", tags: [], models: [], size: nil, local: true, saved: file))
    }

    // MARK: - Words

    /// With a workflow open: change what the words ask for, and only that.
    /// With none open: find the template that does it, open it, then change it.
    /// Nil when it was done; else why not — an agent that asked is told,
    /// instead of the template running as it was.
    @discardableResult
    func ask(_ words: String) async -> String? {
        let wish = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wish.isEmpty else { return nil }
        if let busy = working { return "Comfy 正在\(busy)，等它做完" }
        if current == nil {
            working = "找合适的工作流"
            defer { working = nil }
            if templates.isEmpty { await refresh() }
            guard let pick = await choose(for: wish) else { if note == nil { note = "没找到合适的模板" }; return note }
            working = nil
            await open(pick)
            guard current != nil else { return note ?? "找到的模板打不开" }
        }
        working = "按你说的改"
        defer { working = nil }
        return await adjust(wish)
    }

    private func choose(for wish: String) async -> Template? {
        let usable = templates.filter(\.local)
        let menu = usable.map { "\($0.name) | \($0.title) | \($0.description.prefix(90))" }.joined(separator: "\n")
        let ask = """
            Someone wants this from ComfyUI: "\(wish)"
            These workflows run on their machine (name | title | what it does):
            \(menu)

            Pick the ONE that best does what they want. Prefer one whose models match what they named, if they named any. \
            Answer with JSON only: {"name": "...", "why": "one short sentence in the language they wrote in"}
            """
        guard let said = await Self.write(ask),
              let object = Self.jsonObject(in: said), let name = object["name"] as? String,
              let pick = usable.first(where: { $0.name == name }) else { return nil }
        note = "选了「\(pick.title)」" + ((object["why"] as? String).map { "：\($0)" } ?? "")
        return pick
    }

    @discardableResult
    private func adjust(_ wish: String) async -> String? {
        let list = fields.map { f -> String in
            var line = "{\"node\": \"\(f.node)\", \"in\": \(Self.quoted(f.nodeTitle)), \"name\": \(Self.quoted(f.name)), \"kind\": \"\(f.kind)\", \"value\": \(Self.quoted(String(f.value.prefix(1500))))"
            if let options = f.options { line += ", \"choices\": \(Self.quoted(options.prefix(40).joined(separator: " | ")))" }
            if let min = f.min, let max = f.max { line += ", \"range\": [\(min), \(max)]" }
            return line + "}"
        }.joined(separator: ",\n")
        let guide = notes.joined(separator: "\n---\n").prefix(3000)
        let official = await officialGuide()
        let ask = """
            A ComfyUI workflow, "\(current?.title ?? "")", is open. Its settings:
            [\(list)]
            \(guide.isEmpty ? "" : "The workflow author's notes:\n\(guide)\n")
            \(official.map { "The model maker's official prompt guide — write every prompt field in exactly the structure it describes (its field names, section order, labels and timing notation), matching the video's length:\n<<<\n\($0)\n>>>\n" } ?? "")
            The person says: "\(wish)"

            Change only what that asks for. When they describe a picture or a video, write the prompt the way this model \
            wants it: \(official == nil ? "in English unless the notes say otherwise, dense and concrete — subject and its materials, what is behind it, the light and its direction, the lens and framing, the grade" : "following the official guide above, concrete rather than abstract"). For sizes use values the notes \
            recommend. For choices use one of the listed choices exactly. Leave model file names alone.
            When they give a length, a size, a count or a shape, find the setting that holds it (a duration in \
            seconds, a frame count, an aspect ratio, a width) and set it there too — saying it in the prompt is not enough.
            The pictures, videos and sounds the workflow starts from are the person's, and you cannot see them. The \
            prompt that is there now was written for the template's sample inputs: do not keep anything it says about \
            what is in them. Refer to an input by its label (<Picture 1>, <Video 1>, …) and describe only what they told you.
            Answer with JSON only: {"changes": [{"node": "...", "name": "...", "value": "..."}], \
            "say": "one short sentence, in the language they wrote in, of what you changed"}
            """
        guard let said = await Self.write(ask), let object = Self.jsonObject(in: said) else { note = "写手模型没回答"; return note }
        var changed = 0
        for change in object["changes"] as? [[String: Any]] ?? [] {
            guard let node = change["node"].map({ "\($0)" }), let name = change["name"] as? String,
                  let field = fields.first(where: { $0.node == node && $0.name == name }),
                  let raw = change["value"] else { continue }
            let value = raw as? String ?? "\(raw)"
            if let options = field.options, !options.contains(value) { continue }
            await set(field, to: value)
            changed += 1
        }
        note = (object["say"] as? String ?? "改了 \(changed) 处") + (changed == 0 ? "（其实没改动）" : "")
        return nil
    }

    /// Some model makers publish how their model wants to be prompted. When
    /// the open workflow runs one of those models, the guide is fetched from
    /// where the maker publishes it (and kept, so it is fetched once) and given
    /// to the writer. Fetched, not shipped: it is theirs, and theirs to update.
    private static let guides: [(model: String, pick: (String) -> String)] = [
        // MiniMax H3: one guide for text / first frame / first-and-last frame,
        // another for the full-reference mode.
        ("h3", { name in
            let base = "https://raw.githubusercontent.com/MiniMax-AI/MiniMax-H3/main/skills/h3-prompt-writing/references/"
            return base + (name.contains("r2v") || name.contains("reference") ? "ref-en.txt" : "base-en.txt")
        }),
    ]

    private func officialGuide() async -> String? {
        guard let template = current else { return nil }
        let models = (template.models + fields.filter { $0.kind == "combo" && $0.name.hasSuffix("_name") }.map(\.value))
            .joined(separator: " ").lowercased()
        guard let entry = Self.guides.first(where: { models.contains($0.model) || template.name.lowercased().contains($0.model) }),
              let url = URL(string: entry.pick(template.name.lowercased())) else { return nil }
        let cache = Self.root.appendingPathComponent("guides").appendingPathComponent(url.lastPathComponent)
        if let kept = try? String(contentsOf: cache, encoding: .utf8), !kept.isEmpty { return kept }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else { return nil }
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cache)
        return text
    }

    /// Re-fetch the official guides next time (they are updated upstream).
    func forgetGuides() {
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent("guides"))
    }

    private static func write(_ ask: String) async -> String? {
        guard let writer = await FilmStudio.writer(claude: true), let url = URL(string: writer.host + "/api/chat") else { return nil }
        let body: [String: Any] = ["model": writer.model, "stream": false, "think": false,
                                   "messages": [["role": "user", "content": ask]]]
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (reply["message"] as? [String: Any])?["content"] as? String
    }

    // MARK: - Small things

    private static func jsonObject(in text: String) -> [String: Any]? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8))) as? [String: Any]
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }

    private static func jsList(_ items: [String]) -> String {
        "[" + items.map { quoted($0) }.joined(separator: ",") + "]"
    }

    /// Names and addresses go into a shell on the box, inside double quotes.
    private static func shellSafe(_ text: String) -> String {
        text.filter { !"\"'`$\\;&|<>\n".contains($0) }
    }

    /// What ComfyUI's refusal of a prompt says, readably.
    private static func explain(_ answer: [String: Any]) -> String {
        var parts: [String] = []
        if let error = answer["error"] as? [String: Any] {
            parts.append((error["message"] as? String ?? "") + ((error["details"] as? String).map { "：\($0)" } ?? ""))
        }
        for (_, node) in answer["node_errors"] as? [String: Any] ?? [:] {
            guard let node = node as? [String: Any] else { continue }
            let kind = node["class_type"] as? String ?? ""
            for e in node["errors"] as? [[String: Any]] ?? [] {
                parts.append("\(kind)：\(e["message"] as? String ?? "") \(e["details"] as? String ?? "")")
            }
        }
        return parts.isEmpty ? "说不出原因" : parts.joined(separator: "\n").prefix(600).description
    }

    static func gigabytes(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000 ? String(format: "%.1f GB", Double(bytes) / 1e9) : String(format: "%.0f MB", Double(bytes) / 1e6)
    }
}
