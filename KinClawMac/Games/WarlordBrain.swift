import Foundation

/// An attack the numbers say is worth making: from where, at what, with whom and how many, and how it likely goes.
struct WarlordStrike {
    let from: Int, to: Int
    let team: [Int]
    let troops: Int
    let chance: Double
    let value: Double
}

/// The computer as lord (电脑): a sensible script. It lets its captives go or wins
/// them over, asks the free generals it knows of, makes war on weak neighbours
/// when the odds are good, looks for allies against a strong one and drops an
/// ally who has grown weak, sends soldiers and gold from quiet cities to the
/// borders, and sets every general left to farming, trade, walls, drafting or
/// drill — whichever the city is shortest of.
enum WarlordBrain {
    /// A faction's month. `attacks` false leaves the war to somebody else (Jev or a chat model decides it).
    static func play(_ w: inout WarlordWorld, _ f: Int, attacks: Bool = true) {
        guard w.factions[f].alive else { return }
        prisoners(&w, f)
        recruit(&w, f)
        diplomacy(&w, f, attacks: attacks)
        if attacks { war(&w, f) }
        reinforce(&w, f)
        develop(&w, f)
    }

    // MARK: War

    /// Troops a city should keep at home against what its hostile neighbours could send, leaving out a city about to be taken.
    static func keep(_ w: WarlordWorld, _ c: Int, without t: Int? = nil) -> Int {
        var threat = w.threat(to: c)
        if let t, w.cities[t].owner >= 0, w.cities[t].owner != w.cities[c].owner { threat -= w.cities[t].troops * 7 / 10 }
        let wall = 1 + Double(w.cities[c].wall) / 100
        return max(threat > 0 ? 1_500 : 500, Int(Double(max(0, threat)) * 0.6 / wall))
    }

    /// What a city is worth taking.
    static func value(_ w: WarlordWorld, _ f: Int, _ t: Int) -> Double {
        let site = warlordSites[t], owner = w.cities[t].owner
        var v = Double(site.size) + Double(w.cities[t].gold) / 1_500 + Double(w.cities[t].grain) / 15_000
        if owner >= 0, w.held(owner) == 1 { v += 2.5 }          // the rival's last city
        if owner < 0 { v += 0.8 }
        // A city that joins our lands together, or leaves none of our cities behind it exposed.
        v += Double(warlordLinks[t].filter { w.cities[$0.city].owner == f }.count) * 0.3
        return v
    }

    /// Every attack worth making now, best first.
    static func strikes(_ w: WarlordWorld, _ f: Int, least: Double = 0.64) -> [WarlordStrike] {
        var out: [WarlordStrike] = []
        for c in w.cities(of: f) {
            let idle = w.idle(c).filter { w.officers[$0].rest == 0 }
            guard !idle.isEmpty, w.cities[c].troops >= 1_200 else { continue }
            let lead = idle.max { fighting(w, $0) < fighting(w, $1) }!
            let rest = idle.filter { $0 != lead }
            var team = [lead]
            if rest.count >= 2, let deputy = rest.max(by: { w.war($0) < w.war($1) }) { team.append(deputy) }
            for t in w.foes(of: c) where !w.armies.contains(where: { $0.faction == f && $0.to == t }) {
                let spare = w.cities[c].troops - keep(w, c, without: t)
                guard spare >= 800 else { continue }
                let n: Int
                if let enough = w.needed(team, from: c, to: t, want: 0.86, spare: spare) { n = enough }
                else if w.chance(team, troops: spare, train: w.cities[c].train, from: c, to: t) >= bold(w, f, t, least) { n = spare }
                else { continue }
                let rations = n / 10 * (warlordRoad(c, t)?.months ?? 1)
                guard w.cities[c].grain >= rations else { continue }
                let p = w.chance(team, troops: n, train: w.cities[c].train, from: c, to: t)
                out.append(WarlordStrike(from: c, to: t, team: team, troops: n, chance: p, value: value(w, f, t)))
            }
        }
        return out.sorted { $0.chance * $0.value - Double($0.troops) / 40_000 > $1.chance * $1.value - Double($1.troops) / 40_000 }
    }

    /// Bolder against a much weaker rival.
    static func bold(_ w: WarlordWorld, _ f: Int, _ t: Int, _ least: Double) -> Double {
        let g = w.cities[t].owner
        guard g >= 0 else { return least }
        if g == w.giant { return least - 0.06 }
        return w.strength(f) > w.strength(g) * 2 ? least - 0.06 : least
    }

    static func fighting(_ w: WarlordWorld, _ o: Int) -> Int { w.lead(o) * 2 + w.war(o) + w.wit(o) / 2 }

    static func war(_ w: inout WarlordWorld, _ f: Int) {
        var used = Set<Int>()
        for _ in 0..<min(4, 1 + w.held(f) / 5) {
            guard let s = strikes(w, f).first(where: { !used.contains($0.to) }) else { return }
            used.insert(s.to)
            w.march(s.team, from: s.from, to: s.to, troops: s.troops)
        }
    }

