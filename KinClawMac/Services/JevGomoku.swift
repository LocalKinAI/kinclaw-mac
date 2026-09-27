import SwiftUI
import CoreText

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

/// A kaya board on a dark table, the grid inked on it, and stones of slate and shell.
fileprivate struct GomokuScene {
    let board: [Int8], last: Int?, line: Set<Int>, t: Double, over: Bool, result: String

    /// The board's top face, where the grid starts on it and the step between lines, and how thick the board shows below the face.
    static func layout(_ size: CGSize) -> (face: CGRect, origin: CGPoint, step: CGFloat, thick: CGFloat) {
        let n = CGFloat(GomokuPosition.size - 1), side = min(size.width, size.height)
        let pad = side * 0.024, thick = side * 0.02, margin: CGFloat = 0.95
        let step = min(size.width - 2 * pad, size.height - 2 * pad - thick) / (n + 2 * margin)
        let span = step * (n + 2 * margin)
        let face = CGRect(x: (size.width - span) / 2, y: (size.height - thick - span) / 2, width: span, height: span)
        return (face, CGPoint(x: face.minX + margin * step, y: face.minY + margin * step), step, thick)
    }

    static func geometry(_ size: CGSize) -> (origin: CGPoint, step: CGFloat) {
        let layout = layout(size)
        return (layout.origin, layout.step)
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let (face, origin, step, thick) = Self.layout(size), n = GomokuPosition.size
        func at(_ index: Int) -> CGPoint { CGPoint(x: origin.x + CGFloat(index % n) * step, y: origin.y + CGFloat(index / n) * step) }
        GomokuArt.table(g, size: size, face: face, thick: thick)
        GomokuArt.board(g, face: face, thick: thick)
        GomokuArt.grid(g, origin: origin, step: step)
        // The stone just played comes down onto the board: bigger and higher at first, its shadow further off.
        let radius = step * 0.475
        var stones: [(index: Int, at: CGPoint, lift: Double)] = []
        for index in board.indices where board[index] != 0 {
            stones.append((index, at(index), index == last && t < 1 ? 1 - JevDraw.smooth(t) : 0))
        }
        for stone in stones { GomokuArt.shadow(g, under: stone.at, radius: radius, lift: stone.lift) }
        for stone in stones {
            GomokuArt.stone(g, at: stone.at, radius: radius * CGFloat(1 + 0.18 * stone.lift), black: board[stone.index] == 1,
                            alpha: min(1, 0.3 + 1.4 * (1 - stone.lift)), seed: stone.index)
        }
        if let last, board.indices.contains(last), board[last] != 0, line.count < 5 {
            GomokuArt.marker(g, at: at(last), radius: radius, black: board[last] == 1, appear: JevDraw.smooth((t - 0.55) / 0.45))
        }
        // Five in a row: a line of light through them.
        if line.count >= 5 {
            let points = line.sorted().map(at)
            if let first = points.first, let end = points.last {
                let through = Path { p in p.move(to: first); p.addLine(to: end) }
                for point in points {
                    let r = radius * 1.08
                    g.stroke(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)), with: .color(GomokuArt.glow.opacity(0.9)), lineWidth: 2)
                }
                g.stroke(through, with: .color(GomokuArt.glow.opacity(0.3)), style: StrokeStyle(lineWidth: step * 0.5, lineCap: .round))
                g.stroke(through, with: .color(GomokuArt.glow.opacity(0.95)), style: StrokeStyle(lineWidth: step * 0.14, lineCap: .round))
                g.stroke(through, with: .color(Color.white.opacity(0.85)), style: StrokeStyle(lineWidth: step * 0.045, lineCap: .round))
            }
        }
        if over { JevDraw.curtain(g, size, title: result.components(separatedBy: " · ").last ?? result, detail: result.components(separatedBy: " · ").first ?? "") }
    }
}

