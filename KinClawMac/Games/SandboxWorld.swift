import Foundation

/// 沙盒搭建 — a world of blocks. Foundation only: the land, what stands on
/// it, the plans a chat model writes, and what the program measures of a
/// build for Jev to judge. Drawing is in SandboxRender.swift.

enum Block: UInt8, CaseIterable {
    case air = 0, grass, dirt, stone, sand, water, log, leaves, planks, cobble, bricks, glass, snow, gold, roof, wool, lamp, pine, sandstone, ice, coal

    var solid: Bool { self != .air && self != .water }
    /// Seen through: the faces behind it are drawn.
    var clear: Bool { self == .air || self == .water || self == .glass || self == .ice }
    var name: String {
        ["空气", "草", "土", "石头", "沙子", "水", "原木", "树叶", "木板", "圆石", "砖", "玻璃", "雪", "金块", "瓦", "白羊毛", "灯", "松针", "砂岩", "冰", "煤块"][Int(rawValue)]
    }
    var english: String {
        ["air", "grass", "dirt", "stone", "sand", "water", "log", "leaves", "planks", "cobble", "bricks", "glass", "snow", "gold", "roof", "wool", "lamp", "pine", "sandstone", "ice", "coal"][Int(rawValue)]
    }
    /// What the hotbar offers, in order.
    static let palette: [Block] = [.planks, .cobble, .bricks, .glass, .log, .roof, .stone, .wool, .sandstone, .gold, .lamp, .coal, .leaves, .sand, .dirt, .grass, .snow, .ice, .water]

    /// Other names a model uses for them.
    static let aliases: [String: Block] = [
        "wood": .planks, "plank": .planks, "oak": .planks, "brick": .bricks, "cobblestone": .cobble, "stonebrick": .cobble, "stone_bricks": .cobble,
        "window": .glass, "pane": .glass, "torch": .lamp, "light": .lamp, "lantern": .lamp, "glowstone": .lamp, "tile": .roof, "tiles": .roof,
        "shingles": .roof, "black": .coal, "obsidian": .coal, "white": .wool, "leaf": .leaves, "trunk": .log, "snow_block": .snow,
    ]
    /// The block a word names, if any.
    static func named(_ word: String) -> Block? {
        allCases.first { $0 != .air && ($0.english == word || $0.english + "s" == word) } ?? aliases[word] ?? (word.hasSuffix("s") ? aliases[String(word.dropLast())] : nil) ?? (word.hasSuffix("es") ? aliases[String(word.dropLast(2))] : nil)
    }
}

struct BlockPos: Hashable { var x: Int, y: Int, z: Int }

struct SandboxWorld {
    static let sx = 72, sy = 40, sz = 72
    static let sea = 11
    static let chunk = 12

    var cells: [UInt8]
    /// Blocks somebody put there — a person or a plan — as against the land.
    var placed: [Bool]
    var seed: UInt64
    /// Chunks whose looks changed since they were last drawn.
    var dirty = Set<Int>()

    static var chunksX: Int { (sx + chunk - 1) / chunk }
    static var chunksZ: Int { (sz + chunk - 1) / chunk }
    static func chunkIndex(_ x: Int, _ z: Int) -> Int { (z / chunk) * chunksX + x / chunk }
    static func inside(_ p: BlockPos) -> Bool { p.x >= 0 && p.y >= 0 && p.z >= 0 && p.x < sx && p.y < sy && p.z < sz }
    static func index(_ p: BlockPos) -> Int { (p.y * sz + p.z) * sx + p.x }

    subscript(_ p: BlockPos) -> Block {
        get { Self.inside(p) ? Block(rawValue: cells[Self.index(p)]) ?? .air : .air }
    }
    subscript(_ x: Int, _ y: Int, _ z: Int) -> Block { self[BlockPos(x: x, y: y, z: z)] }

