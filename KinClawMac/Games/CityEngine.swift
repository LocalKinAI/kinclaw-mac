import Foundation

/// 放逐之城 — a town that has to get through its winters. Foundation only, so
/// it runs headless: a mayor can be tried for twenty years in a second.
///
/// The year: in spring the fields are planted, in summer they grow and the
/// woods give berries and mushrooms, in autumn the harvest comes in, and in
/// winter every house burns firewood or the family in it freezes. Everybody
/// eats every month. People are born into houses with room, grow up at twelve,
/// work until sixty-five, and die of age — or of hunger, or of cold. Newcomers
/// arrive in spring when there are empty houses and food to spare. The mayor
/// decides what is built where and how many work at each place; the people do
/// the rest themselves — fetching, carrying, building, felling, fishing,
/// planting and harvesting — walking the paths and the roads between.

struct CityTile: Hashable { var x: Int, y: Int }

enum CityGood: Int, CaseIterable { case food, logs, stone, iron, firewood, tools }

enum CityGround: UInt8 { case grass, forest, rock, ore, water }

enum CityKind: Int, CaseIterable {
    case townHall, house, storage, field, gatherer, forester, woodcutter, quarry, mine, blacksmith, fishery
}

enum CityTask: Equatable {
    case idle
    /// Standing about for a few seconds.
    case pause(Double)
    case wander(CityTile)
    case goHome
    /// At a workplace: a quarry, a mine, a woodcutter's, a smithy, a field.
    case work(Int)
    /// A tree to fell, a forest floor to forage, water to fish.
    case harvest(CityTile)
    /// Carrying the load to a storage.
    case store(Int)
    /// To a storage for a good — for a house, a building site or a workshop.
    case fetch(Int, CityGood, Int)
    /// Carrying it there.
    case bring(Int)
    case build(Int)
}

struct CityPerson {
    let id: Int
    var x: Double, y: Double
    var age: Double
    var home: Int? = nil
    var job: Int? = nil
    var task: CityTask = .idle
    var path: [CityTile] = []
    var repath = 0.0
    var carrying: CityGood? = nil
    var amount = 0.0
    var health = 1.0
    /// Months in a row without food, and heating months without warmth.
    var hungry = 0, cold = 0
    var busy = 0.0
    var facing = 1.0
    /// Seconds since the last stroke of work, for drawing.
    var swung = 9.0
    /// Resting indoors: not on the map.
    var inside = false
    var adult: Bool { age >= 12 }
    var retired: Bool { age >= 65 }
    var worker: Bool { adult && !retired }
}

struct CityBuilding {
    let id: Int
    let kind: CityKind
    let x: Int, y: Int
    var done = false
    var progress = 0.0
    /// Materials brought to the site so far.
    var delivered = [Double](repeating: 0, count: 6)
    /// A storage's goods; a house's food and firewood; a workshop's inputs and outputs.
    var stock = [Double](repeating: 0, count: 6)
    /// How many the mayor wants working here.
    var wanted = 0
    /// Fields: how much of the field is planted, how far the crop has grown, how much is in.
    var planted = 0.0, grown = 0.0, harvested = 0.0
    /// Quarries and mines: what is left in the ground.
    var reserve = 0.0
    /// Houses: who is out fetching for it, so that one goes and not the whole family.
    var fetcher: Int? = nil
    /// What its workers have brought in this year, and last year.
    var output = 0.0, lastOutput = 0.0
}

struct CityEvent {
    enum Cause: String { case hunger, cold, age }
    enum Kind: Equatable { case born, died(Cause), arrived(Int), finished(CityKind), newYear(Int), felled, harvested }
    let kind: Kind
    let x: Double, y: Double
    let time: Double
}

struct CityWorld {
    static let width = 64, height = 40
    /// Seconds of play in a month; a year is four minutes at 1×.
    static let month = 20.0
    static let monthNames = ["早春", "仲春", "暮春", "初夏", "盛夏", "夏末", "初秋", "仲秋", "深秋", "初冬", "隆冬", "冬末"]
    static let goodNames = ["食物", "木头", "石头", "铁", "柴火", "工具"]
    static let kindNames = ["市政厅", "房屋", "仓库", "农田", "采集小屋", "伐木场", "柴房", "采石场", "铁矿", "铁匠铺", "渔屋"]

    var ground: [CityGround]
    /// Forest tiles: 1 is a grown tree; less is a stump growing back.
    var wood: [Double]
    /// Forest tiles: berries and mushrooms left this year.
    var forage: [Double]
    var fish: [Double]
    var fertility: [Double]
    var road: [Bool]
    var occupant: [Int?]
    var buildings: [CityBuilding] = []
    var people: [CityPerson] = []
    var time = 0.0
    var nextID = 1
    var rng: UInt64
    var events: [CityEvent] = []
    var deaths: [String: Int] = [:]
    var births = 0, arrivals = 0
    /// What was made in each of the last twelve months, by good — for "this past year".
    var made: [[Double]] = Array(repeating: Array(repeating: 0, count: 6), count: 12)
    /// What was eaten and burned in each of the last twelve months.
    var used: [[Double]] = Array(repeating: Array(repeating: 0, count: 6), count: 12)
    /// Tools worn but not yet taken from storage.
    var wear = 0.0
    /// The town at the start of each month: people, food, firewood — for the chart.
    var history: [(people: Int, food: Double, firewood: Double)] = []
    private var lastMonth = 0
    private var staffClock = 0.0

    // MARK: The calendar

    var monthNumber: Int { Int(time / Self.month) }
    var monthOfYear: Int { monthNumber % 12 }
    var year: Int { monthNumber / 12 + 1 }
    /// 0 spring, 1 summer, 2 autumn, 3 winter.
    var season: Int { monthOfYear / 3 }
    /// The months a house burns firewood: the three of winter and the first of spring.
    static func heats(_ month: Int) -> Bool { month >= 9 || month == 0 }
    var over: Bool { people.isEmpty }

    // MARK: The rules

