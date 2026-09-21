import SwiftUI

/// Games a decision model can play, one multiple-choice question at a time.
///
/// The shape is the one the Tetris example (`jev-tetris`) arrived at: *the
/// measuring happens here and only the judgment is left to the model.* A model
/// like Jev reads text and is weak at arithmetic, so a game does not hand over
/// a board — it lists the legal moves, works out what each one does, and says
/// it in words: small counts as numbers, larger quantities as named buckets.
/// The model answers one Choice question, "which of these is best".
///
/// A game is therefore five things: what it is, how to judge a move, the
/// position in words, the options in words, and a grid to draw. Adding a game
/// is writing those five.

/// One square of the picture every game here is: a colour, maybe a label.
struct JevCell: Equatable {
    var colour: Color?
    var text: String = ""
    /// The label's colour, and whether it is the point of the square (a chess
    /// piece) rather than a caption on it (a 2048 tile's number).
    var ink: Color? = nil
    var big = false
    /// A round piece under the label — a xiangqi man is a disc with a
    /// character on it, not a figure standing on a square.
    var disc: Color? = nil
}

/// One thing the player could do, as it is put to a model. Several moves that
/// read the same are one option — a model cannot tell them apart, so the game
/// breaks the tie — and `merit` is the game's own opinion, for the heuristic
/// player and for saying how often a model agreed with it.
struct JevOption: Identifiable {
    let id: String              // "p01"
    let label: String
    let merit: Double
    /// The move played when a model picks this option: among moves that read
    /// the same, the one a plain tie-break prefers — not the evaluator's
    /// favourite, or every model would be quietly playing with its help.
    let move: Int
    /// The evaluator's own favourite among them, which is what the heuristic
    /// player plays: the yardstick judges moves, not descriptions of them.
    var strongest: Int? = nil
    /// What the program makes of the move when it looks as far as the words
    /// for a reader do — further than `merit`, which is what the evaluator
    /// that plays sees. Nil where a game looks no further for anybody.
    var insight: Double? = nil

    /// This option as the heuristic would play it.
    var judged: JevOption { JevOption(id: id, label: label, merit: merit, move: strongest ?? move, insight: insight) }
}

@MainActor
protocol JevGame: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    var rules: String { get }
    var question: String { get }
    var howToJudge: String { get }
    /// The position before the move, in words.
    var situation: String { get }
    var over: Bool { get }
    var score: Int { get }
    /// A line for under the board: "37 块 · 12 行 · 下一个 T".
    var status: String { get }
    var grid: [[JevCell]] { get }
    func reset(seed: UInt64)
    func options() -> [JevOption]
    func play(_ option: JevOption)
    /// The sides of a game for two — "白方", "黑方" — and whose move it is.
    /// Empty for a game played alone.
    var sides: [String] { get }
    var turn: Int { get }
    /// The position itself, for a player that can read one: a chat model
    /// knows what a chess board is, and the words about each move are only
    /// what the evaluator made of them. Empty when the words are all there is.
    var position: String { get }
    /// Who the next `options()` are for: a player that reads the words (a
    /// model), or one that does not (the evaluator, dice). A game may measure
    /// more for a reader than the evaluator that plays against it looks at —
    /// which is the only way a reader has ever beaten it.
    func prepare(reader: Bool)
}

extension JevGame {
    var sides: [String] { [] }
    var turn: Int { 0 }
    var position: String { "" }
    func prepare(reader: Bool) {}
}

/// The same seed deals the same game to every player, so they can be compared.
struct JevDice {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
}

private func plural(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }

/// Options that read the same become one, keeping the best by `better`. All of
/// them go out: capping the list at sixteen once cut the best placement off the
/// end of it, and the yardstick lost a game it should play for ever.
private func ballot<M>(_ moves: [M], words: (M) -> String, merit: (M) -> Double, better: (M, M) -> Bool) -> [JevOption] {
    var order: [String] = [], best: [String: Int] = [:], strongest: [String: Int] = [:]
    for (index, move) in moves.enumerated() {
        let text = words(move)
        if let held = best[text] {
            if better(move, moves[held]) { best[text] = index }
            if merit(move) > merit(moves[strongest[text]!]) { strongest[text] = index }
        } else { order.append(text); best[text] = index; strongest[text] = index }
    }
    return order.enumerated().map { n, text in
        JevOption(id: String(format: "p%02d", n + 1), label: text, merit: merit(moves[strongest[text]!]),
                  move: best[text]!, strongest: strongest[text]!)
    }
}

// MARK: - Tetris

