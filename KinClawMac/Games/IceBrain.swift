import Foundation

/// What a lord leans toward: the need that comes first when there is a choice.
enum IceFocus: String, CaseIterable { case heat, coal, food, housing, materials, iron, health, defence, conquest }

/// The frozen city measured: what a lord — the script, Jev, a chat model or
/// the person — would want to know before deciding what comes next.
struct IceLedger {
    let day: Int, temperature: Double
    let people: Int, able: Int, kids: Int, sick: Int, homeless: Int
    /// People sleeping in houses outside the heat, and with no house at all.
    let cold: Int
    let houses: Int, warmHouses: Int, housesBuilding: Int, room: Int, warmRoom: Int
    let coal: Double, wood: Double, food: Double, stone: Double, iron: Double
    /// A day: coal burnt, and dug by the miners at work now; food eaten, and brought in by those at work now.
    let burn: Double, coalCapacity: Double, eats: Double, foodCapacity: Double
    let woodCapacity: Double, stoneCapacity: Double, ironCapacity: Double
    /// The same with every job in every building filled, and what the counties send.
    let full: [Double], tribute: [Double]
    let level: Int, upgrading: Bool
    let workers: Int, laborers: Int, sites: Int
    let count: [Int]
    /// Materials still to be brought to the building sites, and of that to the furnace's upgrade.
    let siteNeeds: [Double], furnaceNeeds: [Double]
    /// The next cold spell, and the great blizzard: when, and how cold.
    let coldStart: Int?, coldEnd: Int?, coldIsBlizzard: Bool
    let blizzardStart: Int, blizzardEnd: Int
    /// In the blizzard at the furnace's level now: warm houses in the wind, and behind a wall.
    let blizzardWarm: Double, blizzardSheltered: Double, blizzardCold: Double
    /// Houses with people in them behind a wall, and all houses with people.
    let shelteredHouses: Int, livedIn: Int
    let soldiers: Int, wounded: Int, defence: Double
    let raidDay: Int?, raiders: Double
    let morale: Double, heals: Double

    init(_ w: IceCity) {
        day = w.today; temperature = w.temperature(on: w.today)
        people = w.people.count
        able = w.people.filter(\.worker).count
        kids = w.people.filter(\.kid).count
        sick = w.sick
        homeless = w.people.filter { $0.home == nil && !IceCity.going($0) }.count
        let houseList = w.buildings.filter { $0.kind == .house && $0.done }
        let warmIDs = Set(houseList.filter { w.warmed($0) }.map(\.id))
        cold = w.people.filter { p in p.home.map { !warmIDs.contains($0) } ?? true }.count
        houses = houseList.count
        warmHouses = warmIDs.count
        housesBuilding = w.buildings.filter { $0.kind == .house && !$0.done }.count
        room = houses * IceCity.houseRoom
        warmRoom = warmHouses * IceCity.houseRoom
        coal = w.total(.coal); wood = w.stored(.wood); food = w.total(.food); stone = w.stored(.stone); iron = w.stored(.iron)
        burn = w.burnRate
        eats = w.eats
        var capacity = [Double](repeating: 0, count: 5), whole = [Double](repeating: 0, count: 5), sent = [Double](repeating: 0, count: 5)
        for b in w.buildings where b.done {
            let good = IceBrain.good(of: b.kind)
            guard let good else { continue }
            capacity[good.rawValue] += IceBrain.yield(w, b, workers: Double(w.workers(b.id)))
            whole[good.rawValue] += IceBrain.yield(w, b, workers: Double(b.kind.slots))
        }
        for (i, c) in iceRegions.enumerated() where i > 0 && w.owner[i] == 0 { sent[c.resource.rawValue] += c.amount }
        for g in 0..<5 { capacity[g] += sent[g]; whole[g] += sent[g] }
        full = whole; tribute = sent
        coalCapacity = capacity[0]; woodCapacity = capacity[1]; foodCapacity = capacity[2]; stoneCapacity = capacity[3]; ironCapacity = capacity[4]
        level = w.level
        upgrading = w.furnace?.upgrading ?? false
        workers = w.people.filter { $0.job != nil }.count
        laborers = w.people.filter { $0.worker && $0.job == nil }.count
        let open = w.buildings.filter(\.site)
        sites = open.count
        var needs = [Double](repeating: 0, count: 5), furnace = [Double](repeating: 0, count: 5)
        for b in open { for g in 0..<5 {
            let left = max(0, w.cost(of: b)[g] - b.delivered[g])
            needs[g] += left
            if b.kind == .furnace { furnace[g] += left }
        } }
        siteNeeds = needs; furnaceNeeds = furnace
        count = IceBuildKind.allCases.map { w.count($0, done: false) }
        let next = w.nextCold(after: w.today)
        coldStart = next?.start; coldEnd = next?.end; coldIsBlizzard = next?.blizzard ?? false
        blizzardStart = w.blizzard.start; blizzardEnd = w.blizzard.end
        let mid = (w.blizzard.start + w.blizzard.end) / 2
        let t = w.temperature(on: mid), power = IceCity.heatPower[min(w.level + (w.furnace?.upgrading == true ? 1 : 0), IceCity.topLevel)]
        blizzardWarm = t + power - 5; blizzardSheltered = t + power + 5; blizzardCold = t + 8 - 5
        let lived = houseList.filter { h in w.people.contains { $0.home == h.id } }
        livedIn = lived.count
        shelteredHouses = lived.filter { w.sheltered($0) }.count
        soldiers = w.soldiers; wounded = w.wounded; defence = w.defenceAtHome
        if let threat = w.raidThreat { raidDay = threat.day; raiders = threat.raiders } else { raidDay = nil; raiders = 0 }
        morale = w.morale; heals = w.heals
    }
    func has(_ k: IceBuildKind) -> Int { count[k.rawValue] }
    var coalNet: Double { coalCapacity - burn }
    var foodNet: Double { foodCapacity - eats }
    /// Days a store lasts at the rate it goes now; 999 when it grows.
    var coalDays: Double { coalNet >= 0 ? 999 : coal / -coalNet }
    var foodDays: Double { foodNet >= 0 ? 999 : food / -foodNet }
    var daysToBlizzard: Int { blizzardStart - day }
    var afterBlizzard: Bool { day > blizzardEnd }
    /// Materials in the storages not already promised to a site.
    var spare: [Double] { [coal, wood - siteNeeds[1], food, stone - siteNeeds[3], iron - siteNeeds[4]] }
}