    /// Put a block (or air) somewhere, and mark what has to be drawn again.
    @discardableResult
    mutating func set(_ p: BlockPos, _ b: Block, placedBy person: Bool = true) -> Bool {
        guard Self.inside(p), p.y > 0 || b != .air else { return false }
        let i = Self.index(p)
        guard cells[i] != b.rawValue else { return false }
        cells[i] = b.rawValue
        placed[i] = b != .air && person
        for (dx, dz) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)] {
            let x = p.x + dx, z = p.z + dz
            if x >= 0, z >= 0, x < Self.sx, z < Self.sz { dirty.insert(Self.chunkIndex(x, z)) }
        }
        return true
    }

    /// Clear the trees where a build is to go: every log, leaf and needle the land grew (none that somebody
    /// put there) in the box and two blocks round it, and the whole of any tree whose trunk stood in it.
    mutating func clearTrees(from a: BlockPos, to b: BlockPos) {
        let x0 = max(0, min(a.x, b.x) - 2), x1 = min(Self.sx - 1, max(a.x, b.x) + 2)
        let z0 = max(0, min(a.z, b.z) - 2), z1 = min(Self.sz - 1, max(a.z, b.z) + 2)
        let y0 = max(1, min(a.y, b.y) - 2)
        guard x0 <= x1, z0 <= z1, y0 < Self.sy else { return }
        func wild(_ p: BlockPos) -> Bool { let k = self[p]; return (k == .log || k == .leaves || k == .pine) && !placed[Self.index(p)] }
        var trunks: [BlockPos] = []
        for y in y0..<Self.sy { for z in z0...z1 { for x in x0...x1 {
            let p = BlockPos(x: x, y: y, z: z)
            guard wild(p) else { continue }
            if self[p] == .log { trunks.append(p) }
            set(p, .air, placedBy: false)
        } } }
        for t in trunks { for y in t.y..<min(Self.sy, t.y + 10) { for z in t.z - 3...t.z + 3 { for x in t.x - 3...t.x + 3 {
            let p = BlockPos(x: x, y: y, z: z)
            if Self.inside(p), wild(p) { set(p, .air, placedBy: false) }
        } } } }
    }

    /// The highest solid block in a column, or -1.
    func top(_ x: Int, _ z: Int) -> Int {
        for y in stride(from: Self.sy - 1, through: 0, by: -1) where self[x, y, z] != .air && self[x, y, z] != .water { return y }
        return -1
    }

    // MARK: Making the land

    init(seed: UInt64) {
        self.seed = seed
        let n = Self.sx * Self.sy * Self.sz
        cells = Array(repeating: 0, count: n)
        placed = Array(repeating: false, count: n)
        var rng = seed &* 0x9E3779B97F4A7C15 | 1
        func roll() -> Double { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Double(rng % 1_000_000) / 1_000_000 }
        func lattice(_ cell: Double) -> (Double, Double) -> Double {
            let gw = Int(Double(Self.sx) / cell) + 2, gh = Int(Double(Self.sz) / cell) + 2
            var values = [Double](repeating: 0, count: gw * gh)
            for i in values.indices { values[i] = roll() }
            return { x, z in
                let fx = x / cell, fz = z / cell, x0 = Int(fx), z0 = Int(fz), tx = fx - Double(x0), tz = fz - Double(z0)
                let sx = tx * tx * (3 - 2 * tx), sz = tz * tz * (3 - 2 * tz)
                let a = values[z0 * gw + x0], b = values[z0 * gw + x0 + 1], c = values[(z0 + 1) * gw + x0], d = values[(z0 + 1) * gw + x0 + 1]
                return (a + (b - a) * sx) * (1 - sz) + (c + (d - c) * sx) * sz
            }
        }
        let hills = lattice(22), bumps = lattice(7), detail = lattice(3)
        var height = [Int](repeating: 0, count: Self.sx * Self.sz)
        for z in 0..<Self.sz {
            for x in 0..<Self.sx {
                let h = hills(Double(x), Double(z)) * 0.62 + bumps(Double(x), Double(z)) * 0.28 + detail(Double(x), Double(z)) * 0.1
                // A flat meadow in the middle to build on; hills and a lake around it.
                let dx = Double(x - Self.sx / 2), dz = Double(z - Self.sz / 2)
                let flat = max(0, 1 - hypot(dx, dz) / 16)
                let raw = 6 + h * 22
                height[z * Self.sx + x] = Int((raw * (1 - flat) + 14 * flat).rounded())
            }
        }
        for z in 0..<Self.sz {
            for x in 0..<Self.sx {
                let h = min(Self.sy - 2, height[z * Self.sx + x])
                for y in 0...h {
                    let b: Block
                    if y == h { b = h <= Self.sea + 1 ? .sand : h >= 23 ? .snow : .grass }
                    else if y >= h - 3 { b = h <= Self.sea + 1 ? .sand : .dirt }
                    else { b = .stone }
                    cells[Self.index(BlockPos(x: x, y: y, z: z))] = b.rawValue
                }
                if h < Self.sea { for y in (h + 1)...Self.sea { cells[Self.index(BlockPos(x: x, y: y, z: z))] = Block.water.rawValue } }
            }
        }
        // Trees on the grass, away from the middle, some broadleaf, some pine.
        for _ in 0..<46 {
            let x = 2 + Int(roll() * Double(Self.sx - 4)), z = 2 + Int(roll() * Double(Self.sz - 4))
            guard hypot(Double(x - Self.sx / 2), Double(z - Self.sz / 2)) > 11 else { continue }
            let y = top(x, z)
            guard y > 0, self[x, y, z] == .grass else { continue }
            if roll() < 0.4 { pine(x, y + 1, z, Int(5 + roll() * 3)) } else { oak(x, y + 1, z, Int(4 + roll() * 2)) }
        }
        dirty = Set(0..<(Self.chunksX * Self.chunksZ))
    }

    private mutating func put(_ x: Int, _ y: Int, _ z: Int, _ b: Block, over: Bool = false) {
        let p = BlockPos(x: x, y: y, z: z)
        guard Self.inside(p) else { return }
        let i = Self.index(p)
        if over || cells[i] == 0 { cells[i] = b.rawValue }
    }

    private mutating func oak(_ x: Int, _ y: Int, _ z: Int, _ h: Int) {
        for k in 0..<h { put(x, y + k, z, .log, over: true) }
        for dy in -2...1 {
            let r = dy >= 0 ? 1 : 2
            for dz in -r...r { for dx in -r...r where !(abs(dx) == r && abs(dz) == r && (dy == 1 || (x + z + dy) % 2 == 0)) {
                put(x + dx, y + h - 1 + dy, z + dz, .leaves)
            } }
        }
    }

    private mutating func pine(_ x: Int, _ y: Int, _ z: Int, _ h: Int) {
        for k in 0..<h { put(x, y + k, z, .log, over: true) }
        for k in 0..<(h - 1) {
            let r = max(0, (h - 1 - k) / 2 - 0)
            let yy = y + 2 + k
            guard r > 0 || k == h - 2 else { continue }
            for dz in -r...r { for dx in -r...r where abs(dx) + abs(dz) <= r + (k % 2 == 0 ? 0 : -1) + 1 { put(x + dx, yy, z + dz, .pine) } }
        }
        put(x, y + h, z, .pine)
        put(x, y + h + 1, z, .pine)
    }

    // MARK: Keeping it

    static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KinClaw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sandbox.world")
    }

    func save(to url: URL = SandboxWorld.file) {
        var data = Data("KCSB1".utf8)
        withUnsafeBytes(of: seed.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: cells)
        data.append(contentsOf: placed.map { $0 ? 1 : 0 })
        try? data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = SandboxWorld.file) -> SandboxWorld? {
        guard let data = try? Data(contentsOf: url), data.count == 5 + 8 + 2 * sx * sy * sz, data.prefix(5) == Data("KCSB1".utf8) else { return nil }
        var seed: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &seed) { data[5..<13].copyBytes(to: $0) }
        var world = SandboxWorld(empty: UInt64(littleEndian: seed))
        let n = sx * sy * sz
        world.cells = [UInt8](data[13..<(13 + n)])
        world.placed = data[(13 + n)...].map { $0 != 0 }
        world.dirty = Set(0..<(chunksX * chunksZ))
        return world
    }

    private init(empty seed: UInt64) {
        self.seed = seed
        cells = []; placed = []
    }
}

