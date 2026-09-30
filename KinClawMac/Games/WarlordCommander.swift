import Foundation

/// Jev — or a chat model — as a warlord: once a month, one multiple-choice
/// question. What should the faction do first this month? Each option is a
/// thing the program has measured — an attack with its odds and what it would
/// cut or win, a field to farm with the grain it brings, soldiers for a city
/// under threat with the troops on the other side, an ally with the enemy you
/// share — written verdict first. The script then carries it out and fills in
/// everything else a lord does in a month, except starting other wars.
enum WarlordPlan {
    case attack(WarlordStrike)
    /// Every attack the odds favour, as the script would make them.
    case allOut([WarlordStrike])
    case work(Int, WarlordWork)
    case ally(Int, Int)
    case recruit(Int, Int)
    case persuade(Int, Int)
    case wait
}

struct WarlordOption {
    var plan: WarlordPlan
    var title: String
    var words: String
}

enum WarlordCommander {
    static let rules = "A game of the Three Kingdoms in the spirit of the classic 三国志: China in 190 AD, 43 cities joined by roads, some across the Yellow River or the Yangtze and some over mountain passes, which favour the defender. Seventeen warlords each hold a few cities; a turn is a month. Each city has people, gold, grain, soldiers, their drill, farming, trade and walls, and the people's loyalty. Gold comes in every month from trade; grain comes in once a year at the autumn harvest from farming; every soldier eats grain and draws pay every month (a gold for every 200), and unfed or unpaid soldiers desert. Each general can do one thing a month in their city: farm, trade, walls, draft soldiers, drill them, search for talent and treasure, recruit a free or captured general, move or send soldiers and goods to a neighbouring city of one's own, march on a neighbouring city, or make alliances, sow discord and persuade enemy generals. An army takes a month or two along a road and fights when it arrives: soldiers, their drill, the generals' leadership, strength and intelligence, the walls, the road and luck decide it; now and then the two best fighters duel. The winner takes the city and may capture its generals; a warlord with no cities is gone. Whoever holds every city unifies the realm; a faction that loses all its cities has lost."
    static func question(_ lord: String) -> String { "What should \(lord)'s faction do first this month?" }
    static let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: not losing a city — an enemy army on the way, or a border city with far fewer soldiers than the hostile troops next to it, must be answered before anything else. Second: taking cities with good odds — about 70% or better — preferring a rival's last city, a rich city, and one that joins our lands or cuts the enemy's apart; odds below 60% lose soldiers for nothing. Third: growing — winning over a great general, more grain when the soldiers will soon go hungry, more gold when there is not enough for drafting, an ally when a much stronger neighbour borders us. An option that gives no orders gains nothing; choose it only when every other option would do harm."

    // MARK: The faction, in words

    static func troops(_ n: Int) -> String { n >= 10_000 ? String(format: "%.1f万", Double(n) / 10_000) : "\(n)" }

