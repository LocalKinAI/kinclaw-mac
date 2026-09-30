import Foundation

/// 长城守卫 — tower defence on the northern frontier.
///
/// Raiders come down out of the grassland through three gaps in the hills and
/// make for the pass (关口) in the Great Wall along the south edge. Every one
/// that gets through costs lives; twenty lives and the pass is lost. They walk
/// the shortest way (A* over the tiles, eight directions, no cutting corners),
/// round rocks, over the river only at its fords, and round whatever is built —
/// so towers are both the guns and the walls of a maze. A tower that would shut
/// every way to the pass is refused. Waves never end: more of them, faster and
/// tougher, new kinds mixing in, and every tenth the 单于 himself with guards.
///
/// Everything here is a value, stepped by `step(dt)`, so a test can play a
/// thousand games without a window.

struct WallTile: Hashable { var x: Int, y: Int }

/// A seeded random stream (SplitMix64): the same seed, the same frontier and the same waves.
struct WallRNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 ^ 0xD1B5_4A32_D192_ED03 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}

enum WallGround: UInt8 { case grass, water, ford, rock, ridge, wall, gate }

// MARK: - Towers

enum WallKind: Int, CaseIterable {
    case arrow, ballista, trebuchet, fire, beacon, barricade

    static let names = ["箭楼", "弩车", "投石机", "火油", "烽火台", "拒马"]
    static let english = ["arrow tower", "ballista", "trebuchet", "fire-oil thrower", "beacon tower", "spiked barricade"]
    var name: String { Self.names[rawValue] }
    var english: String { Self.english[rawValue] }
    var cost: Int { [45, 90, 120, 100, 80, 12][rawValue] }
    /// What raising it to level 2 and to level 3 costs.
    var upgrades: [Int] { [[60, 110], [100, 170], [120, 200], [100, 180], [90, 160], [15, 30]][rawValue] }
    var shoots: Bool { self != .beacon && self != .barricade }
    /// What its shots are, for who is armoured against what.
    var damageKind: WallDamage { [.arrow, .bolt, .stone, .fire, .arrow, .spike][rawValue] }
    /// The key that picks it from the bar.
    var key: String { ["Q", "W", "E", "R", "T", "F"][rawValue] }

    func stats(_ level: Int) -> WallStats {
        let l = max(0, min(2, level))
        switch self {
        case .arrow:
            return WallStats(damage: [12, 22, 38][l], rate: [1.7, 2.0, 2.4][l], range: [3.0, 3.3, 3.7][l], hp: [220, 300, 400][l])
        case .ballista:
            return WallStats(damage: [44, 80, 140][l], rate: [0.55, 0.6, 0.66][l], range: [5.0, 5.5, 6.0][l], hp: [260, 350, 460][l], pierce: [4, 5, 7][l])
        case .trebuchet:
            return WallStats(damage: [60, 105, 180][l], rate: [0.4, 0.42, 0.45][l], range: [4.6, 5.1, 5.6][l], minRange: 1.6, splash: [1.2, 1.35, 1.5][l], hp: [280, 380, 500][l])
        case .fire:
            return WallStats(damage: [18, 30, 48][l], rate: [0.4, 0.42, 0.45][l], range: [2.6, 2.8, 3.1][l], splash: [0.9, 1.0, 1.15][l], hp: [240, 330, 440][l], burn: [4.0, 4.6, 5.2][l])
        case .beacon:
            return WallStats(damage: 0, rate: 0, range: [2.3, 2.7, 3.1][l], hp: [200, 280, 380][l], boost: [0.22, 0.34, 0.48][l], reach: [0.1, 0.15, 0.2][l])
        case .barricade:
            return WallStats(damage: [5, 10, 18][l], rate: 0, range: 0.95, hp: [260, 520, 900][l])
        }
    }
}

struct WallStats {
    var damage: Double
    /// Shots a second.
    var rate: Double
    /// In tiles, from the middle of its tile.
    var range: Double
    var minRange: Double = 0
    /// Radius of a stone's splash or a fire patch.
    var splash: Double = 0
    var hp: Double
    /// Bolts: how many enemies one goes through.
    var pierce: Int = 1
    /// Fire: how long a patch burns.
    var burn: Double = 0
    /// Beacons: damage added to towers within `range`, and range added.
    var boost: Double = 0
    var reach: Double = 0
}

enum WallDamage: Int { case arrow, bolt, stone, fire, spike }

/// Which enemy in range a tower shoots at.
enum WallAim: Int, CaseIterable {
    case first, strongest, nearest
    var title: String { ["最前", "最强", "最近"][rawValue] }
}

struct WallTower {
    var id: Int
    var kind: WallKind
    var x: Int, y: Int
    var level = 0
    var hp: Double
    var invested: Int
    var cooldown = 0.5
    var aim: WallAim = .first
    /// Where it last aimed (radians, 0 east, y down), for the ballista's turn.
    var angle = -Double.pi / 2
    var fired = -9.0
    var hurt = -9.0
    var kills = 0
    var dealt = 0.0
    var built = 0.0
    var stats: WallStats { kind.stats(level) }
    var centre: (x: Double, y: Double) { (Double(x) + 0.5, Double(y) + 0.5) }
    var tile: WallTile { WallTile(x: x, y: y) }
}

// MARK: - Enemies

enum WallFoe: Int, CaseIterable {
    case cavalry, foot, shield, siege, shaman, chanyu, `guard`

    static let names = ["骑兵", "步卒", "盾兵", "攻城车", "萨满", "单于", "亲卫"]
    static let english = ["cavalry", "foot soldiers", "shield men", "siege carts", "shamans", "the Chanyu", "guard riders"]
    static let one = ["a rider", "a foot soldier", "a shield man", "a siege cart", "a shaman", "the Chanyu", "a guard rider"]
    var name: String { Self.names[rawValue] }
    var english: String { Self.english[rawValue] }
    var hp: Double { [36, 70, 95, 320, 65, 1700, 120][rawValue] }
    /// Tiles a second.
    var speed: Double { [2.0, 1.1, 0.9, 0.55, 1.0, 0.62, 1.7][rawValue] }
    var gold: Int { [3, 3, 5, 18, 7, 150, 6][rawValue] }
    /// Lives lost when it gets through the pass.
    var lives: Int { [1, 1, 1, 3, 1, 10, 2][rawValue] }
    var mounted: Bool { self == .cavalry || self == .chanyu || self == .guard }
    /// Does it attack towers it passes?
    var breaker: Bool { self == .siege || self == .chanyu }
    /// Does it hack at barricades beside its way?
    var hacks: Bool { self == .foot || self == .shield || self == .guard || self == .chanyu || self == .siege }

