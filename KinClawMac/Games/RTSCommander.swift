import Foundation

/// Jev — or a chat model — in 帝国时代, one multiple-choice question every few
/// seconds of the game, of two kinds.
///
/// Commanding a side (`postures`): which way to lean — grow, arm, advance an
/// age, attack, defend — each option with what bears on it measured: villagers
/// against what the age wants, both armies and which is stronger, the odds of
/// an attack on their town. The computer's hands carry the leaning out.
///
/// Advising the person (`options`): a specific next move — for a camp, the
/// trees or the gold within reach of each place it could go and how far that
/// is from the town centre — offered with a 照做 button. Either way the
/// program measures and says it in words; the model picks.
enum RTSPlan: Equatable {
    case villager
    case focus(RTSResource)
    case build(RTSBuildingKind, RTSTile)
    /// Put money aside for something big — a building at a place, or the next age — and nothing else on it until then.
    case save(RTSBuildingKind?, RTSTile?)
    case advance
    case train(RTSUnitKind)
    case attack, defend, wait
    /// A standing order for a while: the hands lean that way until told otherwise.
    case posture(RTSPosture)
}

struct RTSOption {
    var plan: RTSPlan
    var title: String
    var words: String
}

enum RTSCommander {
    static let rules = "Age of Empires, in real time, on a 48 by 30 tile map: two towns, each with a town centre. Villagers gather food (berry bushes, then farms), wood (trees), gold and stone, and carry it to the town centre or to a camp that takes it — a mill takes food, a lumber camp wood, a mining camp gold and stone — so a camp close to the work saves walking. Each house gives room for 5 more people; the town centre gives 5. Advancing an age takes time at the town centre and unlocks buildings and soldiers. Spearmen beat knights, archers beat spearmen, knights beat archers; town centres and towers shoot arrows. The side whose town centre falls loses."
    static let question = "What should this empire do next?"
    static let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: if enemy soldiers are at your town, defend — bring the army home and train soldiers that beat theirs. Second: never let the population fill up: with fewer than 4 places left, build a house. Third: keep the town centre training villagers until about 20 in the Dark Age and 28 later; put them on the resource you are shortest of. Fourth: build camps where the words say the most is within reach and the walk from the town centre is short, farms when the berries run low, barracks once the economy is going. Fifth: advance to the next age when you can afford it and are not under attack. Sixth: attack only when your army is clearly stronger than what defends their town; until then build soldiers that beat theirs."

    static let resourceWords = ["food", "wood", "gold", "stone"], resourceCN = ["食物", "木头", "黄金", "石头"]
    static let buildingWords = ["town centre", "house", "mill", "farm", "lumber camp", "mining camp", "barracks", "archery range", "stable", "tower"]
    static let unitWords = ["villager", "spearman", "archer", "knight"], unitPlural = ["villagers", "spearmen", "archers", "knights"]
    static let buildingCN = ["城镇中心", "房屋", "磨坊", "农田", "伐木场", "采矿场", "兵营", "靶场", "马厩", "箭塔"]
    static let unitCN = ["村民", "长枪兵", "弓箭手", "骑士"]

    // MARK: Measuring

    static func army(_ units: [RTSUnit]) -> String {
        let counts = RTSUnitKind.allCases.dropFirst().map { k in (k, units.filter { $0.kind == k }.count) }.filter { $0.1 > 0 }
        return counts.isEmpty ? "no soldiers" : counts.map { "\($0.1) \(($0.1 == 1 ? unitWords : unitPlural)[$0.0.rawValue])" }.joined(separator: ", ")
    }

    /// A rough fighting strength of one army against another: hit points times what each blow does against their mix.
    static func strength(_ a: [RTSUnit], against b: [RTSUnit]) -> Double {
        let kinds = b.map(\.kind), n = Double(max(kinds.count, 1))
        return a.reduce(0) { total, u in
            let blow = kinds.isEmpty ? RTSWorld.attack(u.kind, against: nil) : kinds.reduce(0) { $0 + RTSWorld.attack(u.kind, against: $1) } / n
            return total + u.hp * blow * (u.kind == .archer ? 1.3 : 1)
        }
    }

