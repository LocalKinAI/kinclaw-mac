import SwiftUI

/// Gomoku for two players who read words.
///
/// The division of labour the chess games arrived at, from the start this
/// time. The program finds the points worth considering, works out what a
/// stone on each would make and deny, line by line, and says it as a player
/// would: "makes a four and an open three at once", "blocks the opponent's
/// open three". The evaluator that PLAYS is the classic one — one look, what
/// the stone makes and what it denies, this move and no further — and is the
/// yardstick. For a player that READS, the program looks further (can either
/// side now win by fours alone?), says so, and does not ask what it already
/// knows: a five is the only option offered, a four is only ever answered by
/// blocking it, and a move after which the opponent wins by force is off the
/// list while another is on it.
@MainActor
final class JevGomoku: JevGame {
    let id = "gomoku", title = "五子棋", symbol = "circle.grid.3x3.fill"
    let rules = "Gomoku on a 15 by 15 board. Black moves first; the players take turns placing one stone on an empty point. Five or more of one's own stones in an unbroken row — across, down or diagonally — wins. Nothing is forbidden to either side. A full board is a draw."
    let question = "Which point is the best move for the side to play?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: making five wins at once. Second: if the opponent could make five next move, that point must be taken. Third: an open four, two fours at once, or a four together with an open three cannot be stopped and win; a move that starts a forced win by continuous fours is as good. Fourth: never choose a move after which the opponent wins by force, and prefer a move that wins by force over everything below. Fifth: an opponent's open three has to be answered — by blocking it, or by making a four of your own that forces them first. Sixth: two open threes at once are a winning double threat against an opponent who has no fours to make. Otherwise prefer a move that keeps the initiative four moves on over one that leaves you under pressure, and build: prefer a move that makes an open three over one that makes a three with a blocked end, that over an open two; prefer a move that builds your own line and spoils the opponent's at the same time; prefer points near the centre and near your own stones."
    let sides = ["黑方", "白方"]

    private var state = GomokuPosition()
    private var moves: [Int] = []
    private var played: [Int] = []
    private(set) var result: String?
    private var line: Set<Int> = []
    private(set) var ticked = Date.distantPast
    private var dice = JevDice(seed: 1)
    private var reader = false
    /// Forced by the test harness; otherwise a reader is looked further for, and nobody else is.
    nonisolated(unsafe) static var looksFurther: Bool?
    private var deep: Bool { Self.looksFurther ?? reader }

    func prepare(reader: Bool) { self.reader = reader }
    private var person = false
    func prepare(person: Bool) { self.person = person }
    let controls = "点棋盘上的空点落子"

    func tap(row: Int, col: Int, among options: [JevOption]) -> JevReaction {
        let point = row * GomokuPosition.size + col
        guard let index = moves.firstIndex(of: point), let option = options.first(where: { $0.move == index }) else {
            return state.board.indices.contains(point) && state.board[point] != 0 ? .explain("这里已经有子了") : .nothing
        }
        return .choose(option)
    }

    var turn: Int { state.blackToMove ? 0 : 1 }
    var over: Bool { result != nil }
    var score: Int { state.stones }
    var status: String {
        let last = played.last.map { " · 上一手 \(GomokuPosition.name($0))" } ?? ""
        return (result ?? "第 \(state.stones + 1) 手 · 轮到\(sides[turn])") + last
    }
    var situation: String {
        "\(state.blackToMove ? "Black" : "White") to play, stone number \(state.stones + 1)"
            + (played.last.map { "; the opponent's last stone went on \(GomokuPosition.name($0))" } ?? "")
    }
    var position: String {
        let size = GomokuPosition.size, marks = [".", "X", "O"]
        var rows: [String] = []
        for row in 0..<size {
            var cells: [String] = []
            for col in 0..<size { cells.append(marks[Int(state.board[row * size + col])]) }
            rows.append(String(format: "%2d ", size - row) + cells.joined(separator: " "))
        }
        let files = "ABCDEFGHIJKLMNO".map { String($0) }.joined(separator: " ")
        let soFar = played.isEmpty ? "none" : played.map { GomokuPosition.name($0) }.joined(separator: " ")
        return rows.joined(separator: "\n") + "\n   " + files + "\n(X is Black, O is White.) Stones so far: " + soFar
    }

