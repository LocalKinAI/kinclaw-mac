import Foundation

/// Gomoku — 五子棋 — free style: five or more in a row, in any direction, wins;
/// nothing is forbidden to either side. No SwiftUI in here, so that it can be
/// compiled and played on its own.
///
/// Everything in this game is about lines, so everything here is about one
/// question: *what does a stone on this point make, along this line?* Nine
/// points are looked at — four either side — and the answer is one of eight
/// ranks, worked out by trying rather than by listing shapes: a line is a
/// FIVE if five in a row include the stone; a FOUR if one more stone makes it
/// a five, and an OPEN four if two different stones would; a three is OPEN if
/// one more stone makes an open four, and so on down. Broken shapes (X·XX)
/// come out right without anybody having named them. There are 3⁹ lines and
/// the answers are kept.
struct GomokuPosition {
    static let size = 15
    /// 0 empty, 1 black (who moves first), 2 white. Row 0 is the top, as it is drawn.
    var board = [Int8](repeating: 0, count: size * size)
    var blackToMove = true
    var stones = 0
    var lastMove: Int?

    enum Rank: Int, Comparable {
        case nothing, two, openTwo, three, openThree, four, openFour, five
        static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
    }

    static let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
    static func name(_ point: Int) -> String { "\("ABCDEFGHIJKLMNO".map { String($0) }[point % size])\(size - point / size)" }
    var mover: Int8 { blackToMove ? 1 : 2 }

    mutating func play(_ point: Int) {
        board[point] = mover
        blackToMove.toggle(); stones += 1; lastMove = point
    }

    // MARK: One line

    /// The nine points through `point` along a direction, as a number in base
    /// three: 1 the player's own (the middle one always is — the stone being
    /// asked about), 0 empty, 2 the other side's or off the board.
    private func code(_ point: Int, _ direction: (Int, Int), for player: Int8) -> Int {
        let row = point / Self.size, col = point % Self.size
        var code = 0
        for step in -4...4 {
            let r = row + step * direction.0, c = col + step * direction.1
            var digit = 2
            if step == 0 { digit = 1 }
            else if r >= 0, r < Self.size, c >= 0, c < Self.size {
                let at = board[r * Self.size + c]
                digit = at == 0 ? 0 : at == player ? 1 : 2
            }
            code = code * 3 + digit
        }
        return code
    }

    nonisolated(unsafe) private static var known = [Int8](repeating: -1, count: 19683)

    private static func rank(of code: Int) -> Rank {
        if known[code] >= 0 { return Rank(rawValue: Int(known[code]))! }
        var line = [Int](repeating: 0, count: 9), rest = code
        for index in stride(from: 8, through: 0, by: -1) { line[index] = rest % 3; rest /= 3 }
        let found = judge(line)
        known[code] = Int8(found.rawValue)
        return found
    }

    /// By trying: what the best next stone on this line would make decides what this is.
    private static func judge(_ line: [Int]) -> Rank {
        // Five in a row through the middle?
        for start in 0...4 where (start...(start + 4)).allSatisfy({ line[$0] == 1 }) { return .five }
        // What each empty point would make of it.
        var fives = 0, best = Rank.nothing
        for index in 0..<9 where line[index] == 0 {
            var next = line
            next[index] = 1
            let made = judge(next)
            if made == .five { fives += 1 }
            best = max(best, made)
        }
        if fives >= 2 { return .openFour }
        if fives == 1 { return .four }
        switch best {
        case .openFour: return .openThree
        case .four: return .three
        case .openThree: return .openTwo
        case .three: return .two
        default: return .nothing
        }
    }

    /// What a stone of `player`'s on `point` makes, line by line.
    func ranks(at point: Int, for player: Int8) -> [Rank] {
        Self.directions.map { Self.rank(of: code(point, $0, for: player)) }
    }

    // MARK: Where to look, and who has won

    /// Empty points within two of a stone: nothing further away is ever the move.
    func candidates() -> [Int] {
        if stones == 0 { return [Self.size * Self.size / 2] }
        var near = [Bool](repeating: false, count: board.count)
        for point in board.indices where board[point] != 0 {
            let row = point / Self.size, col = point % Self.size
            for r in max(0, row - 2)...min(Self.size - 1, row + 2) {
                for c in max(0, col - 2)...min(Self.size - 1, col + 2) where board[r * Self.size + c] == 0 { near[r * Self.size + c] = true }
            }
        }
        return near.indices.filter { near[$0] }
    }

    /// The five (or more) that the last stone made, if it made one.
    var winningLine: [Int]? {
        guard let last = lastMove else { return nil }
        let player = board[last], row = last / Self.size, col = last % Self.size
        for (dr, dc) in Self.directions {
            var line = [last]
            for way in [-1, 1] {
                var r = row + way * dr, c = col + way * dc
                while r >= 0, r < Self.size, c >= 0, c < Self.size, board[r * Self.size + c] == player {
                    line.append(r * Self.size + c); r += way * dr; c += way * dc
                }
            }
            if line.count >= 5 { return line }
        }
        return nil
    }

    // MARK: The evaluator that plays