    /// How much of a kind of damage gets through its armour.
    func takes(_ d: WallDamage) -> Double {
        switch (self, d) {
        case (.shield, .arrow): return 0.3
        case (.shield, .bolt): return 0.6
        case (.siege, .arrow): return 0.5
        case (.siege, .bolt): return 1.2
        case (.siege, .stone): return 1.3
        case (.siege, .fire): return 1.5
        case (.siege, .spike), (.chanyu, .spike): return 0.5
        case (.cavalry, .stone), (.guard, .stone): return 0.6
        case (.cavalry, .fire), (.guard, .fire): return 1.2
        case (.chanyu, .arrow): return 0.6
        case (.chanyu, .fire): return 0.8
        default: return 1
        }
    }
}

struct WallEnemy {
    var id: Int
    var foe: WallFoe
    var x: Double, y: Double
    var hp: Double, maxHP: Double
    var speed: Double
    var route: [WallTile] = []
    var next = 0
    var layout = -1
    /// A small offset from the middle of each tile, so a crowd spreads out.
    var ox: Double, oy: Double
    var hit = -9.0
    var burning = -9.0
    var healed = -9.0
    var cooldown = 0.0
    var facing = 1.0
    var seed: Int
    var born: Double
    var wave: Int
    /// Hitting a tower this moment (siege and the Chanyu).
    var ramming = -9.0
    var tile: WallTile { WallTile(x: Int(floor(x)), y: Int(floor(max(0, y)))) }
}

// MARK: - Shots, fires and what is left to see

enum WallShotKind { case arrow, bolt, stone, pot }

struct WallShot {
    var kind: WallShotKind
    var tower: Int
    var fromX: Double, fromY: Double
    var toX: Double, toY: Double
    var target: Int?
    var t = 0.0
    var duration: Double
    var damage: Double
    var splash = 0.0
    var burn = 0.0
    /// Bolts: direction and reach, and who has been hit.
    var dx = 0.0, dy = 0.0, reach = 0.0
    var pierce = 1
    var struck: [Int] = []
    var x: Double { fromX + (toX - fromX) * t }
    var y: Double { fromY + (toY - fromY) * t }
}

struct WallFire {
    var x: Double, y: Double
    var radius: Double
    var dps: Double
    var from: Double, until: Double
    var tower: Int
}

enum WallEffectKind: Equatable {
    case blast(Double)           // size in tiles
    case dust(Double)
    case gold(Int)
    case fallen(WallFoe, Double) // facing
    case leak(Int)               // lives lost
    case heal
    case crumble(WallKind)
    case spark
}

struct WallEffect {
    var kind: WallEffectKind
    var x: Double, y: Double
    var at: Double
    var life: Double
}

/// What happened, for the page to say.
struct WallMoment {
    enum Kind: Equatable {
        case wave(Int)
        case boss(Int)
        case leak(WallFoe, Int)
        case destroyed(WallKind, WallFoe)
        case lost
    }
    var kind: Kind
    var time: Double
}

// MARK: - A wave

struct WallWave {
    var number: Int
    var boss: Bool
    /// What comes, in order, and the seconds before the next.
    var spawns: [(foe: WallFoe, gap: Double)]
    var theme: String
    var english: String

    func count(_ f: WallFoe) -> Int { spawns.reduce(0) { $0 + ($1.foe == f ? 1 : 0) } }
    var total: Int { spawns.count }

