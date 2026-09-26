import Foundation

/// Jev — or a chat model — as the mayor of 放逐之城, or as the person's advisor:
/// one multiple-choice question every few seconds of play.
///
/// As mayor (`needs`): which need comes first for a while — food, firewood,
/// houses, logs and stone, tools, or growth — each option with what bears on
/// it measured: how many months the food lasts, the firewood against the cold
/// months ahead, the homeless and the room, tools per worker. The computer's
/// hands then build and staff with that need at the front; people about to
/// die of hunger or cold come first whatever is chosen.
///
/// As advisor (`advice`): what to build next and where — the place the
/// program found best for each kind the town is short of, with what the place
/// has going for it — offered to the person with a 照做 button.
enum CityPlan: Equatable {
    case focus(CityFocus)
    case build(CityKind, CityTile)
    case wait
}

struct CityOption {
    var plan: CityPlan
    var title: String
    var words: String
}

enum CityCommander {
    static let rules = "A town in the woods that has to get through its winters, month by month. Everybody eats one food a month; food comes from gatherers in the woods (spring to autumn), fishermen, and fields that are planted in spring and harvested in autumn. In the three winter months and the first month of spring every house burns two firewood a month, split from logs; a family without it — and anybody without a house — freezes. Hunger and cold kill in three or four months. Houses hold five; children are born into houses with room; newcomers arrive in spring when there are empty houses and food to spare. Logs come from woodcutters, stone from quarries, iron from mines; the smithy makes tools from iron and logs, and without tools all work is 40% slower. Everything built costs logs and stone and is put up by the people with no other job."
    static let question = "What should the town put first for the next while?"
    static let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: whatever will kill people soon — food that runs out within four months, firewood short of the cold months coming, people without a house before winter. Second: tools, when there is less than one for every three workers. Third: logs and stone, when there is not enough for a house. Fourth: food and firewood that fell short of what was used this past year. Otherwise grow: houses for newcomers and the food to keep them."

    static let adviceQuestion = "What should the mayor build next, and where?"
    static let adviceJudge = "Compare the options in this order. First: anything without which people will die soon — a house when people are homeless before winter, a woodcutter's hut when there is none, food when it runs out within four months. Second: a lumber camp or a quarry when logs or stone are short of a house. Third: food when this past year brought in less than was eaten. Fourth: tools when there is less than one for every three workers. Otherwise houses for newcomers. Between two places for the same thing, the one the words say has more within reach and a shorter walk to a storage."

    static let needTitles: [CityFocus: String] = [.food: "粮食", .firewood: "柴火", .housing: "住房", .materials: "木料石料", .tools: "工具", .growth: "扩张"]

    // MARK: The town, in words

    static func situation(_ w: CityWorld) -> String {
        let l = CityLedger(w)
        var parts = ["year \(w.year), \(["early", "mid", "late"][w.monthOfYear % 3]) \(["spring", "summer", "autumn", "winter"][w.season])"]
        parts.append("\(l.people) people: \(l.able) who can work, \(l.children) children, \(l.retired) old; \(l.workers) at a job, \(l.laborers) free to build")
        parts.append("\(l.houses) houses with room for \(l.room)" + (l.homeless > 0 ? ", \(l.homeless) without a house" : ""))
        parts.append(String(format: "food %.0f, logs %.0f, stone %.0f, iron %.0f, firewood %.0f, tools %.0f", l.food, l.logs, l.stone, l.iron, l.firewood, l.tools))
        parts.append(l.monthsToWinter > 0 ? "winter in \(l.monthsToWinter) months" : "winter now")
        let dead = (w.deaths["hunger"] ?? 0, w.deaths["cold"] ?? 0)
        if dead.0 + dead.1 > 0 { parts.append("so far \(dead.0) have starved and \(dead.1) have frozen") }
        return parts.joined(separator: "; ")
    }

    // MARK: As mayor: which need first

