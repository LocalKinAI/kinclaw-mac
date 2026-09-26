import Foundation

/// 帝国时代 — a real-time strategy game on a tile map. Foundation only, so it
/// runs and is tested without a window.
///
/// Two towns on a 48 × 30 map: villagers walk to trees, bushes, gold and stone,
/// carry what they gather to the nearest place that takes it, and build what
/// they are told to build where they are told to build it; soldiers walk, find
/// what is hostile within sight and fight it; town centres and towers shoot.
/// Everything moves in continuous time — `step(dt)` — on paths found over the
/// tiles.

enum RTSResource: Int, CaseIterable { case food, wood, gold, stone }
enum RTSTerrain: UInt8 { case grass, forest, gold, stone, berries, water }
enum RTSUnitKind: Int, CaseIterable { case villager, spearman, archer, knight }
enum RTSBuildingKind: Int, CaseIterable { case townCenter, house, mill, farm, lumberCamp, miningCamp, barracks, range, stable, tower }

struct RTSTile: Hashable { var x: Int, y: Int }

enum RTSTask: Equatable {
    case idle
    case move(RTSTile)
    case gather(RTSTile)
    case farm(Int)
    case build(Int)
    case attack(Int)          // a unit
    case raze(Int)            // a building
    case attackMove(RTSTile)
}

struct RTSUnit: Equatable {
    var id: Int, owner: Int, kind: RTSUnitKind
    var x: Double, y: Double
    var hp: Double
    var task: RTSTask = .idle
    var path: [RTSTile] = []
    var carrying: RTSResource?
    var load = 0.0
    var cooldown = 0.0
    var repath = 0.0
    /// Which way it last moved, for drawing: −1 left, +1 right.
    var facing = 1.0
    /// Seconds since it last hit something, for drawing a swing.
    var swung = 99.0
}

struct RTSBuilding: Equatable {
    var id: Int, owner: Int, kind: RTSBuildingKind
    var x: Int, y: Int
    var hp: Double
    var progress: Double
    var queue: [RTSUnitKind] = []
    var trained = 0.0
    var cooldown = 0.0
    var farmer: Int?
    /// Where new units go: a tile, a resource or nothing.
    var rally: RTSTile?
    var done: Bool { progress >= 1 }
}

struct RTSPlayer: Equatable {
    var stock = [200.0, 200.0, 100.0, 100.0]
    var age = 0
    /// Seconds of age research left at the town centre; 0 when none.
    var researching = 0.0
    var lost = 0, killed = 0
}

/// Something that happened, for the picture and the messages: an arrow, a hit, a death, a building finished.
struct RTSEvent: Equatable {
    enum Kind: Equatable { case arrow(from: RTSTile, to: RTSTile), hit, death, finished(RTSBuildingKind), attacked, age(Int) }
    var kind: Kind, owner: Int, x: Double, y: Double, time: Double
}

struct RTSWorld {
    static let width = 48, height = 30
    static let names = ["蓝方", "红方"]
    static let ageNames = ["黑暗时代", "封建时代", "城堡时代"]

    // MARK: Rules

