import SwiftUI
import CoreText

/// 冰河三国 — a frozen city of the Three Kingdoms, kept alive around a great
/// furnace, one decision a day for a hundred days.
///
/// The cold comes down day by day, with cold snaps and one great blizzard.
/// The furnace burns coal; its level sets how far its heat reaches and how
/// warm it keeps the houses inside the circle. Whoever lives outside it, or
/// has no house, falls sick in the cold, and the sick can die. Everybody eats.
/// Citizens work the mines, the sawmill, the hunting lodge and the greenhouse
/// by themselves; morale (民心) makes them work faster or slower, and decides
/// whether newcomers settle. Generals recruited at the tavern lead expeditions
/// onto the snowy map, where bandits, wolves, ice raiders and the rival lords
/// of 魏 and 吴 hold the counties, and can govern a building at home.
///
/// Each day is one question. The program lists the sensible decisions and
/// measures each one by playing the city forward — who falls sick, when the
/// coal or the food runs out, how a battle is likely to go — and says so in
/// words, the verdict first. Which of it matters most is the player's call.

// MARK: - What the city is made of

fileprivate enum IceKind: Int, CaseIterable {
    case furnace, house, sawmill, coal, hunting, greenhouse, iron, clinic, barracks, tavern, wall

    var cn: String { ["熔炉", "民居", "伐木场", "煤矿", "猎场", "温室", "铁矿", "医馆", "兵营", "酒馆", "城墙"][rawValue] }
    var en: String { ["the furnace", "a house", "the sawmill", "the coal mine", "the hunting lodge", "the greenhouse", "the iron mine", "the clinic", "the barracks", "the tavern", "the wall"][rawValue] }
    /// The highest level; for houses, the most there is room for around the furnace.
    var top: Int { [5, 24, 4, 4, 4, 4, 4, 3, 3, 3, 3][rawValue] }
    /// Jobs a level of it gives.
    var jobs: Int {
        switch self {
        case .sawmill, .coal, .hunting: return 5
        case .greenhouse, .iron: return 4
        default: return 0
        }
    }
    static let producers: [IceKind] = [.coal, .greenhouse, .hunting, .sawmill, .iron]
}

fileprivate enum IceSkill { case brawler, charge, peerless, planner, healer, charm, saint, fire, ruler, balance, veteran, cavalry }

/// A general: what they are good at, what they cost, and how they look.
fileprivate struct IceHero {
    let name: String, war: Int, wit: Int, lead: Int
    let skill: IceSkill
    let food: Int, iron: Int
    let skillCN: String, skillEN: String
    let coat: Art.RGB, fur: Art.RGB, accent: Art.RGB, hair: Art.RGB
    /// 0 plain, 1 pheasant feathers, 2 feather fan, 3 long beard, 4 flower, 5 helmet crest, 6 bushy beard, 7 white beard, 8 crown
    let mark: Int
    let skin: Art.RGB
}

fileprivate let iceHeroes: [IceHero] = [
    IceHero(name: "张飞", war: 98, wit: 40, lead: 80, skill: .brawler, food: 0, iron: 0, skillCN: "万人敌", skillEN: "+40% battle power against bandits, wolves and ice raiders",
            coat: (0.22, 0.22, 0.28), fur: (0.42, 0.3, 0.2), accent: (0.8, 0.2, 0.16), hair: (0.08, 0.07, 0.07), mark: 6, skin: (0.86, 0.68, 0.54)),
    IceHero(name: "赵云", war: 92, wit: 70, lead: 88, skill: .charge, food: 90, iron: 50, skillCN: "七进七出", skillEN: "a brave charge: +25% battle power",
            coat: (0.93, 0.95, 0.98), fur: (0.99, 0.99, 1), accent: (0.66, 0.72, 0.8), hair: (0.1, 0.09, 0.1), mark: 5, skin: (0.98, 0.84, 0.72)),
    IceHero(name: "吕布", war: 100, wit: 30, lead: 80, skill: .peerless, food: 120, iron: 80, skillCN: "天下无双", skillEN: "unmatched in battle: +45% battle power, but morale falls 1 a day while he stays",
            coat: (0.72, 0.1, 0.12), fur: (0.14, 0.11, 0.12), accent: (0.95, 0.75, 0.25), hair: (0.1, 0.08, 0.08), mark: 1, skin: (0.95, 0.8, 0.66)),
    IceHero(name: "诸葛亮", war: 30, wit: 100, lead: 95, skill: .planner, food: 110, iron: 60, skillCN: "神机妙算", skillEN: "plans: +15% battle power, and governs a building 20% better than others",
            coat: (0.93, 0.92, 0.86), fur: (0.86, 0.87, 0.9), accent: (0.3, 0.46, 0.72), hair: (0.12, 0.1, 0.1), mark: 2, skin: (0.98, 0.86, 0.74)),
    IceHero(name: "华佗", war: 20, wit: 85, lead: 30, skill: .healer, food: 60, iron: 20, skillCN: "青囊", skillEN: "a healer: cures 5 sick a day, 15 when he governs the clinic",
            coat: (0.42, 0.62, 0.44), fur: (0.84, 0.78, 0.66), accent: (0.72, 0.5, 0.26), hair: (0.9, 0.9, 0.9), mark: 7, skin: (0.95, 0.8, 0.66)),
    IceHero(name: "貂蝉", war: 40, wit: 80, lead: 50, skill: .charm, food: 60, iron: 20, skillCN: "闭月", skillEN: "beloved: morale +1 a day while she stays",
            coat: (0.96, 0.62, 0.72), fur: (1, 0.97, 0.98), accent: (0.9, 0.3, 0.45), hair: (0.12, 0.08, 0.1), mark: 4, skin: (1, 0.87, 0.8)),
    IceHero(name: "关羽", war: 97, wit: 75, lead: 95, skill: .saint, food: 100, iron: 60, skillCN: "武圣", skillEN: "+30% battle power",
            coat: (0.2, 0.5, 0.32), fur: (0.9, 0.86, 0.78), accent: (0.85, 0.7, 0.3), hair: (0.08, 0.07, 0.07), mark: 3, skin: (0.86, 0.36, 0.3)),
    IceHero(name: "周瑜", war: 70, wit: 96, lead: 92, skill: .fire, food: 100, iron: 50, skillCN: "火攻", skillEN: "fire: +35% battle power against Wei and Wu, and governing the furnace it burns 25% less coal",
            coat: (0.86, 0.36, 0.2), fur: (0.98, 0.93, 0.84), accent: (0.98, 0.78, 0.3), hair: (0.12, 0.08, 0.06), mark: 0, skin: (0.99, 0.86, 0.74)),
    IceHero(name: "曹操", war: 72, wit: 92, lead: 98, skill: .ruler, food: 120, iron: 70, skillCN: "挟令", skillEN: "a ruler: +10% battle power, a county he takes gives half again as many people, and he governs 10% better",
            coat: (0.28, 0.26, 0.5), fur: (0.16, 0.15, 0.18), accent: (0.9, 0.76, 0.3), hair: (0.1, 0.09, 0.1), mark: 8, skin: (0.95, 0.8, 0.68)),
    IceHero(name: "孙权", war: 65, wit: 82, lead: 88, skill: .balance, food: 80, iron: 40, skillCN: "制衡", skillEN: "balance: morale +0.5 a day, and he governs 10% better",
            coat: (0.78, 0.22, 0.24), fur: (0.95, 0.9, 0.84), accent: (0.55, 0.3, 0.7), hair: (0.36, 0.2, 0.3), mark: 6, skin: (0.97, 0.82, 0.7)),
    IceHero(name: "黄忠", war: 93, wit: 60, lead: 82, skill: .veteran, food: 80, iron: 40, skillCN: "老当益壮", skillEN: "a veteran: +10% battle power and no cold penalty",
            coat: (0.76, 0.56, 0.26), fur: (0.7, 0.62, 0.52), accent: (0.5, 0.3, 0.16), hair: (0.92, 0.92, 0.92), mark: 7, skin: (0.93, 0.76, 0.62)),
    IceHero(name: "马超", war: 96, wit: 50, lead: 80, skill: .cavalry, food: 90, iron: 50, skillCN: "西凉铁骑", skillEN: "cavalry: +15% battle power and marches 1 day faster each way",
            coat: (0.86, 0.87, 0.92), fur: (0.96, 0.96, 0.98), accent: (0.2, 0.42, 0.74), hair: (0.14, 0.1, 0.08), mark: 5, skin: (0.98, 0.84, 0.72)),
]

/// A county on the map: where it sits, who holds it at first, what it gives.
fileprivate struct IceCounty {
    let name: String, x: Double, y: Double
    /// 0 bandits, 1 wolves, 2 ice raiders, 3 Wei, 4 Wu; the owner at the start follows.
    let foe: Int
    let low: Int, high: Int
    /// 0 coal, 1 wood, 2 food, 3 iron.
    let resource: Int, amount: Double
    let people: Int
    let capital: Bool
}

fileprivate let iceCounties: [IceCounty] = [
    IceCounty(name: "成都", x: 0.13, y: 0.6, foe: -1, low: 0, high: 0, resource: 0, amount: 0, people: 0, capital: true),
    IceCounty(name: "梓潼", x: 0.27, y: 0.42, foe: 0, low: 24, high: 32, resource: 1, amount: 8, people: 8, capital: false),
    IceCounty(name: "江州", x: 0.31, y: 0.7, foe: 0, low: 26, high: 34, resource: 2, amount: 8, people: 9, capital: false),
    IceCounty(name: "南中", x: 0.14, y: 0.88, foe: 1, low: 30, high: 40, resource: 3, amount: 4, people: 6, capital: false),
    IceCounty(name: "武都", x: 0.11, y: 0.26, foe: 1, low: 30, high: 40, resource: 0, amount: 6, people: 6, capital: false),
    IceCounty(name: "汉中", x: 0.31, y: 0.13, foe: 2, low: 50, high: 64, resource: 3, amount: 6, people: 10, capital: false),
    IceCounty(name: "永安", x: 0.47, y: 0.53, foe: 0, low: 40, high: 52, resource: 0, amount: 7, people: 8, capital: false),
    IceCounty(name: "武陵", x: 0.45, y: 0.85, foe: 1, low: 44, high: 58, resource: 2, amount: 9, people: 8, capital: false),
    IceCounty(name: "襄阳", x: 0.62, y: 0.35, foe: 2, low: 66, high: 84, resource: 1, amount: 10, people: 12, capital: false),
    IceCounty(name: "长安", x: 0.55, y: 0.1, foe: 3, low: 80, high: 96, resource: 3, amount: 8, people: 12, capital: false),
    IceCounty(name: "宛城", x: 0.77, y: 0.2, foe: 3, low: 80, high: 96, resource: 2, amount: 10, people: 12, capital: false),
    IceCounty(name: "许昌", x: 0.91, y: 0.08, foe: 3, low: 150, high: 170, resource: 0, amount: 12, people: 20, capital: true),
    IceCounty(name: "江陵", x: 0.66, y: 0.64, foe: 4, low: 80, high: 96, resource: 1, amount: 10, people: 12, capital: false),
    IceCounty(name: "长沙", x: 0.68, y: 0.9, foe: 4, low: 76, high: 92, resource: 2, amount: 10, people: 12, capital: false),
    IceCounty(name: "建业", x: 0.91, y: 0.72, foe: 4, low: 150, high: 170, resource: 3, amount: 10, people: 20, capital: true),
]

fileprivate let iceRoads: [(Int, Int)] = [
    (0, 1), (0, 2), (0, 3), (0, 4), (1, 4), (1, 5), (1, 6), (2, 3), (2, 6), (2, 7), (4, 5), (5, 9),
    (6, 8), (6, 12), (6, 7), (7, 13), (8, 9), (8, 10), (8, 12), (9, 10), (9, 11), (10, 11), (12, 13), (12, 14), (13, 14),
]

fileprivate let iceNeighbours: [[Int]] = {
    var out = Array(repeating: [Int](), count: iceCounties.count)
    for (a, b) in iceRoads { out[a].append(b); out[b].append(a) }
    return out
}()

/// Owners: 0 is us (蜀), 1 魏, 2 吴, 3 nobody's (bandits, wolves, raiders).
fileprivate let iceOwnerCN = ["蜀", "魏", "吴", "野"]
fileprivate let iceFoeEN = ["bandits", "wolves", "ice raiders", "Wei", "Wu"]
fileprivate let iceFoeCN = ["山贼", "狼群", "冰原掠夺者", "魏军", "吴军"]
fileprivate let iceResEN = ["coal", "wood", "food", "iron"]
fileprivate let iceResCN = ["煤", "木", "粮", "铁"]

/// An army on its way to a county and back.
fileprivate struct IceMarch {
    var county: Int, hero: Int, soldiers: Int
    var travel: Int, left: Int
    var back = false
    var won: Bool? = nil
    var wounded = 0
    /// In a look ahead, the outcome to assume instead of the dice.
    var forced: Bool? = nil
    var began: Int
}

/// A battle fought: for the news and the picture.
fileprivate struct IceReport {
    var county: Int, hero: Int, won: Bool, killed: Int, wounded: Int, day: Int, people: Int
}

fileprivate struct IceRival {
    var reserve: Double
    var period: Int, offset: Int
    var nextRaid: Int
}

fileprivate struct IceEvent {
    var kind: Int, amount: Int, left: Int, arrived: Int
}

fileprivate struct IceGeneral {
    var hero: Int
    var governs: IceKind? = nil
    var away = false
}

/// What happened on a day, counted as it goes: what a look ahead reads.
fileprivate struct IceTally {
    var sickened = 0, coldDeaths = 0, hungerDeaths = 0, sickDeaths = 0, arrived = 0, left = 0
    var hungryDays = 0, coalOutDays = 0, firstCoalOut: Int? = nil, firstFoodOut: Int? = nil
    var raidsLost = 0, raidsHeld = 0
    var deaths: Int { coldDeaths + hungerDeaths + sickDeaths }
}

fileprivate struct IceStock {
    var coal = 0.0, wood = 0.0, food = 0.0, iron = 0.0
    subscript(_ r: Int) -> Double {
        get { [coal, wood, food, iron][r] }
        set { switch r { case 0: coal = newValue; case 1: wood = newValue; case 2: food = newValue; default: iron = newValue } }
    }
}

// MARK: - The world, and a day of it

