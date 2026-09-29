import Foundation

/// 冰河三国（建造）— a frozen city of the Three Kingdoms, built with the mouse
/// around a great furnace, in real time. Foundation only, so it runs
/// headless: a lord can be tried for a hundred days in a second or two.
///
/// The cold comes down day by day, with cold snaps and one great blizzard
/// around days 60–70. The furnace in the middle burns coal; its level sets how
/// far its heat reaches. Houses inside the heat are warm; houses outside it,
/// and people without a house, get cold, then sick, and some freeze. Everybody
/// eats. The people do the work themselves — felling pines, digging coal and
/// iron, cutting stone, hunting in the woods, fishing through the ice, tending
/// the greenhouse, carrying everything to the storage and the coal to the
/// furnace, putting up what the lord places — and walk the snow and the roads
/// between. 民心 speeds or slows them and decides whether newcomers settle.
/// Generals recruited at the tavern govern a building or lead soldiers from
/// the barracks against the counties on the snowy map, where 魏 and 吴 expand
/// and, once they border us, raid the city. A wall on the north cuts the wind.

struct IceTile: Hashable { var x: Int, y: Int }

enum IceGood: Int, CaseIterable {
    case coal, wood, food, stone, iron
    static let names = ["煤", "木", "粮", "石", "铁"]
    static let english = ["coal", "wood", "food", "stone", "iron"]
    var name: String { Self.names[rawValue] }
}

enum IceGround: UInt8 { case snow, forest, rock, coal, ore, ice }

enum IceBuildKind: Int, CaseIterable {
    case furnace, house, storage, lumber, coalMine, ironMine, quarry, hunter, fishery, greenhouse, clinic, barracks, tavern

    static let names = ["熔炉", "民居", "仓库", "伐木场", "煤矿", "铁矿", "采石场", "猎场", "冰钓屋", "温室", "医馆", "兵营", "酒馆"]
    static let english = ["the furnace", "a house", "a storage", "a lumber camp", "a coal mine", "an iron mine", "a quarry", "a hunting lodge",
                          "an ice-fishing hut", "a greenhouse", "a clinic", "a barracks", "a tavern"]
    var name: String { Self.names[rawValue] }
    var english: String { Self.english[rawValue] }
    var size: Int { [3, 2, 2, 2, 3, 3, 3, 2, 2, 3, 2, 3, 2][rawValue] }
    /// Coal, wood, food, stone, iron to put it up.
    var cost: [Double] {
        switch self {
        case .furnace: return [0, 0, 0, 0, 0]
        case .house: return [0, 20, 0, 6, 0]
        case .storage: return [0, 30, 0, 10, 0]
        case .lumber: return [0, 20, 0, 0, 0]
        case .coalMine: return [0, 30, 0, 8, 0]
        case .ironMine: return [0, 35, 0, 12, 0]
        case .quarry: return [0, 25, 0, 0, 0]
        case .hunter: return [0, 20, 0, 0, 0]
        case .fishery: return [0, 18, 0, 0, 0]
        case .greenhouse: return [0, 40, 0, 12, 15]
        case .clinic: return [0, 30, 0, 15, 5]
        case .barracks: return [0, 40, 0, 20, 10]
        case .tavern: return [0, 45, 0, 15, 5]
        }
    }
    /// Seconds for one builder to put it up.
    var work: Double { [60, 16, 20, 14, 24, 26, 20, 14, 14, 28, 22, 28, 24][rawValue] }
    /// How many can work there.
    var slots: Int { [0, 0, 0, 4, 5, 4, 4, 3, 3, 4, 2, 0, 0][rawValue] }
    /// Does its work happen out in the snow?
    var outdoor: Bool { [.lumber, .coalMine, .ironMine, .quarry, .hunter, .fishery].contains(self) }
    /// The kinds a lord can place.
    static let placeable: [IceBuildKind] = [.house, .storage, .lumber, .coalMine, .ironMine, .quarry, .hunter, .fishery, .greenhouse, .clinic, .barracks, .tavern]
}

enum IceTask: Equatable {
    case idle
    /// Standing about, or resting indoors, for a few seconds.
    case pause(Double)
    case wander(IceTile)
    case goHome
    /// At a workplace: a mine, a quarry, the greenhouse, the clinic.
    case work(Int)
    /// A pine to fell, a wood to hunt in, a hole in the ice to fish.
    case harvest(IceTile)
    /// Carrying the load to a storage.
    case store(Int)
    /// To a storage for a good — for a house, a building site or the furnace.
    case fetch(Int, IceGood, Int)
    /// Carrying it there.
    case bring(Int)
    case build(Int)
    /// Sick: to a clinic's bed.
    case heal(Int)
    /// Leaving the city for good, walking off the map.
    case leave(IceTile)
}

struct IcePerson {
    let id: Int
    var x: Double, y: Double
    var kid: Bool
    /// A child's days until grown.
    var growing = 0.0
    var home: Int? = nil
    var job: Int? = nil
    var task: IceTask = .idle
    var path: [IceTile] = []
    var repath = 0.0
    var carrying: IceGood? = nil
    var amount = 0.0
    var sick = false
    /// Days in a row without food.
    var hungry = 0
    var busy = 0.0
    var facing = 1.0
    /// Seconds since the last stroke of work, for drawing.
    var swung = 9.0
    /// Indoors: not on the map.
    var inside = false
    /// The colour of the fur coat.
    var coat: Int
    var worker: Bool { !kid && !sick }
}

extension IceCity {
    /// Is this person on the way out of the city for good?
    static func going(_ p: IcePerson) -> Bool { if case .leave = p.task { return true }; return false }
}

struct IceBuilding {
    let id: Int
    let kind: IceBuildKind
    let x: Int, y: Int
    var done = false
    var progress = 0.0
    /// Materials brought to the site so far (for the furnace: to its upgrade).
    var delivered = [Double](repeating: 0, count: 5)
    /// A storage's goods; a house's food; the furnace's coal.
    var stock = [Double](repeating: 0, count: 5)
    /// How many the lord wants working here.
    var wanted = 0
    /// Mines and quarries: what is left in the ground.
    var reserve = 0.0
    /// Houses and the furnace: who is out fetching for it.
    var fetcher: Int? = nil
    /// What its workers brought in today, and yesterday.
    var output = 0.0, lastOutput = 0.0
    /// The furnace's level, and an upgrade under way.
    var level = 1
    var upgrading = false
    /// A barracks: soldiers in training, and seconds of it left.
    var batch = 0
    var training = 0.0
    /// A site: under construction, or the furnace being upgraded.
    var site: Bool { !done || upgrading }
}

/// Something that happened a moment ago, for the picture.
struct IceMoment {
    enum Kind: Equatable {
        case died(String), arrived(Int), left(Int), finished(IceBuildKind), upgraded(Int), felled, sick, cured, tribute(IceGood, Int, String), news(String)
    }
    let kind: Kind
    let x: Double, y: Double
    let time: Double
}

// MARK: - Generals, counties, war

enum IceTalent { case brawler, charge, peerless, planner, healer, charm, saint, fire, ruler, balance, veteran, cavalry }

/// A general: what they are good at, what they cost at the tavern, how they look.
struct IceOfficer {
    let name: String, war: Int, wit: Int, lead: Int
    let talent: IceTalent
    let food: Int, iron: Int
    let talentCN: String, talentEN: String
    let coat: (Double, Double, Double), fur: (Double, Double, Double), accent: (Double, Double, Double), hair: (Double, Double, Double)
    /// 0 plain, 1 pheasant feathers, 2 feather fan, 3 long beard, 4 flower, 5 helmet crest, 6 bushy beard, 7 white beard, 8 crown
    let mark: Int
    let skin: (Double, Double, Double)
}

let iceOfficers: [IceOfficer] = [
    IceOfficer(name: "张飞", war: 98, wit: 40, lead: 80, talent: .brawler, food: 0, iron: 0, talentCN: "万人敌：打山贼、狼群、冰寇 +40%", talentEN: "+40% battle power against bandits, wolves and ice raiders",
               coat: (0.22, 0.22, 0.28), fur: (0.42, 0.3, 0.2), accent: (0.8, 0.2, 0.16), hair: (0.08, 0.07, 0.07), mark: 6, skin: (0.86, 0.68, 0.54)),
    IceOfficer(name: "赵云", war: 92, wit: 70, lead: 88, talent: .charge, food: 90, iron: 50, talentCN: "七进七出：战力 +25%", talentEN: "a brave charge: +25% battle power",
               coat: (0.93, 0.95, 0.98), fur: (0.99, 0.99, 1), accent: (0.66, 0.72, 0.8), hair: (0.1, 0.09, 0.1), mark: 5, skin: (0.98, 0.84, 0.72)),
    IceOfficer(name: "吕布", war: 100, wit: 30, lead: 80, talent: .peerless, food: 120, iron: 80, talentCN: "天下无双：战力 +45%，但在城里民心每天 −1", talentEN: "unmatched in battle: +45% battle power, but morale falls 1 a day while he serves",
               coat: (0.72, 0.1, 0.12), fur: (0.14, 0.11, 0.12), accent: (0.95, 0.75, 0.25), hair: (0.1, 0.08, 0.08), mark: 1, skin: (0.95, 0.8, 0.66)),
    IceOfficer(name: "诸葛亮", war: 30, wit: 100, lead: 95, talent: .planner, food: 110, iron: 60, talentCN: "神机妙算：战力 +15%，管建筑多 20%", talentEN: "plans: +15% battle power, and governs a building 20% better than others",
               coat: (0.93, 0.92, 0.86), fur: (0.86, 0.87, 0.9), accent: (0.3, 0.46, 0.72), hair: (0.12, 0.1, 0.1), mark: 2, skin: (0.98, 0.86, 0.74)),
    IceOfficer(name: "华佗", war: 20, wit: 85, lead: 30, talent: .healer, food: 60, iron: 20, talentCN: "青囊：每天多治 3 人，管医馆多治 8 人", talentEN: "a healer: cures 3 more sick a day, 8 more when he governs a clinic",
               coat: (0.42, 0.62, 0.44), fur: (0.84, 0.78, 0.66), accent: (0.72, 0.5, 0.26), hair: (0.9, 0.9, 0.9), mark: 7, skin: (0.95, 0.8, 0.66)),
    IceOfficer(name: "貂蝉", war: 40, wit: 80, lead: 50, talent: .charm, food: 60, iron: 20, talentCN: "闭月：在城里民心每天 +1", talentEN: "beloved: morale +1 a day while she serves",
               coat: (0.96, 0.62, 0.72), fur: (1, 0.97, 0.98), accent: (0.9, 0.3, 0.45), hair: (0.12, 0.08, 0.1), mark: 4, skin: (1, 0.87, 0.8)),
    IceOfficer(name: "关羽", war: 97, wit: 75, lead: 95, talent: .saint, food: 100, iron: 60, talentCN: "武圣：战力 +30%", talentEN: "+30% battle power",
               coat: (0.2, 0.5, 0.32), fur: (0.9, 0.86, 0.78), accent: (0.85, 0.7, 0.3), hair: (0.08, 0.07, 0.07), mark: 3, skin: (0.86, 0.36, 0.3)),
    IceOfficer(name: "周瑜", war: 70, wit: 96, lead: 92, talent: .fire, food: 100, iron: 50, talentCN: "火攻：打魏吴 +35%；管熔炉省煤 25%", talentEN: "fire: +35% battle power against Wei and Wu, and governing the furnace it burns 25% less coal",
               coat: (0.86, 0.36, 0.2), fur: (0.98, 0.93, 0.84), accent: (0.98, 0.78, 0.3), hair: (0.12, 0.08, 0.06), mark: 0, skin: (0.99, 0.86, 0.74)),
    IceOfficer(name: "曹操", war: 72, wit: 92, lead: 98, talent: .ruler, food: 120, iron: 70, talentCN: "挟令：战力 +10%，攻下的州来人多一半，管建筑多 10%", talentEN: "a ruler: +10% battle power, a county he takes gives half again as many people, and he governs 10% better",
               coat: (0.28, 0.26, 0.5), fur: (0.16, 0.15, 0.18), accent: (0.9, 0.76, 0.3), hair: (0.1, 0.09, 0.1), mark: 8, skin: (0.95, 0.8, 0.68)),
    IceOfficer(name: "孙权", war: 65, wit: 82, lead: 88, talent: .balance, food: 80, iron: 40, talentCN: "制衡：民心每天 +0.5，管建筑多 10%", talentEN: "balance: morale +0.5 a day, and he governs 10% better",
               coat: (0.78, 0.22, 0.24), fur: (0.95, 0.9, 0.84), accent: (0.55, 0.3, 0.7), hair: (0.36, 0.2, 0.3), mark: 6, skin: (0.97, 0.82, 0.7)),
    IceOfficer(name: "黄忠", war: 93, wit: 60, lead: 82, talent: .veteran, food: 80, iron: 40, talentCN: "老当益壮：战力 +10%，不怕冷", talentEN: "a veteran: +10% battle power and no cold penalty",
               coat: (0.76, 0.56, 0.26), fur: (0.7, 0.62, 0.52), accent: (0.5, 0.3, 0.16), hair: (0.92, 0.92, 0.92), mark: 7, skin: (0.93, 0.76, 0.62)),
    IceOfficer(name: "马超", war: 96, wit: 50, lead: 80, talent: .cavalry, food: 90, iron: 50, talentCN: "西凉铁骑：战力 +15%，来回各快一天", talentEN: "cavalry: +15% battle power and marches 1 day faster each way",
               coat: (0.86, 0.87, 0.92), fur: (0.96, 0.96, 0.98), accent: (0.2, 0.42, 0.74), hair: (0.14, 0.1, 0.08), mark: 5, skin: (0.98, 0.84, 0.72)),
]