/// The computer as lord: a player who knows what a frozen city needs and in
/// what order — the furnace lit and reaching every house, coal and food with
/// some over, roofs inside the heat, the wood, stone and iron to build and
/// upgrade, a clinic for the sick, the north wall up before the blizzard,
/// then soldiers, generals and counties. Each look it starts at most one
/// thing and sets how many work where; a commander's focus goes to the front.
struct IceBrain {
    var clock = 0.0, warClock = 0.0
    /// A commander's leaning — Jev's or a chat model's — or nil for the script's own order.
    var focus: IceFocus?

    /// Measured over whole days of play: what one worker brings in a day.
    static let perCoal = 3.0, perWood = 3.0, perHunter = 3.2, perFisher = 4.0, perGreenhouse = 3.2, perStone = 2.6, perIron = 1.8

    mutating func think(_ w: inout IceCity, _ dt: Double) {
        clock += dt; warClock += dt
        guard clock >= 1.5, !w.over else { return }
        clock = 0
        // A mine or quarry dug out is taken down: its ground and half its materials come back.
        if let spent = w.buildings.first(where: { [.coalMine, .ironMine, .quarry].contains($0.kind) && $0.done && $0.reserve <= 0 }) { w.remove(spent.id) }
        plan(&w, IceLedger(w))
        staff(&w, IceLedger(w))
        if warClock >= 4 { warClock = 0; war(&w, IceLedger(w)) }
    }

    /// For the person's city: only how many work where.
    mutating func staffOnly(_ w: inout IceCity, _ dt: Double) {
        clock += dt
        guard clock >= 1.5, !w.over else { return }
        clock = 0
        staff(&w, IceLedger(w))
    }

    /// How pressing each need is now, measured: 3 is people dying soon, 2 the city held back, 1 in hand, 0 nothing to do.
    func urgency(_ need: IceFocus, _ l: IceLedger, _ w: IceCity) -> Double {
        switch need {
        case .heat:
            let wanted = IceBrain.levelWanted(l)
            if l.level < wanted, !l.upgrading { return l.daysToBlizzard < 16 && !l.afterBlizzard ? 2.9 : 2.3 }
            if l.cold > 0, !l.upgrading, !IceBrain.roomInHeat(w) { return (l.coldStart ?? 99) - l.day < 4 ? 2.8 : 2.2 }
            return l.upgrading ? 0.5 : 0.3
        case .coal:
            if l.coal < l.burn * 4 { return 3 }
            if l.has(.coalMine) == 0 { return 2.7 }
            if l.full[0] < l.burn * 1.2 { return 2.4 }
            if l.coal < IceBrain.coalWanted(l) { return 1.6 }
            return 0.4
        case .food:
            if l.food < l.eats * 4 { return 3 }
            if l.has(.hunter) + l.has(.fishery) + l.has(.greenhouse) == 0 { return 2.9 }
            if l.full[2] < l.eats * 1.2 { return 2.3 }
            if l.food < l.eats * 8 { return 1.4 }
            return 0.4
        case .housing:
            if l.homeless > 0 { return 2.6 }
            if l.cold > 0, IceBrain.roomInHeat(w) { return 2.5 }
            return l.warmRoom - l.people < 4 ? 1.3 : 0.2
        case .materials:
            if l.has(.lumber) == 0 { return 2.6 }
            if l.spare[1] < 40 || l.spare[3] < 15 { return 2.1 }
            return l.wood < 150 ? 1.2 : 0.5
        case .iron:
            let need = IceCity.upgradeCost(to: min(IceCity.topLevel, l.level + 1))[4]
            if l.has(.ironMine) == 0, l.furnaceNeeds[4] > l.iron { return 2.7 }
            if l.has(.ironMine) == 0, l.day >= 4 { return l.iron < need ? 1.9 : 1.1 }
            return l.iron < need ? 1.3 : 0.2
        case .health:
            if l.sick >= 3, l.has(.clinic) == 0 { return 2.5 }
            if Double(l.sick) > max(2, l.heals * 2) { return 1.8 }
            return l.has(.clinic) == 0 && l.day > 10 ? 1 : 0.2
        case .defence:
            if let raid = l.raidDay, raid - l.day <= 8, l.defence < l.raiders * 1.1 { return 2.2 }
            if !l.afterBlizzard, l.daysToBlizzard < 28, l.shelteredHouses < l.livedIn { return l.daysToBlizzard < 12 ? 2.6 : 1.9 }
            return 0.2
        case .conquest:
            guard l.day > 6 else { return 0 }
            let settled = l.coal > l.burn * 6 && l.food > l.eats * 8 && l.full[2] >= l.eats && l.full[0] >= l.burn
            if l.has(.barracks) == 0 { return settled ? 2.0 : 1.0 }
            if l.has(.tavern) == 0 { return settled ? 1.4 : 0.8 }
            return settled ? 1 : 0.6
        }
    }

