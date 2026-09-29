import Foundation

/// Jev — or a chat model — as lord of the frozen city, or as the person's
/// advisor: one multiple-choice question every few seconds of play.
///
/// As lord (`needs`): which need comes first for a while — heat, coal, food,
/// warm houses, wood and stone, iron, the sick, defence, conquest — each option
/// with what bears on it measured, the verdict first. The computer's hands
/// then build and staff with that need at the front; people about to freeze
/// or starve come first whatever is chosen. Matters at the gate (`answers`)
/// are asked the same way when they come.
///
/// As advisor (`advice`): what to build next and where — the place the
/// program found best for each thing the city is short of — offered to the
/// person with a 照做 button.
enum IcePlan: Equatable {
    case focus(IceFocus)
    case build(IceBuildKind, IceTile)
    case upgrade
    case wall
    case answer(Int)
    case wait
}

struct IceOption {
    var plan: IcePlan
    var title: String
    var words: String
}

enum IceCommander {
    static let rules = "A frozen city of the Three Kingdoms in an ice age that does not end: day after day, until the city fails. A great furnace in the middle burns coal every day; its level (1 to 5) sets how far its heat reaches. Houses inside the heat are warm; people in houses outside it, or with no house, fall sick in the cold, and in deep cold they freeze to death; the sick cannot work and some die; a clinic cures them. It grows colder day by day, quickly for a hundred days and slowly after, with cold snaps and a great blizzard about every fifty days — the first around days 60 to 66 at about −50°C, each later one colder and longer; walls on the north side cut the blizzard's wind. If the furnace runs out of coal the whole city freezes, and five days out loses the game. Everyone eats food: hunters in the woods, fishers on the ice, and greenhouses inside the heat. Coal, iron and stone come from mines on their seams, wood from lumber camps. Morale (民心) makes the people work faster or slower and decides whether newcomers settle; newcomers come only while there is room in warm houses. Soldiers trained at the barracks defend against raids by the rival lords Wei and Wu and march with generals from the tavern to take counties, each giving resources every day and people."
    static let question = "What should the city put first for the next while?"
    static let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: whatever will kill people soon — the furnace running out of coal, food running out, people sleeping outside the heat before a cold spell, the great blizzard coming with the furnace too low or no wall. Second: what holds the city back — no room left in the heat for newcomers, not enough wood, stone or iron to build the next thing, sick people with no clinic. Third: strength — soldiers against a coming raid, then conquest. An option that says there is nothing to do now is worth nothing; waiting is right only when every other option says its need is already met."

    static let adviceQuestion = "What should the lord build next, and where?"
    static let adviceJudge = "Compare the options in this order. First: anything without which people die soon — coal for the furnace, food, warm houses for people sleeping in the cold, the furnace raised before the great blizzard. Second: wood, stone and iron when they are short of what is being built. Third: a clinic when people are sick, the north wall before the blizzard, soldiers before a raid. Otherwise growth: houses in the heat for newcomers. Between two places for the same thing, the one the words say has more within reach and a shorter walk to a storage."

    static let answerQuestion = "How should the lord answer the people at the gate?"
    static let answerJudge = "Choose the answer that keeps the most people alive and warm over the coming days: food and coal before morale. When survival does not differ, choose the answer that raises morale most without leaving the stores short. An answer that costs what the city is about to need for the cold is worse than refusing."

    static let needTitles: [IceFocus: String] = [.heat: "熔炉", .coal: "煤", .food: "粮", .housing: "暖房", .materials: "木石", .iron: "铁", .health: "医疗", .defence: "城防", .conquest: "征战"]

    // MARK: The city, in words

    static func deg(_ t: Double) -> String { "\(Int(t.rounded()))°C" }
    static func days(_ x: Double) -> String { x >= 60 ? "more than 60 days" : x < 1 ? "less than a day" : "\(Int(x)) days" }

