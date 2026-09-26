import Foundation

/// What a mayor leans toward: the need that comes first when there is a choice.
enum CityFocus: String, CaseIterable { case food, firewood, housing, materials, tools, growth }

/// The town measured: what a mayor — the script, Jev, a chat model or the
/// person — would want to know before deciding what comes next.
struct CityLedger {
    let people: Int, adults: Int, able: Int, children: Int, retired: Int, homeless: Int
    let room: Int, houses: Int, housesBuilding: Int
    let food: Double, logs: Double, stone: Double, iron: Double, firewood: Double, tools: Double
    /// Food a year: eaten by everybody; what the places working now would bring in; what came in this past year.
    let eat: Double, foodCapacity: Double, foodMade: Double
    /// Firewood the houses burn from now to the end of the coming cold months, and what the woodcutters could split by then.
    let firewoodNeed: Double, firewoodCapacity: Double
    let monthsToWinter: Int
    let workers: Int, laborers: Int, sites: Int
    let count: [Int]
    /// Materials still to be brought to the building sites.
    let siteLogs: Double, siteStone: Double

    init(_ w: CityWorld) {
        people = w.people.count
        adults = w.people.filter(\.adult).count
        able = w.people.filter(\.worker).count
        children = people - adults
        retired = w.people.filter(\.retired).count
        homeless = w.homeless
        houses = w.buildings.filter { $0.kind == .house && $0.done }.count
        housesBuilding = w.buildings.filter { $0.kind == .house && !$0.done }.count
        room = houses * CityWorld.houseRoom
        food = w.stored(.food) + w.atHome(.food)
        logs = w.stored(.logs); stone = w.stored(.stone); iron = w.stored(.iron)
        firewood = w.stored(.firewood) + w.atHome(.firewood)
        tools = w.stored(.tools)
        eat = Double(people) * 12
        var capacity = 0.0
        for b in w.buildings where b.done {
            let n = Double(w.workers(b.id))
            switch b.kind {
            case .field: capacity += CityBrain.fieldYield(w, b, workers: n)
            case .gatherer: capacity += min(n * CityBrain.perGatherer, CityBrain.forage(w, b) * 0.8)
            case .fishery: capacity += min(n * CityBrain.perFisher, CityBrain.fishing(w, b) * 5)
            default: break
            }
        }
        foodCapacity = capacity
        foodMade = w.madeLastYear(.food)
        let m = w.monthOfYear
        monthsToWinter = m < 9 ? 9 - m : 0
        let occupied = w.buildings.filter { b in b.kind == .house && b.done && w.people.contains { $0.home == b.id } }.count
        let coldLeft = m == 0 ? 1 : m >= 9 ? 12 - m + 1 : 4
        firewoodNeed = Double(max(occupied, (people + 4) / 5)) * 2 * Double(coldLeft)
        let splitters = w.buildings.filter { $0.kind == .woodcutter && $0.done }.reduce(0) { $0 + w.workers($1.id) }
        firewoodCapacity = Double(splitters) * 40 * Double(max(1, monthsToWinter))
        workers = w.people.filter { $0.job != nil }.count
        laborers = w.people.filter { $0.worker && $0.job == nil }.count
        let open = w.buildings.filter { !$0.done }
        sites = open.count
        siteLogs = open.reduce(0) { $0 + max(0, CityWorld.cost($1.kind)[1] - $1.delivered[1]) }
        siteStone = open.reduce(0) { $0 + max(0, CityWorld.cost($1.kind)[2] - $1.delivered[2]) }
        count = CityKind.allCases.map { k in w.buildings.filter { $0.kind == k }.count }
    }
    func has(_ k: CityKind) -> Int { count[k.rawValue] }
    var monthsOfFood: Double { people == 0 ? 99 : food / Double(people) }
}

