import Foundation

/// 帝国 — a small Age of Empires, played as orders. Foundation only, so that it
/// can be compiled and played on its own.
///
/// Two towns at the ends of one road. Each round is ten seconds of the world:
/// Blue gives an order, Red gives an order, then everything happens at once —
/// villagers gather, armies march a stretch of the road, battles are fought a
/// round's worth. Three resources, four ages, eight kinds of building, three
/// kinds of soldier that beat one another in a circle: spearmen beat knights,
/// archers beat spearmen, knights beat archers. A town centre that falls loses
/// the game; at the time limit the stronger empire wins.
///
/// Nothing is random once the game starts, so a battle can be fought in
/// advance — "if they arrive now, your defence holds and loses about 3" — and
/// that is what the words say. What to do about it is the player's judgment.

enum EmpireJob: Int, CaseIterable { case food, wood, gold }
enum EmpireUnit: Int, CaseIterable { case spear, archer, knight }
enum EmpireBuilding: Int, CaseIterable { case house, farm, lumberCamp, miningCamp, barracks, range, stable, tower }

enum EmpireOrder: Equatable {
    /// Two new villagers from the town centre, sent to a job.
    case villagers(EmpireJob)
    /// Three villagers moved from one job to another.
    case shift(EmpireJob, EmpireJob)
    case build(EmpireBuilding)
    /// The next age: three rounds, during which the town centre trains nobody.
    case advance
    /// A batch of soldiers at home: three spearmen, three archers or two knights.
    case train(EmpireUnit)
    /// Everybody at home marches on the enemy town; `retreat` brings them back.
    case attack, retreat
    case wait
}

struct EmpireCost: Equatable {
    var food = 0.0, wood = 0.0, gold = 0.0
    static func * (c: EmpireCost, n: Double) -> EmpireCost { EmpireCost(food: c.food * n, wood: c.wood * n, gold: c.gold * n) }
    var total: Double { food + wood + gold }
}

struct EmpireSide: Equatable {
    var food = 200.0, wood = 200.0, gold = 100.0
    /// Villagers at each job: food, wood, gold.
    var workers = [3, 0, 0]
    /// How many of each building.
    var built = [Int](repeating: 0, count: EmpireBuilding.allCases.count)
    var age = 0
    /// Rounds left of an age being researched; 0 when none is.
    var advancing = 0
    /// Soldiers of each kind at home and on the road. Fractions are wounds.
    var home = [0.0, 0.0, 0.0], field = [0.0, 0.0, 0.0]
    /// How far down the road the field army is, in rounds of marching: 0 … lane (at the enemy town).
    var out = 0
    /// +1 marching on the enemy, −1 coming home, 0 standing still.
    var heading = 0
    var town = EmpireWorld.townHP
    /// The bushes by the town centre: food for four gatherers until they are picked clean.
    var berries = 800.0
    var gathered = 0.0, killed = 0.0, lost = 0.0

    var villagers: Int { workers.reduce(0, +) }
    var atHome: Double { home.reduce(0, +) }
    var onRoad: Double { field.reduce(0, +) }
    /// Every living soul, a wounded soldier counting whole.
    var population: Int { villagers + Int(ceil(atHome - 0.001)) + Int(ceil(onRoad - 0.001)) }
    var room: Int { min(EmpireWorld.popLimit, 5 + 5 * built[EmpireBuilding.house.rawValue]) }
    var free: Int { room - population }
    var foodSlots: Int { (berries > 0 ? 4 : 0) + 3 * built[EmpireBuilding.farm.rawValue] }
    var strength: Double { 1 + 0.15 * Double(age) }
    func has(_ b: EmpireBuilding) -> Bool { built[b.rawValue] > 0 }
    func afford(_ c: EmpireCost) -> Bool { food >= c.food - 1e-9 && wood >= c.wood - 1e-9 && gold >= c.gold - 1e-9 }
    mutating func pay(_ c: EmpireCost) { food -= c.food; wood -= c.wood; gold -= c.gold }

    /// What a round of gathering brings in.
    func income(besieged: Bool = false) -> (food: Double, wood: Double, gold: Double) {
        guard !besieged else { return (0, 0, 0) }
        let boost = 1 + 0.1 * Double(age)
        let farmers = Double(min(workers[0], foodSlots))
        return (farmers * 3.6 * boost,
                Double(workers[1]) * 3.6 * boost * (has(.lumberCamp) ? 1.25 : 1),
                Double(workers[2]) * 3.4 * boost * (has(.miningCamp) ? 1 : 0.4))
    }
    /// Villagers standing at a job with nothing to do: farmers without a field.
    var idle: Int { max(0, workers[0] - foodSlots) }
    /// What an army is worth, by what it cost.
    func value(_ army: [Double]) -> Double { army.indices.reduce(0) { $0 + army[$1] * EmpireWorld.unitCost[$1].total } }
}

