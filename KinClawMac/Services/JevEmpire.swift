import SwiftUI

/// 帝国 — a small Age of Empires for two, one order a side each round.
///
/// The engine (`JevEmpireEngine.swift`) knows the rules and can fight any
/// battle in advance; this is what a player is told and what the people
/// watching see. The words for a model are the measurements: what an order
/// does to income and population, what it leaves at home, and — for anything
/// that touches the army — how the fight it leads to would come out. Whether
/// now is the time to boom, to age up or to go and burn their town centre is
/// the model's call. A person sees the same orders by short Chinese names.
@MainActor
final class JevEmpire: JevGame {
    let id = "empire", title = "帝国", symbol = "building.columns.fill"
    let rules = "A small Age of Empires for two, one order a side each round of ten seconds: Blue orders, Red orders, then everything happens at once. Villagers gather food (from berry bushes, then from farms, three farmers to a farm), wood, and gold (at full speed only with a mining camp). Every house gives room for 5 more people. Advancing an age takes 3 rounds and makes gathering and soldiers stronger. Spearmen beat knights, archers beat spearmen, knights beat archers. An army marches 5 rounds from one town to the other; there it fights whoever is at home, under the towers and the town centre's arrows, and then burns the town centre. The side whose town centre falls loses; after 100 rounds the stronger empire wins."
    let question = "What should your empire do this round?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: if an enemy army is on its way and the words say your defence would not destroy it, strengthen the defence now — soldiers that beat theirs (spearmen beat knights, archers beat spearmen, knights beat archers), a tower, or your own army brought home. Second: never let the population fill up: with fewer than 3 places left, build a house. Third: grow the economy — keep training villagers until about 18 in the Dark Age, 32 in the Feudal Age and 40 in the Castle Age, for the resource you are shortest of, with fields for every farmer, a lumber camp and a mining camp. Fourth: advance to the next age as soon as you can afford it and are not in danger; saving up for it is worth a round of waiting. Fifth: attack only when the words say your army would win against what defends their town; until then build a mix of soldiers that beats theirs."
    let sides = ["蓝方", "红方"]
    let controls = "点右边的一道命令。每回合蓝方、红方各下一道，然后这十秒一起发生"

    private var world = EmpireWorld()
    private var previous = EmpireWorld()
    private(set) var ticked = Date.distantPast
    private var orders: [EmpireOrder] = []