    static func cost(_ kind: RTSUnitKind) -> [Double] {
        switch kind {
        case .villager: return [50, 0, 0, 0]
        case .spearman: return [35, 25, 0, 0]
        case .archer: return [0, 25, 45, 0]
        case .knight: return [60, 0, 75, 0]
        }
    }
    static func cost(_ kind: RTSBuildingKind) -> [Double] {
        switch kind {
        case .townCenter: return [0, 275, 0, 100]
        case .house: return [0, 25, 0, 0]
        case .farm: return [0, 60, 0, 0]
        case .mill, .lumberCamp, .miningCamp: return [0, 100, 0, 0]
        case .barracks, .range, .stable: return [0, 175, 0, 0]
        case .tower: return [0, 25, 0, 100]
        }
    }
    static func size(_ kind: RTSBuildingKind) -> Int {
        switch kind {
        case .townCenter, .farm, .barracks, .range, .stable: return 3
        case .tower: return 1
        default: return 2
        }
    }
    /// Seconds for one villager to put it up.
    static func work(_ kind: RTSBuildingKind) -> Double {
        switch kind {
        case .townCenter: return 60
        case .house: return 10
        case .farm: return 8
        case .mill, .lumberCamp, .miningCamp: return 15
        case .barracks, .range, .stable, .tower: return 25
        }
    }
    static func health(_ kind: RTSBuildingKind) -> Double {
        switch kind {
        case .townCenter: return 2400
        case .house: return 450
        case .farm: return 250
        case .mill, .lumberCamp, .miningCamp: return 700
        case .barracks, .range, .stable: return 1200
        case .tower: return 800
        }
    }
    static func age(_ kind: RTSBuildingKind) -> Int { kind == .range || kind == .tower ? 1 : kind == .stable ? 2 : 0 }
    static func trainer(_ kind: RTSUnitKind) -> RTSBuildingKind { [.townCenter, .barracks, .range, .stable][kind.rawValue] }
    static func trainTime(_ kind: RTSUnitKind) -> Double { [6, 7, 8, 10][kind.rawValue] }
    static let ageCost: [[Double]] = [[500, 0, 0, 0], [800, 0, 200, 0]], ageTime = [35.0, 50.0]
    static func unitHP(_ kind: RTSUnitKind) -> Double { [25, 45, 32, 100][kind.rawValue] }
    static func speed(_ kind: RTSUnitKind) -> Double { [1.9, 1.5, 1.5, 2.5][kind.rawValue] }
    static func range(_ kind: RTSUnitKind) -> Double { kind == .archer ? 4.5 : 1.1 }
    static func attack(_ kind: RTSUnitKind, against other: RTSUnitKind?) -> Double {
        switch (kind, other) {
        case (.villager, _): return 3
        case (.spearman, .knight?): return 16
        case (.spearman, _): return 5
        case (.archer, .spearman?): return 6
        case (.archer, .knight?): return 3
        case (.archer, _): return 4.5
        case (.knight, .archer?): return 16
        case (.knight, _): return 10
        }
    }
    /// Damage to a building is a fraction of the blow: arrows barely scratch walls.
    static func razing(_ kind: RTSUnitKind) -> Double { [0.4, 0.8, 0.2, 0.7][kind.rawValue] }
    static let gatherRate: [RTSTerrain: Double] = [.forest: 0.9, .berries: 0.85, .gold: 0.75, .stone: 0.75]
    static let farmRate = 0.7, carry = 10.0, sight = 6.5, popCap = 60
    static func resource(of terrain: RTSTerrain) -> RTSResource? {
        switch terrain {
        case .forest: return .wood
        case .berries: return .food
        case .gold: return .gold
        case .stone: return .stone
        default: return nil
        }
    }
    /// Which buildings take which resource.
    static func takes(_ kind: RTSBuildingKind, _ r: RTSResource) -> Bool {
        switch kind {
        case .townCenter: return true
        case .mill: return r == .food
        case .lumberCamp: return r == .wood
        case .miningCamp: return r == .gold || r == .stone
        default: return false
        }
    }

    // MARK: State

    var terrain: [RTSTerrain]
    var amount: [Double]
    /// The building standing on each tile, if any.
    var occupant: [Int?]
    var units: [RTSUnit] = []
    var buildings: [RTSBuilding] = []
    var players = [RTSPlayer(), RTSPlayer()]
    var time = 0.0
    var nextID = 1
    var events: [RTSEvent] = []
    var winner: Int?

    static func index(_ t: RTSTile) -> Int { t.y * width + t.x }
    static func inside(_ t: RTSTile) -> Bool { t.x >= 0 && t.y >= 0 && t.x < width && t.y < height }

    // MARK: A map

    /// Two towns facing each other across a lake, the land mirrored so that neither side is favoured.
    init(seed: UInt64) {
        terrain = Array(repeating: .grass, count: Self.width * Self.height)
        amount = Array(repeating: 0, count: Self.width * Self.height)
        occupant = Array(repeating: nil, count: Self.width * Self.height)
        var rng = seed &* 0x9E3779B97F4A7C15 | 1
        func roll(_ n: Int) -> Int { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Int(rng % UInt64(max(n, 1))) }
        let half = Self.width / 2
        func put(_ x: Int, _ y: Int, _ t: RTSTerrain, _ a: Double) {
            guard x >= 0, x < half, y >= 0, y < Self.height else { return }
            for mx in [x, Self.width - 1 - x] {
                terrain[y * Self.width + mx] = t; amount[y * Self.width + mx] = a
            }
        }
        // The lake in the middle, with two fords.
        for y in 0..<Self.height {
            let wobble = Int(2.2 * sin(Double(y) * 0.45 + Double(seed % 7)))
            for x in (half - 3 + wobble / 2)..<half where !(y >= 6 && y <= 8) && !(y >= 21 && y <= 23) { put(x, y, .water, 0) }
        }
        // Forests: a big one behind each town, and a few groves.
        func grove(_ cx: Int, _ cy: Int, _ radius: Double) {
            for y in (cy - Int(radius) - 1)...(cy + Int(radius) + 1) {
                for x in (cx - Int(radius) - 1)...(cx + Int(radius) + 1) {
                    let d = hypot(Double(x - cx), Double(y - cy)) + Double(roll(100)) / 60
                    if d <= radius { put(x, y, .forest, 100) }
                }
            }
        }
        grove(2, 5, 4.2); grove(3, 25, 3.6); grove(15, 2, 2.8); grove(14, 27, 2.6); grove(17 + roll(3), 14, 1.6)
        // Gold, stone and berries near each town, and some gold out by the lake.
        for (x, y) in [(10, 19), (11, 19), (10, 20), (11, 20), (12, 20)] { put(x, y, .gold, 400) }
        for (x, y) in [(10, 8), (11, 8), (11, 9), (10, 9)] { put(x, y, .stone, 350) }
        for (x, y) in [(3, 13), (4, 13), (3, 14), (4, 14), (3, 15), (4, 15)] { put(x, y, .berries, 125) }
        for (x, y) in [(19, 14), (19, 15), (20, 15)] { put(x, y, .gold, 500) }
        // Clear ground for the town centres.
        for y in 12...18 { for x in 5...10 { put(x, y, .grass, 0) } }
        for s in 0..<2 {
            let origin = s == 0 ? RTSTile(x: 6, y: 13) : RTSTile(x: Self.width - 9, y: 13)
            let tc = place(.townCenter, at: origin, owner: s, finished: true)
            for k in 0..<3 {
                spawn(.villager, owner: s, near: tc!, offset: k)
            }
        }
        // Start the villagers on the berries, as everybody does.
        for index in units.indices {
            let s = units[index].owner
            if let bush = nearest(.berries, from: RTSTile(x: Int(units[index].x), y: Int(units[index].y)), within: 12, owner: s) { units[index].task = .gather(bush) }
        }
    }

