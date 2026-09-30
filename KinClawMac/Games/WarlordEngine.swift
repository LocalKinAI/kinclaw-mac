import Foundation

/// 三国争霸（大地图版）: China in 190 AD, month by month. Forty-three cities
/// joined by roads — some across the 黄河 or 长江, some over mountain passes —
/// seventeen warlords and their generals, and many more generals still out in
/// the world to be found and won over. Everything here is plain data and
/// arithmetic, played the same way from the same seed: the person's clicks, the
/// script, Jev and the chat models all come in through the same commands.

// MARK: - The land

enum WarlordRoadKind: Int { case plain, river, pass }

struct WarlordSite {
    let name: String
    let lon: Double, lat: Double
    /// 1 a small town … 5 a great city.
    let size: Int
    let province: String
}

enum WarlordMap {
    /// The map in its own units: west to east 97°E–126°E, north to south 43°N–20°N.
    static let width = 1000.0, height = 933.0
    static func point(_ lon: Double, _ lat: Double) -> CGPoint {
        CGPoint(x: (lon - 97) / 29 * width, y: (43 - lat) / 23 * height)
    }
    static func at(_ city: Int) -> CGPoint { point(warlordSites[city].lon, warlordSites[city].lat) }
}

let warlordSites: [WarlordSite] = [
    WarlordSite(name: "洛阳", lon: 112.45, lat: 34.62, size: 5, province: "司隶"),   // 0
    WarlordSite(name: "长安", lon: 108.94, lat: 34.34, size: 5, province: "司隶"),   // 1
    WarlordSite(name: "许昌", lon: 113.8, lat: 34.0, size: 4, province: "豫州"),     // 2
    WarlordSite(name: "陈留", lon: 114.85, lat: 34.62, size: 3, province: "兖州"),   // 3
    WarlordSite(name: "濮阳", lon: 115.1, lat: 35.75, size: 3, province: "兖州"),    // 4
    WarlordSite(name: "邺", lon: 114.3, lat: 36.4, size: 5, province: "冀州"),       // 5
    WarlordSite(name: "上党", lon: 112.9, lat: 36.15, size: 2, province: "并州"),    // 6
    WarlordSite(name: "晋阳", lon: 112.55, lat: 37.87, size: 3, province: "并州"),   // 7
    WarlordSite(name: "北平", lon: 116.4, lat: 39.9, size: 4, province: "幽州"),     // 8
    WarlordSite(name: "南皮", lon: 116.95, lat: 38.3, size: 3, province: "冀州"),    // 9
    WarlordSite(name: "平原", lon: 116.25, lat: 37.1, size: 3, province: "青州"),    // 10
    WarlordSite(name: "北海", lon: 118.7, lat: 36.7, size: 3, province: "青州"),     // 11
    WarlordSite(name: "辽东", lon: 123.2, lat: 41.27, size: 3, province: "幽州"),    // 12
    WarlordSite(name: "小沛", lon: 116.93, lat: 34.73, size: 2, province: "徐州"),   // 13
    WarlordSite(name: "下邳", lon: 118.0, lat: 34.3, size: 4, province: "徐州"),     // 14
    WarlordSite(name: "广陵", lon: 119.45, lat: 32.6, size: 3, province: "徐州"),    // 15
    WarlordSite(name: "寿春", lon: 116.78, lat: 32.57, size: 4, province: "扬州"),   // 16
    WarlordSite(name: "汝南", lon: 114.4, lat: 33.0, size: 3, province: "豫州"),     // 17
    WarlordSite(name: "宛", lon: 112.53, lat: 33.0, size: 4, province: "荆州"),      // 18
    WarlordSite(name: "襄阳", lon: 112.14, lat: 32.02, size: 4, province: "荆州"),   // 19
    WarlordSite(name: "上庸", lon: 110.3, lat: 32.25, size: 1, province: "荆州"),    // 20
    WarlordSite(name: "江陵", lon: 112.18, lat: 30.35, size: 4, province: "荆州"),   // 21
    WarlordSite(name: "江夏", lon: 114.3, lat: 30.6, size: 3, province: "荆州"),     // 22
    WarlordSite(name: "武陵", lon: 111.7, lat: 29.0, size: 2, province: "荆州"),     // 23
    WarlordSite(name: "长沙", lon: 112.94, lat: 28.2, size: 3, province: "荆州"),    // 24
    WarlordSite(name: "零陵", lon: 111.6, lat: 26.3, size: 2, province: "荆州"),     // 25
    WarlordSite(name: "桂阳", lon: 113.05, lat: 25.8, size: 2, province: "荆州"),    // 26
    WarlordSite(name: "庐江", lon: 117.25, lat: 31.4, size: 2, province: "扬州"),    // 27
    WarlordSite(name: "柴桑", lon: 116.0, lat: 29.72, size: 2, province: "扬州"),    // 28
    WarlordSite(name: "豫章", lon: 115.9, lat: 28.6, size: 3, province: "扬州"),     // 29
    WarlordSite(name: "建业", lon: 118.78, lat: 32.06, size: 4, province: "扬州"),   // 30
    WarlordSite(name: "吴", lon: 120.6, lat: 31.3, size: 4, province: "扬州"),       // 31
    WarlordSite(name: "会稽", lon: 120.58, lat: 30.0, size: 3, province: "扬州"),    // 32
    WarlordSite(name: "汉中", lon: 107.03, lat: 33.07, size: 3, province: "益州"),   // 33
    WarlordSite(name: "梓潼", lon: 105.17, lat: 31.64, size: 2, province: "益州"),   // 34
    WarlordSite(name: "成都", lon: 104.07, lat: 30.67, size: 5, province: "益州"),   // 35
    WarlordSite(name: "江州", lon: 106.55, lat: 29.56, size: 3, province: "益州"),   // 36
    WarlordSite(name: "永安", lon: 109.5, lat: 31.0, size: 2, province: "益州"),     // 37
    WarlordSite(name: "建宁", lon: 103.8, lat: 25.5, size: 2, province: "益州"),     // 38
    WarlordSite(name: "云南", lon: 100.7, lat: 25.6, size: 1, province: "益州"),     // 39
    WarlordSite(name: "天水", lon: 105.72, lat: 34.58, size: 2, province: "凉州"),   // 40
    WarlordSite(name: "武威", lon: 102.64, lat: 37.93, size: 3, province: "凉州"),   // 41
    WarlordSite(name: "南海", lon: 113.3, lat: 23.1, size: 3, province: "交州"),     // 42
]

struct WarlordRoad {
    let a: Int, b: Int
    let kind: WarlordRoadKind
    /// Months an army takes along it.
    let months: Int
    /// What the road is called when it is a crossing or a pass.
    let name: String
}

let warlordRoads: [WarlordRoad] = {
    func r(_ a: Int, _ b: Int, _ k: WarlordRoadKind = .plain, _ m: Int = 1, _ n: String = "") -> WarlordRoad { WarlordRoad(a: a, b: b, kind: k, months: m, name: n) }
    return [
        r(0, 1, .pass, 1, "函谷关"), r(0, 2), r(0, 3), r(0, 5, .river, 1, "孟津"), r(0, 6, .pass, 1, "太行陉"), r(0, 18, .pass, 1, "鲁阳关"),
        r(1, 40, .plain, 2), r(1, 33, .pass, 1, "子午谷"), r(1, 7, .river, 2, "蒲坂津"),
        r(2, 3), r(2, 17), r(2, 18),
        r(3, 4, .river, 1, "白马津"), r(3, 13),
        r(4, 5), r(4, 10),
        r(5, 6, .pass, 1, "滏口陉"), r(5, 9), r(5, 10),
        r(6, 7),
        r(7, 8, .pass, 2, "飞狐陉"),
        r(8, 9), r(8, 12, .pass, 2, "卢龙塞"),
        r(9, 10),
        r(10, 11, .river, 1, "平原津"),
        r(11, 14), r(13, 14), r(14, 15), r(14, 16, .river, 1, "淮水"),
        r(15, 30, .river, 1, "瓜洲渡"),
        r(16, 17), r(16, 27), r(16, 30, .river, 1, "横江渡"),
        r(17, 22, .pass, 1, "大别山"),
        r(18, 19, .river, 1, "汉水"),
        r(19, 20, .pass), r(19, 21), r(19, 22),
        r(20, 33, .pass, 2, "子午道"), r(20, 37, .pass, 1, "巫山"),
        r(21, 22, .river, 1, "长江"), r(21, 23, .river, 1, "长江"), r(21, 37, .river, 1, "三峡"),
        r(22, 24, .river, 1, "巴丘"), r(22, 28, .river, 1, "长江"),
        r(23, 24), r(23, 25, .pass, 1, "雪峰山"),
        r(24, 25), r(24, 26), r(24, 29, .pass, 1, "罗霄山"),
        r(25, 26), r(26, 42, .pass, 2, "骑田岭"),
        r(27, 28, .river, 1, "长江"), r(27, 30),
        r(28, 29),
        r(29, 32, .pass, 2, "怀玉山"), r(29, 42, .pass, 2, "大庾岭"),
        r(30, 31), r(31, 32, .river, 1, "浙江"),
        r(33, 34, .pass, 1, "剑阁"), r(33, 40, .pass, 1, "祁山"),
        r(34, 35), r(35, 36), r(35, 38, .pass, 2, "南中"), r(36, 37, .river, 1, "长江"), r(36, 38, .pass, 2, "南中"),
        r(38, 39),
        r(40, 41, .pass, 2, "陇山"),
    ]
}()

/// For each city: its neighbours and the road to each.
let warlordLinks: [[(city: Int, road: Int)]] = {
    var out = Array(repeating: [(city: Int, road: Int)](), count: warlordSites.count)
    for (i, r) in warlordRoads.enumerated() { out[r.a].append((r.b, i)); out[r.b].append((r.a, i)) }
    return out
}()

func warlordRoad(_ a: Int, _ b: Int) -> WarlordRoad? {
    warlordLinks[a].first { $0.city == b }.map { warlordRoads[$0.road] }
}

// MARK: - People

enum WarlordSkill: Int, CaseIterable {
    case peerless, saint, tiger, brave, genius, schemer, fire, hero, virtue, noble, cavalry, navy, iron, swift, archer, farmer, merchant, scholar, healer, beauty