    static func size(_ k: CityKind) -> Int { [3, 2, 3, 4, 2, 2, 2, 3, 3, 2, 2][k.rawValue] }
    /// Food, logs, stone, iron, firewood, tools.
    static func cost(_ k: CityKind) -> [Double] {
        switch k {
        case .townHall: return [0, 0, 0, 0, 0, 0]
        case .house: return [0, 24, 8, 0, 0, 0]
        case .storage: return [0, 40, 16, 0, 0, 0]
        case .field: return [0, 0, 0, 0, 0, 0]
        case .gatherer: return [0, 20, 0, 0, 0, 0]
        case .forester: return [0, 24, 6, 0, 0, 0]
        case .woodcutter: return [0, 20, 10, 0, 0, 0]
        case .quarry: return [0, 30, 0, 0, 0, 0]
        case .mine: return [0, 40, 20, 0, 0, 0]
        case .blacksmith: return [0, 30, 30, 0, 0, 0]
        case .fishery: return [0, 24, 6, 0, 0, 0]
        }
    }
    /// Seconds for one builder to put it up.
    static func work(_ k: CityKind) -> Double { [60, 24, 36, 8, 16, 20, 20, 28, 36, 32, 20][k.rawValue] }
    static func slots(_ k: CityKind) -> Int { [0, 0, 0, 2, 3, 3, 2, 4, 4, 2, 3][k.rawValue] }
    static func capacity(_ k: CityKind) -> Double { k == .townHall ? 800 : k == .storage ? 600 : 0 }
    static func stores(_ k: CityKind) -> Bool { k == .townHall || k == .storage }
    static let houseRoom = 5
    /// How far from its lodge a gatherer, a woodcutter or a fisherman goes.
    static let reach = 8
    static func inside(_ t: CityTile) -> Bool { t.x >= 0 && t.y >= 0 && t.x < width && t.y < height }
    static func index(_ t: CityTile) -> Int { t.y * width + t.x }

    // MARK: Making the land

