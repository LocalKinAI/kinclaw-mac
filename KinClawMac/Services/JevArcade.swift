import Foundation
import Security

/// Where a decision model plays games: the loop, the players, and the numbers.
///
/// One move is one question. The game lists what can be done, in words; a
/// player picks; the game does it. The players are interchangeable on purpose,
/// because the interesting thing about a model that plays is how it compares:
///
///   - **Jev** — TypeSafe's typed decision model, over its API (`/v1/systemone`,
///     one Choice question). Answers in ~150 ms with a probability for every
///     option, never an illegal one. Needs the user's own key, which lives in
///     the Keychain and is typed into the tab by them.
///   - **Laya** — the open 0.4B model of the same kind, on this Mac, behind
///     `scripts/laya_judge.py`. Same question, no key, no cost.
///   - **本地大模型** — a chat model on the user's Ollama, asked the same
///     question and told to answer with the option's key.
///   - **Jev＋大模型**, **Laya＋大模型** — the two kinds of mind together, which
///     was Jacky's answer to "why can't Jev beat the yardstick": the fast one
///     does what it is for — a probability for every option in 150 ms — and
///     when it is sure, that is the move; when it is not, the three it likes
///     best go to a chat model, which is shown *the board itself* and thinks.
///     Shown only the words, the pair would know no more than either alone:
///     the words are the evaluator's own summary of its search, and nobody
///     beats a judge by reading the judge's notes.
///   - **深算** — the program looking as far as the words for a reader look
///     (three plies at chess and xiangqi, four stones at gomoku): what a
///     perfect reader could do. Where a game looks no further, the same as 启发式.
///   - **启发式** — the game's own evaluator: the yardstick.
///   - **随机** — the floor.
@MainActor
final class JevArcade: ObservableObject {
    static let shared = JevArcade()

    enum Player: String, CaseIterable, Identifiable {
        case jev, laya, llm, duoJev, duoLaya, deep, heuristic, random
        /// Does this player need a chat model chosen for it?
        var thinks: Bool { self == .llm || self == .duoJev || self == .duoLaya }
        var id: String { rawValue }
        @MainActor var title: String {
            switch self {
            case .jev: return "Jev（云）"
            case .laya: return FilmStudio.layaURL == BoxServices.base(.laya) ? "Laya（盒子）" : "Laya（本机）"
            case .llm: return "本地大模型"
            case .duoJev: return "Jev＋大模型"
            case .duoLaya: return "Laya＋大模型"
            case .deep: return "深算"
            case .heuristic: return "启发式"
            case .random: return "随机"
            }
        }
    }

    /// What a player said about one position.
    struct Decision {
        var chosen: String
        var options: [JevOption]
        var chances: [String: Double] = [:]
        var confidence: Double?
        var milliseconds: Int
        var by: String
        var agreed: Bool
        /// Whose move it was, in a game for two.
        var side: String? = nil
    }

    let games: [JevGame] = [JevTetris(), Jev2048(), JevSnake(), JevBlackjack(), JevGomoku(), JevChess(), JevXiangqi()]
    /// A game for two has a player a side, and any player can sit on either:
    /// Jev against Laya, a chat model against the yardstick, one chat model
    /// against another.
    @Published var rivals: [Player] = [.jev, .laya] { didSet { UserDefaults.standard.set(rivals.map { $0.rawValue }, forKey: "kinclaw.jev.rivals") } }
    /// Which chat model sits in a seat whose player is 本地大模型; "" is the
    /// one the app would pick for itself. Seat 0 is also the solo seat.
    @Published var models: [String] = ["", ""] { didSet { UserDefaults.standard.set(models, forKey: "kinclaw.jev.models") } }
    /// Per seat: moves made, moves that matched the yardstick, milliseconds spent.
    @Published private(set) var seats: [(moves: Int, agreed: Int, spent: Int)] = [(0, 0, 0), (0, 0, 0)]
    @Published var game: JevGame
    @Published var player: Player = .jev { didSet { UserDefaults.standard.set(player.rawValue, forKey: "kinclaw.jev.player") } }
    /// Pause between moves, in seconds: so that a game can be watched.
    @Published var pause: Double = 0.15
    @Published var seed: UInt64 = 100
    @Published private(set) var running = false
    @Published private(set) var last: Decision?
    @Published private(set) var trouble: String?
    @Published private(set) var moves = 0
    @Published private(set) var agreed = 0
    @Published private(set) var spent = 0              // milliseconds asking
    @Published private(set) var tokens = 0
    /// Bumped on every move: a game is a class, and SwiftUI has to be told.
    @Published private(set) var frame = 0