    /// The furnace level worth having by now: two by the first real cold, three by mid-winter, four before the blizzard.
    static func levelWanted(_ l: IceLedger) -> Int {
        if l.day > 75 { return l.day > 100 || l.people > 60 ? 5 : 4 }
        if l.daysToBlizzard <= 22 { return 4 }
        if l.day >= 32 || l.people > 34 { return 3 }
        if l.day >= 10 || l.people > 22 { return 2 }
        return 1
    }
    /// Coal worth keeping in store: a week of burning, and before the blizzard enough for all of it.
    static func coalWanted(_ l: IceLedger) -> Double {
        var want = l.burn * 6 + 20
        if !l.afterBlizzard, l.daysToBlizzard < 20 { want = max(want, l.burn * 1.3 * Double(l.blizzardEnd - l.blizzardStart + 3)) }
        return want
    }

    /// The needs in the order they are seen to: the most pressing first; a commander's focus before anything but people dying soon.
    func order(_ l: IceLedger, _ w: IceCity) -> [IceFocus] {
        let base = IceFocus.allCases
        func rank(_ n: IceFocus) -> Double { let u = urgency(n, l, w); return n == focus ? max(u, min(u + 1.5, 2.95)) : u }
        let ranks = Dictionary(uniqueKeysWithValues: base.map { ($0, rank($0)) })
        return base.sorted { a, b in ranks[a]! != ranks[b]! ? ranks[a]! > ranks[b]! : base.firstIndex(of: a)! < base.firstIndex(of: b)! }
    }

    // MARK: What to build

    enum Step: Equatable { case build(IceBuildKind), upgrade, wall }

    mutating func plan(_ w: inout IceCity, _ l: IceLedger) {
        let limit = max(3, 1 + l.able / 9)
        for need in order(l, w) {
            let urgent = need == .housing && l.homeless > 0 || need == .heat || need == .defence
            guard l.sites < limit || urgent && l.sites < limit + 2 else { return }
            guard let step = wants(need, w, l) else { continue }
            if carry(step, &w, l) { return }
        }
    }

    /// Carry out a step: place the building where it does most good, start the upgrade, raise the next stretch of wall.
    @discardableResult
    func carry(_ step: Step, _ w: inout IceCity, _ l: IceLedger) -> Bool {
        switch step {
        case .upgrade: return w.upgradeFurnace()
        case .wall:
            let line = IceBrain.wallLine(w)
            let n = w.raise(walls: Array(line.prefix(8)))
            return n > 0
        case .build(let kind):
            guard let at = site(for: kind, w, l), w.place(kind, at: at) != nil else { return false }
            connect(at, kind, &w)
            return true
        }
    }