    static func needs(_ w: CityWorld) -> [CityOption] {
        let l = CityLedger(w)
        var out: [CityOption] = []
        let months = l.monthsOfFood
        let foodWords = String(format: "food first: more gatherers, fishermen and fields; %.0f food, %@ for %d people; this past year %.0f came in and %.0f was eaten; the places working now would bring in about %.0f a year",
                               l.food, months < 99 ? String(format: "%.0f months", months) : "for ever", l.people, l.foodMade, w.usedLastYear(.food), l.foodCapacity)
        out.append(CityOption(plan: .focus(.food), title: "粮食", words: foodWords + (months < 4 ? " — hunger within \(Int(months.rounded(.up))) months" : "")))
        let cold = l.firewood < l.firewoodNeed
        out.append(CityOption(plan: .focus(.firewood), title: "柴火",
                              words: String(format: "firewood first: woodcutters and splitters; %.0f firewood, and the cold months ahead need about %.0f for %d houses; this past year %.0f was split and %.0f burned", l.firewood, l.firewoodNeed, max(l.houses, 1), w.madeLastYear(.firewood), w.usedLastYear(.firewood))
                              + (cold ? (l.monthsToWinter <= 3 ? " — short, and winter is \(l.monthsToWinter == 0 ? "here" : "\(l.monthsToWinter) months away")" : " — short of the next winter") : "")))
        out.append(CityOption(plan: .focus(.housing), title: "住房",
                              words: "houses first: \(l.people) people, room for \(l.room) in \(l.houses) houses" + (l.homeless > 0 ? "; \(l.homeless) without a house" + (l.monthsToWinter <= 4 ? ", and winter in \(l.monthsToWinter) months: without a house they freeze" : "") : "; everybody has a house")
                              + (l.housesBuilding > 0 ? "; \(l.housesBuilding) going up" : "")))
        let house = CityWorld.cost(.house)
        let short = l.logs < house[1] || l.stone < house[2]
        out.append(CityOption(plan: .focus(.materials), title: "木料石料",
                              words: String(format: "logs and stone first: woodcutters and quarries; logs %.0f, stone %.0f; a house takes %.0f logs and %.0f stone", l.logs, l.stone, house[1], house[2])
                              + (l.siteLogs + l.siteStone > 0 ? String(format: "; the building sites still need %.0f logs and %.0f stone", l.siteLogs, l.siteStone) : "")
                              + (short ? " — not enough for a house" : "")))
        let perWorker = l.workers > 0 ? l.tools / Double(l.workers) : 9
        out.append(CityOption(plan: .focus(.tools), title: "工具",
                              words: String(format: "tools first: a mine and a smithy; %.0f tools for %d workers, who wear out about %.0f a year; this past year the smithy made %.0f", l.tools, l.workers, Double(l.workers) / 3, w.madeLastYear(.tools))
                              + (l.tools < 1 ? " — none left: all work goes 40% slower" : perWorker < 0.34 ? " — less than one for every three workers" : "")))
        let free = l.room - l.people
        out.append(CityOption(plan: .focus(.growth), title: "扩张",
                              words: "growth first: houses and fields for newcomers; \(max(0, free)) places free in the houses; newcomers come each spring when there are three free places and half a year of food; \(w.arrivals) have come so far, \(w.births) born"))
        return out
    }

    // MARK: As advisor: what to build and where

    static func advice(_ w: CityWorld) -> [CityOption] {
        let l = CityLedger(w), brain = CityBrain()
        var out: [CityOption] = []
        var seen = Set<CityKind>()
        for need in brain.order(l) {
            guard let kind = brain.wants(need, w, l), !seen.contains(kind), let at = brain.site(for: kind, w, l) else { continue }
            seen.insert(kind)
            out.append(CityOption(plan: .build(kind, at), title: "盖\(CityWorld.kindNames[kind.rawValue])（\(at.x),\(at.y)）", words: describe(kind, at, w, l, need)))
        }
        out.append(CityOption(plan: .wait, title: "先不盖，等材料", words: "build nothing new for now: the people finish what is going up and the stores fill" + (l.sites > 0 ? "; \(l.sites) buildings are going up" : "")))
        return out
    }