    // MARK: People

    static func prisoners(_ w: inout WarlordWorld, _ f: Int) {
        for t in w.officers.indices where w.officers[t].state == .captive && w.officers[t].faction == f {
            let c = w.officers[t].city
            guard w.cities[c].owner == f else { continue }
            let asker = w.idle(c).max { w.recruitChance($0, t) < w.recruitChance($1, t) }
            if let asker, w.recruitChance(asker, t) >= 0.12 { w.recruit(asker, t) }
            else if w.officers[t].held >= 3 { w.release(t) }
        }
    }

    static func recruit(_ w: inout WarlordWorld, _ f: Int) {
        for c in w.cities(of: f) {
            for t in w.freeKnown(c) {
                guard let asker = w.idle(c).max(by: { w.recruitChance($0, t) < w.recruitChance($1, t) }) else { break }
                w.recruit(asker, t)
            }
        }
    }

    // MARK: Friends and enemies

    static func diplomacy(_ w: inout WarlordWorld, _ f: Int, attacks: Bool) {
        let ours = w.strength(f)
        // An ally grown weak on our border is a city waiting to be taken.
        if attacks {
            for g in w.factions[f].allies.keys.sorted() where w.bordering(f, g) && w.strength(g) * 3 < ours && (w.factions[f].allies[g] ?? 0) <= 26 {
                w.breakAlliance(f, g)
                break
            }
        }
        guard (w.turns + f) % 4 == 0 else { return }
        // A lord with nothing left may give up.
        for c in w.cities(of: f) {
            for t in w.reachable(from: c) where w.factions[w.officers[t].faction].lord == t {
                if let o = w.idle(c).max(by: { w.wit($0) < w.wit($1) }), w.persuadeChance(o, t) >= 0.2 { w.persuade(o, t) }
            }
        }
        // Against a much stronger neighbour: an ally who also borders it.
        let rivals = w.factions.indices.filter { $0 != f && w.factions[$0].alive && w.bordering(f, $0) && !w.allied(f, $0) }
        if let big = rivals.max(by: { w.strength($0) < w.strength($1) }), w.strength(big) > ours * 13 / 10 || big == w.giant, w.factions[f].allies.count < 3 {
            let friends = w.factions.indices.filter { $0 != f && $0 != big && w.factions[$0].alive && !w.allied(f, $0) && w.bordering($0, big) }
            if let g = friends.max(by: { w.strength($0) < w.strength($1) }),
               let envoy = w.cities(of: f).filter({ w.cities[$0].gold >= WarlordWorld.allyCost + 100 }).flatMap({ w.idle($0) }).max(by: { w.wit($0) + w.pol($0) < w.wit($1) + w.pol($1) }),
               w.allyChance(envoy, with: g) >= 0.3 {
                w.ally(envoy, with: g)
            }
        }
        // A clever general works on the enemy's wavering ones.
        for c in w.cities(of: f) where w.frontier(c) {
            guard let o = w.idle(c).filter({ w.wit($0) >= 80 }).max(by: { w.wit($0) < w.wit($1) }) else { continue }
            let targets = w.reachable(from: c).filter { !w.allied(f, w.officers[$0].faction) }
            if let t = targets.max(by: { w.persuadeChance(o, $0) < w.persuadeChance(o, $1) }), w.persuadeChance(o, t) >= 0.35 { w.persuade(o, t); continue }
            if let t = targets.filter({ w.person($0).total > 260 }).max(by: { w.sowChance(o, $0) < w.sowChance(o, $1) }), w.sowChance(o, t) >= 0.45, w.officers[t].loyalty > 40 { w.sow(o, t) }
        }
    }

    // MARK: Soldiers and gold where they are needed