    private var loop: Task<Void, Never>?
    private var drawn = Date.distantPast

    /// Tell the tab to draw — at most thirty times a second. A heuristic
    /// plays a thousand moves a second, and redrawing two hundred squares
    /// for each of them made a game that takes a second take two minutes.
    private func show(now: Bool = false) {
        guard now || Date().timeIntervalSince(drawn) > 0.033 else { return }
        drawn = Date(); frame += 1
    }

    init() {
        game = games[0]
        if let kept = UserDefaults.standard.string(forKey: "kinclaw.jev.player"), let player = Player(rawValue: kept) { self.player = player }
        if let kept = UserDefaults.standard.stringArray(forKey: "kinclaw.jev.rivals")?.compactMap(Player.init(rawValue:)), kept.count == 2 { rivals = kept }
        if let kept = UserDefaults.standard.stringArray(forKey: "kinclaw.jev.models"), kept.count == 2 { models = kept }
        restart()
    }

    func choose(_ id: String) {
        guard let wanted = games.first(where: { $0.id == id }), wanted.id != game.id else { return }
        stop(); game = wanted; restart()
    }

    func restart() {
        stop()
        game.reset(seed: seed)
        last = nil; trouble = nil; moves = 0; agreed = 0; spent = 0; tokens = 0; frame += 1
        seats = [(0, 0, 0), (0, 0, 0)]
    }