/// The board's wood, the grid's ink, the stones, worked out once.
fileprivate enum GomokuArt {
    static let kaya: (Double, Double, Double) = (0.87, 0.67, 0.39)
    static let ink = Color(red: 0.13, green: 0.08, blue: 0.04)
    static let glow = Color(red: 1, green: 0.72, blue: 0.3)

    /// Wood lit more (k > 1) or less, without going grey.
    static func wood(_ k: Double) -> Color { Color(red: min(1, kaya.0 * k), green: min(1, kaya.1 * k), blue: min(1, kaya.2 * k)) }

    /// A strand of grain: where it runs (0…1 across and down the face), its colour, and how wide (a fraction of the face).
    struct Strand { let path: Path, colour: Color, width: CGFloat }

    /// Straight grain running down the board: broad bands of lighter and darker wood, and growth lines in families,
    /// close together, swaying the same way.
    static let grain: [Strand] = {
        func streak(_ x: CGFloat, sway: CGFloat, seed: Int) -> Path {
            let phase = Double(seed % 628) / 100, phase2 = Double(seed / 628 % 628) / 100
            var points: [CGPoint] = []
            for k in 0...16 {
                let y = -0.02 + 1.04 * CGFloat(k) / 16
                let wave = sin(Double(y) * 2 * .pi * 0.8 + phase) + 0.4 * sin(Double(y) * 2 * .pi * 2.3 + phase2)
                points.append(CGPoint(x: x + sway * CGFloat(wave), y: y))
            }
            var p = Path()
            p.move(to: points[0])
            for k in 1..<points.count - 1 {
                p.addQuadCurve(to: CGPoint(x: (points[k].x + points[k + 1].x) / 2, y: (points[k].y + points[k + 1].y) / 2), control: points[k])
            }
            p.addLine(to: points[points.count - 1])
            return p
        }
        let dark = Color(red: 0.55, green: 0.3, blue: 0.1), light = Color(red: 1, green: 0.9, blue: 0.68)
        var strands: [Strand] = []
        for k in 0..<18 {
            let h = JevDraw.hash(k, 401)
            strands.append(Strand(path: streak(CGFloat(h % 1000) / 1000, sway: 0.008, seed: h / 1000),
                                  colour: (h % 2 == 0 ? dark : light).opacity(0.05 + Double(h % 4) * 0.015), width: 0.012 + CGFloat(h / 7 % 30) / 1000))
        }
        for family in 0..<16 {
            let h = JevDraw.hash(family, 402)
            var x = CGFloat(h % 1000) / 1000
            for k in 0..<(3 + h % 5) {
                let hk = JevDraw.hash(family * 16 + k, 403)
                strands.append(Strand(path: streak(x, sway: 0.006, seed: h / 1000), colour: dark.opacity(0.1 + Double(hk % 9) / 100), width: 0.0011 + CGFloat(hk % 3) * 0.0005))
                x += 0.003 + CGFloat(hk / 3 % 6) / 1000
            }
        }
        return strands
    }()

    /// Clamshell striations across a unit disc: fine, slightly curved, parallel.
    static let striations: Path = {
        var p = Path()
        for k in 0..<11 {
            let y = -0.86 + 1.72 * CGFloat(k) / 10 + CGFloat(JevDraw.hash(k, 23) % 7) / 100 - 0.03
            let half = sqrt(max(0, 1 - y * y)) * 0.94
            p.move(to: CGPoint(x: -half, y: y))
            p.addQuadCurve(to: CGPoint(x: half, y: y), control: CGPoint(x: 0, y: y + 0.07))
        }
        return p
    }()

    /// The row numbers down the left, then the column letters along the bottom, each centred on (0, 0), one point of type to the unit.
    static let labels: [Path] = {
        guard let font = ["Baskerville-SemiBold", "Palatino-Bold", "Georgia-Bold"].lazy
            .map({ CTFontCreateWithName($0 as CFString, 100, nil) }).first(where: { ["Baskerville-SemiBold", "Palatino-Bold", "Georgia-Bold"].contains(CTFontCopyPostScriptName($0) as String) })
        else { return [] }
        let cap = CTFontGetCapHeight(font)
        func label(_ text: String) -> Path {
            var path = Path(), x: CGFloat = 0
            for unit in text.utf16 {
                var character = unit, glyph: CGGlyph = 0
                guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                path.addPath(Path(outline), transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: 0))
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
                x += advance.width
            }
            let box = path.boundingRect
            return path.applying(CGAffineTransform(a: 0.01, b: 0, c: 0, d: 0.01, tx: -box.midX * 0.01, ty: cap / 2 * 0.01))
        }
        let size = GomokuPosition.size
        return (0..<size).map { label("\(size - $0)") } + "ABCDEFGHIJKLMNO".map { label(String($0)) }
    }()

    // MARK: Painting

    /// A dark table, and the board's shadow on it.
    static func table(_ g: GraphicsContext, size: CGSize, face: CGRect, thick: CGFloat) {
        let all = CGRect(origin: .zero, size: size)
        g.fill(Path(all), with: .radialGradient(Gradient(colors: [Color(red: 0.2, green: 0.14, blue: 0.1), Color(red: 0.07, green: 0.05, blue: 0.04)]),
                                                center: CGPoint(x: size.width * 0.35, y: size.height * 0.3), startRadius: 0, endRadius: max(size.width, size.height)))
        for k in 0..<6 {
            let grow = CGFloat(k) * 1.8
            let rect = CGRect(x: face.minX - grow + 2, y: face.minY - grow + 5, width: face.width + 2 * grow, height: face.height + thick + 2 * grow)
            g.fill(Path(roundedRect: rect, cornerRadius: 5 + grow), with: .color(Color.black.opacity(0.09)))
        }
    }

    /// The board: its thickness below, its face, the grain, the light on it.
    static func board(_ g: GraphicsContext, face: CGRect, thick: CGFloat) {
        let corner = face.width * 0.009
        let side = CGRect(x: face.minX, y: face.midY, width: face.width, height: face.height / 2 + thick)
        g.fill(Path(roundedRect: side, cornerRadius: corner * 1.6), with: .linearGradient(Gradient(colors: [wood(0.78), wood(0.66), wood(0.46)]),
                                                                                         startPoint: CGPoint(x: 0, y: face.maxY), endPoint: CGPoint(x: 0, y: side.maxY)))
        // End grain on the side, and its lit top edge.
        var sideContext = g
        sideContext.clip(to: Path(CGRect(x: face.minX, y: face.maxY, width: face.width, height: thick)))
        var end = Path()
        for k in 0..<60 {
            let x = face.minX + face.width * (CGFloat(k) + CGFloat(JevDraw.hash(k, 55) % 80) / 100) / 60
            end.move(to: CGPoint(x: x, y: face.maxY)); end.addLine(to: CGPoint(x: x + 1.5, y: face.maxY + thick))
        }
        sideContext.stroke(end, with: .color(Color(red: 0.35, green: 0.2, blue: 0.08).opacity(0.25)), lineWidth: 0.6)
        let shape = Path(roundedRect: face, cornerRadius: corner)
        g.fill(shape, with: .linearGradient(Gradient(colors: [wood(1.0), wood(1.06), wood(0.98), wood(1.05), wood(0.97)]),
                                            startPoint: CGPoint(x: face.minX, y: face.minY), endPoint: CGPoint(x: face.maxX, y: face.minY)))
        var c = g
        c.clip(to: shape)
        let place = CGAffineTransform(a: face.width, b: 0, c: 0, d: face.height, tx: face.minX, ty: face.minY)
        for strand in grain { c.stroke(strand.path.applying(place), with: .color(strand.colour), lineWidth: strand.width * face.width) }
        c.fill(shape, with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 0.2, blue: 0).opacity(0), Color(red: 0.36, green: 0.18, blue: 0.02).opacity(0.3)]),
                                            center: CGPoint(x: face.midX, y: face.midY - face.height * 0.04), startRadius: face.width * 0.3, endRadius: face.width * 0.78))
        c.fill(shape, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0)]), startPoint: face.origin, endPoint: CGPoint(x: face.midX, y: face.midY)))
        c.stroke(Path(roundedRect: face.insetBy(dx: 0.8, dy: 0.8), cornerRadius: corner),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.12), Color.black.opacity(0.2)]),
                                       startPoint: face.origin, endPoint: CGPoint(x: face.maxX, y: face.maxY)), lineWidth: 1.6)
    }

    /// The grid, its star points and its coordinates, in ink.
    static func grid(_ g: GraphicsContext, origin: CGPoint, step: CGFloat) {
        let n = GomokuPosition.size, span = CGFloat(n - 1) * step
        func snap(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
        var lines = Path()
        for k in 1..<(n - 1) {
            let x = snap(origin.x + CGFloat(k) * step), y = snap(origin.y + CGFloat(k) * step)
            lines.move(to: CGPoint(x: x, y: origin.y)); lines.addLine(to: CGPoint(x: x, y: origin.y + span))
            lines.move(to: CGPoint(x: origin.x, y: y)); lines.addLine(to: CGPoint(x: origin.x + span, y: y))
        }
        g.stroke(lines, with: .color(ink.opacity(0.78)), lineWidth: 1)
        g.stroke(Path(CGRect(x: snap(origin.x), y: snap(origin.y), width: snap(span), height: snap(span))), with: .color(ink.opacity(0.9)), lineWidth: 2)
        for (row, col) in [(3, 3), (3, 11), (7, 7), (11, 3), (11, 11)] {
            let p = CGPoint(x: origin.x + CGFloat(col) * step, y: origin.y + CGFloat(row) * step), r = step * 0.095
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(ink.opacity(0.92)))
        }
        guard labels.count == 2 * n else { return }
        let type = step * 0.31, off = step * 0.67
        // One fill each: small type merged into one long path comes out with its curves coarsely cut.
        let brown = Color(red: 0.36, green: 0.23, blue: 0.11)
        for k in 0..<n {
            g.fill(labels[k].applying(CGAffineTransform(a: type, b: 0, c: 0, d: type, tx: origin.x - off, ty: origin.y + CGFloat(k) * step)), with: .color(brown))
            g.fill(labels[n + k].applying(CGAffineTransform(a: type, b: 0, c: 0, d: type, tx: origin.x + CGFloat(k) * step, ty: origin.y + span + off)), with: .color(brown))
        }
    }

    /// The soft shadow a stone throws on the board, and the dark where it touches.
    static func shadow(_ g: GraphicsContext, under p: CGPoint, radius r: CGFloat, lift: Double) {
        let up = CGFloat(lift)
        let centre = CGPoint(x: p.x + r * (0.1 + 0.4 * up), y: p.y + r * (0.16 + 0.6 * up)), reach = r * (1.16 + 0.3 * up)
        let dark = 0.52 * (1 - 0.55 * lift)
        g.fill(Path(ellipseIn: CGRect(x: centre.x - reach, y: centre.y - reach, width: 2 * reach, height: 2 * reach)),
               with: .radialGradient(Gradient(stops: [.init(color: Color.black.opacity(dark), location: 0), .init(color: Color.black.opacity(dark * 0.75), location: 0.7),
                                                      .init(color: Color.black.opacity(0), location: 1)]), center: centre, startRadius: 0, endRadius: reach))
    }

    /// A stone: slate black, polished, with a soft highlight; or shell white, warm, faintly striped, with a sheen.
    static func stone(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, black: Bool, alpha: Double, seed: Int) {
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        let light = CGPoint(x: p.x - r * 0.32, y: p.y - r * 0.38)
        var c = g
        c.opacity = alpha
        if black {
            c.fill(disc, with: .radialGradient(Gradient(stops: [.init(color: Color(red: 0.4, green: 0.41, blue: 0.44), location: 0),
                                                                .init(color: Color(red: 0.17, green: 0.175, blue: 0.19), location: 0.32),
                                                                .init(color: Color(red: 0.06, green: 0.06, blue: 0.07), location: 0.72),
                                                                .init(color: Color(red: 0.015, green: 0.015, blue: 0.02), location: 1)]),
                                               center: light, startRadius: 0, endRadius: r * 1.5))
            // The warm board reflected in the lower rim.
            let rim = r * 0.9
            c.stroke(Path(ellipseIn: CGRect(x: p.x - rim, y: p.y - rim, width: 2 * rim, height: 2 * rim)),
                     with: .linearGradient(Gradient(colors: [Color.clear, Color.clear, Color(red: 0.9, green: 0.64, blue: 0.32).opacity(0.2)]),
                                           startPoint: CGPoint(x: p.x - r, y: p.y - r), endPoint: CGPoint(x: p.x + r * 0.6, y: p.y + r)), lineWidth: r * 0.14)
            glint(c, at: CGPoint(x: p.x - r * 0.34, y: p.y - r * 0.4), radius: r * 0.46, strength: 0.3)
            glint(c, at: CGPoint(x: p.x - r * 0.38, y: p.y - r * 0.44), radius: r * 0.16, strength: 0.6)
        } else {
            c.fill(disc, with: .radialGradient(Gradient(stops: [.init(color: Color(red: 1, green: 1, blue: 0.99), location: 0),
                                                                .init(color: Color(red: 0.975, green: 0.965, blue: 0.935), location: 0.42),
                                                                .init(color: Color(red: 0.9, green: 0.875, blue: 0.83), location: 0.82),
                                                                .init(color: Color(red: 0.78, green: 0.745, blue: 0.68), location: 1)]),
                                               center: light, startRadius: 0, endRadius: r * 1.55))
            let turn = Double(JevDraw.hash(seed, 17) % 628) / 100
            let rotate = CGAffineTransform(a: r * CGFloat(cos(turn)), b: r * CGFloat(sin(turn)), c: -r * CGFloat(sin(turn)), d: r * CGFloat(cos(turn)), tx: p.x, ty: p.y)
            c.stroke(striations.applying(rotate), with: .color(Color(red: 0.62, green: 0.55, blue: 0.44).opacity(0.075)), lineWidth: max(0.45, r * 0.022))
            c.stroke(disc, with: .color(Color(red: 0.42, green: 0.37, blue: 0.3).opacity(0.4)), lineWidth: 0.7)
            glint(c, at: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.36), radius: r * 0.55, strength: 0.75)
        }
    }

    static func glint(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, strength: Double) {
        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: [Color.white.opacity(strength), Color.white.opacity(0)]), center: p, startRadius: 0, endRadius: r))
    }

    /// The last stone played: a small red jewel on it.
    static func marker(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, black: Bool, appear: Double) {
        guard appear > 0 else { return }
        let m = r * 0.24
        var c = g
        c.opacity = appear
        let ring = m + max(1, r * 0.07)
        c.fill(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: 2 * ring, height: 2 * ring)), with: .color(black ? Color.white.opacity(0.85) : Color(red: 0.3, green: 0.05, blue: 0.02).opacity(0.3)))
        c.fill(Path(ellipseIn: CGRect(x: p.x - m, y: p.y - m, width: 2 * m, height: 2 * m)),
               with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.5, blue: 0.4), Color(red: 0.85, green: 0.12, blue: 0.08), Color(red: 0.6, green: 0.05, blue: 0.03)]),
                                     center: CGPoint(x: p.x - m * 0.3, y: p.y - m * 0.35), startRadius: 0, endRadius: m * 1.3))
    }
}