    static func situation(_ w: RTSWorld, _ s: Int) -> String {
        situationWords(w, s)
    }

    private static func situationWords(_ w: RTSWorld, _ s: Int) -> String {
        let me = w.players[s], them = w.players[1 - s]
        let mine = w.units.filter { $0.owner == s }, theirs = w.units.filter { $0.owner != s }
        let jobs = RTSBrain(owner: s).jobs(w), idle = mine.filter { $0.kind == .villager && $0.task == .idle }.count
        let villagers = mine.filter { $0.kind == .villager }.count
        var parts = [String(format: "%d:%02d into the game; you are %@, in the %@", Int(w.time) / 60, Int(w.time) % 60, s == 0 ? "Blue" : "Red",
                            ["Dark Age", "Feudal Age", "Castle Age"][me.age]) + (me.researching > 0 ? ", advancing (\(Int(me.researching)) seconds left)" : "")]
        parts.append((0..<4).map { "\(resourceWords[$0]) \(Int(me.stock[$0]))" }.joined(separator: ", "))
        parts.append("\(villagers) villagers: \(jobs[0]) on food, \(jobs[1]) on wood, \(jobs[2]) on gold, \(jobs[3]) on stone" + (idle > 0 ? ", \(idle) idle" : ""))
        parts.append("population \(w.population(s)) of \(w.room(s))")
        let built = Dictionary(grouping: w.buildings.filter { $0.owner == s }, by: \.kind).sorted { $0.key.rawValue < $1.key.rawValue }
        parts.append("buildings: " + built.map { "\($0.value.count) \(buildingWords[$0.key.rawValue])" }.joined(separator: ", "))
        parts.append("your soldiers: \(army(mine))")
        parts.append("the enemy: \(["Dark Age", "Feudal Age", "Castle Age"][them.age]), \(theirs.filter { $0.kind == .villager }.count) villagers, soldiers: \(army(theirs))")
        if let tc = w.buildings.first(where: { $0.owner == s && $0.kind == .townCenter }) {
            let raiders = theirs.filter { $0.kind != .villager && hypot($0.x - Double(tc.x + 1), $0.y - Double(tc.y + 1)) < 12 }
            if !raiders.isEmpty { parts.append("enemy soldiers are at your town: \(army(raiders))") }
        }
        return parts.joined(separator: "; ")
    }

    // MARK: The options

