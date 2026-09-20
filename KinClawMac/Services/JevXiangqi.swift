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
    let howToJudge = "Checkmate wins at once and is always best. Never choose a move that allows checkmate. Winning material is good and losing it is bad: a chariot is worth 9, a cannon 4.5, a horse 4, an elephant or an advisor 2, a soldier 1, or 2 once it has crossed the river. When material comes out the same, prefer bringing the chariots out early, developing the horses, a cannon on the central file, and soldiers across the river; avoid moving the general, or the advisors and elephants that guard him, for no reason, and avoid retreating for no reason. Giving check is only good if it does not lose material."
    let sides = ["红方", "黑方"]

    private var position = XiangqiPosition()
    private var seen: [String: Int] = [:]
    private var moves: [XiangqiPosition.Move] = []
    private var last: XiangqiPosition.Move?
    private var lastWritten = ""
    private(set) var plies = 0
    private(set) var result: String?
    private var dice = JevDice(seed: 1)

    var turn: Int { position.redToMove ? 0 : 1 }
    var over: Bool { result != nil }
    var score: Int { position.material / 2 }
    var status: String {
        if let result { return result + (lastWritten.isEmpty ? "" : " · 最后一步 \(lastWritten)") }
        let ahead = position.material
        let balance = ahead == 0 ? "子力相当" : "\(ahead > 0 ? "红方" : "黑方")多 \(Self.points(abs(ahead))) 分"
        return "第 \(plies / 2 + 1) 回合 · 轮到\(sides[turn]) · \(balance)" + (position.inCheck(red: position.redToMove) ? " · 将军" : "")
            + (lastWritten.isEmpty ? "" : " · 上一步 \(lastWritten)")
    }
    var situation: String {
        let me = position.redToMove ? "Red" : "Black", balance = (position.redToMove ? 1 : -1) * position.material
        return "\(me) to play, move \(plies / 2 + 1); material: "
            + (balance == 0 ? "even" : balance > 0 ? "\(me) is up \(Self.points(balance))" : "\(me) is down \(Self.points(-balance))")
            + (position.inCheck(red: position.redToMove) ? "; \(me) is in check" : "")
    }

    /// Half points as they are spoken: 9 is "4.5".
    private static func points(_ half: Int) -> String { half % 2 == 0 ? "\(half / 2)" : "\(half / 2).5" }

    nonisolated private static let red = ["", "兵", "仕", "相", "马", "炮", "车", "帅"]
    nonisolated private static let black = ["", "卒", "士", "象", "马", "炮", "车", "将"]
    private static let wood = Color(red: 0.87, green: 0.72, blue: 0.49), palace = Color(red: 0.80, green: 0.64, blue: 0.41)
    private static let river = Color(red: 0.74, green: 0.80, blue: 0.78), disc = Color(red: 0.97, green: 0.91, blue: 0.78)

    var grid: [[JevCell]] {
        (0..<10).map { row in (0..<9).map { col in
            let index = row * 9 + col, piece = position.board[index], kind = Int(abs(piece))
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
        position = XiangqiPosition(); seen = [position.key: 1]; last = nil; lastWritten = ""; plies = 0; result = nil
        dice = JevDice(seed: seed)
    }

    func options() -> [JevOption] {
        guard result == nil else { return [] }
        let legal = position.legalMoves()
        if legal.isEmpty { result = ending(); return [] }
        let judged = legal.map { ($0, position.outcome(of: $0)) }
        let now = (position.redToMove ? 1 : -1) * position.material
        // The shortlist: the evaluator's best eight, then what tempts.
        var keep = Set(judged.enumerated().sorted { $0.element.1.value > $1.element.1.value }.prefix(8).map { $0.offset })
        func also(_ wanted: (XiangqiPosition.Move) -> Bool, atMost: Int) {
            var added = legal.enumerated().filter { keep.contains($0.offset) && wanted($0.element) }.count
            for (index, move) in legal.enumerated() where keep.count < 12 && added < atMost && !keep.contains(index) && wanted(move) {
                keep.insert(index); added += 1
            }
        }
        also({ self.position.board[$0.to] != 0 }, atMost: 4)
        also({ var next = self.position; next.play($0); return next.inCheck(red: next.redToMove) }, atMost: 3)
        let chosen = keep.sorted()                               // in board order, which favours nobody
        moves = chosen.map { legal[$0] }
        return chosen.enumerated().map { index, which in
            let found = judged[which].1
            return JevOption(id: String(format: "p%02d", index + 1), label: describe(legal[which], outcome: found, now: now),
                             merit: Double(found.value) + Double(dice.below(3)) * 0.001, move: index)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        let move = moves[option.move]
        lastWritten = Self.written(move, in: position)
        position.play(move)
        last = move; plies += 1
        seen[position.key, default: 0] += 1
        if !position.canMove { result = ending()
        } else if seen[position.key, default: 0] >= 3 { result = "同一局面出现三次 · 和棋"
        } else if position.quiet >= 120 { result = "六十回合没有吃子 · 和棋"
        } else if position.deadPosition { result = "双方都没有能过河的子了 · 和棋"
        } else if plies >= 400 { result = "下满 200 回合 · 和棋" }
    }

    /// The side to move has nothing legal left: mated, or hemmed in — a loss either way.
    private func ending() -> String {
        let how = position.inCheck(red: position.redToMove) ? "绝杀" : "困毙"
        return "\(how) · \(sides[1 - turn])赢了（\((plies + 1) / 2) 回合）"
    }

    /// One move, in words: what it is, what it does, and how it comes out.
    private func describe(_ move: XiangqiPosition.Move, outcome: (value: Int, material: Int), now: Int) -> String {
        let board = position.board, piece = Int(abs(board[move.from])), red = position.redToMove
        let fromRow = move.from / 9, toRow = move.to / 9, toCol = move.to % 9
        /// Ranks counted from the mover's own back rank.
        func rank(_ row: Int) -> Int { red ? 9 - row : row }
        var parts: [String] = []
        if board[move.to] != 0 {
            let taken = Int(abs(board[move.to]))
            parts.append("captures " + (taken == 1 && rank(toRow) <= 4 ? "a soldier that has crossed the river" : "the \(XiangqiPosition.names[taken])"))
        }
        var next = position
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
        if piece == 7, board[move.to] == 0, !position.inCheck(red: red) { parts.append("moves the general, which was not in check") }
        if (piece == 2 || piece == 3), opening, board[move.to] == 0, !position.inCheck(red: red) { parts.append("moves one of the general's guards") }
        if piece != 1, piece != 7, rank(toRow) < rank(fromRow), board[move.to] == 0 { parts.append("retreats") }
        if outcome.value <= -1_000_000 { parts.append("allows checkmate next move: loses the game") }
        else if outcome.value < 1_000_000 {
            let change = outcome.material - now
            parts.append(change >= 1 ? "after the best reply comes out \(Self.points(change)) ahead in material"
                         : change <= -1 ? "after the best reply comes out \(Self.points(-change)) behind in material: it loses material"
                         : "material stays the same after the best reply")
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
