import SwiftUI
import CoreText

/// Xiangqi for two players who read words.
///
/// The same division of labour as chess beside it: the program generates the
/// legal moves (the generator agrees with the published perft counts on eleven
/// positions, four plies deep), looks one reply ahead for each — and one
/// recapture past that — and says what it found: what is captured, whether it
/// is check or the end of the game, what it does for development, and how the
/// material stands after the opponent's best reply. The players choose among a
/// dozen candidates: the evaluator's best eight, and then the captures and the
/// checks a player is likely to be tempted by and must be allowed to get
/// wrong, in board order, which favours nobody.
///
/// The models are asked in English, in coordinates (files a–i from Red's left,
/// ranks 0–9 from Red's back rank). The person watching reads the move under
/// the board the way it is written in every xiangqi book: 炮二平五.
@MainActor
final class JevXiangqi: JevGame {
    let id = "xiangqi", title = "中国象棋", symbol = "circle.grid.3x3"
    let rules = "Xiangqi (Chinese chess). Each option is one legal move for the side to play; Red moves first. A side with no legal move has lost, whether or not it is in check. Here the game is drawn by threefold repetition, by sixty moves each without a capture, or when neither side has a piece left that can cross the river."
    let question = "Which move is best for the side to play?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: checkmate, or leaving the opponent without a legal move, wins at once and is always best. Second: never choose a move that allows checkmate. Third: the material result after the best reply decides — a move that comes out behind in material is worse than every move that keeps material the same, whatever else it does, even if the other move retreats or moves a guard; a move that comes out ahead is better than every move that does not, and further ahead is better. A chariot is worth 9, a cannon 4.5, a horse 4, an elephant or an advisor 2, a soldier 1, or 2 once it has crossed the river. Fourth, and only among moves with the same material result: prefer a move that threatens checkmate, then one that threatens to win material, the bigger threat first — the opponent has to answer a threat. Fifth: prefer bringing the chariots out early, developing the horses, a cannon on the central file, and soldiers across the river; avoid moving the general, or the advisors and elephants that guard him, avoid retreating, and avoid repeating a position unless you are behind — but only when it costs nothing above."
    let sides = ["红方", "黑方"]
    /// Whether the words about a move say what it threatens.
    nonisolated(unsafe) static var saysThreats = true
    /// How many plies past the move the words look, when somebody insists (the
    /// test harness does). Otherwise: three for a reader, one — what the
    /// evaluator that plays looks — for anybody else.
    nonisolated(unsafe) static var foresight: Int?
    private var reader = false
    private var depth: Int { Self.foresight ?? (reader ? 3 : 1) }

    func prepare(reader: Bool) { self.reader = reader }

    /// Start from a position given in FEN — for tests, and for looking at a position somebody reports.
    func setUp(fen: String) {
        reset(seed: 1)
        state = XiangqiPosition(fen: fen); seen = [state.key: 1]
    }

    // MARK: Played by a person

    private var person = false
    private var picked: Int?
    private var targets: Set<Int> { picked.map { from in Set(moves.filter { $0.from == from }.map(\.to)) } ?? [] }
    func prepare(person: Bool) { self.person = person }
    let controls = "点自己的一个棋子，再点它要去的位置"

    func tap(row: Int, col: Int, among options: [JevOption]) -> JevReaction {
        let point = row * 9 + col
        if let from = picked, let option = options.first(where: { moves[$0.move].from == from && moves[$0.move].to == point }) {
            picked = nil; return .choose(option)
        }
        if moves.contains(where: { $0.from == point }) { picked = point; return .redraw }
        let mine: Int8 = state.redToMove ? 1 : -1
        if state.board[point] * mine > 0 { picked = nil; return .explain(stuck(point)) }
        if let from = picked { picked = nil; return .explain(cannot(from, point)) }
        return .nothing
    }

    /// One of the person's men that has no move: why.
    private func stuck(_ point: Int) -> String {
        let red = state.redToMove, name = (red ? Self.red : Self.black)[Int(abs(state.board[point]))], general = red ? "帅" : "将"
        if state.inCheck(red: red) { return "你正被将军：这个\(name)解不了将。能解将的子圈出来了" }
        var without = state
        without.board[point] = 0
        if without.inCheck(red: red) { return "这个\(name)被牵制了：它一离开这里，你的\(general)就会被将军（或者两个将帅照面）" }
        return "这个\(name)现在没有地方可走"
    }

    /// A man picked up, and a point it may not go to: why.
    private func cannot(_ from: Int, _ to: Int) -> String {
        let piece = state.board[from], kind = Int(abs(piece)), red = piece > 0
        let name = (red ? Self.red : Self.black)[kind], general = red ? "帅" : "将"
        if state.isPseudoLegal(XiangqiPosition.Move(from: from, to: to)) {
            return state.inCheck(red: red) ? "你正被将军：这一步解不了将" : "\(name)这样走完，你的\(general)会被将军（或者两个将帅照面），不能走"
        }
        switch kind {
        case 1: return "\(name)只能往前走一步，过了河才能左右走"
        case 2: return "\(name)只能在九宫里斜着走一格"
        case 3: return "\(name)走田字，不能过河；田字中间有子（塞象眼）就不能走"
        case 4: return "马走日字；挨着它的那一点有子（蹩马腿），就不能往那边跳"
        case 5: return "炮走直线，路上不能有子；吃子时中间要正好隔一个子（炮架）"
        case 6: return "车走直线，路上不能有子"
        default: return "\(name)只能在九宫里横竖走一格"
        }
    }