    static func situation(_ w: IceCity) -> String {
        let l = IceLedger(w)
        var parts = ["day \(l.day), \(deg(l.temperature)) outside" + (w.blizzardsSurvived > 0 ? ", \(w.blizzardsSurvived) great blizzard\(w.blizzardsSurvived == 1 ? "" : "s") come through" : "")]
        if let s = l.coldStart, let e = l.coldEnd {
            parts.append((l.coldIsBlizzard ? "the great blizzard " : "a cold snap ") + (s <= l.day ? "now, until day \(e)" : "on days \(s)–\(e)") + " (about \(deg(w.temperature(on: (s + e) / 2))))")
        }
        if !l.coldIsBlizzard, !l.afterBlizzard { parts.append("the great blizzard on days \(l.blizzardStart)–\(l.blizzardEnd) (about \(deg(w.temperature(on: (l.blizzardStart + l.blizzardEnd) / 2))))") }
        parts.append("furnace level \(l.level)\(l.upgrading ? " (being raised)" : ""), warming \(l.warmHouses) of \(l.houses) houses")
        parts.append("\(l.people) people (\(l.able) can work, \(l.kids) children, \(l.sick) sick); \(l.cold) sleeping outside the heat" + (l.homeless > 0 ? ", \(l.homeless) of them with no house" : ""))
        parts.append(String(format: "coal %.0f (%.0f burnt a day, the mines now dig %.0f); food %.0f (%.0f eaten a day, %.0f brought in); wood %.0f, stone %.0f, iron %.0f", l.coal, l.burn, l.coalCapacity, l.food, l.eats, l.foodCapacity, l.wood, l.stone, l.iron))
        parts.append("morale \(Int(l.morale)); \(l.soldiers) soldiers at home; \(w.counties) counties held")
        if let raid = l.raidDay { parts.append("a raid may come around day \(raid) with about \(Int(l.raiders)) raiders against a defence of \(Int(l.defence))") }
        let dead = (w.deaths["cold"] ?? 0) + (w.deaths["sick"] ?? 0) + (w.deaths["hunger"] ?? 0)
        if dead > 0 { parts.append("so far \(dead) have died") }
        return parts.joined(separator: "; ")
    }

    // MARK: As lord: which need first