    /// What a need calls for now, if anything.
    func wants(_ need: IceFocus, _ w: IceCity, _ l: IceLedger) -> Step? {
        let affordable = { (k: IceBuildKind) -> Bool in
            // Until there is a lumber camp, the wood for one is not spent on anything else.
            let keep = l.has(.lumber) == 0 && k != .lumber ? IceBuildKind.lumber.cost : [0, 0, 0, 0, 0]
            // What feeds the furnace's upgrade is not held back by it: the upgrade waits on its iron and stone.
            let feeds = [.ironMine, .quarry, .lumber, .coalMine, .hunter, .fishery].contains(k)
            let spare = feeds ? zip(l.spare, l.furnaceNeeds).map { $0 + $1 } : l.spare
            let c = k.cost
            return spare[1] - keep[1] >= c[1] && spare[3] >= c[3] && spare[4] >= c[4]
        }
        switch need {
        case .heat:
            guard !l.upgrading, l.level < IceCity.topLevel else { return nil }
            let wanted = IceBrain.levelWanted(l)
            guard l.level < wanted || l.cold > 0 && !IceBrain.roomInHeat(w) else { return nil }
            let c = IceCity.upgradeCost(to: l.level + 1)
            // The upgrade's materials go on the list; the builders carry them as they come in.
            return l.spare[1] >= c[1] * 0.6 && l.spare[3] >= c[3] * 0.6 && l.spare[4] >= c[4] * 0.6 ? .upgrade : nil
        case .housing:
            let short = l.homeless + max(0, l.people + 3 - l.warmRoom) - l.housesBuilding * IceCity.houseRoom
            guard short > 0, affordable(.house) else { return nil }
            // Houses go in the heat; with no room left there, the furnace comes first.
            return IceBrain.roomInHeat(w) || l.homeless > 0 ? .build(.house) : nil
        case .coal:
            let building = w.buildings.contains { $0.kind == .coalMine && !$0.done }
            guard l.has(.coalMine) == 0 || !building && l.full[0] < l.burn * 1.35 + (l.coal < IceBrain.coalWanted(l) ? 4 : 0) else { return nil }
            return affordable(.coalMine) ? .build(.coalMine) : nil
        case .food:
            let building = w.buildings.filter { [.hunter, .fishery, .greenhouse].contains($0.kind) && !$0.done }.count
            // One food place going up at a time — two while the stores are low.
            guard building < (l.food < l.eats * 10 ? 2 : 1), l.full[2] < IceBrain.foodTarget(l) * 1.2 else { return nil }
            if l.has(.hunter) == 0 { return affordable(.hunter) ? .build(.hunter) : nil }
            if l.has(.fishery) == 0, IceBrain.hasIce(w) { return affordable(.fishery) ? .build(.fishery) : nil }
            if l.level >= 2, l.has(.greenhouse) < 1 + l.people / 30, affordable(.greenhouse) { return .build(.greenhouse) }
            if l.has(.hunter) < 1 + l.people / 25, affordable(.hunter) { return .build(.hunter) }
            if l.has(.fishery) < 1 + l.people / 30, IceBrain.hasIce(w), affordable(.fishery) { return .build(.fishery) }
            return l.level >= 2 && affordable(.greenhouse) ? .build(.greenhouse) : affordable(.hunter) ? .build(.hunter) : nil
        case .materials:
            let felled = w.buildings.filter { $0.kind == .lumber }.allSatisfy { IceBrain.trees(w, $0) < 10 }
            if l.has(.lumber) == 0 || felled || l.wood < 80 && l.has(.lumber) < 1 + l.people / 30 { return affordable(.lumber) ? .build(.lumber) : nil }
            let quarried = w.buildings.filter { $0.kind == .quarry }.allSatisfy { $0.reserve < 60 }
            if l.has(.quarry) == 0 || quarried || l.stone < 30 && l.has(.quarry) < 1 + l.people / 50 { return affordable(.quarry) ? .build(.quarry) : nil }
            let building = w.buildings.contains { $0.kind == .storage && !$0.done }
            if !building, l.has(.storage) < 2 + l.people / 20, IceBrain.storageFull(w) || IceBrain.farFromStorage(w) != nil { return affordable(.storage) ? .build(.storage) : nil }
            return nil
        case .iron:
            let mined = w.buildings.filter { $0.kind == .ironMine }.allSatisfy { $0.reserve < 30 }
            if l.has(.ironMine) == 0 || mined { return affordable(.ironMine) ? .build(.ironMine) : nil }
            return nil
        case .health:
            if l.has(.clinic) == 0 || Double(l.sick) > l.heals * 2 + 4 && l.has(.clinic) < 1 + l.people / 40 { return affordable(.clinic) ? .build(.clinic) : nil }
            return nil
        case .defence:
            if !l.afterBlizzard, l.daysToBlizzard < 30, l.shelteredHouses < l.livedIn, !IceBrain.wallLine(w).isEmpty, w.wallAffordable >= 8, l.spare[3] >= 24, l.spare[1] >= 30 { return .wall }
            if let raid = l.raidDay, raid - l.day <= 10, l.has(.barracks) == 0 { return affordable(.barracks) ? .build(.barracks) : nil }
            if let raid = l.raidDay, raid - l.day <= 10, w.wallTiles < 24, w.wallAffordable >= 8, l.spare[3] >= 24, !IceBrain.wallLine(w).isEmpty { return .wall }
            return nil
        case .conquest:
            if l.has(.barracks) == 0 { return affordable(.barracks) ? .build(.barracks) : nil }
            if l.has(.tavern) == 0 { return affordable(.tavern) ? .build(.tavern) : nil }
            if l.day > 40, l.has(.barracks) < 2, l.soldiers + 10 >= w.soldierRoom { return affordable(.barracks) ? .build(.barracks) : nil }
            return nil
        }
    }

    // MARK: Who works where

