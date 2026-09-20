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
    let howToJudge = "Checkmate wins at once and is always best. Never choose a move that allows checkmate. Winning material is good and losing it is bad: a queen is worth 9, a rook 5, a bishop or a knight 3, a pawn 1. When material comes out the same, prefer castling early, developing knights and bishops, and pawns in the center; avoid bringing the queen out early, moving the king and giving up castling, or retreating for no reason. Giving check is only good if it does not lose material."
    let sides = ["白方", "黑方"]

    private var position = ChessPosition()
    private var seen: [String: Int] = [:]
    private var moves: [ChessPosition.Move] = []
    private var last: ChessPosition.Move?
    private(set) var plies = 0
    private(set) var result: String?
    private var dice = JevDice(seed: 1)

    var turn: Int { position.whiteToMove ? 0 : 1 }
    var over: Bool { result != nil }
    var score: Int { position.material }
    var status: String {
        let balance = position.material == 0 ? "子力相当" : position.material > 0 ? "白方多 \(position.material) 分" : "黑方多 \(-position.material) 分"
        return result ?? "第 \(plies / 2 + 1) 回合 · 轮到\(sides[turn]) · \(balance)" + (position.inCheck(white: position.whiteToMove) ? " · 将军" : "")
    }
    var situation: String {
        let me = position.whiteToMove ? "White" : "Black", mine = position.whiteToMove ? 1 : -1
        let balance = mine * position.material
        return "\(me) to play, move \(plies / 2 + 1); material: \(balance == 0 ? "even" : balance > 0 ? "\(me) is up \(balance)" : "\(me) is down \(-balance)")"
            + (position.inCheck(white: position.whiteToMove) ? "; \(me) is in check" : "")
    }

    private static let glyphs = ["", "♟", "♞", "♝", "♜", "♛", "♚"]
    var grid: [[JevCell]] {
        (0..<8).map { row in (0..<8).map { col in
            let index = row * 8 + col, piece = position.board[index]
            let moved = last.map { $0.from == index || $0.to == index } ?? false
            let base = (row + col) % 2 == 0 ? Color(red: 0.93, green: 0.86, blue: 0.72) : Color(red: 0.62, green: 0.46, blue: 0.32)
            return JevCell(colour: moved ? Color.yellow.opacity(0.75) : base, text: Self.glyphs[Int(abs(piece))],
                           ink: piece > 0 ? .white : .black, big: true)
        } }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        position = ChessPosition(); seen = [position.key: 1]; last = nil; plies = 0; result = nil
        dice = JevDice(seed: seed)
    }

    func options() -> [JevOption] {
        guard result == nil else { return [] }
        let legal = position.legalMoves()
        if legal.isEmpty {
            result = position.inCheck(white: position.whiteToMove) ? "将死 · \(sides[1 - turn])赢了（\(plies / 2 + 1) 回合）" : "逼和 · 和棋"
            return []
        }
        let judged = legal.map { ($0, position.outcome(of: $0)) }
        let mine = position.whiteToMove ? 1 : -1, now = mine * position.material
        // The shortlist: the evaluator's best eight, then whatever a player is
        // likely to be tempted by and must be allowed to get wrong.
        var keep = Set(judged.sorted { $0.1.value > $1.1.value }.prefix(8).map { legal.firstIndex(of: $0.0)! })
        func also(_ wanted: (ChessPosition.Move) -> Bool, atMost: Int) {
            for (index, move) in legal.enumerated() where wanted(move) && keep.count < 12 && !keep.contains(index) {
                keep.insert(index)
                if keep.count >= 12 || legal.enumerated().filter({ keep.contains($0.offset) && wanted($0.element) }).count >= atMost { break }
            }
        }
        also({ $0.castle }, atMost: 2)
        also({ self.position.board[$0.to] != 0 }, atMost: 4)
        also({ var next = self.position; next.play($0); return next.inCheck(white: next.whiteToMove) }, atMost: 3)
        moves = keep.sorted().map { legal[$0] }                  // in board order, which favours nobody
        return moves.enumerated().map { index, move in
            let found = judged[legal.firstIndex(of: move)!].1
            return JevOption(id: String(format: "p%02d", index + 1), label: describe(move, outcome: found, now: now),
                             merit: Double(found.value) + Double(dice.below(3)) * 0.001, move: index)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        let move = moves[option.move]
        position.play(move)
        last = move; plies += 1
        seen[position.key, default: 0] += 1
        if position.legalMoves().isEmpty {
            result = position.inCheck(white: position.whiteToMove) ? "将死 · \(sides[1 - turn])赢了（\((plies + 1) / 2) 回合）" : "逼和 · 和棋"
        } else if seen[position.key, default: 0] >= 3 { result = "同一局面出现三次 · 和棋"
        } else if position.halfmoves >= 100 { result = "五十回合没有吃子也没有动兵 · 和棋"
        } else if position.deadPosition { result = "双方都将不死了 · 和棋"
        } else if plies >= 400 { result = "下满 200 回合 · 和棋" }
    }

    /// One move, in words: what it is, what it does, and how it comes out.
    private func describe(_ move: ChessPosition.Move, outcome: (value: Int, material: Int), now: Int) -> String {
        let board = position.board, piece = Int(abs(board[move.from])), white = position.whiteToMove
        var parts: [String] = []
        if move.castle { parts.append(move.to > move.from ? "castles kingside: king to safety, rook into play" : "castles queenside: king to safety, rook into play") }
        if move.enPassant { parts.append("captures a pawn en passant") }
        else if board[move.to] != 0 { parts.append("captures the \(ChessPosition.names[Int(abs(board[move.to]))])") }
        if move.promotion != 0 { parts.append("promotes to a \(ChessPosition.names[Int(move.promotion)])") }
        var next = position
        next.play(move)
        if outcome.value >= 1_000_000 { parts.append("checkmate: wins the game at once") }
        else if next.inCheck(white: next.whiteToMove) { parts.append("gives check") }
        let home = white ? 7 : 0, opening = plies < 20
        if (piece == 2 || piece == 3), move.from / 8 == home, move.to / 8 != home { parts.append("develops the \(ChessPosition.names[piece])") }
        if piece == 1, [27, 28, 35, 36].contains(move.to) { parts.append("puts a pawn in the center") }
        if piece == 5, opening, board[move.to] == 0 { parts.append("brings the queen out early") }
        if piece == 6, !move.castle, white ? (position.castling.wk || position.castling.wq) : (position.castling.bk || position.castling.bq) {
            parts.append("moves the king and gives up castling")
        }
        if outcome.value <= -1_000_000 { parts.append("allows checkmate next move: loses the game") }
        else if outcome.value < 1_000_000 {
            let change = outcome.material - now
            parts.append(change >= 1 ? "after the best reply comes out \(change) ahead in material"
                         : change <= -1 ? "after the best reply comes out \(-change) behind in material: it loses material"
                         : "material stays the same after the best reply")
        }
        return "\(ChessPosition.names[piece]) \(ChessPosition.square(move.from)) to \(ChessPosition.square(move.to)): " + parts.joined(separator: "; ")
    }
}