    /// "22 shield men and 6 foot soldiers"
    var described: String {
        var parts: [String] = []
        for f in [WallFoe.chanyu, .guard, .siege, .shield, .cavalry, .shaman, .foot] {
            let n = count(f)
            if n > 0 { parts.append(f == .chanyu ? "the Chanyu himself" : n == 1 ? WallFoe.one[f.rawValue] : "\(n) \(f.english)") }
        }
        if parts.count <= 1 { return parts.first ?? "nothing" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
    var chinese: String {
        [WallFoe.chanyu, .guard, .siege, .shield, .cavalry, .shaman, .foot].compactMap { f in
            let n = count(f)
            return n > 0 ? (f == .chanyu ? "单于" : "\(f.name)×\(n)") : nil
        }.joined(separator: " ")
    }

    /// Health grows with the wave: gently at first, then ever faster, so every defence falls in the end.
    nonisolated(unsafe) static var growth = (linear: 0.065, square: 0.0095)
    static func health(_ n: Int) -> Double { let w = Double(max(0, n - 1)); return 1 + growth.linear * w + growth.square * w * w }
    static func pace(_ n: Int) -> Double { min(1.35, 1 + 0.008 * Double(max(0, n - 1))) }

    /// Wave `n` of a game: the same every time for the same seed.
    static func make(_ n: Int, seed: UInt64) -> WallWave {
        var rng = WallRNG(seed &+ UInt64(n) &* 7919)
        let base = 7 + Double(n) * 1.05 + (n > 30 ? Double(n - 30) * 0.6 : 0)
        var list: [(WallFoe, Double)] = []
        func add(_ f: WallFoe, _ count: Int, _ gap: Double) { for _ in 0..<max(0, count) { list.append((f, gap)) } }
        func mix(_ weights: [(WallFoe, Double)], _ total: Int) {
            let sum = weights.reduce(0) { $0 + $1.1 }
            for _ in 0..<total {
                var r = rng.unit() * sum
                for (f, w) in weights { r -= w; if r <= 0 { list.append((f, gapOf(f))); break } }
            }
        }
        func gapOf(_ f: WallFoe) -> Double { [0.42, 0.8, 0.95, 2.6, 1.1, 2, 0.5][f.rawValue] }
        let N = Int(base.rounded())
        if n % 10 == 0 {
            let k = n / 10
            add(.foot, N / 3, 0.7)
            list.append((.chanyu, 2.5))
            add(.guard, 4 + 2 * k, 0.45)
            if k >= 2 { add(.shaman, k, 1.0) }
            if k >= 3 { add(.siege, k - 1, 2.2) }
            add(.cavalry, N / 3, 0.42)
            return WallWave(number: n, boss: true, spawns: list, theme: "单于亲征", english: "the Chanyu leads the horde himself, with his guard riders")
        }
        let theme: (String, String)
        switch n {
        case 1, 2: add(.foot, N, 0.85); theme = ("步卒", "foot soldiers on the march")
        case 3: add(.cavalry, N, 0.45); theme = ("骑兵突袭", "a cavalry raid, fast and light")
        case 4: add(.foot, N / 2, 0.8); add(.cavalry, N - N / 2, 0.45); theme = ("步骑混编", "foot and horse together")
        case 5: add(.foot, N / 3, 0.8); add(.shield, N - N / 3, 0.95); theme = ("盾阵", "a shield wall: armoured shield men that arrows barely hurt")
        case 6: mix([(.foot, 2), (.cavalry, 2), (.shield, 1)], N); theme = ("混战", "a mixed band")
        case 7: add(.foot, N - 3, 0.8); add(.siege, 2, 2.6); theme = ("攻城车", "siege carts with an escort: slow, huge, and they smash towers they pass")
        case 8: add(.shield, N - 3, 0.9); add(.shaman, 3, 1.1); theme = ("萨满助阵", "shield men with shamans who heal them")
        case 9: add(.cavalry, N, 0.4); theme = ("铁骑", "a great cavalry charge")
        default:
            let pick = rng.int(7)
            let sieges = 1 + n / 12
            switch pick {
            case 0: add(.cavalry, N + N / 3, 0.36); add(.guard, n / 8, 0.5); theme = ("铁骑", "a great cavalry charge")
            case 1: add(.shield, N * 2 / 3, 0.85); add(.foot, N / 3, 0.75); add(.shaman, 1 + n / 10, 1.0); theme = ("盾阵", "a shield wall: armoured shield men that arrows barely hurt")
            case 2: add(.foot, N * 2 / 3, 0.75); add(.siege, sieges + 1, 2.2); theme = ("攻城车", "siege carts with an escort: slow, huge, and they smash towers they pass")
            case 3: mix([(.foot, 2), (.shield, 1.5), (.shaman, 0.6)], N); theme = ("萨满助阵", "a host healed by shamans")
            case 4: mix([(.cavalry, 3), (.foot, 1)], N + N / 4); theme = ("骑兵突袭", "a cavalry raid, fast and light")
            case 5: add(.foot, N + N / 2, 0.55); theme = ("人海", "a sea of foot soldiers")
            default: mix([(.foot, 2), (.cavalry, 2), (.shield, 1.5), (.shaman, 0.5)], N); add(.siege, sieges, 2.2); theme = ("大军", "a great mixed host with siege carts")
            }
        }
        return WallWave(number: n, boss: false, spawns: list, theme: theme.0, english: theme.1)
    }
}

// MARK: - The frontier

struct WallField {
    static let width = 30, height = 20
    /// The Wall's first row; the pass is in it.
    static let wallRow = 18
    static let gateX = [14, 15]
    static let startGold = 250, startLives = 20
    /// Before the first wave, and between waves.
    static let firstCountdown = 25.0, countdown = 14.0
    static let sellBack = 0.7

    let seed: UInt64
    private(set) var ground: [WallGround]
    /// The columns of the three gaps in the hills (each two tiles wide: x and x + 1).
    private(set) var entries: [Int] = []
    private(set) var fords: [Int] = []

    private(set) var towers: [WallTower] = []
    /// The tower standing on each tile.
    private(set) var occupant: [Int]
    var enemies: [WallEnemy] = []
    var shots: [WallShot] = []
    var fires: [WallFire] = []
    var effects: [WallEffect] = []
    var moments: [WallMoment] = []

    var gold = WallField.startGold
    var lives = WallField.startLives
    /// Waves called so far.
    private(set) var wave = 0
    /// Seconds before the next wave comes by itself; it runs once the last wave has all come out of the hills.
    var clock = WallField.firstCountdown
    private var queue: [(at: Double, foe: WallFoe, wave: Int)] = []
    private var spawnTime = 0.0
    private(set) var time = 0.0
    private(set) var over = false

    /// Changes whenever the way to the pass may have: a tower built, sold or destroyed.
    private(set) var layout = 0
    /// Cost to the pass from every tile (10 a straight step, 14 a diagonal), -1 where there is no way.
    private(set) var dist: [Int]
    /// The way from each gap to the pass, as enemies coming out now would walk it.
    private(set) var routes: [[WallTile]] = []
    /// What beacons add to each tower: damage and range, by tower id.
    private(set) var boosts: [Int: (damage: Double, range: Double)] = [:]

    private(set) var kills = 0, leaked = 0, earned = 0, spent = 0
    private(set) var killsBy: [Int] = Array(repeating: 0, count: WallFoe.allCases.count)
    private(set) var bossesKilled = 0
    private var nextID = 1
    private var rng: WallRNG

    // MARK: Making the land

    init(seed: UInt64) {
        self.seed = seed
        rng = WallRNG(seed)
        let W = Self.width, H = Self.height
        ground = Array(repeating: .grass, count: W * H)
        occupant = Array(repeating: -1, count: W * H)
        dist = Array(repeating: -1, count: W * H)
        // The ridge along the north with three gaps.
        let centres = [4 + rng.int(3) - 1, 14 + rng.int(3) - 1, 24 + rng.int(3) - 1]
        entries = centres
        for x in 0..<W { ground[x] = .ridge }
        for c in centres { ground[c] = .grass; ground[c + 1] = .grass }
        // The Wall along the south, the pass in the middle.
        for y in Self.wallRow..<H { for x in 0..<W { ground[y * W + x] = Self.gateX.contains(x) ? .gate : .wall } }
        // A river from west to east, wandering, with three fords.
        var ry = 6 + rng.int(4)
        var riverRows: [Int] = []
        for x in 0..<W {
            if x > 0, x % 3 == 0 {
                let step = rng.int(3) - 1
                let ny = max(5, min(11, ry + step))
                if ny != ry { ground[ny * W + x] = .water; ground[ry * W + x] = .water }
                ry = ny
            }
            ground[ry * W + x] = .water
            riverRows.append(ry)
        }
        var fordCols: [Int] = []
        for c in [4, 15, 25] {
            // A ford where the river runs straight for a few tiles.
            var best = c
            for dx in [0, 1, -1, 2, -2] {
                let x = c + dx
                guard x > 1, x < W - 2 else { continue }
                let rows = (0..<H).filter { ground[$0 * W + x] == .water }
                if rows.count == 1 { best = x; break }
            }
            fordCols.append(best)
            for y in 0..<H where ground[y * W + best] == .water { ground[y * W + best] = .ford }
        }
        fords = fordCols
        // Rocks, in small clusters, never shutting a way.
        var placed = 0, tries = 0
        while placed < 7, tries < 200 {
            tries += 1
            let x = 1 + rng.int(W - 2), y = 2 + rng.int(13)
            guard ground[y * W + x] == .grass else { continue }
            if fordCols.contains(where: { abs($0 - x) <= 1 }) && abs(y - riverRows[x]) <= 2 { continue }
            if y >= 14, abs(x - 14) <= 4 { continue }
            if y <= 2, centres.contains(where: { abs($0 - x) <= 2 }) { continue }
            var cluster = [WallTile(x: x, y: y)]
            for _ in 0..<rng.int(3) {
                let b = cluster[rng.int(cluster.count)]
                let d = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.int(4)]
                let t = WallTile(x: b.x + d.0, y: b.y + d.1)
                if Self.inside(t), t.y >= 1, t.y <= 16, ground[Self.index(t)] == .grass { cluster.append(t) }
            }
            for t in cluster { ground[Self.index(t)] = .rock }
            if flow(blocked: nil).entriesReached(entries) { placed += 1 } else { for t in cluster { ground[Self.index(t)] = .grass } }
        }
        remap()
    }

    // MARK: Tiles

    static func inside(_ t: WallTile) -> Bool { t.x >= 0 && t.y >= 0 && t.x < width && t.y < height }
    static func index(_ t: WallTile) -> Int { t.y * width + t.x }
    func ground(_ t: WallTile) -> WallGround { Self.inside(t) ? ground[Self.index(t)] : .ridge }

    /// Can an enemy stand here, as the land and the towers are?
    func open(_ t: WallTile) -> Bool {
        guard Self.inside(t) else { return false }
        let i = Self.index(t)
        switch ground[i] {
        case .grass, .ford, .gate: return occupant[i] < 0
        default: return false
        }
    }

    /// Could anything be built here, ignoring whether it shuts the way?
    func buildable(_ t: WallTile) -> Bool {
        guard Self.inside(t), t.y >= 1, t.y < Self.wallRow else { return false }
        let i = Self.index(t)
        return ground[i] == .grass && occupant[i] < 0
    }

    func tower(_ id: Int) -> WallTower? { towers.first { $0.id == id } }
    func towerIndex(_ id: Int) -> Int? { towers.firstIndex { $0.id == id } }
    func tower(at t: WallTile) -> WallTower? {
        guard Self.inside(t) else { return nil }
        let id = occupant[Self.index(t)]
        return id >= 0 ? tower(id) : nil
    }
    func enemy(_ id: Int) -> WallEnemy? { enemies.first { $0.id == id } }

    static func centre(_ t: WallTile) -> (x: Double, y: Double) { (Double(t.x) + 0.5, Double(t.y) + 0.5) }
    var gateTiles: [WallTile] { Self.gateX.map { WallTile(x: $0, y: Self.wallRow) } }

    // MARK: The way to the pass

    static let steps: [(Int, Int, Int)] = [(1, 0, 10), (-1, 0, 10), (0, 1, 10), (0, -1, 10), (1, 1, 14), (1, -1, 14), (-1, 1, 14), (-1, -1, 14)]

    /// A step from `a` by (dx, dy): open, and a diagonal only when both tiles beside it are open (no cutting corners).
    func canStep(_ a: WallTile, _ dx: Int, _ dy: Int, blocked: Int? = nil, shut: [Bool]? = nil) -> Bool {
        let b = WallTile(x: a.x + dx, y: a.y + dy)
        func free(_ t: WallTile) -> Bool { open(t) && Self.index(t) != (blocked ?? -1) && !(shut?[Self.index(t)] ?? false) }
        guard free(b) else { return false }
        if dx != 0 && dy != 0 { return free(WallTile(x: a.x + dx, y: a.y)) && free(WallTile(x: a.x, y: a.y + dy)) }
        return true
    }

    /// Costs to the pass from every tile, with one more tile shut if given: Dijkstra outward from the gate.
    struct Flow {
        var dist: [Int]
        func at(_ t: WallTile) -> Int { WallField.inside(t) ? dist[WallField.index(t)] : -1 }
        func entriesReached(_ entries: [Int]) -> Bool { entries.allSatisfy { dist[$0] >= 0 } }
    }

    func flow(blocked: Int?) -> Flow {
        let W = Self.width, H = Self.height
        var d = Array(repeating: -1, count: W * H)
        // Costs are 10 and 14: a bucket queue is exact and fast.
        var buckets: [[Int]] = Array(repeating: [], count: 16)
        var current = 0, pending = 0
        for t in gateTiles { let i = Self.index(t); d[i] = 0; buckets[0].append(i); pending += 1 }
        var settled = Array(repeating: false, count: W * H)
        while pending > 0 {
            let slot = current % 16
            if buckets[slot].isEmpty { current += 1; continue }
            let i = buckets[slot].removeLast(); pending -= 1
            if settled[i] || d[i] != current { continue }
            settled[i] = true
            let t = WallTile(x: i % W, y: i / W)
            for (dx, dy, c) in Self.steps {
                // Walking from the neighbour to t: the same rule both ways, since it is symmetric.
                let n = WallTile(x: t.x + dx, y: t.y + dy)
                guard Self.inside(n), open(n), Self.index(n) != blocked ?? -1, canStep(t, dx, dy, blocked: blocked) else { continue }
                let j = Self.index(n), nd = current + c
                if d[j] < 0 || nd < d[j] { d[j] = nd; buckets[nd % 16].append(j); pending += 1 }
            }
        }
        return Flow(dist: d)
    }

    /// The shortest way from a tile to the pass: A* over the tiles, eight directions, no cutting corners.
    func route(from s: WallTile, blocked: Int? = nil, shut: [Bool]? = nil) -> [WallTile] {
        guard Self.inside(s) else { return [] }
        let W = Self.width, H = Self.height
        let goalY = Self.wallRow
        func h(_ i: Int) -> Int {
            let x = i % W, y = i / W
            let dy = abs(goalY - y)
            let dx = max(0, max(Self.gateX[0] - x, x - Self.gateX[1]))
            return 10 * max(dx, dy) + 4 * min(dx, dy)
        }
        var g = Array(repeating: Int.max, count: W * H)
        var came = Array(repeating: -1, count: W * H)
        var closed = Array(repeating: false, count: W * H)
        // A binary heap of (f, -g, index): ties go to the one furthest along.
        var heap: [(Int, Int, Int)] = []
        func less(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool { a.0 != b.0 ? a.0 < b.0 : a.1 < b.1 }
        func push(_ e: (Int, Int, Int)) {
            heap.append(e); var c = heap.count - 1
            while c > 0 { let p = (c - 1) / 2; if less(heap[c], heap[p]) { heap.swapAt(c, p); c = p } else { break } }
        }
        func pop() -> (Int, Int, Int) {
            let top = heap[0]; let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last; var p = 0
                while true {
                    let l = 2 * p + 1, r = l + 1; var m = p
                    if l < heap.count, less(heap[l], heap[m]) { m = l }
                    if r < heap.count, less(heap[r], heap[m]) { m = r }
                    if m == p { break }
                    heap.swapAt(p, m); p = m
                }
            }
            return top
        }
        let si = Self.index(s)
        g[si] = 0; push((h(si), 0, si))
        while !heap.isEmpty {
            let (_, _, i) = pop()
            if closed[i] { continue }
            closed[i] = true
            let t = WallTile(x: i % W, y: i / W)
            if ground[i] == .gate {
                var path = [t], k = i
                while came[k] >= 0 { k = came[k]; path.append(WallTile(x: k % W, y: k / W)) }
                return path.reversed()
            }
            for (dx, dy, c) in Self.steps where canStep(t, dx, dy, blocked: blocked, shut: shut) {
                let j = Self.index(WallTile(x: t.x + dx, y: t.y + dy))
                let ng = g[i] + c
                if ng < g[j] { g[j] = ng; came[j] = i; push((ng + h(j), -ng, j)) }
            }
        }
        return []
    }

    /// The length of a way, in tiles (a diagonal step counts 1.4).
    static func length(_ path: [WallTile]) -> Double {
        var n = 0.0
        for k in 1..<max(1, path.count) { n += (path[k].x != path[k - 1].x && path[k].y != path[k - 1].y) ? 1.414 : 1 }
        return n
    }

    /// The enemies' walk to the pass, averaged over the three gaps.
    var pathLength: Double { routes.isEmpty ? 0 : routes.map { Self.length($0) }.reduce(0, +) / Double(routes.count) }

    /// Work out the ways again after the land has changed.
    mutating func remap() {
        layout += 1
        dist = flow(blocked: nil).dist
        routes = entries.map { route(from: WallTile(x: $0, y: 0)) }
        // Beacons.
        boosts = [:]
        let beacons = towers.filter { $0.kind == .beacon }
        for t in towers where t.kind.shoots {
            var best = (damage: 0.0, range: 0.0)
            for b in beacons {
                let s = b.stats
                if hypot(Double(b.x - t.x), Double(b.y - t.y)) <= s.range + 0.01, s.boost > best.damage { best = (s.boost, s.reach) }
            }
            if best.damage > 0 { boosts[t.id] = best }
        }
    }

    /// A tower's reach and damage with any beacon's help.
    func range(of t: WallTower) -> Double { t.stats.range * (1 + (boosts[t.id]?.range ?? 0)) }
    func damage(of t: WallTower) -> Double { t.stats.damage * (1 + (boosts[t.id]?.damage ?? 0)) }

    /// Remaining cost to the pass for an enemy, in tiles.
    func remaining(_ e: WallEnemy) -> Double {
        guard e.next < e.route.count else { return 0 }
        let n = e.route[e.next], c = Self.centre(n)
        let d = dist[Self.index(n)]
        return Double(max(0, d)) / 10 + hypot(c.x - e.x, c.y - e.y) + (e.y < 0 ? -e.y : 0)
    }

    // MARK: Building

    enum Refusal: Equatable {
        case outside, taken, land, blocks, enemy, gold(Int)
    }

    /// Why a tower can't go here, if it can't — shutting every way is the one that matters most.
    func refusal(_ kind: WallKind, at t: WallTile) -> Refusal? {
        guard Self.inside(t) else { return .outside }
        let i = Self.index(t)
        if occupant[i] >= 0 { return .taken }
        guard buildable(t) else { return .land }
        for e in enemies where abs(e.x - (Double(t.x) + 0.5)) < 0.75 && abs(e.y - (Double(t.y) + 0.5)) < 0.75 { return .enemy }
        if shuts(t) { return .blocks }
        if gold < kind.cost { return .gold(kind.cost - gold) }
        return nil
    }

    /// Would shutting this tile leave a gap in the hills, or an enemy on the field, with no way to the pass?
    func shuts(_ t: WallTile) -> Bool {
        let i = Self.index(t)
        // A tile no way runs through can only cut off an enemy walking a way of its own through it.
        let onWay = routes.contains { $0.contains(t) } || enemies.contains { e in e.route[min(e.next, e.route.count)...].contains(t) }
        if !onWay && enemies.allSatisfy({ $0.layout == layout }) { return false }
        let f = flow(blocked: i)
        if !f.entriesReached(entries) { return true }
        for e in enemies {
            var here = e.tile
            if e.y < 0 { here = e.route.first ?? here }
            if Self.index(here) == i { continue }
            if f.at(here) < 0 { return true }
        }
        return false
    }

    @discardableResult
    mutating func build(_ kind: WallKind, at t: WallTile) -> Int? {
        guard refusal(kind, at: t) == nil else { return nil }
        let id = nextID; nextID += 1
        var tower = WallTower(id: id, kind: kind, x: t.x, y: t.y, hp: kind.stats(0).hp, invested: kind.cost)
        tower.built = time
        tower.cooldown = 0.3
        towers.append(tower)
        occupant[Self.index(t)] = id
        gold -= kind.cost; spent += kind.cost
        remap()
        return id
    }

    func upgradeCost(_ t: WallTower) -> Int? { t.level < 2 ? t.kind.upgrades[t.level] : nil }

    @discardableResult
    mutating func upgrade(_ id: Int) -> Bool {
        guard let i = towerIndex(id), let c = upgradeCost(towers[i]), gold >= c else { return false }
        gold -= c; spent += c
        let before = towers[i].stats.hp
        towers[i].level += 1
        towers[i].invested += c
        towers[i].hp += towers[i].stats.hp - before
        if towers[i].kind == .beacon { remap() }
        return true
    }

    func refund(_ t: WallTower) -> Int { Int((Double(t.invested) * Self.sellBack * max(0.3, t.hp / t.stats.hp)).rounded()) }

    @discardableResult
    mutating func sell(_ id: Int) -> Int {
        guard let i = towerIndex(id) else { return 0 }
        let t = towers[i], back = refund(t)
        gold += back
        remove(i)
        effects.append(WallEffect(kind: .dust(0.8), x: Double(t.x) + 0.5, y: Double(t.y) + 0.7, at: time, life: 0.8))
        return back
    }

    mutating func aim(_ id: Int, _ a: WallAim) { if let i = towerIndex(id) { towers[i].aim = a } }

    private mutating func remove(_ i: Int) {
        occupant[Self.index(towers[i].tile)] = -1
        let id = towers[i].id
        towers.remove(at: i)
        shots.removeAll { $0.tower == id && $0.kind == .arrow }
        remap()
    }

    // MARK: Waves

    /// The wave that comes next.
    var coming: WallWave { WallWave.make(wave + 1, seed: seed) }
    /// Has everything of the last wave come out of the hills?
    var spawned: Bool { queue.isEmpty }
    /// Gold for calling the next wave now rather than waiting.
    var earlyBonus: Int { spawned ? Int((max(0, clock) * 1.5).rounded()) : 0 }
    static func waveBonus(_ n: Int) -> Int { 20 + 3 * n }

    /// Bring on the next wave: gold for the wave, and for coming early.
    mutating func call() {
        guard !over, spawned else { return }
        let bonus = earlyBonus
        wave += 1
        let w = WallWave.make(wave, seed: seed)
        gold += Self.waveBonus(wave) + bonus
        earned += Self.waveBonus(wave) + bonus
        var at = max(time, spawnTime) + 0.4
        for s in w.spawns { queue.append((at, s.foe, wave)); at += s.gap }
        clock = Self.countdown
        moments.append(WallMoment(kind: w.boss ? .boss(wave) : .wave(wave), time: time))
    }

    private mutating func spawn(_ foe: WallFoe, wave n: Int) {
        let hpScale = WallWave.health(n) * (foe == .chanyu ? 1 + 0.25 * Double(n / 10 - 1) : 1)
        let k: Int = foe == .chanyu || foe == .guard ? 1 : Int(rng.int(3))
        let x0 = Double(entries[k]) + 0.5 + rng.range(0, 1)
        var e = WallEnemy(id: nextID, foe: foe, x: x0, y: -0.8, hp: foe.hp * hpScale, maxHP: foe.hp * hpScale,
                          speed: foe.speed * WallWave.pace(n) * rng.range(0.94, 1.06),
                          ox: foe == .siege || foe == .chanyu ? 0 : rng.range(-0.22, 0.22), oy: foe == .siege || foe == .chanyu ? 0 : rng.range(-0.22, 0.22),
                          seed: rng.int(10_000), born: time, wave: n)
        nextID += 1
        let start = WallTile(x: Int(floor(x0)), y: 0)
        e.route = route(from: open(start) ? start : WallTile(x: entries[k], y: 0))
        e.layout = layout
        enemies.append(e)
    }

    // MARK: Time

    mutating func step(_ dt: Double) {
        guard !over else { return }
        time += dt
        // The wave clock runs once the last wave is out.
        if spawned, wave > 0 || time > 0.5 {
            clock -= dt
            if clock <= 0 { call() }
        }
        while let first = queue.first, first.at <= time {
            queue.removeFirst()
            spawn(first.foe, wave: first.wave)
            spawnTime = time
        }
        moveEnemies(dt)
        burn(dt)
        shoot(dt)
        fly(dt)
        repair(dt)
        reap()
        effects.removeAll { time - $0.at > $0.life }
        fires.removeAll { $0.until < time }
        if moments.count > 40 { moments.removeFirst(moments.count - 40) }
        if lives <= 0, !over {
            lives = 0; over = true
            moments.append(WallMoment(kind: .lost, time: time))
        }
    }

    private mutating func reroute(_ i: Int) {
        var e = enemies[i]
        var start = e.next < e.route.count ? e.route[e.next] : e.tile
        if e.y < 0 { start = e.route.first ?? WallTile(x: entries[1], y: 0) }
        if !open(start) { start = e.tile }
        if !open(start) {
            // Standing where something now stands (a tower built on a tile it had just left): the nearest open tile beside it.
            start = WallTile.neighbours(e.tile).filter { open($0) }.min { dist[Self.index($0)] < dist[Self.index($1)] } ?? start
        }
        let r = route(from: start)
        if !r.isEmpty { e.route = r; e.next = 0 }
        e.layout = layout
        enemies[i] = e
    }

    private mutating func moveEnemies(_ dt: Double) {
        var leaks: [Int] = []
        for i in enemies.indices {
            if enemies[i].layout != layout { reroute(i) }
            var e = enemies[i]
            e.cooldown -= dt
            // Siege carts and the Chanyu smash towers in reach as they go.
            if e.foe.breaker, e.cooldown <= 0 {
                if let k = towers.indices.filter({ hypot(towers[$0].centre.x - e.x, towers[$0].centre.y - e.y) <= 1.5 }).min(by: {
                    hypot(towers[$0].centre.x - e.x, towers[$0].centre.y - e.y) < hypot(towers[$1].centre.x - e.x, towers[$1].centre.y - e.y) }) {
                    let hit = (e.foe == .chanyu ? 45.0 : 35.0) * WallWave.pace(e.wave)
                    towers[k].hp -= hit
                    towers[k].hurt = time
                    e.cooldown = 1
                    e.ramming = time
                    effects.append(WallEffect(kind: .dust(0.45), x: towers[k].centre.x, y: towers[k].centre.y + 0.2, at: time, life: 0.6))
                } else { e.cooldown = 0.25 }
            }
            // Shamans heal those near them.
            if e.foe == .shaman, e.cooldown <= 0 {
                e.cooldown = 1
                var any = false
                for j in enemies.indices where j != i && enemies[j].hp < enemies[j].maxHP {
                    if hypot(enemies[j].x - e.x, enemies[j].y - e.y) <= 1.9 {
                        enemies[j].hp = min(enemies[j].maxHP, enemies[j].hp + min(enemies[j].maxHP * 0.06, 18 * WallWave.health(e.wave)))
                        enemies[j].healed = time
                        any = true
                    }
                }
                if any { effects.append(WallEffect(kind: .heal, x: e.x, y: e.y, at: time, life: 0.9)); e.healed = time }
            }
            // Walk.
            var budget = e.speed * dt * (e.foe.breaker && time - e.ramming < 0.5 ? 0.5 : 1)
            while budget > 0, e.next < e.route.count {
                let t = e.route[e.next]
                let last = e.next == e.route.count - 1
                let tx = Double(t.x) + 0.5 + (last ? 0 : e.ox), ty = Double(t.y) + 0.5 + (last ? 0 : e.oy)
                let dx = tx - e.x, dy = ty - e.y, d = hypot(dx, dy)
                if abs(dx) > 0.02 { e.facing = dx > 0 ? 1 : -1 }
                if d <= budget { e.x = tx; e.y = ty; budget -= d; e.next += 1 }
                else { e.x += dx / d * budget; e.y += dy / d * budget; budget = 0 }
            }
            if e.next >= e.route.count, !e.route.isEmpty { leaks.append(i) }
            enemies[i] = e
        }
        for i in leaks.reversed() {
            let e = enemies[i]
            lives -= e.foe.lives
            leaked += 1
            effects.append(WallEffect(kind: .leak(e.foe.lives), x: e.x, y: e.y, at: time, life: 1.6))
            moments.append(WallMoment(kind: .leak(e.foe, e.foe.lives), time: time))
            enemies.remove(at: i)
        }
    }

    /// Fire on the ground, and the barricades' spikes (and the hacking at them).
    private mutating func burn(_ dt: Double) {
        for f in fires {
            for i in enemies.indices where hypot(enemies[i].x - f.x, enemies[i].y - f.y) <= f.radius {
                hurt(i, f.dps * dt, .fire, by: f.tower, flash: false)
                enemies[i].burning = time
            }
        }
        for k in towers.indices where towers[k].kind == .barricade {
            let c = towers[k].centre, s = towers[k].stats
            for i in enemies.indices where abs(enemies[i].x - c.x) < 1.25 && abs(enemies[i].y - c.y) < 1.25 {
                hurt(i, s.damage * dt, .spike, by: towers[k].id, flash: false)
                if enemies[i].foe.hacks {
                    towers[k].hp -= (enemies[i].foe == .siege || enemies[i].foe == .chanyu ? 0 : 5 * WallWave.pace(enemies[i].wave)) * dt
                    towers[k].hurt = time
                }
            }
        }
    }

    private func pick(_ t: WallTower, range: Double) -> Int? {
        let c = t.centre, minR = t.stats.minRange
        var best: Int?, score = Double.infinity
        for (i, e) in enemies.enumerated() where e.hp > 0 && e.y > -0.3 {
            let d = hypot(e.x - c.x, e.y - c.y)
            guard d <= range, d >= minR else { continue }
            let s: Double
            switch t.aim {
            case .first: s = remaining(e)
            case .strongest: s = -e.hp
            case .nearest: s = d
            }
            if s < score { score = s; best = i }
        }
        return best
    }

    /// Where an enemy will be in `ahead` seconds, walking its way.
    func lead(_ e: WallEnemy, _ ahead: Double) -> (x: Double, y: Double) {
        var x = e.x, y = e.y, budget = e.speed * ahead, k = e.next
        while budget > 0, k < e.route.count {
            let t = e.route[k], tx = Double(t.x) + 0.5 + e.ox, ty = Double(t.y) + 0.5 + e.oy
            let d = hypot(tx - x, ty - y)
            if d <= budget { x = tx; y = ty; budget -= d; k += 1 } else { x += (tx - x) / d * budget; y += (ty - y) / d * budget; budget = 0 }
        }
        return (x, y)
    }

    private mutating func shoot(_ dt: Double) {
        for k in towers.indices where towers[k].kind.shoots {
            towers[k].cooldown -= dt
            guard towers[k].cooldown <= 0 else { continue }
            let t = towers[k], s = t.stats
            guard let i = pick(t, range: range(of: t)) else { towers[k].cooldown = 0.1; continue }
            let e = enemies[i], c = t.centre
            let dmg = damage(of: t)
            towers[k].cooldown = 1 / s.rate
            towers[k].fired = time
            switch t.kind {
            case .arrow:
                let d = hypot(e.x - c.x, e.y - c.y)
                shots.append(WallShot(kind: .arrow, tower: t.id, fromX: c.x, fromY: c.y - 0.2, toX: e.x, toY: e.y, target: e.id, duration: max(0.08, d / 12), damage: dmg))
                towers[k].angle = atan2(e.y - c.y, e.x - c.x)
            case .ballista:
                let p = lead(e, hypot(e.x - c.x, e.y - c.y) / 16)
                var dx = p.x - c.x, dy = p.y - c.y
                let d = max(0.01, hypot(dx, dy)); dx /= d; dy /= d
                let reach = range(of: t) + 1.2
                towers[k].angle = atan2(dy, dx)
                shots.append(WallShot(kind: .bolt, tower: t.id, fromX: c.x, fromY: c.y, toX: c.x + dx * reach, toY: c.y + dy * reach, target: nil,
                                      duration: reach / 16, damage: dmg, dx: dx, dy: dy, reach: reach, pierce: s.pierce))
            case .trebuchet:
                let flight = 1.15
                let p = lead(e, flight)
                shots.append(WallShot(kind: .stone, tower: t.id, fromX: c.x, fromY: c.y - 0.3, toX: p.x, toY: p.y, target: nil, duration: flight, damage: dmg, splash: s.splash))
                towers[k].angle = atan2(p.y - c.y, p.x - c.x)
            case .fire:
                let flight = 0.6
                let p = lead(e, flight + 0.3)
                shots.append(WallShot(kind: .pot, tower: t.id, fromX: c.x, fromY: c.y - 0.2, toX: p.x, toY: p.y, target: nil, duration: flight, damage: dmg, splash: s.splash, burn: s.burn))
                towers[k].angle = atan2(p.y - c.y, p.x - c.x)
            default: break
            }
        }
    }

    private mutating func fly(_ dt: Double) {
        var gone: [Int] = []
        for s in shots.indices {
            var shot = shots[s]
            let before = shot.t
            shot.t = min(1, shot.t + dt / shot.duration)
            switch shot.kind {
            case .arrow:
                if let id = shot.target, let i = enemies.firstIndex(where: { $0.id == id }) {
                    shot.toX = enemies[i].x; shot.toY = enemies[i].y
                    if shot.t >= 1 { hurt(i, shot.damage, .arrow, by: shot.tower); gone.append(s) }
                } else {
                    shot.target = nil
                    if shot.t >= 1 { gone.append(s) }
                }
            case .bolt:
                // Everything the bolt passes through on this step, up to its pierce.
                let x0 = shot.fromX + (shot.toX - shot.fromX) * before, y0 = shot.fromY + (shot.toY - shot.fromY) * before
                let x1 = shot.x, y1 = shot.y
                for i in enemies.indices where shot.struck.count < shot.pierce && !shot.struck.contains(enemies[i].id) {
                    let e = enemies[i]
                    let vx = x1 - x0, vy = y1 - y0, L2 = max(1e-6, vx * vx + vy * vy)
                    let u = max(0, min(1, ((e.x - x0) * vx + (e.y - y0) * vy) / L2))
                    let px = x0 + vx * u, py = y0 + vy * u
                    if hypot(e.x - px, e.y - py) <= (e.foe == .siege || e.foe == .chanyu ? 0.6 : 0.42) {
                        hurt(i, shot.damage * pow(0.85, Double(shot.struck.count)), .bolt, by: shot.tower)
                        shot.struck.append(e.id)
                    }
                }
                if shot.t >= 1 || shot.struck.count >= shot.pierce { gone.append(s) }
            case .stone, .pot:
                if shot.t >= 1 {
                    gone.append(s)
                    if shot.kind == .stone {
                        for i in enemies.indices {
                            let d = hypot(enemies[i].x - shot.toX, enemies[i].y - shot.toY)
                            if d <= shot.splash { hurt(i, shot.damage * (1 - 0.5 * d / shot.splash), .stone, by: shot.tower) }
                        }
                        effects.append(WallEffect(kind: .blast(shot.splash * 0.55), x: shot.toX, y: shot.toY, at: time, life: 0.9))
                    } else {
                        fires.append(WallFire(x: shot.toX, y: shot.toY, radius: shot.splash, dps: shot.damage, from: time, until: time + shot.burn, tower: shot.tower))
                        effects.append(WallEffect(kind: .blast(shot.splash * 0.45), x: shot.toX, y: shot.toY, at: time, life: 0.7))
                    }
                }
            }
            shots[s] = shot
        }
        for s in gone.reversed() { shots.remove(at: s) }
    }

    private mutating func hurt(_ i: Int, _ amount: Double, _ kind: WallDamage, by tower: Int, flash: Bool = true) {
        guard enemies.indices.contains(i), enemies[i].hp > 0 else { return }
        let dealt = amount * enemies[i].foe.takes(kind)
        enemies[i].hp -= dealt
        if flash { enemies[i].hit = time }
        if let k = towers.firstIndex(where: { $0.id == tower }) {
            towers[k].dealt += dealt
            if enemies[i].hp <= 0 { towers[k].kills += 1 }
        }
    }

    private mutating func repair(_ dt: Double) {
        var broken: [Int] = []
        for k in towers.indices {
            if towers[k].hp <= 0 { broken.append(k); continue }
            let full = towers[k].stats.hp
            if towers[k].hp < full, time - towers[k].hurt > 4 { towers[k].hp = min(full, towers[k].hp + full * 0.03 * dt) }
        }
        for k in broken.reversed() {
            let t = towers[k]
            let by = enemies.filter { $0.foe.breaker || $0.foe.hacks }.min { hypot($0.x - t.centre.x, $0.y - t.centre.y) < hypot($1.x - t.centre.x, $1.y - t.centre.y) }?.foe ?? .siege
            effects.append(WallEffect(kind: .crumble(t.kind), x: t.centre.x, y: t.centre.y + 0.3, at: time, life: 1.4))
            effects.append(WallEffect(kind: .blast(0.5), x: t.centre.x, y: t.centre.y, at: time, life: 1))
            moments.append(WallMoment(kind: .destroyed(t.kind, by), time: time))
            remove(k)
        }
    }

    /// The dead fall and pay.
    private mutating func reap() {
        var k = enemies.count - 1
        while k >= 0 {
            let e = enemies[k]
            if e.hp <= 0 {
                let pay = e.foe.gold
                gold += pay; earned += pay; kills += 1; killsBy[e.foe.rawValue] += 1
                if e.foe == .chanyu { bossesKilled += 1; effects.append(WallEffect(kind: .blast(1.4), x: e.x, y: e.y - 0.3, at: time, life: 1.2)) }
                effects.append(WallEffect(kind: .fallen(e.foe, e.facing), x: e.x, y: e.y, at: time, life: 2.2))
                effects.append(WallEffect(kind: .gold(pay), x: e.x, y: e.y - 0.6, at: time, life: 1.0))
                enemies.remove(at: k)
            }
            k -= 1
        }
        if effects.count > 260 { effects.removeFirst(effects.count - 260) }
    }

    // MARK: Measures for the brain and the words

    /// Tiles of the ways (counted once per gap that walks them) within a reach of a point, beyond a nearest distance.
    static func cover(_ routes: [[WallTile]], x: Double, y: Double, range: Double, minRange: Double = 0) -> Double {
        var n = 0.0
        for r in routes {
            for t in r {
                let d = hypot(Double(t.x) + 0.5 - x, Double(t.y) + 0.5 - y)
                if d <= range && d >= minRange { n += 1 }
            }
        }
        return n / Double(max(1, routes.count))
    }

    /// The ways from the three gaps with one more tile shut, or nil if that shuts them.
    func routes(blocking t: WallTile) -> [[WallTile]]? {
        let i = Self.index(t)
        let r = entries.map { route(from: WallTile(x: $0, y: 0), blocked: i) }
        return r.contains { $0.isEmpty } ? nil : r
    }

    /// The ways from the three gaps with several tiles shut, or nil if that shuts them.
    func routes(blocking tiles: [WallTile]) -> [[WallTile]]? {
        var shut = Array(repeating: false, count: Self.width * Self.height)
        for t in tiles where Self.inside(t) { shut[Self.index(t)] = true }
        let r = entries.map { route(from: WallTile(x: $0, y: 0), shut: shut) }
        return r.contains { $0.isEmpty } ? nil : r
    }

    /// The rows of water, lowest.
    var riverBottom: Int { (0..<Self.height).filter { y in (0..<Self.width).contains { ground[y * Self.width + $0] == .water || ground[y * Self.width + $0] == .ford } }.max() ?? 8 }

    /// Enemies on the field.
    var alive: Int { enemies.count }
}

extension WallTile {
    static func neighbours(_ t: WallTile) -> [WallTile] {
        WallField.steps.map { WallTile(x: t.x + $0.0, y: t.y + $0.1) }
    }
}