    mutating func staff(_ w: inout IceCity, _ l: IceLedger) {
        let builders = l.sites > 0 ? min(max(2, l.able / 5), 1 + l.sites * 2) : 0
        var free = max(0, l.able - builders)
        var want: [Int: Int] = [:]
        let places = w.buildings.filter { $0.done && $0.kind.slots > 0 }
        func of(_ k: IceBuildKind) -> [IceBuilding] { places.filter { $0.kind == k } }
        /// Hands at buildings of these kinds for `amount` a day, the richest places first; returns the hands given.
        func cover(_ kinds: [IceBuildKind], _ amount: Double, limit: Int = 999) -> Int {
            var left = amount, given = 0
            for b in kinds.flatMap({ of($0) }).sorted(by: { IceBrain.yield(w, $0, workers: 1) > IceBrain.yield(w, $1, workers: 1) }) {
                guard left > 0.05, free > 0, given < limit else { break }
                let per = max(0.2, IceBrain.yield(w, b, workers: 1))
                let room = b.kind.slots - want[b.id, default: 0]
                let n = min(room, free, limit - given, Int(ceil(left / per)))
                guard n > 0 else { continue }
                want[b.id, default: 0] += n; free -= n; given += n
                left -= IceBrain.yield(w, b, workers: Double(want[b.id]!)) - IceBrain.yield(w, b, workers: Double(want[b.id]! - n))
            }
            return given
        }
        /// Workers it would take to make `amount` a day at these kinds of place.
        func hands(_ kinds: [IceBuildKind], _ amount: Double) -> Int {
            let places = kinds.flatMap { of($0) }
            guard !places.isEmpty, amount > 0 else { return 0 }
            let per = places.map { IceBrain.yield(w, $0, workers: 1) }.reduce(0, +) / Double(places.count)
            return Int(ceil(amount / max(0.2, per)))
        }
        let foodKinds: [IceBuildKind] = [.greenhouse, .fishery, .hunter]
        // Wood is what everything is built of: a few hands stay on it unless people are about to freeze or starve.
        let dying = l.coal < l.burn * 3 || l.food < l.eats * 3
        if !dying, l.spare[1] < 80 { _ = cover([.lumber], 99, limit: l.spare[1] < 25 ? 3 : 2) }
        if !dying, l.spare[3] < 20, l.siteNeeds[3] + (l.upgrading ? 20 : 0) > l.stone { _ = cover([.quarry], 99, limit: 2) }
        // What survival needs a day: the furnace's coal with a margin, and the food eaten, less what the counties send.
        let coalNeed = max(0, l.burn * 1.12 + (l.coal < IceBrain.coalWanted(l) ? max(3, l.burn * 0.5) : 0) - l.tribute[0])
        let foodNeed = max(0, IceBrain.foodTarget(l) - l.tribute[2])
        // When there are not hands enough for both, they are shared by what each needs — a commander's focus served first.
        let coalHands = hands([.coalMine], coalNeed), foodHands = hands(foodKinds, foodNeed)
        if coalHands + foodHands > free {
            let share = Double(free) / Double(max(1, coalHands + foodHands))
            var coalLimit = max(of(.coalMine).isEmpty ? 0 : 1, Int((Double(coalHands) * share).rounded()))
            var foodLimit = max(0, free - coalLimit)
            if focus == .coal { coalLimit = min(coalHands, free); foodLimit = free - coalLimit }
            if focus == .food { foodLimit = min(foodHands, free); coalLimit = free - foodLimit }
            _ = cover([.coalMine], coalNeed, limit: coalLimit)
            _ = cover(foodKinds, foodNeed, limit: foodLimit)
        } else {
            _ = cover([.coalMine], coalNeed)
            _ = cover(foodKinds, foodNeed)
        }
        // The sick need a doctor.
        for b in of(.clinic) where free > 0 { let n = min(free, l.sick > 0 ? 2 : 1); want[b.id] = n; free -= n }
        // Materials: what the sites and the next upgrade need, and a store to build from.
        let nextUpgrade = l.level < IceCity.topLevel ? IceCity.upgradeCost(to: l.level + 1) : [0, 0, 0, 0, 0]
        let woodShort = max(0, l.siteNeeds[1] + nextUpgrade[1] * 0.5 + 120 - l.wood)
        let stoneShort = max(0, l.siteNeeds[3] + nextUpgrade[3] * 0.5 + 50 - l.stone)
        let ironShort = max(0, l.siteNeeds[4] + nextUpgrade[4] + 15 - l.iron)
        var order: [(IceBuildKind, Double)] = [(.lumber, woodShort / 6 + 3), (.quarry, stoneShort / 8 + (l.stone < 150 ? 1.5 : 0)), (.ironMine, ironShort / 8 + (l.iron < 120 ? 1 : 0))]
        if focus == .materials { order[0].1 += 6; order[1].1 += 4 }
        if focus == .iron { order[2].1 += 6 }
        order.sort { $0.1 > $1.1 }
        for (kind, amount) in order where amount > 0 { _ = cover([kind], amount) }
        // Hands left over: coal toward the blizzard's store, food toward a fortnight's, then wood.
        if free > 0, l.coal < IceBrain.coalWanted(l) * 1.6 { _ = cover([.coalMine], 99) }
        if free > 0, l.food < l.eats * 14 { _ = cover(foodKinds, 99) }
        if free > 0, l.wood < 500 { _ = cover([.lumber], 99) }
        for b in places { if let i = w.buildingIndex(b.id) { w.buildings[i].wanted = want[b.id, default: 0] } }
    }

    /// What a kind of building makes.
    static func good(of k: IceBuildKind) -> IceGood? {
        switch k {
        case .coalMine: return .coal
        case .lumber: return .wood
        case .hunter, .fishery, .greenhouse: return .food
        case .quarry: return .stone
        case .ironMine: return .iron
        default: return nil
        }
    }
    /// What a building makes in a day with so many working, as measured, at its pace now — and what its ground can give.
    static func yield(_ w: IceCity, _ b: IceBuilding, workers n: Double) -> Double {
        let pace = w.pace(b)
        switch b.kind {
        case .coalMine: return b.reserve > 0 ? n * perCoal * pace : 0
        case .lumber: return min(n * perWood * pace, trees(w, b) * 1.5)
        case .hunter: return min(n * perHunter * pace, game(w, b) * 0.1)
        case .fishery: return min(n * perFisher * pace, fishing(w, b) * 0.9)
        case .greenhouse: return n * perGreenhouse * pace
        case .quarry: return b.reserve > 0 ? n * perStone * pace : 0
        case .ironMine: return b.reserve > 0 ? n * perIron * pace : 0
        default: return 0
        }
    }

