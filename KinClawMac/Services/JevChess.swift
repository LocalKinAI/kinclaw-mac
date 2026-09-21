import SwiftUI

/// Chess for two players who read words.
///
/// The same division of labour as the other games, with more to measure: the
/// program generates the legal moves (the engine's move generator agrees with
/// the published perft counts on five standard positions), looks one reply
/// ahead for each — and one recapture past that — and says what it found:
/// what is captured, whether it is check or mate, what it does for
/// development, and how the material stands after the opponent's best reply.
/// The players choose among a dozen candidates. A dozen because that is what
/// Laya can read at once, and both sides must be asked the same question; and
/// not simply the evaluator's best dozen, which would be the evaluator playing
/// — every check, every castle and the tempting captures are in the list
/// whether they are good or not, so there is something to judge.
@MainActor
final class JevChess: JevGame {
    let id = "chess", title = "国际象棋", symbol = "crown"
    let rules = "Chess. Each option is one legal move for the side to play. The game is won by checkmate; it is drawn by stalemate, threefold repetition, fifty moves without a capture or pawn move, or when neither side has enough left to mate."
    let question = "Which move is best for the side to play?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: checkmate wins at once and is always best; a forced checkmate is next best. Second: never choose a move that allows checkmate. Third: the material result decides — a move that comes out behind in material is worse than every move that keeps material the same, whatever else it does; a move that comes out ahead is better than every move that does not, and further ahead is better. A queen is worth 9, a rook 5, a bishop or a knight 3, a pawn 1. Fourth, and only among moves with the same material result: prefer a move that threatens checkmate, then one that threatens to win material, the bigger threat first — the opponent has to answer a threat. Fifth: prefer castling early, developing knights and bishops, and pawns in the center; avoid bringing the queen out early, moving the king and giving up castling, retreating, and repeating a position unless you are behind — but only when it costs nothing above."
    let sides = ["白方", "黑方"]

    private var position_ = ChessPosition()
    private var seen: [String: Int] = [:]
    private var moves: [ChessPosition.Move] = []
    private var last: ChessPosition.Move?
    private var played: [String] = []
    private(set) var plies = 0
    private(set) var result: String?
    private var dice = JevDice(seed: 1)
    /// How many plies past the move the words look, when somebody insists (the
    /// test harness does). Otherwise: three for a reader, one — what the
    /// evaluator that plays looks — for anybody else. See `JevXiangqi`, where
    /// this was worked out: a reader beats the evaluator only by being told
    /// something the evaluator does not know.
    nonisolated(unsafe) static var foresight: Int?
    private var reader = false
    private var depth: Int { Self.foresight ?? (reader ? 3 : 1) }

    func prepare(reader: Bool) { self.reader = reader }

    var turn: Int { position_.whiteToMove ? 0 : 1 }
    var over: Bool { result != nil }
    var score: Int { position_.material }
    var status: String {
        let balance = position_.material == 0 ? "子力相当" : position_.material > 0 ? "白方多 \(position_.material) 分" : "黑方多 \(-position_.material) 分"
        return result ?? "第 \(plies / 2 + 1) 回合 · 轮到\(sides[turn]) · \(balance)" + (position_.inCheck(white: position_.whiteToMove) ? " · 将军" : "")
    }
    var situation: String {
        let me = position_.whiteToMove ? "White" : "Black", mine = position_.whiteToMove ? 1 : -1
        let balance = mine * position_.material
        return "\(me) to play, move \(plies / 2 + 1); material: \(balance == 0 ? "even" : balance > 0 ? "\(me) is up \(balance)" : "\(me) is down \(-balance)")"
            + (position_.inCheck(white: position_.whiteToMove) ? "; \(me) is in check" : "")
    }

    var position: String {
        let letters = Array(".PNBRQK"), diagram = (0..<8).map { row in
            "\(8 - row) " + (0..<8).map { col -> String in
                let piece = position_.board[row * 8 + col], letter = String(letters[Int(abs(piece))])
                return piece < 0 ? letter.lowercased() : letter
            }.joined(separator: " ")
        }.joined(separator: "\n")
        return "FEN: \(position_.fen(move: plies / 2 + 1))\n\(diagram)\n  a b c d e f g h   (uppercase is White)\n"
            + "Moves so far: " + (played.isEmpty ? "none" : played.suffix(24).joined(separator: " "))
    }

    private static let glyphs = ["", "♟", "♞", "♝", "♜", "♛", "♚"]
    var grid: [[JevCell]] {
        (0..<8).map { row in (0..<8).map { col in
            let index = row * 8 + col, piece = position_.board[index]
            let moved = last.map { $0.from == index || $0.to == index } ?? false
            let base = (row + col) % 2 == 0 ? Color(red: 0.93, green: 0.86, blue: 0.72) : Color(red: 0.62, green: 0.46, blue: 0.32)
            return JevCell(colour: moved ? Color.yellow.opacity(0.75) : base, text: Self.glyphs[Int(abs(piece))],
                           ink: piece > 0 ? .white : .black, big: true)
        } }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        position_ = ChessPosition(); seen = [position_.key: 1]; last = nil; played = []; plies = 0; result = nil
        dice = JevDice(seed: seed)
    }