    private static let wood = Color(red: 0.86, green: 0.70, blue: 0.44)
    var grid: [[JevCell]] {
        let size = GomokuPosition.size, stars: Set<Int> = [3 * 15 + 3, 3 * 15 + 11, 7 * 15 + 7, 11 * 15 + 3, 11 * 15 + 11]
        return (0..<size).map { row in (0..<size).map { col in
            let point = row * size + col, stone = state.board[point]
            let ground = line.contains(point) ? Color.green.opacity(0.75) : played.last == point ? Color.yellow.opacity(0.85) : Self.wood
            if stone == 0 { return JevCell(colour: ground, text: stars.contains(point) ? "•" : "", ink: .black.opacity(0.45)) }
            return JevCell(colour: ground, ink: stone == 1 ? .black : Color(white: 0.55),
                           disc: stone == 1 ? Color(white: 0.08) : Color(white: 0.97))
        } }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        state = GomokuPosition(); moves = []; played = []; result = nil; line = []
        dice = JevDice(seed: seed)
    }

    private struct Seen {
        var point: Int, worth: Int, shape: GomokuPosition.Shape
        var losesNow = false, losesByForce = false, threatens = false
        /// Four stones further on, with both sides choosing among their best few: beyond ±500,000 somebody wins by force.
        var further: Int?
        var winsNow: Bool { shape.mine.contains(.five) }
        var winsByForce: Bool { !losesNow && GomokuPosition.Shape.wins(shape.mine) }
    }

    func options() -> [JevOption] {
        guard result == nil else { return [] }
        // A model gets the points near the stones; a person may play anywhere.
        let points = person ? state.board.indices.filter { state.board[$0] == 0 } : state.candidates()
        if points.isEmpty { result = "棋盘下满了 · 和棋"; return [] }
        var seen = points.map { Seen(point: $0, worth: state.worth(of: $0), shape: state.shape(at: $0)) }
        // The shortlist: the evaluator's best eight, then whatever forces or has to be answered.
        let byWorth = seen.indices.sorted { seen[$0].worth > seen[$1].worth }
        var keep = Set(byWorth.prefix(8))
        for index in byWorth where keep.count < 12 {
            let shape = seen[index].shape
            if shape.mine.contains(where: { $0 >= .openThree }) || shape.theirs.contains(where: { $0 >= .openThree }) { keep.insert(index) }
        }
        var chosen = person ? Array(seen.indices) : keep.sorted { seen[$0].point < seen[$1].point }   // in board order, which favours nobody
        if deep {
            // Further than the evaluator that plays looks: what happens after the stone. What looks
            // best further on belongs on the list too — it is what the words are going to be about.
            let far = byWorth.prefix(14).map { (index: $0, value: state.foresight(of: seen[$0].point, stones: 4)) }
            for entry in far { seen[entry.index].further = entry.value }
            for entry in far.sorted(by: { $0.value > $1.value }).prefix(4) where !chosen.contains(entry.index) { chosen.append(entry.index) }
            chosen.sort { seen[$0].point < seen[$1].point }
            for index in chosen where seen[index].further == nil { seen[index].further = state.foresight(of: seen[index].point, stones: 4) }
            for index in chosen {
                var next = state
                next.play(seen[index].point)
                seen[index].losesNow = next.candidates().contains { next.ranks(at: $0, for: next.mover).contains(.five) }
                if !seen[index].losesNow, !seen[index].winsNow { seen[index].losesByForce = next.winsByFours(depth: 4) }
                if !seen[index].losesNow, !seen[index].losesByForce {
                    next.blackToMove.toggle()                                  // if they did nothing about it
                    seen[index].threatens = next.winsByFours(depth: 4)
                }
            }
            // And the program does not ask what it already knows.
            if chosen.contains(where: { seen[$0].winsNow }) { chosen = chosen.filter { seen[$0].winsNow } }
            else {
                func lost(_ index: Int) -> Bool { seen[index].losesNow || seen[index].losesByForce || (seen[index].further ?? 0) <= -500_000 }
                func won(_ index: Int) -> Bool { !lost(index) && (seen[index].winsByForce || (seen[index].further ?? 0) >= 500_000) }
                let safe = chosen.filter { !lost($0) }
                let standing = safe.isEmpty ? chosen.filter { !seen[$0].losesNow } : safe
                if !standing.isEmpty { chosen = standing }
                if chosen.contains(where: won) { chosen = chosen.filter(won) }
            }
        }
        moves = chosen.map { seen[$0].point }
        return chosen.enumerated().map { index, which in
            JevOption(id: String(format: "p%02d", index + 1), label: describe(seen[which]),
                      merit: Double(seen[which].worth) + Double(dice.below(3)) * 0.001, move: index,
                      insight: seen[which].further.map { Double($0) })
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move), result == nil else { return }
        let point = moves[option.move], mover = turn
        state.play(point)
        played.append(point)
        ticked = Date()
        if let five = state.winningLine {
            line = Set(five)
            result = "\(sides[mover])五连 · \(sides[mover])赢了（\(state.stones) 手）"
        } else if state.stones >= GomokuPosition.size * GomokuPosition.size { result = "棋盘下满了 · 和棋" }
    }