    func start(limit: Int = 100_000) {
        guard !running else { return }
        running = true; trouble = nil
        loop = Task { @MainActor in
            defer { running = false }
            var played = 0
            while !Task.isCancelled, played < limit, await step() {
                played += 1
                if pause > 0 { try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000)) }
                else if played % 64 == 0 { await Task.yield() }
            }
            show(now: true)
        }
    }

    func stop() { loop?.cancel(); loop = nil; running = false; show(now: true) }

    /// One move. False when the game is over or the player could not answer.
    @discardableResult
    func step() async -> Bool {
        let seat = game.sides.isEmpty ? 0 : min(game.turn, 1)
        let mover = game.sides.isEmpty ? player : rivals[seat]
        game.prepare(reader: mover != .heuristic && mover != .random)
        let options = game.options()
        guard !options.isEmpty, !game.over else { show(now: true); return false }
        let best = options.max { $0.merit < $1.merit }!
        let began = Date()
        do {
            // One legal move is not a question. Asking anyway costs a call,
            // and Laya answers a one-option choice with an error from inside
            // torch ("selected index k out of range") — found by a snake in a
            // corridor.
            var decision = options.count == 1
                ? Decision(chosen: options[0].id, options: options, milliseconds: 0, by: "只有这一步可走", agreed: true)
                : try await Self.ask(mover, game: game, options: options, model: models[seat])
            decision.side = game.sides.isEmpty ? nil : game.sides[seat]
            decision.milliseconds = Int(Date().timeIntervalSince(began) * 1000)
            guard let picked = options.first(where: { $0.id == decision.chosen }) else {
                throw Failure.message("\(decision.by) 选了「\(decision.chosen)」，不在选项里")
            }
            decision.agreed = picked.merit >= best.merit - 1e-9
            game.play(mover == .heuristic ? picked.judged : picked)
            last = decision
            moves += 1; spent += decision.milliseconds
            if decision.agreed { agreed += 1 }
            seats[seat].moves += 1; seats[seat].spent += decision.milliseconds
            if decision.agreed { seats[seat].agreed += 1 }
            show(now: game.over)
            return !game.over
        } catch {
            trouble = error.localizedDescription
            return false
        }
    }

    /// US dollars spent on Jev so far: input tokens only, at 1.13's price.
    var cost: Double { Double(tokens) * 0.042 / 1_000_000 }

    // MARK: - The players

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private static func ask(_ player: Player, game: JevGame, options: [JevOption], model: String = "") async throws -> Decision {
        switch player {
        case .heuristic:
            let best = options.max { $0.merit < $1.merit }!
            return Decision(chosen: best.id, options: options, milliseconds: 0, by: "启发式", agreed: true)
        case .deep:
            // The program itself, looking as far as the words for a reader look:
            // what a perfect reader of them could do, and the top of the ladder
            // 随机 < 启发式 < 深算 that a model is somewhere on.
            let best = options.max { ($0.insight ?? $0.merit) < ($1.insight ?? $1.merit) }!
            return Decision(chosen: best.id, options: options, milliseconds: 0, by: "深算", agreed: false)
        case .random:
            return Decision(chosen: options[Int.random(in: 0..<options.count)].id, options: options, milliseconds: 0, by: "随机", agreed: false)
        case .jev: return try await askJev(game, options)
        case .laya: return try await askLaya(game, options)
        case .llm: return try await askChat(game, options, model: model)
        case .duoJev: return try await askDuo(game, options, fast: .jev, model: model)
        case .duoLaya: return try await askDuo(game, options, fast: .laya, model: model)
        }
    }

    /// Sure enough not to ask anybody else.
    static let sure = 0.75
    /// Whether the chat model in a pair may think before it answers.
    static let thinkKey = "kinclaw.jev.think"

    /// The fast judge first; the slow one only when the fast one is unsure, and
    /// only about the few moves the fast one could not choose between.
    private static func askDuo(_ game: JevGame, _ options: [JevOption], fast: Player, model: String) async throws -> Decision {
        var first = try await (fast == .jev ? askJev(game, options) : askLaya(game, options))
        let ranked = options.sorted { (first.chances[$0.id] ?? 0) > (first.chances[$1.id] ?? 0) }
        let top = first.chances[ranked[0].id] ?? 0
        if top >= sure || ranked.count <= 2 {
            first.by += " · 有把握，没问大模型"
            return first
        }
        let few = Array(ranked.prefix(3))
        let hint = few.map { "\($0.id) \(Int(((first.chances[$0.id] ?? 0) * 100).rounded()))%" }.joined(separator: ", ")
        do {
            let second = try await askChat(game, few, model: model, board: true,
                                           note: "A fast judge that cannot see the board narrowed the legal moves to these and rated them: \(hint). It was not sure. You can see the board: decide.")
            guard few.contains(where: { $0.id == second.chosen }) else { throw Failure.message("选了不在这三个里的") }
            return Decision(chosen: second.chosen, options: options, chances: first.chances, confidence: first.confidence,
                            milliseconds: 0, by: "\(first.by) → \(second.by)", agreed: false)
        } catch {
            // The slow judge not answering is no reason to stop a game the fast one can carry on.
            first.by += " · 大模型没答上（\(error.localizedDescription.prefix(40))）"
            return first
        }
    }

    private static func object(_ fields: [(String, String)]) -> String { JevClient.object(fields) }
    private static func quoted(_ text: String) -> String { JevClient.quoted(text) }

    private static func askJev(_ game: JevGame, _ options: [JevOption]) async throws -> Decision {
        let question = JevClient.Question(id: "move", question: game.question, howToJudge: game.howToJudge,
                                          options: options.map { ($0.id, $0.label) })
        let reply = try await JevClient.ask(state: [("game", game.rules), ("position_before_move", game.situation)], [question])
        guard let move = reply.answers["move"] else { throw Failure.message("Jev 的回答里没有这道题") }
        await MainActor.run { JevArcade.shared.tokens += reply.tokens }
        return Decision(chosen: move.choice, options: options, chances: move.chances, confidence: move.confidence,
                        milliseconds: 0, by: reply.model, agreed: false)
    }

    private static func askLaya(_ game: JevGame, _ options: [JevOption]) async throws -> Decision {
        guard let url = URL(string: FilmStudio.layaURL + "/decide") else { throw Failure.message("Laya 的地址不对") }
        if JevArcade.shared.moves == 0 { await FilmStudio.layaReady() }      // once a game, not once a move
        // Laya's options share one small token budget (192–256 for all of
        // them), so past a dozen each is a few words and they blur together;
        // its card says as much. The first twelve, in the game's own order —
        // not the best twelve, which would be the evaluator playing for it.
        let options = Array(options.prefix(12))
        // Written in order, like Jev's. As a dictionary the options reached
        // the model in a different order every time, and the same seed played
        // four different games: a model that leans toward the first thing it
        // reads is answering the shuffle, not the question.
        let body = object([
            ("state", object([("game", quoted(game.rules)), ("position_before_move", quoted(game.situation))])),
            ("questions", object([("move", object([
                ("type", quoted("choice")),
                ("instructions", quoted(game.question + " " + game.howToJudge)),
                ("criteria", object(options.map { ($0.id, quoted($0.label)) })),
            ]))])),
        ])
        var request = URLRequest(url: url, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            throw Failure.message("Laya 的服务没起来（\(FilmStudio.layaURL)）。在 设置 → Backend 里启动：盒子上的那份在「盒子上的服务」，本机的命令在「片场 · Laya 打分」")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Up, and said no: its own sentence, not "not running".
            let said = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["detail"] as? String
            throw Failure.message("Laya 没接这道题：\(said ?? String(data: data.prefix(200), encoding: .utf8) ?? "")")
        }
        guard let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let move = (reply["answers"] as? [String: Any])?["move"] as? [String: Any],
              let chosen = move["choice"] as? String else { throw Failure.message("Laya 的回答读不出来") }
        let chances = (move["probabilities"] as? [String: Double]) ?? (move["probs"] as? [String: Double]) ?? [:]
        return Decision(chosen: chosen, options: options, chances: chances, confidence: move["confidence"] as? Double,
                        milliseconds: 0, by: "laya", agreed: false)
    }

    /// Which machine has a chat model, remembered: asked once a game, not once a move.
    private static var homes: [String: String] = [:]

    private static func askChat(_ game: JevGame, _ options: [JevOption], model named: String = "",
                                board: Bool = false, note: String = "") async throws -> Decision {
        // A seat names its model as "host|model": the same name can be on two
        // machines (kimi's cloud model is on both), and the point of choosing
        // the box's is that it runs there. A bare name is looked up.
        var chosen: (host: String, model: String)?
        if named.isEmpty { chosen = await FilmStudio.writer() }
        else if let bar = named.firstIndex(of: "|") { chosen = (String(named[..<bar]), String(named[named.index(after: bar)...])) }
        else {
            if homes[named] == nil {
                for entry in await FilmStudio.candidates() where entry.models.contains(named) { homes[named] = entry.host; break }
            }
            chosen = homes[named].map { ($0, named) }
        }
        guard let writer = chosen, let url = URL(string: writer.host + "/api/chat") else {
            throw Failure.message(named.isEmpty ? "没找到能用的本地对话模型" : "没找到 \(named)：它在哪台机器的 Ollama 上？")
        }
        // The board, for a player asked to judge rather than to read: what the
        // options say about each move is the evaluator's opinion of it, and a
        // chat model that knows the game can have one of its own.
        let seen = board ? await MainActor.run { game.position } : ""
        let ask = """
            \(game.rules)
            Position before the move: \(game.situation)
            \(seen.isEmpty ? "" : seen + "\n")\(note.isEmpty ? "" : note + "\n")\(game.question) \(game.howToJudge)
            Options:
            \(options.map { "\($0.id): \($0.label)" }.joined(separator: "\n"))
            \(board && !seen.isEmpty ? "The descriptions come from a shallow two-move search; use your own knowledge of the game and the board above where they fall short. " : "")Answer with the option's key only, for example p03. Nothing else.
            """
        // Asked to judge, a model is allowed to think first — it is what
        // separated the chat models in the Tetris runs — and one that cannot
        // is asked again plainly.
        // …when the tab says it may: a local 9B thinking about one chess move
        // took forty-four seconds, and a game at that pace is nobody's idea of
        // watching a game. Off, the same model answers in two or three.
        var text: String?
        let mayThink = board && UserDefaults.standard.bool(forKey: Self.thinkKey)
        for think in (mayThink ? [true, false] : [false]) {
            let body: [String: Any] = ["model": writer.model, "stream": false, "think": think, "messages": [["role": "user", "content": ask]]]
            var request = URLRequest(url: url, timeoutInterval: think ? 240 : 90)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let said = (reply["message"] as? [String: Any])?["content"] as? String else { continue }
            text = said
            break
        }
        guard let text else { throw Failure.message("\(writer.model) 没回答") }
        guard let range = text.range(of: #"p\d\d"#, options: [.regularExpression, .backwards]) else {
            throw Failure.message("\(writer.model) 没按要求只答编号：\(text.prefix(80))")
        }
        return Decision(chosen: String(text[range]), options: options, milliseconds: 0,
                        by: "\(writer.model)（\(BoxServices.place(of: writer.host))）", agreed: false)
    }
}