fileprivate struct IceWorld {
    static let days = 100
    static let reach = [0, 7, 11, 15, 20, 24]
    static let power: [Double] = [0, 24, 30, 36, 43, 50]
    static let burn: [Double] = [0, 10, 18, 28, 38, 48]
    static let blizzardDrop = 26.0, blizzardLength = 7
    static let outLimit = 5

    var day = 1
    var stock = IceStock(coal: 100, wood: 150, food: 170, iron: 30)
    var citizens = 32, sick = 0
    var soldiers = 36, wounded = 0
    /// People of a conquered county, moving in as warm houses free up.
    var waiting = 0
    var morale = 60.0
    var level: [Int] = [1, 7, 1, 1, 1, 0, 0, 0, 1, 0, 0]
    var generals: [IceGeneral] = [IceGeneral(hero: 0)]
    var offered: [Int] = []
    var pool: [Int] = []
    var owner: [Int] = []
    var garrison: [Double] = []
    var marches: [IceMarch] = []
    var rivals: [IceRival] = []
    var event: IceEvent? = nil
    var nextEvent = 4
    var overdrive = 0
    var outDays = 0
    var huntBad = 0
    var snaps: [(start: Int, end: Int, drop: Double)] = []
    var blizzard = (start: 64, end: 70)
    var salt = 0
    var dice = JevDice(seed: 1)
    var tally = IceTally()
    /// Today's news, in Chinese, and the battles fought: for the picture.
    var news: [String] = []
    var reports: [IceReport] = []
    /// A building raised or improved today, for the picture to raise it.
    var raised: IceKind? = nil
    var ended: String? = nil
    var peakPopulation = 32
    /// In a look ahead: battles go as `forced` says, and nothing is news.
    var imagined = false

    init(seed: UInt64) {
        dice = JevDice(seed: seed)
        salt = dice.below(1000)
        snaps = []
        for (first, spread) in [(12, 5), (27, 6), (42, 6), (84, 6)] {
            let start = first + dice.below(spread)
            let end = start + 2 + dice.below(2)
            snaps.append((start, end, Double(9 + dice.below(5))))
        }
        let b = 62 + dice.below(7)
        blizzard = (b, b + Self.blizzardLength - 1)
        owner = iceCounties.enumerated().map { i, c in i == 0 ? 0 : c.foe == 3 ? 1 : c.foe == 4 ? 2 : 3 }
        garrison = []
        for c in iceCounties { garrison.append(c.high > 0 ? Double(c.low + dice.below(c.high - c.low + 1)) : 0) }
        var rest = Array(1..<iceHeroes.count)
        for i in stride(from: rest.count - 1, to: 0, by: -1) { rest.swapAt(i, dice.below(i + 1)) }
        offered = Array(rest.prefix(2)); pool = Array(rest.dropFirst(2))
        rivals = [IceRival(reserve: 50, period: 6, offset: dice.below(6), nextRaid: 30 + dice.below(8)),
                  IceRival(reserve: 50, period: 7, offset: dice.below(7), nextRaid: 34 + dice.below(8))]
        nextEvent = 3 + dice.below(3)
    }

    // MARK: Weather

    func temperature(_ d: Int) -> Double {
        var t = -8 - 0.26 * Double(d) + Double(JevDraw.hash(d, salt) % 5) - 2
        for s in snaps where d >= s.start && d <= s.end { t -= s.drop }
        if d >= blizzard.start && d <= blizzard.end { t -= Self.blizzardDrop }
        if d > blizzard.end && d <= blizzard.end + 6 { t += 3 }
        return t
    }
    func inBlizzard(_ d: Int) -> Bool { d >= blizzard.start && d <= blizzard.end }
    /// The next cold spell that has not ended: a snap or the blizzard.
    func nextCold(after d: Int) -> (start: Int, end: Int, blizzard: Bool)? {
        var spells = snaps.map { (start: $0.start, end: $0.end, blizzard: false) }
        spells.append((blizzard.start, blizzard.end, true))
        return spells.filter { $0.end >= d }.min { $0.start < $1.start }
    }

    // MARK: Heat

    var furnace: Int { level[IceKind.furnace.rawValue] }
    var houses: Int { level[IceKind.house.rawValue] }
    var wall: Int { level[IceKind.wall.rawValue] }
    var warmHouses: Int { min(houses, Self.reach[furnace]) }
    var room: Int { houses * 5 }
    var warmRoom: Int { warmHouses * 5 }
    func has(_ k: IceKind) -> Bool { level[k.rawValue] > 0 }
    func governor(_ k: IceKind) -> Int? { generals.first { $0.governs == k && !$0.away }?.hero }
    func serving(_ skill: IceSkill) -> Bool { generals.contains { iceHeroes[$0.hero].skill == skill } }
    func home(_ skill: IceSkill) -> Bool { generals.contains { iceHeroes[$0.hero].skill == skill && !$0.away } }

    /// Coal the furnace burns a day, as things are: more for a bigger fire, and more for every house it keeps warm.
    var burnRate: Double {
        (Self.burn[furnace] + 0.5 * Double(warmHouses)) * (overdrive > 0 ? 2 : 1) * (governor(.furnace).map { iceHeroes[$0].skill == .fire } == true ? 0.75 : 1)
    }
    func wallBonus(_ d: Int) -> Double { Double(wall) * (inBlizzard(d) ? 7 : 2) }
    /// How warm it is in a warm house, a cold one, and out in the snow, on a day, with the furnace burning `lit` of what it needs.
    func warmth(_ d: Int, lit: Double = 1) -> (warm: Double, cold: Double, open: Double) {
        let t = temperature(d), w = wallBonus(d)
        return (t + (Self.power[furnace] + (overdrive > 0 ? 12 : 0)) * lit + w, t + 8 + w, t - 4 + w)
    }
    /// Where the people live: in the heat, in houses outside it, and without a house.
    var housed: (warm: Int, cold: Int, open: Int) {
        let warm = min(citizens, warmRoom), cold = min(citizens - warm, room - warmRoom)
        return (warm, cold, citizens - warm - cold)
    }
    static func sickRate(_ t: Double) -> Double { min(0.3, max(0, (-t - 8) * 0.012)) }
    static func freezeRate(_ t: Double) -> Double { min(0.12, max(0, (-t - 20) * 0.008)) }

    // MARK: Work

    var moraleSpeed: Double { 0.7 + 0.5 * morale / 100 }
    func bonus(_ k: IceKind) -> Double {
        guard let h = governor(k) else { return 1 }
        let hero = iceHeroes[h]
        var b = 0.1 + Double(hero.wit) / 500
        if hero.skill == .planner { b += 0.2 }
        if hero.skill == .ruler || hero.skill == .balance { b += 0.1 }
        return 1 + b
    }
    /// Workers at each producing building, filled in order of need, and those left idle.
    func staffing() -> (at: [IceKind: Int], idle: Int) {
        var free = max(0, citizens - sick), at: [IceKind: Int] = [:]
        for k in IceKind.producers {
            let n = min(free, level[k.rawValue] * k.jobs)
            at[k] = n; free -= n
        }
        return (at, free)
    }
    /// What a day's work brings in, before anything is eaten or burnt.
    func output(_ d: Int, lit: Double = 1) -> IceStock {
        let staff = staffing(), speed = moraleSpeed
        let t = temperature(d), storm = inBlizzard(d)
        let outdoor = speed * (storm ? 0.55 : 1)
        var o = IceStock()
        o.coal = Double(staff.at[.coal] ?? 0) * 2.1 * outdoor * bonus(.coal)
        o.wood = Double(staff.at[.sawmill] ?? 0) * 3.0 * outdoor * bonus(.sawmill)
        let hunt = Double(staff.at[.hunting] ?? 0) * 3.0 * outdoor * bonus(.hunting) * (t < -28 ? 0.7 : 1) * (huntBad > 0 ? 0.5 : 1)
        let grow = Double(staff.at[.greenhouse] ?? 0) * 4.0 * speed * bonus(.greenhouse) * min(1, lit * 1.2)
        o.food = hunt + grow
        o.iron = Double(staff.at[.iron] ?? 0) * 2.2 * outdoor * bonus(.iron)
        let idle = Double(staff.idle) * outdoor
        o.wood += idle * 0.3; o.food += idle * 0.3
        for (i, c) in iceCounties.enumerated() where i > 0 && owner[i] == 0 { o[c.resource] += c.amount }
        return o
    }
    var eats: Double { Double(citizens) * 0.8 + Double(soldiers + wounded + marches.reduce(0) { $0 + $1.soldiers + $1.wounded }) * 0.5 }
    var heals: Double {
        var h = Double(level[IceKind.clinic.rawValue] * 4)
        if home(.healer) { h += governor(.clinic).map { iceHeroes[$0].skill == .healer } == true ? 15 : 5 }
        else if has(.clinic) { h *= bonus(.clinic) }
        return h
    }
    var soldierRoom: Int { 40 + 40 * level[IceKind.barracks.rawValue] }
    var batch: Int { 10 * level[IceKind.barracks.rawValue] }
    var heroRoom: Int { 1 + 2 * level[IceKind.tavern.rawValue] }
    var population: Int { citizens }
    var counties: Int { owner.dropFirst().filter { $0 == 0 }.count }
    var over: Bool { ended != nil }

    mutating func roll(_ x: Double) -> Int {
        let whole = floor(x), part = x - whole
        return Int(whole) + (Double(dice.below(1000)) / 1000 < part ? 1 : 0)
    }

    // MARK: A day

    mutating func advance() {
        news = []; reports = []
        let d = day
        // The furnace.
        let need = burnRate
        let lit = need > 0 ? min(1, stock.coal / need) : 0
        stock.coal = max(0, stock.coal - need)
        if lit < 0.5 { outDays += 1; tally.coalOutDays += 1; if tally.firstCoalOut == nil { tally.firstCoalOut = d } } else { outDays = 0 }
        if lit < 0.5, !imagined { news.append("熔炉断煤了！") }
        let heat = warmth(d, lit: lit), where_ = housed
        // Sickness and frost.
        let healthy = max(0, citizens - sick)
        let share = citizens > 0 ? Double(healthy) / Double(citizens) : 0
        var newSick = 0, frozen = 0
        for (n, t) in [(where_.warm, heat.warm), (where_.cold, heat.cold), (where_.open, heat.open)] where n > 0 {
            newSick += roll(Double(n) * share * Self.sickRate(t))
            frozen += roll(Double(n) * Self.freezeRate(t))
        }
        newSick = min(newSick, healthy)
        frozen = min(frozen, citizens)
        let warmShare = citizens > 0 ? Double(where_.warm) / Double(citizens) : 1
        // The sick: some die before help comes, most of the rest are cured.
        let died = min(sick, roll(Double(sick) * (0.04 + 0.16 * (1 - warmShare))))
        sick -= died; citizens -= died
        let cured = min(sick, roll(heals + Double(sick) * 0.15 * warmShare))
        sick -= cured
        sick += newSick
        let frozenSick = min(sick, frozen * sick / max(citizens, 1))
        sick -= frozenSick; citizens -= frozen
        tally.sickened += newSick; tally.sickDeaths += died; tally.coldDeaths += frozen
        // Work, and the counties' tribute.
        let made = output(d, lit: lit)
        stock.coal += made.coal; stock.wood += made.wood; stock.food += made.food; stock.iron += made.iron
        // Eating.
        let meal = eats
        var starved = 0, hungry = false
        if stock.food >= meal { stock.food -= meal } else {
            hungry = true
            let short = meal - stock.food
            stock.food = 0
            starved = min(citizens, max(short >= 3 ? 1 : 0, roll(short * 0.06)))
            let starvedSick = min(sick, starved / 2)
            sick -= starvedSick; citizens -= starved
            tally.hungerDeaths += starved; tally.hungryDays += 1
            if tally.firstFoodOut == nil { tally.firstFoodOut = d }
        }
        // The wounded mend.
        let mended = min(wounded, roll(Double(wounded) * (0.2 + 0.05 * Double(level[IceKind.clinic.rawValue]))))
        wounded -= mended; soldiers += mended
        // Morale.
        let deaths = died + frozen + starved
        var mood = 0.3 - (morale - 60) * 0.05
        if hungry { mood -= 5 }
        if citizens > 0, Double(where_.cold + where_.open) / Double(citizens) > 0.15 { mood -= 1.5 }
        if citizens > 0, Double(sick) / Double(citizens) > 0.2 { mood -= 1.5 }
        mood -= min(6, Double(deaths) * 0.7)
        if lit < 0.5 { mood -= 4 }
        mood += 0.3 * Double(level[IceKind.tavern.rawValue])
        if serving(.charm) { mood += 1 }
        if serving(.balance) { mood += 0.5 }
        if serving(.peerless) { mood -= 1 }
        morale = min(100, max(0, morale + mood))
        // People come and go: first those of the conquered counties, then newcomers from the snow.
        let moving = min(waiting, max(0, warmRoom - citizens), 3)
        citizens += moving; waiting -= moving; tally.arrived += moving
        let free = warmRoom - citizens
        if waiting == 0, morale >= 45, free > 0, stock.food >= meal * 2, dice.below(3) > 0 {
            let n = min(free, 1 + Int((morale - 45) / 18))
            citizens += n; tally.arrived += n
        }
        if morale < 25, citizens - sick > 0 {
            let n = min(citizens - sick, 1 + dice.below(3))
            citizens -= n; tally.left += n
            if !imagined { news.append("\(n) 人对城主失望，离开了") }
        }
        // Armies on the road.
        marchOn()
        // The rival lords.
        for r in 0..<2 { rivalDay(r) }
        for i in 1..<owner.count where owner[i] == 1 || owner[i] == 2 {
            garrison[i] = min(iceCounties[i].capital ? 200 : 120, garrison[i] + 0.5)
        }
        // Events.
        if var e = event {
            e.left -= 1
            if e.left <= 0 { event = nil; settle(e, choice: Self.choices(e.kind).count - 1, ignored: true) } else { event = e }
        }
        if event == nil {
            if let cold = nextCold(after: d + 1), cold.start == d + 2 {
                event = IceEvent(kind: 2, amount: cold.end - cold.start + 1, left: 2, arrived: d + 1)
            } else if d + 1 >= nextEvent {
                let kinds = [0, 0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 3, 4]
                event = IceEvent(kind: kinds[dice.below(kinds.count)], amount: 5 + dice.below(8), left: 3, arrived: d + 1)
                nextEvent = d + 1 + 4 + dice.below(3)
            }
        }
        if overdrive > 0 { overdrive -= 1 }
        if huntBad > 0 { huntBad -= 1 }
        // A new face at the tavern now and then.
        if d % 8 == 0, !pool.isEmpty, !offered.isEmpty {
            pool.append(offered.removeFirst())
            offered.append(pool.removeFirst())
        }
        day += 1
        peakPopulation = max(peakPopulation, citizens)
        if citizens <= 0 { citizens = 0; sick = 0; ended = "城里的人都没了" }
        else if outDays >= Self.outLimit { ended = "熔炉熄灭了 \(Self.outLimit) 天，城冻住了" }
        else if counties == iceCounties.count - 1 { ended = "天下一统" }
        else if day > Self.days { ended = "熬过了一百天" }
    }

    // MARK: War

    /// How hard a general's soldiers hit a county's defenders, per soldier, on a day.
    func punch(_ h: Int, against county: Int, on d: Int) -> Double {
        let hero = iceHeroes[h], foe = owner[county] == 1 ? 3 : owner[county] == 2 ? 4 : iceCounties[county].foe
        var m = 0.7 + Double(hero.lead) / 200 + Double(hero.war) / 400
        switch hero.skill {
        case .brawler: if foe < 3 { m *= 1.4 }
        case .charge: m *= 1.25
        case .peerless: m *= 1.45
        case .planner: m *= 1.15
        case .saint: m *= 1.3
        case .fire: if foe >= 3 { m *= 1.35 }
        case .ruler: m *= 1.1
        case .veteran: m *= 1.1
        case .cavalry: m *= 1.15
        default: break
        }
        if hero.skill != .veteran { m *= cold(on: d) }
        return m
    }
    func cold(on d: Int) -> Double { max(0.6, min(1, 1 + (temperature(d) + 15) / 100)) }
    func defence(_ county: Int) -> Double {
        let foe = owner[county] == 1 ? 3 : owner[county] == 2 ? 4 : iceCounties[county].foe
        return garrison[county] * [1.0, 0.9, 1.3, 1.2, 1.2][foe] * (iceCounties[county].capital ? 1.25 : 1)
    }
    static func chance(_ ratio: Double) -> Double { 1 / (1 + exp(-5 * (ratio - 1))) }
    /// Days to march from the city to a county, through what we hold.
    func distance(to county: Int) -> Int? {
        var seen = [0], frontier = [0], steps = 0
        while !frontier.isEmpty {
            steps += 1
            var next: [Int] = []
            for a in frontier {
                for b in iceNeighbours[a] where !seen.contains(b) {
                    if b == county { return steps }
                    seen.append(b)
                    if owner[b] == 0 { next.append(b) }
                }
            }
            frontier = next
        }
        return nil
    }
    func travel(_ h: Int, to county: Int) -> Int? {
        guard let steps = distance(to: county) else { return nil }
        return max(1, 1 + steps - (iceHeroes[h].skill == .cavalry ? 1 : 0))
    }
    /// A battle as it would likely go: the chance of winning, and what it costs either way.
    func battle(_ h: Int, _ n: Int, _ county: Int, on d: Int) -> (chance: Double, winKilled: Int, winWounded: Int, loseKilled: Int, loseWounded: Int) {
        let attack = Double(n) * punch(h, against: county, on: d), guard_ = max(1, defence(county))
        let p = Self.chance(attack / guard_)
        let lossWin = min(0.6, max(0.05, 0.4 * guard_ / max(attack, 1))) * Double(n)
        let careful = iceHeroes[h].skill == .planner ? 0.8 : 1
        return (p, Int((lossWin * 0.25 * careful).rounded()), Int((lossWin * 0.75 * careful).rounded()),
                Int((Double(n) * 0.55 * 0.3 * careful).rounded()), Int((Double(n) * 0.55 * 0.7 * careful).rounded()))
    }

    mutating func marchOn() {
        var kept: [IceMarch] = []
        for var m in marches {
            m.left -= 1
            if m.left > 0 { kept.append(m); continue }
            if !m.back {
                let b = battle(m.hero, m.soldiers, m.county, on: day)
                let won: Bool
                if let forced = m.forced { won = forced } else { won = Double(dice.below(10_000)) / 10_000 < b.chance }
                let killed = won ? b.winKilled : b.loseKilled, hurt = won ? b.winWounded : b.loseWounded
                m.soldiers -= killed + hurt; m.wounded = hurt; m.won = won
                var people = 0
                if won {
                    let rival = owner[m.county]
                    owner[m.county] = 0; garrison[m.county] = 0
                    people = iceCounties[m.county].people * (iceHeroes[m.hero].skill == .ruler ? 3 : 2) / 2
                    waiting += people
                    morale = min(100, morale + 4)
                    if rival == 1 || rival == 2 { rivals[rival - 1].reserve *= 0.9 }
                } else {
                    garrison[m.county] = max(5, garrison[m.county] - Double(m.soldiers + killed + hurt) * 0.25)
                    morale = max(0, morale - 3)
                }
                let report = IceReport(county: m.county, hero: m.hero, won: won, killed: killed, wounded: hurt, day: day, people: people)
                reports.append(report)
                if !imagined {
                    news.append(won ? "\(iceHeroes[m.hero].name) 攻下了\(iceCounties[m.county].name)" + (people > 0 ? "，\(people) 人来投" : "")
                                    : "\(iceHeroes[m.hero].name) 在\(iceCounties[m.county].name)吃了败仗")
                }
                m.back = true; m.left = m.travel
                kept.append(m)
            } else {
                soldiers += m.soldiers; wounded += m.wounded
                if let g = generals.firstIndex(where: { $0.hero == m.hero }) { generals[g].away = false }
            }
        }
        marches = kept
    }

    /// A rival lord's turn: now and then it takes a neighbouring county from the wild, or raids the city.
    mutating func rivalDay(_ r: Int) {
        let me = r + 1
        let held = owner.filter { $0 == me }.count
        guard held > 0 else { return }
        rivals[r].reserve += 2 + Double(held)
        let d = day
        // A raid on the city, once it borders what they hold.
        let near = (1..<owner.count).contains { i in owner[i] == me && iceNeighbours[i].contains { owner[$0] == 0 } }
        if d >= rivals[r].nextRaid {
            rivals[r].nextRaid = d + 14 + dice.below(7)
            if near {
                let raiders = min(rivals[r].reserve * 0.4, 30 + Double(d) * 0.8)
                let guardHome = defenceAtHome
                let won = Double(dice.below(10_000)) / 10_000 < Self.chance(raiders / max(1, guardHome))
                rivals[r].reserve -= raiders * (won ? 0.2 : 0.5)
                if won {
                    stock.coal *= 0.88; stock.food *= 0.88; stock.wood *= 0.88
                    let hurt = min(soldiers, Int(Double(soldiers) * 0.2))
                    soldiers -= hurt; wounded += hurt
                    morale = max(0, morale - 6); tally.raidsLost += 1
                    if !imagined { news.append("\(iceOwnerCN[me])军来袭，抢走了一些煤、木和粮") }
                } else {
                    let hurt = min(soldiers, Int(raiders * 0.1))
                    soldiers -= hurt; wounded += hurt
                    morale = min(100, morale + 2); tally.raidsHeld += 1
                    if !imagined { news.append("打退了\(iceOwnerCN[me])军的偷袭") }
                }
                return
            }
        }
        guard (d + rivals[r].offset) % rivals[r].period == 0 else { return }
        // Expand: the weakest wild county next to their land.
        var best: (Int, Double)?
        for i in 1..<owner.count where owner[i] == 3 && iceNeighbours[i].contains(where: { owner[$0] == me }) {
            if marches.contains(where: { $0.county == i && !$0.back }) { continue }
            let dv = defence(i)
            if best == nil || dv < best!.1 { best = (i, dv) }
        }
        guard let pick = best, rivals[r].reserve * 0.7 > pick.1 * 1.2 else { return }
        let target = pick.0, dv = pick.1
        let sent = rivals[r].reserve * 0.7
        let won = Double(dice.below(10_000)) / 10_000 < Self.chance(sent / dv)
        if won {
            owner[target] = me; garrison[target] = max(30, sent * 0.6)
            rivals[r].reserve -= sent * 0.8
            if !imagined { news.append("\(iceOwnerCN[me])国占了\(iceCounties[target].name)") }
        } else {
            garrison[target] = max(10, garrison[target] - sent * 0.3)
            rivals[r].reserve -= sent * 0.6
        }
    }
    /// What would meet raiders at the city: the soldiers at home behind the wall.
    var defenceAtHome: Double { Double(soldiers) * (1 + 0.3 * Double(wall)) + 15 * Double(wall) + 10 }
    /// The rival that could raid next, when, and with about how many.
    var raidThreat: (rival: Int, day: Int, raiders: Double)? {
        var out: (rival: Int, day: Int, raiders: Double)?
        for r in 0..<2 {
            let me = r + 1
            let near = (1..<owner.count).contains { i in owner[i] == me && iceNeighbours[i].contains { owner[$0] == 0 } }
            guard near else { continue }
            let raiders = min(rivals[r].reserve * 0.4, 30 + Double(rivals[r].nextRaid) * 0.8)
            if out == nil || rivals[r].nextRaid < out!.day { out = (r, max(day, rivals[r].nextRaid), raiders) }
        }
        return out
    }

    // MARK: Events

    /// Each event's choices; the last is what happens when it is left unanswered.
    static func choices(_ kind: Int) -> [String] {
        switch kind {
        case 0: return ["收留难民", "请难民离开"]
        case 1: return ["准矿工歇一天", "不准，照常下井"]
        case 2: return ["加倍烧煤，扛过寒潮", "照常烧煤"]
        case 3: return ["用 60 木换 50 粮", "用 30 铁换 60 煤", "用 80 木换 30 铁", "不做买卖"]
        case 4: return ["开仓熬药（30 粮）", "任它蔓延"]
        case 5: return ["办冰灯节", "今年不办"]
        case 6: return ["派 20 兵去猎狼", "关门不出猎"]
        case 7: return ["收下老兵（30 粮）", "婉拒"]
        case 8: return ["挖开冰窖（30 木）", "不去管它"]
        case 9: return ["严惩偷煤贼", "原谅他"]
        default: return ["为新人办婚礼（15 粮）", "简单办"]
        }
    }
    static let eventTitles = ["城门外来了难民", "矿工请愿：想歇一天暖暖身子", "寒潮预警", "冰原商队路过", "城里起了风寒", "孩子们想办冰灯节",
                              "狼群在猎场附近出没", "一队老兵来投军", "发现一座旧冰窖", "抓到一个偷煤贼", "城里有人要成亲"]
    /// Whether a choice can be made at all with what the city has.
    func can(_ e: IceEvent, _ choice: Int) -> Bool {
        switch (e.kind, choice) {
        case (1, 0): return stock.coal >= 20
        case (3, 0): return stock.wood >= 60
        case (3, 1): return stock.iron >= 30
        case (3, 2): return stock.wood >= 80
        case (4, 0): return stock.food >= 30
        case (5, 0): return stock.food >= 25 && stock.wood >= 20
        case (6, 0): return soldiers >= 20
        case (7, 0): return stock.food >= 30
        case (8, 0): return stock.wood >= 30
        case (10, 0): return stock.food >= 15
        default: return true
        }
    }

    mutating func settle(_ e: IceEvent, choice: Int, ignored: Bool = false) {
        func mood(_ x: Double) { morale = min(100, max(0, morale + x)) }
        switch (e.kind, choice) {
        case (0, 0): citizens += e.amount; tally.arrived += e.amount; mood(4)
        case (0, _): mood(ignored ? -5 : -5)
        case (1, 0): stock.coal -= 20; mood(6)
        case (1, _): mood(-6)
        case (2, 0): overdrive = max(overdrive, e.amount + 2)
        case (2, _): break
        case (3, 0): stock.wood -= 60; stock.food += 50
        case (3, 1): stock.iron -= 30; stock.coal += 60
        case (3, 2): stock.wood -= 80; stock.iron += 30
        case (3, _): break
        case (4, 0): stock.food -= 30; sick = max(0, sick - 8); mood(2)
        case (4, _): let n = min(citizens - sick, 6); sick += n; tally.sickened += n
        case (5, 0): stock.food -= 25; stock.wood -= 20; mood(9)
        case (5, _): mood(-2)
        case (6, 0): stock.food += 50; let n = min(soldiers, 4); soldiers -= n; wounded += n
        case (6, _): huntBad = 3
        case (7, 0): stock.food -= 30; soldiers += 12
        case (7, _): break
        case (8, 0): stock.wood -= 30; stock.food += 90
        case (8, _): break
        case (9, 0): stock.coal += 25; mood(-3)
        case (9, _): mood(3)
        case (10, 0): stock.food -= 15; mood(5)
        default: mood(1)
        }
        if !imagined, ignored { news.append("「\(Self.eventTitles[e.kind])」没人理会，过去了") }
    }

    // MARK: Decisions

    func price(_ k: IceKind) -> (wood: Double, iron: Double) {
        let L = Double(level[k.rawValue] + 1)
        switch k {
        case .furnace: return [(0, 0), (0, 0), (100, 20), (180, 45), (280, 80), (400, 120)][min(5, level[k.rawValue] + 1)]
        case .house: return (30 + 2 * L, 0)
        case .sawmill: return (45 * L, 6 * (L - 1))
        case .coal: return (55 * L, 10 * (L - 1))
        case .hunting: return (45 * L, 5 * (L - 1))
        case .greenhouse: return (80 * L, 18 * L)
        case .iron: return (60 * L, 0)
        case .clinic: return (70 * L, 15 * L)
        case .barracks: return (80 * L, 25 * L)
        case .tavern: return (90 * L, 10 * L)
        case .wall: return (130 * L, 35 * L)
        }
    }
    func canBuild(_ k: IceKind) -> Bool {
        guard level[k.rawValue] < k.top else { return false }
        if k == .greenhouse, furnace < 2 { return false }
        let p = price(k)
        return stock.wood >= p.wood && stock.iron >= p.iron
    }
    /// Why a building cannot go up now, in Chinese, for a person's click.
    func whyNot(_ k: IceKind) -> String {
        if level[k.rawValue] >= k.top { return k == .house ? "熔炉周围盖不下更多民居了" : "\(k.cn)已经是最高级了" }
        if k == .greenhouse, furnace < 2 { return "温室要熔炉 2 级才暖得起来" }
        let p = price(k)
        if stock.wood < p.wood { return "木头不够：还差 \(Int((p.wood - stock.wood).rounded(.up)))" }
        if stock.iron < p.iron { return "铁不够：还差 \(Int((p.iron - stock.iron).rounded(.up)))" }
        return "现在不能建\(k.cn)"
    }
    var trainCost: (food: Double, iron: Double) { (Double(batch) * 2, Double(batch)) }
    var canTrain: Bool {
        batch > 0 && soldiers + wounded + marches.reduce(0) { $0 + $1.soldiers + $1.wounded } + 5 <= soldierRoom
            && stock.food >= trainCost.food && stock.iron >= trainCost.iron
    }
    var trainable: Int {
        min(batch, soldierRoom - soldiers - wounded - marches.reduce(0) { $0 + $1.soldiers + $1.wounded })
    }
    func canRecruit(_ h: Int) -> Bool {
        has(.tavern) && generals.count < heroRoom && offered.contains(h)
            && stock.food >= Double(iceHeroes[h].food) && stock.iron >= Double(iceHeroes[h].iron)
    }
    var freeGenerals: [Int] { generals.filter { !$0.away }.map(\.hero) }
    /// Soldiers to send: enough to win nine times in ten, or all there are.
    func army(_ h: Int, to county: Int, arriving d: Int) -> Int {
        let per = punch(h, against: county, on: d)
        let needed = Int((defence(county) * 1.44 / max(per, 0.1) / 10).rounded(.up)) * 10
        return min(soldiers, max(10, needed))
    }

    mutating func apply(_ move: IceMove) {
        raised = nil
        switch move {
        case .build(let k):
            let p = price(k)
            stock.wood -= p.wood; stock.iron -= p.iron
            level[k.rawValue] += 1
            raised = k
        case .recruit(let h):
            stock.food -= Double(iceHeroes[h].food); stock.iron -= Double(iceHeroes[h].iron)
            generals.append(IceGeneral(hero: h))
            offered.removeAll { $0 == h }
            if !pool.isEmpty { offered.append(pool.removeFirst()) }
        case .train:
            let n = trainable
            stock.food -= Double(n) * 2; stock.iron -= Double(n)
            soldiers += n
        case .march(let county, let h, let n, let forced):
            guard let days = travel(h, to: county) else { break }
            soldiers -= n
            if let g = generals.firstIndex(where: { $0.hero == h }) { generals[g].away = true; generals[g].governs = nil }
            marches.append(IceMarch(county: county, hero: h, soldiers: n, travel: days, left: days, forced: forced, began: day))
        case .answer(let choice):
            if let e = event { event = nil; settle(e, choice: choice) }
        case .govern(let h, let k):
            for g in generals.indices where generals[g].governs == k { generals[g].governs = nil }
            if let g = generals.firstIndex(where: { $0.hero == h }) { generals[g].governs = k }
        case .rest:
            break
        }
    }
}

fileprivate enum IceMove: Equatable {
    case build(IceKind)
    case recruit(Int)
    case train
    /// An expedition: to a county, led by a general, with soldiers; `forced` only in a look ahead.
    case march(county: Int, hero: Int, soldiers: Int, forced: Bool?)
    case answer(Int)
    case govern(hero: Int, kind: IceKind)
    case rest
}

// MARK: - Looking ahead, and what a city is worth

fileprivate enum IceJudge {
    /// The city some days on, if nothing more is decided.
    static func ahead(_ w: IceWorld, _ days: Int) -> IceWorld {
        var v = w
        v.imagined = true
        for _ in 0..<days where v.ended == nil { v.advance() }
        return v
    }
    /// How far to look: a week, or to the end of a cold spell coming within ten days.
    static func horizon(_ w: IceWorld) -> Int {
        guard let cold = w.nextCold(after: w.day), cold.start - w.day <= 10 else { return 7 }
        return min(16, max(7, cold.end - w.day + 2))
    }

    /// Whether a city looked ahead has died, on what day, and mostly of what.
    static func doom(_ from: IceWorld, _ later: IceWorld) -> (day: Int, cause: String)? {
        guard later.ended != nil, later.citizens <= 0 || later.outDays >= IceWorld.outLimit else { return nil }
        if later.outDays >= IceWorld.outLimit { return (later.day - 1, "the furnace out of coal") }
        let t = later.tally, f = from.tally
        let causes = [(t.hungerDeaths - f.hungerDeaths, "famine"), (t.coldDeaths - f.coldDeaths, "the cold"), (t.sickDeaths - f.sickDeaths, "sickness"), (t.left - f.left, "people leaving in despair")]
        return (later.day - 1, causes.max { $0.0 < $1.0 }!.1)
    }

    /// The blizzard, foreseen from here: how warm the warm houses and the cold ones would be, the sick it would make, and the coal it needs.
    static func blizzard(_ w: IceWorld) -> (warm: Double, cold: Double, sick: Double, short: Double)? {
        guard w.day <= w.blizzard.end else { return nil }
        let mid = (w.blizzard.start + w.blizzard.end) / 2
        let t = w.temperature(mid), wall = Double(w.wall) * 7
        let warm = t + IceWorld.power[w.furnace] + wall, cold = t + 8 + wall
        let days = Double(w.blizzard.end - max(w.day, w.blizzard.start) + 1)
        let people = Double(w.citizens), inWarm = min(people, Double(w.warmRoom))
        func share(_ rate: Double) -> Double { 1 - pow(1 - rate, days) }
        let sick = inWarm * share(IceWorld.sickRate(warm)) + (people - inWarm) * share(IceWorld.sickRate(cold))
        // Coal: what is there by the time it comes, against what it burns.
        let until = Double(max(0, w.blizzard.start - w.day))
        let made = w.output(w.day).coal
        let atStart = w.stock.coal + (made - w.burnRate) * until
        let storm = made * 0.55
        let need = (w.burnRate - storm) * days
        return (warm, cold, sick, max(0, need - atStart))
    }

    /// What the army could take next: for the three best counties within reach, the chance that everybody
    /// (the wounded as half) under the best general would take it, times what a county is worth.
    static func military(_ w: IceWorld) -> Double {
        let force = Double(w.soldiers + w.marches.reduce(0) { $0 + $1.soldiers }) + Double(w.wounded) * 0.5
        guard force >= 5, !w.generals.isEmpty else { return 0 }
        var gains: [Double] = []
        for c in 1..<iceCounties.count where w.owner[c] != 0 && w.distance(to: c) != nil {
            if w.marches.contains(where: { $0.county == c && !$0.back }) { continue }
            let per = w.generals.map { w.punch($0.hero, against: c, on: w.day + 2) }.max() ?? 1
            let p = IceWorld.chance(force * per / max(1, w.defence(c)))
            gains.append(p * (90 + 6 * Double(iceCounties[c].people)))
        }
        return gains.sorted(by: >).prefix(3).reduce(0, +) * 0.8
    }

    /// What a city is worth: its people, its stores, its strength, and how ready it is for what is coming.
    static func value(_ w: IceWorld) -> Double {
        if w.ended != nil, w.citizens <= 0 || w.outDays >= IceWorld.outLimit { return -20_000 + Double(w.day) * 10 }
        var v = 14 * Double(w.citizens) + 9 * Double(w.waiting) - 6 * Double(w.sick) + 0.8 * w.morale
        func stored(_ x: Double, _ full: Double, _ k: Double) -> Double { k * min(x, full) + k * 0.25 * max(0, x - full) }
        let made = w.output(w.day), left = Double(IceWorld.days - w.day)
        let coalNet = made.coal - w.burnRate, foodNet = made.food - w.eats
        v += stored(w.stock.coal, max(80, w.burnRate * 12), 0.9) + stored(w.stock.food, max(80, w.eats * 10), 0.9)
        v += stored(w.stock.wood, 300, 0.45) + stored(w.stock.iron, 150, 0.6)
        // Income: the future the look ahead does not reach.
        let span = min(left, 25)
        v += min(max(coalNet, -30), 25) * 0.9 * span * 0.5
        v += min(max(foodNet, -30), 25) * 0.9 * span * 0.5
        v += made.wood * 0.5 * span * 0.5 + made.iron * 0.65 * span * 0.5
        // Room to grow, in the heat.
        v += 4 * Double(min(max(0, w.warmRoom - w.citizens), 12))
        // Heat reaching ground where houses could still go: growth to come.
        v += 14 * Double(min(max(0, IceWorld.reach[w.furnace] - w.houses), 3))
        v -= 6 * Double(max(0, w.citizens - w.warmRoom))
        // Strength.
        v += Double(w.soldiers) * 1.5 + Double(w.wounded) * 1.1 + Double(w.marches.reduce(0) { $0 + $1.soldiers + $1.wounded }) * 1.3
        v += military(w)
        v += 0.4 * Double(min(w.soldierRoom, 200))
        v += Double(w.generals.count) * 22 + Double(w.counties) * 55
        v += w.heals * 3 * (w.sick > 0 ? 1.5 : 1)
        v += Double(w.level[IceKind.tavern.rawValue]) * 12 + Double(w.level[IceKind.barracks.rawValue]) * 10
        // Ready for the blizzard?
        if let b = blizzard(w) {
            let soon = w.blizzard.start - w.day
            let weight = soon > 40 ? 0.5 : soon > 20 ? 0.8 : 1
            v -= weight * (b.sick * 9 + b.short * 1.4)
        }
        // Ready for the next cold snap: people outside the heat when it comes.
        if let cold = w.nextCold(after: w.day), !cold.blizzard {
            let heat = w.warmth(cold.start)
            let outside = Double(w.citizens - min(w.citizens, w.warmRoom))
            v -= outside * IceWorld.sickRate(heat.cold) * 25 + Double(min(w.citizens, w.warmRoom)) * IceWorld.sickRate(heat.warm) * 25
        }
        // Raiders coming and the city left bare.
        if let threat = w.raidThreat, threat.day - w.day <= 6 {
            let p = IceWorld.chance(threat.raiders / max(1, w.defenceAtHome))
            v -= p * (0.12 * (w.stock.coal + w.stock.food + w.stock.wood) * 0.9 + 20)
        }
        return v
    }
}

