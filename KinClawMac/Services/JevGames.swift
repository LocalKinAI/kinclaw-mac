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
    let controls = "←→ 移动 · ↑ 旋转 · ↓ 或空格 落下（半透明的是会落到的地方）"

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        board = Array(repeating: Array(repeating: 0, count: Self.width), count: Self.height)
        dice = JevDice(seed: seed); bag = []; pieces = 0; lines = 0; over = false
        current = draw(); next = draw()
        aim()
        drop = nil; ticked = .distantPast
    }

    func prepare(person: Bool) { self.person = person }

    /// A new piece starts unrotated, in the middle.
    private func aim() { cursor = (0, (Self.width - Self.pieces[current][0].w) / 2) }

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
                var placed = board
                for cell in shape.cells { placed[y + cell.y][x + cell.x] = UInt8(current + 1) }
                let kept = placed.filter { $0.contains(0) }
                let cleared = Self.height - kept.count
                let after = Array(repeating: Array(repeating: UInt8(0), count: Self.width), count: cleared) + kept
                var feat = Self.measure(after)
                feat.lines = cleared; feat.newHoles = feat.holes - before.holes; feat.landing = Self.height - y
                moves.append(Placement(after: after, feat: feat)); slots.append((rot, x, y))
            }
        }
        if moves.isEmpty { over = true; return [] }
        return ballot(moves, words: { Self.describe($0.feat) }, merit: { Self.value($0.feat) }) { a, b in
            (a.feat.landing, a.feat.bumpiness, a.feat.aggHeight) < (b.feat.landing, b.feat.bumpiness, b.feat.aggHeight)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        let slot = slots[option.move]
        let cells = Self.pieces[current][slot.rot].cells.map { (x: slot.x + $0.x, y: slot.y + $0.y) }
        var placed = board
        for cell in cells { placed[cell.y][cell.x] = UInt8(current + 1) }
        drop = TetrisDrop(kind: current, cells: cells, before: board, placed: placed,
                          cleared: placed.indices.filter { !placed[$0].contains(0) })
        board = moves[option.move].after
        lines += moves[option.move].feat.lines
        pieces += 1
        current = next; next = draw()
        aim()
        ticked = Date()
    }

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let turns = Self.pieces[current]
        for key in pressed {
            switch key {
            case .left, .right:
                cursor.x = min(max(cursor.x + (key == .left ? -1 : 1), 0), Self.width - turns[cursor.rot].w)
            case .up:
                cursor.rot = (cursor.rot + 1) % turns.count
                cursor.x = min(cursor.x, Self.width - turns[cursor.rot].w)
            case .down, .space:
                // The placement under the cursor, as an option of its own: several
                // placements may read the same, and a person means this one.
                guard let index = slots.firstIndex(where: { $0.rot == cursor.rot && $0.x == cursor.x }) else { return .nothing }
                let words = Self.describe(moves[index].feat)
                guard let listed = options.first(where: { $0.label == words }) else { return .nothing }
                return .choose(JevOption(id: listed.id, label: words, merit: Self.value(moves[index].feat), move: index))
            default: break
            }
        }
        return .redraw
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
}

fileprivate let tetrisTints: [(Double, Double, Double)] = [
    (0.10, 0.80, 0.90), (0.96, 0.80, 0.12), (0.66, 0.28, 0.88), (0.30, 0.80, 0.32), (0.92, 0.22, 0.22), (0.22, 0.38, 0.95), (0.98, 0.56, 0.12),
]