/// The computer as mayor: a player who knows what a town needs and in what order —
/// a roof before winter, food for everybody with some over, firewood for the cold
/// months, logs and stone to build with, tools, then room to grow. Each look it
/// starts at most one building and sets how many work where; a commander's
/// focus goes to the front of its list.
struct CityBrain {
    var clock = 0.0
    /// A commander's leaning — Jev's or a chat model's — or nil for the script's own order.
    var focus: CityFocus?

    mutating func think(_ w: inout CityWorld, _ dt: Double) {
        clock += dt
        guard clock >= 1.5, !w.over else { return }
        clock = 0
        plan(&w, CityLedger(w))
        staff(&w, CityLedger(w))
    }

    /// For the person's town: only how many work where; what is built is the person's.
    mutating func staffOnly(_ w: inout CityWorld, _ dt: Double) {
        clock += dt
        guard clock >= 1.5, !w.over else { return }
        clock = 0
        staff(&w, CityLedger(w))
    }

    /// How pressing each need is now, measured: 3 is people dying soon, 2 the town held back, 1 in hand, 0 nothing to do.
    func urgency(_ need: CityFocus, _ l: CityLedger) -> Double {
        switch need {
        case .food:
            if l.monthsOfFood < 4 { return 3 }
            if l.foodCapacity < l.eat || l.foodMade < l.eat && l.monthsOfFood < 10 { return 2.2 }
            return l.monthsOfFood < 18 ? 1.2 : 0.3
        case .firewood:
            if l.has(.woodcutter) == 0, l.houses + l.housesBuilding > 0 { return 2.6 }
            if l.firewood < l.firewoodNeed, l.monthsToWinter <= 3 { return 3 }
            return l.firewood < l.firewoodNeed ? 1.8 : 0.8
        case .housing:
            if l.homeless > 0 { return l.monthsToWinter <= 4 ? 3 : 2.4 }
            return l.room - l.people < 3 ? 1.1 : 0.2
        case .materials:
            if l.has(.forester) == 0 { return 2.8 }
            let house = CityWorld.cost(.house)
            if l.logs < house[1] || l.stone < house[2] { return 2.3 }
            return l.logs < 80 || l.stone < 40 ? 1.4 : 0.6
        case .tools:
            guard l.workers >= 8 else { return 0 }
            if l.tools < Double(l.workers) * 0.3 { return 2.5 }
            return l.tools < Double(l.workers) ? 1.5 : 0.4
        case .growth:
            return l.monthsOfFood > 5 && l.room - l.people < 6 ? 1 : 0
        }
    }

    /// The needs in the order they are seen to: the most pressing first; a commander's focus before anything
    /// but people dying soon.
    func order(_ l: CityLedger) -> [CityFocus] {
        let base: [CityFocus] = [.food, .firewood, .housing, .materials, .tools, .growth]
        // A focus lifts a need up the list, but never above one where people will die soon.
        func rank(_ n: CityFocus) -> Double { let u = urgency(n, l); return n == focus ? max(u, min(u + 1.5, 2.95)) : u }
        return base.sorted { a, b in
            let ua = rank(a), ub = rank(b)
            return ua != ub ? ua > ub : base.firstIndex(of: a)! < base.firstIndex(of: b)!
        }
    }

    // MARK: What to build

    mutating func plan(_ w: inout CityWorld, _ l: CityLedger) {
        let limit = 1 + l.able / 10
        for need in order(l) {
            let urgent = need == .housing && l.homeless > 0
            guard l.sites < limit || urgent && l.sites < limit + 2 else { return }
            if let kind = wants(need, w, l), let at = site(for: kind, w, l) {
                if w.place(kind, at: at) != nil, kind != .field { connect(at, kind, &w) }
                return
            }
        }
    }

