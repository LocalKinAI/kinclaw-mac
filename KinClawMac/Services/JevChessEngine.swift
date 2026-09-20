import Foundation

/// Chess, as much of it as a fair game needs: every rule that decides what is
/// legal and when a game is over. No SwiftUI in here, so that the move
/// generator can be compiled on its own and counted against the published
/// perft numbers — the only way to know a chess engine's rules are right.
struct ChessPosition {
    /// 64 squares, a8 first, h1 last (row 0 is the eighth rank, as it is drawn).
    /// White is positive: 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king.
    var board = [Int8](repeating: 0, count: 64)
    var whiteToMove = true
    var castling: (wk: Bool, wq: Bool, bk: Bool, bq: Bool) = (true, true, true, true)
    var enPassant: Int?
    var halfmoves = 0

    struct Move: Equatable {
        var from: Int, to: Int
        var promotion: Int8 = 0
        var castle = false, enPassant = false
    }

    static let names = ["", "pawn", "knight", "bishop", "rook", "queen", "king"]
    static let worth = [0, 1, 3, 3, 5, 9, 0]

    static func square(_ index: Int) -> String { "\("abcdefgh".map { String($0) }[index % 8])\(8 - index / 8)" }

    init() { self.init(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") }

    init(fen: String) {
        let parts = fen.split(separator: " ").map(String.init)
        var at = 0
        for ch in parts[0] where ch != "/" {
            if let gap = ch.wholeNumberValue { at += gap; continue }
            let kind = Int8("pnbrqk".firstIndex(of: Character(ch.lowercased())).map { "pnbrqk".distance(from: "pnbrqk".startIndex, to: $0) + 1 } ?? 0)
            board[at] = ch.isUppercase ? kind : -kind
            at += 1
        }
        whiteToMove = parts.count < 2 || parts[1] == "w"
        let rights = parts.count > 2 ? parts[2] : "-"
        castling = (rights.contains("K"), rights.contains("Q"), rights.contains("k"), rights.contains("q"))
        if parts.count > 3, parts[3] != "-", let file = "abcdefgh".firstIndex(of: parts[3].first!), let rank = parts[3].last?.wholeNumberValue {
            enPassant = (8 - rank) * 8 + "abcdefgh".distance(from: "abcdefgh".startIndex, to: file)
        }
        halfmoves = parts.count > 4 ? Int(parts[4]) ?? 0 : 0
    }

    /// What repeats when a position repeats: the squares, whose move, the rights.
    var key: String {
        board.map { String($0) }.joined(separator: ",") + (whiteToMove ? "w" : "b")
            + "\(castling.wk)\(castling.wq)\(castling.bk)\(castling.bq)\(enPassant ?? -1)"
    }

    // MARK: Attacks

    private static let knightSteps = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
    private static let kingSteps = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    private static let straight = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    private static let diagonal = [(-1, -1), (-1, 1), (1, -1), (1, 1)]

    /// The pieces of one colour that attack a square, as kinds (1…6).
    func attackers(of target: Int, white: Bool) -> [Int] {
        let row = target / 8, col = target % 8, sign: Int8 = white ? 1 : -1
        var found: [Int] = []
        func piece(_ r: Int, _ c: Int) -> Int8? { r >= 0 && r < 8 && c >= 0 && c < 8 ? board[r * 8 + c] : nil }
        // A white pawn attacks upward, so it sits one row below its target.
        for dc in [-1, 1] where piece(row + (white ? 1 : -1), col + dc) == sign { found.append(1) }
        for (dr, dc) in Self.knightSteps where piece(row + dr, col + dc) == 2 * sign { found.append(2) }
        for (dr, dc) in Self.kingSteps where piece(row + dr, col + dc) == 6 * sign { found.append(6) }
        for (steps, slider) in [(Self.straight, Int8(4)), (Self.diagonal, Int8(3))] {
            for (dr, dc) in steps {
                var r = row + dr, c = col + dc
                while let p = piece(r, c) {
                    if p != 0 { if p == slider * sign || p == 5 * sign { found.append(Int(abs(p))) }; break }
                    r += dr; c += dc
                }
            }
        }
        return found
    }

    func attacked(_ target: Int, byWhite white: Bool) -> Bool { !attackers(of: target, white: white).isEmpty }

    func king(white: Bool) -> Int? { board.firstIndex(of: white ? 6 : -6) }

    func inCheck(white: Bool) -> Bool { king(white: white).map { attacked($0, byWhite: !white) } ?? false }

    // MARK: Moves

    func legalMoves() -> [Move] {
        pseudoMoves().filter { move in
            var next = self
            next.play(move)
            return !next.inCheck(white: whiteToMove)
        }
    }

    private func pseudoMoves() -> [Move] {
        var moves: [Move] = []
        let white = whiteToMove, sign: Int8 = white ? 1 : -1
        for from in 0..<64 where board[from] * sign > 0 {
            let kind = abs(board[from]), row = from / 8, col = from % 8
            func add(_ r: Int, _ c: Int) -> Bool {             // true while a slider may go on
                guard r >= 0, r < 8, c >= 0, c < 8 else { return false }
                let target = board[r * 8 + c]
                if target * sign > 0 { return false }
                moves.append(Move(from: from, to: r * 8 + c))
                return target == 0
            }
            switch kind {
            case 1:
                let ahead = white ? -1 : 1, start = white ? 6 : 1, last = white ? 0 : 7
                func push(_ to: Int, enPassant: Bool = false) {
                    if to / 8 == last { for promo in [Int8(5), 4, 3, 2] { moves.append(Move(from: from, to: to, promotion: promo)) } }
                    else { moves.append(Move(from: from, to: to, enPassant: enPassant)) }
                }
                let one = (row + ahead) * 8 + col
                if row + ahead >= 0, row + ahead < 8, board[one] == 0 {
                    push(one)
                    if row == start, board[(row + 2 * ahead) * 8 + col] == 0 { moves.append(Move(from: from, to: (row + 2 * ahead) * 8 + col)) }
                }
                for dc in [-1, 1] where col + dc >= 0 && col + dc < 8 && row + ahead >= 0 && row + ahead < 8 {
                    let to = (row + ahead) * 8 + col + dc
                    if board[to] * sign < 0 { push(to) } else if to == enPassant { push(to, enPassant: true) }
                }
            case 2: for (dr, dc) in Self.knightSteps { _ = add(row + dr, col + dc) }
            case 6:
                for (dr, dc) in Self.kingSteps { _ = add(row + dr, col + dc) }
                let home = white ? 60 : 4
                if from == home, !attacked(home, byWhite: !white) {
                    let (short, long) = white ? (castling.wk, castling.wq) : (castling.bk, castling.bq)
                    if short, board[home + 1] == 0, board[home + 2] == 0, board[home + 3] == 4 * sign,
                       !attacked(home + 1, byWhite: !white), !attacked(home + 2, byWhite: !white) {
                        moves.append(Move(from: home, to: home + 2, castle: true))
                    }
                    if long, board[home - 1] == 0, board[home - 2] == 0, board[home - 3] == 0, board[home - 4] == 4 * sign,
                       !attacked(home - 1, byWhite: !white), !attacked(home - 2, byWhite: !white) {
                        moves.append(Move(from: home, to: home - 2, castle: true))
                    }
                }
            default:
                let steps = kind == 3 ? Self.diagonal : kind == 4 ? Self.straight : Self.diagonal + Self.straight
                for (dr, dc) in steps {
                    var r = row + dr, c = col + dc
                    while add(r, c) { r += dr; c += dc }
                }
            }
        }
        return moves
    }

    mutating func play(_ move: Move) {
        let piece = board[move.from], white = piece > 0
        let quiet = board[move.to] == 0 && abs(piece) != 1
        if move.enPassant { board[move.to + (white ? 8 : -8)] = 0 }
        board[move.to] = move.promotion != 0 ? (white ? move.promotion : -move.promotion) : piece
        board[move.from] = 0
        if move.castle {
            if move.to > move.from { board[move.to - 1] = board[move.to + 1]; board[move.to + 1] = 0 }
            else { board[move.to + 1] = board[move.to - 2]; board[move.to - 2] = 0 }
        }
        enPassant = abs(piece) == 1 && abs(move.to - move.from) == 16 ? (move.from + move.to) / 2 : nil
        // A king that has moved, or a rook that has moved or been taken, cannot castle.
        for touched in [move.from, move.to] {
            switch touched {
            case 60: castling.wk = false; castling.wq = false
            case 4: castling.bk = false; castling.bq = false
            case 63: castling.wk = false
            case 56: castling.wq = false
            case 7: castling.bk = false
            case 0: castling.bq = false
            default: break
            }
        }
        halfmoves = quiet ? halfmoves + 1 : 0
        whiteToMove.toggle()
    }

    /// Positions reachable in `depth` moves: the number every engine agrees on.
    func perft(_ depth: Int) -> Int {
        guard depth > 0 else { return 1 }
        let moves = legalMoves()
        if depth == 1 { return moves.count }
        return moves.reduce(0) { total, move in var next = self; next.play(move); return total + next.perft(depth - 1) }
    }

    // MARK: Judging, for the shortlist and the yardstick

    /// Material, in pawns, from White's side.
    var material: Int { board.reduce(0) { $0 + Self.worth[Int(abs($1))] * ($1 > 0 ? 1 : $1 < 0 ? -1 : 0) } }

    /// Material and a little position, in hundredths of a pawn, from White's side.
    func evaluation() -> Int {
        var total = 0
        for (index, piece) in board.enumerated() where piece != 0 {
            let kind = Int(abs(piece)), row = index / 8, col = index % 8, sign = piece > 0 ? 1 : -1
            var value = [0, 100, 320, 330, 500, 900, 0][kind]
            let central = 3 - max(abs(2 * col - 7), abs(2 * row - 7)) / 2         // 0 at the rim, 3 in the centre
            if kind == 2 || kind == 3 { value += 8 * central; if row == (piece > 0 ? 7 : 0) { value -= 12 } }   // undeveloped
            if kind == 1 { value += 4 * central + 3 * (piece > 0 ? 6 - row : row - 1) }
            if kind == 6 { value += (col <= 2 || col >= 6) && row == (piece > 0 ? 7 : 0) ? 25 : 0 }              // tucked away
            total += sign * value
        }
        return total
    }

    /// What a move comes to for the side making it once the other side has
    /// made its best reply: a value in hundredths of a pawn (mate is a very
    /// large number), and the material balance at that point, in pawns.
    func outcome(of move: Move) -> (value: Int, material: Int) {
        let mine = whiteToMove ? 1 : -1
        var next = self
        next.play(move)
        let replies = next.legalMoves()
        if replies.isEmpty { return (next.inCheck(white: next.whiteToMove) ? 1_000_000 : 0, mine * next.material) }
        var worst = (value: Int.max, material: 0)
        for reply in replies {
            var after = next
            after.play(reply)
            var value = mine * after.evaluation()
            // Their reply may itself be answered: a capture I can take back is
            // a trade, not a loss. One more look, at captures only.
            if let back = after.legalMoves().filter({ after.board[$0.to] != 0 })
                .map({ m -> Int in var last = after; last.play(m); return mine * last.evaluation() }).max() { value = max(value, back) }
            if after.legalMoves().isEmpty { value = after.inCheck(white: after.whiteToMove) ? -1_000_000 : 0 }
            if value < worst.value { worst = (value, mine * after.material) }
        }
        return worst
    }

    /// Too little left on the board for anybody to be mated.
    var deadPosition: Bool {
        let left = board.filter { $0 != 0 && abs($0) != 6 }.map { abs($0) }
        return left.isEmpty || (left.count == 1 && (left[0] == 2 || left[0] == 3))
    }
}
