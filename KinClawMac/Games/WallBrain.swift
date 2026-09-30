import Foundation

/// One thing that can be done with the gold: build, raise, call the next wave, or keep the gold.
struct WallMove {
    enum Act: Equatable {
        case build(WallKind, WallTile)
        case upgrade(Int)
        case call
        case save
    }
    var act: Act
    var cost = 0
    /// Damage it adds against one enemy walking the whole way (the yardstick: damage a second × tiles of the way in reach).
    var gain = 0.0
    /// Gain per gold.
    var value: Double { cost > 0 ? gain / Double(cost) : 0 }
    /// The walk to the pass before and after, in tiles (averaged over the gaps).
    var before = 0.0, after = 0.0
    /// Tiles of the way it has in reach.
    var cover = 0.0
    /// Towers a beacon would lift.
    var lifts = 0
    var newRoutes: [[WallTile]]?
    /// Part of a maze line: the walk once the line is whole.
    var line: Double?
}

/// What the program measures of the frontier, for the script's hands and for the words Jev and a chat model read.
///
/// The yardstick is damage a second times the tiles of the way a tower has in reach (plus, for any tower with the
/// way in reach at all, the wave's spread: a wave takes a while to pass). With a maze planned, reach is counted on
/// the way as it is now and on the way the finished maze will make, more on the second the more of it stands.
struct WallJudge {
    let field: WallField
    /// Maze lines to be built, and what each adds once whole (none when there is no plan).
    let plan: [WallLine]
    /// The ways once the whole plan stands, and how much of it stands.
    let planned: [[WallTile]]
    let built: Double
    /// Tiles of the planned ways: kept clear of towers, they are the maze's corridors.
    let corridor: Set<WallTile>
    /// The next wave and the wave on the field, as shares of the enemies to come, for matching damage to armour.
    let mixture: [Double]
    /// A wave comes out over a while: a tower with the way in reach is busy that long besides the time one enemy spends
    /// crossing its reach — in tiles, the wave's spawning time at its walking pace.
    let spread: Double
    let potential: Double

    init(_ f: WallField, plan lines: [[WallTile]] = []) {
        field = f
        var m = Array(repeating: 0.0, count: WallFoe.allCases.count)
        let w = f.coming
        for s in w.spawns { m[s.foe.rawValue] += s.foe == .chanyu ? 8 : s.foe == .siege ? 3 : 1 }
        for e in f.enemies { m[e.foe.rawValue] += 0.5 }
        let total = max(1, m.reduce(0, +))
        let shares = m.map { $0 / total }
        mixture = shares
        let span = w.spawns.dropLast().reduce(0) { $0 + $1.gap }
        let pace = w.spawns.reduce(0) { $0 + $1.foe.speed } / Double(max(1, w.spawns.count))
        let spread = max(6, min(24, span * pace * 0.6))
        self.spread = spread
        // The plan: as many of its lines as can stand together with what is built.
        var keep = lines
        var planned: [[WallTile]]? = nil
        while !keep.isEmpty {
            planned = f.routes(blocking: keep.flatMap { $0 }.filter { f.buildable($0) })
            if planned != nil { break }
            keep.removeLast()
        }
        let all = keep.flatMap { $0 }
        let standing = all.filter { !f.buildable($0) }.count
        // The script commits to its maze from the start: reach is counted half on the finished maze's ways already.
        let built = all.isEmpty ? 0 : 0.5 + 0.5 * Double(standing) / Double(all.count)
        self.built = built
        self.planned = planned ?? f.routes
        var corridor = Set<WallTile>()
        if !keep.isEmpty { for r in self.planned { for t in r { corridor.insert(t) } } }
        self.corridor = corridor
        let pot = Self.potential(f, f.routes, self.planned, built, shares, spread)
        potential = pot
        var made: [WallLine] = []
        let whole = Self.potential(f, self.planned, self.planned, 1, shares, spread)
        let missingAll = all.filter { f.buildable($0) }.count
        for line in keep {
            let missing = line.filter { f.buildable($0) }
            guard !missing.isEmpty else { continue }
            // The whole plan's gain, shared by the pieces still missing.
            let gain = max(0, whole - pot) * Double(missing.count) / Double(max(1, missingAll))
            let after = self.planned.map { WallField.length($0) }.reduce(0, +) / Double(max(1, self.planned.count))
            made.append(WallLine(tiles: line, missing: missing, after: after, gain: gain))
        }
        plan = made
    }

