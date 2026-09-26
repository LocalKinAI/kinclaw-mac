import Foundation

/// What a commander tells the hands to lean toward until told otherwise.
enum RTSPosture: String, CaseIterable { case boom, army, age, attack, defend }

/// The computer's side of 帝国时代: a player who knows a build order.
///
/// Every second of game time it looks at its town and does what a decent
/// player does next — idle villagers to the resource it is shortest of, a
/// house before the population fills, a camp by the trees and the gold, farms
/// when the bushes run out, barracks, the next age, soldiers that beat what it
/// sees, and an attack when the army is big enough. Its villagers and soldiers
/// then do the walking and the fighting by themselves, as everybody's do.
struct RTSBrain {
    let owner: Int
    var attackAt = 9
    var lastAttack = -200.0
    /// When somebody else — Jev or a chat model — decides which way to lean. The economy runs
    /// as the script runs it whatever the leaning; the posture decides soldiers, the next age
    /// and attacks.
    var commanded = false
    /// The commander's standing order; the script on its own plays all of them at once.
    var posture = RTSPosture.boom
    /// What the person, told by Jev, is saving for: bought the moment there is enough.
    var goal: RTSPlan?
    var clock = 0.0
    var rebalance = 0
    /// A resource the last rebalancing freed villagers for.
    var pending: Int?

    init(owner: Int) { self.owner = owner }

    static let shares: [[Double]] = [[0.55, 0.45, 0, 0], [0.45, 0.35, 0.15, 0.05], [0.42, 0.3, 0.23, 0.05]]
    static let villagerTarget = [20, 28, 34]