    var name: String { ["无双", "武圣", "猛将", "一身是胆", "神算", "鬼谋", "火计", "奸雄", "仁德", "名门", "骑兵", "水军", "铁壁", "神速", "神射", "屯田", "商才", "名士", "名医", "倾国"][rawValue] }
    var says: String {
        ["战力 +35%，单挑几乎无敌", "战力 +25%，单挑 +6", "战力 +12%，单挑 +6", "战力 +18%，单挑 +8", "战力 +20%，离间劝降 +25%", "战力 +12%，离间劝降 +20%",
         "战力 +15%，隔江作战 +40%", "战力 +10%，登用 +25%", "登用 +20%，所在城民忠每月 +2", "登用 +15%，征兵多三成", "平地作战 +25%", "渡江作战不吃亏，水战 +20%",
         "守城 +30%", "两月的路一月走到，战力 +8%", "战力 +15%", "开垦加倍", "商业加倍", "内政 +50%，登用 +10%", "所带军伤亡少三成", "离间 +40%"][rawValue]
    }
    var english: String {
        ["unmatched in battle (+35%) and in duels", "+25% battle power, strong in duels", "+12% battle power, strong in duels", "+18% battle power, very strong in duels",
         "+20% battle power, far better at sowing discord and persuading", "+12% battle power, better at sowing discord and persuading", "+15% battle power, +40% across a river",
         "+10% battle power, better at recruiting", "better at recruiting, the city's people grow loyal", "better at recruiting, drafts a third more", "+25% on open roads",
         "no penalty across rivers, +20% there", "+30% defending a city", "two-month roads in one, +8% battle power", "+15% battle power", "double farming", "double trade",
         "+50% at farming, trade and walls, better at recruiting", "a third fewer losses", "+40% at sowing discord"][rawValue]
    }
}

/// How a general looks in a portrait. `hat`: 0 topknot, 1 helmet with a plume, 2 scholar's 纶巾, 3 lord's crown, 4 headband,
/// 5 helmet with pheasant feathers, 6 a lady's hair with a pin, 7 an old man's cap, 8 an official's hat, 9 a southern turban.
/// `beard`: 0 none, 1 moustache, 2 long, 3 bushy, 4 long and white, 5 a goatee. `extra`: 0 none, 1 an eyepatch, 2 a feather fan, 3 heavy jowls.
struct WarlordLook {
    var skin: (Double, Double, Double) = (0.97, 0.82, 0.68)
    var hair: (Double, Double, Double) = (0.12, 0.09, 0.08)
    var coat: (Double, Double, Double)? = nil
    var accent: (Double, Double, Double) = (0.9, 0.74, 0.3)
    var hat = 0, beard = 0, extra = 0
}

struct WarlordPerson {
    let name: String
    let war: Int, wit: Int, lead: Int, pol: Int
    let skill: WarlordSkill?
    /// The faction at the start, or −1 for a general still out in the world.
    let faction: Int
    let city: Int
    /// The year a free general can first be found.
    let appear: Int
    /// Known from the start (everybody knows where 周瑜 is), or to be found by searching.
    let known: Bool
    let loyalty: Int
    var look: WarlordLook
    var total: Int { war + wit + lead + pol }
}

