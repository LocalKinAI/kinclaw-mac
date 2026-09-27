import SwiftUI

/// 植物守卫战 — a lawn defence in the spirit of Plants vs. Zombies, one tick a question.
///
/// Five lanes of nine cells, the house at the left end of every one of them.
/// Zombies walk in from the right in ten waves that grow — the tenth a big
/// one — each straight along its lane, stopping to eat whatever plant is in
/// its way. Sun falls from the sky and comes from sunflowers, and buys the
/// plants: shooters that fire down their lane, a wall that takes a long time
/// to eat, a cherry bomb that clears a patch. Each lane has one mower; a
/// zombie reaching the house in a lane whose mower is spent loses the game.
///
/// A tick is half a second and one question: wait, or plant this there. The
/// program lists, for each plant that is affordable and recharged, the
/// sensible cell in each lane, and measures what it does by playing the lane
/// forward with what is in it — whether its shooters kill its zombies before
/// they reach a plant, whether they eat plants, whether they reach the house
/// and when — as things stand and with the plant. It says that in words,
/// with the sun left and what the plant builds towards; which of it matters
/// most is the player's call.
@MainActor
final class JevGarden: JevGame {
    let id = "garden", title = "植物守卫战", symbol = "leaf.fill"
    let rules = "A lawn-defence game like Plants vs. Zombies. The lawn has 5 lanes, each 9 cells long; column 1 is next to the house, at the left end of every lane, and column 9 is the far end. Zombies walk in from the right, straight along their lane, in 10 waves that grow; the 10th is a big one. A zombie stops to eat any plant in its way. Planting costs sun: a sunflower 50 (it makes 25 sun every 12 seconds), a peashooter 100 (it shoots a pea every 1.5 seconds at the zombies in front of it in its lane), a wall-nut 50 (it only blocks, but takes 36 seconds to eat), a cherry bomb 150 (a second after planting it explodes, destroying every zombie in the 3 by 3 cells around it), a snow pea 175 (a peashooter whose peas also slow zombies to half speed). After planting, each kind needs time to recharge. Sun also falls from the sky, 25 every 10 seconds. An ordinary zombie takes 10 peas, a cone-head 28, a bucket-head 60; a runner takes 8 but walks twice as fast. A zombie eats a sunflower or a shooter in 4 seconds. Each lane has one lawn mower: the first zombie to reach the house in a lane sets it off, and it clears that lane; a zombie reaching the house in a lane whose mower is used up loses the game. Surviving all 10 waves wins. The score is the zombies killed plus 5 for every wave survived."
    let question = "Which move is best now, to survive all 10 waves without a zombie getting into the house?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: a lane where zombies will reach the house is an emergency, and in a lane whose mower is used up it loses the game: choose what stops them there — a shooter in that lane, or a cherry bomb that destroys them — and if nothing that stops them is affordable yet, wait and save sun for it. Second: a lane where zombies will eat plants needs more firepower there: another shooter, or a wall-nut in front of its shooters. Third: while no lane is in danger, sunflowers come first until there are about 8, because sun buys everything else. Fourth: build up every lane before the waves grow: at least 1 shooter in each lane, then 2, then 3 before the big wave; a snow pea is better than a peashooter where armoured zombies come. A cherry bomb is for an emergency, or for 3 or more zombies at once. Waiting is right only when a lane is in danger and nothing affordable now saves it — then save sun for what does — or when no other option does anything useful: sun left unspent does nothing."

    nonisolated static let lanes = 5, columns = 9, waves = 10
    /// The plants, in the order of their seed packets and of the keys 1–5.
    nonisolated static let sunflower = 0, peashooter = 1, wallnut = 2, cherry = 3, snowpea = 4
    nonisolated static let seeds = ["sunflower", "peashooter", "wall-nut", "cherry bomb", "snow pea"]
    nonisolated static let seedTitles = ["向日葵", "豌豆射手", "坚果墙", "樱桃炸弹", "寒冰射手"]
    nonisolated static let cost = [50, 100, 50, 150, 175]
    /// Ticks a seed packet takes to recharge after planting.
    nonisolated static let recharge = [10, 10, 40, 70, 16]
    /// Ticks of eating a plant takes.
    nonisolated static let toughness = [8, 8, 72, 99, 8]
    nonisolated static let breeds = ["zombie", "cone-head", "bucket-head", "runner"]
    /// Peas a zombie takes: an ordinary zombie's ten, and the rest of it is its hat.
    nonisolated static let health = [10, 28, 60, 8]
    nonisolated static let pace = [0.12, 0.12, 0.12, 0.24]
    /// What each costs a wave: the waves are dealt a budget that grows.
    nonisolated static let price = [1, 2, 4, 2]
    nonisolated static let produceEvery = 24, firstSun = 10, fireEvery = 3, slowFor = 16, fuse = 2, skyEvery = 20
    nonisolated static let peaSpeed = 2.0, mowerSpeed = 1.5
    /// Ticks the program plays a lane forward to see what becomes of it: forty seconds.
    nonisolated static let horizon = 80
    nonisolated static let firstWave = 30, waveGap = 34
    nonisolated static func start(of wave: Int) -> Int { firstWave + (wave - 1) * waveGap }
    /// Each wave's budget; the last is the big one.
    nonisolated static let budgets = [1, 2, 4, 7, 10, 14, 18, 22, 27, 70]

    fileprivate struct Plant {
        var kind: Int, lane: Int, col: Int, health: Int, timer: Int, serial: Int
        var planted = 0, fired = -9, made = -9
    }
    fileprivate struct Zombie {
        var breed: Int, lane: Int, x: Double, health: Int, serial: Int
        var slow = 0, eating = false, hit = -9, burnt = false
        /// Still wearing its cone or bucket: more health than a bare zombie.
        var hatted: Bool { health > JevGarden.health[0] && (breed == 1 || breed == 2) }
    }
    fileprivate struct Pea { var lane: Int, x: Double, frozen: Bool, serial: Int }
    fileprivate struct Sun { var serial: Int, x: Double, y: Double, born: Int, due: Int, sky: Bool }
    /// A pea that hit something this tick: where it flew from, and where it struck.
    fileprivate struct Splat { var lane: Int, from: Double, to: Double, frozen: Bool, target: Int }
    fileprivate struct Corpse { var zombie: Zombie, tick: Int }
    fileprivate struct Boom { var lane: Int, col: Int, tick: Int }
    fileprivate struct Arrival { var tick: Int, breed: Int, lane: Int }
    /// Wait (kind -1), or plant a kind in a cell.
    fileprivate struct Move: Equatable { var kind: Int, lane = 0, col = 0 }

    /// A lane played forward with what is in it: its zombies, and what becomes of them.
    fileprivate struct Outlook {
        var zombies = 0, eaten = 0, left = 0
        /// Ticks until a zombie reaches the house, until one first bites a plant, until the first plant is gone.
        var reach: Int? = nil, touch: Int? = nil, bite: Int? = nil
        /// What a cherry bomb destroyed, by breed.
        var burnt: [Int] = []
        /// Whether the lane still has a shooter at the end: zombies left in a lane without one reach the house sooner or later.
        var armed = true
    }

    /// The lawn as it stands. Nothing in it is random: what comes over the
    /// fence and out of the sky is the game's business, not this.
    fileprivate struct Lawn {
        var tick = 0, sun = 100, kills = 0, serial = 0
        var plants: [Plant] = [], zombies: [Zombie] = [], peas: [Pea] = [], suns: [Sun] = []
        /// Each lane's mower: where it is (parked at -0.45), whether it is running, whether it is used up.
        var mower = [Double](repeating: -0.45, count: JevGarden.lanes)
        var mowing = [Bool](repeating: false, count: JevGarden.lanes)
        var spent = [Bool](repeating: false, count: JevGarden.lanes)
        var charging = [Int](repeating: 0, count: 5)
        var lost = false, breach: Int? = nil
        /// For the picture: what happened this tick.
        var splats: [Splat] = [], corpses: [Corpse] = [], booms: [Boom] = []
        var gained = 0

        struct Events { var reached: [Int] = [], eaten: [Int] = [], touched: [Int] = [], burnt: [(lane: Int, breed: Int)] = [] }

        func free(_ lane: Int, _ col: Int) -> Bool { !plants.contains { $0.lane == lane && $0.col == col } }
        func ready(_ lane: Int) -> Bool { !spent[lane] && !mowing[lane] }

        mutating func plant(_ kind: Int, lane: Int, col: Int) {
            sun -= JevGarden.cost[kind]
            charging[kind] = JevGarden.recharge[kind]
            serial += 1
            let timer = kind == JevGarden.sunflower ? JevGarden.firstSun : kind == JevGarden.cherry ? JevGarden.fuse : 0
            plants.append(Plant(kind: kind, lane: lane, col: col, health: JevGarden.toughness[kind], timer: timer, serial: serial, planted: tick))
        }

        mutating func arrive(_ breed: Int, lane: Int, x: Double) {
            serial += 1
            zombies.append(Zombie(breed: breed, lane: lane, x: x, health: JevGarden.health[breed], serial: serial))
        }

        /// Half a second. Quiet is the program looking ahead: no sun, nothing kept for the picture.
        mutating func step(quiet: Bool = false) -> Events {
            var ev = Events()
            tick += 1
            if !quiet {
                splats = []; gained = 0
                corpses.removeAll { tick - $0.tick > 3 }
                booms.removeAll { tick - $0.tick > 4 }
                for s in suns where s.due <= tick { sun += 25; gained += 25 }
                suns.removeAll { $0.due <= tick }
            }
            for k in charging.indices where charging[k] > 0 { charging[k] -= 1 }

            // The plants.
            for i in plants.indices {
                let p = plants[i]
                switch p.kind {
                case JevGarden.sunflower:
                    guard !quiet else { break }
                    plants[i].timer -= 1
                    if plants[i].timer <= 0 {
                        plants[i].timer = JevGarden.produceEvery; plants[i].made = tick
                        serial += 1
                        suns.append(Sun(serial: serial, x: Double(p.col) + 0.86, y: Double(p.lane) + 0.66, born: tick, due: tick + 4, sky: false))
                    }
                case JevGarden.peashooter, JevGarden.snowpea:
                    if plants[i].timer > 0 { plants[i].timer -= 1 }
                    let reach = Double(p.col) + 0.1
                    if plants[i].timer == 0, zombies.contains(where: { $0.lane == p.lane && $0.health > 0 && $0.x > reach && $0.x < 9.0 }) {
                        plants[i].timer = JevGarden.fireEvery; plants[i].fired = tick
                        serial += 1
                        peas.append(Pea(lane: p.lane, x: Double(p.col) + 0.75, frozen: p.kind == JevGarden.snowpea, serial: serial))
                    }
                case JevGarden.cherry:
                    plants[i].timer -= 1
                    guard plants[i].timer <= 0 else { break }
                    let low = Double(p.col) - 1.0, high = Double(p.col) + 2.0
                    for j in zombies.indices where abs(zombies[j].lane - p.lane) <= 1 && zombies[j].health > 0 && zombies[j].x >= low && zombies[j].x <= high {
                        zombies[j].health = 0; zombies[j].burnt = true
                        ev.burnt.append((zombies[j].lane, zombies[j].breed))
                    }
                    plants[i].health = 0
                    if !quiet { booms.append(Boom(lane: p.lane, col: p.col, tick: tick)) }
                default: break
                }
            }

            // The peas: each strikes the first zombie it reaches.
            var used = Set<Int>()
            for i in peas.indices {
                let old = peas[i].x, new = old + JevGarden.peaSpeed
                peas[i].x = new
                var target: Int?
                for j in zombies.indices where zombies[j].lane == peas[i].lane && zombies[j].health > 0 && zombies[j].x < 9.1
                    && zombies[j].x - 0.35 <= new && zombies[j].x + 0.35 >= old {
                    if target.map({ zombies[j].x < zombies[$0].x }) ?? true { target = j }
                }
                if let j = target {
                    zombies[j].health -= 1; zombies[j].hit = tick
                    if peas[i].frozen { zombies[j].slow = JevGarden.slowFor }
                    used.insert(peas[i].serial)
                    if !quiet {
                        splats.append(Splat(lane: peas[i].lane, from: old, to: max(old, zombies[j].x - 0.3), frozen: peas[i].frozen, target: zombies[j].serial))
                    }
                } else if new > 9.8 { used.insert(peas[i].serial) }
            }
            if !used.isEmpty { peas.removeAll { used.contains($0.serial) } }

            // The zombies: eat what is in the way, or walk on.
            for j in zombies.indices where zombies[j].health > 0 {
                var z = zombies[j]
                let slowed = z.slow > 0
                if z.slow > 0 { z.slow -= 1 }
                let x = z.x
                if let i = plants.firstIndex(where: { $0.lane == z.lane && $0.kind != JevGarden.cherry && $0.health > 0
                                                      && x <= Double($0.col) + 0.95 && x >= Double($0.col) + 0.2 }) {
                    if !z.eating { ev.touched.append(z.lane) }
                    z.eating = true
                    if !slowed || tick % 2 == 0 { plants[i].health -= 1 }
                } else {
                    z.eating = false
                    z.x -= JevGarden.pace[z.breed] * (slowed ? 0.5 : 1)
                    if z.x < -0.2 {
                        ev.reached.append(z.lane)
                        if ready(z.lane) { mowing[z.lane] = true } else if !mowing[z.lane] { lost = true; breach = z.lane }
                    }
                }
                zombies[j] = z
            }

            // The mowers: each clears its lane as it goes.
            for lane in 0..<JevGarden.lanes where mowing[lane] {
                mower[lane] += JevGarden.mowerSpeed
                let front = mower[lane] + 0.5
                for j in zombies.indices where zombies[j].lane == lane && zombies[j].health > 0 && zombies[j].x <= front { zombies[j].health = 0 }
                if mower[lane] > 9.8 { mowing[lane] = false; spent[lane] = true }
            }

            for z in zombies where z.health <= 0 {
                kills += 1
                if !quiet { corpses.append(Corpse(zombie: z, tick: tick)) }
            }
            zombies.removeAll { $0.health <= 0 }
            for p in plants where p.health <= 0 && p.kind != JevGarden.cherry { ev.eaten.append(p.lane) }
            plants.removeAll { $0.health <= 0 }
            return ev
        }

        /// These lanes played forward with what is in them now: nothing more
        /// planted, nothing new arriving.
        func outlook(_ lanes: [Int], horizon: Int = JevGarden.horizon) -> [Outlook] {
            var sim = self
            let keep = Set(lanes)
            sim.plants = plants.filter { keep.contains($0.lane) }
            sim.zombies = zombies.filter { keep.contains($0.lane) }
            sim.peas = peas.filter { keep.contains($0.lane) }
            sim.suns = []; sim.splats = []; sim.corpses = []; sim.booms = []
            var out = [Outlook](repeating: Outlook(), count: JevGarden.lanes)
            for z in sim.zombies { out[z.lane].zombies += 1 }
            var decided = Set<Int>()
            var k = 0
            while k < horizon, !sim.zombies.isEmpty || sim.plants.contains(where: { $0.kind == JevGarden.cherry }) {
                k += 1
                let ev = sim.step(quiet: true)
                for hit in ev.burnt { out[hit.lane].burnt.append(hit.breed) }
                for lane in ev.touched where out[lane].touch == nil { out[lane].touch = k }
                for lane in ev.eaten where !decided.contains(lane) {
                    out[lane].eaten += 1
                    if out[lane].bite == nil { out[lane].bite = k }
                }
                for lane in ev.reached where out[lane].reach == nil { out[lane].reach = k; decided.insert(lane) }
                // A lane whose house is reached is decided: its zombies are out of the story.
                if !decided.isEmpty { sim.zombies.removeAll { decided.contains($0.lane) } }
            }
            for z in sim.zombies { out[z.lane].left += 1 }
            for lane in lanes where (0..<JevGarden.lanes).contains(lane) {
                out[lane].armed = sim.plants.contains { $0.lane == lane && ($0.kind == JevGarden.peashooter || $0.kind == JevGarden.snowpea) }
            }
            return out
        }
    }

