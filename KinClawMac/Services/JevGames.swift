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
    /// A short name for a person to click, where the words are long and in English: "训练 3 个长枪兵".
    var title: String? = nil

    /// This option as the heuristic would play it.
    var judged: JevOption { JevOption(id: id, label: label, merit: merit, move: strongest ?? move, insight: insight, title: title) }
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

    // MARK: Played by a person

    /// Seconds a tick, for a game that goes on by itself when a person plays
    /// it — the car keeps driving, the bird keeps falling, and pressing
    /// nothing is a move too. Nil for a game that waits for the move.
    var clock: Double? { get }
    /// The keys, in words, for the person at the keyboard.
    var controls: String { get }
    /// Letter keys the game listens to; the arrows and space are always its own.
    var letters: Set<Character> { get }
    /// What a person's keys mean. On a clock: the keys pressed during the
    /// tick, in order, and those still held — and the answer is an option,
    /// because the clock does not wait. Otherwise one key at a time.
    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction
    /// A click on the board, by row and column as drawn.
    func tap(row: Int, col: Int, among options: [JevOption]) -> JevReaction
    /// Whether the next `options()` are for a person: every legal move, not
    /// a shortlist — a person may play anything — and a board that shows
    /// what a click would do.
    func prepare(person: Bool)
}

extension JevGame {
    var sides: [String] { [] }
    var turn: Int { 0 }
    var position: String { "" }
    func prepare(reader: Bool) {}
    var clock: Double? { nil }
    var controls: String { "点右边的一个选项" }
    var letters: Set<Character> { [] }
    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction { .nothing }
    func tap(row: Int, col: Int, among options: [JevOption]) -> JevReaction { .nothing }
    func prepare(person: Bool) {}
}

/// A key a person pressed, as a game sees it.
enum JevPress: Hashable {
    case left, right, up, down, space
    case letter(Character)
}

/// What a person's key or click did.
enum JevReaction {
    /// Nothing this game listens to.
    case nothing
    /// Only the board changed: a piece picked up, a cursor moved.
    case redraw
    /// That is the move.
    case choose(JevOption)
    /// Not a move, and why not: said to the person over the board.
    case explain(String)
}

extension Array where Element == JevPress {
    /// The last of these that was pressed during the tick, or failing that one still held.
    func latest(of wanted: Set<JevPress>, held: Set<JevPress>) -> JevPress? {
        last(where: wanted.contains) ?? wanted.first(where: held.contains)
    }
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
    /// For each placement, the rotation, the column and the row it lands on: what a person's cursor points at.
    private var slots: [(rot: Int, x: Int, y: Int)] = []
    /// The last piece dropped, for the picture: the board before, the board with it, the rows it filled.
    fileprivate var drop: TetrisDrop?
    private(set) var ticked = Date.distantPast
    private var person = false
    private var cursor = (rot: 0, x: 3)
    /// A person's piece falls by itself: the row it has reached, when it last dropped a row,
    /// since when it has lain on something, and how many moves have bought it more time there.
    private var fall = 0, lastFall = Date(), restingSince: Date?, nudges = 0
    private(set) var pieces = 0, lines = 0
    private(set) var over = false