    static func needs(_ w: IceCity) -> [IceOption] {
        let l = IceLedger(w), brain = IceBrain()
        var out: [IceOption] = []
        func add(_ f: IceFocus, _ words: String) { out.append(IceOption(plan: .focus(f), title: needTitles[f]!, words: words)) }

        // Heat.
        let next = min(IceCity.topLevel, l.level + 1)
        let cost = IceCity.upgradeCost(to: next)
        let reachNow = IceCity.heatReach[l.level], reachNext = IceCity.heatReach[next]
        let outside = w.buildings.filter { $0.kind == .house && $0.done && !w.warmed($0) }
        let wouldWarm = outside.filter { h in let c = w.centre(h); return hypot(c.x - w.hub.x, c.y - w.hub.y) <= reachNext }.count
        let blizzardNow = l.blizzardWarm, blizzardNext = blizzardNow + IceCity.heatPower[next] - IceCity.heatPower[l.level]
        var heat: String
        if l.level >= IceCity.topLevel { heat = "the furnace is at its highest level already: nothing more to raise" }
        else if l.upgrading { heat = "the furnace is already being raised to level \(next): the builders are carrying its materials" }
        else {
            var verdict = ""
            if l.cold > 0, wouldWarm > 0 { verdict = "brings \(l.cold) people sleeping in the cold into the heat" }
            else if !l.afterBlizzard, blizzardNow < -12 { verdict = "keeps the warm houses warmer through the great blizzard" }
            else if !IceBrain.roomInHeat(w) { verdict = "makes room in the heat for more houses and newcomers" }
            else { verdict = "more heat than the city needs yet: every house is already warm" }
            heat = "heat first: \(verdict) — raise the furnace to level \(next), its heat reaching \(fmt(reachNext)) tiles instead of \(fmt(reachNow))"
            if wouldWarm > 0 { heat += ", taking in \(wouldWarm) houses now outside it" }
            if !l.afterBlizzard { heat += "; in the blizzard warm houses would be at about \(deg(blizzardNext)) instead of \(deg(blizzardNow))" }
            heat += String(format: "; costs %.0f wood, %.0f stone, %.0f iron (there is %.0f, %.0f, %.0f); it will burn about %.0f more coal a day", cost[1], cost[3], cost[4], l.wood, l.stone, l.iron, IceCity.burnBase[next] - IceCity.burnBase[l.level])
        }
        add(.heat, heat)

        // Coal.
        let coalDays = l.coal / max(0.1, l.burn)
        var coal: String
        if coalDays < 5 { coal = "keeps the furnace lit: coal runs out in \(days(coalDays)) at \(Int(l.burn)) a day, and then the whole city freezes" }
        else if l.full[0] < l.burn * 1.1 { coal = "keeps the furnace lit for the long winter: the coal mines, fully manned, dig only \(Int(l.full[0])) a day against \(Int(l.burn)) burnt" }
        else if l.coal < IceBrain.coalWanted(l) { coal = "builds up the coal store for the cold to come: \(Int(l.coal)) against about \(Int(IceBrain.coalWanted(l))) wanted" + (l.afterBlizzard ? "" : " before the blizzard") }
        else { coal = "coal is plentiful: \(Int(l.coal)) in store, \(days(coalDays)) of burning" }
        add(.coal, "coal first: " + coal + String(format: "; the mines now dig %.0f a day with every job filled %.0f", l.coalCapacity, l.full[0]))

        // Food.
        let foodDays = l.food / max(0.1, l.eats)
        var food: String
        if foodDays < 5 { food = "saves people from hunger: food runs out in \(days(foodDays)) at \(Int(l.eats)) a day" }
        else if l.full[2] < l.eats { food = "feeds the city for good: the hunters, fishers and greenhouses, fully manned, bring in only \(Int(l.full[2])) a day against \(Int(l.eats)) eaten" }
        else if l.food < l.eats * 10 { food = "builds up the food store: \(days(foodDays)) of food" }
        else { food = "food is plentiful: \(Int(l.food)) in store, \(days(foodDays)) of eating" }
        add(.food, "food first: " + food + String(format: "; now %.0f a day comes in", l.foodCapacity))

        // Warm houses.
        var housing: String
        if l.homeless > 0 { housing = "shelters \(l.homeless) people with no house, who freeze first" }
        else if l.cold > 0, IceBrain.roomInHeat(w) { housing = "moves \(l.cold) people from cold houses into warm ones inside the heat" }
        else if l.warmRoom - l.people < 4 { housing = IceBrain.roomInHeat(w) ? "makes room for newcomers, who settle only in warm houses: \(max(0, l.warmRoom - l.people)) places free" : "no room is left in the heat for more houses: the furnace must be raised first" }
        else { housing = "there is room already: \(l.warmRoom - l.people) places free in warm houses" }
        add(.housing, "warm houses first: " + housing + "; \(l.people) people, room for \(l.warmRoom) in \(l.warmHouses) warm houses")

        // Materials.
        let short = l.spare[1] < 40 || l.spare[3] < 15
        add(.materials, "wood and stone first: " + (l.has(.lumber) == 0 ? "starts the wood that all building needs: there is no lumber camp" : short ? "unblocks building: wood and stone are short of what is going up" : "wood and stone are enough for now")
            + String(format: "; wood %.0f, stone %.0f; the building sites still need %.0f wood and %.0f stone", l.wood, l.stone, l.siteNeeds[1], l.siteNeeds[3]))

        // Iron.
        let ironNeed = l.level < IceCity.topLevel ? cost[4] : 0
        add(.iron, "iron first: " + (l.iron < ironNeed ? "gathers the iron the next furnace level needs: \(Int(l.iron)) of \(Int(ironNeed))" : l.has(.ironMine) == 0 ? "opens an iron mine for greenhouses, soldiers and generals" : "iron is enough for now: \(Int(l.iron))")
            + String(format: "; the iron mines dig %.0f a day", l.ironCapacity))

        // The sick.
        add(.health, "the sick first: " + (l.sick > 0 && l.has(.clinic) == 0 ? "cures \(l.sick) sick people who have no clinic" : Double(l.sick) > l.heals * 2 ? "cures faster: \(l.sick) sick, the clinics cure about \(Int(l.heals)) a day" : l.sick > 0 ? "\(l.sick) sick, and the clinics cure about \(Int(l.heals)) a day already" : "nobody is sick now"))

        // Defence.
        var defence: String
        if let raid = l.raidDay, raid - l.day <= 10, l.defence < l.raiders * 1.1 { defence = "holds off a raid expected around day \(raid): about \(Int(l.raiders)) raiders against a defence of \(Int(l.defence)) (soldiers and walls)" }
        else if !l.afterBlizzard, l.shelteredHouses < l.livedIn { defence = "shelters the houses from the blizzard's wind: a wall on the north keeps \(l.livedIn - l.shelteredHouses) more houses out of the wind, about 10°C warmer in the blizzard" }
        else { defence = "the city is safe for now: defence \(Int(l.defence))" + (l.raidDay.map { ", the next raid around day \($0) with about \(Int(l.raiders))" } ?? ", no raid in sight") }
        add(.defence, "defence first: " + defence)

        // Conquest.
        var conquest = "conquest first: "
        if let best = bestConquest(w) {
            conquest += "takes \(iceRegions[best.region].name) with \(iceOfficers[best.officer].name) and \(best.soldiers) soldiers, winning about \(Int(best.chance * 100))% of the time: +\(Int(iceRegions[best.region].amount)) \(IceGood.english[iceRegions[best.region].resource.rawValue]) a day and \(iceRegions[best.region].people) people for good"
        } else if l.has(.barracks) == 0 { conquest += "builds a barracks first: no soldiers can be trained" }
        else { conquest += "not ready: no county within reach can be won nine times in ten with the \(l.soldiers) soldiers at home" }
        add(.conquest, conquest)
        _ = brain
        return out
    }

