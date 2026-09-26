import Foundation

/// 沙盒搭建's builders: who puts a village up round the square in the meadow.
/// The person builds by hand; the script, Jev or a chat model choose what
/// comes next, from options that say in words what the village has and lacks,
/// and the program draws each kind from a template, finds it a site, levels
/// the ground and runs a path from its door to the square. Foundation only.

enum SandboxSeat: String, CaseIterable, Identifiable {
    case me, computer, jev, llm
    var id: String { rawValue }
    var title: String { ["我", "电脑", "Jev", "大模型"][Self.allCases.firstIndex(of: self)!] }
}

enum TownKind: String, CaseIterable, Codable {
    case cottage, townhouse, well, field, tower, church, market, windmill, fountain, lamps, wall, dock, bridge

    var name: String {
        ["小屋", "两层楼房", "水井", "农田", "瞭望塔", "教堂", "集市", "风车", "喷泉", "路灯", "城墙", "码头", "桥"][Self.allCases.firstIndex(of: self)!]
    }
}

struct TownCell: Hashable, Codable { var x: Int; var z: Int }

/// Something the village has put up: what, where, on what ground, how high, and who chose it.
struct TownProject: Codable {
    var kind: TownKind
    var x0: Int, z0: Int, x1: Int, z1: Int
    var base: Int, top: Int
    var by: String
}

/// One thing the village could put up next: its site found, its blocks drawn, the reason in words.
struct TownOption {
    let kind: TownKind
    let words: String
    fileprivate let plan: TownPlan
}

/// A project ready to go: the ground to level first, the blocks, the cell a path leaves from.
/// The land as a decision sees it, measured once: each column's ground, whether water stands on it, whether it is taken.
fileprivate struct Land {
    let height: [Int], water: [Bool], busy: [Bool]
    init(_ w: SandboxWorld, busy: [Bool]) {
        var height = [Int](repeating: 0, count: SandboxWorld.sx * SandboxWorld.sz), water = [Bool](repeating: false, count: height.count)
        for z in 0..<SandboxWorld.sz { for x in 0..<SandboxWorld.sx {
            let g = SandboxTown.ground(w, x, z)
            height[z * SandboxWorld.sx + x] = g
            water[z * SandboxWorld.sx + x] = w[x, g + 1, z] == .water
        } }
        self.height = height; self.water = water; self.busy = busy
    }
    func h(_ x: Int, _ z: Int) -> Int { height[z * SandboxWorld.sx + x] }
    func wet(_ x: Int, _ z: Int) -> Bool { water[z * SandboxWorld.sx + x] }
    func free(_ x: Int, _ z: Int) -> Bool { !busy[z * SandboxWorld.sx + x] }
}

fileprivate struct TownPlan {
    var level: (x0: Int, z0: Int, x1: Int, z1: Int, base: Int)?
    var blocks: [(BlockPos, Block)]
    var front: TownCell?
    var base: Int
}

struct SandboxTown: Codable {
    private(set) var projects: [TownProject] = []
    private(set) var plaza: [Int]?
    private(set) var paths: [TownCell] = []
    private(set) var lampPosts = 0
    /// How much of `paths` already has its lamps.
    private var lit = 0

    static let centre = TownCell(x: SandboxWorld.sx / 2, z: SandboxWorld.sz / 2)

    func count(_ kind: TownKind) -> Int { projects.filter { $0.kind == kind }.count }
    var homes: Int { count(.cottage) + count(.townhouse) }

