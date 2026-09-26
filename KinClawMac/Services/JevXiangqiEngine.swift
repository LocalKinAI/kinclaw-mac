import Foundation

/// Xiangqi — Chinese chess — as much of it as a fair game needs: every rule
/// that decides what is legal and when a game is over. No SwiftUI in here, so
/// that the move generator can be compiled on its own and counted against the
/// published perft numbers, as the chess engine beside it was: the blocked
/// horse, the elephant's eye, the cannon's screen and the generals who may not
/// face each other are each one line that is easy to get almost right.
struct XiangqiPosition {
    /// 90 points, nine to a rank: Black's back rank first (row 0), Red's last
    /// (row 9) — as it is drawn, Red at the bottom. Red is positive:
    /// 1 soldier, 2 advisor, 3 elephant, 4 horse, 5 cannon, 6 chariot, 7 general.
    var board = [Int8](repeating: 0, count: 90)
    var redToMove = true
    /// Plies since anything was captured.
    var quiet = 0

    struct Move: Equatable { var from: Int, to: Int }

    static let names = ["", "soldier", "advisor", "elephant", "horse", "cannon", "chariot", "general"]
    /// In half points, so that a cannon's four and a half is a whole number.
    /// A soldier is worth twice this once it has crossed the river.
    static let worth = [0, 2, 4, 4, 8, 9, 18, 0]

    /// Files a–i from Red's left, ranks 0–9 from Red's back rank.
    static func square(_ index: Int) -> String { "\("abcdefghi".map { String($0) }[index % 9])\(9 - index / 9)" }

    init() { self.init(fen: "rheakaehr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RHEAKAEHR w - - 0 1") }

    /// Both spellings in use: h or n for the horse, e or b for the elephant.
    init(fen: String) {
        let parts = fen.split(separator: " ").map(String.init)
        let kinds: [Character: Int8] = ["p": 1, "a": 2, "e": 3, "b": 3, "h": 4, "n": 4, "c": 5, "r": 6, "k": 7]
        var at = 0
        for ch in parts[0] where ch != "/" {
            if let gap = ch.wholeNumberValue { at += gap; continue }
            guard at < 90, let kind = kinds[Character(ch.lowercased())] else { at += 1; continue }
            board[at] = ch.isUppercase ? kind : -kind
            at += 1
        }
        redToMove = parts.count < 2 || parts[1] == "w" || parts[1] == "r"
    }

    /// The position as xiangqi programs write it (n is the horse, b the elephant).
    func fen(move number: Int) -> String {
        var rows: [String] = []
        for row in 0..<10 {
            var text = "", gap = 0
            for col in 0..<9 {
                let piece = board[row * 9 + col]
                if piece == 0 { gap += 1; continue }
                if gap > 0 { text += String(gap); gap = 0 }
                let letter = String(Array("pabncrk")[Int(abs(piece)) - 1])
                text += piece > 0 ? letter.uppercased() : letter
            }
            rows.append(text + (gap > 0 ? String(gap) : ""))
        }
        return "\(rows.joined(separator: "/")) \(redToMove ? "w" : "b") - - \(quiet) \(number)"
    }

    /// What repeats when a position repeats: the points, and whose move.
    var key: String { board.map { String($0) }.joined(separator: ",") + (redToMove ? "r" : "b") }

    // MARK: Where things may stand

    private static let straight = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    private static let diagonal = [(-1, -1), (-1, 1), (1, -1), (1, 1)]

    private static func onBoard(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < 10 && c >= 0 && c < 9 }
    private static func inPalace(_ r: Int, _ c: Int, red: Bool) -> Bool { c >= 3 && c <= 5 && (red ? r >= 7 && r <= 9 : r >= 0 && r <= 2) }
    /// A side's own half: the river runs between rows 4 and 5.
    private static func atHome(_ r: Int, red: Bool) -> Bool { red ? r >= 5 : r <= 4 }

    // MARK: Check

    func general(red: Bool) -> Int? { board.firstIndex(of: red ? 7 : -7) }