    // MARK: Soldiers and generals

    mutating func war(_ w: inout IceCity, _ l: IceLedger) {
        // Generals at home and idle govern where they do most good.
        for g in w.officers where !g.away && g.governs == nil {
            if let post = IceBrain.post(for: g.officer, w) { w.govern(g.officer, post) }
        }
        // Soldiers: trained while the food and iron can spare them.
        let upgradeDue = l.level < IceBrain.levelWanted(l) || l.upgrading
        let ironKeep = upgradeDue && l.level < IceCity.topLevel ? IceCity.upgradeCost(to: l.level + 1)[4] : 0
        let threatened = l.raidDay.map { $0 - l.day <= 12 && l.defence < l.raiders * 1.2 } ?? false
        if w.canTrain, l.food > l.eats * (threatened ? 4 : 6) + 20, l.full[2] > l.eats * 0.95, l.iron >= ironKeep * (threatened ? 0.3 : 0.8) + 5 { w.train() }
        // A general from the tavern when the stores can spare one.
        if l.has(.tavern) > 0, w.officers.count < w.heroRoom {
            let pick = w.offered.filter { w.canRecruit($0) && l.food - Double(iceOfficers[$0].food) > l.eats * 8 && l.iron - Double(iceOfficers[$0].iron) > ironKeep * 0.5 }
                .max { IceBrain.worth($0) < IceBrain.worth($1) }
            if let pick { w.recruit(pick) }
        }
        // Expeditions that win nine times in ten, leaving enough at home.
        let keep = l.raidDay.map { $0 - l.day <= 10 ? max(8, Int(l.raiders / 2.5)) : 5 } ?? 5
        guard !w.storm, w.soldiers - keep >= 8 else { return }
        var best: (region: Int, officer: Int, soldiers: Int, value: Double)?
        for r in w.targets {
            for h in w.freeOfficers {
                let n = min(w.army(h, to: r), w.soldiers - keep)
                guard n >= 5, let days = w.travel(h, to: r) else { continue }
                let p = w.battle(h, n, r, on: w.today + days).chance
                guard p >= 0.78 else { continue }
                let value = p * (60 + 6 * Double(iceRegions[r].people) + 5 * iceRegions[r].amount) - Double(n) * 0.5
                if best == nil || value > best!.value { best = (r, h, n, value) }
            }
        }
        if let b = best { w.send(b.officer, soldiers: b.soldiers, to: b.region) }
    }

    /// The building a general does most good governing, if any.
    static func post(for h: Int, _ w: IceCity) -> Int? {
        let o = iceOfficers[h]
        let free = w.buildings.filter { $0.done && w.governor($0.id) == nil }
        if o.talent == .fire, let f = free.first(where: { $0.kind == .furnace }) { return f.id }
        if o.talent == .healer, let c = free.first(where: { $0.kind == .clinic }) { return c.id }
        let worth: [IceBuildKind: Double] = [.coalMine: 1.2, .greenhouse: 1.1, .hunter: 1, .fishery: 1, .lumber: 0.8, .ironMine: 0.9, .quarry: 0.6]
        return free.filter { worth[$0.kind] != nil && w.workers($0.id) >= 2 }
            .max { Double(w.workers($0.id)) * worth[$0.kind]! < Double(w.workers($1.id)) * worth[$1.kind]! }?.id
            ?? free.first { $0.kind == .furnace }?.id
    }
    /// A general's worth to the script: in the field, and at home.
    static func worth(_ h: Int) -> Double {
        let o = iceOfficers[h]
        var v = Double(o.war + o.lead) / 2
        switch o.talent {
        case .fire, .healer, .charm: v += 30
        case .peerless: v += 5
        default: v += 12
        }
        return v
    }

    // MARK: Matters at the gate

    /// The script's answer to the people's matter.
    static func answer(_ e: IceIncident, _ w: IceCity) -> Int {
        let l = IceLedger(w)
        let answer: Int
        switch e.kind {
        case 0: answer = w.warmRoom - w.people.count >= e.amount / 2 && l.foodDays > 6 && l.food > l.eats * 5 ? 0 : 1
        case 1: answer = l.coal > l.burn * 6 ? 0 : 1
        case 2: answer = l.coal >= l.burn * Double(e.amount + 2) * 2 + 20 ? 0 : 1
        case 3:
            if l.food < l.eats * 6, l.wood >= 110 { answer = 0 }
            else if l.coal < l.burn * 6, l.iron >= 50 { answer = 1 }
            else if l.iron < 30, l.wood >= 150 { answer = 2 }
            else { answer = 3 }
        case 4: answer = l.food >= 30 + l.eats * 4 ? 0 : 1
        case 5: answer = l.food >= 25 + l.eats * 6 && l.wood >= 70 && l.morale < 90 ? 0 : 1
        case 6: answer = l.soldiers >= 16 ? 0 : 1
        case 7: answer = l.food >= 30 + l.eats * 6 ? 0 : 1
        case 8: answer = l.wood >= 70 ? 0 : 1
        case 9: answer = l.coalDays < 8 ? 0 : 1
        default: answer = l.food >= 15 + l.eats * 5 ? 0 : 1
        }
        return w.can(e, answer) ? answer : IceCity.choices(e.kind).count - 1
    }