    private var lawn = Lawn()
    /// The lawn before the last tick, for the picture to glide from.
    private var previous = Lawn()
    private var schedule: [Arrival] = []
    private var arrived = 0
    private var dice = JevDice(seed: 1)
    private var moves: [Move] = []
    /// What becomes of every lane if nothing is planted: measured once a tick, for every option's words.
    private var survey: [Outlook] = []
    private(set) var ticked = Date.distantPast
    private(set) var won = false
    var over: Bool { won || lawn.lost }

    /// A person's seat: the cell under the cursor, the seed packet in hand, and why the last try did nothing.
    private var person = false
    private var cursor = (lane: 2, col: 2)
    private var chosen = 1
    private var complaint: (text: String, at: Date)?
    /// Looks at the keys since the last tick: a tick is five of them.
    private var beat = 0

    /// Waves begun so far.
    var wave: Int { lawn.tick < Self.firstWave ? 0 : min(Self.waves, (lawn.tick - Self.firstWave) / Self.waveGap + 1) }
    var survived: Int { won ? Self.waves : max(0, wave - 1) }
    var score: Int { lawn.kills + 5 * survived }
    var status: String {
        let mowers = (0..<Self.lanes).filter { lawn.ready($0) }.count
        let line = "第 \(wave)/\(Self.waves) 波 · 阳光 \(lawn.sun) · 打倒 \(lawn.kills) · 向日葵 \(count(Self.sunflower)) · 小推车 \(mowers)/5"
        return won ? "守住了 · " + line : lawn.lost ? "僵尸进屋了 · " + line : line
    }

    private func count(_ kind: Int) -> Int { lawn.plants.filter { $0.kind == kind }.count }
    private func shooters(_ lane: Int) -> Int { lawn.plants.filter { $0.lane == lane && ($0.kind == Self.peashooter || $0.kind == Self.snowpea) }.count }
    /// Sun a minute: the sky's, and every sunflower's.
    private var income: Int { 150 + 125 * count(Self.sunflower) }

    var situation: String {
        var parts: [String] = []
        let next = wave < Self.waves ? Self.start(of: wave + 1) - lawn.tick : 0
        if wave == 0 { parts.append("no wave yet: the first comes in \(Self.seconds(next))") }
        else if wave < Self.waves {
            parts.append("wave \(wave) of \(Self.waves) has begun; " + (wave + 1 == Self.waves ? "the big final wave" : "wave \(wave + 1)") + " comes in \(Self.seconds(next))")
        } else { parts.append("the big final wave has begun") }
        parts.append("sun \(lawn.sun), income about \(income) a minute from \(Self.plural(count(Self.sunflower), "sunflower")) and the sky")
        parts.append("shooters in lanes 1 to 5: " + (0..<Self.lanes).map { String(shooters($0)) }.joined(separator: ", "))
        let busy = (0..<Self.lanes).filter { lane in lawn.zombies.contains { $0.lane == lane } }
        parts.append(busy.isEmpty ? "no zombies on the lawn" : busy.map { "lane \($0 + 1): \(crowd($0))" }.joined(separator: "; "))
        let used = (0..<Self.lanes).filter { !lawn.ready($0) }
        parts.append(used.isEmpty ? "every lane's mower is ready" : "mower used up in lane " + used.map { String($0 + 1) }.joined(separator: " and ") + " (a zombie reaching the house there loses the game)")
        return parts.joined(separator: "; ")
    }

    var position: String {
        var rows: [String] = []
        for lane in 0..<Self.lanes {
            var cells = Array(repeating: ".", count: Self.columns)
            for p in lawn.plants where p.lane == lane { cells[p.col] = ["S", "P", "W", "C", "I"][p.kind] }
            for z in lawn.zombies where z.lane == lane && z.x < 9 {
                let c = max(0, min(Self.columns - 1, Int(z.x)))
                cells[c] = (cells[c] == "." ? "" : cells[c]) + ["z", "c", "b", "r"][z.breed]
            }
            rows.append((lawn.ready(lane) ? "m|" : " |") + cells.joined(separator: " "))
        }
        return rows.joined(separator: "\n") + "\n(The house is at the left, m a ready mower. S sunflower, P peashooter, W wall-nut, C cherry bomb, I snow pea; z zombie, c cone-head, b bucket-head, r runner. Lanes 1–5 from the top.)"
    }

    var grid: [[JevCell]] {
        (0..<Self.lanes).map { lane in
            (0..<Self.columns).map { col -> JevCell in
                let green = (lane + col) % 2 == 0 ? Color(red: 0.45, green: 0.72, blue: 0.27) : Color(red: 0.38, green: 0.64, blue: 0.22)
                if let z = lawn.zombies.first(where: { $0.lane == lane && Int($0.x) == col }) {
                    return JevCell(colour: green, text: ["僵", "锥", "桶", "跑"][z.breed], ink: .black, big: true)
                }
                if let p = lawn.plants.first(where: { $0.lane == lane && $0.col == col }) {
                    return JevCell(colour: green, text: ["🌻", "🟢", "🥔", "🍒", "❄️"][p.kind], big: true)
                }
                return JevCell(colour: green)
            }
        }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        dice = JevDice(seed: seed)
        lawn = Lawn(); won = false; arrived = 0; moves = []; survey = []
        schedule = []
        for wave in 1...Self.waves {
            var budget = Self.budgets[wave - 1], group: [Int] = []
            while budget > 0 {
                var allowed = [0]
                if wave >= 3 { allowed.append(1) }
                if wave >= 4 { allowed.append(3) }
                if wave >= 6 { allowed.append(2) }
                allowed = allowed.filter { Self.price[$0] <= budget }
                let breed = allowed[dice.below(allowed.count)]
                group.append(breed); budget -= Self.price[breed]
            }
            let begin = Self.start(of: wave), spacing = wave == Self.waves ? 2 : 3
            for (k, breed) in group.enumerated() { schedule.append(Arrival(tick: begin + k * spacing, breed: breed, lane: dice.below(Self.lanes))) }
        }
        previous = lawn; ticked = .distantPast
        cursor = (2, 2); chosen = 1; complaint = nil; beat = 0
    }

    func prepare(person: Bool) { self.person = person }

    // MARK: The options

    func options() -> [JevOption] {
        guard !over else { return [] }
        survey = lawn.outlook(Array(0..<Self.lanes))
        var list: [Move] = []
        for kind in 0..<5 where lawn.sun >= Self.cost[kind] && lawn.charging[kind] == 0 {
            for lane in 0..<Self.lanes { if let col = spot(kind, lane) { list.append(Move(kind: kind, lane: lane, col: col)) } }
        }
        list.append(Move(kind: -1))
        moves = list
        let judged = judgeAll(list)
        return Self.ballot(judged)
    }

    /// The sensible cell for a plant in a lane: sunflowers at the back, shooters
    /// in front of them and behind any wall, a wall in front of everything, a
    /// cherry bomb where it destroys the most.
    private func spot(_ kind: Int, _ lane: Int) -> Int? {
        let here = lawn.plants.filter { $0.lane == lane }
        func free(_ c: Int) -> Bool { !here.contains { $0.col == c } }
        switch kind {
        case Self.sunflower:
            return (0...1).first(where: free)
        case Self.peashooter, Self.snowpea:
            let wall = here.filter { $0.kind == Self.wallnut }.map(\.col).min() ?? Self.columns
            return ([2, 3, 4, 5, 6, 1, 0] as [Int]).first { $0 < wall && free($0) }
        case Self.wallnut:
            // One wall a lane, as far out as column 8 but short of the nearest zombie, in front of everything else.
            guard here.contains(where: { $0.kind == Self.peashooter || $0.kind == Self.snowpea }),
                  !here.contains(where: { $0.kind == Self.wallnut }) else { return nil }
            let front = here.filter { $0.kind != Self.cherry }.map(\.col).max() ?? 0
            let nearest = lawn.zombies.filter { $0.lane == lane }.map { Int(($0.x - 0.2).rounded(.down)) }.min() ?? Self.columns
            let far = min(7, nearest - 1)
            return far > front ? (front + 1...far).reversed().first(where: free) : nil
        default:
            var best: (col: Int, kills: Int)?
            for c in 0..<Self.columns where free(c) {
                let n = lawn.zombies.filter { z in
                    let x = z.eating ? z.x : z.x - Self.pace[z.breed] * Double(Self.fuse)
                    return abs(z.lane - lane) <= 1 && x >= Double(c) - 1 && x <= Double(c) + 2
                }.count
                if n > (best?.kills ?? 0) { best = (c, n) }
            }
            return best?.col
        }
    }

    private struct Judged { var words: String, merit: Double, title: String }

    /// How bad a lane's outlook is: a mower spent, the game lost, plants eaten.
    private func danger(_ o: Outlook, _ lane: Int) -> Double {
        guard o.zombies > 0 else { return 0 }
        if let r = o.reach { return lawn.ready(lane) ? 250 + Double(max(0, 80 - r)) : 5000 + Double(max(0, 80 - r)) * 20 }
        if o.left > 0, !o.armed { return lawn.ready(lane) ? 150 : 3000 }
        var d = Double(o.eaten) * 40 + Double(o.left) * 10
        if let b = o.bite { d += Double(max(0, 80 - b)) * 0.3 }
        if o.touch != nil { d += 5 }
        return d
    }

    private func judgeAll(_ list: [Move]) -> [Judged] {
        let dangers = (0..<Self.lanes).map { danger(survey[$0], $0) }
        let urgent = dangers.indices.max { dangers[$0] < dangers[$1] }.flatMap { dangers[$0] >= 100 ? $0 : nil }
        var effects: [[Outlook]] = []
        var reliefs: [Double] = []
        for m in list {
            guard m.kind >= 0 else { effects.append(survey); reliefs.append(0); continue }
            var trial = lawn
            trial.plant(m.kind, lane: m.lane, col: m.col)
            let lanes = touched(m)
            let with = trial.outlook(lanes)
            var merged = survey
            for l in lanes { merged[l] = with[l] }
            effects.append(merged)
            reliefs.append(lanes.reduce(0) { $0 + dangers[$1] - danger(with[$1], $1) })
        }
        // Waiting is worth something when the lane in danger cannot be saved with what the sun buys now.
        let rescue = urgent.map { u in list.indices.filter { list[$0].kind >= 0 && touched(list[$0]).contains(u) }.map { reliefs[$0] }.max() ?? 0 } ?? 0
        return list.indices.map { i in
            let m = list[i]
            if m.kind < 0 {
                let short = lawn.sun < Self.cost[Self.snowpea]
                let saving = short && urgent.map { survey[$0].reach != nil && dangers[$0] >= 250 } == true && rescue < dangers[urgent!] * 0.5
                return Judged(words: waitWords(urgent: urgent, saving: saving, dangers: dangers), merit: 4 + (saving ? 70 : 0), title: "等一下，攒阳光")
            }
            let merit = reliefs[i] + plan(m, effects[i])
            return Judged(words: words(m, with: effects[i], urgent: urgent), merit: merit,
                          title: "第\(m.lane + 1)行第\(m.col + 1)格种\(Self.seedTitles[m.kind])")
        }
    }

    /// The lanes a planting changes.
    private func touched(_ m: Move) -> [Int] {
        m.kind == Self.cherry ? [m.lane - 1, m.lane, m.lane + 1].filter { (0..<Self.lanes).contains($0) } : [m.lane]
    }

    /// What a planting builds towards, beyond what it does to the zombies on the lawn now.
    private func plan(_ m: Move, _ with: [Outlook]) -> Double {
        let w = Double(wave), mine = Double(shooters(m.lane))
        let here = lawn.zombies.filter { $0.lane == m.lane }
        switch m.kind {
        case Self.sunflower:
            let n = Double(count(Self.sunflower))
            return wave <= 6 ? max(0, 36 - 4 * n) : (n < 4 ? 8 : -4)
        case Self.peashooter, Self.snowpea:
            var v = 22 - 9 * mine + 1.5 * w
            if !here.isEmpty { v += 5 }
            if m.kind == Self.snowpea { v += here.contains(where: \.hatted) || wave >= 6 ? 8 : 3 }
            return v
        case Self.wallnut:
            return !here.isEmpty || wave >= 5 ? 6 + 3 * mine : -5
        default:
            let n = Double(touched(m).reduce(0) { $0 + with[$1].burnt.count })
            return n >= 3 ? 8 * n : -30 + 4 * n
        }
    }

    // MARK: Words