    var turn: Int { world.mover }
    var over: Bool { world.winner != nil }
    var score: Int { Int(world.score(0) - world.score(1)) }
    var grid: [[JevCell]] { [[JevCell(colour: Color(red: 0.36, green: 0.6, blue: 0.3))]] }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        world = EmpireWorld(); previous = world; ticked = .distantPast; orders = []
    }

    // MARK: Words

    nonisolated private static let jobs = ["food", "wood", "gold"], jobsCN = ["种地", "砍树", "挖金"]
    nonisolated private static let units = ["spearmen", "archers", "knights"], one = ["spearman", "archer", "knight"], unitsCN = ["长枪兵", "弓箭手", "骑士"]
    nonisolated private static let beats = ["knights", "spearmen", "archers"]
    nonisolated private static let buildings = ["a house", "a farm", "a lumber camp", "a mining camp", "barracks", "an archery range", "a stable", "a tower"]
    nonisolated private static let buildingsCN = ["房屋", "农田", "伐木场", "采矿场", "兵营", "靶场", "马厩", "箭塔"]
    nonisolated private static let ages = ["Dark Age", "Feudal Age", "Castle Age", "Imperial Age"]

    private func army(_ a: [Double]) -> String {
        let parts = (0..<3).compactMap { k -> String? in
            let n = Int(a[k].rounded())
            return n <= 0 ? nil : "\(n) \(n == 1 ? Self.one[k] : Self.units[k])"
        }
        return parts.isEmpty ? "no soldiers" : parts.joined(separator: ", ")
    }
    private func armyCN(_ a: [Double]) -> String {
        let parts = (0..<3).compactMap { k -> String? in let n = Int(a[k].rounded()); return n <= 0 ? nil : "\(Self.unitsCN[k]) \(n)" }
        return parts.isEmpty ? "没有兵" : parts.joined(separator: "、")
    }
    private func cost(_ c: EmpireCost) -> String {
        [(c.food, "food"), (c.wood, "wood"), (c.gold, "gold")].filter { $0.0 > 0 }.map { "\(Int($0.0)) \($0.1)" }.joined(separator: ", ")
    }
    private func costCN(_ c: EmpireCost) -> String {
        [(c.food, "食"), (c.wood, "木"), (c.gold, "金")].filter { $0.0 > 0 }.map { "\(Int($0.0)) \($0.1)" }.joined(separator: " ")
    }
    private func rates(_ side: EmpireSide) -> [Double] { let r = side.income(); return [r.food, r.wood, r.gold] }
    private func amount(_ x: Double) -> String { x >= 10 ? "\(Int(x.rounded()))" : String(format: "%.1f", x) }

    var situation: String { words(for: world.mover) }

    private func words(for s: Int) -> String {
        let me = world.sides[s], them = world.sides[1 - s], r = rates(me)
        var parts = ["round \(world.round + 1) of \(EmpireWorld.limit); you are \(s == 0 ? "Blue" : "Red"), in the \(Self.ages[me.age])"
                     + (me.advancing > 0 ? " and advancing to the \(Self.ages[me.age + 1]) (\(me.advancing) rounds left)" : "")]
        parts.append("food \(Int(me.food)) (+\(amount(r[0])) a round), wood \(Int(me.wood)) (+\(amount(r[1]))), gold \(Int(me.gold)) (+\(amount(r[2])))")
        parts.append("\(me.villagers) villagers: \(me.workers[0]) farming (fields for \(me.foodSlots)\(me.idle > 0 ? ", so \(me.idle) stand idle" : "")), \(me.workers[1]) on wood, \(me.workers[2]) on gold")
        parts.append("population \(me.population) of \(me.room)")
        var home = "at home: \(army(me.home))"
        if me.onRoad > 0.05 {
            home += "; your army on the road: \(army(me.field)), " + (me.out >= EmpireWorld.lane ? "at their town"
                : me.heading > 0 ? "\(EmpireWorld.lane - me.out) rounds from their town" : "coming home, \(me.out) rounds away")
        }
        parts.append(home)
        parts.append("your town centre \(Int(me.town)) of \(Int(EmpireWorld.townHP)), \(me.built[EmpireBuilding.tower.rawValue]) towers")
        parts.append("the enemy: \(Self.ages[them.age])\(them.advancing > 0 ? " (advancing)" : ""), \(them.villagers) villagers, at home \(army(them.home)), \(them.built[EmpireBuilding.tower.rawValue]) towers, town centre \(Int(them.town))")
        if let coming = world.threat(to: s), let d = world.defence(of: s) {
            parts.append("their army of \(army(coming.army)) is " + (coming.rounds == 0 ? "at your town" : "marching on you, \(coming.rounds) rounds away")
                         + "; against your defence now it would " + (d.holds ? "be destroyed, and you would lose about \(Int(d.lost.rounded()))"
                                                                    : d.falls ? "win and burn your town centre" : "beat your soldiers"))
        }
        return parts.joined(separator: "; ")
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        let s = world.mover
        orders = world.orders(s)
        return orders.enumerated().map { index, order in
            JevOption(id: String(format: "p%02d", index + 1), label: describe(order, s), merit: world.merit(order, for: s) - Double(index) * 0.001,
                      move: index, title: name(order, s))
        }
    }

    func play(_ option: JevOption) {
        guard orders.indices.contains(option.move), !over else { return }
        previous = world
        world.give(orders[option.move], side: world.mover)
        ticked = Date()
    }

    /// An order, in words: what it does, and — where it touches the army — how the fighting would go.
    private func describe(_ order: EmpireOrder, _ s: Int) -> String {
        let me = world.sides[s], them = world.sides[1 - s]
        let after = world.applying(order, side: s), mine = after.sides[s]
        let before = rates(me), then = rates(mine)
        var text: String
        var touchesDefence = false
        switch order {
        case .villagers(let job):
            let n = mine.villagers - me.villagers, k = job.rawValue
            text = "train \(n) villager\(n == 1 ? "" : "s") to gather \(Self.jobs[k]) (\(cost(EmpireWorld.villager * Double(n)))): \(Self.jobs[k]) income \(amount(before[k])) → \(amount(then[k])) a round; population \(me.population) → \(mine.population) of \(mine.room)"
            if job == .food, mine.workers[0] > mine.foodSlots { text += "; but there are fields for only \(mine.foodSlots) farmers, so \(mine.idle) would stand idle until a farm is built" }
            if job == .gold, !me.has(.miningCamp) { text += " (without a mining camp gold comes in at 40% speed)" }
        case .shift(let from, let to):
            let a = from.rawValue, b = to.rawValue
            text = "move three villagers from \(Self.jobs[a]) to \(Self.jobs[b]): \(Self.jobs[a]) income \(amount(before[a])) → \(amount(then[a])), \(Self.jobs[b]) income \(amount(before[b])) → \(amount(then[b])) a round"
            if to == .food, mine.idle > 0 { text += "; but only \(mine.foodSlots) farmers have fields, so \(mine.idle) would stand idle" }
        case .build(let b):
            let price = cost(EmpireWorld.cost(b))
            switch b {
            case .house: text = "build a house (\(price)): room for 5 more people, population \(me.population) of \(me.room) → of \(mine.room)" + (me.free <= 2 ? " (almost full: nobody more can be trained without it)" : "")
            case .farm: text = "build a farm (\(price)): fields for 3 more farmers; \(me.workers[0]) farming, fields for \(me.foodSlots) → \(mine.foodSlots)" + (me.berries > 0 ? " (the berry bushes have \(Int(me.berries)) food left)" : " (the berry bushes are picked clean)")
            case .lumberCamp: text = "build a lumber camp (\(price)): wood gathering 25% faster, \(amount(before[1])) → \(amount(then[1])) a round"
            case .miningCamp: text = "build a mining camp (\(price)): gold gathered at full speed instead of 40%, \(amount(before[2])) → \(amount(then[2])) a round"
            case .barracks: text = "build barracks (\(price)): lets you train spearmen, which beat knights"
            case .range: text = "build an archery range (\(price)): lets you train archers, which beat spearmen"
            case .stable: text = "build a stable (\(price)): lets you train knights, which beat archers"
            case .tower: text = "build a tower (\(price)): it shoots at any army at your town; \(me.built[b.rawValue]) → \(mine.built[b.rawValue]) towers"; touchesDefence = true
            }
        case .advance:
            let unlocks = ["the archery range and towers", "the stable and its knights", "the strongest soldiers"][me.age]
            text = "advance to the \(Self.ages[me.age + 1]) (\(cost(EmpireWorld.ageCost[me.age]))): it takes 3 rounds, during which the town centre trains no villagers; then gathering is 10% faster and soldiers 15% stronger, and it unlocks \(unlocks)"
        case .train(let u):
            let n = Int((mine.home[u.rawValue] - me.home[u.rawValue]).rounded())
            let price = cost(EmpireWorld.unitCost[u.rawValue] * Double(n))
            text = "train \(n) \(n == 1 ? Self.one[u.rawValue] : Self.units[u.rawValue]) (\(price)), which beat \(Self.beats[u.rawValue]): at home \(army(me.home)) → \(army(mine.home))"
            let theirs = (0..<3).map { them.home[$0] + them.field[$0] }
            text += "; the enemy has \(army(theirs)) in all"
            touchesDefence = true
        case .attack:
            let plan = world.assault(by: s)
            text = "attack with \(army(me.home)): it reaches their town in \(EmpireWorld.lane) rounds; against what defends it now (\(army(them.home)), \(them.built[EmpireBuilding.tower.rawValue]) towers and the town centre's arrows) it would "
            if plan.wins { text += "win, and burn their town centre in about \((plan.rounds ?? 0) + EmpireWorld.lane) rounds" }
            else if plan.left.reduce(0, +) > 0.05 { text += "beat their soldiers, but die under the arrows before the town centre falls" }
            else { text += "be destroyed, killing about \(Int(plan.killed.rounded()))" }
            if world.threat(to: s) != nil { text += "; your own town would be left with no soldiers while their army is coming" }
        case .retreat:
            let there = me.out >= EmpireWorld.lane
            let battle = EmpireWorld.fight(me.field, me.age, them.home, them.age, guns: there ? EmpireWorld.guns(them) : 0)
            let winning = battle.attackers.reduce(0, +) > 0.05 && EmpireWorld.siege(battle.attackers, me.age, town: them.town, guns: EmpireWorld.guns(them)) != nil
            text = "bring your army (\(army(me.field))) home, \(me.out) rounds away; " + (there ? (winning ? "at their town it is winning" : "at their town it is losing") : "it has not reached their town")
            touchesDefence = true
        case .wait:
            let next = [me.food + before[0], me.wood + before[1], me.gold + before[2]]
            text = "wait and save: next round food \(Int(next[0])), wood \(Int(next[1])), gold \(Int(next[2]))"
            if me.age < 3, me.advancing == 0, !me.afford(EmpireWorld.ageCost[me.age]) {
                let c = EmpireWorld.ageCost[me.age]
                text += next[0] >= c.food && next[2] >= c.gold ? "; then you can afford the \(Self.ages[me.age + 1])" : "; the \(Self.ages[me.age + 1]) needs \(cost(c))"
            }
        }
        // For anything that changes the defence: how the army coming at you would fare against it.
        if touchesDefence, let coming = world.threat(to: s), let d = after.defence(of: s) {
            let enemy = "their army (\(army(coming.army)), " + (coming.rounds == 0 ? "at your town)" : "\(coming.rounds) rounds away)")
            text += "; then \(enemy) " + (d.holds ? "would be destroyed by your defence, which would lose about \(Int(d.lost.rounded()))"
                                              : d.falls ? "would still beat your defence and burn your town centre" : "would still beat your defence")
        }
        return text
    }

    /// An order by a short name, for a person to click.
    private func name(_ order: EmpireOrder, _ s: Int) -> String {
        let me = world.sides[s], mine = world.applying(order, side: s).sides[s]
        switch order {
        case .villagers(let job):
            let n = mine.villagers - me.villagers
            return "训练 \(n) 个村民去\(Self.jobsCN[job.rawValue])（\(n * 50) 食）"
        case .shift(let from, let to): return "调 3 个村民：\(Self.jobsCN[from.rawValue]) → \(Self.jobsCN[to.rawValue])"
        case .build(let b): return "造\(Self.buildingsCN[b.rawValue])（\(costCN(EmpireWorld.cost(b)))）"
        case .advance: return "升级到\(EmpireWorld.ageNames[me.age + 1])（\(costCN(EmpireWorld.ageCost[me.age]))）"
        case .train(let u):
            let n = Int((mine.home[u.rawValue] - me.home[u.rawValue]).rounded())
            return "训练 \(n) 个\(Self.unitsCN[u.rawValue])（\(costCN(EmpireWorld.unitCost[u.rawValue] * Double(n)))）"
        case .attack: return "全军出击（\(armyCN(me.home))）"
        case .retreat: return "撤军回家"
        case .wait: return "等一回合，攒资源"
        }
    }

    var status: String {
        if over { return result }
        func brief(_ x: EmpireSide) -> String { "\(EmpireWorld.ageNames[x.age])\(x.advancing > 0 ? "↑" : "") 村民 \(x.villagers) 兵 \(Int((x.atHome + x.onRoad).rounded()))" }
        return "第 \(world.round + 1) / \(EmpireWorld.limit) 回合 · 轮到\(sides[world.mover]) · 蓝方 \(brief(world.sides[0])) · 红方 \(brief(world.sides[1]))"
            + (world.news.last.map { " · " + $0 } ?? "")
    }

    private var result: String {
        guard let winner = world.winner else { return "" }
        if winner == 2 { return "打满 \(EmpireWorld.limit) 回合 · 势均力敌 · 和棋" }
        let loser = 1 - winner
        return world.sides[loser].town <= 0 ? "\(sides[loser])的城镇中心被攻破 · \(sides[winner])赢了（\(world.round) 回合）"
            : "打满 \(EmpireWorld.limit) 回合 · \(sides[winner])国力更强 · \(sides[winner])赢了"
    }

    var position: String { words(for: 0) + "\n(Red's view:) " + words(for: 1) }
}