/// A block with a bevel: lit from the top left.
fileprivate func tetrisBlock(_ g: GraphicsContext, _ r: CGRect, _ tint: (Double, Double, Double), alpha: Double = 1) {
    let outer = r.insetBy(dx: 0.6, dy: 0.6)
    g.fill(Path(roundedRect: outer, cornerRadius: r.width * 0.14),
           with: .linearGradient(Gradient(colors: [JevDraw.shade(tint, 1.45).opacity(alpha), JevDraw.shade(tint, 0.55).opacity(alpha)]),
                                 startPoint: outer.origin, endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
    let face = outer.insetBy(dx: r.width * 0.15, dy: r.width * 0.15)
    g.fill(Path(roundedRect: face, cornerRadius: r.width * 0.08), with: .color(JevDraw.shade(tint, 1).opacity(alpha)))
    g.fill(Path(roundedRect: CGRect(x: face.minX, y: face.minY, width: face.width, height: face.height * 0.3), cornerRadius: r.width * 0.06),
           with: .color(Color.white.opacity(0.25 * alpha)))
}

extension JevTetris: JevPainted {
    var aspect: Double { 0.78 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        var ghost: [(x: Int, y: Int)] = []
        if person, !over {
            let shape = Self.pieces[current][min(cursor.rot, Self.pieces[current].count - 1)]
            var y = -shape.h
            while Self.fits(board, shape, cursor.x, y + 1) { y += 1 }
            if y >= 0 { ghost = shape.cells.map { (x: cursor.x + $0.x, y: y + $0.y) } }
        }
        let scene = TetrisScene(board: board, drop: drop, t: t, current: current, next: next,
                                preview: Self.pieces[next][0].cells.map { (x: $0.x, y: $0.y) }, ghost: ghost,
                                lines: lines, pieces: pieces, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

fileprivate struct TetrisScene {
    let board: [[UInt8]], drop: TetrisDrop?, t: Double, current: Int, next: Int
    let preview: [(x: Int, y: Int)], ghost: [(x: Int, y: Int)], lines: Int, pieces: Int, over: Bool

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let cell = min(size.height / 21, size.width / 15.6)
        let well = CGRect(x: cell * 0.6, y: (size.height - cell * 20) / 2, width: cell * 10, height: cell * 20)
        func square(_ x: Double, _ y: Double) -> CGRect { CGRect(x: well.minX + CGFloat(x) * cell, y: well.minY + CGFloat(y) * cell, width: cell, height: cell) }

        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.16), Color(red: 0.12, green: 0.08, blue: 0.24)]),
                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        g.fill(Path(roundedRect: well.insetBy(dx: -4, dy: -4), cornerRadius: 8), with: .color(Color(red: 0.35, green: 0.45, blue: 0.9).opacity(0.35)))
        g.fill(Path(well), with: .color(Color(red: 0.03, green: 0.04, blue: 0.10)))
        for x in 1..<10 { g.fill(Path(CGRect(x: well.minX + CGFloat(x) * cell, y: well.minY, width: 0.6, height: well.height)), with: .color(.white.opacity(0.05))) }
        for y in 1..<20 { g.fill(Path(CGRect(x: well.minX, y: well.minY + CGFloat(y) * cell, width: well.width, height: 0.6)), with: .color(.white.opacity(0.05))) }

        // A move in three beats: the piece falls onto the board it was dropped on,
        // the rows it filled flash, and then they are gone.
        let falling = drop != nil && t < 0.55, flashing = (drop.map { !$0.cleared.isEmpty } ?? false) && t >= 0.55 && t < 1
        let shown = falling ? drop!.before : flashing ? drop!.placed : board
        for y in 0..<shown.count { for x in 0..<shown[y].count where shown[y][x] != 0 { tetrisBlock(g, square(Double(x), Double(y)), tetrisTints[Int(shown[y][x]) - 1]) } }
        if falling, let drop {
            var g = g
            g.clip(to: Path(well))
            let top = drop.cells.map(\.y).min() ?? 0, e = pow(t / 0.55, 2)
            for cell in drop.cells {
                tetrisBlock(g, square(Double(cell.x), Double(cell.y) - Double(top + 3) * (1 - e)), tetrisTints[drop.kind])
            }
        }
        if flashing, let drop {
            let glow = 0.85 * sin((t - 0.55) / 0.45 * .pi)
            for row in drop.cleared { g.fill(Path(CGRect(x: well.minX, y: well.minY + CGFloat(row) * cell, width: well.width, height: cell)), with: .color(.white.opacity(glow))) }
        }
        for cell in ghost {
            let r = square(Double(cell.x), Double(cell.y)).insetBy(dx: 1.5, dy: 1.5)
            g.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(JevDraw.shade(tetrisTints[current], 1).opacity(0.22)))
            g.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(JevDraw.shade(tetrisTints[current], 1.3).opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }

        // Beside the well: the next piece, and the count.
        let side = CGRect(x: well.maxX + cell * 0.7, y: well.minY, width: size.width - well.maxX - cell * 1.3, height: well.height)
        let box = CGRect(x: side.minX, y: side.minY + cell * 1.2, width: side.width, height: cell * 3.6)
        JevDraw.text(g, "下一块", at: CGPoint(x: side.midX, y: side.minY + cell * 0.5), size: cell * 0.62, weight: .bold, colour: .white.opacity(0.75), shadow: false)
        JevDraw.panel(g, box)
        let wide = CGFloat((preview.map(\.x).max() ?? 0) + 1), tall = CGFloat((preview.map(\.y).max() ?? 0) + 1), small = cell * 0.8
        for cell in preview {
            tetrisBlock(g, CGRect(x: box.midX - wide * small / 2 + CGFloat(cell.x) * small, y: box.midY - tall * small / 2 + CGFloat(cell.y) * small,
                                  width: small, height: small), tetrisTints[next])
        }
        for (index, (title, value)) in [("消行", "\(lines)"), ("方块", "\(pieces)")].enumerated() {
            let y = box.maxY + cell * (1.4 + 2.4 * CGFloat(index))
            JevDraw.text(g, title, at: CGPoint(x: side.midX, y: y), size: cell * 0.6, weight: .bold, colour: .white.opacity(0.7), shadow: false)
            JevDraw.text(g, value, at: CGPoint(x: side.midX, y: y + cell * 0.95), size: cell * 1.05)
        }
        if over { JevDraw.curtain(g, size, title: "堆满了！", detail: "消了 \(lines) 行 · 用了 \(pieces) 块") }
    }
}

extension Jev2048: JevPainted {
    var aspect: Double { 0.84 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = Scene2048(board: board, trails: trails, merged: merged, spawned: spawned, t: t, score: score,
                              best: board.flatMap { $0 }.max() ?? 0, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

fileprivate struct Scene2048 {
    let board: [[Int]], trails: [(from: (Int, Int), to: (Int, Int), value: Int)], merged: Set<Int>, spawned: Int?
    let t: Double, score: Int, best: Int, over: Bool

    static func colours(_ value: Int) -> (Color, Color) {
        let table: [Int: (Double, Double, Double)] = [
            2: (0.93, 0.89, 0.85), 4: (0.93, 0.88, 0.78), 8: (0.95, 0.69, 0.47), 16: (0.96, 0.58, 0.39), 32: (0.96, 0.49, 0.37),
            64: (0.96, 0.37, 0.23), 128: (0.93, 0.81, 0.45), 256: (0.93, 0.80, 0.38), 512: (0.93, 0.78, 0.31), 1024: (0.93, 0.77, 0.25),
            2048: (0.93, 0.76, 0.18),
        ]
        let rgb = table[value] ?? (0.24, 0.23, 0.20)
        return (Color(red: rgb.0, green: rgb.1, blue: rgb.2), value <= 4 ? Color(red: 0.47, green: 0.43, blue: 0.40) : .white)
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.98, green: 0.97, blue: 0.94)))
        let side = min(size.width, size.height * 0.84) - 24
        let frame = CGRect(x: (size.width - side) / 2, y: size.height - side - 12, width: side, height: side)
        let gap = side * 0.03, tile = (side - gap * 5) / 4
        func spot(_ r: Double, _ c: Double) -> CGRect { CGRect(x: frame.minX + gap + CGFloat(c) * (tile + gap), y: frame.minY + gap + CGFloat(r) * (tile + gap), width: tile, height: tile) }

        // The title and the score.
        JevDraw.text(g, "2048", at: CGPoint(x: frame.minX, y: (frame.minY) / 2), size: frame.minY * 0.62, colour: Color(red: 0.47, green: 0.43, blue: 0.40), anchor: .leading, shadow: false)
        for (index, (title, value)) in [("分数", "\(score)"), ("最大", "\(best)")].enumerated() {
            let box = CGRect(x: frame.maxX - CGFloat(2 - index) * side * 0.24 - CGFloat(1 - index) * 8, y: frame.minY * 0.18, width: side * 0.24, height: frame.minY * 0.64)
            g.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(Color(red: 0.73, green: 0.68, blue: 0.63)))
            JevDraw.text(g, title, at: CGPoint(x: box.midX, y: box.minY + box.height * 0.28), size: box.height * 0.24, weight: .bold, colour: Color(red: 0.93, green: 0.89, blue: 0.85), shadow: false)
            JevDraw.text(g, value, at: CGPoint(x: box.midX, y: box.minY + box.height * 0.68), size: box.height * 0.36, shadow: false)
        }

        g.fill(Path(roundedRect: frame, cornerRadius: 10), with: .color(Color(red: 0.73, green: 0.68, blue: 0.63)))
        for r in 0..<4 { for c in 0..<4 { g.fill(Path(roundedRect: spot(Double(r), Double(c)), cornerRadius: 6), with: .color(Color(red: 0.80, green: 0.76, blue: 0.71))) } }

        func draw(_ value: Int, in rect: CGRect) {
            let (ground, ink) = Scene2048.colours(value)
            g.fill(Path(roundedRect: rect, cornerRadius: rect.width * 0.08), with: .color(ground))
            if value >= 128 {
                g.stroke(Path(roundedRect: rect, cornerRadius: rect.width * 0.08), with: .color(Color.yellow.opacity(0.35)), lineWidth: 2)
            }
            let digits = CGFloat(String(value).count)
            JevDraw.text(g, "\(value)", at: CGPoint(x: rect.midX, y: rect.midY), size: rect.width * (digits <= 2 ? 0.45 : digits == 3 ? 0.38 : 0.3),
                         colour: ink, shadow: false)
        }
        // A move in two beats: the tiles slide, then what merged swells and what is new appears.
        if !trails.isEmpty, t < 0.7 {
            let e = 1 - pow(1 - t / 0.7, 3)
            for trail in trails {
                draw(trail.value, in: spot(JevDraw.mix(Double(trail.from.0), Double(trail.to.0), e), JevDraw.mix(Double(trail.from.1), Double(trail.to.1), e)))
            }
        } else {
            let beat = trails.isEmpty ? 1 : min(max((t - 0.7) / 0.3, 0), 1)
            for r in 0..<4 {
                for c in 0..<4 where board[r][c] != 0 {
                    var rect = spot(Double(r), Double(c))
                    if merged.contains(r * 4 + c) { let swell = CGFloat(sin(beat * .pi) * 0.12); rect = rect.insetBy(dx: -rect.width * swell / 2, dy: -rect.width * swell / 2) }
                    if spawned == r * 4 + c { let grow = CGFloat(0.3 + 0.7 * beat); rect = rect.insetBy(dx: rect.width * (1 - grow) / 2, dy: rect.width * (1 - grow) / 2) }
                    draw(board[r][c], in: rect)
                }
            }
        }
        if over { JevDraw.curtain(g, size, title: "填满了！", detail: "\(score) 分 · 最大 \(best)") }
    }
}