    /// Is this side's general attacked — or looking straight at the other one
    /// down an open file, which the rules forbid and which comes to the same
    /// thing: the move that brought it about may not be made.
    func inCheck(red: Bool) -> Bool {
        guard let at = general(red: red) else { return true }
        let row = at / 9, col = at % 9, foe: Int8 = red ? -1 : 1
        // Along the lines: a chariot or the other general with nothing between,
        // a cannon with exactly one piece between, a soldier one step away.
        for (dr, dc) in Self.straight {
            var r = row + dr, c = col + dc, between = 0, steps = 1
            while Self.onBoard(r, c) {
                let piece = board[r * 9 + c]
                if piece != 0 {
                    let kind = abs(piece), theirs = piece * foe > 0
                    if between == 0 {
                        if theirs, kind == 6 { return true }
                        if theirs, kind == 7, dc == 0 { return true }
                        if theirs, kind == 1, steps == 1 {
                            // A soldier strikes forward — toward this general's
                            // end of the board — and, across the river, sideways.
                            let forward = red ? 1 : -1          // the way the enemy soldier walks
                            if dc == 0, dr == -forward { return true }
                            if dr == 0, !Self.atHome(r, red: !red) { return true }
                        }
                    } else if theirs, kind == 5 { return true }
                    between += 1
                    if between == 2 { break }
                }
                r += dr; c += dc; steps += 1
            }
        }
        // Horses: from each point a horse could strike from, if its leg is free.
        for (dr, dc) in [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)] {
            let r = row + dr, c = col + dc
            guard Self.onBoard(r, c), board[r * 9 + c] == 4 * foe else { continue }
            // The horse goes one step straight toward us first, then one diagonally.
            let legRow = abs(dr) == 2 ? r - dr / 2 : r, legCol = abs(dc) == 2 ? c - dc / 2 : c
            if board[legRow * 9 + legCol] == 0 { return true }
        }
        return false
    }

    // MARK: Moves

    func legalMoves(capturesOnly: Bool = false) -> [Move] {
        pseudoMoves().filter { move in
            if capturesOnly, board[move.to] == 0 { return false }
            var next = self
            next.play(move)
            return !next.inCheck(red: redToMove)
        }
    }

    /// Could the piece make this move by its own rules, whatever it does to its general?
    func isPseudoLegal(_ move: Move) -> Bool { pseudoMoves().contains(move) }

    private func pseudoMoves() -> [Move] {
        var moves: [Move] = []
        eachPseudoMove { moves.append($0); return false }
        return moves
    }

    /// Has the side to move anything legal at all? Stops at the first move
    /// that is — nearly always the first one tried — where listing them all
    /// to see whether the list is empty costs forty times as much. It is asked
    /// after every reply to every move, because being left without a move
    /// while NOT in check (困毙) loses too, and happens with a full palace: a
    /// shortcut that only looked when few pieces were left changed the
    /// evaluator's own game at move 59.
    var canMove: Bool {
        var found = false
        eachPseudoMove { move in
            var next = self
            next.play(move)
            found = !next.inCheck(red: redToMove)
            return found
        }
        return found
    }

    /// Every move the pieces could make, before asking whether it leaves the
    /// general attacked. `visit` says true to stop.
    private func eachPseudoMove(_ visit: (Move) -> Bool) {
        let red = redToMove, mine: Int8 = red ? 1 : -1
        var stop = false
        for from in 0..<90 where board[from] * mine > 0 {
            if stop { return }
            let row = from / 9, col = from % 9
            /// Go there if it is on the board and not one of our own.
            func go(_ r: Int, _ c: Int) {
                guard !stop, Self.onBoard(r, c), board[r * 9 + c] * mine <= 0 else { return }
                if visit(Move(from: from, to: r * 9 + c)) { stop = true }
            }
            switch abs(board[from]) {
            case 7:
                for (dr, dc) in Self.straight where Self.inPalace(row + dr, col + dc, red: red) { go(row + dr, col + dc) }
            case 2:
                for (dr, dc) in Self.diagonal where Self.inPalace(row + dr, col + dc, red: red) { go(row + dr, col + dc) }
            case 3:
                // Two points diagonally, never over the river, and not past a
                // piece standing on the point between — the elephant's eye.
                for (dr, dc) in Self.diagonal {
                    let r = row + 2 * dr, c = col + 2 * dc
                    if Self.onBoard(r, c), Self.atHome(r, red: red), board[(row + dr) * 9 + col + dc] == 0 { go(r, c) }
                }
            case 4:
                // One point straight, then one diagonally outward; a piece on
                // the first point — the horse's leg — stops both.
                for (dr, dc) in Self.straight where Self.onBoard(row + dr, col + dc) && board[(row + dr) * 9 + col + dc] == 0 {
                    if dc == 0 { go(row + 2 * dr, col - 1); go(row + 2 * dr, col + 1) }
                    else { go(row - 1, col + 2 * dc); go(row + 1, col + 2 * dc) }
                }
            case 6:
                for (dr, dc) in Self.straight {
                    var r = row + dr, c = col + dc
                    while Self.onBoard(r, c) {
                        go(r, c)
                        if board[r * 9 + c] != 0 { break }
                        r += dr; c += dc
                    }
                }
            case 5:
                // Moves like a chariot over empty points; captures only by
                // jumping exactly one piece, of either colour.
                for (dr, dc) in Self.straight {
                    var r = row + dr, c = col + dc
                    while Self.onBoard(r, c), board[r * 9 + c] == 0 { go(r, c); r += dr; c += dc }
                    r += dr; c += dc
                    while Self.onBoard(r, c), board[r * 9 + c] == 0 { r += dr; c += dc }
                    if Self.onBoard(r, c), board[r * 9 + c] * mine < 0 { go(r, c) }
                }
            case 1:
                go(row + (red ? -1 : 1), col)
                if !Self.atHome(row, red: red) { go(row, col - 1); go(row, col + 1) }
            default: break
            }
        }
    }

    mutating func play(_ move: Move) {
        quiet = board[move.to] == 0 ? quiet + 1 : 0
        board[move.to] = board[move.from]
        board[move.from] = 0
        redToMove.toggle()
    }

    /// Leaf positions `depth` plies down: what the published tables count.
    func perft(_ depth: Int) -> Int {
        let moves = legalMoves()
        if depth <= 1 { return depth == 1 ? moves.count : 1 }
        return moves.reduce(0) { total, move in var next = self; next.play(move); return total + next.perft(depth - 1) }
    }

    // MARK: Judging, for the shortlist and the yardstick

    private func crossed(_ index: Int, _ piece: Int8) -> Bool { !Self.atHome(index / 9, red: piece > 0) }

    /// Material in half points, from Red's side.
    var material: Int {
        board.enumerated().reduce(0) { total, item in
            let (index, piece) = item
            guard piece != 0 else { return total }
            let kind = Int(abs(piece))
            let value = kind == 1 && crossed(index, piece) ? 2 * Self.worth[1] : Self.worth[kind]
            return total + (piece > 0 ? value : -value)
        }
    }

    /// Material and a little position, in hundredths of a point, from Red's side.
    func evaluation() -> Int {
        var total = 0
        for (index, piece) in board.enumerated() where piece != 0 {
            let kind = Int(abs(piece)), row = index / 9, col = index % 9, red = piece > 0
            var value = [0, 100, 200, 200, 400, 450, 900, 0][kind]
            let central = 4 - abs(col - 4)                      // 0 on the edge files, 4 on the middle one
            let advance = red ? 9 - row : row                    // ranks from its own back rank
            switch kind {
            case 1:
                if crossed(index, piece) { value += 100 + 8 * central + (advance == 9 ? -40 : 6 * (advance - 5)) }  // an old soldier on the last rank has nowhere to go
            case 4:
                value += 6 * central + (advance == 0 ? -15 : 0)                         // still in the stable
            case 5:
                value += advance <= 2 && col == 4 ? 20 : 0                              // the central cannon
            case 6:
                value += advance == 0 && (col == 0 || col == 8) ? -25 : 0               // three moves and the chariot not out
            default: break
            }
            total += red ? value : -value
        }
        return total
    }

    /// What the position is worth to the side to move once the captures have
    /// been played out: either side may stop and stand on what it has, or go
    /// on taking, a few plies deep; a side in check has to answer it. With the
    /// material (from Red's side, in half points) where the taking stopped.
    ///
    /// One recapture is not enough here. A cannon takes a horse through a
    /// screen from the other end of the board, on the first move of the game —
    /// and the chariot beside that horse takes the cannon; the other cannon
    /// can do the same on the other wing. Counting only the first half of each
    /// of those made the evaluator open every game by giving two cannons for
    /// two horses.
    func settled(_ alpha: Int, _ beta: Int, depth: Int) -> (value: Int, material: Int) {
        let sign = redToMove ? 1 : -1, checked = inCheck(red: redToMove)
        var alpha = alpha, best = (value: sign * evaluation(), material: material)
        var moves: [Move]
        if checked {
            moves = legalMoves()
            if moves.isEmpty { return (-1_000_000, material) }
            best.value = -999_999                                  // no standing pat in check
        } else {
            if depth <= 0 || best.value >= beta { return best }
            alpha = max(alpha, best.value)
            moves = legalMoves(capturesOnly: true)
        }
        if depth <= 0 { return (sign * evaluation(), material) }
        // The biggest prize first: most of the rest is then cut off.
        moves.sort { Self.worth[Int(abs(board[$0.to]))] > Self.worth[Int(abs(board[$1.to]))] }
        for move in moves {
            var next = self
            next.play(move)
            let reply = next.settled(-beta, -alpha, depth: depth - 1)
            if -reply.value > best.value { best = (-reply.value, reply.material) }
            alpha = max(alpha, best.value)
            if alpha >= beta { break }
        }
        return best
    }

    /// What a move comes to for the side making it once the other side has
    /// made its best reply and the captures after that have been played out,
    /// so that a trade reads as a trade and a poisoned horse as poisoned: a
    /// value in hundredths of a point (the end of the game is a very large
    /// number), and the material then, in half points, from the mover's side.
    func outcome(of move: Move) -> (value: Int, material: Int) {
        let mine = redToMove ? 1 : -1
        var next = self
        next.play(move)
        let replies = next.legalMoves()
        if replies.isEmpty { return (1_000_000, mine * next.material) }       // no move left loses, check or not
        var worst = (value: Int.max, material: 0)
        for reply in replies {
            var after = next
            after.play(reply)
            let line = after.canMove ? after.settled(-2_000_000, worst.value, depth: 4)
                                     : (value: -1_000_000, material: after.material)
            if line.value < worst.value { worst = (line.value, mine * line.material) }
        }
        return worst
    }

    /// The position's worth to the side to move, `depth` plies on with both sides
    /// playing their best and the captures settled at the end — and the material
    /// there, from Red's side. Plain alpha-beta, the biggest captures tried first.
    func search(_ depth: Int, _ alpha: Int, _ beta: Int) -> (value: Int, material: Int) {
        if depth <= 0 { return settled(alpha, beta, depth: 4) }
        var moves = legalMoves()
        if moves.isEmpty { return (-1_000_000 - depth, material) }            // having no move is losing, and sooner is worse
        moves.sort { Self.worth[Int(abs(board[$0.to]))] > Self.worth[Int(abs(board[$1.to]))] }
        var alpha = alpha, best = (value: -2_000_000, material: material)
        for move in moves {
            var next = self
            next.play(move)
            let reply = next.search(depth - 1, -beta, -alpha)
            if -reply.value > best.value { best = (-reply.value, reply.material) }
            alpha = max(alpha, best.value)
            if alpha >= beta { break }
        }
        return best
    }

    /// What a move comes to `plies` further on than the move itself — for the
    /// words about it. The evaluator that PLAYS looks one reply ahead
    /// (`outcome`); what is SAID about a move may look further, and a player who
    /// reads that knows something the evaluator does not.
    func foresight(of move: Move, plies: Int) -> (value: Int, material: Int) {
        let mine = redToMove ? 1 : -1
        var next = self
        next.play(move)
        let line = next.search(plies, -2_000_000, 2_000_000)
        return (-line.value, mine * line.material)
    }

    /// What a move threatens: what the mover could do next if the other side did
    /// nothing about it — mate, or material won once the captures are played out
    /// (in half points). A third move deep, which is one more than the evaluator
    /// looks when it chooses: it parries a threat it can see coming in one move,
    /// and does not go looking for one to make. Nothing is reported for a move
    /// that gives check; a side in check cannot do nothing, and "gives check" is
    /// already said.
    func threat(after move: Move) -> (mate: Bool, gain: Int) {
        let mine = redToMove ? 1 : -1
        var next = self
        next.play(move)
        guard !next.inCheck(red: next.redToMove) else { return (false, 0) }
        next.redToMove.toggle()                                   // the other side passes
        let now = mine * next.material
        var best = 0
        for follow in next.legalMoves() {
            var after = next
            after.play(follow)
            if !after.canMove { return (true, 0) }
            guard next.board[follow.to] != 0 else { continue }   // only what is taken can be won next move
            let line = after.settled(-2_000_000, 2_000_000, depth: 3)
            best = max(best, mine * line.material - now)
        }
        return (false, best)
    }

    /// Nothing left on either side that can cross the river: nobody can be mated.
    var deadPosition: Bool { !board.contains { [1, 4, 5, 6].contains(abs($0)) } }
}