    func options() -> [JevOption] {
        guard result == nil else { return [] }
        let legal = position_.legalMoves()
        if legal.isEmpty {
            result = position_.inCheck(white: position_.whiteToMove) ? "将死 · \(sides[1 - turn])赢了（\(plies / 2 + 1) 回合）" : "逼和 · 和棋"
            return []
        }
        let judged = legal.map { ($0, position_.outcome(of: $0)) }
        let mine = position_.whiteToMove ? 1 : -1, now = mine * position_.material
        // The shortlist: the evaluator's best eight, then whatever a player is
        // likely to be tempted by and must be allowed to get wrong.
        let depth = self.depth
        var keep = Set(judged.sorted { $0.1.value > $1.1.value }.prefix(depth > 1 ? 5 : 8).map { legal.firstIndex(of: $0.0)! })
        // For a reader the words look further than the evaluator that plays does,
        // and what looks best further on belongs on the list too.
        let further = depth > 1 ? legal.map { position_.foresight(of: $0, plies: depth) } : []
        if depth > 1 {
            for index in further.indices.sorted(by: { further[$0].value > further[$1].value }).prefix(4) { keep.insert(index) }
        }
        func also(_ wanted: (ChessPosition.Move) -> Bool, atMost: Int) {
            for (index, move) in legal.enumerated() where wanted(move) && keep.count < 12 && !keep.contains(index) {
                keep.insert(index)
                if keep.count >= 12 || legal.enumerated().filter({ keep.contains($0.offset) && wanted($0.element) }).count >= atMost { break }
            }
        }
        also({ $0.castle }, atMost: 2)
        also({ position_.board[$0.to] != 0 }, atMost: 4)
        also({ var next = self.position_; next.play($0); return next.inCheck(white: next.whiteToMove) }, atMost: 3)
        var chosen = keep.sorted()                               // in board order, which favours nobody
        if depth > 1 {
            // The program does not ask what it already knows: moves that come out
            // worse in material than another on the list are taken off it, and a
            // forced mate is the only thing offered.
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
        played.append(ChessPosition.square(move.from) + ChessPosition.square(move.to)
                      + (move.promotion != 0 ? String(Array("pnbrqk")[Int(move.promotion) - 1]) : ""))
        position_.play(move)
        last = move; plies += 1
        seen[position_.key, default: 0] += 1
        if position_.legalMoves().isEmpty {
            result = position_.inCheck(white: position_.whiteToMove) ? "将死 · \(sides[1 - turn])赢了（\((plies + 1) / 2) 回合）" : "逼和 · 和棋"
        } else if seen[position_.key, default: 0] >= 3 { result = "同一局面出现三次 · 和棋"
        } else if position_.halfmoves >= 100 { result = "五十回合没有吃子也没有动兵 · 和棋"
        } else if position_.deadPosition { result = "双方都将不死了 · 和棋"
        } else if plies >= 400 { result = "下满 200 回合 · 和棋" }
    }

    /// One move, in words: what it is, what it does, and how it comes out.
    private func describe(_ move: ChessPosition.Move, outcome: (value: Int, material: Int),
                          further: (value: Int, material: Int)?, now: Int) -> String {
        let depth = self.depth
        let board = position_.board, piece = Int(abs(board[move.from])), white = position_.whiteToMove
        var parts: [String] = []
        if move.castle { parts.append(move.to > move.from ? "castles kingside: king to safety, rook into play" : "castles queenside: king to safety, rook into play") }
        if move.enPassant { parts.append("captures a pawn en passant") }
        else if board[move.to] != 0 { parts.append("captures the \(ChessPosition.names[Int(abs(board[move.to]))])") }
        if move.promotion != 0 { parts.append("promotes to a \(ChessPosition.names[Int(move.promotion)])") }
        var next = position_
        next.play(move)
        if outcome.value >= 1_000_000 { parts.append("checkmate: wins the game at once") }
        else if next.inCheck(white: next.whiteToMove) { parts.append("gives check") }
        let home = white ? 7 : 0, opening = plies < 20
        if (piece == 2 || piece == 3), move.from / 8 == home, move.to / 8 != home { parts.append("develops the \(ChessPosition.names[piece])") }
        if piece == 1, [27, 28, 35, 36].contains(move.to) { parts.append("puts a pawn in the center") }
        if piece == 5, opening, board[move.to] == 0 { parts.append("brings the queen out early") }
        if piece == 6, !move.castle, white ? (position_.castling.wk || position_.castling.wq) : (position_.castling.bk || position_.castling.bq) {
            parts.append("moves the king and gives up castling")
        }
        if seen[next.key, default: 0] >= 1 {
            parts.append("repeats a position that has already occurred" + (seen[next.key, default: 0] >= 2 ? ": the third time, which ends the game as a draw" : ""))
        }
        var outcome = outcome
        var horizon = "after the best reply"
        if let further, outcome.value < 1_000_000, outcome.value > -1_000_000 {
            // What the move is up to, further than the evaluator looks when it chooses for itself.
            let threat = position_.threat(after: move)
            if threat.mate { parts.append("threatens checkmate next move") }
            else if threat.gain >= 1 { parts.append("threatens to win \(threat.gain) in material next move") }
            outcome = further
            horizon = depth == 2 ? "after the best reply and your best answer to it" : "\(depth) moves on, with best play by both sides"
            if outcome.value >= 1_000_000 { parts.append("forces checkmate within \(depth) moves") }
        }
        if outcome.value <= -1_000_000 { parts.append(further != nil ? "allows a forced checkmate: loses the game" : "allows checkmate next move: loses the game") }
        else if outcome.value < 1_000_000 {
            let change = outcome.material - now
            parts.append(change >= 1 ? "\(horizon) comes out \(change) ahead in material"
                         : change <= -1 ? "\(horizon) comes out \(-change) behind in material: it loses material"
                         : "material stays the same \(horizon)")
        }
        return "\(ChessPosition.names[piece]) \(ChessPosition.square(move.from)) to \(ChessPosition.square(move.to)): " + parts.joined(separator: "; ")
    }
}