    static func reinforce(_ w: inout WarlordWorld, _ f: Int) {
        let mine = w.cities(of: f)
        guard mine.count > 1 else { return }
        // Distance of every city of ours from the border, in roads.
        var depth = [Int: Int]()
        var frontier = mine.filter { !w.foes(of: $0).isEmpty }
        for c in frontier { depth[c] = 0 }
        var d = 0
        while !frontier.isEmpty {
            d += 1
            var next: [Int] = []
            for c in frontier { for n in warlordLinks[c].map(\.city) where w.cities[n].owner == f && depth[n] == nil { depth[n] = d; next.append(n) } }
            frontier = next
        }
        let head = spearhead(w, f)
        func deficit(_ x: Int) -> Int { keep(w, x) * 2 - w.cities[x].troops }
        for c in mine {
            guard let courier = w.idle(c).min(by: { WarlordBrain.fighting(w, $0) < WarlordBrain.fighting(w, $1) }) else { continue }
            let here = depth[c] ?? 99
            let near = warlordLinks[c].map(\.city).filter { w.cities[$0].owner == f }
            let towards = near.filter { (depth[$0] ?? 99) < here }
            if here > 0, !towards.isEmpty {
                // A quiet city sends its soldiers and spare gold on toward the border — toward the spearhead when it can.
                let to = towards.contains(where: { $0 == head }) ? head! : towards.max { deficit($0) < deficit($1) }!
                let troops = max(0, w.cities[c].troops - 800)
                let gold = max(0, w.cities[c].gold - 400)
                let grain = max(0, w.cities[c].grain - w.cities[c].troops / 10 * 14)
                if troops >= 1_000 || gold >= 600 { w.move(courier, to: to, troops: troops >= 1_000 ? troops : 0, gold: gold / 2, grain: grain / 2, stay: false) }
            } else if here == 0 {
                let spare = w.cities[c].troops - keep(w, c)
                if let head, head != c, near.contains(head), spare > 2_000 {
                    // Mass on the spearhead: the neighbours lend it what they can spare.
                    w.move(courier, to: head, troops: spare * 7 / 10, grain: max(0, w.cities[c].grain - w.cities[c].troops / 10 * 10) / 2, stay: false)
                } else {
                    // Along the border, the city under the heaviest threat gets help from a safer one.
                    let short = near.filter { deficit($0) > 2_000 && deficit($0) > deficit(c) + 3_000 }
                    if let to = short.max(by: { deficit($0) < deficit($1) }), spare > 1_500 { w.move(courier, to: to, troops: spare / 2, stay: false) }
                }
            }
        }
        // Generals go where they are wanted: two or three to a border city, one to a quiet one.
        func wanted(_ x: Int) -> Int { w.foes(of: x).isEmpty ? 1 : (x == head ? 4 : 2) }
        for c in mine {
            let here = w.idle(c)
            guard w.present(c).count > wanted(c), let o = here.min(by: { WarlordBrain.fighting(w, $0) < WarlordBrain.fighting(w, $1) }) else { continue }
            // The neighbour on the shortest way to a city short of generals.
            var seen: Set<Int> = [c]
            var queue: [(city: Int, first: Int)] = warlordLinks[c].map(\.city).filter { w.cities[$0].owner == f }.map { ($0, $0) }
            for q in queue { seen.insert(q.city) }
            var step: Int?
            while !queue.isEmpty {
                let q = queue.removeFirst()
                if w.present(q.city).count < wanted(q.city) { step = q.first; break }
                for n in warlordLinks[q.city].map(\.city) where w.cities[n].owner == f && !seen.contains(n) { seen.insert(n); queue.append((n, q.first)) }
            }
            if let step { w.move(o, to: step) }
        }
    }

    /// The border city to mass on: the one whose best neighbour to take is the best prize for what it would cost.
    static func spearhead(_ w: WarlordWorld, _ f: Int) -> Int? {
        var best: (city: Int, score: Double)?
        for c in w.cities(of: f) {
            let near = warlordLinks[c].map(\.city).filter { w.cities[$0].owner == f }
            let help = near.reduce(0) { $0 + max(0, w.cities[$1].troops - keep(w, $1)) * 7 / 10 }
            let force = w.cities[c].troops + help - keep(w, c)
            guard force > 2_000 else { continue }
            let team = w.present(c).sorted { fighting(w, $0) > fighting(w, $1) }.prefix(2)
            for t in w.foes(of: c) {
                let p = w.chance(Array(team), troops: force, train: w.cities[c].train, from: c, to: t)
                let score = p * value(w, f, t)
                if best == nil || score > best!.score { best = (c, score) }
            }
        }
        return best?.city
    }

    // MARK: Home

    static func develop(_ w: inout WarlordWorld, _ f: Int) {
        let mine = w.cities(of: f)
        for c in mine {
            var idle = w.idle(c)
            while let o = pick(w, c, idle) {
                let job = task(w, c, o)
                if w.work(o, job) == nil { w.work(o, .search) }
                idle.removeAll { $0 == o }
            }
        }
    }

    private static func pick(_ w: WarlordWorld, _ c: Int, _ idle: [Int]) -> Int? { idle.first }

    /// What a city needs most from this general.
    static func task(_ w: WarlordWorld, _ c: Int, _ o: Int) -> WarlordWork {
        let x = w.cities[c]
        let eats = max(1, x.troops / 10)
        let months = x.grain / eats
        let need = keep(w, c) * 2
        let draft = w.draftSize(o)
        if w.frontier(c), x.troops < need, draft >= 600, x.loyalty > 30 { return .draft }
        if months < 8, x.farm < 100, x.gold >= 50 { return .farm }
        if x.train < 70, x.troops >= 2_000 { return .drill }
        if w.frontier(c), x.wall < 75, x.gold >= 160 { return .wall }
        // Build an army where the grain can feed it.
        if months > 20, draft >= 800, x.loyalty > 45, x.troops < x.people / 20 { return .draft }
        if x.gold < 50 { return .search }
        if x.farm < 100 || x.trade < 100 {
            if x.farm >= 100 { return .trade }
            if x.trade >= 100 { return .farm }
            return x.farm <= x.trade + 5 ? .farm : .trade
        }
        if x.wall < 100 { return .wall }
        return x.train < 100 ? .drill : .search
    }
}