    var score: Int { lines }
    var status: String { "\(pieces) 块 · \(lines) 行 · 这一块 \(Self.names[current]) · 下一块 \(Self.names[next])" }
    var situation: String {
        let f = Self.measure(board)
        return "current piece \(Self.names[current]); board before the move: \(Self.heightWords(f.maxHeight)); \(plural(f.holes, "hole")); surface \(Self.surfaceWords(f.bumpiness))"
    }
    var grid: [[JevCell]] {
        var cells = board.map { $0.map { JevCell(colour: $0 == 0 ? nil : Self.colours[Int($0) - 1]) } }
        // A person's piece, where it would land: a shadow to aim with.
        if person, !over {
            let shape = Self.pieces[current][min(cursor.rot, Self.pieces[current].count - 1)]
            var y = -shape.h
            while Self.fits(board, shape, cursor.x, y + 1) { y += 1 }
            if y >= 0 {
                for cell in shape.cells { cells[y + cell.y][cursor.x + cell.x] = JevCell(colour: Self.colours[current].opacity(0.4)) }
            }
        }
        return cells
    }
    let controls = "方块自己往下落 · ←→ 移动 · ↑ 旋转 · ↓ 加速 · 空格 直接落到底（虚线框是会落到的地方）"
    /// A person plays against gravity: twenty looks a second at the keys.
    var clock: Double? { person ? 0.05 : nil }
    /// Seconds a row: faster every ten lines, as in the arcade.
    private var rowTime: Double { max(0.07, 0.8 * pow(0.82, Double(lines / 10))) }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        board = Array(repeating: Array(repeating: 0, count: Self.width), count: Self.height)
        dice = JevDice(seed: seed); bag = []; pieces = 0; lines = 0; over = false
        current = draw(); next = draw()
        aim()
        drop = nil; ticked = .distantPast
    }

    func prepare(person: Bool) { self.person = person }

    /// A new piece starts unrotated, in the middle, at the top.
    private func aim() {
        cursor = (0, (Self.width - Self.pieces[current][0].w) / 2)
        fall = 0; lastFall = Date(); restingSince = nil; nudges = 0
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
        moves = []; slots = []
        for (rot, shape) in Self.pieces[current].enumerated() {
            for x in 0...(Self.width - shape.w) {
                var y = -shape.h
                while Self.fits(board, shape, x, y + 1) { y += 1 }
                guard y >= 0 else { continue }
                moves.append(Self.placement(board, current, shape, x, y, before: before)); slots.append((rot, x, y))
            }
        }
        if moves.isEmpty { over = true; return [] }
        return ballot(moves, words: { Self.describe($0.feat) }, merit: { Self.value($0.feat) }) { a, b in
            (a.feat.landing, a.feat.bumpiness, a.feat.aggHeight) < (b.feat.landing, b.feat.bumpiness, b.feat.aggHeight)
        }
    }

    private static func placement(_ board: Board, _ kind: Int, _ shape: Shape, _ x: Int, _ y: Int, before: Features) -> Placement {
        var placed = board
        for cell in shape.cells { placed[y + cell.y][x + cell.x] = UInt8(kind + 1) }
        let kept = placed.filter { $0.contains(0) }
        let cleared = height - kept.count
        let after = Array(repeating: Array(repeating: UInt8(0), count: width), count: cleared) + kept
        var feat = measure(after)
        feat.lines = cleared; feat.newHoles = feat.holes - before.holes; feat.landing = height - y
        return Placement(after: after, feat: feat)
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        let slot = slots[option.move]
        let cells = Self.pieces[current][slot.rot].cells.map { (x: slot.x + $0.x, y: slot.y + $0.y) }
        var placed = board
        for cell in cells { placed[cell.y][cell.x] = UInt8(current + 1) }
        drop = TetrisDrop(kind: current, cells: cells, before: board, placed: placed,
                          cleared: placed.indices.filter { !placed[$0].contains(0) }, fell: person)
        board = moves[option.move].after
        lines += moves[option.move].feat.lines
        pieces += 1
        current = next; next = draw()
        aim()
        ticked = Date()
    }

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let turns = Self.pieces[current]
        func fits(_ rot: Int, _ x: Int, _ y: Int) -> Bool { Self.fits(board, turns[rot], x, y) }
        // No room for the new piece to come in: the stack has reached the top.
        guard fits(cursor.rot, cursor.x, fall) else { over = true; return .nothing }
        var moved = false
        for key in pressed {
            switch key {
            case .left, .right:
                let x = cursor.x + (key == .left ? -1 : 1)
                if fits(cursor.rot, x, fall) { cursor.x = x; moved = true }
            case .up:
                // Turned against a wall or a block, it steps aside if it can.
                let rot = (cursor.rot + 1) % turns.count
                if let kick = [0, -1, 1, -2, 2].first(where: { fits(rot, cursor.x + $0, fall) }) { cursor = (rot, cursor.x + kick); moved = true }
            case .space:
                while fits(cursor.rot, cursor.x, fall + 1) { fall += 1 }
                return lock(options)
            default: break
            }
        }
        let now = Date()
        if fits(cursor.rot, cursor.x, fall + 1) {
            restingSince = nil
            // Gravity; with ↓ held, a row a tick.
            let pace = held.contains(.down) || pressed.contains(.down) ? min(rowTime, 0.05) : rowTime
            if now.timeIntervalSince(lastFall) >= pace { fall += 1; lastFall = now }
        } else {
            // On something: half a second to slide it — a little longer for each move, up to a point — then it sets.
            if restingSince == nil || (moved && nudges < 15) { restingSince = now; if moved { nudges += 1 } }
            if let since = restingSince, now.timeIntervalSince(since) >= 0.5 { return lock(options) }
        }
        return .redraw
    }

    /// Where a person's piece came to rest, as the move it is — the list's own, or one slid under an overhang.
    private func lock(_ options: [JevOption]) -> JevReaction {
        let rot = cursor.rot, x = cursor.x, y = fall
        let index: Int
        if let listed = slots.firstIndex(where: { $0.rot == rot && $0.x == x && $0.y == y }) { index = listed }
        else {
            moves.append(Self.placement(board, current, Self.pieces[current][rot], x, y, before: Self.measure(board)))
            slots.append((rot, x, y))
            index = moves.count - 1
        }
        let words = Self.describe(moves[index].feat)
        let id = options.first(where: { $0.label == words })?.id ?? "p00"
        return .choose(JevOption(id: id, label: words, merit: Self.value(moves[index].feat), move: index))
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
    /// The last slide, for the picture: where each tile came from and went, what merged, what appeared.
    private var trails: [(from: (Int, Int), to: (Int, Int), value: Int)] = []
    private var merged: Set<Int> = [], spawned: Int?
    private(set) var ticked = Date.distantPast
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
        trails = []; merged = []; spawned = nil; ticked = .distantPast
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
        let before = board
        (trails, merged) = Self.trace(before, moves[option.move].name)
        board = moves[option.move].after
        score += moves[option.move].gained
        turns += 1
        let slid = board
        spawn()
        spawned = (0..<16).first { slid[$0 / 4][$0 % 4] == 0 && board[$0 / 4][$0 % 4] != 0 }
        ticked = Date()
    }

    /// Where each tile goes in a slide, and which squares end up holding a merge.
    private static func trace(_ board: [[Int]], _ way: String) -> ([(from: (Int, Int), to: (Int, Int), value: Int)], Set<Int>) {
        var out: [(from: (Int, Int), to: (Int, Int), value: Int)] = [], merged: Set<Int> = []
        for line in 0..<4 {
            let cells: [(Int, Int)] = (0..<4).map { k in
                switch way {
                case "left": return (line, k)
                case "right": return (line, 3 - k)
                case "up": return (k, line)
                default: return (3 - k, line)
                }
            }
            let tiles = cells.filter { board[$0.0][$0.1] != 0 }
            var k = 0, target = 0
            while k < tiles.count {
                let value = board[tiles[k].0][tiles[k].1]
                if k + 1 < tiles.count, board[tiles[k + 1].0][tiles[k + 1].1] == value {
                    out.append((tiles[k], cells[target], value)); out.append((tiles[k + 1], cells[target], value))
                    merged.insert(cells[target].0 * 4 + cells[target].1)
                    k += 2
                } else { out.append((tiles[k], cells[target], value)); k += 1 }
                target += 1
            }
        }
        return (out, merged)
    }

    let controls = "方向键滑动"

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let names: [JevPress: String] = [.left: "left", .right: "right", .up: "up", .down: "down"]
        guard let key = pressed.last, let name = names[key],
              let option = options.first(where: { $0.label.hasPrefix("slide \(name):") }) else { return .nothing }
        return .choose(option)
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

    nonisolated static let side = 14
    private struct Step { var name: String; var head: (x: Int, y: Int); var eats: Bool; var distance: Int; var room: Int; var dies: String? = nil }
    private var body: [(x: Int, y: Int)] = []          // head first
    private var food = (x: 0, y: 0)
    /// The body and the food before the last step, and where a person's snake hit, for the picture.
    private var before: [(x: Int, y: Int)] = [], eaten: (x: Int, y: Int)?, crash: (x: Int, y: Int)?
    private(set) var ticked = Date.distantPast
    private var dice = JevDice(seed: 1)
    private var moves: [Step] = []
    private(set) var score = 0, turns = 0
    private(set) var over = false
    private var person = false, crashed = false
    let clock: Double? = 0.14
    let controls = "方向键转弯 · 不按就一直往前"

    func prepare(person: Bool) { self.person = person }

    var status: String { (crashed ? "撞上了 · " : "") + "\(turns) 步 · 吃了 \(score) 个 · 身长 \(body.count)" }
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
        dice = JevDice(seed: seed); score = 0; turns = 0; over = false; crashed = false
        body = [(7, 7), (6, 7), (5, 7)]
        placeFood()
        before = body; eaten = nil; crash = nil; ticked = .distantPast
    }

    func options() -> [JevOption] {
        let head = body[0], neck = body[1]
        moves = [("up", 0, -1), ("down", 0, 1), ("left", -1, 0), ("right", 1, 0)].compactMap { name, dx, dy in
            let to = (x: head.x + dx, y: head.y + dy)
            guard !(to.x == neck.x && to.y == neck.y) else { return nil }                     // cannot reverse
            // A model is offered only the moves that live; a person steers where they steer.
            guard to.x >= 0, to.y >= 0, to.x < Self.side, to.y < Self.side else {
                return person ? Step(name: name, head: to, eats: false, distance: 0, room: 0, dies: "hits the wall") : nil
            }
            let eats = to.x == food.x && to.y == food.y
            let trail = eats ? body : Array(body.dropLast())                                 // the tail moves on unless it grows
            guard !trail.contains(where: { $0.x == to.x && $0.y == to.y }) else {
                return person ? Step(name: name, head: to, eats: false, distance: 0, room: 0, dies: "runs into its own body") : nil
            }
            return Step(name: name, head: to, eats: eats, distance: abs(to.x - food.x) + abs(to.y - food.y),
                        room: room(from: to, blocked: trail))
        }
        if moves.isEmpty { over = true; return [] }
        let now = abs(head.x - food.x) + abs(head.y - food.y)
        return moves.enumerated().map { index, step in
            if let dies = step.dies {
                return JevOption(id: String(format: "p%02d", index + 1), label: "go \(step.name): \(dies): the game ends", merit: -10_000, move: index)
            }
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
        before = body; eaten = nil; ticked = Date()
        if step.dies != nil { over = true; crashed = true; crash = step.head; return }
        body.insert(step.head, at: 0)
        if step.eats { score += 1; eaten = food; placeFood() } else { body.removeLast() }
        turns += 1
        if body.count >= Self.side * Self.side - 1 { over = true }
    }

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let ways: [JevPress: String] = [.up: "up", .down: "down", .left: "left", .right: "right"]
        let heading = (x: body[0].x - body[1].x, y: body[0].y - body[1].y)
        let straight = heading.x < 0 ? "left" : heading.x > 0 ? "right" : heading.y < 0 ? "up" : "down"
        let wanted = pressed.last(where: { ways[$0] != nil }).flatMap { ways[$0] } ?? straight
        for name in [wanted, straight] {
            if let option = options.first(where: { $0.label.hasPrefix("go \(name):") }) { return .choose(option) }
        }
        return options.first.map { .choose($0) } ?? .nothing
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

// MARK: - Pictures

/// The last Tetris piece dropped.
fileprivate struct TetrisDrop {
    var kind: Int
    var cells: [(x: Int, y: Int)]
    var before: [[UInt8]], placed: [[UInt8]]
    var cleared: [Int]
    /// A person's piece has already fallen on screen: no fall to show again, only the landing.
    var fell = false
}

// MARK: Tetris

/// The seven jewels, in piece order I O T S Z J L: aquamarine, citrine, amethyst, emerald, ruby, sapphire, topaz.
fileprivate let tetrisTints: [(Double, Double, Double)] = [
    (0.07, 0.78, 0.95), (1.00, 0.76, 0.10), (0.64, 0.28, 0.95), (0.18, 0.80, 0.36), (0.95, 0.18, 0.28), (0.22, 0.40, 1.00), (1.00, 0.52, 0.10),
]

/// Stars behind the well, in fractions of the picture: where, how big (at 640 points wide), and which of three twinkles.
fileprivate let tetrisStars: [(x: Double, y: Double, r: Double, beat: Int)] = (0..<70).map { i -> (x: Double, y: Double, r: Double, beat: Int) in
    let x: Double = Double(JevDraw.hash(i, 1) % 1000) / 1000, y: Double = Double(JevDraw.hash(i, 2) % 1000) / 1000
    let big: Double = i % 9 == 0 ? 1.4 : 0.6
    let r: Double = 0.5 + Double(JevDraw.hash(i, 3) % 100) / 100 * big
    return (x, y, r, i % 3)
}

/// Tetris blocks cut like jewels: a dark rim, four facets lit from the top left, a table that darkens toward
/// its foot, a glossy highlight and a glint. Gathered a colour at a time — every block of a colour is one path
/// per facet — so a full well is a few dozen fills rather than a thousand.
fileprivate struct TetrisJewels {
    private var rects: [[CGRect]] = Array(repeating: [], count: 7)

    mutating func add(_ rect: CGRect, _ kind: Int) { if rects.indices.contains(kind) { rects[kind].append(rect) } }

    /// Blocks of one size at one height within their row share a gradient that repeats every row.
    private static func beat(_ r: CGRect) -> Int {
        let s = max(r.width, 1), phase = r.minY - (r.minY / s).rounded(.down) * s
        return Int((s * 8).rounded()) * 100_000 + Int((phase * 8).rounded())
    }

    func paint(_ g: GraphicsContext) {
        var shine: [Int: (top: CGFloat, side: CGFloat, path: Path)] = [:]
        var glints = Path()
        for kind in 0..<7 where !rects[kind].isEmpty {
            let tint = tetrisTints[kind]
            var rim = Path(), top = Path(), left = Path(), right = Path(), foot = Path()
            var tables: [Int: (top: CGFloat, side: CGFloat, path: Path)] = [:]
            for r in rects[kind] {
                let s = r.width
                rim.addRoundedRect(in: r.insetBy(dx: s * 0.025, dy: s * 0.025), cornerSize: CGSize(width: s * 0.15, height: s * 0.15))
                let o = r.insetBy(dx: s * 0.085, dy: s * 0.085), f = r.insetBy(dx: s * 0.24, dy: s * 0.24)
                let oTR = CGPoint(x: o.maxX, y: o.minY), oBL = CGPoint(x: o.minX, y: o.maxY), oBR = CGPoint(x: o.maxX, y: o.maxY)
                let fTR = CGPoint(x: f.maxX, y: f.minY), fBL = CGPoint(x: f.minX, y: f.maxY), fBR = CGPoint(x: f.maxX, y: f.maxY)
                top.addLines([o.origin, oTR, fTR, f.origin]); top.closeSubpath()
                left.addLines([o.origin, f.origin, fBL, oBL]); left.closeSubpath()
                right.addLines([oTR, oBR, fBR, fTR]); right.closeSubpath()
                foot.addLines([oBL, fBL, fBR, oBR]); foot.closeSubpath()
                let key = Self.beat(r)
                tables[key, default: (f.minY, s, Path())].path.addRect(f)
                shine[key, default: (f.minY, s, Path())].path.addRoundedRect(
                    in: CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height * 0.46), cornerSize: CGSize(width: s * 0.04, height: s * 0.04))
                glints.addEllipse(in: CGRect(x: f.minX + s * 0.03, y: f.minY + s * 0.03, width: s * 0.11, height: s * 0.11))
            }
            g.fill(rim, with: .color(JevDraw.shade(tint, 0.3)))
            g.fill(foot, with: .color(JevDraw.shade(tint, 0.5)))
            g.fill(right, with: .color(JevDraw.shade(tint, 0.7)))
            g.fill(left, with: .color(JevDraw.shade(tint, 1.2)))
            g.fill(top, with: .color(JevDraw.shade(tint, 1.5)))
            let table = Gradient(stops: [.init(color: JevDraw.shade(tint, 1.18), location: 0), .init(color: JevDraw.shade(tint, 0.95), location: 0.26),
                                         .init(color: JevDraw.shade(tint, 0.74), location: 0.52)])
            for face in tables.values {
                g.fill(face.path, with: .linearGradient(table, startPoint: CGPoint(x: 0, y: face.top), endPoint: CGPoint(x: 0, y: face.top + face.side), options: .repeat))
            }
        }
        let gloss = Gradient(stops: [.init(color: .white.opacity(0.55), location: 0), .init(color: .white.opacity(0.05), location: 0.24)])
        for sheen in shine.values {
            g.fill(sheen.path, with: .linearGradient(gloss, startPoint: CGPoint(x: 0, y: sheen.top), endPoint: CGPoint(x: 0, y: sheen.top + sheen.side), options: .repeat))
        }
        g.fill(glints, with: .color(.white.opacity(0.9)))
    }
}