/// The example's Tetris, ported: ten by twenty, seven pieces from a shuffled
/// bag, every straight drop of every rotation as the choice, and each drop
/// described by what it does — lines, holes, height, surface.
@MainActor
final class JevTetris: JevGame {
    let id = "tetris", title = "俄罗斯方块", symbol = "square.grid.3x3.topleft.filled"
    let rules = "Tetris. The board is 10 columns wide and 20 rows tall. A completed row clears. A hole is an empty cell buried under blocks. The game is lost when the stack reaches the top."
    let question = "Which placement of the current piece is the best move for surviving as long as possible?"
    let howToJudge = "Each option describes the board right after that placement. Clearing lines is good. Creating holes is bad, and worse than missing a line clear. A lower stack is better than a higher one. A flat surface is better than a bumpy one."

    static let width = 10, height = 20
    private typealias Board = [[UInt8]]
    private struct Features { var lines = 0, holes = 0, newHoles = 0, maxHeight = 0, aggHeight = 0, bumpiness = 0, landing = 0 }
    private struct Placement { var after: Board; var feat: Features }
    private struct Shape { var cells: [(x: Int, y: Int)]; var w: Int; var h: Int }

    private static let names = ["I", "O", "T", "S", "Z", "J", "L"]
    private static let colours: [Color] = [.cyan, .yellow, .purple, .green, .red, .blue, .orange]
    private static let pieces: [[Shape]] = [
        [(0, 0), (1, 0), (2, 0), (3, 0)], [(0, 0), (1, 0), (0, 1), (1, 1)], [(0, 0), (1, 0), (2, 0), (1, 1)],
        [(1, 0), (2, 0), (0, 1), (1, 1)], [(0, 0), (1, 0), (1, 1), (2, 1)], [(0, 0), (0, 1), (1, 1), (2, 1)],
        [(2, 0), (0, 1), (1, 1), (2, 1)],
    ].map(rotations)

    private var board: Board = []
    private var current = 0, next = 0, bag: [Int] = []
    private var dice = JevDice(seed: 1)
    private var moves: [Placement] = []
    private(set) var pieces = 0, lines = 0
    private(set) var over = false

