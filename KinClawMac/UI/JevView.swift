import SwiftUI

/// The Jev tab: a decision model plays games, one multiple-choice question a
/// move, and what it was choosing between is shown beside the board.
struct JevView: View {
    @ObservedObject private var arcade = JevArcade.shared
    @State private var key = ""
    @State private var hasKey = JevKey.present
    @AppStorage(JevArcade.thinkKey) private var think = false
    @State private var enteringKey = false
    @State private var chatModels: [(host: String, models: [String])] = []

    var body: some View {
        HStack(spacing: 0) {
            games.frame(width: 150)
            Divider().opacity(0.15)
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

    // MARK: Which game

    private var games: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(arcade.games.map { $0.id }, id: \.self) { id in
                let game = arcade.games.first { $0.id == id }!
                Button { arcade.choose(id) } label: {
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
            Spacer()
            Text("每一步是一道选择题：游戏把能走的每一步会造成什么写成字，模型只管挑。量由程序量，判断留给模型。")
                .font(.system(size: 9)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
    }

    // MARK: The board

    private var board: some View {
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
                        }
                    }
                }
            }
            .id(arcade.frame)
            Text(arcade.game.status).font(.system(size: 11, weight: .medium))
            if arcade.game.over { Text("这一局结束了").font(.system(size: 11)).foregroundColor(.orange) }
        }
    }

    // MARK: What it was choosing between

    private var thinking: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let last = arcade.last {
                HStack(spacing: 6) {
                    if let side = last.side { Text(side).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary) }
                    Text(last.by).font(.system(size: 12, weight: .semibold))
                    Text("\(last.milliseconds) ms").font(.system(size: 10)).foregroundColor(.secondary)
                    if let sure = last.confidence { Text("把握 \(String(format: "%.2f", sure))").font(.system(size: 10)).foregroundColor(.secondary) }
                    Text(last.agreed ? "和启发式一致" : "和启发式不同").font(.system(size: 10))
                        .foregroundColor(last.agreed ? .green : .orange)
                }
                ForEach(ranked(last).prefix(7)) { option in
                    let chance = last.chances[option.id]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(option.id).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            if let chance { Text("\(Int((chance * 100).rounded()))%").font(.system(size: 9, weight: .semibold)) }
                            if option.id == last.chosen { Text("选了这个").font(.system(size: 9, weight: .semibold)).foregroundColor(.accentColor) }
                        }
                        Text(option.label).font(.system(size: 10)).foregroundColor(option.id == last.chosen ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let chance {
                            GeometryReader { space in
                                Capsule().fill(option.id == last.chosen ? Color.accentColor : Color.primary.opacity(0.25))
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
                Button("走一步") { Task { await unlock(); await arcade.step() } }.controlSize(.small).disabled(arcade.running || arcade.game.over)
                Button("重来") { arcade.restart() }.controlSize(.small)
                Stepper("种子 \(arcade.seed)", value: $arcade.seed, in: 1...9999).font(.system(size: 10)).fixedSize()
                Spacer(minLength: 0)
                if usesJev {
                    Button(hasKey ? "换 key" : "填 TypeSafe key") { enteringKey.toggle() }.controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Text("每步停 \(Int(arcade.pause * 1000)) ms").font(.system(size: 10)).foregroundColor(.secondary)
                Slider(value: $arcade.pause, in: 0...1).controlSize(.mini).frame(width: 140)
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