    mutating func think(_ w: inout RTSWorld, _ dt: Double) {
        clock += dt
        guard clock >= 1, w.winner == nil else { return }
        clock = 0
        let me = w.players[owner]
        guard let tc = w.buildings.first(where: { $0.owner == owner && $0.kind == .townCenter }) else { return }
        let home = RTSTile(x: tc.x + 1, y: tc.y + 1)
        let villagers = w.units.filter { $0.owner == owner && $0.kind == .villager }
        let soldiers = w.units.filter { $0.owner == owner && $0.kind != .villager }
        let target = Self.villagerTarget[me.age]

        // Under a commander the economy below runs as it does for the script; the posture decides
        // military buildings, soldiers, the next age and when to march.
        let p: RTSPosture? = commanded ? posture : nil
        let army = p == nil || p == .army || p == .defend
        let raiders = w.units.filter { $0.owner != owner && hypot($0.x - Double(home.x), $0.y - Double(home.y)) < 11 }
        if p == .attack {
            if let theirTC = w.buildings.first(where: { $0.owner != owner && $0.kind == .townCenter }) {
                for s in soldiers where !isFighting(s) { w.command(s.id, .attackMove(RTSTile(x: theirTC.x + 1, y: theirTC.y + 1))) }
            }
            posture = .army
        }
        if p == .defend { for s in soldiers where hypot(s.x - Double(home.x), s.y - Double(home.y)) > 9 && !isFighting(s) { w.command(s.id, .attackMove(forward(home))) } }
        // Villagers: keep them coming.
        if tc.queue.isEmpty, villagers.count < target, me.researching == 0, w.units.filter({ $0.owner == owner }).count < w.room(owner) {
            _ = w.train(.villager, at: tc.id)
        }
        // A house before the town is full.
        let room = w.room(owner), people = w.population(owner)
        let housing = w.buildings.contains { $0.owner == owner && $0.kind == .house && !$0.done }
        if room - people <= 3, room < RTSWorld.popCap, !housing, let spot = spot(.house, near: home, w, clearance: true) {
            order(.house, spot, &w)
        }
        // Camps by the resources, a mill by the bushes.
        let jobs = self.jobs(w)
        if !has(.lumberCamp, w), jobs[1] >= 2, let tree = w.nearest(.forest, from: home, within: 16), let spot = spot(.lumberCamp, near: tree, w, clearance: false) {
            order(.lumberCamp, spot, &w)
        }
        if !has(.mill, w), let bush = w.nearest(.berries, from: home, within: 10), let spot = spot(.mill, near: bush, w, clearance: false) {
            order(.mill, spot, &w)
        }
        if !has(.miningCamp, w), me.age >= 1 || jobs[2] >= 2, let rock = w.nearest(.gold, from: home, within: 16), let spot = spot(.miningCamp, near: rock, w, clearance: false) {
            order(.miningCamp, spot, &w)
        }
        // Farms when the bushes run low — and more when soldiers eat the food while the wood piles up.
        let berriesLeft = (0..<w.amount.count).filter { w.terrain[$0] == .berries }.reduce(0.0) { $0 + w.amount[$1] }
        let farms = w.buildings.filter { $0.owner == owner && $0.kind == .farm }
        let wantFood = Int(Double(villagers.count) * Self.shares[me.age][0])
        let hungry = me.stock[0] < 120 && me.stock[1] > 300 && !farms.contains { $0.done && $0.farmer == nil }
        if berriesLeft < 250, farms.count < (hungry ? 16 : min(12, wantFood)), farms.filter({ !$0.done }).count < 2,
           let spot = spot(.farm, near: farmCentre(w, home), w, clearance: false) {
            order(.farm, spot, &w)
        }
        // Military buildings, the next age.
        if army, !has(.barracks, w), villagers.count >= (p == nil ? 12 : 0), let spot = spot(.barracks, near: forward(home), w, clearance: true) { order(.barracks, spot, &w) }
        if army, me.age >= 1, !has(.range, w), let spot = spot(.range, near: forward(home), w, clearance: true) { order(.range, spot, &w) }
        if army, me.age >= 2, !has(.stable, w), let spot = spot(.stable, near: forward(home), w, clearance: true) { order(.stable, spot, &w) }
        if army, me.age >= 1, w.buildings.filter({ $0.owner == owner && $0.kind == .tower }).count < (p == .defend ? 3 : 1),
           let spot = spot(.tower, near: forward(forward(home)), w, clearance: true) { order(.tower, spot, &w) }
        if p == nil ? villagers.count >= target - 4 : p == .age, me.researching == 0, me.age < 2, w.advance(owner), p == .age { posture = .boom }
        // Soldiers: once the economy is going, a steady trickle of what beats theirs — never
        // eating the food the town centre needs for villagers, never more soldiers than villagers.
        // The script saving for the next age keeps what that needs, unless the enemy is at the door.
        let threatened = raiders.contains { $0.kind != .villager }
        let saving = p == nil && !threatened && me.age < 2 && me.researching == 0 && villagers.count >= target - 4 ? RTSWorld.ageCost[me.age] : [0, 0, 0, 0]
        let reserve = max(villagers.count < target ? (p == nil ? 110.0 : 60) : 0, saving[0])
        let wanted = p == nil ? villagers.count >= 15 && soldiers.count < villagers.count : army || threatened
        if wanted, me.stock[0] >= reserve + 35 || me.age >= 1 && me.stock[2] >= saving[2] + 45 {
            let theirs = w.units.filter { $0.owner != owner && $0.kind != .villager }
            // What beats the most of theirs: archers beat spearmen, knights archers, spearmen knights —
            // and against nobody, what knocks buildings down.
            let counts = RTSUnitKind.allCases.map { k in theirs.filter { $0.kind == k }.count }
            let most = [RTSUnitKind.spearman, .archer, .knight].max { counts[$0.rawValue] < counts[$1.rawValue] }!
            let wants: [RTSUnitKind] = theirs.isEmpty ? [.knight, .spearman, .archer]
                : most == .spearman ? [.archer, .spearman, .knight] : most == .archer ? [.knight, .archer, .spearman] : [.spearman, .archer, .knight]
            for kind in wants + RTSUnitKind.allCases.filter({ $0 != .villager }) {
                guard let yard = w.buildings.first(where: { $0.owner == owner && $0.kind == RTSWorld.trainer(kind) && $0.done && $0.queue.count < 2 }) else { continue }
                if w.train(kind, at: yard.id) { break }
            }
        }
        // Defend: anybody hostile near home brings every soldier.
        if let raider = raiders.first {
            for s in soldiers where !isFighting(s) { w.command(s.id, .attackMove(RTSTile(x: Int(raider.x), y: Int(raider.y)))) }
        } else if p == nil, soldiers.count >= attackAt || soldiers.count >= 5 && !w.units.contains(where: { $0.owner != owner && $0.kind != .villager }),
                  w.time - lastAttack > 45, let theirTC = w.buildings.first(where: { $0.owner != owner && $0.kind == .townCenter }) {
            // Attack: everybody at once, toward their town centre — bigger each time, up to what the population allows.
            lastAttack = w.time; attackAt = min(attackAt + 4, 21)
            for s in soldiers { w.command(s.id, .attackMove(RTSTile(x: theirTC.x + 1, y: theirTC.y + 1))) }
        }
        // Every so often, move a couple of villagers from what piles up to what runs short.
        rebalance += 1
        if rebalance >= 12 {
            rebalance = 0
            let stock = w.players[owner].stock, want = Self.shares[me.age]
            if let rich = (0..<3).max(by: { stock[$0] < stock[$1] }), let poor = (0..<3).filter({ want[$0] > 0 }).min(by: { stock[$0] < stock[$1] }),
               stock[rich] > 400, stock[poor] < 120, rich != poor {
                let movers = w.units.filter { u in
                    guard u.owner == owner, u.kind == .villager else { return false }
                    switch u.task {
                    case .gather(let t): return RTSWorld.resource(of: w.terrain[RTSWorld.index(t)])?.rawValue == rich
                    case .farm: return rich == 0
                    default: return false
                    }
                }.prefix(2)
                for v in movers { w.command(v.id, .idle) }
                pending = poor
            }
        }
        // Idle villagers: build what is unbuilt, else gather what is short.
        for v in w.units where v.owner == owner && v.kind == .villager && v.task == .idle {
            if let site = w.buildings.filter({ $0.owner == owner && !$0.done }).min(by: { w.distance(to: $0, v.x, v.y) < w.distance(to: $1, v.x, v.y) }),
               w.units.filter({ $0.owner == owner && $0.task == .build(site.id) }).count < 3 {
                w.command(v.id, .build(site.id)); continue
            }
            assign(v, &w, home)
        }
    }