    // MARK: Placing things

    /// Can a building of this kind go with its top-left corner here?
    func fits(_ kind: RTSBuildingKind, at origin: RTSTile) -> Bool {
        let n = Self.size(kind)
        for dy in 0..<n {
            for dx in 0..<n {
                let t = RTSTile(x: origin.x + dx, y: origin.y + dy)
                guard Self.inside(t), terrain[Self.index(t)] == .grass, occupant[Self.index(t)] == nil else { return false }
                if units.contains(where: { $0.kind != .villager && Int($0.x) == t.x && Int($0.y) == t.y && false }) { return false }
            }
        }
        return true
    }

    /// Put a building down — paid for or not — and return its id.
    @discardableResult
    mutating func place(_ kind: RTSBuildingKind, at origin: RTSTile, owner: Int, finished: Bool = false) -> Int? {
        guard fits(kind, at: origin) else { return nil }
        let id = nextID; nextID += 1
        let n = Self.size(kind)
        buildings.append(RTSBuilding(id: id, owner: owner, kind: kind, x: origin.x, y: origin.y,
                                     hp: finished ? Self.health(kind) : Self.health(kind) * 0.1, progress: finished ? 1 : 0))
        for dy in 0..<n { for dx in 0..<n { occupant[Self.index(RTSTile(x: origin.x + dx, y: origin.y + dy))] = id } }
        return id
    }

    /// Order a building: pay for it, lay the foundation, and send builders.
    @discardableResult
    mutating func order(_ kind: RTSBuildingKind, at origin: RTSTile, owner: Int, builders: [Int]) -> Int? {
        let price = Self.cost(kind)
        guard players[owner].age >= Self.age(kind), afford(price, owner), fits(kind, at: origin),
              let id = place(kind, at: origin, owner: owner) else { return nil }
        pay(price, owner)
        for unit in builders { command(unit, .build(id)) }
        return id
    }

    func afford(_ price: [Double], _ owner: Int) -> Bool { (0..<4).allSatisfy { players[owner].stock[$0] >= price[$0] - 1e-9 } }
    mutating func pay(_ price: [Double], _ owner: Int) { for k in 0..<4 { players[owner].stock[k] -= price[k] } }

    func building(_ id: Int) -> RTSBuilding? { buildings.first { $0.id == id } }
    func unitIndex(_ id: Int) -> Int? { units.firstIndex { $0.id == id } }
    func buildingIndex(_ id: Int) -> Int? { buildings.firstIndex { $0.id == id } }

    func population(_ owner: Int) -> Int { units.filter { $0.owner == owner }.count + buildings.filter { $0.owner == owner }.reduce(0) { $0 + $1.queue.prefix(1).count } }
    func room(_ owner: Int) -> Int {
        min(Self.popCap, buildings.filter { $0.owner == owner && $0.done }.reduce(0) { $0 + ($1.kind == .townCenter ? 5 : $1.kind == .house ? 5 : 0) })
    }

    // MARK: Units

