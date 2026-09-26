import AppKit
import SwiftUI

/// The Jev tab: what a decision model does here. Games, where each move is
/// one multiple-choice question and what it was choosing between is shown
/// beside the board — and the shelf, where two thousand books on a disk are
/// each one question of the same kind. Same model, same shape, same panel:
/// the program measures, the model judges.
struct JevView: View {
    @ObservedObject private var arcade = JevArcade.shared
    @State private var key = ""
    @State private var hasKey = JevKey.present
    @AppStorage(JevArcade.thinkKey) private var think = false
    @State private var enteringKey = false
    @State private var chatModels: [(host: String, models: [String])] = []
    /// Nil is a game; "books" is the shelf.
    @AppStorage("kinclaw.jev.doing") private var doing = ""

    var body: some View {
        HStack(spacing: 0) {
            games.frame(width: 150).background(Theme.sidebar)
            Rectangle().fill(Theme.hairline).frame(width: 0.5)
            if doing == "books" {
                BookShelfView()
            } else if doing == "rts" {
                RTSView()
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        board
                        thinking.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(14)
                    .frame(maxHeight: .infinity, alignment: .top)
                    Divider().opacity(0.15)
                    controls
                }
            }
        }
        .onAppear { JevKeys.install() }
        .onDisappear { JevKeys.remove() }
    }

    // MARK: Which game

    private var games: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(arcade.games.map { $0.id }, id: \.self) { id in
                let game = arcade.games.first { $0.id == id }!
                Button { arcade.choose(id); doing = "" } label: {
                    HStack(spacing: 8) {
                        Image(systemName: game.symbol).frame(width: 18)
                        Text(game.title).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(arcade.game.id == id ? 0.10 : 0)))
                }
                .buttonStyle(.plain)
            }
            Divider().opacity(0.12).padding(.vertical, 4)
            // Building games: played with the mouse, in real time.
            Text("建造").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).padding(.leading, 8)
            Button { doing = "rts" } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled").frame(width: 18)
                    Text("帝国时代").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(doing == "rts" ? 0.10 : 0)))
            }
            .buttonStyle(.plain)
            Divider().opacity(0.12).padding(.vertical, 4)
            // Not a game, and the same thing: one question a book.
            Button { doing = "books" } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.book.closed").frame(width: 18)
                    Text("书架").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    if BookShelf.shared.books.count > 0 {
                        Text("\(BookShelf.shared.books.count)").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(doing == "books" ? 0.10 : 0)))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("每一步是一道选择题：游戏把能走的每一步会造成什么写成字，模型只管挑。量由程序量，判断留给模型。")
                .font(.system(size: 9)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
    }

    // MARK: The board

    private var board: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let painted = arcade.game as? JevPainted { scene(painted) } else { squares }
            Text(arcade.game.status).font(.system(size: 11, weight: .medium))
            if arcade.game.over { Text("这一局结束了").font(.system(size: 11)).foregroundColor(.orange) }
            if arcade.game.sides.isEmpty, !arcade.standings.isEmpty {
                // The same seed deals everybody the same game: a person against the models, on one line.
                Text("种子 \(arcade.seed) 最好成绩：" + arcade.standings.prefix(5).map { "\($0.who) \($0.score)" }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A game that draws itself: sixty frames a second while it runs, each one
    /// part of the way from the last move to this one.
    private func scene(_ painted: JevPainted) -> some View {
        let aspect = CGFloat(painted.aspect)
        let width = min(640, 560 * aspect), height = width / aspect
        let idle = !arcade.running && Date().timeIntervalSince(painted.ticked) > 2.5
        return TimelineView(.animation(minimumInterval: nil, paused: idle)) { timeline in
            let since = timeline.date.timeIntervalSince(painted.ticked)
            let picture = painted.picture(t: min(max(since / arcade.glide, 0), 1), since: since,
                                          now: timeline.date.timeIntervalSinceReferenceDate)
            Canvas { context, size in picture.paint(&context, size) }
                .overlay(alignment: .bottom) {
                    // Why a click did nothing.
                    if let notice = arcade.notice {
                        Text(notice).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Color.black.opacity(0.78)))
                            .padding(14)
                    }
                }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { point in
            if let spot = painted.spot(at: point, in: CGSize(width: width, height: height)) { arcade.tap(row: spot.row, col: spot.col) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private var squares: some View {
        let grid = arcade.game.grid
        let rows = grid.count, columns = grid.first?.count ?? 1
        let cell: CGFloat = min(300 / CGFloat(columns), 440 / CGFloat(rows))
        return VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 1) {
                ForEach(0..<rows, id: \.self) { y in
                    HStack(spacing: 1) {
                        ForEach(0..<columns, id: \.self) { x in
                            let square = grid[y][x]
                            RoundedRectangle(cornerRadius: cell > 30 ? 6 : 2)
                                .fill(square.colour ?? Color.primary.opacity(0.06))
                                .frame(width: cell, height: cell)
                                .overlay {
                                    if let disc = square.disc {
                                        Circle().fill(disc).padding(cell * 0.06)
                                            .overlay(Circle().strokeBorder((square.ink ?? .black).opacity(0.85), lineWidth: 1.2).padding(cell * 0.12))
                                            .shadow(color: .black.opacity(0.35), radius: 0.8, y: 0.6)
                                    }
                                }
                                .overlay(Text(square.text)
                                    .font(.system(size: cell * (square.disc != nil ? 0.5 : square.big ? 0.74 : 0.32), weight: .bold))
                                    .foregroundColor(square.ink ?? .black.opacity(0.75))
                                    .shadow(color: square.big && square.disc == nil ? .black.opacity(0.55) : .clear, radius: 0.6))
                                .contentShape(Rectangle())
                                .onTapGesture { arcade.tap(row: y, col: x) }
                        }
                    }
                }
            }
            .id(arcade.frame)
        }
    }

    // MARK: What it was choosing between

    private var thinking: some View {
        VStack(alignment: .leading, spacing: 8) {
            if arcade.personSeated {
                Text(arcade.game.controls + (arcade.running ? "" : "（点「开始」或直接按键）"))
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if arcade.running, arcade.personSeated, arcade.mover != .me, !arcade.game.over {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(arcade.mover.title) 在想…").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                }
            }
            if !arcade.offered.isEmpty {
                Text("轮到你了\(arcade.game.sides.isEmpty ? "" : "（\(arcade.game.sides[min(arcade.game.turn, 1)])）")：按键、点棋盘，或者点下面一个")
                    .font(.system(size: 12, weight: .semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(arcade.offered) { option in
                            Button { arcade.pick(option) } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(option.id).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let title = option.title { Text(title).font(.system(size: 12, weight: .semibold)) }
                                        Text(option.label).font(.system(size: option.title == nil ? 10 : 9))
                                            .foregroundColor(option.title == nil ? .primary : .secondary)
                                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let last = arcade.last {
                HStack(spacing: 6) {
                    if let side = last.side { Text(side).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary) }
                    Text(last.by).font(.system(size: 12, weight: .semibold))
                    Text("\(last.milliseconds) ms").font(.system(size: 10)).foregroundColor(.secondary)
                    if let sure = last.confidence { Text("把握 \(String(format: "%.2f", sure))").font(.system(size: 10)).foregroundColor(.secondary) }
                    Text(last.agreed ? "和启发式一致" : "和启发式不同").font(.system(size: 10))
                        .foregroundColor(last.agreed ? Theme.accent : .orange)
                }
                ForEach(ranked(last).prefix(7)) { option in
                    let chance = last.chances[option.id]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(option.id).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            if let chance { Text("\(Int((chance * 100).rounded()))%").font(.system(size: 9, weight: .semibold)) }
                            if option.id == last.chosen { Text("选了这个").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.accent) }
                        }
                        if let title = option.title {
                            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(option.id == last.chosen ? .primary : .secondary)
                        }
                        Text(option.label).font(.system(size: option.title == nil ? 10 : 9)).foregroundColor(option.id == last.chosen && option.title == nil ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let chance {
                            GeometryReader { space in
                                Capsule().fill(option.id == last.chosen ? Theme.accent : Color.primary.opacity(0.25))
                                    .frame(width: max(2, space.size.width * chance), height: 3)
                            }
                            .frame(height: 3)
                        }
                    }
                }
                if last.options.count > 7 { Text("……一共 \(last.options.count) 个选项").font(.system(size: 9)).foregroundColor(.secondary) }
            } else {
                Text("还没走第一步").font(.system(size: 11)).foregroundColor(.secondary)
            }
            if let trouble = arcade.trouble {
                Text(trouble).font(.system(size: 10)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(tally).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .id(arcade.frame)
    }

    /// The chosen one first, then by the chance the player gave each, then by the game's own opinion.
    private func ranked(_ decision: JevArcade.Decision) -> [JevOption] {
        decision.options.sorted { a, b in
            if (a.id == decision.chosen) != (b.id == decision.chosen) { return a.id == decision.chosen }
            let (ca, cb) = (decision.chances[a.id] ?? -1, decision.chances[b.id] ?? -1)
            return ca != cb ? ca > cb : a.merit > b.merit
        }
    }

    private var tally: String {
        guard arcade.moves > 0 else { return "同一个种子给每个玩家发同一局，可以拿来比。" }
        if !arcade.game.sides.isEmpty {
            return arcade.game.sides.enumerated().map { seat, side in
                let tally = arcade.seats[seat]
                guard tally.moves > 0 else { return "\(side) \(arcade.rivals[seat].title)" }
                return "\(side) \(arcade.rivals[seat].title)：\(tally.moves) 步 · 平均 \(tally.spent / tally.moves) ms · 和启发式一致 \(100 * tally.agreed / tally.moves)%"
            }.joined(separator: "\n") + (arcade.tokens > 0 ? "\nJev：\(arcade.tokens) tokens ≈ $\(String(format: "%.4f", arcade.cost))" : "")
        }
        var parts = ["\(arcade.moves) 步", "平均 \(arcade.spent / arcade.moves) ms", "和启发式一致 \(Int(100 * arcade.agreed / arcade.moves))%"]
        if arcade.tokens > 0 { parts.append("\(arcade.tokens) tokens ≈ $\(String(format: "%.4f", arcade.cost))") }
        return parts.joined(separator: " · ")
    }

    /// One seat: who sits in it, and — for a chat model — which one.
    private func seat(_ side: String?, player: Binding<JevArcade.Player>, model: Binding<String>) -> some View {
        HStack(spacing: 4) {
            if let side { Text(side).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary) }
            Picker("", selection: player) {
                ForEach(JevArcade.Player.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().controlSize(.small).fixedSize()
            if player.wrappedValue.thinks {
                // Every Ollama within reach, by machine: this Mac's, the box's.
                // A model on the box runs on the box — a 35B costs this Mac
                // nothing, and a local one costs no cloud quota.
                Picker("", selection: model) {
                    Text("自动").tag("")
                    ForEach(chatModels, id: \.host) { entry in
                        Section(BoxServices.place(of: entry.host)) {
                            ForEach(entry.models, id: \.self) { name in
                                Text(name + (name.hasSuffix(":cloud") ? " ☁︎" : "")).tag("\(entry.host)|\(name)")
                            }
                        }
                    }
                }
                .labelsHidden().controlSize(.small).fixedSize()
                .task { if chatModels.isEmpty { chatModels = await FilmStudio.candidates() } }
            }
        }
    }

    // MARK: Who plays, and how fast

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if arcade.game.sides.isEmpty {
                    seat(nil, player: $arcade.player, model: $arcade.models[0])
                } else {
                    ForEach(Array(arcade.game.sides.enumerated()), id: \.offset) { index, side in
                        seat(side, player: $arcade.rivals[index], model: $arcade.models[index])
                    }
                }
                Button(arcade.running ? "暂停" : "开始") {
                    if arcade.running { arcade.stop() } else { Task { await unlock(); arcade.start() } }
                }
                    .controlSize(.small).disabled(arcade.game.over)
                Button("走一步") { Task { await unlock(); await arcade.step() } }.controlSize(.small)
                    .disabled(arcade.running || arcade.game.over || arcade.mover == .me)
                Button("重来") { arcade.restart() }.controlSize(.small)
                Stepper("种子 \(arcade.seed)", value: $arcade.seed, in: 1...9999).font(.system(size: 10)).fixedSize()
                Spacer(minLength: 0)
                if usesJev {
                    Button(hasKey ? "换 key" : "填 TypeSafe key") { enteringKey.toggle() }.controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                if arcade.personSeated, let clock = arcade.game.clock {
                    Text("速度 ×\(String(format: "%.1f", arcade.tempo))（一步 \(Int(clock / arcade.tempo * 1000)) ms）").font(.system(size: 10)).foregroundColor(.secondary)
                    Slider(value: $arcade.tempo, in: 0.5...2).controlSize(.mini).frame(width: 140)
                } else {
                    Text("每步停 \(Int(arcade.pause * 1000)) ms").font(.system(size: 10)).foregroundColor(.secondary)
                    Slider(value: $arcade.pause, in: 0...1).controlSize(.mini).frame(width: 140)
                }
                if (arcade.game.sides.isEmpty ? [arcade.player] : arcade.rivals).contains(where: { $0 == .duoJev || $0 == .duoLaya }) {
                    Toggle("大模型先想再答（慢很多）", isOn: $think).toggleStyle(.checkbox).controlSize(.mini).font(.system(size: 10))
                        .help("「Jev＋大模型」里的大模型看着棋盘在三个候选里挑。让它先想，棋会好一些；本地 9B 想一步要四十多秒，不想两三秒")
                }
                Spacer(minLength: 0)
            }
            if enteringKey {
                HStack(spacing: 8) {
                    SecureField("TypeSafe API key（console.typesafe.ai/keys），存进钥匙串", text: $key)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    Button("存") { JevKey.write(key); key = ""; hasKey = JevKey.present; enteringKey = false }.controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Is TypeSafe's key going to be needed for the game as it is set up?
    private var usesJev: Bool {
        let seated = arcade.game.sides.isEmpty ? [arcade.player] : arcade.rivals
        return seated.contains(.jev) || seated.contains(.duoJev)
    }

    /// Somebody pressed a button and is here: if Jev is to play and the
    /// Keychain wants consent before it hands the key over, now is when it may
    /// ask. Off the main thread — the read waits for the dialog.
    private func unlock() async {
        guard usesJev, hasKey else { return }
        _ = await Task.detached { JevKey.read(asking: true) }.value
    }
}

/// The keyboard, for a person playing in the Jev tab: the arrows, space and
/// the letters the game listens to, taken before anything else in the panel
/// sees them — a focused button would take space as a click — but only while
/// somebody has a seat, and never from a text field being typed in.
@MainActor
enum JevKeys {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            take(event) ? nil : event
        }
    }

    static func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        JevArcade.shared.letGo()
    }

    private static func take(_ event: NSEvent) -> Bool {
        let arcade = JevArcade.shared
        guard arcade.personSeated, UserDefaults.standard.string(forKey: "kinclaw.jev.doing") != "books",
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !(event.window?.firstResponder is NSText) else { return false }
        let press: JevPress
        switch event.keyCode {
        case 123: press = .left
        case 124: press = .right
        case 125: press = .down
        case 126: press = .up
        case 49: press = .space
        default:
            guard let letter = event.charactersIgnoringModifiers?.lowercased().first, arcade.game.letters.contains(letter) else { return false }
            press = .letter(letter)
        }
        arcade.key(press, down: event.type == .keyDown, repeat: event.type == .keyDown && event.isARepeat)
        return true
    }
}