// MARK: - The game

@MainActor
final class JevIceKingdoms: JevGame {
    let id = "icekingdoms", title = "冰河三国·回合", symbol = "snowflake"
    let rules = "A survival and conquest game in an ice age of the Three Kingdoms: you rule a frozen city built around a great furnace, one decision a day for 100 days. The furnace burns coal every day; its level sets how many houses its heat reaches, how warm it keeps them and how much coal it burns. It grows colder day by day, with cold snaps and one great blizzard of about a week, somewhere between days 62 and 75, when it falls to about −50°C. People in houses outside the heat, or with no house, fall sick in the cold; in deep cold they freeze; the sick cannot work and some die; a clinic heals them. Everyone eats food; hunger kills and lowers morale. Citizens work the buildings by themselves: coal mine, sawmill, hunting lodge and greenhouse (food), iron mine. Morale (0–100) speeds or slows work, and newcomers settle only in warm houses while morale is good. A wall keeps out the blizzard's wind and raiders. Generals recruited at the tavern lead expeditions and can govern a building for a bonus. An expedition marches to a county on the map and fights its garrison; winning gives the county's resources every day and its people. The rival lords Wei and Wu take counties too, and raid the city once their land borders yours. The game ends at day 100, when everyone is dead, when the furnace stays out 5 days, or when you hold every county. The score counts population, counties, generals and survival."
    let question = "Which decision is best for the city today?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First, survival: an option that keeps people from getting sick, freezing or starving beats everything else — keep coal and food lasting well past the next cold spell, keep everybody in houses inside the furnace's heat, and have the city ready for the great blizzard before it comes (a furnace of level 3 or more, a wall, and coal for the blizzard days). Second, growth: warm houses for more people, more coal and food coming in, a clinic, good morale. Third, conquest: send expeditions that win about 75% of the time or more, for counties that give resources and people; a strong general is worth recruiting. Answer an event the way that helps survival first and morale second. Doing nothing wastes the day: the day's coal, wood, food and iron come in whatever you choose, so waiting is right only when no option helps."
    let controls = "每天做一个决定：点右边的选项，或者直接点画面 —— 点城里的建筑就是造它或升级它，点地图上的州府就是出征那里，点事件卡上的按钮就是那样回应"

    fileprivate var world = IceWorld(seed: 1)
    fileprivate var previous = IceWorld(seed: 1)
    fileprivate var moves: [IceMove] = []
    private(set) var ticked = Date.distantPast
    private var person = false
    private var seed: UInt64 = 1

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        self.seed = seed
        world = IceWorld(seed: seed); previous = world; moves = []; ticked = .distantPast
    }

    func prepare(person: Bool) { self.person = person }

    var over: Bool { world.over }
    var score: Int {
        let alive = world.citizens > 0 && world.outDays < IceWorld.outLimit
        return world.citizens * 10 + world.counties * 60 + world.generals.count * 25 + (alive ? min(world.day - 1, IceWorld.days) * 3 : (world.day - 1) * 2)
            + (alive && world.over ? 200 : 0)
    }
    var grid: [[JevCell]] { [[JevCell(colour: Color(red: 0.85, green: 0.9, blue: 0.97))]] }

    var status: String {
        let w = world
        if let end = w.ended { return "第 \(min(w.day - 1, IceWorld.days)) 天 · \(end) · \(w.citizens) 人 · \(w.counties) 州 · 得分 \(score)" }
        return "第 \(w.day) / \(IceWorld.days) 天 · \(Int(w.temperature(w.day).rounded()))°C · 👥\(w.citizens)（病 \(w.sick)） · 民心 \(Int(w.morale)) · 煤 \(Int(w.stock.coal)) 木 \(Int(w.stock.wood)) 粮 \(Int(w.stock.food)) 铁 \(Int(w.stock.iron)) · 兵 \(w.soldiers) · \(w.counties) 州"
            + (w.news.isEmpty ? "" : " · " + w.news.joined(separator: "；"))
    }

    // MARK: Words for the position

    private static func days(_ x: Double) -> String {
        if x.isInfinite || x > 60 { return "more than 60 days" }
        let n = max(0, Int(x.rounded(.down)))
        return n == 1 ? "1 day" : "\(n) days"
    }
    private static func deg(_ t: Double) -> String { "\(Int(t.rounded()))°C" }
    private static func stockWord(_ x: Double) -> String {
        x < 30 ? "almost none" : x < 100 ? "little" : x < 250 ? "some" : x < 500 ? "plenty" : "a great deal"
    }
    /// How long a store lasts at a net rate.
    private static func lasts(_ stock: Double, _ net: Double) -> Double { net >= 0 ? .infinity : stock / -net }

    var situation: String {
        let w = world
        let t = w.temperature(w.day), made = w.output(w.day), where_ = w.housed
        var parts = ["day \(w.day) of \(IceWorld.days); \(Self.deg(t)) outside"]
        if let cold = w.nextCold(after: w.day) {
            let when = cold.start <= w.day ? "now, until day \(cold.end)" : "on days \(cold.start)–\(cold.end)"
            parts.append((cold.blizzard ? "the great blizzard comes " : "a cold snap comes ") + when + " (about \(Self.deg(w.temperature((cold.start + cold.end) / 2))))")
        }
        if w.day < w.blizzard.start, w.nextCold(after: w.day).map({ !$0.blizzard }) ?? true {
            parts.append("the great blizzard comes on days \(w.blizzard.start)–\(w.blizzard.end) (about \(Self.deg(w.temperature((w.blizzard.start + w.blizzard.end) / 2))))")
        }
        let heat = w.warmth(w.day)
        parts.append("\(w.citizens) people (\(w.sick) sick): \(where_.warm) in warm houses at \(Self.deg(heat.warm))"
                     + (where_.cold > 0 ? ", \(where_.cold) in houses outside the heat at \(Self.deg(heat.cold))" : "")
                     + (where_.open > 0 ? ", \(where_.open) with no house at \(Self.deg(heat.open))" : ""))
        parts.append("furnace level \(w.furnace), warming \(w.warmHouses) of \(w.houses) houses (room for \(w.warmRoom) people in the heat)")
        parts.append("morale \(Int(w.morale)) (work speed \(Int((w.moraleSpeed * 100).rounded()))%)")
        let coalNet = made.coal - w.burnRate, foodNet = made.food - w.eats
        parts.append("coal \(Int(w.stock.coal)) (+\(Int(made.coal)) mined, −\(Int(w.burnRate)) burnt a day: " + (coalNet >= 0 ? "growing" : "lasts \(Self.days(Self.lasts(w.stock.coal, coalNet)))") + ")")
        parts.append("food \(Int(w.stock.food)) (+\(Int(made.food)), −\(Int(w.eats)) eaten a day: " + (foodNet >= 0 ? "growing" : "lasts \(Self.days(Self.lasts(w.stock.food, foodNet)))") + ")")
        parts.append("wood \(Int(w.stock.wood)) (+\(Int(made.wood)) a day), iron \(Int(w.stock.iron)) (+\(Int(made.iron)) a day)")
        let away = w.marches.reduce(0) { $0 + $1.soldiers }
        parts.append("\(w.soldiers) soldiers at home" + (w.wounded > 0 ? ", \(w.wounded) wounded mending" : "") + (away > 0 ? ", \(away) on expeditions" : ""))
        let gens = w.generals.map { g -> String in
            let name = iceHeroes[g.hero].name
            if g.away { return name + " (away)" }
            if let k = g.governs { return name + " (governing \(k.en))" }
            return name + " (free)"
        }
        parts.append("generals: " + gens.joined(separator: ", "))
        parts.append("you hold \(w.counties) of \(iceCounties.count - 1) counties; Wei holds \(w.owner.filter { $0 == 1 }.count), Wu \(w.owner.filter { $0 == 2 }.count)")
        if let threat = w.raidThreat {
            parts.append("\(threat.rival == 0 ? "Wei" : "Wu") may raid the city around day \(threat.day) with about \(Int(threat.raiders)) raiders against a defence of \(Int(w.defenceAtHome))")
        }
        if let e = w.event { parts.append("waiting at the gate: \(Self.eventEN[e.kind]) (\(e.left == 1 ? "today is the last day to answer" : "\(e.left) days to answer"))") }
        if let d = IceJudge.doom(w, IceJudge.ahead(w, IceJudge.horizon(w))) { parts.insert("DANGER: if nothing changes the city dies by day \(d.day), of \(d.cause)", at: 1) }
        return parts.joined(separator: "; ")
    }

    private static let eventEN = ["refugees at the gate", "the miners ask for a warm day off", "a cold-spell warning", "a caravan of traders", "a fever in the city",
                                  "the children want an ice-lantern festival", "wolves near the hunting grounds", "veterans offering to serve", "an old ice cellar found",
                                  "a coal thief caught", "a wedding"]

    // MARK: Options

    func options() -> [JevOption] {
        guard !world.over else { return [] }
        let w = world
        var list: [IceMove] = []
        if let e = w.event {
            for c in IceWorld.choices(e.kind).indices where w.can(e, c) { list.append(.answer(c)) }
        }
        for k in IceKind.allCases where w.canBuild(k) { list.append(.build(k)) }
        for h in w.offered where w.canRecruit(h) { list.append(.recruit(h)) }
        if w.canTrain { list.append(.train) }
        let free = w.freeGenerals
        if !free.isEmpty, w.soldiers >= 10 {
            for c in 1..<iceCounties.count where w.owner[c] != 0 {
                guard !w.marches.contains(where: { $0.county == c && !$0.back }), w.distance(to: c) != nil else { continue }
                // The free general who hits hardest there.
                guard let h = free.max(by: { w.punch($0, against: c, on: w.day) < w.punch($1, against: c, on: w.day) }),
                      let days = w.travel(h, to: c) else { continue }
                list.append(.march(county: c, hero: h, soldiers: w.army(h, to: c, arriving: w.day + days), forced: nil))
            }
        }
        for h in free where !w.generals.contains(where: { $0.hero == h && $0.governs != nil }) {
            if let k = bestPost(for: h, in: w) { list.append(.govern(hero: h, kind: k)) }
        }
        list.append(.rest)

        // Measure every move: the city a while on with it, against the city without it.
        let span = IceJudge.horizon(w)
        let rested = IceJudge.ahead(w, span)
        let base = IceJudge.value(rested)
        var judged: [(move: IceMove, merit: Double, after: IceWorld)] = []
        for m in list {
            var now = w
            now.apply(m)
            if case .march(let c, let h, let n, _) = m, let days = w.travel(h, to: c) {
                let p = w.battle(h, n, c, on: w.day + days).chance
                var win = w, lose = w
                win.apply(.march(county: c, hero: h, soldiers: n, forced: true))
                lose.apply(.march(county: c, hero: h, soldiers: n, forced: false))
                let a = IceJudge.ahead(win, max(span, days * 2 + 1)), b = IceJudge.ahead(lose, max(span, days * 2 + 1))
                let restLong = IceJudge.value(IceJudge.ahead(w, max(span, days * 2 + 1)))
                // A lost battle costs more than soldiers: time, a general away, and the people's faith; a long shot is not taken.
                let risk = (1 - p) * 90 + (p < 0.65 ? 150 : 0)
                judged.append((m, p * IceJudge.value(a) + (1 - p) * IceJudge.value(b) - restLong - risk, IceJudge.ahead(now, span)))
                continue
            }
            let later = IceJudge.ahead(now, span)
            judged.append((m, m == .rest ? 0 : IceJudge.value(later) - base, later))
        }
        // A shortlist for a reader: every answer to the event, and the best few of each kind.
        var chosen = judged
        if !person {
            func kind(_ m: IceMove) -> Int {
                switch m { case .answer: return 0; case .build: return 1; case .recruit: return 2; case .train: return 3; case .march: return 4; case .govern: return 5; case .rest: return 6 }
            }
            let caps = [9, 6, 1, 1, 3, 1, 1]
            var kept: [(IceMove, Double, IceWorld)] = []
            for k in 0..<7 {
                let these = judged.filter { kind($0.move) == k }.sorted { $0.merit > $1.merit }
                kept += these.prefix(caps[k]).map { ($0.move, $0.merit, $0.after) }
            }
            // In the order a person would read them: events, buildings, people, war, rest.
            chosen = judged.filter { j in kept.contains { $0.0 == j.move } }
        }
        moves = chosen.map(\.move)
        var seen: [String: Int] = [:]
        var out: [JevOption] = []
        for (i, j) in chosen.enumerated() {
            let words = describe(j.move, in: w, after: j.after, rested: rested, span: span)
            if seen[words] != nil { continue }
            seen[words] = i
            out.append(JevOption(id: String(format: "p%02d", out.count + 1), label: words, merit: j.merit - Double(i) * 0.0001, move: i, title: name(j.move, in: w)))
        }
        return out
    }

    /// The building a general would do most good governing, if any.
    private func bestPost(for h: Int, in w: IceWorld) -> IceKind? {
        let hero = iceHeroes[h]
        if hero.skill == .fire, w.furnace >= 2, w.governor(.furnace) == nil { return .furnace }
        if hero.skill == .healer, w.has(.clinic), w.governor(.clinic) == nil { return .clinic }
        let staff = w.staffing()
        let ranked = IceKind.producers.filter { w.governor($0) == nil && (staff.at[$0] ?? 0) >= 3 }
            .max { (staff.at[$0] ?? 0) * [4, 5, 4, 3, 2][IceKind.producers.firstIndex(of: $0)!] < (staff.at[$1] ?? 0) * [4, 5, 4, 3, 2][IceKind.producers.firstIndex(of: $1)!] }
        return ranked
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move), !world.over else { return }
        previous = world
        world.apply(moves[option.move])
        world.advance()
        ticked = Date()
    }

    // MARK: Words for a move, the verdict first

    private func describe(_ m: IceMove, in w: IceWorld, after: IceWorld, rested: IceWorld, span: Int) -> String {
        var now = w
        now.apply(m)
        let made = w.output(w.day), then = now.output(w.day)
        let coalNet = made.coal - w.burnRate, foodNet = made.food - w.eats
        let dSick = after.tally.sickened - rested.tally.sickened
        let dDeaths = after.tally.deaths - rested.tally.deaths
        // The city dying soon comes before anything else.
        let doomed = IceJudge.doom(w, rested), fate = IceJudge.doom(w, after)
        let lifeline: String
        if let d = doomed, m != .rest {
            if let f = fate { lifeline = f.day > d.day ? "delays the end: the city still dies, by day \(f.day) instead of day \(d.day) (\(f.cause)); " : "does not save the city: it still dies by day \(f.day) (\(f.cause)); " }
            else { lifeline = "SAVES THE CITY, which otherwise dies by day \(d.day) (\(d.cause)); " }
        } else if doomed == nil, let f = fate, m != .rest {
            lifeline = "DOOMS THE CITY: it would die by day \(f.day) (\(f.cause)); "
        } else { lifeline = "" }
        return lifeline + words(m, w: w, now: now, after: after, rested: rested, span: span, made: made, then: then, coalNet: coalNet, foodNet: foodNet, dSick: dSick, dDeaths: dDeaths)
    }

    private func words(_ m: IceMove, w: IceWorld, now: IceWorld, after: IceWorld, rested: IceWorld, span: Int, made: IceStock, then: IceStock, coalNet: Double, foodNet: Double, dSick: Int, dDeaths: Int) -> String {
        func fate(_ x: IceWorld) -> String {
            let s = x.tally.sickened - w.tally.sickened, d = x.tally.deaths - w.tally.deaths
            if s == 0 && d == 0 { return "nobody falls sick or dies" }
            return "\(s) fall sick and \(d) die"
        }
        /// The next days, with the move and without: sickness and deaths, said as the verdict.
        func health(_ good: String) -> String? {
            guard dSick != 0 || dDeaths != 0 else { return nil }
            let better = dSick < 0 || dDeaths < 0
            return (better ? good : "costs lives") + " — over the next \(span) days \(fate(after)) with it, against \(fate(rested)) without"
        }
        switch m {
        case .build(let k):
            let p = w.price(k)
            let cost = "costs \(Int(p.wood)) wood" + (p.iron > 0 ? " and \(Int(p.iron)) iron" : "")
            let next = w.level[k.rawValue] + 1
            var verdict: [String] = [], detail: [String] = []
            switch k {
            case .furnace:
                let before = w.warmth(w.day), later = now.warmth(w.day)
                verdict.append("upgrade the furnace to level \(next)")
                if let h = health("keeps people warm and alive") { verdict.append(h) }
                let more = now.warmHouses - w.warmHouses
                detail.append("warm houses \(Self.deg(before.warm)) → \(Self.deg(later.warm)) today")
                detail.append(more > 0 ? "its heat reaches \(more) more houses (\(w.warmHouses) → \(now.warmHouses) of \(w.houses) built, room in the heat \(w.warmRoom) → \(now.warmRoom))"
                                       : "the heat already reaches all \(w.houses) houses; it could reach \(IceWorld.reach[next])")
                if let a = IceJudge.blizzard(w), let b = IceJudge.blizzard(now) {
                    detail.append("in the great blizzard warm houses would be at \(Self.deg(b.warm)) instead of \(Self.deg(a.warm))")
                }
                let burn = now.burnRate
                let net = made.coal - burn
                detail.append("burns \(Int(burn)) coal a day instead of \(Int(w.burnRate)); " + (net >= 0 ? "the mines still dig more than it burns" : "coal lasts \(Self.days(Self.lasts(w.stock.coal, net))) at that rate"))
            case .house:
                let inside = w.houses < IceWorld.reach[w.furnace]
                if inside { verdict.append("build a warm house inside the furnace's heat: room for 5 more people (warm room \(w.warmRoom) → \(now.warmRoom), \(w.citizens) people now), and newcomers settle in it") }
                else { verdict.append("build a cold house outside the furnace's heat: whoever lives there is at \(Self.deg(w.warmth(w.day).cold)) and falls sick in the cold, and newcomers do not settle there (the furnace must be upgraded to warm more houses)") }
                if let h = health("shelters people") { verdict.append(h) }
                let homeless = w.housed.open
                if homeless > 0 { detail.append("\(homeless) people have no house now") }
                let arrivals = after.tally.arrived - rested.tally.arrived
                if arrivals > 0 { detail.append("about \(arrivals) newcomers settle within \(span) days") }
            case .sawmill, .coal, .hunting, .greenhouse, .iron:
                let r = k == .coal ? 0 : k == .sawmill ? 1 : k == .iron ? 3 : 2
                let gain = then[r] - made[r]
                let staff = w.staffing().idle
                let name = k.en.replacingOccurrences(of: "the ", with: "")
                verdict.append((w.level[k.rawValue] == 0 ? "build \(k.en)" : "upgrade \(name) to level \(next)") + ": \(iceResEN[r]) +\(Int(gain.rounded())) a day (\(Int(made[r])) → \(Int(then[r])))")
                if r == 0, coalNet < 0 { verdict.append("coal would last \(Self.days(Self.lasts(w.stock.coal, coalNet + gain))) instead of \(Self.days(Self.lasts(w.stock.coal, coalNet)))") }
                if r == 2, foodNet < 0 { verdict.append("food would last \(Self.days(Self.lasts(w.stock.food, foodNet + gain))) instead of \(Self.days(Self.lasts(w.stock.food, foodNet)))") }
                if let h = health("saves lives") { verdict.append(h) }
                detail.append(staff >= k.jobs ? "\(k.jobs) more jobs, taken by idle citizens" : staff > 0 ? "\(k.jobs) more jobs, but only \(staff) idle citizens to take them" : "\(k.jobs) more jobs, but nobody is idle to take them")
                if k == .greenhouse { detail.append("a greenhouse grows food whatever the cold outside") }
                if k == .hunting { detail.append("hunting yields less in deep cold and in the blizzard") }
            case .clinic:
                verdict.append((next == 1 ? "build a clinic" : "upgrade the clinic to level \(next)") + ": heals \(Int(now.heals - w.heals)) more sick a day (\(w.sick) sick now)")
                if let h = health("saves lives") { verdict.append(h) }
                detail.append("wounded soldiers mend faster")
            case .barracks:
                verdict.append("upgrade the barracks to level \(next): trains \(now.batch) soldiers at a time instead of \(w.batch), room for \(now.soldierRoom) soldiers instead of \(w.soldierRoom)")
            case .tavern:
                verdict.append(next == 1 ? "build a tavern: generals can be recruited there (room for \(now.heroRoom) generals, you have \(w.generals.count)); morale +0.3 a day"
                                         : "upgrade the tavern to level \(next): room for \(now.heroRoom) generals instead of \(w.heroRoom); morale +0.3 a day more")
            case .wall:
                verdict.append((next == 1 ? "build a wall" : "raise the wall to level \(next)") + ": keeps out the wind")
                if let a = IceJudge.blizzard(w), let b = IceJudge.blizzard(now) {
                    verdict.append("in the great blizzard warm houses would be at \(Self.deg(b.warm)) instead of \(Self.deg(a.warm)), houses outside the heat \(Self.deg(b.cold)) instead of \(Self.deg(a.cold))")
                }
                if let h = health("keeps people warm") { verdict.append(h) }
                detail.append("defence against raiders \(Int(w.defenceAtHome)) → \(Int(now.defenceAtHome))")
            }
            return (verdict + detail + [cost + ", leaving \(Int(w.stock.wood - p.wood)) wood"]).joined(separator: "; ")
        case .recruit(let h):
            let hero = iceHeroes[h]
            var text = "recruit \(hero.name) at the tavern (war \(hero.war), wits \(hero.wit), leadership \(hero.lead); \(hero.skillEN)) for \(hero.food) food and \(hero.iron) iron"
            // What they would do in the field: the hardest county within reach.
            let targets = (1..<iceCounties.count).filter { w.owner[$0] != 0 && w.distance(to: $0) != nil }
            if let c = targets.max(by: { w.defence($0) < w.defence($1) }), w.soldiers >= 10 {
                let n = w.army(h, to: c, arriving: w.day + 2)
                let with = w.battle(h, n, c, on: w.day + 2).chance
                let best = w.freeGenerals.map { w.battle($0, n, c, on: w.day + 2).chance }.max()
                text += "; with \(n) soldiers against \(iceCounties[c].name) \(hero.name) would win about \(Int((with * 100).rounded()))% of the time"
                    + (best.map { " (your best free general now: \(Int(($0 * 100).rounded()))%)" } ?? " (no general is free now)")
            }
            if foodNet < 0 { text += "; food would last \(Self.days(Self.lasts(w.stock.food - Double(hero.food), foodNet))) instead of \(Self.days(Self.lasts(w.stock.food, foodNet)))" }
            text += "; generals \(w.generals.count) → \(w.generals.count + 1) of \(w.heroRoom)"
            return text
        case .train:
            let n = w.trainable
            let hungry = foodNet - Double(n) * 0.5 < 0 && Self.lasts(w.stock.food - Double(n * 2), foodNet - Double(n) * 0.5) < 15
            var verdict = ""
            if hungry {
                verdict = "makes food shorter: food would last \(Self.days(Self.lasts(w.stock.food - Double(n * 2), foodNet - Double(n) * 0.5))) instead of \(Self.days(Self.lasts(w.stock.food, foodNet))), and soldiers eat every day"
            } else {
                // What more soldiers are for: the hardest county within reach, as the best general would fight it.
                let reach = (1..<iceCounties.count).filter { w.owner[$0] != 0 && w.distance(to: $0) != nil }
                if let c = reach.min(by: { w.defence($0) < w.defence($1) }), let h = w.generals.map(\.hero).max(by: { w.punch($0, against: c, on: w.day + 2) < w.punch($1, against: c, on: w.day + 2) }) {
                    let before = IceWorld.chance(Double(w.soldiers) * w.punch(h, against: c, on: w.day + 2) / max(1, w.defence(c)))
                    let after = IceWorld.chance(Double(w.soldiers + n) * w.punch(h, against: c, on: w.day + 2) / max(1, w.defence(c)))
                    verdict = after - before > 0.05 ? "makes conquest likelier: all your soldiers under \(iceHeroes[h].name) would take \(iceCounties[c].name), the weakest county within reach, about \(Int((after * 100).rounded()))% of the time instead of \(Int((before * 100).rounded()))%"
                        : "adds little: all your soldiers under \(iceHeroes[h].name) would take \(iceCounties[c].name), the weakest county within reach, about \(Int((after * 100).rounded()))% of the time either way"
                }
            }
            var text = "train \(n) soldiers (\(n * 2) food, \(n) iron)" + (verdict.isEmpty ? "" : ": " + verdict) + "; soldiers at home \(w.soldiers) → \(w.soldiers + n)"
            if let threat = w.raidThreat { text += "; defence against the \(threat.rival == 0 ? "Wei" : "Wu") raid \(Int(w.defenceAtHome)) → \(Int(now.defenceAtHome)) against about \(Int(threat.raiders))" }
            return text
        case .march(let c, let h, let n, _):
            let hero = iceHeroes[h], county = iceCounties[c]
            let days = w.travel(h, to: c) ?? 2
            let b = w.battle(h, n, c, on: w.day + days)
            let holder = w.owner[c] == 1 ? "held by Wei" : w.owner[c] == 2 ? "held by Wu" : "held by \(iceFoeEN[county.foe])"
            let pct = Int((b.chance * 100).rounded())
            let odds = pct >= 90 ? "almost surely wins" : pct >= 70 ? "wins about \(pct)% of the time" : pct >= 45 ? "a gamble: wins about \(pct)% of the time" : "likely loses: wins only about \(pct)% of the time"
            let people = county.people * (hero.skill == .ruler ? 3 : 2) / 2
            var text = "conquer \(county.name) (\(holder), garrison about \(Int(w.garrison[c].rounded()))), sending \(hero.name) with \(n) soldiers: \(odds); a won county gives +\(Int(county.amount)) \(iceResEN[county.resource]) a day and \(people) more people for good"
            if people > 0 { text += w.citizens + w.waiting + people > w.warmRoom ? " (they move in as warm houses free up; room for \(max(0, w.warmRoom - w.citizens - w.waiting)) now)" : " (there is room for them in warm houses)" }
            text += "; it costs about \(b.winKilled) soldiers killed and \(b.winWounded) wounded if it wins (the wounded heal in a few days), \(b.loseKilled) killed and \(b.loseWounded) wounded if it loses"
            text += "; \(days) days to march there and \(days) back"
            if w.soldiers - n < 10 { text += "; leaves \(w.soldiers - n) soldiers at home" }
            if let threat = w.raidThreat, threat.day - w.day <= days * 2 {
                let p = IceWorld.chance(threat.raiders / max(1, now.defenceAtHome))
                text += "; while it is away a \(threat.rival == 0 ? "Wei" : "Wu") raid of about \(Int(threat.raiders)) would get through \(Int((p * 100).rounded()))% of the time"
            }
            if let post = w.generals.first(where: { $0.hero == h })?.governs { text += "; \(hero.name) stops governing \(post.en)" }
            return text
        case .answer(let choice):
            guard let e = w.event else { return "rest" }
            return eventWords(e, choice, w: w, now: now, after: after, rested: rested, span: span, foodNet: foodNet)
        case .govern(let h, let k):
            let hero = iceHeroes[h]
            if k == .furnace { return "put \(hero.name) in charge of the furnace: it burns \(Int(now.burnRate)) coal a day instead of \(Int(w.burnRate))" + (coalNet < 0 ? "; coal would last \(Self.days(Self.lasts(w.stock.coal, made.coal - now.burnRate))) instead of \(Self.days(Self.lasts(w.stock.coal, coalNet)))" : "") }
            if k == .clinic { return "put \(hero.name) in charge of the clinic: heals \(Int(now.heals)) sick a day instead of \(Int(w.heals)) (\(w.sick) sick now)" }
            let r = k == .coal ? 0 : k == .sawmill ? 1 : k == .iron ? 3 : 2
            return "put \(hero.name) in charge of \(k.en): \(iceResEN[r]) \(Int(made[r])) → \(Int(then[r])) a day while \(hero.name) stays home"
        case .rest:
            // Waiting, said as what it is: the day's work comes in whatever is chosen, so it is not a gain of waiting.
            var text = "do nothing today: nothing is built, trained or sent, and the day is used up"
            if let d = IceJudge.doom(w, rested) { text = "do nothing today, and the city dies by day \(d.day) (\(d.cause))" }
            let idle = w.staffing().idle
            if idle > 0 { text += "; \(idle) idle citizens stay idle" }
            let affordable = moves.filter { if case .build = $0 { return true }; if case .march = $0 { return true }; return false }.count
            if affordable > 0 { text += "; the wood, iron and soldiers that could be put to work today lie unused" }
            if let e = w.event { text += "; the event (\(Self.eventEN[e.kind])) " + (e.left == 1 ? "goes unanswered: \(Self.ignoredEN(e.kind))" : "is left waiting another day") }
            return text
        }
    }

    private static func ignoredEN(_ kind: Int) -> String {
        ["the refugees leave and morale falls 5", "the miners grumble: morale −6", "the furnace burns as usual", "the traders move on", "the fever spreads: 6 more sick",
         "no festival: morale −2", "the hunters stay home: hunting halved for 3 days", "the veterans move on", "the cellar stays shut", "the thief is forgiven: morale +3",
         "a quiet wedding: morale +1"][kind]
    }

    private func eventWords(_ e: IceEvent, _ c: Int, w: IceWorld, now: IceWorld, after: IceWorld, rested: IceWorld, span: Int, foodNet: Double) -> String {
        let dSick = after.tally.sickened - rested.tally.sickened, dDeaths = after.tally.deaths - rested.tally.deaths
        let health = dSick == 0 && dDeaths == 0 ? "" : "; over the next \(span) days \(after.tally.sickened - w.tally.sickened) fall sick and \(after.tally.deaths - w.tally.deaths) die, against \(rested.tally.sickened - w.tally.sickened) and \(rested.tally.deaths - w.tally.deaths) if it is left"
        let foodLast = { (x: IceWorld) -> String in Self.days(Self.lasts(x.stock.food, x.output(x.day).food - x.eats)) }
        switch (e.kind, c) {
        case (0, 0):
            let inside = max(0, w.warmRoom - w.citizens)
            return "take in the \(e.amount) refugees: people \(w.citizens) → \(now.citizens); " + (inside >= e.amount ? "there is room for all of them in warm houses" : "room in warm houses for only \(inside) of them, so \(e.amount - inside) would live outside the heat")
                + "; food lasts \(foodLast(now)) instead of \(foodLast(w)); morale +4" + health
        case (0, _): return "turn the refugees away: morale −5; nothing else changes"
        case (1, 0): return "give the miners their warm day off: morale +6 (\(Int(w.morale)) → \(Int(now.morale))), costs 20 coal" + health
        case (1, _): return "refuse the miners: morale −6 (\(Int(w.morale)) → \(Int(now.morale)))"
        case (2, 0):
            let cold = w.nextCold(after: w.day)
            return "burn double coal through the coming cold (days \(cold?.start ?? w.day)–\(cold?.end ?? w.day)): warm houses +12°C, at about \(Self.deg(now.warmth(cold?.start ?? w.day).warm)) instead of \(Self.deg(w.warmth(cold?.start ?? w.day).warm)); burns \(Int(now.burnRate)) coal a day instead of \(Int(w.burnRate))" + health
                + "; coal \(Int(w.stock.coal)) now, " + (after.tally.firstCoalOut != nil && after.tally.firstCoalOut! > w.day ? "it would run out on day \(after.tally.firstCoalOut!)" : "enough for it")
        case (2, _): return "keep burning coal as usual through the cold spell; warm houses at about \(Self.deg(w.warmth(w.nextCold(after: w.day)?.start ?? w.day).warm)) when it comes" + health
        case (3, 0): return "trade 60 wood for 50 food with the caravan: wood \(Int(w.stock.wood)) → \(Int(now.stock.wood)), food \(Int(w.stock.food)) → \(Int(now.stock.food)); food lasts \(foodLast(now)) instead of \(foodLast(w))" + health
        case (3, 1): return "trade 30 iron for 60 coal with the caravan: iron \(Int(w.stock.iron)) → \(Int(now.stock.iron)), coal \(Int(w.stock.coal)) → \(Int(now.stock.coal))" + health
        case (3, 2): return "trade 80 wood for 30 iron with the caravan: wood \(Int(w.stock.wood)) → \(Int(now.stock.wood)), iron \(Int(w.stock.iron)) → \(Int(now.stock.iron))"
        case (3, _): return "let the caravan pass without trading"
        case (4, 0): return "open the stores to brew medicine for the fever: cures \(min(8, w.sick)) sick now, costs 30 food, morale +2" + health
        case (4, _): return "let the fever run its course: 6 more people fall sick" + health
        case (5, 0): return "hold the ice-lantern festival: morale +9 (\(Int(w.morale)) → \(Int(now.morale))), costs 25 food and 20 wood" + health
        case (5, _): return "skip the festival: morale −2"
        case (6, 0): return "send 20 soldiers to hunt the wolves: +50 food from the hunt, 4 soldiers wounded"
        case (6, _): return "keep the hunters inside: hunting yields half for 3 days"
        case (7, 0): return "take in the veterans: soldiers +12 (\(w.soldiers) → \(now.soldiers)), costs 30 food"
        case (7, _): return "turn the veterans away"
        case (8, 0): return "dig out the ice cellar: +90 food for 30 wood; food lasts \(foodLast(now)) instead of \(foodLast(w))"
        case (8, _): return "leave the ice cellar shut"
        case (9, 0): return "punish the coal thief: 25 coal recovered, morale −3"
        case (9, _): return "forgive the coal thief: morale +3"
        case (10, 0): return "throw the couple a wedding feast: morale +5, costs 15 food"
        default: return "a quiet wedding: morale +1"
        }
    }

    /// A move by a short Chinese name, for a person to click.
    private func name(_ m: IceMove, in w: IceWorld) -> String {
        switch m {
        case .build(let k):
            let p = w.price(k)
            let cost = "（\(Int(p.wood)) 木" + (p.iron > 0 ? " \(Int(p.iron)) 铁）" : "）")
            if k == .house { return "盖一座民居" + cost }
            return (w.level[k.rawValue] == 0 ? "建\(k.cn)" : "升级\(k.cn)到 \(w.level[k.rawValue] + 1) 级") + cost
        case .recruit(let h): return "招募\(iceHeroes[h].name)（\(iceHeroes[h].food) 粮 \(iceHeroes[h].iron) 铁）"
        case .train: return "训练 \(w.trainable) 个兵（\(w.trainable * 2) 粮 \(w.trainable) 铁）"
        case .march(let c, let h, let n, _):
            let days = w.travel(h, to: c) ?? 2
            let p = Int((w.battle(h, n, c, on: w.day + days).chance * 100).rounded())
            return "派\(iceHeroes[h].name)带 \(n) 兵打\(iceCounties[c].name)（胜算 \(p)%）"
        case .answer(let c): return w.event.map { IceWorld.choices($0.kind)[c] } ?? "回应"
        case .govern(let h, let k): return "让\(iceHeroes[h].name)管\(k.cn)"
        case .rest: return "休养一天"
        }
    }

    // MARK: A person's clicks

    /// Rows of the picture a click can land on: 0 a building (col = its kind), 1 a county (col = its index), 2 an event's choice.
    func tap(row: Int, col: Int, among options: [JevOption]) -> JevReaction {
        guard !world.over else { return .nothing }
        let w = world
        func option(_ wanted: (IceMove) -> Bool) -> JevOption? {
            options.first { moves.indices.contains($0.move) && wanted(moves[$0.move]) }
        }
        switch row {
        case 0:
            guard let k = IceKind(rawValue: col) else { return .nothing }
            if let o = option({ $0 == .build(k) }) { return .choose(o) }
            if k == .tavern, w.has(.tavern) {
                if let o = option({ if case .recruit = $0 { return true }; return false }) { return .choose(o) }
                if w.generals.count >= w.heroRoom { return .explain("酒馆坐满了：升级酒馆才能再招武将") }
            }
            if k == .barracks, w.has(.barracks), let o = option({ $0 == .train }) { return .choose(o) }
            return .explain(w.whyNot(k))
        case 1:
            guard iceCounties.indices.contains(col), col > 0 else { return .explain("这是我们自己的城") }
            if w.owner[col] == 0 { return .explain("\(iceCounties[col].name)已经是我们的了") }
            if let o = option({ if case .march(let c, _, _, _) = $0 { return c == col }; return false }) { return .choose(o) }
            if w.marches.contains(where: { $0.county == col && !$0.back }) { return .explain("已经有兵在去\(iceCounties[col].name)的路上了") }
            if w.distance(to: col) == nil { return .explain("\(iceCounties[col].name)还太远：先打下和它相连的州府") }
            if w.freeGenerals.isEmpty { return .explain("没有空闲的武将能带兵") }
            if w.soldiers < 10 { return .explain("兵不够：至少要 10 个") }
            return .explain("现在出不了兵")
        case 2:
            if let o = option({ $0 == .answer(col) }) { return .choose(o) }
            if let e = w.event, IceWorld.choices(e.kind).indices.contains(col) { return .explain("现在做不到：\(IceWorld.choices(e.kind)[col])") }
            return .nothing
        case 3:
            if let o = option({ $0 == .rest }) { return .choose(o) }
            return .nothing
        default:
            return .nothing
        }
    }

    var position: String { situation }
}