/// A battle fought during the last round, for the picture.
struct EmpireClash: Equatable {
    enum Place: Equatable { case road(Double), town(Int) }
    var place: Place
    var losses: [Double]
}

struct EmpireWorld: Equatable {
    static let lane = 5, limit = 100, popLimit = 100, townHP = 1600.0
    static let villager = EmpireCost(food: 50)
    static let unitCost = [EmpireCost(food: 35, wood: 25), EmpireCost(wood: 25, gold: 45), EmpireCost(food: 60, gold: 75)]
    static let batch = [3, 3, 2]
    static let hp = [50.0, 30.0, 110.0], attack = [4.0, 5.0, 10.0]
    /// Damage multiplier, attacker by row against defender by column: spear, archer, knight.
    static let counter = [[1.0, 0.7, 3.0], [1.5, 1.0, 0.5], [0.6, 2.0, 1.0]]
    /// Damage to a town centre in a round, by a soldier of each kind with no one left to fight.
    static let raze = [22.0, 6.0, 28.0]
    static let ageCost = [EmpireCost(food: 400), EmpireCost(food: 700, gold: 150), EmpireCost(food: 900, gold: 600)]
    /// The age each building needs.
    static let needs: [EmpireBuilding: Int] = [.range: 1, .tower: 1, .stable: 2]
    static let single: Set<EmpireBuilding> = [.lumberCamp, .miningCamp, .barracks, .range, .stable]
    static let maximum: [EmpireBuilding: Int] = [.farm: 20, .tower: 4]
    static func cost(_ b: EmpireBuilding) -> EmpireCost {
        switch b {
        case .house: return EmpireCost(wood: 25)
        case .farm: return EmpireCost(wood: 60)
        case .lumberCamp, .miningCamp: return EmpireCost(wood: 100)
        case .barracks, .range, .stable: return EmpireCost(wood: 175)
        case .tower: return EmpireCost(wood: 150, gold: 50)
        }
    }
    static func trainer(_ u: EmpireUnit) -> EmpireBuilding { [.barracks, .range, .stable][u.rawValue] }

    var sides = [EmpireSide(), EmpireSide()]
    var round = 0
    /// Whose order is next: 0 Blue, then 1 Red; the round is played after Red's.
    var mover = 0
    /// 0 or 1 once somebody has won; 2 for a draw at the time limit.
    var winner: Int?
    var clashes: [EmpireClash] = []
    /// What happened in the last round, in Chinese, for the people watching.
    var news: [String] = []

    // MARK: Orders

    /// What side `s` could order now.
    func orders(_ s: Int) -> [EmpireOrder] {
        let me = sides[s]
        var out: [EmpireOrder] = []
        if me.advancing == 0, me.free >= 1, me.afford(Self.villager) { out += EmpireJob.allCases.map { .villagers($0) } }
        // Moving villagers: from the busiest job to each of the others.
        if let busiest = EmpireJob.allCases.max(by: { me.workers[$0.rawValue] < me.workers[$1.rawValue] }), me.workers[busiest.rawValue] >= 3 {
            for job in EmpireJob.allCases where job != busiest { out.append(.shift(busiest, job)) }
        }
        for b in EmpireBuilding.allCases {
            guard me.age >= Self.needs[b] ?? 0, me.afford(Self.cost(b)) else { continue }
            if Self.single.contains(b), me.has(b) { continue }
            if let most = Self.maximum[b], me.built[b.rawValue] >= most { continue }
            if b == .house, me.room >= Self.popLimit { continue }
            out.append(.build(b))
        }
        if me.age < 3, me.advancing == 0, me.afford(Self.ageCost[me.age]) { out.append(.advance) }
        for u in EmpireUnit.allCases where me.has(Self.trainer(u)) && me.free >= 1 && me.afford(Self.unitCost[u.rawValue]) { out.append(.train(u)) }
        if me.atHome >= 0.5, me.onRoad < 0.05 { out.append(.attack) }          // one army on the road at a time
        if me.onRoad >= 0.05, me.heading >= 0, me.out > 0 { out.append(.retreat) }
        out.append(.wait)
        return out
    }