    nonisolated static func plural(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
    nonisolated static func seconds(_ ticks: Int) -> String {
        let s = max(1, Int((Double(ticks) / 2).rounded()))
        return s == 1 ? "1 second" : "about \(s) seconds"
    }

    /// The zombies in a lane: how many of what, and how near the house the nearest is.
    private func crowd(_ lane: Int) -> String {
        let here = lawn.zombies.filter { $0.lane == lane }
        guard let nearest = here.map(\.x).min() else { return "no zombies" }
        var kinds: [String] = []
        for breed in [2, 1, 3, 0] {
            let n = here.filter { $0.breed == breed }.count
            if n > 0 { kinds.append(Self.plural(n, Self.breeds[breed])) }
        }
        let cells = max(0, Int(nearest.rounded()))
        let where_ = nearest >= 9 ? "just coming onto the lawn" : "the nearest \(Self.plural(cells, "cell")) from the house"
        return kinds.joined(separator: " and ") + ", " + where_
    }

    /// What becomes of a lane's zombies.
    private func fate(_ o: Outlook, _ lane: Int) -> String {
        guard o.zombies > 0 else { return "no zombies" }
        if let r = o.reach {
            return "they reach the house in \(Self.seconds(r))" + (lawn.ready(lane) ? ", which uses up its mower" : ", where the mower is used up: the game is lost")
        }
        if o.left > 0, !o.armed {
            return "nothing in the lane can kill them, so they reach the house after about 40 seconds" + (lawn.ready(lane) ? ", using up its mower" : ", where the mower is used up: the game is lost")
        }
        if o.eaten > 0 {
            let first = "they eat \(o.eaten == 1 ? "a plant" : "\(o.eaten) plants"), the first gone in \(Self.seconds(o.bite ?? 1))"
            return first + (o.left > 0 ? ", and are still alive after 40 seconds" : ", then die")
        }
        if o.touch != nil { return o.left > 0 ? "they are held at the front plant, still alive after 40 seconds" : "they die at the front plant, which survives" }
        return o.left > 0 ? "they are still alive after 40 seconds" : "the shooters kill them before they reach any plant"
    }

    /// What a planting does for a lane, the verdict first: saves it, helps it, or changes nothing.
    private func laneWords(_ lane: Int, _ with: Outlook) -> String {
        let now = survey[lane], name = "lane \(lane + 1)"
        guard now.zombies > 0 else { return "\(name) has no zombies now" }
        let before = fate(now, lane), after = fate(with, lane)
        let crowd = "\(name) has \(self.crowd(lane))"
        if before == after { return "changes nothing for the zombies in \(name): \(before) either way (\(crowd))" }
        let gain = danger(now, lane) - danger(with, lane)
        let detail = "without it \(before); with it \(after) (\(crowd))"
        if gain <= 0 { return "does not help \(name): " + detail }
        let held = with.reach == nil && (with.left == 0 || with.armed)
        if held && with.eaten == 0 { return "saves \(name): " + detail }
        if held && (now.reach != nil || (now.left > 0 && !now.armed)) { return "keeps the zombies in \(name) out of the house: " + detail }
        return "helps \(name) but does not save it: " + detail
    }

    private func words(_ m: Move, with: [Outlook], urgent: Int?) -> String {
        let cost = Self.cost[m.kind], left = lawn.sun - cost
        var parts: [String] = []
        switch m.kind {
        case Self.sunflower:
            let n = count(Self.sunflower)
            parts.append(n < 8 ? "more sun: sunflowers \(n) → \(n + 1) of the 8 needed, income \(income) → \(income + 125) a minute"
                               : "sunflowers \(n) → \(n + 1), more than the 8 needed")
            if wave >= 7 { parts.append("this late a sunflower pays back little") }
            if survey[m.lane].zombies > 0 { parts.append(laneWords(m.lane, with[m.lane])) }
        case Self.peashooter, Self.snowpea:
            let s = shooters(m.lane)
            parts.append(laneWords(m.lane, with[m.lane]))
            parts.append("lane \(m.lane + 1)'s shooters \(s) → \(s + 1)" + (s == 0 ? ", its first (every lane needs one before its zombies come)" : ""))
            if m.kind == Self.snowpea { parts.append("its peas slow zombies to half speed") }
        case Self.wallnut:
            parts.append(laneWords(m.lane, with[m.lane]))
            parts.append("a wall in front of its \(Self.plural(shooters(m.lane), "shooter"))")
        default:
            let burnt = touched(m).flatMap { with[$0].burnt }
            let lanes = touched(m).map { String($0 + 1) }
            if burnt.isEmpty { parts.append("explodes in 1 second and destroys nothing") }
            else {
                var kinds: [String] = []
                for breed in [2, 1, 3, 0] {
                    let n = burnt.filter { $0 == breed }.count
                    if n > 0 { kinds.append(Self.plural(n, Self.breeds[breed])) }
                }
                parts.append("explodes in 1 second and destroys \(Self.plural(burnt.count, "zombie")) (\(kinds.joined(separator: ", "))) in lanes \(lanes.first!) to \(lanes.last!)")
            }
            for l in touched(m) where survey[l].zombies > 0 { parts.append(laneWords(l, with[l])) }
        }
        let after = (0..<5).filter { Self.cost[$0] <= left && lawn.charging[$0] == 0 && $0 != m.kind }
        parts.append("costs \(cost), leaves \(left) sun" + (after.isEmpty ? "" : " (a " + after.map { Self.seeds[$0] }.joined(separator: " or ") + " still affordable)"))
        if let u = urgent, !touched(m).contains(u) { parts.append("does nothing for lane \(u + 1), which is in danger: \(fate(survey[u], u))") }
        return "\(Self.seeds[m.kind]) in lane \(m.lane + 1), column \(m.col + 1): " + parts.joined(separator: "; ")
    }

    /// Waiting, said as what it is: saving for something that is needed, or sun left lying idle.
    /// Waiting, said as what it is: saving for a lane nothing affordable saves, or sun left lying idle.
    /// Nothing good is said of anything else here: a reader takes every word as said of this option.
    private func waitWords(urgent: Int?, saving: Bool, dangers: [Double]) -> String {
        let perTick = Double(income) / 120
        var soon: [String] = []
        for kind in [Self.peashooter, Self.snowpea, Self.cherry] where lawn.sun < Self.cost[kind] || lawn.charging[kind] > 0 {
            let ticks = max(Int((Double(Self.cost[kind] - lawn.sun) / perTick).rounded(.up)), lawn.charging[kind])
            if ticks <= 40 { soon.append("a \(Self.seeds[kind]) in \(Self.seconds(ticks))") }
        }
        let ready = soon.isEmpty ? "" : " (affordable next: " + soon.joined(separator: ", ") + ")"
        let others = (0..<Self.lanes).filter { $0 != urgent && dangers[$0] >= 100 }.map { String($0 + 1) }
        let alsoLeft = others.isEmpty ? "" : "; waiting also leaves lane " + others.joined(separator: " and ") + " in danger"
        if let u = urgent, saving {
            return "wait and save sun for lane \(u + 1), which is in danger: \(fate(survey[u], u)); nothing affordable now saves it" + ready + alsoLeft
        }
        if let u = urgent {
            return "wait, planting nothing: lane \(u + 1) stays in danger (\(fate(survey[u], u)))" + alsoLeft + "; sun \(lawn.sun) is left unspent"
        }
        let n = count(Self.sunflower)
        return "wait, planting nothing this tick: sun \(lawn.sun) is left unspent and no lane is in danger, so there is nothing to save for"
            + (n < 8 ? "; the garden has only \(n) of the 8 sunflowers it needs" : "")
    }

    /// Options that read the same become one: the first is played for a reader, the best by the yardstick.
    private static func ballot(_ judged: [Judged]) -> [JevOption] {
        var order: [String] = [], first: [String: Int] = [:], best: [String: Int] = [:]
        for (i, j) in judged.enumerated() {
            if let b = best[j.words] { if j.merit > judged[b].merit { best[j.words] = i } }
            else { order.append(j.words); first[j.words] = i; best[j.words] = i }
        }
        return order.enumerated().map { n, text in
            JevOption(id: String(format: "p%02d", n + 1), label: text, merit: judged[best[text]!].merit, move: first[text]!,
                      strongest: best[text]!, title: judged[first[text]!].title)
        }
    }

    // MARK: A move

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move), !over else { return }
        previous = lawn
        let m = moves[option.move]
        if m.kind >= 0, lawn.sun >= Self.cost[m.kind], lawn.charging[m.kind] == 0, lawn.free(m.lane, m.col) {
            lawn.plant(m.kind, lane: m.lane, col: m.col)
        }
        _ = lawn.step()
        // Sun out of the sky, somewhere on the lawn.
        if lawn.tick % Self.skyEvery == 6 {
            lawn.serial += 1
            lawn.suns.append(Sun(serial: lawn.serial, x: 0.5 + Double(dice.below(80)) / 10, y: 0.4 + Double(dice.below(40)) / 10,
                                 born: lawn.tick, due: lawn.tick + 7, sky: true))
        }
        // Zombies over the fence at the far end.
        while arrived < schedule.count, schedule[arrived].tick <= lawn.tick {
            let a = schedule[arrived]
            lawn.arrive(a.breed, lane: a.lane, x: 9.3 + Double(dice.below(30)) / 100)
            arrived += 1
        }
        if !lawn.lost, arrived == schedule.count, lawn.zombies.isEmpty { won = true }
        ticked = Date()
        beat = 0
    }

    // MARK: Played by a person

    /// The keys are looked at ten times a second, so the cursor answers at once; the lawn moves every fifth look.
    var clock: Double? { person ? 0.1 : nil }
    let controls = "1–5 选植物 · ←↑↓→ 移动方框 · 空格 种下 · 阳光自己收 · 不按就是等"
    let letters: Set<Character> = ["1", "2", "3", "4", "5"]

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        var sow = false
        for key in pressed {
            switch key {
            case .letter(let c): if let d = c.wholeNumberValue, (1...5).contains(d) { chosen = d - 1 }
            case .left: cursor.col = max(cursor.col - 1, 0)
            case .right: cursor.col = min(cursor.col + 1, Self.columns - 1)
            case .up: cursor.lane = max(cursor.lane - 1, 0)
            case .down: cursor.lane = min(cursor.lane + 1, Self.lanes - 1)
            case .space: sow = true
            }
        }
        if sow {
            if let why = refusal(chosen, lane: cursor.lane, col: cursor.col) { complaint = (why, Date()) }
            else { return .choose(planting(Move(kind: chosen, lane: cursor.lane, col: cursor.col), options)) }
        }
        beat += 1
        if beat >= 5, let wait = options.first(where: { moves.indices.contains($0.move) && moves[$0.move].kind < 0 }) { return .choose(wait) }
        return pressed.isEmpty ? .nothing : .redraw
    }

    /// Why a plant cannot go in a cell now, or nil.
    private func refusal(_ kind: Int, lane: Int, col: Int) -> String? {
        if lawn.charging[kind] > 0 { return "\(Self.seedTitles[kind])还在准备" }
        if lawn.sun < Self.cost[kind] { return "阳光不够：\(Self.seedTitles[kind])要 \(Self.cost[kind])" }
        if !lawn.free(lane, col) { return "这一格已经种了" }
        return nil
    }

    /// A person's planting as the move it is — the list's own, or one added to it.
    private func planting(_ m: Move, _ options: [JevOption]) -> JevOption {
        let index: Int
        if let listed = moves.firstIndex(of: m) { index = listed } else { moves.append(m); index = moves.count - 1 }
        if let option = options.first(where: { $0.move == index }) { return option }
        let judged = judgeAll([m])[0]
        let id = options.first(where: { $0.label == judged.words })?.id ?? "p00"
        return JevOption(id: id, label: judged.words, merit: judged.merit, move: index, title: judged.title)
    }
}

// MARK: - The picture