// MARK: - Plans: what a chat model writes, and what it becomes

/// One line of a plan, in a small language a chat model can write well: boxes, walls, roofs, openings —
/// never block-by-block coordinates, which it cannot keep straight.
enum PlanStep {
    case box(Block, BlockPos, BlockPos)
    case hollow(Block, BlockPos, BlockPos)
    case walls(Block, BlockPos, BlockPos)
    case floor(Block, Int, Int, Int, Int, Int)
    case roof(Block, Int, Int, Int, Int, Int)
    case clear(BlockPos, BlockPos)
    case cylinder(Block, Int, Int, Int, Int, Int, Bool)
    case sphere(Block, Int, Int, Int, Int, Bool)
    case line(Block, BlockPos, BlockPos)
    case stairs(Block, BlockPos, Int, Int)
}

enum SandboxPlan {
    static let blocks = Block.palette.map(\.english).joined(separator: ", ")

    /// The language, as the model is told it.
    static let grammar = """
        Build in a world of 1-metre blocks. x runs east, y up, z south. The spot you build on is 0 0 0: y 0 is the first layer above the ground, and nothing goes below it.
        Every box is given by two opposite corners, x1 y1 z1 x2 y2 z2, both included.
        Answer with commands only, one per line, no numbering, no explanation:
        box BLOCK x1 y1 z1 x2 y2 z2        a solid box, filled right through: floors, platforms, pillars — never a building's body
        hollow BLOCK x1 y1 z1 x2 y2 z2     a box's walls, floor and ceiling, and whatever was inside emptied
        walls BLOCK x1 y1 z1 x2 y2 z2      only the four walls of the box
        clear x1 y1 z1 x2 y2 z2            empty a box — doorways and windows, after the walls
        roof BLOCK x1 y1 z1 x2 z2          a pitched roof over x1..x2, z1..z2, its eaves at height y1 — for houses; at most 16 across
        cylinder BLOCK cx cz r y1 y2 [hollow]
        sphere BLOCK cx cy cz r [hollow]   a ball from cy-r to cy+r: one resting on the ground has cy = r
        line BLOCK x1 y1 z1 x2 y2 z2
        stairs BLOCK x y z length east|west|north|south
        BLOCK is one of: \(blocks).
        Sizes: a cottage about 7 by 9, a house two storeys about 9 by 11, a tower about 5 by 5 and 16 high, a castle about 20 by 20 with towers at the corners. Stay within x and z -14..14 and y 0..24.
        Stacked balls: each centre sits at the top of the ball below plus its own radius. A bridge is a deck one block thick raised over the gap on arches or piers, railings along its sides, open underneath. A boat is a hollow hull, narrow at the keel and wider at the deck, pointed at the bow.
        A doorway is clear 1 wide and 2 high at y 0 and 1. Windows: glass boxes in the walls, after the walls. Castles and towers have flat tops with battlements: a wall one block higher at the edge with every other block cleared. Use 10 to 40 commands.
        For instance, a cottage:
        hollow planks -3 0 -4 3 4 4
        clear 0 0 -4 0 1 -4
        box glass -3 2 -2 -3 2 -1
        box glass 3 2 1 3 2 2
        roof roof -3 5 -4 3 4
        """

    static let commands: Set<String> = ["box", "fill", "hollow", "walls", "wall", "floor", "roof", "clear", "air", "cylinder", "sphere", "line", "stairs", "stair"]

