import SwiftUI

/// 消消乐 — match three, as Bejeweled and Candy Crush play it — for a player
/// that reads words.
///
/// Every legal swap is an option, and the program works out what each one does
/// before anybody chooses: how many gems it clears at once and of which colour,
/// the special gem it makes or sets off and how much that clears, the cascades
/// that follow from the gems already on the board — gravity with the known gems
/// only; the ones that drop in from the top are unknown, so what they might add
/// is not counted — where on the board it is, and the points it scores for
/// sure. Whether a striped gem made now is worth more than forty points today
/// is the judgment left to the model.
@MainActor
final class JevMatch3: JevGame {
    let id = "match3", title = "消消乐", symbol = "sparkles"
    let rules = "Match-3, like Bejeweled or Candy Crush, on an 8 by 8 board of gems in six colours. A move swaps two neighbouring gems, side by side or one above the other, and is allowed only if it lines up 3 or more gems of one colour in a row or a column. Lined-up gems are cleared and score points; the gems above fall down and new random gems drop in from the top. If fallen gems line up again they clear too: a cascade, and every cascade scores more per gem than the one before. Four in a line makes a striped gem, which clears its whole row or column when it is cleared itself. Five in an L or T shape makes a wrapped gem, which clears the 3 by 3 square around it. Five in a line makes a colour bomb: swapping it with any gem clears every gem of that colour. The game is 30 moves, and the goal is the highest score."
    let question = "Which swap is the best move for scoring the most points over the whole game?"
    let howToJudge = "Each option says what the swap does for sure: the gems it clears, any special gem it makes or sets off, the cascades that follow from gems already on the board (the new gems that drop in are unknown, so whatever they add is not counted), the points it scores for sure, and where on the board it is. A special gem is worth much more than the points it scores when it is made, because it clears a whole row, column or square when it goes off later: a colour bomb is worth the most, then a wrapped gem, then a striped gem. So making a special gem beats a plain match that scores a few more points, unless the game is about to end. Otherwise more points is better. Between swaps that are otherwise alike, prefer one near the bottom of the board: more gems fall after it, and the new ones may cascade."

    private var board: [Match3Gem] = []
    private var dice = JevDice(seed: 1)
    /// Each column's own stream of new gems: what drops into a column comes in the same order whoever plays.
    private var feeds: [JevDice] = []
    /// The legal swaps `options()` listed, and what each does, measured with the known gems only.
    private var legal: [Match3Swap] = []
    private var facts: [Match3Facts] = []
    /// The last move, for the picture: the board before it and everything that happened, beat by beat.
    fileprivate var replay: Match3Replay?
    private(set) var ticked = Date.distantPast
    private(set) var score = 0, used = 0, combo = 0, shuffles = 0
    private(set) var over = false
    /// A person at the board: the gem they picked up, and the square the arrow keys are on.
    private var person = false
    private var picked: Int?
    private var cursor = 27
    private var keyed = false

    let controls = "点一颗宝石，再点它旁边的一颗交换 · 方向键移动、空格选中"

    var status: String {
        "第 \(used)/\(Match3Rules.turns) 步 · \(score) 分 · 最佳连击 ×\(combo)" + (shuffles > 0 ? " · 洗牌 \(shuffles) 次" : "")
    }
    var situation: String {
        let left = Match3Rules.turns - used
        let turn = left <= 1 ? "this is the last move, so a special gem made now will never be used"
            : "\(left) moves left counting this one"
        let specials = board.map(\.kind).filter { $0 != .plain }
        return "move \(used + 1) of \(Match3Rules.turns): \(turn); score so far \(score); special gems on the board: "
            + (specials.isEmpty ? "none" : Match3Facts.specials(specials))
    }
    var grid: [[JevCell]] {
        (0..<Match3Rules.side).map { row in
            (0..<Match3Rules.side).map { col in
                let gem = board[row * Match3Rules.side + col]
                if gem.kind == .bomb { return JevCell(colour: Color(white: 0.16), text: "✸", ink: .white, big: true) }
                let mark = gem.kind == .row ? "═" : gem.kind == .column ? "‖" : gem.kind == .wrapped ? "▣" : ""
                return JevCell(colour: Match3Art.colour(gem.colour), text: mark, ink: .white, big: true)
            }
        }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        dice = JevDice(seed: seed)
        feeds = (0..<Match3Rules.side).map { _ in JevDice(seed: dice.next()) }
        board = deal()
        score = 0; used = 0; combo = 0; shuffles = 0; over = false
        legal = []; facts = []; replay = nil; ticked = .distantPast
        picked = nil; cursor = 27; keyed = false
    }

    func prepare(person: Bool) {
        self.person = person
        if !person { picked = nil; keyed = false }
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        legal = Match3Rules.swaps(board)
        if legal.isEmpty { _ = reshuffle(); legal = Match3Rules.swaps(board) }
        guard !legal.isEmpty else { over = true; return [] }
        facts = legal.map { swap in
            Match3Facts(board: board, swap: swap, outcome: Match3Rules.resolve(board, swap, fill: { _ in .unknown }))
        }
        let left = Match3Rules.turns - used
        // A person may play anything, and clicks exactly the swap an option names: one option a swap.
        if person {
            return facts.indices.map { index in
                JevOption(id: String(format: "p%02d", index + 1), label: facts[index].words, merit: facts[index].merit(left: left),
                          move: index, title: facts[index].title)
            }
        }
        return Self.ballot(facts, left: left)
    }

    /// Options that read the same become one. The move played is the first of them in board order — a
    /// tie-break that favours nobody — and `strongest` is the evaluator's own favourite, for the heuristic.
    private static func ballot(_ facts: [Match3Facts], left: Int) -> [JevOption] {
        var order: [String] = [], first: [String: Int] = [:], strongest: [String: Int] = [:]
        for (index, fact) in facts.enumerated() {
            if let held = strongest[fact.words] {
                if fact.merit(left: left) > facts[held].merit(left: left) { strongest[fact.words] = index }
            } else {
                order.append(fact.words); first[fact.words] = index; strongest[fact.words] = index
            }
        }
        return order.enumerated().map { n, words in
            let pick = first[words]!, best = strongest[words]!
            return JevOption(id: String(format: "p%02d", n + 1), label: words, merit: facts[best].merit(left: left),
                             move: pick, strongest: best, title: facts[pick].title)
        }
    }

    func play(_ option: JevOption) {
        guard legal.indices.contains(option.move), !over else { return }
        let swap = legal[option.move], before = board, earlier = score
        let outcome = Match3Rules.resolve(board, swap, fill: { self.feed($0) })
        board = outcome.final
        score += outcome.points
        used += 1
        combo = max(combo, outcome.beats.count)
        var order: [Int]?
        if used >= Match3Rules.turns { over = true } else if Match3Rules.swaps(board).isEmpty { order = reshuffle() }
        let front = facts.indices.contains(option.move) ? facts[option.move].mover : swap.a
        replay = Match3Replay(before: before, swap: swap, front: front, outcome: outcome, shuffle: order, shuffled: board,
                              scoreBefore: earlier, person: person)
        legal = []; facts = []; picked = nil
        ticked = Date()
    }

    // MARK: A person at the board

    func tap(row: Int, col: Int, among options: [JevOption]) -> JevReaction {
        let side = Match3Rules.side
        guard !over, (0..<side).contains(row), (0..<side).contains(col) else { return .nothing }
        let cell = row * side + col
        keyed = false
        guard let held = picked, held != cell else {
            // The first click picks a gem up; a second click on it puts it down.
            picked = picked == cell ? nil : cell
            cursor = cell
            return .redraw
        }
        guard Match3Rules.neighbours(held, cell) else { picked = cell; cursor = cell; return .redraw }
        picked = nil
        let reaction = attempt(held, cell, among: options)
        if case .choose = reaction { cursor = cell }
        return reaction
    }

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        guard let key = pressed.last, !over else { return .nothing }
        let side = Match3Rules.side
        var step = (0, 0)
        switch key {
        case .left: step = (0, -1)
        case .right: step = (0, 1)
        case .up: step = (-1, 0)
        case .down: step = (1, 0)
        case .space:
            keyed = true
            picked = picked == cursor ? nil : cursor
            return .redraw
        case .letter: return .nothing
        }
        keyed = true
        let row = cursor / side + step.0, col = cursor % side + step.1
        guard (0..<side).contains(row), (0..<side).contains(col) else { return .redraw }
        let next = row * side + col
        // With a gem picked up, an arrow swaps it that way; without one, it moves the cursor.
        guard let from = picked else { cursor = next; return .redraw }
        picked = nil
        let reaction = attempt(from, next, among: options)
        if case .choose = reaction { cursor = next }
        return reaction
    }

    private func attempt(_ from: Int, _ to: Int, among options: [JevOption]) -> JevReaction {
        guard let index = legal.firstIndex(of: Match3Swap(from, to)) else { return .explain("换了也连不成三个") }
        if let option = options.first(where: { $0.move == index }) { return .choose(option) }
        // Offered merged (not how a person is offered moves, but then): the move itself, under its option's name.
        let fact = facts[index]
        return .choose(JevOption(id: options.first { $0.label == fact.words }?.id ?? "p00", label: fact.words,
                                 merit: fact.merit(left: Match3Rules.turns - used), move: index, title: fact.title))
    }

    // MARK: Dealing

    private func feed(_ column: Int) -> Match3Gem { Match3Gem(colour: feeds[column].below(Match3Rules.colours)) }

    /// A board with no line on it and at least one move.
    private func deal() -> [Match3Gem] {
        let side = Match3Rules.side
        while true {
            var dealt: [Match3Gem] = []
            for cell in 0..<(side * side) {
                let row = cell / side, col = cell % side
                var colour = dice.below(Match3Rules.colours)
                while (col >= 2 && dealt[cell - 1].colour == colour && dealt[cell - 2].colour == colour)
                        || (row >= 2 && dealt[cell - side].colour == colour && dealt[cell - 2 * side].colour == colour) {
                    colour = dice.below(Match3Rules.colours)
                }
                dealt.append(Match3Gem(colour: colour))
            }
            if !Match3Rules.swaps(dealt).isEmpty { return dealt }
        }
    }

    /// No move left: the same gems, shuffled, with no line on the board and a move to make. Returns where
    /// each gem came from.
    private func reshuffle() -> [Int] {
        shuffles += 1
        var order = Array(board.indices)
        for _ in 0..<400 {
            for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, dice.below(i + 1)) }
            let mixed = order.map { board[$0] }
            if Match3Rules.runs(mixed).isEmpty, !Match3Rules.swaps(mixed).isEmpty { board = mixed; return order }
        }
        // Hardly possible with six colours: the plain gems are dealt again where they lie.
        let specials = board
        board = deal()
        for cell in board.indices where specials[cell].kind != .plain { board[cell] = specials[cell] }
        if !Match3Rules.runs(board).isEmpty || Match3Rules.swaps(board).isEmpty { board = deal() }
        return Array(board.indices)
    }
}

// MARK: - The rules

fileprivate enum Match3Kind: UInt8 {
    /// A striped gem clears its row (`.row`) or its column (`.column`).
    case plain, row, column, wrapped, bomb
}

fileprivate struct Match3Gem: Equatable {
    /// 0…5 for the six colours; 6 for a colour bomb, which has none; 7 for a gem nobody knows yet.
    var colour: Int
    var kind: Match3Kind = .plain
    static let unknown = Match3Gem(colour: 7)
    static let bomb = Match3Gem(colour: 6, kind: .bomb)
    /// Whether it can line up: a colour bomb cannot, nor can a gem nobody knows yet.
    var lines: Bool { colour < 6 }
}

/// Two neighbouring cells, the lower-numbered first.
fileprivate struct Match3Swap: Equatable {
    var a: Int, b: Int
    init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
}

/// A special gem going off.
fileprivate struct Match3Blast {
    var cell: Int
    var kind: Match3Kind
    /// The colour a colour bomb went off on (-1 for everything); otherwise the gem's own.
    var colour: Int
    /// The gems it cleared that nothing had cleared before it.
    var cells: [Int]
    /// How far down a chain of specials setting each other off: 0 for one set off by a line or a swap.
    var depth: Int
}