    @discardableResult
    mutating func spawn(_ kind: RTSUnitKind, owner: Int, near buildingID: Int, offset: Int = 0) -> Int? {
        guard let b = building(buildingID) else { return nil }
        let n = Self.size(b.kind)
        // The ring of tiles around the building, starting on the side facing the middle of the map.
        var ring: [RTSTile] = []
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n { ring.append(RTSTile(x: b.x + dx, y: b.y + dy)) } }
        let middle = Double(Self.width) / 2
        ring.sort { abs(Double($0.x) - middle) < abs(Double($1.x) - middle) }
        let free = ring.filter { Self.inside($0) && walkable($0) }
        guard !free.isEmpty else { return nil }
        let at = free[offset % free.count]
        let id = nextID; nextID += 1
        units.append(RTSUnit(id: id, owner: owner, kind: kind, x: Double(at.x) + 0.5, y: Double(at.y) + 0.5, hp: Self.unitHP(kind)))
        return id
    }

    func walkable(_ t: RTSTile) -> Bool {
        guard Self.inside(t) else { return false }
        let i = Self.index(t)
        if let b = occupant[i] { return building(b)?.kind == .farm }
        return terrain[i] == .grass
    }

    /// Tell a unit what to do.
    mutating func command(_ id: Int, _ task: RTSTask) {
        guard let i = unitIndex(id) else { return }
        if case .farm(let old) = units[i].task, let f = buildingIndex(old), buildings[f].farmer == id { buildings[f].farmer = nil }
        units[i].task = task; units[i].path = []; units[i].repath = 0
    }

    // MARK: Finding things

    func nearest(_ kind: RTSTerrain, from t: RTSTile, within radius: Int, owner: Int? = nil, besides: RTSTile? = nil) -> RTSTile? {
        var best: RTSTile?, bestD = Double.infinity
        for y in max(0, t.y - radius)...min(Self.height - 1, t.y + radius) {
            for x in max(0, t.x - radius)...min(Self.width - 1, t.x + radius) where terrain[y * Self.width + x] == kind && amount[y * Self.width + x] > 0
                && RTSTile(x: x, y: y) != besides {
                let d = hypot(Double(x - t.x), Double(y - t.y))
                // Of two as near, the one nearer the middle of the map — the same choice on either side of it.
                let nearer = d < bestD - 1e-9 || abs(d - bestD) <= 1e-9 && best.map { abs(Double(x) + 0.5 - Double(Self.width) / 2) < abs(Double($0.x) + 0.5 - Double(Self.width) / 2) } == true
                // A tile nobody can stand next to is no use.
                if nearer, reachableSide(RTSTile(x: x, y: y)) != nil { bestD = d; best = RTSTile(x: x, y: y) }
            }
        }
        return best
    }

    /// A walkable tile next to this one.
    func reachableSide(_ t: RTSTile) -> RTSTile? {
        for (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
            let n = RTSTile(x: t.x + dx, y: t.y + dy)
            if walkable(n) { return n }
        }
        return nil
    }

    /// The nearest finished building of an owner's that takes this resource.
    func dropSite(for r: RTSResource, owner: Int, near x: Double, _ y: Double) -> RTSBuilding? {
        buildings.filter { $0.owner == owner && $0.done && Self.takes($0.kind, r) }
            .min { distance(to: $0, x, y) < distance(to: $1, x, y) }
    }

    /// From a point to the nearest edge of a building.
    func distance(to b: RTSBuilding, _ x: Double, _ y: Double) -> Double {
        let n = Double(Self.size(b.kind))
        let cx = min(max(x, Double(b.x)), Double(b.x) + n), cy = min(max(y, Double(b.y)), Double(b.y) + n)
        return hypot(x - cx, y - cy)
    }

    /// A path of tiles over walkable ground to any of the goal tiles, by A*.
    func path(from start: RTSTile, to goals: Set<RTSTile>) -> [RTSTile]? {
        guard !goals.isEmpty else { return nil }
        if goals.contains(start) { return [] }
        let w = Self.width, h = Self.height
        var g = [Double](repeating: .infinity, count: w * h), came = [Int](repeating: -1, count: w * h), closed = [Bool](repeating: false, count: w * h)
        let goalIndex = Set(goals.map(Self.index))
        func guess(_ i: Int) -> Double {
            let x = i % w, y = i / w
            return goals.map { max(abs($0.x - x), abs($0.y - y)) }.min().map(Double.init) ?? 0
        }
        var open: [(f: Double, i: Int)] = [(guess(Self.index(start)), Self.index(start))]
        g[Self.index(start)] = 0
        var expanded = 0
        while !open.isEmpty, expanded < 3000 {
            var best = 0
            for k in 1..<open.count where open[k].f < open[best].f { best = k }
            let current = open.remove(at: best).i
            if closed[current] { continue }
            closed[current] = true; expanded += 1
            if goalIndex.contains(current) {
                var out: [RTSTile] = [], at = current
                while at != Self.index(start) { out.append(RTSTile(x: at % w, y: at / w)); at = came[at] }
                return out.reversed()
            }
            let cx = current % w, cy = current / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let n = RTSTile(x: cx + dx, y: cy + dy)
                guard Self.inside(n) else { continue }
                let ni = Self.index(n)
                guard !closed[ni], walkable(n) || goalIndex.contains(ni) else { continue }
                // No cutting corners past trees and walls.
                if dx != 0, dy != 0, !walkable(RTSTile(x: cx + dx, y: cy)) || !walkable(RTSTile(x: cx, y: cy + dy)) { continue }
                let step = g[current] + (dx != 0 && dy != 0 ? 1.414 : 1)
                if step < g[ni] { g[ni] = step; came[ni] = current; open.append((step + guess(ni), ni)) }
            }
        }
        return nil
    }

    /// The tiles around a building a unit can stand on to work at it.
    func around(_ b: RTSBuilding) -> Set<RTSTile> {
        let n = Self.size(b.kind)
        var out = Set<RTSTile>()
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n {
            let t = RTSTile(x: b.x + dx, y: b.y + dy)
            if walkable(t) { out.insert(t) }
        } }
        return out
    }

    func neighbours(_ t: RTSTile) -> Set<RTSTile> {
        var out = Set<RTSTile>()
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let n = RTSTile(x: t.x + dx, y: t.y + dy)
            if walkable(n) { out.insert(n) }
        } }
        return out
    }
}