    /// How much of a kind of damage gets through, over the enemies to come.
    static func match(_ d: WallDamage, _ mixture: [Double]) -> Double {
        var s = 0.0
        for f in WallFoe.allCases { s += mixture[f.rawValue] * f.takes(d) }
        return s
    }

    /// A tower's damage a second as the yardstick counts it: shots, splash, pierce and fire each weighed for a crowd.
    static func dps(_ kind: WallKind, level: Int, boost: Double, _ mixture: [Double]) -> Double {
        let s = kind.stats(level)
        let dmg = s.damage * (1 + boost)
        let raw: Double
        switch kind {
        case .arrow: raw = dmg * s.rate
        case .ballista: raw = dmg * s.rate * (1 + 0.1 * Double(s.pierce))
        case .trebuchet: raw = dmg * s.rate * 2 * s.splash * s.splash
        case .fire: raw = dmg * s.rate * s.burn * 1.1 * s.splash * s.splash
        case .barricade: raw = dmg * 0.6
        case .beacon: raw = 0
        }
        return raw * match(kind.damageKind, mixture)
    }

    static func reach(_ f: WallField, _ t: WallTower) -> (range: Double, min: Double) {
        t.kind == .barricade ? (1.3, 0) : (f.range(of: t), t.stats.minRange)
    }

    /// Tiles of the way in reach, plus the wave's spread when there are any.
    static func busy(_ cover: Double, _ spread: Double) -> Double { cover + (cover >= 0.5 ? spread * min(1, cover / 3) : 0) }

    /// Reach counted on the way now and the planned way, weighed by how much of the plan stands.
    static func cover(_ now: [[WallTile]], _ planned: [[WallTile]], _ built: Double, x: Double, y: Double, range: Double, minRange: Double) -> Double {
        let a = WallField.cover(now, x: x, y: y, range: range, minRange: minRange)
        guard built > 0 else { return a }
        return a * (1 - built) + WallField.cover(planned, x: x, y: y, range: range, minRange: minRange) * built
    }
    func cover(_ now: [[WallTile]], x: Double, y: Double, range: Double, minRange: Double = 0) -> Double {
        Self.cover(now, planned, built, x: x, y: y, range: range, minRange: minRange)
    }

    /// Everything's yardstick added up.
    static func potential(_ f: WallField, _ now: [[WallTile]], _ planned: [[WallTile]], _ built: Double, _ mixture: [Double], _ spread: Double) -> Double {
        var p = 0.0
        for t in f.towers where t.kind != .beacon {
            let r = reach(f, t)
            let c = cover(now, planned, built, x: t.centre.x, y: t.centre.y, range: r.range, minRange: r.min)
            p += dps(t.kind, level: t.level, boost: f.boosts[t.id]?.damage ?? 0, mixture) * (t.kind == .barricade ? c : busy(c, spread))
        }
        return p
    }

    /// Tiles worth considering: open grass within six tiles of a way, off the maze's corridors.
    func candidates() -> [WallTile] {
        var near = Array(repeating: false, count: WallField.width * WallField.height)
        for r in field.routes + planned { for t in r {
            for dy in -6...6 { for dx in -6...6 where dx * dx + dy * dy <= 36 {
                let n = WallTile(x: t.x + dx, y: t.y + dy)
                if WallField.inside(n) { near[WallField.index(n)] = true }
            } }
        } }
        var out: [WallTile] = []
        for y in 1..<WallField.wallRow { for x in 0..<WallField.width {
            let t = WallTile(x: x, y: y)
            if near[WallField.index(t)], field.buildable(t), !corridor.contains(t) { out.append(t) }
        } }
        return out
    }