    struct Shape {
        var mine: [Rank], theirs: [Rank]
        func count(_ ranks: [Rank], _ wanted: Rank) -> Int { ranks.filter { $0 == wanted }.count }
        /// A five next move that cannot be stopped: an open four, two fours, or a four with an open three.
        static func wins(_ ranks: [Rank]) -> Bool {
            let fours = ranks.filter { $0 == .four }.count
            return ranks.contains(.openFour) || fours >= 2 || (fours >= 1 && ranks.contains(.openThree))
        }
    }

    func shape(at point: Int) -> Shape {
        Shape(mine: ranks(at: point, for: mover), theirs: ranks(at: point, for: 3 - mover))
    }

    /// What a stone is worth by what it makes and what it denies, this move and
    /// no further: the classic one-look evaluator, and the yardstick here.
    func worth(of point: Int) -> Int {
        let shape = shape(at: point)
        let row = point / Self.size, col = point % Self.size, middle = Self.size / 2
        let central = 2 * middle - abs(row - middle) - abs(col - middle)
        return Self.value(shape.mine, attack: true) + Self.value(shape.theirs, attack: false) + central
    }

    private static func value(_ ranks: [Rank], attack: Bool) -> Int {
        if ranks.contains(.five) { return attack ? 10_000_000 : 5_000_000 }
        if Shape.wins(ranks) { return attack ? 1_000_000 : 400_000 }
        if ranks.filter({ $0 == .openThree }).count >= 2 { return attack ? 200_000 : 90_000 }
        var sum = 0
        for rank in ranks {
            switch rank {
            case .four: sum += 2_400
            case .openThree: sum += 3_000
            case .three: sum += 320
            case .openTwo: sum += 300
            case .two: sum += 30
            default: break
            }
        }
        return attack ? sum : sum * 8 / 10
    }

    /// The most a player could make with one stone, anywhere: how dangerous that side is.
    func menace(of player: Int8) -> Int {
        candidates().reduce(0) { max($0, Self.value(ranks(at: $1, for: player), attack: true)) }
    }

    // MARK: Looking further, for what is said to a reader

    /// The best few points for the side to move, by the one-look evaluator, with what each is worth.
    private func best(_ count: Int) -> [(point: Int, worth: Int)] {
        candidates().map { ($0, worth(of: $0)) }.sorted { $0.1 > $1.1 }.prefix(count).map { (point: $0.0, worth: $0.1) }
    }

    /// The position's worth to the side to move, `depth` stones on with both
    /// sides choosing among their best few by the one-look evaluator: beyond
    /// ±500,000 somebody wins by force. Alpha-beta; at the end of the line, what
    /// the side to move could make next against half of what it would have to
    /// fear — it is the side to move that gets there first.
    func search(_ depth: Int, _ alpha: Int, _ beta: Int, width: Int = 7) -> Int {
        let moves = best(width)
        guard let first = moves.first else { return 0 }
        if first.worth >= 10_000_000 { return 1_000_000 + depth }                 // five: sooner is better
        if depth <= 0 {
            // How dangerous each side is, and whose move it is. (Counting the worth
            // of the best MOVE here was wrong: a move is worth a great deal when
            // it has to block something, and the side that has to block is not
            // the side that is doing well. A player who followed that played
            // every game to a full board.)
            let mine = menace(of: mover), theirs = menace(of: 3 - mover)
            if mine >= 1_000_000 { return 900_000 }                               // an open four or a double threat to make, and the move to make it
            if theirs >= 1_000_000, mine < 2_400 { return -800_000 }              // theirs to make, and no four of mine to make them answer first
            return min(mine, 400_000) - min(theirs, 400_000) * 8 / 10
        }
        var alpha = alpha, value = -2_000_000
        for move in moves {
            var next = self
            next.play(move.point)
            value = max(value, -next.search(depth - 1, -beta, -alpha, width: width))
            alpha = max(alpha, value)
            if alpha >= beta { break }
        }
        return value
    }

    /// What a stone comes to `stones` further on than itself — for the words
    /// about it. The evaluator that PLAYS looks at the stone and no further.
    func foresight(of point: Int, stones: Int) -> Int {
        var next = self
        next.play(point)
        if next.winningLine != nil { return 1_000_000 + stones + 1 }
        return -next.search(stones, -2_000_000, 2_000_000)
    }

    /// Can the side to move win by fours alone — each one forcing the single
    /// answer that blocks it — within `depth` of them? (VCF, to players.) The
    /// one-look evaluator sees a four when it is made and never the third one on.
    func winsByFours(depth: Int) -> Bool {
        let me = mover, them = 3 - mover
        let points = candidates()
        if points.contains(where: { ranks(at: $0, for: me).contains(.five) }) { return true }
        let theirFives = points.filter { ranks(at: $0, for: them).contains(.five) }
        if theirFives.count >= 2 || depth <= 0 { return false }
        for point in (theirFives.isEmpty ? points : theirFives) {
            let made = ranks(at: point, for: me)
            guard made.contains(where: { $0 >= .four }) else { continue }
            var next = self
            next.play(point)
            let near = next.candidates()
            // They may simply make five themselves instead of answering.
            if near.contains(where: { next.ranks(at: $0, for: them).contains(.five) }) { continue }
            let completions = near.filter { next.ranks(at: $0, for: me).contains(.five) }
            if completions.count >= 2 { return true }
            guard let forced = completions.first else { continue }
            next.play(forced)
            if next.winsByFours(depth: depth - 1) { return true }
        }
        return false
    }
}