// MARK: - The picture

extension JevIceKingdoms: JevPainted {
    var aspect: Double { 1.25 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = IceScene(before: previous, after: world, t: t, since: since, now: now, score: score, person: person)
        return JevPicture { g, size in scene.paint(&g, size) }
    }

    /// Rows: 0 a building (col = its kind), 1 a county on the map (col = its index), 2 a choice on the event card, 3 the rest button.
    func spot(at point: CGPoint, in size: CGSize) -> (row: Int, col: Int)? {
        let k = IceLook.W / max(size.width, 1)
        return IceLook.hit(CGPoint(x: point.x * k, y: point.y * k), world)
    }
}

/// Where everything is, in a picture 640 wide and 512 tall: the city on the left around its furnace, seen from the
/// south at three-quarters; the map and the day's card on the right; the generals along the bottom; numbers on top.
fileprivate enum IceLook {
    static let W: CGFloat = 640, H: CGFloat = 512
    static let centre = CGPoint(x: 212, y: 268)
    static let squash: CGFloat = 0.64
    /// How far the heat reaches at each furnace level (across; up and down it is squashed).
    static let heat: [CGFloat] = [0, 94, 116, 138, 160, 184]
    static let rings: [(r: CGFloat, angles: [Double])] = [
        (72, [118, 168, 218, 270, 322, 12, 62]),
        (100, [0, 180, 242, 298]),
        (122, [30, 150, 212, 328]),
        (146, [270, 352, 188, 60, 120]),
        (168, [224, 316, 40, 140]),
    ]
    static let houseSpots: [CGPoint] = rings.flatMap { ring in ring.angles.map { at($0, ring.r) } }
    static let angle: [IceKind: Double] = [.coal: 246, .iron: 294, .sawmill: 202, .hunting: 338, .greenhouse: 18, .barracks: 64, .tavern: 116, .clinic: 160]
    static let buildingR: CGFloat = 192, wallR: CGFloat = 210
    static let mapBox = CGRect(x: 430, y: 42, width: 204, height: 250)
    static let cardBox = CGRect(x: 430, y: 298, width: 204, height: 150)
    static let strip = CGRect(x: 6, y: 455, width: 628, height: 52)

    static func at(_ deg: Double, _ r: CGFloat) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: centre.x + CGFloat(cos(a)) * r, y: centre.y + CGFloat(sin(a)) * r * squash)
    }
    static func spot(_ k: IceKind) -> CGPoint { k == .furnace ? centre : at(angle[k] ?? 90, buildingR) }
    static func node(_ c: Int) -> CGPoint {
        CGPoint(x: mapBox.minX + 14 + (mapBox.width - 28) * CGFloat(iceCounties[c].x), y: mapBox.minY + 34 + (mapBox.height - 50) * CGFloat(iceCounties[c].y))
    }
    /// The buttons on the day's card: an answer to each choice of the event, and a day's rest.
    static func buttons(_ w: IceWorld) -> [(rect: CGRect, row: Int, col: Int, text: String, on: Bool)] {
        var out: [(CGRect, Int, Int, String, Bool)] = []
        if let e = w.event {
            let choices = IceWorld.choices(e.kind)
            let h: CGFloat = choices.count > 3 ? 19 : 22
            for (i, c) in choices.enumerated() {
                out.append((CGRect(x: cardBox.minX + 10, y: cardBox.minY + 40 + CGFloat(i) * (h + 4), width: cardBox.width - 20, height: h), 2, i, c, w.can(e, i)))
            }
        }
        out.append((CGRect(x: cardBox.maxX - 86, y: cardBox.maxY - 24, width: 78, height: 18), 3, 0, "休养一天 ▸", true))
        return out
    }

    static func hit(_ p: CGPoint, _ w: IceWorld) -> (row: Int, col: Int)? {
        for b in buttons(w) where b.rect.insetBy(dx: -2, dy: -2).contains(p) { return (b.row, b.col) }
        if mapBox.contains(p) {
            let near = (0..<iceCounties.count).min { hypot(node($0).x - p.x, node($0).y - p.y) < hypot(node($1).x - p.x, node($1).y - p.y) }!
            return hypot(node(near).x - p.x, node(near).y - p.y) < 16 ? (1, near) : nil
        }
        guard p.x < mapBox.minX - 4, p.y > 36, p.y < strip.minY else { return nil }
        if abs(p.x - centre.x) < 30, p.y > centre.y - 82, p.y < centre.y + 14 { return (0, IceKind.furnace.rawValue) }
        for (k, _) in angle {
            let s = spot(k)
            if abs(p.x - s.x) < 26, p.y > s.y - 42, p.y < s.y + 10 { return (0, k.rawValue) }
        }
        for (i, s) in houseSpots.enumerated() where i <= w.houses {
            if abs(p.x - s.x) < 16, p.y > s.y - 30, p.y < s.y + 8 { return (0, IceKind.house.rawValue) }
        }
        let dx = (p.x - centre.x) / wallR, dy = (p.y - centre.y) / (wallR * squash)
        if abs(hypot(dx, dy) - 1) < 0.07 { return (0, IceKind.wall.rawValue) }
        return nil
    }
}

