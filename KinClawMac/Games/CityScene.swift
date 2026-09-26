import SwiftUI

/// What the mouse is doing besides choosing and placing buildings.
enum CityTool: Equatable { case road, bulldoze }

/// 放逐之城 at one moment, from above at three-quarters, in its season: the
/// ground green, then deep green, then gold, then under snow; trees in
/// blossom, in leaf, in colour and bare; fields sprouting, ripening and cut;
/// houses with timber walls and shingle roofs and smoke from the chimney
/// through the cold months, windows lit; the people at their work, carrying
/// what they gathered; snow falling, leaves falling.
struct CityScene {
    let world: CityWorld
    let selected: Int?
    let placing: CityKind?
    let tool: CityTool?
    let hover: CityTile?
    let drag: (CityTile, CityTile)?
    let now: Double

    var season: Art.Season { Art.Season(month: (world.time / CityWorld.month).truncatingRemainder(dividingBy: 12)) }

    /// Paint the part of the map in `view` (in tiles), `S` points to a tile, the map's corner at the context's origin.
    func paint(_ g: inout GraphicsContext, tile S: CGFloat, view: CGRect) {
        let W = CityWorld.width, H = CityWorld.height
        let size = CGSize(width: CGFloat(W) * S, height: CGFloat(H) * S)
        let season = self.season, snow = season.snow
        let near = view.insetBy(dx: -2, dy: -2)
        let x0 = max(0, Int(near.minX)), x1 = min(W - 1, Int(near.maxX)), y0 = max(0, Int(near.minY)), y1 = min(H - 1, Int(near.maxY))
        func seen(_ x: Int, _ y: Int) -> Bool { x >= x0 && x <= x1 && y >= y0 && y <= y1 }

        Art.ground(&g, size: size, S: S, season: season, visible: view, tiles: CGSize(width: W, height: H))
        var woods: [(Int, Int)] = [], waters: [(Int, Int, Int)] = [], roads: [(Int, Int)] = []
        for y in y0...y1 { for x in x0...x1 {
            let i = y * W + x
            switch world.ground[i] {
            case .forest: woods.append((x, y))
            case .water: waters.append((x, y, depth(x, y)))
            default: break
            }
            if world.road[i] { roads.append((x, y)) }
        } }
        Art.forestFloor(&g, woods, S: S, season: season)
        Art.water(&g, tiles: waters, S: S, season: season, now: now)
        Art.roads(&g, roads, isRoad: { x, y in x >= 0 && y >= 0 && x < W && y < H && world.road[y * W + x] }, S: S, season: season)

        // Flat things: fields and the plots under buildings.
        for b in world.buildings where seen(b.x, b.y) || seen(b.x + 3, b.y + 3) {
            let n = CityWorld.size(b.kind), r = CGRect(x: CGFloat(b.x) * S, y: CGFloat(b.y) * S, width: CGFloat(n) * S, height: CGFloat(n) * S)
            if b.kind == .field { field(&g, b, r, S, season) } else { Art.plot(&g, r, S: S, season: season) }
        }

        // Standing things, from the back to the front.
        enum Thing { case tree(Int, Int), rock(Int, Int), building(CityBuilding), person(CityPerson) }
        var things: [(CGFloat, Thing)] = []
        for (x, y) in woods { things.append((CGFloat(y) + 0.82, .tree(x, y))) }
        for y in y0...y1 { for x in x0...x1 where world.ground[y * W + x] == .rock || world.ground[y * W + x] == .ore { things.append((CGFloat(y) + 0.8, .rock(x, y))) } }
        for b in world.buildings where b.kind != .field && (seen(b.x, b.y) || seen(b.x + 2, b.y + 2)) { things.append((CGFloat(b.y + CityWorld.size(b.kind)) - 0.15, .building(b))) }
        for p in world.people where !p.inside && seen(Int(p.x), Int(p.y)) { things.append((CGFloat(p.y), .person(p))) }
        things.sort { $0.0 < $1.0 }
        for (_, thing) in things {
            switch thing {
            case .tree(let x, let y):
                let h = Art.hash(x, y)
                let foot = CGPoint(x: (CGFloat(x) + 0.5 + CGFloat(h % 9 - 4) * 0.035) * S, y: (CGFloat(y) + 0.82) * S)
                Art.tree(&g, foot: foot, S: S, grown: world.wood[y * W + x], variant: h, season: season, conifer: h % 10 < 6, now: now)
            case .rock(let x, let y):
                Art.deposit(&g, world.ground[y * W + x] == .ore ? .ore : .stone, centre: CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.6) * S), S: S, left: 1, variant: Art.hash(x, y), season: season)
            case .building(let b): building(&g, b, S, season)
            case .person(let p): person(&g, p, S)
            }
        }

        // What happened a moment ago.
        for e in world.events {
            let age = world.time - e.time
            let at = CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S)
            switch e.kind {
            case .born where age < 4:
                JevDraw.text(g, "❤︎", at: CGPoint(x: at.x, y: at.y - S * (0.9 + CGFloat(age) * 0.35)), size: S * 0.6, colour: Color(red: 1, green: 0.4, blue: 0.5).opacity(1 - age / 4))
            case .died(let cause) where age < 5:
                JevDraw.text(g, cause == .age ? "✝︎" : cause == .hunger ? "✝︎ 饿" : "✝︎ 冻", at: CGPoint(x: at.x, y: at.y - S * 0.8), size: S * 0.45, colour: Color.white.opacity(1 - age / 5))
            case .finished where age < 2:
                for k in 0..<8 {
                    let a = Double(k) * 0.785 + age * 2
                    let r = S * CGFloat(0.7 + age * 0.9)
                    JevDraw.text(g, "✦", at: CGPoint(x: at.x + CGFloat(cos(a)) * r, y: at.y - S * 0.4 + CGFloat(sin(a)) * r * 0.7), size: S * 0.35, colour: Color.yellow.opacity(1 - age / 2), shadow: false)
                }
            case .felled where age < 0.9:
                let t = age / 0.9
                g.fill(Path(ellipseIn: CGRect(x: at.x - S * 0.5 * CGFloat(0.5 + t), y: at.y - S * 0.15, width: S * CGFloat(0.5 + t), height: S * 0.3)), with: .color(Color(red: 0.62, green: 0.52, blue: 0.36).opacity(0.5 * (1 - t))))
            case .arrived(let n) where age < 6:
                JevDraw.text(g, "新来了 \(n) 人", at: CGPoint(x: at.x + S * 2.5, y: at.y - S), size: max(12, S * 0.55), colour: .white.opacity(1 - age / 6))
            default: break
            }
        }

        // The weather, over the part in view.
        let viewPoints = CGRect(x: view.minX * S, y: view.minY * S, width: view.width * S, height: view.height * S)
        var sky = g
        sky.translateBy(x: viewPoints.minX, y: viewPoints.minY)
        let m = season.month
        if snow > 0 || (8.6...9.3).contains(m) { Art.snowfall(&sky, size: viewPoints.size, amount: max(snow, (8.6...9.3).contains(m) ? (m - 8.6) / 0.7 : 0), now: now, S: S) }
        else if (6.6...8.8).contains(m) { Art.leaves(&sky, size: viewPoints.size, now: now, spring: false) }
        else if m < 1.5 { Art.leaves(&sky, size: viewPoints.size, now: now, spring: true) }

        // The mouse: the building chosen, the one about to go down, the road being drawn.
        func rect(_ x: Int, _ y: Int, _ n: Int = 1) -> CGRect { CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: CGFloat(n) * S, height: CGFloat(n) * S) }
        if let id = selected, let b = world.building(id) {
            let n = CityWorld.size(b.kind), r = rect(b.x, b.y, n)
            g.stroke(Path(roundedRect: r.insetBy(dx: -2, dy: -2), cornerRadius: S * 0.2), with: .color(.yellow), lineWidth: 2)
            if [.gatherer, .forester, .fishery].contains(b.kind) { reach(&g, CGPoint(x: r.midX, y: r.midY), S) }
        }
        if let kind = placing, let hover {
            let n = CityWorld.size(kind), o = CityTile(x: hover.x - (n - 1) / 2, y: hover.y - (n - 1) / 2)
            let ok = world.fits(kind, at: o), r = rect(o.x, o.y, n)
            var ghost = g
            ghost.opacity = 0.6
            if kind == .field { field(&ghost, CityBuilding(id: -1, kind: kind, x: o.x, y: o.y, done: true), r, S, season) }
            else { building(&ghost, CityBuilding(id: -1, kind: kind, x: o.x, y: o.y, done: true), S, season) }
            g.fill(Path(roundedRect: r, cornerRadius: S * 0.2), with: .color((ok ? Color.green : Color.red).opacity(0.22)))
            g.stroke(Path(roundedRect: r, cornerRadius: S * 0.2), with: .color(ok ? .green : .red), lineWidth: 1.5)
            if [.gatherer, .forester, .fishery].contains(kind) { reach(&g, CGPoint(x: r.midX, y: r.midY), S) }
        }
        if tool == .road {
            for t in CityScene.line(drag?.0 ?? hover, drag?.1 ?? hover) {
                let ok = CityWorld.inside(t) && world.ground[CityWorld.index(t)] == .grass && world.occupant[CityWorld.index(t)] == nil
                g.fill(Path(roundedRect: rect(t.x, t.y).insetBy(dx: S * 0.08, dy: S * 0.08), cornerRadius: S * 0.3), with: .color((ok ? Color(red: 0.78, green: 0.64, blue: 0.46) : Color.red).opacity(0.7)))
            }
        }
        if tool == .bulldoze, let hover, CityWorld.inside(hover) {
            if let id = world.occupant[CityWorld.index(hover)], let b = world.building(id), b.kind != .townHall {
                g.fill(Path(roundedRect: rect(b.x, b.y, CityWorld.size(b.kind)), cornerRadius: S * 0.2), with: .color(Color.red.opacity(0.35)))
            } else {
                g.stroke(Path(roundedRect: rect(hover.x, hover.y), cornerRadius: S * 0.2), with: .color(.red), lineWidth: 1.5)
            }
        }
    }

    /// The tiles of a road dragged from one tile to another: along, then down.
    static func line(_ a: CityTile?, _ b: CityTile?) -> [CityTile] {
        guard let a, let b else { return [] }
        var out: [CityTile] = []
        let sx = b.x >= a.x ? 1 : -1, sy = b.y >= a.y ? 1 : -1
        for x in stride(from: a.x, through: b.x, by: sx) { out.append(CityTile(x: x, y: a.y)) }
        for y in stride(from: a.y + sy, through: b.y, by: sy) where a.y != b.y { out.append(CityTile(x: b.x, y: y)) }
        return out
    }

    /// Steps from a water tile to the nearest land, up to 3.
    private func depth(_ x: Int, _ y: Int) -> Int {
        for d in 1...3 {
            for dy in -d...d { for dx in -d...d where abs(dx) == d || abs(dy) == d {
                let t = CityTile(x: x + dx, y: y + dy)
                if CityWorld.inside(t), world.ground[CityWorld.index(t)] != .water { return d }
            } }
        }
        return 4
    }

    private func reach(_ g: inout GraphicsContext, _ c: CGPoint, _ S: CGFloat) {
        let r = CGFloat(CityWorld.reach) * S
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color.white.opacity(0.08)))
        g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.65)), style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
    }

    // MARK: Fields

    private func field(_ g: inout GraphicsContext, _ b: CityBuilding, _ area: CGRect, _ S: CGFloat, _ season: Art.Season) {
        let n = CityWorld.size(.field), m = season.month, snow = season.snow
        let soil: Art.RGB = (0.5, 0.36, 0.22)
        let inner = area.insetBy(dx: S * 0.08, dy: S * 0.08)
        // A low fence of posts and rails.
        g.fill(Path(roundedRect: inner, cornerRadius: S * 0.12), with: .color(Art.c(soil, b.done ? 1 : 0.4 + 0.6 * b.progress)))
        for row in 0..<(n * 3) {
            let y = inner.minY + inner.height * (CGFloat(row) + 0.5) / CGFloat(n * 3)
            g.stroke(Path { p in p.move(to: CGPoint(x: inner.minX + S * 0.08, y: y)); p.addLine(to: CGPoint(x: inner.maxX - S * 0.08, y: y)) }, with: .color(Art.c(Art.lit(soil, 0.72))), lineWidth: max(1, S * 0.07))
            g.stroke(Path { p in p.move(to: CGPoint(x: inner.minX + S * 0.08, y: y - S * 0.06)); p.addLine(to: CGPoint(x: inner.maxX - S * 0.08, y: y - S * 0.06)) }, with: .color(Art.c(Art.lit(soil, 1.15))), lineWidth: max(0.6, S * 0.03))
        }
        if b.done {
            let tiles = n * n
            for k in 0..<tiles {
                let row = k / n, col = row % 2 == 0 ? k % n : n - 1 - k % n
                let cell = CGRect(x: CGFloat(b.x + col) * S, y: CGFloat(b.y + row) * S, width: S, height: S)
                guard Double(k) < b.planted * Double(tiles) - 0.01 else { continue }
                let cut = Double(k) < b.harvested * Double(tiles) - 0.01
                for f in 0..<3 { for q in 0..<4 {
                    let p = CGPoint(x: cell.minX + S * (0.14 + CGFloat(q) * 0.24), y: cell.minY + S * (0.3 + CGFloat(f) * 0.3))
                    if cut {
                        g.stroke(Path { path in path.move(to: p); path.addLine(to: CGPoint(x: p.x, y: p.y - S * 0.06)) }, with: .color(Art.c((0.86, 0.76, 0.46))), lineWidth: max(0.8, S * 0.035))
                        continue
                    }
                    let sway = CGFloat(sin(now * 1.6 + Double(b.x + col + q + f))) * S * 0.03
                    if m < 3 {
                        let r = S * CGFloat(0.03 + 0.04 * b.planted)
                        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 1.5, width: 2 * r, height: 2 * r)), with: .color(Art.c((0.45, 0.74, 0.3))))
                    } else {
                        let tall = S * CGFloat(0.12 + 0.2 * b.grown)
                        let ripe = m >= 5.5
                        let stem: Art.RGB = ripe ? (0.86, 0.72, 0.3) : Art.mix((0.34, 0.62, 0.24), (0.6, 0.68, 0.3), b.grown)
                        g.stroke(Path { path in path.move(to: p); path.addQuadCurve(to: CGPoint(x: p.x + sway, y: p.y - tall), control: CGPoint(x: p.x, y: p.y - tall * 0.5)) }, with: .color(Art.c(stem)), lineWidth: max(0.9, S * 0.04))
                        if ripe { g.fill(Path(ellipseIn: CGRect(x: p.x + sway - S * 0.035, y: p.y - tall - S * 0.07, width: S * 0.07, height: S * 0.12)), with: .color(Art.c((0.95, 0.8, 0.36)))) }
                    }
                } }
            }
        }
        if snow > 0 { g.fill(Path(roundedRect: inner, cornerRadius: S * 0.12), with: .color(.white.opacity(0.85 * snow))) }
        let post: Art.RGB = (0.5, 0.36, 0.22)
        g.stroke(Path(roundedRect: inner, cornerRadius: S * 0.12), with: .color(Art.c(post)), lineWidth: max(1, S * 0.04))
        if S > 18 {
            for k in 0...(n * 2) {
                for (x, y) in [(inner.minX + inner.width * CGFloat(k) / CGFloat(n * 2), inner.minY), (inner.minX + inner.width * CGFloat(k) / CGFloat(n * 2), inner.maxY)] {
                    g.fill(Path(CGRect(x: x - S * 0.03, y: y - S * 0.12, width: S * 0.06, height: S * 0.14)), with: .color(Art.c(Art.lit(post, 0.8))))
                }
            }
        }
        if !b.done { Art.bar(&g, CGRect(x: area.minX + S * 0.2, y: area.minY - S * 0.2, width: area.width - S * 0.4, height: max(3, S * 0.1)), b.progress, colour: Color(red: 0.98, green: 0.78, blue: 0.2)) }
    }

    // MARK: Buildings

    private func building(_ g: inout GraphicsContext, _ b: CityBuilding, _ S: CGFloat, _ season: Art.Season) {
        let n = CGFloat(CityWorld.size(b.kind))
        let F = CGRect(x: CGFloat(b.x) * S, y: CGFloat(b.y) * S, width: n * S, height: n * S)
        let snow = season.snow
        let heats = CityWorld.heats(Int(season.month))
        let occupied = b.kind == .house ? world.people.contains { $0.home == b.id } : world.people.contains { $0.job == b.id }
        let warm = heats && occupied && (b.stock[4] > 0 || world.stored(.firewood) > 0)
        let m = S * 0.16
        let wallH = S * (n >= 3 ? 0.8 : 0.58)
        let bottom = F.maxY - m
        let wall = CGRect(x: F.minX + m, y: bottom - wallH, width: F.width - 2 * m, height: wallH)
        let roofArea = CGRect(x: F.minX + m, y: F.minY + m - wallH * 0.45, width: F.width - 2 * m, height: wall.minY - (F.minY + m - wallH * 0.45))
        var draw = g
        if !b.done { draw.opacity = 0.25 + 0.65 * b.progress }

        // The shadow thrown to the lower right.
        g.fill(Path { p in
            p.move(to: CGPoint(x: wall.maxX, y: roofArea.minY + S * 0.2)); p.addLine(to: CGPoint(x: wall.maxX + S * 0.35, y: roofArea.minY + S * 0.45))
            p.addLine(to: CGPoint(x: wall.maxX + S * 0.35, y: bottom + S * 0.18)); p.addLine(to: CGPoint(x: wall.minX + S * 0.25, y: bottom + S * 0.18)); p.addLine(to: CGPoint(x: wall.minX, y: bottom)); p.addLine(to: CGPoint(x: wall.maxX, y: bottom)); p.closeSubpath()
        }, with: .color(.black.opacity(b.done ? 0.2 : 0.08)))

        switch b.kind {
        case .house:
            Art.wall(&draw, wall, .plaster, S: S)
            Art.gable(&draw, wall, roofArea, colour: (0.68, 0.3, 0.2), kind: .shingles, S: S, snow: snow)
            Art.door(&draw, CGRect(x: wall.midX - S * 0.13, y: wall.maxY - wallH * 0.62, width: S * 0.26, height: wallH * 0.62), S: S)
            Art.window(&draw, CGRect(x: wall.minX + S * 0.18, y: wall.minY + wallH * 0.28, width: S * 0.24, height: S * 0.2), S: S, glow: warm)
            Art.window(&draw, CGRect(x: wall.maxX - S * 0.42, y: wall.minY + wallH * 0.28, width: S * 0.24, height: S * 0.2), S: S, glow: warm)
            Art.chimney(&draw, at: CGPoint(x: roofArea.maxX - S * 0.4, y: roofArea.minY + roofArea.height * 0.45), S: S, smoking: warm, now: now, seed: b.id, snow: snow)
        case .townHall:
            Art.wall(&draw, wall, .stone, S: S, tint: (0.78, 0.74, 0.66))
            Art.roof(&draw, roofArea, .slate, colour: (0.34, 0.4, 0.52), S: S, snow: snow, gable: false)
            // The bell tower, its spire and a flag.
            let tower = CGRect(x: wall.midX - S * 0.45, y: roofArea.minY + roofArea.height * 0.25, width: S * 0.9, height: wall.minY - roofArea.minY - roofArea.height * 0.25 + S * 0.2)
            Art.wall(&draw, tower, .stone, S: S, tint: (0.86, 0.82, 0.72))
            Art.window(&draw, CGRect(x: tower.midX - S * 0.14, y: tower.minY + S * 0.2, width: S * 0.28, height: S * 0.3), S: S, glow: heats)
            let spire = Path { p in p.move(to: CGPoint(x: tower.midX, y: tower.minY - S * 1.0)); p.addLine(to: CGPoint(x: tower.maxX + S * 0.08, y: tower.minY + S * 0.05)); p.addLine(to: CGPoint(x: tower.minX - S * 0.08, y: tower.minY + S * 0.05)); p.closeSubpath() }
            draw.fill(spire, with: .color(Art.c((0.3, 0.36, 0.5))))
            draw.fill(Path { p in p.move(to: CGPoint(x: tower.midX, y: tower.minY - S * 1.0)); p.addLine(to: CGPoint(x: tower.maxX + S * 0.08, y: tower.minY + S * 0.05)); p.addLine(to: CGPoint(x: tower.midX, y: tower.minY + S * 0.05)); p.closeSubpath() }, with: .color(Art.c((0.22, 0.27, 0.38))))
            if snow > 0 { draw.fill(Path { p in p.move(to: CGPoint(x: tower.midX, y: tower.minY - S * 1.0)); p.addLine(to: CGPoint(x: tower.midX + S * 0.2, y: tower.minY - S * 0.62)); p.addLine(to: CGPoint(x: tower.midX - S * 0.2, y: tower.minY - S * 0.62)); p.closeSubpath() }, with: .color(.white.opacity(snow))) }
            let top = CGPoint(x: tower.midX, y: tower.minY - S * 1.0)
            draw.stroke(Path { p in p.move(to: top); p.addLine(to: CGPoint(x: top.x, y: top.y - S * 0.55)) }, with: .color(Art.c(Art.ink)), lineWidth: max(1, S * 0.03))
            let wave = CGFloat(sin(now * 3.2)) * S * 0.05
            draw.fill(Path { p in p.move(to: CGPoint(x: top.x, y: top.y - S * 0.55)); p.addQuadCurve(to: CGPoint(x: top.x + S * 0.5, y: top.y - S * 0.44 + wave), control: CGPoint(x: top.x + S * 0.25, y: top.y - S * 0.6 - wave)); p.addLine(to: CGPoint(x: top.x, y: top.y - S * 0.3)); p.closeSubpath() }, with: .color(Art.c((0.2, 0.62, 0.46))))
            Art.door(&draw, CGRect(x: wall.midX - S * 0.22, y: wall.maxY - wallH * 0.7, width: S * 0.44, height: wallH * 0.7), S: S, colour: (0.36, 0.22, 0.14))
            for x in [wall.minX + S * 0.35, wall.maxX - S * 0.65] { Art.window(&draw, CGRect(x: x, y: wall.minY + wallH * 0.25, width: S * 0.3, height: S * 0.26), S: S, glow: heats) }
            goods(&draw, b, CGRect(x: F.minX, y: F.maxY - S * 0.42, width: F.width, height: S * 0.4), S)
        case .storage:
            Art.wall(&draw, wall, .planks, S: S, tint: (0.66, 0.38, 0.26))
            Art.roof(&draw, roofArea, .planks, colour: (0.6, 0.26, 0.2), S: S, snow: snow, gable: false)
            let doors = CGRect(x: wall.midX - S * 0.45, y: wall.maxY - wallH * 0.82, width: S * 0.9, height: wallH * 0.82)
            draw.fill(Path(doors), with: .color(Art.c((0.46, 0.26, 0.18))))
            draw.stroke(Path { p in p.move(to: CGPoint(x: doors.minX, y: doors.minY)); p.addLine(to: CGPoint(x: doors.maxX, y: doors.maxY)); p.move(to: CGPoint(x: doors.maxX, y: doors.minY)); p.addLine(to: CGPoint(x: doors.minX, y: doors.maxY)); p.move(to: CGPoint(x: doors.midX, y: doors.minY)); p.addLine(to: CGPoint(x: doors.midX, y: doors.maxY)) },
                        with: .color(Art.c((0.92, 0.86, 0.74))), lineWidth: max(0.8, S * 0.04))
            goods(&draw, b, CGRect(x: F.minX, y: F.maxY - S * 0.42, width: F.width, height: S * 0.4), S)
        case .gatherer:
            Art.wall(&draw, wall, .logs, S: S)
            Art.gable(&draw, wall, roofArea, colour: (0.82, 0.68, 0.36), kind: .thatch, S: S, snow: snow)
            Art.door(&draw, CGRect(x: wall.midX - S * 0.12, y: wall.maxY - wallH * 0.6, width: S * 0.24, height: wallH * 0.6), S: S)
            for k in 0..<2 { basket(&draw, CGPoint(x: F.minX + S * (0.28 + CGFloat(k) * 1.4), y: F.maxY - S * 0.1), S, berries: k == 0) }
        case .forester:
            Art.wall(&draw, wall, .logs, S: S, tint: (0.5, 0.34, 0.2))
            Art.gable(&draw, wall, roofArea, colour: (0.36, 0.3, 0.26), kind: .shingles, S: S, snow: snow)
            Art.door(&draw, CGRect(x: wall.minX + S * 0.18, y: wall.maxY - wallH * 0.6, width: S * 0.24, height: wallH * 0.6), S: S)
            logPile(&draw, CGRect(x: F.maxX - S * 0.95, y: F.maxY - S * 0.42, width: S * 0.85, height: S * 0.34), S, snow: snow)
        case .woodcutter:
            // An open shed: a back wall, a lean-to roof, firewood stacked under it, a block with an axe.
            let back = CGRect(x: wall.minX, y: roofArea.minY + S * 0.1, width: wall.width, height: bottom - roofArea.minY - S * 0.1)
            Art.wall(&draw, back, .planks, S: S)
            let lean = CGRect(x: roofArea.minX - S * 0.05, y: roofArea.minY, width: roofArea.width + S * 0.1, height: roofArea.height * 0.7)
            Art.roof(&draw, lean, .planks, colour: (0.52, 0.38, 0.26), S: S, snow: snow, gable: false)
            let split = min(1, (b.stock[4] + 6) / 16)
            for k in 0..<Int(3 + 6 * split) {
                let x = wall.minX + S * 0.08 + CGFloat(k % 5) * S * 0.24, y = bottom - S * 0.12 - CGFloat(k / 5) * S * 0.16
                draw.fill(Path(roundedRect: CGRect(x: x, y: y - S * 0.14, width: S * 0.22, height: S * 0.14), cornerRadius: S * 0.03), with: .color(Art.c((0.72, 0.52, 0.3))))
                draw.fill(Path(ellipseIn: CGRect(x: x + S * 0.02, y: y - S * 0.12, width: S * 0.1, height: S * 0.1)), with: .color(Art.c((0.9, 0.78, 0.56))))
            }
            let block = CGRect(x: F.maxX - S * 0.55, y: F.maxY - S * 0.42, width: S * 0.34, height: S * 0.22)
            draw.fill(Path(ellipseIn: block), with: .color(Art.c((0.55, 0.4, 0.26))))
            draw.stroke(Path { p in p.move(to: CGPoint(x: block.midX, y: block.minY + S * 0.05)); p.addLine(to: CGPoint(x: block.midX + S * 0.18, y: block.minY - S * 0.22)) }, with: .color(Art.c((0.5, 0.36, 0.22))), lineWidth: max(1, S * 0.04))
        case .quarry, .mine:
            let stone = b.kind == .quarry
            let pit = F.insetBy(dx: S * 0.12, dy: S * 0.12)
            let rock: Art.RGB = stone ? (0.66, 0.65, 0.63) : (0.42, 0.38, 0.36)
            for k in 0..<3 {
                let r = pit.insetBy(dx: CGFloat(k) * S * 0.28, dy: CGFloat(k) * S * 0.24)
                draw.fill(Path(roundedRect: r, cornerRadius: S * 0.25), with: .color(Art.c(Art.lit(rock, 1 - Double(k) * 0.14))))
                draw.stroke(Path(roundedRect: r, cornerRadius: S * 0.25), with: .color(Art.c(Art.lit(rock, 0.66))), lineWidth: max(0.7, S * 0.03))
            }
            if stone {
                for k in 0..<5 {
                    let r = CGRect(x: pit.minX + S * (0.15 + CGFloat(k % 3) * 0.55), y: pit.maxY - S * (0.42 + CGFloat(k / 3) * 0.28), width: S * 0.42, height: S * 0.26)
                    draw.fill(Path(roundedRect: r, cornerRadius: S * 0.04), with: .color(Art.c((0.84, 0.83, 0.8))))
                    draw.fill(Path(CGRect(x: r.minX, y: r.maxY - S * 0.07, width: r.width, height: S * 0.07)), with: .color(Art.c((0.62, 0.61, 0.58))))
                }
                // A wooden crane.
                let foot = CGPoint(x: pit.maxX - S * 0.4, y: pit.maxY - S * 0.2)
                draw.stroke(Path { p in p.move(to: foot); p.addLine(to: CGPoint(x: foot.x, y: foot.y - S * 1.4)); p.addLine(to: CGPoint(x: foot.x - S * 1.1, y: foot.y - S * 1.1)) }, with: .color(Art.c((0.5, 0.36, 0.22))), lineWidth: max(1, S * 0.07))
                draw.stroke(Path { p in p.move(to: CGPoint(x: foot.x - S * 1.1, y: foot.y - S * 1.1)); p.addLine(to: CGPoint(x: foot.x - S * 1.1, y: foot.y - S * 0.5)) }, with: .color(Art.c(Art.ink, 0.7)), lineWidth: max(0.5, S * 0.02))
            } else {
                // A timbered mouth in the hillside, rails, a cart of ore.
                let mouth = CGRect(x: pit.midX - S * 0.45, y: pit.midY - S * 0.45, width: S * 0.9, height: S * 0.8)
                draw.fill(Path(roundedRect: mouth, cornerRadii: RectangleCornerRadii(topLeading: S * 0.45, bottomLeading: 0, bottomTrailing: 0, topTrailing: S * 0.45)), with: .color(Art.c((0.08, 0.06, 0.05))))
                draw.stroke(Path { p in p.move(to: CGPoint(x: mouth.minX, y: mouth.maxY)); p.addLine(to: CGPoint(x: mouth.minX, y: mouth.minY + S * 0.2)); p.addLine(to: CGPoint(x: mouth.maxX, y: mouth.minY + S * 0.2)); p.addLine(to: CGPoint(x: mouth.maxX, y: mouth.maxY)) },
                            with: .color(Art.c((0.6, 0.44, 0.26))), lineWidth: max(1.2, S * 0.08))
                for dx in [-0.18, 0.18] { draw.stroke(Path { p in p.move(to: CGPoint(x: mouth.midX + S * CGFloat(dx), y: mouth.maxY)); p.addLine(to: CGPoint(x: mouth.midX + S * CGFloat(dx) * 1.6, y: pit.maxY)) }, with: .color(Art.c((0.45, 0.42, 0.4))), lineWidth: max(0.8, S * 0.03)) }
                let cart = CGRect(x: pit.maxX - S * 0.8, y: pit.maxY - S * 0.48, width: S * 0.55, height: S * 0.3)
                draw.fill(Path(roundedRect: cart, cornerRadius: S * 0.04), with: .color(Art.c((0.46, 0.32, 0.2))))
                draw.fill(Path(ellipseIn: CGRect(x: cart.minX + S * 0.05, y: cart.minY - S * 0.1, width: cart.width - S * 0.1, height: S * 0.18)), with: .color(Art.c((0.32, 0.3, 0.32))))
                draw.fill(Path(ellipseIn: CGRect(x: cart.midX - S * 0.08, y: cart.minY - S * 0.08, width: S * 0.1, height: S * 0.08)), with: .color(Art.c((0.82, 0.44, 0.2))))
            }
            if snow > 0 { draw.fill(Path(roundedRect: pit, cornerRadius: S * 0.25), with: .color(.white.opacity(0.4 * snow))) }
            if b.done, b.reserve <= 0 { JevDraw.text(draw, "挖空了", at: CGPoint(x: pit.midX, y: pit.midY), size: max(11, S * 0.4)) }
        case .blacksmith:
            Art.wall(&draw, wall, .stone, S: S)
            Art.gable(&draw, wall, roofArea, colour: (0.36, 0.38, 0.44), kind: .slate, S: S, snow: snow)
            let forge = CGRect(x: wall.minX + S * 0.14, y: wall.maxY - wallH * 0.64, width: S * 0.42, height: wallH * 0.52)
            let glow = 0.6 + 0.4 * sin(now * 6 + Double(b.id))
            draw.fill(Path(roundedRect: forge, cornerRadii: RectangleCornerRadii(topLeading: S * 0.2, bottomLeading: 0, bottomTrailing: 0, topTrailing: S * 0.2)), with: .color(Color(red: 1, green: 0.45 + 0.25 * glow, blue: 0.1)))
            draw.fill(Path(ellipseIn: forge.insetBy(dx: -S * 0.3, dy: -S * 0.3)), with: .color(Color(red: 1, green: 0.6, blue: 0.2).opacity(0.18 * glow)))
            let anvil = CGPoint(x: F.maxX - S * 0.55, y: F.maxY - S * 0.14)
            draw.fill(Path { p in p.move(to: CGPoint(x: anvil.x - S * 0.22, y: anvil.y - S * 0.2)); p.addLine(to: CGPoint(x: anvil.x + S * 0.24, y: anvil.y - S * 0.2)); p.addLine(to: CGPoint(x: anvil.x + S * 0.1, y: anvil.y - S * 0.1)); p.addLine(to: CGPoint(x: anvil.x + S * 0.08, y: anvil.y)); p.addLine(to: CGPoint(x: anvil.x - S * 0.08, y: anvil.y)); p.addLine(to: CGPoint(x: anvil.x - S * 0.1, y: anvil.y - S * 0.1)); p.closeSubpath() }, with: .color(Art.c((0.26, 0.26, 0.28))))
            Art.chimney(&draw, at: CGPoint(x: roofArea.maxX - S * 0.35, y: roofArea.minY + roofArea.height * 0.4), S: S, smoking: occupied, now: now, seed: b.id, snow: snow)
            if occupied, S > 16 {
                for k in 0..<4 {
                    let t = (now * 1.6 + Double(k) * 0.25).truncatingRemainder(dividingBy: 1)
                    draw.fill(Path(ellipseIn: CGRect(x: anvil.x + CGFloat(cos(Double(k) * 1.7)) * S * 0.3 * CGFloat(t), y: anvil.y - S * 0.25 - CGFloat(t) * S * 0.35, width: S * 0.04, height: S * 0.04)), with: .color(Color(red: 1, green: 0.8, blue: 0.3).opacity(1 - t)))
                }
            }
        case .fishery:
            // A jetty out to the nearest water, a boat at it, nets drying, then the hut.
            let c = world.centre(b)
            var best: CityTile?, d = Double.infinity
            for dy in -3...3 { for dx in -3...3 {
                let t = CityTile(x: b.x + dx, y: b.y + dy)
                if CityWorld.inside(t), world.ground[CityWorld.index(t)] == .water, hypot(Double(t.x) + 0.5 - c.x, Double(t.y) + 0.5 - c.y) < d { d = hypot(Double(t.x) + 0.5 - c.x, Double(t.y) + 0.5 - c.y); best = t }
            } }
            if let wtile = best {
                let to = CGPoint(x: (CGFloat(wtile.x) + 0.5) * S, y: (CGFloat(wtile.y) + 0.5) * S)
                g.stroke(Path { p in p.move(to: CGPoint(x: F.midX, y: F.midY)); p.addLine(to: to) }, with: .color(Art.c((0.58, 0.42, 0.26))), style: StrokeStyle(lineWidth: S * 0.26, lineCap: .butt))
                g.stroke(Path { p in p.move(to: CGPoint(x: F.midX, y: F.midY)); p.addLine(to: to) }, with: .color(Art.c((0.44, 0.3, 0.18))), style: StrokeStyle(lineWidth: S * 0.26, lineCap: .butt, dash: [S * 0.02, S * 0.1]))
                let bob = CGFloat(sin(now * 2 + Double(b.id))) * S * 0.03
                let boat = Path(ellipseIn: CGRect(x: to.x - S * 0.4, y: to.y + S * 0.1 + bob, width: S * 0.8, height: S * 0.3))
                g.fill(boat, with: .color(Art.c((0.52, 0.32, 0.18))))
                g.fill(Path(ellipseIn: CGRect(x: to.x - S * 0.3, y: to.y + S * 0.13 + bob, width: S * 0.6, height: S * 0.18)), with: .color(Art.c((0.68, 0.48, 0.3))))
            }
            Art.wall(&draw, wall, .planks, S: S, tint: (0.56, 0.5, 0.44))
            Art.gable(&draw, wall, roofArea, colour: (0.78, 0.66, 0.4), kind: .thatch, S: S, snow: snow)
            Art.door(&draw, CGRect(x: wall.midX - S * 0.12, y: wall.maxY - wallH * 0.6, width: S * 0.24, height: wallH * 0.6), S: S)
            if S > 16 {
                let net = CGRect(x: F.minX - S * 0.05, y: F.maxY - S * 0.55, width: S * 0.5, height: S * 0.4)
                for x in [net.minX, net.maxX] { draw.stroke(Path { p in p.move(to: CGPoint(x: x, y: net.maxY)); p.addLine(to: CGPoint(x: x, y: net.minY)) }, with: .color(Art.c((0.5, 0.36, 0.22))), lineWidth: max(0.8, S * 0.03)) }
                for k in 1..<4 { draw.stroke(Path { p in p.move(to: CGPoint(x: net.minX, y: net.minY + net.height * CGFloat(k) / 4)); p.addLine(to: CGPoint(x: net.maxX, y: net.minY + net.height * CGFloat(k) / 4)) }, with: .color(Art.c((0.86, 0.84, 0.76), 0.8)), lineWidth: max(0.4, S * 0.012)) }
                for k in 1..<4 { draw.stroke(Path { p in p.move(to: CGPoint(x: net.minX + net.width * CGFloat(k) / 4, y: net.minY)); p.addLine(to: CGPoint(x: net.minX + net.width * CGFloat(k) / 4, y: net.maxY)) }, with: .color(Art.c((0.86, 0.84, 0.76), 0.8)), lineWidth: max(0.4, S * 0.012)) }
            }
        case .field: break
        }
        if !b.done {
            let cost = CityWorld.cost(b.kind)
            let brought = cost[1] + cost[2] > 0 ? (b.delivered[1] + b.delivered[2]) / (cost[1] + cost[2]) : 1
            Art.scaffold(&g, CGRect(x: wall.minX, y: roofArea.minY, width: wall.width, height: bottom - roofArea.minY), S: S, progress: b.progress, brought: brought)
            if b.delivered[1] > 0 { logPile(&g, CGRect(x: F.minX + S * 0.05, y: F.maxY - S * 0.3, width: S * 0.7, height: S * 0.26), S, snow: 0) }
            if b.delivered[2] > 0 {
                for k in 0..<min(3, Int(b.delivered[2] / 5) + 1) {
                    g.fill(Path(roundedRect: CGRect(x: F.maxX - S * (0.42 + CGFloat(k) * 0.22), y: F.maxY - S * 0.3, width: S * 0.2, height: S * 0.16), cornerRadius: S * 0.03), with: .color(Art.c((0.74, 0.74, 0.72))))
                }
            }
        }
    }

    private func logPile(_ g: inout GraphicsContext, _ r: CGRect, _ S: CGFloat, snow: Double) {
        let rows = 3
        for row in 0..<rows {
            let count = rows - row + 1
            for k in 0..<count {
                let d = r.height / CGFloat(rows)
                let x = r.minX + CGFloat(row) * d * 0.5 + CGFloat(k) * d
                let y = r.maxY - CGFloat(row + 1) * d * 0.9
                g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(Art.c((0.58, 0.4, 0.22))))
                g.fill(Path(ellipseIn: CGRect(x: x + d * 0.18, y: y + d * 0.18, width: d * 0.64, height: d * 0.64)), with: .color(Art.c((0.88, 0.74, 0.5))))
            }
        }
        if snow > 0 { g.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY - S * 0.04, width: r.width * 0.9, height: S * 0.08), cornerRadius: S * 0.04), with: .color(.white.opacity(snow))) }
    }

    private func basket(_ g: inout GraphicsContext, _ at: CGPoint, _ S: CGFloat, berries: Bool) {
        g.fill(Path(ellipseIn: CGRect(x: at.x - S * 0.2, y: at.y - S * 0.2, width: S * 0.4, height: S * 0.24)), with: .color(Art.c((0.66, 0.48, 0.26))))
        g.stroke(Path(ellipseIn: CGRect(x: at.x - S * 0.2, y: at.y - S * 0.2, width: S * 0.4, height: S * 0.24)), with: .color(Art.c((0.48, 0.34, 0.18))), lineWidth: max(0.5, S * 0.02))
        for k in 0..<5 {
            let p = CGPoint(x: at.x - S * 0.12 + CGFloat(k) * S * 0.06, y: at.y - S * 0.17 + CGFloat(k % 2) * S * 0.03)
            g.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: S * 0.07, height: S * 0.07)), with: .color(berries ? Art.c((0.85, 0.14, 0.22)) : Art.c((0.92, 0.84, 0.72))))
        }
    }

    /// Goods piled in front of a storage: sacks of food, logs, stone blocks, iron, firewood, tools — by how much there is.
    private func goods(_ g: inout GraphicsContext, _ b: CityBuilding, _ strip: CGRect, _ S: CGFloat) {
        var x = strip.minX + S * 0.12
        for gd in 0..<6 where b.stock[gd] >= 1 {
            let piles = min(3, Int(b.stock[gd] / 60) + 1)
            for k in 0..<piles {
                let r = CGRect(x: x + CGFloat(k) * S * 0.06, y: strip.maxY - S * 0.24 - CGFloat(k) * S * 0.1, width: S * 0.24, height: S * 0.18)
                switch gd {
                case 0: g.fill(Path(roundedRect: r, cornerRadius: S * 0.07), with: .color(Art.c((0.9, 0.82, 0.62))))
                case 1: g.fill(Path(roundedRect: r, cornerRadius: S * 0.03), with: .color(Art.c((0.58, 0.4, 0.22)))); g.fill(Path(ellipseIn: CGRect(x: r.maxX - S * 0.06, y: r.minY, width: S * 0.07, height: r.height)), with: .color(Art.c((0.88, 0.74, 0.5))))
                case 2: g.fill(Path(roundedRect: r, cornerRadius: S * 0.02), with: .color(Art.c((0.78, 0.77, 0.75))))
                case 3: g.fill(Path(roundedRect: r.insetBy(dx: S * 0.02, dy: S * 0.03), cornerRadius: S * 0.02), with: .color(Art.c((0.38, 0.36, 0.4))))
                case 4: g.fill(Path(roundedRect: r, cornerRadius: S * 0.03), with: .color(Art.c((0.74, 0.52, 0.3))))
                default: g.fill(Path(roundedRect: r.insetBy(dx: S * 0.03, dy: S * 0.04), cornerRadius: S * 0.02), with: .color(Art.c((0.3, 0.3, 0.34))))
                }
            }
            x += S * 0.4
            if x > strip.maxX - S * 0.3 { break }
        }
    }

    // MARK: People

    private func person(_ g: inout GraphicsContext, _ p: CityPerson, _ S: CGFloat) {
        let foot = CGPoint(x: CGFloat(p.x) * S, y: CGFloat(p.y) * S)
        let job = p.job.flatMap(world.building)?.kind
        let child = !p.adult
        var clothes: Art.RGB = (0.72, 0.6, 0.46), hat = Art.Hat.none, tool: Art.RGB = (0.6, 0.6, 0.62)
        if child { clothes = [(0.95, 0.72, 0.38), (0.55, 0.72, 0.9), (0.9, 0.55, 0.6)][p.id % 3] }
        else if p.retired { clothes = (0.58, 0.56, 0.58) }
        else {
            switch job {
            case .field?: clothes = (0.8, 0.66, 0.4); hat = .straw
            case .gatherer?: clothes = (0.36, 0.58, 0.34); hat = .hood
            case .forester?: clothes = (0.52, 0.3, 0.2); hat = .cap
            case .woodcutter?: clothes = (0.68, 0.24, 0.2); hat = .cap
            case .quarry?: clothes = (0.56, 0.56, 0.6); hat = .cap
            case .mine?: clothes = (0.3, 0.28, 0.3); hat = .helmet
            case .blacksmith?: clothes = (0.22, 0.22, 0.24); tool = (0.3, 0.3, 0.32)
            case .fishery?: clothes = (0.26, 0.44, 0.7); hat = .cap
            default: clothes = [(0.72, 0.6, 0.46), (0.6, 0.5, 0.62), (0.5, 0.6, 0.66)][p.id % 3]
            }
        }
        let item: Art.Item
        switch (p.amount > 0 ? p.carrying : nil) {
        case .logs?: item = .logs
        case .firewood?: item = .firewood
        case .stone?: item = .stone
        case .iron?: item = .iron
        case .food?: item = .food
        case .tools?: item = .tools
        case nil: item = .none
        }
        let walking = !p.path.isEmpty
        let working = !walking && p.swung < 0.5 && p.worker && item == .none
        Art.person(&g, foot: foot, height: S * (child ? 0.5 : 0.72), clothes: clothes, facing: p.facing, walking: walking,
                   phase: now * 10 + Double(p.id), seed: p.id, hat: hat, carry: item, swing: working ? p.swung : nil, tool: tool,
                   pale: p.health < 0.6 ? 0.55 + 0.45 * p.health / 0.6 : 1, child: child, grey: p.retired)
    }
}