    /// One point, in words: what a stone there makes, what it denies, where it is.
    private func describe(_ seen: Seen) -> String {
        typealias Rank = GomokuPosition.Rank
        let mine = seen.shape.mine, theirs = seen.shape.theirs
        func count(_ ranks: [Rank], _ rank: Rank) -> Int { ranks.filter { $0 == rank }.count }
        var parts: [String] = []
        if mine.contains(.five) { parts.append("makes five in a row: wins the game") }
        else {
            if mine.contains(.openFour) { parts.append("makes an open four: five next move cannot be stopped") }
            else if count(mine, .four) >= 2 { parts.append("makes two fours at once: only one can be blocked") }
            else if count(mine, .four) >= 1, mine.contains(.openThree) { parts.append("makes a four and an open three at once: a winning double threat") }
            else if count(mine, .openThree) >= 2 { parts.append("makes two open threes at once: a double threat") }
            else if mine.contains(.four) { parts.append("makes a four: the opponent must block at once") }
            else if mine.contains(.openThree) { parts.append("makes an open three, which threatens an open four") }
            else if mine.contains(.three) { parts.append("makes a three with one end blocked") }
            else if count(mine, .openTwo) >= 2 { parts.append("makes two open twos") }
            else if mine.contains(.openTwo) { parts.append("makes an open two") }

            if theirs.contains(.five) { parts.append("blocks the opponent's four: they would make five here next move") }
            else if GomokuPosition.Shape.wins(theirs) { parts.append("takes the point where the opponent would make an open four or a winning double threat") }
            else if count(theirs, .openThree) >= 2 { parts.append("takes the point where the opponent would make two open threes") }
            else if theirs.contains(.four) { parts.append("blocks one end of the opponent's three") }
            else if theirs.contains(.openThree) { parts.append("spoils the opponent's open two") }
        }
        if deep, !mine.contains(.five) {
            if seen.losesNow { parts.append("leaves the opponent's four unblocked: loses the game") }
            else if seen.losesByForce { parts.append("after it the opponent wins by force with continuous fours: loses the game") }
            else if seen.threatens, !seen.winsByForce { parts.append("threatens to win by continuous fours if it is not answered") }
            if let further = seen.further, !seen.losesNow, !seen.losesByForce {
                if further >= 500_000 { parts.append("with best play it wins by force within a few moves") }
                else if further <= -500_000 { parts.append("with best play the opponent wins by force within a few moves: loses the game") }
                else if further >= 2_500 { parts.append("four moves on it keeps the initiative: you are the one making threats") }
                else if further <= -2_500 { parts.append("four moves on it leaves you under pressure: the opponent is the one making threats") }
                else { parts.append("four moves on the position is balanced") }
            }
        }
        let size = GomokuPosition.size, row = seen.point / size, col = seen.point % size
        let fromEdge = min(row, col, size - 1 - row, size - 1 - col)
        if parts.isEmpty { parts.append("a quiet move next to stones already there") }
        parts.append(fromEdge <= 1 ? "on the edge of the board" : fromEdge >= 5 ? "in the middle of the board" : "between the middle and the edge")
        return "\(GomokuPosition.name(seen.point)): " + parts.joined(separator: "; ")
    }
}