    /// What a need calls for now, if anything.
    func wants(_ need: CityFocus, _ w: CityWorld, _ l: CityLedger) -> CityKind? {
        let affordable = { (k: CityKind) -> Bool in
            // Until there is a lumber camp, the wood for one is not spent on anything else: without it there is never more.
            let keep = l.has(.forester) == 0 && k != .forester ? CityWorld.cost(.forester) : [0, 0, 0, 0, 0, 0]
            let c = CityWorld.cost(k)
            return l.logs - l.siteLogs - keep[1] >= c[1] && l.stone - l.siteStone - keep[2] >= c[2]
        }
        switch need {
        case .housing:
            let short = l.homeless + max(0, l.people + 2 - l.room) - l.housesBuilding * CityWorld.houseRoom
            return short > 0 && affordable(.house) ? .house : nil
        case .food:
            let fellShort = w.year > 1 && l.foodMade < l.eat * 1.05 && l.monthsOfFood < 10
            let idleHands = l.laborers > 4 + l.sites * 2 && l.monthsOfFood < 12
            guard l.monthsOfFood < 18 else { return nil }
            guard l.foodCapacity < CityBrain.foodTarget(l) || l.monthsOfFood < 4 || fellShort || idleHands else { return nil }
            if l.has(.gatherer) == 0 { return .gatherer }
            // Hands before buildings: another food place only when those there are full.
            let open = w.buildings.filter { [.gatherer, .fishery, .field].contains($0.kind) }
                .reduce(0) { $0 + ($1.done ? CityWorld.slots($1.kind) - w.workers($1.id) : CityWorld.slots($1.kind)) }
            if l.has(.fishery) == 0, CityBrain.hasWater(w) { return affordable(.fishery) ? .fishery : nil }
            guard open == 0 else { return nil }
            if l.has(.gatherer) < 1 + l.people / 40, affordable(.gatherer) { return .gatherer }
            return .field
        case .firewood:
            if l.has(.woodcutter) == 0, l.houses + l.housesBuilding >= 1 { return affordable(.woodcutter) ? .woodcutter : nil }
            let slots = l.has(.woodcutter) * CityWorld.slots(.woodcutter)
            if Double(slots) * CityBrain.perSplitter < CityBrain.firewoodTarget(l), affordable(.woodcutter) { return .woodcutter }
            return nil
        case .materials:
            if l.has(.forester) == 0 || l.logs < 60 && l.has(.forester) < 1 + l.people / 35 { return affordable(.forester) ? .forester : nil }
            let quarried = w.buildings.filter { $0.kind == .quarry }.allSatisfy { $0.reserve < 80 }
            if l.has(.quarry) == 0 || quarried || l.stone < 40 && l.has(.quarry) < 1 + l.people / 60 { return affordable(.quarry) ? .quarry : nil }
            if CityBrain.storageFull(w) || l.people >= 28 && l.has(.storage) == 0 || CityBrain.farFromStorage(w) != nil { return affordable(.storage) ? .storage : nil }
            return nil
        case .tools:
            guard w.year >= 2 || l.tools < Double(l.workers) * 0.6 else { return nil }
            let mined = w.buildings.filter { $0.kind == .mine }.allSatisfy { $0.reserve < 30 }
            if l.has(.mine) == 0 || mined && l.iron < 20 { return affordable(.mine) ? .mine : nil }
            if l.has(.blacksmith) == 0 { return affordable(.blacksmith) ? .blacksmith : nil }
            return nil
        case .growth:
            guard l.room - l.people < 6, l.monthsOfFood > 5, l.foodCapacity > l.eat * 1.2 else { return nil }
            return affordable(.house) ? .house : nil
        }
    }

    // MARK: Who works where