extension JevSnake: JevPainted {
    var aspect: Double { 0.9 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = SnakeScene(before: before, after: body, food: food, eaten: eaten, crash: crash, t: t, since: since, now: now,
                               score: score, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

fileprivate struct SnakeScene {
    let before: [(x: Int, y: Int)], after: [(x: Int, y: Int)], food: (x: Int, y: Int), eaten: (x: Int, y: Int)?, crash: (x: Int, y: Int)?
    let t: Double, since: Double, now: Double, score: Int, over: Bool

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let n = CGFloat(JevSnake.side), header = size.height * 0.1
        let cell = min(size.width / n, (size.height - header) / n)
        let board = CGRect(x: (size.width - cell * n) / 2, y: header, width: cell * n, height: cell * n)
        func centre(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: board.minX + (CGFloat(x) + 0.5) * cell, y: board.minY + (CGFloat(y) + 0.5) * cell) }

        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.29, green: 0.46, blue: 0.17)))
        for y in 0..<JevSnake.side {
            for x in 0..<JevSnake.side {
                g.fill(Path(CGRect(x: board.minX + CGFloat(x) * cell, y: board.minY + CGFloat(y) * cell, width: cell, height: cell)),
                       with: .color((x + y) % 2 == 0 ? Color(red: 0.67, green: 0.84, blue: 0.32) : Color(red: 0.64, green: 0.82, blue: 0.29)))
            }
        }
        JevDraw.text(g, "🍎 \(score)", at: CGPoint(x: board.minX + 6, y: header / 2), size: header * 0.42, anchor: .leading)
        JevDraw.text(g, "长度 \(after.count)", at: CGPoint(x: board.maxX - 6, y: header / 2), size: header * 0.36, weight: .bold, anchor: .trailing)

        // The apple, bobbing; the one just eaten shrinks away in the snake's mouth.
        func apple(_ p: CGPoint, _ scale: CGFloat) {
            let r = cell * 0.36 * scale
            g.fill(Path(ellipseIn: CGRect(x: p.x - r + 2, y: p.y - r + 3, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.18)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.82, green: 0.1, blue: 0.08)]),
                                         center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35), startRadius: 0, endRadius: r * 1.2))
            g.fill(Path(CGRect(x: p.x - 1, y: p.y - r * 1.35, width: 2, height: r * 0.5)), with: .color(Color(red: 0.4, green: 0.25, blue: 0.1)))
            g.fill(Path(ellipseIn: CGRect(x: p.x + 1, y: p.y - r * 1.4, width: r * 0.7, height: r * 0.4)), with: .color(Color(red: 0.2, green: 0.6, blue: 0.2)))
        }
        apple(centre(Double(food.x), Double(food.y) + 0.06 * sin(now * 4)), 1)
        if let eaten, t < 1 { apple(centre(Double(eaten.x), Double(eaten.y)), CGFloat(1 - t)) }

        // The body: a thick line through the squares it fills, the head and the tail sliding.
        guard let head = after.first, !before.isEmpty else { return }
        let e = JevDraw.smooth(t)
        var points: [CGPoint] = []
        if crash == nil {
            points.append(centre(JevDraw.mix(Double(before[0].x), Double(head.x), e), JevDraw.mix(Double(before[0].y), Double(head.y), e)))
        } else { points.append(centre(Double(before[0].x), Double(before[0].y))) }
        let grew = after.count > before.count
        let kept = crash != nil || grew ? before : Array(before.dropLast())
        points += kept.map { centre(Double($0.x), Double($0.y)) }
        if crash == nil, !grew, before.count >= 2 {
            let tail = before[before.count - 1], next = before[before.count - 2]
            points.append(centre(JevDraw.mix(Double(tail.x), Double(next.x), e), JevDraw.mix(Double(tail.y), Double(next.y), e)))
        }
        let path = Path { p in p.move(to: points[0]); for q in points.dropFirst() { p.addLine(to: q) } }
        g.stroke(path.offsetBy(dx: 2, dy: 3), with: .color(.black.opacity(0.2)), style: StrokeStyle(lineWidth: cell * 0.74, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(Color(red: 0.17, green: 0.35, blue: 0.85)), style: StrokeStyle(lineWidth: cell * 0.74, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(Color(red: 0.33, green: 0.55, blue: 1)), style: StrokeStyle(lineWidth: cell * 0.44, lineCap: .round, lineJoin: .round))
        // The head, and eyes that look where it is going.
        let face = points[0]
        let look = after.count > 1 ? (x: CGFloat(head.x - after[1].x), y: CGFloat(head.y - after[1].y)) : (x: 1, y: 0)
        g.fill(Path(ellipseIn: CGRect(x: face.x - cell * 0.42, y: face.y - cell * 0.42, width: cell * 0.84, height: cell * 0.84)), with: .color(Color(red: 0.2, green: 0.4, blue: 0.95)))
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: face.x + look.x * cell * 0.12 - look.y * CGFloat(side) * cell * 0.2, y: face.y + look.y * cell * 0.12 + look.x * CGFloat(side) * cell * 0.2)
            g.fill(Path(ellipseIn: CGRect(x: eye.x - cell * 0.13, y: eye.y - cell * 0.13, width: cell * 0.26, height: cell * 0.26)), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: eye.x + look.x * cell * 0.04 - cell * 0.06, y: eye.y + look.y * cell * 0.04 - cell * 0.06, width: cell * 0.12, height: cell * 0.12)), with: .color(.black))
        }
        if let crash { JevDraw.blast(g, at: centre(Double(crash.x), Double(crash.y)), size: cell * 0.6, age: since) }
        if over { JevDraw.curtain(g, size, title: crash != nil ? "撞上了！" : "吃满了！", detail: "吃了 \(score) 个 · 长度 \(after.count)") }
    }
}