    /// Every build worth weighing, by kind, and every upgrade.
    func moves(kinds: [WallKind] = WallKind.allCases) -> [WallMove] {
        var out: [WallMove] = []
        let f = field
        let before = f.pathLength
        var onWay = Set<WallTile>()
        for r in f.routes { for t in r { onWay.insert(t) } }
        for e in f.enemies { for t in e.route[min(e.next, e.route.count)...] { onWay.insert(t) } }
        for t in candidates() {
            let c = WallField.centre(t)
            var routes = f.routes, after = before, base = potential
            if onWay.contains(t) {
                guard !f.shuts(t), let r = f.routes(blocking: t) else { continue }
                routes = r
                after = r.map { WallField.length($0) }.reduce(0, +) / Double(r.count)
                base = Self.potential(f, r, planned, built, mixture, spread)
            }
            // Enemies standing on it: it can't go there now.
            if f.enemies.contains(where: { abs($0.x - c.x) < 0.75 && abs($0.y - c.y) < 0.75 }) { continue }
            let line = plan.first { $0.missing.contains(t) }
            for kind in kinds {
                var m = WallMove(act: .build(kind, t), cost: kind.cost, before: before, after: after)
                m.newRoutes = routes == f.routes ? nil : routes
                let s = kind.stats(0)
                switch kind {
                case .beacon:
                    var lift = 0.0
                    for o in f.towers where o.kind.shoots && hypot(Double(o.x - t.x), Double(o.y - t.y)) <= s.range + 0.01 {
                        let had = f.boosts[o.id]?.damage ?? 0
                        guard s.boost > had else { continue }
                        let r = Self.reach(f, o)
                        let cov1 = cover(routes, x: o.centre.x, y: o.centre.y, range: o.stats.range * (1 + s.reach), minRange: r.min)
                        let cov0 = cover(routes, x: o.centre.x, y: o.centre.y, range: r.range, minRange: r.min)
                        lift += Self.dps(o.kind, level: o.level, boost: s.boost, mixture) * Self.busy(cov1, spread) - Self.dps(o.kind, level: o.level, boost: had, mixture) * Self.busy(cov0, spread)
                        m.lifts += 1
                    }
                    m.gain = base - potential + lift
                default:
                    let range = kind == .barricade ? 1.3 : s.range
                    let cov = cover(routes, x: c.x, y: c.y, range: range, minRange: s.minRange)
                    let boost = f.towers.filter { $0.kind == .beacon && hypot(Double($0.x - t.x), Double($0.y - t.y)) <= $0.stats.range + 0.01 }.map { $0.stats.boost }.max() ?? 0
                    m.cover = WallField.cover(routes, x: c.x, y: c.y, range: range, minRange: s.minRange)
                    let own = Self.dps(kind, level: 0, boost: boost, mixture) * (kind == .barricade ? cov : Self.busy(cov, spread))
                    // A barricade's lengthening lasts only as long as it stands.
                    m.gain = own + (base - potential) * (kind == .barricade ? 0.55 : 1)
                }
                if let line, kind != .beacon {
                    // Worth more the nearer the maze is to whole.
                    m.gain += line.gain / Double(line.missing.count) * (1 + 2 * (built - 0.5) * 2)
                    m.line = line.after
                }
                out.append(m)
            }
        }
        for t in f.towers {
            guard let c = f.upgradeCost(t) else { continue }
            var m = WallMove(act: .upgrade(t.id), cost: c, before: before, after: before)
            let r = Self.reach(f, t)
            if t.kind == .beacon {
                let s1 = t.kind.stats(t.level + 1)
                var lift = 0.0
                for o in f.towers where o.kind.shoots && hypot(Double(o.x - t.x), Double(o.y - t.y)) <= s1.range + 0.01 {
                    let had = f.boosts[o.id]?.damage ?? 0
                    guard s1.boost > had else { continue }
                    let ro = Self.reach(f, o)
                    let cov1 = cover(f.routes, x: o.centre.x, y: o.centre.y, range: o.stats.range * (1 + s1.reach), minRange: ro.min)
                    let cov0 = cover(f.routes, x: o.centre.x, y: o.centre.y, range: ro.range, minRange: ro.min)
                    lift += Self.dps(o.kind, level: o.level, boost: s1.boost, mixture) * Self.busy(cov1, spread) - Self.dps(o.kind, level: o.level, boost: had, mixture) * Self.busy(cov0, spread)
                    m.lifts += 1
                }
                m.gain = lift
            } else if t.kind == .barricade {
                // A stronger barricade stands longer against the hacking.
                let cov = cover(f.routes, x: t.centre.x, y: t.centre.y, range: 1.3, minRange: 0)
                m.cover = cov
                // Worth it only while it is being hacked at or is worn down.
                let pressed = t.hp < t.stats.hp * 0.7 || f.time - t.hurt < 8
                m.gain = pressed ? (Self.dps(t.kind, level: t.level + 1, boost: 0, mixture) - Self.dps(t.kind, level: t.level, boost: 0, mixture)) * cov + 6 : 0
            } else {
                let boost = f.boosts[t.id]?.damage ?? 0
                let range1 = t.kind.stats(t.level + 1).range * (1 + (f.boosts[t.id]?.range ?? 0))
                let cov0 = cover(f.routes, x: t.centre.x, y: t.centre.y, range: r.range, minRange: r.min)
                let cov1 = cover(f.routes, x: t.centre.x, y: t.centre.y, range: range1, minRange: r.min)
                m.cover = WallField.cover(f.routes, x: t.centre.x, y: t.centre.y, range: range1, minRange: r.min)
                m.gain = Self.dps(t.kind, level: t.level + 1, boost: boost, mixture) * Self.busy(cov1, spread) - Self.dps(t.kind, level: t.level, boost: boost, mixture) * Self.busy(cov0, spread)
            }
            out.append(m)
        }
        return out
    }