/// What never moves — the sky, the hills, the pines, the snowfield and its paths, the map's land — painted once
/// for a canvas size with CoreGraphics and laid under every frame.
fileprivate enum IceBackdrop {
    nonisolated(unsafe) static var kept: (key: String, image: CGImage)?

    static func image(_ size: CGSize, scale: CGFloat) -> CGImage? {
        let key = "\(Int(size.width * 4))x\(Int(size.height * 4))@\(Int(scale * 4))"
        if let kept, kept.key == key { return kept.image }
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let k = scale * size.width / IceLook.W
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: k, y: -k)
        paint(c, space)
        guard let image = c.makeImage() else { return nil }
        kept = (key, image)
        return image
    }

    /// Words set once with CoreText: centred on a point (anchor 0), or starting (−1) or ending (1) there.
    static func label(_ c: CGContext, _ text: String, _ p: CGPoint, size: CGFloat, colour: CGColor, anchor: Int = 0) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("PingFangSC-Semibold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                         NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        c.saveGState()
        c.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        c.textPosition = CGPoint(x: anchor == 0 ? p.x - width / 2 : anchor < 0 ? p.x : p.x - width, y: p.y + (ascent - descent) / 2)
        CTLineDraw(line, c)
        c.restoreGState()
    }

    static func rgb(_ v: (Double, Double, Double), _ a: Double = 1) -> CGColor { CGColor(srgbRed: CGFloat(v.0), green: CGFloat(v.1), blue: CGFloat(v.2), alpha: CGFloat(a)) }
    static func u(_ a: Int, _ b: Int) -> CGFloat { CGFloat(JevDraw.hash(a, b) % 10_000) / 10_000 }

    static func paint(_ c: CGContext, _ space: CGColorSpace) {
        let W = IceLook.W, H = IceLook.H
        func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient? { CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1)) }
        func linear(_ path: CGPath?, _ stops: [(CGColor, CGFloat)], _ a: CGPoint, _ b: CGPoint) {
            guard let lit = gradient(stops) else { return }
            c.saveGState(); if let path { c.addPath(path); c.clip() }
            c.drawLinearGradient(lit, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); c.restoreGState()
        }
        func glow(_ colour: (Double, Double, Double), _ alpha: Double, at p: CGPoint, r: CGFloat, squash: CGFloat = 1) {
            guard let lit = gradient([(rgb(colour, alpha), 0), (rgb(colour, 0), 1)]) else { return }
            c.saveGState(); c.translateBy(x: p.x, y: p.y); c.scaleBy(x: 1, y: squash)
            c.drawRadialGradient(lit, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: []); c.restoreGState()
        }
        func fill(_ path: CGPath, _ colour: CGColor) { c.addPath(path); c.setFillColor(colour); c.fillPath() }
        func ellipse(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }
        func pine(_ foot: CGPoint, _ s: CGFloat, _ v: Int) {
            fill(ellipse(CGRect(x: foot.x - s * 0.3, y: foot.y - s * 0.1, width: s * 1.1, height: s * 0.26)), rgb((0.45, 0.52, 0.66), 0.25))
            fill(CGPath(rect: CGRect(x: foot.x - s * 0.06, y: foot.y - s * 0.3, width: s * 0.12, height: s * 0.3), transform: nil), rgb((0.36, 0.26, 0.2)))
            let green = (0.16 + 0.05 * Double(u(v, 1)), 0.36 + 0.08 * Double(u(v, 2)), 0.34 + 0.06 * Double(u(v, 3)))
            for tier in 0..<3 {
                let t = CGFloat(tier), w = s * (0.5 - t * 0.12), bottom = foot.y - s * (0.2 + t * 0.32), top = bottom - s * 0.52
                let body = CGMutablePath(); body.addLines(between: [CGPoint(x: foot.x, y: top), CGPoint(x: foot.x + w, y: bottom), CGPoint(x: foot.x - w, y: bottom)]); body.closeSubpath()
                fill(body, rgb(green))
                let lit = CGMutablePath(); lit.addLines(between: [CGPoint(x: foot.x, y: top), CGPoint(x: foot.x, y: bottom), CGPoint(x: foot.x - w, y: bottom)]); lit.closeSubpath()
                fill(lit, rgb((green.0 * 1.25, green.1 * 1.2, green.2 * 1.15)))
                let cap = CGMutablePath()
                cap.move(to: CGPoint(x: foot.x, y: top))
                cap.addLine(to: CGPoint(x: foot.x + w * 0.7, y: top + (bottom - top) * 0.72))
                cap.addQuadCurve(to: CGPoint(x: foot.x - w * 0.7, y: top + (bottom - top) * 0.72), control: CGPoint(x: foot.x, y: top + (bottom - top) * 0.95))
                cap.closeSubpath()
                fill(cap, rgb((0.97, 0.98, 1)))
            }
        }

        // The sky, low and pale, and the hills under it.
        linear(nil, [(rgb((0.62, 0.72, 0.88)), 0), (rgb((0.84, 0.88, 0.95)), 0.14), (rgb((0.9, 0.93, 0.98)), 0.2), (rgb((0.94, 0.96, 0.99)), 1)], .zero, CGPoint(x: 0, y: H))
        glow((1, 0.93, 0.82), 0.5, at: CGPoint(x: 120, y: 58), r: 160, squash: 0.45)
        for (k, (x0, peak, colour)) in [(0.0, 64.0, (0.68, 0.74, 0.86)), (190, 58, (0.62, 0.69, 0.83)), (420, 62, (0.66, 0.72, 0.85))].enumerated() {
            let hill = CGMutablePath()
            hill.move(to: CGPoint(x: CGFloat(x0) - 60, y: 104))
            var x = CGFloat(x0) - 60
            while x < CGFloat(x0) + 330 {
                let y = CGFloat(peak) + 22 * sin(x / 37 + CGFloat(k)) * 0.6 + 14 * sin(x / 13 + CGFloat(k) * 2) * 0.4
                hill.addLine(to: CGPoint(x: x, y: y)); x += 8
            }
            hill.addLine(to: CGPoint(x: CGFloat(x0) + 330, y: 104)); hill.closeSubpath()
            fill(hill, rgb(colour))
            c.saveGState(); c.addPath(hill); c.clip()
            linear(nil, [(rgb((1, 1, 1), 0.75), 0), (rgb((1, 1, 1), 0), 1)], CGPoint(x: 0, y: CGFloat(peak) - 10), CGPoint(x: 0, y: CGFloat(peak) + 26))
            c.restoreGState()
        }
        // The snowfield.
        let field = CGMutablePath()
        field.move(to: CGPoint(x: 0, y: 96))
        var x: CGFloat = 0
        while x <= W { field.addLine(to: CGPoint(x: x, y: 96 + 5 * sin(x / 41))); x += 10 }
        field.addLine(to: CGPoint(x: W, y: H)); field.addLine(to: CGPoint(x: 0, y: H)); field.closeSubpath()
        linear(field, [(rgb((0.88, 0.92, 0.98)), 0), (rgb((0.95, 0.97, 1)), 0.5), (rgb((0.9, 0.93, 0.98)), 1)], CGPoint(x: 0, y: 96), CGPoint(x: 0, y: H))
        c.saveGState(); c.addPath(field); c.clip()
        // Drifts: light on the upper left, a blue shade on the lower right.
        for i in 0..<34 {
            let p = CGPoint(x: u(i, 5) * W, y: 110 + u(i, 6) * (H - 110)), r = 20 + u(i, 7) * 46
            glow((0.62, 0.72, 0.9), 0.2, at: CGPoint(x: p.x + r * 0.25, y: p.y + r * 0.18), r: r, squash: 0.5)
            glow((1, 1, 1), 0.7, at: CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.12), r: r * 0.8, squash: 0.45)
        }
        // Sparkle and grain.
        for i in 0..<420 {
            let p = CGPoint(x: u(i, 8) * W, y: 100 + u(i, 9) * (H - 100)), r = 0.4 + u(i, 10) * 0.9
            fill(ellipse(CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), i % 3 == 0 ? rgb((0.6, 0.7, 0.88), 0.35) : rgb((1, 1, 1), 0.9))
        }
        c.restoreGState()
        // Trodden snow: the square round the furnace, and paths out to every building and the gate.
        let hub = IceLook.centre
        let trod = rgb((0.8, 0.85, 0.93)), middle = rgb((0.88, 0.91, 0.96))
        let paths = CGMutablePath()
        for (_, a) in IceLook.angle { paths.move(to: hub); paths.addLine(to: IceLook.at(a, IceLook.buildingR)) }
        paths.move(to: hub); paths.addLine(to: IceLook.at(90, IceLook.wallR + 40))
        c.setLineCap(.round)
        c.addPath(paths); c.setStrokeColor(trod); c.setLineWidth(11); c.strokePath()
        c.addPath(paths); c.setStrokeColor(middle); c.setLineWidth(6); c.strokePath()
        let ring = CGMutablePath()
        ring.addEllipse(in: CGRect(x: hub.x - 118, y: hub.y - 118 * IceLook.squash, width: 236, height: 236 * IceLook.squash))
        c.addPath(ring); c.setStrokeColor(trod); c.setLineWidth(7); c.strokePath()
        c.addPath(ring); c.setStrokeColor(middle); c.setLineWidth(3.5); c.strokePath()
        fill(ellipse(CGRect(x: hub.x - 50, y: hub.y - 50 * IceLook.squash, width: 100, height: 100 * IceLook.squash)), trod)
        fill(ellipse(CGRect(x: hub.x - 44, y: hub.y - 44 * IceLook.squash, width: 88, height: 88 * IceLook.squash)), rgb((0.76, 0.8, 0.88)))
        for i in 0..<14 {
            let a = Double(i) / 14 * 2 * .pi, p = CGPoint(x: hub.x + CGFloat(cos(a)) * 38, y: hub.y + CGFloat(sin(a)) * 38 * IceLook.squash)
            fill(ellipse(CGRect(x: p.x - 5, y: p.y - 3, width: 10, height: 6)), rgb((0.7, 0.74, 0.82)))
        }
        // Pines outside the wall: along the far edge, down the sides and in the corners.
        var trees: [(CGPoint, CGFloat, Int)] = []
        for i in 0..<60 {
            let a = Double(i) / 60 * 2 * .pi
            let r = IceLook.wallR + 26 + 30 * u(i, 11)
            let p = CGPoint(x: hub.x + CGFloat(cos(a)) * r, y: hub.y + CGFloat(sin(a)) * r * IceLook.squash)
            if p.y > 380 && abs(p.x - hub.x) < 60 { continue }          // the road out of the gate
            if p.x > 424 || p.x < -10 || p.y < 92 { continue }
            trees.append((p, 22 + 12 * u(i, 12), i))
        }
        for i in 0..<40 {
            let p = CGPoint(x: 424 + u(i, 13) * 220, y: 98 + u(i, 14) * 360)
            trees.append((p, 20 + 14 * u(i, 15), i + 100))
        }
        for i in 0..<16 {
            let p = CGPoint(x: u(i, 16) * 420, y: 96 + u(i, 17) * 14)
            trees.append((p, 16 + 8 * u(i, 18), i + 200))
        }
        for (p, s, v) in trees.sorted(by: { $0.0.y < $1.0.y }) { pine(p, s, v) }
        // Rocks with snow on them.
        for i in 0..<9 {
            let a = Double(i) * 0.83 + 0.4, r = 58 + 150 * u(i, 19)
            let p = CGPoint(x: hub.x + CGFloat(cos(a)) * r, y: hub.y + CGFloat(sin(a)) * r * IceLook.squash)
            if IceLook.houseSpots.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 20 }) { continue }
            if IceLook.angle.values.contains(where: { hypot(IceLook.at($0, IceLook.buildingR).x - p.x, IceLook.at($0, IceLook.buildingR).y - p.y) < 30 }) { continue }
            let s = 5 + 4 * u(i, 20)
            fill(ellipse(CGRect(x: p.x - s, y: p.y - s * 0.5, width: s * 2.2, height: s * 0.9)), rgb((0.4, 0.46, 0.6), 0.25))
            fill(ellipse(CGRect(x: p.x - s, y: p.y - s * 1.1, width: s * 2, height: s * 1.4)), rgb((0.52, 0.55, 0.62)))
            fill(ellipse(CGRect(x: p.x - s * 0.9, y: p.y - s * 1.2, width: s * 1.7, height: s * 0.8)), rgb((0.97, 0.98, 1)))
        }
        // The map's land: ice-blue parchment, hills, a frozen river, woods.
        let box = IceLook.mapBox
        let sheet = CGPath(roundedRect: box, cornerWidth: 12, cornerHeight: 12, transform: nil)
        fill(CGPath(roundedRect: box.offsetBy(dx: 2, dy: 4), cornerWidth: 12, cornerHeight: 12, transform: nil), rgb((0.1, 0.16, 0.3), 0.25))
        linear(sheet, [(rgb((0.95, 0.97, 1)), 0), (rgb((0.86, 0.91, 0.97)), 1)], box.origin, CGPoint(x: box.maxX, y: box.maxY))
        c.saveGState(); c.addPath(sheet); c.clip()
        let river = CGMutablePath()
        river.move(to: CGPoint(x: box.minX, y: box.minY + box.height * 0.84))
        river.addCurve(to: CGPoint(x: box.minX + box.width * 0.56, y: box.minY + box.height * 0.8),
                       control1: CGPoint(x: box.minX + box.width * 0.2, y: box.minY + box.height * 0.9), control2: CGPoint(x: box.minX + box.width * 0.38, y: box.minY + box.height * 0.74))
        river.addCurve(to: CGPoint(x: box.maxX, y: box.minY + box.height * 0.84),
                       control1: CGPoint(x: box.minX + box.width * 0.74, y: box.minY + box.height * 0.86), control2: CGPoint(x: box.minX + box.width * 0.86, y: box.minY + box.height * 0.76))
        c.addPath(river); c.setStrokeColor(rgb((0.62, 0.78, 0.92))); c.setLineWidth(7); c.strokePath()
        c.addPath(river); c.setStrokeColor(rgb((0.84, 0.93, 1))); c.setLineWidth(3); c.strokePath()
        for i in 0..<16 {
            let p = CGPoint(x: box.minX + 10 + u(i, 21) * (box.width - 20), y: box.minY + 30 + u(i, 22) * 70)
            let s = 7 + 7 * u(i, 23)
            let m = CGMutablePath(); m.addLines(between: [CGPoint(x: p.x - s, y: p.y + s * 0.5), CGPoint(x: p.x, y: p.y - s * 0.6), CGPoint(x: p.x + s, y: p.y + s * 0.5)]); m.closeSubpath()
            fill(m, rgb((0.64, 0.7, 0.82)))
            let cap = CGMutablePath(); cap.addLines(between: [CGPoint(x: p.x - s * 0.45, y: p.y - s * 0.05), CGPoint(x: p.x, y: p.y - s * 0.6), CGPoint(x: p.x + s * 0.45, y: p.y - s * 0.05)]); cap.closeSubpath()
            fill(cap, rgb((1, 1, 1)))
        }
        for i in 0..<34 {
            let p = CGPoint(x: box.minX + 8 + u(i, 24) * (box.width - 16), y: box.minY + 110 + u(i, 25) * (box.height - 120))
            let s: CGFloat = 5
            let m = CGMutablePath(); m.addLines(between: [CGPoint(x: p.x - s * 0.5, y: p.y + s * 0.4), CGPoint(x: p.x, y: p.y - s * 0.7), CGPoint(x: p.x + s * 0.5, y: p.y + s * 0.4)]); m.closeSubpath()
            fill(m, rgb((0.42, 0.58, 0.56), 0.55))
        }
        c.restoreGState()
        c.addPath(sheet); c.setStrokeColor(rgb((0.36, 0.46, 0.64), 0.7)); c.setLineWidth(1.5); c.strokePath()
        // The map's names and title, which never change.
        label(c, "冰原舆图", CGPoint(x: box.minX + 12, y: box.minY + 14), size: 12, colour: rgb((0.2, 0.28, 0.46)), anchor: -1)
        for (i, county) in iceCounties.enumerated() {
            let p = IceLook.node(i), r: CGFloat = county.capital ? 9 : 7
            label(c, county.name, CGPoint(x: p.x, y: p.y + r + 6), size: 7.5, colour: rgb((0.16, 0.2, 0.32)))
        }
        // The bar along the top: glass panels and the names of the stores.
        linear(CGPath(rect: CGRect(x: 0, y: 0, width: W, height: 36), transform: nil), [(rgb((0.1, 0.14, 0.28), 0.95), 0), (rgb((0.14, 0.2, 0.36), 0.9), 1)], .zero, CGPoint(x: 0, y: 36))
        fill(CGPath(rect: CGRect(x: 0, y: 35, width: W, height: 1), transform: nil), rgb((1, 1, 1), 0.25))
        for r in [CGRect(x: 5, y: 5, width: 128, height: 26), CGRect(x: 138, y: 5, width: 330, height: 26), CGRect(x: 473, y: 5, width: 162, height: 26)] {
            let glass = CGPath(roundedRect: r, cornerWidth: 9, cornerHeight: 9, transform: nil)
            linear(glass, [(rgb((1, 1, 1), 0.2), 0), (rgb((1, 1, 1), 0.07), 1)], CGPoint(x: 0, y: r.minY), CGPoint(x: 0, y: r.maxY))
            c.addPath(glass); c.setStrokeColor(rgb((1, 1, 1), 0.28)); c.setLineWidth(0.8); c.strokePath()
        }
        let tints: [(Double, Double, Double)] = [(0.25, 0.25, 0.3), (0.7, 0.48, 0.26), (0.95, 0.66, 0.24), (0.6, 0.64, 0.72), (0.24, 0.62, 0.36)]
        for (i, name) in ["煤", "木", "粮", "铁", "兵"].enumerated() {
            let x = 146 + CGFloat(i) * 65
            fill(CGPath(roundedRect: CGRect(x: x, y: 10, width: 16, height: 16), cornerWidth: 5, cornerHeight: 5, transform: nil), rgb(tints[i]))
            label(c, name, CGPoint(x: x + 8, y: 18), size: 10, colour: rgb((1, 1, 1)))
        }
        label(c, "民心", CGPoint(x: 530, y: 18), size: 9.5, colour: rgb((1, 1, 1)), anchor: -1)
        fill(CGPath(roundedRect: CGRect(x: 556, y: 13, width: 72, height: 10), cornerWidth: 5, cornerHeight: 5, transform: nil), rgb((0, 0, 0), 0.35))
        let bulb = CGPoint(x: 80, y: 23)
        fill(CGPath(roundedRect: CGRect(x: bulb.x - 2.5, y: 9, width: 5, height: 14), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil), rgb((1, 1, 1), 0.9))
        // The generals' tray.
        let tray = CGPath(roundedRect: IceLook.strip, cornerWidth: 12, cornerHeight: 12, transform: nil)
        fill(tray, rgb((0.12, 0.17, 0.3), 0.72))
        c.addPath(tray); c.setStrokeColor(rgb((1, 1, 1), 0.2)); c.setLineWidth(1); c.strokePath()
        // The corners darker and bluer, the cold closing in round the city.
        c.saveGState()
        c.addRect(CGRect(x: 0, y: 36, width: W, height: H - 36)); c.clip()
        if let edge = gradient([(rgb((0.2, 0.3, 0.55), 0), 0), (rgb((0.2, 0.3, 0.55), 0), 0.55), (rgb((0.2, 0.3, 0.55), 0.2), 1)]) {
            c.drawRadialGradient(edge, startCenter: IceLook.centre, startRadius: 0, endCenter: IceLook.centre, endRadius: 440, options: [.drawsAfterEndLocation])
        }
        c.restoreGState()
        c.addPath(CGPath(roundedRect: box.insetBy(dx: 4, dy: 4), cornerWidth: 9, cornerHeight: 9, transform: nil)); c.setStrokeColor(rgb((0.36, 0.46, 0.64), 0.25)); c.setLineWidth(0.8); c.strokePath()
    }
}

/// Soft round lights painted once and then only placed: the furnace's heat on the snow, and a gust of blown snow.
fileprivate enum IceSprites {
    nonisolated(unsafe) static var heat: CGImage? = make([(1, 0.62, 0.24, 0.42), (1, 0.7, 0.36, 0.26), (1, 0.78, 0.5, 0.14), (1, 0.8, 0.55, 0)], [0, 0.58, 0.86, 1])
    nonisolated(unsafe) static var gust: CGImage? = make([(1, 1, 1, 0.62), (1, 1, 1, 0.2), (1, 1, 1, 0)], [0, 0.5, 1])

    static func make(_ stops: [(Double, Double, Double, Double)], _ at: [CGFloat]) -> CGImage? {
        let side = 256
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: space, colors: stops.map { CGColor(srgbRed: CGFloat($0.0), green: CGFloat($0.1), blue: CGFloat($0.2), alpha: CGFloat($0.3)) } as CFArray, locations: at) else { return nil }
        let mid = CGPoint(x: side / 2, y: side / 2)
        c.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: CGFloat(side / 2), options: [])
        return c.makeImage()
    }
}