/// A general in the lord's service.
struct IceHired {
    var officer: Int
    /// The building they govern, by id.
    var governs: Int? = nil
    var away = false
}

/// A county on the snowy map: where it sits, who holds it at first, what it gives.
struct IceRegion {
    let name: String, x: Double, y: Double
    /// 0 bandits, 1 wolves, 2 ice raiders, 3 Wei, 4 Wu; −1 is our own city.
    let foe: Int
    let low: Int, high: Int
    let resource: IceGood, amount: Double
    let people: Int
    let capital: Bool
}

let iceRegions: [IceRegion] = [
    IceRegion(name: "成都", x: 0.13, y: 0.6, foe: -1, low: 0, high: 0, resource: .coal, amount: 0, people: 0, capital: true),
    IceRegion(name: "梓潼", x: 0.27, y: 0.42, foe: 0, low: 16, high: 22, resource: .wood, amount: 8, people: 8, capital: false),
    IceRegion(name: "江州", x: 0.31, y: 0.7, foe: 0, low: 18, high: 24, resource: .food, amount: 8, people: 9, capital: false),
    IceRegion(name: "南中", x: 0.14, y: 0.88, foe: 1, low: 20, high: 28, resource: .iron, amount: 4, people: 6, capital: false),
    IceRegion(name: "武都", x: 0.11, y: 0.26, foe: 1, low: 20, high: 28, resource: .coal, amount: 6, people: 6, capital: false),
    IceRegion(name: "汉中", x: 0.31, y: 0.13, foe: 2, low: 40, high: 52, resource: .iron, amount: 6, people: 10, capital: false),
    IceRegion(name: "永安", x: 0.47, y: 0.53, foe: 0, low: 28, high: 36, resource: .coal, amount: 7, people: 8, capital: false),
    IceRegion(name: "武陵", x: 0.45, y: 0.85, foe: 1, low: 30, high: 40, resource: .food, amount: 9, people: 8, capital: false),
    IceRegion(name: "襄阳", x: 0.62, y: 0.35, foe: 2, low: 56, high: 70, resource: .wood, amount: 10, people: 12, capital: false),
    IceRegion(name: "长安", x: 0.55, y: 0.1, foe: 3, low: 80, high: 96, resource: .iron, amount: 8, people: 12, capital: false),
    IceRegion(name: "宛城", x: 0.77, y: 0.2, foe: 3, low: 80, high: 96, resource: .food, amount: 10, people: 12, capital: false),
    IceRegion(name: "许昌", x: 0.91, y: 0.08, foe: 3, low: 150, high: 170, resource: .coal, amount: 12, people: 20, capital: true),
    IceRegion(name: "江陵", x: 0.66, y: 0.64, foe: 4, low: 80, high: 96, resource: .wood, amount: 10, people: 12, capital: false),
    IceRegion(name: "长沙", x: 0.68, y: 0.9, foe: 4, low: 76, high: 92, resource: .food, amount: 10, people: 12, capital: false),
    IceRegion(name: "建业", x: 0.91, y: 0.72, foe: 4, low: 150, high: 170, resource: .iron, amount: 10, people: 20, capital: true),
]

let iceRegionRoads: [(Int, Int)] = [
    (0, 1), (0, 2), (0, 3), (0, 4), (1, 4), (1, 5), (1, 6), (2, 3), (2, 6), (2, 7), (4, 5), (5, 9),
    (6, 8), (6, 12), (6, 7), (7, 13), (8, 9), (8, 10), (8, 12), (9, 10), (9, 11), (10, 11), (12, 13), (12, 14), (13, 14),
]

let iceRegionLinks: [[Int]] = {
    var out = Array(repeating: [Int](), count: iceRegions.count)
    for (a, b) in iceRegionRoads { out[a].append(b); out[b].append(a) }
    return out
}()

/// Owners: 0 is us (蜀), 1 魏, 2 吴, 3 nobody's (bandits, wolves, raiders).
let iceSideCN = ["蜀", "魏", "吴", "野"]
let iceEnemyCN = ["山贼", "狼群", "冰原掠夺者", "魏军", "吴军"]
let iceEnemyEN = ["bandits", "wolves", "ice raiders", "Wei", "Wu"]

/// An army on its way to a county and back.
struct IceExpedition {
    var region: Int, officer: Int, soldiers: Int
    var travel: Int, left: Int
    var back = false
    var won: Bool? = nil
    var wounded = 0
    /// When it set out or turned for home, for the column on the map.
    var since: Double
}

/// A battle fought far away: for the news and the map.
struct IceBattle {
    var region: Int, officer: Int, won: Bool, killed: Int, wounded: Int, people: Int, time: Double
}

struct IceRivalLord {
    var reserve: Double
    var period: Int, offset: Int
    var nextRaid: Int
}

/// Raiders at the city: where they came from, whether they got through, when.
struct IceRaid {
    var rival: Int, raiders: Int, won: Bool, time: Double
    var from: IceTile
}

/// A matter the people bring to the lord, with two or more answers.
struct IceIncident {
    var kind: Int, amount: Int
    var day: Int
    /// For a lord who is not the person: the answer chosen and when, shown a moment before it is carried out.
    var chosen: Int? = nil
    var at: Double = 0
}

// MARK: - The city

struct IceCity {
    static let width = 64, height = 40
    /// Seconds of play in a day at 1×.
    static let daySeconds = 9.0
    /// The day the cold stops getting much worse from one day to the next — after it, only slowly.
    static let steepDays = 100
    /// A great blizzard about every fifty days, for as long as the city lasts.
    static let blizzardGap = 50
    static let houseRoom = 5
    static let clinicBeds = 6
    /// How far from its lodge a woodcutter or a hunter goes; a fisher on the ice.
    static let reach = 9, fishReach = 6
    static let outLimit = 5
    static let blizzardDrop = 30.0, blizzardLength = 7
    static let heatReach: [Double] = [0, 6.5, 9, 11.5, 14, 16.5]
    static let heatPower: [Double] = [0, 24, 30, 36, 43, 50]
    static let burnBase: [Double] = [0, 6, 10, 15, 21, 28]
    static let topLevel = 5
    static let upgradeWork = 40.0
    /// Coal, wood, food, stone, iron for one tile of wall.
    static let wallCost: [Double] = [0, 1, 0, 3, 0]
    static let soldiersBase = 10, soldiersPerBarracks = 20, batchSize = 5

    static func inside(_ t: IceTile) -> Bool { t.x >= 0 && t.y >= 0 && t.x < width && t.y < height }
    static func index(_ t: IceTile) -> Int { t.y * width + t.x }
    /// Coal, wood, food, stone, iron to raise the furnace to a level.
    static func upgradeCost(to level: Int) -> [Double] {
        switch level {
        case 2: return [0, 80, 0, 20, 15]
        case 3: return [0, 140, 0, 40, 35]
        case 4: return [0, 220, 0, 60, 60]
        default: return [0, 320, 0, 90, 100]
        }
    }

    /// The seed the land was made from: the same seed, the same map.
    let seed: UInt64
    var ground: [IceGround]
    /// Forest tiles: 1 is a grown pine; less is a stump growing back.
    var wood: [Double]
    /// Forest tiles: game left to hunt.
    var game: [Double]
    /// Ice tiles: fish under the ice.
    var fish: [Double]
    var road: [Bool]
    /// Wall tiles: the time the wall went up, or −1.
    var wall: [Double]
    var occupant: [Int?]
    var buildings: [IceBuilding] = []
    var people: [IcePerson] = []
    var time = 0.0
    var nextID = 1
    var rng: UInt64
    var moments: [IceMoment] = []

    // The weather
    var salt = 0

    // The city
    var morale = 60.0
    var soldiers = 12, wounded = 0
    /// People of a conquered county, coming as warm houses free up.
    var waiting = 0
    var outDays = 0
    /// Seconds the furnace burned today, and the share of yesterday it burned.
    var burned = 0.0, lit = 1.0
    var overdrive = 0, huntBad = 0, minersRest = 0
    var officers: [IceHired] = [IceHired(officer: 0)]
    var offered: [Int] = [], pool: [Int] = []
    var owner: [Int] = [], garrison: [Double] = []
    var expeditions: [IceExpedition] = []
    var battles: [IceBattle] = []
    var rivals: [IceRivalLord] = []
    var incident: IceIncident? = nil
    var nextIncident = 5
    var raids: [IceRaid] = []
    var ended: String? = nil

    // Counting
    var deaths: [String: Int] = [:]
    var arrivals = 0, departures = 0, sickened = 0, cured = 0, peak = 0
    var raidsHeld = 0, raidsLost = 0
    /// What was made and used today, and yesterday, by good.
    var made = [Double](repeating: 0, count: 5), used = [Double](repeating: 0, count: 5)
    var madeYesterday = [Double](repeating: 0, count: 5), usedYesterday = [Double](repeating: 0, count: 5)
    /// The city at each dawn: people, sick, coal, food, the temperature — for the report and the harness.
    var history: [(people: Int, sick: Int, coal: Double, food: Double, temperature: Double)] = []
    private var lastDay = 1
    private var staffClock = 0.0
    /// The burn rate, measured once a second: what the furnace eats between.
    private var burnNow = 0.0
    /// Walls changed: the lee behind them is measured again.
    private(set) var wallsVersion = 0
    /// Tiles out of the north wind, behind a wall.
    private(set) var lee: [Bool] = []
    /// Roads changed: the picture of the land is painted again.
    private(set) var landVersion = 0

    // MARK: The calendar and the weather

    /// The day, with its fraction: 1.0 at the start.
    var day: Double { time / Self.daySeconds + 1 }
    var today: Int { Int(day) }
    var over: Bool { ended != nil }

    // The ice age has no end: the game lasts until the city fails. A great blizzard comes about every
    // fifty days, each a little colder and longer than the last; cold snaps come between them.

    /// The k-th great blizzard (from 0): its days and how far it drops the cold.
    func blizzardNumber(_ k: Int) -> (start: Int, end: Int, drop: Double) {
        let start = 60 + k * Self.blizzardGap + Self.mix(k, salt) % 7
        let length = min(10, Self.blizzardLength + k)
        return (start, start + length - 1, min(45, Self.blizzardDrop + 5 * Double(k)))
    }
    /// Which blizzard is on day d or comes next.
    func blizzardIndex(after d: Int) -> Int {
        var k = max(0, (d - 60) / Self.blizzardGap - 1)
        while blizzardNumber(k).end < d { k += 1 }
        return k
    }
    /// The great blizzard on day d, if there is one.
    func blizzardOn(_ d: Int) -> (start: Int, end: Int, drop: Double)? {
        let b = blizzardNumber(blizzardIndex(after: d))
        return d >= b.start ? b : nil
    }
    /// The blizzard now, or the next to come.
    var blizzard: (start: Int, end: Int) { let b = blizzardNumber(blizzardIndex(after: today)); return (b.start, b.end) }
    /// How many great blizzards the city has come through.
    var blizzardsSurvived: Int { blizzardIndex(after: today) }
    /// The j-th cold snap, about one a fortnight — none on a blizzard or in the calm week after one.
    func snap(_ j: Int) -> (start: Int, end: Int, drop: Double)? {
        let start = 12 + j * 15 + Self.mix(j, salt &+ 7) % 5
        let end = start + 2 + Self.mix(j, salt &+ 11) % 2
        for d in (start - 3)...(end + 1) where blizzardOn(d) != nil { return nil }
        let k = blizzardIndex(after: start)
        if k > 0, start - blizzardNumber(k - 1).end < 8 { return nil }
        return (start, end, 9 + Double(Self.mix(j, salt &+ 13) % 5) + min(8, Double(j) / 3))
    }
    /// The cold snaps around now.
    var snaps: [(start: Int, end: Int, drop: Double)] {
        let j = max(0, (today - 12) / 15)
        return (max(0, j - 1)...(j + 4)).compactMap { snap($0) }
    }