    private var state = XiangqiPosition()
    private var seen: [String: Int] = [:]
    private var moves: [XiangqiPosition.Move] = []
    private var last: XiangqiPosition.Move?
    /// The board before the last move, for the picture: the piece slides from there.
    private var previous = [Int8](repeating: 0, count: 90)
    private(set) var ticked = Date.distantPast
    private var lastWritten = ""
    private var played: [String] = []
    private(set) var plies = 0
    private(set) var result: String?
    private var dice = JevDice(seed: 1)

    var turn: Int { state.redToMove ? 0 : 1 }
    var over: Bool { result != nil }
    var score: Int { state.material / 2 }
    var status: String {
        if let result { return result + (lastWritten.isEmpty ? "" : " · 最后一步 \(lastWritten)") }
        let ahead = state.material
        let balance = ahead == 0 ? "子力相当" : "\(ahead > 0 ? "红方" : "黑方")多 \(Self.points(abs(ahead))) 分"
        return "第 \(plies / 2 + 1) 回合 · 轮到\(sides[turn]) · \(balance)" + (state.inCheck(red: state.redToMove) ? " · 将军" : "")
            + (lastWritten.isEmpty ? "" : " · 上一步 \(lastWritten)")
    }
    var situation: String {
        let me = state.redToMove ? "Red" : "Black", balance = (state.redToMove ? 1 : -1) * state.material
        return "\(me) to play, move \(plies / 2 + 1); material: "
            + (balance == 0 ? "even" : balance > 0 ? "\(me) is up \(Self.points(balance))" : "\(me) is down \(Self.points(-balance))")
            + (state.inCheck(red: state.redToMove) ? "; \(me) is in check" : "")
    }

    var position: String {
        let diagram = (0..<10).map { row in
            "\(9 - row) " + (0..<9).map { col -> String in
                let piece = state.board[row * 9 + col], kind = Int(abs(piece))
                return piece == 0 ? "．" : piece > 0 ? Self.red[kind] : Self.black[kind]
            }.joined()
        }.joined(separator: "\n")
        return "FEN: \(state.fen(move: plies / 2 + 1))\n\(diagram)\n  ａｂｃｄｅｆｇｈｉ   (帅仕相兵 are Red, who started at the bottom, ranks 0–4; 将士象卒 are Black)\n"
            + "Moves so far: " + (played.isEmpty ? "none" : played.suffix(24).joined(separator: " "))
    }

    /// Half points as they are spoken: 9 is "4.5".
    private static func points(_ half: Int) -> String { half % 2 == 0 ? "\(half / 2)" : "\(half / 2).5" }

    nonisolated private static let red = ["", "兵", "仕", "相", "马", "炮", "车", "帅"]
    nonisolated private static let black = ["", "卒", "士", "象", "马", "炮", "车", "将"]
    private static let wood = Color(red: 0.87, green: 0.72, blue: 0.49), palace = Color(red: 0.80, green: 0.64, blue: 0.41)
    private static let river = Color(red: 0.74, green: 0.80, blue: 0.78), disc = Color(red: 0.97, green: 0.91, blue: 0.78)

    var grid: [[JevCell]] {
        (0..<10).map { row in (0..<9).map { col in
            let index = row * 9 + col, piece = state.board[index], kind = Int(abs(piece))
            let moved = last.map { $0.from == index || $0.to == index } ?? false
            let ground = (col >= 3 && col <= 5 && (row <= 2 || row >= 7)) ? Self.palace : (row == 4 || row == 5) ? Self.river : Self.wood
            return JevCell(colour: picked == index ? Color.blue.opacity(0.5) : targets.contains(index) ? Color.green.opacity(0.55)
                                : moved ? Color.yellow.opacity(0.8) : ground,
                           text: piece > 0 ? Self.red[kind] : Self.black[kind],
                           ink: piece > 0 ? Color(red: 0.75, green: 0.08, blue: 0.06) : Color(red: 0.08, green: 0.08, blue: 0.10),
                           big: true, disc: piece == 0 ? nil : Self.disc)
        } }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        state = XiangqiPosition(); seen = [state.key: 1]; last = nil; lastWritten = ""; played = []; plies = 0; result = nil; picked = nil
        dice = JevDice(seed: seed)
    }