/// TypeSafe's Jev, asked Choice questions: `POST /v1/systemone` with a state, and
/// for each question what is asked, how to judge, and the options in words. The
/// answer is a choice with a probability for every option — so a yes-or-no put
/// as two options comes back as a number between nought and one, which is what
/// lets it judge a film take as well as pick a chess move.
///
/// Choice is the one question type this app has seen work (it is the one the
/// Tetris example uses), so it is the only one used.
enum JevClient {
    struct Question {
        var id: String
        var question: String
        var howToJudge: String = ""
        var options: [(key: String, label: String)]
    }
    struct Answer { var choice: String; var chances: [String: Double]; var confidence: Double? }
    struct Reply { var answers: [String: Answer]; var tokens: Int; var model: String }

    static let base = "https://api.typesafe.ai"

    /// Field order is part of the question: a model reads a request top to
    /// bottom, and a dictionary would shuffle it. So the JSON is written by hand.
    static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { "\(quoted($0.0)): \($0.1)" }.joined(separator: ", ") + "}"
    }
    static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }

    static func ask(state: [(String, String)], _ questions: [Question]) async throws -> Reply {
        guard let key = JevKey.read(), !key.isEmpty else {
            if let status = JevKey.refusal {
                throw JevArcade.Failure.message("钥匙串没让这一版 app 读 TypeSafe 的 key（\(status)）：app 重新编译过，对钥匙串来说是另一个程序。到 Jev 标签点一次「开始」让它问你，或者把 key 重新填一遍")
            }
            throw JevArcade.Failure.message("还没有 TypeSafe 的 key：在 console.typesafe.ai/keys 建一个，填到 Jev 标签里")
        }
        func setting(_ name: String, _ fallback: String) -> String {
            let set = UserDefaults.standard.string(forKey: name) ?? ""
            return set.isEmpty ? fallback : set
        }
        let address = setting("kinclaw.jev.base", base), model = setting("kinclaw.jev.model", "jev-latest")
        let body = object([
            ("state", object(state.map { ($0.0, quoted($0.1)) })),
            ("model", quoted(model)),
            ("questions", object(questions.map { q in
                (q.id, object([
                    ("type", quoted("choice")),
                    ("instructions", q.howToJudge.isEmpty ? object([("question", quoted(q.question))])
                        : object([("question", quoted(q.question)), ("how_to_judge", quoted(q.howToJudge))])),
                    ("criteria", object(q.options.map { ($0.key, quoted($0.label)) })),
                ]))
            })),
        ])
        guard let url = URL(string: address + "/v1/systemone") else { throw JevArcade.Failure.message("Jev 的地址不对：\(address)") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        var answer: (Data, URLResponse)?
        for attempt in 0..<4 {                          // rate limits and overload are retried, as the SDKs do
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(500_000_000 << (attempt - 1))) }
            guard let got = try? await URLSession.shared.data(for: request) else { continue }
            answer = got
            let status = (got.1 as? HTTPURLResponse)?.statusCode ?? 0
            if status != 429 && status < 500 { break }
        }
        guard let (data, response) = answer else { throw JevArcade.Failure.message("连不上 \(address)") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 422, questions.count > 1 {
            // Several questions in one request is what the wire format invites,
            // but nothing here has seen it answered; one at a time has been.
            var merged = Reply(answers: [:], tokens: 0, model: model)
            for question in questions {
                let one = try await ask(state: state, [question])
                merged.answers.merge(one.answers) { $1 }
                merged.tokens += one.tokens
                merged.model = one.model
            }
            return merged
        }
        guard status == 200 else {
            let said = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw JevArcade.Failure.message("Jev \(status)：\(said)" + (status == 401 ? " —— key 不对或者过期了" : ""))
        }
        guard let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let answers = reply["answers"] as? [String: [String: Any]] else { throw JevArcade.Failure.message("Jev 的回答读不出来") }
        var read: [String: Answer] = [:]
        for (id, item) in answers {
            guard let choice = item["choice"] as? String else { continue }
            read[id] = Answer(choice: choice, chances: (item["probabilities"] as? [String: Double]) ?? [:], confidence: item["confidence"] as? Double)
        }
        return Reply(answers: read, tokens: ((reply["usage"] as? [String: Any])?["input_tokens"] as? Int) ?? 0,
                     model: (reply["model"] as? String) ?? model)
    }
}

