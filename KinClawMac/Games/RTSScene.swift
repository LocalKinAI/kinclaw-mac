import SwiftUI

/// The map of 帝国时代 at one moment, from above at three-quarters: grass,
/// woods, lakes with sandy shores, gold and stone and berry bushes; the two
/// towns' buildings standing up in the style of their age — wood and thatch,
/// then timber and shingles, then stone and slate — with their team's banners;
/// villagers carrying what they gathered, spearmen, archers, knights on
/// horseback; arrows in the air; and what the player is doing with the mouse.
struct RTSScene {
    let world: RTSWorld
    /// The side whose view this is: whose rally point shows, whose age and stock a building being placed is judged by.
    let viewer: Int
    let selected: Set<Int>, building: Int?
    let placing: RTSBuildingKind?, hover: RTSTile?
    /// The box being dragged, in tiles.
    let box: (CGPoint, CGPoint)?
    let now: Double

    static let team = [Color(red: 0.2, green: 0.45, blue: 0.98), Color(red: 0.9, green: 0.18, blue: 0.16)]
    static let teamRGB: [Art.RGB] = [(0.22, 0.44, 0.92), (0.86, 0.2, 0.18)]
    /// Summer all game long.
    static let season = Art.Season(month: 4.2)

    func paint(_ g: inout GraphicsContext, tile S: CGFloat, view: CGRect) {
        let W = RTSWorld.width, H = RTSWorld.height
        let season = Self.season
        let near = view.insetBy(dx: -2, dy: -2)
        let x0 = max(0, Int(near.minX)), x1 = min(W - 1, Int(near.maxX)), y0 = max(0, Int(near.minY)), y1 = min(H - 1, Int(near.maxY))
        func rect(_ x: Int, _ y: Int, _ n: Int = 1) -> CGRect { CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: CGFloat(n) * S, height: CGFloat(n) * S) }

        Art.ground(&g, size: CGSize(width: CGFloat(W) * S, height: CGFloat(H) * S), S: S, season: season, visible: view, tiles: CGSize(width: W, height: H))
        var woods: [(Int, Int)] = [], waters: [(Int, Int, Int)] = []
        for y in y0...y1 { for x in x0...x1 {
            switch world.terrain[y * W + x] {
            case .forest: woods.append((x, y))
            case .water: waters.append((x, y, depth(x, y)))
            default: break
            }
        } }
        Art.forestFloor(&g, woods, S: S, season: season)
        Art.water(&g, tiles: waters, S: S, season: season, now: now)
        for b in world.buildings where b.kind == .farm { farm(&g, b, rect(b.x, b.y, 3), S) }
        for b in world.buildings where b.kind != .farm {
            Art.plot(&g, rect(b.x, b.y, RTSWorld.size(b.kind)), S: S, season: season)
        }