    mutating func staff(_ w: inout CityWorld, _ l: CityLedger) {
        var free = l.able - (l.sites > 0 ? min(max(2, l.able / 4), 2 + l.sites * 2) : 1)
        var want: [Int: Int] = [:]
        func give(_ id: Int, _ n: Int) {
            guard free > 0 else { return }
            let slots = CityWorld.slots(w.building(id)!.kind) - want[id, default: 0]
            let k = min(n, slots, free)
            guard k > 0 else { return }
            want[id, default: 0] += k; free -= k
        }
        let places = w.buildings.filter { $0.done && CityWorld.slots($0.kind) > 0 }
        func of(_ k: CityKind) -> [CityBuilding] { places.filter { $0.kind == k } }
        for need in order(l) {
            switch need {
            case .food:
                // Enough hands for the food the town eats, with a margin: the cheapest food first.
                var capacity = 0.0
                let target = CityBrain.foodTarget(l)
                // Gatherers and fishermen bring food in every month but winter; a field only in autumn.
                for b in of(.gatherer) where capacity < target {
                    give(b.id, min(3, Int(ceil((target - capacity) / CityBrain.perGatherer))))
                    capacity += min(Double(want[b.id, default: 0]) * CityBrain.perGatherer, CityBrain.forage(w, b) * 0.8)
                }
                for b in of(.fishery) where capacity < target {
                    give(b.id, min(3, Int(ceil((target - capacity) / CityBrain.perFisher))))
                    capacity += min(Double(want[b.id, default: 0]) * CityBrain.perFisher, CityBrain.fishing(w, b) * 5)
                }
                for b in of(.field) where capacity < target {
                    give(b.id, 2); capacity += CityBrain.fieldYield(w, b, workers: Double(want[b.id, default: 0]))
                }
            case .firewood:
                // Hands for a year's firewood with a margin, and more while the stock is short of the coming winter.
                var need = CityBrain.firewoodTarget(l) + (l.firewood < l.firewoodNeed ? l.firewoodNeed - l.firewood : 0)
                for b in of(.woodcutter) where need > 0 {
                    let n = min(2, Int(ceil(need / CityBrain.perSplitter)))
                    give(b.id, n); need -= Double(want[b.id, default: 0]) * CityBrain.perSplitter
                }
            case .housing, .growth:
                break
            case .materials:
                for b in of(.forester) { give(b.id, l.logs < 80 || l.siteLogs > 20 ? 3 : l.logs < 300 ? 2 : 1) }
                for b in of(.quarry) where b.reserve > 0 { give(b.id, l.stone < 60 ? 3 : l.stone < 200 ? 2 : 0) }
            case .tools:
                let short = l.tools < Double(l.workers) * 1.2
                for b in of(.mine) where b.reserve > 0 { give(b.id, short && l.iron < 30 ? 2 : l.iron < 10 ? 1 : 0) }
                for b in of(.blacksmith) { give(b.id, short ? (l.tools < Double(l.workers) * 0.5 ? 2 : 1) : 0) }
            }
        }
        // Hands left over: food while the stores are not full, then wood while it is short; the rest build.
        if l.monthsOfFood < 12 { for b in of(.field) { give(b.id, 2) }; for b in of(.gatherer) { give(b.id, 3) } }
        if l.logs < 300 { for b in of(.forester) { give(b.id, 1) } }
        for b in places.indices { w.buildings[w.buildingIndex(places[b].id)!].wanted = want[places[b].id, default: 0] }
    }

    // MARK: Where