    func options() -> [JevOption] {
        guard result == nil else { return [] }
        let legal = state.legalMoves()
        if legal.isEmpty { result = ending(); return [] }
        let judged = legal.map { ($0, state.outcome(of: $0)) }
        let now = (state.redToMove ? 1 : -1) * state.material
        if person {
            moves = legal
            return legal.enumerated().map { index, move in
                JevOption(id: String(format: "p%02d", index + 1), label: describe(move, outcome: judged[index].1, further: nil, now: now),
                          merit: Double(judged[index].1.value), move: index)
            }
        }
        // The shortlist: the evaluator's best eight, then what tempts.
        let depth = self.depth
        var keep = Set(judged.enumerated().sorted { $0.element.1.value > $1.element.1.value }.prefix(depth > 1 ? 5 : 8).map { $0.offset })
        // For a reader the words look further than the evaluator that plays does,
        // and what looks best further on belongs on the list as much as what looks
        // best now: it is what the words are going to be about.
        let further = depth > 1 ? legal.map { state.foresight(of: $0, plies: depth) } : []
        if depth > 1 {
            for index in further.indices.sorted(by: { further[$0].value > further[$1].value }).prefix(4) { keep.insert(index) }
        }
        func also(_ wanted: (XiangqiPosition.Move) -> Bool, atMost: Int) {
            var added = legal.enumerated().filter { keep.contains($0.offset) && wanted($0.element) }.count
            for (index, move) in legal.enumerated() where keep.count < 12 && added < atMost && !keep.contains(index) && wanted(move) {
                keep.insert(index); added += 1
            }
        }
        also({ self.state.board[$0.to] != 0 }, atMost: 4)
        also({ var next = self.state; next.play($0); return next.inCheck(red: next.redToMove) }, atMost: 3)
        var chosen = keep.sorted()                               // in board order, which favours nobody
        if depth > 1 {
            // The program does not ask what it already knows. A chat model that was
            // asked lost five games in six to the evaluator, each by one move whose
            // own description said "it loses material"; with those moves off the
            // list it lost none. What is left to judge is what measuring cannot
            // settle: among moves that come out the same, which threat, which plan.
            let sound = chosen.filter { further[$0].value > -1_000_000 }
            let pool = sound.isEmpty ? chosen : sound
            if let mate = pool.first(where: { further[$0].value >= 1_000_000 }) { chosen = [mate] }
            else {
                let top = pool.map { further[$0].material }.max() ?? 0
                chosen = pool.filter { further[$0].material >= top }
            }
        }
        moves = chosen.map { legal[$0] }
        return chosen.enumerated().map { index, which in
            let found = judged[which].1
            return JevOption(id: String(format: "p%02d", index + 1),
                             label: describe(legal[which], outcome: found, further: depth > 1 ? further[which] : nil, now: now),
                             merit: Double(found.value) + Double(dice.below(3)) * 0.001, move: index,
                             insight: depth > 1 ? Double(further[which].value) : nil)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        let move = moves[option.move]
        lastWritten = Self.written(move, in: state); played.append(lastWritten)
        previous = state.board
        state.play(move)
        ticked = Date()
        last = move; plies += 1; picked = nil
        seen[state.key, default: 0] += 1
        if !state.canMove { result = ending()
        } else if seen[state.key, default: 0] >= 3 { result = "同一局面出现三次 · 和棋"
        } else if state.quiet >= 120 { result = "六十回合没有吃子 · 和棋"
        } else if state.deadPosition { result = "双方都没有能过河的子了 · 和棋"
        } else if plies >= 400 { result = "下满 200 回合 · 和棋" }
    }

    /// The side to move has nothing legal left: mated, or hemmed in — a loss either way.
    private func ending() -> String {
        let how = state.inCheck(red: state.redToMove) ? "绝杀" : "困毙"
        return "\(how) · \(sides[1 - turn])赢了（\((plies + 1) / 2) 回合）"
    }

    /// One move, in words: what it is, what it does, and how it comes out.
    private func describe(_ move: XiangqiPosition.Move, outcome: (value: Int, material: Int),
                          further: (value: Int, material: Int)?, now: Int) -> String {
        let depth = self.depth
        let board = state.board, piece = Int(abs(board[move.from])), red = state.redToMove
        let fromRow = move.from / 9, toRow = move.to / 9, toCol = move.to % 9
        /// Ranks counted from the mover's own back rank.
        func rank(_ row: Int) -> Int { red ? 9 - row : row }
        var parts: [String] = []
        if board[move.to] != 0 {
            let taken = Int(abs(board[move.to]))
            parts.append("captures " + (taken == 1 && rank(toRow) <= 4 ? "a soldier that has crossed the river" : "the \(XiangqiPosition.names[taken])"))
        }
        var next = state
        next.play(move)
        if outcome.value >= 1_000_000 {
            parts.append(next.inCheck(red: next.redToMove) ? "checkmate: wins the game at once"
                         : "leaves the opponent without a single legal move, which wins the game at once")
        } else if next.inCheck(red: next.redToMove) { parts.append("gives check") }
        let opening = plies < 24
        if piece == 4, rank(fromRow) == 0, rank(toRow) > 0 { parts.append("develops the horse") }
        if piece == 6, rank(fromRow) == 0, [0, 8].contains(move.from % 9), board[move.to] == 0 { parts.append("brings the chariot out of its corner") }
        if piece == 5, opening, toCol == 4, rank(toRow) <= 2, move.from % 9 != 4 { parts.append("places a cannon on the central file") }
        if piece == 1, rank(fromRow) == 4, rank(toRow) == 5 { parts.append("the soldier crosses the river and becomes worth 2") }
        if piece == 7, board[move.to] == 0, !state.inCheck(red: red) { parts.append("moves the general, which was not in check") }
        if (piece == 2 || piece == 3), opening, board[move.to] == 0, !state.inCheck(red: red) { parts.append("moves one of the general's guards") }
        if piece != 1, piece != 7, rank(toRow) < rank(fromRow), board[move.to] == 0 { parts.append("retreats") }
        if seen[next.key, default: 0] >= 1 { parts.append("repeats a position that has already occurred\(seen[next.key, default: 0] >= 2 ? ": the third time, which ends the game as a draw" : "")") }
        // What the move is up to, a move further than the evaluator looks when it
        // chooses for itself: the one thing in these words that is not its opinion.
        if Self.saysThreats, outcome.value < 1_000_000, outcome.value > -1_000_000 {
            let threat = state.threat(after: move)
            if threat.mate { parts.append("threatens checkmate next move") }
            else if threat.gain >= 2 { parts.append("threatens to win \(Self.points(threat.gain)) in material next move") }
        }
        var outcome = outcome
        var horizon = "after the best reply"
        if let further, outcome.value < 1_000_000, outcome.value > -1_000_000 {
            outcome = further
            horizon = depth == 2 ? "after the best reply and your best answer to it" : "\(depth) moves on, with best play by both sides"
            if outcome.value >= 1_000_000 { parts.append("forces checkmate within \(depth) moves") }
        }
        if outcome.value <= -1_000_000 { parts.append(further != nil ? "allows a forced checkmate: loses the game" : "allows checkmate next move: loses the game") }
        else if outcome.value < 1_000_000 {
            let change = outcome.material - now
            parts.append(change >= 1 ? "\(horizon) comes out \(Self.points(change)) ahead in material"
                         : change <= -1 ? "\(horizon) comes out \(Self.points(-change)) behind in material: it loses material"
                         : "material stays the same \(horizon)")
        }
        return "\(XiangqiPosition.names[piece]) \(XiangqiPosition.square(move.from)) to \(XiangqiPosition.square(move.to)): " + parts.joined(separator: "; ")
    }

    // MARK: The move as a xiangqi book writes it

    nonisolated private static let numerals = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 炮二平五, 马8进7, 前车退一: the piece, the file it stands on counted from
    /// its own side's right, the direction, and then the file it arrives on —
    /// or, for a piece that moves along a file, how far it went. Two of a kind
    /// on one file are told apart as 前 and 后, the front one being nearer the
    /// enemy.
    nonisolated static func written(_ move: XiangqiPosition.Move, in position: XiangqiPosition) -> String {
        let board = position.board, piece = board[move.from], kind = Int(abs(piece)), red = piece > 0
        let fromRow = move.from / 9, fromCol = move.from % 9, toRow = move.to / 9, toCol = move.to % 9
        func file(_ col: Int) -> String { red ? numerals[9 - col] : String(col + 1) }
        func count(_ n: Int) -> String { red ? numerals[n] : String(n) }
        let name = (red ? Self.red : Self.black)[kind]
        var who = name + file(fromCol)
        if [1, 4, 5, 6].contains(kind) {
            // The others of this kind on this file, front to back.
            let rows = (0..<10).filter { board[$0 * 9 + fromCol] == piece }
            let ordered = red ? rows : rows.reversed()           // nearest the enemy first
            if ordered.count == 2 { who = (ordered[0] == fromRow ? "前" : "后") + name }
            else if ordered.count == 3 { who = ["前", "中", "后"][ordered.firstIndex(of: fromRow) ?? 0] + name }
            else if ordered.count > 3 { who = (["前", "二", "三", "四", "五"][ordered.firstIndex(of: fromRow) ?? 0]) + name }
        }
        let forward = red ? toRow < fromRow : toRow > fromRow
        if toRow == fromRow { return who + "平" + file(toCol) }
        let way = forward ? "进" : "退"
        // Along a file: how far. The horse, the elephant and the advisor never
        // move along one, so for them it is the file they land on.
        return who + way + (toCol == fromCol ? count(abs(toRow - fromRow)) : file(toCol))
    }
}

// MARK: - The picture

extension JevXiangqi: JevPainted {
    var aspect: Double { 0.9 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let red = state.redToMove
        let general = state.inCheck(red: red) ? state.board.firstIndex(of: red ? 7 : -7) : nil
        // When a person is in check, the men that can answer it are ringed.
        let movable = person && general != nil ? Set(moves.map(\.from)) : []
        let scene = XiangqiScene(board: state.board, previous: previous, last: last.map { ($0.from, $0.to) }, picked: picked, targets: targets,
                                 check: general, movable: movable, t: t, over: over, result: result ?? "", redNames: Self.red, blackNames: Self.black)
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    func spot(at point: CGPoint, in size: CGSize) -> (row: Int, col: Int)? {
        let (origin, step) = XiangqiScene.geometry(size)
        let col = Int(((point.x - origin.x) / step).rounded()), row = Int(((point.y - origin.y) / step).rounded())
        guard (0..<10).contains(row), (0..<9).contains(col) else { return nil }
        return (row, col)
    }
}

/// A wooden board with its lines cut in and inked, the river written in a running hand, and the men as turned
/// wooden discs with their names carved in red or black.
fileprivate struct XiangqiScene {
    let board: [Int8], previous: [Int8], last: (from: Int, to: Int)?, picked: Int?, targets: Set<Int>, check: Int?, movable: Set<Int>
    let t: Double, over: Bool, result: String, redNames: [String], blackNames: [String]

    /// The board's face, where the lines start on it and the step between them, and how thick the board shows below the face.
    static func layout(_ size: CGSize) -> (face: CGRect, origin: CGPoint, step: CGFloat, thick: CGFloat) {
        let side = min(size.width, size.height), pad = side * 0.016, thick = side * 0.014, margin: CGFloat = 0.72
        let step = min((size.width - 2 * pad) / (8 + 2 * margin), (size.height - 2 * pad - thick) / (9 + 2 * margin))
        let width = step * (8 + 2 * margin), height = step * (9 + 2 * margin)
        let face = CGRect(x: (size.width - width) / 2, y: (size.height - thick - height) / 2, width: width, height: height)
        return (face, CGPoint(x: face.minX + margin * step, y: face.minY + margin * step), step, thick)
    }

    static func geometry(_ size: CGSize) -> (origin: CGPoint, step: CGFloat) {
        let layout = layout(size)
        return (layout.origin, layout.step)
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let (face, origin, step, thick) = Self.layout(size)
        func at(_ index: Int) -> CGPoint { CGPoint(x: origin.x + CGFloat(index % 9) * step, y: origin.y + CGFloat(index / 9) * step) }
        XiangqiArt.table(g, size: size, face: face, thick: thick)
        XiangqiArt.board(g, face: face, thick: thick)
        XiangqiArt.lines(g, origin: origin, step: step)
        let r = step * 0.45
        // Where the last move came from.
        if let last { XiangqiArt.from(g, at: at(last.from), radius: r) }
        let moving = last != nil && t < 1
        let shown = moving ? previous : board
        var standing: [Int] = []
        for index in 0..<90 where shown[index] != 0 {
            if moving, let last, index == last.from || index == last.to { continue }
            standing.append(index)
        }
        for index in standing { XiangqiArt.shadow(g, at: at(index), radius: r) }
        for index in standing {
            let p = at(index)
            if index == check && !moving { XiangqiArt.halo(g, at: p, radius: r, colour: Color(red: 1, green: 0.15, blue: 0.08), strength: 0.95) }
            if index == picked { XiangqiArt.halo(g, at: p, radius: r, colour: XiangqiArt.sky, strength: index == check ? 0 : 0.55) }
            if !moving, let last, index == last.to { XiangqiArt.halo(g, at: p, radius: r, colour: XiangqiArt.amber, strength: 0.75) }
            XiangqiArt.piece(g, shown[index], at: p, radius: r, name: name(shown[index]))
            if !moving, let last, index == last.to { XiangqiArt.ring(g, at: p, radius: r * 1.06, colour: XiangqiArt.amber, width: max(1.5, r * 0.07)) }
            if index == picked { XiangqiArt.ring(g, at: p, radius: r * 1.1, colour: XiangqiArt.sky, width: max(2, r * 0.1)) }
        }
        if moving, let last {
            // The man taken fades as the other arrives.
            if shown[last.to] != 0 {
                let p = at(last.to), taken = shown[last.to]
                g.drawLayer { layer in
                    layer.opacity = 1 - t
                    XiangqiArt.shadow(layer, at: p, radius: r)
                    XiangqiArt.piece(layer, taken, at: p, radius: r, name: name(taken))
                }
            }
            let from = at(last.from), to = at(last.to), e = JevDraw.smooth(t)
            let p = CGPoint(x: JevDraw.mix(Double(from.x), Double(to.x), e), y: JevDraw.mix(Double(from.y), Double(to.y), e))
            let lift = CGFloat(sin(Double.pi * e))
            XiangqiArt.shadow(g, at: p, radius: r, lift: lift)
            XiangqiArt.piece(g, previous[last.from], at: CGPoint(x: p.x, y: p.y - r * 0.12 * lift), radius: r * (1 + 0.06 * lift), name: name(previous[last.from]))
        }
        for target in targets {
            let p = at(target)
            if board[target] != 0 { XiangqiArt.ring(g, at: p, radius: r * 1.08, colour: XiangqiArt.jade, width: max(2, r * 0.1)) }
            else {
                let d = step * 0.13
                g.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d)),
                       with: .radialGradient(Gradient(colors: [XiangqiArt.jade.opacity(0.95), XiangqiArt.jade.opacity(0.75)]), center: p, startRadius: 0, endRadius: d))
                g.stroke(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d)), with: .color(Color.white.opacity(0.55)), lineWidth: 1)
            }
        }
        for index in movable where index != picked { XiangqiArt.ring(g, at: at(index), radius: r * 1.12, colour: XiangqiArt.jade, width: max(2, r * 0.1)) }
        if over { JevDraw.curtain(g, size, title: result.components(separatedBy: " · ").first ?? result, detail: result.components(separatedBy: " · ").dropFirst().joined(separator: " · ")) }
    }

    private func name(_ piece: Int8) -> String { (piece > 0 ? redNames : blackNames)[Int(abs(piece))] }
}