// MARK: - The picture

extension JevEmpire: JevPainted {
    var aspect: Double { 1.6 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = EmpireScene(before: previous, after: world, t: t, since: since, now: now, result: over ? result : nil)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

/// Two towns and the road between them, from above.
fileprivate struct EmpireScene {
    let before: EmpireWorld, after: EmpireWorld, t: Double, since: Double, now: Double, result: String?
    static let team = [Color(red: 0.18, green: 0.42, blue: 0.95), Color(red: 0.88, green: 0.18, blue: 0.16)]
    static let teamRGB: [Art.RGB] = [(0.2, 0.44, 0.94), (0.86, 0.2, 0.18)]
    static let season = Art.Season(month: 4.2)
    /// A tile's size for the shared drawings, from the picture's unit.
    private func tile(_ unit: CGFloat) -> CGFloat { 15 * unit }
    private func footprint(_ p: CGPoint, _ n: CGFloat, _ S: CGFloat) -> CGRect { CGRect(x: p.x - n * S / 2, y: p.y - n * S / 2, width: n * S, height: n * S) }
    /// Walls and roofs by age: logs and thatch, timber and shingles, stone and slate, marble and gold.
    private func style(_ age: Int) -> (Art.Wall, Art.Roof, Art.RGB, Art.RGB?) {
        switch age {
        case 0: return (.logs, .thatch, (0.8, 0.66, 0.36), nil)
        case 1: return (.plaster, .shingles, (0.68, 0.3, 0.2), nil)
        case 2: return (.stone, .slate, (0.36, 0.4, 0.5), nil)
        default: return (.stone, .slate, (0.88, 0.7, 0.22), (0.95, 0.94, 0.9))
        }
    }
    /// Roofs and walls by age: timber and thatch, tiles, stone, marble and gold.
    static let roofs = [Color(red: 0.55, green: 0.38, blue: 0.2), Color(red: 0.78, green: 0.3, blue: 0.2), Color(red: 0.3, green: 0.38, blue: 0.55), Color(red: 0.85, green: 0.68, blue: 0.2)]
    static let walls = [Color(red: 0.78, green: 0.64, blue: 0.45), Color(red: 0.88, green: 0.82, blue: 0.7), Color(red: 0.72, green: 0.72, blue: 0.74), Color(red: 0.96, green: 0.95, blue: 0.9)]

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let width = size.width, height = size.height
        let S = tile(height / 400)
        Art.ground(&g, size: size, S: S, season: Self.season, visible: CGRect(x: 0, y: 0, width: width / S, height: height / S), tiles: CGSize(width: width / S, height: height / S))
        // The road between the towns: a trodden path.
        let road = roadPath(width, height)
        g.stroke(road, with: .color(Art.c((0.62, 0.52, 0.38))), style: StrokeStyle(lineWidth: height * 0.07, lineCap: .round, lineJoin: .round))
        g.stroke(road, with: .color(Art.c((0.78, 0.67, 0.5))), style: StrokeStyle(lineWidth: height * 0.054, lineCap: .round, lineJoin: .round))
        g.stroke(road, with: .color(Art.c((0.84, 0.74, 0.58), 0.6)), style: StrokeStyle(lineWidth: height * 0.016, lineCap: .round, lineJoin: .round))
        for s in 0..<2 { town(g, s, size) }
        for s in 0..<2 { marching(g, s, size) }
        fights(g, size)
        hud(g, size)
        if let result {
            let parts = result.components(separatedBy: " · ")
            JevDraw.curtain(g, size, title: parts.last ?? result, detail: parts.dropLast().joined(separator: " · "))
        }
    }

    // MARK: Where things are

    /// A point given as fractions of the picture, mirrored for Red.
    private func at(_ s: Int, _ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * CGFloat(s == 0 ? x : 1 - x), y: size.height * CGFloat(y))
    }
    private func roadPoint(_ f: Double, _ size: CGSize) -> CGPoint {
        let x = 0.2 + 0.6 * f
        return CGPoint(x: size.width * CGFloat(x), y: size.height * CGFloat(0.63 + 0.04 * sin(f * .pi * 2)))
    }
    private func roadPath(_ width: CGFloat, _ height: CGFloat) -> Path {
        let size = CGSize(width: width, height: height)
        return Path { p in
            p.move(to: CGPoint(x: width * 0.13, y: height * 0.6))
            for k in 0...40 { p.addLine(to: roadPoint(Double(k) / 40, size)) }
            p.addLine(to: CGPoint(x: width * 0.87, y: height * 0.6))
        }
    }
    static let houseSpots: [(Double, Double)] = [(0.05, 0.42), (0.04, 0.6), (0.1, 0.35), (0.17, 0.35), (0.04, 0.74), (0.1, 0.75), (0.25, 0.24),
                                                 (0.31, 0.24), (0.37, 0.28), (0.16, 0.27), (0.23, 0.3), (0.02, 0.52)]
    static let farmSpots: [(Double, Double)] = [(0.19, 0.76), (0.25, 0.76), (0.31, 0.76), (0.19, 0.88), (0.25, 0.88), (0.31, 0.88), (0.37, 0.88), (0.37, 0.76)]
    static let towerSpots: [(Double, Double)] = [(0.46, 0.5), (0.46, 0.78), (0.43, 0.25), (0.47, 0.92)]