    /// A place for a building of this kind: the best by what the kind cares about, with room to walk around it.
    func site(for kind: CityKind, _ w: CityWorld, _ l: CityLedger) -> CityTile? {
        guard let hall = w.hall else { return nil }
        let hc = w.centre(hall), n = CityWorld.size(kind)
        let stores = w.buildings.filter { CityWorld.stores($0.kind) }
        func storeDistance(_ x: Double, _ y: Double) -> Double { stores.map { w.distance($0, x, y) }.min() ?? 99 }
        var best: CityTile?, bestScore = Double.infinity
        let radius = kind == .mine || kind == .quarry || kind == .fishery ? 44 : kind == .forester || kind == .gatherer ? 26 : 18
        let focusX = kind == .storage ? CityBrain.farFromStorage(w)?.x ?? hc.x : hc.x, focusY = kind == .storage ? CityBrain.farFromStorage(w)?.y ?? hc.y : hc.y
        for dy in -radius...radius {
            for dx in -radius...radius {
                let o = CityTile(x: Int(focusX) + dx - n / 2, y: Int(focusY) + dy - n / 2)
                guard w.fits(kind, at: o), clear(o, n, w, field: kind == .field) else { continue }
                // The ground beside rock and ore is kept for the quarries and mines.
                if kind != .quarry, kind != .mine, w.near(.rock, o, n, 2) + w.near(.ore, o, n, 2) > 0 { continue }
                let cx = Double(o.x) + Double(n) / 2, cy = Double(o.y) + Double(n) / 2
                let toStore = storeDistance(cx, cy)
                var score: Double
                switch kind {
                case .house:
                    score = hypot(cx - hc.x, cy - hc.y) + (touchesRoad(o, n, w) ? 0 : 2)
                case .field:
                    guard toStore < 16 else { continue }
                    let f = w.fieldFertility(CityBuilding(id: 0, kind: .field, x: o.x, y: o.y))
                    score = toStore - f * 8 + hypot(cx - hc.x, cy - hc.y) * 0.2
                case .gatherer, .forester:
                    guard !w.buildings.contains(where: { $0.kind == kind && w.distance($0, cx, cy) < 11 }) else { continue }
                    let probe = CityBuilding(id: 0, kind: kind, x: o.x, y: o.y)
                    let wood = kind == .gatherer ? CityBrain.forage(w, probe) / 3 : CityBrain.trees(w, probe)
                    guard wood >= 20 else { continue }
                    score = -wood * 0.12 + toStore * 0.6
                case .fishery:
                    let probe = CityBuilding(id: 0, kind: kind, x: o.x, y: o.y)
                    let water = CityBrain.fishing(w, probe)
                    guard water >= 8 else { continue }
                    score = -water * 0.1 + toStore * 0.6
                case .quarry:
                    score = -Double(w.near(.rock, o, n, 2)) * 0.6 + toStore * 0.4
                case .mine:
                    score = -Double(w.near(.ore, o, n, 2)) * 0.6 + toStore * 0.4
                case .storage:
                    score = hypot(cx - focusX, cy - focusY) + (stores.contains { w.distance($0, cx, cy) < 9 } ? 50 : 0)
                default:
                    score = toStore + hypot(cx - hc.x, cy - hc.y) * 0.3
                }
                if score < bestScore { bestScore = score; best = o }
            }
        }
        return best
    }