    init(seed: UInt64) {
        let n = Self.width * Self.height
        ground = Array(repeating: .grass, count: n)
        wood = Array(repeating: 0, count: n); forage = Array(repeating: 0, count: n); fish = Array(repeating: 0, count: n)
        fertility = Array(repeating: 1, count: n); road = Array(repeating: false, count: n)
        occupant = Array(repeating: nil, count: n)
        rng = seed &* 0x9E3779B97F4A7C15 | 1
        for _ in 0..<4 { _ = roll(2) }

        // Smooth noise: random values on a coarse lattice, blended.
        func noise(_ cell: Double) -> [Double] {
            let gw = Int(Double(Self.width) / cell) + 2, gh = Int(Double(Self.height) / cell) + 2
            var lattice = [Double](repeating: 0, count: gw * gh)
            for i in lattice.indices { lattice[i] = Double(roll(1000)) / 1000 }
            var out = [Double](repeating: 0, count: n)
            for y in 0..<Self.height {
                for x in 0..<Self.width {
                    let fx = Double(x) / cell, fy = Double(y) / cell
                    let x0 = Int(fx), y0 = Int(fy), tx = fx - Double(x0), ty = fy - Double(y0)
                    let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
                    let a = lattice[y0 * gw + x0], b = lattice[y0 * gw + x0 + 1], c = lattice[(y0 + 1) * gw + x0], d = lattice[(y0 + 1) * gw + x0 + 1]
                    out[y * Self.width + x] = (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
                }
            }
            return out
        }
        let woods = noise(6.5), grain = noise(2.5), soil = noise(8)
        let hall = CityTile(x: 26 + roll(5) - 2, y: 18 + roll(5) - 2)

        // A river from the top of the map to the bottom, east of the town, with two fords.
        let phase = Double(roll(628)) / 100, bend = 2.5 + Double(roll(20)) / 10
        let fords = [8 + roll(6), 26 + roll(6)]
        for y in 0..<Self.height {
            let cx = 45 + bend * sin(Double(y) * 0.22 + phase) + 1.2 * sin(Double(y) * 0.61 + phase * 2)
            let half = 1.1 + 0.5 * sin(Double(y) * 0.4 + phase)
            for x in Int((cx - half).rounded())...Int((cx + half).rounded()) where x >= 0 && x < Self.width {
                if fords.contains(where: { abs($0 - y) <= 1 }) { continue }
                ground[y * Self.width + x] = .water
            }
        }
        // A pond to the south-west.
        let pond = CityTile(x: 10 + roll(6), y: 30 + roll(5))
        for y in 0..<Self.height { for x in 0..<Self.width {
            let d = hypot(Double(x - pond.x) / 3.2, Double(y - pond.y) / 2.2) + (grain[y * Self.width + x] - 0.5) * 0.5
            if d < 1 { ground[y * Self.width + x] = .water }
        } }
        // Woods where the noise is high, thicker toward the edges of the map.
        for y in 0..<Self.height {
            for x in 0..<Self.width where ground[y * Self.width + x] == .grass {
                let i = y * Self.width + x
                let edge = max(0, 1 - Double(min(x, Self.width - 1 - x, y, Self.height - 1 - y)) / 9)
                let fromHall = hypot(Double(x - hall.x), Double(y - hall.y))
                if woods[i] * 0.8 + grain[i] * 0.2 + edge * 0.28 - (fromHall < 9 ? 0.25 : 0) > 0.6 { ground[i] = .forest }
            }
        }
        // Rock and ore: a few outcrops, the stone near the town, the iron further out.
        func outcrop(_ kind: CityGround, near: CityTile, from lo: Double, to hi: Double, size: Int) {
            for _ in 0..<60 {
                let a = Double(roll(628)) / 100, r = lo + Double(roll(Int((hi - lo) * 10))) / 10
                let c = CityTile(x: near.x + Int(cos(a) * r), y: near.y + Int(sin(a) * r * 0.8))
                guard c.x > 2, c.y > 2, c.x < Self.width - 3, c.y < Self.height - 3, ground[Self.index(c)] != .water else { continue }
                for y in (c.y - 4)...(c.y + 4) { for x in (c.x - 4)...(c.x + 4) where Self.inside(CityTile(x: x, y: y)) && ground[y * Self.width + x] == .forest && hypot(Double(x - c.x), Double(y - c.y)) < 4.5 {
                    ground[y * Self.width + x] = .grass
                } }
                var placed = 0, at = c
                while placed < size {
                    if Self.inside(at), ground[Self.index(at)] != .water, ground[Self.index(at)] != kind {
                        ground[Self.index(at)] = kind; placed += 1
                    }
                    at = CityTile(x: at.x + roll(3) - 1, y: at.y + roll(3) - 1)
                    if !Self.inside(at) || hypot(Double(at.x - c.x), Double(at.y - c.y)) > 3 { at = c }
                }
                return
            }
        }
        outcrop(.rock, near: hall, from: 8, to: 13, size: 7)
        outcrop(.rock, near: hall, from: 14, to: 22, size: 8)
        outcrop(.ore, near: hall, from: 15, to: 22, size: 6)
        outcrop(.ore, near: CityTile(x: 54, y: hall.y), from: 3, to: 10, size: 7)
        for i in 0..<n {
            switch ground[i] {
            case .forest: wood[i] = 1; forage[i] = 3
            case .water: fish[i] = 10
            default: break
            }
            fertility[i] = 0.7 + soil[i] * 0.6
        }
        // Clear ground for the town hall, and the first families beside it.
        for y in (hall.y - 3)...(hall.y + 5) { for x in (hall.x - 3)...(hall.x + 5) where Self.inside(CityTile(x: x, y: y)) {
            let i = y * Self.width + x
            if ground[i] != .water { ground[i] = .grass; wood[i] = 0; forage[i] = 0 }
        } }
        let id = place(.townHall, at: hall, done: true)!
        let b = buildingIndex(id)!
        buildings[b].stock = [260, 110, 44, 0, 30, 30]
        let ages: [Double] = [31, 29, 26, 24, 34, 30, 22, 21, 27, 25, 9, 7, 5, 3, 2]
        for (k, age) in ages.enumerated() {
            let a = Double(k) * 0.42
            people.append(CityPerson(id: nextID, x: Double(hall.x) + 1.5 + cos(a) * 2.6, y: Double(hall.y) + 1.5 + sin(a) * 2.6, age: age))
            nextID += 1
        }
    }

    mutating func roll(_ n: Int) -> Int {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Int(rng % UInt64(max(n, 1)))
    }
    mutating func chance(_ p: Double) -> Bool { Double(roll(100_000)) / 100_000 < p }

    // MARK: Looking things up

    func building(_ id: Int) -> CityBuilding? { buildings.first { $0.id == id } }
    func buildingIndex(_ id: Int) -> Int? { buildings.firstIndex { $0.id == id } }
    func personIndex(_ id: Int) -> Int? { people.firstIndex { $0.id == id } }
    var hall: CityBuilding? { buildings.first { $0.kind == .townHall } }
    func tile(of p: CityPerson) -> CityTile { CityTile(x: Int(p.x), y: Int(p.y)) }
    func centre(_ b: CityBuilding) -> (x: Double, y: Double) { (Double(b.x) + Double(Self.size(b.kind)) / 2, Double(b.y) + Double(Self.size(b.kind)) / 2) }
    func distance(_ b: CityBuilding, _ x: Double, _ y: Double) -> Double { let c = centre(b); return hypot(c.x - x, c.y - y) }
    func residents(_ id: Int) -> Int { people.reduce(0) { $0 + ($1.home == id ? 1 : 0) } }
    func workers(_ id: Int) -> Int { people.reduce(0) { $0 + ($1.job == id ? 1 : 0) } }
    /// What the storages hold.
    func stored(_ g: CityGood) -> Double { buildings.reduce(0) { $0 + ($1.done && Self.stores($1.kind) ? $1.stock[g.rawValue] : 0) } }
    /// What the houses hold, fetched home.
    func atHome(_ g: CityGood) -> Double { buildings.reduce(0) { $0 + ($1.kind == .house ? $1.stock[g.rawValue] : 0) } }
    func room(_ b: CityBuilding) -> Double { Self.capacity(b.kind) - b.stock.reduce(0, +) }
    var houseRoom: Int { buildings.filter { $0.kind == .house && $0.done }.count * Self.houseRoom }
    var homeless: Int { people.filter { $0.home == nil }.count }
    /// Made, and used, over the last twelve months.
    func madeLastYear(_ g: CityGood) -> Double { made.reduce(0) { $0 + $1[g.rawValue] } }
    func usedLastYear(_ g: CityGood) -> Double { used.reduce(0) { $0 + $1[g.rawValue] } }
    var toolless: Bool { stored(.tools) < 1 }

    // MARK: Placing things

    func fits(_ k: CityKind, at o: CityTile) -> Bool {
        let n = Self.size(k)
        for dy in 0..<n { for dx in 0..<n {
            let t = CityTile(x: o.x + dx, y: o.y + dy)
            guard Self.inside(t) else { return false }
            let i = Self.index(t)
            guard ground[i] == .grass, occupant[i] == nil else { return false }
        } }
        switch k {
        case .quarry: return near(.rock, o, n, 1) > 0
        case .mine: return near(.ore, o, n, 1) > 0
        case .fishery: return near(.water, o, n, 1) > 0
        default: return true
        }
    }

    /// How many tiles of a kind lie within `r` of a footprint.
    func near(_ kind: CityGround, _ o: CityTile, _ n: Int, _ r: Int) -> Int {
        var count = 0
        for y in (o.y - r)..<(o.y + n + r) { for x in (o.x - r)..<(o.x + n + r) where Self.inside(CityTile(x: x, y: y)) && ground[y * Self.width + x] == kind { count += 1 } }
        return count
    }

    @discardableResult
    mutating func place(_ k: CityKind, at o: CityTile, done: Bool = false) -> Int? {
        guard fits(k, at: o) else { return nil }
        let id = nextID; nextID += 1
        var b = CityBuilding(id: id, kind: k, x: o.x, y: o.y, done: done)
        if done { b.progress = 1; b.delivered = Self.cost(k) }
        let n = Self.size(k)
        if k == .quarry { b.reserve = Double(near(.rock, o, n, 2)) * 120 }
        if k == .mine { b.reserve = Double(near(.ore, o, n, 2)) * 90 }
        buildings.append(b)
        for dy in 0..<n { for dx in 0..<n { occupant[Self.index(CityTile(x: o.x + dx, y: o.y + dy))] = id; road[Self.index(CityTile(x: o.x + dx, y: o.y + dy))] = false } }
        return id
    }

    /// Take a building down: its workers and its family go free, half of what went into it comes back.
    mutating func remove(_ id: Int) {
        guard let bi = buildingIndex(id), buildings[bi].kind != .townHall else { return }
        let b = buildings[bi], n = Self.size(b.kind)
        for dy in 0..<n { for dx in 0..<n { occupant[Self.index(CityTile(x: b.x + dx, y: b.y + dy))] = nil } }
        for i in people.indices {
            if people[i].job == id { people[i].job = nil }
            if people[i].home == id { people[i].home = nil }
            switch people[i].task {
            case .work(id), .store(id), .bring(id), .build(id): people[i].task = .idle
            case .fetch(let s, _, let f) where s == id || f == id: people[i].task = .idle
            default: break
            }
        }
        buildings.remove(at: bi)
        let back = b.delivered.map { $0 / 2 }
        if let s = nearestStorage(Double(b.x), Double(b.y), room: 0) { deposit(back, into: s) }
    }

    /// A road on open grass.
    @discardableResult
    mutating func lay(road t: CityTile) -> Bool {
        guard Self.inside(t), ground[Self.index(t)] == .grass, occupant[Self.index(t)] == nil, !road[Self.index(t)] else { return false }
        road[Self.index(t)] = true
        return true
    }
    mutating func unlay(road t: CityTile) { if Self.inside(t) { road[Self.index(t)] = false } }

    // MARK: Storage

    func nearestStorage(_ x: Double, _ y: Double, room: Double) -> Int? {
        buildings.filter { $0.done && Self.stores($0.kind) && self.room($0) >= room }
            .min { distance($0, x, y) < distance($1, x, y) }?.id
    }
    func storage(with g: CityGood, _ x: Double, _ y: Double, atLeast: Double = 1) -> Int? {
        buildings.filter { $0.done && Self.stores($0.kind) && $0.stock[g.rawValue] >= atLeast }
            .min { distance($0, x, y) < distance($1, x, y) }?.id
    }
    mutating func deposit(_ goods: [Double], into id: Int) {
        guard let s = buildingIndex(id) else { return }
        for g in 0..<6 { buildings[s].stock[g] += goods[g] }
    }
    /// Take from the storages, the fullest first; returns how much there was.
    mutating func take(_ g: CityGood, _ amount: Double) -> Double {
        var left = amount
        for s in buildings.indices.filter({ buildings[$0].done && Self.stores(buildings[$0].kind) }).sorted(by: { buildings[$0].stock[g.rawValue] > buildings[$1].stock[g.rawValue] }) {
            let t = min(left, buildings[s].stock[g.rawValue])
            buildings[s].stock[g.rawValue] -= t; left -= t
            if left <= 0 { break }
        }
        return amount - left
    }
    private mutating func note(made g: CityGood, _ n: Double, by i: Int? = nil) {
        made[monthNumber % 12][g.rawValue] += n
        if let i, let job = people[i].job, let b = buildingIndex(job) { buildings[b].output += n }
    }

    // MARK: Walking

    func walkable(_ t: CityTile) -> Bool {
        guard Self.inside(t) else { return false }
        let i = Self.index(t)
        if let b = occupant[i] { return building(b)?.kind == .field }
        return ground[i] == .grass || ground[i] == .forest
    }
    func stepCost(_ i: Int) -> Double { road[i] ? 0.55 : ground[i] == .forest ? 1.7 : 1 }

    /// A* over the tiles, eight ways, without cutting corners past walls and water.
    func path(from start: CityTile, to goals: Set<CityTile>) -> [CityTile]? {
        guard !goals.isEmpty else { return nil }
        if goals.contains(start) { return [] }
        let w = Self.width, n = Self.width * Self.height
        var g = [Double](repeating: .infinity, count: n), came = [Int](repeating: -1, count: n), closed = [Bool](repeating: false, count: n)
        let goalIndex = Set(goals.map(Self.index))
        let gx = goals.map(\.x), gy = goals.map(\.y)
        func guess(_ i: Int) -> Double {
            let x = i % w, y = i / w
            var best = Int.max
            for k in gx.indices { best = min(best, max(abs(gx[k] - x), abs(gy[k] - y))) }
            return Double(best) * 0.55
        }
        var heap = CityHeap()
        let s = Self.index(start)
        g[s] = 0; heap.push(guess(s), s)
        var expanded = 0
        while let current = heap.pop(), expanded < 9000 {
            if closed[current] { continue }
            closed[current] = true; expanded += 1
            if goalIndex.contains(current) {
                var out: [CityTile] = [], at = current
                while at != s { out.append(CityTile(x: at % w, y: at / w)); at = came[at] }
                return out.reversed()
            }
            let cx = current % w, cy = current / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let t = CityTile(x: cx + dx, y: cy + dy)
                guard Self.inside(t) else { continue }
                let ni = Self.index(t)
                guard !closed[ni], walkable(t) || goalIndex.contains(ni) else { continue }
                if dx != 0, dy != 0, !walkable(CityTile(x: cx + dx, y: cy)) || !walkable(CityTile(x: cx, y: cy + dy)) { continue }
                let step = g[current] + (dx != 0 && dy != 0 ? 1.414 : 1) * (stepCost(ni) + stepCost(current)) / 2
                if step < g[ni] { g[ni] = step; came[ni] = current; heap.push(step + guess(ni), ni) }
            }
        }
        return nil
    }