extension JevTetris: JevPainted {
    var aspect: Double { 0.78 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        var ghost: [(x: Int, y: Int)] = [], active: [(x: Int, y: Int)] = [], sink = 0.0
        if person, !over {
            let shape = Self.pieces[current][min(cursor.rot, Self.pieces[current].count - 1)]
            if Self.fits(board, shape, cursor.x, fall) {
                var y = fall
                while Self.fits(board, shape, cursor.x, y + 1) { y += 1 }
                active = shape.cells.map { (x: cursor.x + $0.x, y: fall + $0.y) }
                if y > fall {
                    ghost = shape.cells.map { (x: cursor.x + $0.x, y: y + $0.y) }
                    // Between rows it sinks smoothly, rather than hopping.
                    sink = min(max((now - lastFall.timeIntervalSinceReferenceDate) / rowTime, 0), 0.97)
                }
            }
        }
        let scene = TetrisScene(board: board, drop: drop, t: t, now: now, current: current, next: next,
                                preview: Self.pieces[next][0].cells.map { (x: $0.x, y: $0.y) }, ghost: ghost,
                                active: active, sink: sink, lines: lines, pieces: pieces, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

fileprivate struct TetrisScene {
    let board: [[UInt8]], drop: TetrisDrop?, t: Double, now: Double, current: Int, next: Int
    let preview: [(x: Int, y: Int)], ghost: [(x: Int, y: Int)]
    /// A person's piece on its way down, and how far it has sunk toward the next row.
    let active: [(x: Int, y: Int)], sink: Double
    let lines: Int, pieces: Int, over: Bool

    /// A drop in beats: the piece falls and lands with a flash; the rows it filled go white, burst from the
    /// middle outwards and are gone; then the rows above settle into their places.
    private static let landed = 0.42, burst = 0.82

    /// When the block in column `x` of a clearing row bursts, through the clearing (0…1): the middle first.
    private static func vanish(_ x: Int) -> Double { 0.32 + 0.42 * abs(Double(x) - 4.5) / 4.5 }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let cell = min(size.height / 21.6, size.width / 16.3)
        let well = CGRect(x: cell * 0.9, y: (size.height - cell * 20) / 2, width: cell * 10, height: cell * 20)
        func square(_ x: Double, _ y: Double) -> CGRect {
            CGRect(x: well.minX + CGFloat(x) * cell, y: well.minY + CGFloat(y) * cell, width: cell, height: cell)
        }
        backdrop(g, size)
        frame(g, well, cell)

        var inWell = g
        inWell.clip(to: Path(roundedRect: well, cornerRadius: cell * 0.12))
        var glow = inWell
        glow.blendMode = .plusLighter
        // A stack near the top: the top of the well smoulders red.
        if let top = board.firstIndex(where: { $0.contains { $0 != 0 } }), top < 6 {
            let heat = Double(6 - top) / 6 * (0.75 + 0.25 * sin(now * 4))
            inWell.fill(Path(CGRect(x: well.minX, y: well.minY, width: well.width, height: cell * 6)),
                        with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.16, blue: 0.3).opacity(0.42 * heat), .clear]),
                                              startPoint: well.origin, endPoint: CGPoint(x: well.minX, y: well.minY + cell * 6)))
        }

        // What stands in the well at this moment.
        let fell = drop?.fell ?? false
        let landed = fell ? 0 : Self.landed
        let falling = drop != nil && !fell && t < landed
        let clearing = !falling && t < 1 && !(drop?.cleared.isEmpty ?? true)
        let p = min(max((t - landed) / (Self.burst - landed), 0), 1)
        var gems = TetrisJewels()
        if falling, let drop {
            for y in drop.before.indices { for x in drop.before[y].indices where drop.before[y][x] != 0 { gems.add(square(Double(x), Double(y)), Int(drop.before[y][x]) - 1) } }
        } else if clearing, let drop {
            let settle = JevDraw.smooth((t - Self.burst) / (1 - Self.burst))
            for y in drop.placed.indices {
                let gone = drop.cleared.contains(y)
                let fall = Double(drop.cleared.filter { $0 > y }.count) * settle
                for x in drop.placed[y].indices where drop.placed[y][x] != 0 && (!gone || p < Self.vanish(x)) {
                    gems.add(square(Double(x), Double(y) + (gone ? 0 : fall)), Int(drop.placed[y][x]) - 1)
                }
            }
        } else {
            for y in board.indices { for x in board[y].indices where board[y][x] != 0 { gems.add(square(Double(x), Double(y)), Int(board[y][x]) - 1) } }
        }

        // A person's aim: a faint beam from the falling piece down to the outline of where it will land.
        if !ghost.isEmpty {
            let tint = tetrisTints[current]
            let left = ghost.map(\.x).min() ?? 0, right = ghost.map(\.x).max() ?? 0, top = ghost.map(\.y).min() ?? 0
            let from = CGFloat(Double((active.map(\.y).max() ?? -1) + 1) + sink)
            let beam = CGRect(x: well.minX + CGFloat(left) * cell, y: well.minY + from * cell, width: CGFloat(right - left + 1) * cell, height: max(0, CGFloat(top) - from) * cell)
            inWell.fill(Path(beam), with: .linearGradient(Gradient(colors: [JevDraw.shade(tint, 1).opacity(0), JevDraw.shade(tint, 1).opacity(0.09)]),
                                                        startPoint: CGPoint(x: 0, y: beam.minY), endPoint: CGPoint(x: 0, y: beam.maxY)))
        }

        // The falling piece, with a streak of light above each of its columns.
        if falling, let drop {
            let e = pow(t / Self.landed, 2), top = drop.cells.map(\.y).min() ?? 0
            let lift = Double(top + 3) * (1 - e)
            var columns: [Int: Int] = [:]
            for c in drop.cells { columns[c.x] = min(columns[c.x] ?? c.y, c.y) }
            let tint = tetrisTints[drop.kind]
            for (x, y) in columns {
                let head = square(Double(x), Double(y) - lift)
                let long = cell * CGFloat(0.5 + 2.8 * e)
                for (inset, alpha) in [(0.3, 0.22), (0.42, 0.4)] as [(CGFloat, Double)] {
                    let streak = CGRect(x: head.minX + cell * inset, y: head.minY - long, width: cell * (1 - 2 * inset), height: long + cell * 0.4)
                    glow.fill(Path(roundedRect: streak, cornerRadius: streak.width / 2),
                              with: .linearGradient(Gradient(colors: [JevDraw.shade(tint, 1.3).opacity(0), JevDraw.shade(tint, 1.3).opacity(alpha)]),
                                                    startPoint: CGPoint(x: 0, y: streak.minY), endPoint: CGPoint(x: 0, y: streak.maxY)))
                }
            }
            for c in drop.cells { gems.add(square(Double(c.x), Double(c.y) - lift), drop.kind) }
        }
        for c in active { gems.add(square(Double(c.x), Double(c.y) + sink), current) }
        gems.paint(inWell)

        if let drop, !falling, t < 1 {
            // It lands with a flash.
            let land = 1 - (t - landed) / 0.2
            if land > 0 {
                var flash = Path()
                for c in drop.cells where !drop.cleared.contains(c.y) {
                    flash.addRoundedRect(in: square(Double(c.x), Double(c.y)).insetBy(dx: cell * 0.04, dy: cell * 0.04), cornerSize: CGSize(width: cell * 0.14, height: cell * 0.14))
                }
                glow.fill(flash, with: .color(.white.opacity(0.5 * land)))
            }
            // The rows it filled: white hot, a glow either side, bursting from the middle out in sparks of their own colours.
            if clearing {
                var hot = Path(), cores = Path(), sparks = Array(repeating: Path(), count: 7)
                let heat = min(p / 0.22, 1) * 0.92
                for row in drop.cleared {
                    let band = CGRect(x: well.minX, y: well.minY + CGFloat(row) * cell, width: well.width, height: cell)
                    let halo = band.insetBy(dx: 0, dy: -cell * 1.3)
                    glow.fill(Path(halo), with: .linearGradient(Gradient(colors: [.clear, Color(red: 0.8, green: 0.75, blue: 1).opacity(0.5 * sin(p * .pi)), .clear]),
                                                              startPoint: CGPoint(x: 0, y: halo.minY), endPoint: CGPoint(x: 0, y: halo.maxY)))
                    for x in 0..<10 {
                        let box = square(Double(x), Double(row))
                        if p < Self.vanish(x) {
                            hot.addRoundedRect(in: box.insetBy(dx: cell * 0.03, dy: cell * 0.03), cornerSize: CGSize(width: cell * 0.14, height: cell * 0.14))
                            continue
                        }
                        let age = (p - Self.vanish(x)) / 0.38, kind = Int(drop.placed[row][x]) - 1
                        guard age < 1, sparks.indices.contains(kind) else { continue }
                        for k in 0..<3 {
                            let angle = Double(JevDraw.hash(row * 10 + x, k) % 628) / 100
                            let reach = cell * CGFloat((0.5 + Double(JevDraw.hash(x, row * 3 + k) % 100) / 70) * (1 - pow(1 - age, 2)))
                            let r = cell * 0.2 * CGFloat(1 - age)
                            let q = CGPoint(x: box.midX + CGFloat(cos(angle)) * reach, y: box.midY + CGFloat(sin(angle)) * reach * 0.8)
                            sparks[kind].addLines([CGPoint(x: q.x, y: q.y - r), CGPoint(x: q.x + r * 0.42, y: q.y), CGPoint(x: q.x, y: q.y + r), CGPoint(x: q.x - r * 0.42, y: q.y)])
                            sparks[kind].closeSubpath()
                            cores.addEllipse(in: CGRect(x: q.x - r * 0.22, y: q.y - r * 0.22, width: r * 0.44, height: r * 0.44))
                        }
                    }
                }
                glow.fill(hot, with: .color(.white.opacity(heat)))
                let reach = min(p / 0.25, 1), beam = (1 - p) * min(p / 0.1, 1)
                for row in drop.cleared {
                    let y = well.minY + (CGFloat(row) + 0.5) * cell, half = well.width * 0.5 * CGFloat(reach)
                    glow.fill(Path(roundedRect: CGRect(x: well.midX - half, y: y - cell * 0.09, width: half * 2, height: cell * 0.18), cornerRadius: cell * 0.09),
                              with: .color(.white.opacity(beam)))
                }
                for kind in 0..<7 where !sparks[kind].isEmpty { inWell.fill(sparks[kind], with: .color(JevDraw.shade(tetrisTints[kind], 1.3))) }
                glow.fill(cores, with: .color(.white.opacity(0.9)))
            }
        }

        if !ghost.isEmpty {
            let tint = tetrisTints[current]
            var shape = Path()
            for c in ghost {
                shape.addRoundedRect(in: square(Double(c.x), Double(c.y)).insetBy(dx: cell * 0.1, dy: cell * 0.1), cornerSize: CGSize(width: cell * 0.16, height: cell * 0.16))
            }
            inWell.fill(shape, with: .color(JevDraw.shade(tint, 1).opacity(0.2)))
            inWell.stroke(shape, with: .color(JevDraw.shade(tint, 1.35).opacity(0.95)), lineWidth: max(1.2, cell * 0.06))
        }

        // The glass over the well catches the light.
        var pane = Path()
        pane.addLines([well.origin, CGPoint(x: well.minX + well.width * 0.75, y: well.minY), CGPoint(x: well.minX, y: well.minY + well.height * 0.38)])
        pane.closeSubpath()
        inWell.fill(pane, with: .linearGradient(Gradient(colors: [.white.opacity(0.07), .white.opacity(0)]), startPoint: well.origin,
                                               endPoint: CGPoint(x: well.minX + well.width * 0.28, y: well.minY + well.height * 0.14)))

        panel(g, size, well, cell)
        if over { JevDraw.curtain(g, size, title: "堆满了！", detail: "消了 \(lines) 行 · 用了 \(pieces) 块") }
    }

    /// Night: a deep gradient, two soft glows and a sky of slowly twinkling stars.
    private func backdrop(_ g: GraphicsContext, _ size: CGSize) {
        let all = Path(CGRect(origin: .zero, size: size))
        g.fill(all, with: .linearGradient(Gradient(colors: [Color(red: 0.045, green: 0.05, blue: 0.14), Color(red: 0.11, green: 0.055, blue: 0.21)]),
                                          startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
        g.fill(all, with: .radialGradient(Gradient(colors: [Color(red: 0.34, green: 0.26, blue: 0.92).opacity(0.32), .clear]),
                                          center: CGPoint(x: size.width * 0.92, y: size.height * 0.1), startRadius: 0, endRadius: size.width * 0.8))
        g.fill(all, with: .radialGradient(Gradient(colors: [Color(red: 0.8, green: 0.2, blue: 0.62).opacity(0.2), .clear]),
                                          center: CGPoint(x: size.width * 0.02, y: size.height * 0.98), startRadius: 0, endRadius: size.width * 0.75))
        for beat in 0..<3 {
            var dots = Path()
            for star in tetrisStars where star.beat == beat {
                let r = CGFloat(star.r) * size.width / 640
                dots.addEllipse(in: CGRect(x: CGFloat(star.x) * size.width - r, y: CGFloat(star.y) * size.height - r, width: 2 * r, height: 2 * r))
            }
            g.fill(dots, with: .color(.white.opacity(0.3 + 0.25 * sin(now * 1.7 + Double(beat) * 2.1))))
        }
    }

    /// The well: a soft halo, a bevelled frame, a deep shaft lit faintly from below, a faint grid, and shade under its lip.
    private func frame(_ g: GraphicsContext, _ well: CGRect, _ cell: CGFloat) {
        for (reach, alpha) in [(0.7, 0.045), (0.5, 0.06), (0.34, 0.09)] {
            g.fill(Path(roundedRect: well.insetBy(dx: -cell * reach, dy: -cell * reach), cornerRadius: cell * (0.3 + reach)),
                   with: .color(Color(red: 0.5, green: 0.4, blue: 1).opacity(alpha)))
        }
        let bezel = well.insetBy(dx: -cell * 0.24, dy: -cell * 0.24)
        g.fill(Path(roundedRect: bezel.offsetBy(dx: cell * 0.08, dy: cell * 0.16), cornerRadius: cell * 0.34), with: .color(.black.opacity(0.35)))
        g.fill(Path(roundedRect: bezel, cornerRadius: cell * 0.3),
               with: .linearGradient(Gradient(colors: [Color(red: 0.52, green: 0.54, blue: 0.9), Color(red: 0.2, green: 0.16, blue: 0.44)]),
                                     startPoint: bezel.origin, endPoint: CGPoint(x: bezel.maxX, y: bezel.maxY)))
        g.stroke(Path(roundedRect: bezel.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.3),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.6), .white.opacity(0.04)]), startPoint: bezel.origin,
                                       endPoint: CGPoint(x: bezel.minX + cell * 2, y: bezel.minY + cell * 4)), lineWidth: 1)
        let hole = Path(roundedRect: well, cornerRadius: cell * 0.12)
        g.fill(hole, with: .linearGradient(Gradient(colors: [Color(red: 0.012, green: 0.016, blue: 0.06), Color(red: 0.05, green: 0.035, blue: 0.15)]),
                                           startPoint: well.origin, endPoint: CGPoint(x: well.minX, y: well.maxY)))
        g.fill(hole, with: .radialGradient(Gradient(colors: [Color(red: 0.42, green: 0.26, blue: 0.95).opacity(0.26), .clear]),
                                           center: CGPoint(x: well.midX, y: well.maxY), startRadius: 0, endRadius: well.height * 0.62))
        var grid = Path()
        for x in 1..<10 { grid.addRect(CGRect(x: well.minX + CGFloat(x) * cell - 0.35, y: well.minY, width: 0.7, height: well.height)) }
        for y in 1..<20 { grid.addRect(CGRect(x: well.minX, y: well.minY + CGFloat(y) * cell - 0.35, width: well.width, height: 0.7)) }
        g.fill(grid, with: .color(Color(red: 0.7, green: 0.7, blue: 1).opacity(0.065)))
        // Shade under the lip on the top and left, a little light caught on the bottom and right.
        let lip = cell * 0.6, caught = Color(red: 0.6, green: 0.55, blue: 1)
        g.fill(Path(CGRect(x: well.minX, y: well.minY, width: well.width, height: lip)),
               with: .linearGradient(Gradient(colors: [.black.opacity(0.55), .clear]), startPoint: CGPoint(x: 0, y: well.minY), endPoint: CGPoint(x: 0, y: well.minY + lip)))
        g.fill(Path(CGRect(x: well.minX, y: well.minY, width: lip * 0.7, height: well.height)),
               with: .linearGradient(Gradient(colors: [.black.opacity(0.4), .clear]), startPoint: CGPoint(x: well.minX, y: 0), endPoint: CGPoint(x: well.minX + lip * 0.7, y: 0)))
        g.fill(Path(CGRect(x: well.maxX - lip * 0.6, y: well.minY, width: lip * 0.6, height: well.height)),
               with: .linearGradient(Gradient(colors: [caught.opacity(0.1), .clear]), startPoint: CGPoint(x: well.maxX, y: 0), endPoint: CGPoint(x: well.maxX - lip * 0.6, y: 0)))
        g.fill(Path(CGRect(x: well.minX, y: well.maxY - lip * 0.6, width: well.width, height: lip * 0.6)),
               with: .linearGradient(Gradient(colors: [caught.opacity(0.14), .clear]), startPoint: CGPoint(x: 0, y: well.maxY), endPoint: CGPoint(x: 0, y: well.maxY - lip * 0.6)))
    }

    /// Beside the well, one tall pane of glass: the next piece floating over a pool of its own light, the lines
    /// cleared and the pieces used, and the seven jewels along its foot.
    private func panel(_ g: GraphicsContext, _ size: CGSize, _ well: CGRect, _ cell: CGFloat) {
        let side = CGRect(x: well.maxX + cell * 1.0, y: well.minY - cell * 0.24, width: size.width - well.maxX - cell * 1.55, height: well.height + cell * 0.48)
        glass(g, side, cell)
        let unit = side.height / 20
        func y(_ k: CGFloat) -> CGFloat { side.minY + unit * k }
        caption(g, "下一块", at: CGPoint(x: side.midX, y: y(0.95)), cell)
        let small = cell * 0.8, tint = tetrisTints[next]
        let wide = CGFloat((preview.map(\.x).max() ?? 0) + 1), tall = CGFloat((preview.map(\.y).max() ?? 0) + 1)
        let centre = CGPoint(x: side.midX, y: y(3.9) + cell * 0.06 * CGFloat(sin(now * 2.1)))
        var lit = g
        lit.clip(to: Path(roundedRect: side, cornerRadius: cell * 0.42))
        lit.fill(Path(CGRect(x: centre.x - cell * 2.4, y: centre.y - cell * 2.4, width: cell * 4.8, height: cell * 4.8)),
                 with: .radialGradient(Gradient(colors: [JevDraw.shade(tint, 1).opacity(0.4), JevDraw.shade(tint, 1).opacity(0)]), center: centre, startRadius: 0, endRadius: cell * 2.2))
        let pool = CGRect(x: side.midX - cell * 1.6, y: y(5.75), width: cell * 3.2, height: cell * 0.5)
        lit.fill(Path(ellipseIn: pool), with: .radialGradient(Gradient(colors: [JevDraw.shade(tint, 1.3).opacity(0.35), JevDraw.shade(tint, 1).opacity(0)]),
                                                             center: CGPoint(x: pool.midX, y: pool.midY), startRadius: 0, endRadius: pool.width / 2))
        var shown = TetrisJewels()
        for c in preview {
            shown.add(CGRect(x: centre.x - wide * small / 2 + CGFloat(c.x) * small, y: centre.y - tall * small / 2 + CGFloat(c.y) * small, width: small, height: small), next)
        }
        shown.paint(g)
        for (index, (title, value)) in [("消行", lines), ("方块", pieces)].enumerated() {
            let top = y(7.3 + 4.9 * CGFloat(index))
            let rule = CGRect(x: side.minX + cell * 0.5, y: top, width: side.width - cell, height: 1)
            g.fill(Path(rule), with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)]),
                                                     startPoint: CGPoint(x: rule.minX, y: 0), endPoint: CGPoint(x: rule.maxX, y: 0)))
            caption(g, title, at: CGPoint(x: side.midX, y: top + unit * 1.25), cell)
            let font = Font.system(size: cell * 1.45, weight: .heavy, design: .rounded).monospacedDigit()
            let at = CGPoint(x: side.midX, y: top + unit * 2.95)
            g.draw(Text(verbatim: "\(value)").font(font).foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.9).opacity(0.55)), at: CGPoint(x: at.x, y: at.y + cell * 0.08))
            g.draw(Text(verbatim: "\(value)").font(font).foregroundColor(.white), at: at)
        }
        // The seven jewels, small, along the foot of the pane.
        let rule = CGRect(x: side.minX + cell * 0.5, y: y(17.1), width: side.width - cell, height: 1)
        g.fill(Path(rule), with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)]),
                                                 startPoint: CGPoint(x: rule.minX, y: 0), endPoint: CGPoint(x: rule.maxX, y: 0)))
        let tiny = min(cell * 0.5, (side.width - cell * 0.8) / 7.6)
        var row = TetrisJewels()
        for kind in 0..<7 {
            let bob = CGFloat(sin(now * 1.6 + Double(kind) * 0.8)) * tiny * 0.08
            row.add(CGRect(x: side.midX - tiny * 3.5 + CGFloat(kind) * tiny, y: y(18.55) - tiny / 2 + bob, width: tiny, height: tiny), kind)
        }
        row.paint(g)
    }

    /// A pane of smoked glass: a shadow under it, lighter at the top, an edge that catches the light.
    private func glass(_ g: GraphicsContext, _ r: CGRect, _ cell: CGFloat) {
        let radius = cell * 0.42
        g.fill(Path(roundedRect: r.offsetBy(dx: cell * 0.06, dy: cell * 0.16), cornerRadius: radius), with: .color(.black.opacity(0.32)))
        let shape = Path(roundedRect: r, cornerRadius: radius)
        g.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.28, blue: 0.6).opacity(0.6), Color(red: 0.12, green: 0.09, blue: 0.3).opacity(0.6)]),
                                            startPoint: r.origin, endPoint: CGPoint(x: r.minX, y: r.maxY)))
        g.fill(shape, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0.12), location: 0), .init(color: .white.opacity(0), location: 0.5)]),
                                            startPoint: r.origin, endPoint: CGPoint(x: r.minX, y: r.maxY)))
        g.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.45), .white.opacity(0.08)]), startPoint: r.origin, endPoint: CGPoint(x: r.minX, y: r.maxY)), lineWidth: 1)
    }

    private func caption(_ g: GraphicsContext, _ text: String, at point: CGPoint, _ cell: CGFloat) {
        g.draw(Text(text).font(.system(size: cell * 0.5, weight: .bold, design: .rounded)).tracking(cell * 0.12)
                .foregroundColor(Color(red: 0.8, green: 0.78, blue: 1).opacity(0.85)), at: point)
    }
}

