import SwiftUI

/// 吃豆人 — Pac-Man in a small classic maze, one tick a question.
///
/// Twenty-one cells by twenty-one: the arcade's maze taken in to walls and
/// corridors a cell thick, with its ghost house, its tunnel and its four power
/// pellets where they were, and no dead ends. Pac-Man moves a cell a tick, or
/// stays; the ghosts are a little slower and keep their arcade manners —
/// Blinky chases, Pinky aims four cells ahead, Inky flanks off Blinky, Clyde
/// chases until he is close and then goes to his corner — scattering and
/// chasing by turns, leaving the house one by one. A power pellet turns them
/// blue, slow and edible for a while; their eyes go home.
///
/// Nothing moves at random but a blue ghost at a crossing and a ghost choosing
/// its way out of the house, and both come from the seed: so once Pac-Man's
/// path is known, so is every ghost's, and the program says what a move comes
/// to — whether a ghost catches him on it or within two ticks whatever he does,
/// whether it walks into a trap, how near the nearest ghost is and whether it
/// is closing, what dots it eats and how far the next one is, where the power
/// pellets are, and while the ghosts are blue, which one can still be caught.
/// The evaluator that plays looks eight ticks ahead for its life and weighs the
/// rest.
@MainActor
final class JevPacman: JevGame {
    let id = "pacman", title = "吃豆人", symbol = "circle.circle"
    let rules = "Pac-Man in a maze 21 cells wide and 21 tall. Each tick Pac-Man moves one cell up, down, left or right, or stays put; walls stop him. A dot is worth 10 points and a power pellet 50, and eating every dot and pellet clears the level; the next level's ghosts are faster. Four ghosts hunt him, a little slower than he is: Blinky heads straight for him, Pinky for the cells in front of him, Inky cuts him off from the other side, and Clyde comes close and then wanders off. By turns the ghosts chase him and scatter to their corners. A ghost that reaches Pac-Man's cell catches him and he loses one of his 3 lives; with none left the game is over. A power pellet turns the ghosts blue for a while: blue ghosts are slow and harmless, and eating them is worth 200, 400, 800 and 1600 points. The tunnel in the middle row leads from one side of the maze to the other. The score is the points."
    let question = "Which way should Pac-Man go this tick, to score as many points as possible without being caught by a ghost?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: never choose an option in which a ghost catches Pac-Man — on this move, within 2 ticks, or in a trap with no way out; each costs a life. Second: avoid a way that a ghost can cut off, and do not walk toward a ghost that is closing in and near. Third: while the ghosts are blue, chasing a blue ghost that is within reach comes before eating dots: it is worth 200 to 1600 points. Fourth: eat dots — eating one now is good, more dots in the next cells is better, and a nearer next dot is better than a farther one. A ghost that is far away is no reason to turn away from the dots. Staying put and turning back gain nothing unless they keep Pac-Man away from a ghost."
    let controls = "方向键转弯（可以提前按，到了路口自己拐）· 不按就一直走"

    fileprivate var world = PacmanWorld(seed: 1)
    /// The maze before the last tick, for the picture to glide from.
    fileprivate var previous = PacmanWorld(seed: 1)
    private(set) var ticked = Date.distantPast
    /// What each option does: a direction (0 up, 1 left, 2 down, 3 right) or -1, stay put.
    private var moves: [Int] = []
    private var person = false
    /// A person's turn, pressed early, kept until the maze allows it.
    private var queued: Int?
    /// The best score this board has seen, across games.
    private var best = 0

    var clock: Double? { person ? 0.16 : nil }
    func prepare(person: Bool) { self.person = person }

    var over: Bool { world.phase == .over }
    var score: Int { world.score }
    var status: String {
        (over ? "游戏结束 · " : "") + "第 \(world.level) 关 · 得分 \(world.score) · 命 \(String(repeating: "♥", count: max(world.lives, 0))) · 剩 \(world.left) 颗豆"
    }

    var situation: String {
        let w = world
        var parts = ["level \(w.level)", "score \(w.score)", "\(w.lives) li\(w.lives == 1 ? "fe" : "ves") left", PacmanWords.dotsLeft(w.left)]
        if w.blue > 0 {
            parts.append("the ghosts are blue for \(w.blue) more tick\(w.blue == 1 ? "" : "s")")
        } else if w.chasing {
            parts.append("the ghosts are chasing Pac-Man" + (w.wave < w.waves.count ? " (they scatter to their corners in \(w.waveLeft) ticks)" : ""))
        } else {
            parts.append("the ghosts are scattering to their corners (they chase again in \(w.waveLeft) ticks)")
        }
        parts.append("Pac-Man is heading \(PacmanMaze.names[w.heading])")
        let home = (0..<4).filter { w.ghosts[$0].mode == .pen }.map { PacmanMaze.ghostNames[$0] }
        if !home.isEmpty { parts.append(PacmanWords.list(home) + (home.count == 1 ? " is" : " are") + " still in the ghost house") }
        return parts.joined(separator: "; ")
    }

    /// The maze as text, for a player that can read one.
    var position: String {
        var rows = PacmanMaze.plan.map { row in row.map { ch -> Character in ch == "#" || ch == "x" ? "#" : ch == "-" ? "-" : " " } }
        for c in 0..<PacmanMaze.count where world.has(c) {
            rows[PacmanMaze.y(c)][PacmanMaze.x(c)] = PacmanMaze.tiles[c] == .pellet ? "o" : "."
        }
        for (i, ghost) in world.ghosts.enumerated() {
            let mark: Character = ghost.mode == .eyes || ghost.mode == .entering ? "e" : ghost.blue ? Character(["b", "p", "i", "c"][i]) : Character(["B", "P", "I", "C"][i])
            rows[PacmanMaze.y(ghost.cell)][PacmanMaze.x(ghost.cell)] = mark
        }
        rows[PacmanMaze.y(world.pac)][PacmanMaze.x(world.pac)] = "@"
        return rows.map { String($0) }.joined(separator: "\n")
            + "\n(@ is Pac-Man; B Blinky, P Pinky, I Inky, C Clyde, lower case when blue; e a ghost's eyes going home; . dot, o power pellet, # wall, - the ghost house door. Row 10 wraps through the tunnel.)"
    }