    /// What the person, on Jev's advice, is saving for: bought the moment there is enough.
    mutating func fulfil(_ w: inout RTSWorld) {
        guard case .save(let kind, let spot)? = goal else { return }
        let me = w.players[owner]
        if let kind, let spot {
            guard w.afford(RTSWorld.cost(kind), owner) else { return }
            if let place = w.fits(kind, at: spot) ? spot : self.spot(kind, near: spot, w, clearance: kind != .farm) { order(kind, place, &w) }
            goal = nil
        } else if me.researching > 0 || me.age >= 2 || w.advance(owner) {
            goal = nil
        }
    }

    /// Where the town's people are working now: food, wood, gold, stone.
    func jobs(_ w: RTSWorld) -> [Int] {
        var out = [0, 0, 0, 0]
        for u in w.units where u.owner == owner && u.kind == .villager {
            switch u.task {
            case .gather(let t): if let r = RTSWorld.resource(of: w.terrain[RTSWorld.index(t)]) { out[r.rawValue] += 1 }
            case .farm: out[0] += 1
            default: break
            }
        }
        return out
    }

    /// Send a villager to the resource the town is shortest of.
    mutating func assign(_ v: RTSUnit, _ w: inout RTSWorld, _ home: RTSTile) {
        let jobs = self.jobs(w), total = max(1, jobs.reduce(0, +)), want = Self.shares[w.players[owner].age]
        var order = (0..<4).sorted { want[$0] - Double(jobs[$0]) / Double(total) > want[$1] - Double(jobs[$1]) / Double(total) }
        if let first = pending { order = [first] + order.filter { $0 != first }; pending = nil }
        let here = RTSTile(x: Int(v.x), y: Int(v.y))
        for r in order where want[r] > 0 {
            if r == 0 {
                if let field = w.buildings.first(where: { $0.owner == owner && $0.kind == .farm && $0.done && $0.farmer == nil }) { w.command(v.id, .farm(field.id)); return }
                if let bush = w.nearest(.berries, from: home, within: 12) { w.command(v.id, .gather(bush)); return }
                continue
            }
            let terrain: RTSTerrain = [.berries, .forest, .gold, .stone][r]
            let from = w.buildings.first { $0.owner == owner && RTSWorld.takes($0.kind, RTSResource(rawValue: r)!) && $0.kind != .townCenter }.map(Self.middle) ?? here
            if let tile = w.nearest(terrain, from: from, within: 16) ?? w.nearest(terrain, from: home, within: 22) { w.command(v.id, .gather(tile)); return }
        }
    }