/// Lines of one colour that share gems: one match, and the special gem it makes, if any, and where.
fileprivate struct Match3Group {
    var colour: Int
    var cells: [Int]
    var runs: Int
    var made: Match3Gem?
    var at: Int
}

/// One clear and the fall after it.
fileprivate struct Match3Beat {
    /// The board as the beat begins: just after the swap, or after the last fall.
    var start: [Match3Gem]
    var groups: [Match3Group]
    var blasts: [Match3Blast]
    var cleared: [Int]
    /// The board after the fall, and for each of its cells the row its gem fell from (negative: dropped in from above).
    var landed: [Match3Gem]
    var from: [Int]
    var points: Int
    var level: Int
}

fileprivate struct Match3Outcome {
    var beats: [Match3Beat]
    var points: Int
    var final: [Match3Gem]
    /// A colour bomb went off on the swap: nothing slid.
    var bomb: Bool
}

fileprivate enum Match3Rules {
    static let side = 8, colours = 6, turns = 30

    static func neighbours(_ x: Int, _ y: Int) -> Bool {
        abs(x / side - y / side) + abs(x % side - y % side) == 1
    }

    /// Every line of three or more of one colour, across and down.
    static func runs(_ b: [Match3Gem]) -> [(cells: [Int], across: Bool)] {
        var out: [(cells: [Int], across: Bool)] = []
        for across in [true, false] {
            for line in 0..<side {
                func cell(_ k: Int) -> Int { across ? line * side + k : k * side + line }
                var start = 0
                while start < side {
                    let gem = b[cell(start)]
                    var end = start + 1
                    if gem.lines {
                        while end < side, b[cell(end)].colour == gem.colour { end += 1 }
                        if end - start >= 3 { out.append(((start..<end).map(cell), across)) }
                    }
                    start = end
                }
            }
        }
        return out
    }

    /// Whether the gem on `cell` is in a line of three or more.
    static func lined(_ b: [Match3Gem], _ cell: Int) -> Bool {
        let gem = b[cell]
        guard gem.lines else { return false }
        let row = cell / side, col = cell % side
        func count(_ dr: Int, _ dc: Int) -> Int {
            var n = 0, r = row + dr, c = col + dc
            while r >= 0, r < side, c >= 0, c < side, b[r * side + c].colour == gem.colour { n += 1; r += dr; c += dc }
            return n
        }
        return count(0, -1) + count(0, 1) >= 2 || count(-1, 0) + count(1, 0) >= 2
    }

    /// Every legal swap, in board order: one that lines up three, or one with a colour bomb in it.
    static func swaps(_ b: [Match3Gem]) -> [Match3Swap] {
        var out: [Match3Swap] = [], work = b
        for cell in b.indices {
            for other in [cell % side < side - 1 ? cell + 1 : -1, cell / side < side - 1 ? cell + side : -1] where other >= 0 {
                if b[cell].kind == .bomb || b[other].kind == .bomb { out.append(Match3Swap(cell, other)); continue }
                guard b[cell].colour != b[other].colour else { continue }
                work.swapAt(cell, other)
                if lined(work, cell) || lined(work, other) { out.append(Match3Swap(cell, other)) }
                work.swapAt(cell, other)
            }
        }
        return out
    }

    /// Lines that share gems are one match. Five in a line makes a colour bomb; lines crossing (an L, a T)
    /// make a wrapped gem where they cross; four in a line makes a striped gem, striped across the line.
    /// It is made where the gem that caused it moved to, if that is one of them.
    static func groups(_ b: [Match3Gem], _ runs: [(cells: [Int], across: Bool)], prefer: [Int]) -> [Match3Group] {
        var owner = Array(runs.indices)
        func root(_ x: Int) -> Int { var x = x; while owner[x] != x { x = owner[x] }; return x }
        for i in runs.indices {
            for j in runs.indices where j > i && !Set(runs[i].cells).isDisjoint(with: runs[j].cells) {
                let ri = root(i), rj = root(j)
                if ri != rj { owner[rj] = ri }
            }
        }
        var out: [Match3Group] = []
        for leader in runs.indices where root(leader) == leader {
            let members = runs.indices.filter { root($0) == leader }
            var cells: [Int] = []
            for member in members { for cell in runs[member].cells where !cells.contains(cell) { cells.append(cell) } }
            let colour = b[cells[0]].colour
            var made: Match3Gem?
            var spots: [Int] = []
            if let long = members.first(where: { runs[$0].cells.count >= 5 }) {
                made = .bomb; spots = runs[long].cells
            } else if members.count >= 2 {
                made = Match3Gem(colour: colour, kind: .wrapped)
                spots = cells.filter { cell in members.filter { runs[$0].cells.contains(cell) }.count >= 2 }
            } else if runs[members[0]].cells.count == 4 {
                made = Match3Gem(colour: colour, kind: runs[members[0]].across ? .column : .row)
                spots = runs[members[0]].cells
            }
            let at = prefer.first(where: spots.contains) ?? (spots.isEmpty ? cells[0] : spots[spots.count / 2])
            out.append(Match3Group(colour: colour, cells: cells, runs: members.count, made: made, at: at))
        }
        return out
    }

    /// The colour most gems still standing have, for a colour bomb set off by a blast rather than a swap.
    static func commonest(_ b: [Match3Gem], _ cleared: [Bool]) -> Int {
        var counts = Array(repeating: 0, count: colours)
        for cell in b.indices where !cleared[cell] && b[cell].lines { counts[b[cell].colour] += 1 }
        guard let most = counts.max(), most > 0 else { return -1 }
        return counts.firstIndex(of: most)!
    }

    /// Special gems among the cleared set each other off, breadth first.
    static func chain(_ b: [Match3Gem], _ cleared: inout [Bool], from start: [Int], depth first: Int, spent: Set<Int>) -> [Match3Blast] {
        var blasts: [Match3Blast] = [], queue = start.map { (cell: $0, depth: first) }, fired = spent, head = 0
        while head < queue.count {
            let (cell, depth) = queue[head]
            head += 1
            let gem = b[cell]
            guard gem.kind != .plain, fired.insert(cell).inserted else { continue }
            let row = cell / side, col = cell % side
            var hit: [Int] = [], colour = gem.colour
            switch gem.kind {
            case .plain: continue
            case .row: hit = (0..<side).map { row * side + $0 }
            case .column: hit = (0..<side).map { $0 * side + col }
            case .wrapped:
                for r in max(0, row - 1)...min(side - 1, row + 1) { for c in max(0, col - 1)...min(side - 1, col + 1) { hit.append(r * side + c) } }
            case .bomb:
                colour = commonest(b, cleared)
                hit = colour < 0 ? [] : b.indices.filter { b[$0].colour == colour }
                hit.append(cell)
            }
            var fresh: [Int] = []
            for h in hit where !cleared[h] { cleared[h] = true; fresh.append(h) }
            blasts.append(Match3Blast(cell: cell, kind: gem.kind, colour: colour, cells: fresh, depth: depth))
            for h in fresh where b[h].kind != .plain && !fired.contains(h) { queue.append((h, depth + 1)) }
        }
        return blasts
    }

    static func bonus(_ kind: Match3Kind) -> Int {
        switch kind {
        case .plain: return 0
        case .row, .column: return 30
        case .wrapped: return 50
        case .bomb: return 80
        }
    }

    /// A swap played out to the end: the clear it makes, then fall after fall until nothing lines up.
    /// Ten points a gem cleared, a bonus for a special gem made, all of it times the beat's number.
    /// `fill` says what drops into a column: the next gem from its stream, or a gem nobody knows yet.
    static func resolve(_ board: [Match3Gem], _ swap: Match3Swap, fill: (Int) -> Match3Gem) -> Match3Outcome {
        var b = board
        let bombSwap = b[swap.a].kind == .bomb || b[swap.b].kind == .bomb
        if !bombSwap { b.swapAt(swap.a, swap.b) }
        var beats: [Match3Beat] = [], moved = [swap.a, swap.b], total = 0, level = 1
        while level <= 40 {
            var cleared = Array(repeating: false, count: side * side)
            var groups: [Match3Group] = [], blasts: [Match3Blast] = []
            if bombSwap, level == 1 {
                let bomb = b[swap.a].kind == .bomb ? swap.a : swap.b, other = bomb == swap.a ? swap.b : swap.a
                let everything = b[other].kind == .bomb
                let colour = everything ? -1 : b[other].colour
                var hit = everything ? Array(b.indices) : b.indices.filter { b[$0].colour == colour }
                if !everything { hit.append(bomb) }
                for cell in hit { cleared[cell] = true }
                blasts.append(Match3Blast(cell: bomb, kind: .bomb, colour: colour, cells: hit, depth: 0))
                let spent: Set<Int> = everything ? [bomb, other] : [bomb]
                blasts += chain(b, &cleared, from: hit.filter { b[$0].kind != .plain && !spent.contains($0) }, depth: 1, spent: spent)
            } else {
                let found = runs(b)
                if found.isEmpty { break }
                groups = self.groups(b, found, prefer: moved)
                for group in groups { for cell in group.cells { cleared[cell] = true } }
                blasts = chain(b, &cleared, from: groups.flatMap(\.cells).filter { b[$0].kind != .plain }, depth: 0, spent: [])
            }
            let gone = cleared.indices.filter { cleared[$0] }
            var points = 10 * gone.count
            for group in groups { if let made = group.made { points += bonus(made.kind) } }
            points *= level
            var holes: [Match3Gem?] = b.map(Optional.some)
            for cell in gone { holes[cell] = nil }
            for group in groups { if let made = group.made { holes[group.at] = made } }
            var landed = b, from = Array(repeating: 0, count: side * side)
            moved = []
            for col in 0..<side {
                var write = side - 1
                for row in stride(from: side - 1, through: 0, by: -1) {
                    guard let gem = holes[row * side + col] else { continue }
                    landed[write * side + col] = gem
                    from[write * side + col] = row
                    if write != row { moved.append(write * side + col) }
                    write -= 1
                }
                for row in stride(from: write, through: 0, by: -1) {
                    landed[row * side + col] = fill(col)
                    from[row * side + col] = row - write - 1
                    moved.append(row * side + col)
                }
            }
            beats.append(Match3Beat(start: b, groups: groups, blasts: blasts, cleared: gone, landed: landed, from: from, points: points, level: level))
            total += points
            b = landed
            moved.sort(by: >)
            level += 1
        }
        return Match3Outcome(beats: beats, points: total, final: b, bomb: bombSwap)
    }
}

// MARK: - The words