    /// The temperature outside on a whole day: colder by the day for a hundred days and slowly colder after,
    /// with the cold snaps and the great blizzards on top.
    func temperature(on d: Int) -> Double {
        let steep: Double = 0.26 * Double(min(d, Self.steepDays))
        let slow: Double = 0.04 * Double(max(0, d - Self.steepDays))
        let wobble: Double = Double(Self.mix(d, salt) % 5)
        var t: Double = -10 - steep - slow + wobble
        let j = max(0, (d - 12) / 15)
        for i in max(0, j - 1)...(j + 1) { if let s = snap(i), d >= s.start, d <= s.end { t -= s.drop } }
        if let b = blizzardOn(d) { t -= b.drop }
        let k = blizzardIndex(after: d)
        if k > 0 { let before = blizzardNumber(k - 1); if d > before.end, d <= before.end + 6 { t += 3 } }
        return t
    }
    /// The temperature now, sliding from one day's to the next through the day.
    var temperature: Double {
        let d = today, f = day - Double(d)
        let a = temperature(on: d), b = temperature(on: d + 1)
        // Cold spells come in over the last quarter of the day before.
        return f < 0.75 ? a : a + (b - a) * (f - 0.75) / 0.25
    }
    func inBlizzard(_ d: Int) -> Bool { blizzardOn(d) != nil }
    var storm: Bool { inBlizzard(today) }
    /// The next cold spell that has not ended: a snap or the blizzard.
    func nextCold(after d: Int) -> (start: Int, end: Int, blizzard: Bool)? {
        let j = max(0, (d - 12) / 15)
        var spells = (max(0, j - 1)...(j + 2)).compactMap { snap($0) }.map { (start: $0.start, end: $0.end, blizzard: false) }
        let b = blizzardNumber(blizzardIndex(after: d))
        spells.append((b.start, b.end, true))
        return spells.filter { $0.end >= d }.min { $0.start < $1.start }
    }
    static func mix(_ a: Int, _ b: Int) -> Int {
        var h = UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15 ^ UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F
        h ^= h >> 29; h &*= 0xBF58476D1CE4E5B9; h ^= h >> 32
        return Int(h % 1_000_003)
    }
    static func sickRate(_ t: Double) -> Double { min(0.3, max(0, (-t - 8) * 0.012)) }
    static func freezeRate(_ t: Double) -> Double { min(0.12, max(0, (-t - 20) * 0.008)) }

    // MARK: Making the land