let warlordPeople: [WarlordPerson] = {
    var out: [WarlordPerson] = []
    func p(_ name: String, _ war: Int, _ wit: Int, _ lead: Int, _ pol: Int, _ skill: WarlordSkill?, _ f: Int, _ city: Int, loyal: Int = 90, appear: Int = 190, known: Bool = true,
           _ look: WarlordLook = WarlordLook()) {
        out.append(WarlordPerson(name: name, war: war, wit: wit, lead: lead, pol: pol, skill: skill, faction: f, city: city, appear: appear, known: known, loyalty: loyal, look: look))
    }
    let red = (0.86, 0.34, 0.28), dark = (0.66, 0.5, 0.4), grey = (0.72, 0.72, 0.72), white = (0.95, 0.95, 0.95)
    // 0 曹操 — 陈留
    p("曹操", 72, 91, 96, 94, .hero, 0, 3, loyal: 100, WarlordLook(hat: 3, beard: 5))
    p("夏侯惇", 90, 58, 86, 70, .tiger, 0, 3, loyal: 100, WarlordLook(hat: 1, beard: 1, extra: 1))
    p("夏侯渊", 91, 55, 85, 50, .swift, 0, 3, loyal: 100, WarlordLook(hat: 1, beard: 1))
    p("曹仁", 86, 62, 88, 60, .iron, 0, 3, loyal: 100, WarlordLook(hat: 1, beard: 3))
    p("曹洪", 81, 45, 76, 42, nil, 0, 3, loyal: 95, WarlordLook(hat: 4, beard: 1))
    p("乐进", 84, 52, 78, 48, nil, 0, 3, loyal: 90)
    p("李典", 77, 78, 80, 65, nil, 0, 3, loyal: 90, WarlordLook(hat: 8))
    // 1 刘备 — 平原
    p("刘备", 75, 74, 78, 80, .virtue, 1, 10, loyal: 100, WarlordLook(hat: 3, beard: 5))
    p("关羽", 97, 76, 96, 64, .saint, 1, 10, loyal: 100, WarlordLook(skin: red, coat: (0.2, 0.52, 0.32), accent: (0.2, 0.52, 0.32), hat: 4, beard: 2))
    p("张飞", 98, 30, 85, 22, .tiger, 1, 10, loyal: 100, WarlordLook(skin: dark, coat: (0.2, 0.2, 0.26), hat: 4, beard: 3))
    p("简雍", 42, 72, 30, 75, nil, 1, 10, loyal: 95, WarlordLook(hat: 8, beard: 5))
    // 2 孙坚 — 长沙
    p("孙坚", 90, 72, 92, 70, .brave, 2, 24, loyal: 100, WarlordLook(hat: 1, beard: 1))
    p("孙策", 94, 70, 92, 72, .tiger, 2, 24, loyal: 100, WarlordLook(hat: 1))
    p("程普", 78, 75, 84, 70, .navy, 2, 24, loyal: 95, WarlordLook(hat: 1, beard: 4))
    p("黄盖", 83, 68, 79, 60, .navy, 2, 24, loyal: 100, WarlordLook(hat: 4, beard: 3))
    p("韩当", 81, 50, 78, 50, nil, 2, 24, loyal: 95, WarlordLook(hat: 1, beard: 1))
    p("祖茂", 72, 40, 60, 30, nil, 2, 24, loyal: 95)
    // 3 袁绍 — 南皮
    p("袁绍", 69, 70, 81, 73, .noble, 3, 9, loyal: 100, WarlordLook(hat: 3, beard: 5))
    p("颜良", 93, 41, 80, 30, .tiger, 3, 9, loyal: 95, WarlordLook(hat: 1, beard: 3))
    p("文丑", 94, 26, 78, 25, .tiger, 3, 9, loyal: 95, WarlordLook(skin: dark, hat: 1, beard: 3))
    p("田丰", 30, 95, 70, 82, nil, 3, 9, loyal: 85, WarlordLook(hat: 8, beard: 4))
    p("审配", 42, 76, 75, 68, .iron, 3, 9, loyal: 95, WarlordLook(hat: 8, beard: 5))
    p("许攸", 30, 88, 40, 60, .schemer, 3, 9, loyal: 60, WarlordLook(hat: 8, beard: 1))
    p("高览", 82, 45, 73, 30, nil, 3, 9, loyal: 80, WarlordLook(hat: 1))
    // 4 袁术 — 宛, 汝南
    p("袁术", 65, 61, 72, 55, .noble, 4, 18, loyal: 100, WarlordLook(hat: 3, beard: 1))
    p("纪灵", 85, 42, 76, 40, nil, 4, 18, loyal: 95, WarlordLook(hat: 1, beard: 3))
    p("张勋", 70, 45, 68, 40, nil, 4, 18, loyal: 85, WarlordLook(hat: 1))
    p("桥蕤", 67, 44, 65, 40, nil, 4, 17, loyal: 85)
    p("阎象", 30, 76, 40, 72, nil, 4, 17, loyal: 80, WarlordLook(hat: 8, beard: 4))
    p("雷薄", 70, 30, 60, 25, nil, 4, 17, loyal: 65, WarlordLook(hat: 4, beard: 3))
    p("陈兰", 68, 30, 58, 25, nil, 4, 18, loyal: 65, WarlordLook(hat: 4))
    // 5 董卓 — 洛阳, 长安, 上党
    p("董卓", 87, 69, 84, 20, .cavalry, 5, 0, loyal: 100, WarlordLook(skin: (0.93, 0.74, 0.6), hat: 3, beard: 3, extra: 3))
    p("吕布", 100, 26, 90, 13, .peerless, 5, 0, loyal: 60, WarlordLook(coat: (0.72, 0.12, 0.14), hat: 5))
    p("华雄", 88, 36, 76, 22, .tiger, 5, 0, loyal: 90, WarlordLook(skin: dark, hat: 1, beard: 3))
    p("李傕", 76, 32, 72, 20, .cavalry, 5, 1, loyal: 80, WarlordLook(hat: 1, beard: 1))
    p("郭汜", 72, 30, 70, 20, .cavalry, 5, 1, loyal: 80, WarlordLook(hat: 4, beard: 3))
    p("张辽", 92, 78, 93, 60, .brave, 5, 0, loyal: 70, WarlordLook(hat: 1, beard: 5))
    p("李儒", 22, 92, 40, 65, .schemer, 5, 0, loyal: 95, WarlordLook(hat: 8, beard: 5))
    p("贾诩", 25, 97, 86, 80, .schemer, 5, 1, loyal: 70, WarlordLook(hat: 8, beard: 4))
    p("徐荣", 75, 65, 80, 40, nil, 5, 6, loyal: 85, WarlordLook(hat: 1))
    p("高顺", 85, 55, 84, 35, .iron, 5, 6, loyal: 75, WarlordLook(hat: 1, beard: 1))
    // 6 刘表 — 襄阳, 江陵, 江夏
    p("刘表", 48, 72, 60, 82, .scholar, 6, 19, loyal: 100, WarlordLook(hat: 3, beard: 4))
    p("蔡瑁", 68, 70, 76, 60, .navy, 6, 19, loyal: 85, WarlordLook(hat: 1, beard: 1))
    p("蒯越", 32, 88, 60, 80, nil, 6, 19, loyal: 85, WarlordLook(hat: 8, beard: 5))
    p("蒯良", 25, 89, 50, 82, nil, 6, 21, loyal: 90, WarlordLook(hat: 8, beard: 4))
    p("文聘", 83, 60, 82, 55, .iron, 6, 21, loyal: 90, WarlordLook(hat: 1, beard: 1))
    p("黄忠", 94, 60, 86, 48, .archer, 6, 21, loyal: 80, WarlordLook(hat: 1, beard: 4))
    p("黄祖", 68, 50, 70, 40, .navy, 6, 22, loyal: 90, WarlordLook(hat: 4, beard: 3))
    p("张允", 60, 50, 62, 40, .navy, 6, 22, loyal: 80)
    // 7 刘璋 — 成都, 梓潼, 江州, 永安
    p("刘璋", 30, 45, 40, 60, nil, 7, 35, loyal: 100, WarlordLook(hat: 3, beard: 1))
    p("张任", 85, 70, 86, 40, .archer, 7, 34, loyal: 100, WarlordLook(hat: 1, beard: 1))
    p("严颜", 83, 66, 84, 55, .archer, 7, 36, loyal: 90, WarlordLook(hat: 1, beard: 4))
    p("黄权", 50, 86, 70, 82, nil, 7, 35, loyal: 90, WarlordLook(hat: 8, beard: 5))
    p("李严", 85, 80, 85, 72, nil, 7, 35, loyal: 80, WarlordLook(hat: 1, beard: 5))
    p("吴懿", 75, 60, 76, 55, nil, 7, 37, loyal: 85)
    p("泠苞", 70, 40, 65, 30, nil, 7, 34, loyal: 85, WarlordLook(hat: 4))
    p("张松", 20, 85, 30, 75, nil, 7, 35, loyal: 50, WarlordLook(hat: 8, beard: 1))
    // 8 马腾 — 武威, 天水
    p("马腾", 85, 50, 80, 50, .cavalry, 8, 41, loyal: 100, WarlordLook(hat: 1, beard: 3))
    p("马超", 97, 45, 88, 30, .cavalry, 8, 41, loyal: 100, WarlordLook(coat: (0.9, 0.92, 0.96), hat: 1))
    p("马岱", 83, 58, 78, 45, .cavalry, 8, 40, loyal: 100, WarlordLook(hat: 1, beard: 1))
    p("庞德", 94, 60, 82, 40, .tiger, 8, 40, loyal: 95, WarlordLook(skin: dark, hat: 1, beard: 3))
    p("韩遂", 72, 72, 79, 60, .cavalry, 8, 41, loyal: 60, WarlordLook(hat: 4, beard: 4))
    p("马铁", 70, 30, 60, 25, .cavalry, 8, 41, loyal: 100)
    // 9 公孙瓒 — 北平
    p("公孙瓒", 84, 60, 82, 55, .cavalry, 9, 8, loyal: 100, WarlordLook(coat: (0.92, 0.93, 0.95), hat: 3, beard: 1))
    p("赵云", 96, 76, 91, 65, .brave, 9, 8, loyal: 75, WarlordLook(coat: (0.92, 0.94, 0.98), hat: 1))
    p("田楷", 60, 55, 65, 50, nil, 9, 8, loyal: 90, WarlordLook(hat: 1, beard: 1))
    p("严纲", 62, 40, 64, 30, .cavalry, 9, 8, loyal: 90)
    p("单经", 58, 40, 60, 35, nil, 9, 8, loyal: 85, WarlordLook(hat: 4, beard: 3))
    // 10 陶谦 — 下邳, 小沛, 广陵
    p("陶谦", 35, 62, 55, 70, .virtue, 10, 14, loyal: 100, WarlordLook(hat: 3, beard: 4))
    p("糜竺", 30, 72, 40, 82, .merchant, 10, 14, loyal: 85, WarlordLook(hat: 8, beard: 5))
    p("陈登", 66, 86, 80, 82, .farmer, 10, 15, loyal: 75, WarlordLook(hat: 8))
    p("曹豹", 60, 30, 58, 30, nil, 10, 13, loyal: 80, WarlordLook(hat: 1, beard: 3))
    p("臧霸", 83, 60, 80, 45, nil, 10, 13, loyal: 70, WarlordLook(hat: 4, beard: 3))
    p("陈珪", 20, 80, 30, 78, nil, 10, 15, loyal: 70, WarlordLook(hat: 7, beard: 4))
    p("孙乾", 30, 76, 25, 80, nil, 10, 14, loyal: 80, WarlordLook(hat: 8, beard: 5))
    // 11 孔融 — 北海
    p("孔融", 30, 76, 50, 82, .scholar, 11, 11, loyal: 100, WarlordLook(hat: 3, beard: 4))
    p("武安国", 80, 30, 60, 20, nil, 11, 11, loyal: 90, WarlordLook(hat: 4, beard: 3))
    p("王修", 40, 70, 50, 75, nil, 11, 11, loyal: 90, WarlordLook(hat: 8))
    // 12 张鲁 — 汉中
    p("张鲁", 30, 72, 60, 80, .virtue, 12, 33, loyal: 100, WarlordLook(accent: (0.95, 0.9, 0.7), hat: 7, beard: 4))
    p("张卫", 70, 40, 65, 30, nil, 12, 33, loyal: 95, WarlordLook(hat: 4))
    p("阎圃", 30, 80, 40, 75, nil, 12, 33, loyal: 90, WarlordLook(hat: 8, beard: 5))
    p("杨昂", 60, 30, 55, 25, nil, 12, 33, loyal: 80)
    // 13 公孙度 — 辽东
    p("公孙度", 70, 60, 72, 65, nil, 13, 12, loyal: 100, WarlordLook(hat: 3, beard: 3))
    p("公孙康", 68, 60, 70, 60, nil, 13, 12, loyal: 100, WarlordLook(hat: 1))
    p("柳毅", 60, 50, 60, 50, nil, 13, 12, loyal: 90)
    // 14 王朗 — 会稽
    p("王朗", 30, 75, 50, 80, .scholar, 14, 32, loyal: 100, WarlordLook(hat: 3, beard: 4))
    p("虞翻", 40, 88, 50, 78, nil, 14, 32, loyal: 85, WarlordLook(hat: 8, beard: 5))
    p("周昕", 60, 50, 60, 50, nil, 14, 32, loyal: 90, WarlordLook(hat: 1))
    // 15 士燮 — 南海
    p("士燮", 40, 75, 60, 85, .scholar, 15, 42, loyal: 100, WarlordLook(hat: 3, beard: 4))
    p("士徽", 55, 40, 50, 40, nil, 15, 42, loyal: 95, WarlordLook(hat: 9))
    p("士壹", 50, 50, 55, 60, nil, 15, 42, loyal: 95, WarlordLook(hat: 8, beard: 1))
    // 16 韩馥 — 邺
    p("韩馥", 40, 55, 55, 60, nil, 16, 5, loyal: 100, WarlordLook(hat: 3, beard: 5))
    p("张郃", 89, 69, 88, 57, .brave, 16, 5, loyal: 70, WarlordLook(hat: 1))
    p("沮授", 35, 93, 74, 82, nil, 16, 5, loyal: 80, WarlordLook(hat: 8, beard: 5))
    p("麴义", 85, 55, 83, 30, .archer, 16, 5, loyal: 60, WarlordLook(hat: 1, beard: 3))

    // Out in the world.
    p("典韦", 95, 35, 60, 25, .tiger, -1, 3, known: false, WarlordLook(skin: dark, hat: 4, beard: 3))
    p("许褚", 96, 36, 65, 20, .tiger, -1, 17, known: false, WarlordLook(hat: 0, beard: 1))
    p("荀彧", 30, 97, 60, 98, .scholar, -1, 2, WarlordLook(hat: 8, beard: 5))
    p("郭嘉", 15, 98, 62, 84, .schemer, -1, 2, appear: 194, known: false, WarlordLook(hat: 8))
    p("程昱", 45, 90, 74, 82, .schemer, -1, 4, known: false, WarlordLook(hat: 8, beard: 4))
    p("于禁", 80, 70, 85, 60, .iron, -1, 4, known: false, WarlordLook(hat: 1, beard: 1))
    p("徐晃", 90, 72, 84, 50, .brave, -1, 1, known: false, WarlordLook(hat: 1, beard: 3))
    p("司马懿", 63, 96, 98, 93, .schemer, -1, 0, appear: 201, known: false, WarlordLook(hat: 8, beard: 5))
    p("诸葛亮", 38, 100, 95, 97, .genius, -1, 19, appear: 197, known: false, WarlordLook(coat: (0.94, 0.94, 0.9), accent: (0.3, 0.46, 0.72), hat: 2, beard: 1, extra: 2))
    p("庞统", 34, 97, 80, 85, .schemer, -1, 21, appear: 198, known: false, WarlordLook(skin: (0.86, 0.7, 0.56), hat: 2, beard: 3))
    p("徐庶", 65, 92, 82, 80, .schemer, -1, 18, appear: 194, known: false, WarlordLook(hat: 2))
    p("魏延", 92, 58, 80, 40, .tiger, -1, 24, known: false, WarlordLook(skin: dark, hat: 1, beard: 3))
    p("周瑜", 71, 99, 97, 86, .fire, -1, 27, WarlordLook(coat: (0.86, 0.36, 0.22), hat: 0))
    p("鲁肃", 56, 94, 80, 90, nil, -1, 16, known: false, WarlordLook(hat: 8, beard: 5))
    p("张昭", 20, 85, 20, 97, .scholar, -1, 15, known: false, WarlordLook(hat: 7, beard: 4))
    p("吕蒙", 81, 89, 90, 78, .navy, -1, 17, appear: 196, known: false, WarlordLook(hat: 1, beard: 1))
    p("陆逊", 69, 98, 96, 87, .fire, -1, 31, appear: 200, known: false, WarlordLook(hat: 2))
    p("甘宁", 94, 68, 86, 30, .navy, -1, 36, known: false, WarlordLook(hat: 5, beard: 1))
    p("周泰", 91, 50, 75, 30, .navy, -1, 27, known: false, WarlordLook(skin: dark, hat: 4, beard: 3))
    p("太史慈", 93, 66, 84, 50, .archer, -1, 11, WarlordLook(hat: 1, beard: 1))
    p("华佗", 20, 80, 20, 60, .healer, -1, 13, known: false, WarlordLook(hat: 7, beard: 4))
    p("貂蝉", 26, 80, 30, 70, .beauty, -1, 0, known: false, WarlordLook(skin: (1, 0.87, 0.8), coat: (0.96, 0.6, 0.72), accent: (0.9, 0.3, 0.45), hat: 6))
    p("马良", 30, 90, 50, 85, nil, -1, 19, appear: 196, known: false, WarlordLook(hair: white, hat: 8))
    p("法正", 47, 94, 75, 78, .schemer, -1, 35, known: false, WarlordLook(hat: 8, beard: 5))
    p("孟获", 87, 40, 70, 30, .tiger, -1, 39, known: false, WarlordLook(skin: (0.66, 0.46, 0.32), hat: 9, beard: 3))
    p("陈宫", 40, 88, 72, 76, .schemer, -1, 4, WarlordLook(hat: 8, beard: 5))
    p("凌统", 88, 50, 76, 40, .navy, -1, 31, appear: 196, known: false, WarlordLook(hat: 1))
    p("姜维", 89, 90, 90, 70, .genius, -1, 40, appear: 205, known: false, WarlordLook(hat: 1))
    p("黄月英", 20, 92, 40, 80, .farmer, -1, 19, appear: 196, known: false, WarlordLook(skin: (1, 0.86, 0.76), coat: (0.5, 0.62, 0.4), accent: (0.9, 0.8, 0.3), hat: 6))
    p("邓艾", 85, 92, 92, 80, .farmer, -1, 17, appear: 208, known: false, WarlordLook(hat: 1, beard: 1))
    _ = grey
    return out
}()