    static func fmt(_ x: Double) -> String { x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x) }

    /// The county the soldiers at home could best take now, if any.
    static func bestConquest(_ w: IceCity) -> (region: Int, officer: Int, soldiers: Int, chance: Double)? {
        var best: (region: Int, officer: Int, soldiers: Int, chance: Double)?
        for r in w.targets {
            for h in w.freeOfficers {
                let n = min(w.army(h, to: r), w.soldiers)
                guard n >= 5, let days = w.travel(h, to: r) else { continue }
                let p = w.battle(h, n, r, on: w.today + days).chance
                if p >= 0.6, best == nil || p * Double(iceRegions[r].people + 10) > best!.chance * Double(iceRegions[best!.region].people + 10) { best = (r, h, n, p) }
            }
        }
        return best
    }

    // MARK: Answering the people

    static func answers(_ w: IceCity, _ e: IceIncident) -> [IceOption] {
        let l = IceLedger(w)
        let foodDays = l.food / max(0.1, l.eats), coalDays = l.coal / max(0.1, l.burn)
        return IceCity.choices(e.kind).indices.filter { w.can(e, $0) }.map { c in
            let text: String
            switch (e.kind, c) {
            case (0, 0):
                let room = max(0, l.warmRoom - l.people)
                text = "take in the \(e.amount) refugees: people \(l.people) → \(l.people + e.amount); " + (room >= e.amount ? "there is room for all of them in warm houses" : "room in warm houses for only \(room), so \(e.amount - room) would sleep in the cold") + "; food lasts \(days(l.food / max(0.1, l.eats + Double(e.amount) * 0.8))) instead of \(days(foodDays)); morale +4"
            case (0, _): text = "turn the refugees away: morale −5; nothing else changes"
            case (1, 0): text = "give the miners a warm day off: the coal mines stop for a day (about \(Int(l.coalCapacity)) coal not dug, \(Int(l.coal)) in store, \(days(coalDays)) of burning); morale +6"
            case (1, _): text = "refuse the miners: morale −6"
            case (2, 0):
                let need = l.burn * Double(e.amount + 2)
                text = "burn double coal through the cold snap: warm houses 10°C warmer; about \(Int(need)) more coal burnt, \(Int(l.coal)) in store" + (l.coal < need * 2 ? " — it would leave the store short" : "")
            case (2, _): text = "keep burning coal as usual through the cold snap: warm houses stay at their usual warmth"
            case (3, 0): text = "trade 60 wood for 50 food: food lasts \(days((l.food + 50) / max(0.1, l.eats))) instead of \(days(foodDays)); wood \(Int(l.wood)) → \(Int(l.wood - 60))"
            case (3, 1): text = "trade 30 iron for 60 coal: coal lasts \(days((l.coal + 60) / max(0.1, l.burn))) instead of \(days(coalDays)); iron \(Int(l.iron)) → \(Int(l.iron - 30))"
            case (3, 2): text = "trade 80 wood for 30 iron: iron \(Int(l.iron)) → \(Int(l.iron + 30)); wood \(Int(l.wood)) → \(Int(l.wood - 80))"
            case (3, _): text = "let the caravan pass without trading"
            case (4, 0): text = "brew medicine for the fever: cures up to 8 sick now (\(l.sick) sick), costs 30 food; morale +2"
            case (4, _): text = "let the fever run: 6 more people fall sick and cannot work"
            case (5, 0): text = "hold the ice-lantern festival: morale +9 (\(Int(l.morale)) → \(min(100, Int(l.morale) + 9))), costs 25 food and 20 wood"
            case (5, _): text = "skip the festival: morale −2"
            case (6, 0): text = "send 10 soldiers to hunt the wolves: +40 food, 3 soldiers wounded"
            case (6, _): text = "keep the hunters inside: hunting brings in half for 3 days"
            case (7, 0): text = "take in the veterans: soldiers \(l.soldiers) → \(l.soldiers + 8), costs 30 food"
            case (7, _): text = "turn the veterans away"
            case (8, 0): text = "dig out the ice cellar: +90 food for 30 wood; food lasts \(days((l.food + 90) / max(0.1, l.eats))) instead of \(days(foodDays))"
            case (8, _): text = "leave the ice cellar shut"
            case (9, 0): text = "punish the coal thief: 25 coal recovered, morale −3"
            case (9, _): text = "forgive the coal thief: morale +3"
            case (10, 0): text = "throw the couple a wedding feast: morale +5, costs 15 food"
            default: text = "a quiet wedding: morale +1"
            }
            return IceOption(plan: .answer(c), title: IceCity.choices(e.kind)[c], words: text)
        }
    }

    // MARK: As advisor: what to build and where

    static func advice(_ w: IceCity) -> [IceOption] {
        let l = IceLedger(w), brain = IceBrain()
        var out: [IceOption] = []
        var seen = Set<String>()
        for need in brain.order(l, w) {
            guard let step = brain.wants(need, w, l) else { continue }
            switch step {
            case .upgrade:
                guard !seen.contains("up") else { continue }
                seen.insert("up")
                let c = IceCity.upgradeCost(to: l.level + 1)
                out.append(IceOption(plan: .upgrade, title: "升级熔炉到 \(l.level + 1) 级", words: String(format: "raise the furnace to level %d: its heat reaches %@ tiles instead of %@ (%.0f wood, %.0f stone, %.0f iron)", l.level + 1, fmt(IceCity.heatReach[l.level + 1]), fmt(IceCity.heatReach[l.level]), c[1], c[3], c[4]) + "; " + why(need, l)))
            case .wall:
                guard !seen.contains("wall") else { continue }
                seen.insert("wall")
                out.append(IceOption(plan: .wall, title: "北面筑墙", words: "raise the next stretch of the north wall: the houses behind it are out of the blizzard's wind, about 10°C warmer in it; 3 stone and 1 wood a tile; " + why(need, l)))
            case .build(let kind):
                guard !seen.contains(kind.name), let at = brain.site(for: kind, w, l) else { continue }
                seen.insert(kind.name)
                out.append(IceOption(plan: .build(kind, at), title: "盖\(kind.name)（\(at.x),\(at.y)）", words: describe(kind, at, w, l) + "; " + why(need, l)))
            }
        }
        out.append(IceOption(plan: .wait, title: "先不盖，等材料", words: "build nothing new for now: the people finish what is going up and the stores fill" + (l.sites > 0 ? "; \(l.sites) things are going up" : "")))
        return out
    }

    static func describe(_ kind: IceBuildKind, _ at: IceTile, _ w: IceCity, _ l: IceLedger) -> String {
        let n = kind.size, probe = IceBuilding(id: 0, kind: kind, x: at.x, y: at.y)
        let c = (x: Double(at.x) + Double(n) / 2, y: Double(at.y) + Double(n) / 2)
        let store = w.buildings.filter { $0.kind == .storage && $0.done }.map { w.distance($0, c.x, c.y) }.min() ?? 0
        let cost = kind.cost
        let price = String(format: " (%.0f wood%@%@)", cost[1], cost[3] > 0 ? String(format: ", %.0f stone", cost[3]) : "", cost[4] > 0 ? String(format: ", %.0f iron", cost[4]) : "")
        let warm = hypot(c.x - w.hub.x, c.y - w.hub.y) <= w.heatRadius
        switch kind {
        case .house: return "a house\(price) \(warm ? "inside the heat: warm, room for five" : "outside the heat: its people would sleep in the cold")"
        case .hunter: return String(format: "a hunting lodge%@ %.0f tiles from a storage, game in %.0f forest tiles within reach: about %.0f food a day with three hunters", price, store, IceBrain.game(w, probe) / 3, IceBrain.yield(w, probe, workers: 3))
        case .fishery: return String(format: "an ice-fishing hut%@ on the ice, %.0f tiles of ice within reach, %.0f tiles from a storage: about %.0f food a day with three", price, IceBrain.fishing(w, probe), store, IceBrain.yield(w, probe, workers: 3))
        case .greenhouse: return String(format: "a greenhouse%@ inside the heat: about %.0f food a day with four, whatever the cold", price, IceBrain.yield(w, probe, workers: 4))
        case .lumber: return String(format: "a lumber camp%@ %.0f tiles from a storage: %.0f pines within reach, six wood a pine", price, store, IceBrain.trees(w, probe))
        case .coalMine: return String(format: "a coal mine%@ on %d tiles of coal seam, %.0f tiles from a storage: about %.0f coal a day with five", price, w.near(.coal, at, n, 2), store, 5 * IceBrain.perCoal * w.moraleSpeed)
        case .ironMine: return String(format: "an iron mine%@ on %d tiles of ore, %.0f tiles from a storage", price, w.near(.ore, at, n, 2), store)
        case .quarry: return String(format: "a quarry%@ on %d tiles of rock, %.0f tiles from a storage", price, w.near(.rock, at, n, 2), store)
        case .storage: return "a storage\(price) where the work is far from the nearest one: shorter walks for everybody who carries"
        case .clinic: return "a clinic\(price): six beds, cures the sick faster than lying at home"
        case .barracks: return "a barracks\(price): trains soldiers five at a time, room for 20 more"
        case .tavern: return "a tavern\(price): generals can be recruited there; morale +0.3 a day"
        case .furnace: return "the furnace"
        }
    }

    static func why(_ need: IceFocus, _ l: IceLedger) -> String {
        switch need {
        case .heat: return "\(l.cold) people sleep outside the heat; furnace level \(l.level)"
        case .coal: return String(format: "coal %.0f, burning %.0f a day", l.coal, l.burn)
        case .food: return String(format: "food %.0f, %.0f eaten a day, %.0f coming in", l.food, l.eats, l.foodCapacity)
        case .housing: return "\(l.people) people, room for \(l.warmRoom) in warm houses" + (l.homeless > 0 ? ", \(l.homeless) with no house" : "")
        case .materials: return String(format: "wood %.0f, stone %.0f", l.wood, l.stone)
        case .iron: return String(format: "iron %.0f", l.iron)
        case .health: return "\(l.sick) sick"
        case .defence: return l.raidDay.map { "a raid around day \($0)" } ?? "the blizzard on day \(l.blizzardStart)"
        case .conquest: return "\(l.soldiers) soldiers at home"
        }
    }

    // MARK: Carrying it out

    static func execute(_ plan: IcePlan, _ w: inout IceCity, _ brain: inout IceBrain) {
        switch plan {
        case .focus(let f): brain.focus = f
        case .build(let kind, let at):
            if w.place(kind, at: at) != nil { brain.connect(at, kind, &w) }
        case .upgrade: w.upgradeFurnace()
        case .wall: w.raise(walls: Array(IceBrain.wallLine(w).prefix(8)))
        case .answer(let c): w.answer(c)
        case .wait: break
        }
    }
}