    static func options(_ w: RTSWorld, _ s: Int, goal: RTSPlan? = nil) -> [RTSOption] {
        guard let tc = w.buildings.first(where: { $0.owner == s && $0.kind == .townCenter }) else { return [] }
        let brain = RTSBrain(owner: s), me = w.players[s], home = RTSTile(x: tc.x + 1, y: tc.y + 1)
        let mine = w.units.filter { $0.owner == s }, theirs = w.units.filter { $0.owner != s }
        let villagers = mine.filter { $0.kind == .villager }.count, jobs = brain.jobs(w)
        func price(_ p: [Double]) -> String { (0..<4).filter { p[$0] > 0 }.map { "\(Int(p[$0])) \(resourceWords[$0])" }.joined(separator: ", ") }
        func priceCN(_ p: [Double]) -> String { (0..<4).filter { p[$0] > 0 }.map { "\(Int(p[$0]))\(["食", "木", "金", "石"][$0])" }.joined(separator: " ") }
        func far(_ t: RTSTile) -> Int { Int(hypot(Double(t.x - home.x), Double(t.y - home.y)).rounded()) }
        func around(_ t: RTSTile, _ kind: RTSTerrain, _ r: Int) -> Int {
            var n = 0
            for y in max(0, t.y - r)...min(RTSWorld.height - 1, t.y + r) { for x in max(0, t.x - r)...min(RTSWorld.width - 1, t.x + r)
                where w.terrain[y * RTSWorld.width + x] == kind && w.amount[y * RTSWorld.width + x] > 0 { n += 1 } }
            return n
        }
        var out: [RTSOption] = []
        let room = w.room(s) - w.population(s)

        // How far each load is carried now, by resource: what a camp would save.
        func carried(_ r: RTSResource) -> (workers: Int, tiles: Double) {
            var n = 0, total = 0.0
            for u in mine where u.kind == .villager {
                guard case .gather(let t) = u.task, RTSWorld.resource(of: w.terrain[RTSWorld.index(t)]) == r,
                      let drop = w.dropSite(for: r, owner: s, near: Double(t.x) + 0.5, Double(t.y) + 0.5) else { continue }
                n += 1; total += w.distance(to: drop, Double(t.x) + 0.5, Double(t.y) + 0.5)
            }
            return (n, n == 0 ? 0 : total / Double(n))
        }
        _ = tc; _ = villagers
        func income(_ r: Int) -> Double {
            let rate: [Double] = [0.8, 0.9, 0.75, 0.75]
            return Double(jobs[r]) * rate[r] * 60 * 0.7                                  // walking eats about a third
        }
        /// Something too dear today: what it needs, and how long saving would take at this income.
        func saving(_ price: [Double]) -> String {
            let short = (0..<4).filter { price[$0] > me.stock[$0] }
            let wait = short.map { r in income(r) > 0 ? (price[r] - me.stock[r]) / income(r) * 60 : 999 }.max() ?? 0
            return "needs " + short.map { "\(Int(price[$0])) \(resourceWords[$0]) (you have \(Int(me.stock[$0])))" }.joined(separator: ", ")
                + (wait < 999 ? ", about \(Int(wait.rounded())) seconds of saving" : ", and nobody is gathering it")
        }
        func saveFor(_ kind: RTSBuildingKind?, _ spot: RTSTile?, _ title: String, _ what: String, _ price: [Double]) {
            guard goal == nil, !w.afford(price, s) else { return }
            out.append(RTSOption(plan: .save(kind, spot), title: "攒钱：\(title)", words: "save up for \(what): it \(saving(price)); nothing else is bought with it until then"))
        }
        func build(_ kind: RTSBuildingKind, _ spot: RTSTile?, _ detail: String) {
            guard let spot, me.age >= RTSWorld.age(kind), w.afford(RTSWorld.cost(kind), s) else { return }
            out.append(RTSOption(plan: .build(kind, spot), title: "造\(buildingCN[kind.rawValue])（\(priceCN(RTSWorld.cost(kind)))）" + (detail.isEmpty ? "" : " · \(spot.x),\(spot.y)"),
                                 words: "build a \(buildingWords[kind.rawValue]) (\(price(RTSWorld.cost(kind)))) \(detail)"))
        }
        if w.room(s) < RTSWorld.popCap, room <= 5 {
            build(.house, brain.spot(.house, near: home, w, clearance: true), "next to the town centre: room for 5 more people; population \(w.population(s)) of \(w.room(s))" + (room <= 1 ? " — full: nobody more can be trained" : ""))
        }
        // Camps: at the two best places each, by what is within reach and how far the town is.
        let trees = (0..<(RTSWorld.width * RTSWorld.height)).filter { w.terrain[$0] == .forest }.map { RTSTile(x: $0 % RTSWorld.width, y: $0 / RTSWorld.width) }
            .filter { far($0) <= 16 && w.reachableSide($0) != nil }
        let groves = trees.sorted { around($0, .forest, 3) - far($0) > around($1, .forest, 3) - far($1) }
        // A camp is offered only where no camp of the kind already stands within six tiles.
        func campNear(_ kind: RTSBuildingKind, _ t: RTSTile) -> Bool {
            w.buildings.contains { $0.owner == s && ($0.kind == kind || $0.kind == .townCenter) && hypot(Double($0.x - t.x), Double($0.y - t.y)) < 6.5 }
        }
        var campSpots: [RTSTile] = []
        for tree in groves.prefix(40) {
            guard campSpots.count < 2, !campNear(.lumberCamp, tree), let spot = brain.spot(.lumberCamp, near: tree, w, clearance: false),
                  !campSpots.contains(where: { hypot(Double($0.x - spot.x), Double($0.y - spot.y)) < 5 }) else { continue }
            campSpots.append(spot)
            let now = carried(.wood)
            build(.lumberCamp, spot, "at \(spot.x),\(spot.y): \(around(spot, .forest, 4)) trees within 4 tiles, \(far(spot)) tiles from the town centre"
                  + (now.workers > 0 ? "; your \(now.workers) woodcutters now carry each load about \(Int(now.tiles.rounded())) tiles" : "; nobody is cutting wood yet"))
        }
        for rock in [RTSTerrain.gold, .stone] where me.age >= 1 || rock == .gold {
            if let near = w.nearest(rock, from: home, within: 18), !campNear(.miningCamp, near), let spot = brain.spot(.miningCamp, near: near, w, clearance: false) {
                let now = carried(rock == .gold ? .gold : .stone)
                build(.miningCamp, spot, "at \(spot.x),\(spot.y): \(around(spot, rock, 3)) \(rock == .gold ? "gold" : "stone") deposits within 3 tiles, \(far(spot)) tiles from the town centre"
                      + (now.workers > 0 ? "; your \(now.workers) miners now carry each load about \(Int(now.tiles.rounded())) tiles" : "") + (rock == .gold && me.age == 0 ? "; gold is for archers, knights and the Castle Age" : ""))
            }
        }
        if let bush = w.nearest(.berries, from: home, within: 12), !w.buildings.contains(where: { $0.owner == s && $0.kind == .mill }) {
            build(.mill, brain.spot(.mill, near: bush, w, clearance: false), "by the berry bushes: \(around(bush, .berries, 3)) bushes within reach")
        }
        let fields = w.buildings.filter { $0.owner == s && $0.kind == .farm }, farms = fields.count, empty = fields.filter { $0.farmer == nil }.count
        let berries = (0..<w.amount.count).filter { w.terrain[$0] == .berries }.reduce(0.0) { $0 + w.amount[$1] }
        let mill = w.buildings.first { $0.owner == s && $0.kind == .mill }.map { RTSTile(x: $0.x, y: $0.y) } ?? home
        let gatherers = jobs[0], minutes = gatherers == 0 ? 99 : berries / (Double(gatherers) * 0.85 * 60)
        // A field nobody will work is not offered.
        if empty == 0, berries < 300 || farms < 2 {
            build(.farm, brain.spot(.farm, near: mill, w, clearance: false), "next to the mill: food for one farmer for ever; \(farms) farms now, all worked; the berry bushes have \(Int(berries)) food left"
                  + (berries <= 0 ? ", none: farms are the only food" : minutes < 99 ? ", about \(String(format: "%.1f", minutes)) minutes for your \(gatherers) food gatherers" : ""))
        }
        let forward = RTSTile(x: home.x + (s == 0 ? 4 : -4), y: home.y)
        let threat = theirs.filter { $0.kind != .villager }.count, guards = mine.filter { $0.kind != .villager }.count
        let danger = threat > guards ? "; the enemy has \(threat) soldiers and you have \(guards)" : ""
        for kind in [RTSBuildingKind.barracks, .range, .stable] where !w.buildings.contains(where: { $0.owner == s && $0.kind == kind }) && me.age >= RTSWorld.age(kind) {
            let what = ["", "", "", "", "", "", "to train spearmen, which beat knights", "to train archers, which beat spearmen", "to train knights, which beat archers", ""][kind.rawValue] + danger
            let spot = brain.spot(kind, near: forward, w, clearance: true)
            if w.afford(RTSWorld.cost(kind), s) { build(kind, spot, what) }
            else if let spot { saveFor(kind, spot, "造\(buildingCN[kind.rawValue])（\(priceCN(RTSWorld.cost(kind))))", "a \(buildingWords[kind.rawValue]) \(what)", RTSWorld.cost(kind)) }
        }
        build(.tower, brain.spot(.tower, near: RTSTile(x: forward.x + (s == 0 ? 3 : -3), y: forward.y), w, clearance: true), "in front of the town, facing the enemy: it shoots at raiders")
        if me.age < 2, me.researching == 0, !w.afford(RTSWorld.ageCost[me.age], s) {
            saveFor(nil, nil, "升级到\(RTSWorld.ageNames[me.age + 1])", "the \(["Feudal Age", "Castle Age"][me.age])", RTSWorld.ageCost[me.age])
        }
        if me.age < 2, me.researching == 0, w.afford(RTSWorld.ageCost[me.age], s) {
            out.append(RTSOption(plan: .advance, title: "升级到\(RTSWorld.ageNames[me.age + 1])（\(priceCN(RTSWorld.ageCost[me.age])))",
                                 words: "advance to the \(["Feudal Age", "Castle Age"][me.age]) (\(price(RTSWorld.ageCost[me.age]))): \(Int(RTSWorld.ageTime[me.age])) seconds at the town centre, which trains no villagers meanwhile; unlocks " + (me.age == 0 ? "the archery range and towers" : "the stable and knights")))
        }
        let theirArmy = theirs.filter { $0.kind != .villager }, myArmy = mine.filter { $0.kind != .villager }
        for kind in [RTSUnitKind.spearman, .archer, .knight] {
            guard let yard = w.buildings.first(where: { $0.owner == s && $0.kind == RTSWorld.trainer(kind) && $0.done }), yard.queue.count < 3,
                  room > 0, kind != .knight || me.age >= 2, w.afford(RTSWorld.cost(kind), s) else { continue }
            out.append(RTSOption(plan: .train(kind), title: "训练\(unitCN[kind.rawValue])（\(priceCN(RTSWorld.cost(kind))))",
                                 words: "train a \(unitWords[kind.rawValue]) (\(price(RTSWorld.cost(kind)))), which beats \(["", "knights", "spearmen", "archers"][kind.rawValue]): your soldiers \(army(myArmy)); theirs \(army(theirArmy))"))
        }
        if !myArmy.isEmpty, let theirTC = w.buildings.first(where: { $0.owner != s && $0.kind == .townCenter }) {
            let guards = theirArmy.filter { hypot($0.x - Double(theirTC.x + 1), $0.y - Double(theirTC.y + 1)) < 14 }
            let towers = w.buildings.filter { $0.owner != s && $0.kind == .tower }.count
            let ours = strength(myArmy, against: guards), defence = strength(guards, against: myArmy) + Double(towers + 1) * 900
            out.append(RTSOption(plan: .attack, title: "全军出击（\(myArmy.count) 人）",
                                 words: "send every soldier (\(army(myArmy))) against their town, defended by \(army(guards)), \(towers) towers and the town centre's arrows: your strength about \(Int(ours / 100)), theirs about \(Int(defence / 100))"))
            // Home is offered only to an army that is away.
            let away = myArmy.filter { hypot($0.x - Double(home.x), $0.y - Double(home.y)) > 10 }
            if !away.isEmpty { out.append(RTSOption(plan: .defend, title: "全军回防（\(away.count) 人在外）", words: "bring the \(away.count) soldiers away from home back to guard the town")) }
        }
        out.append(RTSOption(plan: .wait, title: "等一等，攒资源", words: "do nothing new for now and let the stock grow"
                             + (goal != nil ? "; you are saving up for \(goalWords(goal!))" : "")))
        if let goal {
            let price = goalPrice(goal)
            out.removeAll { option in
                guard case .build(let kind, _) = option.plan, kind != .house else { return false }
                let cost = RTSWorld.cost(kind)
                return (0..<4).contains { cost[$0] > 0 && price[$0] > 0 }
            }
        }
        return out
    }