// MARK: - Time passing

extension RTSWorld {
    /// Advance the world `dt` seconds.
    mutating func step(_ dt: Double) {
        guard winner == nil else { return }
        time += dt
        events.removeAll { time - $0.time > 3 }
        for s in 0..<2 { research(s, dt) }
        for index in buildings.indices { work(building: index, dt) }
        for index in units.indices { act(index, dt) }
        // The dead.
        for unit in units where unit.hp <= 0 {
            events.append(RTSEvent(kind: .death, owner: unit.owner, x: unit.x, y: unit.y, time: time))
            players[unit.owner].lost += 1; players[1 - unit.owner].killed += 1
        }
        let fallen = Set(units.filter { $0.hp <= 0 }.map(\.id))
        if !fallen.isEmpty {
            units.removeAll { fallen.contains($0.id) }
            for i in buildings.indices where buildings[i].farmer.map(fallen.contains) == true { buildings[i].farmer = nil }
        }
        for b in buildings where b.hp <= 0 {
            let n = Self.size(b.kind)
            for dy in 0..<n { for dx in 0..<n { occupant[Self.index(RTSTile(x: b.x + dx, y: b.y + dy))] = nil } }
            events.append(RTSEvent(kind: .death, owner: b.owner, x: Double(b.x) + Double(n) / 2, y: Double(b.y) + Double(n) / 2, time: time))
        }
        buildings.removeAll { $0.hp <= 0 }
        for s in 0..<2 where !buildings.contains(where: { $0.owner == s && $0.kind == .townCenter }) { winner = 1 - s }
    }

    private mutating func research(_ s: Int, _ dt: Double) {
        guard players[s].researching > 0 else { return }
        players[s].researching -= dt
        if players[s].researching <= 0 {
            players[s].researching = 0; players[s].age += 1
            if let tc = buildings.first(where: { $0.owner == s && $0.kind == .townCenter }) {
                events.append(RTSEvent(kind: .age(players[s].age), owner: s, x: Double(tc.x) + 1.5, y: Double(tc.y) + 1.5, time: time))
            }
        }
    }

    /// Start researching the next age at the town centre.
    mutating func advance(_ s: Int) -> Bool {
        let age = players[s].age
        guard age < 2, players[s].researching == 0, afford(Self.ageCost[age], s) else { return false }
        pay(Self.ageCost[age], s)
        players[s].researching = Self.ageTime[age]
        return true
    }

    /// Queue a unit at a building of the right kind.
    mutating func train(_ kind: RTSUnitKind, at buildingID: Int) -> Bool {
        guard let i = buildingIndex(buildingID), buildings[i].done, buildings[i].kind == Self.trainer(kind), buildings[i].queue.count < 5 else { return false }
        let s = buildings[i].owner
        if kind == .knight, players[s].age < 2 { return false }
        guard afford(Self.cost(kind), s) else { return false }
        pay(Self.cost(kind), s)
        buildings[i].queue.append(kind)
        return true
    }

    private mutating func work(building i: Int, _ dt: Double) {
        let b = buildings[i]
        guard b.done else { return }
        // Training: the first in the queue, when there is room for it.
        if let kind = b.queue.first {
            let researchingHere = b.kind == .townCenter && players[b.owner].researching > 0
            if !researchingHere, units.filter({ $0.owner == b.owner }).count < room(b.owner) {
                buildings[i].trained += dt
                if buildings[i].trained >= Self.trainTime(kind) {
                    buildings[i].trained = 0; buildings[i].queue.removeFirst()
                    if let id = spawn(kind, owner: b.owner, near: b.id, offset: units.count) { sendNew(id, from: buildings[i]) }
                }
            }
        }
        // Arrows from town centres and towers.
        if b.kind == .townCenter || b.kind == .tower {
            buildings[i].cooldown -= dt
            guard buildings[i].cooldown <= 0 else { return }
            let n = Double(Self.size(b.kind)), cx = Double(b.x) + n / 2, cy = Double(b.y) + n / 2
            let reach = 7.0
            if let target = units.indices.filter({ units[$0].owner != b.owner && hypot(units[$0].x - cx, units[$0].y - cy) <= reach })
                .min(by: { hypot(units[$0].x - cx, units[$0].y - cy) < hypot(units[$1].x - cx, units[$1].y - cy) }) {
                units[target].hp -= b.kind == .tower ? 7 : 5
                buildings[i].cooldown = 2
                events.append(RTSEvent(kind: .arrow(from: RTSTile(x: Int(cx), y: Int(cy)), to: RTSTile(x: Int(units[target].x), y: Int(units[target].y))),
                                       owner: b.owner, x: units[target].x, y: units[target].y, time: time))
            }
        }
    }