    /// Switchback lines across the field below the river, a gap at alternate ends, the first two rows above the Wall:
    /// the maze the script builds, a piece at a time.
    static func maze(_ f: WallField) -> [[WallTile]] {
        var out: [[WallTile]] = []
        var row = WallField.wallRow - 2, gapEast = false
        let bottom = f.riverBottom
        while row >= bottom + 2, out.count < 3 {
            var line: [WallTile] = []
            for x in 0..<WallField.width {
                if gapEast ? x >= WallField.width - 2 : x < 2 { continue }
                let t = WallTile(x: x, y: row)
                if f.ground(t) == .grass { line.append(t) }
            }
            out.append(line)
            row -= 3; gapEast.toggle()
        }
        return out
    }
}

/// A line of the maze plan: its tiles, those not yet built, the walk once it is whole, and what that adds.
struct WallLine {
    var tiles: [WallTile]
    var missing: [WallTile]
    var after: Double
    var gain: Double
}

/// The computer's hands: a script that builds a maze and guns along it, spending where the yardstick gains most a
/// gold — or, as dice, random towers in random places.
struct WallBrain {
    enum Style { case script, dice }
    var style: Style = .script
    var next = 0.0
    var rng = WallRNG(17)
    /// How often it looks, in seconds of play.
    var every = 0.7
    /// The kinds it may build (all, unless a test narrows them).
    var kinds = WallKind.allCases
    /// The maze it means to build (worked out from the land on first look).
    var maze: [[WallTile]]?

    init(_ style: Style = .script, seed: UInt64 = 17) { self.style = style; rng = WallRNG(seed) }

    mutating func think(_ f: inout WallField) {
        guard f.time >= next, !f.over else { return }
        next = f.time + (style == .dice ? 1.2 : every)
        switch style {
        case .script:
            if maze == nil { maze = WallJudge.maze(f) }
            for _ in 0..<3 { guard let m = Self.best(f, kinds: kinds, maze: maze ?? []), m.act != .save else { break }; Self.carry(m, &f) }
        case .dice: roll(&f)
        }
    }

    /// The script's pick: the most gain a gold among what can be paid for now — unless something twice as good
    /// is only a little gold away, when it saves.
    static func best(_ f: WallField, kinds: [WallKind] = WallKind.allCases, maze: [[WallTile]] = []) -> WallMove? {
        let judge = WallJudge(f, plan: maze)
        let all = judge.moves(kinds: kinds).filter { $0.gain > 0.5 }
        guard !all.isEmpty else { return WallMove(act: .save) }
        let affordable = all.filter { $0.cost <= f.gold }
        guard let pick = affordable.max(by: { $0.value < $1.value }) else { return WallMove(act: .save) }
        // Something better that is not yet affordable is worth less the longer it takes to afford.
        let income = max(0.8, Double(f.earned) / max(40, f.time))
        let top = all.map { m in m.value * exp(-Double(max(0, m.cost - f.gold)) / income / 25) }.max() ?? 0
        if pick.value < top * 0.6 { return WallMove(act: .save) }
        return pick
    }

    @discardableResult
    static func carry(_ m: WallMove, _ f: inout WallField) -> Bool {
        switch m.act {
        case .build(let kind, let t): return f.build(kind, at: t) != nil
        case .upgrade(let id): return f.upgrade(id)
        case .call: guard f.spawned else { return false }; f.call(); return true
        case .save: return true
        }
    }

    private mutating func roll(_ f: inout WallField) {
        if !f.towers.isEmpty, rng.unit() < 0.3 {
            let t = f.towers[rng.int(f.towers.count)]
            f.upgrade(t.id)
            return
        }
        let kinds = WallKind.allCases.filter { $0.cost <= f.gold }
        guard !kinds.isEmpty else { return }
        let kind = kinds[rng.int(kinds.count)]
        for _ in 0..<30 {
            let t = WallTile(x: rng.int(WallField.width), y: 1 + rng.int(WallField.wallRow - 1))
            if f.refusal(kind, at: t) == nil { f.build(kind, at: t); return }
        }
    }
}