    var grid: [[JevCell]] {
        let wall = Color(red: 0.13, green: 0.2, blue: 0.85), floor = Color(red: 0.02, green: 0.02, blue: 0.06)
        var cells = PacmanMaze.plan.map { row in
            row.map { ch -> JevCell in JevCell(colour: ch == "#" ? wall : ch == "x" ? .black : floor, text: ch == "-" ? "—" : "", ink: .pink) }
        }
        for c in 0..<PacmanMaze.count where world.has(c) {
            cells[PacmanMaze.y(c)][PacmanMaze.x(c)] = JevCell(colour: floor, text: PacmanMaze.tiles[c] == .pellet ? "●" : "·", ink: Color(red: 1, green: 0.85, blue: 0.7))
        }
        for (i, ghost) in world.ghosts.enumerated() {
            let ink = ghost.mode == .eyes || ghost.mode == .entering ? Color.white : ghost.blue ? Color.blue : PacmanArt.colours[i]
            cells[PacmanMaze.y(ghost.cell)][PacmanMaze.x(ghost.cell)] = JevCell(colour: floor, text: "ᗣ", ink: ink, big: true)
        }
        cells[PacmanMaze.y(world.pac)][PacmanMaze.x(world.pac)] = JevCell(colour: floor, text: "ᗧ", ink: .yellow, big: true)
        return cells
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        world = PacmanWorld(seed: seed)
        previous = world
        ticked = .distantPast
        queued = nil
        moves = []
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        guard world.phase == .play else {
            moves = [-1]
            return [JevOption(id: "p01", label: PacmanWords.waiting(world), merit: 0, move: 0, title: "等一下")]
        }
        moves = (0..<4).filter { PacmanMaze.link[world.pac * 4 + $0] >= 0 } + [-1]
        return moves.enumerated().map { index, move in judge(move, index) }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move), !over else { return }
        previous = world
        world.step(moves[option.move])
        best = max(best, world.score)
        ticked = Date()
    }

    /// One way to go, measured and put in words.
    private func judge(_ move: Int, _ index: Int) -> JevOption {
        let now = world
        var next = now
        let tick = next.step(move)
        let id = String(format: "p%02d", index + 1)
        let arrow = move < 0 ? "停住" : ["向上", "向左", "向下", "向右"][move]
        let back = move >= 0 && move == (now.heading + 2) % 4
        let doing = move < 0 ? "stay put" : "go \(PacmanMaze.names[move])" + (back ? " (turning back)" : "")

        if tick.died {
            let end = now.lives <= 1 ? "loses his last life: the game ends" : "loses a life"
            return JevOption(id: id, label: "\(doing): runs into \(PacmanMaze.ghostNames[tick.by]): Pac-Man is caught and \(end)",
                             merit: -10_000, move: index, title: "\(arrow) · 撞上\(PacmanMaze.ghostHan[tick.by])鬼！")
        }

        // What a move leaves: how long he surely lives, what is near, what is eaten.
        let life = next.lasts(PacmanWorld.foresight)
        let hunters = next.hunters(from: next.pac)
        let nearest = hunters.first
        let was = nearest.flatMap { now.gap($0.ghost, from: now.pac) }
        let ahead = move < 0 ? 0 : now.trail(next.pac, move, 5)
        let dot = next.nearestFood(from: next.pac)
        let pellet = next.nearestFood(from: next.pac, pellets: true)
        let room = next.room(limit: PacmanWorld.roomy)
        let prey = next.prey(from: next.pac)
        let caught = hunters.prefix(2).map { PacmanMaze.ghostNames[$0.ghost] }

        var parts: [String] = []
        if life < 2 {
            parts.append("then \(PacmanWords.list(caught.isEmpty ? ["a ghost"] : caught)) catch\(caught.count == 1 ? "es" : "") him within 2 ticks whatever he does: he loses a life")
        } else if life < PacmanWorld.foresight {
            parts.append("a trap: \(PacmanWords.list(caught.isEmpty ? ["the ghosts"] : caught)) close\(caught.count == 1 ? "s" : "") in from every side and catch\(caught.count == 1 ? "es" : "") him within \(life + 1) ticks whatever he does: he loses a life")
        }
        for ghost in tick.eaten {
            parts.append("eats the blue \(PacmanMaze.ghostNames[ghost]) (\(PacmanWords.worth(of: ghost, in: tick)) points)")
        }
        if tick.pellet {
            parts.append("eats a power pellet (50 points): the ghosts turn blue for \(next.fright) ticks")
        } else if tick.dot {
            parts.append("eats a dot (10 points)")
        }
        if move >= 0 {
            let more = ahead - (tick.dot || tick.pellet ? 1 : 0)
            if tick.dot || tick.pellet {
                parts.append(more == 0 ? "no more dots in the 4 cells after it" : "\(more) more dot\(more == 1 ? "" : "s") in the 4 cells after it")
            } else {
                parts.append(ahead == 0 ? "no dots in the next 5 cells this way" : "\(ahead) dot\(ahead == 1 ? "" : "s") in the next 5 cells this way")
            }
        } else {
            parts.append("eats nothing")
        }
        if let dot { parts.append("the nearest dot left is then " + PacmanWords.steps(dot) + " away") }
        if let nearest {
            let name = PacmanMaze.ghostNames[nearest.ghost]
            if nearest.steps > 10 {
                parts.append("the nearest ghost, \(name), is far away (more than 10 steps)")
            } else {
                let trend = was.map { nearest.steps < $0 ? "closing in" : nearest.steps > $0 ? "falling back" : "keeping its distance" } ?? "coming out of the house"
                parts.append("the nearest ghost, \(name), is then \(PacmanWords.steps(nearest.steps)) away and \(trend)")
            }
        } else if next.blue == 0 {
            parts.append("no ghost is out hunting")
        }
        if life >= PacmanWorld.foresight, room.cells < PacmanWorld.roomy, let by = room.by, (nearest?.steps ?? 99) <= 8 {
            parts.append("the way on can be cut off by \(PacmanMaze.ghostNames[by]) (risky)")
        }
        if next.blue > 0, let prey {
            // Said as a chase or not, as Snake says closer to the food: a reader should not have to compare numbers across options.
            let name = PacmanMaze.ghostNames[prey.ghost], worth = 200 << min(next.chain, 3)
            let reach = prey.steps * 3 <= next.blue * 2
            let then = PacmanWords.steps(prey.steps) + " away, \(next.blue) tick\(next.blue == 1 ? "" : "s") of blue left"
            if !now.ghosts[prey.ghost].blue {
                // Blue from this move on: no chase yet, only how far.
                parts.append("the nearest blue ghost, \(name), is then \(then)" + (reach ? ": within reach, worth \(worth) points" : ""))
            } else if prey.steps < PacmanMaze.far(now.pac, now.ghosts[prey.ghost].cell) {
                parts.append(reach ? "chases the blue \(name) (then \(then)): within reach, worth \(worth) points" : "chases the blue \(name) (then \(then)): probably out of reach")
            } else {
                parts.append("turns away from the blue ghosts (the nearest, \(name), then \(then))")
            }
        }
        if let pellet, !tick.pellet {
            parts.append("a power pellet is " + PacmanWords.steps(pellet) + " away")
        }

        // The evaluator: its life first, then what is near, then what is eaten.
        var merit = 0.0
        if life < 2 { merit -= 9_000 } else if life < PacmanWorld.foresight { merit -= 7_000 - 400 * Double(life) }
        let worth = tick.points - (tick.pellet ? 50 : 0)
        merit += Double(worth)
        if tick.pellet {
            // A pellet is worth what it can catch: kept for when a ghost is near.
            let near = hunters.filter { $0.steps <= 8 }.count
            merit += near > 0 ? 40 + 60 * Double(near) : (next.left < 12 ? 20 : -30)
        }
        merit -= 2.2 * Double(dot ?? 0)
        merit += 1.2 * Double(ahead)
        for hunter in hunters where hunter.steps < 7 {
            merit -= pow(Double(7 - hunter.steps), 2) * (hunter.steps <= 2 ? 9 : 5)
        }
        if room.cells < PacmanWorld.roomy { merit -= Double(PacmanWorld.roomy - room.cells) * 12 }
        if let prey, prey.steps * 3 <= next.blue * 2 { merit += max(0, 160 - 14 * Double(prey.steps)) }
        if move < 0 { merit -= 6 } else if back { merit -= 2 }

        var title = arrow
        if life < 2 { title += " · 会被抓！" }
        else if life < PacmanWorld.foresight { title += " · 死路" }
        else if !tick.eaten.isEmpty { title += " · 吃掉蓝鬼 +\(worth)" }
        else if tick.pellet { title += " · 能量豆" }
        else {
            title += move < 0 ? " · 不动" : " · \(ahead) 颗豆"
            if next.blue > 0, let prey { title += " · 蓝鬼 \(prey.steps) 步" }
            else if let nearest { title += nearest.steps > 10 ? " · 鬼在远处" : " · 鬼在 \(nearest.steps) 步外" }
        }
        return JevOption(id: id, label: doing + ": " + parts.joined(separator: "; "), merit: merit, move: index, title: title)
    }

    // MARK: Played by a person

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let ways: [JevPress: Int] = [.up: 0, .left: 1, .down: 2, .right: 3]
        if let key = pressed.latest(of: [.up, .left, .down, .right], held: held) { queued = ways[key] }
        func option(_ way: Int) -> JevOption? {
            moves.firstIndex(of: way).flatMap { index in options.first { $0.move == index } }
        }
        // The turn asked for, as soon as the maze allows it; until then straight on; at a wall, stop.
        if let turn = queued, let chosen = option(turn) { queued = nil; return .choose(chosen) }
        if let chosen = option(world.heading) ?? option(-1) { return .choose(chosen) }
        return options.first.map { .choose($0) } ?? .nothing
    }
}

// MARK: - The maze