// MARK: 2048

extension Jev2048: JevPainted {
    var aspect: Double { 0.84 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = Scene2048(board: board, trails: trails, merged: merged, spawned: spawned, t: t, now: now, score: score,
                              best: board.flatMap { $0 }.max() ?? 0, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

fileprivate struct Scene2048 {
    let board: [[Int]], trails: [(from: (Int, Int), to: (Int, Int), value: Int)], merged: Set<Int>, spawned: Int?
    let t: Double, now: Double, score: Int, best: Int, over: Bool

    /// The classic tiles.
    private static let tints: [Int: (Double, Double, Double)] = [
        2: (0.93, 0.89, 0.85), 4: (0.93, 0.88, 0.78), 8: (0.95, 0.69, 0.47), 16: (0.96, 0.58, 0.39), 32: (0.96, 0.49, 0.37),
        64: (0.96, 0.37, 0.23), 128: (0.93, 0.81, 0.45), 256: (0.93, 0.80, 0.38), 512: (0.93, 0.78, 0.31), 1024: (0.93, 0.77, 0.25),
        2048: (0.93, 0.76, 0.18),
    ]
    private static func tint(_ value: Int) -> (Double, Double, Double) { tints[value] ?? (0.24, 0.23, 0.20) }
    private static let ink: (Double, Double, Double) = (0.47, 0.43, 0.40), tray: (Double, Double, Double) = (0.73, 0.68, 0.63)
    private static func colour(_ rgb: (Double, Double, Double)) -> Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
    /// The tiles slide until here; then what merged pops and what is new grows in.
    private static let slid = 0.6

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let pad = size.width * 0.03
        let side = min(size.width, size.height * 0.84) - 2 * pad
        let frame = CGRect(x: (size.width - side) / 2, y: size.height - side - pad, width: side, height: side)
        let gap = side * 0.03, tile = (side - gap * 5) / 4
        func spot(_ r: Double, _ c: Double) -> CGRect {
            CGRect(x: frame.minX + gap + CGFloat(c) * (tile + gap), y: frame.minY + gap + CGFloat(r) * (tile + gap), width: tile, height: tile)
        }
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [Color(red: 0.985, green: 0.972, blue: 0.945), Color(red: 0.955, green: 0.932, blue: 0.892)]),
                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                                                               center: CGPoint(x: size.width * 0.2, y: 0), startRadius: 0, endRadius: size.width * 0.9))
        header(g, frame)
        board(g, frame, gap: gap, tile: tile)