    private func has(_ kind: RTSBuildingKind, _ w: RTSWorld) -> Bool { w.buildings.contains { $0.owner == owner && $0.kind == kind } }
    private func isFighting(_ u: RTSUnit) -> Bool { if case .attack = u.task { return true }; return false }

    /// A little toward the middle of the map from here.
    private func forward(_ t: RTSTile) -> RTSTile { RTSTile(x: t.x + (owner == 0 ? 4 : -4), y: t.y) }

    private func farmCentre(_ w: RTSWorld, _ home: RTSTile) -> RTSTile {
        if let mill = w.buildings.first(where: { $0.owner == owner && $0.kind == .mill }) { return Self.middle(mill) }
        return home
    }

    /// The tile in the middle of a building — of the middle two, the one nearer the middle of the map,
    /// so that mirrored buildings give mirrored tiles.
    static func middle(_ b: RTSBuilding) -> RTSTile {
        let n = RTSWorld.size(b.kind)
        let x = n % 2 == 1 || Double(b.x) + Double(n) / 2 < Double(RTSWorld.width) / 2 ? b.x + n / 2 : b.x + n / 2 - 1
        return RTSTile(x: x, y: b.y + n / 2)
    }

    mutating func order(_ kind: RTSBuildingKind, _ spot: RTSTile, _ w: inout RTSWorld) {
        guard w.afford(RTSWorld.cost(kind), owner) else { return }
        // Up to two builders: whoever is idle, else whoever is nearest and not carrying much.
        let candidates = w.units.filter { $0.owner == owner && $0.kind == .villager }
            .sorted { hypot($0.x - Double(spot.x), $0.y - Double(spot.y)) < hypot($1.x - Double(spot.x), $1.y - Double(spot.y)) }
        let builders = Array((candidates.filter { $0.task == .idle } + candidates).prefix(kind == .house || kind == .farm ? 1 : 2).map(\.id))
        w.order(kind, at: spot, owner: owner, builders: Array(Set(builders)))
    }

    /// A place for a building near a tile: the one whose middle is nearest, with a lane left around it when asked.
    /// Ties go to the middle of the map, so both sides place alike.
    func spot(_ kind: RTSBuildingKind, near t: RTSTile, _ w: RTSWorld, clearance: Bool) -> RTSTile? {
        let n = RTSWorld.size(kind), half = Double(n) / 2, middle = Double(RTSWorld.width) / 2
        var best: RTSTile?, bestKey = (Double.infinity, Double.infinity, Double.infinity)
        for dy in -15...15 { for dx in -15...15 {
            let origin = RTSTile(x: t.x + dx - n / 2, y: t.y + dy - n / 2)
            let cx = Double(origin.x) + half, cy = Double(origin.y) + half
            let key = ((hypot(cx - Double(t.x) - 0.5, cy - Double(t.y) - 0.5) * 100).rounded(), (abs(cx - middle) * 100).rounded(), cy)
            guard key < bestKey, w.fits(kind, at: origin) else { continue }
            if clearance {
                var clear = true
                for ey in -1...n { for ex in -1...n where ex == -1 || ey == -1 || ex == n || ey == n {
                    let edge = RTSTile(x: origin.x + ex, y: origin.y + ey)
                    if RTSWorld.inside(edge), w.occupant[RTSWorld.index(edge)] != nil { clear = false }
                } }
                if !clear { continue }
            }
            best = origin; bestKey = key
        } }
        return best
    }
}