    var score: Int { lines }
    var status: String { "\(pieces) 块 · \(lines) 行 · 这一块 \(Self.names[current]) · 下一块 \(Self.names[next])" }
    var situation: String {
        let f = Self.measure(board)
        return "current piece \(Self.names[current]); board before the move: \(Self.heightWords(f.maxHeight)); \(plural(f.holes, "hole")); surface \(Self.surfaceWords(f.bumpiness))"
    }
    var grid: [[JevCell]] { board.map { $0.map { JevCell(colour: $0 == 0 ? nil : Self.colours[Int($0) - 1]) } } }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        board = Array(repeating: Array(repeating: 0, count: Self.width), count: Self.height)
        dice = JevDice(seed: seed); bag = []; pieces = 0; lines = 0; over = false
        current = draw(); next = draw()
    }

    private func draw() -> Int {
        if bag.isEmpty {                                  // a shuffled bag of all seven, like modern Tetris
            bag = Array(0..<7)
            for i in stride(from: 6, to: 0, by: -1) { bag.swapAt(i, dice.below(i + 1)) }
        }
        return bag.removeFirst()
    }

    func options() -> [JevOption] {
        let before = Self.measure(board)
        moves = []
        for shape in Self.pieces[current] {
            for x in 0...(Self.width - shape.w) {
                var y = -shape.h
                while Self.fits(board, shape, x, y + 1) { y += 1 }
                guard y >= 0 else { continue }
                var placed = board
                for cell in shape.cells { placed[y + cell.y][x + cell.x] = UInt8(current + 1) }
                let kept = placed.filter { $0.contains(0) }
                let cleared = Self.height - kept.count
                let after = Array(repeating: Array(repeating: UInt8(0), count: Self.width), count: cleared) + kept
                var feat = Self.measure(after)
                feat.lines = cleared; feat.newHoles = feat.holes - before.holes; feat.landing = Self.height - y
                moves.append(Placement(after: after, feat: feat))
            }
        }
        if moves.isEmpty { over = true; return [] }
        return ballot(moves, words: { Self.describe($0.feat) }, merit: { Self.value($0.feat) }) { a, b in
            (a.feat.landing, a.feat.bumpiness, a.feat.aggHeight) < (b.feat.landing, b.feat.bumpiness, b.feat.aggHeight)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        board = moves[option.move].after
        lines += moves[option.move].feat.lines
        pieces += 1
        current = next; next = draw()
    }

    // The classic four-feature evaluator, with the weights Yiyuan Lee found by genetic search.
    private static func value(_ f: Features) -> Double {
        -0.510066 * Double(f.aggHeight) + 0.760666 * Double(f.lines) - 0.35663 * Double(f.holes) - 0.184483 * Double(f.bumpiness)
    }

    private static func describe(_ f: Features) -> String {
        let cleared = f.lines == 0 ? "clears no lines" : f.lines == 4 ? "clears 4 lines (a Tetris)" : "clears \(plural(f.lines, "line"))"
        let holes = f.newHoles == 0 ? "creates no holes" : f.newHoles < 0 ? "uncovers \(plural(-f.newHoles, "buried hole"))" : "creates \(plural(f.newHoles, "hole"))"
        return [cleared, holes, heightWords(f.maxHeight), "surface " + surfaceWords(f.bumpiness)].joined(separator: "; ")
    }
    private static func heightWords(_ h: Int) -> String {
        "stack \(plural(h, "row")) high (\(h <= 5 ? "low" : h <= 10 ? "medium" : h <= 14 ? "high" : "dangerously high"))"
    }
    private static func surfaceWords(_ b: Int) -> String { b <= 4 ? "flat" : b <= 8 ? "slightly uneven" : b <= 13 ? "bumpy" : "very jagged" }

    private static func measure(_ board: Board) -> Features {
        var f = Features(), last = 0
        for x in 0..<width {
            var top = 0
            for y in 0..<height {
                if board[y][x] != 0, top == 0 { top = height - y } else if board[y][x] == 0, top != 0 { f.holes += 1 }
            }
            f.aggHeight += top; f.maxHeight = max(f.maxHeight, top)
            if x > 0 { f.bumpiness += abs(top - last) }
            last = top
        }
        return f
    }

    private static func fits(_ board: Board, _ shape: Shape, _ x: Int, _ y: Int) -> Bool {
        shape.cells.allSatisfy { cell in
            let cx = x + cell.x, cy = y + cell.y
            return cx >= 0 && cx < width && cy < height && (cy < 0 || board[cy][cx] == 0)
        }
    }

    private static func rotations(_ base: [(Int, Int)]) -> [Shape] {
        var seen = Set<String>(), shapes: [Shape] = [], cells = base
        for _ in 0..<4 {
            let minX = cells.map { $0.0 }.min()!, minY = cells.map { $0.1 }.min()!
            let moved = cells.map { (x: $0.0 - minX, y: $0.1 - minY) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            let key = moved.map { "\($0.x),\($0.y)" }.joined(separator: " ")
            if seen.insert(key).inserted {
                shapes.append(Shape(cells: moved, w: moved.map { $0.x }.max()! + 1, h: moved.map { $0.y }.max()! + 1))
            }
            cells = cells.map { (-$0.1, $0.0) }
        }
        return shapes
    }
}

// MARK: - 2048

/// Four moves at most, and a long way to look ahead — the opposite kind of
/// choice from Tetris. Each slide is described by what it merges, how much
/// room it leaves, and whether the big tile keeps its corner.
@MainActor
final class Jev2048: JevGame {
    let id = "2048", title = "2048", symbol = "number.square"
    let rules = "2048. A 4 by 4 board of numbered tiles. A move slides every tile one way; two equal tiles that meet merge into their sum. After each move a new 2 or 4 appears in an empty cell. The game is lost when the board is full and nothing can merge."
    let question = "Which direction is the best move for reaching the highest tile without filling the board?"
    let howToJudge = "Each option describes the board right after sliding that way, before the new tile appears. Keeping the largest tile in a corner is good, and pulling it out of the corner is bad. More empty cells is good. Merging tiles is good. A board whose rows and columns run in order is better than a scrambled one."

    private struct Slide { var name: String; var after: [[Int]]; var gained: Int; var merges: Int }
    private var board = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    private var dice = JevDice(seed: 1)
    private var moves: [Slide] = []
    private(set) var score = 0, turns = 0
    private(set) var over = false

    var status: String { "\(turns) 步 · \(score) 分 · 最大 \(board.flatMap { $0 }.max() ?? 0)" }
    var situation: String {
        let largest = board.flatMap { $0 }.max() ?? 0
        return "largest tile \(largest), \(Self.cornered(board) ? "in a corner" : "not in a corner"); \(Self.roomWords(Self.empties(board))); \(Self.orderWords(Self.ordered(board)))"
    }
    var grid: [[JevCell]] {
        board.map { $0.map { value in
            guard value > 0 else { return JevCell() }
            let warmth = min(log2(Double(value)) / 11, 1)
            return JevCell(colour: Color(hue: 0.13 - 0.13 * warmth, saturation: 0.35 + 0.6 * warmth, brightness: 0.95), text: "\(value)")
        } }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        board = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        dice = JevDice(seed: seed); score = 0; turns = 0; over = false
        spawn(); spawn()
    }

    func options() -> [JevOption] {
        moves = ["left", "right", "up", "down"].compactMap { name in
            let slid = Self.slide(board, name)
            return slid.after == board ? nil : Slide(name: name, after: slid.after, gained: slid.gained, merges: slid.merges)
        }
        if moves.isEmpty { over = true; return [] }
        // Four options that are four different directions: never merged into one, whatever they read like.
        return moves.enumerated().map { index, move in
            JevOption(id: String(format: "p%02d", index + 1), label: "slide \(move.name): " + Self.describe(move, before: board),
                      merit: Self.value(move), move: index)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        board = moves[option.move].after
        score += moves[option.move].gained
        turns += 1
        spawn()
    }

    private func spawn() {
        let free = (0..<16).filter { board[$0 / 4][$0 % 4] == 0 }
        guard !free.isEmpty else { return }
        let at = free[dice.below(free.count)]
        board[at / 4][at % 4] = dice.below(10) == 0 ? 4 : 2
    }

    private static func describe(_ move: Slide, before: [[Int]]) -> String {
        let largest = move.after.flatMap { $0 }.max() ?? 0
        let merged = move.merges == 0 ? "merges nothing" : "merges \(plural(move.merges, "pair")) for \(move.gained) points"
        let corner = cornered(move.after) ? "largest tile \(largest) is in a corner"
            : (cornered(before) ? "pulls the largest tile \(largest) out of its corner" : "largest tile \(largest) is not in a corner")
        return [merged, roomWords(empties(move.after)), corner, orderWords(ordered(move.after))].joined(separator: "; ")
    }
    private static func roomWords(_ n: Int) -> String { "\(plural(n, "empty cell")) (\(n >= 8 ? "roomy" : n >= 4 ? "getting tight" : "nearly full"))" }
    private static func orderWords(_ n: Int) -> String { "\(n) of 8 rows and columns in order (\(n >= 6 ? "orderly" : n >= 4 ? "mixed" : "scrambled"))" }
    private static func empties(_ b: [[Int]]) -> Int { b.flatMap { $0 }.filter { $0 == 0 }.count }
    private static func cornered(_ b: [[Int]]) -> Bool {
        let largest = b.flatMap { $0 }.max() ?? 0
        return largest > 0 && [b[0][0], b[0][3], b[3][0], b[3][3]].contains(largest)
    }
    /// Rows and columns whose tiles never go up and then down.
    private static func ordered(_ b: [[Int]]) -> Int {
        let lines = b + (0..<4).map { x in (0..<4).map { b[$0][x] } }
        return lines.filter { line in
            let tiles = line.filter { $0 > 0 }
            return tiles == tiles.sorted() || tiles == tiles.sorted(by: >)
        }.count
    }
    private static func value(_ m: Slide) -> Double {
        2.7 * Double(empties(m.after)) + (cornered(m.after) ? 6 : 0) + 1.2 * Double(ordered(m.after)) + log2(Double(max(m.gained, 1)))
    }

    private static func slide(_ board: [[Int]], _ way: String) -> (after: [[Int]], gained: Int, merges: Int) {
        var gained = 0, merges = 0
        func squeeze(_ line: [Int]) -> [Int] {
            var tiles = line.filter { $0 > 0 }, out: [Int] = []
            while !tiles.isEmpty {
                let tile = tiles.removeFirst()
                if let next = tiles.first, next == tile { tiles.removeFirst(); out.append(tile * 2); gained += tile * 2; merges += 1 }
                else { out.append(tile) }
            }
            return out + Array(repeating: 0, count: 4 - out.count)
        }
        var after = board
        switch way {
        case "left": after = board.map(squeeze)
        case "right": after = board.map { Array(squeeze($0.reversed()).reversed()) }
        default:
            for x in 0..<4 {
                let column = (0..<4).map { board[$0][x] }
                let slid = way == "up" ? squeeze(column) : Array(squeeze(column.reversed()).reversed())
                for y in 0..<4 { after[y][x] = slid[y] }
            }
        }
        return (after, gained, merges)
    }
}

// MARK: - Snake

/// A choice about space: up to three ways to go, each described by whether it
/// reaches the food and by how much room is left once it has.
@MainActor
final class JevSnake: JevGame {
    let id = "snake", title = "贪吃蛇", symbol = "scribble.variable"
    let rules = "Snake on a 14 by 14 board. The snake moves one cell at a time and cannot stop or reverse. Eating the food makes it one cell longer and a new food appears. The game is lost when the head hits a wall or the snake's own body."
    let question = "Which way should the snake go next to eat as much food as possible without ever trapping itself?"
    let howToJudge = "Each option describes where the head ends up. Never choose a move into a space smaller than the snake: it is a trap and the game ends there. Among safe moves, getting closer to the food is good and eating it is best. Plenty of open space ahead is better than a cramped corridor."

    static let side = 14
    private struct Step { var name: String; var head: (x: Int, y: Int); var eats: Bool; var distance: Int; var room: Int }
    private var body: [(x: Int, y: Int)] = []          // head first
    private var food = (x: 0, y: 0)
    private var dice = JevDice(seed: 1)
    private var moves: [Step] = []
    private(set) var score = 0, turns = 0
    private(set) var over = false

    var status: String { "\(turns) 步 · 吃了 \(score) 个 · 身长 \(body.count)" }
    var situation: String {
        let head = body[0]
        return "snake length \(body.count); food is \(abs(head.x - food.x) + abs(head.y - food.y)) cells away"
    }
    var grid: [[JevCell]] {
        var cells = Array(repeating: Array(repeating: JevCell(), count: Self.side), count: Self.side)
        cells[food.y][food.x] = JevCell(colour: .red)
        for (index, part) in body.enumerated() { cells[part.y][part.x] = JevCell(colour: index == 0 ? .green : Color.green.opacity(0.55)) }
        return cells
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        dice = JevDice(seed: seed); score = 0; turns = 0; over = false
        body = [(7, 7), (6, 7), (5, 7)]
        placeFood()
    }

    func options() -> [JevOption] {
        let head = body[0], neck = body[1]
        moves = [("up", 0, -1), ("down", 0, 1), ("left", -1, 0), ("right", 1, 0)].compactMap { name, dx, dy in
            let to = (x: head.x + dx, y: head.y + dy)
            guard !(to.x == neck.x && to.y == neck.y) else { return nil }                     // cannot reverse
            guard to.x >= 0, to.y >= 0, to.x < Self.side, to.y < Self.side else { return nil }
            let eats = to.x == food.x && to.y == food.y
            let trail = eats ? body : Array(body.dropLast())                                 // the tail moves on unless it grows
            guard !trail.contains(where: { $0.x == to.x && $0.y == to.y }) else { return nil }
            return Step(name: name, head: to, eats: eats, distance: abs(to.x - food.x) + abs(to.y - food.y),
                        room: room(from: to, blocked: trail))
        }
        if moves.isEmpty { over = true; return [] }
        let now = abs(head.x - food.x) + abs(head.y - food.y)
        return moves.enumerated().map { index, step in
            let food = step.eats ? "eats the food" : step.distance < now ? "gets closer to the food (\(plural(step.distance, "cell")) away)"
                : "moves away from the food (\(plural(step.distance, "cell")) away)"
            let space = step.room < body.count ? "only \(plural(step.room, "free cell")) ahead, fewer than the snake is long (a trap)"
                : step.room < body.count * 3 ? "\(step.room) free cells ahead (cramped)" : "\(step.room) free cells ahead (plenty of room)"
            let merit = (step.room < body.count ? -1000 : 0) + (step.eats ? 50 : 0) - Double(step.distance) + min(Double(step.room), 60) * 0.05
            return JevOption(id: String(format: "p%02d", index + 1), label: "go \(step.name): \(food); \(space)", merit: merit, move: index)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        let step = moves[option.move]
        body.insert(step.head, at: 0)
        if step.eats { score += 1; placeFood() } else { body.removeLast() }
        turns += 1
        if body.count >= Self.side * Self.side - 1 { over = true }
    }

    private func placeFood() {
        let free = (0..<(Self.side * Self.side)).filter { at in !body.contains { $0.x == at % Self.side && $0.y == at / Self.side } }
        guard !free.isEmpty else { over = true; return }
        let at = free[dice.below(free.count)]
        food = (at % Self.side, at / Self.side)
    }

    /// Cells reachable from `start` without crossing the snake.
    private func room(from start: (x: Int, y: Int), blocked: [(x: Int, y: Int)]) -> Int {
        var seen = Set(blocked.map { $0.y * Self.side + $0.x }), queue = [start], count = 0
        seen.insert(start.y * Self.side + start.x)
        while let cell = queue.popLast() {
            count += 1
            for (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                let x = cell.x + dx, y = cell.y + dy
                guard x >= 0, y >= 0, x < Self.side, y < Self.side, seen.insert(y * Self.side + x).inserted else { continue }
                queue.append((x, y))
            }
        }
        return count
    }
}