    static func parse(_ text: String) -> (steps: [PlanStep], unread: Int) {
        var steps: [PlanStep] = [], unread = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.isEmpty { continue }
            line = line.replacingOccurrences(of: ",", with: " ")
            let words = line.split(separator: " ").map { String($0).lowercased() }
            guard let verb = words.first else { continue }
            func block(_ k: Int) -> Block? { words.count > k ? Block.named(words[k]) : nil }
            func ints(_ from: Int, _ count: Int) -> [Int]? {
                guard words.count >= from + count else { return nil }
                let v = words[from..<(from + count)].compactMap { w -> Int? in
                    guard let d = Double(w), d.isFinite, abs(d) < 10_000 else { return nil }
                    return Int(d.rounded())
                }
                return v.count == count ? v : nil
            }
            func pos(_ v: [Int], _ k: Int) -> BlockPos { BlockPos(x: v[k], y: v[k + 1], z: v[k + 2]) }
            // A block's name used as the command — a box of it, or one block — unless it is a command's name too (roof).
            if !Self.commands.contains(verb), let b = Block.named(verb) {
                if let v = ints(1, 6) { steps.append(.box(b, pos(v, 0), pos(v, 3))) }
                else if let v = ints(1, 3) { steps.append(.box(b, pos(v, 0), pos(v, 0))) }
                else { unread += 1 }
                continue
            }
            switch verb {
            case "box", "fill":
                if let b = block(1), let v = ints(2, 6) { steps.append(.box(b, pos(v, 0), pos(v, 3))) } else { unread += 1 }
            case "hollow":
                if let b = block(1), let v = ints(2, 6) { steps.append(.hollow(b, pos(v, 0), pos(v, 3))) } else { unread += 1 }
            case "walls", "wall":
                if let b = block(1), let v = ints(2, 6) { steps.append(.walls(b, pos(v, 0), pos(v, 3))) } else { unread += 1 }
            case "floor":
                if let b = block(1), let v = ints(2, 6) { steps.append(.box(b, pos(v, 0), pos(v, 3))) }
                else if let b = block(1), let v = ints(2, 5) { steps.append(.floor(b, v[0], v[1], v[2], v[3], v[4])) } else { unread += 1 }
            case "roof":
                // x1 y1 z1 x2 z2 — or, as a box, x1 y1 z1 x2 y2 z2 with the eaves at y1.
                if let b = block(1), let v = ints(2, 6) { steps.append(.roof(b, v[0], v[2], v[3], v[5], v[1])) }
                else if let b = block(1), let v = ints(2, 5) { steps.append(.roof(b, v[0], v[2], v[3], v[4], v[1])) } else { unread += 1 }
            case "clear", "air":
                if let v = ints(1, 6) { steps.append(.clear(pos(v, 0), pos(v, 3))) } else { unread += 1 }
            case "cylinder":
                if let b = block(1), let v = ints(2, 5) { steps.append(.cylinder(b, v[0], v[1], v[2], v[3], v[4], words.contains("hollow"))) } else { unread += 1 }
            case "sphere":
                if let b = block(1), let v = ints(2, 4) { steps.append(.sphere(b, v[0], v[1], v[2], v[3], words.contains("hollow"))) } else { unread += 1 }
            case "line":
                if let b = block(1), let v = ints(2, 6) { steps.append(.line(b, pos(v, 0), pos(v, 3))) } else { unread += 1 }
            case "stairs", "stair":
                let dirs = ["east": 0, "west": 1, "north": 2, "south": 3]
                if let b = block(1), let v = ints(2, 4), words.count > 6, let d = dirs[words[6]] { steps.append(.stairs(b, pos(v, 0), v[3], d)) } else { unread += 1 }
            default:
                unread += 1
            }
        }
        return (steps, unread)
    }

    /// The blocks a plan puts down, in order, relative to the spot — bottom up within each step.
    static func blocks(_ steps: [PlanStep]) -> [(BlockPos, Block)] {
        var out: [(BlockPos, Block)] = []
        func span(_ a: Int, _ b: Int) -> [Int] { let lo = max(-20, min(a, b)), hi = min(30, max(a, b)); return lo <= hi ? Array(lo...hi) : [] }
        func each(_ a: BlockPos, _ b: BlockPos, _ keep: (Int, Int, Int) -> Bool, _ block: Block) {
            let xs = span(a.x, b.x), ys = span(a.y, b.y), zs = span(a.z, b.z)
            for y in ys { for z in zs { for x in xs where keep(x, y, z) { out.append((BlockPos(x: x, y: y, z: z), block)) } } }
        }
        for step in steps {
            switch step {
            case .box(let b, let p, let q): each(p, q, { _, _, _ in true }, b)
            case .hollow(let b, let p, let q):
                // Empty inside, as Minecraft's fill … hollow is: a box and then a hollow over it make a shell.
                func rim(_ x: Int, _ y: Int, _ z: Int) -> Bool { x == min(p.x, q.x) || x == max(p.x, q.x) || y == min(p.y, q.y) || y == max(p.y, q.y) || z == min(p.z, q.z) || z == max(p.z, q.z) }
                let xs = span(p.x, q.x), ys = span(p.y, q.y), zs = span(p.z, q.z)
                for y in ys { for z in zs { for x in xs { out.append((BlockPos(x: x, y: y, z: z), rim(x, y, z) ? b : .air)) } } }
            case .walls(let b, let p, let q):
                each(p, q, { x, _, z in x == min(p.x, q.x) || x == max(p.x, q.x) || z == min(p.z, q.z) || z == max(p.z, q.z) }, b)
            case .floor(let b, let x1, let z1, let x2, let z2, let y): each(BlockPos(x: x1, y: y, z: z1), BlockPos(x: x2, y: y, z: z2), { _, _, _ in true }, b)
            case .roof(let b, let x1, let z1, let x2, let z2, let y) where min(abs(x2 - x1), abs(z2 - z1)) > 16:
                each(BlockPos(x: x1, y: y, z: z1), BlockPos(x: x2, y: y, z: z2), { _, _, _ in true }, b)
            case .roof(let b, let x1, let z1, let x2, let z2, let y):
                // Each layer steps in from the two long sides, eaves overhanging by one.
                let alongX = abs(x2 - x1) >= abs(z2 - z1)
                let lo = (alongX ? min(z1, z2) : min(x1, x2)) - 1, hi = (alongX ? max(z1, z2) : max(x1, x2)) + 1
                var layer = 0
                while lo + layer <= hi - layer {
                    for s in [lo + layer, hi - layer] {
                        if alongX { each(BlockPos(x: min(x1, x2) - 1, y: y + layer, z: s), BlockPos(x: max(x1, x2) + 1, y: y + layer, z: s), { _, _, _ in true }, b) }
                        else { each(BlockPos(x: s, y: y + layer, z: min(z1, z2) - 1), BlockPos(x: s, y: y + layer, z: max(z1, z2) + 1), { _, _, _ in true }, b) }
                    }
                    layer += 1
                    if layer > 20 { break }
                }
                // The gable ends under the slopes.
                var k = 0
                while lo + 1 + k <= hi - 1 - k {
                    let a = lo + 1 + k, c = hi - 1 - k
                    for e in alongX ? [min(x1, x2), max(x1, x2)] : [min(z1, z2), max(z1, z2)] {
                        if alongX { each(BlockPos(x: e, y: y + k, z: a), BlockPos(x: e, y: y + k, z: c), { _, _, _ in true }, b == .roof ? .planks : b) }
                        else { each(BlockPos(x: a, y: y + k, z: e), BlockPos(x: c, y: y + k, z: e), { _, _, _ in true }, b == .roof ? .planks : b) }
                    }
                    k += 1
                    if k > 20 { break }
                }
            case .clear(let p, let q): each(p, q, { _, _, _ in true }, .air)
            case .cylinder(let b, let cx, let cz, let r, let y1, let y2, let hollow):
                let rr = Double(r) + 0.5
                each(BlockPos(x: cx - r, y: y1, z: cz - r), BlockPos(x: cx + r, y: y2, z: cz + r), { x, _, z in
                    let d = hypot(Double(x - cx), Double(z - cz))
                    return d <= rr && (!hollow || d > rr - 1.2)
                }, b)
            case .sphere(let b, let cx, let cy, let cz, let r, let hollow):
                let rr = Double(r) + 0.5
                each(BlockPos(x: cx - r, y: cy - r, z: cz - r), BlockPos(x: cx + r, y: cy + r, z: cz + r), { x, y, z in
                    let d = sqrt(Double((x - cx) * (x - cx) + (y - cy) * (y - cy) + (z - cz) * (z - cz)))
                    return d <= rr && (!hollow || d > rr - 1.2)
                }, b)
            case .line(let b, let p, let q):
                let n = max(abs(q.x - p.x), abs(q.y - p.y), abs(q.z - p.z), 1)
                for k in 0...n {
                    let t = Double(k) / Double(n)
                    out.append((BlockPos(x: Int((Double(p.x) + Double(q.x - p.x) * t).rounded()), y: Int((Double(p.y) + Double(q.y - p.y) * t).rounded()), z: Int((Double(p.z) + Double(q.z - p.z) * t).rounded())), b))
                }
            case .stairs(let b, let p, let length, let dir):
                let (dx, dz) = [(1, 0), (-1, 0), (0, -1), (0, 1)][dir]
                for k in 0..<max(0, min(length, 24)) { out.append((BlockPos(x: p.x + dx * k, y: p.y + k, z: p.z + dz * k), b)) }
            }
        }
        return out
    }
}