/// What one swap does, measured, and said.
fileprivate struct Match3Facts {
    let swap: Match3Swap
    /// The cell whose gem makes the line — the one a person would say they moved — and that gem.
    let mover: Int, gem: Match3Gem
    /// The lower of the two rows, counted from the top.
    let row: Int
    let bomb: Bool, everything: Bool, target: Int
    /// What the swap lines up: the colour, how many, and whether in an L or T.
    let lines: [(colour: Int, count: Int, cross: Bool)]
    /// The gems the swap itself clears, what it sets off included.
    let first: Int
    let made: [Match3Kind], fired: [Match3Kind]
    /// Cascades from the gems already on the board, the gems they clear and the special gems they make.
    let cascades: Int, more: Int, later: [Match3Kind]
    let points: Int
    let words: String, title: String

    init(board: [Match3Gem], swap: Match3Swap, outcome: Match3Outcome) {
        self.swap = swap
        let opening = outcome.beats[0]
        bomb = outcome.bomb
        if bomb {
            mover = board[swap.a].kind == .bomb ? swap.a : swap.b
            let other = mover == swap.a ? swap.b : swap.a
            everything = board[other].kind == .bomb
            target = everything ? -1 : board[other].colour
        } else {
            // After the swap the gem on `a` is the one that came from `b`: if `a` is in a line, that gem made it.
            mover = opening.groups.contains(where: { $0.cells.contains(swap.a) }) ? swap.b : swap.a
            everything = false; target = -1
        }
        gem = board[mover]
        row = swap.b / Match3Rules.side
        lines = opening.groups.map { ($0.colour, $0.cells.count, $0.runs > 1) }
        first = opening.cleared.count
        made = opening.groups.compactMap { $0.made?.kind }
        fired = opening.blasts.filter { !(outcome.bomb && $0.depth == 0) }.map(\.kind)
        let rest = outcome.beats.dropFirst()
        cascades = rest.count
        more = rest.reduce(0) { $0 + $1.cleared.count }
        later = rest.flatMap { $0.groups.compactMap { $0.made?.kind } }
        points = outcome.points
        words = Self.describe(bomb: bomb, everything: everything, target: target, lines: lines, first: first, made: made, fired: fired,
                              cascades: cascades, more: more, later: later, points: points, row: row)
        let side = Match3Rules.side, r1 = swap.a / side, c1 = swap.a % side, r2 = swap.b / side, c2 = swap.b % side
        let place = r1 == r2 ? "第\(r1 + 1)行 \(c1 + 1)↔\(c2 + 1) 列" : "第\(c1 + 1)列 \(r1 + 1)↔\(r2 + 1) 行"
        let name = everything ? "两个彩色炸弹" : bomb ? "彩色炸弹炸\(Self.chinese[max(target, 0)])色" : Self.name(gem)
        title = "\(name) \(place)"
    }

    /// The evaluator: the points for sure, what the special gems made are worth later (nothing on the last
    /// move), and a little for a swap low on the board, which shakes more gems — by the same top, middle
    /// and bottom the words say, so that swaps that read alike are worth alike.
    func merit(left: Int) -> Double {
        let after = left - 1
        let use = after >= 2 ? 1.0 : after == 1 ? 0.6 : 0
        let worth = (made + later).reduce(0.0) { sum, kind in
            sum + (kind == .bomb ? 150 : kind == .wrapped ? 75 : kind == .plain ? 0 : 60)
        }
        return Double(points) + use * worth + (row <= 2 ? 0 : row <= 4 ? 8 : 15)
    }

    static let english = ["red", "orange", "yellow", "green", "blue", "purple"]
    static let chinese = ["红", "橙", "黄", "绿", "蓝", "紫"]

    static func name(_ gem: Match3Gem) -> String {
        guard gem.lines else { return "彩色炸弹" }
        let base = chinese[gem.colour] + "宝石"
        switch gem.kind {
        case .row, .column: return "条纹" + base
        case .wrapped: return "包装" + base
        default: return base
        }
    }

    /// Small counts as numbers; past a handful, named.
    static func amount(_ n: Int) -> String {
        n < 10 ? "\(n)" : n < 15 ? "about a dozen" : n < 25 ? "about twenty" : n < 45 ? "about thirty or more" : "more than 45"
    }

    static func specials(_ kinds: [Match3Kind]) -> String {
        let striped = kinds.filter { $0 == .row || $0 == .column }.count
        let wrapped = kinds.filter { $0 == .wrapped }.count, bombs = kinds.filter { $0 == .bomb }.count
        var parts: [String] = []
        if striped > 0 { parts.append(striped == 1 ? "a striped gem" : "\(striped) striped gems") }
        if wrapped > 0 { parts.append(wrapped == 1 ? "a wrapped gem" : "\(wrapped) wrapped gems") }
        if bombs > 0 { parts.append(bombs == 1 ? "a colour bomb" : "\(bombs) colour bombs") }
        return parts.joined(separator: " and ")
    }

    static func makes(_ kind: Match3Kind) -> String {
        switch kind {
        case .row: return "makes a striped gem, which clears its whole row, 8 gems, when it is matched later"
        case .column: return "makes a striped gem, which clears its whole column, 8 gems, when it is matched later"
        case .wrapped: return "makes a wrapped gem, which clears the 3 by 3 square around it, 9 gems, when it is matched later"
        case .bomb: return "makes a colour bomb, which clears every gem of one colour, about a dozen, when it is swapped later"
        case .plain: return ""
        }
    }

    static func describe(bomb: Bool, everything: Bool, target: Int, lines: [(colour: Int, count: Int, cross: Bool)], first: Int,
                         made: [Match3Kind], fired: [Match3Kind], cascades: Int, more: Int, later: [Match3Kind],
                         points: Int, row: Int) -> String {
        var parts: [String] = []
        if everything {
            parts.append("swaps two colour bombs together: clears the whole board, all 64 gems at once")
        } else if bomb {
            let name = english[max(target, 0)]
            parts.append("sets off the colour bomb on \(name): clears every \(name) gem"
                         + (fired.isEmpty ? ", \(amount(first)) gems at once" : " and sets off \(specials(fired)) among them, \(amount(first)) gems at once in all"))
        } else {
            let lined = lines.map { "\($0.count) \(english[$0.colour]) gems" + ($0.cross ? " in an L or T" : "") }.joined(separator: " and ")
            parts.append("lines up \(lined)" + (made.isEmpty && fired.isEmpty ? (lines.count > 1 ? ", plain matches" : ", a plain match") : ""))
            parts += made.map(makes)
            if !fired.isEmpty { parts.append("sets off \(specials(fired)) already on the board: \(amount(first)) gems cleared at once in all") }
        }
        if cascades == 0 {
            parts.append("no cascade follows from the gems already on the board")
        } else {
            parts.append("then the gems already on the board fall into " + (cascades == 1 ? "a cascade that clears" : "\(cascades) cascades that clear")
                         + " \(amount(more)) more" + (later.isEmpty ? "" : " and make \(specials(later))"))
        }
        let rounded = points < 100 ? "\(points) points" : points < 250 ? "about \((points + 5) / 10 * 10) points (a big score)"
            : "about \((points + 25) / 50 * 50) points (a huge score)"
        parts.append("scores \(rounded) for sure")
        parts.append(row <= 2 ? "near the top of the board" : row <= 4 ? "in the middle of the board" : "near the bottom of the board")
        return parts.joined(separator: "; ")
    }
}

// MARK: - The picture

/// The last move, kept for the picture, and how long each part of it takes to watch.
fileprivate struct Match3Replay {
    var before: [Match3Gem]
    var swap: Match3Swap
    /// The cell whose gem the player moved: it passes in front.
    var front: Int
    var outcome: Match3Outcome
    /// No move was left afterwards: where each gem of the reshuffled board came from.
    var shuffle: [Int]?
    var shuffled: [Match3Gem]
    var scoreBefore: Int
    var person: Bool

    static let slide = 0.2, clear = 0.36, fall = 0.34, mix = 0.6
    var duration: Double { Self.slide + Double(outcome.beats.count) * (Self.clear + Self.fall) + (shuffle == nil ? 0 : Self.mix) }
    func clearStart(_ beat: Int) -> Double { Self.slide + Double(beat) * (Self.clear + Self.fall) }
    /// When a beat's points pop up over the board.
    func popTime(_ beat: Int) -> Double { clearStart(beat) + Self.clear * 0.42 }
}

extension JevMatch3: JevPainted {
    var aspect: Double { 0.8 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let total = replay?.duration ?? 0
        // A person watches the move at its own pace — sped up if a long cascade would drag — since
        // their next move is a while off; a player on the arcade's clock sees it within the glide.
        let pace = max(1, total / 2.2)
        let natural = min(max(since, 0) * pace, total)
        let u = replay.map { $0.person ? natural : max(natural, t * total) } ?? 0
        let done = replay.map { $0.person ? total / pace : 0.6 } ?? 0
        let targets = picked.map { held in legal.compactMap { $0.a == held ? $0.b : $0.b == held ? $0.a : nil } } ?? []
        let scene = Match3Scene(board: board, replay: replay, u: u, now: now, score: score, left: Match3Rules.turns - used, combo: combo,
                                over: over, curtain: over ? min(1, max(0, (since - done) / 0.4)) : 0,
                                picked: person ? picked : nil, cursor: person && keyed && !over ? cursor : nil, targets: person ? targets : [])
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    func spot(at point: CGPoint, in size: CGSize) -> (row: Int, col: Int)? {
        let (frame, cell) = Match3Scene.layout(size)
        guard frame.contains(point) else { return nil }
        let last = Match3Rules.side - 1
        return (min(Int((point.y - frame.minY) / cell), last), min(Int((point.x - frame.minX) / cell), last))
    }
}

/// One cut of gem, in a unit circle: its outline, the ring where the facets start (the rim shows outside
/// it), a middle ring, and the table on top, with the shade of every facet lit from the top left.
fileprivate struct Match3Cut {
    let outline: [CGPoint], girdle: [CGPoint], middle: [CGPoint], table: [CGPoint]
    let outer: [Int], inner: [Int]
    let tableTop: CGFloat, tableHeight: CGFloat
    /// The highlight: centre and size of an ellipse, turned a little; and the glint.
    let gloss: CGRect, glint: CGPoint

    init(_ outline: [CGPoint], table k: CGFloat, gloss: CGRect, glint: CGPoint) {
        var cx: CGFloat = 0, cy: CGFloat = 0
        for p in outline { cx += p.x; cy += p.y }
        cx /= CGFloat(outline.count); cy /= CGFloat(outline.count)
        func scaled(_ s: CGFloat, lift: CGFloat) -> [CGPoint] {
            outline.map { CGPoint(x: cx + ($0.x - cx) * s, y: cy + ($0.y - cy) * s - lift) }
        }
        self.outline = outline
        girdle = scaled(0.87, lift: 0)
        middle = scaled(0.5 + k * 0.45, lift: 0.03)
        table = scaled(k, lift: 0.06)
        var outer: [Int] = [], inner: [Int] = []
        let light = (x: -0.5, y: -0.866)
        for i in outline.indices {
            let p = outline[i], q = outline[(i + 1) % outline.count]
            var nx = Double(q.y - p.y), ny = Double(p.x - q.x)
            if nx * Double((p.x + q.x) / 2 - cx) + ny * Double((p.y + q.y) / 2 - cy) < 0 { nx = -nx; ny = -ny }
            let d = (nx * light.x + ny * light.y) / max((nx * nx + ny * ny).squareRoot(), 1e-9)
            let level = d > 0.55 ? 0 : d > 0.12 ? 1 : d > -0.3 ? 2 : d > -0.7 ? 3 : 4
            outer.append(level)
            // Nearer the table the facets lie flatter: the same light, softer, and every other one catching it.
            inner.append(min(4, max(0, (level + 2) / 2 + (i % 2 == 0 ? 0 : 1) - 1)))
        }
        self.outer = outer; self.inner = inner
        let ys = table.map(\.y)
        tableTop = ys.min() ?? 0; tableHeight = (ys.max() ?? 0) - tableTop
        self.gloss = gloss; self.glint = glint
    }
}

/// The gems' colours and cuts, worked out once.
fileprivate enum Match3Art {
    typealias RGB = (Double, Double, Double)
    /// Ruby, topaz, citrine, emerald, sapphire, amethyst.
    static let tints: [RGB] = [(0.96, 0.13, 0.25), (1.0, 0.52, 0.1), (1.0, 0.82, 0.12), (0.1, 0.78, 0.38), (0.15, 0.46, 1.0), (0.7, 0.3, 0.98)]
    static let levels: [Double] = [1.6, 1.28, 0.98, 0.72, 0.5]
    static let rims: [Color] = tints.map { JevDraw.shade($0, 0.3) }
    static let facets: [[Color]] = tints.map { tint in levels.map { JevDraw.shade(tint, $0) } }
    static let sparks: [Color] = tints.map { JevDraw.shade($0, 1.35) }
    static func colour(_ index: Int) -> Color { index >= 0 && index < tints.count ? JevDraw.shade(tints[index], 1) : Color(white: 0.9) }

    static func polygon(_ count: Int, radius: CGFloat, turn: Double, squash: CGFloat = 1, shift: CGFloat = 0) -> [CGPoint] {
        (0..<count).map { k in
            let a = turn + Double(k) * 2 * .pi / Double(count)
            return CGPoint(x: CGFloat(cos(a)) * radius, y: CGFloat(sin(a)) * radius * squash + shift)
        }
    }

    static func points(_ xy: [(Double, Double)]) -> [CGPoint] { xy.map { CGPoint(x: $0.0, y: $0.1) } }

    /// A ruby cut round.
    static let round: [CGPoint] = polygon(12, radius: 0.98, turn: .pi / 12)
    /// A topaz, a hexagon lying flat.
    static let hexagon: [CGPoint] = polygon(6, radius: 1.02, turn: 0, squash: 0.93)
    /// A citrine cut as a triangle, its corners taken off.
    static let triangle: [CGPoint] = {
        let a = CGPoint(x: 0, y: -1.16), b = CGPoint(x: 1.12, y: 0.74), c = CGPoint(x: -1.12, y: 0.74)
        func along(_ p: CGPoint, _ q: CGPoint, _ f: CGFloat) -> CGPoint { CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f) }
        let corners: [(CGPoint, CGPoint, CGFloat)] = [(a, b, 0.13), (a, b, 0.87), (b, c, 0.1), (b, c, 0.9), (c, a, 0.87), (c, a, 0.13)]
        return corners.map { along($0.0, $0.1, $0.2) }
    }()
    /// An emerald, step cut: an oblong with its corners cut.
    static let emerald: [CGPoint] = points([(-0.52, -0.95), (0.52, -0.95), (0.84, -0.63), (0.84, 0.63), (0.52, 0.95), (-0.52, 0.95), (-0.84, 0.63), (-0.84, -0.63)])
    /// A sapphire, a diamond shape, its sides a touch full.
    static let diamond: [CGPoint] = points([(0, -1.06), (0.48, -0.5), (0.88, 0), (0.48, 0.5), (0, 1.06), (-0.48, 0.5), (-0.88, 0), (-0.48, -0.5)])
    /// An amethyst, a pear: a point on top, round below.
    static let pear: [CGPoint] = {
        var out: [CGPoint] = [CGPoint(x: 0, y: -1.06)]
        for k in 0..<9 {
            let angle: Double = (-33.4 + 246.8 * Double(k) / 8) * Double.pi / 180
            let x: CGFloat = CGFloat(cos(angle)) * 0.74, y: CGFloat = 0.24 + CGFloat(sin(angle)) * 0.74
            out.append(CGPoint(x: x, y: y))
        }
        return out
    }()