        // Every tile where it is at this moment: sliding, or popping where two merged, or growing where one is new.
        var shown: [(rect: CGRect, value: Int, pop: Double, fade: Double)] = []
        if !trails.isEmpty, t < Self.slid {
            let e = 1 - pow(1 - t / Self.slid, 3)
            for trail in trails {
                shown.append((spot(JevDraw.mix(Double(trail.from.0), Double(trail.to.0), e), JevDraw.mix(Double(trail.from.1), Double(trail.to.1), e)), trail.value, 0, 1))
            }
        } else {
            let p = trails.isEmpty ? 1 : min(max((t - Self.slid) / (1 - Self.slid), 0), 1)
            for r in 0..<4 {
                for c in 0..<4 where board[r][c] != 0 {
                    var rect = spot(Double(r), Double(c)), pop = 0.0, fade = 1.0
                    if merged.contains(r * 4 + c), p < 1 {
                        let swell = CGFloat(sin(p * .pi) * 0.17)
                        rect = rect.insetBy(dx: -rect.width * swell / 2, dy: -rect.height * swell / 2); pop = max(p, 0.001)
                    }
                    if spawned == r * 4 + c, p < 1 {
                        // Grows in from nothing, a touch past its size and back.
                        let x = p - 1, k = CGFloat(max(0, 1 + 2.7 * x * x * x + 1.7 * x * x))
                        rect = rect.insetBy(dx: rect.width * (1 - k) / 2, dy: rect.height * (1 - k) / 2); fade = min(1, p * 3)
                    }
                    shown.append((rect, board[r][c], pop, fade))
                }
            }
        }
        // A merge throws off a soft burst of its colour; big tiles glow warm. Both under everything.
        for s in shown where s.pop > 0 {
            let w = s.rect.width, fade = 1 - s.pop
            for (reach, alpha) in [(0.05 + 0.24 * s.pop, 0.22), (0.02 + 0.14 * s.pop, 0.3)] {
                g.fill(Path(roundedRect: s.rect.insetBy(dx: -w * reach, dy: -w * reach), cornerRadius: w * (0.09 + reach)),
                       with: .color(JevDraw.shade(Self.tint(s.value), 1.15).opacity(alpha * fade)))
            }
        }
        for s in shown where s.value >= 128 {
            let k = min(max((log2(Double(s.value)) - 6) / 5, 0.2), 1) * (0.85 + 0.15 * sin(now * 2.3 + Double(s.value % 7))) * s.fade
            let w = s.rect.width
            for (reach, alpha) in [(0.22, 0.09), (0.14, 0.15), (0.07, 0.24)] {
                g.fill(Path(roundedRect: s.rect.insetBy(dx: -w * reach, dy: -w * reach), cornerRadius: w * (0.09 + reach)),
                       with: .color(Color(red: 1, green: 0.8, blue: 0.3).opacity(alpha * k)))
            }
        }
        for s in shown {
            let w = s.rect.width
            g.fill(Path(roundedRect: s.rect.insetBy(dx: -w * 0.01, dy: -w * 0.01).offsetBy(dx: w * 0.012, dy: w * 0.05), cornerRadius: w * 0.1),
                   with: .color(.black.opacity(0.06 * s.fade)))
            g.fill(Path(roundedRect: s.rect.offsetBy(dx: w * 0.006, dy: w * 0.03), cornerRadius: w * 0.09), with: .color(.black.opacity(0.09 * s.fade)))
        }
        for s in shown {
            var tg = g
            tg.opacity = s.fade
            draw(tg, s.value, in: s.rect)
            if s.pop > 0, s.pop < 0.4 {
                // The new tile flashes as it forms.
                let w = s.rect.width
                g.fill(Path(roundedRect: CGRect(x: s.rect.minX, y: s.rect.minY, width: w, height: s.rect.height - w * 0.045), cornerRadius: w * 0.09),
                       with: .color(.white.opacity(0.4 * (1 - s.pop / 0.4))))
            }
        }
        // From 1024 up, a tile twinkles.
        var stars = Path()
        for s in shown where s.value >= 1024 && s.fade > 0.5 {
            for k in 0..<3 {
                let beat = sin(now * 2.6 + Double(k) * 2.1 + Double(s.value % 11))
                guard beat > 0 else { continue }
                let spots: [(CGFloat, CGFloat)] = [(0.2, 0.2), (0.84, 0.3), (0.72, 0.84)]
                let at = CGPoint(x: s.rect.minX + s.rect.width * spots[k].0, y: s.rect.minY + s.rect.height * spots[k].1)
                let r = s.rect.width * 0.09 * CGFloat(beat)
                stars.addLines([CGPoint(x: at.x, y: at.y - r), CGPoint(x: at.x + r * 0.22, y: at.y - r * 0.22), CGPoint(x: at.x + r, y: at.y),
                                CGPoint(x: at.x + r * 0.22, y: at.y + r * 0.22), CGPoint(x: at.x, y: at.y + r), CGPoint(x: at.x - r * 0.22, y: at.y + r * 0.22),
                                CGPoint(x: at.x - r, y: at.y), CGPoint(x: at.x - r * 0.22, y: at.y - r * 0.22)])
                stars.closeSubpath()
            }
        }
        g.fill(stars, with: .color(.white.opacity(0.95)))
        if over { JevDraw.curtain(g, size, title: "填满了！", detail: "\(score) 分 · 最大 \(best)") }
    }

    /// One tile: raised a little, its foot a shade darker, lit along the top, its number sized to fit.
    private func draw(_ g: GraphicsContext, _ value: Int, in r: CGRect) {
        let rgb = Self.tint(value), w = r.width, radius = w * 0.09
        g.fill(Path(roundedRect: r, cornerRadius: radius), with: .color(JevDraw.shade(rgb, 0.8)))
        let face = CGRect(x: r.minX, y: r.minY, width: w, height: r.height - w * 0.045)
        let top = CGPoint(x: 0, y: face.minY), foot = CGPoint(x: 0, y: face.maxY)
        g.fill(Path(roundedRect: face, cornerRadius: radius), with: .linearGradient(Gradient(colors: [JevDraw.shade(rgb, 1.07), JevDraw.shade(rgb, 0.96)]), startPoint: top, endPoint: foot))
        if value >= 128 {
            // The big ones are lit from inside.
            g.fill(Path(roundedRect: face, cornerRadius: radius), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.8).opacity(0.45), .clear]),
                                                                                         center: CGPoint(x: face.midX, y: face.midY - w * 0.1), startRadius: 0, endRadius: w * 0.62))
        }
        g.fill(Path(roundedRect: face, cornerRadius: radius), with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0.3), location: 0), .init(color: .white.opacity(0), location: 0.4)]),
                                                                                     startPoint: top, endPoint: foot))
        g.stroke(Path(roundedRect: face.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]), startPoint: top, endPoint: CGPoint(x: 0, y: face.minY + w * 0.14)), lineWidth: 1.2)
        let digits = CGFloat(String(value).count)
        let font = Font.system(size: w * min(0.5, 0.78 / (digits * 0.6)), weight: .heavy, design: .rounded)
        let centre = CGPoint(x: face.midX, y: face.midY)
        if value > 4 {
            g.draw(Text(verbatim: "\(value)").font(font).foregroundColor(JevDraw.shade(rgb, 0.55).opacity(0.35)), at: CGPoint(x: centre.x, y: centre.y + w * 0.018))
        }
        g.draw(Text(verbatim: "\(value)").font(font).foregroundColor(value <= 4 ? Self.colour(Self.ink) : Color(red: 0.99, green: 0.97, blue: 0.95)), at: centre)
    }

    /// The title, pressed into the paper, and the two scores on raised plaques.
    private func header(_ g: GraphicsContext, _ frame: CGRect) {
        let band = frame.minY
        let title = Font.system(size: band * 0.6, weight: .heavy, design: .rounded)
        let at = CGPoint(x: frame.minX + 1, y: band * 0.5)
        g.draw(Text("2048").font(title).foregroundColor(.white.opacity(0.95)), at: CGPoint(x: at.x, y: at.y + band * 0.025), anchor: .leading)
        g.draw(Text("2048").font(title).foregroundColor(Self.colour(Self.ink)), at: at, anchor: .leading)
        let w = frame.width * 0.235, h = band * 0.62
        for (index, (title, value)) in [("分数", "\(score)"), ("最大", "\(best)")].enumerated() {
            let box = CGRect(x: frame.maxX - CGFloat(2 - index) * w - CGFloat(1 - index) * frame.width * 0.02, y: (band - h) / 2, width: w, height: h)
            let radius = h * 0.16
            g.fill(Path(roundedRect: box.offsetBy(dx: 0, dy: h * 0.07), cornerRadius: radius), with: .color(.black.opacity(0.08)))
            g.fill(Path(roundedRect: box, cornerRadius: radius), with: .color(JevDraw.shade(Self.tray, 0.84)))
            let face = CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height - h * 0.05)
            g.fill(Path(roundedRect: face, cornerRadius: radius), with: .linearGradient(Gradient(colors: [JevDraw.shade(Self.tray, 1.06), JevDraw.shade(Self.tray, 0.97)]),
                                                                                         startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.maxY)))
            g.stroke(Path(roundedRect: face.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius),
                     with: .linearGradient(Gradient(colors: [.white.opacity(0.45), .white.opacity(0)]), startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.minY + h * 0.3)), lineWidth: 1)
            g.draw(Text(title).font(.system(size: h * 0.21, weight: .bold, design: .rounded)).tracking(h * 0.04)
                    .foregroundColor(Color(red: 0.97, green: 0.94, blue: 0.9)), at: CGPoint(x: face.midX, y: face.minY + face.height * 0.29))
            let digits = CGFloat(value.count)
            let font = Font.system(size: min(h * 0.4, w * 0.84 / (digits * 0.62)), weight: .heavy, design: .rounded).monospacedDigit()
            g.draw(Text(value).font(font).foregroundColor(JevDraw.shade(Self.tray, 0.6).opacity(0.5)), at: CGPoint(x: face.midX, y: face.minY + face.height * 0.67 + h * 0.025))
            g.draw(Text(value).font(font).foregroundColor(.white), at: CGPoint(x: face.midX, y: face.minY + face.height * 0.67))
        }
    }

    /// The board: a raised tray with a shadow on the paper, and sixteen slots sunk into it.
    private func board(_ g: GraphicsContext, _ frame: CGRect, gap: CGFloat, tile: CGFloat) {
        let side = frame.width, radius = side * 0.022
        g.fill(Path(roundedRect: frame.insetBy(dx: -side * 0.008, dy: -side * 0.008).offsetBy(dx: 0, dy: side * 0.018), cornerRadius: radius * 1.4), with: .color(.black.opacity(0.05)))
        g.fill(Path(roundedRect: frame.offsetBy(dx: 0, dy: side * 0.008), cornerRadius: radius), with: .color(.black.opacity(0.1)))
        g.fill(Path(roundedRect: frame, cornerRadius: radius), with: .color(JevDraw.shade(Self.tray, 0.82)))
        let top = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - side * 0.01)
        g.fill(Path(roundedRect: top, cornerRadius: radius), with: .linearGradient(Gradient(colors: [JevDraw.shade(Self.tray, 1.05), JevDraw.shade(Self.tray, 0.97)]),
                                                                                    startPoint: CGPoint(x: 0, y: top.minY), endPoint: CGPoint(x: 0, y: top.maxY)))
        g.stroke(Path(roundedRect: top.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.4), .white.opacity(0)]), startPoint: CGPoint(x: 0, y: top.minY), endPoint: CGPoint(x: 0, y: top.minY + gap * 2)), lineWidth: 1)
        var slots = Path()
        for r in 0..<4 {
            for c in 0..<4 {
                slots.addRoundedRect(in: CGRect(x: frame.minX + gap + CGFloat(c) * (tile + gap), y: frame.minY + gap + CGFloat(r) * (tile + gap), width: tile, height: tile),
                                     cornerSize: CGSize(width: tile * 0.08, height: tile * 0.08))
            }
        }
        g.fill(slots, with: .color(Color(red: 0.8, green: 0.76, blue: 0.71)))
        // Sunk: shade along the top of each slot, light along its foot — one gradient that repeats every row.
        let span = Double(tile / (tile + gap))
        g.fill(slots, with: .linearGradient(Gradient(stops: [.init(color: .black.opacity(0.13), location: 0), .init(color: .black.opacity(0), location: 0.16 * span),
                                                             .init(color: .white.opacity(0), location: 0.84 * span), .init(color: .white.opacity(0.3), location: span)]),
                                            startPoint: CGPoint(x: 0, y: frame.minY + gap), endPoint: CGPoint(x: 0, y: frame.minY + gap + tile + gap), options: .repeat))
    }
}