// MARK: - A build, measured

/// What the program sees of a build, for Jev to judge: its size, what it is made of, the rooms closed in
/// it, the openings at the foot of its walls, its windows, how much of it is roofed, how it stands.
struct BuildSurvey {
    let blocks: Int
    let width: Int, depth: Int, height: Int
    let materials: [(Block, Int)]
    let rooms: Int, roomVolume: Int
    /// Floors of sheltered air one above another, each parted from the next by a floor.
    let storeys: Int
    let doors: Int, windows: Int
    let roofed: Double
    let symmetric: Double
    let overWater: Bool
    let supports: Int
    let hollowTall: Bool
    /// How the build narrows or widens going up: bands of layers with the same outline.
    let profile: [(from: Int, to: Int, width: Int, depth: Int)]
    let cornerTowers: Bool, battlements: Bool
    /// The longest run of layers each a little smaller on every side than the one below, like a stepped heap.
    let steps: Int
    /// The highest point over the corners, the edges between them and the middle of the ground plan.
    let reachCorners: Int, reachEdges: Int, reachMiddle: Int
    /// Of the ground plan, the share that is low ground walled round on all four sides, at least two higher.
    let yard: Double
    /// Blocks of open air under the middle third of its length, where it stands clear of the ground; 0 when it does not.
    let openBelow: Int
    /// How many times the outline swells and narrows again going up, like balls stacked one on another.
    let swells: Int