    /// A ring of open ground around a building, so nobody is walled in — fields may sit side by side.
    private func clear(_ o: CityTile, _ n: Int, _ w: CityWorld, field: Bool) -> Bool {
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n {
            let t = CityTile(x: o.x + dx, y: o.y + dy)
            guard CityWorld.inside(t) else { return false }
            if let b = w.occupant[CityWorld.index(t)], !(field && w.building(b)?.kind == .field) { return false }
        } }
        return true
    }

    private func touchesRoad(_ o: CityTile, _ n: Int, _ w: CityWorld) -> Bool {
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n {
            let t = CityTile(x: o.x + dx, y: o.y + dy)
            if CityWorld.inside(t), w.road[CityWorld.index(t)] { return true }
        } }
        return false
    }

    /// A road from a new building's door to the nearest road already there — or to the town hall, for the first.
    func connect(_ o: CityTile, _ kind: CityKind, _ w: inout CityWorld) {
        guard let hall = w.hall, let id = w.occupant[CityWorld.index(o)], let b = w.building(id) else { return }
        let hc = w.centre(hall)
        guard let door = w.around(b).sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }).min(by: { hypot(Double($0.x) - hc.x, Double($0.y) - hc.y) < hypot(Double($1.x) - hc.x, Double($1.y) - hc.y) }) else { return }
        var goals = w.around(hall)
        for y in max(0, door.y - 14)...min(CityWorld.height - 1, door.y + 14) {
            for x in max(0, door.x - 14)...min(CityWorld.width - 1, door.x + 14) where w.road[y * CityWorld.width + x] { goals.insert(CityTile(x: x, y: y)) }
        }
        if goals.contains(door) { return }
        guard let route = w.path(from: door, to: goals) else { return }
        for t in [door] + route { w.lay(road: t) }
    }

    /// Measured over whole years of play: what a worker brings in a year.
    static let perGatherer = 42.0, perFisher = 32.0, perSplitter = 150.0
    /// Firewood a year: two a month for each house through the four cold months, with a margin.
    static func firewoodTarget(_ l: CityLedger) -> Double { Double(max(l.houses, (l.people + 4) / 5)) * 8 * 1.3 }
    static func fieldYield(_ w: CityWorld, _ b: CityBuilding, workers n: Double) -> Double {
        100 * w.fieldFertility(b) * min(1, n * 0.6)
    }

    /// Food a year worth having hands for: more when the stores are low, less while they are full.
    static func foodTarget(_ l: CityLedger) -> Double {
        let margin = l.monthsOfFood < 4 ? 1.6 : l.monthsOfFood < 8 ? 1.35 : l.monthsOfFood < 14 ? 1.15 : 0.9
        return l.eat * margin + 24
    }

    // MARK: Measures of a place

    static func forage(_ w: CityWorld, _ b: CityBuilding) -> Double {
        within(w, b) { i in w.ground[i] == .forest ? 3 : 0 }
    }
    static func trees(_ w: CityWorld, _ b: CityBuilding) -> Double {
        within(w, b) { i in w.ground[i] == .forest && w.wood[i] >= 1 ? 1 : 0 }
    }
    static func fishing(_ w: CityWorld, _ b: CityBuilding) -> Double {
        within(w, b) { i in w.ground[i] == .water && !w.neighbours(CityTile(x: i % CityWorld.width, y: i / CityWorld.width)).isEmpty ? 1 : 0 }
    }
    static func within(_ w: CityWorld, _ b: CityBuilding, _ value: (Int) -> Double) -> Double {
        let c = w.centre(b), r = CityWorld.reach
        var total = 0.0
        for y in max(0, Int(c.y) - r)...min(CityWorld.height - 1, Int(c.y) + r) {
            for x in max(0, Int(c.x) - r)...min(CityWorld.width - 1, Int(c.x) + r) where hypot(Double(x) + 0.5 - c.x, Double(y) + 0.5 - c.y) <= Double(r) {
                total += value(y * CityWorld.width + x)
            }
        }
        return total
    }
    static func hasWater(_ w: CityWorld) -> Bool {
        guard let hall = w.hall else { return false }
        let c = w.centre(hall)
        for y in 0..<CityWorld.height { for x in 0..<CityWorld.width where w.ground[y * CityWorld.width + x] == .water && hypot(Double(x) - c.x, Double(y) - c.y) < 22 { return true } }
        return false
    }
    static func storageFull(_ w: CityWorld) -> Bool {
        let stores = w.buildings.filter { $0.done && CityWorld.stores($0.kind) }
        let cap = stores.reduce(0) { $0 + CityWorld.capacity($1.kind) }, held = stores.reduce(0) { $0 + $1.stock.reduce(0, +) }
        return cap > 0 && held / cap > 0.7
    }
    /// The middle of the workplaces that are a long walk from any storage, if there are some.
    static func farFromStorage(_ w: CityWorld) -> (x: Double, y: Double)? {
        let stores = w.buildings.filter { CityWorld.stores($0.kind) }
        let far = w.buildings.filter { b in CityWorld.slots(b.kind) > 0 && (stores.map { w.distance($0, w.centre(b).x, w.centre(b).y) }.min() ?? 99) > 13 }
        guard far.count >= 2 else { return nil }
        let cs = far.map { w.centre($0) }
        return (cs.map(\.x).reduce(0, +) / Double(cs.count), cs.map(\.y).reduce(0, +) / Double(cs.count))
    }
}
