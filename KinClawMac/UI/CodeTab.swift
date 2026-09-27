import AppKit
import SwiftUI

/// The Code tab: Claude Code and Codex, the general agents, each conversation
/// in its own terminal ("term 标签改名为 code，然后里面就是现在 claude code 和
/// codex 就是通用 agent").
///
/// Along the left, every conversation the two keep on this Mac — the Claude
/// desktop app's too — newest first: one clicked is gone back into here, and
/// carries on as it would there ("我可以在那里操作和这里一样"). They think with
/// Claude Code's own sign-in, the Claude subscription, unless told otherwise;
/// a session's brain can be changed while it runs — to a model on this Mac or
/// the box, when the plan has run out — and the conversation goes on under the
/// new one ("等到我的 plan 上线到了我还可以换模型在那里操作").
///
/// The sessions and their terminals are AgentTerminalSessions', not this
/// view's: a conversation keeps running with the tab out of sight, and comes
/// back — resumed from its file — when the app is opened again.
struct CodeTab: View {
    @ObservedObject private var sessions = AgentTerminalSessions.shared
    @ObservedObject private var history = CodeHistory.shared

    @AppStorage("kinclaw.code.harness") private var harnessRaw = AgentHarness.claude.rawValue
    @AppStorage("kinclaw.code.brain") private var brainRaw = ""
    @AppStorage("kinclaw.code.folder") private var folderRaw = ""
    /// The folders whose groups are folded shut, one path a line.
    @AppStorage("kinclaw.code.folded") private var foldedRaw = ""

    @State private var search = ""
    /// Groups showing every conversation, not just their latest few.
    @State private var unfolded: Set<String> = []
    /// Narrow, the list and a conversation take turns: this is the list's.
    @State private var listing = false