let warlordIndex: [String: Int] = Dictionary(uniqueKeysWithValues: warlordPeople.enumerated().map { ($0.element.name, $0.offset) })

// MARK: - Treasures

struct WarlordItem {
    let name: String
    let war: Int, wit: Int, lead: Int, pol: Int
    /// A horse: two-month roads in one.
    let swift: Bool
    /// Held by somebody at the start, or hidden in a city.
    let holder: String?
    let city: Int?
    var says: String {
        var parts: [String] = []
        if war > 0 { parts.append("武力+\(war)") }
        if wit > 0 { parts.append("智力+\(wit)") }
        if lead > 0 { parts.append("统率+\(lead)") }
        if pol > 0 { parts.append("政治+\(pol)") }
        if swift { parts.append("远路一月到") }
        return parts.joined(separator: " ")
    }
}

let warlordItems: [WarlordItem] = [
    WarlordItem(name: "赤兔马", war: 3, wit: 0, lead: 2, pol: 0, swift: true, holder: "吕布", city: nil),
    WarlordItem(name: "倚天剑", war: 4, wit: 0, lead: 0, pol: 0, swift: false, holder: "曹操", city: nil),
    WarlordItem(name: "传国玉玺", war: 0, wit: 0, lead: 0, pol: 8, swift: false, holder: nil, city: 0),
    WarlordItem(name: "青釭剑", war: 5, wit: 0, lead: 0, pol: 0, swift: false, holder: nil, city: 2),
    WarlordItem(name: "孙子兵法", war: 0, wit: 2, lead: 6, pol: 0, swift: false, holder: nil, city: 31),
    WarlordItem(name: "太平要术", war: 0, wit: 6, lead: 0, pol: 2, swift: false, holder: nil, city: 9),
    WarlordItem(name: "的卢", war: 1, wit: 0, lead: 1, pol: 0, swift: true, holder: nil, city: 22),
    WarlordItem(name: "遁甲天书", war: 0, wit: 5, lead: 2, pol: 0, swift: false, holder: nil, city: 39),
]

// MARK: - Factions

struct WarlordBanner {
    let lord: String
    /// The character on the flag.
    let mark: String
    let colour: (Double, Double, Double)
    let cities: [Int]
    /// Who takes over when the lord falls, before anybody else.
    let heirs: [String]
}

let warlordBanners: [WarlordBanner] = [
    WarlordBanner(lord: "曹操", mark: "曹", colour: (0.2, 0.34, 0.72), cities: [3], heirs: ["夏侯惇", "曹仁"]),
    WarlordBanner(lord: "刘备", mark: "刘", colour: (0.16, 0.56, 0.3), cities: [10], heirs: ["关羽", "诸葛亮"]),
    WarlordBanner(lord: "孙坚", mark: "孙", colour: (0.84, 0.18, 0.16), cities: [24], heirs: ["孙策", "程普"]),
    WarlordBanner(lord: "袁绍", mark: "袁", colour: (0.9, 0.72, 0.14), cities: [9], heirs: ["审配"]),
    WarlordBanner(lord: "袁术", mark: "术", colour: (0.93, 0.52, 0.2), cities: [18, 17], heirs: ["纪灵"]),
    WarlordBanner(lord: "董卓", mark: "董", colour: (0.3, 0.26, 0.44), cities: [0, 1, 6], heirs: ["李傕", "吕布"]),
    WarlordBanner(lord: "刘表", mark: "表", colour: (0.14, 0.58, 0.62), cities: [19, 21, 22], heirs: ["蔡瑁", "蒯越"]),
    WarlordBanner(lord: "刘璋", mark: "璋", colour: (0.56, 0.3, 0.68), cities: [35, 34, 36, 37], heirs: ["黄权", "李严"]),
    WarlordBanner(lord: "马腾", mark: "马", colour: (0.5, 0.74, 0.92), cities: [41, 40], heirs: ["马超", "韩遂"]),
    WarlordBanner(lord: "公孙瓒", mark: "瓒", colour: (0.92, 0.92, 0.9), cities: [8], heirs: ["田楷"]),
    WarlordBanner(lord: "陶谦", mark: "陶", colour: (0.56, 0.62, 0.18), cities: [14, 13, 15], heirs: ["陈登", "糜竺"]),
    WarlordBanner(lord: "孔融", mark: "孔", colour: (0.92, 0.52, 0.66), cities: [11], heirs: []),
    WarlordBanner(lord: "张鲁", mark: "鲁", colour: (0.72, 0.22, 0.5), cities: [33], heirs: ["张卫"]),
    WarlordBanner(lord: "公孙度", mark: "度", colour: (0.52, 0.34, 0.2), cities: [12], heirs: ["公孙康"]),
    WarlordBanner(lord: "王朗", mark: "王", colour: (0.2, 0.42, 0.52), cities: [32], heirs: []),
    WarlordBanner(lord: "士燮", mark: "士", colour: (0.64, 0.8, 0.3), cities: [42], heirs: ["士壹"]),
    WarlordBanner(lord: "韩馥", mark: "韩", colour: (0.56, 0.12, 0.16), cities: [5], heirs: ["沮授"]),
]

let warlordNeutralColour = (0.64, 0.6, 0.52)

// MARK: - The state of the world

struct WarlordCity {
    /// The faction holding it, or −1 when it answers to nobody.
    var owner: Int
    var people: Int
    var gold: Int, grain: Int
    var troops: Int
    /// 0–100: drilled soldiers fight better.
    var train: Int
    var farm: Int, trade: Int, wall: Int
    /// 民忠, 0–100.
    var loyalty: Int
}

struct WarlordOfficer {
    enum State: Equatable { case serving, free, captive, dead, unborn }
    var state: State
    /// Their faction when serving; the captor's when a captive; −1 when free.
    var faction: Int
    var city: Int
    var loyalty: Int
    /// Has already had their command this month.
    var done = false
    /// On the road with an army.
    var army: Int? = nil
    var item: Int? = nil
    /// A free general somebody has found (or everybody knew of).
    var known = true
    var held = 0
    /// Months of rest still owed after a battle: an army that has fought needs a month before it marches again.
    var rest = 0
}

struct WarlordFaction {
    var alive = true
    var lord: Int
    /// Allies, with the months each alliance has left.
    var allies: [Int: Int] = [:]
    /// Months since it last broke an alliance (the others remember).
    var broke = 99
}

struct WarlordArmy {
    let id: Int
    let faction: Int
    let from: Int, to: Int
    var officers: [Int]
    var troops: Int
    var train: Int
    var left: Int
    let months: Int
}

/// A battle as it went, for its card.
struct WarlordBattle {
    let year: Int, month: Int
    let city: Int, from: Int
    let attacker: Int, defender: Int
    let attackers: [Int], defenders: [Int]
    let troopsA: Int, troopsD: Int
    var leftA: Int, leftD: Int
    let chance: Double
    var won: Bool
    var duel: (a: Int, b: Int, aWon: Bool, fate: String)?
    var captured: [Int] = []
    var fled: [Int] = []
    var killed: [Int] = []
    var surrendered = 0
    var road: WarlordRoadKind
}

struct WarlordNote {
    let year: Int, month: Int
    let faction: Int
    let text: String
    let city: Int?
}

/// Where everything came from and went, to show nothing is made or lost unaccounted.
struct WarlordLedger {
    var goldIn = 0, goldOut = 0, grainIn = 0, grainOut = 0, troopsIn = 0, troopsOut = 0
}

enum WarlordWork: Int, CaseIterable {
    case farm, trade, wall, draft, drill, search
    var name: String { ["开垦", "商业", "筑城", "征兵", "训练", "搜索"][rawValue] }
    var cost: Int { [50, 50, 60, 0, 0, 0][rawValue] }
}

struct WarlordWorld {
    let seed: UInt64
    private(set) var rng: UInt64
    var year = 190, month = 1
    var cities: [WarlordCity]
    var officers: [WarlordOfficer]
    var factions: [WarlordFaction]
    var armies: [WarlordArmy] = []
    var nextArmy = 1
    /// Where each treasure is: held by an officer, or hidden in a city.
    var itemHolder: [Int?]
    var itemCity: [Int?]
    /// The order the factions move in this month.
    var order: [Int] = []
    /// This month's battles, once the month has ended; the last ones stay until the next battles.
    var battles: [WarlordBattle] = []
    var chronicle: [WarlordNote] = []
    var ledger = WarlordLedger()
    var winner: Int?
    /// Months played.
    var turns = 0

    static let cityCount = warlordSites.count

    init(seed: UInt64) {
        self.seed = seed
        rng = seed &* 0x9E37_79B9_7F4A_7C15 ^ 0xD1B5_4A32_D192_ED03
        factions = warlordBanners.map { WarlordFaction(lord: warlordIndex[$0.lord]!) }
        cities = []
        var owners = Array(repeating: -1, count: Self.cityCount)
        for (f, b) in warlordBanners.enumerated() { for c in b.cities { owners[c] = f } }
        for (i, s) in warlordSites.enumerated() {
            let h = Double(Self.mixHash(Int(i), 7) % 1000) / 1000
            let owned = owners[i] >= 0
            let people = Int((Double(s.size) * 60_000 + h * 40_000).rounded(.down) / 1000) * 1000 + 20_000
            var troops = owned ? 4_000 + s.size * 2_000 + Int(h * 2_000) : 1_000 + s.size * 700 + Int(h * 800)
            if owners[i] == 5 { troops += 1_000 }              // 董卓 holds the capital's armies
            if [3, 9, 18].contains(owners[i]) { troops += 2_000 }
            troops = troops / 100 * 100
            cities.append(WarlordCity(owner: owners[i], people: people, gold: owned ? 400 + s.size * 150 : 150 + s.size * 50,
                                      grain: owned ? 6_000 + s.size * 3_000 : 2_000 + s.size * 1_000, troops: troops, train: owned ? 45 + Int(h * 20) : 30,
                                      farm: 18 + s.size * 6 + Int(h * 10), trade: 14 + s.size * 6 + Int(h * 12), wall: 20 + s.size * 8 + Int(h * 15), loyalty: 55 + Int(h * 20)))
        }
        officers = warlordPeople.map { p in
            var o = WarlordOfficer(state: p.faction >= 0 ? .serving : (p.appear > 190 ? .unborn : .free), faction: p.faction, city: p.city, loyalty: p.loyalty)
            o.known = p.faction >= 0 || p.known
            return o
        }
        itemHolder = warlordItems.map { $0.holder.flatMap { warlordIndex[$0] } }
        itemCity = warlordItems.map { $0.city }
        for (i, h) in itemHolder.enumerated() { if let h { officers[h].item = i } }
        beginMonth()
    }