    /// A unit fresh from training: to the rally point, or — a villager — to work.
    private mutating func sendNew(_ id: Int, from b: RTSBuilding) {
        guard let i = unitIndex(id) else { return }
        if let rally = b.rally {
            let t = terrain[Self.index(rally)]
            if units[i].kind == .villager, Self.resource(of: t) != nil { units[i].task = .gather(rally) }
            else if units[i].kind == .villager, let f = occupant[Self.index(rally)], building(f)?.kind == .farm, building(f)?.farmer == nil { command(id, .farm(f)) }
            else { units[i].task = units[i].kind == .villager ? .move(rally) : .attackMove(rally) }
        }
    }

    // MARK: A unit's turn

    private mutating func act(_ i: Int, _ dt: Double) {
        guard units[i].hp > 0 else { return }
        units[i].cooldown -= dt; units[i].swung += dt; units[i].repath -= dt
        let unit = units[i]
        switch unit.task {
        case .idle:
            if unit.kind != .villager, let enemy = sighted(i) { units[i].task = enemy }
        case .move(let to):
            if walk(i, toward: [to], dt) { units[i].task = .idle }
        case .attackMove(let to):
            if let enemy = sighted(i) { units[i].task = enemy; units[i].path = []; return }
            if walk(i, toward: [to], dt) { units[i].task = .idle }
        case .gather(let tile):
            gather(i, tile, dt)
        case .farm(let id):
            farm(i, id, dt)
        case .build(let id):
            guard let b = buildingIndex(id), buildings[b].owner == unit.owner, !buildings[b].done else { settle(i); return }
            if touches(tile(of: unit), buildings[b]) {
                units[i].path = []
                buildings[b].progress = min(1, buildings[b].progress + dt / Self.work(buildings[b].kind))
                buildings[b].hp = min(Self.health(buildings[b].kind), buildings[b].hp + Self.health(buildings[b].kind) * dt / Self.work(buildings[b].kind) * 0.9)
                units[i].swung = 0
                if buildings[b].done {
                    events.append(RTSEvent(kind: .finished(buildings[b].kind), owner: unit.owner, x: Double(buildings[b].x) + 1, y: Double(buildings[b].y) + 1, time: time))
                    afterBuilding(i, buildings[b])
                }
            } else if go(i, toward: around(buildings[b]), dt) == .unreachable { units[i].task = .idle }
        case .attack(let target):
            guard let t = unitIndex(target), units[t].hp > 0 else { units[i].task = unit.kind == .villager ? .idle : .idle; return }
            let d = hypot(units[t].x - unit.x, units[t].y - unit.y)
            if d <= Self.range(unit.kind) {
                units[i].path = []
                if units[i].cooldown <= 0 {
                    units[t].hp -= Self.attack(unit.kind, against: units[t].kind)
                    units[i].cooldown = unit.kind == .archer ? 1.6 : 1.2; units[i].swung = 0
                    units[i].facing = units[t].x >= unit.x ? 1 : -1
                    if unit.kind == .archer { events.append(RTSEvent(kind: .arrow(from: RTSTile(x: Int(unit.x), y: Int(unit.y)), to: RTSTile(x: Int(units[t].x), y: Int(units[t].y))), owner: unit.owner, x: units[t].x, y: units[t].y, time: time)) }
                    else { events.append(RTSEvent(kind: .hit, owner: unit.owner, x: units[t].x, y: units[t].y, time: time)) }
                    // Hitting back: a soldier that is struck turns on who struck it.
                    if units[t].kind != .villager, units[t].task == .idle || { if case .raze = units[t].task { return true }; return false }() { units[t].task = .attack(unit.id) }
                }
            } else if max(abs(tile(of: unit).x - tile(of: units[t]).x), abs(tile(of: unit).y - tile(of: units[t]).y)) <= 1 {
                // On the next tile already, yet out of reach — a tile is wide: close the last step straight.
                units[i].path = []
                let dx = units[t].x - unit.x, dy = units[t].y - unit.y
                let step = min(Self.speed(unit.kind) * dt, d - Self.range(unit.kind) * 0.8)
                units[i].x += dx / d * step; units[i].y += dy / d * step
                if abs(dx) > 0.05 { units[i].facing = dx > 0 ? 1 : -1 }
            } else {
                if units[i].repath <= 0 || units[i].path.isEmpty {
                    units[i].repath = 0.8
                    let goal = RTSTile(x: Int(units[t].x), y: Int(units[t].y))
                    units[i].path = path(from: RTSTile(x: Int(unit.x), y: Int(unit.y)), to: neighbours(goal).union([goal])) ?? []
                }
                follow(i, dt)
            }
        case .raze(let target):
            guard let b = buildingIndex(target) else { units[i].task = .idle; return }
            if unit.kind != .villager, let enemy = sighted(i, unitsOnly: true) { units[i].task = enemy; return }
            if unit.kind == .archer ? distance(to: buildings[b], unit.x, unit.y) <= Self.range(unit.kind) : touches(tile(of: unit), buildings[b]) {
                units[i].path = []
                if units[i].cooldown <= 0 {
                    buildings[b].hp -= Self.attack(unit.kind, against: nil) * Self.razing(unit.kind)
                    units[i].cooldown = 1.2; units[i].swung = 0
                    events.append(RTSEvent(kind: .attacked, owner: buildings[b].owner, x: Double(buildings[b].x) + 1, y: Double(buildings[b].y) + 1, time: time))
                }
            } else if go(i, toward: around(buildings[b]), dt) == .unreachable { units[i].task = .idle }
        }
    }