    static func describe(_ kind: CityKind, _ at: CityTile, _ w: CityWorld, _ l: CityLedger, _ need: CityFocus) -> String {
        let n = CityWorld.size(kind), probe = CityBuilding(id: 0, kind: kind, x: at.x, y: at.y)
        let c = (x: Double(at.x) + Double(n) / 2, y: Double(at.y) + Double(n) / 2)
        let store = w.buildings.filter { CityWorld.stores($0.kind) && $0.done }.map { w.distance($0, c.x, c.y) }.min() ?? 0
        let cost = CityWorld.cost(kind)
        let price = cost[1] + cost[2] > 0 ? String(format: " (%.0f logs, %.0f stone)", cost[1], cost[2]) : " (no materials)"
        var what: String
        switch kind {
        case .house: what = "a house\(price): room for five; \(l.homeless) without a house, \(max(0, l.room - l.people)) places free"
        case .field: what = String(format: "a field\(price) %.0f tiles from a storage, soil %.0f%% of the best: about %.0f food a year with two farmers, planted in spring and in by autumn", store, w.fieldFertility(probe) / 1.3 * 100, CityBrain.fieldYield(w, probe, workers: 2))
        case .gatherer: what = String(format: "a gatherer's hut\(price) %.0f tiles from a storage: berries and mushrooms on %.0f forest tiles within reach, about %.0f food a year with three gatherers", store, CityBrain.forage(w, probe) / 3, min(3 * CityBrain.perGatherer, CityBrain.forage(w, probe) * 0.8))
        case .fishery: what = String(format: "a fishing hut\(price) %.0f tiles from a storage: %.0f tiles of water within reach, about %.0f food a year with three fishermen", store, CityBrain.fishing(w, probe), min(3 * CityBrain.perFisher, CityBrain.fishing(w, probe) * 5))
        case .forester: what = String(format: "a lumber camp\(price) %.0f tiles from a storage: %.0f grown trees within reach, six logs a tree", store, CityBrain.trees(w, probe))
        case .woodcutter: what = String(format: "a woodcutter's hut\(price) %.0f tiles from a storage, splitting logs into firewood: about %.0f a year with two", store, 2 * CityBrain.perSplitter)
        case .quarry: what = String(format: "a quarry\(price) on %d rock tiles, %.0f tiles from a storage", w.near(.rock, at, n, 2), store)
        case .mine: what = String(format: "an iron mine\(price) on %d ore tiles, %.0f tiles from a storage", w.near(.ore, at, n, 2), store)
        case .blacksmith: what = "a smithy\(price): tools from iron and logs"
        case .storage: what = "a storage\(price) where the work is far from the nearest one: shorter walks for everybody who carries"
        case .townHall: what = "a town hall"
        }
        let why: String
        switch need {
        case .food: why = String(format: "food lasts %.0f months; this past year %.0f came in and %.0f was eaten", l.monthsOfFood, l.foodMade, l.eat)
        case .firewood: why = String(format: "firewood %.0f against %.0f the cold months ahead need", l.firewood, l.firewoodNeed)
        case .housing: why = l.homeless > 0 ? "\(l.homeless) without a house, winter in \(l.monthsToWinter) months" : "the houses are nearly full"
        case .materials: why = String(format: "logs %.0f and stone %.0f", l.logs, l.stone)
        case .tools: why = String(format: "%.0f tools for %d workers", l.tools, l.workers)
        case .growth: why = "room for newcomers"
        }
        return what + "; " + why
    }

    // MARK: Carrying it out

    static func execute(_ plan: CityPlan, _ w: inout CityWorld, _ brain: inout CityBrain) {
        switch plan {
        case .focus(let f): brain.focus = f
        case .build(let kind, let at):
            if w.place(kind, at: at) != nil, kind != .field { brain.connect(at, kind, &w) }
        case .wait: break
        }
    }
}