    static func goalPrice(_ plan: RTSPlan) -> [Double] {
        if case .save(let kind, _) = plan { return kind.map(RTSWorld.cost) ?? [0, 0, 0, 0] }
        return [0, 0, 0, 0]
    }
    static func goalWords(_ plan: RTSPlan) -> String {
        if case .save(let kind, _) = plan { return kind.map { "a \(buildingWords[$0.rawValue])" } ?? "the next age" }
        return "something"
    }

    // MARK: The commander's question: which way to lean

    static let postureQuestion = "Which way should this empire lean for the next while?"
    static let postureJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: if enemy soldiers are in your town and stronger than your guard at home, defend. Second: if the words say your army is stronger than what defends their town, attack. Third: if the enemy is a whole age ahead of you, advance to the next age. Fourth: if their army is more than twice as strong as yours, build up the army. Fifth: once you have all the villagers this age wants, advance to the next age; in the last age, build up the army. Otherwise grow the economy."

    /// Two strengths in words, the stronger side named: "your army is more than twice as strong as theirs".
    static func versus(_ a: Double, _ b: Double, _ first: String, _ second: String) -> String {
        if a < 1, b < 1 { return "neither has any strength" }
        let r = b < 1 ? 99 : a / b
        if r >= 2 { return "\(first) is more than twice as strong as \(second)" }
        if r >= 1.15 { return String(format: "%@ is stronger, about %.1f times as strong as %@", first, r, second) }
        if r > 0.87 { return "they are about even" }
        return versus(b, a, second == "theirs" ? "their army" : second, first == "your army" ? "yours" : first)
    }