    init(seed: UInt64) {
        self.seed = seed
        let n = Self.width * Self.height
        ground = Array(repeating: .snow, count: n)
        wood = Array(repeating: 0, count: n); game = Array(repeating: 0, count: n); fish = Array(repeating: 0, count: n)
        road = Array(repeating: false, count: n); wall = Array(repeating: -1, count: n); lee = Array(repeating: false, count: n)
        occupant = Array(repeating: nil, count: n)
        rng = seed &* 0x9E3779B97F4A7C15 | 1
        for _ in 0..<4 { _ = roll(2) }
        salt = roll(1000)
        for spread in [5, 6, 6, 6] { _ = roll(spread); _ = roll(2); _ = roll(5) }
        _ = roll(7)

        func noise(_ cell: Double) -> [Double] {
            let gw = Int(Double(Self.width) / cell) + 2, gh = Int(Double(Self.height) / cell) + 2
            var lattice = [Double](repeating: 0, count: gw * gh)
            for i in lattice.indices { lattice[i] = Double(roll(1000)) / 1000 }
            var out = [Double](repeating: 0, count: n)
            for y in 0..<Self.height {
                for x in 0..<Self.width {
                    let fx = Double(x) / cell, fy = Double(y) / cell
                    let x0 = Int(fx), y0 = Int(fy), tx = fx - Double(x0), ty = fy - Double(y0)
                    let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
                    let a = lattice[y0 * gw + x0], b = lattice[y0 * gw + x0 + 1], c = lattice[(y0 + 1) * gw + x0], d = lattice[(y0 + 1) * gw + x0 + 1]
                    out[y * Self.width + x] = (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
                }
            }
            return out
        }
        let woods = noise(6.5), grain = noise(2.5)
        let hub = IceTile(x: 29 + roll(5) - 2, y: 17 + roll(3) - 1)
        let hx = Double(hub.x) + 1.5, hy = Double(hub.y) + 1.5

        // A frozen river from the top of the map down into a lake, east or west of the city.
        let east = roll(2) == 0
        let phase = Double(roll(628)) / 100, bend = 2 + Double(roll(15)) / 10
        let riverX = east ? hx + 15 + Double(roll(4)) : hx - 15 - Double(roll(4))
        let lake = (x: riverX + (east ? 2 : -2), y: 27.0 + Double(roll(5)))
        for y in 0..<Self.height where Double(y) < lake.y {
            let cx = riverX + bend * sin(Double(y) * 0.23 + phase) + 0.9 * sin(Double(y) * 0.57 + phase * 2)
            let half = 0.9 + 0.35 * sin(Double(y) * 0.41 + phase)
            for x in Int((cx - half).rounded())...Int((cx + half).rounded()) where x >= 0 && x < Self.width { ground[y * Self.width + x] = .ice }
        }
        for y in 0..<Self.height { for x in 0..<Self.width {
            let d = hypot((Double(x) - lake.x) / 5.2, (Double(y) - lake.y) / 3.6) + (grain[y * Self.width + x] - 0.5) * 0.45
            if d < 1 { ground[y * Self.width + x] = .ice }
        } }
        // Pine woods where the noise is high, thicker toward the edges of the map, none near the furnace.
        for y in 0..<Self.height {
            for x in 0..<Self.width where ground[y * Self.width + x] == .snow {
                let i = y * Self.width + x
                let edge = max(0, 1 - Double(min(x, Self.width - 1 - x, y, Self.height - 1 - y)) / 9)
                let fromHub = hypot(Double(x) + 0.5 - hx, Double(y) + 0.5 - hy)
                if woods[i] * 0.8 + grain[i] * 0.2 + edge * 0.3 - (fromHub < 12 ? 0.35 : 0) > 0.58 { ground[i] = .forest }
            }
        }
        // Rock, coal seams and iron ore: outcrops at their distances from the furnace.
        func outcrop(_ kind: IceGround, from lo: Double, to hi: Double, size: Int) {
            for _ in 0..<80 {
                let a = Double(roll(628)) / 100, r = lo + Double(roll(Int((hi - lo) * 10))) / 10
                let c = IceTile(x: Int(hx + cos(a) * r), y: Int(hy + sin(a) * r * 0.75))
                guard c.x > 2, c.y > 2, c.x < Self.width - 3, c.y < Self.height - 3 else { continue }
                // Keep clear of ice and of the other deposits.
                var clash = false
                for y in (c.y - 4)...(c.y + 4) { for x in (c.x - 4)...(c.x + 4) where Self.inside(IceTile(x: x, y: y)) {
                    let g = ground[y * Self.width + x]
                    if g == .ice || g == .rock || g == .coal || g == .ore { clash = true }
                } }
                if clash { continue }
                for y in (c.y - 4)...(c.y + 4) { for x in (c.x - 4)...(c.x + 4) where Self.inside(IceTile(x: x, y: y)) && ground[y * Self.width + x] == .forest && hypot(Double(x - c.x), Double(y - c.y)) < 4.5 {
                    ground[y * Self.width + x] = .snow
                } }
                var placed = 0, at = c
                while placed < size {
                    if Self.inside(at), ground[Self.index(at)] == .snow || ground[Self.index(at)] == .forest { ground[Self.index(at)] = kind; placed += 1 }
                    at = IceTile(x: at.x + roll(3) - 1, y: at.y + roll(3) - 1)
                    if !Self.inside(at) || hypot(Double(at.x - c.x), Double(at.y - c.y)) > 2.6 { at = c }
                }
                return
            }
        }
        outcrop(.coal, from: 8, to: 12, size: 7)
        outcrop(.rock, from: 9, to: 14, size: 7)
        outcrop(.ore, from: 12, to: 18, size: 6)
        outcrop(.coal, from: 15, to: 23, size: 8)
        outcrop(.rock, from: 16, to: 24, size: 7)
        outcrop(.ore, from: 18, to: 26, size: 7)
        for i in 0..<n {
            switch ground[i] {
            case .forest: wood[i] = 1; game[i] = 3
            case .ice: fish[i] = 6
            default: break
            }
        }
        // The square round the furnace: cleared.
        for y in (hub.y - 7)...(hub.y + 9) { for x in (hub.x - 8)...(hub.x + 10) where Self.inside(IceTile(x: x, y: y)) {
            let i = y * Self.width + x
            if ground[i] == .forest { ground[i] = .snow; wood[i] = 0; game[i] = 0 }
        } }
        // The furnace, a storage and four houses round it, and roads between.
        let furnace = place(.furnace, at: hub, done: true)!
        buildings[buildingIndex(furnace)!].stock[0] = 20
        for k in 1...5 {
            lay(road: IceTile(x: hub.x + 1, y: hub.y - 1 - k)); lay(road: IceTile(x: hub.x + 1, y: hub.y + 3 + k))
            lay(road: IceTile(x: hub.x - 1 - k, y: hub.y + 1)); lay(road: IceTile(x: hub.x + 3 + k, y: hub.y + 1))
        }
        if let s = place(.storage, at: IceTile(x: hub.x + 5, y: hub.y + 2), done: true), let si = buildingIndex(s) {
            buildings[si].stock = [110, 170, 240, 50, 40]
        }
        for (dx, dy) in [(-4, -4), (4, -4), (-4, 4), (1, 5)] {
            _ = place(.house, at: IceTile(x: hub.x + dx, y: hub.y + dy), done: true)
        }
        var k = 0
        for kid in [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true] {
            let a = Double(k) * 0.37
            var p = IcePerson(id: nextID, x: hx + cos(a) * 3.4, y: hy + 1 + sin(a) * 2.6, kid: kid, coat: roll(6))
            if kid { p.growing = 20 + Double(roll(20)) }
            people.append(p); nextID += 1; k += 1
        }
        rehouse()
        // The counties and the rival lords.
        owner = iceRegions.enumerated().map { i, c in i == 0 ? 0 : c.foe == 3 ? 1 : c.foe == 4 ? 2 : 3 }
        garrison = iceRegions.map { $0.high > 0 ? Double($0.low + roll($0.high - $0.low + 1)) : 0 }
        var rest = Array(1..<iceOfficers.count)
        for i in stride(from: rest.count - 1, to: 0, by: -1) { rest.swapAt(i, roll(i + 1)) }
        offered = Array(rest.prefix(2)); pool = Array(rest.dropFirst(2))
        rivals = [IceRivalLord(reserve: 30, period: 7, offset: roll(7), nextRaid: 30 + roll(8)),
                  IceRivalLord(reserve: 30, period: 8, offset: roll(8), nextRaid: 34 + roll(8))]
        nextIncident = 4 + roll(3)
        peak = people.count
    }

    mutating func roll(_ n: Int) -> Int {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Int(rng % UInt64(max(n, 1)))
    }
    mutating func chance(_ p: Double) -> Bool { Double(roll(100_000)) / 100_000 < p }
    /// 0..<n in an order shuffled by the city's own dice.
    mutating func shuffled(_ n: Int) -> [Int] {
        var out = Array(0..<n)
        for i in stride(from: n - 1, to: 0, by: -1) { out.swapAt(i, roll(i + 1)) }
        return out
    }
    /// A count with a fractional part: the whole, and one more by chance.
    mutating func some(_ x: Double) -> Int { let whole = floor(x); return Int(whole) + (chance(x - whole) ? 1 : 0) }

    // MARK: Looking things up

    func building(_ id: Int) -> IceBuilding? { buildings.first { $0.id == id } }
    func buildingIndex(_ id: Int) -> Int? { buildings.firstIndex { $0.id == id } }
    var furnace: IceBuilding? { buildings.first { $0.kind == .furnace } }
    var furnaceIndex: Int? { buildings.firstIndex { $0.kind == .furnace } }
    var level: Int { furnace?.level ?? 0 }
    var hub: (x: Double, y: Double) { furnace.map { centre($0) } ?? (Double(Self.width) / 2, Double(Self.height) / 2) }
    func tile(of p: IcePerson) -> IceTile { IceTile(x: Int(p.x), y: Int(p.y)) }
    func centre(_ b: IceBuilding) -> (x: Double, y: Double) { (Double(b.x) + Double(b.kind.size) / 2, Double(b.y) + Double(b.kind.size) / 2) }
    func distance(_ b: IceBuilding, _ x: Double, _ y: Double) -> Double { let c = centre(b); return hypot(c.x - x, c.y - y) }
    func residents(_ id: Int) -> Int { people.reduce(0) { $0 + ($1.home == id ? 1 : 0) } }
    func workers(_ id: Int) -> Int { people.reduce(0) { $0 + ($1.job == id ? 1 : 0) } }
    func count(_ k: IceBuildKind, done: Bool = true) -> Int { buildings.reduce(0) { $0 + ($1.kind == k && (!done || $1.done) ? 1 : 0) } }
    /// What the storages hold.
    func stored(_ g: IceGood) -> Double { buildings.reduce(0) { $0 + ($1.done && $1.kind == .storage ? $1.stock[g.rawValue] : 0) } }
    /// Food and coal also count what is in the houses and the furnace.
    func total(_ g: IceGood) -> Double {
        stored(g) + (g == .food ? buildings.reduce(0) { $0 + ($1.kind == .house ? $1.stock[2] : 0) } : 0)
            + (g == .coal ? furnace?.stock[0] ?? 0 : 0)
    }
    static let capacity = 700.0
    func room(_ b: IceBuilding) -> Double { Self.capacity - b.stock.reduce(0, +) }
    var houses: Int { count(.house) }
    var homeless: Int { people.filter { $0.home == nil }.count }
    var sick: Int { people.filter(\.sick).count }

    // MARK: Heat

    var heatRadius: Double { Self.heatReach[min(level, Self.topLevel)] }
    /// Is this point inside the furnace's heat?
    func warmed(_ x: Double, _ y: Double) -> Bool { let h = hub; return hypot(x - h.x, y - h.y) <= heatRadius }
    func warmed(_ b: IceBuilding) -> Bool { let c = centre(b); return warmed(c.x, c.y) }
    /// Houses done and in the heat, and the room in them.
    var warmHouses: [IceBuilding] { buildings.filter { $0.kind == .house && $0.done && warmed($0) } }
    var warmRoom: Int { warmHouses.count * Self.houseRoom }
    var room: Int { houses * Self.houseRoom }
    func governor(_ id: Int) -> Int? { officers.first { $0.governs == id && !$0.away }?.officer }
    func serving(_ t: IceTalent) -> Bool { officers.contains { iceOfficers[$0.officer].talent == t } }
    /// Coal the furnace burns a day: more for a bigger fire and for every lived-in house it keeps warm.
    var burnRate: Double {
        guard let f = furnace else { return 0 }
        let kept = warmHouses.filter { h in people.contains { $0.home == h.id } }.count
        var rate = Self.burnBase[min(f.level, Self.topLevel)] + 0.25 * Double(kept)
        if overdrive > 0 { rate *= 2 }
        if let g = governor(f.id) { rate *= iceOfficers[g].talent == .fire ? 0.75 : 0.9 }
        return rate
    }
    /// Is the furnace burning right now?
    var burning: Bool { (furnace?.stock[0] ?? 0) > 0.001 || stored(.coal) > 0.001 }

    /// Walls cut the north wind: the lee of a wall reaches twenty rows south of it, widening as it goes.
    static let leeRows = 20
    func sheltered(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < Self.width && y < Self.height && lee[y * Self.width + x] }
    func sheltered(_ b: IceBuilding) -> Bool { (0..<b.kind.size).contains { sheltered(b.x + $0, b.y) } }
    /// Measure the lee again, from every tile of wall.
    mutating func measureLee() {
        var out = [Bool](repeating: false, count: Self.width * Self.height)
        for i in wall.indices where wall[i] >= 0 {
            let wx = i % Self.width, wy = i / Self.width
            for k in 1...Self.leeRows {
                let y = wy + k
                guard y < Self.height else { break }
                let spread = 1 + k / 3
                for x in max(0, wx - spread)...min(Self.width - 1, wx + spread) { out[y * Self.width + x] = true }
            }
        }
        lee = out
    }
    var wallTiles: Int { wall.reduce(0) { $0 + ($1 >= 0 ? 1 : 0) } }
    /// Walls as a strength against raiders: 0 to 3.
    var wallStrength: Double { min(3, Double(wallTiles) / 24) }

    /// How warm it is in a house (or out in the snow for nil), on a day, with the furnace burning `lit` of the time.
    func warmth(of house: IceBuilding?, on d: Int, lit: Double) -> Double {
        let t = temperature(on: d), storm = inBlizzard(d)
        guard let h = house else { return t - 4 - (storm ? 4 : 0) }
        var w = t
        if warmed(h) { w += (Self.heatPower[min(level, Self.topLevel)] + (overdrive > 0 ? 10 : 0)) * lit } else { w += 8 }
        if sheltered(h) { w += storm ? 5 : 2 } else if storm { w -= 5 }
        return w
    }

    // MARK: Work

    var moraleSpeed: Double { 0.7 + 0.5 * morale / 100 }
    /// A governor's bonus to a building.
    func bonus(_ id: Int) -> Double {
        guard let g = governor(id) else { return 1 }
        let o = iceOfficers[g]
        var b = 0.1 + Double(o.wit) / 500
        if o.talent == .planner { b += 0.2 }
        if o.talent == .ruler || o.talent == .balance { b += 0.1 }
        return 1 + b
    }
    /// How fast work goes at a building, all told.
    func pace(_ b: IceBuilding) -> Double {
        var r = moraleSpeed * bonus(b.id)
        if b.kind.outdoor, storm { r *= 0.55 }
        if b.kind == .hunter { if temperature(on: today) < -28 { r *= 0.7 }; if huntBad > 0 { r *= 0.5 } }
        if b.kind == .greenhouse { r *= min(1, 0.25 + 0.75 * lit) * (warmed(b) ? 1 : 0.2) }
        return r
    }
    var eats: Double { Double(people.count) * 0.8 + Double(soldiers + wounded + expeditions.reduce(0) { $0 + $1.soldiers + $1.wounded }) * 0.5 }
    /// Sick cured a day by the clinics, as staffed.
    var heals: Double {
        var h = 0.0
        for b in buildings where b.kind == .clinic && b.done {
            let doctors = workers(b.id)
            guard doctors > 0 else { continue }
            var c = 1.5 + 2 * Double(doctors)
            if let g = governor(b.id) { c = iceOfficers[g].talent == .healer ? c * 1.5 + 8 : c * bonus(b.id) }
            h += c
        }
        if h > 0, serving(.healer), !buildings.contains(where: { $0.kind == .clinic && governor($0.id).map { iceOfficers[$0].talent == .healer } == true }) { h += 3 }
        return h
    }
    var beds: Int { count(.clinic) * Self.clinicBeds }
    var soldierRoom: Int { Self.soldiersBase + Self.soldiersPerBarracks * count(.barracks) }
    var inArms: Int { soldiers + wounded + expeditions.reduce(0) { $0 + $1.soldiers + $1.wounded } + buildings.reduce(0) { $0 + $1.batch } }
    var heroRoom: Int { 1 + 2 * count(.tavern) }
    var counties: Int { owner.dropFirst().filter { $0 == 0 }.count }

    // MARK: Placing things

    func fits(_ k: IceBuildKind, at o: IceTile) -> Bool {
        let n = k.size
        for dy in 0..<n { for dx in 0..<n {
            let t = IceTile(x: o.x + dx, y: o.y + dy)
            guard Self.inside(t) else { return false }
            let i = Self.index(t)
            guard occupant[i] == nil, wall[i] < 0 else { return false }
            if k == .fishery { guard ground[i] == .ice else { return false } } else { guard ground[i] == .snow else { return false } }
        } }
        switch k {
        case .coalMine: return near(.coal, o, n, 1) > 0
        case .ironMine: return near(.ore, o, n, 1) > 0
        case .quarry: return near(.rock, o, n, 1) > 0
        case .greenhouse: return level >= 2 && warmed(Double(o.x) + Double(n) / 2, Double(o.y) + Double(n) / 2)
        default: return true
        }
    }
    /// Why a building cannot go here, in Chinese, for a person's click.
    func whyNot(_ k: IceBuildKind, at o: IceTile) -> String {
        switch k {
        case .coalMine: if near(.coal, o, k.size, 1) == 0 { return "煤矿要挨着煤层（黑色的石头）" }
        case .ironMine: if near(.ore, o, k.size, 1) == 0 { return "铁矿要挨着铁矿石（带红斑的石头）" }
        case .quarry: if near(.rock, o, k.size, 1) == 0 { return "采石场要挨着岩石" }
        case .fishery: return "冰钓屋要整个放在冰面上"
        case .greenhouse:
            if level < 2 { return "温室要熔炉 2 级才暖得起来" }
            if !warmed(Double(o.x) + Double(k.size) / 2, Double(o.y) + Double(k.size) / 2) { return "温室要放在熔炉的热圈里" }
        default: break
        }
        return "这里放不下"
    }

    /// How many tiles of a kind lie within `r` of a footprint.
    func near(_ kind: IceGround, _ o: IceTile, _ n: Int, _ r: Int) -> Int {
        var count = 0
        for y in (o.y - r)..<(o.y + n + r) { for x in (o.x - r)..<(o.x + n + r) where Self.inside(IceTile(x: x, y: y)) && ground[y * Self.width + x] == kind { count += 1 } }
        return count
    }

    @discardableResult
    mutating func place(_ k: IceBuildKind, at o: IceTile, done: Bool = false) -> Int? {
        guard fits(k, at: o) || k == .furnace else { return nil }
        let id = nextID; nextID += 1
        var b = IceBuilding(id: id, kind: k, x: o.x, y: o.y, done: done)
        if done { b.progress = 1; b.delivered = k.cost }
        let n = k.size
        if k == .coalMine { b.reserve = Double(near(.coal, o, n, 2)) * 280 }
        if k == .ironMine { b.reserve = Double(near(.ore, o, n, 2)) * 110 }
        if k == .quarry { b.reserve = Double(near(.rock, o, n, 2)) * 120 }
        buildings.append(b)
        for dy in 0..<n { for dx in 0..<n {
            let i = Self.index(IceTile(x: o.x + dx, y: o.y + dy))
            occupant[i] = id
            if road[i] { road[i] = false; landVersion += 1 }
        } }
        return id
    }

    /// Take a building down: its workers and family go free, half of what went into it comes back.
    mutating func remove(_ id: Int) {
        guard let bi = buildingIndex(id), buildings[bi].kind != .furnace else { return }
        let b = buildings[bi], n = b.kind.size
        for dy in 0..<n { for dx in 0..<n { occupant[Self.index(IceTile(x: b.x + dx, y: b.y + dy))] = nil } }
        for i in people.indices {
            if people[i].job == id { people[i].job = nil }
            if people[i].home == id { people[i].home = nil; people[i].inside = false }
            switch people[i].task {
            case .work(id), .store(id), .bring(id), .build(id), .heal(id): people[i].task = .idle; people[i].inside = false
            case .fetch(let s, _, let f) where s == id || f == id: people[i].task = .idle
            default: break
            }
        }
        for g in officers.indices where officers[g].governs == id { officers[g].governs = nil }
        buildings.remove(at: bi)
        var back = b.delivered.map { $0 / 2 }
        if b.kind == .storage { back = zip(back, b.stock).map { $0 + $1 * 0.8 } }
        if let s = nearestStorage(Double(b.x), Double(b.y), room: 0) { deposit(back, into: s) }
        rehouse()
    }

    /// A road on open snow.
    @discardableResult
    mutating func lay(road t: IceTile) -> Bool {
        guard Self.inside(t), ground[Self.index(t)] == .snow, occupant[Self.index(t)] == nil, !road[Self.index(t)] else { return false }
        road[Self.index(t)] = true
        landVersion += 1
        return true
    }
    mutating func unlay(road t: IceTile) { if Self.inside(t), road[Self.index(t)] { road[Self.index(t)] = false; landVersion += 1 } }

    /// A tile of wall on open snow or across a road (a gate), paid for from the storages at once.
    func canWall(_ t: IceTile) -> Bool {
        guard Self.inside(t) else { return false }
        let i = Self.index(t)
        return ground[i] == .snow && occupant[i] == nil && wall[i] < 0
    }
    var wallAffordable: Int {
        let byStone = Self.wallCost[3] > 0 ? stored(.stone) / Self.wallCost[3] : 999
        let byWood = Self.wallCost[1] > 0 ? stored(.wood) / Self.wallCost[1] : 999
        return Int(min(byStone, byWood))
    }
    /// Raise a line of wall, tile by tile while the stone and wood last; returns how many went up.
    @discardableResult
    mutating func raise(walls tiles: [IceTile]) -> Int {
        var n = 0
        for (k, t) in tiles.enumerated() where canWall(t) && wallAffordable >= 1 {
            for g in IceGood.allCases where Self.wallCost[g.rawValue] > 0 { take(g, Self.wallCost[g.rawValue]); used[g.rawValue] += Self.wallCost[g.rawValue] }
            // Each tile rises a moment after the one before it, down the line.
            wall[Self.index(t)] = time + Double(k) * 0.12
            n += 1
        }
        if n > 0 { wallsVersion += 1; measureLee() }
        return n
    }
    mutating func razeWall(_ t: IceTile) {
        guard Self.inside(t), wall[Self.index(t)] >= 0 else { return }
        wall[Self.index(t)] = -1
        wallsVersion += 1; measureLee()
        if let s = nearestStorage(Double(t.x), Double(t.y), room: 0) { var back = [Double](repeating: 0, count: 5); back[3] = Self.wallCost[3] / 2; deposit(back, into: s) }
    }

    /// Start raising the furnace a level: the materials are carried to it and builders put it up while it burns on.
    @discardableResult
    mutating func upgradeFurnace() -> Bool {
        guard let fi = furnaceIndex, !buildings[fi].upgrading, buildings[fi].level < Self.topLevel else { return false }
        buildings[fi].upgrading = true
        buildings[fi].delivered = [0, 0, 0, 0, 0]
        buildings[fi].progress = 0
        return true
    }
    /// What the site still needs: for a building going up its cost, for the furnace its upgrade.
    func cost(of b: IceBuilding) -> [Double] { b.kind == .furnace ? Self.upgradeCost(to: b.level + 1) : b.kind.cost }

    // MARK: Storage

    func nearestStorage(_ x: Double, _ y: Double, room: Double) -> Int? {
        buildings.filter { $0.done && $0.kind == .storage && self.room($0) >= room }
            .min { distance($0, x, y) < distance($1, x, y) }?.id
    }
    func storage(with g: IceGood, _ x: Double, _ y: Double, atLeast: Double = 1) -> Int? {
        buildings.filter { $0.done && $0.kind == .storage && $0.stock[g.rawValue] >= atLeast }
            .min { distance($0, x, y) < distance($1, x, y) }?.id
    }
    mutating func deposit(_ goods: [Double], into id: Int) {
        guard let s = buildingIndex(id) else { return }
        for g in 0..<5 { buildings[s].stock[g] += goods[g] }
    }
    /// Take from the storages, the fullest first; returns how much there was.
    @discardableResult
    mutating func take(_ g: IceGood, _ amount: Double) -> Double {
        var left = amount
        for s in buildings.indices.filter({ buildings[$0].done && buildings[$0].kind == .storage }).sorted(by: { buildings[$0].stock[g.rawValue] > buildings[$1].stock[g.rawValue] }) {
            let t = min(left, buildings[s].stock[g.rawValue])
            buildings[s].stock[g.rawValue] -= t; left -= t
            if left <= 0 { break }
        }
        return amount - left
    }
    /// Goods coming in from outside (tribute, trade, a cellar): into the storage nearest the furnace.
    mutating func receive(_ g: IceGood, _ amount: Double) {
        let h = hub
        if amount < 0 { take(g, -amount); used[g.rawValue] -= amount; return }
        guard let s = nearestStorage(h.x, h.y, room: 0) else { return }
        var goods = [Double](repeating: 0, count: 5); goods[g.rawValue] = amount
        deposit(goods, into: s)
        made[g.rawValue] += amount
    }
    private mutating func note(made g: IceGood, _ n: Double, by i: Int) {
        made[g.rawValue] += n
        if let job = people[i].job, let b = buildingIndex(job) { buildings[b].output += n }
    }

    // MARK: Walking

    func walkable(_ t: IceTile) -> Bool {
        guard Self.inside(t) else { return false }
        let i = Self.index(t)
        if occupant[i] != nil { return false }
        return ground[i] == .snow || ground[i] == .forest || ground[i] == .ice
    }
    func stepCost(_ i: Int) -> Double {
        if wall[i] >= 0 { return road[i] ? 0.6 : 5 }
        return road[i] ? 0.55 : ground[i] == .forest ? 1.7 : ground[i] == .ice ? 1.15 : 1
    }

    /// A* over the tiles, eight ways, without cutting corners past buildings and rock.
    func path(from start: IceTile, to goals: Set<IceTile>) -> [IceTile]? {
        guard !goals.isEmpty else { return nil }
        if goals.contains(start) { return [] }
        let w = Self.width, n = Self.width * Self.height
        var g = [Double](repeating: .infinity, count: n), came = [Int](repeating: -1, count: n), closed = [Bool](repeating: false, count: n)
        let goalIndex = Set(goals.map(Self.index))
        let gx = goals.map(\.x), gy = goals.map(\.y)
        func guess(_ i: Int) -> Double {
            let x = i % w, y = i / w
            var best = Int.max
            for k in gx.indices { best = min(best, max(abs(gx[k] - x), abs(gy[k] - y))) }
            return Double(best) * 0.55
        }
        var heap = IceHeap()
        let s = Self.index(start)
        g[s] = 0; heap.push(guess(s), s)
        var expanded = 0
        while let current = heap.pop(), expanded < 9000 {
            if closed[current] { continue }
            closed[current] = true; expanded += 1
            if goalIndex.contains(current) {
                var out: [IceTile] = [], at = current
                while at != s { out.append(IceTile(x: at % w, y: at / w)); at = came[at] }
                return out.reversed()
            }
            let cx = current % w, cy = current / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let t = IceTile(x: cx + dx, y: cy + dy)
                guard Self.inside(t) else { continue }
                let ni = Self.index(t)
                guard !closed[ni], walkable(t) || goalIndex.contains(ni) else { continue }
                if dx != 0, dy != 0, !walkable(IceTile(x: cx + dx, y: cy)) || !walkable(IceTile(x: cx, y: cy + dy)) { continue }
                let step = g[current] + (dx != 0 && dy != 0 ? 1.414 : 1) * (stepCost(ni) + stepCost(current)) / 2
                if step < g[ni] { g[ni] = step; came[ni] = current; heap.push(step + guess(ni), ni) }
            }
        }
        return nil
    }