    static let cuts: [Match3Cut] = [
        Match3Cut(round, table: 0.5, gloss: CGRect(x: -0.24, y: -0.42, width: 0.62, height: 0.3), glint: CGPoint(x: -0.44, y: -0.5)),
        Match3Cut(hexagon, table: 0.5, gloss: CGRect(x: -0.24, y: -0.44, width: 0.66, height: 0.26), glint: CGPoint(x: -0.52, y: -0.52)),
        Match3Cut(triangle, table: 0.46, gloss: CGRect(x: -0.3, y: -0.2, width: 0.4, height: 0.18), glint: CGPoint(x: -0.2, y: -0.44)),
        Match3Cut(emerald, table: 0.56, gloss: CGRect(x: -0.2, y: -0.46, width: 0.66, height: 0.24), glint: CGPoint(x: -0.52, y: -0.66)),
        Match3Cut(diamond, table: 0.46, gloss: CGRect(x: -0.14, y: -0.36, width: 0.46, height: 0.24), glint: CGPoint(x: -0.3, y: -0.58)),
        Match3Cut(pear, table: 0.48, gloss: CGRect(x: -0.18, y: -0.08, width: 0.5, height: 0.26), glint: CGPoint(x: -0.4, y: -0.12)),
    ]

    static let rainbow = Gradient(colors: (tints + [tints[0]]).map { JevDraw.shade($0, 1.15) })

    /// A gem's outline, for clipping and for flashes.
    static func outline(_ colour: Int, at p: CGPoint, radius r: CGFloat) -> Path {
        var path = Path()
        guard colour < 6 else { path.addEllipse(in: CGRect(x: p.x - r * 0.86, y: p.y - r * 0.86, width: r * 1.72, height: r * 1.72)); return path }
        path.addLines(cuts[colour].outline.map { CGPoint(x: p.x + $0.x * r, y: p.y + $0.y * r) })
        path.closeSubpath()
        return path
    }

    /// A four-pointed sparkle.
    static func star(_ path: inout Path, at p: CGPoint, radius r: CGFloat, waist: CGFloat = 0.22) {
        let w = r * waist
        path.addLines([CGPoint(x: p.x, y: p.y - r), CGPoint(x: p.x + w, y: p.y - w), CGPoint(x: p.x + r, y: p.y), CGPoint(x: p.x + w, y: p.y + w),
                       CGPoint(x: p.x, y: p.y + r), CGPoint(x: p.x - w, y: p.y + w), CGPoint(x: p.x - r, y: p.y), CGPoint(x: p.x - w, y: p.y - w)])
        path.closeSubpath()
    }

    /// A ring as a filled band, so that many of them of different widths are one fill.
    static func ring(_ path: inout Path, at p: CGPoint, radius r: CGFloat, width w: CGFloat) {
        guard r > 0, w > 0 else { return }
        path.move(to: CGPoint(x: p.x + r + w / 2, y: p.y))
        path.addArc(center: p, radius: r + w / 2, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        path.closeSubpath()
        path.move(to: CGPoint(x: p.x + max(0, r - w / 2), y: p.y))
        path.addArc(center: p, radius: max(0, r - w / 2), startAngle: .zero, endAngle: .degrees(-360), clockwise: true)
        path.closeSubpath()
    }

    /// Stars and soft lights behind the board, in fractions of the picture.
    static let bokeh: [(x: Double, y: Double, r: Double, tint: Int, phase: Double)] = (0..<16).map { i -> (x: Double, y: Double, r: Double, tint: Int, phase: Double) in
        let x: Double = Double(JevDraw.hash(i, 31) % 1000) / 1000, y: Double = Double(JevDraw.hash(i, 32) % 1000) / 1000
        let r: Double = 0.03 + Double(JevDraw.hash(i, 33) % 100) / 100 * 0.07
        return (x, y, r, i % 6, Double(JevDraw.hash(i, 34) % 628) / 100)
    }
    static let stars: [(x: Double, y: Double, r: Double, beat: Int)] = (0..<60).map { i -> (x: Double, y: Double, r: Double, beat: Int) in
        let x: Double = Double(JevDraw.hash(i, 41) % 1000) / 1000, y: Double = Double(JevDraw.hash(i, 42) % 1000) / 1000
        let r: Double = 0.4 + Double(JevDraw.hash(i, 43) % 100) / 100 * (i % 7 == 0 ? 1.3 : 0.6)
        return (x, y, r, i % 3)
    }

    // MARK: Painting

    /// The lights over the velvet: soft discs drifting and faint stars twinkling, only where the tray does not hide them.
    static func lights(_ g: GraphicsContext, _ size: CGSize, hole: CGRect, now: Double) {
        for b in bokeh {
            let r = CGFloat(b.r) * size.width
            let p = CGPoint(x: CGFloat(b.x) * size.width + CGFloat(sin(now * 0.21 + b.phase)) * size.width * 0.012,
                            y: CGFloat(b.y) * size.height + CGFloat(cos(now * 0.17 + b.phase)) * size.width * 0.012)
            let disc = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            guard !hole.intersects(disc) else { continue }
            let tint = JevDraw.shade(tints[b.tint], 1.2)
            let a = 0.1 + 0.05 * sin(now * 0.6 + b.phase)
            g.fill(Path(ellipseIn: disc), with: .radialGradient(Gradient(colors: [tint.opacity(a), tint.opacity(a * 0.6), tint.opacity(0)]), center: p, startRadius: 0, endRadius: r))
        }
        for beat in 0..<3 {
            var dots = Path()
            for star in stars where star.beat == beat {
                let r = CGFloat(star.r) * size.width / 640, p = CGPoint(x: CGFloat(star.x) * size.width, y: CGFloat(star.y) * size.height)
                guard !hole.contains(p) else { continue }
                dots.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
            g.fill(dots, with: .color(.white.opacity(0.28 + 0.24 * sin(now * 1.5 + Double(beat) * 2.1))))
        }
    }

    /// A pane of smoked glass: a shadow under it, lighter at the top, an edge that catches the light.
    static func glass(_ g: GraphicsContext, _ r: CGRect, _ cell: CGFloat) {
        let radius = cell * 0.3
        g.fill(Path(roundedRect: r.offsetBy(dx: cell * 0.04, dy: cell * 0.12), cornerRadius: radius), with: .color(.black.opacity(0.3)))
        let shape = Path(roundedRect: r, cornerRadius: radius)
        g.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.36, green: 0.26, blue: 0.62).opacity(0.62), Color(red: 0.13, green: 0.07, blue: 0.3).opacity(0.62)]),
                                            startPoint: r.origin, endPoint: CGPoint(x: r.minX, y: r.maxY)))
        g.fill(shape, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0), location: 0.55)]),
                                            startPoint: r.origin, endPoint: CGPoint(x: r.minX, y: r.maxY)))
        g.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0.08)]), startPoint: r.origin, endPoint: CGPoint(x: r.minX, y: r.maxY)), lineWidth: 1)
    }

    /// What makes a special gem look special, drawn over (and for a wrapped gem, under) its body.
    static func under(_ g: GraphicsContext, _ gem: Match3Gem, at p: CGPoint, radius r: CGFloat, now: Double) {
        let pulse = 0.5 + 0.5 * sin(now * 3.2 + Double(p.x + p.y) * 0.05)
        switch gem.kind {
        case .wrapped:
            let tint = tints[gem.colour], reach = r * CGFloat(1.32 + 0.06 * pulse)
            g.fill(Path(ellipseIn: CGRect(x: p.x - reach, y: p.y - reach, width: 2 * reach, height: 2 * reach)),
                   with: .radialGradient(Gradient(colors: [JevDraw.shade(tint, 1.3).opacity(0.75), JevDraw.shade(tint, 1.1).opacity(0.3), .clear]),
                                         center: p, startRadius: r * 0.5, endRadius: reach))
            // The wrapper: a rounded square behind the gem, lit at its edge.
            let box = CGRect(x: p.x - r * 1.02, y: p.y - r * 1.02, width: r * 2.04, height: r * 2.04)
            g.fill(Path(roundedRect: box, cornerRadius: r * 0.42), with: .linearGradient(Gradient(colors: [JevDraw.shade(tint, 1.35), JevDraw.shade(tint, 0.55)]),
                                                                                         startPoint: box.origin, endPoint: CGPoint(x: box.maxX, y: box.maxY)))
            g.stroke(Path(roundedRect: box.insetBy(dx: r * 0.05, dy: r * 0.05), cornerRadius: r * 0.38), with: .color(.white.opacity(0.55 + 0.3 * pulse)), lineWidth: max(1, r * 0.07))
        case .row, .column:
            let tint = tints[gem.colour], reach = r * 1.25
            g.fill(Path(ellipseIn: CGRect(x: p.x - reach, y: p.y - reach, width: 2 * reach, height: 2 * reach)),
                   with: .radialGradient(Gradient(colors: [JevDraw.shade(tint, 1.4).opacity(0.35 + 0.25 * pulse), .clear]), center: p, startRadius: r * 0.6, endRadius: reach))
        default: break
        }
    }

    static func over(_ g: GraphicsContext, _ gem: Match3Gem, at p: CGPoint, radius r: CGFloat, now: Double) {
        switch gem.kind {
        case .row, .column:
            // Candy stripes across the gem, the way it will fire.
            var c = g
            c.clip(to: outline(gem.colour, at: p, radius: r * 0.9))
            var bands = Path(), edges = Path()
            let drift = CGFloat((now * 0.35).truncatingRemainder(dividingBy: 1)) * r * 0.52
            for k in -3...3 {
                let offset = CGFloat(k) * r * 0.52 + drift
                let band = gem.kind == .row ? CGRect(x: p.x - r, y: p.y + offset - r * 0.1, width: 2 * r, height: r * 0.2)
                    : CGRect(x: p.x + offset - r * 0.1, y: p.y - r, width: r * 0.2, height: 2 * r)
                bands.addRect(band)
                edges.addRect(gem.kind == .row ? band.offsetBy(dx: 0, dy: r * 0.06) : band.offsetBy(dx: r * 0.06, dy: 0))
            }
            c.fill(edges, with: .color(JevDraw.shade(tints[gem.colour], 0.4).opacity(0.5)))
            c.fill(bands, with: .color(.white.opacity(0.88)))
            g.stroke(outline(gem.colour, at: p, radius: r), with: .color(.white.opacity(0.7)), lineWidth: max(1, r * 0.07))
        case .wrapped:
            // Tied up with a ribbon, a bow on top.
            var c = g
            c.clip(to: outline(gem.colour, at: p, radius: r * 0.95))
            let ribbon = Color(red: 1, green: 0.95, blue: 0.8)
            var cross = Path()
            cross.addRect(CGRect(x: p.x - r * 0.12, y: p.y - r, width: r * 0.24, height: 2 * r))
            cross.addRect(CGRect(x: p.x - r, y: p.y - r * 0.12, width: 2 * r, height: r * 0.24))
            c.fill(cross.offsetBy(dx: r * 0.04, dy: r * 0.05), with: .color(.black.opacity(0.25)))
            c.fill(cross, with: .color(ribbon.opacity(0.92)))
            var bow = Path()
            let top = CGPoint(x: p.x, y: p.y - r * 0.02)
            bow.addEllipse(in: CGRect(x: top.x - r * 0.46, y: top.y - r * 0.2, width: r * 0.42, height: r * 0.3))
            bow.addEllipse(in: CGRect(x: top.x + r * 0.04, y: top.y - r * 0.2, width: r * 0.42, height: r * 0.3))
            g.fill(bow.offsetBy(dx: r * 0.03, dy: r * 0.05), with: .color(.black.opacity(0.25)))
            g.fill(bow, with: .color(ribbon))
            g.stroke(bow, with: .color(Color(red: 0.8, green: 0.6, blue: 0.3)), lineWidth: max(0.8, r * 0.04))
            g.fill(Path(ellipseIn: CGRect(x: top.x - r * 0.11, y: top.y - r * 0.12, width: r * 0.22, height: r * 0.22)), with: .color(Color(red: 1, green: 0.85, blue: 0.5)))
        case .bomb:
            bomb(g, at: p, radius: r, now: now)
        case .plain:
            break
        }
    }

    /// A colour bomb: a dark glossy sphere dusted with sprinkles of every colour, in a turning rainbow ring.
    static func bomb(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat, now: Double) {
        let ring = r * 0.98
        let turn = Angle.radians(now * 0.9)
        g.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.3, y: p.y - r * 1.3, width: r * 2.6, height: r * 2.6)),
               with: .radialGradient(Gradient(colors: [Color.white.opacity(0.35), Color(red: 0.8, green: 0.5, blue: 1).opacity(0.18), .clear]),
                                     center: p, startRadius: r * 0.6, endRadius: r * 1.3))
        g.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: 2 * ring, height: 2 * ring)),
                 with: .conicGradient(rainbow, center: p, angle: turn), lineWidth: r * 0.18)
        let body = r * 0.84
        let sphere = Path(ellipseIn: CGRect(x: p.x - body, y: p.y - body, width: 2 * body, height: 2 * body))
        g.fill(sphere, with: .radialGradient(Gradient(stops: [.init(color: Color(red: 0.46, green: 0.34, blue: 0.56), location: 0),
                                                              .init(color: Color(red: 0.16, green: 0.08, blue: 0.22), location: 0.45),
                                                              .init(color: Color(red: 0.03, green: 0.01, blue: 0.06), location: 1)]),
                                             center: CGPoint(x: p.x - body * 0.32, y: p.y - body * 0.36), startRadius: 0, endRadius: body * 1.5))
        var sprinkles = Array(repeating: Path(), count: 6)
        for k in 0..<14 {
            let angle = Double(k) * 2.39996 + now * 0.5
            let reach = body * CGFloat(0.18 + 0.64 * (Double(k) + 0.5) / 14)
            let at = CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach * 0.92)
            let tilt = CGAffineTransform(rotationAngle: CGFloat(angle * 1.7 + Double(k))).concatenating(CGAffineTransform(translationX: at.x, y: at.y))
            let w = body * 0.3, h = body * 0.11
            sprinkles[k % 6].addRoundedRect(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerSize: CGSize(width: h / 2, height: h / 2), transform: tilt)
        }
        var c = g
        c.clip(to: sphere)
        for index in 0..<6 { c.fill(sprinkles[index], with: .color(JevDraw.shade(tints[index], 1.2))) }
        c.fill(Path(ellipseIn: CGRect(x: p.x - body * 0.62, y: p.y - body * 0.78, width: body * 0.9, height: body * 0.52)),
               with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]), startPoint: CGPoint(x: 0, y: p.y - body * 0.78), endPoint: CGPoint(x: 0, y: p.y - body * 0.2)))
        c.fill(Path(ellipseIn: CGRect(x: p.x - body * 0.52, y: p.y - body * 0.62, width: body * 0.18, height: body * 0.18)), with: .color(.white.opacity(0.9)))
    }
}