    // MARK: Where

    /// A place for a building of this kind: the best by what the kind cares about, with room to walk around it.
    func site(for kind: IceBuildKind, _ w: IceCity, _ l: IceLedger) -> IceTile? {
        let hc = w.hub, n = kind.size, R = w.heatRadius
        let stores = w.buildings.filter { $0.kind == .storage }
        func storeDistance(_ x: Double, _ y: Double) -> Double { stores.map { w.distance($0, x, y) }.min() ?? 99 }
        var best: IceTile?, bestScore = Double.infinity
        let radius = [.coalMine, .ironMine, .quarry, .fishery, .lumber, .hunter].contains(kind) ? 34 : 18
        let far = kind == .storage ? IceBrain.farFromStorage(w) : nil
        let fx = far?.x ?? hc.x, fy = far?.y ?? hc.y
        for dy in -radius...radius {
            for dx in -radius...radius {
                let o = IceTile(x: Int(fx) + dx - n / 2, y: Int(fy) + dy - n / 2)
                guard w.fits(kind, at: o), clear(o, n, w) else { continue }
                // The ground beside the deposits is kept for the mines.
                if ![.coalMine, .ironMine, .quarry].contains(kind), w.near(.rock, o, n, 2) + w.near(.coal, o, n, 2) + w.near(.ore, o, n, 2) > 0 { continue }
                let cx = Double(o.x) + Double(n) / 2, cy = Double(o.y) + Double(n) / 2
                let toStore = storeDistance(cx, cy), toHub = hypot(cx - hc.x, cy - hc.y)
                let warm = toHub <= R
                // The warm ground is kept for houses and what must be warm.
                let crowding = warm && ![.house, .greenhouse, .clinic, .tavern, .storage].contains(kind) ? 12.0 : 0
                var score: Double
                switch kind {
                case .house:
                    score = toHub + (warm ? 0 : 60) + (touchesRoad(o, n, w) ? 0 : 1.5)
                case .storage:
                    score = hypot(cx - fx, cy - fy) + (stores.contains { w.distance($0, cx, cy) < 8 } ? 50 : 0) + (warm ? 3 : 0)
                case .lumber, .hunter:
                    guard !w.buildings.contains(where: { $0.kind == kind && w.distance($0, cx, cy) < 11 }) else { continue }
                    let probe = IceBuilding(id: 0, kind: kind, x: o.x, y: o.y)
                    let there = kind == .lumber ? IceBrain.trees(w, probe) : IceBrain.game(w, probe) / 2
                    guard there >= 18 else { continue }
                    score = -there * 0.12 + toStore * 0.5 + toHub * 0.15
                case .fishery:
                    let probe = IceBuilding(id: 0, kind: kind, x: o.x, y: o.y)
                    let water = IceBrain.fishing(w, probe)
                    guard water >= 12, !w.buildings.contains(where: { $0.kind == .fishery && w.distance($0, cx, cy) < 7 }) else { continue }
                    score = -water * 0.1 + toStore * 0.5 + toHub * 0.15
                case .coalMine:
                    score = -Double(w.near(.coal, o, n, 2)) * 0.6 + toStore * 0.4 + toHub * 0.2
                case .ironMine:
                    score = -Double(w.near(.ore, o, n, 2)) * 0.6 + toStore * 0.4 + toHub * 0.2
                case .quarry:
                    score = -Double(w.near(.rock, o, n, 2)) * 0.6 + toStore * 0.4 + toHub * 0.2
                case .greenhouse, .clinic, .tavern:
                    score = toHub * 0.6 + toStore * 0.3 + (warm ? 0 : 25)
                case .barracks:
                    // Toward the gate at the south, near but not on the warm ground.
                    score = abs(toHub - (R + 3)) + max(0, hc.y - cy) * 0.8
                default:
                    score = toStore + toHub * 0.3
                }
                score += crowding
                if score < bestScore { bestScore = score; best = o }
            }
        }
        return best
    }