    /// The tiles around a building one can stand on to use it.
    func around(_ b: IceBuilding) -> Set<IceTile> {
        let n = b.kind.size
        var out = Set<IceTile>()
        for dy in -1...n { for dx in -1...n where dx == -1 || dy == -1 || dx == n || dy == n {
            let t = IceTile(x: b.x + dx, y: b.y + dy)
            if walkable(t) { out.insert(t) }
        } }
        return out
    }
    func neighbours(_ t: IceTile) -> Set<IceTile> {
        var out = Set<IceTile>()
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let n = IceTile(x: t.x + dx, y: t.y + dy)
            if walkable(n) { out.insert(n) }
        } }
        return out
    }

    enum Arrival { case arrived, walking, stuck }

    private mutating func go(_ i: Int, _ goals: Set<IceTile>, _ dt: Double) -> Arrival {
        let here = tile(of: people[i])
        if goals.contains(here), people[i].path.isEmpty { return .arrived }
        if people[i].path.isEmpty || people[i].repath <= 0 {
            people[i].repath = 6
            guard let found = path(from: here, to: goals) else { people[i].path = []; return .stuck }
            people[i].path = found
            if found.isEmpty { return .arrived }
        }
        guard let next = people[i].path.first else { return .arrived }
        let tx = Double(next.x) + 0.5, ty = Double(next.y) + 0.5
        let dx = tx - people[i].x, dy = ty - people[i].y, d = hypot(dx, dy)
        let under = Self.inside(here) ? Self.index(here) : 0
        var speed = road[under] ? 2.6 : ground[under] == .forest ? 1.1 : ground[under] == .ice ? 1.6 : 1.6
        if storm { speed *= 0.7 }
        if people[i].kid { speed *= 0.8 }
        if people[i].amount > 0 { speed *= 0.9 }
        let stride = speed * dt
        if abs(dx) > 0.05 { people[i].facing = dx > 0 ? 1 : -1 }
        if d <= stride { people[i].x = tx; people[i].y = ty; people[i].path.removeFirst() }
        else { people[i].x += dx / d * stride; people[i].y += dy / d * stride }
        return people[i].path.isEmpty && goals.contains(tile(of: people[i])) ? .arrived : .walking
    }

    // MARK: The clock

    mutating func step(_ dt: Double) {
        guard !over else { return }
        time += dt
        burn(dt)
        if today != lastDay { lastDay = today; dawn() }
        guard !over else { return }
        staffClock += dt
        if staffClock >= 1 { staffClock = 0; staff(); burnNow = burnRate }
        for i in people.indices { act(i, dt) }
        people.removeAll { if case .leave = $0.task, $0.path.isEmpty, $0.x < 0.6 || $0.y < 0.6 || $0.x > Double(Self.width) - 0.6 || $0.y > Double(Self.height) - 0.6 { return true }; return false }
        for b in buildings.indices where buildings[b].kind == .barracks && buildings[b].batch > 0 {
            buildings[b].training -= dt
            if buildings[b].training <= 0 { soldiers += buildings[b].batch; buildings[b].batch = 0 }
        }
        if moments.count > 80 { moments.removeAll { time - $0.time > 8 } }
    }

    /// The furnace eats coal as it burns: from its own hopper, then straight from the storages.
    private mutating func burn(_ dt: Double) {
        guard let fi = furnaceIndex else { return }
        let need = burnNow * dt / Self.daySeconds
        let hopper = min(need, buildings[fi].stock[0])
        buildings[fi].stock[0] -= hopper
        let rest = need - hopper > 0 ? take(.coal, need - hopper) : 0
        let got = hopper + rest
        used[0] += got
        if need > 0 { burned += dt * min(1, got / need) }
    }

    /// Workers to where the lord wants them: the nearest free hands, and back when fewer are wanted.
    private mutating func staff() {
        for bi in buildings.indices where buildings[bi].done && buildings[bi].kind.slots > 0 {
            let b = buildings[bi]
            var want = min(b.wanted, b.kind.slots)
            if b.kind == .coalMine, minersRest > 0 { want = 0 }
            var at = people.indices.filter { people[$0].job == b.id }
            while at.count > want {
                let i = at.removeLast()
                people[i].job = nil
                if case .work = people[i].task { people[i].task = .idle }
                if case .harvest = people[i].task { people[i].task = .idle }
            }
            guard at.count < want else { continue }
            let c = centre(b)
            let free = people.indices.filter { people[$0].worker && people[$0].job == nil && !Self.going(people[$0]) }
                .sorted { hypot(people[$0].x - c.x, people[$0].y - c.y) < hypot(people[$1].x - c.x, people[$1].y - c.y) }
            for i in free.prefix(want - at.count) {
                people[i].job = b.id
                switch people[i].task {
                case .idle, .wander, .pause, .goHome: people[i].task = .idle; people[i].inside = false
                default: break
                }
            }
        }
    }

    // MARK: A day goes by

    private mutating func dawn() {
        let d = today - 1                           // the day that just ended
        lit = min(1, burned / Self.daySeconds)
        burned = 0
        madeYesterday = made; usedYesterday = used
        made = [0, 0, 0, 0, 0]; used = [0, 0, 0, 0, 0]
        for b in buildings.indices { buildings[b].lastOutput = buildings[b].output; buildings[b].output = 0 }
        if lit < 0.5 { outDays += 1; moment(.news("熔炉断煤了！"), hub) } else { outDays = 0 }
        // The land: stumps grow back slowly, game and fish come back.
        for i in wood.indices where ground[i] == .forest {
            if wood[i] < 1 { wood[i] = min(1, wood[i] + 1.0 / 45) }
            game[i] = min(3, game[i] + 0.1)
        }
        for i in fish.indices where ground[i] == .ice { fish[i] = min(6, fish[i] + 0.3) }

        // Cold, sickness and death, person by person, by where each sleeps.
        let houseOf = Dictionary(uniqueKeysWithValues: buildings.filter { $0.kind == .house && $0.done }.map { ($0.id, $0) })
        var dead: [(Int, String)] = []
        var bedsFree = Double(heals)
        var inClinic = Set<Int>()
        for i in people.indices { if case .heal = people[i].task, people[i].inside { inClinic.insert(i) } }
        for i in people.indices {
            let home = people[i].home.flatMap { houseOf[$0] }
            var feel = warmth(of: home, on: d, lit: lit)
            if inClinic.contains(i) { feel = max(feel, temperature(on: d) + 30) }
            if people[i].sick {
                let cold = max(0, min(1, (-feel - 5) / 20))
                if chance(inClinic.contains(i) ? 0.02 : 0.03 + 0.14 * cold) { dead.append((i, "sick")); continue }
                if inClinic.contains(i), bedsFree >= 1 { bedsFree -= 1; people[i].sick = false; cured += 1; moment(.cured, people[i].x, people[i].y); continue }
                if chance(0.12 * (feel > -8 ? 1 : 0.3)) { people[i].sick = false; cured += 1; continue }
            } else if chance(Self.sickRate(feel)) {
                people[i].sick = true; sickened += 1
                people[i].job = nil
                switch people[i].task { case .work, .harvest, .build: people[i].task = .idle; default: break }
                moment(.sick, people[i].x, people[i].y)
            }
            if chance(Self.freezeRate(feel)) { dead.append((i, "cold")) }
        }
        // Eating: from the house, then the storages; soldiers from the storages.
        var hungry = false
        for i in people.indices {
            var fed = false
            if let h = people[i].home, let hi = buildingIndex(h), buildings[hi].stock[2] >= 0.8 { buildings[hi].stock[2] -= 0.8; fed = true }
            else if take(.food, 0.8) >= 0.79 { fed = true }
            if fed { used[2] += 0.8; people[i].hungry = 0 } else { people[i].hungry += 1; hungry = true }
        }
        let rations = Double(soldiers + wounded + buildings.reduce(0) { $0 + $1.batch }) * 0.5
        let got = take(.food, rations); used[2] += got
        if got < rations - 0.5 { hungry = true }
        for i in people.indices where people[i].hungry > 0 && !dead.contains(where: { $0.0 == i }) {
            if chance(0.04 + 0.05 * Double(people[i].hungry)) { dead.append((i, "hunger")) }
        }
        dead.sort { $0.0 > $1.0 }
        var deathCount = 0
        for (i, cause) in dead {
            let p = people[i]
            moment(.died(cause), p.x, p.y)
            deaths[cause, default: 0] += 1
            for b in buildings.indices where buildings[b].fetcher == p.id { buildings[b].fetcher = nil }
            people.remove(at: i)
            deathCount += 1
        }
        // The wounded mend, faster with a clinic.
        let mended = min(wounded, some(Double(wounded) * (0.2 + 0.05 * Double(count(.clinic)))))
        wounded -= mended; soldiers += mended
        // Children grow up.
        for i in people.indices where people[i].kid { people[i].growing -= 1; if people[i].growing <= 0 { people[i].kid = false } }
        // 民心.
        let n = max(1, people.count)
        let cold = people.filter { p in p.home.flatMap { houseOf[$0] }.map { !warmed($0) } ?? true }.count
        var mood = 0.3 - (morale - 60) * 0.05
        if hungry { mood -= 3 }
        if Double(cold) / Double(n) > 0.15 { mood -= 1.5 }
        if Double(sick) / Double(n) > 0.2 { mood -= 1.5 }
        mood -= min(6, Double(deathCount) * 0.7)
        if lit < 0.5 { mood -= 4 }
        mood += 0.3 * Double(min(3, count(.tavern)))
        if serving(.charm) { mood += 1 }
        if serving(.balance) { mood += 0.5 }
        if serving(.peerless) { mood -= 1 }
        morale = min(100, max(0, morale + mood))
        rehouse()
        // People come and go: first those of the conquered counties, then newcomers from the snow.
        let free = warmRoom - people.count
        let moving = min(waiting, max(0, free), 4)
        if moving > 0 { waiting -= moving; newcomers(moving) }
        else if waiting == 0, morale >= 45, free > 0, total(.food) >= eats * 2, roll(3) > 0 {
            newcomers(min(free, 1 + Int((morale - 45) / 18)))
        }
        if morale < 20 {
            let few = 1 + roll(2)
            let leaving = people.indices.filter { !people[$0].sick && !people[$0].kid && !Self.going(people[$0]) }.prefix(few)
            for i in leaving { walkOff(i) }
            if !leaving.isEmpty { departures += leaving.count; moment(.left(leaving.count), hub) }
        }
        // Armies on the road, the rival lords, raids.
        marchOn()
        for r in 0..<2 { rivalDay(r) }
        for i in 1..<owner.count where owner[i] == 1 || owner[i] == 2 { garrison[i] = min(iceRegions[i].capital ? 150 : 90, garrison[i] + 0.3) }
        // What the counties send.
        for (i, c) in iceRegions.enumerated() where i > 0 && owner[i] == 0 {
            receive(c.resource, c.amount)
            moment(.tribute(c.resource, Int(c.amount), c.name), hub)
        }
        // A matter at the gate.
        if incident == nil {
            if let cold = nextCold(after: today), cold.start == today + 2 {
                incident = IceIncident(kind: 2, amount: cold.end - cold.start + 1, day: today)
            } else if today >= nextIncident {
                let kinds = [0, 0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 3, 4]
                var kind = kinds[roll(kinds.count)]
                if kind == 6, count(.hunter) == 0 { kind = 8 }
                if kind == 1, count(.coalMine) == 0 { kind = 9 }
                incident = IceIncident(kind: kind, amount: 4 + roll(6), day: today)
                nextIncident = today + 4 + roll(3)
            }
        }
        if overdrive > 0 { overdrive -= 1 }
        if huntBad > 0 { huntBad -= 1 }
        if minersRest > 0 { minersRest -= 1 }
        // A new face at the tavern now and then.
        if today % 8 == 0, !pool.isEmpty, !offered.isEmpty { pool.append(offered.removeFirst()); offered.append(pool.removeFirst()) }
        peak = max(peak, people.count)
        history.append((people.count, sick, total(.coal), total(.food), temperature(on: today)))
        // No last day: the city lasts until it fails.
        if people.isEmpty { ended = "城里的人都没了" }
        else if outDays >= Self.outLimit { ended = "熔炉熄灭了 \(Self.outLimit) 天，城冻住了" }
    }

    /// Newcomers walking in from the road at the bottom edge.
    mutating func newcomers(_ n: Int) {
        guard n > 0 else { return }
        let h = hub
        let edge = IceTile(x: max(1, min(Self.width - 2, Int(h.x) + roll(9) - 4)), y: Self.height - 1)
        for k in 0..<n {
            var p = IcePerson(id: nextID, x: Double(edge.x) + 0.5 + Double(k % 3) * 0.4, y: Double(edge.y) + 0.5 - Double(k / 3) * 0.4, kid: roll(5) == 0, coat: roll(6))
            if p.kid { p.growing = 20 + Double(roll(15)) }
            p.task = .wander(IceTile(x: Int(h.x) + roll(5) - 2, y: Int(h.y) + 3 + roll(2)))
            people.append(p); nextID += 1
        }
        arrivals += n
        moment(.arrived(n), Double(edge.x), Double(edge.y) - 1)
        rehouse()
    }

    private mutating func walkOff(_ i: Int) {
        let p = people[i]
        let edges = [IceTile(x: 0, y: Int(p.y)), IceTile(x: Self.width - 1, y: Int(p.y)), IceTile(x: Int(p.x), y: Self.height - 1)]
        let to = edges.min { hypot(Double($0.x) - p.x, Double($0.y) - p.y) < hypot(Double($1.x) - p.x, Double($1.y) - p.y) }!
        people[i].home = nil; people[i].job = nil; people[i].inside = false
        people[i].amount = 0; people[i].carrying = nil
        people[i].task = .leave(to)
    }

    /// Everybody into a house: the warm ones first, and out of cold houses into warm ones with room.
    mutating func rehouse() {
        let all = buildings.filter { $0.kind == .house && $0.done }
        let warm = Set(all.filter { warmed($0) }.map(\.id))
        var count = Dictionary(uniqueKeysWithValues: all.map { ($0.id, 0) })
        for p in people { if let h = p.home, count[h] != nil { count[h]! += 1 } }
        // The homeless, and anybody in a cold house while a warm one has room.
        for i in people.indices {
            if case .leave = people[i].task { continue }
            let h = people[i].home
            if let h, count[h] != nil, warm.contains(h) { continue }
            let target = all.filter { warm.contains($0.id) && count[$0.id]! < Self.houseRoom }.min { count[$0.id]! > count[$1.id]! }?.id
                ?? (h == nil || count[h!] == nil ? all.filter { count[$0.id]! < Self.houseRoom }.min { count[$0.id]! > count[$1.id]! }?.id : nil)
            guard let target else { continue }
            if let h, count[h] != nil { count[h]! -= 1 }
            people[i].home = target; count[target]! += 1
        }
    }

    // MARK: A person's turn

    private mutating func act(_ i: Int, _ dt: Double) {
        people[i].swung += dt
        people[i].repath -= dt
        if people[i].inside, !{ if case .pause = people[i].task { return true }; if case .heal = people[i].task { return true }; return false }() { people[i].inside = false }
        switch people[i].task {
        case .idle: decide(i)
        case .pause(let left):
            if left - dt > 0 { people[i].task = .pause(left - dt) } else { people[i].task = .idle; people[i].inside = false }
        case .wander(let t):
            if go(i, [t], dt) != .walking { people[i].task = .pause(1 + Double(roll(30)) / 10) }
        case .leave(let t):
            if go(i, [t], dt) != .walking { people[i].x = Double(t.x) + 0.5; people[i].y = Double(t.y) + 0.5; people[i].path = [] }
        case .goHome:
            guard let h = people[i].home, let b = building(h) else { people[i].task = .idle; return }
            if go(i, around(b), dt) != .walking {
                let c = centre(b)
                people[i].x = c.x; people[i].y = Double(b.y) + Double(b.kind.size) + 0.3
                people[i].inside = true
                people[i].task = .pause((people[i].sick ? 14 : 6) + Double(roll(50)) / 10)
            }
        case .heal(let id):
            guard let b = building(id), b.done else { people[i].task = .idle; people[i].inside = false; return }
            if !people[i].sick { people[i].inside = false; people[i].task = .idle; return }
            if people[i].inside { return }
            if go(i, around(b), dt) != .walking {
                let c = centre(b)
                people[i].x = c.x; people[i].y = Double(b.y) + Double(b.kind.size) + 0.3
                people[i].inside = true
            }
        case .work(let id): labour(i, id, dt)
        case .harvest(let t): harvest(i, t, dt)
        case .store(let id):
            guard let b = building(id), b.done else { people[i].task = .idle; return }
            switch go(i, around(b), dt) {
            case .walking: return
            case .stuck: people[i].amount = 0; people[i].carrying = nil; people[i].task = .idle
            case .arrived:
                if let g = people[i].carrying { var goods = [Double](repeating: 0, count: 5); goods[g.rawValue] = people[i].amount; deposit(goods, into: id) }
                people[i].amount = 0; people[i].carrying = nil; people[i].task = .idle
            }
        case .fetch(let id, let g, let purpose):
            guard let b = building(id), let bi = buildingIndex(id) else { people[i].task = .idle; release(i); return }
            switch go(i, around(b), dt) {
            case .walking: return
            case .stuck: people[i].task = .idle; release(i)
            case .arrived:
                let want = wanted(g, for: purpose, by: people[i].id)
                let got = min(want, b.stock[g.rawValue])
                guard got > 0 else { people[i].task = .idle; release(i); return }
                buildings[bi].stock[g.rawValue] -= got
                people[i].carrying = g; people[i].amount = got
                people[i].task = .bring(purpose)
            }
        case .bring(let id):
            guard let b = building(id), let bi = buildingIndex(id), let g = people[i].carrying else { people[i].task = .idle; release(i); return }
            switch go(i, around(b), dt) {
            case .walking: return
            case .stuck: people[i].task = .idle; release(i)
            case .arrived:
                if b.site, !(b.kind == .furnace && g == .coal) { buildings[bi].delivered[g.rawValue] += people[i].amount }
                else { buildings[bi].stock[g.rawValue] += people[i].amount }
                if buildings[bi].fetcher == people[i].id { buildings[bi].fetcher = nil }
                people[i].amount = 0; people[i].carrying = nil; people[i].task = .idle
            }
        case .build(let id):
            guard let bi = buildingIndex(id), buildings[bi].site else { people[i].task = .idle; return }
            let b = buildings[bi], need = cost(of: b)
            // Builders work from the front of the site, where the scaffolding faces the street.
            let front = around(b).filter { $0.y == b.y + b.kind.size }
            switch go(i, front.isEmpty ? around(b) : front, dt) {
            case .walking: return
            case .stuck: people[i].task = .pause(3)
            case .arrived:
                guard (0..<5).allSatisfy({ b.delivered[$0] >= need[$0] - 0.01 }) else { people[i].task = .idle; return }
                let work = b.kind == .furnace ? Self.upgradeWork : b.kind.work
                buildings[bi].progress += dt / work * moraleSpeed * (storm ? 0.6 : 1)
                if people[i].swung > 0.6 { people[i].swung = 0 }
                people[i].facing = centre(b).x >= people[i].x ? 1 : -1
                if buildings[bi].progress >= 1 {
                    buildings[bi].progress = 1
                    if b.kind == .furnace {
                        buildings[bi].upgrading = false; buildings[bi].level += 1
                        buildings[bi].delivered = [0, 0, 0, 0, 0]
                        moment(.upgraded(buildings[bi].level), centre(b).x, centre(b).y)
                    } else {
                        buildings[bi].done = true
                        moment(.finished(b.kind), centre(b).x, centre(b).y)
                    }
                    if b.kind == .house || b.kind == .furnace { rehouse() }
                    people[i].task = .idle
                }
            }
        }
    }

    /// A fetcher is free again when the errand fails.
    private mutating func release(_ i: Int) {
        let id = people[i].id
        for b in buildings.indices where buildings[b].fetcher == id { buildings[b].fetcher = nil }
        if people[i].amount > 0, let s = nearestStorage(people[i].x, people[i].y, room: 0) { people[i].task = .store(s) }
    }

    /// How much of a good to carry for this purpose, minus what others are already bringing.
    private func wanted(_ g: IceGood, for purpose: Int, by who: Int) -> Double {
        guard let b = building(purpose) else { return 0 }
        if b.kind == .furnace, g == .coal { return 10 }
        if b.site { return min(12, max(0, cost(of: b)[g.rawValue] - b.delivered[g.rawValue] - incoming(g, to: purpose, besides: who))) }
        return b.kind == .house ? 8 : 6
    }

    /// What is on its way to a building: being fetched for it, or carried to it.
    func incoming(_ g: IceGood, to id: Int, besides: Int? = nil) -> Double {
        people.reduce(0) { sum, p in
            guard p.id != besides else { return sum }
            switch p.task {
            case .fetch(_, g, id): return sum + 12
            case .bring(id) where p.carrying == g: return sum + p.amount
            default: return sum
            }
        }
    }

    // MARK: What to do next

    private mutating func decide(_ i: Int) {
        let p = people[i]
        let home = p.home.flatMap(building)
        if p.amount > 0 {
            if let s = nearestStorage(p.x, p.y, room: p.amount) ?? nearestStorage(p.x, p.y, room: 0) { people[i].task = .store(s) }
            else { people[i].amount = 0; people[i].carrying = nil }
            return
        }
        // The sick: to a clinic's bed if there is one free, else home to lie down.
        if p.sick {
            let lying = people.reduce(into: [Int: Int]()) { n, q in if case .heal(let c) = q.task { n[c, default: 0] += 1 } }
            if let c = buildings.filter({ $0.kind == .clinic && $0.done && lying[$0.id, default: 0] < Self.clinicBeds }).min(by: { distance($0, p.x, p.y) < distance($1, p.x, p.y) }) {
                people[i].task = .heal(c.id); return
            }
            people[i].task = home != nil ? .goHome : .pause(4)
            return
        }
        if p.kid {
            let h = hub
            let base = home.map { centre($0) } ?? h
            if home != nil, roll(3) == 0 { people[i].task = .goHome; return }
            let t = IceTile(x: Int(base.x) + roll(7) - 3, y: Int(base.y) + roll(5) - 1)
            people[i].task = walkable(t) ? .wander(t) : .pause(2)
            return
        }
        // Errands for the house: food.
        if let home, let hi = buildingIndex(home.id), home.fetcher == nil || home.fetcher == p.id {
            let n = Double(residents(home.id))
            if home.stock[2] < n * 1.2, let s = storage(with: .food, p.x, p.y, atLeast: 2) {
                buildings[hi].fetcher = p.id; people[i].task = .fetch(s, .food, home.id); return
            }
        }
        if let job = p.job, let b = building(job), b.done {
            switch b.kind {
            case .lumber, .hunter, .fishery:
                if let t = target(for: b, from: p) { people[i].task = .harvest(t); return }
            case .coalMine, .ironMine, .quarry:
                if b.reserve > 0 { people[i].task = .work(job); return }
            case .greenhouse, .clinic:
                people[i].task = .work(job); return
            default: break
            }
        }
        // Hands for building: fetch what a site is missing, or build one that has everything.
        let sites = buildings.filter { $0.site }
            .sorted { hypot(Double($0.x) - p.x, Double($0.y) - p.y) + ($0.kind == .furnace ? -8 : 0) < hypot(Double($1.x) - p.x, Double($1.y) - p.y) + ($1.kind == .furnace ? -8 : 0) }
        for site in sites {
            let need = cost(of: site)
            for g in IceGood.allCases where need[g.rawValue] - site.delivered[g.rawValue] - incoming(g, to: site.id) > 0.01 {
                if let s = storage(with: g, Double(site.x), Double(site.y)) { people[i].task = .fetch(s, g, site.id); return }
            }
        }
        for site in sites where (0..<5).allSatisfy({ site.delivered[$0] >= cost(of: site)[$0] - 0.01 }) {
            let builders = people.filter { $0.task == .build(site.id) }.count
            if builders < (site.kind == .furnace ? 6 : 4) { people[i].task = .build(site.id); return }
        }
        // Coal to the furnace's hopper, by whoever is free: two at a time.
        if let f = furnace, f.stock[0] < burnNow * 1.5 {
            let carrying = people.filter { if case .fetch(_, .coal, f.id) = $0.task { return true }; if case .bring(f.id) = $0.task, $0.carrying == .coal { return true }; return false }.count
            if carrying < 2, let s = storage(with: .coal, p.x, p.y, atLeast: 3) { people[i].task = .fetch(s, .coal, f.id); return }
        }
        // Nothing to do: home to rest, or a walk to warm up by the furnace.
        if home != nil, roll(3) > 0 { people[i].task = .goHome; return }
        let h = hub
        let a = Double(roll(628)) / 100, r = 2.4 + Double(roll(20)) / 10
        let t = IceTile(x: Int(h.x + cos(a) * r), y: Int(h.y + sin(a) * r * 0.8))
        people[i].task = walkable(t) ? .wander(t) : .pause(3)
    }

    /// The next pine, hunting ground or fishing hole for a lodge's worker: the nearest to the worker within reach.
    private func target(for b: IceBuilding, from p: IcePerson) -> IceTile? {
        let c = centre(b), r = b.kind == .fishery ? Self.fishReach : Self.reach
        var best: IceTile?, bestD = Double.infinity
        let taken = Set(people.compactMap { q -> IceTile? in if case .harvest(let t) = q.task, q.id != p.id { return t }; return nil })
        for y in max(0, Int(c.y) - r)...min(Self.height - 1, Int(c.y) + r) {
            for x in max(0, Int(c.x) - r)...min(Self.width - 1, Int(c.x) + r) {
                let i = y * Self.width + x, t = IceTile(x: x, y: y)
                guard hypot(Double(x) + 0.5 - c.x, Double(y) + 0.5 - c.y) <= Double(r), !taken.contains(t) else { continue }
                switch b.kind {
                case .lumber: guard ground[i] == .forest, wood[i] >= 1 else { continue }
                case .hunter: guard ground[i] == .forest, game[i] >= 1 else { continue }
                case .fishery: guard ground[i] == .ice, fish[i] >= 1, occupant[i] == nil else { continue }
                default: continue
                }
                let d = hypot(Double(x) - p.x, Double(y) - p.y) + hypot(Double(x) - c.x, Double(y) - c.y) * 0.5
                if d < bestD { bestD = d; best = t }
            }
        }
        return best
    }

    private mutating func harvest(_ i: Int, _ t: IceTile, _ dt: Double) {
        guard let job = people[i].job, let b = building(job) else { people[i].task = .idle; return }
        let ti = Self.index(t)
        let goals = b.kind == .lumber ? neighbours(t) : neighbours(t).union(walkable(t) ? [t] : [])
        switch go(i, goals, dt) {
        case .walking: return
        case .stuck: people[i].task = .pause(2); return
        case .arrived: break
        }
        people[i].busy += dt * pace(b)
        if people[i].swung > 0.7 { people[i].swung = 0 }
        people[i].facing = Double(t.x) + 0.5 >= people[i].x ? 1 : -1
        switch b.kind {
        case .lumber:
            guard wood[ti] >= 1 else { people[i].busy = 0; people[i].task = .idle; return }
            guard people[i].busy >= 4.5 else { return }
            wood[ti] = 0; people[i].busy = 0
            people[i].carrying = .wood; people[i].amount += 6; note(made: .wood, 6, by: i)
            moment(.felled, Double(t.x) + 0.5, Double(t.y) + 0.5)
            // Two pines a trip, then to the storage.
            if people[i].amount < 12, let next = target(for: b, from: people[i]) { people[i].task = .harvest(next) } else { people[i].task = .idle }
        case .hunter:
            guard game[ti] >= 1 else { people[i].busy = 0; people[i].task = .idle; return }
            guard people[i].busy >= 2.4 else { return }
            game[ti] -= 1; people[i].busy = 0
            people[i].carrying = .food; people[i].amount += 3; note(made: .food, 3, by: i)
            if people[i].amount >= 9 { people[i].task = .idle }
            else if let next = target(for: b, from: people[i]) { people[i].task = .harvest(next) } else { people[i].task = .idle }
        case .fishery:
            guard fish[ti] >= 1 else { people[i].busy = 0; people[i].task = .idle; return }
            guard people[i].busy >= 3.2 else { return }
            fish[ti] -= 1; people[i].busy = 0
            people[i].carrying = .food; people[i].amount += 3; note(made: .food, 3, by: i)
            if people[i].amount >= 9 { people[i].task = .idle }
            else if let next = target(for: b, from: people[i]) { people[i].task = .harvest(next) } else { people[i].task = .idle }
        default:
            people[i].task = .idle
        }
    }

    /// Work at the place itself.
    private mutating func labour(_ i: Int, _ id: Int, _ dt: Double) {
        guard let bi = buildingIndex(id), people[i].job == id else { people[i].task = .idle; return }
        let b = buildings[bi]
        switch go(i, around(b), dt) {
        case .walking: return
        case .stuck: people[i].task = .pause(3); return
        case .arrived: break
        }
        let rate = pace(b)
        switch b.kind {
        case .coalMine, .ironMine, .quarry:
            guard b.reserve > 0 else { people[i].task = .idle; return }
            people[i].busy += dt * rate
            if people[i].swung > 0.7 { people[i].swung = 0 }
            let good: IceGood = b.kind == .coalMine ? .coal : b.kind == .ironMine ? .iron : .stone
            let (every, lump, load): (Double, Double, Double) = good == .coal ? (4.2, 3, 9) : good == .iron ? (4.6, 2, 8) : (5.2, 3, 9)
            guard people[i].busy >= every else { return }
            people[i].busy = 0
            let got = min(b.reserve, lump)
            buildings[bi].reserve -= got
            people[i].carrying = good; people[i].amount += got; note(made: good, got, by: i)
            if people[i].amount >= load { people[i].task = .idle }
        case .greenhouse:
            people[i].busy += dt * rate
            if people[i].swung > 0.9 { people[i].swung = 0 }
            guard people[i].busy >= 3.5 else { return }
            people[i].busy = 0
            people[i].carrying = .food; people[i].amount += 2; note(made: .food, 2, by: i)
            if people[i].amount >= 8 { people[i].task = .idle }
        case .clinic:
            // Doctors tend the beds inside; out now and then for air.
            people[i].inside = true
            people[i].task = .pause(6 + Double(roll(40)) / 10)
        default:
            people[i].task = .idle
        }
    }

    // MARK: War

    /// How hard a general's soldiers hit a county's defenders, per soldier, on a day.
    func punch(_ h: Int, against region: Int, on d: Int) -> Double {
        let o = iceOfficers[h], foe = owner[region] == 1 ? 3 : owner[region] == 2 ? 4 : iceRegions[region].foe
        var m = 0.7 + Double(o.lead) / 200 + Double(o.war) / 400
        switch o.talent {
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
        if o.talent != .veteran { m *= max(0.6, min(1, 1 + (temperature(on: d) + 15) / 100)) }
        return m
    }
    func defence(_ region: Int) -> Double {
        let foe = owner[region] == 1 ? 3 : owner[region] == 2 ? 4 : iceRegions[region].foe
        return garrison[region] * [1.0, 0.9, 1.3, 1.2, 1.2][max(0, foe)] * (iceRegions[region].capital ? 1.25 : 1)
    }
    static func odds(_ ratio: Double) -> Double { 1 / (1 + exp(-5 * (ratio - 1))) }
    /// Days to march from the city to a county, through what we hold.
    func steps(to region: Int) -> Int? {
        var seen = [0], frontier = [0], steps = 0
        while !frontier.isEmpty {
            steps += 1
            var next: [Int] = []
            for a in frontier {
                for b in iceRegionLinks[a] where !seen.contains(b) {
                    if b == region { return steps }
                    seen.append(b)
                    if owner[b] == 0 { next.append(b) }
                }
            }
            frontier = next
        }
        return nil
    }
    func travel(_ h: Int, to region: Int) -> Int? {
        guard let s = steps(to: region) else { return nil }
        return max(1, 1 + s - (iceOfficers[h].talent == .cavalry ? 1 : 0))
    }
    /// A battle as it would likely go: the chance of winning, and what it costs either way.
    func battle(_ h: Int, _ n: Int, _ region: Int, on d: Int) -> (chance: Double, winKilled: Int, winWounded: Int, loseKilled: Int, loseWounded: Int) {
        let attack = Double(n) * punch(h, against: region, on: d), guard_ = max(1, defence(region))
        let p = Self.odds(attack / guard_)
        let lossWin = min(0.6, max(0.05, 0.4 * guard_ / max(attack, 1))) * Double(n)
        let careful = iceOfficers[h].talent == .planner ? 0.8 : 1
        return (p, Int((lossWin * 0.25 * careful).rounded()), Int((lossWin * 0.75 * careful).rounded()),
                Int((Double(n) * 0.55 * 0.3 * careful).rounded()), Int((Double(n) * 0.55 * 0.7 * careful).rounded()))
    }
    /// Soldiers to send: enough to win nine times in ten, or all there are.
    func army(_ h: Int, to region: Int) -> Int {
        let days = travel(h, to: region) ?? 2
        let per = punch(h, against: region, on: today + days)
        let needed = Int((defence(region) * 1.44 / max(per, 0.1) / 5).rounded(.up)) * 5
        return min(soldiers, max(5, needed))
    }
    var freeOfficers: [Int] { officers.filter { !$0.away }.map(\.officer) }
    /// Counties an army can reach now.
    var targets: [Int] { (1..<iceRegions.count).filter { r in owner[r] != 0 && steps(to: r) != nil && !expeditions.contains { $0.region == r && !$0.back } } }

    /// Send a general with soldiers to a county.
    @discardableResult
    mutating func send(_ h: Int, soldiers n: Int, to region: Int) -> Bool {
        guard n > 0, n <= soldiers, owner[region] != 0, let g = officers.firstIndex(where: { $0.officer == h && !$0.away }),
              let days = travel(h, to: region), !expeditions.contains(where: { $0.region == region && !$0.back }) else { return false }
        soldiers -= n
        officers[g].away = true; officers[g].governs = nil
        expeditions.append(IceExpedition(region: region, officer: h, soldiers: n, travel: days, left: days, since: time))
        moment(.news("\(iceOfficers[h].name)带 \(n) 兵出征\(iceRegions[region].name)"), hub)
        return true
    }

    private mutating func marchOn() {
        var kept: [IceExpedition] = []
        for var m in expeditions {
            m.left -= 1
            if m.left > 0 { kept.append(m); continue }
            if !m.back {
                let b = battle(m.officer, m.soldiers, m.region, on: today)
                let won = Double(roll(10_000)) / 10_000 < b.chance
                let killed = won ? b.winKilled : b.loseKilled, hurt = won ? b.winWounded : b.loseWounded
                m.soldiers -= killed + hurt; m.wounded = hurt; m.won = won
                var joined = 0
                if won {
                    let rival = owner[m.region]
                    owner[m.region] = 0; garrison[m.region] = 0
                    joined = iceRegions[m.region].people * (iceOfficers[m.officer].talent == .ruler ? 3 : 2) / 2
                    waiting += joined
                    morale = min(100, morale + 4)
                    if rival == 1 || rival == 2 { rivals[rival - 1].reserve *= 0.9 }
                } else {
                    garrison[m.region] = max(5, garrison[m.region] - Double(m.soldiers + killed + hurt) * 0.25)
                    morale = max(0, morale - 3)
                }
                battles.append(IceBattle(region: m.region, officer: m.officer, won: won, killed: killed, wounded: hurt, people: joined, time: time))
                moment(.news(won ? "\(iceOfficers[m.officer].name)攻下了\(iceRegions[m.region].name)" + (joined > 0 ? "，\(joined) 人要来投奔" : "")
                                 : "\(iceOfficers[m.officer].name)在\(iceRegions[m.region].name)吃了败仗"), hub)
                m.back = true; m.left = m.travel; m.since = time
                kept.append(m)
            } else {
                soldiers += m.soldiers; wounded += m.wounded
                if let g = officers.firstIndex(where: { $0.officer == m.officer }) { officers[g].away = false }
                moment(.news("\(iceOfficers[m.officer].name)带兵回城了"), hub)
            }
        }
        expeditions = kept
        if battles.count > 12 { battles.removeFirst(battles.count - 12) }
    }

    /// What would meet raiders at the city: the soldiers at home behind the wall.
    var defenceAtHome: Double { Double(soldiers) * (1 + 0.3 * wallStrength) + 15 * wallStrength + 10 }
    /// The rival that could raid next, when, and with about how many.
    var raidThreat: (rival: Int, day: Int, raiders: Double)? {
        var out: (rival: Int, day: Int, raiders: Double)?
        for r in 0..<2 {
            let me = r + 1
            guard (1..<owner.count).contains(where: { i in owner[i] == me && iceRegionLinks[i].contains { owner[$0] == 0 } }) else { continue }
            let raiders = min(rivals[r].reserve * 0.3, 12 + Double(rivals[r].nextRaid) * 0.45)
            if out == nil || rivals[r].nextRaid < out!.day { out = (r, max(today, rivals[r].nextRaid), raiders) }
        }
        return out
    }

    /// A rival lord's day: now and then it takes a neighbouring county from the wild, or raids the city.
    private mutating func rivalDay(_ r: Int) {
        let me = r + 1
        let held = owner.filter { $0 == me }.count
        guard held > 0 else { return }
        rivals[r].reserve += 1 + 0.5 * Double(held)
        let d = today
        let near = (1..<owner.count).contains { i in owner[i] == me && iceRegionLinks[i].contains { owner[$0] == 0 } }
        if d >= rivals[r].nextRaid {
            rivals[r].nextRaid = d + 14 + roll(7)
            if near {
                let raiders = min(rivals[r].reserve * 0.3, 12 + Double(d) * 0.45)
                let won = Double(roll(10_000)) / 10_000 < Self.odds(raiders / max(1, defenceAtHome))
                rivals[r].reserve -= raiders * (won ? 0.2 : 0.5)
                let from = r == 0 ? IceTile(x: Self.width - 1, y: 2 + roll(8)) : IceTile(x: Self.width - 1, y: Self.height - 3 - roll(8))
                raids.append(IceRaid(rival: r, raiders: Int(raiders), won: won, time: time, from: from))
                if raids.count > 4 { raids.removeFirst() }
                if won {
                    for g in [IceGood.coal, .food, .wood] { let lost = stored(g) * 0.12; take(g, lost); used[g.rawValue] += lost }
                    let hurt = min(soldiers, Int(Double(soldiers) * 0.2))
                    soldiers -= hurt; wounded += hurt
                    morale = max(0, morale - 6); raidsLost += 1
                    moment(.news("\(iceSideCN[me])军来袭，抢走了一些煤、木和粮"), hub)
                } else {
                    let hurt = min(soldiers, Int(raiders * 0.1))
                    soldiers -= hurt; wounded += hurt
                    morale = min(100, morale + 2); raidsHeld += 1
                    moment(.news("打退了\(iceSideCN[me])军的偷袭"), hub)
                }
                return
            }
        }
        guard d >= 12 + 4 * r, (d + rivals[r].offset) % rivals[r].period == 0 else { return }
        var best: (Int, Double)?
        for i in 1..<owner.count where owner[i] == 3 && iceRegionLinks[i].contains(where: { owner[$0] == me }) {
            if expeditions.contains(where: { $0.region == i && !$0.back }) { continue }
            let dv = defence(i)
            if best == nil || dv < best!.1 { best = (i, dv) }
        }
        guard let pick = best, rivals[r].reserve * 0.7 > pick.1 * 1.3 else { return }
        let sent = rivals[r].reserve * 0.7
        if Double(roll(10_000)) / 10_000 < Self.odds(sent / pick.1) {
            owner[pick.0] = me; garrison[pick.0] = max(22, sent * 0.45)
            rivals[r].reserve -= sent * 0.8
            moment(.news("\(iceSideCN[me])国占了\(iceRegions[pick.0].name)"), hub)
        } else {
            garrison[pick.0] = max(10, garrison[pick.0] - sent * 0.3)
            rivals[r].reserve -= sent * 0.6
        }
    }

    // MARK: The lord's other orders

    var canTrain: Bool {
        count(.barracks) > 0 && inArms + Self.batchSize <= soldierRoom && stored(.food) >= Double(Self.batchSize) * 2 && stored(.iron) >= Double(Self.batchSize)
            && buildings.contains { $0.kind == .barracks && $0.done && $0.batch == 0 }
    }
    /// A batch of soldiers into training at a free barracks: a day's drill, paid in food and iron.
    @discardableResult
    mutating func train() -> Bool {
        guard canTrain, let b = buildings.firstIndex(where: { $0.kind == .barracks && $0.done && $0.batch == 0 }) else { return false }
        let n = Self.batchSize
        take(.food, Double(n) * 2); take(.iron, Double(n)); used[2] += Double(n) * 2; used[4] += Double(n)
        buildings[b].batch = n; buildings[b].training = Self.daySeconds
        return true
    }
    func canRecruit(_ h: Int) -> Bool {
        count(.tavern) > 0 && officers.count < heroRoom && offered.contains(h)
            && stored(.food) >= Double(iceOfficers[h].food) && stored(.iron) >= Double(iceOfficers[h].iron)
    }
    @discardableResult
    mutating func recruit(_ h: Int) -> Bool {
        guard canRecruit(h) else { return false }
        take(.food, Double(iceOfficers[h].food)); take(.iron, Double(iceOfficers[h].iron))
        used[2] += Double(iceOfficers[h].food); used[4] += Double(iceOfficers[h].iron)
        officers.append(IceHired(officer: h))
        offered.removeAll { $0 == h }
        if !pool.isEmpty { offered.append(pool.removeFirst()) }
        moment(.news("\(iceOfficers[h].name)来投奔了"), hub)
        return true
    }
    /// A general to govern a building (nil: back to being free).
    mutating func govern(_ h: Int, _ id: Int?) {
        guard let g = officers.firstIndex(where: { $0.officer == h }), !officers[g].away else { return }
        if let id { for k in officers.indices where officers[k].governs == id { officers[k].governs = nil } }
        officers[g].governs = id
    }

    // MARK: Matters at the gate

    /// Each matter's answers; the last is the one that costs nothing.
    static func choices(_ kind: Int) -> [String] {
        switch kind {
        case 0: return ["收留难民", "请难民离开"]
        case 1: return ["准矿工歇一天", "不准，照常下井"]
        case 2: return ["加倍烧煤，扛过寒潮", "照常烧煤"]
        case 3: return ["用 60 木换 50 粮", "用 30 铁换 60 煤", "用 80 木换 30 铁", "不做买卖"]
        case 4: return ["开仓熬药（30 粮）", "任它蔓延"]
        case 5: return ["办冰灯节（25 粮 20 木）", "今年不办"]
        case 6: return ["派 10 兵去猎狼", "关门不出猎"]
        case 7: return ["收下老兵（30 粮）", "婉拒"]
        case 8: return ["挖开冰窖（30 木）", "不去管它"]
        case 9: return ["严惩偷煤贼", "原谅他"]
        default: return ["为新人办婚礼（15 粮）", "简单办"]
        }
    }
    static let incidentTitles = ["城门外来了难民", "矿工请愿：想歇一天暖暖身子", "寒潮预警", "冰原商队路过", "城里起了风寒", "孩子们想办冰灯节",
                                 "狼群在猎场附近出没", "一队老兵来投军", "发现一座旧冰窖", "抓到一个偷煤贼", "城里有人要成亲"]
    static let incidentIcons = ["🧳", "⛏️", "🌨️", "🐫", "🤒", "🏮", "🐺", "🛡️", "🧊", "🕵️", "💍"]
    static let incidentEN = ["refugees at the gate", "the miners ask for a warm day off", "a cold-spell warning", "a caravan of traders", "a fever in the city",
                             "the children want an ice-lantern festival", "wolves near the hunting grounds", "veterans offering to serve", "an old ice cellar found",
                             "a coal thief caught", "a wedding"]
    /// Whether an answer can be given at all with what the city has.
    func can(_ e: IceIncident, _ choice: Int) -> Bool {
        switch (e.kind, choice) {
        case (3, 0): return stored(.wood) >= 60
        case (3, 1): return stored(.iron) >= 30
        case (3, 2): return stored(.wood) >= 80
        case (4, 0): return stored(.food) >= 30
        case (5, 0): return stored(.food) >= 25 && stored(.wood) >= 20
        case (6, 0): return soldiers >= 10
        case (7, 0): return stored(.food) >= 30
        case (8, 0): return stored(.wood) >= 30
        case (10, 0): return stored(.food) >= 15
        default: return true
        }
    }

    /// Answer the matter at the gate.
    mutating func answer(_ choice: Int) {
        guard let e = incident else { return }
        let c = can(e, choice) ? choice : Self.choices(e.kind).count - 1
        incident = nil
        func mood(_ x: Double) { morale = min(100, max(0, morale + x)) }
        switch (e.kind, c) {
        case (0, 0): newcomers(e.amount); mood(4)
        case (0, _): mood(-5)
        case (1, 0): minersRest = 1; mood(6)
        case (1, _): mood(-6)
        case (2, 0): overdrive = max(overdrive, e.amount + 2)
        case (2, _): break
        case (3, 0): receive(.wood, -60); receive(.food, 50)
        case (3, 1): receive(.iron, -30); receive(.coal, 60)
        case (3, 2): receive(.wood, -80); receive(.iron, 30)
        case (3, _): break
        case (4, 0):
            receive(.food, -30)
            var n = 8
            for i in people.indices where people[i].sick && n > 0 { people[i].sick = false; cured += 1; n -= 1 }
            mood(2)
        case (4, _):
            var n = 6
            for i in shuffled(people.count) where !people[i].sick && !people[i].kid && n > 0 {
                people[i].sick = true; people[i].job = nil; sickened += 1; n -= 1
                switch people[i].task { case .work, .harvest, .build: people[i].task = .idle; default: break }
            }
        case (5, 0): receive(.food, -25); receive(.wood, -20); mood(9)
        case (5, _): mood(-2)
        case (6, 0): receive(.food, 40); let n = min(soldiers, 3); soldiers -= n; wounded += n
        case (6, _): huntBad = 3
        case (7, 0): receive(.food, -30); soldiers += 8
        case (7, _): break
        case (8, 0): receive(.wood, -30); receive(.food, 90)
        case (8, _): break
        case (9, 0): receive(.coal, 25); mood(-3)
        case (9, _): mood(3)
        case (10, 0): receive(.food, -15); mood(5)
        default: mood(1)
        }
    }

    mutating func moment(_ kind: IceMoment.Kind, _ x: Double, _ y: Double) { moments.append(IceMoment(kind: kind, x: x, y: y, time: time)) }
    mutating func moment(_ kind: IceMoment.Kind, _ at: (x: Double, y: Double)) { moment(kind, at.x, at.y) }
}

/// A binary heap of (priority, tile index), smallest first — for A*.
struct IceHeap {
    private var items: [(Double, Int)] = []
    mutating func push(_ f: Double, _ i: Int) {
        items.append((f, i))
        var c = items.count - 1
        while c > 0 {
            let p = (c - 1) / 2
            if items[p].0 <= items[c].0 { break }
            items.swapAt(p, c); c = p
        }
    }
    mutating func pop() -> Int? {
        guard !items.isEmpty else { return nil }
        let top = items[0].1
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var p = 0
            while true {
                let l = 2 * p + 1, r = l + 1
                var m = p
                if l < items.count, items[l].0 < items[m].0 { m = l }
                if r < items.count, items[r].0 < items[m].0 { m = r }
                if m == p { break }
                items.swapAt(p, m); p = m
            }
        }
        return top
    }
}