    static func situation(_ w: WarlordWorld, _ f: Int) -> String {
        var parts = ["\(w.year) AD, month \(w.month) (\(["", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter", "winter", "winter"][w.month])); the harvest comes at the end of month 9"]
        let mine = w.cities(of: f)
        parts.append("\(w.lordName(f))'s faction holds \(mine.count) of 43 cities with \(w.troops(of: f)) soldiers, \(w.gold(of: f)) gold, \(w.grain(of: f)) grain and \(w.staff(of: f).count) generals")
        for c in mine {
            let x = w.cities[c]
            var line = "\(warlordSites[c].name): \(x.troops) soldiers (drill \(x.train)), walls \(x.wall), farming \(x.farm), trade \(x.trade), \(x.gold) gold, \(x.grain) grain, \(x.people) people, loyalty \(x.loyalty), \(w.present(c).count) generals"
            let t = menace(w, c)
            if t > 0 { line += "; the strongest hostile neighbour could send about \(t)" }
            for a in w.armies where a.to == c && a.faction != f { line += "; \(w.banner(a.faction)) army of \(a.troops) marching on it, arriving in \(a.left) month\(a.left == 1 ? "" : "s")" }
            parts.append(line)
        }
        let rivals = w.factions.indices.filter { $0 != f && w.factions[$0].alive }.sorted { w.strength($0) > w.strength($1) }
        parts.append("the others: " + rivals.map { g in "\(w.lordName(g)) \(w.held(g)) cities \(w.troops(of: g)) soldiers" + (w.allied(f, g) ? " (our ally)" : w.bordering(f, g) ? " (borders us)" : "") }.joined(separator: ", "))
        return parts.joined(separator: "; ")
    }

    // MARK: What could be done first

    static func options(_ w: WarlordWorld, _ f: Int) -> [WarlordOption] {
        var out: [WarlordOption] = []
        let mine = w.cities(of: f)

        // War: the best few attacks the numbers allow, each measured.
        let strikes = WarlordBrain.strikes(w, f, least: 0.55)
        var seen = Set<Int>()
        for s in strikes where !seen.contains(s.to) {
            seen.insert(s.to)
            out.append(WarlordOption(plan: .attack(s), title: "出征\(warlordSites[s.to].name)", words: attackWords(w, f, s)))
            if seen.count >= 4 { break }
        }
        let good = WarlordBrain.strikes(w, f).reduce(into: [WarlordStrike]()) { acc, s in if !acc.contains(where: { $0.to == s.to || $0.from == s.from }) { acc.append(s) } }
        if good.count >= 2 {
            let list = good.prefix(4).map { "\(warlordSites[$0.to].name) (\(Int(($0.chance * 100).rounded()))% with \($0.troops) soldiers)" }.joined(separator: ", ")
            out.append(WarlordOption(plan: .allOut(Array(good.prefix(4))), title: "全线进攻", words: "attacks on \(min(4, good.count)) fronts at once where the odds are good: \(list); the cities they leave keep enough against their neighbours"))
        }

        // Danger: the city most in need of soldiers or walls — measured against the one enemy most likely to come, or an army already coming.
        let danger = mine.filter { menace(w, $0) > 0 }.max { Double(menace(w, $0)) / held(w, $0) < Double(menace(w, $1)) / held(w, $1) }
        if let c = danger, let o = w.idle(c).max(by: { w.lead($0) < w.lead($1) }) {
            let x = w.cities[c], m = menace(w, c), hold = held(w, c)
            let n = w.draftSize(o)
            let coming = w.armies.filter { $0.to == c && $0.faction != f }
            let why = coming.isEmpty ? "the strongest hostile neighbour holds \(m) soldiers and no army is marching on it" : "\(coming.map { "\(w.banner($0.faction)) marches on it with \($0.troops)" }.joined(separator: ", "))"
            let fall = Double(m) > hold, close = Double(m) > hold * 0.7
            if n >= 300 {
                // What the soldiers cost every month from then on, against what comes in.
                let earn = income(w, f), pay = (w.troops(of: f) + n) / 200
                let grainYear = harvest(w, f), eatYear = (w.troops(of: f) + n) / 10 * 12
                var verdict = fall && !coming.isEmpty ? "keeps \(warlordSites[c].name) from falling" : fall || close ? "makes \(warlordSites[c].name) safer" : "adds soldiers \(warlordSites[c].name) does not need yet"
                if pay > earn - 40 || eatYear > grainYear + w.grain(of: f) { verdict += " but the faction cannot feed and pay them for long" }
                out.append(WarlordOption(plan: .work(o, .draft), title: "\(warlordSites[c].name)征兵", words: "\(verdict): \(w.name(o)) drafts \(n) soldiers there (then \(x.troops + n)), while \(why); walls \(x.wall) make its \(x.troops) soldiers hold like about \(Int(hold)); costs \(n / 10) gold, loyalty −4; then \((w.troops(of: f) + n) / 200) gold pay a month against \(income(w, f)) coming in, and \((w.troops(of: f) + n) / 10 * 12) grain a year against a harvest of about \(harvest(w, f)) and \(w.grain(of: f)) in store"))
            }
            if x.wall < 100, x.gold >= WarlordWork.wall.cost {
                let verdict = fall && !coming.isEmpty ? "makes \(warlordSites[c].name) harder to take before the enemy arrives" : fall || close ? "makes \(warlordSites[c].name) a little harder to take" : "strengthens walls \(warlordSites[c].name) does not need yet"
                out.append(WarlordOption(plan: .work(o, .wall), title: "\(warlordSites[c].name)筑城", words: "\(verdict): walls \(x.wall) → about \(min(100, x.wall + 3 + w.lead(o) / 20)), each wall point worth about 0.5% more defence; \(x.troops) soldiers there while \(why); costs \(WarlordWork.wall.cost) gold"))
            }
        }

        // Home: the city where farming or trade pays most, and drill where soldiers are raw.
        let eats = mine.reduce(0) { $0 + w.cities[$1].troops / 10 }, grain = w.grain(of: f)
        let monthsOfGrain = eats > 0 ? grain / eats : 99
        if let c = mine.filter({ w.cities[$0].farm < 100 && w.cities[$0].gold >= 50 && !w.idle($0).isEmpty }).max(by: { w.cities[$0].people < w.cities[$1].people }),
           let o = w.idle(c).max(by: { w.pol($0) < w.pol($1) }) {
            let x = w.cities[c], up = 3 + w.pol(o) / 16
            let more = Int(Double(x.people) / 1000 * Double(up) / 100 * 200 * (0.5 + Double(x.loyalty) / 200))
            let verdict = monthsOfGrain < 6 ? "feeds soldiers who will soon go hungry" : monthsOfGrain < 12 ? "adds grain the soldiers will need" : "adds grain there is already plenty of"
            out.append(WarlordOption(plan: .work(o, .farm), title: "\(warlordSites[c].name)开垦", words: "\(verdict): \(w.name(o)) farms \(warlordSites[c].name), farming \(x.farm) → about \(min(100, x.farm + up)), about +\(more) grain a year; the faction has \(grain) grain, \(monthsOfGrain) months of eating; costs 50 gold"))
        }
        let gold = w.gold(of: f)
        if let c = mine.filter({ w.cities[$0].trade < 100 && w.cities[$0].gold >= 50 && !w.idle($0).isEmpty }).max(by: { w.cities[$0].people < w.cities[$1].people }),
           let o = w.idle(c).max(by: { w.pol($0) < w.pol($1) }) {
            let x = w.cities[c], up = 3 + w.pol(o) / 16
            let more = Int(Double(x.people) / 1000 * Double(up) / 100 * 3 * (0.5 + Double(x.loyalty) / 200) * 12)
            let pay = w.troops(of: f) / 200
            let verdict = gold < pay * 3 ? "pays soldiers who will soon go unpaid" : gold < 1_000 ? "adds gold for drafting and walls" : "adds gold to a full treasury"
            out.append(WarlordOption(plan: .work(o, .trade), title: "\(warlordSites[c].name)商业", words: "\(verdict): \(w.name(o)) builds trade in \(warlordSites[c].name), trade \(x.trade) → about \(min(100, x.trade + up)), about +\(more) gold a year; the faction has \(gold) gold and pays \(pay) a month; costs 50 gold"))
        }
        if let c = mine.filter({ w.cities[$0].train < 70 && w.cities[$0].troops >= 3_000 && !w.idle($0).isEmpty }).max(by: { w.cities[$0].troops < w.cities[$1].troops }),
           let o = w.idle(c).max(by: { w.lead($0) < w.lead($1) }) {
            let x = w.cities[c], up = min(100 - x.train, 5 + w.lead(o) / 12)
            out.append(WarlordOption(plan: .work(o, .drill), title: "\(warlordSites[c].name)训练", words: "makes \(x.troops) soldiers in \(warlordSites[c].name) fight better: drill \(x.train) → \(x.train + up), about \(Int(Double(up) * 0.5))% more battle power"))
        }

        // People: the best general who could be won over this month.
        var asks: [(o: Int, t: Int, p: Double)] = []
        for c in mine {
            for t in w.freeKnown(c) + w.captives(c).filter({ w.officers[$0].faction == f }) {
                if let o = w.idle(c).max(by: { w.recruitChance($0, t) < w.recruitChance($1, t) }) { asks.append((o, t, w.recruitChance(o, t))) }
            }
        }
        if let best = asks.max(by: { Double(w.person($0.t).total) * $0.p < Double(w.person($1.t).total) * $1.p }) {
            let p = w.person(best.t)
            out.append(WarlordOption(plan: .recruit(best.o, best.t), title: "登用\(p.name)", words: "wins over \(p.name) about \(Int((best.p * 100).rounded()))% of the time\(w.officers[best.t].state == .captive ? " (a captive)" : ""): strength \(p.war), intelligence \(p.wit), leadership \(p.lead), politics \(p.pol)" + (p.skill.map { ", \($0.english)" } ?? "") + "; asked by \(w.name(best.o)) in \(warlordSites[w.officers[best.o].city].name)"))
        }

        // Friends: an ally against the strongest neighbour, and a beaten lord who might give in.
        let rivals = w.factions.indices.filter { $0 != f && w.factions[$0].alive && w.bordering(f, $0) && !w.allied(f, $0) }
        if let big = rivals.max(by: { w.strength($0) < w.strength($1) }) {
            let friends = w.factions.indices.filter { $0 != f && $0 != big && w.factions[$0].alive && !w.allied(f, $0) && w.bordering($0, big) }
            if let g = friends.max(by: { w.strength($0) < w.strength($1) }),
               let envoy = mine.filter({ w.cities[$0].gold >= WarlordWorld.allyCost }).flatMap({ w.idle($0) }).max(by: { w.wit($0) + w.pol($0) < w.wit($1) + w.pol($1) }) {
                let p = w.allyChance(envoy, with: g)
                let verdict = w.strength(big) > w.strength(f) ? "guards our back against the stronger \(w.lordName(big))" : "makes a friend against \(w.lordName(big)), who is weaker than us"
                out.append(WarlordOption(plan: .ally(envoy, g), title: "与\(w.lordName(g))结盟", words: "\(verdict), if \(w.lordName(g)) agrees (about \(Int((p * 100).rounded()))%): three years of peace; both border \(w.lordName(big)) (\(w.held(big)) cities, \(w.troops(of: big)) soldiers against our \(w.troops(of: f))); costs \(WarlordWorld.allyCost) gold, and allies cannot be attacked"))
            }
        }
        for c in mine {
            for t in w.reachable(from: c) where w.factions[w.officers[t].faction].lord == t {
                if let o = w.idle(c).max(by: { w.persuadeChance($0, t) < w.persuadeChance($1, t) }), w.persuadeChance(o, t) > 0 {
                    let g = w.officers[t].faction
                    out.append(WarlordOption(plan: .persuade(o, t), title: "劝降\(w.name(t))", words: "takes all of \(w.name(t))'s \(w.held(g)) city and \(w.troops(of: g)) soldiers without a fight about \(Int((w.persuadeChance(o, t) * 100).rounded()))% of the time: \(w.name(o)) goes to persuade him to submit"))
                }
            }
        }

        out.append(WarlordOption(plan: .wait, title: "按兵不动", words: "gives no orders this month: nothing is farmed, drafted, drilled or won, and the generals sit idle"))
        return out
    }

    static func attackWords(_ w: WarlordWorld, _ f: Int, _ s: WarlordStrike) -> String {
        let t = s.to, g = w.cities[t].owner, x = w.cities[t]
        let pct = Int((s.chance * 100).rounded())
        let verdict = s.chance >= 0.8 ? "takes \(warlordSites[t].name) about \(pct)% of the time" : s.chance >= 0.65 ? "probably takes \(warlordSites[t].name) (about \(pct)%)" : "risks losing the army at \(warlordSites[t].name) (only about \(pct)% to win)"
        let guardName = w.defenders(t).first.map { ", led by \(w.name($0))" } ?? ""
        let road = warlordRoad(s.from, t)!
        var words = "\(verdict): \(s.team.map { w.name($0) }.joined(separator: " and ")) march\(s.team.count == 1 ? "es" : "") from \(warlordSites[s.from].name) with \(s.troops) soldiers; \(warlordSites[t].name) holds \(x.troops) soldiers, walls \(x.wall)\(guardName)"
        words += g >= 0 ? " for \(w.lordName(g))" : " for nobody"
        if road.kind == .river { words += "; across the \(road.name) (a river crossing favours the defender)" }
        if road.kind == .pass { words += "; over the \(road.name) (a mountain pass favours the defender)" }
        if road.months > 1 { words += "; \(road.months) months on the road" }
        if g >= 0, w.held(g) == 1 { words += "; it is \(w.lordName(g))'s last city: the faction falls" }
        else if g >= 0 {
            let before = pieces(w, g, without: nil), after = pieces(w, g, without: t)
            if after > before { words += "; it cuts \(w.lordName(g))'s lands apart" }
        }
        words += "; it holds \(x.people) people, \(x.gold) gold and \(x.grain) grain"
        let left = w.cities[s.from].troops - s.troops, threat = w.threat(to: s.from) - (g >= 0 ? x.troops * 7 / 10 : 0)
        if threat > left { words += "; \(warlordSites[s.from].name) is left with \(left) soldiers against about \(threat) hostile ones next door" }
        return words
    }

    /// Gold a faction takes in a month, and grain at a year's harvest, as the engine counts them.
    static func income(_ w: WarlordWorld, _ f: Int) -> Int {
        var total = 0
        for c in w.cities(of: f) {
            let x = w.cities[c]
            let heart = 0.5 + Double(x.loyalty) / 200
            total += Int(Double(x.people) / 1000 * Double(x.trade) / 100 * 3 * heart) + 20
        }
        return total
    }
    static func harvest(_ w: WarlordWorld, _ f: Int) -> Int {
        var total = 0
        for c in w.cities(of: f) {
            let x = w.cities[c]
            let heart = 0.5 + Double(x.loyalty) / 200
            total += Int(Double(x.people) / 1000 * Double(x.farm) / 100 * 200 * heart) + 500
        }
        return total
    }

    /// The enemy most likely to come: the strongest hostile neighbour, or all the armies already marching on the city.
    static func menace(_ w: WarlordWorld, _ c: Int) -> Int {
        let f = w.cities[c].owner
        let coming = w.armies.filter { $0.to == c && $0.faction != f }.reduce(0) { $0 + $1.troops }
        let near = w.foes(of: c).filter { w.cities[$0].owner >= 0 }.map { w.cities[$0].troops }.max() ?? 0
        return max(coming, near * 7 / 10)
    }
    /// A city's soldiers as they would count behind its walls.
    static func held(_ w: WarlordWorld, _ c: Int) -> Double { Double(max(1, w.cities[c].troops)) * 1.15 * (1 + Double(w.cities[c].wall) / 200) }

    /// How many separate pieces a faction's lands are in.
    static func pieces(_ w: WarlordWorld, _ g: Int, without t: Int?) -> Int {
        var left = Set(w.cities(of: g).filter { $0 != t }), n = 0
        while let start = left.first {
            n += 1
            var stack = [start]
            left.remove(start)
            while let c = stack.popLast() { for x in warlordLinks[c].map(\.city) where left.contains(x) { left.remove(x); stack.append(x) } }
        }
        return n
    }

    // MARK: Carrying it out

    /// The chosen thing first, then the rest of the month as the script would spend it — without starting other wars.
    static func execute(_ plan: WarlordPlan, _ w: inout WarlordWorld, _ f: Int) {
        switch plan {
        case .attack(let s): w.march(s.team, from: s.from, to: s.to, troops: s.troops)
        case .allOut(let list): for s in list { w.march(s.team, from: s.from, to: s.to, troops: s.troops) }
        case .work(let o, let job): w.work(o, job)
        case .ally(let o, let g): w.ally(o, with: g)
        case .recruit(let o, let t): w.recruit(o, t)
        case .persuade(let o, let t): w.persuade(o, t)
        case .wait: return
        }
        WarlordBrain.play(&w, f, attacks: false)
    }
}