    static func mixHash(_ a: Int, _ b: Int) -> Int {
        var x = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663))
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
        return Int(x % 1_000_000)
    }

    /// The seeded dice: every chance in the game is rolled here, in order.
    mutating func random() -> Double {
        rng = rng &+ 0x9E37_79B9_7F4A_7C15
        var z = rng
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
    mutating func roll(_ n: Int) -> Int { min(n - 1, Int(random() * Double(n))) }

    // MARK: Reading the world

    var season: String { ["", "春", "春", "春", "夏", "夏", "夏", "秋", "秋", "秋", "冬", "冬", "冬"][month] }
    var date: String { "\(year)年 \(month)月" }
    var over: Bool { winner != nil || factions.allSatisfy { !$0.alive } }

    func person(_ o: Int) -> WarlordPerson { warlordPeople[o] }
    func name(_ o: Int) -> String { warlordPeople[o].name }
    func lordName(_ f: Int) -> String { f < 0 ? "空城" : name(factions[f].lord) }
    func banner(_ f: Int) -> String { f < 0 ? "无主" : lordName(f) + "军" }

    private func bonus(_ o: Int) -> WarlordItem? { officers[o].item.map { warlordItems[$0] } }
    func war(_ o: Int) -> Int { min(110, warlordPeople[o].war + (bonus(o)?.war ?? 0)) }
    func wit(_ o: Int) -> Int { min(110, warlordPeople[o].wit + (bonus(o)?.wit ?? 0)) }
    func lead(_ o: Int) -> Int { min(110, warlordPeople[o].lead + (bonus(o)?.lead ?? 0)) }
    func pol(_ o: Int) -> Int { min(110, warlordPeople[o].pol + (bonus(o)?.pol ?? 0)) }
    func has(_ o: Int, _ s: WarlordSkill) -> Bool { warlordPeople[o].skill == s }

    func cities(of f: Int) -> [Int] { cities.indices.filter { cities[$0].owner == f } }
    /// Generals serving a faction (at home or on the road).
    func staff(of f: Int) -> [Int] { officers.indices.filter { officers[$0].state == .serving && officers[$0].faction == f } }
    /// Generals at home in a city, serving whoever holds it.
    func present(_ c: Int) -> [Int] {
        let f = cities[c].owner
        return officers.indices.filter { officers[$0].state == .serving && officers[$0].city == c && officers[$0].army == nil && officers[$0].faction == f && f >= 0 }
    }
    func idle(_ c: Int) -> [Int] { present(c).filter { !officers[$0].done } }
    func captives(_ c: Int) -> [Int] { officers.indices.filter { officers[$0].state == .captive && officers[$0].city == c } }
    /// Free generals known to be in a city, and ready to be asked.
    func freeKnown(_ c: Int) -> [Int] { officers.indices.filter { officers[$0].state == .free && officers[$0].city == c && officers[$0].known } }
    func troops(of f: Int) -> Int { cities(of: f).reduce(0) { $0 + cities[$1].troops } + armies.filter { $0.faction == f }.reduce(0) { $0 + $1.troops } }
    func gold(of f: Int) -> Int { cities(of: f).reduce(0) { $0 + cities[$1].gold } }
    func grain(of f: Int) -> Int { cities(of: f).reduce(0) { $0 + cities[$1].grain } }
    func allied(_ a: Int, _ b: Int) -> Bool { a >= 0 && b >= 0 && factions[a].allies[b] != nil }
    /// Neighbours of a city held by somebody else who is not an ally.
    func foes(of c: Int) -> [Int] {
        let f = cities[c].owner
        return warlordLinks[c].map(\.city).filter { cities[$0].owner != f && !allied(f, cities[$0].owner) }
    }
    func frontier(_ c: Int) -> Bool { warlordLinks[c].contains { cities[$0.city].owner >= 0 && cities[$0.city].owner != cities[c].owner && !allied(cities[c].owner, cities[$0.city].owner) } }
    /// Enemy troops that could fall on a city next month: what the hostile neighbours hold, and armies already on the way.
    func threat(to c: Int) -> Int {
        let f = cities[c].owner
        var t = 0
        for n in warlordLinks[c].map(\.city) {
            let o = cities[n].owner
            if o >= 0, o != f, !allied(f, o) { t += cities[n].troops * 7 / 10 }
        }
        for a in armies where a.to == c && a.faction != f { t += a.troops }
        return t
    }
    /// The faction's strength, for measuring one against another.
    func strength(_ f: Int) -> Int { troops(of: f) + cities(of: f).count * 3_000 + staff(of: f).count * 800 }
    func held(_ f: Int) -> Int { cities(of: f).count }
    /// A faction holding more than a quarter of the realm, whom the rest learn to fear.
    var giant: Int? {
        var counts = Array(repeating: 0, count: factions.count)
        for c in cities where c.owner >= 0 { counts[c.owner] += 1 }
        guard let top = counts.indices.max(by: { (counts[$0], -$0) < (counts[$1], -$1) }) else { return nil }
        return counts[top] * 4 > cities.count && counts[top] * 10 < cities.count * 9 ? top : nil
    }

    // MARK: Battles, measured

    /// A side's fighting power: soldiers, drilled, led by their best.
    func power(_ team: [Int], troops: Int, train: Int, attacking: Bool, road: WarlordRoadKind, city: Int) -> Double {
        let best = { (f: (Int) -> Int) -> Double in Double(team.map(f).max() ?? 42) }
        let L = best(lead), W = best(war), I = best(wit)
        var p = Double(troops) * (0.55 + L / 100 * 0.55) * (0.8 + W / 100 * 0.3) * (0.9 + I / 100 * 0.2) * (0.6 + Double(train) / 100 * 0.5)
        var skill = 1.0
        for o in team {
            guard let s = warlordPeople[o].skill else { continue }
            var m = 1.0
            switch s {
            case .peerless: m = 1.35
            case .saint: m = 1.25
            case .tiger: m = 1.12
            case .brave: m = 1.18
            case .genius: m = 1.2
            case .schemer: m = 1.12
            case .fire: m = road == .river ? 1.4 : 1.15
            case .hero: m = 1.1
            case .cavalry: m = road == .plain ? 1.25 : 1
            case .navy: m = road == .river ? 1.2 : 1
            case .iron: m = attacking ? 1 : 1.3
            case .swift: m = 1.08
            case .archer: m = 1.15
            default: m = 1
            }
            skill = max(skill, m)
        }
        p *= skill
        if attacking {
            if [12, 1, 2].contains(month), warlordSites[city].lat > 33 { p *= 0.9 }        // a winter march in the north
            if road == .river, !team.contains(where: { has($0, .navy) || has($0, .fire) }) { p /= 1.2 }
            if road == .pass { p /= 1.3 }
        } else {
            p *= 1.15 * (1 + Double(cities[city].wall) / 100 * 0.5)
        }
        return max(1, p)
    }

    /// Who defends a city: its generals at home (the best three), its soldiers.
    func defenders(_ c: Int) -> [Int] {
        Array(present(c).sorted { lead($0) + war($0) > lead($1) + war($1) }.prefix(3))
    }

    static func odds(_ ratio: Double) -> Double { 1 / (1 + pow(1 / max(ratio, 0.01), 4.5)) }

    /// The chance an army wins at a city, as the forecast says it.
    func chance(_ team: [Int], troops: Int, train: Int, from: Int, to: Int) -> Double {
        guard let road = warlordRoad(from, to) else { return 0 }
        let a = power(team, troops: troops, train: train, attacking: true, road: road.kind, city: to)
        let d = power(defenders(to), troops: cities[to].troops + cities[to].people / 400, train: cities[to].train, attacking: false, road: road.kind, city: to)
        return Self.odds(a / d)
    }

    /// Soldiers to send for a chance, at most what can be spared; nil when even that is not enough.
    func needed(_ team: [Int], from: Int, to: Int, want p: Double, spare: Int) -> Int? {
        guard spare >= 500 else { return nil }
        let train = cities[from].train
        if chance(team, troops: spare, train: train, from: from, to: to) < p { return nil }
        var lo = 500, hi = spare
        while hi - lo > 250 {
            let mid = (lo + hi) / 2
            if chance(team, troops: mid, train: train, from: from, to: to) >= p { hi = mid } else { lo = mid }
        }
        return (hi + 99) / 100 * 100
    }

    // MARK: Commands

    mutating func note(_ f: Int, _ text: String, _ c: Int? = nil) {
        chronicle.append(WarlordNote(year: year, month: month, faction: f, text: text, city: c))
        if chronicle.count > 400 { chronicle.removeFirst(chronicle.count - 400) }
    }

    /// Can this general take a command now?
    func ready(_ o: Int) -> Bool {
        let x = officers[o]
        return x.state == .serving && x.army == nil && !x.done && cities[x.city].owner == x.faction
    }

    /// 开垦 商业 筑城 征兵 训练 搜索, by a general in their city. Returns what happened, or nil when it cannot be done.
    @discardableResult
    mutating func work(_ o: Int, _ kind: WarlordWork) -> String? {
        guard ready(o) else { return nil }
        let c = officers[o].city
        var city = cities[c]
        let scholar = has(o, .scholar) ? 1.5 : 1.0
        var said: String
        switch kind {
        case .farm, .trade, .wall:
            guard city.gold >= kind.cost else { return nil }
            let level = kind == .farm ? city.farm : kind == .trade ? city.trade : city.wall
            guard level < 100 else { return nil }
            let skill = kind == .farm ? pol(o) : kind == .trade ? pol(o) : lead(o)
            // Each point is harder won than the last.
            var gain = (2.0 + Double(skill) / 16 + random() * 2) * scholar * max(0.3, 1.15 - Double(level) / 100)
            if kind == .farm, has(o, .farmer) { gain *= 2 }
            if kind == .trade, has(o, .merchant) { gain *= 2 }
            let up = min(100 - level, max(1, Int(gain.rounded())))
            city.gold -= kind.cost; ledger.goldOut += kind.cost
            if kind == .farm { city.farm += up } else if kind == .trade { city.trade += up } else { city.wall += up }
            city.loyalty = min(100, city.loyalty + (kind == .wall ? 0 : 1))
            said = "\(name(o))在\(warlordSites[c].name)\(kind.name)：\(kind == .farm ? "农业" : kind == .trade ? "商业" : "城防") +\(up)"
        case .draft:
            let n = draftSize(o)
            guard n >= 300 else { return nil }
            let cost = n / 10
            city.gold -= cost; ledger.goldOut += cost
            city.people -= n
            city.train = (city.train * city.troops + 25 * n) / max(1, city.troops + n)
            city.troops += n; ledger.troopsIn += n
            city.loyalty = max(0, city.loyalty - 4)
            said = "\(name(o))在\(warlordSites[c].name)征兵 \(n)"
        case .drill:
            guard city.train < 100, city.troops > 0 else { return nil }
            let up = min(100 - city.train, 5 + lead(o) / 12)
            city.train += up
            said = "\(name(o))在\(warlordSites[c].name)训练：训练 +\(up)"
        case .search:
            cities[c] = city
            said = search(o, c)
            city = cities[c]
        }
        cities[c] = city
        officers[o].done = true
        return said
    }

    /// Soldiers a general can raise in their city this month.
    func draftSize(_ o: Int) -> Int {
        let c = officers[o].city, city = cities[c]
        var n = Double(1_000 + lead(o) * 20) * (has(o, .noble) ? 1.3 : 1)
        n = min(n, Double(city.people) / 25, Double(city.gold * 10))
        return Int(n) / 100 * 100
    }

    private mutating func search(_ o: Int, _ c: Int) -> String {
        let hidden = officers.indices.filter { officers[$0].state == .free && officers[$0].city == c && !officers[$0].known }
        if let h = hidden.first, random() < 0.3 + Double(wit(o)) / 300 {
            officers[h].known = true
            return "\(name(o))在\(warlordSites[c].name)寻得人才：\(name(h))"
        }
        if let item = itemCity.indices.first(where: { itemCity[$0] == c }), random() < 0.18 + Double(wit(o)) / 400 {
            itemCity[item] = nil
            give(item, to: o)
            return "\(name(o))在\(warlordSites[c].name)寻得宝物：\(warlordItems[item].name)"
        }
        if random() < 0.35 {
            let g = 40 + roll(80)
            cities[c].gold += g; ledger.goldIn += g
            return "\(name(o))在\(warlordSites[c].name)搜索，得金 \(g)"
        }
        return "\(name(o))在\(warlordSites[c].name)搜索，一无所获"
    }

    private mutating func give(_ item: Int, to o: Int) {
        // A general carries one treasure; the lesser goes to the lord.
        if let old = officers[o].item {
            let lord = factions[max(0, officers[o].faction)].lord
            if officers[o].faction >= 0, lord != o, officers[lord].item == nil { officers[lord].item = old; itemHolder[old] = lord }
            else { itemCity[old] = officers[o].city; itemHolder[old] = nil }
        }
        officers[o].item = item; itemHolder[item] = o
    }

    /// The chance a general wins another over: a free one, or a captive.
    func recruitChance(_ o: Int, _ t: Int) -> Double {
        let x = officers[t]
        var p = 0.3 + Double(pol(o) + wit(o)) / 500
        if has(o, .hero) { p += 0.25 }
        if has(o, .virtue) { p += 0.2 }
        if has(o, .noble) { p += 0.15 }
        if has(o, .scholar) { p += 0.1 }
        let lord = factions[officers[o].faction].lord
        if has(lord, .hero) || has(lord, .virtue) { p += 0.1 }
        if warlordPeople[t].total > 330 { p -= 0.15 }
        if x.state == .captive {
            let theirs = lastFaction[t] ?? warlordPeople[t].faction
            let former = factions.indices.contains(theirs) ? factions[theirs] : nil
            p -= Double(x.loyalty) / 160
            if former?.alive == false { p += 0.3 }
            if former?.lord == t { p -= 0.5 }
            if x.held > 0 { p += 0.08 * Double(x.held) }
        }
        return max(0.02, min(0.95, p))
    }

    /// 登用: ask a free general in the city, or a captive held there.
    @discardableResult
    mutating func recruit(_ o: Int, _ t: Int) -> Bool? {
        guard ready(o), officers[t].city == officers[o].city,
              (officers[t].state == .free && officers[t].known) || (officers[t].state == .captive && officers[t].faction == officers[o].faction) else { return nil }
        let p = recruitChance(o, t), f = officers[o].faction, c = officers[o].city
        officers[o].done = true
        if random() < p {
            officers[t].state = .serving; officers[t].faction = f; officers[t].loyalty = 65 + roll(25); officers[t].done = true; officers[t].held = 0
            note(f, "\(name(t))投效\(lordName(f))", c)
            return true
        }
        if officers[t].state == .captive { officers[t].held += 1 }
        return false
    }

    /// Let a captive go: home to their lord if the lord still stands, or out into the world.
    mutating func release(_ t: Int) {
        guard officers[t].state == .captive else { return }
        let captor = officers[t].faction, home = warlordPeople[t].faction
        let lordOf = factions.indices.first { factions[$0].alive && staffed(t, $0) }
        if let g = lordOf, let back = nearest(of: g, to: officers[t].city) {
            officers[t].state = .serving; officers[t].faction = g; officers[t].city = back
            officers[t].loyalty = min(100, officers[t].loyalty + 5)
        } else {
            officers[t].state = .free; officers[t].faction = -1; officers[t].known = true
        }
        officers[t].held = 0
        _ = home
        note(captor, "释放了\(name(t))", officers[t].city)
    }
    /// Which faction a captive last served (kept in `lastFaction`).
    private func staffed(_ t: Int, _ f: Int) -> Bool { lastFaction[t] == f }
    var lastFaction: [Int: Int] = [:]

    mutating func execute(_ t: Int) {
        guard officers[t].state == .captive else { return }
        let captor = officers[t].faction
        drop(t)
        officers[t].state = .dead
        note(captor, "斩了\(name(t))", officers[t].city)
    }

    /// A general leaves the world or changes hands: their treasure goes to the lord who holds them, or stays in the city.
    private mutating func drop(_ t: Int) {
        guard let item = officers[t].item else { return }
        officers[t].item = nil; itemHolder[item] = nil
        let f = officers[t].faction
        if f >= 0, factions[f].alive, officers[factions[f].lord].item == nil, factions[f].lord != t { give(item, to: factions[f].lord) }
        else { itemCity[item] = officers[t].city }
    }

    func nearest(of f: Int, to c: Int) -> Int? {
        var seen: Set<Int> = [c], frontier = [c]
        while !frontier.isEmpty {
            var next: [Int] = []
            for x in frontier {
                if cities[x].owner == f { return x }
                for n in warlordLinks[x].map(\.city) where !seen.contains(n) { seen.insert(n); next.append(n) }
            }
            frontier = next
        }
        return nil
    }

    /// 移动 (the general goes, taking what they carry) or 运输 (the goods go, the general stays): to a neighbouring city of one's own.
    @discardableResult
    mutating func move(_ o: Int, to d: Int, troops: Int = 0, gold: Int = 0, grain: Int = 0, stay: Bool = true) -> Bool {
        guard ready(o) else { return false }
        let c = officers[o].city, f = officers[o].faction
        guard c != d, cities[d].owner == f, warlordRoad(c, d) != nil else { return false }
        let t = max(0, min(troops, cities[c].troops)), g = max(0, min(gold, cities[c].gold)), r = max(0, min(grain, cities[c].grain))
        if t > 0 {
            cities[d].train = (cities[d].train * cities[d].troops + cities[c].train * t) / max(1, cities[d].troops + t)
        }
        cities[c].troops -= t; cities[d].troops += t
        cities[c].gold -= g; cities[d].gold += g
        cities[c].grain -= r; cities[d].grain += r
        officers[o].done = true
        if stay { officers[o].city = d }
        return true
    }

    /// 出征: generals lead soldiers from their city down the road to a neighbour not their own. Returns the army's id.
    @discardableResult
    mutating func march(_ team: [Int], from c: Int, to d: Int, troops n: Int) -> Int? {
        guard let lead0 = team.first, let road = warlordRoad(c, d) else { return nil }
        let f = officers[lead0].faction
        guard cities[c].owner == f, cities[d].owner != f, !allied(f, cities[d].owner), team.allSatisfy({ ready($0) && officers[$0].rest == 0 && officers[$0].city == c && officers[$0].faction == f }),
              n >= 300, n <= cities[c].troops, !armies.contains(where: { $0.faction == f && $0.to == d }) else { return nil }
        let months = road.months > 1 && team.contains(where: { has($0, .swift) || bonus($0)?.swift == true }) ? 1 : road.months
        let rations = n / 10 * months
        guard cities[c].grain >= rations else { return nil }
        cities[c].grain -= rations; ledger.grainOut += rations
        cities[c].troops -= n
        let id = nextArmy
        nextArmy += 1
        armies.append(WarlordArmy(id: id, faction: f, from: c, to: d, officers: team, troops: n, train: cities[c].train, left: months, months: months))
        for o in team { officers[o].army = id; officers[o].done = true }
        note(f, "\(name(lead0))率兵 \(n) 自\(warlordSites[c].name)出征\(warlordSites[d].name)", c)
        return id
    }

    // MARK: Diplomacy

    func allyChance(_ o: Int, with g: Int) -> Double {
        let f = officers[o].faction
        guard f != g, factions[g].alive, !allied(f, g) else { return 0 }
        var p = 0.2 + Double(wit(o) + pol(o)) / 600
        let common = commonFoes(f, g)
        if !common.isEmpty { p += 0.25 }
        if strength(g) < strength(f) { p += 0.1 }
        if bordering(f, g) { p -= 0.1 }
        if factions[f].broke < 24 { p -= 0.25 }
        // Everybody fears the one who is swallowing the realm.
        if let giant = giant, giant != f, giant != g, bordering(g, giant) { p += 0.2 }
        return max(0.03, min(0.9, p))
    }
    func bordering(_ f: Int, _ g: Int) -> Bool { cities(of: f).contains { c in warlordLinks[c].contains { cities[$0.city].owner == g } } }
    /// Factions both border.
    func commonFoes(_ f: Int, _ g: Int) -> [Int] {
        factions.indices.filter { $0 != f && $0 != g && factions[$0].alive && bordering(f, $0) && bordering(g, $0) && !allied(f, $0) && !allied(g, $0) }
    }
    static let allyCost = 200

    /// 同盟: a gift and an envoy; three years of peace if they agree.
    @discardableResult
    mutating func ally(_ o: Int, with g: Int) -> Bool? {
        guard ready(o), cities[officers[o].city].gold >= Self.allyCost else { return nil }
        let f = officers[o].faction
        let p = allyChance(o, with: g)
        guard p > 0 else { return nil }
        officers[o].done = true
        cities[officers[o].city].gold -= Self.allyCost; ledger.goldOut += Self.allyCost
        if random() < p {
            factions[f].allies[g] = 36; factions[g].allies[f] = 36
            note(f, "\(lordName(f))与\(lordName(g))结盟", nil)
            return true
        }
        note(f, "\(lordName(g))拒绝了\(lordName(f))的结盟", nil)
        return false
    }

    mutating func breakAlliance(_ f: Int, _ g: Int) {
        guard allied(f, g) else { return }
        factions[f].allies[g] = nil; factions[g].allies[f] = nil
        factions[f].broke = 0
        note(f, "\(lordName(f))背弃了与\(lordName(g))的盟约", nil)
    }

    /// Enemy generals within reach of a city: in the neighbouring cities, serving someone else.
    func reachable(from c: Int) -> [Int] {
        let f = cities[c].owner
        let near = Set(warlordLinks[c].map(\.city))
        return officers.indices.filter { officers[$0].state == .serving && officers[$0].army == nil && near.contains(officers[$0].city) && officers[$0].faction != f && officers[$0].faction >= 0 }
    }

    func sowChance(_ o: Int, _ t: Int) -> Double {
        guard factions[officers[t].faction].lord != t else { return 0 }
        var p = 0.3 + Double(wit(o) - wit(t)) / 150
        if has(o, .genius) { p += 0.25 }
        if has(o, .schemer) { p += 0.2 }
        if has(o, .beauty) { p += 0.4 }
        p -= Double(officers[t].loyalty - 70) / 100
        return max(0.03, min(0.9, p))
    }

    /// 离间: a rumour to turn an enemy general against their lord.
    @discardableResult
    mutating func sow(_ o: Int, _ t: Int) -> Int? {
        guard ready(o), reachable(from: officers[o].city).contains(t), sowChance(o, t) > 0 else { return nil }
        let p = sowChance(o, t)
        officers[o].done = true
        if random() < p {
            let drop = 8 + roll(14)
            officers[t].loyalty = max(0, officers[t].loyalty - drop)
            note(officers[o].faction, "\(name(o))离间\(name(t))：忠诚 −\(drop)", officers[t].city)
            return drop
        }
        return 0
    }

    func persuadeChance(_ o: Int, _ t: Int) -> Double {
        let g = officers[t].faction, f = officers[o].faction
        guard g >= 0, g != f else { return 0 }
        if factions[g].lord == t {
            // A lord gives up only with one city left and no fight in them: never a 曹操 or a 孙坚.
            let theirs = strength(g), ours = strength(f)
            guard held(g) == 1, ours > theirs * 6, war(t) + lead(t) < 130, ![.hero, .virtue, .brave, .noble].contains(warlordPeople[t].skill) else { return 0 }
            return max(0.03, min(0.35, 0.05 + Double(wit(o)) / 500 + Double(ours) / Double(max(1, theirs)) / 100))
        }
        guard officers[t].loyalty < 80 else { return 0.0 }
        var p = Double(80 - officers[t].loyalty) / 80 * 0.8 + Double(wit(o) - wit(t)) / 300
        if has(o, .genius) { p += 0.25 }
        if has(o, .schemer) { p += 0.2 }
        let lord = factions[f].lord
        if has(lord, .virtue) || has(lord, .hero) { p += 0.1 }
        return max(0.02, min(0.9, p))
    }

    /// 劝降: talk an enemy general into coming over — or a beaten lord into giving everything up.
    @discardableResult
    mutating func persuade(_ o: Int, _ t: Int) -> Bool? {
        guard ready(o), reachable(from: officers[o].city).contains(t) else { return nil }
        let p = persuadeChance(o, t)
        guard p > 0 else { return nil }
        let f = officers[o].faction, g = officers[t].faction
        officers[o].done = true
        guard random() < p else { return false }
        if factions[g].lord == t {
            for c in cities(of: g) { cities[c].owner = f }
            for x in staff(of: g) { officers[x].faction = f; officers[x].loyalty = 60 + roll(25) }
            for i in armies.indices where armies[i].faction == g { armies[i] = WarlordArmy(id: armies[i].id, faction: f, from: armies[i].from, to: armies[i].to, officers: armies[i].officers, troops: armies[i].troops, train: armies[i].train, left: armies[i].left, months: armies[i].months) }
            for x in officers.indices where officers[x].state == .captive && officers[x].faction == g { officers[x].faction = f }
            factions[g].alive = false; factions[g].allies = [:]
            for h in factions.indices { factions[h].allies[g] = nil }
            note(f, "\(lordName(g))率众归降\(lordName(f))", nil)
            return true
        }
        officers[t].faction = f; officers[t].city = officers[o].city; officers[t].loyalty = 55 + roll(20); officers[t].done = true
        note(f, "\(name(t))被\(name(o))说动，投奔\(lordName(f))", officers[o].city)
        return true
    }

    // MARK: The month

    /// Everybody's commands are fresh; the order of the factions is drawn.
    mutating func beginMonth() {
        for i in officers.indices { officers[i].done = false; if officers[i].rest > 0 { officers[i].rest -= 1 } }
        var alive = factions.indices.filter { factions[$0].alive }
        for i in stride(from: alive.count - 1, to: 0, by: -1) { alive.swapAt(i, roll(i + 1)) }
        order = alive
    }

    /// The month ends: armies arrive and fight, the treasuries fill, autumn's harvest comes in, people eat.
    mutating func endMonth() {
        battles = []
        var arriving: [WarlordArmy] = []
        var marching: [WarlordArmy] = []
        for var a in armies {
            a.left -= 1
            if a.left <= 0 { arriving.append(a) } else { marching.append(a) }
        }
        armies = marching
        for a in arriving { arrive(a) }
        economy()
        loyalties()
        for i in officers.indices where officers[i].state == .unborn && warlordPeople[i].appear <= year { officers[i].state = .free }
        for f in factions.indices where factions[f].alive {
            factions[f].broke += 1
            for g in factions[f].allies.keys.sorted() {
                let left = factions[f].allies[g] ?? 0
                if left <= 1 || !factions[g].alive { factions[f].allies[g] = nil; if factions[g].alive, f < g { note(f, "\(lordName(f))与\(lordName(g))的盟约到期", nil) } }
                else { factions[f].allies[g] = left - 1 }
            }
        }
        census()
        turns += 1
        month += 1
        if month > 12 { month = 1; year += 1 }
        beginMonth()
    }

    private mutating func arrive(_ a: WarlordArmy) {
        let d = a.to, f = a.faction
        guard factions[f].alive else { disband(a); return }
        let team = a.officers.filter { officers[$0].state == .serving && officers[$0].faction == f }
        if cities[d].owner == f {
            join(a, team, at: d)
            return
        }
        if allied(f, cities[d].owner) { retreat(a, team, troops: a.troops); return }
        fight(a, team)
    }

    private mutating func join(_ a: WarlordArmy, _ team: [Int], at d: Int) {
        cities[d].train = (cities[d].train * cities[d].troops + a.train * a.troops) / max(1, cities[d].troops + a.troops)
        cities[d].troops += a.troops
        for o in team { officers[o].army = nil; officers[o].city = d }
    }

    /// Back the way it came, or to the nearest city of its own; with nowhere to go it breaks up.
    private mutating func retreat(_ a: WarlordArmy, _ team: [Int], troops: Int) {
        let home = cities[a.from].owner == a.faction ? a.from : nearest(of: a.faction, to: a.from)
        guard let home else {
            ledger.troopsOut += troops
            for o in team { officers[o].army = nil; officers[o].state = .free; officers[o].faction = -1; officers[o].city = a.from; drop(o) }
            return
        }
        cities[home].troops += troops
        for o in team { officers[o].army = nil; officers[o].city = home }
    }

    private mutating func disband(_ a: WarlordArmy) {
        ledger.troopsOut += a.troops
        for o in a.officers where officers[o].army == a.id { officers[o].army = nil; if officers[o].state == .serving { officers[o].state = .free; officers[o].faction = -1; officers[o].city = a.from } }
    }

    private mutating func fight(_ a: WarlordArmy, _ team: [Int]) {
        let d = a.to, f = a.faction, g = cities[d].owner
        for o in team { officers[o].rest = 2 }
        let road = warlordRoad(a.from, d)?.kind ?? .plain
        let guards = defenders(d)
        let militia = cities[d].people / 400
        let defending = cities[d].troops + militia
        var pa = power(team, troops: a.troops, train: a.train, attacking: true, road: road, city: d)
        var pd = power(guards, troops: defending, train: cities[d].train, attacking: false, road: road, city: d)
        let forecast = Self.odds(pa / pd)
        var b = WarlordBattle(year: year, month: month, city: d, from: a.from, attacker: f, defender: g, attackers: team, defenders: guards,
                              troopsA: a.troops, troopsD: cities[d].troops, leftA: a.troops, leftD: cities[d].troops, chance: forecast, won: false, road: road)
        // Now and then the two best fighters meet between the lines.
        if let x = team.max(by: { war($0) < war($1) }), let y = guards.max(by: { war($0) < war($1) }) {
            let fierce = [x, y].contains { war($0) >= 90 }
            if random() < (fierce ? 0.34 : 0.18) {
                func edge(_ o: Int) -> Double { has(o, .peerless) ? 10 : has(o, .brave) ? 8 : (has(o, .tiger) || has(o, .saint)) ? 6 : 0 }
                let pw = 1 / (1 + exp(-(Double(war(x) - war(y)) + edge(x) - edge(y)) / 6))
                let aWon = random() < pw
                let loser = aWon ? y : x
                var fate = "负伤退走"
                let r = random()
                let isLord = officers[loser].faction >= 0 && factions[officers[loser].faction].lord == loser
                if r < (isLord ? 0.05 : 0.1) {
                    fate = "被斩于马下"
                    kill(loser)
                    b.killed.append(loser)
                } else if r < 0.3 {
                    fate = "被生擒"
                    capture(loser, by: aWon ? f : g, at: d, heldIn: aWon ? a.from : d)
                    b.captured.append(loser)
                }
                b.duel = (x, y, aWon, fate)
                if aWon { pa *= 1.2 } else { pd *= 1.2 }
            }
        }
        let ratio = pa / pd
        let won = random() < Self.odds(ratio)
        b.won = won
        let luck = 0.8 + random() * 0.4
        let healer = team.contains { has($0, .healer) } ? 0.7 : 1.0
        if won {
            let lost = min(a.troops - 100, Int(Double(a.troops) * min(0.5, max(0.04, 0.26 / ratio)) * luck * healer))
            let before = cities[d].troops
            let joined = before / 10
            ledger.troopsOut += lost + (before - joined)
            b.leftA = a.troops - lost + joined
            b.leftD = 0
            b.surrendered = joined
            // The defenders flee to a city of their own nearby, or are taken.
            for o in guards + present(d).filter({ !guards.contains($0) }) where officers[o].state == .serving {
                let escape = warlordLinks[d].map(\.city).first { cities[$0].owner == g && g >= 0 }
                let lord = g >= 0 && factions[g].lord == o
                if let escape, random() < (lord ? 0.65 : 0.4) + Double(wit(o)) / 300 {
                    officers[o].city = escape
                    b.fled.append(o)
                } else {
                    capture(o, by: f, at: d, heldIn: d)
                    b.captured.append(o)
                }
            }
            let prize = cities[d]
            cities[d].owner = f
            cities[d].troops = a.troops - lost + joined
            cities[d].train = max(20, a.train - 15)
            cities[d].loyalty = max(10, prize.loyalty - 15)
            cities[d].wall = max(5, prize.wall - 8)
            for o in team where officers[o].state == .serving && officers[o].faction == f { officers[o].army = nil; officers[o].city = d }
            // Prisoners the old masters kept here go free: ours come home, the rest go their way.
            for o in captives(d) where officers[o].faction == g {
                if lastFaction[o] == f { officers[o].state = .serving; officers[o].faction = f }
                else { officers[o].state = .free; officers[o].faction = -1; officers[o].known = true }
                officers[o].held = 0
            }
            note(f, "\(banner(f))攻克\(warlordSites[d].name)" + (g >= 0 ? "（\(banner(g))败走）" : ""), d)
            if g >= 0 { settleLord(g) }
        } else {
            let lost = min(a.troops, Int(Double(a.troops) * min(0.8, max(0.2, 0.3 / ratio + 0.15)) * luck * healer))
            let hurt = min(cities[d].troops, Int(Double(cities[d].troops) * min(0.5, max(0.04, 0.22 * ratio)) * luck))
            cities[d].wall = max(5, cities[d].wall - 2 - roll(5))          // the siege leaves its mark
            ledger.troopsOut += lost + hurt
            cities[d].troops -= hurt
            b.leftA = a.troops - lost; b.leftD = cities[d].troops
            // A rout: now and then a general is caught in it.
            for (i, o) in team.enumerated() where officers[o].state == .serving && random() < (i == 0 ? 0.08 : 0.05) {
                capture(o, by: g, at: d, heldIn: d)
                b.captured.append(o)
            }
            retreat(a, team.filter { officers[$0].state == .serving && officers[$0].faction == f }, troops: a.troops - lost)
            note(f, "\(banner(f))攻\(warlordSites[d].name)不克", d)
            settleLord(f)
        }
        battles.append(b)
    }

    private mutating func kill(_ o: Int) {
        let f = officers[o].faction
        drop(o)
        officers[o].state = .dead; officers[o].army = nil
        if f >= 0 { settleLord(f) }
    }

    /// Taken in battle. A neutral city's captors let their prisoners go at once.
    private mutating func capture(_ o: Int, by f: Int, at c: Int, heldIn: Int) {
        let was = officers[o].faction
        lastFaction[o] = was
        officers[o].army = nil
        if f < 0 {
            officers[o].state = .free; officers[o].faction = -1; officers[o].city = heldIn; officers[o].known = true
            drop(o)
        } else {
            drop(o)
            officers[o].state = .captive; officers[o].faction = f; officers[o].city = heldIn; officers[o].held = 0
        }
        if was >= 0 { settleLord(was) }
    }

    /// A faction whose lord has fallen takes a new one; one with no cities left is gone.
    private mutating func settleLord(_ f: Int) {
        guard factions[f].alive else { return }
        let lord = factions[f].lord
        let lordServes = officers[lord].state == .serving && officers[lord].faction == f
        if cities(of: f).isEmpty {
            factions[f].alive = false
            factions[f].allies = [:]
            for g in factions.indices { factions[g].allies[f] = nil }
            for o in staff(of: f) {
                if let a = officers[o].army, let i = armies.firstIndex(where: { $0.id == a }) {
                    let army = armies.remove(at: i)
                    ledger.troopsOut += army.troops
                }
                officers[o].army = nil; officers[o].state = .free; officers[o].faction = -1; officers[o].known = true; lastFaction[o] = f
            }
            for i in armies.indices.reversed() where armies[i].faction == f { ledger.troopsOut += armies[i].troops; armies.remove(at: i) }
            for o in officers.indices where officers[o].state == .captive && officers[o].faction == f { officers[o].state = .free; officers[o].faction = -1; officers[o].known = true }
            note(f, "\(banner(f))灭亡", nil)
            return
        }
        guard !lordServes else { return }
        let staff = staff(of: f)
        let heir = warlordBanners[f].heirs.compactMap { warlordIndex[$0] }.first { staff.contains($0) }
            ?? staff.max { lead($0) + pol($0) + wit($0) < lead($1) + pol($1) + wit($1) }
        guard let heir else {
            // Nobody left to lead: the cities fall away to nobody.
            for c in cities(of: f) { cities[c].owner = -1 }
            settleLord(f)
            return
        }
        factions[f].lord = heir
        officers[heir].loyalty = 100
        note(f, "\(name(heir))继任为主", nil)
    }

    private mutating func economy() {
        for c in cities.indices {
            var x = cities[c]
            if x.owner >= 0 {
                let heart = 0.5 + Double(x.loyalty) / 200
                let gold = Int((Double(x.people) / 1000 * Double(x.trade) / 100 * 3 * heart).rounded()) + 20
                x.gold += gold; ledger.goldIn += gold
                if month == 9 {
                    let harvest = Int((Double(x.people) / 1000 * Double(x.farm) / 100 * 200 * heart).rounded()) + 500
                    x.grain += harvest; ledger.grainIn += harvest
                }
            } else {
                // Nobody's town keeps a little guard and a little store.
                let base = 1_000 + warlordSites[c].size * 700
                if x.troops < base { let n = min(base - x.troops, 60); x.troops += n; ledger.troopsIn += n }
                if month == 9 { let h = 800 + warlordSites[c].size * 400; x.grain += h; ledger.grainIn += h }
            }
            // Soldiers are paid: a gold for every two hundred a month; unpaid ones go home.
            if x.owner >= 0 {
                let pay = x.troops / 200
                if x.gold >= pay { x.gold -= pay; ledger.goldOut += pay }
                else {
                    let gone = min(x.troops, (pay - x.gold) * 60)
                    ledger.goldOut += x.gold; x.gold = 0
                    x.troops -= gone; ledger.troopsOut += gone
                    if gone > 0 { note(x.owner, "\(warlordSites[c].name)欠饷，逃兵 \(gone)", c) }
                }
            }
            let eat = x.troops / 10
            if x.grain >= eat { x.grain -= eat; ledger.grainOut += eat }
            else {
                ledger.grainOut += x.grain
                let hungry = eat - x.grain
                x.grain = 0
                let gone = min(x.troops, max(hungry * 2, x.troops / 10))
                x.troops -= gone; ledger.troopsOut += gone
                x.loyalty = max(0, x.loyalty - 3)
                if x.owner >= 0 { note(x.owner, "\(warlordSites[c].name)缺粮，逃兵 \(gone)", c) }
            }
            // People come to a loyal, busy city and leave a hungry, angry one.
            let grow = Double(x.people) * (Double(x.loyalty) - 40) / 100 * 0.004 * (0.6 + Double(x.farm + x.trade) / 250)
            x.people = max(5_000, min(900_000, x.people + Int(grow)))
            let target = 55 + (x.owner >= 0 && present(c).contains { has($0, .virtue) } ? 20 : 0)
            if x.loyalty < target { x.loyalty += 1 } else if x.loyalty > target + 10 { x.loyalty -= 1 }
            if x.owner >= 0, present(c).contains(where: { has($0, .virtue) }) { x.loyalty = min(100, x.loyalty + 2) }
            // A treasury holds only so much: the rest is spent at court or spoils in the granaries.
            if x.gold > 30_000 { ledger.goldOut += x.gold - 30_000; x.gold = 30_000 }
            if x.grain > 300_000 { ledger.grainOut += x.grain - 300_000; x.grain = 300_000 }
            cities[c] = x
        }
    }

    /// Generals of low loyalty may slip away; captives wait.
    private mutating func loyalties() {
        for o in officers.indices where officers[o].state == .serving && officers[o].army == nil {
            let f = officers[o].faction
            guard f >= 0, factions[f].lord != o else { continue }
            if officers[o].loyalty < 100, month % 3 == 0 { officers[o].loyalty += 1 }
            if officers[o].loyalty < 40, random() < Double(40 - officers[o].loyalty) / 400 {
                lastFaction[o] = f
                drop(o)
                officers[o].state = .free; officers[o].faction = -1; officers[o].known = true
                note(f, "\(name(o))离开了\(lordName(f))", officers[o].city)
            }
        }
        for o in officers.indices where officers[o].state == .captive { officers[o].held += 1 }
    }

    /// Who still stands, and has anyone won.
    private mutating func census() {
        for f in factions.indices where factions[f].alive && cities(of: f).isEmpty { settleLord(f) }
        let owners = Set(cities.map(\.owner))
        if owners.count == 1, let f = owners.first, f >= 0 { winner = f }
    }

    // MARK: Checks

    /// Everything counted: what is in the cities and on the roads, against what came in and went out since the start.
    func totals() -> (gold: Int, grain: Int, troops: Int) {
        (cities.reduce(0) { $0 + $1.gold }, cities.reduce(0) { $0 + $1.grain }, cities.reduce(0) { $0 + $1.troops } + armies.reduce(0) { $0 + $1.troops })
    }
}
