import SwiftUI

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

    private var state = XiangqiPosition()
    private var seen: [String: Int] = [:]
    private var moves: [XiangqiPosition.Move] = []
    private var last: XiangqiPosition.Move?
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
            return JevCell(colour: moved ? Color.yellow.opacity(0.8) : ground,
                           text: piece > 0 ? Self.red[kind] : Self.black[kind],
                           ink: piece > 0 ? Color(red: 0.75, green: 0.08, blue: 0.06) : Color(red: 0.08, green: 0.08, blue: 0.10),
                           big: true, disc: piece == 0 ? nil : Self.disc)
        } }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        state = XiangqiPosition(); seen = [state.key: 1]; last = nil; lastWritten = ""; played = []; plies = 0; result = nil
        dice = JevDice(seed: seed)
    }

    func options() -> [JevOption] {
        guard result == nil else { return [] }
        let legal = state.legalMoves()
        if legal.isEmpty { result = ending(); return [] }
        let judged = legal.map { ($0, state.outcome(of: $0)) }
        let now = (state.redToMove ? 1 : -1) * state.material
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
        state.play(move)
        last = move; plies += 1
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