    /// The nearest thing worth fighting within sight: a soldier or villager, else a building — the
    /// town centre before a tower, a tower before a barracks, a barracks before the farms and houses.
    private func sighted(_ i: Int, unitsOnly: Bool = false) -> RTSTask? {
        let u = units[i]
        if let foe = units.filter({ $0.owner != u.owner && hypot($0.x - u.x, $0.y - u.y) <= Self.sight })
            .min(by: { hypot($0.x - u.x, $0.y - u.y) < hypot($1.x - u.x, $1.y - u.y) }) { return .attack(foe.id) }
        guard !unitsOnly else { return nil }
        func rank(_ b: RTSBuilding) -> Int {
            switch b.kind { case .townCenter: return 0; case .tower: return 1; case .barracks, .range, .stable: return 2; default: return 3 }
        }
        if let wall = buildings.filter({ $0.owner != u.owner && distance(to: $0, u.x, u.y) <= Self.sight })
            .min(by: { (rank($0), distance(to: $0, u.x, u.y)) < (rank($1), distance(to: $1, u.x, u.y)) }) { return .raze(wall.id) }
        return nil
    }

    enum Arrival { case arrived, walking, unreachable }

    /// Walk toward any of the goals. True on arrival — or when there is no way there.
    private mutating func walk(_ i: Int, toward wanted: Set<RTSTile>, _ dt: Double) -> Bool { go(i, toward: wanted, dt) != .walking }

    /// Walk toward any of the goals, and say how it went.
    private mutating func go(_ i: Int, toward wanted: Set<RTSTile>, _ dt: Double) -> Arrival {
        let here = RTSTile(x: Int(units[i].x), y: Int(units[i].y))
        // A goal nobody can stand on — a building, a tree — means the ground around it.
        var goals = wanted.filter(walkable)
        if goals.isEmpty {
            for radius in 1...3 where goals.isEmpty {
                for t in wanted { for dy in -radius...radius { for dx in -radius...radius {
                    let n = RTSTile(x: t.x + dx, y: t.y + dy)
                    if walkable(n) { goals.insert(n) }
                } } }
            }
        }
        if goals.contains(here), units[i].path.isEmpty { return .arrived }
        if units[i].path.isEmpty || units[i].repath <= 0 {
            units[i].repath = 3
            guard let found = path(from: here, to: goals) else { units[i].path = []; return .unreachable }
            units[i].path = found
            if found.isEmpty { return .arrived }
        }
        follow(i, dt)
        return units[i].path.isEmpty && goals.contains(RTSTile(x: Int(units[i].x), y: Int(units[i].y))) ? .arrived : .walking
    }

    /// The tile a unit stands on.
    func tile(of u: RTSUnit) -> RTSTile { RTSTile(x: Int(u.x), y: Int(u.y)) }

    /// Is this tile touching the building — on it or beside it?
    func touches(_ t: RTSTile, _ b: RTSBuilding) -> Bool {
        let n = Self.size(b.kind)
        return t.x >= b.x - 1 && t.x <= b.x + n && t.y >= b.y - 1 && t.y <= b.y + n
    }

    private mutating func follow(_ i: Int, _ dt: Double) {
        guard let next = units[i].path.first else { return }
        let tx = Double(next.x) + 0.5, ty = Double(next.y) + 0.5
        let dx = tx - units[i].x, dy = ty - units[i].y, d = hypot(dx, dy)
        let stepLength = Self.speed(units[i].kind) * dt
        if abs(dx) > 0.05 { units[i].facing = dx > 0 ? 1 : -1 }
        if d <= stepLength { units[i].x = tx; units[i].y = ty; units[i].path.removeFirst() }
        else { units[i].x += dx / d * stepLength; units[i].y += dy / d * stepLength }
    }