    /// The leanings Jev or a chat model chooses among, each with what it would do and what bears on it, measured.
    static func postures(_ w: RTSWorld, _ s: Int, current: RTSPosture) -> [RTSOption] {
        guard let tc = w.buildings.first(where: { $0.owner == s && $0.kind == .townCenter }) else { return [] }
        let me = w.players[s], them = w.players[1 - s], home = RTSTile(x: tc.x + 1, y: tc.y + 1)
        let mine = w.units.filter { $0.owner == s }, theirs = w.units.filter { $0.owner != s }
        let myArmy = mine.filter { $0.kind != .villager }, theirArmy = theirs.filter { $0.kind != .villager }
        let villagers = mine.filter { $0.kind == .villager }.count, target = RTSBrain.villagerTarget[me.age], jobs = RTSBrain(owner: s).jobs(w)
        let minute = [0.8, 0.9, 0.75, 0.75].enumerated().map { Int(Double(jobs[$0.offset]) * $0.element * 60 * 0.7) }
        let ageName = ["Dark Age", "Feudal Age", "Castle Age"]
        func near(_ u: RTSUnit) -> Bool { hypot(u.x - Double(home.x), u.y - Double(home.y)) < 14 }
        let people = villagers >= target ? "you have \(villagers) villagers, all the \(ageName[me.age]) wants" : "you have \(villagers) villagers and the \(ageName[me.age]) wants \(target)"
        let armies = "your army: \(army(myArmy)); theirs: \(army(theirArmy)); " + versus(strength(myArmy, against: theirArmy), strength(theirArmy, against: myArmy), "your army", "theirs")
        var out: [RTSOption] = []
        out.append(RTSOption(plan: .posture(.boom), title: "发展经济：村民、农田、营地",
                             words: "grow the economy: everything goes into villagers, farms and camps, and no soldiers are trained; \(people); income about \(minute[0]) food, \(minute[1]) wood, \(minute[2]) gold a minute"))
        let noBarracks = !w.buildings.contains { $0.owner == s && $0.kind == .barracks }
        out.append(RTSOption(plan: .posture(.army), title: "扩军：一直造兵",
                             words: "build up the army: soldiers from every military building, those that beat theirs first, while villagers keep coming"
                             + (noBarracks ? "; there are no barracks yet, so they are built first" : "") + "; \(armies)"))
        let raiders = theirArmy.filter(near), guards = myArmy.filter(near)
        let danger = !raiders.isEmpty && strength(raiders, against: guards) > strength(guards, against: raiders) * 1.15
        if me.age < 2, me.researching == 0 {
            let price = RTSWorld.ageCost[me.age]
            let short = (0..<4).filter { price[$0] > me.stock[$0] }
            let wait = short.map { r in minute[r] > 0 ? (price[r] - me.stock[r]) / Double(minute[r]) * 60 : 999 }.max() ?? 0
            if current == .age, !danger, wait < 150 { return [RTSOption(plan: .posture(.age), title: "升级到\(RTSWorld.ageNames[me.age + 1])", words: "keep saving for the next age")] }
            let cost: String = (0..<4).filter { price[$0] > 0 }.map { "\(Int(price[$0])) \(resourceWords[$0]) (you have \(Int(me.stock[$0])))" }.joined(separator: ", ")
            let when: String = short.isEmpty ? ", affordable now" : wait < 999 ? ", about \(Int(wait.rounded())) seconds of saving" : ", and nobody gathers what is missing"
            let unlocks: String = me.age == 0 ? "archers, towers and 8 more villagers" : "knights and 6 more villagers"
            let rival: String = them.age > me.age ? "; the enemy is a whole age ahead of you, in the \(ageName[them.age])" : them.age == me.age ? "; the enemy is in the same age" : ""
            let words: String = "advance to the \(ageName[me.age + 1]): it costs \(cost)\(when); it unlocks \(unlocks); \(people)\(rival)"
            out.append(RTSOption(plan: .posture(.age), title: "升级到\(RTSWorld.ageNames[me.age + 1])", words: words))
        }
        if myArmy.count >= 3, let theirTC = w.buildings.first(where: { $0.owner != s && $0.kind == .townCenter }) {
            let guards = theirArmy.filter { hypot($0.x - Double(theirTC.x + 1), $0.y - Double(theirTC.y + 1)) < 14 }
            let towers = w.buildings.filter { $0.owner != s && $0.kind == .tower }.count
            let ours = strength(myArmy, against: guards), defence = strength(guards, against: myArmy) + Double(towers + 1) * 900
            let odds = ours >= defence * 1.5 ? "you would very likely win" : ours >= defence * 1.15 ? "you would likely win, with losses"
                : ours > defence * 0.87 ? "a coin toss" : "you would likely lose the army"
            let walls: String = towers == 0 ? "no towers" : "\(towers) tower\(towers == 1 ? "" : "s")"
            out.append(RTSOption(plan: .posture(.attack), title: "进攻（\(myArmy.count) 人）",
                                 words: "attack their town now with \(army(myArmy)): \(odds); what defends it: \(army(guards)), \(walls) and the town centre's arrows; "
                                 + versus(ours, defence, "your army", "what defends their town")))
        }
        // Home is offered only when the raiders there are stronger than whoever guards it: a guard
        // at home that can handle them fights them without being told.
        if danger {
            out.append(RTSOption(plan: .posture(.defend), title: "回防：兵回城、造塔、造兵",
                                 words: "defend at home: every soldier back to the town, towers, and soldiers that beat the raiders; enemy soldiers are in your town: \(army(raiders)); your soldiers at home: \(army(guards)); "
                                 + versus(strength(guards, against: raiders), strength(raiders, against: guards), "your guard at home", "the raiding party")))
        }
        return out
    }