/// The board's wood, its lines, the men's shapes, worked out once.
fileprivate enum XiangqiArt {
    static let wood: (Double, Double, Double) = (0.88, 0.69, 0.43)
    static let ink = Color(red: 0.24, green: 0.12, blue: 0.05)
    static let amber = Color(red: 1, green: 0.76, blue: 0.2)
    static let jade = Color(red: 0.1, green: 0.6, blue: 0.36)
    static let sky = Color(red: 0.22, green: 0.52, blue: 1)

    /// Wood lit more (k > 1) or less, without going grey.
    static func tone(_ rgb: (Double, Double, Double), _ k: Double) -> Color { Color(red: min(1, rgb.0 * k), green: min(1, rgb.1 * k), blue: min(1, rgb.2 * k)) }

    // MARK: Glyphs

    /// A character's outline in the first of these fonts that has it, centred on (0, 0), one point of type to the unit.
    static func glyph(_ character: String, fonts: [String]) -> Path? {
        guard let unit = character.utf16.first else { return nil }
        for name in fonts {
            let font = CTFontCreateWithName(name as CFString, 100, nil)
            guard CTFontCopyPostScriptName(font) as String == name else { continue }
            var character = unit, glyph: CGGlyph = 0
            guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), glyph != 0, let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
            let box = outline.boundingBox
            return Path(outline).applying(CGAffineTransform(a: 0.01, b: 0, c: 0, d: -0.01, tx: -box.midX * 0.01, ty: box.midY * 0.01))
        }
        return nil
    }

    /// The men's names, cut in a heavy regular hand.
    static let names: [String: Path] = {
        var names: [String: Path] = [:]
        for character in "兵仕相马炮车帅卒士象将" {
            names[String(character)] = glyph(String(character), fonts: ["STKaitiSC-Black", "STKaitiSC-Bold", "STSongti-SC-Black", "STSongti-SC-Bold", "PingFangSC-Semibold"])
        }
        return names
    }()

    /// The river's four characters, in a running hand.
    static let river: [Path] = "楚河漢界".compactMap { glyph(String($0), fonts: ["STXingkaiSC-Bold", "STKaitiSC-Black", "STSongti-SC-Bold", "PingFangSC-Semibold"]) }

    /// Every line on the board, one step to the unit from the top left point: the grid, the palaces' diagonals, and the
    /// small corner marks where the soldiers and the cannons start.
    static let grid: Path = {
        var p = Path()
        func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) { p.move(to: CGPoint(x: a.0, y: a.1)); p.addLine(to: CGPoint(x: b.0, y: b.1)) }
        for row in 0..<10 { line((0, CGFloat(row)), (8, CGFloat(row))) }
        for col in 0..<9 {
            if col == 0 || col == 8 { line((CGFloat(col), 0), (CGFloat(col), 9)) }
            else { line((CGFloat(col), 0), (CGFloat(col), 4)); line((CGFloat(col), 5), (CGFloat(col), 9)) }
        }
        line((3, 0), (5, 2)); line((5, 0), (3, 2)); line((3, 7), (5, 9)); line((5, 7), (3, 9))
        return p
    }()

    static let marks: Path = {
        var p = Path()
        let gap: CGFloat = 0.08, arm: CGFloat = 0.19
        for (col, row) in [(1, 2), (7, 2), (1, 7), (7, 7), (0, 3), (2, 3), (4, 3), (6, 3), (8, 3), (0, 6), (2, 6), (4, 6), (6, 6), (8, 6)] {
            for sx: CGFloat in [-1, 1] where !(col == 0 && sx < 0) && !(col == 8 && sx > 0) {
                for sy: CGFloat in [-1, 1] {
                    let x = CGFloat(col) + sx * gap, y = CGFloat(row) + sy * gap
                    p.move(to: CGPoint(x: x + sx * arm, y: y))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x, y: y + sy * arm))
                }
            }
        }
        return p
    }()

    /// A strand of grain: where it runs (0…1 across and down the face), its colour, and how wide (a fraction of the face's width).
    struct Strand { let path: Path, colour: Color, width: CGFloat }

    /// The board's grain, running across it: soft bands and fine lines in families, gently waving.
    static let grain: [Strand] = {
        func streak(_ y: CGFloat, sway: CGFloat, seed: Int) -> Path {
            let phase = Double(seed % 628) / 100, phase2 = Double(seed / 628 % 628) / 100
            var points: [CGPoint] = []
            for k in 0...14 {
                let x = -0.02 + 1.04 * CGFloat(k) / 14
                let wave = sin(Double(x) * 2 * .pi * 0.7 + phase) + 0.45 * sin(Double(x) * 2 * .pi * 1.9 + phase2)
                points.append(CGPoint(x: x, y: y + sway * CGFloat(wave)))
            }
            var p = Path()
            p.move(to: points[0])
            for k in 1..<points.count - 1 {
                p.addQuadCurve(to: CGPoint(x: (points[k].x + points[k + 1].x) / 2, y: (points[k].y + points[k + 1].y) / 2), control: points[k])
            }
            p.addLine(to: points[points.count - 1])
            return p
        }
        let dark = Color(red: 0.5, green: 0.28, blue: 0.1), light = Color(red: 1, green: 0.92, blue: 0.72)
        var strands: [Strand] = []
        for k in 0..<16 {
            let h = JevDraw.hash(k, 501)
            strands.append(Strand(path: streak(CGFloat(h % 1000) / 1000, sway: 0.01, seed: h / 1000),
                                  colour: (h % 2 == 0 ? dark : light).opacity(0.05 + Double(h % 4) * 0.015), width: 0.014 + CGFloat(h / 7 % 30) / 1000))
        }
        for family in 0..<15 {
            let h = JevDraw.hash(family, 502)
            var y = CGFloat(h % 1000) / 1000
            for k in 0..<(3 + h % 5) {
                let hk = JevDraw.hash(family * 16 + k, 503)
                strands.append(Strand(path: streak(y, sway: 0.008, seed: h / 1000), colour: dark.opacity(0.1 + Double(hk % 9) / 100), width: 0.0012 + CGFloat(hk % 3) * 0.0006))
                y += 0.0035 + CGFloat(hk / 3 % 6) / 1000
            }
        }
        return strands
    }()

    /// A turned disc's grain: a few faint arcs across a unit disc.
    static let discGrain: Path = {
        var p = Path()
        for k in 0..<7 {
            let y = -0.78 + 1.56 * CGFloat(k) / 6 + CGFloat(JevDraw.hash(k, 31) % 9) / 100 - 0.04
            let half = sqrt(max(0, 1 - y * y)) * 0.97
            p.move(to: CGPoint(x: -half, y: y))
            p.addQuadCurve(to: CGPoint(x: half, y: y + 0.03), control: CGPoint(x: 0, y: y - 0.12))
        }
        return p
    }()

    // MARK: Painting

    /// A dark table, and the board's shadow on it.
    static func table(_ g: GraphicsContext, size: CGSize, face: CGRect, thick: CGFloat) {
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [Color(red: 0.2, green: 0.13, blue: 0.09), Color(red: 0.07, green: 0.045, blue: 0.035)]),
                                                                          center: CGPoint(x: size.width * 0.35, y: size.height * 0.3), startRadius: 0, endRadius: max(size.width, size.height)))
        for k in 0..<6 {
            let grow = CGFloat(k) * 1.6
            let rect = CGRect(x: face.minX - grow + 2, y: face.minY - grow + 5, width: face.width + 2 * grow, height: face.height + thick + 2 * grow)
            g.fill(Path(roundedRect: rect, cornerRadius: 6 + grow), with: .color(Color.black.opacity(0.09)))
        }
    }

    /// The board: its edge below, its face, the grain, the light on it.
    static func board(_ g: GraphicsContext, face: CGRect, thick: CGFloat) {
        let corner = face.width * 0.012
        let side = CGRect(x: face.minX, y: face.midY, width: face.width, height: face.height / 2 + thick)
        g.fill(Path(roundedRect: side, cornerRadius: corner * 1.5), with: .linearGradient(Gradient(colors: [tone(wood, 0.72), tone(wood, 0.6), tone(wood, 0.42)]),
                                                                                         startPoint: CGPoint(x: 0, y: face.maxY), endPoint: CGPoint(x: 0, y: side.maxY)))
        let shape = Path(roundedRect: face, cornerRadius: corner)
        g.fill(shape, with: .linearGradient(Gradient(colors: [tone(wood, 1.02), tone(wood, 0.97), tone(wood, 1.05), tone(wood, 0.98)]),
                                            startPoint: CGPoint(x: face.minX, y: face.minY), endPoint: CGPoint(x: face.minX, y: face.maxY)))
        var c = g
        c.clip(to: shape)
        let place = CGAffineTransform(a: face.width, b: 0, c: 0, d: face.height, tx: face.minX, ty: face.minY)
        for strand in grain { c.stroke(strand.path.applying(place), with: .color(strand.colour), lineWidth: strand.width * face.width) }
        c.fill(shape, with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 0.2, blue: 0).opacity(0), Color(red: 0.34, green: 0.16, blue: 0.02).opacity(0.3)]),
                                            center: CGPoint(x: face.midX, y: face.midY), startRadius: face.width * 0.32, endRadius: face.height * 0.72))
        c.fill(shape, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0)]), startPoint: face.origin, endPoint: CGPoint(x: face.midX, y: face.midY)))
        c.stroke(Path(roundedRect: face.insetBy(dx: 0.8, dy: 0.8), cornerRadius: corner),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.12), Color.black.opacity(0.22)]),
                                       startPoint: face.origin, endPoint: CGPoint(x: face.maxX, y: face.maxY)), lineWidth: 1.6)
    }

    /// The lines, cut into the wood and inked: each groove has a lit lower edge. Then the river, written.
    static func lines(_ g: GraphicsContext, origin: CGPoint, step: CGFloat) {
        let place = CGAffineTransform(a: step, b: 0, c: 0, d: step, tx: origin.x, ty: origin.y)
        let lit = Color(red: 1, green: 0.95, blue: 0.82).opacity(0.55), width = max(1.1, step * 0.022)
        let drawn = grid.applying(place), small = marks.applying(place)
        let frame = Path(CGRect(x: origin.x - step * 0.12, y: origin.y - step * 0.12, width: step * 8.24, height: step * 9.24))
        let border = Path(CGRect(x: origin.x, y: origin.y, width: step * 8, height: step * 9))
        let down = CGAffineTransform(translationX: 0.8, y: 0.9)
        for (path, w) in [(drawn, width), (small, width), (border, width * 1.5), (frame, width * 2.4)] {
            g.stroke(path.applying(down), with: .color(lit), lineWidth: w)
        }
        for (path, w) in [(drawn, width), (small, width), (border, width * 1.5), (frame, width * 2.4)] {
            g.stroke(path, with: .color(ink.opacity(0.88)), style: StrokeStyle(lineWidth: w, lineCap: .square))
        }
        // 楚河 on the left bank of the river, 漢界 on the right, written into the wood.
        guard river.count == 4 else { return }
        let type = step * 0.74, y = origin.y + step * 4.5
        for (k, x) in [1.52, 2.48, 5.52, 6.48].enumerated() {
            let mark = river[k].applying(CGAffineTransform(a: type, b: 0, c: 0, d: type, tx: origin.x + step * CGFloat(x), ty: y))
            g.fill(mark.applying(CGAffineTransform(translationX: 0.9, y: 1.1)), with: .color(lit))
            g.fill(mark, with: .color(ink.opacity(0.8)))
        }
    }

    /// The soft shadow a man throws on the board.
    static func shadow(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, lift: CGFloat = 0) {
        let centre = CGPoint(x: p.x + r * (0.08 + 0.3 * lift), y: p.y + r * (0.2 + 0.45 * lift)), reach = r * (1.16 + 0.25 * lift)
        let dark = 0.5 * Double(1 - 0.5 * lift)
        g.fill(Path(ellipseIn: CGRect(x: centre.x - reach, y: centre.y - reach, width: 2 * reach, height: 2 * reach)),
               with: .radialGradient(Gradient(stops: [.init(color: Color.black.opacity(dark), location: 0), .init(color: Color.black.opacity(dark * 0.7), location: 0.72),
                                                      .init(color: Color.black.opacity(0), location: 1)]), center: centre, startRadius: 0, endRadius: reach))
    }

    /// A soft coloured light round a man: in check, picked up, just moved.
    static func halo(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, colour: Color, strength: Double) {
        let reach = r * 1.5
        g.fill(Path(ellipseIn: CGRect(x: p.x - reach, y: p.y - reach, width: 2 * reach, height: 2 * reach)),
               with: .radialGradient(Gradient(stops: [.init(color: colour.opacity(strength), location: 0.55), .init(color: colour.opacity(0), location: 1)]),
                                     center: p, startRadius: 0, endRadius: reach))
    }

    static func ring(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, colour: Color, width: CGFloat) {
        g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(colour.opacity(0.95)), lineWidth: width)
    }

    /// Where the last move started: four small amber corners.
    static func from(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat) {
        var corners = Path()
        let d = r * 0.62, arm = r * 0.3
        for sx: CGFloat in [-1, 1] {
            for sy: CGFloat in [-1, 1] {
                corners.move(to: CGPoint(x: p.x + sx * d, y: p.y + sy * (d - arm)))
                corners.addLine(to: CGPoint(x: p.x + sx * d, y: p.y + sy * d))
                corners.addLine(to: CGPoint(x: p.x + sx * (d - arm), y: p.y + sy * d))
            }
        }
        g.stroke(corners, with: .color(Color.black.opacity(0.25)), style: StrokeStyle(lineWidth: max(2.5, r * 0.11), lineCap: .round, lineJoin: .round))
        g.stroke(corners, with: .color(amber), style: StrokeStyle(lineWidth: max(1.8, r * 0.075), lineCap: .round, lineJoin: .round))
    }

    /// A man: a turned wooden disc with a bevelled rim, a ring cut round the face, and his name carved in and inked.
    static func piece(_ g: GraphicsContext, _ piece: Int8, at p: CGPoint, radius r: CGFloat, name: String) {
        let red = piece > 0
        func disc(_ k: CGFloat, dy: CGFloat = 0) -> Path { Path(ellipseIn: CGRect(x: p.x - r * k, y: p.y - r * k + dy, width: 2 * r * k, height: 2 * r * k)) }
        // The disc's side, showing below its face.
        g.fill(disc(1, dy: r * 0.1), with: .linearGradient(Gradient(colors: [Color(red: 0.72, green: 0.5, blue: 0.27), Color(red: 0.48, green: 0.3, blue: 0.14)]),
                                                         startPoint: CGPoint(x: p.x, y: p.y), endPoint: CGPoint(x: p.x, y: p.y + r * 1.1)))
        // The face, lit from the top left.
        g.fill(disc(1), with: .radialGradient(Gradient(stops: [.init(color: Color(red: 0.99, green: 0.93, blue: 0.8), location: 0),
                                                              .init(color: Color(red: 0.95, green: 0.83, blue: 0.62), location: 0.5),
                                                              .init(color: Color(red: 0.86, green: 0.68, blue: 0.44), location: 0.9),
                                                              .init(color: Color(red: 0.78, green: 0.58, blue: 0.35), location: 1)]),
                                              center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.55))
        let turn = Double(JevDraw.hash(Int(piece) + 20, Int(p.x * 3 + p.y)) % 628) / 100
        g.stroke(discGrain.applying(CGAffineTransform(a: r * CGFloat(cos(turn)), b: r * CGFloat(sin(turn)), c: -r * CGFloat(sin(turn)), d: r * CGFloat(cos(turn)), tx: p.x, ty: p.y)),
                 with: .color(Color(red: 0.6, green: 0.4, blue: 0.2).opacity(0.14)), lineWidth: max(0.5, r * 0.025))
        // The bevel: the rim rounds over, lit on the upper left, in shade on the lower right.
        g.stroke(disc(0.915), with: .linearGradient(Gradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.1), Color(red: 0.4, green: 0.22, blue: 0.08).opacity(0.35)]),
                                                    startPoint: CGPoint(x: p.x - r * 0.7, y: p.y - r * 0.7), endPoint: CGPoint(x: p.x + r * 0.7, y: p.y + r * 0.7)),
                 lineWidth: r * 0.14)
        g.stroke(disc(1), with: .color(Color(red: 0.36, green: 0.2, blue: 0.08).opacity(0.55)), lineWidth: max(0.8, r * 0.03))
        // A ring cut round the face, and the name, carved: a lit lower edge to each groove, then the colour in it.
        let colour = red ? Color(red: 0.72, green: 0.1, blue: 0.07) : Color(red: 0.1, green: 0.085, blue: 0.075)
        let lit = Color(red: 1, green: 0.97, blue: 0.88).opacity(0.85), shade = Color(red: 0.3, green: 0.15, blue: 0.04).opacity(0.35)
        let groove = disc(0.74), w = max(1, r * 0.055)
        g.stroke(groove.applying(CGAffineTransform(translationX: r * 0.03, y: r * 0.04)), with: .color(lit), lineWidth: w)
        g.stroke(groove, with: .color(colour.opacity(0.9)), lineWidth: w)
        guard let glyph = names[name] else {
            g.draw(Text(name).font(.system(size: r * 1.05, weight: .heavy)).foregroundColor(colour), at: p)
            return
        }
        let type = r * 1.14, cut = glyph.applying(CGAffineTransform(a: type, b: 0, c: 0, d: type, tx: p.x, ty: p.y))
        g.fill(cut.applying(CGAffineTransform(translationX: r * 0.035, y: r * 0.045)), with: .color(lit))
        g.fill(cut.applying(CGAffineTransform(translationX: -r * 0.02, y: -r * 0.025)), with: .color(shade))
        g.fill(cut, with: .linearGradient(Gradient(colors: red ? [Color(red: 0.84, green: 0.16, blue: 0.1), Color(red: 0.6, green: 0.06, blue: 0.04)]
                                                                : [Color(red: 0.24, green: 0.21, blue: 0.19), Color(red: 0.03, green: 0.025, blue: 0.02)]),
                                          startPoint: CGPoint(x: p.x, y: p.y - r * 0.5), endPoint: CGPoint(x: p.x, y: p.y + r * 0.5)))
    }
}