    private typealias Session = AgentTerminalSessions.Session

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 620
            let listFirst = listing || sessions.selectedCode == nil
            HStack(spacing: 0) {
                if wide || listFirst {
                    sidebar(wide: wide)
                        .frame(width: wide ? min(300, max(230, geo.size.width * 0.3)) : geo.size.width)
                    if wide { Rectangle().fill(Theme.hairline).frame(width: 0.5) }
                }
                if wide || !listFirst {
                    detail(wide: wide)
                }
            }
        }
        .task {
            // The list keeps up with conversations going on elsewhere: a stat
            // of each file, and a read of only the ones that changed.
            while !Task.isCancelled {
                history.refresh()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    // MARK: The defaults for new sessions

    private var harness: AgentHarness {
        let chosen = AgentHarness(rawValue: harnessRaw) ?? .claude
        return chosen.binary != nil ? chosen : (AgentHarness.allCases.first { $0.binary != nil } ?? .claude)
    }

    private var brain: AgentBrain {
        guard let data = brainRaw.data(using: .utf8), let saved = try? JSONDecoder().decode(AgentBrain.self, from: data) else {
            return .account
        }
        return saved
    }

    private func setBrain(_ new: AgentBrain) {
        brainRaw = (try? JSONEncoder().encode(new)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Where a new session starts: the folder picked for them, else the one
    /// the latest conversation was in.
    private var folder: String {
        if !folderRaw.isEmpty, FileManager.default.fileExists(atPath: folderRaw) { return folderRaw }
        return history.items.first?.folder ?? NSHomeDirectory()
    }

    /// The folders conversations were had in, latest first.
    private var recentFolders: [String] {
        var out: [String] = []
        for path in [folder] + history.items.map(\.folder) where !out.contains(path) {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            out.append(path)
            if out.count == 10 { break }
        }
        return out
    }

    // MARK: The list

    private func sidebar(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Button {
                    sessions.newCode(harness, brain: brain, folder: folder)
                    listing = false
                } label: {
                    Label("新会话", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .help("在「\(short(folder))」里开一个新的 \(harness.title)，用 \(brain.title(for: harness))")
                FlowLayout(spacing: 6) {
                    HarnessMenu(harness: harness, help: "新会话用哪个 agent") { harnessRaw = $0.rawValue }
                    folderMenu
                    BrainMenu(harness: harness, brain: brain,
                              help: "新会话、和从下面接着的会话，用哪个模型想事情。默认是这台 Mac 上 Claude Code 登录的订阅；开着的会话在它自己上面换") { setBrain($0) }
                }
                searchField
            }
            .padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    let list = groups
                    if list.isEmpty {
                        Text(!searching ? (history.loading ? "在读…" : "还没有 Claude Code 或 Codex 的会话") : "没有对得上「\(search)」的")
                            .font(.kinCaption).foregroundStyle(.secondary).padding(.horizontal, 6)
                    }
                    ForEach(list) { group in folderSection(group) }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
        .background(Theme.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("找会话：名字或文件夹", text: $search)
                .textFieldStyle(.plain).font(.kinLabel)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .well(radius: Theme.Radius.small)
    }

    private var folderMenu: some View {
        Menu {
            ForEach(recentFolders, id: \.self) { path in
                Button { folderRaw = path } label: {
                    Label(short(path), systemImage: path == folder ? "checkmark" : "")
                }
            }
            Divider()
            Button("选择文件夹…") { pickFolder() }
        } label: {
            ChipLabel(title: (folder as NSString).lastPathComponent, symbol: "folder", menu: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("新会话在哪个文件夹里：\(folder)")
    }

    // MARK: By folder

    /// The conversations in a folder, as the list shows them.
    private struct FolderGroup: Identifiable {
        /// The folder.
        let id: String
        var name = ""
        /// Its sessions open here, at the head of the group.
        var open: [Session] = []
        /// The rest, newest first.
        var items: [CodeHistory.Item] = []
        var latest = Date.distantPast
    }

    private var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The list by folder, as the Claude desktop app's sidebar has it ("像你现在
    /// 的一样按 folder 分类"): the folders with something open first, then the
    /// one talked in latest; narrowed by the search, by name or folder.
    private var groups: [FolderGroup] {
        let words = search.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ title: String, _ folder: String) -> Bool {
            words.isEmpty || title.lowercased().contains(words) || folder.lowercased().contains(words)
        }
        var byFolder: [String: FolderGroup] = [:]
        for s in sessions.codeSessions {
            let folder = AgentTerminalSessions.folder(of: s)
            guard matches(title(of: s), folder) else { continue }
            let key = CodeHistory.groupKey(folder)
            byFolder[key, default: FolderGroup(id: key)].open.append(s)
        }
        let open = Set(sessions.codeSessions.flatMap { [$0.conversation, $0.forkOf].compactMap { $0 } })
        for item in history.items where !open.contains(item.id) && matches(item.title, item.folder) {
            byFolder[item.group, default: FolderGroup(id: item.group)].items.append(item)
            if let latest = byFolder[item.group]?.latest, item.modified > latest { byFolder[item.group]?.latest = item.modified }
        }
        var list = byFolder.values.sorted {
            if $0.open.isEmpty != $1.open.isEmpty { return !$0.open.isEmpty }
            return $0.latest != $1.latest ? $0.latest > $1.latest : $0.id < $1.id
        }
        // Named by the folder, and by its parent too where two share a name.
        let names = list.map { ($0.id as NSString).lastPathComponent }
        for i in list.indices {
            let parent = ((list[i].id as NSString).deletingLastPathComponent as NSString).lastPathComponent
            list[i].name = names.filter { $0 == names[i] }.count > 1 ? parent + "/" + names[i] : names[i]
        }
        return list
    }

    private var folded: Set<String> { Set(foldedRaw.split(separator: "\n").map(String.init)) }

    private func fold(_ key: String) {
        var shut = folded
        if shut.contains(key) { shut.remove(key) } else { shut.insert(key) }
        foldedRaw = shut.sorted().joined(separator: "\n")
    }

    /// How many of a folder's past conversations show before 「还有 N 段」.
    private static let few = 5

    @ViewBuilder
    private func folderSection(_ group: FolderGroup) -> some View {
        let shut = !searching && folded.contains(group.id)
        FolderHeader(name: group.name, path: group.id, count: group.open.count + group.items.count, folded: shut,
                     toggle: { fold(group.id) },
                     new: {
                         folderRaw = group.id
                         sessions.newCode(harness, brain: brain, folder: group.id)
                         listing = false
                     })
        .padding(.top, 6)
        if !shut {
            ForEach(group.open) { s in openRow(s) }
            let all = searching || unfolded.contains(group.id)
            let shown = all ? group.items : Array(group.items.prefix(Self.few))
            ForEach(shown) { item in historyRow(item, in: group) }
            if group.items.count > shown.count {
                moreButton("还有 \(group.items.count - shown.count) 段") { unfolded.insert(group.id) }
            } else if all, !searching, group.items.count > Self.few {
                moreButton("收起") { unfolded.remove(group.id) }
            }
        }
    }

    private func moreButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.kinCaption).foregroundStyle(.secondary)
                .padding(.leading, 20).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openRow(_ s: Session) -> some View {
        let running = sessions.running.contains(s.id)
        let selected = s.id == sessions.selectedCode?.id
        return CodeRow(title: title(of: s),
                       detail: brainTitle(of: s) + " · " + (running ? "在跑" : "停着"),
                       dot: running ? Theme.good : Color.secondary.opacity(0.4),
                       selected: selected,
                       close: { sessions.close(s.id) }) {
            sessions.selectedID = s.id
            listing = false
        }
        .help(AgentTerminalSessions.folder(of: s) + (running ? "" : "\n停着：点开，重启就接着这段对话"))
    }

    private func historyRow(_ item: CodeHistory.Item, in group: FolderGroup) -> some View {
        let live = Date().timeIntervalSince(item.modified) < 600
        var detail = Self.ago(item.modified)
        // Had in a worktree or a folder inside the group's: which.
        if CodeHistory.realPath(item.folder) != group.id { detail += " · " + (item.folder as NSString).lastPathComponent }
        if item.harness == .codex { detail += " · Codex" }
        return CodeRow(title: item.title, detail: detail, dot: live ? Theme.notice : nil, selected: false, close: nil) {
            sessions.resume(item, brain: brain)
            listing = false
        }
        .help(item.folder + (live && item.harness == .claude
            ? "\n这段对话刚刚还在动，可能正开在别处（比如 Claude 桌面 app）：接着的是它的一份副本，两边互不打扰"
            : "\n点一下在这里接着聊"))
    }

    // MARK: A conversation

    @ViewBuilder
    private func detail(wide: Bool) -> some View {
        if let s = sessions.selectedCode {
            VStack(spacing: 0) {
                header(s, wide: wide)
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                if let terminal = sessions.terminal(for: s) {
                    TerminalSlot(terminal: terminal)
                        .id(s.id)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color(nsColor: NSColor(calibratedWhite: 0.06, alpha: 1)))
                    if !sessions.running.contains(s.id) { stopped(s) }
                } else {
                    unavailable(s)
                }
            }
        } else {
            empty
        }
    }

    private func header(_ s: Session, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if !wide {
                    Button { listing = true } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain).help("回到会话列表")
                }
                Text(title(of: s)).font(.kinHeadline).lineLimit(1).truncationMode(.tail)
                    .help(title(of: s))
                Spacer(minLength: 6)
                Button { sessions.restart(s.id) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("重启：再开这个 agent，接着这段对话")
                Button { sessions.close(s.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("关掉这个会话（agent 停下，对话还在，下面的列表里还能接着）")
            }
            FlowLayout(spacing: 6) {
                if let harness = s.harness {
                    ChipLabel(title: harness.title, symbol: "terminal")
                    BrainMenu(harness: harness, brain: s.brain ?? AgentBrain.at(AgentTerminalSessions.host(of: s), model: s.model) ?? .account,
                              help: "这个会话用哪个模型想事情。换了它会重启，接着同一段对话") { new in
                        sessions.update(s.id) { $0.brain = new; $0.host = ""; $0.model = "" }
                    }
                } else if let item = AgentTerminalSessions.installed(s) {
                    ChipLabel(title: item.integration.label, symbol: "terminal")
                }
                Menu {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: AgentTerminalSessions.folder(of: s))
                    }
                    Button("在这里开一个 shell") { Drawers.shared.openShell(in: AgentTerminalSessions.folder(of: s)) }
                } label: {
                    ChipLabel(title: (AgentTerminalSessions.folder(of: s) as NSString).lastPathComponent, symbol: "folder", menu: true)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(AgentTerminalSessions.folder(of: s))
            }
            if let note = sessions.notes[s.id] {
                Text(note).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Under the screen of a session that has stopped, the screen still up.
    private func stopped(_ s: Session) -> some View {
        HStack(spacing: 8) {
            Text(sessions.notes[s.id] ?? "它停了").font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Button { sessions.restart(s.id) } label: { Label("接着这段对话", systemImage: "arrow.clockwise") }
                .buttonStyle(.primary)
                .help("再开 agent，回到这段对话")
            Button("关掉") { sessions.close(s.id) }
                .buttonStyle(.quietFilled)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func unavailable(_ s: Session) -> some View {
        VStack(spacing: 8) {
            Text(s.harness.map { "这台 Mac 上没找到 \($0.title)" } ?? "这个会话要的 agent 不在了")
                .font(.kinBody)
            Text("装好它再回来点「重启」，或者关掉这个会话。")
                .font(.kinCaption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("重启") { sessions.restart(s.id) }.buttonStyle(.quietFilled)
                Button("关掉") { sessions.close(s.id) }.buttonStyle(.quietFilled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
            Text("Claude Code 和 Codex").font(.kinTitle)
            Text("开一个新会话，或者从左边挑一段接着聊。默认用这台 Mac 上 Claude Code 登录的订阅；会话开着的时候也能换成这台 Mac 或盒子上的模型，接着同一段对话。")
                .font(.kinLabel).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                sessions.newCode(harness, brain: brain, folder: folder)
            } label: { Label("新会话", systemImage: "plus") }
                .buttonStyle(.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Words

    private func title(of s: Session) -> String {
        if let name = history.item(s.conversation)?.title ?? s.title { return name }
        let who = s.harness?.title ?? AgentTerminalSessions.installed(s)?.integration.label ?? "Agent"
        return "\(who) · 新会话"
    }

    private func brainTitle(of s: Session) -> String {
        guard let harness = s.harness else { return s.model.isEmpty ? "" : s.model }
        if let brain = s.brain { return brain.source == .account ? (harness == .claude ? "订阅" : "ChatGPT") : brain.model }
        return s.model.isEmpty ? "订阅" : s.model
    }

    private func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static let clock: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()

    private static func ago(_ date: Date) -> String {
        Date().timeIntervalSince(date) < 60 ? "刚刚" : clock.localizedString(for: date, relativeTo: Date())
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: folder)
        panel.message = "新会话在哪个文件夹里工作？"
        if panel.runModal() == .OK, let url = panel.url { folderRaw = url.path }
    }
}

/// A folder's heading in the list: folds its group shut, and starts a new
/// session there.
private struct FolderHeader: View {
    let name: String
    let path: String
    let count: Int
    let folded: Bool
    let toggle: () -> Void
    let new: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: folded ? "chevron.right" : "chevron.down")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).frame(width: 10)
            Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text("\(count)").font(.kinCaption).foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            if hovering {
                Button(action: new) { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("在「\(name)」里开一个新会话")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: toggle)
        .help(path)
    }
}

/// A row of the list: a name, what sits under it, and a close button when
/// the pointer is on it.
private struct CodeRow: View {
    let title: String
    let detail: String
    let dot: Color?
    let selected: Bool
    let close: (() -> Void)?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(dot ?? .clear).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kinLabel).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(selected ? Theme.accent : Color.primary)
                Text(detail).font(.kinCaption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let close, hovering {
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.top, 3)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(selected ? Theme.accentWash : hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}