    /// A ring of open ground around a building, so nobody is walled in.
    private func clear(_ o: IceTile, _ n: Int, _ w: IceCity) -> Bool {
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n {
            let t = IceTile(x: o.x + dx, y: o.y + dy)
            guard IceCity.inside(t) else { return false }
            let i = IceCity.index(t)
            if w.occupant[i] != nil || w.wall[i] >= 0 { return false }
        } }
        return true
    }

    private func touchesRoad(_ o: IceTile, _ n: Int, _ w: IceCity) -> Bool {
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n {
            let t = IceTile(x: o.x + dx, y: o.y + dy)
            if IceCity.inside(t), w.road[IceCity.index(t)] { return true }
        } }
        return false
    }

    /// A road from a new building's door to the nearest road already there — or to the furnace.
    func connect(_ o: IceTile, _ kind: IceBuildKind, _ w: inout IceCity) {
        guard let f = w.furnace, let id = w.occupant[IceCity.index(o)], let b = w.building(id) else { return }
        let hc = w.centre(f)
        guard let door = w.around(b).sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }).min(by: { hypot(Double($0.x) - hc.x, Double($0.y) - hc.y) < hypot(Double($1.x) - hc.x, Double($1.y) - hc.y) }) else { return }
        var goals = w.around(f)
        for y in max(0, door.y - 14)...min(IceCity.height - 1, door.y + 14) {
            for x in max(0, door.x - 14)...min(IceCity.width - 1, door.x + 14) where w.road[y * IceCity.width + x] { goals.insert(IceTile(x: x, y: y)) }
        }
        if goals.contains(door) { return }
        guard let route = w.path(from: door, to: goals), route.count < 30 else { return }
        for t in [door] + route { w.lay(road: t) }
    }

    /// The north wall: a line across the city's north, beyond the heat's widest reach, left to right — the tiles not yet up.
    static func wallLine(_ w: IceCity) -> [IceTile] {
        let h = w.hub
        let y = max(1, Int(h.y) - 14)
        var out: [IceTile] = []
        for x in (Int(h.x) - 13)...(Int(h.x) + 13) {
            // A tile blocked by a building is stepped round: one row further north.
            for yy in [y, y - 1, y + 1] {
                let t = IceTile(x: x, y: yy)
                guard IceCity.inside(t) else { continue }
                let i = IceCity.index(t)
                if w.wall[i] >= 0 { break }
                if w.canWall(t) { out.append(t); break }
            }
        }
        // From the middle outward, so the city's heart is sheltered first.
        return out.sorted { abs(Double($0.x) - h.x) < abs(Double($1.x) - h.x) }
    }

    /// Measured over whole days: food a day worth having hands for — more when the stores are low.
    static func foodTarget(_ l: IceLedger) -> Double {
        let days = l.eats > 0 ? l.food / l.eats : 99
        let margin = days < 4 ? 1.5 : days < 8 ? 1.3 : days < 14 ? 1.12 : 0.95
        return l.eats * margin + 2
    }

    /// Is there a spot for a house left inside the heat?
    static func roomInHeat(_ w: IceCity) -> Bool {
        let h = w.hub, R = w.heatRadius
        for dy in -Int(R)...Int(R) { for dx in -Int(R)...Int(R) {
            let o = IceTile(x: Int(h.x) + dx - 1, y: Int(h.y) + dy - 1)
            guard hypot(Double(o.x) + 1 - h.x, Double(o.y) + 1 - h.y) <= R, w.fits(.house, at: o) else { continue }
            var ok = true
            for yy in (o.y - 1)...(o.y + 2) { for xx in (o.x - 1)...(o.x + 2) {
                let t = IceTile(x: xx, y: yy)
                if !IceCity.inside(t) || w.occupant[IceCity.index(t)] != nil || w.wall[IceCity.index(t)] >= 0 { ok = false }
            } }
            if ok { return true }
        } }
        return false
    }

    // MARK: Measures of a place

    static func trees(_ w: IceCity, _ b: IceBuilding) -> Double { within(w, b, IceCity.reach) { i in w.ground[i] == .forest && w.wood[i] >= 1 ? 1 : 0 } }
    static func game(_ w: IceCity, _ b: IceBuilding) -> Double { within(w, b, IceCity.reach) { i in w.ground[i] == .forest ? w.game[i] : 0 } }
    static func fishing(_ w: IceCity, _ b: IceBuilding) -> Double { within(w, b, IceCity.fishReach) { i in w.ground[i] == .ice && w.occupant[i] == nil ? 1 : 0 } }
    static func within(_ w: IceCity, _ b: IceBuilding, _ r: Int, _ value: (Int) -> Double) -> Double {
        let c = w.centre(b)
        var total = 0.0
        for y in max(0, Int(c.y) - r)...min(IceCity.height - 1, Int(c.y) + r) {
            for x in max(0, Int(c.x) - r)...min(IceCity.width - 1, Int(c.x) + r) where hypot(Double(x) + 0.5 - c.x, Double(y) + 0.5 - c.y) <= Double(r) {
                total += value(y * IceCity.width + x)
            }
        }
        return total
    }
    static func hasIce(_ w: IceCity) -> Bool { w.ground.contains(.ice) }
    static func storageFull(_ w: IceCity) -> Bool {
        let stores = w.buildings.filter { $0.done && $0.kind == .storage }
        let cap = Double(stores.count) * IceCity.capacity, held = stores.reduce(0) { $0 + $1.stock.reduce(0, +) }
        return cap > 0 && held / cap > 0.7
    }
    /// The busiest workplace a long walk from any storage, if there is one.
    static func farFromStorage(_ w: IceCity) -> (x: Double, y: Double)? {
        let stores = w.buildings.filter { $0.kind == .storage }
        let far = w.buildings.filter { b in b.kind.slots > 0 && b.kind != .clinic && w.workers(b.id) >= 2 && (stores.map { w.distance($0, w.centre(b).x, w.centre(b).y) }.min() ?? 99) > 12 }
        guard let busiest = far.max(by: { w.workers($0.id) < w.workers($1.id) }) else { return nil }
        return w.centre(busiest)
    }
}