/// What never moves — the velvet behind and the tray with its slots — painted once for a canvas size with
/// CoreGraphics and kept, so a frame starts with one picture instead of a few dozen gradients.
fileprivate enum Match3Stage {
    nonisolated(unsafe) static var kept: (key: String, image: CGImage)?

    static func image(_ size: CGSize, scale: CGFloat) -> CGImage? {
        let key = "\(Int(size.width * 4))x\(Int(size.height * 4))@\(Int(scale * 4))"
        if let kept, kept.key == key { return kept.image }
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        paint(ctx, size, space)
        guard let image = ctx.makeImage() else { return nil }
        kept = (key, image)
        return image
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    static func paint(_ ctx: CGContext, _ size: CGSize, _ space: CGColorSpace) {
        let (frame, cell) = Match3Scene.layout(size)
        let pad: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient? {
            CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))
        }
        func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
        }
        func ring(_ outer: CGPath, _ inner: CGPath) -> CGPath {
            let path = CGMutablePath()
            path.addPath(outer)
            path.addPath(inner)
            return path
        }
        /// A gradient along a line, within a shape (even-odd, so a ring is a ring).
        func linear(_ shape: CGPath?, _ stops: [(CGColor, CGFloat)], _ from: CGPoint, _ to: CGPoint) {
            guard let lit = gradient(stops) else { return }
            ctx.saveGState()
            if let shape { ctx.addPath(shape); ctx.clip(using: .evenOdd) }
            ctx.drawLinearGradient(lit, start: from, end: to, options: pad)
            ctx.restoreGState()
        }
        func glow(_ colour: (Double, Double, Double, Double), at centre: CGPoint, radius: CGFloat) {
            guard let lit = gradient([(rgb(colour.0, colour.1, colour.2, colour.3), 0), (rgb(colour.0, colour.1, colour.2, 0), 1)]) else { return }
            ctx.drawRadialGradient(lit, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }
        func fill(_ shape: CGPath, _ colour: CGColor, evenOdd: Bool = false) {
            ctx.addPath(shape)
            ctx.setFillColor(colour)
            ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
        }

        // Velvet: a deep violet going to plum, a warm glow low on the left, a cool one high on the right.
        linear(nil, [(rgb(0.09, 0.05, 0.2), 0), (rgb(0.2, 0.05, 0.24), 1)], .zero, CGPoint(x: size.width * 0.35, y: size.height))
        glow((0.95, 0.25, 0.62, 0.3), at: CGPoint(x: 0, y: size.height), radius: size.width * 0.95)
        glow((0.3, 0.5, 1, 0.26), at: CGPoint(x: size.width, y: 0), radius: size.width * 0.9)

        // The tray's shadow, a gold bezel with a bright edge, a dark lip, and the violet face.
        let bezel = frame.insetBy(dx: -cell * 0.24, dy: -cell * 0.24), inside = CGPath(rect: bezel.insetBy(dx: cell * 0.14, dy: cell * 0.14), transform: nil)
        for (grow, alpha) in [(0.5, 0.12), (0.2, 0.22)] as [(CGFloat, Double)] {
            fill(ring(rounded(bezel.insetBy(dx: -cell * grow, dy: -cell * grow).offsetBy(dx: cell * 0.04, dy: cell * 0.2), cell * (0.38 + grow)), inside),
                 rgb(0, 0, 0, alpha), evenOdd: true)
        }
        let lip = frame.insetBy(dx: -cell * 0.07, dy: -cell * 0.07)
        linear(ring(rounded(bezel, cell * 0.34), rounded(lip, cell * 0.2)),
               [(rgb(1, 0.92, 0.66), 0), (rgb(0.93, 0.72, 0.36), 0.3), (rgb(0.62, 0.4, 0.16), 0.66), (rgb(0.36, 0.21, 0.08), 1)],
               bezel.origin, CGPoint(x: bezel.maxX, y: bezel.maxY))
        ctx.saveGState()
        ctx.addPath(rounded(bezel.insetBy(dx: 0.6, dy: 0.6), cell * 0.34))
        ctx.setLineWidth(1.2)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        if let edge = gradient([(rgb(1, 1, 1, 0.85), 0), (rgb(1, 1, 1, 0.1), 0.5), (rgb(0, 0, 0, 0.25), 1)]) {
            ctx.drawLinearGradient(edge, start: bezel.origin, end: CGPoint(x: bezel.maxX, y: bezel.maxY), options: pad)
        }
        ctx.restoreGState()
        linear(ring(rounded(lip, cell * 0.2), rounded(frame, cell * 0.16)), [(rgb(0.2, 0.1, 0.05), 0), (rgb(0.55, 0.36, 0.16), 1)],
               lip.origin, CGPoint(x: lip.maxX, y: lip.maxY))
        linear(rounded(frame, cell * 0.16), [(rgb(0.14, 0.1, 0.3), 0), (rgb(0.07, 0.045, 0.16), 1)], frame.origin, CGPoint(x: frame.minX, y: frame.maxY))

        // Sixty-four slots in a faint check, each sunk: shade under its top and left edges, light along its foot.
        let light = CGMutablePath(), dark = CGMutablePath(), tops = CGMutablePath(), lefts = CGMutablePath(), feet = CGMutablePath()
        let inset = cell * 0.045
        for row in 0..<Match3Rules.side {
            for col in 0..<Match3Rules.side {
                let slot = CGRect(x: frame.minX + CGFloat(col) * cell, y: frame.minY + CGFloat(row) * cell, width: cell, height: cell).insetBy(dx: inset, dy: inset)
                ((row + col) % 2 == 0 ? light : dark).addPath(rounded(slot, cell * 0.16))
                tops.addPath(rounded(CGRect(x: slot.minX, y: slot.minY, width: slot.width, height: cell * 0.16), cell * 0.08))
                lefts.addRect(CGRect(x: slot.minX, y: slot.minY + cell * 0.1, width: cell * 0.07, height: slot.height - cell * 0.2))
                feet.addRect(CGRect(x: slot.minX + cell * 0.12, y: slot.maxY - cell * 0.035, width: slot.width - cell * 0.24, height: cell * 0.035))
            }
        }
        fill(light, rgb(0.27, 0.22, 0.48, 0.62))
        fill(dark, rgb(0.19, 0.15, 0.37, 0.62))
        fill(tops, rgb(0, 0, 0, 0.22))
        fill(lefts, rgb(0, 0, 0, 0.12))
        fill(feet, rgb(1, 1, 1, 0.1))
        // Shade under the lip of the tray.
        linear(CGPath(rect: CGRect(x: frame.minX + cell * 0.1, y: frame.minY, width: frame.width - cell * 0.2, height: cell * 0.45), transform: nil),
               [(rgb(0, 0, 0, 0.4), 0), (rgb(0, 0, 0, 0), 1)], CGPoint(x: 0, y: frame.minY), CGPoint(x: 0, y: frame.minY + cell * 0.45))
    }
}