    // MARK: Saving, next to the world

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KinClaw", isDirectory: true)
        return dir.appendingPathComponent("sandbox.town.json")
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }
    static func load() -> SandboxTown? { (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(SandboxTown.self, from: $0) } }

    // MARK: The ground

    /// The top of the land in a column — not trees, not water.
    static func ground(_ w: SandboxWorld, _ x: Int, _ z: Int) -> Int {
        for y in stride(from: SandboxWorld.sy - 1, through: 0, by: -1) {
            switch w[x, y, z] {
            case .air, .water, .log, .leaves, .pine: continue
            default: return y
            }
        }
        return 0
    }

    /// What a new build cannot go on: anything somebody built, the paths, the square — and water, unless it is meant for it.
    private func taken(_ w: SandboxWorld) -> [Bool] {
        var out = [Bool](repeating: false, count: SandboxWorld.sx * SandboxWorld.sz)
        for y in 0..<SandboxWorld.sy { for z in 0..<SandboxWorld.sz { for x in 0..<SandboxWorld.sx where w.placed[SandboxWorld.index(BlockPos(x: x, y: y, z: z))] {
            out[z * SandboxWorld.sx + x] = true
        } } }
        for c in paths { out[c.z * SandboxWorld.sx + c.x] = true }
        if let p = plaza { for z in p[1]...p[3] { for x in p[0]...p[2] { out[z * SandboxWorld.sx + x] = true } } }
        return out
    }

    // MARK: What could come next

    /// Everything the village could put up now, each with a site; a kind with no room for it is left out.
    func options(_ w: SandboxWorld) -> [TownOption] {
        var rng = UInt64(truncatingIfNeeded: w.seed) &* 0x9E3779B97F4A7C15 &+ UInt64(projects.count + 1) &* 0xBF58476D1CE4E5B9 | 1
        let land = Land(w, busy: taken(w))
        var out: [TownOption] = []
        let homes = self.homes, fields = count(.field), wells = count(.well)
        let tallest = projects.map { $0.top }.max() ?? 0
        func add(_ kind: TownKind, _ words: String, _ plan: TownPlan?) { if let plan { out.append(TownOption(kind: kind, words: words, plan: plan)) } }
        let styleIndex = Int(Self.roll(&rng) * 1000)
        func placed(_ kind: TownKind) -> TownPlan? {
            let t = Self.template(kind, style: styleIndex, &rng)
            return site(t, land)
        }
        // Each option says whether what it answers is short or already enough — a chooser that reads literally needs that said.
        let n = { (k: Int, one: String, many: String) in "\(k) \(k == 1 ? one : many)" }
        let people = max(homes, 1)
        add(.cottage, "a cottage: one more family — \(n(homes, "home", "homes")) now" + (homes < 3 ? "; a village needs at least three homes" : ""), placed(.cottage))
        add(.townhouse, "a two-storey townhouse: one more family, in a bigger home — \(n(homes, "home", "homes")) now, \(count(.townhouse)) of them two storeys", placed(.townhouse))
        if wells <= homes / 4 {
            let words = wells == 0 ? "a well — needed: the village has no water" : wells * 4 >= people
                ? "another well — not needed: \(n(wells, "well serves", "wells serve")) up to \(wells * 4) homes, there are \(homes)"
                : "another well — needed: \(n(wells, "well serves", "wells serve")) up to \(wells * 4) homes, there are \(homes)"
            add(.well, words, placed(.well))
        }
        let fieldWords = fields == 0 ? "a field of crops — needed: the village grows no food" : fields * 3 >= people
            ? "another field — not needed yet: \(n(fields, "field feeds", "fields feed")) up to \(fields * 3) homes, there are \(homes)"
            : "another field — needed: \(n(fields, "field feeds", "fields feed")) up to \(fields * 3) homes, there are \(homes)"
        add(.field, fieldWords, placed(.field))
        func due(_ at: Int) -> String { homes >= at ? "due: a village of \(homes) homes usually has one, and this one has none" : "early: a village gets one at about \(at) homes, this one has \(homes)" }
        if count(.tower) == 0 { add(.tower, "a watchtower 15 high — " + due(4), placed(.tower)) }
        else if count(.tower) < 2, homes >= 9 { add(.tower, "a second watchtower — the village has one; big villages have two", placed(.tower)) }
        if count(.church) == 0 { add(.church, "a church with a bell tower and a spire — " + due(3), placed(.church)) }
        if count(.market) == 0 { add(.market, "a market with stalls, somewhere to trade — " + due(3), placed(.market)) }
        if count(.windmill) == 0 { add(.windmill, "a windmill to grind the grain — " + (fields >= 2 ? "due: \(fields) fields and no mill" : "early: it needs two fields to grind for, there \(fields == 1 ? "is 1" : "are \(fields)")"), placed(.windmill)) }
        if count(.fountain) == 0, plaza != nil || projects.isEmpty { add(.fountain, "a fountain in the middle of the square — " + due(3), fountain(land)) }
        let unlit = paths.count - lit
        if unlit >= 18 { add(.lamps, "lamp posts along the paths — \(unlit) blocks of path are dark", lamps(land)) }
        if count(.wall) == 0, homes >= 3, let (plan, wide, deep) = wall(land) { add(.wall, "a stone wall with gates round the whole village, \(wide) by \(deep) — " + due(8), plan) }
        if count(.dock) == 0, let (plan, far) = dock(land) { add(.dock, "a dock with a boat, on the water \(far) blocks from the square — the village has no way onto the water", plan) }
        if count(.bridge) == 0, let (plan, far, across) = bridge(land) { add(.bridge, "a bridge \(across) blocks across the water, \(far) blocks from the square — nothing reaches the far shore", plan) }
        return out
    }

    /// The village so far, in words, for the ones who choose.
    func situation(_ w: SandboxWorld) -> String {
        if projects.isEmpty { return "Nothing is built yet: an empty meadow, the square to be laid in the middle." }
        let have = TownKind.allCases.compactMap { k -> String? in
            let n = count(k)
            guard n > 0 else { return nil }
            let nouns = [("cottage", "cottages"), ("two-storey townhouse", "two-storey townhouses"), ("well", "wells"), ("field", "fields"), ("watchtower", "watchtowers"),
                         ("church", "churches"), ("market", "markets"), ("windmill", "windmills"), ("fountain", "fountains"), ("row of lamp posts", "rows of lamp posts"),
                         ("wall", "walls"), ("dock", "docks"), ("bridge", "bridges")][TownKind.allCases.firstIndex(of: k)!]
            return "\(n) \(n == 1 ? nouns.0 : nouns.1)"
        }
        let xs = projects.flatMap { [$0.x0, $0.x1] }, zs = projects.flatMap { [$0.z0, $0.z1] }
        let spread = "\((xs.max() ?? 0) - (xs.min() ?? 0) + 1) by \((zs.max() ?? 0) - (zs.min() ?? 0) + 1) blocks"
        return "A village of blocks round a square in a meadow, \(projects.count) things built so far, over \(spread): " + have.joined(separator: ", ")
            + ". Homes for \(homes) famil\(homes == 1 ? "y" : "ies"). The tallest building stands \(projects.map { $0.top }.max() ?? 0) high. \(paths.count) blocks of path."
    }

    static let rules = "You are growing a village in a world of one-metre blocks, one building at a time. A village does well when its people have homes, water and food; then places to meet, trade and pray; then what keeps it safe and makes it fine. Once there is enough of something, more of it adds little."
    static let question = "Which should the village build next?"
    static let howToJudge = "Take what is needed first, then what is due; never what is not needed or early while something is needed or due. Water and food only come first while they are short."

    /// The script: a fixed order of needs, the first one that has a site.
    func scripted(_ options: [TownOption]) -> Int {
        let homes = self.homes, fields = count(.field)
        var want: [TownKind] = []
        if homes == 0 { want.append(.cottage) }
        if count(.well) == 0 { want.append(.well) }
        if homes < 3 { want.append(.cottage) }
        if fields == 0 { want.append(.field) }
        if count(.townhouse) == 0 { want.append(.townhouse) }
        if count(.fountain) == 0 { want.append(.fountain) }
        if count(.market) == 0 { want.append(.market) }
        if count(.tower) == 0 { want.append(.tower) }
        if homes >= 3, count(.church) == 0 { want.append(.church) }
        if fields * 3 < homes { want.append(.field) }
        if fields >= 2, count(.windmill) == 0 { want.append(.windmill) }
        if homes >= 4, count(.dock) == 0 { want.append(.dock) }
        if homes >= 6, count(.bridge) == 0 { want.append(.bridge) }
        want.append(.lamps)
        if homes >= 8, count(.wall) == 0 { want.append(.wall) }
        want += homes % 3 == 2 ? [.townhouse, .cottage] : [.cottage, .townhouse]
        want += [.field, .well, .tower]
        for k in want { if let i = options.firstIndex(where: { $0.kind == k }) { return i } }
        return 0
    }

    // MARK: Putting one up

    /// Level its ground, lay the square the first time, run its path — and hand back its blocks to raise.
    mutating func build(_ option: TownOption, in w: inout SandboxWorld, by who: String) -> [(BlockPos, Block)] {
        if plaza == nil { layPlaza(&w) }
        let plan = option.plan
        if let l = plan.level { Self.level(&w, l.x0, l.z0, l.x1, l.z1, l.base) }
        let xs = plan.blocks.map(\.0.x), ys = plan.blocks.map(\.0.y), zs = plan.blocks.map(\.0.z)
        if let x0 = xs.min(), let x1 = xs.max(), let z0 = zs.min(), let z1 = zs.max(), let y0 = ys.min(), let y1 = ys.max() {
            w.clearTrees(from: BlockPos(x: x0, y: y0, z: z0), to: BlockPos(x: x1, y: y1, z: z1))
            projects.append(TownProject(kind: option.kind, x0: x0, z0: z0, x1: x1, z1: z1, base: plan.base, top: y1 - plan.base, by: who))
        }
        if option.kind == .lamps { lampPosts += plan.blocks.filter { $0.1 == .lamp }.count; lit = paths.count }
        // The path goes round where the building is about to stand.
        if let front = plan.front { pave(from: front, &w, avoiding: Set(plan.blocks.map { TownCell(x: $0.0.x, z: $0.0.z) })) }
        return plan.blocks
    }

    /// The square: seven by seven of cobble, level with the meadow, in the middle of the world.
    private mutating func layPlaza(_ w: inout SandboxWorld) {
        let c = Self.centre, x0 = c.x - 3, z0 = c.z - 3, x1 = c.x + 3, z1 = c.z + 3
        let base = Self.ground(w, c.x, c.z)
        Self.level(&w, x0, z0, x1, z1, base)
        w.clearTrees(from: BlockPos(x: x0, y: base, z: z0), to: BlockPos(x: x1, y: base + 8, z: z1))
        for z in z0...z1 { for x in x0...x1 { w.set(BlockPos(x: x, y: base, z: z), .cobble, placedBy: false) } }
        plaza = [x0, z0, x1, z1]
    }

    /// Flatten a rectangle and a block round it to one height: dig down what stands higher, fill up what lies lower.
    static func level(_ w: inout SandboxWorld, _ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, _ base: Int) {
        for z in max(0, z0 - 1)...min(SandboxWorld.sz - 1, z1 + 1) { for x in max(0, x0 - 1)...min(SandboxWorld.sx - 1, x1 + 1) {
            let g = ground(w, x, z)
            if g > base { for y in (base + 1)...g where !w.placed[SandboxWorld.index(BlockPos(x: x, y: y, z: z))] { w.set(BlockPos(x: x, y: y, z: z), .air, placedBy: false) } }
            if g < base { for y in (g + 1)...base { w.set(BlockPos(x: x, y: y, z: z), y == base ? .grass : .dirt, placedBy: false) } }
            else if w[x, base, z] == .dirt || w[x, base, z] == .stone { w.set(BlockPos(x: x, y: base, z: z), .grass, placedBy: false) }
        } }
    }

    /// A path of trodden earth from a door to the nearest path or the square, round whatever stands in the way.
    private mutating func pave(from start: TownCell, _ w: inout SandboxWorld, avoiding: Set<TownCell>) {
        let sx = SandboxWorld.sx, sz = SandboxWorld.sz
        func inside(_ c: TownCell) -> Bool { c.x >= 1 && c.z >= 1 && c.x < sx - 1 && c.z < sz - 1 }
        guard inside(start) else { return }
        let land = Land(w, busy: taken(w))
        var goal = Set(paths)
        if let p = plaza { for z in p[1]...p[3] { for x in p[0]...p[2] { goal.insert(TownCell(x: x, z: z)) } } }
        if goal.contains(start) { return }
        var came: [TownCell: TownCell] = [start: start], queue = [start], head = 0, end: TownCell?
        while head < queue.count, queue.count < 6000 {
            let c = queue[head]; head += 1
            if goal.contains(c) { end = c; break }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = TownCell(x: c.x + dx, z: c.z + dz)
                guard inside(n), came[n] == nil else { continue }
                let free = goal.contains(n) || land.free(n.x, n.z) && !avoiding.contains(n)
                guard free, !land.wet(n.x, n.z), abs(land.h(n.x, n.z) - land.h(c.x, c.z)) <= 1 else { continue }
                came[n] = c; queue.append(n)
            }
        }
        guard var c = end else { return }
        var trail: [TownCell] = []
        while c != start { c = came[c]!; trail.append(c) }
        for cell in trail where !goal.contains(cell) {
            let g = land.h(cell.x, cell.z)
            w.set(BlockPos(x: cell.x, y: g, z: cell.z), .dirt, placedBy: false)
            // Nothing growing on a path.
            let above = BlockPos(x: cell.x, y: g + 1, z: cell.z)
            if [.leaves, .log, .pine].contains(w[above]), !w.placed[SandboxWorld.index(above)] { w.clearTrees(from: above, to: above) }
            paths.append(cell)
        }
    }

    // MARK: Sites

    /// A template: blocks in its own frame — the front along +z, y 0 the first layer above the ground — and its door.
    fileprivate struct Template {
        var blocks: [(BlockPos, Block)]
        /// The part that stands on the ground, which is levelled: 0..<w by 0..<d.
        var w: Int, d: Int
        /// Where a path leaves from, just outside the front.
        var front: TownCell
    }

    /// The nearest free, fairly flat place round the square for a template, turned to face the square.
    fileprivate func site(_ t: Template, _ land: Land) -> TownPlan? {
        let sx = SandboxWorld.sx, sz = SandboxWorld.sz, c = Self.centre
        let bx0 = t.blocks.map(\.0.x).min() ?? 0, bx1 = t.blocks.map(\.0.x).max() ?? 0, bz0 = t.blocks.map(\.0.z).min() ?? 0, bz1 = t.blocks.map(\.0.z).max() ?? 0
        var best: (score: Double, plan: TownPlan)?
        for (ox, oz, away) in Self.candidates {
            let dx = Double(c.x - ox), dz = Double(c.z - oz)
            guard away <= (t.w * t.d > 60 ? 34 : 30) else { break }
            // Nearest first: nothing further out can beat what is found.
            if let b = best, away > b.score { break }
            // Face the square: 0 south (+z), 1 east (+x), 2 north (-z), 3 west (-x).
            let facing = abs(dz) >= abs(dx) ? (dz > 0 ? 0 : 2) : (dx > 0 ? 1 : 3)
            func turn(_ x: Int, _ z: Int) -> (Int, Int) {
                switch facing {
                case 0: return (x, z)
                case 1: return (z, -x)
                case 2: return (-x, -z)
                default: return (-z, x)
                }
            }
            // The footprint's middle goes on (ox, oz).
            let (mx, mz) = turn(t.w / 2, t.d / 2)
            func world(_ x: Int, _ z: Int) -> (Int, Int) { let (rx, rz) = turn(x, z); return (ox + rx - mx, oz + rz - mz) }
            let corners = [world(bx0, bz0), world(bx1, bz1), world(bx0, bz1), world(bx1, bz0)]
            let wx0 = corners.map(\.0).min()! - 2, wx1 = corners.map(\.0).max()! + 2, wz0 = corners.map(\.1).min()! - 2, wz1 = corners.map(\.1).max()! + 2
            guard wx0 >= 1, wz0 >= 1, wx1 < sx - 1, wz1 < sz - 1 else { continue }
            var clear = true, lo = Int.max, hi = Int.min, heights: [Int] = []
            let feet = [world(0, 0), world(t.w - 1, t.d - 1)]
            let fx0 = min(feet[0].0, feet[1].0), fx1 = max(feet[0].0, feet[1].0), fz0 = min(feet[0].1, feet[1].1), fz1 = max(feet[0].1, feet[1].1)
            scan: for z in wz0...wz1 { for x in wx0...wx1 {
                if !land.free(x, z) || land.wet(x, z) { clear = false; break scan }
                if x >= fx0, x <= fx1, z >= fz0, z <= fz1 { let g = land.h(x, z); lo = min(lo, g); hi = max(hi, g); heights.append(g) }
            } }
            guard clear, hi - lo <= 3, !heights.isEmpty else { continue }
            let base = heights.sorted()[heights.count / 2]
            let score = away + Double(hi - lo) * 1.5
            if let b = best, b.score <= score { continue }
            let blocks = t.blocks.map { p, k -> (BlockPos, Block) in let (x, z) = world(p.x, p.z); return (BlockPos(x: x, y: base + 1 + p.y, z: z), k) }
            let (fx, fz) = world(t.front.x, t.front.z)
            best = (score, TownPlan(level: (fx0, fz0, fx1, fz1, base), blocks: blocks, front: TownCell(x: fx, z: fz), base: base))
        }
        return best?.plan
    }

    /// Places round the square for a building's middle, every other block, nearest first.
    private static let candidates: [(Int, Int, Double)] = {
        var out: [(Int, Int, Double)] = []
        for oz in stride(from: 3, to: SandboxWorld.sz - 3, by: 2) { for ox in stride(from: 3, to: SandboxWorld.sx - 3, by: 2) {
            let away = hypot(Double(centre.x - ox), Double(centre.z - oz))
            if away >= 5, away <= 34 { out.append((ox, oz, away)) }
        } }
        return out.sorted { $0.2 < $1.2 }
    }()

    private func fountain(_ land: Land) -> TownPlan? {
        let c = Self.centre, base = land.h(c.x, c.z)
        var steps: [PlanStep] = [.walls(.cobble, BlockPos(x: -2, y: 0, z: -2), BlockPos(x: 2, y: 0, z: 2)), .box(.water, BlockPos(x: -1, y: 0, z: -1), BlockPos(x: 1, y: 0, z: 1))]
        steps += [.box(.cobble, BlockPos(x: 0, y: 0, z: 0), BlockPos(x: 0, y: 2, z: 0)), .box(.gold, BlockPos(x: 0, y: 3, z: 0), BlockPos(x: 0, y: 3, z: 0))]
        let blocks = SandboxPlan.blocks(steps).map { (BlockPos(x: c.x + $0.0.x, y: base + 1 + $0.0.y, z: c.z + $0.0.z), $0.1) }
        return TownPlan(level: nil, blocks: blocks, front: nil, base: base)
    }

    /// Lamp posts beside the paths: every sixth block of path, on free ground next to it.
    private func lamps(_ land: Land) -> TownPlan? {
        var blocks: [(BlockPos, Block)] = [], used = Set<TownCell>()
        let onPath = Set(paths)
        for (k, cell) in paths.enumerated() where k >= lit && k % 6 == 3 {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = TownCell(x: cell.x + dx, z: cell.z + dz)
                guard n.x > 0, n.z > 0, n.x < SandboxWorld.sx - 1, n.z < SandboxWorld.sz - 1, !onPath.contains(n), !used.contains(n),
                      land.free(n.x, n.z), !land.wet(n.x, n.z) else { continue }
                let g = land.h(n.x, n.z)
                blocks += [(BlockPos(x: n.x, y: g + 1, z: n.z), .log), (BlockPos(x: n.x, y: g + 2, z: n.z), .log), (BlockPos(x: n.x, y: g + 3, z: n.z), .lamp)]
                used.insert(n)
                break
            }
            if used.count >= 16 { break }
        }
        guard !blocks.isEmpty else { return nil }
        return TownPlan(level: nil, blocks: blocks, front: nil, base: blocks.map(\.0.y).min()! - 1)
    }

    /// A wall round everything built, three out from it: three high with merlons, a gate in the middle of each side.
    private func wall(_ land: Land) -> (TownPlan, Int, Int)? {
        let xs = projects.flatMap { [$0.x0, $0.x1] } + paths.map(\.x), zs = projects.flatMap { [$0.z0, $0.z1] } + paths.map(\.z)
        guard let lx = xs.min(), let hx = xs.max(), let lz = zs.min(), let hz = zs.max() else { return nil }
        let x0 = max(1, lx - 3), x1 = min(SandboxWorld.sx - 2, hx + 3), z0 = max(1, lz - 3), z1 = min(SandboxWorld.sz - 2, hz + 3)
        guard x1 - x0 >= 10, z1 - z0 >= 10 else { return nil }
        var ring: [TownCell] = []
        for x in x0...x1 { ring += [TownCell(x: x, z: z0), TownCell(x: x, z: z1)] }
        for z in (z0 + 1)..<z1 { ring += [TownCell(x: x0, z: z), TownCell(x: x1, z: z)] }
        let gates = [TownCell(x: (x0 + x1) / 2, z: z0), TownCell(x: (x0 + x1) / 2, z: z1), TownCell(x: x0, z: (z0 + z1) / 2), TownCell(x: x1, z: (z0 + z1) / 2)]
        let onPath = Set(paths)
        var blocks: [(BlockPos, Block)] = []
        for c in ring {
            // Not through water, nor through anything standing; across a path, a gate.
            guard !land.wet(c.x, c.z), land.free(c.x, c.z) || onPath.contains(c) else { continue }
            let gate = gates.contains { abs($0.x - c.x) + abs($0.z - c.z) <= 1 } || onPath.contains(c)
            let g = land.h(c.x, c.z)
            if gate { blocks.append((BlockPos(x: c.x, y: g + 4, z: c.z), .cobble)); continue }
            for y in 1...3 { blocks.append((BlockPos(x: c.x, y: g + y, z: c.z), .cobble)) }
            if (c.x + c.z) % 2 == 0 { blocks.append((BlockPos(x: c.x, y: g + 4, z: c.z), .cobble)) }
        }
        guard blocks.count > 40 else { return nil }
        return (TownPlan(level: nil, blocks: blocks, front: nil, base: blocks.map(\.0.y).min()! - 1), x1 - x0 + 1, z1 - z0 + 1)
    }

    /// A dock off the nearest shore with seven blocks of open water in front, and a boat moored beside it.
    private func dock(_ land: Land) -> (TownPlan, Int)? {
        let c = Self.centre, sea = SandboxWorld.sea
        var best: (Double, TownCell, (Int, Int))?
        for z in 3..<(SandboxWorld.sz - 3) { for x in 3..<(SandboxWorld.sx - 3) {
            let away = hypot(Double(x - c.x), Double(z - c.z))
            guard away <= 34, !land.wet(x, z), land.free(x, z), land.h(x, z) <= sea + 2 else { continue }
            if let b = best, b.0 <= away { continue }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let open = (1...6).allSatisfy { k in
                    let px = x + dx * k, pz = z + dz * k
                    return px > 3 && pz > 3 && px < SandboxWorld.sx - 4 && pz < SandboxWorld.sz - 4 && land.wet(px, pz) && land.wet(px - dz * 2, pz + dx * 2) && land.wet(px + dz, pz - dx)
                }
                if open { best = (away, TownCell(x: x, z: z), (dx, dz)); break }
            }
        } }
        guard let (away, shore, (dx, dz)) = best else { return nil }
        let deck = sea + 1
        var blocks: [(BlockPos, Block)] = []
        for k in 1...6 { for s in -1...1 {
            let x = shore.x + dx * k - dz * s, z = shore.z + dz * k + dx * s
            blocks.append((BlockPos(x: x, y: deck, z: z), .planks))
            if (k == 3 || k == 6), s != 0 { for y in stride(from: land.h(x, z) + 1, to: deck, by: 1) { blocks.append((BlockPos(x: x, y: y, z: z), .log)) } }
        } }
        blocks.append((BlockPos(x: shore.x + dx * 6 + dz, y: deck + 1, z: shore.z + dz * 6 - dx), .lamp))
        // The boat, on the side away from the posts: a hull three wide and five long, a mast and a sail.
        let bx = shore.x + dx * 4 - dz * 2, bz = shore.z + dz * 4 + dx * 2
        for k in -2...2 { for s in 0...1 {
            let x = bx + dx * k - dz * s, z = bz + dz * k + dx * s
            blocks.append((BlockPos(x: x, y: sea, z: z), .planks))
            if abs(k) == 2 || s == 1 || k == 0 { blocks.append((BlockPos(x: x, y: sea + 1, z: z), .planks)) }
        } }
        for y in (sea + 1)...(sea + 5) { blocks.append((BlockPos(x: bx, y: y, z: bz), .log)) }
        for k in -1...1 { for y in (sea + 3)...(sea + 5) { blocks.append((BlockPos(x: bx + dx * k - dz, y: y, z: bz + dz * k + dx), .wool)) } }
        return (TownPlan(level: nil, blocks: blocks, front: shore, base: deck - 1), Int(away))
    }

    /// A bridge over the narrowest water near the square, three to sixteen blocks across.
    private func bridge(_ land: Land) -> (TownPlan, Int, Int)? {
        let c = Self.centre, sea = SandboxWorld.sea
        var best: (Double, TownCell, (Int, Int), Int)?
        for z in 3..<(SandboxWorld.sz - 3) { for x in 3..<(SandboxWorld.sx - 3) {
            let away = hypot(Double(x - c.x), Double(z - c.z))
            guard away <= 30, !land.wet(x, z), land.free(x, z), land.h(x, z) <= sea + 3 else { continue }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                var k = 1
                while k <= 17, x + dx * k > 1, z + dz * k > 1, x + dx * k < SandboxWorld.sx - 2, z + dz * k < SandboxWorld.sz - 2, land.wet(x + dx * k, z + dz * k) { k += 1 }
                let across = k - 1, lx = x + dx * k, lz = z + dz * k
                guard across >= 3, across <= 16, lx > 1, lz > 1, lx < SandboxWorld.sx - 2, lz < SandboxWorld.sz - 2, !land.wet(lx, lz), land.h(lx, lz) <= sea + 3 else { continue }
                let score = away + Double(across)
                if best == nil || score < best!.0 { best = (score, TownCell(x: x, z: z), (dx, dz), across) }
            }
        } }
        guard let (_, start, (dx, dz), across) = best else { return nil }
        let deck = sea + 2
        var blocks: [(BlockPos, Block)] = []
        for k in 0...(across + 1) { for s in -1...1 {
            let x = start.x + dx * k - dz * s, z = start.z + dz * k + dx * s
            blocks.append((BlockPos(x: x, y: deck, z: z), .planks))
            if s != 0 { blocks.append((BlockPos(x: x, y: deck + 1, z: z), k == 0 || k == across + 1 ? .lamp : .log)) }
            if k > 0, k <= across, k % 4 == 2 { for y in stride(from: land.h(x, z) + 1, to: deck, by: 1) { blocks.append((BlockPos(x: x, y: y, z: z), .cobble)) } }
        } }
        let away = Int(hypot(Double(start.x - c.x), Double(start.z - c.z)))
        return (TownPlan(level: nil, blocks: blocks, front: start, base: deck - 1), away, across)
    }

    // MARK: Templates

    static func roll(_ rng: inout UInt64) -> Double { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Double(rng % 1_000_000) / 1_000_000 }

    /// Walls, floor and roof for a style: wood, stone, brick, sandstone or white plaster.
    private static let styles: [(wall: Block, floor: Block, roof: Block)] = [(.planks, .planks, .roof), (.cobble, .planks, .roof), (.bricks, .planks, .roof), (.sandstone, .sandstone, .planks), (.wool, .planks, .roof)]

    fileprivate static func template(_ kind: TownKind, style: Int, _ rng: inout UInt64) -> Template {
        func p(_ x: Int, _ y: Int, _ z: Int) -> BlockPos { BlockPos(x: x, y: y, z: z) }
        let s = styles[style % styles.count]
        var steps: [PlanStep] = []
        var w = 5, d = 5, door: Int? = nil
        switch kind {
        case .cottage:
            w = roll(&rng) < 0.5 ? 5 : 7; d = w + 2
            let mid = w / 2
            steps = [.box(s.floor, p(0, 0, 0), p(w - 1, 0, d - 1)), .walls(s.wall, p(0, 1, 0), p(w - 1, 3, d - 1))]
            for (x, z) in [(0, 0), (w - 1, 0), (0, d - 1), (w - 1, d - 1)] { steps.append(.box(.log, p(x, 0, z), p(x, 3, z))) }
            steps += [.clear(p(mid, 1, d - 1), p(mid, 2, d - 1)),
                      .box(.glass, p(0, 2, d / 2 - 1), p(0, 2, d / 2)), .box(.glass, p(w - 1, 2, d / 2 - 1), p(w - 1, 2, d / 2)), .box(.glass, p(mid, 2, 0), p(mid, 2, 0)),
                      .roof(s.roof, 0, 0, w - 1, d - 1, 4), .box(.cobble, p(1, 1, 1), p(1, 4 + w / 2 + 1, 1)), .box(.lamp, p(mid, 3, d / 2), p(mid, 3, d / 2))]
            if w >= 7 { steps += [.box(.glass, p(1, 2, d - 1), p(1, 2, d - 1)), .box(.glass, p(w - 2, 2, d - 1), p(w - 2, 2, d - 1))] }
            door = mid
        case .townhouse:
            w = roll(&rng) < 0.5 ? 7 : 9; d = w + 2
            let mid = w / 2, low: Block = [.bricks, .cobble, .stone][Int(roll(&rng) * 3)], high: Block = roll(&rng) < 0.5 ? .planks : .wool
            steps = [.box(.cobble, p(0, 0, 0), p(w - 1, 0, d - 1)), .walls(low, p(0, 1, 0), p(w - 1, 3, d - 1)), .box(.planks, p(0, 4, 0), p(w - 1, 4, d - 1)),
                     .walls(high, p(0, 5, 0), p(w - 1, 7, d - 1))]
            for (x, z) in [(0, 0), (w - 1, 0), (0, d - 1), (w - 1, d - 1)] { steps.append(.box(.log, p(x, 0, z), p(x, 7, z))) }
            steps += [.clear(p(mid, 1, d - 1), p(mid, 2, d - 1)),
                      .box(.glass, p(mid - 2, 2, d - 1), p(mid - 2, 2, d - 1)), .box(.glass, p(mid + 2, 2, d - 1), p(mid + 2, 2, d - 1)),
                      .box(.glass, p(mid - 1, 6, d - 1), p(mid + 1, 6, d - 1)), .box(.glass, p(mid, 6, 0), p(mid, 6, 0)),
                      .box(.glass, p(0, 2, d / 2), p(0, 2, d / 2)), .box(.glass, p(w - 1, 2, d / 2), p(w - 1, 2, d / 2)),
                      .box(.glass, p(0, 6, d / 2 - 1), p(0, 6, d / 2)), .box(.glass, p(w - 1, 6, d / 2 - 1), p(w - 1, 6, d / 2)),
                      .roof(.roof, 0, 0, w - 1, d - 1, 8), .box(.lamp, p(mid, 3, d / 2), p(mid, 3, d / 2)), .box(.lamp, p(mid, 7, d / 2), p(mid, 7, d / 2))]
            door = mid
        case .well:
            w = 5; d = 5
            steps = [.box(.cobble, p(0, -1, 0), p(4, -1, 4)), .walls(.cobble, p(1, 0, 1), p(3, 1, 3)), .box(.water, p(2, -2, 2), p(2, 0, 2))]
            for (x, z) in [(1, 1), (3, 1), (1, 3), (3, 3)] { steps.append(.box(.log, p(x, 2, z), p(x, 3, z))) }
            steps += [.box(s.roof == .planks ? .planks : .roof, p(0, 4, 0), p(4, 4, 4)), .box(.roof, p(1, 5, 1), p(3, 5, 3)), .box(.planks, p(2, 6, 2), p(2, 6, 2))]
        case .field:
            w = roll(&rng) < 0.5 ? 7 : 9; d = w + 2
            let mid = w / 2
            steps = [.walls(.log, p(0, 0, 0), p(w - 1, 0, d - 1)), .clear(p(mid, 0, d - 1), p(mid, 0, d - 1))]
            for x in 1..<(w - 1) {
                if x == mid { steps.append(.box(.water, p(x, -1, 1), p(x, -1, d - 2))); continue }
                steps.append(.box(.dirt, p(x, -1, 1), p(x, -1, d - 2)))
                if x % 2 == 1 { steps.append(.box(.leaves, p(x, 0, 1), p(x, 0, d - 2))) }
            }
            door = mid
        case .tower:
            w = 5; d = 5
            steps = [.box(.cobble, p(0, 0, 0), p(4, 0, 4)), .walls(.cobble, p(0, 1, 0), p(4, 12, 4)), .box(.planks, p(1, 6, 1), p(3, 6, 3)),
                     .box(.cobble, p(-1, 13, -1), p(5, 13, 5)), .clear(p(2, 1, 4), p(2, 2, 4)), .box(.lamp, p(2, 14, 2), p(2, 14, 2))]
            for k in -1...5 where (k + 1) % 2 == 0 { steps += [.box(.cobble, p(k, 14, -1), p(k, 14, -1)), .box(.cobble, p(k, 14, 5), p(k, 14, 5)), .box(.cobble, p(-1, 14, k), p(-1, 14, k)), .box(.cobble, p(5, 14, k), p(5, 14, k))] }
            for y in [4, 9] { steps += [.box(.glass, p(2, y, 0), p(2, y, 0)), .box(.glass, p(0, y, 2), p(0, y, 2)), .box(.glass, p(4, y, 2), p(4, y, 2))] }
            steps.append(.box(.glass, p(2, 9, 4), p(2, 9, 4)))
            door = 2
        case .church:
            w = 9; d = 15
            let back = d - 6, stone: Block = roll(&rng) < 0.5 ? .stone : .cobble
            steps = [.box(stone, p(0, 0, 0), p(w - 1, 0, back)), .walls(stone, p(0, 1, 0), p(w - 1, 5, back)), .roof(.roof, 0, 0, w - 1, back, 6),
                     .box(.glass, p(3, 3, 0), p(5, 4, 0)), .box(.lamp, p(4, 4, back / 2), p(4, 4, back / 2))]
            for z in stride(from: 2, to: back - 1, by: 3) { steps += [.box(.glass, p(0, 2, z), p(0, 4, z)), .box(.glass, p(w - 1, 2, z), p(w - 1, 4, z))] }
            steps += [.box(stone, p(2, 0, d - 5), p(6, 0, d - 1)), .walls(stone, p(2, 1, d - 5), p(6, 14, d - 1)), .clear(p(4, 1, d - 1), p(4, 3, d - 1)),
                      .clear(p(4, 1, back), p(4, 3, d - 5)), .box(.glass, p(4, 7, d - 1), p(4, 8, d - 1)),
                      .clear(p(4, 11, d - 5), p(4, 12, d - 5)), .clear(p(2, 11, d - 3), p(2, 12, d - 3)), .clear(p(6, 11, d - 3), p(6, 12, d - 3)), .clear(p(4, 11, d - 1), p(4, 12, d - 1)),
                      .box(.roof, p(2, 15, d - 5), p(6, 15, d - 1)), .box(.roof, p(3, 16, d - 4), p(5, 17, d - 2)), .box(.roof, p(4, 18, d - 3), p(4, 19, d - 3)),
                      .box(.gold, p(4, 20, d - 3), p(4, 20, d - 3))]
            door = 4
        case .market:
            w = 9; d = 9
            steps = [.box(.cobble, p(0, -1, 0), p(8, -1, 8))]
            let goods: [Block] = [.gold, .leaves, .sand]
            for (k, x) in [0, 3, 6].enumerated() {
                for (px, pz) in [(x, 0), (x + 2, 0), (x, 2), (x + 2, 2)] { steps.append(.box(.log, p(px, 0, pz), p(px, 2, pz))) }
                steps += [.box(.planks, p(x, 0, 2), p(x + 2, 0, 2)), .box(goods[k], p(x + 1, 1, 2), p(x + 1, 1, 2)), .box(.wool, p(x, 3, 0), p(x + 2, 3, 2))]
            }
            steps += [.box(.log, p(4, 0, 6), p(4, 1, 6)), .box(.lamp, p(4, 2, 6), p(4, 2, 6))]
            door = 4
        case .windmill:
            w = 5; d = 5
            steps = [.box(.cobble, p(0, 0, 0), p(4, 0, 4)), .walls(.cobble, p(0, 1, 0), p(4, 3, 4)), .walls(.planks, p(0, 4, 0), p(4, 9, 4)),
                     .box(.roof, p(0, 10, 0), p(4, 10, 4)), .box(.roof, p(1, 11, 1), p(3, 11, 3)), .box(.roof, p(2, 12, 2), p(2, 12, 2)),
                     .clear(p(2, 1, 4), p(2, 2, 4)), .box(.glass, p(0, 6, 2), p(0, 6, 2)), .box(.glass, p(4, 6, 2), p(4, 6, 2)),
                     .box(.log, p(2, 7, 5), p(2, 7, 5)),
                     .line(.planks, p(2, 8, 5), p(2, 12, 5)), .line(.planks, p(2, 6, 5), p(2, 2, 5)), .line(.planks, p(3, 7, 5), p(7, 7, 5)), .line(.planks, p(1, 7, 5), p(-3, 7, 5)),
                     .box(.wool, p(3, 9, 5), p(3, 12, 5)), .box(.wool, p(1, 2, 5), p(1, 5, 5)), .box(.wool, p(4, 6, 5), p(7, 6, 5)), .box(.wool, p(-3, 8, 5), p(0, 8, 5))]
            door = 2
        default:
            break
        }
        let blocks = SandboxPlan.blocks(steps)
        let front = TownCell(x: door ?? w / 2, z: d)
        return Template(blocks: blocks, w: w, d: d, front: front)
    }
}