/// The TypeSafe key, in the Keychain. Typed in by the user, read only to be
/// sent as the Authorization header; never logged, never shown.
enum JevKey {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "dev.localkin.kinclawmac.typesafe",
                                               kSecAttrAccount as String: "api-key"]
    private static let lock = NSLock()
    /// The key once it has been read, so the Keychain is asked once a launch.
    private static var held: String?
    /// Why the last read got nothing, when the Keychain said no rather than "not found".
    private(set) static var refusal: OSStatus?

    /// Is there a key at all? Only the item's attributes are asked for, which
    /// no access list guards — so looking never raises a dialog. Reading the
    /// secret to see whether it exists did: this app is signed ad hoc, to the
    /// Keychain every rebuild is a different program from the one that stored
    /// the key, and a view that checked at launch meant a password dialog at
    /// every launch.
    static var present: Bool {
        if !(ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] ?? "").isEmpty { return true }
        if outside() != nil { return true }
        var ask = query
        ask[kSecReturnAttributes as String] = true
        ask[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        return SecItemCopyMatching(ask as CFDictionary, &found) == errSecSuccess
    }

    /// The key. When the Keychain wants the user's consent first, `asking`
    /// says whether it may put its dialog up: yes when somebody just pressed a
    /// button in the Jev tab and is there to answer it; no for everything that
    /// runs unattended — a film being reviewed shot by shot, a tool call —
    /// where a dialog nobody expects blocks the work until somebody comes
    /// back. Unasked, a refusal is an error that says what to do.
    static func read(asking: Bool = false) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let held { return held }
        // A key the user keeps outside the app wins, and asks nobody: no
        // Keychain dialog, and no lock after every rebuild.
        if let kept = outside() { held = kept; refusal = nil; return kept }
        var ask = query
        ask[kSecReturnData as String] = true
        ask[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        if !asking { SecKeychainSetUserInteractionAllowed(false) }
        let status = SecItemCopyMatching(ask as CFDictionary, &found)
        if !asking { SecKeychainSetUserInteractionAllowed(true) }
        if status == errSecSuccess, let data = found as? Data, let key = String(data: data, encoding: .utf8) {
            held = key; refusal = nil
            return key
        }
        refusal = status == errSecItemNotFound ? nil : status
        return nil
    }

    /// The key where the user keeps it for everything else: the environment,
    /// then `~/.typesafe_key` (the jev-tetris program's file). The environment
    /// only reaches this app when it was launched from a shell — `.zshrc` is
    /// not read by anything the Dock or `open` starts — so the file is what
    /// actually works day to day.
    private static func outside() -> String? {
        let env = (ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty { return env }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".typesafe_key")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    @discardableResult
    static func write(_ key: String) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); held = nil; refusal = nil; lock.unlock()
        SecItemDelete(query as CFDictionary)
        guard !cleaned.isEmpty else { return true }
        var item = query
        item[kSecValueData as String] = Data(cleaned.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