/// Each colour of gem drawn once, with CoreGraphics, into a picture of its own — shadow, rim, facets, a
/// table lit from above, gloss and glint — and after that only placed: a board of gems is sixty-four
/// images a frame rather than a few thousand facets.
fileprivate enum Match3Sprites {
    /// How far a sprite reaches from the gem's centre, in radii: room for the shadow.
    static let span: CGFloat = 1.3
    nonisolated(unsafe) static var cache: [Int: CGImage] = [:]

    static func colour(_ rgb: (Double, Double, Double), _ k: Double, _ alpha: Double = 1) -> CGColor {
        func c(_ v: Double) -> CGFloat { CGFloat(k >= 1 ? v + (1 - v) * (k - 1) : v * k) }
        return CGColor(srgbRed: c(rgb.0), green: c(rgb.1), blue: c(rgb.2), alpha: CGFloat(alpha))
    }

    static func sprite(_ index: Int, pixels: Int) -> CGImage? {
        let key = index * 100_000 + pixels
        if let known = cache[key] { return known }
        guard pixels > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let side = CGFloat(pixels)
        ctx.translateBy(x: 0, y: side)
        ctx.scaleBy(x: 1, y: -1)
        let r = side / (2 * span), p = CGPoint(x: side / 2, y: side / 2)
        let cut = Match3Art.cuts[index], tint = Match3Art.tints[index], n = cut.outline.count
        func at(_ q: CGPoint) -> CGPoint { CGPoint(x: p.x + q.x * r, y: p.y + q.y * r) }
        func polygon(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            return path
        }
        func fill(_ path: CGPath, _ colour: CGColor) { ctx.addPath(path); ctx.setFillColor(colour); ctx.fillPath() }
        fill(polygon(cut.outline.map { CGPoint(x: p.x + $0.x * r * 1.02 + r * 0.06, y: p.y + $0.y * r * 1.02 + r * 0.16) }), CGColor(gray: 0, alpha: 0.34))
        fill(polygon(cut.outline.map(at)), colour(tint, 0.3))
        let girdle = cut.girdle.map(at), middle = cut.middle.map(at), table = cut.table.map(at)
        for i in 0..<n {
            let j = (i + 1) % n
            fill(polygon([girdle[i], girdle[j], middle[j], middle[i]]), colour(tint, Match3Art.levels[cut.outer[i]]))
            fill(polygon([middle[i], middle[j], table[j], table[i]]), colour(tint, Match3Art.levels[cut.inner[i]]))
        }
        let top = p.y + cut.tableTop * r, height = cut.tableHeight * r
        if let lit = CGGradient(colorsSpace: space, colors: [colour(tint, 1.45), colour(tint, 1.08), colour(tint, 0.8)] as CFArray, locations: [0, 0.4, 1]) {
            ctx.saveGState()
            ctx.addPath(polygon(table))
            ctx.clip()
            ctx.drawLinearGradient(lit, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: top + height), options: [])
            ctx.restoreGState()
        }
        let g = cut.gloss
        ctx.saveGState()
        ctx.translateBy(x: p.x + (g.minX + g.width / 2) * r * 0.9, y: p.y + (g.minY + g.height / 2) * r)
        ctx.rotate(by: -0.42)
        ctx.addEllipse(in: CGRect(x: -g.width * r / 2, y: -g.height * r / 2, width: g.width * r, height: g.height * r))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.36))
        ctx.fillPath()
        ctx.restoreGState()
        let glint = at(cut.glint), s = r * 0.085
        ctx.addEllipse(in: CGRect(x: glint.x - s, y: glint.y - s, width: 2 * s, height: 2 * s))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
        ctx.fillPath()
        guard let image = ctx.makeImage() else { return nil }
        if cache.count > 60 { cache = [:] }
        cache[key] = image
        return image
    }
}

/// The gems of one layer of the picture: sprites placed where the gems are, and what makes a special gem
/// special drawn over them.
fileprivate struct Match3Jewels {
    let cell: CGFloat, top: CGFloat
    private var placed: [(colour: Int, rect: CGRect)] = []
    private var shadows = Path()
    private var specials: [(gem: Match3Gem, at: CGPoint, r: CGFloat)] = []

    init(cell: CGFloat, top: CGFloat) { self.cell = cell; self.top = top }

    mutating func add(_ gem: Match3Gem, at p: CGPoint, radius r: CGFloat) {
        guard gem.colour < 7, r > 0 else { return }
        if gem.colour < 6 {
            let reach = r * Match3Sprites.span
            placed.append((gem.colour, CGRect(x: p.x - reach, y: p.y - reach, width: 2 * reach, height: 2 * reach)))
        } else {
            shadows.addEllipse(in: CGRect(x: p.x - r * 0.84, y: p.y - r * 0.7, width: r * 1.8, height: r * 1.8))
        }
        if gem.kind != .plain { specials.append((gem, p, r)) }
    }

    func paint(_ g: GraphicsContext, now: Double) {
        for s in specials { Match3Art.under(g, s.gem, at: s.at, radius: s.r, now: now) }
        if !shadows.isEmpty { g.fill(shadows, with: .color(.black.opacity(0.34))) }
        // One sprite a colour, big enough for the largest a gem gets drawn (lifted, swelling) at this cell size.
        let pixels = Int((cell * 0.45 * 1.25 * 2 * Match3Sprites.span * g.environment.displayScale).rounded(.up))
        var resolved: [Int: GraphicsContext.ResolvedImage] = [:]
        var twinkles = Path()
        for item in placed {
            if resolved[item.colour] == nil, let image = Match3Sprites.sprite(item.colour, pixels: pixels) {
                resolved[item.colour] = g.resolve(Image(decorative: image, scale: 1))
            }
            if let image = resolved[item.colour] { g.draw(image, in: item.rect) }
            // Now and then a gem catches the light: a glint flares on it and fades.
            let phase = Double(JevDraw.hash(Int(item.rect.midX / cell * 7), Int(item.rect.midY / cell * 7)) % 1000) / 1000
            let beat = (now * 0.21 + phase).truncatingRemainder(dividingBy: 1)
            if beat < 0.06 {
                let r = item.rect.width / (2 * Match3Sprites.span), glint = Match3Art.cuts[item.colour].glint
                Match3Art.star(&twinkles, at: CGPoint(x: item.rect.midX + glint.x * r, y: item.rect.midY + glint.y * r), radius: r * 0.6 * CGFloat(sin(beat / 0.06 * .pi)), waist: 0.1)
            }
        }
        if !twinkles.isEmpty { g.fill(twinkles, with: .color(.white.opacity(0.92))) }
        for s in specials { Match3Art.over(g, s.gem, at: s.at, radius: s.r, now: now) }
    }
}