    /// Carry out one side's order: it takes effect at once; the round is played after both have given theirs.
    mutating func give(_ order: EmpireOrder, side s: Int) {
        carry(order, side: s)
        mover = 1 - mover
        if mover == 0 { play() }
    }

    /// The world right after an order, before the round is played.
    func applying(_ order: EmpireOrder, side s: Int) -> EmpireWorld {
        var copy = self
        copy.carry(order, side: s)
        return copy
    }

    /// What an order does at once.
    private mutating func carry(_ order: EmpireOrder, side s: Int) {
        var me = sides[s]
        switch order {
        case .villagers(let job):
            let n = max(1, min(2, me.free, Int(me.food / 50)))
            me.pay(Self.villager * Double(n)); me.workers[job.rawValue] += n
        case .shift(let from, let to):
            let n = min(3, me.workers[from.rawValue])
            me.workers[from.rawValue] -= n; me.workers[to.rawValue] += n
        case .build(let b):
            me.pay(Self.cost(b)); me.built[b.rawValue] += 1
        case .advance:
            me.pay(Self.ageCost[me.age]); me.advancing = 3
        case .train(let u):
            let each = Self.unitCost[u.rawValue]
            var n = min(Self.batch[u.rawValue], me.free)
            while n > 1, !me.afford(each * Double(n)) { n -= 1 }
            me.pay(each * Double(n)); me.home[u.rawValue] += Double(n)
        case .attack:
            for k in 0..<3 { me.field[k] += me.home[k]; me.home[k] = 0 }
            me.heading = 1
        case .retreat:
            me.heading = -1
        case .wait:
            break
        }
        sides[s] = me
    }

    // MARK: A round of the world

    /// Ten seconds: armies march and fight, villagers gather, ages come.
    mutating func play() {
        clashes = []; news = []
        // Armies march a stretch — unless they are locked in a fight on the road.
        let meeting = sides[0].onRoad > 0.05 && sides[1].onRoad > 0.05 && sides[0].out + sides[1].out >= Self.lane
            && sides[0].out < Self.lane && sides[1].out < Self.lane
        if !meeting {
            for s in 0..<2 {
                var side = sides[s]
                if side.onRoad < 0.05 { side.out = 0; side.heading = 0 }
                else if side.heading > 0, side.out < Self.lane { side.out += 1 }
                else if side.heading < 0 {
                    side.out -= 1
                    if side.out <= 0 {
                        side.out = 0; side.heading = 0
                        for k in 0..<3 { side.home[k] += side.field[k]; side.field[k] = 0 }
                        news.append("\(Self.names[s])的军队回到了家")
                    }
                }
                sides[s] = side
            }
        }
        // Two armies that have met on the road fight there.
        if sides[0].onRoad > 0.05, sides[1].onRoad > 0.05, sides[0].out + sides[1].out >= Self.lane,
           sides[0].out < Self.lane, sides[1].out < Self.lane {
            var blue = sides[0].field, red = sides[1].field
            let lost = Self.clash(&blue, sides[0].age, &red, sides[1].age)
            sides[0].field = blue; sides[1].field = red
            book(0, lost.a, killedBy: 1); book(1, lost.b, killedBy: 0)
            let at = Double(sides[0].out) / Double(Self.lane)
            clashes.append(EmpireClash(place: .road(at), losses: [lost.a.reduce(0, +), lost.b.reduce(0, +)]))
            news.append("两军在路上交战：蓝方损失 \(Int(lost.a.reduce(0, +).rounded())) 人，红方损失 \(Int(lost.b.reduce(0, +).rounded())) 人")
        }
        // An army at the other town fights whoever is at home there, under the towers and the town centre's arrows.
        var besieged = [false, false]
        for s in 0..<2 where sides[s].out >= Self.lane && sides[s].onRoad > 0.05 {
            let d = 1 - s
            besieged[d] = true
            let guns = Self.guns(sides[d])
            var raiders = sides[s].field, guards = sides[d].home
            let lost = Self.clash(&raiders, sides[s].age, &guards, sides[d].age, extraOnA: guns)
            sides[s].field = raiders; sides[d].home = guards
            book(s, lost.a, killedBy: d); book(d, lost.b, killedBy: s)
            var razed = 0.0
            if sides[d].atHome < 0.05 {
                razed = (0..<3).reduce(0) { $0 + sides[s].field[$1] * Self.raze[$1] } * sides[s].strength
                sides[d].town -= razed
            }
            clashes.append(EmpireClash(place: .town(d), losses: [s == 0 ? lost.a.reduce(0, +) : lost.b.reduce(0, +), s == 0 ? lost.b.reduce(0, +) : lost.a.reduce(0, +)]))
            news.append("\(Self.names[s])攻到了\(Self.names[d])城下" + (razed > 0 ? "，城镇中心 −\(Int(razed))" : "，和守军交战"))
        }
        // Gathering, and the berries running out; ages arriving.
        for s in 0..<2 {
            var side = sides[s]
            let income = side.income(besieged: besieged[s])
            let fromBushes = min(side.berries, Double(min(side.workers[0], 4)) * 3.6 * (1 + 0.1 * Double(side.age)))
            if !besieged[s] { side.berries = max(0, side.berries - fromBushes) }
            side.food += income.food; side.wood += income.wood; side.gold += income.gold
            side.gathered += income.food + income.wood + income.gold
            if side.advancing > 0 {
                side.advancing -= 1
                if side.advancing == 0 { side.age += 1; news.append("\(Self.names[s])进入了\(Self.ageNames[side.age])") }
            }
            sides[s] = side
        }
        round += 1
        for s in 0..<2 where sides[s].town <= 0 { sides[s].town = 0; winner = 1 - s }
        if winner == nil, round >= Self.limit {
            let a = score(0), b = score(1)
            winner = abs(a - b) < 0.02 * max(a, b) ? 2 : (a > b ? 0 : 1)
        }
    }