fileprivate enum PacmanMaze {
    /// The arcade's maze, taken in: `#` wall, `x` outside it, `.` dot, `o` power pellet,
    /// blank a corridor without a dot, `P` Pac-Man's start, `-` the ghost house door, `_` inside the house.
    static let plan: [[Character]] = [
        "#####################",
        "#.........#.........#",
        "#o##.####.#.####.##o#",
        "#...................#",
        "#.##.#.#######.#.##.#",
        "#....#....#....#....#",
        "####.####.#.####.####",
        "xxx#.#.........#.#xxx",
        "####.#.###-###.#.####",
        "    ...#_____#...    ",
        "####.#.#######.#.####",
        "xxx#.#.........#.#xxx",
        "####.#.#######.#.####",
        "#.........#.........#",
        "#.##.####.#.####.##.#",
        "#o.#......P......#.o#",
        "##.#.#.#######.#.#.##",
        "#....#....#....#....#",
        "#.#######.#.#######.#",
        "#...................#",
        "#####################",
    ].map { Array($0) }

    static let width = 21, height = 21, tunnel = 9, houseRow = 9
    static let count = width * height

    enum Tile { case wall, void, open, dot, pellet, house, door }
    static let tiles: [Tile] = plan.flatMap { row in
        row.map { ch -> Tile in
            switch ch {
            case "#": return .wall
            case "x": return .void
            case ".": return .dot
            case "o": return .pellet
            case "_": return .house
            case "-": return .door
            default: return .open
            }
        }
    }

    static func at(_ x: Int, _ y: Int) -> Int { y * width + x }
    static func x(_ c: Int) -> Int { c % width }
    static func y(_ c: Int) -> Int { c / width }

    static let start = at(10, 15), exit = at(10, 7), door = at(10, 8), home = at(10, 9)
    /// Where each ghost starts: Blinky outside the door, the others in the house.
    static let pens = [at(10, 7), at(10, 9), at(8, 9), at(12, 9)]
    /// Each ghost's corner, outside the maze, where it heads when scattering.
    static let corners: [(x: Int, y: Int)] = [(18, -3), (2, -3), (20, 23), (0, 23)]
    static let ghostNames = ["Blinky", "Pinky", "Inky", "Clyde"]
    static let ghostHan = ["红", "粉", "青", "橙"]
    static let names = ["up", "left", "down", "right"]
    static let dx = [0, -1, 0, 1], dy = [-1, 0, 1, 0]

    static let open: [Bool] = tiles.map { $0 == .open || $0 == .dot || $0 == .pellet }
    /// The corridor cell a step from each cell each way, through the tunnel; -1 for a wall.
    static let link: [Int] = (0..<count).flatMap { c in
        (0..<4).map { d -> Int in
            var nx = x(c) + dx[d]
            let ny = y(c) + dy[d]
            guard ny >= 0, ny < height else { return -1 }
            if nx < 0 || nx >= width {
                guard ny == tunnel else { return -1 }
                nx = (nx + width) % width
            }
            return open[at(nx, ny)] ? at(nx, ny) : -1
        }
    }
    static let inTunnel: [Bool] = (0..<count).map { y($0) == tunnel && (x($0) < 4 || x($0) > 16) }
    static let food: [Int] = (0..<count).filter { tiles[$0] == .dot || tiles[$0] == .pellet }

    /// Steps between any two corridor cells, the tunnel included: 255 where there is no way.
    static let steps: [UInt8] = {
        var table = [UInt8](repeating: 255, count: count * count)
        for source in 0..<count where open[source] {
            table[source * count + source] = 0
            var queue = [source], head = 0
            while head < queue.count {
                let c = queue[head]; head += 1
                let d = table[source * count + c]
                for way in 0..<4 {
                    let n = link[c * 4 + way]
                    if n >= 0, table[source * count + n] == 255 { table[source * count + n] = d + 1; queue.append(n) }
                }
            }
        }
        return table
    }()
    static func far(_ a: Int, _ b: Int) -> Int { Int(steps[a * count + b]) }

    /// Steps from a cell in the house or its door out to the corridor above the door.
    static func outSteps(_ c: Int) -> Int {
        c == exit ? 0 : c == door ? 1 : abs(x(c) - 10) + 2
    }
}

// MARK: - The rules

fileprivate struct PacmanGhost {
    enum Mode { case pen, leaving, roaming, eyes, entering }
    var cell: Int
    var dir: Int
    var mode: Mode
    var blue = false
    /// How far along its next step it is: a ghost slower than Pac-Man misses a tick now and then.
    var pace = 0.0
    /// Told to turn round: the scatter and chase turned over, or the ghosts went blue.
    var turn = false
    /// The cell it passed through in the last tick, when it took two steps (eyes are quick).
    var via = -1
}

fileprivate struct PacmanTick {
    var died = false, by = -1
    var dot = false, pellet = false
    var eaten: [Int] = [], worths: [Int] = []
    var points = 0
}