fileprivate struct Match3Scene {
    let board: [Match3Gem], replay: Match3Replay?, u: Double, now: Double
    let score: Int, left: Int, combo: Int, over: Bool, curtain: Double
    let picked: Int?, cursor: Int?, targets: [Int]

    typealias R = Match3Replay

    static func layout(_ size: CGSize) -> (board: CGRect, cell: CGFloat) {
        let pad = size.width * 0.05
        let side = min(size.width - 2 * pad, size.height - pad - size.width * 0.21)
        return (CGRect(x: (size.width - side) / 2, y: size.height - pad - side, width: side, height: side), side / CGFloat(Match3Rules.side))
    }

    /// Where the replay is: the swap sliding, a beat's clear or its fall, or the gems reshuffling.
    enum Moment { case still, slide(Double), clear(Int, Double), fall(Int, Double), mix(Double) }

    var moment: Moment {
        guard let replay else { return .still }
        var t = u
        if t < R.slide { return .slide(max(0, t) / R.slide) }
        t -= R.slide
        for k in replay.outcome.beats.indices {
            if t < R.clear { return .clear(k, t / R.clear) }
            t -= R.clear
            if t < R.fall { return .fall(k, t / R.fall) }
            t -= R.fall
        }
        if replay.shuffle != nil, t < R.mix { return .mix(t / R.mix) }
        return .still
    }

    /// When each cleared gem of a beat goes (0…1 of the clear), and where it slides to if it melts into a special gem made there.
    static func vanish(_ beat: Match3Beat, bombFirst: Bool) -> [Int: (at: Double, into: Int?)] {
        var out: [Int: (at: Double, into: Int?)] = [:]
        for group in beat.groups {
            for cell in group.cells { out[cell] = group.made == nil ? (0.36, nil) : (0.42, cell == group.at ? nil : group.at) }
        }
        for blast in beat.blasts {
            let start = blastStart(blast, bombFirst: bombFirst)
            for (index, cell) in blast.cells.enumerated() where cell != blast.cell {
                var delay = 0.06
                switch blast.kind {
                case .row, .column: delay += 0.035 * Double(abs(cell / 8 - blast.cell / 8) + abs(cell % 8 - blast.cell % 8))
                case .wrapped: delay += 0.03
                case .bomb: delay += 0.3 * Double(index) / Double(max(1, blast.cells.count))
                case .plain: break
                }
                let at = min(0.94, start + delay)
                if at < out[cell]?.at ?? 2 { out[cell] = (at, nil) }
            }
            let own = blast.kind == .bomb && blast.depth == 0 && bombFirst ? min(0.94, start + 0.42) : start
            if own < out[blast.cell]?.at ?? 2 || out[blast.cell]?.into != nil { out[blast.cell] = (own, nil) }
        }
        return out
    }

    static func blastStart(_ blast: Match3Blast, bombFirst: Bool) -> Double {
        if bombFirst { return blast.depth == 0 ? 0.02 : min(0.9, 0.48 + 0.12 * Double(blast.depth - 1)) }
        return min(0.9, 0.3 + 0.12 * Double(blast.depth))
    }

    /// Falling: from rest, faster and faster, the longest drop landing at 0.8; then a little hop.
    static func fall(from: Double, to: Double, _ t: Double, longest: Double) -> Double {
        let h = to - from
        guard h > 0 else { return to }
        let pull = 2 * longest / 0.64
        let land = (2 * h / pull).squareRoot()
        if t < land { return from + 0.5 * pull * t * t }
        let s = (t - land) / 0.2
        return s < 1 ? to - 0.13 * min(1, h) * sin(.pi * s) * (1 - s) : to
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let (frame, cell) = Self.layout(size)
        let radius = cell * 0.45, n = Match3Rules.side
        func centre(_ row: Double, _ col: Double) -> CGPoint {
            CGPoint(x: frame.minX + (CGFloat(col) + 0.5) * cell, y: frame.minY + (CGFloat(row) + 0.5) * cell)
        }
        func centre(_ index: Int) -> CGPoint { centre(Double(index / n), Double(index % n)) }

        let scale = g.environment.displayScale
        if let stage = Match3Stage.image(size, scale: scale) {
            g.draw(Image(decorative: stage, scale: scale), in: CGRect(origin: .zero, size: size))
        } else {
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.12, green: 0.06, blue: 0.22)))
        }
        Match3Art.lights(g, size, hole: frame.insetBy(dx: -cell * 0.8, dy: -cell * 0.8), now: now)
        hud(g, size, frame, cell)

        var inBoard = g
        inBoard.clip(to: Path(roundedRect: frame, cornerRadius: cell * 0.16))
        var glow = g
        glow.blendMode = .plusLighter
        glow.clip(to: Path(roundedRect: frame.insetBy(dx: -cell * 0.24, dy: -cell * 0.24), cornerRadius: cell * 0.34))

        var gems = Match3Jewels(cell: cell, top: frame.minY), back = gems, front = gems
        var flashes: [(Path, Double)] = []
        let moment = self.moment

        switch moment {
        case .still:
            for i in board.indices where i != picked { gems.add(board[i], at: centre(i), radius: radius) }
            if let picked {
                let bob = CGFloat(sin(now * 5)) * cell * 0.025
                front.add(board[picked], at: CGPoint(x: centre(picked).x, y: centre(picked).y - cell * 0.05 + bob), radius: radius * 1.1)
            }
        case .slide(let t):
            guard let replay else { break }
            let a = replay.swap.a, b = replay.swap.b
            for i in replay.before.indices where i != a && i != b { gems.add(replay.before[i], at: centre(i), radius: radius) }
            if replay.outcome.bomb {
                // The bomb gathers itself; the gem it was swapped with glows.
                let bomb = replay.before[a].kind == .bomb ? a : b, other = bomb == a ? b : a
                gems.add(replay.before[other], at: centre(other), radius: radius)
                front.add(replay.before[bomb], at: centre(bomb), radius: radius * CGFloat(1 + 0.2 * JevDraw.smooth(t)))
                flashes.append((Match3Art.outline(replay.before[other].colour, at: centre(other), radius: radius), 0.5 * t))
            } else {
                let e = CGFloat(JevDraw.smooth(t)), arc = CGFloat(sin(t * .pi))
                let mover = replay.front, other = mover == a ? b : a
                let p = centre(mover), q = centre(other)
                // Across the line of the swap, the moved gem passes a little in front and to one side.
                let side = CGPoint(x: -(q.y - p.y) / cell * 0.14 * cell, y: (q.x - p.x) / cell * 0.14 * cell)
                back.add(replay.before[other], at: CGPoint(x: q.x + (p.x - q.x) * e - side.x * arc, y: q.y + (p.y - q.y) * e - side.y * arc), radius: radius * (1 - 0.08 * arc))
                front.add(replay.before[mover], at: CGPoint(x: p.x + (q.x - p.x) * e + side.x * arc, y: p.y + (q.y - p.y) * e + side.y * arc), radius: radius * (1 + 0.12 * arc))
            }
        case .clear(let k, let t):
            guard let replay else { break }
            let beat = replay.outcome.beats[k]
            let times = Self.vanish(beat, bombFirst: replay.outcome.bomb && k == 0)
            for i in beat.start.indices {
                guard let v = times[i] else { gems.add(beat.start[i], at: centre(i), radius: radius); continue }
                guard t < v.at else { continue }
                var p = centre(i), r = radius
                if let into = v.into {
                    let q = JevDraw.smooth((t - 0.1) / (v.at - 0.1)), target = centre(into)
                    p = CGPoint(x: p.x + (target.x - p.x) * CGFloat(q), y: p.y + (target.y - p.y) * CGFloat(q))
                    r = radius * CGFloat(1 - 0.25 * q)
                    flashes.append((Match3Art.outline(beat.start[i].colour, at: p, radius: r), 0.55 * q))
                } else {
                    let swell = min(1, max(0, (t - (v.at - 0.28)) / 0.28))
                    r = radius * CGFloat(1 + 0.16 * swell)
                    flashes.append((Match3Art.outline(beat.start[i].colour, at: p, radius: r), 0.85 * swell))
                }
                gems.add(beat.start[i], at: p, radius: r)
            }
            for group in beat.groups {
                guard let made = group.made, t >= 0.42 else { continue }
                let q = (t - 0.42) / 0.3
                let pop = q < 1 ? 1 + 0.35 * sin(min(q, 1) * .pi) * (1 - q * 0.4) : 1
                front.add(made, at: centre(group.at), radius: radius * CGFloat(min(pop, 1.4) * min(1, 0.4 + q * 1.6)))
            }
        case .fall(let k, let t):
            guard let replay else { break }
            let beat = replay.outcome.beats[k]
            var longest = 0.0
            for i in beat.landed.indices { longest = max(longest, Double(i / n - beat.from[i])) }
            for i in beat.landed.indices {
                let row = Self.fall(from: Double(beat.from[i]), to: Double(i / n), t, longest: max(longest, 1))
                gems.add(beat.landed[i], at: centre(row, Double(i % n)), radius: radius)
            }
        case .mix(let t):
            guard let replay, let order = replay.shuffle else { break }
            let e = JevDraw.smooth(t), mid = CGPoint(x: frame.midX, y: frame.midY)
            for i in replay.shuffled.indices {
                let p = centre(order[i]), q = centre(i)
                // Swept round the middle of the board on their way.
                let swirl = CGFloat(sin(e * .pi)) * 0.35
                let x = p.x + (q.x - p.x) * CGFloat(e), y = p.y + (q.y - p.y) * CGFloat(e)
                let dx = x - mid.x, dy = y - mid.y
                gems.add(replay.shuffled[i], at: CGPoint(x: mid.x + dx * (1 - swirl * 0.4) - dy * swirl, y: mid.y + dy * (1 - swirl * 0.4) + dx * swirl),
                         radius: radius * CGFloat(1 - 0.2 * sin(e * .pi)))
            }
        }

        // A gem picked up: a ring of light under it, and a mark on each neighbour it could swap with.
        if let picked {
            let p = centre(picked), pulse = 0.5 + 0.5 * sin(now * 4.5)
            let box = CGRect(x: p.x - cell * 0.5, y: p.y - cell * 0.5, width: cell, height: cell).insetBy(dx: cell * 0.03, dy: cell * 0.03)
            inBoard.fill(Path(roundedRect: box, cornerRadius: cell * 0.18),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.6).opacity(0.5 + 0.2 * pulse), Color(red: 1, green: 0.75, blue: 0.3).opacity(0.1)]),
                                               center: p, startRadius: 0, endRadius: cell * 0.62))
        }
        back.paint(inBoard, now: now)
        gems.paint(inBoard, now: now)

        // Gems about to go flash white.
        for (path, strength) in flashes where strength > 0.02 {
            glow.fill(path, with: .color(.white.opacity(min(0.6, strength * 0.65))))
        }
        front.paint(g, now: now)
        if let picked { marks(g, glow, centre(picked), cell: cell, targets: targets.map { centre($0) }) }
        if let cursor { brackets(g, centre(cursor), cell: cell) }

        if let replay { effects(glow, replay, cell: cell, centre: centre) }
        if let replay { popups(g, replay, frame: frame, cell: cell, centre: centre) }
        if case .mix(let t) = moment { banner(g, "没有能走的了 · 重新洗牌", at: CGPoint(x: frame.midX, y: frame.midY), cell: cell, alpha: sin(t * .pi)) }

        if over, curtain > 0 {
            var c = g
            c.opacity = curtain
            JevDraw.curtain(c, size, title: "步数用完了！", detail: "\(score) 分 · 最佳连击 ×\(combo)")
        }
    }

    // MARK: Effects

    /// How far through its life an effect is (0…1), or nil when it is not showing. Whatever its span, it is
    /// over by the end of the move, so nothing hangs on the board while the next move is awaited.
    private func age(_ start: Double, _ span: Double) -> Double? {
        guard let replay else { return nil }
        let end = min(start + span, replay.duration)
        guard u >= start, u < end else { return nil }
        return (u - start) / (end - start)
    }

    /// Everything that shines: where a gem bursts, a glow, shards of it and glints flying out, and a thin ring;
    /// beams where striped gems fire, a blast where a wrapped gem goes, lightning from a colour bomb, and a
    /// flash where a special gem is made.
    private func effects(_ g: GraphicsContext, _ replay: Match3Replay, cell: CGFloat, centre: (Int) -> CGPoint) {
        var shards = Array(repeating: Path(), count: 7), deep = Array(repeating: Path(), count: 7)
        var rings = Array(repeating: Path(), count: 7), glints = Path()
        for (k, beat) in replay.outcome.beats.enumerated() {
            let begin = replay.clearStart(k)
            guard u >= begin else { continue }
            let bombFirst = replay.outcome.bomb && k == 0
            let times = Self.vanish(beat, bombFirst: bombFirst)
            for (spot, v) in times where v.into == nil {
                guard let age = age(begin + v.at * R.clear, 0.55) else { continue }
                let gem = beat.start[spot], tint = gem.lines ? gem.colour : 6
                let p = centre(spot), fly = 1 - (1 - age) * (1 - age)
                if age < 0.6 {
                    let glow = cell * CGFloat(0.45 + 0.5 * age), fade = 1 - age / 0.6
                    let colour = tint < 6 ? Match3Art.sparks[tint] : Color.white
                    g.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: 2 * glow, height: 2 * glow)),
                           with: .radialGradient(Gradient(colors: [Color.white.opacity(0.7 * fade), colour.opacity(0.45 * fade), colour.opacity(0)]),
                                                 center: p, startRadius: 0, endRadius: glow))
                }
                for s in 0..<6 {
                    let angle = Double(s) * 1.047 + Double(JevDraw.hash(spot * 7 + s, k + 3) % 100) / 90
                    let reach = cell * CGFloat(0.35 + Double(JevDraw.hash(s, spot * 5 + k) % 80) / 100) * CGFloat(fly)
                    let q = CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach + cell * 0.35 * CGFloat(age * age))
                    let size = cell * CGFloat(0.15 * (1 - 0.75 * age)), turn = angle + age * (s % 2 == 0 ? 7 : -7)
                    let corners = [0.0, 2.3, 4.2].map { CGPoint(x: q.x + CGFloat(cos(turn + $0)) * size, y: q.y + CGFloat(sin(turn + $0)) * size * ($0 == 0 ? 1.3 : 0.8)) }
                    if s % 2 == 0 { shards[tint].addLines(corners); shards[tint].closeSubpath() } else { deep[tint].addLines(corners); deep[tint].closeSubpath() }
                }
                for s in 0..<3 {
                    let angle = Double(s) * 2.094 + 0.5 + Double(JevDraw.hash(spot, s + 11 * k) % 100) / 100
                    let reach = cell * CGFloat(0.3 + 0.75 * fly)
                    let q = CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach)
                    Match3Art.star(&glints, at: q, radius: cell * CGFloat(0.12 * (1 - age)), waist: 0.16)
                }
                Match3Art.ring(&rings[tint], at: p, radius: cell * CGFloat(0.3 + 0.7 * fly), width: cell * 0.05 * CGFloat(1 - age))
            }
            for blast in beat.blasts { self.blast(g, blast, begin: begin, bombFirst: bombFirst, cell: cell, centre: centre) }
            for group in beat.groups {
                guard group.made != nil, let age = age(begin + 0.42 * R.clear, 0.5) else { continue }
                let p = centre(group.at)
                Match3Art.ring(&rings[group.colour < 6 ? group.colour : 6], at: p, radius: cell * CGFloat(0.35 + 0.6 * age), width: cell * 0.08 * CGFloat(1 - age))
                var star = Path()
                Match3Art.star(&star, at: p, radius: cell * CGFloat(0.95 * sin(age * .pi)), waist: 0.1)
                g.fill(star, with: .color(.white.opacity(0.85 * (1 - age))))
            }
        }
        for tint in 0..<7 {
            let colour = tint < 6 ? Match3Art.sparks[tint] : Color(white: 0.95)
            if !rings[tint].isEmpty { g.fill(rings[tint], with: .color(colour.opacity(0.55))) }
            if !deep[tint].isEmpty { g.fill(deep[tint], with: .color(tint < 6 ? Match3Art.facets[tint][2] : Color(white: 0.7))) }
            if !shards[tint].isEmpty { g.fill(shards[tint], with: .color(colour)) }
        }
        g.fill(glints, with: .color(.white.opacity(0.95)))
    }

    private func blast(_ g: GraphicsContext, _ blast: Match3Blast, begin: Double, bombFirst: Bool, cell: CGFloat, centre: (Int) -> CGPoint) {
        let start = begin + Self.blastStart(blast, bombFirst: bombFirst) * R.clear
        guard let age = age(start, 0.5) else { return }
        let p = centre(blast.cell), n = Match3Rules.side
        let tint = blast.colour >= 0 && blast.colour < 6 ? Match3Art.tints[blast.colour] : (1.0, 0.95, 0.9)
        switch blast.kind {
        case .row, .column:
            // A beam along the row or column, shot out both ways from the gem, with a flare where it starts.
            let reach = CGFloat(min(1, age / 0.3)) * cell * CGFloat(n), fade = age < 0.3 ? 1 : 1 - (age - 0.3) / 0.7
            for (width, colour) in [(1.0, JevDraw.shade(tint, 1.1).opacity(0.3 * fade)), (0.5, JevDraw.shade(tint, 1.4).opacity(0.65 * fade)),
                                    (0.16, Color.white.opacity(0.95 * fade))] as [(CGFloat, Color)] {
                let w = cell * width * CGFloat(0.65 + 0.35 * fade)
                let beam = blast.kind == .row ? CGRect(x: p.x - reach, y: p.y - w / 2, width: 2 * reach, height: w)
                    : CGRect(x: p.x - w / 2, y: p.y - reach, width: w, height: 2 * reach)
                g.fill(Path(roundedRect: beam, cornerRadius: w / 2), with: .color(colour))
            }
            var flare = Path()
            Match3Art.star(&flare, at: p, radius: cell * CGFloat(1.1 * fade), waist: 0.08)
            g.fill(flare, with: .color(.white.opacity(0.9 * fade)))
        case .wrapped:
            // A square blast over the three by three, and a ring running out from it.
            let grow = CGFloat(1 - pow(1 - min(age / 0.35, 1), 3)), fade = 1 - age
            let side = cell * (1 + 2.3 * grow)
            let box = CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
            g.fill(Path(roundedRect: box, cornerRadius: side * 0.22),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.95 * fade), JevDraw.shade(tint, 1.3).opacity(0.7 * fade), JevDraw.shade(tint, 1).opacity(0)]),
                                         center: p, startRadius: 0, endRadius: side * 0.72))
            var ring = Path()
            Match3Art.ring(&ring, at: p, radius: cell * (0.6 + 1.8 * CGFloat(age)), width: cell * 0.09 * CGFloat(fade))
            g.fill(ring, with: .color(JevDraw.shade(tint, 1.4).opacity(0.75 * fade)))
        case .bomb:
            // Lightning from the bomb to every gem of the colour, one after another; everything, if two bombs met.
            let fade = 1 - age
            if blast.colour < 0 {
                let full = cell * CGFloat(n) * CGFloat(0.2 + 1.2 * age)
                g.fill(Path(ellipseIn: CGRect(x: p.x - full, y: p.y - full, width: 2 * full, height: 2 * full)),
                       with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * fade), Color(red: 1, green: 0.8, blue: 1).opacity(0.5 * fade), .clear]),
                                             center: p, startRadius: 0, endRadius: full))
                return
            }
            var bolts = Path()
            let seconds = age * 0.5
            for (index, target) in blast.cells.enumerated() where target != blast.cell {
                // Each bolt goes out when its gem's turn comes, over the first 0.3 of the clear.
                let lit = (seconds - 0.3 * R.clear * Double(index) / Double(max(1, blast.cells.count))) / 0.06
                guard lit > 0 else { continue }
                let q = centre(target)
                let reach = CGFloat(min(1, lit))
                let dx = q.x - p.x, dy = q.y - p.y, length = max((dx * dx + dy * dy).squareRoot(), 1)
                let nx = -dy / length, ny = dx / length
                bolts.move(to: p)
                for step in 1...5 {
                    let f = CGFloat(step) / 5 * reach
                    let jag = step == 5 ? 0 : CGFloat(JevDraw.hash(target, step + Int(age * 12)) % 100 - 50) / 50 * cell * 0.2
                    bolts.addLine(to: CGPoint(x: p.x + dx * f + nx * jag, y: p.y + dy * f + ny * jag))
                }
            }
            g.stroke(bolts, with: .color(JevDraw.shade(tint, 1.2).opacity(0.4 * fade)), style: StrokeStyle(lineWidth: cell * 0.24, lineCap: .round, lineJoin: .round))
            g.stroke(bolts, with: .color(JevDraw.shade(tint, 1.5).opacity(0.8 * fade)), style: StrokeStyle(lineWidth: cell * 0.09, lineCap: .round, lineJoin: .round))
            g.stroke(bolts, with: .color(Color.white.opacity(0.95 * fade)), style: StrokeStyle(lineWidth: cell * 0.035, lineCap: .round, lineJoin: .round))
            let r = cell * CGFloat(0.55 + 0.6 * age)
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * fade), JevDraw.shade(tint, 1.3).opacity(0.5 * fade), .clear]), center: p, startRadius: 0, endRadius: r))
            var ring = Path()
            Match3Art.ring(&ring, at: p, radius: r * 0.9, width: cell * 0.12 * CGFloat(fade))
            g.fill(ring, with: .conicGradient(Match3Art.rainbow, center: p, angle: .radians(now * 2)))
        case .plain:
            break
        }
    }

    /// The points each beat scores, rising from where its gems were, and the cascade count once there is one.
    private func popups(_ g: GraphicsContext, _ replay: Match3Replay, frame: CGRect, cell: CGFloat, centre: (Int) -> CGPoint) {
        for (k, beat) in replay.outcome.beats.enumerated() where beat.points > 0 {
            guard let age = age(replay.popTime(k), 0.95) else { continue }
            var x: CGFloat = 0, y: CGFloat = 0
            for c in beat.cleared { let p = centre(c); x += p.x; y += p.y }
            let count = CGFloat(max(beat.cleared.count, 1))
            let rise = cell * 0.9 * CGFloat(1 - (1 - age) * (1 - age))
            let at = CGPoint(x: min(max(x / count, frame.minX + cell), frame.maxX - cell), y: min(max(y / count, frame.minY + cell * 0.6), frame.maxY - cell * 0.4) - rise)
            var c = g
            c.opacity = age < 0.7 ? 1 : (1 - age) / 0.3
            let size = cell * CGFloat(0.5 + 0.18 * max(0, 1 - age * 5)) * (beat.points >= 100 ? 1.15 : 1)
            JevDraw.text(c, "+\(beat.points)", at: at, size: size, colour: Color(red: 1, green: 0.93, blue: 0.62))
            if beat.level >= 2 {
                let pop = CGFloat(1 + 0.3 * max(0, 1 - age * 4))
                c.opacity = age < 0.6 ? 1 : (1 - age) / 0.4
                banner(c, "连击 ×\(beat.level)", at: CGPoint(x: frame.midX, y: frame.minY + cell * 0.75), cell: cell * 0.9 * pop, alpha: 1)
            }
        }
    }

    private func banner(_ g: GraphicsContext, _ text: String, at p: CGPoint, cell: CGFloat, alpha: Double) {
        var c = g
        c.opacity = alpha
        let font = Font.system(size: cell * 0.62, weight: .heavy, design: .rounded)
        let resolved = c.resolve(Text(text).font(font).foregroundColor(.white))
        let size = resolved.measure(in: CGSize(width: 2000, height: 400))
        let box = CGRect(x: p.x - size.width / 2 - cell * 0.4, y: p.y - size.height / 2 - cell * 0.14, width: size.width + cell * 0.8, height: size.height + cell * 0.28)
        c.fill(Path(roundedRect: box.offsetBy(dx: 0, dy: cell * 0.06), cornerRadius: box.height / 2), with: .color(.black.opacity(0.3)))
        c.fill(Path(roundedRect: box, cornerRadius: box.height / 2),
               with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.2, blue: 0.9)]),
                                     startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))
        c.stroke(Path(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), cornerRadius: box.height / 2), with: .color(.white.opacity(0.6)), lineWidth: 1.2)
        c.draw(Text(text).font(font).foregroundColor(Color(red: 0.35, green: 0.05, blue: 0.3).opacity(0.5)), at: CGPoint(x: p.x, y: p.y + cell * 0.04))
        c.draw(resolved, at: p)
    }

    // MARK: A person's marks

    /// Small chevrons from the picked gem toward each neighbour it can be swapped with.
    private func marks(_ g: GraphicsContext, _ glow: GraphicsContext, _ p: CGPoint, cell: CGFloat, targets: [CGPoint]) {
        let pulse = 0.5 + 0.5 * sin(now * 4.5)
        var ring = Path()
        ring.addRoundedRect(in: CGRect(x: p.x - cell * 0.47, y: p.y - cell * 0.47, width: cell * 0.94, height: cell * 0.94), cornerSize: CGSize(width: cell * 0.2, height: cell * 0.2))
        glow.stroke(ring, with: .color(Color(red: 1, green: 0.85, blue: 0.45).opacity(0.5 + 0.4 * pulse)), lineWidth: cell * 0.07)
        g.stroke(ring, with: .color(.white.opacity(0.9)), lineWidth: max(1.2, cell * 0.03))
        var arrows = Path()
        for q in targets {
            let dx = (q.x - p.x) / cell, dy = (q.y - p.y) / cell
            let tip = CGPoint(x: p.x + dx * cell * CGFloat(0.62 + 0.05 * pulse), y: p.y + dy * cell * CGFloat(0.62 + 0.05 * pulse))
            let back = CGPoint(x: tip.x - dx * cell * 0.13, y: tip.y - dy * cell * 0.13)
            arrows.addLines([tip, CGPoint(x: back.x - dy * cell * 0.12, y: back.y + dx * cell * 0.12), CGPoint(x: back.x + dy * cell * 0.12, y: back.y - dx * cell * 0.12)])
            arrows.closeSubpath()
        }
        g.fill(arrows.offsetBy(dx: 0, dy: cell * 0.02), with: .color(.black.opacity(0.35)))
        g.fill(arrows, with: .color(Color(red: 1, green: 0.95, blue: 0.75)))
    }

    /// The keyboard's cursor: four corners around the square.
    private func brackets(_ g: GraphicsContext, _ p: CGPoint, cell: CGFloat) {
        let h = cell * 0.48, l = cell * 0.16
        var path = Path()
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] as [(CGFloat, CGFloat)] {
            let corner = CGPoint(x: p.x + sx * h, y: p.y + sy * h)
            path.move(to: CGPoint(x: corner.x, y: corner.y - sy * l))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x - sx * l, y: corner.y))
        }
        g.stroke(path, with: .color(.black.opacity(0.4)), style: StrokeStyle(lineWidth: cell * 0.07, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: cell * 0.04, lineCap: .round, lineJoin: .round))
    }

    // MARK: The numbers

    /// The score as it counts up during the move.
    private var shownScore: Int {
        guard let replay else { return score }
        var shown = Double(replay.scoreBefore)
        for (k, beat) in replay.outcome.beats.enumerated() {
            shown += Double(beat.points) * min(1, max(0, (u - replay.popTime(k)) / 0.3))
        }
        return u >= replay.duration ? score : Int(shown.rounded())
    }

    /// Three panes of glass over the board: the score, the moves left, the best cascade.
    private func hud(_ g: GraphicsContext, _ size: CGSize, _ frame: CGRect, _ cell: CGFloat) {
        let top = size.height - frame.maxY - cell * 0.02, bottom = frame.minY - cell * 0.58
        let height = bottom - top, gap = cell * 0.22
        let span = frame.width + cell * 0.48
        let widths: [CGFloat] = [0.4, 0.3, 0.3].map { $0 * (span - 2 * gap) }
        var x = frame.minX - cell * 0.24
        let items: [(String, String)] = [("分数", "\(shownScore)"), ("剩余步数", "\(left)"), ("最佳连击", "×\(combo)")]
        for (index, item) in items.enumerated() {
            let rect = CGRect(x: x, y: top, width: widths[index], height: height)
            Match3Art.glass(g, rect, cell)
            g.draw(Text(item.0).font(.system(size: height * 0.17, weight: .bold, design: .rounded)).tracking(height * 0.03)
                    .foregroundColor(Color(red: 0.88, green: 0.82, blue: 1).opacity(0.85)), at: CGPoint(x: rect.midX, y: rect.minY + height * 0.25))
            let digits = CGFloat(max(item.1.count, 2))
            let font = Font.system(size: min(height * 0.42, rect.width * 0.9 / (digits * 0.6)), weight: .heavy, design: .rounded).monospacedDigit()
            let at = CGPoint(x: rect.midX, y: rect.minY + height * 0.62)
            g.draw(Text(verbatim: item.1).font(font).foregroundColor(Color(red: 0.45, green: 0.12, blue: 0.6).opacity(0.6)), at: CGPoint(x: at.x, y: at.y + height * 0.03))
            g.draw(Text(verbatim: item.1).font(font).foregroundColor(index == 0 ? Color(red: 1, green: 0.93, blue: 0.7) : .white), at: at)
            if index == 1 {
                // How much of the game is left, as a thin bar along the foot of the pane.
                let track = CGRect(x: rect.minX + rect.width * 0.16, y: rect.maxY - height * 0.14, width: rect.width * 0.68, height: max(2, height * 0.045))
                g.fill(Path(roundedRect: track, cornerRadius: track.height / 2), with: .color(.black.opacity(0.35)))
                let full = track.width * CGFloat(left) / CGFloat(Match3Rules.turns)
                g.fill(Path(roundedRect: CGRect(x: track.minX, y: track.minY, width: full, height: track.height), cornerRadius: track.height / 2),
                       with: .linearGradient(Gradient(colors: [Color(red: 0.4, green: 0.9, blue: 1), Color(red: 0.75, green: 0.5, blue: 1)]),
                                             startPoint: CGPoint(x: track.minX, y: 0), endPoint: CGPoint(x: track.maxX, y: 0)))
            }
            x += widths[index] + gap
        }
    }
}