    /// What Jev chooses between when it says what a build is.
    static let kinds: [(String, String)] = [
        ("房子", "a house: walls around a room somebody could live in, a doorway, windows, a roof over it"),
        ("塔", "a tower: tall and narrow, much higher than it is wide, perhaps hollow with windows up the sides"),
        ("城堡", "a castle: big and strong, thick stone walls, towers at the corners, battlements, a gate"),
        ("教堂", "a church or temple: a long hall for many people, with a tall tower or spire rising at one end"),
        ("桥", "a bridge: long and thin, open underneath in the middle, crossing water or a gap, resting on ground at its ends"),
        ("墙", "a wall: long and thin and upright, no room inside"),
        ("金字塔", "a pyramid: a solid heap wide at the bottom and narrowing step by step to the top, no room inside"),
        ("雕像", "a statue or sculpture: a solid figure, taller than wide, no rooms, no doorway"),
        ("雪人", "a snowman: two or three balls of snow stacked one on another, the biggest at the bottom"),
        ("树", "a tree: a trunk of logs with leaves around the top"),
        ("船", "a boat: long and low, hollow like a hull, standing on water"),
        ("拱门", "an arch or gate: two uprights joined over the top with an opening through the middle"),
        ("别的", "something else: none of these"),
    ]

    /// The build around a spot: every placed block joined to the ones near it, from the one nearest the spot.
    init?(_ w: SandboxWorld, near spot: BlockPos) {
        var start: BlockPos?
        var best = Int.max
        for y in max(0, spot.y - 3)..<min(SandboxWorld.sy, spot.y + 26) {
            for z in max(0, spot.z - 16)..<min(SandboxWorld.sz, spot.z + 17) {
                for x in max(0, spot.x - 16)..<min(SandboxWorld.sx, spot.x + 17) where w.placed[SandboxWorld.index(BlockPos(x: x, y: y, z: z))] {
                    let d = abs(x - spot.x) + abs(y - spot.y) + abs(z - spot.z)
                    if d < best { best = d; start = BlockPos(x: x, y: y, z: z) }
                }
            }
        }
        guard let start else { return nil }
        var seen: Set<BlockPos> = [start], queue = [start], cells: [BlockPos] = []
        while let p = queue.popLast() {
            cells.append(p)
            guard cells.count < 20000 else { break }
            for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                let q = BlockPos(x: p.x + dx, y: p.y + dy, z: p.z + dz)
                if SandboxWorld.inside(q), !seen.contains(q), w.placed[SandboxWorld.index(q)] { seen.insert(q); queue.append(q) }
            } } }
        }
        let xs = cells.map(\.x), ys = cells.map(\.y), zs = cells.map(\.z)
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!, z0 = zs.min()!, z1 = zs.max()!
        blocks = cells.count
        width = x1 - x0 + 1; depth = z1 - z0 + 1; height = y1 - y0 + 1
        var counts: [Block: Int] = [:]
        for p in cells { counts[w[p], default: 0] += 1 }
        materials = counts.sorted { $0.value > $1.value }
        windows = counts[.glass] ?? 0
        // Rooms: air inside the build that has something of it overhead and walls of it on all four sides —
        // sheltered, whether or not a doorway stands open.
        let built = Set(cells)
        func sheltered(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let p = BlockPos(x: x, y: y, z: z)
            guard !built.contains(p), w[p] == .air || w[p] == .water else { return false }
            let over = ((y + 1)...y1 + 1).contains { built.contains(BlockPos(x: x, y: $0, z: z)) }
            let east = ((x + 1)...x1 + 1).contains { built.contains(BlockPos(x: $0, y: y, z: z)) }
            let west = (x0 - 1...max(x0 - 1, x - 1)).contains { built.contains(BlockPos(x: $0, y: y, z: z)) }
            let south = ((z + 1)...z1 + 1).contains { built.contains(BlockPos(x: x, y: y, z: $0)) }
            let north = (z0 - 1...max(z0 - 1, z - 1)).contains { built.contains(BlockPos(x: x, y: y, z: $0)) }
            return over && east && west && south && north
        }
        var inner = Set<BlockPos>()
        for y in y0...y1 { for z in z0...z1 { for x in x0...x1 where sheltered(x, y, z) { inner.insert(BlockPos(x: x, y: y, z: z)) } } }
        var roomCount = 0, roomCells = 0, left = inner
        while let s = left.first {
            var stack = [s], size = 0
            left.remove(s)
            while let p = stack.popLast() {
                size += 1
                for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                    let n = BlockPos(x: p.x + dx, y: p.y + dy, z: p.z + dz)
                    if left.contains(n) { left.remove(n); stack.append(n) }
                }
            }
            // A pocket too small to stand in is not a room.
            if size >= 4 { roomCount += 1; roomCells += size }
        }
        rooms = roomCount; roomVolume = roomCells
        var perLayer: [Int: Int] = [:]
        for p in inner { perLayer[p.y, default: 0] += 1 }
        var floors = 0, below = Int.min
        for y in perLayer.keys.sorted() where perLayer[y]! >= 4 {
            if y != below + 1 { floors += 1 }
            below = y
        }
        storeys = floors
        // Doorways: sheltered air low down, beside open air that is not sheltered — two cells high for each.
        var doorCells = Set<BlockPos>()
        for p in inner where p.y <= y0 + 3 {
            let above = BlockPos(x: p.x, y: p.y + 1, z: p.z)
            guard inner.contains(above) || w[above] == .air else { continue }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let q = BlockPos(x: p.x + dx, y: p.y, z: p.z + dz)
                if !inner.contains(q), !built.contains(q), w[q] == .air, w[BlockPos(x: q.x, y: q.y + 1, z: q.z)] == .air { doorCells.insert(p); break }
            }
        }
        // Each opening once, however many cells of it there are.
        var openings = 0, unseen = doorCells
        while let first = unseen.first {
            openings += 1
            var stack = [first]
            unseen.remove(first)
            while let p = stack.popLast() {
                for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                    let n = BlockPos(x: p.x + dx, y: p.y + dy, z: p.z + dz)
                    if unseen.contains(n) { unseen.remove(n); stack.append(n) }
                }
            }
        }
        doors = openings
        // Roofed: of the columns inside the walls, how many have something over them.
        var covered = 0, columns = 0
        if width > 2, depth > 2 {
            for z in (z0 + 1)..<z1 { for x in (x0 + 1)..<x1 {
                columns += 1
                if (y0...y1).contains(where: { y in w.placed[SandboxWorld.index(BlockPos(x: x, y: y, z: z))] && y > y0 + 1 }) { covered += 1 }
            } }
        }
        roofed = columns == 0 ? 0 : Double(covered) / Double(columns)
        // Symmetric: how many blocks have their twin across the middle, east to west or north to south.
        let set = Set(cells)
        let mx = cells.filter { set.contains(BlockPos(x: x0 + x1 - $0.x, y: $0.y, z: $0.z)) }.count
        let mz = cells.filter { set.contains(BlockPos(x: $0.x, y: $0.y, z: z0 + z1 - $0.z)) }.count
        symmetric = Double(max(mx, mz)) / Double(cells.count)
        // Over water, and on how many feet it stands.
        var water = 0, feet = 0
        for z in z0...z1 { for x in x0...x1 {
            let below = BlockPos(x: x, y: y0 - 1, z: z)
            if w[below] == .water { water += 1 }
            if set.contains(BlockPos(x: x, y: y0, z: z)), w[below].solid { feet += 1 }
        } }
        overWater = water > width * depth / 4
        supports = feet
        hollowTall = height >= max(width, depth) * 2 && roomVolume > 0
        // The outline of each layer, and the layers grouped where the outline stays about the same.
        var bands: [(from: Int, to: Int, width: Int, depth: Int)] = []
        var sizes: [Int] = []
        for y in y0...y1 {
            let layer = cells.filter { $0.y == y }
            guard let lx0 = layer.map(\.x).min(), let lx1 = layer.map(\.x).max(), let lz0 = layer.map(\.z).min(), let lz1 = layer.map(\.z).max() else { continue }
            let wdt = lx1 - lx0 + 1, dpt = lz1 - lz0 + 1
            sizes.append(max(wdt, dpt))
            if let last = bands.last, abs(last.width - wdt) <= 1, abs(last.depth - dpt) <= 1 { bands[bands.count - 1].to = y - y0 + 1 }
            else { bands.append((y - y0 + 1, y - y0 + 1, wdt, dpt)) }
        }
        profile = bands
        // How high the build reaches over each part of its footprint: corners against the middle.
        let wide = width, deep = depth
        var reach = [Int](repeating: 0, count: wide * deep)
        for p in cells { reach[(p.z - z0) * wide + (p.x - x0)] = max(reach[(p.z - z0) * wide + (p.x - x0)], p.y - y0 + 1) }
        func highest(_ ax: Int, _ az: Int) -> Int {
            // One of nine parts of the footprint: 0, 1 or 2 across and down.
            var best = 0
            for z in az * deep / 3..<(az + 1) * deep / 3 { for x in ax * wide / 3..<(ax + 1) * wide / 3 { best = max(best, reach[z * wide + x]) } }
            return best
        }
        if wide >= 3, deep >= 3 {
            let corners = [highest(0, 0), highest(2, 0), highest(0, 2), highest(2, 2)], sides = [highest(1, 0), highest(0, 1), highest(2, 1), highest(1, 2)]
            cornerTowers = wide >= 7 && deep >= 7 && corners.min()! >= sides.max()! + 3
            reachCorners = corners.max()!; reachEdges = sides.max()!; reachMiddle = highest(1, 1)
        } else { cornerTowers = false; reachCorners = height; reachEdges = height; reachMiddle = height }
        // A yard: low ground, at most half the height, with the build standing two higher all round it.
        var low = 0
        for z in 0..<deep { for x in 0..<wide {
            let h = reach[z * wide + x]
            guard h * 2 <= height else { continue }
            let west = (0..<x).map { reach[z * wide + $0] }.max() ?? 0, east = (x + 1..<wide).map { reach[z * wide + $0] }.max() ?? 0
            let north = (0..<z).map { reach[$0 * wide + x] }.max() ?? 0, south = (z + 1..<deep).map { reach[$0 * wide + x] }.max() ?? 0
            if min(west, east, north, south) >= h + 2 { low += 1 }
        } }
        yard = Double(low) / Double(wide * deep)
        // Open underneath: along its length, the middle third standing on air rather than on the ground.
        var lowest = [Int](repeating: Int.max, count: wide * deep)
        for p in cells { lowest[(p.z - z0) * wide + (p.x - x0)] = min(lowest[(p.z - z0) * wide + (p.x - x0)], p.y - y0) }
        let alongX = wide >= deep, length = alongX ? wide : deep
        var standing = 0, clear: [Int] = []
        for a in length / 3..<max(length / 3 + 1, 2 * length / 3) { for b in 0..<(alongX ? deep : wide) {
            let x = alongX ? a : b, z = alongX ? b : a
            guard x < wide, z < deep, lowest[z * wide + x] != Int.max else { continue }
            standing += 1
            // Air or water straight down from its lowest block to whatever it would land on.
            var gap = 0, y = y0 + lowest[z * wide + x] - 1
            while y >= 0, gap < 16, w[BlockPos(x: x0 + x, y: y, z: z0 + z)] == .air || w[BlockPos(x: x0 + x, y: y, z: z0 + z)] == .water { gap += 1; y -= 1 }
            if gap >= 2 { clear.append(gap) }
        } }
        openBelow = standing > 0 && clear.count * 2 >= standing ? clear.sorted()[clear.count / 2] : 0
        // Swells: the outline growing by two or more and shrinking by two or more again.
        var bulges = 0, rising = false, lowMark = sizes.first ?? 0, highMark = lowMark
        for v in sizes {
            if rising {
                if v > highMark { highMark = v } else if v <= highMark - 2 { bulges += 1; rising = false; lowMark = v }
            } else {
                if v < lowMark { lowMark = v } else if v >= lowMark + 2 { rising = true; highMark = v }
            }
        }
        swells = bulges
        // Steps: thin bands, each smaller on both sides than the one below.
        var run = 0, longest = 0
        for k in bands.indices.dropFirst() {
            let a = bands[k - 1], b = bands[k]
            let dw = a.width - b.width, dd = a.depth - b.depth
            if b.to - b.from < 2, (1...4).contains(dw), (1...4).contains(dd) { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        steps = longest
        // Battlements: merlons — a block standing alone on its layer, on top of a wall, with nothing over it.
        var merlons = 0
        for p in cells where !built.contains(BlockPos(x: p.x, y: p.y + 1, z: p.z)) && built.contains(BlockPos(x: p.x, y: p.y - 1, z: p.z)) {
            let beside = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            guard !beside.contains(where: { built.contains(BlockPos(x: p.x + $0.0, y: p.y, z: p.z + $0.1)) }) else { continue }
            let onWall = built.contains(BlockPos(x: p.x + 1, y: p.y - 1, z: p.z)) && built.contains(BlockPos(x: p.x - 1, y: p.y - 1, z: p.z))
                || built.contains(BlockPos(x: p.x, y: p.y - 1, z: p.z + 1)) && built.contains(BlockPos(x: p.x, y: p.y - 1, z: p.z - 1))
            if onWall { merlons += 1 }
        }
        battlements = merlons >= 4
    }

    /// The build in words, measured, for Jev.
    var words: String {
        let what = materials.prefix(4).map { "\($0.1) \($0.0.english)" }.joined(separator: ", ")
        var parts = ["\(blocks) blocks, \(width) wide by \(depth) deep and \(height) high", "made of \(what)"]
        let tallness = Double(height) / Double(max(width, depth))
        if tallness >= 1.5 { parts.append(String(format: "tall and narrow: it stands %.1f times as high as it is wide", tallness)) }
        else if tallness <= 0.25 { parts.append(String(format: "low and flat: it is %.0f times as wide as it is high", 1 / tallness)) }
        parts.append(rooms == 0 ? "nothing closed in: no room inside" : "\(rooms) closed room\(rooms == 1 ? "" : "s") inside, \(roomVolume) blocks of air")
        if storeys >= 2 { parts.append("the space inside is on \(storeys) floors, one above another") }
        parts.append(doors == 0 ? "no doorway at ground level" : "\(doors) doorway\(doors == 1 ? "" : "s") at ground level")
        parts.append(windows == 0 ? "no glass" : "\(windows) glass blocks")
        if width > 2, depth > 2 { parts.append(String(format: "%.0f%% of the inside covered from above", roofed * 100)) }
        parts.append(String(format: "%.0f%% of it matches its mirror image", symmetric * 100))
        if overWater { parts.append("it stands over water") }
        parts.append("it rests on \(supports) blocks of ground")
        if steps >= 3, steps * 2 >= profile.count - 1 {
            let first = profile.first!, last = profile.last!
            parts.append("its sides step in at every layer, \(steps) steps, from \(first.width) by \(first.depth) at the bottom to \(last.width) by \(last.depth) at the top")
        } else if profile.count > 1 {
            parts.append("going up: " + profile.prefix(5).map { "layers \($0.from)\($0.to > $0.from ? " to \($0.to)" : "") \($0.width) by \($0.depth)" }.joined(separator: ", "))
        }
        if let tall = profile.max(by: { $0.to - $0.from < $1.to - $1.from }), tall.to - tall.from + 1 >= max(4, max(tall.width, tall.depth) * 2) {
            parts.append("a tall narrow part: \(tall.width) by \(tall.depth) for \(tall.to - tall.from + 1) layers")
        }
        if width >= 3, depth >= 3 { parts.append("over its ground plan it reaches \(reachCorners) high at the corners, \(reachEdges) along the sides between them, \(reachMiddle) in the middle") }
        if openBelow >= 2 { parts.append("the middle third of its length stands clear of the ground, with \(openBelow) blocks of open air under it") }
        if swells >= 2 { parts.append("going up, its outline swells and narrows again \(swells) times, like round things stacked one on another") }
        if cornerTowers { parts.append("towers rise at the four corners, higher than the walls between them") }
        if yard >= 0.08 { parts.append(String(format: "%.0f%% of its ground plan is an open yard with walls standing higher all round it", yard * 100)) }
        if battlements { parts.append("battlements along the top of the walls") }
        if width >= max(depth, 1) * 4 || depth >= max(width, 1) * 4 { parts.append("long and thin") }
        return parts.joined(separator: "; ")
    }
}