/// The maze as it stands. A value: a look ahead is a copy played on, dice and all.
fileprivate struct PacmanWorld {
    enum Phase: Equatable { case ready(Int), play, eating(Int), dying(Int), clearing(Int), over }
    static let readyTicks = 6, eatTicks = 4, dyingTicks = 10, clearTicks = 12, startLives = 3
    /// How far ahead the evaluator looks for Pac-Man's life (eight ticks: six let a quarter of the
    /// heuristic's games end inside 3000 ticks, eight none), and the room it likes around him.
    static let foresight = 8, roomy = 6

    var food: [UInt64] = []
    var left = 0
    var pac = PacmanMaze.start, heading = 1, moved = false
    var ghosts: [PacmanGhost] = []
    var score = 0, lives = PacmanWorld.startLives, level = 1
    /// Ticks of play since this life or level began, and ticks all told.
    var tick = 0, total = 0
    var wave = 0, waveLeft = 0
    var blue = 0, chain = 0
    var phase: Phase = .ready(PacmanWorld.readyTicks)
    var dice: JevDice
    var bonus = false
    /// The ghost just eaten, where and for how much: shown while the game holds still.
    var eaten: (cell: Int, points: Int)?
    /// The ghost that caught Pac-Man.
    var caught = -1
    var cleared = 0, deaths = 0, ghostsEaten = 0

    init(seed: UInt64) {
        dice = JevDice(seed: seed)
        fill()
        restart()
    }

    private static let speeds = [0.75, 0.8, 0.85, 0.9]
    private static let schedules = [[28, 100, 28, 100, 20, 100, 20], [20, 120, 20, 120, 12, 120, 8]]
    private static let leaving = [[0, 2, 14, 28], [0, 2, 8, 16], [0, 1, 4, 8]]
    /// A ghost's pace, in cells a tick: Pac-Man's is one.
    var speed: Double { Self.speeds[min(level, 4) - 1] }
    var fright: Int { max(12, 36 - 6 * (level - 1)) }
    /// Scatter and chase by turns, in ticks; after the last, chase for good.
    var waves: [Int] { Self.schedules[level == 1 ? 0 : 1] }
    /// The tick of this life each ghost leaves the house.
    var releases: [Int] { Self.leaving[min(level, 3) - 1] }
    var chasing: Bool { wave % 2 == 1 || wave >= waves.count }

    func has(_ c: Int) -> Bool { food[c >> 6] & (1 << UInt64(c & 63)) != 0 }
    private mutating func take(_ c: Int) { food[c >> 6] &= ~(1 << UInt64(c & 63)) }

    mutating func fill() {
        food = Array(repeating: 0, count: (PacmanMaze.count + 63) / 64)
        for c in PacmanMaze.food { food[c >> 6] |= 1 << UInt64(c & 63) }
        left = PacmanMaze.food.count
    }

    /// Everybody back to the start: a new life or a new level.
    mutating func restart() {
        pac = PacmanMaze.start; heading = 1; moved = false
        tick = 0; wave = 0; waveLeft = waves[0]; blue = 0; chain = 0; eaten = nil
        ghosts = (0..<4).map { i in
            PacmanGhost(cell: PacmanMaze.pens[i], dir: i == 0 ? (dice.below(2) == 0 ? 1 : 3) : 0, mode: i == 0 ? .roaming : .pen)
        }
    }

    /// One tick: Pac-Man moves (a direction, or -1 to stay), eats, and the ghosts move after him.
    @discardableResult
    mutating func step(_ move: Int) -> PacmanTick {
        var out = PacmanTick()
        total += 1
        moved = false
        for i in ghosts.indices { ghosts[i].via = -1 }
        switch phase {
        case .ready(let k):
            phase = k > 1 ? .ready(k - 1) : .play
            return out
        case .eating(let k):
            if k > 1 { phase = .eating(k - 1) } else { phase = .play; eaten = nil }
            return out
        case .dying(let k):
            if k > 1 { phase = .dying(k - 1) } else if lives <= 0 { phase = .over } else { restart(); phase = .ready(Self.readyTicks) }
            return out
        case .clearing(let k):
            if k > 1 { phase = .clearing(k - 1) } else { level += 1; fill(); restart(); phase = .ready(Self.readyTicks) }
            return out
        case .over:
            return out
        case .play:
            break
        }
        if move >= 0 {
            let to = PacmanMaze.link[pac * 4 + move]
            if to >= 0 { pac = to; moved = true; heading = move }
        }
        if has(pac) {
            take(pac); left -= 1
            if PacmanMaze.tiles[pac] == .pellet { gain(50, &out); out.pellet = true; frighten() } else { gain(10, &out); out.dot = true }
        }
        for i in ghosts.indices where ghosts[i].mode == .roaming && ghosts[i].cell == pac { meet(i, &out) }
        if !out.died {
            for i in ghosts.indices {
                advance(i, &out)
                if out.died { break }
            }
        }
        if out.died {
            lives -= 1; deaths += 1; caught = out.by
            phase = .dying(Self.dyingTicks)
            return out
        }
        tick += 1
        if blue > 0 {
            blue -= 1
            if blue == 0 { chain = 0; for i in ghosts.indices { ghosts[i].blue = false } }
        } else if wave < waves.count {
            waveLeft -= 1
            if waveLeft <= 0 {
                wave += 1
                waveLeft = wave < waves.count ? waves[wave] : 0
                for i in ghosts.indices where ghosts[i].mode == .roaming { ghosts[i].turn = true }
            }
        }
        let release = releases
        for i in 1..<4 where ghosts[i].mode == .pen && tick >= release[i] { ghosts[i].mode = .leaving }
        if left == 0 { phase = .clearing(Self.clearTicks); cleared += 1 }
        else if !out.eaten.isEmpty { phase = .eating(Self.eatTicks) }
        return out
    }

    private mutating func gain(_ points: Int, _ out: inout PacmanTick) {
        if !bonus, score + points >= 10_000 { bonus = true; lives += 1 }
        score += points; out.points += points
    }

    /// A power pellet: every ghost not already eyes turns blue, and those about turn round.
    private mutating func frighten() {
        blue = fright; chain = 0
        for i in ghosts.indices where ghosts[i].mode != .eyes && ghosts[i].mode != .entering {
            ghosts[i].blue = true
            if ghosts[i].mode == .roaming { ghosts[i].turn = true }
        }
    }

    /// Pac-Man and a ghost in one cell: the ghost is eaten if it is blue, and otherwise he is caught.
    private mutating func meet(_ i: Int, _ out: inout PacmanTick) {
        if ghosts[i].blue {
            let points = 200 << min(chain, 3)
            chain += 1; ghostsEaten += 1
            gain(points, &out)
            ghosts[i].blue = false; ghosts[i].mode = .eyes; ghosts[i].pace = 0; ghosts[i].turn = false
            eaten = (pac, points)
            out.eaten.append(i); out.worths.append(points)
        } else if !out.died {
            out.died = true; out.by = i
        }
    }

    /// A ghost's steps this tick, as many as its pace has earned.
    private mutating func advance(_ i: Int, _ out: inout PacmanTick) {
        let pace: Double
        switch ghosts[i].mode {
        case .pen: return
        case .eyes, .entering: pace = 2
        case .leaving: pace = speed * 0.8
        case .roaming: pace = ghosts[i].blue || PacmanMaze.inTunnel[ghosts[i].cell] ? 0.5 : speed
        }
        ghosts[i].pace += pace
        var first = true
        while ghosts[i].pace >= 1 {
            ghosts[i].pace -= 1
            if !first { ghosts[i].via = ghosts[i].cell }
            first = false
            walk(i)
            if ghosts[i].mode == .roaming, ghosts[i].cell == pac {
                meet(i, &out)
                if out.died || ghosts[i].mode == .eyes { break }
            }
        }
    }

    /// One step of one ghost, by its own rule.
    private mutating func walk(_ i: Int) {
        let cell = ghosts[i].cell, x = PacmanMaze.x(cell), y = PacmanMaze.y(cell)
        switch ghosts[i].mode {
        case .pen:
            return
        case .leaving:
            // Across the house to under the door, then up and out.
            if y == PacmanMaze.houseRow && x != 10 { ghosts[i].dir = x < 10 ? 3 : 1; ghosts[i].cell += x < 10 ? 1 : -1 }
            else { ghosts[i].dir = 0; ghosts[i].cell -= PacmanMaze.width }
            if ghosts[i].cell == PacmanMaze.exit {
                ghosts[i].mode = .roaming; ghosts[i].turn = false
                ghosts[i].dir = dice.below(2) == 0 ? 1 : 3
            }
        case .entering:
            ghosts[i].dir = 2; ghosts[i].cell += PacmanMaze.width
            if ghosts[i].cell == PacmanMaze.home { ghosts[i].mode = .leaving; ghosts[i].blue = false }
        case .eyes:
            if cell == PacmanMaze.exit { ghosts[i].mode = .entering; ghosts[i].dir = 2; ghosts[i].cell = PacmanMaze.door; return }
            let way = aim(from: cell, heading: ghosts[i].dir, to: (10, 7))
            ghosts[i].dir = way; ghosts[i].cell = PacmanMaze.link[cell * 4 + way]
        case .roaming:
            if ghosts[i].turn {
                ghosts[i].turn = false
                let back = (ghosts[i].dir + 2) % 4, to = PacmanMaze.link[cell * 4 + back]
                if to >= 0 { ghosts[i].dir = back; ghosts[i].cell = to; return }
            }
            let way: Int
            if ghosts[i].blue {
                // A blue ghost turns at random at a crossing: the seed's dice.
                let back = (ghosts[i].dir + 2) % 4
                var open = 0
                for d in 0..<4 where d != back && PacmanMaze.link[cell * 4 + d] >= 0 { open += 1 }
                if open == 0 { way = back } else {
                    var pick = dice.below(open), chosen = back
                    for d in 0..<4 where d != back && PacmanMaze.link[cell * 4 + d] >= 0 {
                        if pick == 0 { chosen = d; break }
                        pick -= 1
                    }
                    way = chosen
                }
            } else {
                way = aim(from: cell, heading: ghosts[i].dir, to: target(i))
            }
            ghosts[i].dir = way; ghosts[i].cell = PacmanMaze.link[cell * 4 + way]
        }
    }

    /// The arcade's rule: never straight back; of the ways left, the one whose next
    /// cell is nearest the target as the crow flies; ties go up, left, down, right.
    func aim(from cell: Int, heading: Int, to target: (x: Int, y: Int)) -> Int {
        let back = (heading + 2) % 4
        var best = -1, bestDistance = Int.max
        for d in 0..<4 where d != back {
            let n = PacmanMaze.link[cell * 4 + d]
            guard n >= 0 else { continue }
            let ex = PacmanMaze.x(n) - target.x, ey = PacmanMaze.y(n) - target.y
            if ex * ex + ey * ey < bestDistance { bestDistance = ex * ex + ey * ey; best = d }
        }
        return best >= 0 ? best : back
    }

    /// Where each ghost is headed: its corner when scattering; when chasing, Blinky
    /// Pac-Man himself, Pinky four cells ahead of him, Inky Blinky's reflection
    /// through the cell two ahead of him, Clyde him while far and his corner once near.
    func target(_ i: Int) -> (x: Int, y: Int) {
        guard chasing else { return PacmanMaze.corners[i] }
        let px = PacmanMaze.x(pac), py = PacmanMaze.y(pac), hx = PacmanMaze.dx[heading], hy = PacmanMaze.dy[heading]
        switch i {
        case 0: return (px, py)
        case 1: return (px + 4 * hx, py + 4 * hy)
        case 2:
            let bx = PacmanMaze.x(ghosts[0].cell), by = PacmanMaze.y(ghosts[0].cell)
            return (2 * (px + 2 * hx) - bx, 2 * (py + 2 * hy) - by)
        default:
            let cx = PacmanMaze.x(ghosts[3].cell), cy = PacmanMaze.y(ghosts[3].cell)
            return (cx - px) * (cx - px) + (cy - py) * (cy - py) > 36 ? (px, py) : PacmanMaze.corners[3]
        }
    }

    // MARK: Measures

    /// Ticks Pac-Man surely stays alive, looking `depth` ahead over all his moves.
    func lasts(_ depth: Int) -> Int {
        guard depth > 0 else { return 0 }
        switch phase {
        case .dying, .over: return 0
        case .clearing: return depth
        case .ready, .eating:
            var next = self
            next.step(-1)
            return next.lasts(depth)
        case .play: break
        }
        var best = 0
        for k in 0..<5 {
            let move = k == 4 ? -1 : (heading + [0, 1, 3, 2][k]) % 4
            if move >= 0 && PacmanMaze.link[pac * 4 + move] < 0 { continue }
            var next = self
            if next.step(move).died { continue }
            let got = 1 + next.lasts(depth - 1)
            if got >= depth { return depth }
            best = max(best, got)
        }
        return best
    }

    /// Steps from a cell to a ghost that can hurt him: out and not blue, or on its way out of the house.
    func gap(_ i: Int, from c: Int) -> Int? {
        let ghost = ghosts[i]
        guard !ghost.blue else { return nil }
        switch ghost.mode {
        case .roaming: return PacmanMaze.far(c, ghost.cell)
        case .leaving: return PacmanMaze.far(c, PacmanMaze.exit) + PacmanMaze.outSteps(ghost.cell)
        default: return nil
        }
    }

    /// The ghosts that can hurt him, nearest first.
    func hunters(from c: Int) -> [(ghost: Int, steps: Int)] {
        (0..<4).compactMap { i in gap(i, from: c).map { (i, $0) } }.sorted { $0.steps < $1.steps || ($0.steps == $1.steps && $0.ghost < $1.ghost) }
    }

    /// The nearest blue ghost out in the maze.
    func prey(from c: Int) -> (ghost: Int, steps: Int)? {
        (0..<4).filter { ghosts[$0].blue && ghosts[$0].mode == .roaming }
            .map { (ghost: $0, steps: PacmanMaze.far(c, ghosts[$0].cell)) }
            .min { $0.steps < $1.steps }
    }

    /// Steps to the nearest dot (or power pellet) left.
    func nearestFood(from c: Int, pellets: Bool = false) -> Int? {
        var best = Int.max
        for (w, word) in food.enumerated() where word != 0 {
            var bits = word
            while bits != 0 {
                let cell = w * 64 + bits.trailingZeroBitCount
                bits &= bits - 1
                if pellets && PacmanMaze.tiles[cell] != .pellet { continue }
                best = min(best, PacmanMaze.far(c, cell))
            }
        }
        return best == Int.max ? nil : best
    }

    /// The most dots on a path of `length` cells from `c`, arrived at going `way`, never turning back.
    func trail(_ c: Int, _ way: Int, _ length: Int) -> Int {
        let here = has(c) ? 1 : 0
        guard length > 1 else { return here }
        var best = 0
        for d in 0..<4 where d != (way + 2) % 4 {
            let n = PacmanMaze.link[c * 4 + d]
            if n >= 0 { best = max(best, trail(n, d, length - 1)) }
        }
        return here + best
    }

    /// When a ghost could be at a cell at the earliest, in ticks: straight there at its
    /// best pace, the blue ones once they are blue no more. Eyes are not counted.
    func arrival(_ i: Int, at c: Int) -> Double {
        let ghost = ghosts[i]
        switch ghost.mode {
        case .roaming:
            let steps = Double(PacmanMaze.far(ghost.cell, c)) / speed
            return ghost.blue ? max(Double(blue), steps) : steps
        case .leaving:
            return Double(blue) * (ghost.blue ? 1 : 0) + Double(PacmanMaze.outSteps(ghost.cell) + PacmanMaze.far(PacmanMaze.exit, c)) / speed
        case .pen:
            return Double(max(0, releases[i] - tick)) + Double(4 + PacmanMaze.far(PacmanMaze.exit, c)) / speed
        case .eyes, .entering:
            return .infinity
        }
    }

    /// The cells Pac-Man can reach a tick before any ghost could, counted up to
    /// `limit`, and the ghost that shuts him in most.
    func room(limit: Int) -> (cells: Int, by: Int?) {
        var seen = [Bool](repeating: false, count: PacmanMaze.count)
        var queue = [(pac, 0)], head = 0, blockers = [0, 0, 0, 0]
        seen[pac] = true
        while head < queue.count, queue.count < limit {
            let (c, d) = queue[head]; head += 1
            for way in 0..<4 {
                let n = PacmanMaze.link[c * 4 + way]
                guard n >= 0, !seen[n] else { continue }
                seen[n] = true
                var first = Double.infinity, who = -1
                for i in 0..<4 {
                    let a = arrival(i, at: n)
                    if a < first { first = a; who = i }
                }
                if Double(d + 1) + 1 <= first { queue.append((n, d + 1)) } else if who >= 0 { blockers[who] += 1 }
            }
        }
        let most = blockers.indices.max { blockers[$0] < blockers[$1] }!
        return (min(queue.count, limit), blockers[most] > 0 ? most : nil)
    }
}