    static let names = ["蓝方", "红方"]
    static let ageNames = ["黑暗时代", "封建时代", "城堡时代", "帝王时代"]

    private mutating func book(_ s: Int, _ losses: [Double], killedBy other: Int) {
        let n = losses.reduce(0, +)
        sides[s].lost += n; sides[other].killed += n
    }

    /// A town's towers and its town centre, shooting at anybody at its gates:
    /// the villagers run inside and add their arrows.
    static func guns(_ side: EmpireSide) -> Double {
        (40 + 4 * Double(min(side.villagers, 15)) + 60 * Double(side.built[EmpireBuilding.tower.rawValue])) * side.strength
    }

    /// One round of fighting: each kind hits the other side's kinds in
    /// proportion to their numbers, harder where it counters them; `extraOnA`
    /// is what towers and a town centre add against side A.
    static func clash(_ a: inout [Double], _ ageA: Int, _ b: inout [Double], _ ageB: Int, extraOnA: Double = 0) -> (a: [Double], b: [Double]) {
        let fa = 1 + 0.15 * Double(ageA), fb = 1 + 0.15 * Double(ageB)
        func hurt(_ by: [Double], _ fBy: Double, _ to: [Double], _ fTo: Double, extra: Double) -> [Double] {
            let total = to.reduce(0, +)
            guard total > 0.001 else { return [0, 0, 0] }
            return (0..<3).map { j in
                guard to[j] > 0.001 else { return 0 }
                let share = to[j] / total
                var damage = extra * share
                for i in 0..<3 where by[i] > 0 { damage += by[i] * attack[i] * 5 * fBy * counter[i][j] * share }
                return min(to[j], damage / (hp[j] * fTo))
            }
        }
        let lostB = hurt(a, fa, b, fb, extra: 0), lostA = hurt(b, fb, a, fa, extra: extraOnA)
        for k in 0..<3 {
            a[k] -= lostA[k]; b[k] -= lostB[k]
            if a[k] < 0.05 { a[k] = 0 }
            if b[k] < 0.05 { b[k] = 0 }
        }
        // Less than half a soldier left is nobody: the rest scatter.
        if a.reduce(0, +) < 0.5 { a = [0, 0, 0] }
        if b.reduce(0, +) < 0.5 { b = [0, 0, 0] }
        return (lostA, lostB)
    }

    /// A battle fought to the end, in advance: what is left of each side, and in how many rounds.
    static func fight(_ attackers: [Double], _ ageA: Int, _ defenders: [Double], _ ageD: Int, guns: Double = 0) -> (attackers: [Double], defenders: [Double], rounds: Int) {
        var a = attackers, d = defenders, rounds = 0
        while a.reduce(0, +) > 0.05, d.reduce(0, +) > 0.05, rounds < 12 {
            _ = clash(&a, ageA, &d, ageD, extraOnA: guns)
            rounds += 1
        }
        return (a, d, rounds)
    }