    // MARK: A town

    private func town(_ g: GraphicsContext, _ s: Int, _ size: CGSize) {
        let side = after.sides[s], unit = size.height / 400, colour = Self.team[s], team = Self.teamRGB[s]
        var g = g
        let S = tile(unit)
        let (wall, roof, roofColour, marble) = style(side.age)
        let wallKind: Art.Wall = marble != nil ? .stone : wall
        // Berry bushes while there are berries, and fields in rows, golden once the age is up.
        for (index, spot) in Self.farmSpots.prefix(min(side.built[EmpireBuilding.farm.rawValue], Self.farmSpots.count)).enumerated() {
            let p = at(s, spot.0, spot.1, size)
            field(&g, CGRect(x: p.x - 17 * unit, y: p.y - 11 * unit, width: 34 * unit, height: 22 * unit), S, ripe: side.age >= 2 || index % 3 == 1, team: team)
        }
        // Everything that stands, from the back to the front.
        var standing: [(CGFloat, (inout GraphicsContext) -> Void)] = []
        for tree in 0..<26 {
            let p = at(s, 0.02 + 0.2 * Double(JevDraw.hash(tree, 11 + s) % 1000) / 1000, 0.14 + 0.16 * Double(JevDraw.hash(tree, 13 + s) % 1000) / 1000, size)
            let h = JevDraw.hash(tree, 17 + s)
            let r = unit * CGFloat(9 + h % 6)
            standing.append((p.y + r * 0.8, { g in Art.tree(&g, foot: CGPoint(x: p.x, y: p.y + r * 0.8), S: r * 2.1, grown: 1, variant: h, season: Self.season, conifer: h % 3 != 0, now: self.now) }))
        }
        let mine = at(s, 0.07, 0.9, size)
        for rock in 0..<5 {
            let p = CGPoint(x: mine.x + CGFloat(rock % 3 - 1) * 14 * unit, y: mine.y + CGFloat(rock / 3) * 9 * unit - 4 * unit)
            standing.append((p.y, { g in Art.deposit(&g, .gold, centre: p, S: S * 1.3, left: 1, variant: rock + s * 7, season: Self.season) }))
        }
        if side.berries > 0 {
            for bush in 0..<4 {
                let p = at(s, 0.24 + 0.03 * Double(bush % 2), 0.56 + 0.05 * Double(bush / 2), size)
                standing.append((p.y, { g in Art.deposit(&g, .berries, centre: p, S: S * 1.2, left: 1, variant: bush + s * 5, season: Self.season) }))
            }
        }
        func put(_ p: CGPoint, _ n: CGFloat, _ draw: @escaping (inout GraphicsContext, CGRect) -> Void) {
            let F = footprint(p, n, S)
            standing.append((F.maxY, { g in draw(&g, F) }))
        }
        if side.has(.lumberCamp) { put(at(s, 0.2, 0.22, size), 2) { g, F in Art.shed(&g, F, S: S, pile: .logs, team: team, snow: 0, now: self.now) } }
        if side.has(.miningCamp) { put(at(s, 0.14, 0.87, size), 2) { g, F in Art.shed(&g, F, S: S, pile: .gold, team: team, snow: 0, now: self.now) } }
        for (building, spot, yard) in [(EmpireBuilding.barracks, (0.33, 0.37), Art.Yard.weapons), (.range, (0.33, 0.5), .target), (.stable, (0.4, 0.43), .hay)] where side.has(building) {
            put(at(s, spot.0, spot.1, size), 2.6) { g, F in Art.hall(&g, F, S: S, wall: wallKind, roof: roof, roofColour: roofColour, team: team, yard: yard, snow: 0, now: self.now) }
        }
        for index in 0..<min(side.built[EmpireBuilding.tower.rawValue], Self.towerSpots.count) {
            let spot = Self.towerSpots[index]
            put(at(s, spot.0, spot.1, size), 1) { g, F in Art.tower(&g, F, S: S * 1.2, team: team, snow: 0, now: self.now) }
        }
        for index in 0..<min(side.built[EmpireBuilding.house.rawValue], Self.houseSpots.count) {
            let spot = Self.houseSpots[index]
            put(at(s, spot.0, spot.1, size), 2) { g, F in
                Art.house(&g, F, S: S, wall: wallKind, roof: roof, roofColour: roofColour, trim: team, snow: 0, glow: false, smoke: index % 3 == 0, now: self.now, seed: index + s * 17)
            }
        }
        // The town centre, with a banner, its health and — if it burns — fire.
        let centre = at(s, 0.13, 0.55, size)
        put(CGPoint(x: centre.x, y: centre.y - S * 0.2), 3.4) { g, F in Art.keep(&g, F, S: S, wall: wallKind, roof: roof, roofColour: roofColour, team: team, snow: 0, glow: false, now: self.now) }
        for (_, draw) in standing.sorted(by: { $0.0 < $1.0 }) { draw(&g) }
        if side.town < EmpireWorld.townHP {
            let bar = CGRect(x: centre.x - 30 * unit, y: centre.y - 48 * unit, width: 60 * unit, height: 6 * unit)
            g.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(.black.opacity(0.5)))
            g.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(max(side.town, 0) / EmpireWorld.townHP), height: bar.height), cornerRadius: 3),
                   with: .color(side.town > EmpireWorld.townHP * 0.5 ? .green : side.town > EmpireWorld.townHP * 0.25 ? .yellow : .red))
            if side.town < EmpireWorld.townHP * 0.6 {
                for flame in 0..<3 {
                    let flicker = CGFloat(0.7 + 0.3 * sin(now * 9 + Double(flame) * 2))
                    let p = CGPoint(x: centre.x - 14 * unit + CGFloat(flame) * 14 * unit, y: centre.y - 22 * unit)
                    g.fill(Path(ellipseIn: CGRect(x: p.x - 5 * unit, y: p.y - 12 * unit * flicker, width: 10 * unit, height: 14 * unit * flicker)),
                           with: .linearGradient(Gradient(colors: [.yellow, .orange, Color.red.opacity(0)]), startPoint: CGPoint(x: p.x, y: p.y + 2 * unit), endPoint: CGPoint(x: p.x, y: p.y - 14 * unit)))
                }
            }
        }
        // Villagers at work — or, with raiders at the gates, gone inside.
        let raided = after.sides[1 - s].onRoad > 0.05 && after.sides[1 - s].out >= EmpireWorld.lane
        if raided {
            JevDraw.text(g, "村民躲进了城里", at: CGPoint(x: centre.x, y: centre.y + 36 * unit), size: 11 * unit, weight: .bold)
        } else {
            let places = [at(s, 0.25, 0.8, size), at(s, 0.12, 0.28, size), at(s, 0.09, 0.84, size)]
            let berries = at(s, 0.25, 0.58, size)
            for job in 0..<3 {
                for worker in 0..<min(side.workers[job], 9) {
                    let seed = worker * 7 + job * 31 + s * 101
                    let target = job == 0 && side.berries > 0 && worker < 4 ? berries : places[job]
                    let spread = CGPoint(x: target.x + CGFloat(JevDraw.hash(seed, 1) % 40 - 20) * unit, y: target.y + CGFloat(JevDraw.hash(seed, 2) % 24 - 12) * unit)
                    let phase = (now * 0.09 + Double(JevDraw.hash(seed, 3) % 100) / 100).truncatingRemainder(dividingBy: 1)
                    let leg = phase < 0.5 ? phase * 2 : 2 - phase * 2              // out and back
                    let p = CGPoint(x: JevDraw.mix(Double(centre.x), Double(spread.x), leg), y: JevDraw.mix(Double(centre.y + 10 * unit), Double(spread.y), leg))
                    let carry: Art.Item = phase >= 0.5 ? [Art.Item.food, .logs, .gold][job] : .none
                    Art.person(&g, foot: p, height: 13 * unit, clothes: (0.78, 0.66, 0.48), facing: leg < 1 && phase < 0.5 ? (spread.x >= centre.x ? 1 : -1) : (spread.x >= centre.x ? -1 : 1),
                               walking: true, phase: now * 9 + Double(seed), seed: seed, carry: carry, trim: team)
                }
            }
        }
        // Soldiers at home, drawn up by the barracks.
        var rank = 0
        for kind in 0..<3 {
            let count = Int(side.home[kind].rounded(.up))
            guard count > 0 else { continue }
            let shown = min(count, 8)
            for index in 0..<shown {
                let p = at(s, 0.2 + 0.022 * Double(index % 4), 0.35 + 0.045 * Double(rank + index / 4), size)
                Art.soldier(&g, [Art.Soldier.spearman, .archer, .knight][kind], foot: p, S: S * 1.1, team: team, facing: s == 0 ? 1 : -1, walking: false, working: false, seed: index + kind * 9 + s * 31, now: now)
            }
            if count > shown { JevDraw.text(g, "×\(count)", at: at(s, 0.2 + 0.022 * 4.1, 0.35 + 0.045 * Double(rank), size), size: 9 * unit, weight: .bold) }
            rank += (shown + 3) / 4
        }
    }

    // MARK: Armies on the road, and the fighting

    private func marching(_ g: GraphicsContext, _ s: Int, _ size: CGSize) {
        let then = after.sides[s], was = before.sides[s]
        var army = then.field
        var from = Double(was.out), to = Double(then.out)
        if then.onRoad < 0.05 {
            // Home this round: the last stretch, then into the ranks.
            guard was.onRoad > 0.05, was.heading < 0, t < 1 else { return }
            army = was.field; to = 0
        }
        if was.onRoad < 0.05 { from = 0 }
        let f = JevDraw.mix(from, to, t) / Double(EmpireWorld.lane)
        let centre = roadPoint(s == 0 ? f : 1 - f, size), unit = size.height / 400
        let facing: CGFloat = (then.heading < 0) == (s == 0) ? -1 : 1
        var g = g
        var placed = 0
        var ranks: [(CGPoint, Int)] = []
        for kind in 0..<3 {
            for _ in 0..<min(Int(army[kind].rounded(.up)), 6) {
                ranks.append((CGPoint(x: centre.x - facing * CGFloat(placed / 3) * 13 * unit, y: centre.y + CGFloat(placed % 3 - 1) * 12 * unit), kind))
                placed += 1
            }
        }
        for (k, (p, kind)) in ranks.sorted(by: { $0.0.y < $1.0.y }).enumerated() {
            Art.soldier(&g, [Art.Soldier.spearman, .archer, .knight][kind], foot: p, S: tile(unit) * 1.1, team: Self.teamRGB[s], facing: Double(facing), walking: t < 1, working: false, seed: k + s * 31, now: now)
        }
        let total = Int(army.reduce(0, +).rounded())
        let flag = CGPoint(x: centre.x + facing * 14 * unit, y: centre.y - 26 * unit)
        g.fill(Path(CGRect(x: flag.x, y: flag.y, width: 1.5 * unit, height: 22 * unit)), with: .color(Color(white: 0.3)))
        g.fill(Path(CGRect(x: flag.x, y: flag.y, width: 22 * unit, height: 13 * unit)), with: .color(Self.team[s]))
        JevDraw.text(g, "\(total)", at: CGPoint(x: flag.x + 11 * unit, y: flag.y + 6.5 * unit), size: 9 * unit, weight: .heavy, shadow: false)
    }

    private func fights(_ g: GraphicsContext, _ size: CGSize) {
        guard since < 2.2 else { return }
        let unit = size.height / 400, fade = max(0, 1 - since / 2.2)
        for clash in after.clashes {
            let p: CGPoint
            switch clash.place {
            case .road(let f): p = roadPoint(f, size)
            case .town(let d): p = at(d, 0.22, 0.58, size)
            }
            for spark in 0..<8 {
                let angle = Double(spark) * .pi / 4 + now * 3
                let reach = CGFloat(10 + 8 * sin(now * 12 + Double(spark))) * unit
                g.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x + CGFloat(cos(angle)) * reach * 0.4, y: p.y + CGFloat(sin(angle)) * reach * 0.4))
                    path.addLine(to: CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach))
                }, with: .color(Color(red: 1, green: 0.85, blue: 0.3).opacity(fade)), lineWidth: 2 * unit)
            }
            JevDraw.text(g, "⚔️", at: p, size: 20 * unit, shadow: false)
            for side in 0..<2 where clash.losses[side] >= 0.5 {
                JevDraw.text(g, "−\(Int(clash.losses[side].rounded()))", at: CGPoint(x: p.x + CGFloat(side == 0 ? -26 : 26) * unit, y: p.y - 20 * unit - CGFloat(since) * 12 * unit),
                             size: 14 * unit, colour: Self.team[side].opacity(fade))
            }
        }
    }

    // MARK: The numbers along the top

    private func hud(_ g: GraphicsContext, _ size: CGSize) {
        let unit = size.height / 400
        g.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 40 * unit)), with: .color(.black.opacity(0.45)))
        JevDraw.text(g, "第 \(min(after.round + 1, EmpireWorld.limit)) / \(EmpireWorld.limit) 回合", at: CGPoint(x: size.width / 2, y: 20 * unit), size: 12 * unit, weight: .bold, shadow: false)
        for s in 0..<2 {
            let side = after.sides[s]
            let edge: CGFloat = s == 0 ? 10 * unit : size.width - 10 * unit, anchor: UnitPoint = s == 0 ? .leading : .trailing
            if after.mover == s, after.winner == nil {
                g.fill(Path(roundedRect: CGRect(x: s == 0 ? 2 * unit : size.width * 0.58, y: 2 * unit, width: size.width * 0.4, height: 36 * unit), cornerRadius: 6 * unit),
                       with: .color(Self.team[s].opacity(0.35)))
            }
            JevDraw.text(g, "\(EmpireWorld.names[s]) · \(EmpireWorld.ageNames[side.age])" + (side.advancing > 0 ? " ↑\(side.advancing)" : ""),
                         at: CGPoint(x: edge, y: 12 * unit), size: 11 * unit, weight: .heavy, colour: .white, anchor: anchor, shadow: false)
            let line = "🍖\(Int(side.food))  🪵\(Int(side.wood))  🪙\(Int(side.gold))  👥\(side.population)/\(side.room)  ⚔️\(Int((side.atHome + side.onRoad).rounded()))"
            JevDraw.text(g, line, at: CGPoint(x: edge, y: 29 * unit), size: 10 * unit, weight: .semibold, colour: .white.opacity(0.9), anchor: anchor, shadow: false)
        }
    }

    // MARK: Drawing things

    /// A field in rows, green or ripe, with a low fence in the team's colour.
    private func field(_ g: inout GraphicsContext, _ r: CGRect, _ S: CGFloat, ripe: Bool, team: Art.RGB) {
        let soil: Art.RGB = (0.5, 0.36, 0.22)
        g.fill(Path(roundedRect: r, cornerRadius: S * 0.12), with: .color(Art.c(soil)))
        for row in 0..<4 {
            let y = r.minY + r.height * (CGFloat(row) + 0.5) / 4
            g.stroke(Path { p in p.move(to: CGPoint(x: r.minX + S * 0.1, y: y)); p.addLine(to: CGPoint(x: r.maxX - S * 0.1, y: y)) }, with: .color(Art.c(Art.lit(soil, 0.72))), lineWidth: max(1, S * 0.07))
            for k in 0..<8 {
                let p = CGPoint(x: r.minX + S * 0.15 + (r.width - S * 0.3) * CGFloat(k) / 7, y: y)
                let sway = CGFloat(sin(now * 1.6 + Double(k + row))) * S * 0.03
                g.stroke(Path { path in path.move(to: p); path.addLine(to: CGPoint(x: p.x + sway, y: p.y - S * 0.26)) }, with: .color(Art.c(ripe ? (0.86, 0.72, 0.3) : (0.4, 0.66, 0.28))), lineWidth: max(0.9, S * 0.05))
                if ripe { g.fill(Path(ellipseIn: CGRect(x: p.x + sway - S * 0.035, y: p.y - S * 0.33, width: S * 0.07, height: S * 0.11)), with: .color(Art.c((0.95, 0.8, 0.36)))) }
            }
        }
        g.stroke(Path(roundedRect: r, cornerRadius: S * 0.12), with: .color(Art.c(team, 0.6)), lineWidth: max(1, S * 0.05))
    }
}