    /// Carry out a plan, if it can still be done.
    static func execute(_ plan: RTSPlan, _ w: inout RTSWorld, _ s: Int, _ brain: inout RTSBrain) {
        guard let tc = w.buildings.first(where: { $0.owner == s && $0.kind == .townCenter }) else { return }
        switch plan {
        case .villager: _ = w.train(.villager, at: tc.id)
        case .focus(let r):
            brain.pending = r.rawValue
            // And a couple from whatever has the most hands.
            let jobs = brain.jobs(w)
            if let rich = (0..<4).max(by: { jobs[$0] < jobs[$1] }), rich != r.rawValue, jobs[rich] >= 4 {
                for v in w.units.filter({ u in
                    guard u.owner == s, u.kind == .villager else { return false }
                    if case .gather(let t) = u.task { return RTSWorld.resource(of: w.terrain[RTSWorld.index(t)])?.rawValue == rich }
                    if case .farm = u.task { return rich == 0 }
                    return false
                }).prefix(2) { w.command(v.id, .idle) }
            }
        case .build(let kind, let spot): brain.order(kind, spot, &w)
        case .save: brain.goal = plan
        case .advance: _ = w.advance(s)
        case .train(let kind):
            if let yard = w.buildings.first(where: { $0.owner == s && $0.kind == RTSWorld.trainer(kind) && $0.done }) { _ = w.train(kind, at: yard.id) }
        case .attack:
            if let theirTC = w.buildings.first(where: { $0.owner != s && $0.kind == .townCenter }) {
                for u in w.units where u.owner == s && u.kind != .villager { w.command(u.id, .attackMove(RTSTile(x: theirTC.x + 1, y: theirTC.y + 1))) }
            }
        case .defend:
            for u in w.units where u.owner == s && u.kind != .villager { w.command(u.id, .attackMove(RTSTile(x: tc.x + (s == 0 ? 4 : -2), y: tc.y + 1))) }
        case .wait: break
        case .posture(let p): brain.posture = p
        }
    }
}