    /// Raiders with nobody left to fight, under a town's guns: the rounds until
    /// its town centre falls, or nil if they die first (or it takes too long).
    static func siege(_ raiders: [Double], _ age: Int, town: Double, guns: Double) -> Int? {
        var a = raiders, left = town
        for round in 1...20 {
            left -= (0..<3).reduce(0) { $0 + a[$1] * raze[$1] } * (1 + 0.15 * Double(age))
            if left <= 0 { return round }
            var nobody = [0.0, 0.0, 0.0]
            _ = clash(&a, age, &nobody, 0, extraOnA: guns)
            if a.reduce(0, +) <= 0.05 { return nil }
        }
        return nil
    }

    /// Everything an empire is, in one number: for the time limit.
    func score(_ s: Int) -> Double {
        let side = sides[s]
        let buildings = EmpireBuilding.allCases.reduce(0.0) { $0 + Double(side.built[$1.rawValue]) * Self.cost($1).total }
        return Double(side.villagers) * 60 + side.value(side.home) + side.value(side.field) + buildings
            + 900 * Double(side.age) + side.town * 0.5 + side.killed * 40
    }
}

// MARK: - Judging: the predictions the words give, and the evaluator that plays

extension EmpireWorld {
    /// The other side's army on its way here or already at the gates: what it is and how many rounds off.
    func threat(to s: Int) -> (army: [Double], rounds: Int)? {
        let them = sides[1 - s]
        guard them.onRoad > 0.05, them.heading > 0 || them.out >= Self.lane else { return nil }
        return (them.field, max(0, Self.lane - them.out))
    }

    /// If that army came against what defends this town now: whether every raider
    /// falls, what the defence loses, and whether the town centre would fall.
    func defence(of s: Int) -> (holds: Bool, lost: Double, raidersLeft: Double, falls: Bool)? {
        guard let coming = threat(to: s) else { return nil }
        let me = sides[s], them = sides[1 - s]
        let battle = Self.fight(coming.army, them.age, me.home, me.age, guns: Self.guns(me))
        let raiders = battle.attackers.reduce(0, +)
        let falls = raiders > 0.05 && Self.siege(battle.attackers, them.age, town: me.town, guns: Self.guns(me)) != nil
        return (raiders <= 0.05, me.atHome - battle.defenders.reduce(0, +), raiders, falls)
    }

    /// If everybody at home marched on the other town now, against what defends it now.
    func assault(by s: Int) -> (wins: Bool, left: [Double], killed: Double, rounds: Int?) {
        let me = sides[s], them = sides[1 - s]
        let battle = Self.fight(me.home, me.age, them.home, them.age, guns: Self.guns(them))
        let left = battle.attackers
        let rounds = left.reduce(0, +) > 0.05 ? Self.siege(left, me.age, town: them.town, guns: Self.guns(them)) : nil
        return (rounds != nil, left, them.atHome - battle.defenders.reduce(0, +), rounds)
    }

    /// The share of villagers an empire wants at each job, by age.
    static let shares: [[Double]] = [[0.62, 0.38, 0], [0.45, 0.35, 0.2], [0.4, 0.3, 0.3], [0.36, 0.28, 0.36]]
    static let villagerTarget = [18, 32, 40, 46]