// MARK: Snake

extension JevSnake: JevPainted {
    var aspect: Double { 0.9 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = SnakeScene(before: before, after: body, food: food, eaten: eaten, crash: crash, t: t, since: since, now: now,
                               score: score, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

/// The garden's fixed furniture, worked out once, in fractions of whatever it decorates.
fileprivate enum SnakeGarden {
    static func unit(_ a: Int, _ b: Int) -> Double { Double(JevDraw.hash(a, b) % 10_000) / 10_000 }

    /// Blades of grass on the lawn: where (0…1 of the lawn), which way they lean, how long (in squares), light or dark.
    static let blades: [(x: Double, y: Double, lean: Double, length: Double, light: Bool)] = (0..<340).map { i -> (x: Double, y: Double, lean: Double, length: Double, light: Bool) in
        let lean: Double = (unit(i, 3) - 0.5) * 0.9, length: Double = 0.1 + 0.13 * unit(i, 4)
        return (unit(i, 1), unit(i, 2), lean, length, i % 3 == 0)
    }
    /// Tufts: little fans of taller, darker blades.
    static let tufts: [(x: Double, y: Double, size: Double)] = (0..<24).map { i -> (x: Double, y: Double, size: Double) in
        let size: Double = 0.75 + 0.5 * unit(i, 7)
        return (unit(i, 5), unit(i, 6), size)
    }
    /// Where each stone of the wall ends along its side, as a fraction of the side: top, right, bottom, left.
    static let stones: [[Double]] = (0..<4).map { side -> [Double] in
        let lengths: [Double] = (0..<18).map { (k: Int) -> Double in 0.65 + 0.7 * unit(side * 31 + k, 8) }
        let total: Double = lengths.reduce(0, +)
        var ends: [Double] = [], at = 0.0
        for length in lengths { at += length / total; ends.append(at) }
        return ends
    }
    /// Leaves of the hedge around the garden, in fractions of the picture: where, how big, how turned, which green.
    static let leaves: [(x: Double, y: Double, r: Double, turn: Double, tone: Int)] = (0..<260).map { i -> (x: Double, y: Double, r: Double, turn: Double, tone: Int) in
        let y: Double = i < 170 ? unit(i, 10) * 0.16 : unit(i, 10)
        let r: Double = 0.012 + 0.012 * unit(i, 11), turn: Double = unit(i, 12) * Double.pi
        return (unit(i, 9), y, r, turn, i % 3)
    }
    /// Flowers in the hedge above the lawn, in fractions of the picture: where, how big, and which colour.
    static let flowers: [(x: Double, y: Double, r: Double, hue: Int)] = (0..<9).map { i -> (x: Double, y: Double, r: Double, hue: Int) in
        let x: Double = 0.36 + 0.28 * (Double(i) + unit(i, 13)) / 9
        let y: Double = 0.035 + 0.07 * unit(i, 14), r: Double = 0.011 + 0.006 * unit(i, 15)
        return (x, y, r, i % 3)
    }
}

fileprivate struct SnakeScene {
    let before: [(x: Int, y: Int)], after: [(x: Int, y: Int)], food: (x: Int, y: Int), eaten: (x: Int, y: Int)?, crash: (x: Int, y: Int)?
    let t: Double, since: Double, now: Double, score: Int, over: Bool

    private typealias RGB = (Double, Double, Double)
    private static let head: RGB = (0.32, 0.6, 1.0), tail: RGB = (0.16, 0.27, 0.78), rim: RGB = (0.06, 0.12, 0.38)
    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let n = CGFloat(JevSnake.side), pad = size.width * 0.022, top = size.height * 0.105
        let cell = min((size.width - 2 * pad) / (n + 0.9), (size.height - top - pad) / (n + 0.9))
        let wall = cell * 0.45
        let lawn = CGRect(x: (size.width - cell * n) / 2, y: size.height - pad - wall - cell * n, width: cell * n, height: cell * n)
        func centre(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: lawn.minX + (CGFloat(x) + 0.5) * cell, y: lawn.minY + (CGFloat(y) + 0.5) * cell) }

        hedge(g, size)
        stones(g, lawn, wall: wall, cell: cell)
        grass(g, lawn, cell: cell)

        // The apple, bobbing over its shadow; the one just eaten shrinks into the snake's mouth in a burst of juice.
        let bob = 0.5 + 0.5 * sin(now * 3.4)
        apple(g, at: centre(Double(food.x), Double(food.y)), cell: cell, scale: 1, lift: cell * CGFloat(0.02 + 0.06 * bob), shadow: true)
        if let eaten, t < 1 {
            let spot = centre(Double(eaten.x), Double(eaten.y)), e = CGFloat(1 - pow(1 - t, 2))
            apple(g, at: spot, cell: cell, scale: CGFloat(1 - t), lift: 0, shadow: false)
            var juice = Path()
            for k in 0..<9 {
                let angle = Double(k) * 0.7 + Double(JevDraw.hash(k, eaten.x * 14 + eaten.y) % 60) / 100
                let reach = cell * (0.3 + 0.45 * e), r = cell * 0.06 * CGFloat(1 - t)
                juice.addEllipse(in: CGRect(x: spot.x + CGFloat(cos(angle)) * reach - r, y: spot.y + CGFloat(sin(angle)) * reach - r, width: 2 * r, height: 2 * r))
            }
            g.fill(juice, with: .color(Color(red: 1, green: 0.4, blue: 0.35).opacity(0.9)))
        }

        if let head = after.first, !before.isEmpty {
            snake(g, head: head, cell: cell, centre: centre)
        }
        if let crash { JevDraw.blast(g, at: centre(Double(crash.x), Double(crash.y)), size: cell * 0.6, age: since) }
        hud(g, size, lawn: lawn, wall: wall, cell: cell)
        if over { JevDraw.curtain(g, size, title: crash != nil ? "撞上了！" : "吃满了！", detail: "吃了 \(score) 个 · 长度 \(after.count)") }
    }

    // MARK: The garden

    /// A dark hedge all round, and a few flowers in it.
    private func hedge(_ g: GraphicsContext, _ size: CGSize) {
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.14, green: 0.32, blue: 0.13), Color(red: 0.09, green: 0.22, blue: 0.09)]),
                                                                              startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let tones = [Color(red: 0.1, green: 0.25, blue: 0.1), Color(red: 0.2, green: 0.42, blue: 0.16), Color(red: 0.3, green: 0.52, blue: 0.2)]
        for tone in 0..<3 {
            var leaves = Path()
            for leaf in SnakeGarden.leaves where leaf.tone == tone {
                let r = CGFloat(leaf.r) * size.width
                leaves.addPath(Path(ellipseIn: CGRect(x: -r, y: -r * 0.55, width: 2 * r, height: 1.1 * r)),
                               transform: CGAffineTransform(translationX: CGFloat(leaf.x) * size.width, y: CGFloat(leaf.y) * size.height).rotated(by: CGFloat(leaf.turn)))
            }
            g.fill(leaves, with: .color(tones[tone]))
        }
        let petals = [Color(red: 1, green: 1, blue: 0.97), Color(red: 1, green: 0.72, blue: 0.82), Color(red: 1, green: 0.88, blue: 0.4)]
        var hearts = Path()
        for hue in 0..<3 {
            var flower = Path()
            for f in SnakeGarden.flowers where f.hue == hue {
                let r = CGFloat(f.r) * size.width, at = CGPoint(x: CGFloat(f.x) * size.width, y: CGFloat(f.y) * size.height)
                for k in 0..<5 {
                    flower.addPath(Path(ellipseIn: CGRect(x: r * 0.15, y: -r * 0.32, width: r * 0.95, height: r * 0.64)),
                                   transform: CGAffineTransform(translationX: at.x, y: at.y).rotated(by: CGFloat(k) * 1.2566 + CGFloat(f.x * 9)))
                }
                hearts.addEllipse(in: CGRect(x: at.x - r * 0.3, y: at.y - r * 0.3, width: r * 0.6, height: r * 0.6))
            }
            g.fill(flower, with: .color(petals[hue]))
        }
        g.fill(hearts, with: .color(Color(red: 0.98, green: 0.7, blue: 0.15)))
    }

    /// A low wall of cobbles round the lawn, lit from the top left, throwing a shadow on the hedge.
    private func stones(_ g: GraphicsContext, _ lawn: CGRect, wall: CGFloat, cell: CGFloat) {
        let outer = lawn.insetBy(dx: -wall, dy: -wall)
        g.fill(Path(roundedRect: outer.offsetBy(dx: wall * 0.2, dy: wall * 0.35), cornerRadius: wall * 0.6), with: .color(.black.opacity(0.3)))
        g.fill(Path(roundedRect: outer, cornerRadius: wall * 0.5), with: .color(Color(red: 0.3, green: 0.28, blue: 0.24)))
        let tones = [Color(red: 0.66, green: 0.64, blue: 0.59), Color(red: 0.59, green: 0.57, blue: 0.53), Color(red: 0.72, green: 0.69, blue: 0.63)]
        var bodies = Array(repeating: Path(), count: 3), lips = Path(), lights = Path()
        for side in 0..<4 {
            // top and bottom run the whole width; the sides fit between them
            let run: (CGFloat, CGFloat) = side % 2 == 0 ? (outer.minX, outer.maxX) : (lawn.minY, lawn.maxY)
            var start = run.0
            for (index, end) in SnakeGarden.stones[side].enumerated() {
                let stop = run.0 + (run.1 - run.0) * CGFloat(end)
                let rect: CGRect
                switch side {
                case 0: rect = CGRect(x: start, y: outer.minY, width: stop - start, height: wall)
                case 2: rect = CGRect(x: start, y: lawn.maxY, width: stop - start, height: wall)
                case 1: rect = CGRect(x: lawn.maxX, y: start, width: wall, height: stop - start)
                default: rect = CGRect(x: outer.minX, y: start, width: wall, height: stop - start)
                }
                start = stop
                let stone = rect.insetBy(dx: wall * 0.06, dy: wall * 0.06), round = min(stone.width, stone.height) * 0.42
                bodies[JevDraw.hash(side, index) % 3].addRoundedRect(in: stone, cornerSize: CGSize(width: round, height: round))
                lips.addRoundedRect(in: CGRect(x: stone.minX + stone.width * 0.12, y: stone.maxY - stone.height * 0.3, width: stone.width * 0.88, height: stone.height * 0.3),
                                    cornerSize: CGSize(width: round * 0.7, height: round * 0.7))
                lights.addRoundedRect(in: CGRect(x: stone.minX + stone.width * 0.12, y: stone.minY + stone.height * 0.12, width: stone.width * 0.55, height: stone.height * 0.22),
                                      cornerSize: CGSize(width: round * 0.4, height: round * 0.4))
            }
        }
        for tone in 0..<3 { g.fill(bodies[tone], with: .color(tones[tone])) }
        g.fill(lips, with: .color(.black.opacity(0.16)))
        g.fill(lights, with: .color(.white.opacity(0.28)))
    }

    /// The lawn: mown in stripes, a little uneven, with blades and tufts, and the wall's shade along its top and left.
    private func grass(_ g: GraphicsContext, _ lawn: CGRect, cell: CGFloat) {
        g.fill(Path(lawn), with: .color(Color(red: 0.55, green: 0.78, blue: 0.3)))
        var stripes = Path(), columns = Path()
        for k in stride(from: 1, to: JevSnake.side, by: 2) {
            stripes.addRect(CGRect(x: lawn.minX, y: lawn.minY + CGFloat(k) * cell, width: lawn.width, height: cell))
            columns.addRect(CGRect(x: lawn.minX + CGFloat(k) * cell, y: lawn.minY, width: cell, height: lawn.height))
        }
        g.fill(stripes, with: .color(Color(red: 0.36, green: 0.62, blue: 0.16).opacity(0.28)))
        g.fill(columns, with: .color(Color(red: 1, green: 1, blue: 0.8).opacity(0.035)))
        var dark = Path(), light = Path()
        func blade(_ path: inout Path, _ x: CGFloat, _ y: CGFloat, _ lean: Double, _ length: CGFloat, _ width: CGFloat) {
            let tip = CGPoint(x: x + CGFloat(sin(lean)) * length, y: y - CGFloat(cos(lean)) * length)
            path.move(to: CGPoint(x: x - width, y: y)); path.addLine(to: tip); path.addLine(to: CGPoint(x: x + width, y: y)); path.closeSubpath()
        }
        for b in SnakeGarden.blades {
            let x = lawn.minX + CGFloat(b.x) * lawn.width, y = lawn.minY + CGFloat(b.y) * lawn.height
            if b.light { blade(&light, x, y, b.lean, cell * CGFloat(b.length), cell * 0.022) } else { blade(&dark, x, y, b.lean, cell * CGFloat(b.length), cell * 0.022) }
        }
        for tuft in SnakeGarden.tufts {
            let x = lawn.minX + CGFloat(tuft.x) * lawn.width, y = lawn.minY + CGFloat(tuft.y) * lawn.height
            for k in -2...2 { blade(&dark, x + CGFloat(k) * cell * 0.03, y, Double(k) * 0.28, cell * CGFloat(tuft.size * (0.3 - 0.03 * Double(abs(k)))), cell * 0.03) }
        }
        g.fill(dark, with: .color(Color(red: 0.2, green: 0.45, blue: 0.1).opacity(0.5)))
        g.fill(light, with: .color(Color(red: 0.85, green: 0.95, blue: 0.55).opacity(0.45)))
        let shade = cell * 0.4
        g.fill(Path(CGRect(x: lawn.minX, y: lawn.minY, width: lawn.width, height: shade)),
               with: .linearGradient(Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: CGPoint(x: 0, y: lawn.minY), endPoint: CGPoint(x: 0, y: lawn.minY + shade)))
        g.fill(Path(CGRect(x: lawn.minX, y: lawn.minY, width: shade * 0.8, height: lawn.height)),
               with: .linearGradient(Gradient(colors: [.black.opacity(0.22), .clear]), startPoint: CGPoint(x: lawn.minX, y: 0), endPoint: CGPoint(x: lawn.minX + shade * 0.8, y: 0)))
    }

    /// A red apple with a shine, a stem and a leaf, and its soft shadow on the grass.
    private func apple(_ g: GraphicsContext, at p: CGPoint, cell: CGFloat, scale k: CGFloat, lift: CGFloat, shadow: Bool) {
        guard k > 0.02 else { return }
        let r = cell * 0.35 * k
        if shadow {
            let spread = 1 - lift / cell
            let s = CGRect(x: p.x - r * 1.05 * spread + cell * 0.07, y: p.y + r * 0.72, width: r * 2.1 * spread, height: r * 0.7 * spread)
            g.fill(Path(ellipseIn: s), with: .radialGradient(Gradient(colors: [.black.opacity(0.34), .black.opacity(0)]), center: CGPoint(x: s.midX, y: s.midY),
                                                             startRadius: 0, endRadius: s.width * 0.5))
        }
        let c = CGPoint(x: p.x, y: p.y - lift + r * 0.08)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * r, y: c.y + y * r) }
        var body = Path()
        body.move(to: at(0, -0.62))
        body.addCurve(to: at(0.98, -0.3), control1: at(0.3, -0.98), control2: at(0.9, -0.88))
        body.addCurve(to: at(0.42, 0.92), control1: at(1.08, 0.3), control2: at(0.8, 0.86))
        body.addCurve(to: at(-0.42, 0.92), control1: at(0.2, 1.02), control2: at(-0.2, 1.02))
        body.addCurve(to: at(-0.98, -0.3), control1: at(-0.8, 0.86), control2: at(-1.08, 0.3))
        body.addCurve(to: at(0, -0.62), control1: at(-0.9, -0.88), control2: at(-0.3, -0.98))
        body.closeSubpath()
        g.fill(body, with: .radialGradient(Gradient(stops: [.init(color: Color(red: 1, green: 0.5, blue: 0.42), location: 0), .init(color: Color(red: 0.88, green: 0.1, blue: 0.1), location: 0.45),
                                                            .init(color: Color(red: 0.55, green: 0.02, blue: 0.06), location: 1)]),
                                           center: at(-0.38, -0.38), startRadius: 0, endRadius: r * 1.6))
        var stem = Path()
        stem.move(to: at(0, -0.5)); stem.addQuadCurve(to: at(0.14, -1.08), control: at(-0.02, -0.86))
        g.stroke(stem, with: .color(Color(red: 0.4, green: 0.24, blue: 0.1)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
        var leaf = Path()
        leaf.move(to: at(0.06, -0.86))
        leaf.addQuadCurve(to: at(0.86, -1.08), control: at(0.36, -1.32))
        leaf.addQuadCurve(to: at(0.06, -0.86), control: at(0.56, -0.72))
        g.fill(leaf, with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.8, blue: 0.3), Color(red: 0.16, green: 0.5, blue: 0.14)]), startPoint: at(0.4, -1.2), endPoint: at(0.5, -0.8)))
        var vein = Path()
        vein.move(to: at(0.1, -0.87)); vein.addQuadCurve(to: at(0.74, -1.04), control: at(0.42, -1.04))
        g.stroke(vein, with: .color(Color(red: 0.75, green: 0.95, blue: 0.55).opacity(0.7)), lineWidth: max(0.5, r * 0.05))
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.5, width: r * 0.3, height: r * 0.46)), with: .color(.white.opacity(0.72)))
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.24, y: c.y - r * 0.56, width: r * 0.14, height: r * 0.14)), with: .color(.white.opacity(0.55)))
    }

    // MARK: The snake

    /// The body is a tube of overlapping discs along its centre line — lit from the top left, tapering to the
    /// tail, blue from a bright head to a deep tail, with scales — and then the head, with eyes and a tongue.
    private func snake(_ g: GraphicsContext, head: (x: Int, y: Int), cell: CGFloat, centre: (Double, Double) -> CGPoint) {
        // The centre line, head first: where the head is now, the squares the body fills, where the tail is now.
        // Before the first move nothing has moved, and the whole body is where it is.
        let e = JevDraw.smooth(t)
        let moved = !(before[0].x == head.x && before[0].y == head.y) && crash == nil
        var line: [CGPoint] = []
        if !moved {
            line = (crash != nil ? before : after).map { centre(Double($0.x), Double($0.y)) }
        } else {
            line.append(centre(JevDraw.mix(Double(before[0].x), Double(head.x), e), JevDraw.mix(Double(before[0].y), Double(head.y), e)))
            let grew = after.count > before.count
            line += (grew ? before : Array(before.dropLast())).map { centre(Double($0.x), Double($0.y)) }
            if !grew, before.count >= 2 {
                let tail = before[before.count - 1], next = before[before.count - 2]
                line.append(centre(JevDraw.mix(Double(tail.x), Double(next.x), e), JevDraw.mix(Double(tail.y), Double(next.y), e)))
            }
        }
        var points: [CGPoint] = []
        for p in line where points.last.map({ hypot($0.x - p.x, $0.y - p.y) > 0.5 }) ?? true { points.append(p) }
        if points.count < 2 { points.append(CGPoint(x: points[0].x - cell * 0.5, y: points[0].y)) }
        var reach: [CGFloat] = [0]
        for i in 1..<points.count { reach.append(reach[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)) }
        let total = max(reach[reach.count - 1], 1), taper = min(cell * 2.4, total * 0.5)
        func radius(_ s: CGFloat) -> CGFloat {
            let left = total - s
            return cell * 0.37 * (left >= taper ? 1 : 0.3 + 0.7 * pow(max(left, 0) / taper, 0.85))
        }
        /// Points along the line from the head, `s` apart or wherever `step` says, with the way the line runs there.
        func walk(from start: CGFloat, step: (CGFloat) -> CGFloat) -> [(p: CGPoint, s: CGFloat, along: CGVector)] {
            var out: [(p: CGPoint, s: CGFloat, along: CGVector)] = [], s = start, k = 0
            while s <= total {
                while k < points.count - 2 && reach[k + 1] < s { k += 1 }
                let a = points[k], b = points[k + 1], length = max(reach[k + 1] - reach[k], 0.001)
                let u = min(max((s - reach[k]) / length, 0), 1)
                out.append((CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u), s, CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)))
                s += step(s)
            }
            return out
        }
        // Discs close enough together to make a smooth tube, closer still where it narrows to the tail.
        var samples = walk(from: 0) { max(cell * 0.04, min(cell * 0.18, radius($0) * 0.45)) }
        if let last = samples.last, last.s < total, let end = walk(from: total, step: { _ in cell }).first { samples.append(end) }
        func discs(_ scale: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0, from: Int = 0, to: Int? = nil) -> Path {
            var path = Path()
            for sample in samples[from..<(to ?? samples.count)] {
                let r = radius(sample.s) * scale
                path.addEllipse(in: CGRect(x: sample.p.x + dx * r - r, y: sample.p.y + dy * r - r, width: 2 * r, height: 2 * r))
            }
            return path
        }
        let spine = Path { p in p.addLines(points) }

        // Where the head is, and which way it faces: turning toward where it is going.
        let face = points[0]
        func way(_ a: (x: Int, y: Int), _ b: (x: Int, y: Int)) -> Double? { a.x == b.x && a.y == b.y ? nil : atan2(Double(b.y - a.y), Double(b.x - a.x)) }
        let going = (crash.flatMap { way(before[0], $0) } ?? way(before[0], head)) ?? (after.count > 1 ? way(after[1], after[0]) : nil) ?? 0
        let was = moved && before.count > 1 ? way(before[1], before[0]) ?? going : going
        var turn = going - was
        if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
        let angle = CGFloat(was + turn * (crash != nil ? 1 : JevDraw.smooth(t / 0.6)))
        let ahead = CGVector(dx: cos(angle), dy: sin(angle)), side = CGVector(dx: -sin(angle), dy: cos(angle))
        func local(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: face.x + (ahead.dx * x + side.dx * y) * cell, y: face.y + (ahead.dy * x + side.dy * y) * cell) }
        var skull = Path()
        skull.move(to: CGPoint(x: 0.56, y: 0))
        skull.addCurve(to: CGPoint(x: 0.02, y: 0.44), control1: CGPoint(x: 0.56, y: 0.29), control2: CGPoint(x: 0.3, y: 0.44))
        skull.addCurve(to: CGPoint(x: -0.42, y: 0), control1: CGPoint(x: -0.26, y: 0.44), control2: CGPoint(x: -0.42, y: 0.25))
        skull.addCurve(to: CGPoint(x: 0.02, y: -0.44), control1: CGPoint(x: -0.42, y: -0.25), control2: CGPoint(x: -0.26, y: -0.44))
        skull.addCurve(to: CGPoint(x: 0.56, y: 0), control1: CGPoint(x: 0.3, y: -0.44), control2: CGPoint(x: 0.56, y: -0.29))
        skull.closeSubpath()
        let place = CGAffineTransform(translationX: face.x, y: face.y).rotated(by: angle)
        let shape = skull.applying(place.scaledBy(x: cell, y: cell)), outline = skull.applying(place.scaledBy(x: cell * 1.09, y: cell * 1.09))

        // Its soft shadow on the grass; a dark rim round body and head together, so they are one creature; the body
        // in bands from a bright head to a deep tail; markings and a net of scales on the skin; a gloss along its back.
        var shadow = discs(1.12, dx: 0.3, dy: 0.44)
        shadow.addPath(outline.offsetBy(dx: cell * 0.11, dy: cell * 0.16))
        g.fill(shadow, with: .color(.black.opacity(0.1)))
        g.fill(discs(1, dx: 0.24, dy: 0.34), with: .color(.black.opacity(0.14)))
        var rim = discs(1)
        rim.addPath(outline)
        g.fill(rim, with: .color(JevDraw.shade(Self.rim, 1)))
        let bands = 16
        var skin = Path()
        for band in stride(from: bands - 1, through: 0, by: -1) {
            let from = samples.count * band / bands, to = min(samples.count, samples.count * (band + 1) / bands + 1)
            guard from < to else { continue }
            let part = discs(0.86, dx: -0.06, dy: -0.08, from: from, to: to)
            skin.addPath(part)
            g.fill(part, with: .color(JevDraw.shade(Self.mix(Self.head, Self.tail, Double(band) / Double(bands - 1)), 1)))
        }
        var clipped = g
        clipped.clip(to: skin)
        var saddles = Path(), net = Path()
        for mark in walk(from: cell * 0.8, step: { _ in cell * 0.95 }) where total - mark.s > cell * 0.4 {
            let r = radius(mark.s) * 1.3
            saddles.move(to: CGPoint(x: mark.p.x + mark.along.dy * r, y: mark.p.y - mark.along.dx * r))
            saddles.addLine(to: CGPoint(x: mark.p.x - mark.along.dy * r, y: mark.p.y + mark.along.dx * r))
        }
        for knot in walk(from: cell * 0.1, step: { _ in cell * 0.19 }) {
            let r = radius(knot.s) * 1.3
            for turn in [0.87, -0.87] as [CGFloat] {
                let c = cos(turn), s = sin(turn)
                let dir = CGVector(dx: knot.along.dx * c - knot.along.dy * s, dy: knot.along.dx * s + knot.along.dy * c)
                net.move(to: CGPoint(x: knot.p.x - dir.dx * r, y: knot.p.y - dir.dy * r))
                net.addLine(to: CGPoint(x: knot.p.x + dir.dx * r, y: knot.p.y + dir.dy * r))
            }
        }
        clipped.stroke(saddles, with: .color(JevDraw.shade(Self.rim, 1).opacity(0.24)), style: StrokeStyle(lineWidth: cell * 0.2, lineCap: .round))
        clipped.stroke(net, with: .color(JevDraw.shade(Self.rim, 1).opacity(0.2)), lineWidth: max(0.6, cell * 0.022))
        let round = StrokeStyle(lineWidth: cell * 0.26, lineCap: .round, lineJoin: .round)
        clipped.stroke(spine.offsetBy(dx: -cell * 0.1, dy: -cell * 0.12), with: .color(Color(red: 0.62, green: 0.84, blue: 1).opacity(0.34)), style: round)
        clipped.stroke(spine.offsetBy(dx: -cell * 0.14, dy: -cell * 0.17), with: .color(.white.opacity(0.22)),
                       style: StrokeStyle(lineWidth: cell * 0.09, lineCap: .round, lineJoin: .round))

        // The head, with eyes that look where it is going and a tongue that flicks.
        if crash == nil, !over {
            let cycle = (now * 0.6).truncatingRemainder(dividingBy: 1)
            if cycle < 0.26 {
                // Out, forked at the end, flickering from side to side.
                let out = CGFloat(sin(cycle / 0.26 * .pi)), wag = 0.05 * sin(now * 40) * out
                let fork = local(0.46 + 0.26 * out, wag)
                var tongue = Path()
                tongue.move(to: local(0.44, 0)); tongue.addLine(to: fork)
                tongue.move(to: local(0.46 + 0.4 * out, wag + 0.075 * out)); tongue.addLine(to: fork); tongue.addLine(to: local(0.46 + 0.4 * out, wag - 0.075 * out))
                g.stroke(tongue, with: .color(Color(red: 0.9, green: 0.1, blue: 0.22)), style: StrokeStyle(lineWidth: cell * 0.05, lineCap: .round, lineJoin: .round))
            }
        }
        g.fill(shape, with: .radialGradient(Gradient(stops: [.init(color: JevDraw.shade(Self.head, 1.4), location: 0), .init(color: JevDraw.shade(Self.head, 1), location: 0.5),
                                                             .init(color: JevDraw.shade(Self.head, 0.7), location: 1)]),
                                            center: CGPoint(x: face.x - cell * 0.16, y: face.y - cell * 0.2), startRadius: 0, endRadius: cell * 0.7))
        g.fill(Path(ellipseIn: CGRect(x: face.x - cell * 0.3, y: face.y - cell * 0.33, width: cell * 0.26, height: cell * 0.16)), with: .color(.white.opacity(0.3)))
        var nostrils = Path()
        for y in [-0.08, 0.08] as [CGFloat] { let q = local(0.46, y); nostrils.addEllipse(in: CGRect(x: q.x - cell * 0.022, y: q.y - cell * 0.022, width: cell * 0.044, height: cell * 0.044)) }
        g.fill(nostrils, with: .color(JevDraw.shade(Self.rim, 1).opacity(0.8)))
        for y in [-0.2, 0.2] as [CGFloat] {
            let eye = local(0.1, y), r = cell * 0.14
            g.fill(Path(ellipseIn: CGRect(x: eye.x - r * 1.16, y: eye.y - r * 1.16, width: r * 2.32, height: r * 2.32)), with: .color(JevDraw.shade(Self.rim, 1).opacity(0.9)))
            g.fill(Path(ellipseIn: CGRect(x: eye.x - r, y: eye.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
            if crash != nil {
                var cross = Path()
                cross.move(to: CGPoint(x: eye.x - r * 0.55, y: eye.y - r * 0.55)); cross.addLine(to: CGPoint(x: eye.x + r * 0.55, y: eye.y + r * 0.55))
                cross.move(to: CGPoint(x: eye.x + r * 0.55, y: eye.y - r * 0.55)); cross.addLine(to: CGPoint(x: eye.x - r * 0.55, y: eye.y + r * 0.55))
                g.stroke(cross, with: .color(.black), style: StrokeStyle(lineWidth: r * 0.32, lineCap: .round))
            } else {
                let pupil = CGPoint(x: eye.x + ahead.dx * r * 0.36, y: eye.y + ahead.dy * r * 0.36), s = r * 0.56
                g.fill(Path(ellipseIn: CGRect(x: pupil.x - s, y: pupil.y - s, width: 2 * s, height: 2 * s)), with: .color(Color(red: 0.05, green: 0.06, blue: 0.12)))
                g.fill(Path(ellipseIn: CGRect(x: pupil.x - s * 0.62, y: pupil.y - s * 0.7, width: s * 0.6, height: s * 0.6)), with: .color(.white))
            }
        }
    }

    // MARK: The numbers

    /// A little snake for the length: an S of body with a head and an eye.
    private func icon(_ g: GraphicsContext, in r: CGRect) {
        var body = Path()
        body.move(to: CGPoint(x: r.minX + r.width * 0.06, y: r.maxY - r.height * 0.18))
        body.addCurve(to: CGPoint(x: r.maxX - r.width * 0.3, y: r.minY + r.height * 0.45),
                      control1: CGPoint(x: r.minX + r.width * 0.45, y: r.maxY + r.height * 0.25), control2: CGPoint(x: r.minX + r.width * 0.35, y: r.minY - r.height * 0.2))
        let width = r.height * 0.36
        g.stroke(body.offsetBy(dx: width * 0.2, dy: width * 0.3), with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        g.stroke(body, with: .color(JevDraw.shade(Self.rim, 1)), style: StrokeStyle(lineWidth: width * 1.25, lineCap: .round))
        g.stroke(body, with: .color(JevDraw.shade(Self.head, 1)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        let head = CGPoint(x: r.maxX - r.width * 0.2, y: r.minY + r.height * 0.42), hr = r.height * 0.3
        g.fill(Path(ellipseIn: CGRect(x: head.x - hr * 1.12, y: head.y - hr * 1.02, width: hr * 2.24, height: hr * 2.04)), with: .color(JevDraw.shade(Self.rim, 1)))
        g.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr * 0.9, width: hr * 2, height: hr * 1.8)),
               with: .radialGradient(Gradient(colors: [JevDraw.shade(Self.head, 1.4), JevDraw.shade(Self.head, 0.85)]), center: CGPoint(x: head.x - hr * 0.4, y: head.y - hr * 0.4),
                                     startRadius: 0, endRadius: hr * 1.6))
        let eye = CGPoint(x: head.x + hr * 0.2, y: head.y - hr * 0.15), er = hr * 0.38
        g.fill(Path(ellipseIn: CGRect(x: eye.x - er, y: eye.y - er, width: 2 * er, height: 2 * er)), with: .color(.white))
        g.fill(Path(ellipseIn: CGRect(x: eye.x - er * 0.2, y: eye.y - er * 0.55, width: er * 1.1, height: er * 1.1)), with: .color(Color(red: 0.05, green: 0.06, blue: 0.12)))
    }

    /// The apples eaten and the length, on glass over the hedge.
    private func hud(_ g: GraphicsContext, _ size: CGSize, lawn: CGRect, wall: CGFloat, cell: CGFloat) {
        let band = lawn.minY - wall, h = band * 0.64, w = size.width * 0.27
        for (index, x) in [lawn.minX - wall, lawn.maxX + wall - w].enumerated() {
            let pill = CGRect(x: x, y: (band - h) / 2, width: w, height: h)
            g.fill(Path(roundedRect: pill.offsetBy(dx: h * 0.04, dy: h * 0.1), cornerRadius: h / 2), with: .color(.black.opacity(0.28)))
            let shape = Path(roundedRect: pill, cornerRadius: h / 2)
            g.fill(shape, with: .color(Color(red: 0.03, green: 0.12, blue: 0.04).opacity(0.45)))
            g.fill(shape, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0.24), location: 0), .init(color: .white.opacity(0.04), location: 0.55)]),
                                                startPoint: CGPoint(x: 0, y: pill.minY), endPoint: CGPoint(x: 0, y: pill.maxY)))
            g.stroke(Path(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), cornerRadius: h / 2),
                     with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0.1)]), startPoint: CGPoint(x: 0, y: pill.minY), endPoint: CGPoint(x: 0, y: pill.maxY)), lineWidth: 1)
            if index == 0 {
                apple(g, at: CGPoint(x: pill.minX + h * 0.62, y: pill.midY + h * 0.04), cell: h * 1.05, scale: 1, lift: 0, shadow: false)
                JevDraw.text(g, "\(score)", at: CGPoint(x: pill.minX + h * 1.2, y: pill.midY), size: h * 0.56, anchor: .leading)
            } else {
                icon(g, in: CGRect(x: pill.minX + h * 0.28, y: pill.minY + h * 0.2, width: h * 0.95, height: h * 0.6))
                JevDraw.text(g, "长度 \(after.count)", at: CGPoint(x: pill.minX + h * 1.35, y: pill.midY), size: h * 0.46, weight: .bold, anchor: .leading)
            }
        }
    }
}