/// One moment of the city, ready to be drawn.
fileprivate struct IceScene {
    let before: IceWorld, after: IceWorld, t: Double, since: Double, now: Double, score: Int, person: Bool

    static let shu: Art.RGB = (0.24, 0.62, 0.36), wei: Art.RGB = (0.26, 0.46, 0.86), wu: Art.RGB = (0.86, 0.3, 0.26)
    static func owner(_ o: Int) -> Art.RGB { [shu, wei, wu, (0.93, 0.94, 0.97)][o] }
    static let coats: [Art.RGB] = [(0.86, 0.3, 0.26), (0.26, 0.5, 0.8), (0.32, 0.6, 0.42), (0.9, 0.6, 0.22), (0.62, 0.38, 0.72), (0.55, 0.4, 0.3)]
    static func c(_ v: Art.RGB, _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }

    var storm: Double {
        let d = after.day - 1
        if after.inBlizzard(d) || after.inBlizzard(after.day) { return 1 }
        return 0
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let k = size.width / IceLook.W
        let scale = g.environment.displayScale
        if let back = IceBackdrop.image(size, scale: scale) {
            g.draw(Image(decorative: back, scale: scale), in: CGRect(origin: .zero, size: size))
        }
        g.scaleBy(x: k, y: k)
        city(&g)
        weather(g)
        map(g)
        card(g)
        generals(g)
        hud(g)
        reports(g)
        if let end = after.ended {
            let alive = after.citizens > 0 && after.outDays < IceWorld.outLimit
            let title = alive ? (end == "天下一统" ? "天下一统！" : "熬过了冰河的一百天") : (after.outDays >= IceWorld.outLimit ? "城冻住了" : "城里的人都没了")
            let detail = "\(after.citizens) 人 · \(after.counties) 州 · \(after.generals.count) 员武将 · 得分 \(score)"
            JevDraw.curtain(g, CGSize(width: IceLook.W, height: IceLook.H), title: title, detail: detail)
            if !alive {
                g.fill(Path(CGRect(x: 0, y: 0, width: IceLook.W, height: IceLook.H)), with: .color(Color(red: 0.7, green: 0.85, blue: 1).opacity(0.18)))
            }
        }
    }

    // MARK: The city

    private func city(_ g: inout GraphicsContext) {
        let w = after, hub = IceLook.centre
        // The heat on the snow: a warm circle as far as the furnace reaches, breathing a little.
        let lit = w.outDays == 0 && w.furnace > 0
        let r = JevDraw.mix(Double(IceLook.heat[before.furnace]), Double(IceLook.heat[w.furnace]), JevDraw.smooth(t)) * (1 + 0.015 * sin(now * 2.2))
        if lit {
            let R = CGFloat(r)
            var warm = g
            warm.translateBy(x: hub.x, y: hub.y); warm.scaleBy(x: 1, y: IceLook.squash)
            if let heat = IceSprites.heat { warm.draw(Image(decorative: heat, scale: 1), in: CGRect(x: -R * 1.08, y: -R * 1.08, width: R * 2.16, height: R * 2.16)) }
            warm.stroke(Path(ellipseIn: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R)), with: .color(Color(red: 1, green: 0.66, blue: 0.3).opacity(0.35)),
                        style: StrokeStyle(lineWidth: 1.4 / IceLook.squash, dash: [5, 5], dashPhase: CGFloat(now * 6)))
        }
        if w.wall > 0 { wall(g, back: true) } else {
            // Where a wall would go: a line of stakes in the snow.
            let R = IceLook.wallR
            g.stroke(Path(ellipseIn: CGRect(x: hub.x - R, y: hub.y - R * IceLook.squash, width: 2 * R, height: 2 * R * IceLook.squash)),
                     with: .color(Color(red: 0.45, green: 0.52, blue: 0.66).opacity(w.canBuild(.wall) ? 0.55 : 0.3)), style: StrokeStyle(lineWidth: 1.2, dash: [2, 6]))
        }
        // Everything that stands, from the back to the front.
        var standing: [(CGFloat, (inout GraphicsContext) -> Void)] = []
        let reach = IceWorld.reach[w.furnace]
        for i in 0..<min(w.houses, IceLook.houseSpots.count) {
            let p = IceLook.houseSpots[i]
            let rise = w.raised == .house && i == w.houses - 1 ? growth : 1
            standing.append((p.y, { g in self.house(&g, p, warm: i < reach && lit, seed: i, rise: rise) }))
        }
        for (kind, _) in IceLook.angle {
            let p = IceLook.spot(kind), level = w.level[kind.rawValue]
            if level == 0 {
                standing.append((p.y - 1, { g in self.plot(g, p, kind) }))
            } else {
                let rise = w.raised == kind ? growth : 1
                standing.append((p.y, { g in self.building(&g, kind, p, level: level, rise: rise) }))
            }
        }
        standing.append((hub.y + 4, { g in self.furnace(&g) }))
        // People in their furs, going between the furnace and their work; fewer out in a storm.
        let out = storm > 0 ? 3 : min(18, 4 + w.citizens / 6)
        let places: [CGPoint] = IceLook.angle.keys.sorted { $0.rawValue < $1.rawValue }.filter { w.level[$0.rawValue] > 0 }.map { IceLook.spot($0) }
            + IceLook.houseSpots.prefix(max(1, min(w.houses, 12)))
        for n in 0..<out {
            let seed = n * 7 + 3
            let to = places[JevDraw.hash(seed, 11) % places.count]
            let from = CGPoint(x: hub.x + CGFloat(JevDraw.hash(seed, 12) % 60 - 30), y: hub.y + 30 + CGFloat(JevDraw.hash(seed, 13) % 16))
            let phase = (now * (0.035 + 0.01 * Double(JevDraw.hash(seed, 14) % 4)) + Double(JevDraw.hash(seed, 15) % 100) / 100).truncatingRemainder(dividingBy: 1)
            let leg = phase < 0.5 ? phase * 2 : 2 - phase * 2
            let p = CGPoint(x: from.x + (to.x - from.x) * CGFloat(leg), y: from.y + (to.y + 6 - from.y) * CGFloat(leg))
            let facing: CGFloat = (to.x >= from.x) == (phase < 0.5) ? 1 : -1
            let coat = Self.coats[JevDraw.hash(seed, 16) % Self.coats.count]
            standing.append((p.y, { g in self.folk(g, p, coat: coat, facing: facing, step: now * 7 + Double(seed), carry: phase >= 0.5 ? JevDraw.hash(seed, 17) % 3 : -1) }))
        }
        // Guards at the gate and by the barracks.
        let guards = min(6, w.soldiers / 12)
        for n in 0..<guards {
            let base = n < 2 ? IceLook.at(90, IceLook.wallR - 14) : IceLook.spot(.barracks)
            let p = CGPoint(x: base.x + CGFloat(n < 2 ? (n == 0 ? -20 : 20) : (n - 3) * 12), y: base.y + (n < 2 ? 2 : 14))
            standing.append((p.y, { g in self.guardsman(g, p, seed: n) }))
        }
        for (_, draw) in standing.sorted(by: { $0.0 < $1.0 }) { draw(&g) }
        if w.wall > 0 { wall(g, back: false) }
        // Dust where something went up today.
        if let k = w.raised, since < 1.4 {
            let p = k == .house ? IceLook.houseSpots[max(0, min(w.houses - 1, IceLook.houseSpots.count - 1))] : IceLook.spot(k)
            let f = CGFloat(min(1, since / 1.4))
            for n in 0..<7 {
                let a = Double(n) / 7 * 2 * .pi
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * (10 + 22 * f), y: p.y + CGFloat(sin(a)) * (5 + 9 * f))
                let rr = 4 + 5 * f
                g.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(.white.opacity(0.85 * Double(1 - f))))
            }
            JevDraw.text(g, k == .house ? "新民居" : (before.level[k.rawValue] == 0 ? "建成 \(k.cn)" : "\(k.cn) Lv\(w.level[k.rawValue])"),
                         at: CGPoint(x: p.x, y: p.y - 58 - 12 * f), size: 11, colour: Color(red: 1, green: 0.95, blue: 0.7).opacity(Double(1.2 - f)))
        }
    }

    /// How far up a building going up today has come.
    private var growth: CGFloat { CGFloat(0.25 + 0.75 * JevDraw.smooth(min(1, since / 0.7))) }

    /// A small house in the snow: warm and lit inside the heat, frosted and dark outside it.
    private func house(_ g: inout GraphicsContext, _ p: CGPoint, warm: Bool, seed: Int, rise: CGFloat) {
        let w: CGFloat = 25, h: CGFloat = 13 * rise, roofH: CGFloat = 12 * rise
        g.fill(Path(ellipseIn: CGRect(x: p.x - w * 0.46, y: p.y - 4, width: w * 1.25, height: 9)), with: .color(Color(red: 0.3, green: 0.36, blue: 0.52).opacity(0.22)))
        let body = CGRect(x: p.x - w / 2, y: p.y - h, width: w, height: h)
        let wallTop: Art.RGB = warm ? [(0.96, 0.84, 0.66), (0.92, 0.78, 0.62), (0.95, 0.88, 0.74)][seed % 3] : (0.78, 0.84, 0.92)
        g.fill(Path(roundedRect: body, cornerRadius: 2), with: .color(Self.c(wallTop)))
        g.fill(Path(CGRect(x: body.maxX - w * 0.3, y: body.minY, width: w * 0.3, height: body.height)), with: .color(Self.c(Art.lit(wallTop, 0.86))))
        // Timber corners, a door, a window.
        let timber = warm ? Color(red: 0.5, green: 0.32, blue: 0.2) : Color(red: 0.46, green: 0.5, blue: 0.6)
        g.fill(Path(CGRect(x: body.minX, y: body.minY, width: 2, height: body.height)), with: .color(timber))
        g.fill(Path(CGRect(x: body.maxX - 2, y: body.minY, width: 2, height: body.height)), with: .color(timber))
        g.fill(Path(roundedRect: CGRect(x: p.x - 3 + CGFloat(seed % 2 == 0 ? -5 : 5), y: p.y - 8 * rise, width: 6, height: 8 * rise), cornerRadius: 2.5), with: .color(warm ? Color(red: 0.46, green: 0.28, blue: 0.16) : Color(red: 0.36, green: 0.4, blue: 0.5)))
        let win = CGRect(x: p.x + CGFloat(seed % 2 == 0 ? 3 : -9), y: p.y - 10 * rise, width: 6, height: 5 * rise)
        if warm {
            let flicker = 0.85 + 0.15 * sin(now * 3 + Double(seed))
            g.fill(Path(ellipseIn: win.insetBy(dx: -5, dy: -4)), with: .color(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.3 * flicker)))
            g.fill(Path(roundedRect: win, cornerRadius: 1.2), with: .color(Color(red: 1, green: 0.84 * flicker, blue: 0.42)))
        } else {
            g.fill(Path(roundedRect: win, cornerRadius: 1.2), with: .color(Color(red: 0.3, green: 0.38, blue: 0.52)))
            g.stroke(Path { q in q.move(to: CGPoint(x: win.minX + 1, y: win.minY + 1)); q.addLine(to: CGPoint(x: win.maxX - 1, y: win.maxY - 1)); q.move(to: CGPoint(x: win.maxX - 1, y: win.minY + 1)); q.addLine(to: CGPoint(x: win.minX + 1, y: win.maxY - 1)) },
                     with: .color(.white.opacity(0.7)), lineWidth: 0.7)
        }
        // The roof: a slope of snow over a coloured eave, icicles under it.
        let eave = body.minY
        let roof = Path { q in
            q.move(to: CGPoint(x: body.minX - 4, y: eave + 1)); q.addLine(to: CGPoint(x: body.maxX + 4, y: eave + 1))
            q.addLine(to: CGPoint(x: body.maxX - 2, y: eave - roofH)); q.addLine(to: CGPoint(x: body.minX + 2, y: eave - roofH)); q.closeSubpath()
        }
        let roofColour: Art.RGB = [(0.78, 0.28, 0.24), (0.36, 0.44, 0.66), (0.56, 0.36, 0.24)][seed % 3]
        g.fill(roof, with: .color(Self.c(roofColour)))
        let snow = Path { q in
            q.move(to: CGPoint(x: body.minX - 3, y: eave - 1.6)); q.addLine(to: CGPoint(x: body.maxX + 3, y: eave - 1.6))
            q.addLine(to: CGPoint(x: body.maxX - 1, y: eave - roofH - 2.5))
            q.addQuadCurve(to: CGPoint(x: body.minX + 1, y: eave - roofH - 2.5), control: CGPoint(x: p.x, y: eave - roofH - 6))
            q.closeSubpath()
            for d in stride(from: body.minX + 1, to: body.maxX - 1, by: 6) { q.addEllipse(in: CGRect(x: d, y: eave - 3.4, width: 5, height: 4.2)) }
        }
        g.fill(snow, with: .color(.white))
        g.fill(Path(CGRect(x: body.minX - 3, y: eave - 3.2, width: w + 6, height: 1.6)), with: .color(Color(red: 0.84, green: 0.89, blue: 0.97)))
        let icicles = Path { q in
            let long: CGFloat = warm ? 2.5 : 5
            for (n, d) in stride(from: body.minX, through: body.maxX, by: 4).enumerated() {
                let l = long * CGFloat(0.6 + 0.4 * Double(JevDraw.hash(n, seed) % 10) / 10)
                q.move(to: CGPoint(x: d - 1, y: eave + 1)); q.addLine(to: CGPoint(x: d, y: eave + 1 + l)); q.addLine(to: CGPoint(x: d + 1, y: eave + 1))
            }
        }
        g.fill(icicles, with: .color(Color(red: 0.86, green: 0.94, blue: 1).opacity(0.95)))
        // A chimney, smoking where it is warm.
        let chimney = CGRect(x: p.x + 5, y: eave - roofH + 1, width: 4.5, height: 7)
        g.fill(Path(chimney), with: .color(Color(red: 0.5, green: 0.36, blue: 0.32)))
        g.fill(Path(roundedRect: CGRect(x: chimney.minX - 1, y: chimney.minY - 2, width: chimney.width + 2, height: 3), cornerRadius: 1.5), with: .color(.white))
        if warm {
            for n in 0..<3 {
                let f = (now * 0.4 + Double(n) / 3 + Double(seed % 7) / 7).truncatingRemainder(dividingBy: 1)
                let q = CGPoint(x: chimney.midX + CGFloat(f * f) * 10 + CGFloat(sin(now + Double(n))) * 1.5, y: chimney.minY - 3 - CGFloat(f) * 18)
                let rr = CGFloat(1.8 + f * 4)
                g.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(Color(white: 0.96).opacity(0.7 * (1 - f))))
            }
        }
    }

    /// Where a building could go: a staked plot with a signpost.
    private func plot(_ g: GraphicsContext, _ p: CGPoint, _ kind: IceKind) {
        let can = after.canBuild(kind)
        let r = CGRect(x: p.x - 20, y: p.y - 10, width: 40, height: 18)
        g.stroke(Path(roundedRect: r, cornerRadius: 5), with: .color(can ? Color(red: 0.95, green: 0.72, blue: 0.2).opacity(0.9) : Color(red: 0.45, green: 0.52, blue: 0.66).opacity(0.5)),
                 style: StrokeStyle(lineWidth: can ? 1.4 : 1, dash: [3, 3]))
        g.fill(Path(CGRect(x: p.x - 1, y: p.y - 22, width: 2, height: 20)), with: .color(Color(red: 0.46, green: 0.32, blue: 0.2)))
        let board = CGRect(x: p.x - 15, y: p.y - 30, width: 30, height: 11)
        g.fill(Path(roundedRect: board, cornerRadius: 2), with: .color(Color(red: 0.72, green: 0.52, blue: 0.32)))
        g.fill(Path(roundedRect: CGRect(x: board.minX, y: board.minY - 1.5, width: board.width, height: 3), cornerRadius: 1.5), with: .color(.white))
        g.draw(Text(kind.cn).font(.system(size: 7.5, weight: .bold, design: .rounded)).foregroundColor(Color(red: 0.25, green: 0.14, blue: 0.08)), at: CGPoint(x: board.midX, y: board.midY + 0.5))
    }

    /// A long box of a building: a front wall, a snowy roof, a badge for its level.
    private func block(_ g: inout GraphicsContext, _ p: CGPoint, width: CGFloat, height: CGFloat, roof: Art.RGB, wallColour: Art.RGB, rise: CGFloat) -> CGRect {
        let h = height * rise
        g.fill(Path(ellipseIn: CGRect(x: p.x - width * 0.5, y: p.y - 5, width: width * 1.2, height: 11)), with: .color(Color(red: 0.3, green: 0.36, blue: 0.52).opacity(0.22)))
        let body = CGRect(x: p.x - width / 2, y: p.y - h, width: width, height: h)
        g.fill(Path(roundedRect: body, cornerRadius: 2), with: .color(Self.c(wallColour)))
        g.fill(Path(CGRect(x: body.maxX - width * 0.28, y: body.minY, width: width * 0.28, height: body.height)), with: .color(Self.c(Art.lit(wallColour, 0.85))))
        let roofH = 12 * rise
        let top = Path { q in
            q.move(to: CGPoint(x: body.minX - 4, y: body.minY + 1)); q.addLine(to: CGPoint(x: body.maxX + 4, y: body.minY + 1))
            q.addLine(to: CGPoint(x: body.maxX - 3, y: body.minY - roofH)); q.addLine(to: CGPoint(x: body.minX + 3, y: body.minY - roofH)); q.closeSubpath()
        }
        g.fill(top, with: .color(Self.c(roof)))
        let snow = Path { q in
            q.move(to: CGPoint(x: body.minX - 3, y: body.minY - 1.5)); q.addLine(to: CGPoint(x: body.maxX + 3, y: body.minY - 1.5))
            q.addLine(to: CGPoint(x: body.maxX - 2, y: body.minY - roofH - 2.5))
            q.addQuadCurve(to: CGPoint(x: body.minX + 2, y: body.minY - roofH - 2.5), control: CGPoint(x: p.x, y: body.minY - roofH - 6))
            q.closeSubpath()
            for d in stride(from: body.minX + 1, to: body.maxX - 2, by: 6.5) { q.addEllipse(in: CGRect(x: d, y: body.minY - 3.5, width: 5.5, height: 4.5)) }
        }
        g.fill(snow, with: .color(.white))
        return body
    }

    /// A building's level as a row of gold pips on a dark tab.
    private func badge(_ g: GraphicsContext, _ p: CGPoint, _ level: Int) {
        let n = max(1, level), w = CGFloat(n) * 6 + 6
        let r = CGRect(x: p.x - w / 2, y: p.y - 4.5, width: w, height: 9)
        g.fill(Path(roundedRect: r, cornerRadius: 4.5), with: .color(Color(red: 0.14, green: 0.2, blue: 0.34).opacity(0.78)))
        var pips = Path()
        for i in 0..<n { pips.addEllipse(in: CGRect(x: r.minX + 4 + CGFloat(i) * 6, y: r.midY - 2, width: 4, height: 4)) }
        g.fill(pips, with: .color(Color(red: 1, green: 0.82, blue: 0.3)))
    }

    private func building(_ g: inout GraphicsContext, _ kind: IceKind, _ p: CGPoint, level: Int, rise: CGFloat) {
        let wood: Art.RGB = (0.62, 0.42, 0.26), stone: Art.RGB = (0.7, 0.72, 0.78)
        switch kind {
        case .sawmill:
            let body = block(&g, p, width: 36, height: 13, roof: (0.5, 0.34, 0.22), wallColour: wood, rise: rise)
            for n in 0..<min(3 + level, 6) {
                let q = CGPoint(x: body.minX - 8 + CGFloat(n % 3) * 5.5, y: p.y - 1 - CGFloat(n / 3) * 5)
                g.fill(Path(ellipseIn: CGRect(x: q.x, y: q.y - 5, width: 5.5, height: 5.5)), with: .color(Color(red: 0.62, green: 0.42, blue: 0.24)))
                g.fill(Path(ellipseIn: CGRect(x: q.x + 1.3, y: q.y - 3.7, width: 2.9, height: 2.9)), with: .color(Color(red: 0.92, green: 0.78, blue: 0.54)))
            }
            let saw = CGPoint(x: body.maxX - 5, y: body.minY + 7)
            var spin = g; spin.translateBy(x: saw.x, y: saw.y); spin.rotate(by: .radians(now * 3))
            spin.fill(Path { q in for n in 0..<10 { let a = Double(n) / 10 * 2 * .pi; q.move(to: .zero); q.addLine(to: CGPoint(x: cos(a) * 5.5, y: sin(a) * 5.5)); q.addLine(to: CGPoint(x: cos(a + 0.3) * 4, y: sin(a + 0.3) * 4)) } }, with: .color(Color(white: 0.82)))
            spin.fill(Path(ellipseIn: CGRect(x: -1.5, y: -1.5, width: 3, height: 3)), with: .color(Color(white: 0.4)))
        case .coal:
            // A timber headframe with its wheel over a dark adit, and a cart heaped with coal.
            let body = block(&g, CGPoint(x: p.x + 6, y: p.y), width: 28, height: 11, roof: (0.3, 0.3, 0.34), wallColour: stone, rise: rise)
            g.fill(Path(roundedRect: CGRect(x: body.midX - 5, y: p.y - 9 * rise, width: 10, height: 9 * rise), cornerRadii: RectangleCornerRadii(topLeading: 5, bottomLeading: 0, bottomTrailing: 0, topTrailing: 5)), with: .color(Color(red: 0.12, green: 0.1, blue: 0.1)))
            let top = CGPoint(x: p.x - 12, y: p.y - 36 * rise)
            g.stroke(Path { q in q.move(to: CGPoint(x: p.x - 20, y: p.y)); q.addLine(to: top); q.addLine(to: CGPoint(x: p.x - 4, y: p.y)); q.move(to: CGPoint(x: p.x - 17, y: p.y - 12 * rise)); q.addLine(to: CGPoint(x: p.x - 7, y: p.y - 12 * rise)) },
                     with: .color(Color(red: 0.46, green: 0.3, blue: 0.18)), lineWidth: 2.2)
            var wheel = g; wheel.translateBy(x: top.x, y: top.y + 2); wheel.rotate(by: .radians(now * 1.6))
            wheel.stroke(Path(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10)), with: .color(Color(red: 0.3, green: 0.22, blue: 0.16)), lineWidth: 1.6)
            wheel.stroke(Path { q in q.move(to: CGPoint(x: -5, y: 0)); q.addLine(to: CGPoint(x: 5, y: 0)); q.move(to: CGPoint(x: 0, y: -5)); q.addLine(to: CGPoint(x: 0, y: 5)) }, with: .color(Color(red: 0.3, green: 0.22, blue: 0.16)), lineWidth: 1)
            g.fill(Path(ellipseIn: CGRect(x: top.x - 3, y: top.y - 6, width: 6, height: 3)), with: .color(.white))
            let cart = CGRect(x: body.maxX - 2, y: p.y - 7, width: 11, height: 6)
            g.fill(Path(roundedRect: cart, cornerRadius: 1.5), with: .color(Color(red: 0.42, green: 0.3, blue: 0.22)))
            g.fill(Path { q in q.addEllipse(in: CGRect(x: cart.minX, y: cart.minY - 3.5, width: 6, height: 5)); q.addEllipse(in: CGRect(x: cart.minX + 4.5, y: cart.minY - 4, width: 6, height: 5.5)) }, with: .color(Color(red: 0.13, green: 0.13, blue: 0.15)))
            for x in [cart.minX + 2.5, cart.maxX - 2.5] { g.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: cart.maxY - 1.5, width: 3.6, height: 3.6)), with: .color(Color(white: 0.2))) }
        case .hunting:
            let body = block(&g, p, width: 32, height: 14, roof: (0.46, 0.3, 0.2), wallColour: (0.58, 0.38, 0.22), rise: rise)
            for n in 1..<4 { g.stroke(Path { q in q.move(to: CGPoint(x: body.minX, y: body.minY + CGFloat(n) * body.height / 4)); q.addLine(to: CGPoint(x: body.maxX, y: body.minY + CGFloat(n) * body.height / 4)) }, with: .color(Color(red: 0.4, green: 0.24, blue: 0.14).opacity(0.6)), lineWidth: 0.7) }
            // Antlers over the door, a pelt on its rack.
            let a = CGPoint(x: p.x, y: body.minY + 3)
            g.stroke(Path { q in
                for s in [-1.0, 1.0] as [CGFloat] {
                    q.move(to: a); q.addQuadCurve(to: CGPoint(x: a.x + s * 8, y: a.y - 7), control: CGPoint(x: a.x + s * 7, y: a.y))
                    q.move(to: CGPoint(x: a.x + s * 5, y: a.y - 2)); q.addLine(to: CGPoint(x: a.x + s * 4, y: a.y - 7))
                }
            }, with: .color(Color(red: 0.95, green: 0.9, blue: 0.8)), lineWidth: 1.3)
            g.fill(Path(roundedRect: CGRect(x: p.x - 3, y: p.y - 8 * rise, width: 6, height: 8 * rise), cornerRadius: 2.5), with: .color(Color(red: 0.34, green: 0.2, blue: 0.12)))
            let rack = CGPoint(x: body.maxX + 7, y: p.y)
            g.stroke(Path { q in q.move(to: CGPoint(x: rack.x - 5, y: rack.y)); q.addLine(to: CGPoint(x: rack.x - 5, y: rack.y - 14)); q.move(to: CGPoint(x: rack.x + 5, y: rack.y)); q.addLine(to: CGPoint(x: rack.x + 5, y: rack.y - 14)); q.move(to: CGPoint(x: rack.x - 6, y: rack.y - 13)); q.addLine(to: CGPoint(x: rack.x + 6, y: rack.y - 13)) },
                     with: .color(Color(red: 0.42, green: 0.28, blue: 0.18)), lineWidth: 1.4)
            g.fill(Path(roundedRect: CGRect(x: rack.x - 4, y: rack.y - 13, width: 8, height: 10), cornerRadius: 3), with: .color(Color(red: 0.72, green: 0.5, blue: 0.3)))
        case .greenhouse:
            // Glass on a stone sill, green inside, the furnace's warmth fogging it.
            let width: CGFloat = 38, h = 18 * rise
            g.fill(Path(ellipseIn: CGRect(x: p.x - width * 0.5, y: p.y - 5, width: width * 1.2, height: 11)), with: .color(Color(red: 0.3, green: 0.36, blue: 0.52).opacity(0.22)))
            let body = CGRect(x: p.x - width / 2, y: p.y - h, width: width, height: h)
            g.fill(Path(roundedRect: CGRect(x: body.minX - 1, y: p.y - 4, width: width + 2, height: 4), cornerRadius: 1), with: .color(Self.c(stone)))
            let glass = Path { q in q.move(to: CGPoint(x: body.minX, y: p.y - 4)); q.addLine(to: CGPoint(x: body.minX, y: body.minY + 6)); q.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + 6), control: CGPoint(x: p.x, y: body.minY - 8 * rise)); q.addLine(to: CGPoint(x: body.maxX, y: p.y - 4)); q.closeSubpath() }
            g.fill(glass, with: .linearGradient(Gradient(colors: [Color(red: 0.72, green: 0.92, blue: 0.9).opacity(0.9), Color(red: 0.5, green: 0.78, blue: 0.7).opacity(0.9)]), startPoint: CGPoint(x: p.x, y: body.minY), endPoint: CGPoint(x: p.x, y: p.y)))
            var inside = g; inside.clip(to: glass)
            for n in 0..<7 {
                let q = CGPoint(x: body.minX + 4 + CGFloat(n) * 5, y: p.y - 5)
                inside.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 7 - CGFloat(n % 2) * 2, width: 6, height: 7)), with: .color(Color(red: 0.22 + 0.06 * Double(n % 3), green: 0.58, blue: 0.3)))
                if n % 3 == 1 { inside.fill(Path(ellipseIn: CGRect(x: q.x - 1, y: q.y - 8, width: 2.5, height: 2.5)), with: .color(Color(red: 0.95, green: 0.3, blue: 0.25))) }
            }
            inside.fill(Path(ellipseIn: body.insetBy(dx: 4, dy: 2)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.6).opacity(0.35), .clear]), center: CGPoint(x: p.x, y: body.midY), startRadius: 0, endRadius: 20))
            g.stroke(glass, with: .color(.white), lineWidth: 1.2)
            g.stroke(Path { q in for n in 1..<5 { let x = body.minX + CGFloat(n) * width / 5; q.move(to: CGPoint(x: x, y: p.y - 4)); q.addLine(to: CGPoint(x: x, y: body.minY + 2)) } }, with: .color(.white.opacity(0.8)), lineWidth: 0.8)
            g.fill(Path(ellipseIn: CGRect(x: p.x - 12, y: body.minY - 4 * rise, width: 24, height: 5)), with: .color(.white))
        case .iron:
            // A rocky knoll with a timbered adit, and ore heaped by it.
            let hill = Path { q in q.move(to: CGPoint(x: p.x - 22, y: p.y)); q.addQuadCurve(to: CGPoint(x: p.x + 20, y: p.y), control: CGPoint(x: p.x - 2, y: p.y - 40 * rise)); q.closeSubpath() }
            g.fill(Path(ellipseIn: CGRect(x: p.x - 20, y: p.y - 5, width: 48, height: 10)), with: .color(Color(red: 0.3, green: 0.36, blue: 0.52).opacity(0.22)))
            g.fill(hill, with: .linearGradient(Gradient(colors: [Color(red: 0.62, green: 0.6, blue: 0.62), Color(red: 0.4, green: 0.38, blue: 0.42)]), startPoint: CGPoint(x: p.x - 16, y: p.y - 26), endPoint: CGPoint(x: p.x + 16, y: p.y)))
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - 14, y: p.y - 12 * rise)); q.addQuadCurve(to: CGPoint(x: p.x + 11, y: p.y - 12 * rise), control: CGPoint(x: p.x - 2, y: p.y - 38 * rise)); q.closeSubpath() }, with: .color(.white))
            g.fill(Path(roundedRect: CGRect(x: p.x - 6, y: p.y - 11 * rise, width: 12, height: 11 * rise), cornerRadii: RectangleCornerRadii(topLeading: 6, bottomLeading: 0, bottomTrailing: 0, topTrailing: 6)), with: .color(Color(red: 0.12, green: 0.1, blue: 0.1)))
            g.stroke(Path { q in q.move(to: CGPoint(x: p.x - 7, y: p.y)); q.addLine(to: CGPoint(x: p.x - 7, y: p.y - 11 * rise)); q.addLine(to: CGPoint(x: p.x + 7, y: p.y - 11 * rise)); q.addLine(to: CGPoint(x: p.x + 7, y: p.y)) }, with: .color(Color(red: 0.5, green: 0.34, blue: 0.2)), lineWidth: 2)
            for n in 0..<4 {
                let q = CGPoint(x: p.x + 12 + CGFloat(n % 2) * 5, y: p.y - 2 - CGFloat(n / 2) * 4)
                g.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 2.5, width: 6, height: 5)), with: .color(Color(red: 0.42, green: 0.4, blue: 0.44)))
                g.fill(Path(ellipseIn: CGRect(x: q.x - 1, y: q.y - 1.5, width: 2, height: 2)), with: .color(Color(red: 0.95, green: 0.55, blue: 0.25)))
            }
        case .clinic:
            let body = block(&g, p, width: 32, height: 15, roof: (0.3, 0.52, 0.46), wallColour: (0.96, 0.94, 0.9), rise: rise)
            g.fill(Path(roundedRect: CGRect(x: p.x - 3.5, y: p.y - 9 * rise, width: 7, height: 9 * rise), cornerRadius: 3), with: .color(Color(red: 0.4, green: 0.26, blue: 0.18)))
            // A white banner with a red cross-knot for the healer's house, and a gourd.
            let pole = CGPoint(x: body.maxX + 4, y: p.y)
            g.stroke(Path { q in q.move(to: pole); q.addLine(to: CGPoint(x: pole.x, y: pole.y - 30)) }, with: .color(Color(red: 0.4, green: 0.28, blue: 0.18)), lineWidth: 1.4)
            let flag = CGRect(x: pole.x - 11, y: pole.y - 29, width: 10, height: 15)
            g.fill(Path(roundedRect: flag, cornerRadius: 1.5), with: .color(.white))
            g.draw(Text("医").font(.system(size: 8, weight: .heavy)).foregroundColor(Color(red: 0.85, green: 0.2, blue: 0.2)), at: CGPoint(x: flag.midX, y: flag.midY))
            g.fill(Path(ellipseIn: CGRect(x: body.minX + 3, y: body.minY + 3, width: 5, height: 5)), with: .color(Color(red: 0.9, green: 0.62, blue: 0.2)))
            g.fill(Path(ellipseIn: CGRect(x: body.minX + 4, y: body.minY + 7, width: 7, height: 7)), with: .color(Color(red: 0.95, green: 0.68, blue: 0.24)))
        case .barracks:
            let body = block(&g, p, width: 40, height: 14, roof: (0.24, 0.42, 0.3), wallColour: stone, rise: rise)
            g.fill(Path(roundedRect: CGRect(x: p.x - 5, y: p.y - 10 * rise, width: 10, height: 10 * rise), cornerRadius: 3), with: .color(Color(red: 0.36, green: 0.24, blue: 0.16)))
            for x in [body.minX + 4, body.maxX - 4] { flag(g, CGPoint(x: x, y: body.minY - 8), Self.shu, text: "蜀") }
            for n in 0..<3 { g.stroke(Path { q in q.move(to: CGPoint(x: body.maxX + 3 + CGFloat(n) * 3, y: p.y)); q.addLine(to: CGPoint(x: body.maxX + 5 + CGFloat(n) * 3, y: p.y - 18)) }, with: .color(Color(red: 0.5, green: 0.36, blue: 0.22)), lineWidth: 1) }
        case .tavern:
            let body = block(&g, p, width: 34, height: 20, roof: (0.7, 0.24, 0.2), wallColour: (0.9, 0.76, 0.56), rise: rise)
            for x in [body.minX + 5, body.maxX - 11] {
                let win = CGRect(x: x, y: body.minY + 4, width: 6, height: 5)
                g.fill(Path(ellipseIn: win.insetBy(dx: -5, dy: -4)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.4).opacity(0.45), .clear]), center: CGPoint(x: win.midX, y: win.midY), startRadius: 0, endRadius: 8))
                g.fill(Path(roundedRect: win, cornerRadius: 1), with: .color(Color(red: 1, green: 0.84, blue: 0.42)))
            }
            g.fill(Path(roundedRect: CGRect(x: p.x - 4, y: p.y - 10 * rise, width: 8, height: 10 * rise), cornerRadius: 3), with: .color(Color(red: 0.42, green: 0.24, blue: 0.14)))
            // The wine flag, and a red lantern swinging.
            let pole = CGPoint(x: body.minX - 5, y: p.y)
            g.stroke(Path { q in q.move(to: pole); q.addLine(to: CGPoint(x: pole.x, y: pole.y - 34)) }, with: .color(Color(red: 0.4, green: 0.28, blue: 0.18)), lineWidth: 1.4)
            let wave = CGFloat(sin(now * 3)) * 1.5
            let cloth = Path { q in q.move(to: CGPoint(x: pole.x, y: pole.y - 33)); q.addLine(to: CGPoint(x: pole.x - 11 + wave, y: pole.y - 32)); q.addLine(to: CGPoint(x: pole.x - 11 - wave, y: pole.y - 16)); q.addLine(to: CGPoint(x: pole.x, y: pole.y - 17)); q.closeSubpath() }
            g.fill(cloth, with: .color(Color(red: 0.95, green: 0.9, blue: 0.78)))
            g.stroke(cloth, with: .color(Color(red: 0.8, green: 0.2, blue: 0.16)), lineWidth: 1)
            g.draw(Text("酒").font(.system(size: 8, weight: .heavy)).foregroundColor(Color(red: 0.8, green: 0.16, blue: 0.12)), at: CGPoint(x: pole.x - 5.5, y: pole.y - 24.5))
            let swing = CGFloat(sin(now * 2)) * 2
            g.fill(Path(ellipseIn: CGRect(x: body.maxX - 1 + swing, y: body.minY + 1, width: 6, height: 7)), with: .color(Color(red: 0.92, green: 0.2, blue: 0.14)))
        default:
            break
        }
        badge(g, CGPoint(x: p.x, y: p.y + 8), level)
    }

    private func flag(_ g: GraphicsContext, _ at: CGPoint, _ colour: Art.RGB, text: String) {
        g.stroke(Path { q in q.move(to: CGPoint(x: at.x, y: at.y + 8)); q.addLine(to: CGPoint(x: at.x, y: at.y - 12)) }, with: .color(Color(red: 0.35, green: 0.25, blue: 0.18)), lineWidth: 1.2)
        let wave = CGFloat(sin(now * 4 + Double(at.x))) * 1.2
        let cloth = Path { q in q.move(to: CGPoint(x: at.x, y: at.y - 12)); q.addQuadCurve(to: CGPoint(x: at.x + 11, y: at.y - 10 + wave), control: CGPoint(x: at.x + 5, y: at.y - 13 - wave)); q.addLine(to: CGPoint(x: at.x + 11, y: at.y - 2 + wave)); q.addQuadCurve(to: CGPoint(x: at.x, y: at.y - 3), control: CGPoint(x: at.x + 5, y: at.y - 4 - wave)); q.closeSubpath() }
        g.fill(cloth, with: .color(Self.c(colour)))
        g.draw(Text(text).font(.system(size: 6, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: at.x + 5.5, y: at.y - 7))
    }

    /// The great furnace: an iron tower with a fire in its mouth, a stack and steam — bigger for every level.
    private func furnace(_ g: inout GraphicsContext) {
        let w = after, hub = IceLook.centre, level = max(1, w.furnace)
        let lit = w.outDays == 0
        let grow = w.raised == .furnace ? growth : 1
        let s = CGFloat(0.8 + 0.07 * Double(level)) * (w.raised == .furnace ? CGFloat(0.9 + 0.1 * Double(grow)) : 1)
        let flicker = 0.8 + 0.2 * sin(now * 9) * sin(now * 5.3 + 1)
        // Stone footing.
        g.fill(Path(ellipseIn: CGRect(x: hub.x - 38 * s, y: hub.y - 12 * s, width: 76 * s, height: 26 * s)), with: .color(Color(red: 0.36, green: 0.38, blue: 0.46)))
        g.fill(Path(ellipseIn: CGRect(x: hub.x - 36 * s, y: hub.y - 14 * s, width: 72 * s, height: 24 * s)), with: .linearGradient(Gradient(colors: [Color(red: 0.72, green: 0.74, blue: 0.8), Color(red: 0.5, green: 0.52, blue: 0.6)]), startPoint: CGPoint(x: hub.x - 30 * s, y: hub.y - 14 * s), endPoint: CGPoint(x: hub.x + 30 * s, y: hub.y + 10 * s)))
        // The tower: a drum of iron plates, lit from the fire's side.
        let body = CGRect(x: hub.x - 25 * s, y: hub.y - 58 * s, width: 50 * s, height: 56 * s)
        g.fill(Path(roundedRect: body, cornerRadius: 8 * s), with: .linearGradient(Gradient(stops: [.init(color: Color(red: 0.42, green: 0.44, blue: 0.52), location: 0), .init(color: Color(red: 0.3, green: 0.31, blue: 0.38), location: 0.55), .init(color: Color(red: 0.2, green: 0.2, blue: 0.26), location: 1)]),
                                                                        startPoint: CGPoint(x: body.minX, y: body.midY), endPoint: CGPoint(x: body.maxX, y: body.midY)))
        g.fill(Path(ellipseIn: CGRect(x: body.minX, y: body.minY - 7 * s, width: body.width, height: 14 * s)), with: .color(Color(red: 0.46, green: 0.48, blue: 0.56)))
        // Copper bands with rivets, one more for each level.
        for n in 0..<min(level, 4) {
            let y = body.maxY - 10 * s - CGFloat(n) * 11 * s
            g.fill(Path(roundedRect: CGRect(x: body.minX - 1.5, y: y, width: body.width + 3, height: 4 * s), cornerRadius: 2), with: .color(Color(red: 0.78, green: 0.48, blue: 0.26)))
            for r in 0..<5 { g.fill(Path(ellipseIn: CGRect(x: body.minX + 4 * s + CGFloat(r) * 10 * s, y: y + 1 * s, width: 2 * s, height: 2 * s)), with: .color(Color(red: 1, green: 0.8, blue: 0.5))) }
        }
        // The fire's mouth.
        let mouth = CGRect(x: hub.x - 12 * s, y: hub.y - 30 * s, width: 24 * s, height: 26 * s)
        let arch = Path(roundedRect: mouth, cornerRadii: RectangleCornerRadii(topLeading: 12 * s, bottomLeading: 2, bottomTrailing: 2, topTrailing: 12 * s))
        g.fill(arch, with: .color(Color(red: 0.12, green: 0.08, blue: 0.08)))
        if lit {
            g.fill(arch.applying(CGAffineTransform(translationX: 0, y: 0)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.7), Color(red: 1, green: 0.62, blue: 0.16), Color(red: 0.86, green: 0.26, blue: 0.08)]),
                                                                                                center: CGPoint(x: mouth.midX, y: mouth.maxY - 4 * s), startRadius: 0, endRadius: 22 * s * CGFloat(flicker)))
            for n in 0..<3 {
                let x = mouth.minX + 6 * s + CGFloat(n) * 6 * s, h = 10 * s * CGFloat(0.7 + 0.3 * sin(now * 8 + Double(n) * 2))
                g.fill(Path { q in q.move(to: CGPoint(x: x - 3 * s, y: mouth.maxY)); q.addQuadCurve(to: CGPoint(x: x, y: mouth.maxY - h - 6 * s), control: CGPoint(x: x - 4 * s, y: mouth.maxY - h)); q.addQuadCurve(to: CGPoint(x: x + 3 * s, y: mouth.maxY), control: CGPoint(x: x + 4 * s, y: mouth.maxY - h)); q.closeSubpath() },
                       with: .color(Color(red: 1, green: 0.9, blue: 0.5).opacity(0.85)))
            }
            g.fill(Path(ellipseIn: CGRect(x: hub.x - 46 * s, y: hub.y - 44 * s, width: 92 * s, height: 70 * s)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.2).opacity(0.3 * flicker), .clear]), center: CGPoint(x: mouth.midX, y: mouth.midY), startRadius: 0, endRadius: 46 * s))
        }
        g.stroke(arch, with: .color(Color(red: 0.8, green: 0.5, blue: 0.28)), lineWidth: 2 * s)
        // Cone roof, snow on it, and the stack.
        let cone = Path { q in q.move(to: CGPoint(x: body.minX - 4 * s, y: body.minY + 2 * s)); q.addQuadCurve(to: CGPoint(x: body.maxX + 4 * s, y: body.minY + 2 * s), control: CGPoint(x: hub.x, y: body.minY + 8 * s)); q.addLine(to: CGPoint(x: hub.x + 8 * s, y: body.minY - 20 * s)); q.addLine(to: CGPoint(x: hub.x - 8 * s, y: body.minY - 20 * s)); q.closeSubpath() }
        g.fill(cone, with: .linearGradient(Gradient(colors: [Color(red: 0.5, green: 0.52, blue: 0.6), Color(red: 0.26, green: 0.27, blue: 0.33)]), startPoint: CGPoint(x: body.minX, y: body.minY), endPoint: CGPoint(x: body.maxX, y: body.minY)))
        g.fill(Path { q in q.move(to: CGPoint(x: body.minX - 2 * s, y: body.minY)); q.addQuadCurve(to: CGPoint(x: hub.x - 4 * s, y: body.minY - 14 * s), control: CGPoint(x: body.minX + 6 * s, y: body.minY - 10 * s)); q.addLine(to: CGPoint(x: hub.x + 6 * s, y: body.minY - 12 * s)); q.addQuadCurve(to: CGPoint(x: body.maxX - 8 * s, y: body.minY - 1 * s), control: CGPoint(x: hub.x + 4 * s, y: body.minY - 4 * s)); q.closeSubpath() }, with: .color(.white))
        let stack = CGRect(x: hub.x - 6 * s, y: body.minY - 44 * s, width: 12 * s, height: 26 * s)
        g.fill(Path(stack), with: .linearGradient(Gradient(colors: [Color(red: 0.4, green: 0.4, blue: 0.48), Color(red: 0.2, green: 0.2, blue: 0.26)]), startPoint: CGPoint(x: stack.minX, y: 0), endPoint: CGPoint(x: stack.maxX, y: 0)))
        g.fill(Path(roundedRect: CGRect(x: stack.minX - 2 * s, y: stack.minY - 2 * s, width: stack.width + 4 * s, height: 5 * s), cornerRadius: 2), with: .color(Color(red: 0.78, green: 0.48, blue: 0.26)))
        if lit {
            g.fill(Path(ellipseIn: CGRect(x: stack.minX, y: stack.minY - 2 * s, width: stack.width, height: 4 * s)), with: .color(Color(red: 1, green: 0.6, blue: 0.2).opacity(flicker)))
            // Smoke rolling up and away, steam off the sides, sparks.
            let wind = storm > 0 ? 2.4 : 1
            for n in 0..<9 {
                let f = (now * 0.22 + Double(n) / 9).truncatingRemainder(dividingBy: 1)
                let q = CGPoint(x: hub.x + CGFloat(f * f) * 60 * CGFloat(wind) + CGFloat(sin(now * 0.7 + Double(n))) * 4, y: stack.minY - 4 - CGFloat(f) * 90)
                let rr = CGFloat(5 + f * 18) * s
                let grey = 0.55 + 0.35 * f
                g.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr * 0.85, width: 2 * rr, height: 1.7 * rr)), with: .color(Color(white: grey).opacity(0.62 * (1 - f))))
            }
            for n in 0..<5 {
                let f = (now * 0.9 + Double(n) * 0.37).truncatingRemainder(dividingBy: 1)
                let q = CGPoint(x: hub.x + CGFloat(sin(Double(n) * 2.3 + now)) * 8 * s, y: stack.minY - CGFloat(f) * 40)
                g.fill(Path(ellipseIn: CGRect(x: q.x - 1, y: q.y - 1, width: 2, height: 2)), with: .color(Color(red: 1, green: 0.8, blue: 0.3).opacity(1 - f)))
            }
            if level >= 3 {
                for side in [-1.0, 1.0] as [CGFloat] {
                    let vent = CGPoint(x: hub.x + side * 27 * s, y: body.minY + 16 * s)
                    g.fill(Path(roundedRect: CGRect(x: vent.x - 3 * s, y: vent.y - 2 * s, width: 6 * s, height: 10 * s), cornerRadius: 2), with: .color(Color(red: 0.62, green: 0.4, blue: 0.24)))
                    for n in 0..<3 {
                        let f = (now * 0.5 + Double(n) / 3 + (side > 0 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                        let q = CGPoint(x: vent.x + side * CGFloat(f) * 14, y: vent.y - 4 - CGFloat(f) * 16)
                        let rr = CGFloat(2 + f * 6)
                        g.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(.white.opacity(0.55 * (1 - f))))
                    }
                }
            }
        } else {
            g.fill(Path(roundedRect: CGRect(x: hub.x - 20, y: hub.y - 96, width: 40, height: 16), cornerRadius: 8), with: .color(Color(red: 0.2, green: 0.3, blue: 0.5).opacity(0.85)))
            g.draw(Text("熄灭了").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: hub.x, y: hub.y - 88))
        }
        badge(g, CGPoint(x: hub.x, y: hub.y + 14), w.furnace)
    }

    /// A townsperson in a puffy coat with a fur-trimmed hood.
    private func folk(_ g: GraphicsContext, _ p: CGPoint, coat: Art.RGB, facing: CGFloat, step: Double, carry: Int) {
        let bob = CGFloat(abs(sin(step))) * 0.8
        g.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 1.5, width: 9, height: 3)), with: .color(Color(red: 0.3, green: 0.36, blue: 0.52).opacity(0.25)))
        let swing = CGFloat(sin(step)) * 1.6
        g.fill(Path { q in q.addEllipse(in: CGRect(x: p.x - 3 + swing, y: p.y - 3, width: 2.8, height: 3)); q.addEllipse(in: CGRect(x: p.x + 0.4 - swing, y: p.y - 3, width: 2.8, height: 3)) }, with: .color(Color(red: 0.3, green: 0.22, blue: 0.18)))
        let body = CGRect(x: p.x - 4.2, y: p.y - 11 - bob, width: 8.4, height: 9)
        g.fill(Path(ellipseIn: body), with: .linearGradient(Gradient(colors: [Self.c(Art.lit(coat, 1.15)), Self.c(Art.lit(coat, 0.8))]), startPoint: CGPoint(x: body.minX, y: body.minY), endPoint: CGPoint(x: body.maxX, y: body.maxY)))
        g.fill(Path(roundedRect: CGRect(x: body.minX + 0.5, y: body.maxY - 2.2, width: body.width - 1, height: 2.2), cornerRadius: 1.1), with: .color(.white))
        let head = CGPoint(x: p.x + facing * 0.4, y: body.minY - 2.6)
        g.fill(Path(ellipseIn: CGRect(x: head.x - 4.4, y: head.y - 4.4, width: 8.8, height: 8.8)), with: .color(Self.c(Art.lit(coat, 0.9))))
        g.fill(Path(ellipseIn: CGRect(x: head.x - 3.6, y: head.y - 3.2, width: 7.2, height: 7)), with: .color(.white))
        g.fill(Path(ellipseIn: CGRect(x: head.x - 2.6, y: head.y - 2.2, width: 5.2, height: 5)), with: .color(Color(red: 0.99, green: 0.86, blue: 0.74)))
        g.fill(Path { q in q.addEllipse(in: CGRect(x: head.x - 1.6 + facing * 0.6, y: head.y - 0.6, width: 1, height: 1.2)); q.addEllipse(in: CGRect(x: head.x + 0.7 + facing * 0.6, y: head.y - 0.6, width: 1, height: 1.2)) }, with: .color(Color(red: 0.15, green: 0.1, blue: 0.1)))
        if carry >= 0 {
            let colour: Color = [Color(red: 0.2, green: 0.2, blue: 0.22), Color(red: 0.62, green: 0.42, blue: 0.24), Color(red: 0.86, green: 0.5, blue: 0.3)][carry]
            g.fill(Path(roundedRect: CGRect(x: p.x - facing * 6 - 2.5, y: body.minY + 1, width: 5, height: 4.5), cornerRadius: 1.4), with: .color(colour))
        }
    }

    private func guardsman(_ g: GraphicsContext, _ p: CGPoint, seed: Int) {
        folk(g, p, coat: Self.shu, facing: seed % 2 == 0 ? 1 : -1, step: 0, carry: -1)
        g.stroke(Path { q in q.move(to: CGPoint(x: p.x + 5, y: p.y)); q.addLine(to: CGPoint(x: p.x + 5, y: p.y - 22)) }, with: .color(Color(red: 0.46, green: 0.32, blue: 0.2)), lineWidth: 1.1)
        g.fill(Path { q in q.move(to: CGPoint(x: p.x + 5, y: p.y - 26)); q.addLine(to: CGPoint(x: p.x + 6.6, y: p.y - 21)); q.addLine(to: CGPoint(x: p.x + 3.4, y: p.y - 21)); q.closeSubpath() }, with: .color(Color(white: 0.85)))
        g.fill(Path(CGRect(x: p.x + 5, y: p.y - 21, width: 3, height: 2)), with: .color(Color(red: 0.86, green: 0.2, blue: 0.2)))
    }

    /// The wall round the city: a stockade, then stone, then stone with towers; the far half behind everything, the near half in front.
    private func wall(_ g: GraphicsContext, back: Bool) {
        let level = after.wall, hub = IceLook.centre, R = IceLook.wallR
        let height: CGFloat = level == 1 ? 9 : 12
        func point(_ deg: Double, _ lift: CGFloat = 0) -> CGPoint { let p = IceLook.at(deg, R); return CGPoint(x: p.x, y: p.y - lift) }
        let range: [Double] = back ? Array(stride(from: 180.0, through: 360.0, by: 3)) : Array(stride(from: 0.0, through: 180.0, by: 3))
        // The gate: a gap in the near half.
        let segments: [[Double]] = back ? [range] : [range.filter { $0 < 80 }, range.filter { $0 > 100 }]
        for seg in segments where seg.count > 1 {
            let face = Path { q in
                q.move(to: point(seg[0]))
                for d in seg.dropFirst() { q.addLine(to: point(d)) }
                for d in seg.reversed() { q.addLine(to: point(d, height)) }
                q.closeSubpath()
            }
            let colour: Color = level == 1 ? Color(red: 0.56, green: 0.38, blue: 0.24) : Color(red: 0.62, green: 0.64, blue: 0.7)
            g.fill(face, with: .color(back ? colour.opacity(0.9) : colour))
            let lines = Path { q in
                if level == 1 {
                    for d in seg where Int(d) % 6 == 0 { q.move(to: point(d)); q.addLine(to: point(d, height + 2)) }
                } else {
                    for d in seg where Int(d) % 9 == 0 { q.move(to: point(d)); q.addLine(to: point(d, height)) }
                    q.move(to: point(seg[0], height * 0.5)); for d in seg.dropFirst() { q.addLine(to: point(d, height * 0.5)) }
                }
            }
            g.stroke(lines, with: .color(.black.opacity(0.22)), lineWidth: 0.8)
            let top = Path { q in q.move(to: point(seg[0], height + 1)); for d in seg.dropFirst() { q.addLine(to: point(d, height + 1)) } }
            g.stroke(top, with: .color(.white), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
            if level == 1 {
                let tips = Path { q in for d in seg where Int(d) % 6 == 0 { let b = point(d, height + 2); q.move(to: CGPoint(x: b.x - 1.6, y: b.y + 1)); q.addLine(to: CGPoint(x: b.x, y: b.y - 3)); q.addLine(to: CGPoint(x: b.x + 1.6, y: b.y + 1)) } }
                g.fill(tips, with: .color(Color(red: 0.5, green: 0.34, blue: 0.22)))
            }
        }
        // Towers at the level-three wall, and the gatehouse.
        if level >= 3 {
            for d in (back ? [225.0, 315.0] : [35.0, 145.0]) {
                let p = point(d)
                g.fill(Path(roundedRect: CGRect(x: p.x - 8, y: p.y - 26, width: 16, height: 26), cornerRadius: 2), with: .linearGradient(Gradient(colors: [Color(red: 0.7, green: 0.72, blue: 0.78), Color(red: 0.52, green: 0.54, blue: 0.6)]), startPoint: CGPoint(x: p.x - 8, y: 0), endPoint: CGPoint(x: p.x + 8, y: 0)))
                g.fill(Path(roundedRect: CGRect(x: p.x - 10, y: p.y - 31, width: 20, height: 6), cornerRadius: 3), with: .color(.white))
                flag(g, CGPoint(x: p.x, y: p.y - 34), Self.shu, text: "蜀")
            }
        }
        if !back {
            let g1 = point(80), g2 = point(100)
            for p in [g1, g2] {
                g.fill(Path(roundedRect: CGRect(x: p.x - 4, y: p.y - height - 12, width: 8, height: height + 12), cornerRadius: 2), with: .color(level == 1 ? Color(red: 0.5, green: 0.34, blue: 0.22) : Color(red: 0.56, green: 0.58, blue: 0.64)))
                g.fill(Path(roundedRect: CGRect(x: p.x - 5, y: p.y - height - 15, width: 10, height: 4), cornerRadius: 2), with: .color(.white))
            }
            g.fill(Path(roundedRect: CGRect(x: g1.x - 2, y: g1.y - height - 14, width: g2.x - g1.x + 4, height: 5), cornerRadius: 2), with: .color(Color(red: 0.62, green: 0.26, blue: 0.2)))
            flag(g, CGPoint(x: (g1.x + g2.x) / 2 - 5, y: g1.y - height - 16), Self.shu, text: "蜀")
        }
        _ = hub
    }

    // MARK: Weather

    private func weather(_ g: GraphicsContext) {
        let area = CGRect(x: 0, y: 36, width: IceLook.W, height: IceLook.H - 36)
        var c = g
        c.clip(to: Path(area))
        let heavy = storm
        let n = heavy > 0 ? 280 : 80
        var small = Path(), big = Path(), streaks = Path()
        var bigDots = Path()
        for i in 0..<n {
            let speed = (heavy > 0 ? 90 : 22) + Double(JevDraw.hash(i, 31) % 100) / 100 * (heavy > 0 ? 70 : 20)
            let drift = heavy > 0 ? 160.0 : 8.0
            let y = (Double(JevDraw.hash(i, 32) % 1000) / 1000 * Double(area.height) + now * speed).truncatingRemainder(dividingBy: Double(area.height)) + Double(area.minY)
            let x0 = Double(JevDraw.hash(i, 33) % 1000) / 1000 * Double(IceLook.W + 200) - 100
            let x = (x0 + now * drift + sin(now * 0.9 + Double(i)) * 6).truncatingRemainder(dividingBy: Double(IceLook.W + 100)) - 20
            let r = 0.7 + Double(JevDraw.hash(i, 34) % 100) / 100 * 1.5
            if heavy > 0, i % 2 == 0 {
                streaks.move(to: CGPoint(x: x, y: y)); streaks.addLine(to: CGPoint(x: x - 16, y: y - 6))
            } else if r > 1.6 {
                bigDots.move(to: CGPoint(x: x, y: y)); bigDots.addLine(to: CGPoint(x: x + 0.01, y: y))
            } else {
                small.move(to: CGPoint(x: x, y: y)); small.addLine(to: CGPoint(x: x + 0.01, y: y))
            }
        }
        if heavy > 0 {
            // The storm's veil over the city; the panels on the right stay clear to read.
            c.fill(Path(roundedRect: CGRect(x: 0, y: 36, width: IceLook.mapBox.minX - 2, height: IceLook.strip.minY - 38), cornerRadius: 0), with: .color(Color(red: 0.74, green: 0.85, blue: 1).opacity(0.46)))
            // Gusts: bands of blown snow sweeping across.
            if let sprite = IceSprites.gust {
                for k in 0..<2 {
                    let f = (now * 0.16 + Double(k) / 2).truncatingRemainder(dividingBy: 1)
                    let x = CGFloat(-220 + f * 880)
                    let y = 150 + CGFloat(k) * 170 + CGFloat(f) * 60
                    c.draw(Image(decorative: sprite, scale: 1), in: CGRect(x: x - 200, y: y - 48, width: 400, height: 96))
                }
            }
            c.stroke(streaks, with: .color(.white.opacity(0.85)), lineWidth: 1.3)
        }
        c.stroke(small, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        c.stroke(bigDots, with: .color(.white), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        _ = big
    }

    // MARK: The map

    private func map(_ g: GraphicsContext) {
        let w = after, box = IceLook.mapBox
        let held = "我 \(w.counties) · 魏 \(w.owner.filter { $0 == 1 }.count) · 吴 \(w.owner.filter { $0 == 2 }.count)"
        JevDraw.text(g, held, at: CGPoint(x: box.maxX - 10, y: box.minY + 14), size: 8.5, weight: .bold, colour: Color(red: 0.3, green: 0.36, blue: 0.5), anchor: .trailing, shadow: false)
        var roads = Path(), mine = Path()
        for (a, b) in iceRoads {
            let pa = IceLook.node(a), pb = IceLook.node(b)
            if w.owner[a] == 0 && w.owner[b] == 0 { mine.move(to: pa); mine.addLine(to: pb) } else { roads.move(to: pa); roads.addLine(to: pb) }
        }
        g.stroke(roads, with: .color(Color(red: 0.5, green: 0.58, blue: 0.72).opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, dash: [3, 2.5]))
        g.stroke(mine, with: .color(Self.c(Self.shu, 0.8)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        // Where an army can march today, for a person choosing.
        let targets = Set((1..<iceCounties.count).filter { w.owner[$0] != 0 && w.distance(to: $0) != nil })
        for c in 0..<iceCounties.count {
            let p = IceLook.node(c), o = w.owner[c], county = iceCounties[c]
            let r: CGFloat = county.capital ? 9 : 7
            if c == 0 {
                g.fill(Path(ellipseIn: CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.7, blue: 0.3).opacity(0.55), .clear]), center: p, startRadius: 0, endRadius: 16))
            }
            if targets.contains(c), w.over == false {
                let pulse = 0.5 + 0.5 * sin(now * 3 + Double(c))
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r - 3, y: p.y - r - 3, width: 2 * r + 6, height: 2 * r + 6)), with: .color(Color(red: 0.95, green: 0.62, blue: 0.2).opacity(0.4 + 0.4 * pulse)), lineWidth: 1.4)
            }
            g.fill(Path(ellipseIn: CGRect(x: p.x - r + 0.8, y: p.y - r + 1.6, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.18)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .radialGradient(Gradient(colors: [Self.c(Art.lit(Self.owner(o), 1.25)), Self.c(Self.owner(o))]), center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
            g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(o == 3 ? Color(red: 0.5, green: 0.56, blue: 0.68) : .white), lineWidth: 1.2)
            let mark: String = c == 0 ? "城" : o == 0 ? "蜀" : o == 1 ? "魏" : o == 2 ? "吴" : ["贼", "狼", "寇"][county.foe]
            g.draw(Text(mark).font(.system(size: county.capital ? 8.5 : 7.5, weight: .heavy, design: .rounded)).foregroundColor(o == 3 ? Color(red: 0.3, green: 0.34, blue: 0.46) : .white), at: p)
            if o != 0, c > 0 {
                g.draw(Text("\(Int(w.garrison[c].rounded()))").font(.system(size: 6.5, weight: .semibold, design: .rounded)).foregroundColor(Color(red: 0.42, green: 0.46, blue: 0.58)), at: CGPoint(x: p.x + r + 6, y: p.y - r + 1))
            }
        }
        // Armies on the march: a banner going out, or coming home.
        for m in w.marches {
            let route = path(to: m.county, in: w)
            let was = before.marches.first { $0.county == m.county && $0.hero == m.hero }
            let doneNow = Double(m.travel - m.left), doneBefore = was.map { Double($0.travel - $0.left) + ($0.back != m.back ? -Double(m.travel) : 0) } ?? doneNow - 1
            let f = max(0, min(1, JevDraw.mix(doneBefore, doneNow, JevDraw.smooth(t)) / Double(max(1, m.travel))))
            let along = m.back ? 1 - f : f
            let p = point(on: route, at: along)
            banner(g, p, name: iceHeroes[m.hero].name, soldiers: m.soldiers, back: m.back, won: m.won)
        }
    }

    /// The way from the city to a county, through land we hold.
    private func path(to county: Int, in w: IceWorld) -> [CGPoint] {
        var came: [Int: Int] = [0: 0], frontier = [0]
        while !frontier.isEmpty, came[county] == nil {
            var next: [Int] = []
            for a in frontier {
                for b in iceNeighbours[a] where came[b] == nil && (b == county || w.owner[b] == 0) {
                    came[b] = a; next.append(b)
                }
            }
            frontier = next
        }
        guard came[county] != nil else { return [IceLook.node(0), IceLook.node(county)] }
        var out = [county]
        while let last = out.last, last != 0, let from = came[last] { out.append(from) }
        return out.reversed().map(IceLook.node)
    }
    private func point(on route: [CGPoint], at f: Double) -> CGPoint {
        guard route.count > 1 else { return route.first ?? .zero }
        let lengths = zip(route, route.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = CGFloat(f) * lengths.reduce(0, +)
        for (i, l) in lengths.enumerated() {
            if left <= l || i == lengths.count - 1 {
                let u = l > 0 ? min(1, left / l) : 0
                return CGPoint(x: route[i].x + (route[i + 1].x - route[i].x) * u, y: route[i].y + (route[i + 1].y - route[i].y) * u)
            }
            left -= l
        }
        return route.last!
    }
    private func banner(_ g: GraphicsContext, _ p: CGPoint, name: String, soldiers: Int, back: Bool, won: Bool?) {
        let bob = CGFloat(sin(now * 6)) * 0.8
        g.stroke(Path { q in q.move(to: CGPoint(x: p.x, y: p.y + 4)); q.addLine(to: CGPoint(x: p.x, y: p.y - 18 + bob)) }, with: .color(Color(red: 0.3, green: 0.22, blue: 0.16)), lineWidth: 1.3)
        let wave = CGFloat(sin(now * 5)) * 1.2
        let cloth = Path { q in q.move(to: CGPoint(x: p.x, y: p.y - 18 + bob)); q.addQuadCurve(to: CGPoint(x: p.x + 20, y: p.y - 16 + wave + bob), control: CGPoint(x: p.x + 10, y: p.y - 20 - wave + bob)); q.addLine(to: CGPoint(x: p.x + 20, y: p.y - 6 + wave + bob)); q.addQuadCurve(to: CGPoint(x: p.x, y: p.y - 7 + bob), control: CGPoint(x: p.x + 10, y: p.y - 8 - wave + bob)); q.closeSubpath() }
        g.fill(cloth, with: .color(Self.c(Self.shu)))
        g.stroke(cloth, with: .color(.white.opacity(0.8)), lineWidth: 0.7)
        g.draw(Text(String(name.prefix(1))).font(.system(size: 7.5, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: p.x + 9.5, y: p.y - 12 + bob))
        let tag = back ? (won == true ? "凯旋 \(soldiers)" : "撤回 \(soldiers)") : "\(soldiers)"
        g.draw(Text(tag).font(.system(size: 6.5, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.12, green: 0.3, blue: 0.18)), at: CGPoint(x: p.x + 10, y: p.y + 1))
    }

    // MARK: The day's card: an event waiting, or the news

    private func card(_ g: GraphicsContext) {
        let w = after, box = IceLook.cardBox
        let panel = Path(roundedRect: box, cornerRadius: 12)
        g.fill(Path(roundedRect: box.offsetBy(dx: 1.5, dy: 3), cornerRadius: 12), with: .color(Color(red: 0.1, green: 0.14, blue: 0.3).opacity(0.25)))
        if let e = w.event {
            let fresh = e.arrived == w.day ? min(1, since / 0.5) : 1
            g.fill(panel, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.9), Color(red: 0.98, green: 0.9, blue: 0.78)]), startPoint: CGPoint(x: 0, y: box.minY), endPoint: CGPoint(x: 0, y: box.maxY)))
            g.stroke(panel, with: .color(Color(red: 0.86, green: 0.6, blue: 0.3).opacity(0.6 + 0.4 * (1 - fresh))), lineWidth: 1.5 + 2 * CGFloat(1 - fresh))
            let icon = ["🧳", "⛏️", "🌨️", "🐫", "🤒", "🏮", "🐺", "🛡️", "🧊", "🕵️", "💍"][e.kind]
            JevDraw.text(g, icon, at: CGPoint(x: box.minX + 16, y: box.minY + 16), size: 14, shadow: false)
            JevDraw.text(g, IceWorld.eventTitles[e.kind], at: CGPoint(x: box.minX + 30, y: box.minY + 15), size: 10.5, weight: .heavy, colour: Color(red: 0.36, green: 0.2, blue: 0.1), anchor: .leading, shadow: false)
            JevDraw.text(g, e.kind == 0 ? "\(e.amount) 个人，冻得发抖 · 还剩 \(e.left) 天" : "还剩 \(e.left) 天答复", at: CGPoint(x: box.minX + 30, y: box.minY + 29), size: 8, weight: .semibold,
                         colour: Color(red: 0.55, green: 0.36, blue: 0.2), anchor: .leading, shadow: false)
        } else {
            g.fill(panel, with: .color(Color(red: 0.97, green: 0.98, blue: 1).opacity(0.93)))
            g.stroke(panel, with: .color(Color(red: 0.4, green: 0.5, blue: 0.7).opacity(0.5)), lineWidth: 1)
            JevDraw.text(g, "今日", at: CGPoint(x: box.minX + 12, y: box.minY + 15), size: 11, weight: .heavy, colour: Color(red: 0.2, green: 0.28, blue: 0.46), anchor: .leading, shadow: false)
            var lines = w.news
            if lines.isEmpty {
                if let cold = w.nextCold(after: w.day), cold.start - w.day <= 8, cold.start > w.day - 1 {
                    lines.append(cold.blizzard ? "大寒暴风雪还有 \(cold.start - w.day) 天" : "寒潮还有 \(max(0, cold.start - w.day)) 天")
                }
                lines.append(w.sick > 0 ? "城里有 \(w.sick) 个病人" : "城里平安")
                if w.waiting > 0 { lines.append("\(w.waiting) 人等着搬进暖屋") }
            }
            for (i, line) in lines.prefix(5).enumerated() {
                g.draw(Text(line).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundColor(Color(red: 0.2, green: 0.24, blue: 0.34)),
                       in: CGRect(x: box.minX + 12, y: box.minY + 26 + CGFloat(i) * 17, width: box.width - 22, height: 17))
            }
        }
        for b in IceLook.buttons(w) {
            let face = Path(roundedRect: b.rect, cornerRadius: b.rect.height / 2)
            if b.row == 3 {
                g.fill(face, with: .color(Color(red: 0.3, green: 0.4, blue: 0.62).opacity(0.85)))
            } else {
                g.fill(face, with: .linearGradient(Gradient(colors: b.on ? [Color(red: 0.98, green: 0.72, blue: 0.3), Color(red: 0.9, green: 0.52, blue: 0.2)] : [Color(white: 0.8), Color(white: 0.7)]),
                                                   startPoint: CGPoint(x: 0, y: b.rect.minY), endPoint: CGPoint(x: 0, y: b.rect.maxY)))
                g.stroke(face, with: .color(.white.opacity(0.7)), lineWidth: 0.8)
            }
            g.draw(Text(b.text).font(.system(size: b.row == 3 ? 8.5 : 9.5, weight: .bold, design: .rounded)).foregroundColor(.white), at: CGPoint(x: b.rect.midX, y: b.rect.midY))
        }
    }

    /// A battle's outcome over the map, for a few seconds.
    private func reports(_ g: GraphicsContext) {
        guard !after.reports.isEmpty, since < 4.5 else { return }
        let fade = min(1, (4.5 - since) / 0.8), pop = JevDraw.smooth(min(1, since / 0.35))
        for (i, r) in after.reports.prefix(2).enumerated() {
            let p = IceLook.node(r.county)
            JevDraw.blast(g, at: p, size: 9, age: since * 0.8)
            let text = r.won ? "\(iceHeroes[r.hero].name) 攻下\(iceCounties[r.county].name)！" : "\(iceHeroes[r.hero].name) 败于\(iceCounties[r.county].name)"
            let rect = CGRect(x: IceLook.mapBox.minX + 8, y: IceLook.mapBox.maxY - 40 - CGFloat(i) * 32, width: IceLook.mapBox.width - 16, height: 28)
            var c = g
            c.opacity = fade
            c.translateBy(x: rect.midX, y: rect.midY); c.scaleBy(x: CGFloat(0.7 + 0.3 * pop), y: CGFloat(0.7 + 0.3 * pop)); c.translateBy(x: -rect.midX, y: -rect.midY)
            c.fill(Path(roundedRect: rect, cornerRadius: 9), with: .linearGradient(Gradient(colors: r.won ? [Color(red: 0.28, green: 0.66, blue: 0.4), Color(red: 0.16, green: 0.46, blue: 0.28)] : [Color(red: 0.8, green: 0.3, blue: 0.26), Color(red: 0.56, green: 0.16, blue: 0.14)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            c.stroke(Path(roundedRect: rect, cornerRadius: 9), with: .color(.white.opacity(0.8)), lineWidth: 1)
            JevDraw.text(c, (r.won ? "⚔ " : "✕ ") + text, at: CGPoint(x: rect.midX, y: rect.minY + 10), size: 10.5, weight: .heavy)
            JevDraw.text(c, r.won ? "伤 \(r.wounded) 亡 \(r.killed)" + (r.people > 0 ? " · \(r.people) 人来投" : "") : "伤 \(r.wounded) 亡 \(r.killed) · 伤兵会慢慢养好", at: CGPoint(x: rect.midX, y: rect.minY + 21), size: 7.5, weight: .semibold, colour: .white.opacity(0.9), shadow: false)
        }
    }

    // MARK: The generals

    private func generals(_ g: GraphicsContext) {
        let w = after, box = IceLook.strip
        var chips: [(hero: Int, state: String, ghost: Bool)] = w.generals.map { gen in
            let state: String
            if gen.away, let m = w.marches.first(where: { $0.hero == gen.hero }) { state = m.back ? "回城中" : "出征\(iceCounties[m.county].name)" }
            else if let k = gen.governs { state = "管\(k.cn)" }
            else { state = "空闲" }
            return (gen.hero, state, false)
        }
        if w.has(.tavern) { chips += w.offered.map { ($0, "酒馆 \(iceHeroes[$0].food)粮\(iceHeroes[$0].iron)铁", true) } }
        else { chips.append((-1, "建酒馆招武将", true)) }
        let width: CGFloat = 88, gap: CGFloat = 1.5
        for (i, chip) in chips.prefix(7).enumerated() {
            let r = CGRect(x: box.minX + 4 + CGFloat(i) * (width + gap), y: box.minY + 4, width: width, height: box.height - 8)
            var c = g
            if chip.ghost { c.opacity = 0.6 }
            guard chip.hero >= 0 else {
                c.stroke(Path(roundedRect: r, cornerRadius: 9), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                JevDraw.text(c, chip.state, at: CGPoint(x: r.midX, y: r.midY), size: 8.5, weight: .bold, colour: .white.opacity(0.85), shadow: false)
                continue
            }
            let hero = iceHeroes[chip.hero]
            c.fill(Path(roundedRect: r, cornerRadius: 9), with: .linearGradient(Gradient(colors: [Self.c(Art.lit(hero.coat, 0.9), 0.9), Self.c(Art.lit(hero.coat, 0.55), 0.9)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
            c.stroke(Path(roundedRect: r, cornerRadius: 9), with: .color(.white.opacity(chip.ghost ? 0.4 : 0.55)), style: StrokeStyle(lineWidth: 1, dash: chip.ghost ? [3, 3] : []))
            portrait(c, hero, at: CGPoint(x: r.minX + 20, y: r.midY + 1), size: 18)
            JevDraw.text(c, hero.name, at: CGPoint(x: r.minX + 41, y: r.minY + 11), size: 10.5, weight: .heavy, anchor: .leading, shadow: false)
            c.draw(Text("武\(hero.war) 智\(hero.wit) 统\(hero.lead)").font(.system(size: 6.4, weight: .semibold).width(.condensed)).foregroundColor(.white.opacity(0.88)),
                   at: CGPoint(x: r.minX + 41, y: r.minY + 23), anchor: .leading)
            c.draw(Text(chip.state).font(.system(size: 7, weight: .bold, design: .rounded).width(.condensed)).foregroundColor(Color(red: 1, green: 0.92, blue: 0.7)), at: CGPoint(x: r.minX + 41, y: r.minY + 34), anchor: .leading)
        }
    }

    /// A general as a round-faced little figure in a fur hood, with what marks them out.
    private func portrait(_ g: GraphicsContext, _ hero: IceHero, at p: CGPoint, size s: CGFloat) {
        let fur = Self.c(hero.fur), furDark = Self.c(Art.lit(hero.fur, 0.82))
        // Behind the head: feathers, a crest.
        if hero.mark == 1 {
            for side in [-1.0, 1.0] as [CGFloat] {
                g.stroke(Path { q in q.move(to: CGPoint(x: p.x + side * s * 0.25, y: p.y - s * 0.7)); q.addQuadCurve(to: CGPoint(x: p.x + side * s * 1.05, y: p.y - s * 1.35), control: CGPoint(x: p.x + side * s * 0.2, y: p.y - s * 1.5)) },
                         with: .color(Color(red: 0.95, green: 0.7, blue: 0.2)), style: StrokeStyle(lineWidth: s * 0.12, lineCap: .round))
                g.stroke(Path { q in q.move(to: CGPoint(x: p.x + side * s * 0.25, y: p.y - s * 0.7)); q.addQuadCurve(to: CGPoint(x: p.x + side * s * 1.05, y: p.y - s * 1.35), control: CGPoint(x: p.x + side * s * 0.2, y: p.y - s * 1.5)) },
                         with: .color(Color(red: 0.7, green: 0.14, blue: 0.12)), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
            }
        }
        // The hood: a round of fur with a fluffy rim.
        g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.95, y: p.y - s * 0.95, width: s * 1.9, height: s * 1.9)), with: .color(furDark))
        g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.85, y: p.y - s * 0.95, width: s * 1.6, height: s * 1.6)), with: .color(fur))
        var tufts = Path()
        for n in 0..<12 {
            let a = Double(n) / 12 * 2 * .pi
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * s * 0.88, y: p.y + CGFloat(sin(a)) * s * 0.88)
            tufts.addEllipse(in: CGRect(x: q.x - s * 0.2, y: q.y - s * 0.2, width: s * 0.4, height: s * 0.4))
        }
        g.fill(tufts, with: .color(fur))
        // Coat collar in their colour.
        g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.7, y: p.y + s * 0.75)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.7, y: p.y + s * 0.75), control: CGPoint(x: p.x, y: p.y + s * 0.35)); q.addLine(to: CGPoint(x: p.x + s * 0.55, y: p.y + s * 0.98)); q.addLine(to: CGPoint(x: p.x - s * 0.55, y: p.y + s * 0.98)); q.closeSubpath() }, with: .color(Self.c(hero.coat)))
        // The face.
        let face = CGRect(x: p.x - s * 0.58, y: p.y - s * 0.52, width: s * 1.16, height: s * 1.1)
        g.fill(Path(ellipseIn: face), with: .color(Self.c(hero.skin)))
        // Hair: a fringe, grey or dark.
        g.fill(Path { q in q.move(to: CGPoint(x: face.minX, y: face.midY - s * 0.05)); q.addQuadCurve(to: CGPoint(x: face.maxX, y: face.midY - s * 0.05), control: CGPoint(x: p.x, y: face.minY - s * 0.45)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.1, y: face.minY + s * 0.28), control: CGPoint(x: face.maxX - s * 0.1, y: face.minY + s * 0.1)); q.addQuadCurve(to: CGPoint(x: face.minX, y: face.midY - s * 0.05), control: CGPoint(x: face.minX + s * 0.2, y: face.minY + s * 0.2)); q.closeSubpath() },
               with: .color(Self.c(hero.hair)))
        // Eyes with a shine, cheeks, a small mouth.
        for side in [-1.0, 1.0] as [CGFloat] {
            let e = CGPoint(x: p.x + side * s * 0.24, y: p.y + s * 0.08)
            g.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.09, y: e.y - s * 0.12, width: s * 0.18, height: s * 0.24)), with: .color(Color(red: 0.12, green: 0.08, blue: 0.08)))
            g.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.03, y: e.y - s * 0.09, width: s * 0.07, height: s * 0.07)), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: e.x + side * s * 0.1 - s * 0.1, y: e.y + s * 0.13, width: s * 0.2, height: s * 0.1)), with: .color(Color(red: 1, green: 0.5, blue: 0.5).opacity(0.5)))
        }
        if hero.mark != 3 && hero.mark != 6 && hero.mark != 7 {
            g.stroke(Path { q in q.move(to: CGPoint(x: p.x - s * 0.08, y: p.y + s * 0.3)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.08, y: p.y + s * 0.3), control: CGPoint(x: p.x, y: p.y + s * 0.38)) }, with: .color(Color(red: 0.5, green: 0.2, blue: 0.2)), lineWidth: s * 0.05)
        }
        switch hero.mark {
        case 2:      // a feather fan, and a scholar's cap
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.3, y: face.minY - s * 0.28, width: s * 0.6, height: s * 0.3), cornerRadius: s * 0.08), with: .color(Self.c(hero.accent)))
            var fan = g; fan.translateBy(x: p.x + s * 0.72, y: p.y + s * 0.45); fan.rotate(by: .radians(-0.5 + 0.1 * sin(now * 2)))
            fan.fill(Path { q in q.move(to: .zero); q.addQuadCurve(to: CGPoint(x: -s * 0.35, y: -s * 0.85), control: CGPoint(x: -s * 0.5, y: -s * 0.3)); q.addQuadCurve(to: CGPoint(x: s * 0.35, y: -s * 0.85), control: CGPoint(x: 0, y: -s * 1.05)); q.addQuadCurve(to: .zero, control: CGPoint(x: s * 0.5, y: -s * 0.3)); q.closeSubpath() }, with: .color(.white))
            fan.stroke(Path { q in for n in -2...2 { q.move(to: .zero); q.addLine(to: CGPoint(x: CGFloat(n) * s * 0.14, y: -s * 0.85)) } }, with: .color(Color(white: 0.75)), lineWidth: s * 0.03)
        case 3:      // a long beard
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.35, y: p.y + s * 0.3)); q.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s * 1.3), control: CGPoint(x: p.x - s * 0.4, y: p.y + s * 1)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.35, y: p.y + s * 0.3), control: CGPoint(x: p.x + s * 0.4, y: p.y + s * 1)); q.closeSubpath() }, with: .color(Self.c(hero.hair)))
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.45, y: face.minY - s * 0.3, width: s * 0.9, height: s * 0.32), cornerRadius: s * 0.1), with: .color(Self.c(hero.coat)))
        case 4:      // a flower in the hood
            let f = CGPoint(x: p.x + s * 0.62, y: p.y - s * 0.55)
            for n in 0..<5 { let a = Double(n) / 5 * 2 * .pi; g.fill(Path(ellipseIn: CGRect(x: f.x + CGFloat(cos(a)) * s * 0.16 - s * 0.13, y: f.y + CGFloat(sin(a)) * s * 0.16 - s * 0.13, width: s * 0.26, height: s * 0.26)), with: .color(Self.c(hero.accent))) }
            g.fill(Path(ellipseIn: CGRect(x: f.x - s * 0.08, y: f.y - s * 0.08, width: s * 0.16, height: s * 0.16)), with: .color(Color(red: 1, green: 0.9, blue: 0.4)))
        case 5:      // a silver helmet with a red plume
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX - s * 0.05, y: face.midY - s * 0.12)); q.addQuadCurve(to: CGPoint(x: face.maxX + s * 0.05, y: face.midY - s * 0.12), control: CGPoint(x: p.x, y: face.minY - s * 0.55)); q.closeSubpath() },
                   with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(red: 0.62, green: 0.68, blue: 0.76)]), startPoint: CGPoint(x: face.minX, y: face.minY), endPoint: CGPoint(x: face.maxX, y: face.midY)))
            g.fill(Path { q in q.move(to: CGPoint(x: p.x, y: face.minY - s * 0.1)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.55, y: face.minY - s * 0.55), control: CGPoint(x: p.x + s * 0.1, y: face.minY - s * 0.6)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.1, y: face.minY), control: CGPoint(x: p.x + s * 0.4, y: face.minY - s * 0.2)); q.closeSubpath() }, with: .color(Color(red: 0.88, green: 0.2, blue: 0.18)))
        case 6, 7:   // a bushy beard, dark or white
            let beard = hero.mark == 7 ? Color(white: 0.96) : Self.c(hero.hair)
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX + s * 0.05, y: p.y + s * 0.2)); q.addQuadCurve(to: CGPoint(x: face.maxX - s * 0.05, y: p.y + s * 0.2), control: CGPoint(x: p.x, y: p.y + s * 1.05)); q.addQuadCurve(to: CGPoint(x: face.minX + s * 0.05, y: p.y + s * 0.2), control: CGPoint(x: p.x, y: p.y + s * 0.5)); q.closeSubpath() }, with: .color(beard))
            if hero.mark == 6 { g.stroke(Path { q in for side in [-1.0, 1.0] as [CGFloat] { q.move(to: CGPoint(x: p.x + side * s * 0.1, y: p.y - s * 0.12)); q.addLine(to: CGPoint(x: p.x + side * s * 0.4, y: p.y - s * 0.2)) } }, with: .color(Self.c(hero.hair)), lineWidth: s * 0.08) }
        case 8:      // a little gold crown
            g.fill(Path { q in let b = face.minY - s * 0.05; q.move(to: CGPoint(x: p.x - s * 0.35, y: b)); q.addLine(to: CGPoint(x: p.x - s * 0.35, y: b - s * 0.3)); q.addLine(to: CGPoint(x: p.x - s * 0.17, y: b - s * 0.15)); q.addLine(to: CGPoint(x: p.x, y: b - s * 0.38)); q.addLine(to: CGPoint(x: p.x + s * 0.17, y: b - s * 0.15)); q.addLine(to: CGPoint(x: p.x + s * 0.35, y: b - s * 0.3)); q.addLine(to: CGPoint(x: p.x + s * 0.35, y: b)); q.closeSubpath() }, with: .color(Self.c(hero.accent)))
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.28, y: p.y + s * 0.32)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.28, y: p.y + s * 0.32), control: CGPoint(x: p.x, y: p.y + s * 0.62)); q.closeSubpath() }, with: .color(Self.c(hero.hair)))
        default:     // a topknot tied with their colour
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.16, y: face.minY - s * 0.3, width: s * 0.32, height: s * 0.3)), with: .color(Self.c(hero.hair)))
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.2, y: face.minY - s * 0.06, width: s * 0.4, height: s * 0.1), cornerRadius: s * 0.05), with: .color(Self.c(hero.accent)))
        }
    }

    // MARK: The numbers along the top

    private func hud(_ g: GraphicsContext) {
        let w = after, b = before, e = JevDraw.smooth(t)
        func eased(_ x: Double, _ y: Double) -> Int { Int(JevDraw.mix(x, y, e).rounded()) }
        // The day and the thermometer.
        let day = min(w.day, IceWorld.days)
        JevDraw.text(g, "第 \(day) 天", at: CGPoint(x: 13, y: 18), size: 12, weight: .heavy, anchor: .leading, shadow: false)
        let temp = JevDraw.mix(b.temperature(max(1, min(b.day, IceWorld.days))), w.temperature(max(1, min(w.day, IceWorld.days))), e)
        let bulb = CGPoint(x: 80, y: 23)
        let frac = CGFloat(max(0, min(1, (temp + 60) / 60)))
        let hot = Color(red: 0.3 + 0.7 * Double(frac), green: 0.5, blue: 1 - 0.8 * Double(frac))
        g.fill(Path(roundedRect: CGRect(x: bulb.x - 1.5, y: 9 + 13 * (1 - frac), width: 3, height: 13 * frac + 1), cornerRadius: 1.5), with: .color(hot))
        g.fill(Path(ellipseIn: CGRect(x: bulb.x - 4, y: bulb.y - 3, width: 8, height: 8)), with: .color(hot))
        JevDraw.text(g, "\(Int(temp.rounded()))°C", at: CGPoint(x: 88, y: 18), size: 12, weight: .heavy, colour: temp < -40 ? Color(red: 0.7, green: 0.85, blue: 1) : .white, anchor: .leading, shadow: false)
        // Stores and soldiers.
        let items: [(String, Color, Int)] = [
            ("煤", Color(red: 0.25, green: 0.25, blue: 0.3), eased(b.stock.coal, w.stock.coal)),
            ("木", Color(red: 0.7, green: 0.48, blue: 0.26), eased(b.stock.wood, w.stock.wood)),
            ("粮", Color(red: 0.95, green: 0.66, blue: 0.24), eased(b.stock.food, w.stock.food)),
            ("铁", Color(red: 0.6, green: 0.64, blue: 0.72), eased(b.stock.iron, w.stock.iron)),
            ("兵", Self.c(Self.shu), eased(Double(b.soldiers), Double(w.soldiers))),
        ]
        let made = w.output(w.day)
        let rates = [made.coal - w.burnRate, made.wood, made.food - w.eats, made.iron]
        for (i, item) in items.enumerated() {
            let x = 146 + CGFloat(i) * 65
            JevDraw.text(g, "\(item.2)", at: CGPoint(x: x + 20, y: 15), size: 10.5, weight: .heavy, anchor: .leading, shadow: false)
            if i < 4 {
                let r = rates[i]
                JevDraw.text(g, (r >= 0 ? "+" : "") + "\(Int(r.rounded()))/天", at: CGPoint(x: x + 20, y: 26), size: 6.5, weight: .bold,
                             colour: r < 0 ? Color(red: 1, green: 0.55, blue: 0.5) : Color(red: 0.7, green: 0.95, blue: 0.75), anchor: .leading, shadow: false)
            } else {
                JevDraw.text(g, w.wounded > 0 ? "伤 \(w.wounded)" : "", at: CGPoint(x: x + 20, y: 26), size: 6.5, weight: .bold, colour: Color(red: 1, green: 0.8, blue: 0.6), anchor: .leading, shadow: false)
            }
        }
        // People and their heart.
        JevDraw.text(g, "👥 \(eased(Double(b.citizens), Double(w.citizens)))", at: CGPoint(x: 480, y: 15), size: 10.5, weight: .heavy, anchor: .leading, shadow: false)
        JevDraw.text(g, w.sick > 0 ? "病 \(w.sick)" : "无病", at: CGPoint(x: 480, y: 26), size: 6.5, weight: .bold, colour: w.sick > 0 ? Color(red: 1, green: 0.7, blue: 0.6) : Color(red: 0.7, green: 0.95, blue: 0.75), anchor: .leading, shadow: false)
        let mood = JevDraw.mix(b.morale, w.morale, e)
        let bar = CGRect(x: 556, y: 13, width: 72, height: 10)
        g.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(mood / 100), height: bar.height), cornerRadius: 5),
               with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.45, blue: 0.5), Color(red: 1, green: 0.7, blue: 0.4)]), startPoint: CGPoint(x: bar.minX, y: 0), endPoint: CGPoint(x: bar.maxX, y: 0)))
        g.draw(Text("♥ \(Int(mood.rounded()))").font(.system(size: 7.5, weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: bar.midX, y: bar.midY))
    }
}