        // Standing things, back to front.
        enum Thing { case tree(Int, Int), deposit(Int, Int), building(RTSBuilding), unit(RTSUnit) }
        var things: [(CGFloat, Thing)] = []
        for (x, y) in woods { things.append((CGFloat(y) + 0.82, .tree(x, y))) }
        for y in y0...y1 { for x in x0...x1 where [.gold, .stone, .berries].contains(world.terrain[y * W + x]) { things.append((CGFloat(y) + 0.75, .deposit(x, y))) } }
        for b in world.buildings where b.kind != .farm { things.append((CGFloat(b.y + RTSWorld.size(b.kind)) - 0.15, .building(b))) }
        for u in world.units where near.contains(CGPoint(x: u.x, y: u.y)) { things.append((CGFloat(u.y), .unit(u))) }
        things.sort { $0.0 < $1.0 }
        let recentHits = Set(world.events.filter { $0.kind == .attacked && world.time - $0.time < 0.25 }.map { Int($0.x) * 1000 + Int($0.y) })
        for (_, thing) in things {
            switch thing {
            case .tree(let x, let y):
                let h = Art.hash(x, y)
                let foot = CGPoint(x: (CGFloat(x) + 0.5 + CGFloat(h % 9 - 4) * 0.035) * S, y: (CGFloat(y) + 0.82) * S)
                Art.tree(&g, foot: foot, S: S, grown: 0.45 + 0.55 * min(1, world.amount[y * W + x] / 100), variant: h, season: season, conifer: h % 10 < 5, now: now)
            case .deposit(let x, let y):
                let i = y * W + x
                let kind: Art.Deposit = world.terrain[i] == .gold ? .gold : world.terrain[i] == .stone ? .stone : .berries
                let full: Double = kind == .gold ? 400 : kind == .stone ? 350 : 125
                Art.deposit(&g, kind, centre: CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.6) * S), S: S, left: world.amount[i] / full, variant: Art.hash(x, y), season: season)
            case .building(let b):
                structure(&g, b, S)
                let area = rect(b.x, b.y, RTSWorld.size(b.kind))
                if recentHits.contains(b.x * 1000 + b.y) || recentHits.contains((b.x + 1) * 1000 + b.y + 1) {
                    g.fill(Path(roundedRect: area, cornerRadius: S * 0.2), with: .color(Color.red.opacity(0.22)))
                }
                if b.done, b.hp < RTSWorld.health(b.kind) - 1 || b.id == building {
                    Art.bar(&g, CGRect(x: area.minX + S * 0.2, y: area.minY - S * 0.9, width: area.width - S * 0.4, height: max(3, S * 0.1)), b.hp / RTSWorld.health(b.kind), colour: b.owner == viewer ? .green : .red)
                }
                if b.done, b.hp < RTSWorld.health(b.kind) * 0.5 { fire(&g, CGPoint(x: area.midX, y: area.minY + S * 0.3), S, seed: b.id) }
            case .unit(let u):
                let p = CGPoint(x: CGFloat(u.x) * S, y: CGFloat(u.y) * S)
                if selected.contains(u.id) {
                    g.stroke(Path(ellipseIn: CGRect(x: p.x - S * 0.4, y: p.y - S * 0.12, width: S * 0.8, height: S * 0.3)), with: .color(.green), lineWidth: 1.6)
                }
                unit(&g, u, p, S)
                if selected.contains(u.id) || u.hp < RTSWorld.unitHP(u.kind) - 0.5 {
                    Art.bar(&g, CGRect(x: p.x - S * 0.35, y: p.y - S * (u.kind == .knight ? 1.3 : 1.0), width: S * 0.7, height: max(2.5, S * 0.08)), u.hp / RTSWorld.unitHP(u.kind), colour: u.owner == viewer ? .green : .red)
                }
            }
        }
        // The selected building: its outline and its rally point.
        if let id = building, let b = world.building(id) {
            let area = rect(b.x, b.y, RTSWorld.size(b.kind))
            g.stroke(Path(roundedRect: area.insetBy(dx: -2, dy: -2), cornerRadius: S * 0.2), with: .color(.yellow), lineWidth: 2)
            if let rally = b.rally {
                let to = CGPoint(x: (CGFloat(rally.x) + 0.5) * S, y: (CGFloat(rally.y) + 0.5) * S)
                g.stroke(Path { p in p.move(to: CGPoint(x: area.midX, y: area.midY)); p.addLine(to: to) }, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Art.banner(&g, to, S * 0.8, Self.teamRGB[b.owner], now: now)
            }
        }

        // What happened in the last moments: arrows in flight, blows, the fallen, an age reached.
        for e in world.events {
            let age = world.time - e.time
            switch e.kind {
            case .arrow(let from, let to):
                guard age < 0.35 else { continue }
                let f = CGFloat(age / 0.35)
                let a = CGPoint(x: (CGFloat(from.x) + 0.5) * S, y: (CGFloat(from.y) + 0.5) * S), b = CGPoint(x: (CGFloat(to.x) + 0.5) * S, y: (CGFloat(to.y) + 0.5) * S)
                let head = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f - sin(f * .pi) * S * 0.9)
                let tail = CGPoint(x: head.x - (b.x - a.x) * 0.09, y: head.y - (b.y - a.y) * 0.09 + S * 0.05)
                g.stroke(Path { p in p.move(to: tail); p.addLine(to: head) }, with: .color(Art.c((0.3, 0.22, 0.12))), lineWidth: max(1, S * 0.05))
            case .hit:
                guard age < 0.25 else { continue }
                let p = CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S - S * 0.4)
                for k in 0..<6 {
                    let a = Double(k) * 1.05
                    g.stroke(Path { path in path.move(to: p); path.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * S * 0.3, y: p.y + CGFloat(sin(a)) * S * 0.3)) },
                             with: .color(Color.yellow.opacity(1 - age / 0.25)), lineWidth: max(1, S * 0.05))
                }
            case .death:
                guard age < 1.5 else { continue }
                JevDraw.text(g, "✕", at: CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S - CGFloat(age) * S * 0.4), size: S * 0.55, colour: Self.team[e.owner].opacity(1 - age / 1.5), shadow: false)
            case .age(let n):
                guard age < 2.5 else { continue }
                JevDraw.text(g, RTSWorld.ageNames[n] + "！", at: CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S - S * (2.2 + CGFloat(age) * 0.5)), size: max(14, S * 0.75), colour: Color.yellow.opacity(1 - age / 2.5))
            case .finished:
                guard age < 1.2 else { continue }
                for k in 0..<8 {
                    let a = Double(k) * 0.785 + age * 2, r = S * CGFloat(0.8 + age)
                    JevDraw.text(g, "✦", at: CGPoint(x: CGFloat(e.x) * S + CGFloat(cos(a)) * r, y: CGFloat(e.y) * S - S * 0.5 + CGFloat(sin(a)) * r * 0.7), size: S * 0.35, colour: Color.yellow.opacity(1 - age / 1.2), shadow: false)
                }
            case .attacked: break
            }
        }

        // A building about to be put down: the building itself, faint, and green or red.
        if let kind = placing, let hover {
            let n = RTSWorld.size(kind), origin = RTSTile(x: hover.x - (n - 1) / 2, y: hover.y - (n - 1) / 2)
            let fits = world.fits(kind, at: origin) && world.afford(RTSWorld.cost(kind), viewer)
            let area = rect(origin.x, origin.y, n)
            var ghost = g
            ghost.opacity = 0.55
            let probe = RTSBuilding(id: -1, owner: viewer, kind: kind, x: origin.x, y: origin.y, hp: 1, progress: 1)
            if kind == .farm { farm(&ghost, probe, area, S) } else { structure(&ghost, probe, S) }
            g.fill(Path(roundedRect: area, cornerRadius: S * 0.2), with: .color((fits ? Color.green : Color.red).opacity(0.25)))
            g.stroke(Path(roundedRect: area, cornerRadius: S * 0.2), with: .color(fits ? .green : .red), lineWidth: 2)
        }
        if let box {
            let r = CGRect(x: min(box.0.x, box.1.x) * S, y: min(box.0.y, box.1.y) * S, width: abs(box.1.x - box.0.x) * S, height: abs(box.1.y - box.0.y) * S)
            g.fill(Path(r), with: .color(Color.green.opacity(0.12)))
            g.stroke(Path(r), with: .color(.green), lineWidth: 1)
        }
    }

    private func depth(_ x: Int, _ y: Int) -> Int {
        for d in 1...3 {
            for dy in -d...d { for dx in -d...d where abs(dx) == d || abs(dy) == d {
                let t = RTSTile(x: x + dx, y: y + dy)
                if RTSWorld.inside(t), world.terrain[RTSWorld.index(t)] != .water { return d }
            } }
        }
        return 4
    }

    // MARK: Buildings

    private func fire(_ g: inout GraphicsContext, _ at: CGPoint, _ S: CGFloat, seed: Int) {
        for k in 0..<4 {
            let t = (now * 1.2 + Double(k) * 0.25 + Double(seed % 7) / 7).truncatingRemainder(dividingBy: 1)
            let p = CGPoint(x: at.x + CGFloat(sin(Double(k) * 2.1)) * S * 0.3, y: at.y - CGFloat(t) * S * 0.8)
            let r = S * CGFloat(0.12 + 0.12 * (1 - t))
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 1.3, width: 2 * r, height: 2.6 * r)), with: .color(Color(red: 1, green: 0.5 + 0.3 * (1 - t), blue: 0.1).opacity(0.8 * (1 - t))))
            g.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.3, y: p.y - S * 0.6 - r, width: 2.6 * r, height: 2.6 * r)), with: .color(Color(white: 0.3).opacity(0.35 * (1 - t))))
        }
    }

    private func farm(_ g: inout GraphicsContext, _ b: RTSBuilding, _ area: CGRect, _ S: CGFloat) {
        let inner = area.insetBy(dx: S * 0.08, dy: S * 0.08)
        let soil: Art.RGB = (0.5, 0.36, 0.22)
        g.fill(Path(roundedRect: inner, cornerRadius: S * 0.12), with: .color(Art.c(soil, b.done ? 1 : 0.4 + 0.6 * b.progress)))
        for row in 0..<9 {
            let y = inner.minY + inner.height * (CGFloat(row) + 0.5) / 9
            g.stroke(Path { p in p.move(to: CGPoint(x: inner.minX + S * 0.1, y: y)); p.addLine(to: CGPoint(x: inner.maxX - S * 0.1, y: y)) }, with: .color(Art.c(Art.lit(soil, 0.72))), lineWidth: max(1, S * 0.07))
            guard b.done, b.farmer != nil else { continue }
            for k in 0..<10 {
                let p = CGPoint(x: inner.minX + S * 0.15 + (inner.width - S * 0.3) * CGFloat(k) / 9, y: y)
                let sway = CGFloat(sin(now * 1.6 + Double(k + row))) * S * 0.03
                g.stroke(Path { path in path.move(to: p); path.addLine(to: CGPoint(x: p.x + sway, y: p.y - S * 0.24)) }, with: .color(Art.c((0.62, 0.72, 0.3))), lineWidth: max(0.9, S * 0.04))
                g.fill(Path(ellipseIn: CGRect(x: p.x + sway - S * 0.03, y: p.y - S * 0.3, width: S * 0.06, height: S * 0.1)), with: .color(Art.c((0.9, 0.78, 0.34))))
            }
        }
        g.stroke(Path(roundedRect: inner, cornerRadius: S * 0.12), with: .color(Art.c(Self.teamRGB[b.owner], 0.7)), lineWidth: max(1, S * 0.05))
        if !b.done { Art.bar(&g, CGRect(x: area.minX + S * 0.2, y: area.minY - S * 0.2, width: area.width - S * 0.4, height: max(3, S * 0.1)), b.progress, colour: Color(red: 0.98, green: 0.78, blue: 0.2)) }
    }

    /// A building standing on its plot, in the style of its owner's age.
    private func structure(_ g: inout GraphicsContext, _ b: RTSBuilding, _ S: CGFloat) {
        let n = CGFloat(RTSWorld.size(b.kind))
        let F = CGRect(x: CGFloat(b.x) * S, y: CGFloat(b.y) * S, width: n * S, height: n * S)
        let age = world.players[b.owner].age, colour = Self.teamRGB[b.owner]
        let wall: Art.Wall = age == 0 ? .logs : age == 1 ? .plaster : .stone
        let roof: Art.Roof = age == 0 ? .thatch : age == 1 ? .shingles : .slate
        let roofColour: Art.RGB = age == 0 ? (0.8, 0.66, 0.36) : age == 1 ? (0.68, 0.3, 0.2) : (0.36, 0.4, 0.5)
        var draw = g
        if !b.done { draw.opacity = 0.25 + 0.65 * b.progress }
        switch b.kind {
        case .tower: Art.tower(&draw, F, S: S, team: colour, snow: 0, now: now)
        case .townCenter: Art.keep(&draw, F, S: S, wall: wall, roof: roof, roofColour: roofColour, team: colour, snow: 0, glow: false, now: now)
        case .house: Art.house(&draw, F, S: S, wall: wall, roof: roof, roofColour: roofColour, trim: colour, snow: 0, glow: false, smoke: b.done && b.id % 3 == 0, now: now, seed: b.id)
        case .mill:
            Art.house(&draw, F, S: S, wall: wall, roof: roof, roofColour: roofColour, trim: colour, snow: 0, glow: false, smoke: false, now: now, seed: b.id)
            let f = Art.Frame(F, S: S, tall: false)
            let hub = CGPoint(x: f.wall.midX, y: f.wall.minY - S * 0.3)
            for k in 0..<4 {
                let a = now * 1.4 + Double(k) * .pi / 2
                let tip = CGPoint(x: hub.x + CGFloat(cos(a)) * S * 0.95, y: hub.y + CGFloat(sin(a)) * S * 0.95)
                draw.stroke(Path { p in p.move(to: hub); p.addLine(to: tip) }, with: .color(Art.c((0.45, 0.32, 0.2))), lineWidth: max(1, S * 0.05))
                let side = CGPoint(x: CGFloat(-sin(a)) * S * 0.14, y: CGFloat(cos(a)) * S * 0.14)
                draw.fill(Path { p in
                    p.move(to: CGPoint(x: hub.x + (tip.x - hub.x) * 0.25, y: hub.y + (tip.y - hub.y) * 0.25)); p.addLine(to: tip)
                    p.addLine(to: CGPoint(x: tip.x + side.x, y: tip.y + side.y)); p.addLine(to: CGPoint(x: hub.x + (tip.x - hub.x) * 0.25 + side.x, y: hub.y + (tip.y - hub.y) * 0.25 + side.y)); p.closeSubpath()
                }, with: .color(Art.c((0.94, 0.9, 0.8))))
            }
            draw.fill(Path(ellipseIn: CGRect(x: hub.x - S * 0.08, y: hub.y - S * 0.08, width: S * 0.16, height: S * 0.16)), with: .color(Art.c((0.35, 0.25, 0.15))))
        case .lumberCamp: Art.shed(&draw, F, S: S, pile: .logs, team: colour, snow: 0, now: now)
        case .miningCamp: Art.shed(&draw, F, S: S, pile: .gold, team: colour, snow: 0, now: now)
        case .barracks, .range, .stable:
            Art.hall(&draw, F, S: S, wall: wall, roof: roof, roofColour: roofColour, team: colour, yard: b.kind == .barracks ? .weapons : b.kind == .range ? .target : .hay, snow: 0, now: now)
        case .farm: break
        }
        if !b.done {
            if b.kind == .tower { Art.scaffold(&g, CGRect(x: F.minX + S * 0.14, y: F.maxY - S * 1.9, width: S * 0.72, height: S * 1.8), S: S * 0.7, progress: b.progress, brought: 1) }
            else {
                let f = Art.Frame(F, S: S, tall: n >= 3)
                Art.scaffold(&g, CGRect(x: f.wall.minX, y: f.roof.minY, width: f.wall.width, height: f.bottom - f.roof.minY), S: S, progress: b.progress, brought: 1)
            }
        }
    }

    // MARK: Units

    /// A villager or a soldier in its team's colours, doing what it does.
    private func unit(_ g: inout GraphicsContext, _ u: RTSUnit, _ foot: CGPoint, _ S: CGFloat) {
        let colour = Self.teamRGB[u.owner]
        let walking = !u.path.isEmpty, working = u.swung < 0.35
        switch u.kind {
        case .villager:
            var item = Art.Item.none
            if u.load > 0.5, let r = u.carrying { item = [Art.Item.food, .logs, .gold, .stone][r.rawValue] }
            Art.person(&g, foot: foot, height: S * 0.72, clothes: (0.78, 0.66, 0.48), facing: u.facing, walking: walking, phase: now * 11 + Double(u.id), seed: u.id,
                       hat: .none, carry: item, swing: working && item == .none ? u.swung : nil, trim: colour)
        case .spearman: Art.soldier(&g, .spearman, foot: foot, S: S, team: colour, facing: u.facing, walking: walking, working: working, seed: u.id, now: now)
        case .archer: Art.soldier(&g, .archer, foot: foot, S: S, team: colour, facing: u.facing, walking: walking, working: working, seed: u.id, now: now)
        case .knight: Art.soldier(&g, .knight, foot: foot, S: S, team: colour, facing: u.facing, walking: walking, working: working, seed: u.id, now: now)
        }
    }
}