/// Wood, with a little grain.
fileprivate func woodBoard(_ g: GraphicsContext, _ rect: CGRect, light: (Double, Double, Double), seed: Int) {
    g.fill(Path(roundedRect: rect, cornerRadius: 8),
           with: .linearGradient(Gradient(colors: [JevDraw.shade(light, 1.06), JevDraw.shade(light, 0.9), JevDraw.shade(light, 1.02)]),
                                 startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
    for grain in 0..<26 {
        let y = rect.minY + rect.height * CGFloat(JevDraw.hash(grain, seed) % 1000) / 1000
        let wave = CGFloat(JevDraw.hash(grain, seed + 1) % 7) - 3
        g.stroke(Path { p in
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addCurve(to: CGPoint(x: rect.maxX, y: y + wave), control1: CGPoint(x: rect.minX + rect.width * 0.3, y: y - wave * 2),
                       control2: CGPoint(x: rect.minX + rect.width * 0.7, y: y + wave * 3))
        }, with: .color(JevDraw.shade(light, 0.7).opacity(0.18)), lineWidth: 1)
    }
}

// MARK: - The picture

extension JevGomoku: JevPainted {
    var aspect: Double { 1 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = GomokuScene(board: state.board, last: played.last, line: line, t: t, over: over, result: result ?? "")
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    func spot(at point: CGPoint, in size: CGSize) -> (row: Int, col: Int)? {
        let geometry = GomokuScene.geometry(size)
        let col = Int(((point.x - geometry.origin.x) / geometry.step).rounded()), row = Int(((point.y - geometry.origin.y) / geometry.step).rounded())
        guard (0..<GomokuPosition.size).contains(row), (0..<GomokuPosition.size).contains(col) else { return nil }
        return (row, col)
    }
}

fileprivate struct GomokuScene {
    let board: [Int8], last: Int?, line: Set<Int>, t: Double, over: Bool, result: String

    static func geometry(_ size: CGSize) -> (origin: CGPoint, step: CGFloat) {
        let n = CGFloat(GomokuPosition.size - 1), step = min(size.width, size.height) / (n + 1.8)
        return (CGPoint(x: (size.width - n * step) / 2, y: (size.height - n * step) / 2), step)
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let (origin, step) = Self.geometry(size), n = GomokuPosition.size
        func at(_ index: Int) -> CGPoint { CGPoint(x: origin.x + CGFloat(index % n) * step, y: origin.y + CGFloat(index / n) * step) }
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.36, green: 0.24, blue: 0.14)))
        woodBoard(g, CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6), light: (0.86, 0.69, 0.42), seed: 11)
        let ink = Color(red: 0.25, green: 0.16, blue: 0.08)
        for k in 0..<n {
            let offset = CGFloat(k) * step
            g.fill(Path(CGRect(x: origin.x, y: origin.y + offset - 0.5, width: CGFloat(n - 1) * step, height: 1)), with: .color(ink.opacity(0.8)))
            g.fill(Path(CGRect(x: origin.x + offset - 0.5, y: origin.y, width: 1, height: CGFloat(n - 1) * step)), with: .color(ink.opacity(0.8)))
            JevDraw.text(g, String("ABCDEFGHIJKLMNO"[String.Index(utf16Offset: k, in: "ABCDEFGHIJKLMNO")]),
                         at: CGPoint(x: origin.x + offset, y: origin.y + CGFloat(n - 1) * step + step * 0.6), size: step * 0.32, weight: .semibold, colour: ink, shadow: false)
            JevDraw.text(g, "\(n - k)", at: CGPoint(x: origin.x - step * 0.6, y: origin.y + offset), size: step * 0.32, weight: .semibold, colour: ink, shadow: false)
        }
        g.stroke(Path(CGRect(x: origin.x, y: origin.y, width: CGFloat(n - 1) * step, height: CGFloat(n - 1) * step)), with: .color(ink), lineWidth: 2)
        for star in [3 * 15 + 3, 3 * 15 + 11, 7 * 15 + 7, 11 * 15 + 3, 11 * 15 + 11] {
            let p = at(star)
            g.fill(Path(ellipseIn: CGRect(x: p.x - step * 0.09, y: p.y - step * 0.09, width: step * 0.18, height: step * 0.18)), with: .color(ink))
        }
        for index in board.indices where board[index] != 0 {
            var r = step * 0.46, alpha = 1.0
            if index == last, t < 1 { let e = JevDraw.smooth(t); r *= CGFloat(1.35 - 0.35 * e); alpha = 0.4 + 0.6 * e }
            stone(g, at: at(index), radius: r, black: board[index] == 1, alpha: alpha)
        }
        if let last, board.indices.contains(last), board[last] != 0 {
            let p = at(last)
            g.fill(Path(ellipseIn: CGRect(x: p.x - step * 0.1, y: p.y - step * 0.1, width: step * 0.2, height: step * 0.2)), with: .color(Color.red.opacity(0.9)))
        }
        // Five in a row: a line of light through them.
        if line.count >= 5 {
            let points = line.sorted().map(at)
            if let first = points.first, let end = points.last {
                for (width, alpha) in [(step * 0.5, 0.25), (step * 0.18, 0.9)] {
                    g.stroke(Path { p in p.move(to: first); p.addLine(to: end) }, with: .color(Color(red: 1, green: 0.3, blue: 0.2).opacity(alpha)),
                             style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
        }
        if over { JevDraw.curtain(g, size, title: result.components(separatedBy: " · ").last ?? result, detail: result.components(separatedBy: " · ").first ?? "") }
    }

    private func stone(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, black: Bool, alpha: Double) {
        g.fill(Path(ellipseIn: CGRect(x: p.x - r + r * 0.12, y: p.y - r + r * 0.18, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.35 * alpha)))
        let colours = black ? [Color(white: 0.45), Color(white: 0.02)] : [Color.white, Color(white: 0.97), Color(white: 0.84)]
        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: colours.map { $0.opacity(alpha) }), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35),
                                     startRadius: 0, endRadius: r * (black ? 1.4 : 1.7)))
        if !black { g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(white: 0.55).opacity(alpha)), lineWidth: 0.8) }
    }
}