    /// The evaluator: what a sensible player makes of an order, in points. It
    /// does not look ahead; it knows what matters when.
    func merit(_ order: EmpireOrder, for s: Int) -> Double {
        let me = sides[s], them = sides[1 - s]
        let after = applying(order, side: s)
        let target = Self.villagerTarget[me.age], want = Self.shares[me.age]
        func share(_ side: EmpireSide, _ job: Int) -> Double { side.villagers == 0 ? 0 : Double(side.workers[job]) / Double(side.villagers) }

        // Danger first: an army coming, and whether this order makes the defence hold.
        if let before = defence(of: s), let then = after.defence(of: s) {
            if !before.holds, then.holds { return 200 }
            if !before.holds {
                let better = before.raidersLeft - then.raidersLeft
                if better > 0.3 { return 120 + better * 10 }
                if order == .retreat, me.onRoad > 0.05 { return 110 }             // bring the army home to defend
            }
        }
        // An army at their gates that is losing comes home; one that is winning stays.
        if me.onRoad > 0.05 {
            let there = me.out >= Self.lane
            let battle = Self.fight(me.field, me.age, them.home, them.age, guns: there ? Self.guns(them) : 0)
            let winning = battle.attackers.reduce(0, +) > 0.05 && Self.siege(battle.attackers, me.age, town: them.town, guns: Self.guns(them)) != nil
            if order == .retreat { return winning ? -50 : 90 }
        }
        var points = 1.0
        switch order {
        case .attack:
            let plan = assault(by: s)
            let army = me.atHome
            if plan.wins, army >= 6 { points = 95 + (plan.rounds.map { Double(20 - $0) } ?? 0) }
            else if plan.wins { points = 40 }
            else { points = -40 + plan.killed * 3 }
            if defence(of: s) != nil { points -= 60 }                              // not while they are coming
        case .build(.house):
            points = me.free <= 2 ? 90 : me.free <= 5 ? 35 : me.free > 10 ? -20 : 8
        case .villagers(let job):
            guard me.villagers < target else { points = -10; break }
            if job == .food, me.workers[0] >= me.foodSlots { points = 5; break }        // a farm first
            if job == .gold, !me.has(.miningCamp), me.age == 0 { points = -5; break }
            points = 50 + 60 * max(0, want[job.rawValue] - share(me, job.rawValue))
        case .shift(let from, let to):
            let over = share(me, from.rawValue) - want[from.rawValue], under = want[to.rawValue] - share(me, to.rawValue)
            points = (over > 0.15 && under > 0.15) ? 30 : (to == .food && me.idle > 0) ? -30 : -8
            if from == .food, me.idle >= 3 { points = 45 }
        case .build(.farm):
            // Fields for the farmers there are and for those about to come.
            points = me.workers[0] >= me.foodSlots ? 70 : me.workers[0] >= me.foodSlots - 1 || (me.berries < 250 && me.built[EmpireBuilding.farm.rawValue] < 2) ? 52
                : share(me, 0) < want[0] - 0.1 && me.villagers < target ? 40 : -5
        case .build(.lumberCamp):
            points = me.workers[1] >= 3 ? 55 : 5
        case .build(.miningCamp):
            points = me.age >= 1 || me.workers[2] > 0 ? 50 : 2
        case .build(.barracks):
            points = me.villagers >= 10 ? 45 : 5
        case .build(.range), .build(.stable):
            points = me.villagers >= 14 ? 58 : 20
        case .build(.tower):
            points = defence(of: s) != nil ? 40 : me.built[EmpireBuilding.tower.rawValue] == 0 && me.age >= 1 ? 12 : 3
        case .advance:
            points = me.villagers >= target * 7 / 10 && defence(of: s) == nil ? 85 : 20
        case .train(let unit):
            // Soldiers that beat what the other side has, and enough of them.
            let theirs = them.home.indices.map { them.home[$0] + them.field[$0] }
            let total = theirs.reduce(0, +)
            let edge = total > 0.05 ? (0..<3).reduce(0.0) { $0 + theirs[$1] / total * (Self.counter[unit.rawValue][$1] - 1) } : 0
            let mineValue = me.value(me.home) + me.value(me.field), theirValue = them.value(them.home) + them.value(them.field)
            let behind = mineValue < 0.85 * theirValue
            let soldiers = me.atHome + me.onRoad
            // Enough soldiers, and not so many that the economy stops growing: a mix, led by what counters theirs.
            points = (behind ? 55 : me.age >= 1 && me.villagers >= target * 7 / 10 ? 36 : 12) + 14 * edge
            if soldiers > Double(me.villagers) * 0.9 { points -= 30 }
            if me.age == 0, !behind, soldiers >= 6 { points -= 25 }              // the Dark Age is for the economy
            let kinds = (0..<3).map { me.home[$0] + me.field[$0] }
            if soldiers > 3, kinds[unit.rawValue] / soldiers > 0.6 { points -= 10 }
            // Saving for the next age: soldiers wait, unless they are needed.
            if me.age < 3, me.advancing == 0, !behind, defence(of: s) == nil {
                let next = Self.ageCost[me.age], cost = Self.unitCost[unit.rawValue]
                if (cost.gold > 0 && next.gold > 0 && me.gold < next.gold + cost.gold * 3) || (cost.food > 0 && me.food < next.food && me.food >= next.food * 0.5) { points -= 22 }
            }
        case .retreat:
            points = -20
        case .wait:
            // Saving for the next age, when it is near.
            let next = me.age < 3 ? Self.ageCost[me.age] : EmpireCost()
            let near = me.food >= next.food * 0.7 && me.gold >= next.gold * 0.7
            points = me.advancing == 0 && me.age < 3 && !me.afford(next) && near && me.villagers >= target * 7 / 10 ? 42 : 0
        }
        return points
    }
}