    /// The tiles around a building one can stand on to use it — for a field, the field itself.
    func around(_ b: CityBuilding) -> Set<CityTile> {
        let n = Self.size(b.kind)
        var out = Set<CityTile>()
        if b.kind == .field {
            for dy in 0..<n { for dx in 0..<n { out.insert(CityTile(x: b.x + dx, y: b.y + dy)) } }
            return out
        }
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n {
            let t = CityTile(x: b.x + dx, y: b.y + dy)
            if walkable(t) { out.insert(t) }
        } }
        return out
    }
    func neighbours(_ t: CityTile) -> Set<CityTile> {
        var out = Set<CityTile>()
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let n = CityTile(x: t.x + dx, y: t.y + dy)
            if walkable(n) { out.insert(n) }
        } }
        return out
    }

    enum Arrival { case arrived, walking, stuck }

    private mutating func go(_ i: Int, _ goals: Set<CityTile>, _ dt: Double) -> Arrival {
        let here = tile(of: people[i])
        if goals.contains(here), people[i].path.isEmpty { return .arrived }
        if people[i].path.isEmpty || people[i].repath <= 0 {
            people[i].repath = 6
            guard let found = path(from: here, to: goals) else { people[i].path = []; return .stuck }
            people[i].path = found
            if found.isEmpty { return .arrived }
        }
        guard let next = people[i].path.first else { return .arrived }
        let tx = Double(next.x) + 0.5, ty = Double(next.y) + 0.5
        let dx = tx - people[i].x, dy = ty - people[i].y, d = hypot(dx, dy)
        let under = Self.index(here)
        var speed = road[under] ? 2.4 : ground[under] == .forest ? 1.0 : 1.6
        if !people[i].adult || people[i].retired { speed *= 0.8 }
        if people[i].amount > 0 { speed *= 0.9 }
        let stride = speed * dt
        if abs(dx) > 0.05 { people[i].facing = dx > 0 ? 1 : -1 }
        if d <= stride { people[i].x = tx; people[i].y = ty; people[i].path.removeFirst() }
        else { people[i].x += dx / d * stride; people[i].y += dy / d * stride }
        return people[i].path.isEmpty && goals.contains(tile(of: people[i])) ? .arrived : .walking
    }

    // MARK: The clock

    mutating func step(_ dt: Double) {
        guard !over else { return }
        time += dt
        if monthNumber != lastMonth { lastMonth = monthNumber; monthly() }
        staffClock += dt
        if staffClock >= 1 { staffClock = 0; staff() }
        for i in people.indices { act(i, dt) }
        if events.count > 60 { events.removeAll { time - $0.time > 8 } }
    }

    /// Workers to where the mayor wants them: the nearest free hands, and back when fewer are wanted.
    private mutating func staff() {
        for bi in buildings.indices where buildings[bi].done && Self.slots(buildings[bi].kind) > 0 {
            let b = buildings[bi], want = min(b.wanted, Self.slots(b.kind))
            var at = people.indices.filter { people[$0].job == b.id }
            while at.count > want {
                let i = at.removeLast()
                people[i].job = nil
                if case .work = people[i].task { people[i].task = .idle }
                if case .harvest = people[i].task { people[i].task = .idle }
            }
            guard at.count < want else { continue }
            let c = centre(b)
            let free = people.indices.filter { people[$0].worker && people[$0].job == nil }
                .sorted { hypot(people[$0].x - c.x, people[$0].y - c.y) < hypot(people[$1].x - c.x, people[$1].y - c.y) }
            for i in free.prefix(want - at.count) {
                people[i].job = b.id
                if people[i].task == .idle || { if case .wander = people[i].task { return true }; if case .pause = people[i].task { return true }; return false }() {
                    people[i].task = .idle
                }
            }
        }
    }

    // MARK: A month goes by

    private mutating func monthly() {
        let m = monthOfYear
        made[monthNumber % 12] = Array(repeating: 0, count: 6)
        used[monthNumber % 12] = Array(repeating: 0, count: 6)
        if m == 0 {
            for b in buildings.indices { buildings[b].lastOutput = buildings[b].output; buildings[b].output = 0 }
            for i in forage.indices where ground[i] == .forest { forage[i] = 3 }
            events.append(CityEvent(kind: .newYear(year), x: 0, y: 0, time: time))
        }
        for i in wood.indices where ground[i] == .forest && wood[i] < 1 { wood[i] = min(1, wood[i] + 1.0 / 30) }
        for i in fish.indices where ground[i] == .water { fish[i] = min(10, fish[i] + 0.5) }
        // Fields grow through the summer; what is not in by winter is lost.
        for b in buildings.indices where buildings[b].kind == .field && buildings[b].done {
            if (3...5).contains(m) { buildings[b].grown = min(1, buildings[b].grown + 1.0 / 3) }
            if m == 9 { buildings[b].planted = 0; buildings[b].grown = 0; buildings[b].harvested = 0 }
        }
        // Everybody eats; houses burn firewood through the cold months.
        for i in people.indices {
            var fed = false
            if let h = people[i].home, let hi = buildingIndex(h), buildings[hi].stock[0] >= 1 { buildings[hi].stock[0] -= 1; fed = true }
            else if take(.food, 1) >= 1 { fed = true }
            if fed { used[monthNumber % 12][0] += 1; people[i].hungry = 0 } else { people[i].hungry += 1 }
        }
        var warm = Set<Int>()
        if Self.heats(m) {
            for hi in buildings.indices where buildings[hi].kind == .house && buildings[hi].done {
                let id = buildings[hi].id
                guard residents(id) > 0 else { continue }
                var got = min(2, buildings[hi].stock[4])
                buildings[hi].stock[4] -= got
                if got < 2 { got += take(.firewood, 2 - got) }
                used[monthNumber % 12][4] += got
                if got >= 1.99 { warm.insert(id) }
            }
        }
        for i in people.indices {
            let cold = Self.heats(m) && !(people[i].home.map(warm.contains) ?? false)
            people[i].cold = cold ? people[i].cold + 1 : 0
            var loss = 0.0
            if people[i].hungry > 0 { loss += 0.3 }
            if cold { loss += people[i].home == nil ? 0.36 : 0.26 }
            if people[i].age < 6 || people[i].age >= 65 { loss *= 1.3 }
            people[i].health = loss > 0 ? people[i].health - loss : min(1, people[i].health + 0.15)
            people[i].age += 1.0 / 12
        }
        // Deaths.
        var dead: [(Int, CityEvent.Cause)] = []
        for i in people.indices {
            if people[i].health <= 0.001 { dead.append((i, people[i].hungry > 0 ? .hunger : .cold)) }
            else if people[i].age >= 58, chance((people[i].age - 56) * 0.0035) { dead.append((i, .age)) }
        }
        for (i, cause) in dead.reversed() {
            events.append(CityEvent(kind: .died(cause), x: people[i].x, y: people[i].y, time: time))
            deaths[cause.rawValue, default: 0] += 1
            let id = people[i].id
            for b in buildings.indices where buildings[b].fetcher == id { buildings[b].fetcher = nil }
            people.remove(at: i)
        }
        // Births: a house with a couple, room, and nobody going hungry.
        for hi in buildings.indices where buildings[hi].kind == .house && buildings[hi].done {
            let id = buildings[hi].id
            let family = people.filter { $0.home == id }
            let couples = family.filter { $0.age >= 16 && $0.age <= 45 }.count
            guard couples >= 2, family.count < Self.houseRoom, !family.contains(where: { $0.hungry > 0 }), chance(0.045) else { continue }
            let c = centre(buildings[hi])
            people.append(CityPerson(id: nextID, x: c.x, y: c.y + 1.2, age: 0, home: id)); nextID += 1
            births += 1
            events.append(CityEvent(kind: .born, x: c.x, y: c.y, time: time))
        }
        rehouse()
        // Newcomers in spring, when there is room and food to spare.
        if m == 0, let hall {
            let free = houseRoom - people.filter { $0.home != nil }.count - homeless
            if free >= 3, stored(.food) >= Double(people.count) * 6 {
                let n = min(free, 2 + roll(4)), edge = CityTile(x: 1, y: hall.y + roll(7) - 3)
                for k in 0..<n {
                    people.append(CityPerson(id: nextID, x: Double(edge.x) + 0.5, y: Double(edge.y) + 0.5 + Double(k) * 0.4, age: k < 2 || roll(3) > 0 ? Double(18 + roll(20)) : Double(2 + roll(9))))
                    people[people.count - 1].task = .wander(CityTile(x: hall.x + 1, y: hall.y + 4))
                    nextID += 1
                }
                arrivals += n
                events.append(CityEvent(kind: .arrived(n), x: Double(edge.x), y: Double(edge.y), time: time))
                rehouse()
            }
        }
        // Tools wear out with work.
        wear += Double(people.filter { $0.job != nil }.count) / 36
        while wear >= 1 { if take(.tools, 1) >= 1 { wear -= 1; used[monthNumber % 12][5] += 1 } else { wear = 0; break } }
        history.append((people.count, stored(.food) + atHome(.food), stored(.firewood) + atHome(.firewood)))
    }

    /// The homeless into houses with room — an empty house first, as a new household — and young couples
    /// out of crowded houses into empty ones.
    private mutating func rehouse() {
        let houses = buildings.filter { $0.kind == .house && $0.done }.map(\.id)
        var count = Dictionary(uniqueKeysWithValues: houses.map { ($0, 0) })
        for p in people { if let h = p.home, count[h] != nil { count[h]! += 1 } }
        for i in people.indices where people[i].home == nil || count[people[i].home!] == nil {
            let adults = people[i].adult
            guard let h = houses.filter({ count[$0]! < Self.houseRoom }).min(by: { adults ? count[$0]! < count[$1]! : count[$0]! > count[$1]! }) else { break }
            people[i].home = h; count[h]! += 1
        }
        for empty in houses where count[empty] == 0 {
            guard let crowded = houses.filter({ count[$0]! >= 4 }).max(by: { count[$0]! < count[$1]! }) else { break }
            let movers = people.indices.filter { people[$0].home == crowded && people[$0].age >= 16 && people[$0].age <= 35 }.prefix(2)
            for i in movers { people[i].home = empty }
            count[empty]! += movers.count; count[crowded]! -= movers.count
        }
    }

    // MARK: A person's turn

    private mutating func act(_ i: Int, _ dt: Double) {
        people[i].swung += dt
        people[i].repath -= dt
        if people[i].inside, people[i].task != .idle, !{ if case .pause = people[i].task { return true }; return false }() { people[i].inside = false }
        switch people[i].task {
        case .idle: decide(i)
        case .pause(let left):
            if left - dt > 0 { people[i].task = .pause(left - dt) } else { people[i].task = .idle; people[i].inside = false }
        case .wander(let t):
            if go(i, [t], dt) != .walking { people[i].task = .pause(1.5 + Double(roll(40)) / 10) }
        case .goHome:
            guard let h = people[i].home, let b = building(h) else { people[i].task = .idle; return }
            if go(i, around(b), dt) != .walking {
                let c = centre(b)
                people[i].x = c.x; people[i].y = Double(b.y) + Double(Self.size(b.kind)) + 0.3
                people[i].inside = true
                people[i].task = .pause((Self.heats(monthOfYear) ? 10 : 5) + Double(roll(60)) / 10)
            }
        case .work(let id): labour(i, id, dt)
        case .harvest(let t): harvest(i, t, dt)
        case .store(let id):
            guard let b = building(id), b.done else { people[i].task = .idle; return }
            switch go(i, around(b), dt) {
            case .walking: return
            case .stuck: people[i].amount = 0; people[i].carrying = nil; people[i].task = .idle
            case .arrived:
                if let g = people[i].carrying { var goods = [Double](repeating: 0, count: 6); goods[g.rawValue] = people[i].amount; deposit(goods, into: id) }
                people[i].amount = 0; people[i].carrying = nil; people[i].task = .idle
            }
        case .fetch(let id, let g, let purpose):
            guard let b = building(id), let bi = buildingIndex(id) else { people[i].task = .idle; release(i); return }
            switch go(i, around(b), dt) {
            case .walking: return
            case .stuck: people[i].task = .idle; release(i)
            case .arrived:
                let want = wanted(g, for: purpose, by: people[i].id)
                let got = min(want, b.stock[g.rawValue])
                guard got > 0 else { people[i].task = .idle; release(i); return }
                buildings[bi].stock[g.rawValue] -= got
                people[i].carrying = g; people[i].amount = got
                people[i].task = .bring(purpose)
            }
        case .bring(let id):
            guard let b = building(id), let bi = buildingIndex(id), let g = people[i].carrying else { people[i].task = .idle; release(i); return }
            switch go(i, around(b), dt) {
            case .walking: return
            case .stuck:
                people[i].task = .idle; release(i)
            case .arrived:
                if !b.done { buildings[bi].delivered[g.rawValue] += people[i].amount }
                else { buildings[bi].stock[g.rawValue] += people[i].amount }
                if buildings[bi].fetcher == people[i].id { buildings[bi].fetcher = nil }
                people[i].amount = 0; people[i].carrying = nil; people[i].task = .idle
            }
        case .build(let id):
            guard let bi = buildingIndex(id), !buildings[bi].done else { people[i].task = .idle; return }
            let b = buildings[bi]
            switch go(i, around(b), dt) {
            case .walking: return
            case .stuck: people[i].task = .pause(3)
            case .arrived:
                guard (0..<6).allSatisfy({ b.delivered[$0] >= Self.cost(b.kind)[$0] - 0.01 }) else { people[i].task = .idle; return }
                buildings[bi].progress += dt / Self.work(b.kind) * (toolless ? 0.6 : 1)
                if people[i].swung > 0.6 { people[i].swung = 0 }
                if buildings[bi].progress >= 1 {
                    buildings[bi].progress = 1; buildings[bi].done = true
                    events.append(CityEvent(kind: .finished(b.kind), x: centre(b).x, y: centre(b).y, time: time))
                    if b.kind == .house { rehouse() }
                    people[i].task = .idle
                }
            }
        }
    }

    /// A house's fetcher is free again when the errand fails.
    private mutating func release(_ i: Int) {
        let id = people[i].id
        for b in buildings.indices where buildings[b].fetcher == id { buildings[b].fetcher = nil }
        if people[i].amount > 0, let s = nearestStorage(people[i].x, people[i].y, room: 0) { people[i].task = .store(s) }
    }

    /// How much of a good to carry for this purpose, minus what others are already bringing.
    private func wanted(_ g: CityGood, for purpose: Int, by who: Int) -> Double {
        guard let b = building(purpose) else { return 0 }
        if !b.done { return min(10, max(0, Self.cost(b.kind)[g.rawValue] - b.delivered[g.rawValue] - incoming(g, to: purpose, besides: who))) }
        switch b.kind {
        case .house: return g == .food ? 10 : 8
        case .woodcutter: return 10
        case .blacksmith: return 6
        default: return 5
        }
    }

    /// What is on its way to a building: being fetched for it, or carried to it.
    func incoming(_ g: CityGood, to id: Int, besides: Int? = nil) -> Double {
        people.reduce(0) { sum, p in
            guard p.id != besides else { return sum }
            switch p.task {
            case .fetch(_, g, id): return sum + 10
            case .bring(id) where p.carrying == g: return sum + p.amount
            default: return sum
            }
        }
    }

    // MARK: What to do next

    private mutating func decide(_ i: Int) {
        let p = people[i]
        let home = p.home.flatMap(building)
        if p.amount > 0 {
            if let s = nearestStorage(p.x, p.y, room: p.amount) ?? nearestStorage(p.x, p.y, room: 0) { people[i].task = .store(s) }
            else { people[i].amount = 0; people[i].carrying = nil }
            return
        }
        if !p.adult {
            let base = home.map { centre($0) } ?? hall.map { centre($0) } ?? (x: p.x, y: p.y)
            if home != nil, roll(3) == 0 { people[i].task = .goHome; return }
            let t = CityTile(x: Int(base.x) + roll(9) - 4, y: Int(base.y) + roll(7) - 3)
            people[i].task = walkable(t) ? .wander(t) : .pause(2)
            return
        }
        // Errands for the house: food, and firewood from late autumn.
        if let home, let hi = buildingIndex(home.id), home.fetcher == nil || home.fetcher == p.id {
            let n = Double(residents(home.id))
            if home.stock[0] < n * 1.5, let s = storage(with: .food, p.x, p.y, atLeast: 2) {
                buildings[hi].fetcher = p.id; people[i].task = .fetch(s, .food, home.id); return
            }
            if Self.heats(monthOfYear) || monthOfYear == 8, home.stock[4] < 3, let s = storage(with: .firewood, p.x, p.y, atLeast: 2) {
                buildings[hi].fetcher = p.id; people[i].task = .fetch(s, .firewood, home.id); return
            }
        }
        if p.retired {
            if home != nil, roll(2) == 0 { people[i].task = .goHome } else { people[i].task = .pause(5) }
            return
        }
        if let job = p.job, let b = building(job), b.done {
            switch b.kind {
            case .field:
                if let t = fieldWork(b) { people[i].task = t; return }
            case .gatherer, .forester, .fishery:
                if let t = target(for: b, from: p) { people[i].task = .harvest(t); return }
            case .quarry, .mine:
                if b.reserve > 0 { people[i].task = .work(job); return }
            case .woodcutter, .blacksmith:
                people[i].task = .work(job); return
            default: break
            }
        }
        // Hands for building: fetch what a site is missing, or build one that has everything.
        let sites = buildings.filter { !$0.done }
            .sorted { hypot(Double($0.x) - p.x, Double($0.y) - p.y) < hypot(Double($1.x) - p.x, Double($1.y) - p.y) }
        for site in sites {
            let cost = Self.cost(site.kind)
            for g in CityGood.allCases where cost[g.rawValue] - site.delivered[g.rawValue] - incoming(g, to: site.id) > 0.01 {
                if let s = storage(with: g, Double(site.x), Double(site.y)) { people[i].task = .fetch(s, g, site.id); return }
            }
        }
        for site in sites where (0..<6).allSatisfy({ site.delivered[$0] >= Self.cost(site.kind)[$0] - 0.01 }) {
            let builders = people.filter { $0.task == .build(site.id) }.count
            if builders < 4 { people[i].task = .build(site.id); return }
        }
        // Nothing to do: home for a rest — always in the cold months — or a stroll by the town hall.
        if home != nil, Self.heats(monthOfYear) || roll(3) > 0 { people[i].task = .goHome; return }
        let base = hall.map { centre($0) } ?? (x: p.x, y: p.y)
        let t = CityTile(x: Int(base.x) + roll(11) - 5, y: Int(base.y) + roll(9) - 4)
        people[i].task = walkable(t) ? .wander(t) : .pause(3)
    }

    /// A field's work by the season: planting in spring, harvesting in autumn — nothing in between.
    private func fieldWork(_ b: CityBuilding) -> CityTask? {
        let m = monthOfYear
        if m <= 2, b.planted < 1 { return .work(b.id) }
        if (6...8).contains(m), b.harvested < b.planted, b.grown > 0 { return .work(b.id) }
        return nil
    }

    /// The next tree, forest floor or fishing water for a lodge's worker: the nearest to the worker within the lodge's reach.
    private func target(for b: CityBuilding, from p: CityPerson) -> CityTile? {
        let c = centre(b), r = Self.reach
        var best: CityTile?, bestD = Double.infinity
        let taken = Set(people.compactMap { q -> CityTile? in if case .harvest(let t) = q.task, q.id != p.id { return t }; return nil })
        for y in max(0, Int(c.y) - r)...min(Self.height - 1, Int(c.y) + r) {
            for x in max(0, Int(c.x) - r)...min(Self.width - 1, Int(c.x) + r) {
                let i = y * Self.width + x, t = CityTile(x: x, y: y)
                guard hypot(Double(x) + 0.5 - c.x, Double(y) + 0.5 - c.y) <= Double(r), !taken.contains(t) else { continue }
                switch b.kind {
                case .forester: guard ground[i] == .forest, wood[i] >= 1 else { continue }
                case .gatherer: guard ground[i] == .forest, forage[i] >= 1, monthOfYear < 9 else { continue }
                case .fishery: guard ground[i] == .water, fish[i] >= 2, !neighbours(t).isEmpty else { continue }
                default: continue
                }
                let d = hypot(Double(x) - p.x, Double(y) - p.y) + hypot(Double(x) - c.x, Double(y) - c.y) * 0.5
                if d < bestD { bestD = d; best = t }
            }
        }
        return best
    }

    private mutating func harvest(_ i: Int, _ t: CityTile, _ dt: Double) {
        guard let job = people[i].job, let b = building(job) else { people[i].task = .idle; return }
        let ti = Self.index(t)
        let goals = b.kind == .fishery ? neighbours(t) : neighbours(t).union(walkable(t) ? [t] : [])
        switch go(i, goals, dt) {
        case .walking: return
        case .stuck: people[i].task = .pause(2); return
        case .arrived: break
        }
        let rate = toolless ? 0.6 : 1
        people[i].busy += dt * rate
        if people[i].swung > 0.7 { people[i].swung = 0 }
        people[i].facing = Double(t.x) + 0.5 >= people[i].x ? 1 : -1
        switch b.kind {
        case .forester:
            guard wood[ti] >= 1 else { people[i].busy = 0; people[i].task = .idle; return }
            guard people[i].busy >= 6 else { return }
            wood[ti] = 0; people[i].busy = 0
            people[i].carrying = .logs; people[i].amount += 6; note(made: .logs, 6, by: i)
            events.append(CityEvent(kind: .felled, x: Double(t.x) + 0.5, y: Double(t.y) + 0.5, time: time))
            people[i].task = .idle
        case .gatherer:
            guard forage[ti] >= 1, monthOfYear < 9 else { people[i].busy = 0; people[i].task = .idle; return }
            guard people[i].busy >= 2.5 else { return }
            forage[ti] -= 1; people[i].busy = 0
            people[i].carrying = .food; people[i].amount += 1; note(made: .food, 1, by: i)
            if people[i].amount >= 6 { people[i].task = .idle }
            else if let next = target(for: b, from: people[i]) { people[i].task = .harvest(next) } else { people[i].task = .idle }
        case .fishery:
            guard fish[ti] >= 2 else { people[i].busy = 0; people[i].task = .idle; return }
            guard people[i].busy >= (monthOfYear >= 9 ? 11 : 7) else { return }
            fish[ti] -= 2; people[i].busy = 0
            people[i].carrying = .food; people[i].amount += 2; note(made: .food, 2, by: i)
            if people[i].amount >= 8 { people[i].task = .idle }
        default:
            people[i].task = .idle
        }
    }

    /// Work at the place itself.
    private mutating func labour(_ i: Int, _ id: Int, _ dt: Double) {
        guard let bi = buildingIndex(id), people[i].job == id else { people[i].task = .idle; return }
        let b = buildings[bi]
        switch go(i, around(b), dt) {
        case .walking: return
        case .stuck: people[i].task = .pause(3); return
        case .arrived: break
        }
        let rate = toolless ? 0.6 : 1
        switch b.kind {
        case .field:
            let m = monthOfYear, tiles = Double(Self.size(.field) * Self.size(.field))
            if m <= 2, b.planted < 1 {
                people[i].busy += dt * rate
                if people[i].swung > 0.8 { people[i].swung = 0 }
                walkFurrow(i, b, b.planted)
                if people[i].busy >= 3 { people[i].busy = 0; buildings[bi].planted = min(1, b.planted + 1 / tiles) }
            } else if (6...8).contains(m), b.harvested < b.planted, b.grown > 0 {
                people[i].busy += dt * rate
                if people[i].swung > 0.8 { people[i].swung = 0 }
                walkFurrow(i, b, b.harvested)
                if people[i].busy >= 3 {
                    people[i].busy = 0
                    buildings[bi].harvested = min(b.planted, b.harvested + 1 / tiles)
                    let f = fieldFertility(b)
                    people[i].carrying = .food; people[i].amount += 7 * b.grown * f; note(made: .food, 7 * b.grown * f, by: i)
                    if people[i].amount >= 10 { people[i].task = .idle }
                }
            } else { people[i].task = .idle }
        case .quarry, .mine:
            guard b.reserve > 0 else { people[i].task = .idle; return }
            people[i].busy += dt * rate
            if people[i].swung > 0.7 { people[i].swung = 0 }
            let stone = b.kind == .quarry
            guard people[i].busy >= (stone ? 8 : 10) else { return }
            people[i].busy = 0
            let got = min(b.reserve, stone ? 4 : 3)
            buildings[bi].reserve -= got
            people[i].carrying = stone ? .stone : .iron; people[i].amount += got; note(made: stone ? .stone : .iron, got, by: i)
            if people[i].amount >= (stone ? 8 : 6) { people[i].task = .idle }
        case .woodcutter:
            if b.stock[4] >= 8 {
                buildings[bi].stock[4] -= 8; people[i].carrying = .firewood; people[i].amount = 8; people[i].task = .idle; return
            }
            if b.stock[1] >= 1 {
                people[i].busy += dt * rate
                if people[i].swung > 0.6 { people[i].swung = 0 }
                guard people[i].busy >= 2.5 else { return }
                people[i].busy = 0
                buildings[bi].stock[1] -= 1; buildings[bi].stock[4] += 2; note(made: .firewood, 2, by: i)
                return
            }
            if b.stock[4] >= 1 { buildings[bi].stock[4] -= b.stock[4]; people[i].carrying = .firewood; people[i].amount = b.stock[4]; people[i].task = .idle; return }
            // Each splitter fetches an armful of logs for itself.
            if let s = storage(with: .logs, people[i].x, people[i].y, atLeast: 1) { people[i].task = .fetch(s, .logs, id) }
            else { people[i].task = .pause(4) }
        case .blacksmith:
            if b.stock[5] >= 2 {
                buildings[bi].stock[5] -= 2; people[i].carrying = .tools; people[i].amount = 2; people[i].task = .idle; return
            }
            if b.stock[3] >= 1, b.stock[1] >= 1 {
                people[i].busy += dt * rate
                if people[i].swung > 0.5 { people[i].swung = 0 }
                guard people[i].busy >= 6 else { return }
                people[i].busy = 0
                buildings[bi].stock[3] -= 1; buildings[bi].stock[1] -= 1; buildings[bi].stock[5] += 1; note(made: .tools, 1, by: i)
                return
            }
            let need: CityGood = b.stock[3] < 1 ? .iron : .logs
            if let s = storage(with: need, people[i].x, people[i].y, atLeast: 1) { people[i].task = .fetch(s, need, id) }
            else { people[i].task = .pause(4) }
        default:
            people[i].task = .idle
        }
    }

    /// A farmer works along the rows: stand on the tile the work has reached.
    private mutating func walkFurrow(_ i: Int, _ b: CityBuilding, _ done: Double) {
        let n = Self.size(.field), k = min(n * n - 1, Int(done * Double(n * n)))
        let row = k / n, col = row % 2 == 0 ? k % n : n - 1 - k % n
        let tx = Double(b.x + col) + 0.5, ty = Double(b.y + row) + 0.5
        let dx = tx - people[i].x, dy = ty - people[i].y, d = hypot(dx, dy)
        if d > 0.05 { let s = min(d, 0.03); people[i].x += dx / d * s; people[i].y += dy / d * s; if abs(dx) > 0.01 { people[i].facing = dx > 0 ? 1 : -1 } }
    }

    func fieldFertility(_ b: CityBuilding) -> Double {
        let n = Self.size(.field)
        var total = 0.0
        for dy in 0..<n { for dx in 0..<n { total += fertility[Self.index(CityTile(x: b.x + dx, y: b.y + dy))] } }
        return total / Double(n * n)
    }
}

/// A binary heap of (priority, tile index), smallest first — for A*.
struct CityHeap {
    private var items: [(Double, Int)] = []
    mutating func push(_ f: Double, _ i: Int) {
        items.append((f, i))
        var c = items.count - 1
        while c > 0 {
            let p = (c - 1) / 2
            if items[p].0 <= items[c].0 { break }
            items.swapAt(p, c); c = p
        }
    }
    mutating func pop() -> Int? {
        guard !items.isEmpty else { return nil }
        let top = items[0].1
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var p = 0
            while true {
                let l = 2 * p + 1, r = l + 1
                var m = p
                if l < items.count, items[l].0 < items[m].0 { m = l }
                if r < items.count, items[r].0 < items[m].0 { m = r }
                if m == p { break }
                items.swapAt(p, m); p = m
            }
        }
        return top
    }
}