/// Words shared by the options and the position.
fileprivate enum PacmanWords {
    static func steps(_ n: Int) -> String {
        n > 10 ? "more than 10 steps" : n == 1 ? "1 step" : "\(n) steps"
    }
    static func list(_ names: [String]) -> String {
        names.count <= 1 ? names.first ?? "" : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
    static func dotsLeft(_ n: Int) -> String {
        n > 100 ? "many dots left (more than 100)" : n >= 30 ? "some dots left (fewer than 100)" : "only \(n) dot\(n == 1 ? "" : "s") left"
    }
    static func worth(of ghost: Int, in tick: PacmanTick) -> Int {
        tick.eaten.firstIndex(of: ghost).map { tick.worths[$0] } ?? 200
    }
    /// The one option while the game holds still.
    static func waiting(_ w: PacmanWorld) -> String {
        switch w.phase {
        case .ready: return "wait: Pac-Man and the ghosts are getting ready"
        case .eating: return "wait: the eaten ghost's eyes set off home"
        case .dying: return "wait: Pac-Man was caught"
        case .clearing: return "wait: the level is cleared"
        default: return "wait"
        }
    }
}

// MARK: - The picture

extension JevPacman: JevPainted {
    var aspect: Double { 0.9 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = PacmanScene(before: previous, after: world, t: t, since: since, now: now, best: max(best, world.score))
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

/// The walls, traced once from the plan, in cells: a line round every wall a
/// little way in from the corridor, and a second inside it — the neon tubes.
fileprivate enum PacmanArt {
    static let colours: [Color] = [Color(red: 1, green: 0.16, blue: 0.14), Color(red: 1, green: 0.62, blue: 0.86),
                                   Color(red: 0.22, green: 0.93, blue: 1), Color(red: 1, green: 0.68, blue: 0.24)]
    static let rgb: [(Double, Double, Double)] = [(1, 0.16, 0.14), (1, 0.62, 0.86), (0.22, 0.93, 1), (1, 0.68, 0.24)]

    static let outer = outline(inset: 0.2, radius: 0.34)
    static let inner = outline(inset: 0.36, radius: 0.18)
    /// The walls standing in the maze, inside their inner line, for a faint fill; the frame round it stays dark.
    static let body = outline(inset: 0.36, radius: 0.18, blocks: true)

    /// Loops of grid corners round every stretch of wall, the corridor on the left
    /// hand, corners only. Off the sides the maze is wall, but for the tunnel.
    static let loops: [[(x: Int, y: Int, dir: Int)]] = {
        let W = PacmanMaze.width, H = PacmanMaze.height
        func solid(_ x: Int, _ y: Int) -> Bool {
            if x < -3 || x > W + 2 || y < 0 || y >= H { return true }
            if x < 0 || x >= W { return y != PacmanMaze.tunnel }
            let tile = PacmanMaze.tiles[PacmanMaze.at(x, y)]
            return tile == .wall || tile == .void
        }
        // Edges run east, south, west, north (0…3), each with the wall on its right.
        var edges: [(x: Int, y: Int, dir: Int)] = []
        for y in -1...H {
            for x in -4...(W + 3) where solid(x, y) {
                if !solid(x, y - 1) { edges.append((x, y, 0)) }
                if !solid(x + 1, y) { edges.append((x + 1, y, 1)) }
                if !solid(x, y + 1) { edges.append((x + 1, y + 1, 2)) }
                if !solid(x - 1, y) { edges.append((x, y + 1, 3)) }
            }
        }
        let step = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        func key(_ x: Int, _ y: Int) -> Int { (y + 8) * 64 + (x + 8) }
        var starting: [Int: [Int]] = [:]
        for (index, edge) in edges.enumerated() { starting[key(edge.x, edge.y), default: []].append(index) }
        var used = [Bool](repeating: false, count: edges.count)
        var loops: [[(x: Int, y: Int, dir: Int)]] = []
        for first in edges.indices where !used[first] {
            var loop: [(x: Int, y: Int, dir: Int)] = []
            var current = first
            while !used[current] {
                used[current] = true
                let edge = edges[current]
                if loop.last?.dir != edge.dir { loop.append(edge) }
                let end = (edge.x + step[edge.dir].0, edge.y + step[edge.dir].1)
                // Where two walls touch at a corner, keep hugging this one: right turn first.
                func rank(_ e: Int) -> Int { (5 - (edges[e].dir - edge.dir + 4) % 4) % 4 }     // right 0, straight 1, left 2
                let next = (starting[key(end.0, end.1)] ?? []).filter { !used[$0] || $0 == first }.min { rank($0) < rank($1) }
                guard let next else { break }
                current = next
            }
            if loop.count > 1, loop.first!.dir == loop.last!.dir { loop.removeFirst() }
            loops.append(loop)
        }
        return loops
    }()

    /// The loops, moved `inset` into the walls, their corners rounded.
    static func outline(inset: CGFloat, radius: CGFloat, blocks: Bool = false) -> Path {
        let normal: [(CGFloat, CGFloat)] = [(0, 1), (-1, 0), (0, -1), (1, 0)]    // to the right of east, south, west, north
        var path = Path()
        // The frame is the one loop that goes out through the tunnel, past the maze's side.
        for loop in loops where loop.count >= 3 && !(blocks && loop.contains { $0.x < 0 }) {
            let n = loop.count
            let points: [CGPoint] = (0..<n).map { i in
                let corner = loop[i], before = loop[(i + n - 1) % n].dir
                let a = normal[before], b = normal[corner.dir]
                return CGPoint(x: CGFloat(corner.x) + inset * (a.0 + b.0), y: CGFloat(corner.y) + inset * (a.1 + b.1))
            }
            func middle(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
            func length(_ p: CGPoint, _ q: CGPoint) -> CGFloat { abs(p.x - q.x) + abs(p.y - q.y) }
            path.move(to: middle(points[n - 1], points[0]))
            for i in 0..<n {
                let p = points[i], before = points[(i + n - 1) % n], after = points[(i + 1) % n]
                path.addArc(tangent1End: p, tangent2End: after, radius: min(radius, length(p, before) / 2, length(p, after) / 2))
            }
            path.closeSubpath()
        }
        return path
    }

    /// A ghost's skirt and dome, a unit across, the skirt's waves `phase` along.
    static func ghost(phase: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -1, y: 0.86))
        path.addLine(to: CGPoint(x: -1, y: -0.02))
        path.addArc(center: CGPoint(x: 0, y: -0.02), radius: 1, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: 1, y: 0.86))
        let n = 18
        for k in 1...n {
            let x = 1 - 2 * Double(k) / Double(n)
            let y = 0.8 + 0.16 * cos(Double(k) / Double(n) * 3 * 2 * .pi + phase)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }

    /// A blue ghost's wobbly mouth, a unit across.
    static let frown: Path = {
        var path = Path()
        for k in 0...8 {
            let p = CGPoint(x: -0.62 + 1.24 * CGFloat(k) / 8, y: 0.34 + (k % 2 == 0 ? 0.08 : -0.08))
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }()
}

fileprivate struct PacmanScene {
    let before: PacmanWorld, after: PacmanWorld
    let t: Double, since: Double, now: Double, best: Int

    typealias RGB = (Double, Double, Double)
    /// Everybody put back at the start — a new life or a new level — is not a glide.
    private var snapped: Bool {
        switch (before.phase, after.phase) {
        case (.dying, .ready), (.clearing, .ready): return true
        default: return false
        }
    }
    private func rgb(_ c: RGB, _ a: Double = 1) -> Color { Color(red: c.0, green: c.1, blue: c.2).opacity(a) }

    private static let neon: RGB = (0.3, 0.46, 1), deep: RGB = (0.13, 0.22, 1), cream: RGB = (1, 0.86, 0.72), yellow: RGB = (1, 0.88, 0.1)

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let width = size.width, height = size.height
        let band = height * 0.1, pad = width * 0.025
        let s = min((width - 2 * pad) / CGFloat(PacmanMaze.width), (height - band - pad) / CGFloat(PacmanMaze.height))
        let maze = CGRect(x: (width - s * CGFloat(PacmanMaze.width)) / 2, y: band + (height - band - pad * 0.5 - s * CGFloat(PacmanMaze.height)) / 2,
                          width: s * CGFloat(PacmanMaze.width), height: s * CGFloat(PacmanMaze.height))
        let place = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: maze.minX, ty: maze.minY)
        func centre(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: maze.minX + CGFloat(x + 0.5) * s, y: maze.minY + CGFloat(y + 0.5) * s) }

        backdrop(g, size)
        // Everything in the maze is cut off at its sides, so what goes into the tunnel goes out of sight.
        var inside = g
        inside.clip(to: Path(CGRect(x: maze.minX, y: 0, width: maze.width, height: height)))
        walls(inside, place: place, s: s, maze: maze)
        dots(inside, centre: centre, s: s)

        let dying: Double? = { if case .dying(let k) = after.phase { return (Double(PacmanWorld.dyingTicks - k) + t) / Double(PacmanWorld.dyingTicks) }; return nil }()
        let clearing: Bool = { if case .clearing = after.phase { return true }; return false }()
        let eating: Bool = { if case .eating = after.phase { return true }; return false }()

        // Pac-Man under the ghosts, as in the arcade; hidden while a ghost's points show where he is.
        if !eating && after.phase != .over {
            let p = glide(before.pac, after.pac, via: -1)
            if let dying {
                death(inside, at: centre(p.x, p.y), r: s * 0.62, progress: dying)
            } else {
                let chomping = after.moved && t < 1
                let mouth = chomping ? 0.08 + 0.72 * abs(sin(Double.pi * t)) : clearing ? 0 : after.phase == .play ? 0.5 + 0.12 * sin(now * 3) : 0.55
                for x in copies(p.x) { pacman(inside, at: centre(x, p.y), r: s * 0.62, facing: Double(after.heading), mouth: mouth, glow: true) }
            }
        }
        let showGhosts = !clearing && after.phase != .over && (dying ?? 0) < 0.16
        if showGhosts {
            for i in [3, 2, 1, 0] { ghost(inside, i, centre: centre, s: s) }
        }
        if eating, let eaten = after.eaten {
            let spot = centre(Double(PacmanMaze.x(eaten.cell)), Double(PacmanMaze.y(eaten.cell)))
            popup(g, "\(eaten.points)", at: spot, s: s)
        }
        if case .ready = after.phase {
            let spot = centre(10, 11)
            let pulse = 0.82 + 0.18 * sin(now * 5)
            var glow = g
            glow.blendMode = .plusLighter
            glow.fill(Path(ellipseIn: CGRect(x: spot.x - s * 2.6, y: spot.y - s * 0.9, width: s * 5.2, height: s * 1.8)),
                      with: .radialGradient(Gradient(colors: [rgb(Self.yellow, 0.28 * pulse), .clear]), center: spot, startRadius: 0, endRadius: s * 2.6))
            g.fill(Path(roundedRect: CGRect(x: spot.x - s * 1.9, y: spot.y - s * 0.52, width: s * 3.8, height: s * 1.04), cornerRadius: s * 0.3),
                   with: .color(Color(red: 0.01, green: 0.01, blue: 0.05).opacity(0.82)))
            JevDraw.text(g, "准备！", at: spot, size: s * 0.8, colour: rgb(Self.yellow), shadow: false)
        }
        hud(g, size, maze: maze, band: band)
        if after.phase == .over {
            JevDraw.curtain(g, size, title: "游戏结束", detail: "得分 \(after.score) · 第 \(after.level) 关")
        }
    }

    // MARK: Where things are

    /// A point `t` of the way from one cell to another (through `via` for a double step), across the tunnel the short way.
    private func glide(_ from: Int, _ to: Int, via: Int) -> (x: Double, y: Double) {
        func segment(_ a: Int, _ b: Int, _ k: Double) -> (x: Double, y: Double) {
            let ax = Double(PacmanMaze.x(a)), ay = Double(PacmanMaze.y(a))
            var bx = Double(PacmanMaze.x(b)), by = Double(PacmanMaze.y(b))
            if abs(bx - ax) > 1.5 { bx = ax + (bx > ax ? -1 : 1) }
            if abs(by - ay) > 1.5 { by = ay }
            return (JevDraw.mix(ax, bx, k), JevDraw.mix(ay, by, k))
        }
        let k = snapped ? 1 : min(max(t, 0), 1)
        if via >= 0 { return k < 0.5 ? segment(from, via, k * 2) : segment(via, to, k * 2 - 1) }
        return segment(from, to, k)
    }

    /// Where to draw something at `x`: there, and again on the far side while it is in the tunnel's mouth.
    private func copies(_ x: Double) -> [Double] {
        let w = Double(PacmanMaze.width)
        return x < 0.5 ? [x, x + w] : x > w - 1.5 ? [x, x - w] : [x]
    }

    // MARK: The maze

    private func backdrop(_ g: GraphicsContext, _ size: CGSize) {
        // The arcade's black glass: all the light is the tubes' own. (A gradient over the whole
        // picture would cost a third of the frame.)
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.01, green: 0.01, blue: 0.04)))
    }

    private func walls(_ g: GraphicsContext, place: CGAffineTransform, s: CGFloat, maze: CGRect) {
        let outer = PacmanArt.outer.applying(place), inner = PacmanArt.inner.applying(place)
        // The level cleared: the maze flashes white and blue, as in the arcade.
        var white = false
        if case .clearing(let k) = after.phase { white = (k + (t > 0.5 ? 1 : 0)) % 2 == 0 }
        let line: RGB = white ? (0.95, 0.96, 1) : Self.neon, core: RGB = white ? (1, 1, 1) : (0.62, 0.74, 1)
        let hum = 0.9 + 0.1 * sin(now * 1.7)
        g.fill(PacmanArt.body.applying(place), with: .color(rgb(white ? (0.3, 0.32, 0.5) : (0.05, 0.07, 0.26), 0.55)))
        var glow = g
        glow.blendMode = .plusLighter
        glow.stroke(outer, with: .color(rgb(white ? line : Self.deep, 0.13 * hum)), lineWidth: s * 0.62)
        glow.stroke(outer, with: .color(rgb(white ? line : Self.deep, 0.22 * hum)), lineWidth: s * 0.28)
        g.stroke(inner, with: .color(rgb(line, 0.8)), lineWidth: max(1, s * 0.06))
        g.stroke(outer, with: .color(rgb(line)), lineWidth: max(1.2, s * 0.095))
        g.stroke(outer, with: .color(rgb(core, 0.9)), lineWidth: max(0.5, s * 0.03))
        // The ghost house door: a pink bar across the gap.
        let door = CGRect(x: 9.8, y: 8.43, width: 1.4, height: 0.14).applying(place)
        glow.fill(Path(door.insetBy(dx: -s * 0.12, dy: -s * 0.14)), with: .color(Color(red: 1, green: 0.45, blue: 0.75).opacity(0.3)))
        g.fill(Path(door), with: .color(Color(red: 1, green: 0.72, blue: 0.86)))
    }

    private func dots(_ g: GraphicsContext, centre: (Double, Double) -> CGPoint, s: CGFloat) {
        var small = Path(), halo = Path()
        var pellets: [CGPoint] = []
        let r = s * 0.1
        for c in PacmanMaze.food {
            // The dot Pac-Man is moving onto stays until he gets there.
            let there = after.has(c) || (c == after.pac && before.has(c) && t < 0.5 && after.moved)
            guard there else { continue }
            let p = centre(Double(PacmanMaze.x(c)), Double(PacmanMaze.y(c)))
            if PacmanMaze.tiles[c] == .pellet { pellets.append(p); continue }
            small.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            halo.addEllipse(in: CGRect(x: p.x - r * 2.4, y: p.y - r * 2.4, width: r * 4.8, height: r * 4.8))
        }
        var glow = g
        glow.blendMode = .plusLighter
        glow.fill(halo, with: .color(rgb(Self.cream, 0.07)))
        g.fill(small, with: .color(rgb(Self.cream)))
        for (index, p) in pellets.enumerated() {
            let pulse = 0.5 + 0.5 * sin(now * 5.5 + Double(index) * 0.7)
            let rr = s * CGFloat(0.26 + 0.06 * pulse)
            glow.fill(Path(ellipseIn: CGRect(x: p.x - rr * 2.6, y: p.y - rr * 2.6, width: rr * 5.2, height: rr * 5.2)),
                      with: .radialGradient(Gradient(colors: [rgb((1, 0.8, 0.6), 0.45 * pulse + 0.15), .clear]), center: p, startRadius: 0, endRadius: rr * 2.6))
            g.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr)),
                   with: .radialGradient(Gradient(colors: [.white, rgb(Self.cream), rgb((0.95, 0.66, 0.45))]),
                                         center: CGPoint(x: p.x - rr * 0.3, y: p.y - rr * 0.35), startRadius: 0, endRadius: rr * 1.3))
        }
    }

    // MARK: Pac-Man

    /// The yellow disc, his mouth `mouth` radians either side of the way he faces (0 up, 1 left, 2 down, 3 right).
    private func pacman(_ g: GraphicsContext, at c: CGPoint, r: CGFloat, facing: Double, mouth: Double, glow: Bool) {
        let angle = [-Double.pi / 2, Double.pi, Double.pi / 2, 0][Int(facing) % 4]
        if glow {
            var light = g
            light.blendMode = .plusLighter
            light.fill(Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)),
                       with: .radialGradient(Gradient(colors: [rgb((1, 0.85, 0.2), 0.3), rgb((1, 0.7, 0.1), 0.08), .clear]), center: c, startRadius: r * 0.5, endRadius: r * 2))
        }
        var body = Path()
        if mouth < 0.02 {
            body.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        } else {
            body.move(to: c)
            body.addArc(center: c, radius: r, startAngle: .radians(angle + mouth), endAngle: .radians(angle + 2 * .pi - mouth), clockwise: false)
            body.closeSubpath()
        }
        g.fill(body.applying(CGAffineTransform(translationX: r * 0.08, y: r * 0.12)), with: .color(.black.opacity(0.35)))
        g.fill(body, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 1, blue: 0.72), rgb(Self.yellow), Color(red: 0.96, green: 0.66, blue: 0.02)]),
                                           center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.45))
        g.stroke(body, with: .color(Color(red: 0.55, green: 0.32, blue: 0).opacity(0.55)), lineWidth: max(0.6, r * 0.05))
        // Light along the rim at the top left, where it falls.
        var rim = Path()
        rim.addArc(center: c, radius: r * 0.8, startAngle: .degrees(196), endAngle: .degrees(248), clockwise: false)
        g.stroke(rim, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: max(0.8, r * 0.1), lineCap: .round))
    }

    /// Caught: he turns up, his mouth opens right round until nothing is left, and he goes out in a spark.
    private func death(_ g: GraphicsContext, at c: CGPoint, r: CGFloat, progress p: Double) {
        if p < 0.16 {
            pacman(g, at: c, r: r, facing: 0, mouth: 0.3, glow: true)
        } else if p < 0.8 {
            let k = (p - 0.16) / 0.64
            let mouth = 0.3 + (Double.pi - 0.3) * k * k * (3 - 2 * k)
            if mouth < Double.pi - 0.02 { pacman(g, at: c, r: r * CGFloat(1 - 0.12 * k), facing: 0, mouth: mouth, glow: true) }
        } else {
            let k = (p - 0.8) / 0.2
            var glow = g
            glow.blendMode = .plusLighter
            var rays = Path()
            for i in 0..<10 {
                let a = Double(i) * .pi / 5
                let near = r * CGFloat(0.3 + 0.6 * k), far = r * CGFloat(0.55 + 0.9 * k)
                rays.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * near, y: c.y + CGFloat(sin(a)) * near))
                rays.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * far, y: c.y + CGFloat(sin(a)) * far))
            }
            glow.stroke(rays, with: .color(rgb(Self.yellow, 1 - k)), style: StrokeStyle(lineWidth: max(1, r * 0.14), lineCap: .round))
        }
    }

    // MARK: Ghosts

    private func ghost(_ g: GraphicsContext, _ i: Int, centre: (Double, Double) -> CGPoint, s: CGFloat) {
        let a = before.ghosts[i], b = after.ghosts[i]
        if case .eating = after.phase, b.mode == .eyes, b.cell == after.eaten?.cell { return }
        var p = glide(a.cell, b.cell, via: b.via)
        if b.mode == .pen { p.y += 0.16 * sin(now * 4.2 + Double(i) * 1.7) }
        let r = s * 0.6
        let eyesOnly = b.mode == .eyes || b.mode == .entering
        // A glance between the way it went and the way it goes, turning quickly.
        let facing = b.dir
        for x in copies(p.x) {
            let c = centre(x, p.y)
            if eyesOnly {
                eyes(g, at: c, r: r, facing: facing)
            } else if b.blue {
                scared(g, at: c, r: r, i: i)
            } else {
                body(g, at: c, r: r, colour: PacmanArt.rgb[i], phase: now * 9 + Double(i))
                eyes(g, at: c, r: r, facing: facing)
            }
        }
    }

    private func body(_ g: GraphicsContext, at c: CGPoint, r: CGFloat, colour: RGB, phase: Double) {
        let shape = PacmanArt.ghost(phase: phase).applying(CGAffineTransform(a: r, b: 0, c: 0, d: r, tx: c.x, ty: c.y))
        var light = g
        light.blendMode = .plusLighter
        light.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.1, y: c.y - r * 2.1, width: r * 4.2, height: r * 4.2)),
                   with: .radialGradient(Gradient(colors: [rgb(colour, 0.34), rgb(colour, 0.1), .clear]), center: c, startRadius: r * 0.4, endRadius: r * 2.1))
        g.fill(shape.applying(CGAffineTransform(translationX: r * 0.08, y: r * 0.12)), with: .color(.black.opacity(0.35)))
        g.fill(shape, with: .linearGradient(Gradient(colors: [JevDraw.shade(colour, 1.35), rgb(colour), JevDraw.shade(colour, 0.62)]),
                                            startPoint: CGPoint(x: c.x - r * 0.8, y: c.y - r), endPoint: CGPoint(x: c.x + r * 0.7, y: c.y + r)))
        g.stroke(shape, with: .color(JevDraw.shade(colour, 0.4).opacity(0.7)), lineWidth: max(0.6, r * 0.05))
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.86, width: r * 0.5, height: r * 0.3)), with: .color(.white.opacity(0.35)))
    }

    private func eyes(_ g: GraphicsContext, at c: CGPoint, r: CGFloat, facing: Int) {
        let look = CGPoint(x: CGFloat(PacmanMaze.dx[facing]), y: CGFloat(PacmanMaze.dy[facing]))
        for side: CGFloat in [-1, 1] {
            let e = CGPoint(x: c.x + side * r * 0.36 + look.x * r * 0.1, y: c.y - r * 0.2 + look.y * r * 0.1)
            g.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.25, y: e.y - r * 0.31, width: r * 0.5, height: r * 0.62)), with: .color(.white))
            let q = CGPoint(x: e.x + look.x * r * 0.12, y: e.y + look.y * r * 0.15)
            g.fill(Path(ellipseIn: CGRect(x: q.x - r * 0.13, y: q.y - r * 0.13, width: r * 0.26, height: r * 0.26)), with: .color(Color(red: 0.12, green: 0.2, blue: 0.85)))
        }
    }

    /// Blue, with a wobbly mouth — flashing white when the blue is nearly over.
    private func scared(_ g: GraphicsContext, at c: CGPoint, r: CGFloat, i: Int) {
        let flashing = after.blue <= 10 && Int(now * 6) % 2 == 0
        let colour: RGB = flashing ? (0.93, 0.94, 1) : (0.16, 0.24, 1)
        let face: Color = flashing ? Color(red: 1, green: 0.22, blue: 0.25) : Color(red: 1, green: 0.8, blue: 0.68)
        body(g, at: c, r: r, colour: colour, phase: now * 14 + Double(i))
        for side: CGFloat in [-1, 1] {
            g.fill(Path(roundedRect: CGRect(x: c.x + side * r * 0.3 - r * 0.1, y: c.y - r * 0.32, width: r * 0.2, height: r * 0.2), cornerRadius: r * 0.05), with: .color(face))
        }
        g.stroke(PacmanArt.frown.applying(CGAffineTransform(a: r, b: 0, c: 0, d: r, tx: c.x, ty: c.y)), with: .color(face),
                 style: StrokeStyle(lineWidth: max(1, r * 0.1), lineCap: .round, lineJoin: .round))
    }

    /// A ghost's worth where it was eaten, in cyan, popping up.
    private func popup(_ g: GraphicsContext, _ text: String, at p: CGPoint, s: CGFloat) {
        let k = min(max(t, 0), 1)
        let size = s * CGFloat(0.62 + 0.14 * (1 - (1 - k) * (1 - k)))
        var glow = g
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.4, y: p.y - s * 0.8, width: s * 2.8, height: s * 1.6)),
                  with: .radialGradient(Gradient(colors: [Color(red: 0.2, green: 0.85, blue: 1).opacity(0.4), .clear]), center: p, startRadius: 0, endRadius: s * 1.4))
        JevDraw.text(g, text, at: p, size: size, colour: Color(red: 0.45, green: 0.95, blue: 1))
    }

    // MARK: The panel

    private func glass(_ g: GraphicsContext, _ rect: CGRect) {
        let shape = Path(roundedRect: rect, cornerRadius: min(rect.height * 0.34, 12))
        g.fill(shape.applying(CGAffineTransform(translationX: 1.5, y: 2.5)), with: .color(.black.opacity(0.3)))
        g.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.14, green: 0.17, blue: 0.42).opacity(0.62), Color(red: 0.03, green: 0.03, blue: 0.13).opacity(0.78)]),
                                            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        var sheen = g
        sheen.clip(to: shape)
        sheen.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.5)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0.03)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.midY)))
        g.stroke(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0.08)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)),
                 lineWidth: 1)
    }

    /// Score, level and best on glass above the maze, and a little Pac-Man for each life.
    private func hud(_ g: GraphicsContext, _ size: CGSize, maze: CGRect, band: CGFloat) {
        let h = band * 0.72
        let panel = CGRect(x: maze.minX, y: (band - h) / 2 + band * 0.04, width: maze.width, height: h)
        glass(g, panel)
        let label = Color(red: 0.55, green: 0.72, blue: 1)
        let digits = Font.system(size: h * 0.5, weight: .heavy, design: .rounded).monospacedDigit()
        let small = Font.system(size: h * 0.25, weight: .bold, design: .rounded)
        // Score, at the left.
        let left = panel.minX + h * 0.36
        g.draw(Text(verbatim: "得分").font(small).foregroundColor(label), at: CGPoint(x: left, y: panel.minY + h * 0.27), anchor: .leading)
        g.draw(Text(verbatim: "\(after.score)").font(digits).foregroundColor(Color(red: 0, green: 0.03, blue: 0.2).opacity(0.7)),
               at: CGPoint(x: left + 1, y: panel.minY + h * 0.66 + 1.5), anchor: .leading)
        g.draw(Text(verbatim: "\(after.score)").font(digits).foregroundColor(.white), at: CGPoint(x: left, y: panel.minY + h * 0.66), anchor: .leading)
        // The level, in the middle, over how much of it is eaten.
        let mid = panel.midX - panel.width * 0.04
        g.draw(Text(verbatim: "第 \(after.level) 关").font(.system(size: h * 0.36, weight: .heavy, design: .rounded)).foregroundColor(rgb(Self.yellow)),
               at: CGPoint(x: mid, y: panel.minY + h * 0.4), anchor: .center)
        let bar = CGRect(x: mid - panel.width * 0.11, y: panel.minY + h * 0.7, width: panel.width * 0.22, height: max(3, h * 0.08))
        let eaten = 1 - Double(after.left) / Double(PacmanMaze.food.count)
        g.fill(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(.white.opacity(0.12)))
        if eaten > 0 {
            var fill = bar
            fill.size.width = max(bar.height, bar.width * CGFloat(eaten))
            g.fill(Path(roundedRect: fill, cornerRadius: bar.height / 2),
                   with: .linearGradient(Gradient(colors: [rgb(Self.cream), rgb(Self.yellow)]), startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
        }
        // Lives and the best score, at the right.
        let right = panel.maxX - h * 0.36
        let lifeR = h * 0.15
        for life in 0..<max(after.lives, 0) {
            let c = CGPoint(x: right - lifeR - CGFloat(life) * lifeR * 2.7, y: panel.minY + h * 0.3)
            pacman(g, at: c, r: lifeR, facing: 1, mouth: 0.62, glow: false)
        }
        g.draw(Text(verbatim: "最高 \(best)").font(small).foregroundColor(label), at: CGPoint(x: right, y: panel.minY + h * 0.72), anchor: .trailing)
    }
}