    // MARK: Villagers at work

    private mutating func gather(_ i: Int, _ tile: RTSTile, _ dt: Double) {
        let unit = units[i]
        let t = terrain[Self.index(tile)]
        guard let kind = Self.resource(of: t), amount[Self.index(tile)] > 0 else {
            // Used up: the next of the same, close by — or home with the load.
            let was = unit.carrying.flatMap { r -> RTSTerrain? in [RTSTerrain.berries, .forest, .gold, .stone][r.rawValue] }
            if let same = was.flatMap({ nearest($0, from: tile, within: 7) }) { units[i].task = .gather(same); units[i].path = [] }
            else if unit.load > 0 { deliver(i, dt, then: nil) }
            else { units[i].task = .idle }
            return
        }
        if unit.carrying != kind, unit.load > 0 { units[i].load = 0 }                  // dropped what it had
        units[i].carrying = kind
        if unit.load >= Self.carry { deliver(i, dt, then: .gather(tile)); return }
        let here = self.tile(of: unit)
        if max(abs(here.x - tile.x), abs(here.y - tile.y)) <= 1 {
            units[i].path = []
            let take = min(Self.gatherRate[t]! * dt, amount[Self.index(tile)], Self.carry - unit.load)
            units[i].load += take; amount[Self.index(tile)] -= take
            units[i].swung = 0; units[i].facing = Double(tile.x) + 0.5 >= unit.x ? 1 : -1
            if amount[Self.index(tile)] <= 0 { amount[Self.index(tile)] = 0; terrain[Self.index(tile)] = .grass }
        } else if go(i, toward: neighbours(tile), dt) == .unreachable {
            // No way there: the next nearest of the same that is not this one, else wait to be told.
            units[i].task = .idle
            if let other = nearest(t, from: here, within: 10, besides: tile) { units[i].task = .gather(other) }
        }
    }

    private mutating func farm(_ i: Int, _ id: Int, _ dt: Double) {
        guard let f = buildingIndex(id), buildings[f].done else { units[i].task = .idle; return }
        if buildings[f].farmer == nil { buildings[f].farmer = units[i].id }
        guard buildings[f].farmer == units[i].id else { units[i].task = .idle; return }
        units[i].carrying = .food
        if units[i].load >= Self.carry { deliver(i, dt, then: .farm(id)); return }
        let centre = RTSTile(x: buildings[f].x + 1, y: buildings[f].y + 1)
        if walk(i, toward: [centre], dt) {
            units[i].load += Self.farmRate * dt; units[i].swung = 0
            // Wander the rows a little while working.
            units[i].x = Double(centre.x) + 0.5 + 0.6 * sin(time * 0.7 + Double(units[i].id))
        }
    }

    /// Carry the load to the nearest place that takes it, then go back to `then`.
    private mutating func deliver(_ i: Int, _ dt: Double, then next: RTSTask?) {
        guard let kind = units[i].carrying, let site = dropSite(for: kind, owner: units[i].owner, near: units[i].x, units[i].y) else { units[i].task = .idle; return }
        if touches(tile(of: units[i]), site) {
            players[units[i].owner].stock[kind.rawValue] += units[i].load
            units[i].load = 0; units[i].path = []
            if let next { units[i].task = next } else { units[i].task = .idle }
        } else if go(i, toward: around(site), dt) == .unreachable { units[i].task = .idle; units[i].load = 0 }
    }

    /// A villager who has just finished a building: farm it, work by it, or look for work.
    private mutating func afterBuilding(_ i: Int, _ b: RTSBuilding) {
        let here = RTSTile(x: Int(units[i].x), y: Int(units[i].y))
        switch b.kind {
        case .farm: command(units[i].id, .farm(b.id))
        case .lumberCamp: if let tree = nearest(.forest, from: here, within: 8) { command(units[i].id, .gather(tree)) } else { settle(i) }
        case .miningCamp: if let rock = nearest(.gold, from: here, within: 8) ?? nearest(.stone, from: here, within: 8) { command(units[i].id, .gather(rock)) } else { settle(i) }
        case .mill: if let bush = nearest(.berries, from: here, within: 8) { command(units[i].id, .gather(bush)) } else { settle(i) }
        default: settle(i)
        }
    }

    /// Anything left unfinished of its owner's to help build, else stand.
    private mutating func settle(_ i: Int) {
        let u = units[i]
        if let site = buildings.filter({ $0.owner == u.owner && !$0.done }).min(by: { distance(to: $0, u.x, u.y) < distance(to: $1, u.x, u.y) }),
           distance(to: site, u.x, u.y) < 12 {
            units[i].task = .build(site.id)
        } else { units[i].task = .idle }
        units[i].path = []
    }
}