extension JevGarden: JevPainted {
    var aspect: Double { 1.35 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        var seat: Seat?
        if person, !over {
            let age = complaint.map { Date().timeIntervalSince($0.at) } ?? 99
            seat = Seat(lane: cursor.lane, col: cursor.col, chosen: chosen, ok: refusal(chosen, lane: cursor.lane, col: cursor.col) == nil,
                        complaint: age < 1.8 ? complaint?.text : nil, age: age)
        }
        let scene = Scene(before: previous, after: lawn, t: t, since: since, now: now, over: over, won: won, wave: wave, seat: seat)
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    /// A person's cursor and seed packet, as the picture shows them.
    fileprivate struct Seat { let lane: Int, col: Int, chosen: Int, ok: Bool, complaint: String?, age: Double }

    /// A sunny back garden seen from the side: the house and its porch on the
    /// left, the lawn in two greens, a fence and a hedge along the back, the
    /// street on the right where the zombies come from. The sun is high on the
    /// left: everything is lit from the top left and drops a soft shadow.
    fileprivate struct Scene {
        let before: Lawn, after: Lawn, t: Double, since: Double, now: Double
        let over: Bool, won: Bool, wave: Int, seat: Seat?

        /// Where everything is on the canvas.
        struct Frame {
            let width: CGFloat, height: CGFloat, bar: CGFloat, left: CGFloat, top: CGFloat, cell: CGFloat, row: CGFloat, pad: CGFloat
            init(_ size: CGSize) {
                width = size.width; height = size.height
                bar = height * 0.155; pad = height * 0.012
                left = width * 0.1
                cell = (width * 0.955 - left) / CGFloat(JevGarden.columns)
                top = bar + height * 0.01
                row = (height - top - height * 0.012) / CGFloat(JevGarden.lanes)
            }
            var right: CGFloat { left + cell * CGFloat(JevGarden.columns) }
            var bottom: CGFloat { top + row * CGFloat(JevGarden.lanes) }
            func x(_ col: Double) -> CGFloat { left + CGFloat(col) * cell }
            func y(_ lane: Double) -> CGFloat { top + CGFloat(lane) * row }
            /// Where feet stand in a lane.
            func ground(_ lane: Int) -> CGFloat { top + (CGFloat(lane) + 0.8) * row }
            // The seed bank and the wave meter across the top.
            var high: CGFloat { bar - 2 * pad }
            var bank: CGRect { CGRect(x: pad, y: pad, width: high * (1 + 5 * 0.86) + high * 0.1, height: high) }
            func packet(_ k: Int) -> CGRect {
                CGRect(x: bank.minX + high * (1.02 + 0.86 * CGFloat(k)), y: bank.minY + high * 0.08, width: high * 0.78, height: high * 0.84)
            }
            var counter: CGPoint { CGPoint(x: bank.minX + high * 0.5, y: bank.minY + high * 0.36) }
            var meter: CGRect { CGRect(x: bank.maxX + pad, y: pad, width: width - bank.maxX - 2 * pad, height: high) }
        }

        func paint(_ g: inout GraphicsContext, _ size: CGSize) {
            let f = Frame(size)
            let clock = Double(after.tick - 1) + t
            let beat = t > 0.05 && t < 0.98 ? min(max(since / t, 0.05), 1.5) : 0.5
            backdrop(g, f)
            scorches(g, f, beat: beat)
            if let seat { cursor(g, f, seat) }
            let oldZombies = Dictionary(before.zombies.map { ($0.serial, $0) }, uniquingKeysWith: { a, _ in a })
            // Every shadow on the lawn in one go, under everything that casts one.
            var shade = Path()
            func shadow(at p: CGPoint, width w: CGFloat) { shade.addEllipse(in: CGRect(x: p.x + w * 0.1 - w * 0.78, y: p.y + w * 0.02 - w * 0.19, width: w * 1.56, height: w * 0.38)) }
            for p in after.plants { shadow(at: CGPoint(x: f.x(Double(p.col) + 0.5), y: f.ground(p.lane)), width: f.cell * 0.34) }
            for z in after.zombies {
                let x = JevDraw.mix(oldZombies[z.serial]?.x ?? z.x + JevGarden.pace[z.breed], z.x, t)
                shadow(at: CGPoint(x: f.x(x + 0.15), y: f.ground(z.lane)), width: f.cell * 0.3)
            }
            g.fill(shade, with: .color(.black.opacity(0.2)))
            let oldPeas = Dictionary(before.peas.map { ($0.serial, $0.x) }, uniquingKeysWith: { a, _ in a })
            let kept = Set(after.plants.map(\.serial))
            for lane in 0..<JevGarden.lanes {
                if after.ready(lane) { mower(g, f, lane) }
                for p in before.plants where p.lane == lane && p.kind != JevGarden.cherry && !kept.contains(p.serial) {
                    // Eaten this tick: gulped down.
                    let s = f.cell * CGFloat(max(0, 1 - t * 1.6))
                    if s > 1 { plant(g, p, at: CGPoint(x: f.x(Double(p.col) + 0.5), y: f.ground(lane)), s: s, chewed: true, clock: clock) }
                }
                // A cherry bomb about to go off is drawn over the zombies it is about to meet.
                let (bombs, rest) = (after.plants.filter { $0.lane == lane && $0.kind == JevGarden.cherry },
                                     after.plants.filter { $0.lane == lane && $0.kind != JevGarden.cherry }.sorted { $0.col < $1.col })
                for p in rest {
                    let fresh = p.planted == before.tick && after.tick != before.tick
                    let grow = fresh ? JevDraw.smooth(t * 2.2) : 1
                    let pop = fresh ? 1 + 0.18 * sin(.pi * min(1, t * 2.2)) : 1
                    let s = f.cell * CGFloat((0.35 + 0.65 * grow) * pop)
                    let chewed = after.zombies.contains { $0.lane == lane && $0.eating && $0.x <= Double(p.col) + 0.95 && $0.x >= Double(p.col) + 0.2 }
                    let base = CGPoint(x: f.x(Double(p.col) + 0.5), y: f.ground(lane))
                    plant(g, p, at: base, s: s, chewed: chewed, clock: clock)
                    if fresh, t < 0.6 { puff(g, at: base, s: f.cell, age: t / 0.6) }
                }
                for c in after.corpses where c.zombie.lane == lane {
                    let age = since + Double(after.tick - c.tick) * beat
                    zombie(g, c.zombie, at: CGPoint(x: f.x(c.zombie.x + 0.15), y: f.ground(lane)), s: f.cell, walk: -c.zombie.x * 15 + Double(c.zombie.serial), flash: 0, fall: age)
                }
                for z in after.zombies.filter({ $0.lane == lane }).sorted(by: { $0.x > $1.x }) {
                    let from = oldZombies[z.serial]?.x ?? z.x + JevGarden.pace[z.breed]
                    let x = JevDraw.mix(from, z.x, t)
                    var flash = 0.0
                    if z.hit == after.tick, let hit = after.splats.first(where: { $0.target == z.serial }) {
                        let at = min(1, (hit.to + 0.25 - hit.from) / JevGarden.peaSpeed)
                        if t >= at { flash = max(0, 1 - (t - at) * beat / 0.14) }
                    }
                    let base = CGPoint(x: f.x(x + 0.15), y: f.ground(lane))
                    zombie(g, z, at: base, s: f.cell, walk: -x * 15 + Double(z.serial), flash: flash, fall: nil)
                }
                for p in bombs {
                    let base = CGPoint(x: f.x(Double(p.col) + 0.5), y: f.ground(lane))
                    plant(g, p, at: base, s: f.cell, chewed: false, clock: clock)
                    if p.planted == before.tick, t < 0.6 { puff(g, at: base, s: f.cell, age: t / 0.6) }
                }
                if !after.ready(lane) { mower(g, f, lane) }
                let height = f.ground(lane) - f.cell * 0.56
                for p in after.peas where p.lane == lane {
                    let x = JevDraw.mix(oldPeas[p.serial] ?? p.x - JevGarden.peaSpeed, p.x, t)
                    if x < Double(JevGarden.columns) + 0.6 { pea(g, at: CGPoint(x: f.x(x), y: height), r: f.cell * 0.1, frozen: p.frozen, ground: f.ground(lane)) }
                }
                for s in after.splats where s.lane == lane {
                    let hitX = max(s.from, s.to + 0.25)
                    let at = min(1, (hitX - s.from) / JevGarden.peaSpeed)
                    if t < at { pea(g, at: CGPoint(x: f.x(JevDraw.mix(s.from, hitX, t / max(at, 0.001))), y: height), r: f.cell * 0.1, frozen: s.frozen, ground: f.ground(lane)) }
                    else { splash(g, at: CGPoint(x: f.x(hitX), y: height), s: f.cell, age: (t - at) * beat, frozen: s.frozen, seed: Int(hitX * 100)) }
                }
            }
            booms(g, f, beat: beat)
            suns(g, f, clock: clock)
            if let seat { ghost(g, f, seat) }
            light(g, f)
            hud(g, f, clock: clock)
            banner(g, f, clock: clock)
            if let seat, let text = seat.complaint { toast(g, f, text, age: seat.age) }
            if over {
                JevDraw.curtain(g, CGSize(width: f.width, height: f.height), title: won ? "守住了！" : "僵尸进屋了！",
                                detail: won ? "10 波全部挡住 · 打倒 \(after.kills) 个僵尸" : "撑到第 \(wave) 波 · 打倒 \(after.kills) 个僵尸")
            }
        }

        // MARK: Helpers

        private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r, green: g, blue: b).opacity(a) }
        private func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)) }
        private func radial(_ colours: [Color], _ c: CGPoint, _ r: CGFloat) -> GraphicsContext.Shading {
            .radialGradient(Gradient(colors: colours), center: c, startRadius: 0, endRadius: r)
        }
        private func linear(_ colours: [Color], _ a: CGPoint, _ b: CGPoint) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: colours), startPoint: a, endPoint: b)
        }
        /// A context whose unit is `s` points, its origin at `p`: every figure is drawn in cells.
        private func unit(_ g: GraphicsContext, at p: CGPoint, s: CGFloat, turn: Double = 0) -> GraphicsContext {
            var c = g
            c.translateBy(x: p.x, y: p.y)
            if turn != 0 { c.rotate(by: .radians(turn)) }
            c.scaleBy(x: s, y: s)
            return c
        }
        private static func number(_ a: Int, _ b: Int) -> Double { Double(JevDraw.hash(a, b) % 10_000) / 10_000 }

        /// A leaf from its stalk to its tip, as wide as asked in the middle.
        private func leaf(_ from: CGPoint, _ to: CGPoint, width w: CGFloat) -> Path {
            let dx = to.x - from.x, dy = to.y - from.y
            let n = CGPoint(x: -dy, y: dx)
            let len = max(sqrt(n.x * n.x + n.y * n.y), 0.0001)
            let side = CGPoint(x: n.x / len * w, y: n.y / len * w)
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            var p = Path()
            p.move(to: from)
            p.addQuadCurve(to: to, control: CGPoint(x: mid.x + side.x, y: mid.y + side.y))
            p.addQuadCurve(to: from, control: CGPoint(x: mid.x - side.x, y: mid.y - side.y))
            p.closeSubpath()
            return p
        }

        private func shadow(_ g: GraphicsContext, at p: CGPoint, width w: CGFloat) {
            g.fill(oval(p.x + w * 0.1, p.y + w * 0.02, w * 0.78, w * 0.19), with: .color(.black.opacity(0.2)))
        }

        // MARK: The garden

        /// Tufts of grass and a few daisies, placed once, in cells.
        private static let tufts: Path = {
            var p = Path()
            for i in 0..<130 {
                let x = number(i, 1) * 9, y = number(i, 2) * 5
                let s = 0.05 + 0.05 * number(i, 3)
                // Three blades from one root, each a thin sliver.
                for (dx, dy) in [(-0.7, -0.9), (0.1, -1.3), (0.7, -0.85)] as [(Double, Double)] {
                    p.move(to: CGPoint(x: x - 0.012, y: y)); p.addLine(to: CGPoint(x: x + s * dx, y: y + s * dy)); p.addLine(to: CGPoint(x: x + 0.012, y: y)); p.closeSubpath()
                }
            }
            return p
        }()
        private static let daisies: (petals: Path, hearts: Path) = {
            var petals = Path(), hearts = Path()
            for i in 0..<16 {
                let x = number(i, 11) * 9, y = number(i, 12) * 5
                for k in 0..<5 {
                    let a = Double(k) / 5 * 2 * .pi
                    petals.addEllipse(in: CGRect(x: x + cos(a) * 0.028 - 0.022, y: y + sin(a) * 0.022 - 0.016, width: 0.044, height: 0.032))
                }
                hearts.addEllipse(in: CGRect(x: x - 0.016, y: y - 0.012, width: 0.032, height: 0.024))
            }
            return (petals, hearts)
        }()

        private func backdrop(_ g: GraphicsContext, _ f: Frame) {
            // The sky, and a wooden fence along the back of the garden.
            g.fill(Path(CGRect(x: 0, y: 0, width: f.width, height: f.top + 2)),
                   with: linear([rgb(0.55, 0.8, 0.98), rgb(0.84, 0.94, 1)], .zero, CGPoint(x: 0, y: f.top)))
            let plank = f.cell * 0.36, peak = f.top * 0.16
            var boards = Path(), seams = Path()
            var x: CGFloat = -plank * 0.3, k = 0
            while x < f.width {
                let top = peak + (k % 2 == 0 ? 0 : f.top * 0.03)
                boards.move(to: CGPoint(x: x, y: top + plank * 0.4))
                boards.addLine(to: CGPoint(x: x + plank / 2, y: top))
                boards.addLine(to: CGPoint(x: x + plank, y: top + plank * 0.4))
                boards.addLine(to: CGPoint(x: x + plank, y: f.top + 2))
                boards.addLine(to: CGPoint(x: x, y: f.top + 2))
                boards.closeSubpath()
                seams.move(to: CGPoint(x: x + plank, y: top + plank * 0.4)); seams.addLine(to: CGPoint(x: x + plank, y: f.top))
                x += plank; k += 1
            }
            g.fill(boards, with: .color(rgb(0.9, 0.76, 0.56)))
            g.stroke(seams, with: .color(rgb(0.45, 0.3, 0.16, 0.45)), lineWidth: 1)
            for y in [f.top * 0.38, f.top * 0.72] {
                g.fill(Path(CGRect(x: 0, y: y, width: f.width, height: f.top * 0.06)), with: .color(rgb(0.66, 0.47, 0.3, 0.9)))
            }
            // A hedge at the foot of the fence.
            var hedge = Path()
            let bush = f.cell * 0.34
            var bx: CGFloat = -bush * 0.5, n = 0
            while bx < f.width + bush {
                let r = bush * CGFloat(0.8 + 0.4 * Self.number(n, 21))
                hedge.addEllipse(in: CGRect(x: bx - r, y: f.top - r * 0.9, width: 2 * r, height: 1.6 * r))
                bx += bush * 1.1; n += 1
            }
            g.fill(hedge, with: .color(rgb(0.24, 0.52, 0.2)))

            // The lawn: lanes in two greens, every other cell a shade darker, grass and daisies all over.
            var light = Path(), dark = Path()
            for lane in 0..<JevGarden.lanes {
                for col in 0..<JevGarden.columns {
                    let r = CGRect(x: f.x(Double(col)), y: f.y(Double(lane)), width: f.cell + 0.5, height: f.row + 0.5)
                    if (lane + col) % 2 == 0 { light.addRect(r) } else { dark.addRect(r) }
                }
            }
            g.fill(light, with: .color(rgb(0.54, 0.79, 0.31)))
            g.fill(dark, with: .color(rgb(0.46, 0.71, 0.26)))
            let place = CGAffineTransform(a: f.cell, b: 0, c: 0, d: f.row, tx: f.left, ty: f.top)
            g.fill(Self.tufts.applying(place), with: .color(rgb(0.2, 0.45, 0.12, 0.5)))
            g.fill(Self.daisies.petals.applying(place), with: .color(.white.opacity(0.85)))
            g.fill(Self.daisies.hearts.applying(place), with: .color(rgb(1, 0.82, 0.2)))
            // The edge of the lawn along the bottom.
            g.fill(Path(CGRect(x: 0, y: f.bottom, width: f.width, height: f.height - f.bottom + 1)), with: .color(rgb(0.3, 0.5, 0.18)))
            g.fill(Path(CGRect(x: 0, y: f.bottom, width: f.width, height: 1.5)), with: .color(rgb(0.2, 0.36, 0.1, 0.6)))
            // The hedge's shade along the top of the lawn.
            g.fill(Path(CGRect(x: f.left, y: f.top, width: f.right - f.left, height: f.row * 0.25)),
                   with: linear([.black.opacity(0.16), .black.opacity(0)], CGPoint(x: 0, y: f.top), CGPoint(x: 0, y: f.top + f.row * 0.25)))

            // The house: clapboard siding, and a porch deck where the mowers wait.
            let wall = f.left * 0.34
            g.fill(Path(CGRect(x: 0, y: f.top - f.row * 0.2, width: wall, height: f.height)), with: .color(rgb(0.92, 0.88, 0.8)))
            var siding = Path()
            var sy = f.top - f.row * 0.2
            while sy < f.height { siding.move(to: CGPoint(x: 0, y: sy)); siding.addLine(to: CGPoint(x: wall, y: sy)); sy += f.row * 0.16 }
            g.stroke(siding, with: .color(rgb(0.55, 0.48, 0.4, 0.4)), lineWidth: 1)
            let deck = CGRect(x: wall, y: f.top - f.row * 0.2, width: f.left - wall, height: f.height)
            g.fill(Path(deck), with: .color(rgb(0.74, 0.53, 0.32)))
            var planks = Path()
            for k in 1..<3 {
                let px = deck.minX + deck.width * CGFloat(k) / 3
                planks.move(to: CGPoint(x: px, y: deck.minY)); planks.addLine(to: CGPoint(x: px, y: deck.maxY))
            }
            for lane in 0...JevGarden.lanes {
                let py = f.y(Double(lane)) - f.row * 0.2
                planks.move(to: CGPoint(x: deck.minX, y: py)); planks.addLine(to: CGPoint(x: deck.maxX, y: py))
            }
            g.stroke(planks, with: .color(rgb(0.4, 0.25, 0.12, 0.45)), lineWidth: 1)
            g.fill(Path(CGRect(x: wall, y: deck.minY, width: deck.width * 0.18, height: deck.height)), with: .color(.black.opacity(0.14)))
            // The deck's edge against the grass.
            g.fill(Path(CGRect(x: f.left - 3, y: deck.minY, width: 3, height: deck.height)), with: .color(rgb(0.45, 0.3, 0.15, 0.8)))

            // The pavement on the right, where the zombies come in.
            let street = CGRect(x: f.right, y: f.top - f.row * 0.2, width: f.width - f.right, height: f.height)
            g.fill(Path(street), with: .color(rgb(0.66, 0.66, 0.65)))
            var slabs = Path()
            var y = street.minY
            while y < f.height { slabs.move(to: CGPoint(x: street.minX, y: y)); slabs.addLine(to: CGPoint(x: street.maxX, y: y)); y += f.row * 0.55 }
            g.stroke(slabs, with: .color(.black.opacity(0.15)), lineWidth: 1)
            g.fill(Path(CGRect(x: f.right, y: street.minY, width: 4, height: street.height)), with: .color(rgb(0.86, 0.86, 0.83)))
            g.fill(Path(CGRect(x: f.right + 4, y: street.minY, width: 2, height: street.height)), with: .color(.black.opacity(0.18)))
        }

        /// Warm sun from the top left, and the corners falling away.
        /// (A gradient over the whole picture costs more than everything on the lawn: the light is a warm corner and shaded edges.)
        private func light(_ g: GraphicsContext, _ f: Frame) {
            let corner = CGRect(x: 0, y: 0, width: f.width * 0.45, height: f.height * 0.45)
            g.fill(Path(corner), with: radial([rgb(1, 0.95, 0.75, 0.16), rgb(1, 0.95, 0.75, 0)], .zero, f.width * 0.45))
            g.fill(Path(CGRect(x: 0, y: f.height - f.row * 0.3, width: f.width, height: f.row * 0.3)),
                   with: linear([.black.opacity(0), .black.opacity(0.14)], CGPoint(x: 0, y: f.height - f.row * 0.3), CGPoint(x: 0, y: f.height)))
        }

        /// Scorched grass where a cherry bomb went off.
        private func scorches(_ g: GraphicsContext, _ f: Frame, beat: Double) {
            for b in after.booms {
                let age = since + Double(after.tick - b.tick) * beat
                let fade = max(0, min(1, 2.4 - age))
                guard fade > 0 else { continue }
                let c = CGPoint(x: f.x(Double(b.col) + 0.5), y: f.ground(b.lane) - f.row * 0.15)
                g.fill(oval(c.x, c.y, f.cell * 1.3, f.row * 0.62), with: radial([rgb(0.1, 0.06, 0.02, 0.6 * fade), rgb(0.2, 0.12, 0.04, 0.25 * fade), .clear], c, f.cell * 1.3))
            }
        }

        /// Where a person's plant would go.
        private func cursor(_ g: GraphicsContext, _ f: Frame, _ seat: Seat) {
            let r = CGRect(x: f.x(Double(seat.col)), y: f.y(Double(seat.lane)), width: f.cell, height: f.row).insetBy(dx: 2.5, dy: 2.5)
            let pulse = 0.5 + 0.5 * sin(now * 5)
            let tint = seat.ok ? Color.white : rgb(1, 0.35, 0.3)
            g.fill(Path(roundedRect: r, cornerRadius: 9), with: .color(tint.opacity(0.18 + 0.1 * pulse)))
            g.stroke(Path(roundedRect: r, cornerRadius: 9), with: .color(tint.opacity(0.75 + 0.25 * pulse)),
                     style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 5], dashPhase: CGFloat(now * 14)))
        }

        /// The chosen plant, see-through, over the cursor's cell.
        private func ghost(_ g: GraphicsContext, _ f: Frame, _ seat: Seat) {
            var c = g
            c.opacity = seat.ok ? 0.55 : 0.3
            let p = Plant(kind: seat.chosen, lane: seat.lane, col: seat.col, health: JevGarden.toughness[seat.chosen], timer: 9, serial: 7, planted: -99)
            plant(c, p, at: CGPoint(x: f.x(Double(seat.col) + 0.5), y: f.ground(seat.lane)), s: f.cell, chewed: false, clock: -1)
        }

        // MARK: Plants

        private func plant(_ g: GraphicsContext, _ p: Plant, at base: CGPoint, s: CGFloat, chewed: Bool, clock: Double) {
            switch p.kind {
            case JevGarden.sunflower:
                let glow = p.made == after.tick ? max(0, 1 - since / 0.7) : 0
                sunflower(g, at: base, s: s, seed: p.serial, glow: glow)
            case JevGarden.peashooter, JevGarden.snowpea:
                let kick = p.fired == after.tick ? max(0, 1 - t * 3.2) : 0
                shooter(g, at: base, s: s, seed: p.serial, kick: kick, snow: p.kind == JevGarden.snowpea)
            case JevGarden.wallnut:
                wallnut(g, at: base, s: s, seed: p.serial, health: Double(p.health) / Double(JevGarden.toughness[JevGarden.wallnut]), chewed: chewed)
            default:
                cherry(g, at: base, s: s, fuse: clock < 0 ? 0 : min(1, max(0, (clock - Double(p.planted)) / Double(JevGarden.fuse))))
            }
        }

        /// A ring of petals as one path: lobes out and back round the face.
        private static func ring(_ n: Int, inner: Double, outer: Double, turn: Double) -> Path {
            var p = Path()
            func at(_ a: Double, _ r: Double) -> CGPoint { CGPoint(x: cos(a) * r, y: sin(a) * r) }
            for k in 0..<n {
                let a0 = (Double(k) + turn) / Double(n) * 2 * .pi, a1 = (Double(k) + 1 + turn) / Double(n) * 2 * .pi, am = (a0 + a1) / 2
                if k == 0 { p.move(to: at(a0, inner)) }
                let side = 0.55 * (a1 - a0)
                p.addCurve(to: at(am, outer), control1: at(a0 - side * 0.3, outer * 0.9), control2: at(am - side, outer))
                p.addCurve(to: at(a1, inner), control1: at(am + side, outer), control2: at(a1 + side * 0.3, outer * 0.9))
            }
            p.closeSubpath()
            return p
        }
        private static let petals = ring(13, inner: 0.12, outer: 0.3, turn: 0)
        private static let backPetals = ring(13, inner: 0.12, outer: 0.31, turn: 0.5)

        /// A sunflower: a ring of petals round a smiling face, swaying on its stem; it glows as it makes sun.
        private func sunflower(_ g: GraphicsContext, at p: CGPoint, s: CGFloat, seed: Int, glow: Double) {
            let sway = sin(now * 1.7 + Double(seed)) * 0.08
            let c = unit(g, at: p, s: s)
            var leaves = leaf(CGPoint(x: 0, y: -0.06), CGPoint(x: -0.3, y: -0.2), width: 0.08)
            leaves.addPath(leaf(CGPoint(x: 0, y: -0.16), CGPoint(x: 0.27, y: -0.3), width: 0.07))
            c.fill(leaves, with: .color(rgb(0.33, 0.66, 0.2)))
            let head = CGPoint(x: CGFloat(sin(sway)) * 0.64, y: -CGFloat(cos(sway)) * 0.64)
            var stem = Path()
            stem.move(to: .zero)
            stem.addQuadCurve(to: head, control: CGPoint(x: -0.06, y: -0.32))
            c.stroke(stem, with: .color(rgb(0.27, 0.6, 0.18)), style: StrokeStyle(lineWidth: 0.07, lineCap: .round))
            var h = c
            h.translateBy(x: head.x, y: head.y)
            h.rotate(by: .radians(sway * 0.7))
            if glow > 0 {
                var light = h
                light.blendMode = .plusLighter
                light.fill(oval(0, 0, 0.5, 0.5), with: radial([rgb(1, 0.9, 0.4, 0.7 * glow), rgb(1, 0.8, 0.2, 0)], .zero, 0.5))
            }
            h.fill(Self.backPetals, with: .color(rgb(0.96, 0.6, 0.08)))
            h.fill(Self.petals, with: .color(rgb(1, 0.84, 0.16)))
            h.fill(oval(-0.06, -0.08, 0.14, 0.12), with: .color(rgb(1, 0.95, 0.55, 0.55)))
            h.fill(oval(0, 0, 0.15, 0.145), with: .color(rgb(0.52, 0.31, 0.1)))
            h.fill(oval(-0.03, -0.04, 0.09, 0.07), with: .color(rgb(0.68, 0.45, 0.2, 0.7)))
            let ink = rgb(0.16, 0.08, 0.02)
            var eyes = oval(-0.05, -0.03, 0.023, 0.033)
            eyes.addPath(oval(0.05, -0.03, 0.023, 0.033))
            h.fill(eyes, with: .color(ink))
            var glints = oval(-0.056, -0.042, 0.008, 0.01)
            glints.addPath(oval(0.044, -0.042, 0.008, 0.01))
            h.fill(glints, with: .color(.white))
            var smile = Path()
            smile.move(to: CGPoint(x: -0.06, y: 0.035))
            smile.addQuadCurve(to: CGPoint(x: 0.06, y: 0.035), control: CGPoint(x: 0, y: 0.1))
            h.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 0.018, lineCap: .round))
            var cheeks = oval(-0.095, 0.03, 0.025, 0.015)
            cheeks.addPath(oval(0.095, 0.03, 0.025, 0.015))
            h.fill(cheeks, with: .color(rgb(1, 0.45, 0.35, 0.5)))
        }

        /// A peashooter: a round green head with a tube for a mouth, recoiling as it fires. The snow pea is the icy one.
        private func shooter(_ g: GraphicsContext, at p: CGPoint, s: CGFloat, seed: Int, kick: Double, snow: Bool) {
            let sway = sin(now * 1.4 + Double(seed) * 1.7) * 0.04
            let c = unit(g, at: p, s: s)
            let dark = snow ? rgb(0.16, 0.42, 0.62) : rgb(0.12, 0.42, 0.08)
            let mid = snow ? rgb(0.45, 0.78, 0.96) : rgb(0.4, 0.76, 0.22)
            let light = snow ? rgb(0.88, 0.98, 1) : rgb(0.74, 0.95, 0.44)
            var leaves = leaf(CGPoint(x: -0.02, y: -0.02), CGPoint(x: -0.3, y: -0.08), width: 0.08)
            leaves.addPath(leaf(CGPoint(x: 0.02, y: -0.02), CGPoint(x: 0.28, y: -0.1), width: 0.075))
            c.fill(leaves, with: .color(rgb(0.3, 0.62, 0.18)))
            let back = CGFloat(kick) * 0.07
            let head = CGPoint(x: CGFloat(sin(sway)) * 0.56 - back, y: -CGFloat(cos(sway)) * 0.56)
            var stem = Path()
            stem.move(to: .zero)
            stem.addQuadCurve(to: CGPoint(x: head.x, y: head.y + 0.1), control: CGPoint(x: 0.07, y: -0.25))
            c.stroke(stem, with: .color(snow ? rgb(0.3, 0.6, 0.62) : rgb(0.25, 0.58, 0.15)), style: StrokeStyle(lineWidth: 0.065, lineCap: .round))
            var h = c
            h.translateBy(x: head.x, y: head.y)
            h.rotate(by: .radians(sway))
            // The tuft at the back of the head.
            h.fill(leaf(CGPoint(x: -0.13, y: -0.1), CGPoint(x: -0.34, y: -0.2), width: 0.06), with: .color(dark))
            // The tube, squashed as it fires.
            let long = 0.27 * (1 - 0.25 * CGFloat(kick))
            let tube = Path(roundedRect: CGRect(x: 0.05, y: -0.085, width: long, height: 0.17), cornerRadius: 0.07)
            h.fill(tube, with: .color(mid))
            h.fill(Path(roundedRect: CGRect(x: 0.07, y: -0.07, width: long - 0.04, height: 0.045), cornerRadius: 0.02), with: .color(light.opacity(0.7)))
            h.fill(oval(0, 0, 0.2, 0.19), with: .color(mid))
            h.fill(oval(0.02, 0.05, 0.17, 0.13), with: .color(dark.opacity(0.35)))
            h.fill(oval(-0.06, -0.07, 0.1, 0.075), with: .color(light.opacity(0.8)))
            h.stroke(oval(0, 0, 0.2, 0.19), with: .color(dark), lineWidth: 0.012)
            h.fill(oval(0.05 + long, 0, 0.045 + 0.02 * CGFloat(kick), 0.1 + 0.015 * CGFloat(kick)), with: .color(dark))
            h.fill(oval(0.055 + long, 0, 0.026, 0.066), with: .color(snow ? rgb(0.05, 0.18, 0.3) : rgb(0.04, 0.16, 0.02)))
            var white = oval(0.03, -0.075, 0.05, 0.06)
            white.addPath(oval(0.042, -0.085, 0.009, 0.011))
            h.fill(white, with: .color(.white), style: FillStyle(eoFill: true))
            h.fill(oval(0.05, -0.07, 0.026, 0.036), with: .color(rgb(0.05, 0.05, 0.05)))
            h.fill(oval(0.042, -0.085, 0.009, 0.011), with: .color(.white))
            if snow {
                // Frost on its head: a crown of ice.
                var ice = Path()
                for (x, tall) in [(-0.12, 0.1), (-0.05, 0.14), (0.03, 0.11), (0.1, 0.08)] as [(CGFloat, CGFloat)] {
                    let y = -sqrt(max(0.0001, 0.036 - x * x * 0.9))
                    ice.move(to: CGPoint(x: x - 0.035, y: y + 0.01)); ice.addLine(to: CGPoint(x: x, y: y - tall)); ice.addLine(to: CGPoint(x: x + 0.035, y: y + 0.01)); ice.closeSubpath()
                }
                h.fill(ice, with: linear([.white, rgb(0.6, 0.88, 1)], CGPoint(x: 0, y: -0.34), CGPoint(x: 0, y: -0.16)))
                h.stroke(ice, with: .color(rgb(0.3, 0.6, 0.85, 0.7)), lineWidth: 0.008)
            }
        }

        /// A wall-nut: a big brown nut with a stubborn face, cracking as it is eaten.
        private func wallnut(_ g: GraphicsContext, at p: CGPoint, s: CGFloat, seed: Int, health: Double, chewed: Bool) {
            let wobble = chewed ? sin(now * 34) * 0.035 : sin(now * 1.3 + Double(seed)) * 0.015
            let c = unit(g, at: p, s: s, turn: wobble)
            let body = oval(0, -0.38, 0.31, 0.38)
            c.fill(body, with: radial([rgb(0.95, 0.78, 0.5), rgb(0.78, 0.53, 0.27), rgb(0.5, 0.3, 0.12)], CGPoint(x: -0.11, y: -0.55), 0.55))
            var grain = Path()
            grain.move(to: CGPoint(x: -0.2, y: -0.62)); grain.addQuadCurve(to: CGPoint(x: -0.24, y: -0.2), control: CGPoint(x: -0.29, y: -0.42))
            grain.move(to: CGPoint(x: 0.21, y: -0.6)); grain.addQuadCurve(to: CGPoint(x: 0.24, y: -0.18), control: CGPoint(x: 0.29, y: -0.4))
            grain.move(to: CGPoint(x: -0.05, y: -0.72)); grain.addQuadCurve(to: CGPoint(x: 0.08, y: -0.7), control: CGPoint(x: 0.01, y: -0.75))
            c.stroke(grain, with: .color(rgb(0.45, 0.26, 0.1, 0.55)), style: StrokeStyle(lineWidth: 0.014, lineCap: .round))
            c.stroke(body, with: .color(rgb(0.34, 0.19, 0.06)), lineWidth: 0.02)
            let ink = rgb(0.12, 0.06, 0.02)
            for x in [-0.02, 0.13] as [CGFloat] {
                c.fill(oval(x, -0.44, 0.058, 0.072), with: .color(.white))
                c.fill(oval(x + 0.02, -0.43, 0.026, 0.034), with: .color(ink))
            }
            if health < 0.5 {
                var brows = Path()
                brows.move(to: CGPoint(x: -0.08, y: -0.54)); brows.addLine(to: CGPoint(x: 0.02, y: -0.51))
                brows.move(to: CGPoint(x: 0.19, y: -0.54)); brows.addLine(to: CGPoint(x: 0.1, y: -0.51))
                c.stroke(brows, with: .color(ink), style: StrokeStyle(lineWidth: 0.02, lineCap: .round))
            }
            var mouth = Path()
            mouth.move(to: CGPoint(x: 0.0, y: -0.28))
            if health < 0.5 { mouth.addQuadCurve(to: CGPoint(x: 0.13, y: -0.28), control: CGPoint(x: 0.065, y: -0.32)) }
            else { mouth.addQuadCurve(to: CGPoint(x: 0.13, y: -0.29), control: CGPoint(x: 0.065, y: -0.26)) }
            c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 0.018, lineCap: .round))
            if health < 0.67 {
                var crack = Path()
                crack.move(to: CGPoint(x: -0.29, y: -0.5)); crack.addLine(to: CGPoint(x: -0.2, y: -0.47)); crack.addLine(to: CGPoint(x: -0.18, y: -0.38)); crack.addLine(to: CGPoint(x: -0.1, y: -0.34))
                crack.move(to: CGPoint(x: 0.1, y: -0.75)); crack.addLine(to: CGPoint(x: 0.07, y: -0.66)); crack.addLine(to: CGPoint(x: 0.12, y: -0.6))
                if health < 0.34 {
                    crack.move(to: CGPoint(x: 0.3, y: -0.3)); crack.addLine(to: CGPoint(x: 0.2, y: -0.25)); crack.addLine(to: CGPoint(x: 0.19, y: -0.15)); crack.addLine(to: CGPoint(x: 0.1, y: -0.1))
                    crack.move(to: CGPoint(x: -0.26, y: -0.18)); crack.addLine(to: CGPoint(x: -0.16, y: -0.16)); crack.addLine(to: CGPoint(x: -0.12, y: -0.06))
                }
                c.stroke(crack, with: .color(rgb(0.25, 0.12, 0.03)), style: StrokeStyle(lineWidth: 0.02, lineCap: .round, lineJoin: .round))
            }
        }

        /// A cherry bomb: two angry cherries on one stalk, a spark fizzing at the top, swelling as the fuse burns.
        private func cherry(_ g: GraphicsContext, at p: CGPoint, s: CGFloat, fuse: Double) {
            let swell = 1 + 0.2 * fuse + 0.05 * fuse * sin(now * 45)
            var c = unit(g, at: p, s: s)
            c.scaleBy(x: CGFloat(swell), y: CGFloat(swell))
            var stalks = Path()
            stalks.move(to: CGPoint(x: -0.14, y: -0.36)); stalks.addQuadCurve(to: CGPoint(x: 0.02, y: -0.74), control: CGPoint(x: -0.14, y: -0.6))
            stalks.move(to: CGPoint(x: 0.15, y: -0.34)); stalks.addQuadCurve(to: CGPoint(x: 0.02, y: -0.74), control: CGPoint(x: 0.14, y: -0.58))
            c.stroke(stalks, with: .color(rgb(0.25, 0.5, 0.14)), style: StrokeStyle(lineWidth: 0.035, lineCap: .round))
            c.fill(leaf(CGPoint(x: 0.02, y: -0.72), CGPoint(x: 0.26, y: -0.8), width: 0.06), with: linear([rgb(0.5, 0.82, 0.3), rgb(0.2, 0.5, 0.12)], CGPoint(x: 0, y: -0.8), CGPoint(x: 0.26, y: -0.72)))
            let red = [rgb(1, 0.5, 0.45), rgb(0.88, 0.08, 0.12), rgb(0.5, 0.0, 0.05)]
            for (x, y) in [(-0.15, -0.21), (0.15, -0.19)] as [(CGFloat, CGFloat)] {
                c.fill(oval(x, y, 0.17, 0.17), with: radial(red, CGPoint(x: x - 0.06, y: y - 0.07), 0.24))
                c.stroke(oval(x, y, 0.17, 0.17), with: .color(rgb(0.35, 0.0, 0.03)), lineWidth: 0.014)
                c.fill(oval(x - 0.07, y - 0.08, 0.035, 0.022), with: .color(.white.opacity(0.7)))
                var brows = Path()
                brows.move(to: CGPoint(x: x - 0.08, y: y - 0.06)); brows.addLine(to: CGPoint(x: x - 0.01, y: y - 0.02))
                brows.move(to: CGPoint(x: x + 0.08, y: y - 0.06)); brows.addLine(to: CGPoint(x: x + 0.01, y: y - 0.02))
                c.stroke(brows, with: .color(rgb(0.15, 0.0, 0.0)), style: StrokeStyle(lineWidth: 0.022, lineCap: .round))
                c.fill(oval(x - 0.04, y + 0.01, 0.02, 0.024), with: .color(.black))
                c.fill(oval(x + 0.04, y + 0.01, 0.02, 0.024), with: .color(.black))
                c.fill(oval(x, y + 0.08, 0.04, 0.018 + 0.02 * CGFloat(fuse)), with: .color(rgb(0.25, 0.0, 0.02)))
            }
            // The spark.
            var spark = c
            spark.blendMode = .plusLighter
            let flicker = CGFloat(0.8 + 0.2 * sin(now * 37) + 0.1 * sin(now * 23))
            let q = CGPoint(x: 0.02, y: -0.76)
            spark.fill(oval(q.x, q.y, 0.14 * flicker, 0.14 * flicker), with: radial([rgb(1, 0.9, 0.5, 0.9), rgb(1, 0.5, 0.1, 0)], q, 0.14 * flicker))
            var star = Path()
            for k in 0..<8 {
                let a = now * 6 + Double(k) * .pi / 4
                let r: CGFloat = k % 2 == 0 ? 0.11 * flicker : 0.05
                star.move(to: q); star.addLine(to: CGPoint(x: q.x + CGFloat(cos(a)) * r, y: q.y + CGFloat(sin(a)) * r))
            }
            spark.stroke(star, with: .color(rgb(1, 0.95, 0.7)), style: StrokeStyle(lineWidth: 0.018, lineCap: .round))
        }

        /// A puff of dirt where something was just planted.
        private func puff(_ g: GraphicsContext, at p: CGPoint, s: CGFloat, age: Double) {
            let fade = 1 - age
            var dirt = Path()
            for k in 0..<7 {
                let a = Double(k) / 7 * .pi + .pi
                let reach = s * CGFloat(0.2 + 0.25 * age)
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * reach, y: p.y + CGFloat(sin(a)) * reach * 0.45)
                let r = s * 0.05 * CGFloat(1 - age * 0.5)
                dirt.addEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
            }
            g.fill(dirt, with: .color(rgb(0.5, 0.36, 0.2, 0.8 * fade)))
        }

        // MARK: Zombies

        /// A zombie: grey-green skin, a torn coat and a red tie, arms out,
        /// shambling to the left — a cone or a bucket on its head while it
        /// lasts, the runner in a tracksuit. It flashes when hit, turns blue
        /// when slowed, and topples over backwards when it dies.
        private func zombie(_ g: GraphicsContext, _ z: Zombie, at p: CGPoint, s: CGFloat, walk: Double, flash: Double, fall: Double?) {
            let dying = fall != nil
            let eating = z.eating && !dying
            let runner = z.breed == 3
            let swing = eating ? 0 : sin(walk)
            let chomp = eating ? sin(now * 11 + Double(z.serial)) : 0
            var lean = -0.05 + swing * 0.035 + (runner ? -0.1 : 0)
            if eating { lean = -0.12 + chomp * 0.04 }
            var c = g
            if let fall {
                if fall > 1.1 { return }
                c.opacity = fall < 0.6 ? 1 : max(0, 1 - (fall - 0.6) / 0.5)
            }
            c.translateBy(x: p.x, y: p.y)
            if let fall { let k = min(1, fall / 0.5); c.rotate(by: .radians(k * k * 1.4)) }
            c.rotate(by: .radians(lean))
            c.scaleBy(x: s, y: s)
            let burnt = z.burnt && dying
            let skinLight = burnt ? rgb(0.22, 0.2, 0.18) : rgb(0.74, 0.82, 0.62)
            let skinDark = burnt ? rgb(0.08, 0.07, 0.06) : rgb(0.43, 0.54, 0.4)
            let coatLight = burnt ? rgb(0.18, 0.16, 0.14) : runner ? rgb(0.35, 0.5, 0.86) : rgb(0.6, 0.47, 0.34)
            let coatDark = burnt ? rgb(0.06, 0.05, 0.05) : runner ? rgb(0.14, 0.2, 0.5) : rgb(0.35, 0.25, 0.17)
            let legs = burnt ? rgb(0.1, 0.09, 0.08) : runner ? rgb(0.18, 0.24, 0.52) : rgb(0.35, 0.36, 0.45)
            let ink = rgb(0.1, 0.12, 0.08, 0.8)

            // Legs, the far one darker, shuffling.
            var shoes = Path()
            for side in [1.0, -1.0] {
                let foot = CGPoint(x: 0.03 + CGFloat(side * swing) * 0.13, y: 0)
                let hip = CGPoint(x: 0.03 + CGFloat(side) * 0.03, y: -0.52)
                var leg = Path()
                leg.move(to: hip)
                leg.addQuadCurve(to: CGPoint(x: foot.x, y: -0.05), control: CGPoint(x: (hip.x + foot.x) / 2 - 0.04, y: -0.28))
                c.stroke(leg, with: .color(side > 0 ? legs.opacity(0.75) : legs), style: StrokeStyle(lineWidth: 0.11, lineCap: .round))
                shoes.addPath(oval(foot.x - 0.05, -0.03, 0.09, 0.045))
            }
            c.fill(shoes, with: .color(burnt ? rgb(0.05, 0.05, 0.05) : rgb(0.24, 0.16, 0.1)))
            // The far arm.
            let reach: CGFloat = eating ? -0.38 : -0.42
            let armY: CGFloat = eating ? -0.8 + CGFloat(chomp) * 0.05 : -0.9
            var far = Path()
            far.move(to: CGPoint(x: 0.08, y: -0.94))
            far.addQuadCurve(to: CGPoint(x: reach + 0.07, y: armY + CGFloat(swing) * 0.04), control: CGPoint(x: -0.1, y: -0.99))
            c.stroke(far, with: .color(coatDark), style: StrokeStyle(lineWidth: 0.09, lineCap: .round))
            var hands = oval(reach + 0.04, armY + CGFloat(swing) * 0.04, 0.05, 0.045)
            // The coat, torn at the hem, over a shirt and a red tie.
            var torso = Path()
            torso.move(to: CGPoint(x: -0.17, y: -1.01))
            torso.addLine(to: CGPoint(x: 0.17, y: -0.99))
            torso.addLine(to: CGPoint(x: 0.2, y: -0.55))
            for (x, y) in [(0.13, -0.48), (0.08, -0.55), (0.02, -0.47), (-0.05, -0.55), (-0.11, -0.48), (-0.19, -0.56)] as [(CGFloat, CGFloat)] {
                torso.addLine(to: CGPoint(x: x, y: y))
            }
            torso.closeSubpath()
            c.fill(torso, with: .color(coatLight))
            var side = Path()
            side.move(to: CGPoint(x: 0.06, y: -1.0)); side.addLine(to: CGPoint(x: 0.17, y: -0.99)); side.addLine(to: CGPoint(x: 0.2, y: -0.55))
            side.addLine(to: CGPoint(x: 0.13, y: -0.48)); side.addLine(to: CGPoint(x: 0.08, y: -0.55)); side.closeSubpath()
            c.fill(side, with: .color(coatDark.opacity(0.55)))
            if !burnt {
                var shirt = Path()
                shirt.move(to: CGPoint(x: -0.1, y: -1.0)); shirt.addLine(to: CGPoint(x: 0.05, y: -1.0)); shirt.addLine(to: CGPoint(x: -0.03, y: -0.78)); shirt.closeSubpath()
                c.fill(shirt, with: .color(runner ? rgb(0.95, 0.95, 0.95) : rgb(0.88, 0.86, 0.78)))
                var tie = Path()
                tie.move(to: CGPoint(x: -0.05, y: -0.99)); tie.addLine(to: CGPoint(x: 0.0, y: -0.99)); tie.addLine(to: CGPoint(x: 0.01, y: -0.73))
                tie.addLine(to: CGPoint(x: -0.025, y: -0.68)); tie.addLine(to: CGPoint(x: -0.06, y: -0.73)); tie.closeSubpath()
                c.fill(tie, with: .color(runner ? rgb(0.9, 0.2, 0.15) : rgb(0.78, 0.1, 0.1)))
                if runner {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: 0.15, y: -0.98)); stripe.addLine(to: CGPoint(x: 0.18, y: -0.56))
                    c.stroke(stripe, with: .color(.white.opacity(0.85)), lineWidth: 0.03)
                }
            }
            c.stroke(torso, with: .color(ink), lineWidth: 0.016)
            // The near arm.
            var near = Path()
            near.move(to: CGPoint(x: -0.08, y: -0.95))
            near.addQuadCurve(to: CGPoint(x: reach, y: armY - 0.03 - CGFloat(swing) * 0.04), control: CGPoint(x: -0.26, y: -0.98))
            c.stroke(near, with: .color(coatLight), style: StrokeStyle(lineWidth: 0.095, lineCap: .round))
            hands.addPath(oval(reach - 0.03, armY - 0.03 - CGFloat(swing) * 0.04, 0.055, 0.05))
            c.fill(hands, with: .color(skinLight))
            // The head, bobbing, chewing when it eats.
            var h = c
            h.translateBy(x: -0.03, y: -1.2)
            h.rotate(by: .radians(eating ? chomp * 0.09 : swing * 0.05 + sin(now * 2 + Double(z.serial)) * 0.03))
            let skull = oval(0, 0, 0.2, 0.22)
            h.fill(oval(0.16, 0.01, 0.04, 0.06), with: .color(skinDark))
            h.fill(skull, with: .color(skinDark))
            h.fill(oval(-0.035, -0.04, 0.155, 0.165), with: .color(skinLight))
            h.stroke(skull, with: .color(ink), lineWidth: 0.016)
            if !burnt {
                var whites = oval(-0.1, -0.035, 0.066, 0.072), pupils = oval(-0.125, -0.03, 0.022, 0.022)
                whites.addPath(oval(0.01, -0.05, 0.048, 0.054)); pupils.addPath(oval(-0.005, -0.045, 0.017, 0.017))
                h.fill(whites, with: .color(rgb(0.97, 0.97, 0.88)))
                h.fill(pupils, with: .color(rgb(0.1, 0.1, 0.1)))
            }
            let open = eating ? 0.028 + 0.03 * CGFloat(chomp + 1) : 0.022
            h.fill(oval(-0.09, 0.11, 0.075, open), with: .color(rgb(0.22, 0.05, 0.06)))
            if !burnt {
                var hair = Path()
                hair.move(to: CGPoint(x: -0.02, y: -0.21)); hair.addQuadCurve(to: CGPoint(x: 0.04, y: -0.3), control: CGPoint(x: -0.03, y: -0.29))
                hair.move(to: CGPoint(x: 0.05, y: -0.2)); hair.addQuadCurve(to: CGPoint(x: 0.12, y: -0.27), control: CGPoint(x: 0.07, y: -0.28))
                h.stroke(hair, with: .color(rgb(0.2, 0.2, 0.15)), style: StrokeStyle(lineWidth: 0.014, lineCap: .round))
            }
            // What it wears on its head.
            if z.hatted, z.breed == 1 {
                var cone = Path()
                cone.move(to: CGPoint(x: -0.2, y: -0.13)); cone.addLine(to: CGPoint(x: 0.16, y: -0.15)); cone.addLine(to: CGPoint(x: -0.04, y: -0.6)); cone.closeSubpath()
                h.fill(cone, with: linear(burnt ? [rgb(0.2, 0.1, 0.05), rgb(0.1, 0.05, 0.02)] : [rgb(1, 0.66, 0.25), rgb(0.93, 0.42, 0.06), rgb(0.72, 0.28, 0.02)],
                                          CGPoint(x: -0.2, y: -0.4), CGPoint(x: 0.16, y: -0.3)))
                // The white band, between y -0.4 and -0.33, cut to the cone's sides.
                var band = Path()
                band.move(to: CGPoint(x: -0.134, y: -0.33)); band.addLine(to: CGPoint(x: 0.084, y: -0.33))
                band.addLine(to: CGPoint(x: 0.049, y: -0.4)); band.addLine(to: CGPoint(x: -0.101, y: -0.4)); band.closeSubpath()
                h.fill(band, with: .color(.white.opacity(burnt ? 0.1 : 0.85)))
                h.stroke(cone, with: .color(rgb(0.45, 0.18, 0.0, 0.8)), lineWidth: 0.014)
                h.fill(oval(-0.02, -0.14, 0.23, 0.045), with: .color(burnt ? rgb(0.12, 0.06, 0.03) : rgb(0.85, 0.36, 0.04)))
            } else if z.hatted, z.breed == 2 {
                var pail = Path()
                pail.move(to: CGPoint(x: -0.24, y: -0.08)); pail.addLine(to: CGPoint(x: 0.2, y: -0.1))
                pail.addLine(to: CGPoint(x: 0.16, y: -0.43)); pail.addLine(to: CGPoint(x: -0.2, y: -0.41)); pail.closeSubpath()
                h.fill(pail, with: linear(burnt ? [rgb(0.25, 0.25, 0.25), rgb(0.1, 0.1, 0.1)] : [rgb(0.94, 0.96, 0.98), rgb(0.66, 0.7, 0.74), rgb(0.42, 0.45, 0.5)],
                                          CGPoint(x: -0.24, y: -0.3), CGPoint(x: 0.2, y: -0.2)))
                h.stroke(pail, with: .color(rgb(0.2, 0.22, 0.26)), lineWidth: 0.014)
                h.fill(oval(-0.02, -0.09, 0.23, 0.035), with: .color(rgb(0.36, 0.38, 0.42)))
                h.fill(oval(-0.02, -0.42, 0.18, 0.03), with: .color(rgb(0.78, 0.8, 0.84)))
                h.fill(Path(CGRect(x: -0.17, y: -0.36, width: 0.03, height: 0.2)), with: .color(.white.opacity(burnt ? 0.05 : 0.5)))
            } else if runner {
                h.fill(Path(roundedRect: CGRect(x: -0.2, y: -0.15, width: 0.4, height: 0.07), cornerRadius: 0.02), with: .color(burnt ? rgb(0.1, 0.05, 0.05) : rgb(0.92, 0.18, 0.14)))
                var tail = Path()
                tail.move(to: CGPoint(x: 0.19, y: -0.12)); tail.addLine(to: CGPoint(x: 0.3, y: -0.06 + CGFloat(sin(now * 12)) * 0.03))
                h.stroke(tail, with: .color(rgb(0.92, 0.18, 0.14)), style: StrokeStyle(lineWidth: 0.035, lineCap: .round))
            }
            // Hit: a white flash over it. Slowed: blue, with frost.
            if flash > 0 || (z.slow > 0 && !dying) {
                var body = torso
                body.addPath(skull, transform: CGAffineTransform(translationX: -0.03, y: -1.2))
                if flash > 0 { c.fill(body, with: .color(.white.opacity(0.6 * flash))) }
                if z.slow > 0, !dying {
                    c.fill(body, with: .color(rgb(0.45, 0.75, 1, 0.35)))
                    var frost = Path()
                    for k in 0..<5 {
                        let x = -0.15 + 0.08 * CGFloat(k), y = -0.6 - 0.1 * CGFloat(k % 3)
                        frost.move(to: CGPoint(x: x - 0.025, y: y)); frost.addLine(to: CGPoint(x: x + 0.025, y: y))
                        frost.move(to: CGPoint(x: x, y: y - 0.025)); frost.addLine(to: CGPoint(x: x, y: y + 0.025))
                    }
                    c.stroke(frost, with: .color(.white.opacity(0.8)), lineWidth: 0.012)
                }
            }
        }

        // MARK: Peas, sun, mowers, fire

        private func pea(_ g: GraphicsContext, at p: CGPoint, r: CGFloat, frozen: Bool, ground: CGFloat) {
            g.fill(oval(p.x + r * 0.3, ground - r * 0.2, r * 0.9, r * 0.3), with: .color(.black.opacity(0.14)))
            if frozen {
                var glow = g
                glow.blendMode = .plusLighter
                glow.fill(oval(p.x - r * 0.6, p.y, r * 2.4, r * 1.6), with: radial([rgb(0.5, 0.85, 1, 0.5), rgb(0.4, 0.7, 1, 0)], CGPoint(x: p.x - r * 0.6, y: p.y), r * 2.4))
            }
            g.fill(oval(p.x, p.y, r, r), with: .color(frozen ? rgb(0.45, 0.78, 1) : rgb(0.4, 0.8, 0.18)))
            g.stroke(oval(p.x, p.y, r, r), with: .color(frozen ? rgb(0.1, 0.3, 0.6, 0.8) : rgb(0.1, 0.35, 0.03, 0.8)), lineWidth: 0.8)
            g.fill(oval(p.x - r * 0.3, p.y - r * 0.32, r * 0.42, r * 0.36), with: .color(frozen ? .white : rgb(0.85, 1, 0.62)))
        }

        /// A pea bursting on what it hit.
        private func splash(_ g: GraphicsContext, at p: CGPoint, s: CGFloat, age: Double, frozen: Bool, seed: Int) {
            guard age < 0.3 else { return }
            let k = age / 0.3, fade = 1 - k
            var drops = Path()
            for i in 0..<6 {
                let a = Double(i) / 6 * 2 * .pi + Self.number(seed, i)
                let reach = s * CGFloat(0.08 + 0.18 * k)
                let q = CGPoint(x: p.x + CGFloat(cos(a)) * reach, y: p.y + CGFloat(sin(a)) * reach * 0.8)
                let r = s * 0.035 * CGFloat(1 - k * 0.6)
                drops.addEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
            }
            let colour = frozen ? rgb(0.75, 0.95, 1) : rgb(0.55, 0.9, 0.25)
            g.fill(drops, with: .color(colour.opacity(fade)))
            g.fill(oval(p.x, p.y, s * 0.08 * CGFloat(1 + k), s * 0.1 * CGFloat(1 - k * 0.5)), with: .color(colour.opacity(0.8 * fade)))
        }

        private static let rays: Path = {
            var p = Path()
            let n = 12
            for k in 0..<(2 * n) {
                let a = Double(k) / Double(2 * n) * 2 * .pi
                let r = k % 2 == 0 ? 1.0 : 0.62
                let q = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
            return p
        }()

        private func sunDisc(_ g: GraphicsContext, at p: CGPoint, r: CGFloat, spin: Double, alpha: Double = 1) {
            var glow = g
            glow.blendMode = .plusLighter
            glow.opacity = alpha
            glow.fill(oval(p.x, p.y, r * 2, r * 2), with: radial([rgb(1, 0.92, 0.45, 0.6), rgb(1, 0.8, 0.2, 0)], p, r * 2))
            var c = g
            c.opacity = alpha
            c.fill(Self.rays.applying(CGAffineTransform(translationX: p.x, y: p.y).rotated(by: CGFloat(spin)).scaledBy(x: r, y: r)), with: .color(rgb(1, 0.78, 0.12, 0.9)))
            c.fill(oval(p.x, p.y, r * 0.7, r * 0.7), with: radial([rgb(1, 1, 0.88), rgb(1, 0.88, 0.32), rgb(0.98, 0.64, 0.06)], CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.22), r * 0.85))
        }

        /// Sun falling from the sky, or popping out of a sunflower, settling a moment, then flying up to the counter.
        private func suns(_ g: GraphicsContext, _ f: Frame, clock: Double) {
            let live = Set(after.suns.map(\.serial))
            let flying = before.suns.filter { !live.contains($0.serial) }
            let r = f.cell * 0.26
            for s in after.suns + flying {
                let age = clock - Double(s.born - 1)
                let life = Double(s.due - s.born + 1)
                let rest = CGPoint(x: f.x(s.x), y: f.y(s.y))
                var at = rest
                var size = r
                if age >= life - 1 {
                    // Up to the counter, quickly.
                    let k = CGFloat(JevDraw.smooth(age - (life - 1)))
                    at = CGPoint(x: rest.x + (f.counter.x - rest.x) * k, y: rest.y + (f.counter.y - rest.y) * k - sin(k * .pi) * f.row * 0.4)
                    size = r * (1 - 0.35 * k)
                } else if s.sky {
                    let k = min(1, age / 5)
                    let fall = 1 - (1 - k) * (1 - k)
                    at = CGPoint(x: rest.x + CGFloat(sin(age * 1.3 + Double(s.serial))) * f.cell * 0.1 * CGFloat(1 - k),
                                 y: f.top - r + (rest.y - f.top + r) * CGFloat(fall))
                } else {
                    let k = min(1, age / 1.1)
                    let start = CGPoint(x: rest.x - f.cell * 0.36, y: rest.y - f.row * 0.55)
                    at = CGPoint(x: start.x + (rest.x - start.x) * CGFloat(k), y: start.y + (rest.y - start.y) * CGFloat(k) - sin(CGFloat(k) * .pi) * f.row * 0.35)
                    size = r * CGFloat(0.4 + 0.6 * min(1, age / 0.4))
                }
                if age > 0 { sunDisc(g, at: at, r: size, spin: now * 0.8 + Double(s.serial)) }
            }
        }

        private func mower(_ g: GraphicsContext, _ f: Frame, _ lane: Int) {
            var x: Double
            var running = false
            if after.ready(lane) { x = -0.45 }
            else if after.mowing[lane] { x = JevDraw.mix(before.mower[lane], after.mower[lane], t); running = true }
            else if before.mowing[lane] { x = before.mower[lane] + JevGarden.mowerSpeed * t; running = true }
            else { return }
            guard x < Double(JevGarden.columns) + 1 else { return }
            let base = CGPoint(x: f.x(x), y: f.ground(lane))
            shadow(g, at: base, width: f.cell * 0.3)
            let bump = running ? CGFloat(abs(sin(now * 30))) * f.cell * 0.02 : 0
            let c = unit(g, at: CGPoint(x: base.x, y: base.y - bump), s: f.cell * 0.95)
            if running {
                // Grass flung out behind it, and the blur of speed.
                var bits = Path()
                for k in 0..<9 {
                    let u = (now * 3 + Double(k) / 9).truncatingRemainder(dividingBy: 1)
                    let q = CGPoint(x: -0.25 - CGFloat(u) * 0.7 + CGFloat(Self.number(k, 5)) * 0.1, y: -0.1 - CGFloat(sin(u * .pi)) * 0.35 * CGFloat(0.5 + Self.number(k, 6)))
                    bits.addRect(CGRect(x: q.x, y: q.y, width: 0.035, height: 0.02))
                }
                c.fill(bits, with: .color(rgb(0.3, 0.62, 0.15, 0.85)))
                var blur = Path()
                for y in [-0.3, -0.2, -0.12] as [CGFloat] { blur.move(to: CGPoint(x: -0.3, y: y)); blur.addLine(to: CGPoint(x: -0.75, y: y)) }
                c.stroke(blur, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 0.025, lineCap: .round))
            }
            var handle = Path()
            handle.move(to: CGPoint(x: -0.12, y: -0.22)); handle.addLine(to: CGPoint(x: -0.32, y: -0.52))
            c.stroke(handle, with: .color(rgb(0.3, 0.3, 0.32)), style: StrokeStyle(lineWidth: 0.04, lineCap: .round))
            c.fill(Path(roundedRect: CGRect(x: -0.42, y: -0.56, width: 0.16, height: 0.06), cornerRadius: 0.03), with: .color(rgb(0.12, 0.12, 0.12)))
            let body = Path(roundedRect: CGRect(x: -0.22, y: -0.3, width: 0.46, height: 0.2), cornerRadius: 0.06)
            c.fill(body, with: .color(rgb(0.84, 0.12, 0.1)))
            c.fill(Path(roundedRect: CGRect(x: -0.2, y: -0.29, width: 0.42, height: 0.05), cornerRadius: 0.025), with: .color(rgb(1, 0.5, 0.42)))
            c.stroke(body, with: .color(rgb(0.3, 0.02, 0.02)), lineWidth: 0.014)
            c.fill(Path(CGRect(x: -0.2, y: -0.23, width: 0.42, height: 0.025)), with: .color(.white.opacity(0.8)))
            c.fill(Path(roundedRect: CGRect(x: -0.08, y: -0.41, width: 0.18, height: 0.13), cornerRadius: 0.03), with: .color(rgb(0.55, 0.56, 0.6)))
            var wheels = oval(-0.13, -0.08, 0.08, 0.08), hubs = oval(-0.13, -0.08, 0.03, 0.03)
            wheels.addPath(oval(0.15, -0.08, 0.08, 0.08)); hubs.addPath(oval(0.15, -0.08, 0.03, 0.03))
            c.fill(wheels, with: .color(rgb(0.12, 0.12, 0.12)))
            c.fill(hubs, with: .color(rgb(0.8, 0.8, 0.8)))
        }

        /// Cherry bombs going off: a flash over the three by three cells, a shockwave, and the fireball.
        private func booms(_ g: GraphicsContext, _ f: Frame, beat: Double) {
            for b in after.booms {
                let age = since + Double(after.tick - b.tick) * beat
                guard age < 1.3 else { continue }
                let c = CGPoint(x: f.x(Double(b.col) + 0.5), y: f.ground(b.lane) - f.row * 0.35)
                var glow = g
                glow.blendMode = .plusLighter
                if age < 0.4 {
                    let k = 1 - age / 0.4
                    let area = CGRect(x: f.x(Double(b.col) - 1), y: f.y(Double(b.lane) - 1), width: f.cell * 3, height: f.row * 3)
                    glow.fill(Path(roundedRect: area, cornerRadius: f.cell * 0.4), with: radial([rgb(1, 0.95, 0.7, 0.7 * k), rgb(1, 0.5, 0.1, 0.25 * k)], c, f.cell * 2.2))
                }
                if age < 0.8 {
                    let k = age / 0.8, r = f.cell * CGFloat(0.4 + 2.2 * (1 - (1 - k) * (1 - k)))
                    glow.stroke(oval(c.x, c.y, r, r * 0.7), with: .color(rgb(1, 0.85, 0.55, 0.7 * (1 - k))), lineWidth: f.cell * 0.12 * CGFloat(1 - k) + 0.5)
                }
                JevDraw.blast(g, at: c, size: f.cell * 0.95, age: age)
            }
        }

        // MARK: The seed bank and the waves

        /// Smoked glass, lit along its top edge.
        private func glass(_ g: GraphicsContext, _ rect: CGRect, radius: CGFloat) {
            let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            g.fill(Path(roundedRect: rect.offsetBy(dx: 1.5, dy: 2.5), cornerRadius: radius, style: .continuous), with: .color(.black.opacity(0.22)))
            g.fill(shape, with: .color(rgb(0.13, 0.1, 0.07, 0.78)))
            let sheen = CGRect(x: rect.minX + 1.5, y: rect.minY + 1.5, width: rect.width - 3, height: rect.height * 0.46)
            g.fill(Path(roundedRect: sheen, cornerRadius: max(radius - 1.5, 1), style: .continuous), with: .color(.white.opacity(0.09)))
            g.stroke(shape, with: .color(.white.opacity(0.25)), lineWidth: 1)
        }

        private func label(_ g: GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat, colour: Color = .white, weight: Font.Weight = .heavy,
                           anchor: UnitPoint = .center, shadow: Bool = true) {
            // Measured once, drawn twice: laying out text is the dearest thing in the picture.
            var resolved = g.resolve(Text(text).font(.system(size: size, weight: weight, design: .rounded)))
            if shadow {
                resolved.shading = .color(.black.opacity(0.5))
                g.draw(resolved, at: CGPoint(x: p.x + size * 0.03, y: p.y + size * 0.07), anchor: anchor)
            }
            resolved.shading = .color(colour)
            g.draw(resolved, at: p, anchor: anchor)
        }

        private func hud(_ g: GraphicsContext, _ f: Frame, clock: Double) {
            glass(g, f.bank, radius: f.high * 0.18)
            // The sun counter, bouncing when sun comes in.
            let pulse = after.gained > 0 ? max(0, 1 - since / 0.35) : 0
            sunDisc(g, at: f.counter, r: f.high * CGFloat(0.2 + 0.04 * pulse), spin: now * 0.5)
            label(g, "\(after.sun)", at: CGPoint(x: f.counter.x, y: f.bank.maxY - f.high * 0.17), size: f.high * 0.23, colour: pulse > 0 ? rgb(1, 0.95, 0.6) : .white)
            for k in 0..<5 { packet(g, f, k) }
            // The waves: how far through, a flag for each, the big one's red.
            let m = f.meter
            glass(g, m, radius: f.high * 0.18)
            let final = Double(JevGarden.start(of: JevGarden.waves))
            label(g, wave == 0 ? "准备" : "第 \(wave)/\(JevGarden.waves) 波", at: CGPoint(x: m.minX + f.high * 0.25, y: m.minY + f.high * 0.3), size: f.high * 0.24, anchor: .leading)
            label(g, "打倒 \(after.kills)", at: CGPoint(x: m.maxX - f.high * 0.25, y: m.minY + f.high * 0.3), size: f.high * 0.2, colour: rgb(0.75, 0.95, 0.55), weight: .bold, anchor: .trailing)
            let track = CGRect(x: m.minX + f.high * 0.3, y: m.minY + f.high * 0.62, width: m.width - f.high * 0.75, height: f.high * 0.16)
            let trough = Path(roundedRect: track, cornerRadius: track.height / 2)
            g.fill(trough, with: .color(.black.opacity(0.45)))
            let done = min(1, max(0, clock / final))
            if done > 0 {
                let filled = CGRect(x: track.minX, y: track.minY, width: max(track.height, track.width * CGFloat(done)), height: track.height)
                g.fill(Path(roundedRect: filled, cornerRadius: track.height / 2),
                       with: linear([rgb(0.45, 0.85, 0.3), rgb(0.95, 0.8, 0.2), rgb(0.95, 0.3, 0.2)], CGPoint(x: track.minX, y: 0), CGPoint(x: track.maxX, y: 0)))
                g.fill(Path(roundedRect: CGRect(x: filled.minX + 2, y: filled.minY + 1.5, width: max(0, filled.width - 4), height: filled.height * 0.3), cornerRadius: 1),
                       with: .color(.white.opacity(0.35)))
            }
            g.stroke(trough, with: .color(.white.opacity(0.25)), lineWidth: 1)
            var flags = Path(), poles = Path()
            for w in 2...JevGarden.waves {
                let x = track.minX + track.width * CGFloat(Double(JevGarden.start(of: w)) / final)
                let big = w == JevGarden.waves
                let h = track.height * (big ? 2.1 : 1.3)
                poles.move(to: CGPoint(x: x, y: track.midY)); poles.addLine(to: CGPoint(x: x, y: track.midY - h))
                if big {
                    flags.move(to: CGPoint(x: x, y: track.midY - h)); flags.addLine(to: CGPoint(x: x + h * 0.6, y: track.midY - h * 0.8)); flags.addLine(to: CGPoint(x: x, y: track.midY - h * 0.55)); flags.closeSubpath()
                }
            }
            g.stroke(poles, with: .color(.white.opacity(0.6)), lineWidth: 1)
            g.fill(flags, with: .color(rgb(0.95, 0.2, 0.15)))
            // A zombie's head marks how far the waves have come.
            let head = CGPoint(x: track.minX + track.width * CGFloat(done), y: track.midY)
            let hr = track.height * 0.95
            g.fill(oval(head.x, head.y, hr, hr * 1.08), with: radial([rgb(0.78, 0.86, 0.66), rgb(0.45, 0.56, 0.4)], CGPoint(x: head.x - hr * 0.3, y: head.y - hr * 0.3), hr * 1.3))
            g.stroke(oval(head.x, head.y, hr, hr * 1.08), with: .color(rgb(0.15, 0.2, 0.1)), lineWidth: 1)
            g.fill(oval(head.x - hr * 0.35, head.y - hr * 0.15, hr * 0.28, hr * 0.3), with: .color(.white))
            g.fill(oval(head.x - hr * 0.42, head.y - hr * 0.12, hr * 0.1, hr * 0.1), with: .color(.black))
            g.fill(oval(head.x - hr * 0.3, head.y + hr * 0.45, hr * 0.3, hr * 0.12), with: .color(rgb(0.25, 0.05, 0.05)))
        }

        /// A seed packet: the plant on a green card, its price, its key; shaded while it recharges, dimmed when the sun is short.
        private func packet(_ g: GraphicsContext, _ f: Frame, _ k: Int) {
            let picked = seat?.chosen == k
            var r = f.packet(k)
            if picked { r = r.offsetBy(dx: 0, dy: -f.high * 0.05) }
            let affordable = after.sun >= JevGarden.cost[k]
            let charge = JevDraw.mix(Double(before.charging[k]), Double(after.charging[k]), t) / Double(JevGarden.recharge[k])
            let card = Path(roundedRect: r, cornerRadius: r.width * 0.14)
            g.fill(card.applying(CGAffineTransform(translationX: 1.2, y: 2)), with: .color(.black.opacity(0.3)))
            g.fill(card, with: .color(rgb(0.95, 0.9, 0.72)))
            let well = CGRect(x: r.minX + r.width * 0.09, y: r.minY + r.width * 0.09, width: r.width * 0.82, height: r.height * 0.62)
            g.fill(Path(roundedRect: well, cornerRadius: r.width * 0.08), with: .color(rgb(0.58, 0.8, 0.42)))
            let inside = g
            let icon = Plant(kind: k, lane: 0, col: 0, health: JevGarden.toughness[k], timer: 9, serial: k * 3, planted: -99)
            let scale: CGFloat = k == JevGarden.wallnut ? 0.72 : k == JevGarden.cherry ? 0.78 : 0.8
            plant(inside, icon, at: CGPoint(x: well.midX - well.width * (k == JevGarden.peashooter || k == JevGarden.snowpea ? 0.1 : 0), y: well.maxY - well.height * 0.04),
                  s: well.width * scale, chewed: false, clock: -1)
            label(g, "\(JevGarden.cost[k])", at: CGPoint(x: r.midX, y: r.maxY - r.height * 0.155), size: r.height * 0.2,
                  colour: affordable ? rgb(0.28, 0.16, 0.04) : rgb(0.85, 0.1, 0.08), weight: .heavy, shadow: false)
            if charge > 0.001 {
                let shade = CGRect(x: r.minX, y: r.minY, width: r.width, height: max(r.width * 0.28, r.height * CGFloat(min(1, charge))))
                g.fill(Path(roundedRect: shade, cornerRadius: r.width * 0.14), with: .color(.black.opacity(0.5)))
            }
            if !affordable { g.fill(card, with: .color(rgb(0.2, 0.2, 0.2, 0.32))) }
            g.stroke(card, with: .color(picked ? rgb(1, 0.86, 0.25) : rgb(0.42, 0.27, 0.1)), lineWidth: picked ? 2.5 : 1.2)
            if picked {
                var glow = g
                glow.blendMode = .plusLighter
                glow.stroke(card, with: .color(rgb(1, 0.85, 0.3, 0.5 + 0.3 * sin(now * 6))), lineWidth: 5)
            }
            // Its key, in the corner, for a person at the keyboard.
            guard seat != nil else { return }
            let key = CGPoint(x: r.minX + r.width * 0.17, y: r.minY + r.width * 0.17)
            g.fill(oval(key.x, key.y, r.width * 0.14, r.width * 0.14), with: .color(.black.opacity(0.55)))
            label(g, "\(k + 1)", at: key, size: r.width * 0.18, weight: .bold, shadow: false)
        }

        /// 一大波僵尸来了: a banner across the lawn before the big wave.
        private func banner(_ g: GraphicsContext, _ f: Frame, clock: Double) {
            let final = Double(JevGarden.start(of: JevGarden.waves))
            let u = (clock - (final - 10)) / 14
            guard !over, u > 0, u < 1 else { return }
            let alpha = min(1, u * 6, (1 - u) * 5)
            let mid = CGPoint(x: (f.left + f.right) / 2, y: f.top + f.row * 2.5)
            var c = g
            c.opacity = alpha
            let band = CGRect(x: 0, y: mid.y - f.row * 0.55, width: f.width, height: f.row * 1.1)
            c.fill(Path(band), with: linear([.black.opacity(0), .black.opacity(0.45), .black.opacity(0.45), .black.opacity(0)], CGPoint(x: 0, y: band.minY), CGPoint(x: 0, y: band.maxY)))
            let size = f.height * 0.085 * CGFloat(1 + 0.04 * sin(now * 7))
            let shake = CGFloat(sin(now * 43)) * 1.5
            var words = c.resolve(Text("一大波僵尸来了！").font(.system(size: size, weight: .black, design: .rounded)))
            words.shading = .color(rgb(0.3, 0.0, 0.0))
            for (dx, dy) in [(-2, -1), (2, -1), (1, 3)] as [(CGFloat, CGFloat)] {
                c.draw(words, at: CGPoint(x: mid.x + dx + shake, y: mid.y + dy))
            }
            words.shading = .color(rgb(1, 0.27, 0.2))
            c.draw(words, at: CGPoint(x: mid.x + shake, y: mid.y))
        }

        /// Why a person's key did nothing, for a moment under the seed bank.
        private func toast(_ g: GraphicsContext, _ f: Frame, _ text: String, age: Double) {
            let fade = min(1, (1.8 - age) / 0.4)
            var c = g
            c.opacity = max(0, fade)
            let resolved = c.resolve(Text(text).font(.system(size: f.high * 0.22, weight: .bold, design: .rounded)).foregroundColor(.white))
            let size = resolved.measure(in: CGSize(width: f.width, height: f.height))
            let box = CGRect(x: f.bank.midX - size.width / 2 - 12, y: f.top + 6, width: size.width + 24, height: size.height + 10)
            c.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(.black.opacity(0.7)))
            c.draw(resolved, at: CGPoint(x: box.midX, y: box.midY))
        }
    }
}
