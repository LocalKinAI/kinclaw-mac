import SwiftUI

/// What the mouse is doing besides choosing and placing buildings.
enum IceTool: Equatable { case road, wall, bulldoze }

/// 冰河三国 at one moment, from above at three-quarters: snow over everything,
/// pines heavy with it, a frozen river and lake, and in the middle the great
/// furnace glowing orange with its warm circle on the snow. Grey-tiled roofs
/// with upturned eaves under thick snow, red pillars, lanterns, 蜀 banners;
/// warm houses lit and smoking, cold ones frosted and dark; people in fluffy
/// fur coats walking the paths, felling pines, digging coal, fishing through
/// the ice, carrying everything home. Snow falling; in the great blizzard it
/// is driven sideways and the whole city goes blue-white.
struct IceCityScene {
    let city: IceCity
    let selected: Int?
    let placing: IceBuildKind?
    let tool: IceTool?
    let hover: IceTile?
    let drag: (IceTile, IceTile)?
    let now: Double
    /// Drawn as a card's picture: houses warm and lived in, the greenhouse lit, the fishing hut smoking.
    var icon = false

    typealias RGB = Art.RGB
    static func c(_ v: RGB, _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }
    static let snow: RGB = (0.93, 0.955, 0.985), snowShade: RGB = (0.8, 0.86, 0.94), snowDeep: RGB = (0.72, 0.79, 0.9)
    static let tileGrey: RGB = (0.38, 0.42, 0.52), pillar: RGB = (0.76, 0.2, 0.15), plaster: RGB = (0.97, 0.92, 0.83)
    static let timber: RGB = (0.42, 0.28, 0.19), shu: RGB = (0.2, 0.56, 0.36), wei: RGB = (0.24, 0.42, 0.82), wu: RGB = (0.84, 0.28, 0.24)
    static let gold: RGB = (1, 0.8, 0.3), lanternRed: RGB = (0.92, 0.2, 0.14)
    static let coats: [RGB] = [(0.86, 0.3, 0.28), (0.28, 0.5, 0.82), (0.3, 0.62, 0.44), (0.94, 0.6, 0.22), (0.6, 0.4, 0.74), (0.62, 0.42, 0.3)]

    var storm: Bool { city.storm }
    /// How far into the blizzard's look: 0 calm, 1 full storm, easing in and out over half a day.
    var storminess: Double {
        let d = city.day
        let a = Double(city.blizzard.start) - 0.4, b = Double(city.blizzard.end) + 1
        if d < a || d > b + 0.4 { return 0 }
        return min(1, (d - a) / 0.4, (b + 0.4 - d) / 0.4)
    }

    // MARK: The whole picture

    /// Paint the part of the map in `view` (in tiles), `S` points to a tile, the map's corner at the context's origin.
    func paint(_ g: inout GraphicsContext, tile S: CGFloat, view: CGRect) {
        let W = IceCity.width, H = IceCity.height
        let near = view.insetBy(dx: -2, dy: -3)
        let x0 = max(0, Int(near.minX)), x1 = min(W - 1, Int(near.maxX)), y0 = max(0, Int(near.minY)), y1 = min(H - 1, Int(near.maxY))
        func seen(_ x: Int, _ y: Int, _ n: Int = 1) -> Bool { x + n >= x0 && x <= x1 && y + n >= y0 && y <= y1 + 1 }

        ground(&g, S, view, x0, x1, y0, y1)
        heat(&g, S)
        if tool == .wall { lee(&g, S, x0, x1, y0, y1) }

        // Flat things: plots under buildings.
        for b in city.buildings where seen(b.x, b.y, b.kind.size) { plot(&g, b, S) }

        // Standing things, row by row from the back: pines and rocks batched a row at a time, then walls, buildings and people.
        enum Thing { case building(IceBuilding), person(IcePerson), soldier(CGPoint, Int, Bool), general(Int, CGPoint), raider(CGPoint, Int, Int, Bool), marcher(CGPoint, Int, Bool) }
        var things: [(CGFloat, Thing)] = []
        for b in city.buildings where seen(b.x, b.y, b.kind.size) { things.append((CGFloat(b.y + b.kind.size) - 0.2, .building(b))) }
        for p in city.people where !p.inside && seen(Int(p.x), Int(p.y)) { things.append((CGFloat(p.y), .person(p))) }
        for (k, (p, spear)) in soldiers().enumerated() { things.append((p.y, .soldier(p, k, spear))) }
        for (h, p) in generals() { things.append((p.y, .general(h, p))) }
        for r in raiders() { things.append((r.at.y, .raider(r.at, r.side, r.seed, r.fleeing))) }
        for m in marchers() { things.append((m.at.y, .marcher(m.at, m.seed, m.facing > 0))) }
        things.sort { $0.0 < $1.0 }
        var next = 0
        for y in y0...y1 {
            pines(&g, S, row: y, x0, x1)
            rocks(&g, S, row: y, x0, x1)
            walls(&g, S, row: y, x0, x1)
            while next < things.count, things[next].0 < CGFloat(y + 1) {
                switch things[next].1 {
                case .building(let b): building(&g, b, S)
                case .person(let p): person(&g, p, S)
                case .soldier(let p, let k, let spear): soldier(&g, CGPoint(x: p.x * S, y: p.y * S), S, seed: k, team: Self.shu, spear: spear, walking: false, facing: k % 2 == 0 ? 1 : -1)
                case .general(let h, let p): general(&g, h, CGPoint(x: p.x * S, y: p.y * S), S)
                case .raider(let p, let side, let seed, let fleeing): soldier(&g, CGPoint(x: p.x * S, y: p.y * S), S, seed: seed, team: side == 0 ? Self.wei : Self.wu, spear: true, walking: true, facing: fleeing ? 1 : -1)
                case .marcher(let p, let seed, let east): soldier(&g, CGPoint(x: p.x * S, y: p.y * S), S, seed: seed, team: Self.shu, spear: true, walking: true, facing: east ? 1 : -1)
                }
                next += 1
            }
        }
        while next < things.count {
            if case .person(let p) = things[next].1 { person(&g, p, S) }
            next += 1
        }
        moments(&g, S)
        weather(&g, S, view)
        mouse(&g, S)
    }

    // MARK: The ground

    private func ground(_ g: inout GraphicsContext, _ S: CGFloat, _ view: CGRect, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) {
        let W = IceCity.width, H = IceCity.height
        // The land never changes in a game: painted once, then only placed.
        if let land = IceLand.image(city) {
            // Barely magnified, the nearest pixel is enough and much cheaper; closer in, smoothed.
            let magnified = S * g.environment.displayScale / IceLand.px
            g.draw(Image(decorative: land, scale: 1).interpolation(magnified <= 1.3 ? .none : .low), in: CGRect(x: 0, y: 0, width: CGFloat(W) * S, height: CGFloat(H) * S))
        } else {
            g.fill(Path(CGRect(x: 0, y: 0, width: CGFloat(W) * S, height: CGFloat(H) * S)), with: .color(Self.c(Self.snow)))
        }
        holes(&g, S)
    }

    /// Holes the fishers keep open in the ice.
    private func holes(_ g: inout GraphicsContext, _ S: CGFloat) {
        var holes = Path(), rims = Path()
        for p in city.people {
            guard case .harvest(let t) = p.task, city.ground[IceCity.index(t)] == .ice else { continue }
            let c = CGPoint(x: (CGFloat(t.x) + 0.5) * S, y: (CGFloat(t.y) + 0.55) * S)
            rims.addEllipse(in: CGRect(x: c.x - S * 0.22, y: c.y - S * 0.12, width: S * 0.44, height: S * 0.24))
            holes.addEllipse(in: CGRect(x: c.x - S * 0.16, y: c.y - S * 0.08, width: S * 0.32, height: S * 0.16))
        }
        g.fill(rims, with: .color(.white))
        g.fill(holes, with: .color(Self.c((0.12, 0.3, 0.46))))
    }

    /// The furnace's warmth on the snow: its glow and plaza are painted into the land; here only its dashed rim, turning.
    private func heat(_ g: inout GraphicsContext, _ S: CGFloat) {
        guard let f = city.furnace else { return }
        let c = city.centre(f)
        let centre = CGPoint(x: CGFloat(c.x) * S, y: CGFloat(c.y) * S)
        let R = CGFloat(city.heatRadius) * S
        let circle = Path(ellipseIn: CGRect(x: centre.x - R, y: centre.y - R, width: 2 * R, height: 2 * R))
        if city.burning {
            g.stroke(circle, with: .color(Color(red: 1, green: 0.62, blue: 0.28).opacity(0.55)), style: StrokeStyle(lineWidth: max(1, S * 0.06), dash: [S * 0.35, S * 0.25], dashPhase: CGFloat(now * 6)))
        } else {
            g.stroke(circle, with: .color(Color(red: 0.4, green: 0.55, blue: 0.8).opacity(0.5)), style: StrokeStyle(lineWidth: max(1, S * 0.05), dash: [S * 0.2, S * 0.3]))
        }
    }

    /// The lee of the walls: out of the north wind, shown while walls are being laid.
    private func lee(_ g: inout GraphicsContext, _ S: CGFloat, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) {
        var p = Path()
        for y in y0...y1 { for x in x0...x1 where city.lee[y * IceCity.width + x] { p.addRect(CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: S, height: S)) } }
        g.fill(p, with: .color(Color(red: 0.4, green: 0.7, blue: 1).opacity(0.14)))
    }

    private func plot(_ g: inout GraphicsContext, _ b: IceBuilding, _ S: CGFloat) {
        let n = CGFloat(b.kind.size)
        let r = CGRect(x: CGFloat(b.x) * S, y: CGFloat(b.y) * S, width: n * S, height: n * S)
        switch b.kind {
        case .furnace: return
        case .fishery: g.fill(Path(ellipseIn: r.insetBy(dx: S * 0.05, dy: S * 0.2).offsetBy(dx: 0, dy: S * 0.2)), with: .color(Self.c((0.9, 0.95, 1), 0.8)))
        case .coalMine, .ironMine, .quarry: g.fill(Path(ellipseIn: r.insetBy(dx: -S * 0.1, dy: S * 0.05)), with: .color(Self.c((0.74, 0.74, 0.78), 0.45)))
        default: g.fill(Path(ellipseIn: CGRect(x: r.minX - S * 0.1, y: r.maxY - S * 0.75, width: r.width + S * 0.3, height: S * 0.9)), with: .color(Self.c(Self.snowShade, 0.45)))
        }
    }

    // MARK: Pines, rocks and walls — a row at a time, in a few shapes each

    private func pines(_ g: inout GraphicsContext, _ S: CGFloat, row y: Int, _ x0: Int, _ x1: Int) {
        let W = IceCity.width
        var shadow = Path(), trunks = Path(), stumps = Path(), stumpTops = Path(), snow = Path()
        var left = [Path](repeating: Path(), count: 2), right = [Path](repeating: Path(), count: 2)
        var any = false
        for x in x0...x1 {
            let i = y * W + x
            guard city.ground[i] == .forest else { continue }
            any = true
            let h = Art.hash(x, y), grown = city.wood[i]
            let foot = CGPoint(x: (CGFloat(x) + 0.5 + CGFloat(h % 9 - 4) * 0.04) * S, y: (CGFloat(y) + 0.84) * S)
            if grown < 0.15 {
                let r = S * 0.15
                stumps.addRoundedRect(in: CGRect(x: foot.x - r, y: foot.y - r * 1.2, width: 2 * r, height: r * 1.3), cornerSize: CGSize(width: r * 0.3, height: r * 0.3))
                stumpTops.addEllipse(in: CGRect(x: foot.x - r * 1.1, y: foot.y - r * 1.65, width: r * 2.2, height: r * 0.9))
                continue
            }
            let size = CGFloat(0.45 + 0.55 * min(1, grown)) * CGFloat(0.9 + Double(h % 7) * 0.035) * S
            let v = h % 2
            if S < 30 {
                // Far out: one cone and its snow cap.
                let w = size * 0.46, top = foot.y - size * 1.25, bottom = foot.y - size * 0.1
                left[v].move(to: CGPoint(x: foot.x, y: top)); left[v].addLine(to: CGPoint(x: foot.x, y: bottom)); left[v].addLine(to: CGPoint(x: foot.x - w, y: bottom)); left[v].closeSubpath()
                right[v].move(to: CGPoint(x: foot.x, y: top)); right[v].addLine(to: CGPoint(x: foot.x + w, y: bottom)); right[v].addLine(to: CGPoint(x: foot.x, y: bottom)); right[v].closeSubpath()
                snow.move(to: CGPoint(x: foot.x, y: top - size * 0.03)); snow.addLine(to: CGPoint(x: foot.x + w * 0.62, y: top + size * 0.6)); snow.addLine(to: CGPoint(x: foot.x - w * 0.62, y: top + size * 0.6)); snow.closeSubpath()
                continue
            }
            shadow.addEllipse(in: CGRect(x: foot.x - size * 0.3, y: foot.y - size * 0.12, width: size * 1.15, height: size * 0.34))
            trunks.addRect(CGRect(x: foot.x - size * 0.06, y: foot.y - size * 0.26, width: size * 0.12, height: size * 0.28))
            for k in 0..<3 {
                let t = CGFloat(k)
                let w = size * (0.5 - t * 0.12), bottom = foot.y - size * (0.2 + t * 0.34), top = bottom - size * 0.56
                left[v].move(to: CGPoint(x: foot.x, y: top)); left[v].addLine(to: CGPoint(x: foot.x, y: bottom + size * 0.05)); left[v].addLine(to: CGPoint(x: foot.x - w, y: bottom)); left[v].closeSubpath()
                right[v].move(to: CGPoint(x: foot.x, y: top)); right[v].addLine(to: CGPoint(x: foot.x + w, y: bottom)); right[v].addLine(to: CGPoint(x: foot.x, y: bottom + size * 0.05)); right[v].closeSubpath()
                // Snow on each tier: a cap with a zigzag hem.
                let hem = top + (bottom - top) * 0.7
                snow.move(to: CGPoint(x: foot.x, y: top - size * 0.03))
                snow.addLine(to: CGPoint(x: foot.x + w * 0.74, y: hem))
                snow.addLine(to: CGPoint(x: foot.x + w * 0.46, y: hem + size * 0.06))
                snow.addLine(to: CGPoint(x: foot.x + w * 0.2, y: hem))
                snow.addLine(to: CGPoint(x: foot.x - w * 0.05, y: hem + size * 0.07))
                snow.addLine(to: CGPoint(x: foot.x - w * 0.3, y: hem + size * 0.01))
                snow.addLine(to: CGPoint(x: foot.x - w * 0.56, y: hem + size * 0.06))
                snow.addLine(to: CGPoint(x: foot.x - w * 0.78, y: hem))
                snow.closeSubpath()
            }
        }
        guard any else { return }
        g.fill(shadow, with: .color(Color(red: 0.3, green: 0.4, blue: 0.6).opacity(0.18)))
        g.fill(trunks, with: .color(Self.c((0.4, 0.28, 0.2))))
        let greens: [RGB] = [(0.14, 0.4, 0.34), (0.18, 0.44, 0.3)]
        for v in 0..<2 {
            g.fill(left[v], with: .color(Self.c(Art.lit(greens[v], 1.22))))
            g.fill(right[v], with: .color(Self.c(Art.lit(greens[v], 0.82))))
        }
        g.fill(snow, with: .color(.white))
        g.fill(stumps, with: .color(Self.c((0.5, 0.36, 0.24))))
        g.fill(stumpTops, with: .color(.white))
    }

    private func rocks(_ g: inout GraphicsContext, _ S: CGFloat, row y: Int, _ x0: Int, _ x1: Int) {
        let W = IceCity.width
        let winter = Art.Season(month: 10.5)
        var lumps = Path(), shine = Path(), caps = Path()
        for x in x0...x1 {
            let kind = city.ground[y * W + x]
            switch kind {
            case .rock, .ore:
                Art.deposit(&g, kind == .ore ? .ore : .stone, centre: CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.62) * S), S: S, left: 1, variant: Art.hash(x, y), season: winter)
            case .coal:
                // Coal: black lumps with a blue sheen and snow on top.
                let c = CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.62) * S)
                let h = Art.hash(x, y)
                for (k, (dx, dy, rr)) in [(-0.24, 0.04, 0.24), (0.22, 0.08, 0.22), (0.0, -0.12, 0.3)].enumerated() {
                    let r = S * CGFloat(rr) * CGFloat(0.9 + Double((h >> k) % 4) * 0.06)
                    let p = CGPoint(x: c.x + CGFloat(dx) * S, y: c.y + CGFloat(dy) * S)
                    // A faceted lump: a few corners, not a box.
                    let tilt = CGFloat((h >> (k + 2)) % 5) * 0.08 - 0.16
                    lumps.move(to: CGPoint(x: p.x - r, y: p.y + r * 0.5))
                    lumps.addLine(to: CGPoint(x: p.x - r * 0.8, y: p.y - r * (0.5 + tilt)))
                    lumps.addLine(to: CGPoint(x: p.x - r * 0.1, y: p.y - r * 0.85))
                    lumps.addLine(to: CGPoint(x: p.x + r * 0.75, y: p.y - r * (0.45 - tilt)))
                    lumps.addLine(to: CGPoint(x: p.x + r, y: p.y + r * 0.5))
                    lumps.closeSubpath()
                    shine.move(to: CGPoint(x: p.x - r * 0.7, y: p.y - r * 0.3)); shine.addLine(to: CGPoint(x: p.x - r * 0.15, y: p.y - r * 0.62)); shine.addLine(to: CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.1)); shine.closeSubpath()
                    caps.move(to: CGPoint(x: p.x - r * 0.75, y: p.y - r * (0.42 + tilt)))
                    caps.addLine(to: CGPoint(x: p.x - r * 0.1, y: p.y - r * 0.92))
                    caps.addLine(to: CGPoint(x: p.x + r * 0.7, y: p.y - r * (0.4 - tilt)))
                    caps.addQuadCurve(to: CGPoint(x: p.x - r * 0.75, y: p.y - r * (0.42 + tilt)), control: CGPoint(x: p.x, y: p.y - r * 0.3))
                }
            default: break
            }
        }
        if !lumps.isEmpty {
            g.fill(lumps, with: .color(Self.c((0.14, 0.14, 0.17))))
            g.fill(shine, with: .color(Self.c((0.45, 0.52, 0.66), 0.8)))
            g.fill(caps, with: .color(.white.opacity(0.95)))
        }
    }

    /// Walls: grey brick with crenellations and snow along the top; a gate where a road runs through. Each tile rises as it is laid.
    private func walls(_ g: inout GraphicsContext, _ S: CGFloat, row y: Int, _ x0: Int, _ x1: Int) {
        let W = IceCity.width, H = IceCity.height
        func isWall(_ x: Int, _ yy: Int) -> Bool { x >= 0 && yy >= 0 && x < W && yy < H && city.wall[yy * W + x] >= 0 }
        var faces = Path(), tops = Path(), snowTops = Path(), bricks = Path(), merlons = Path(), gates = Path(), shadows = Path()
        var any = false
        for x in x0...x1 where isWall(x, y) {
            let built = city.wall[y * W + x]
            let rise = CGFloat(max(0, min(1, (city.time - built) / 0.6)))
            guard rise > 0 else { continue }
            any = true
            let h = S * 0.95 * rise
            let l = CGFloat(x) * S - (isWall(x - 1, y) ? 0.5 : 0), r = CGFloat(x + 1) * S + (isWall(x + 1, y) ? 0.5 : 0)
            let base = CGFloat(y) * S + S * 0.78
            let top = CGRect(x: l, y: base - h - S * 0.5, width: r - l, height: S * 0.5)
            shadows.addRect(CGRect(x: l + S * 0.2, y: base - S * 0.05, width: r - l, height: S * 0.3))
            if !isWall(x, y + 1) {
                let face = CGRect(x: l, y: base - h, width: r - l, height: h)
                faces.addRect(face)
                if S > 12 {
                    for k in 1..<3 { bricks.move(to: CGPoint(x: l, y: face.minY + face.height * CGFloat(k) / 3)); bricks.addLine(to: CGPoint(x: r, y: face.minY + face.height * CGFloat(k) / 3)) }
                    for k in 0..<3 {
                        let bx = CGFloat(x) * S + S * (k % 2 == 0 ? 0.3 : 0.65)
                        bricks.move(to: CGPoint(x: bx, y: face.minY + face.height * CGFloat(k) / 3)); bricks.addLine(to: CGPoint(x: bx, y: face.minY + face.height * CGFloat(k + 1) / 3))
                    }
                }
                if city.road[y * W + x] {
                    let arch = CGRect(x: CGFloat(x) * S + S * 0.2, y: base - h * 0.78, width: S * 0.6, height: h * 0.78)
                    gates.addRoundedRect(in: arch, cornerSize: CGSize(width: S * 0.28, height: S * 0.28))
                }
            }
            tops.addRect(top)
            if S > 10 {
                for k in 0..<2 { merlons.addRect(CGRect(x: CGFloat(x) * S + S * (0.1 + CGFloat(k) * 0.5), y: top.maxY - S * 0.18, width: S * 0.3, height: S * 0.2)) }
            }
            snowTops.addRoundedRect(in: CGRect(x: l, y: top.minY - S * 0.04, width: r - l, height: S * 0.34), cornerSize: CGSize(width: S * 0.12, height: S * 0.12))
        }
        guard any else { return }
        g.fill(shadows, with: .color(Color(red: 0.3, green: 0.4, blue: 0.6).opacity(0.2)))
        g.fill(faces, with: .linearGradient(Gradient(colors: [Self.c((0.64, 0.66, 0.72)), Self.c((0.5, 0.52, 0.58))]), startPoint: CGPoint(x: 0, y: CGFloat(y) * S), endPoint: CGPoint(x: 0, y: CGFloat(y + 1) * S)))
        g.stroke(bricks, with: .color(Self.c((0.4, 0.42, 0.48), 0.6)), lineWidth: max(0.5, S * 0.02))
        g.fill(gates, with: .color(Self.c((0.18, 0.16, 0.2))))
        g.fill(tops, with: .color(Self.c((0.72, 0.74, 0.8))))
        g.fill(merlons, with: .color(Self.c((0.6, 0.62, 0.68))))
        g.fill(snowTops, with: .color(.white))
    }

    // MARK: Pictures for the cards

    /// The land the cards' pictures are drawn against (never shown).
    static let iconCity = IceCity(seed: 11)

    /// A building — or a tool — drawn by the scene's own hand at the size of a card.
    static func icon(_ g: inout GraphicsContext, kind: IceBuildKind?, tool: IceTool?, size: CGSize) {
        let scene = IceCityScene(city: iconCity, selected: nil, placing: nil, tool: nil, hover: nil, drag: nil, now: 0, icon: true)
        if let kind {
            let n = CGFloat(kind.size)
            let S = min(size.width / (n + 0.35), size.height / (n + 0.5))
            var c = g
            c.translateBy(x: (size.width - n * S) / 2 - S * 0.08, y: size.height - n * S - S * 0.02)
            var b = IceBuilding(id: 0, kind: kind, x: 0, y: 0, done: true)
            b.reserve = 100
            scene.building(&c, b, S)
            return
        }
        let s = min(size.width, size.height)
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        switch tool {
        case .road?:
            let way = Path { p in p.move(to: CGPoint(x: mid.x - s * 0.62, y: mid.y + s * 0.3)); p.addQuadCurve(to: CGPoint(x: mid.x + s * 0.62, y: mid.y - s * 0.22), control: CGPoint(x: mid.x - s * 0.05, y: mid.y - s * 0.28)) }
            g.stroke(way, with: .color(Self.c((0.86, 0.9, 0.96))), style: StrokeStyle(lineWidth: s * 0.5, lineCap: .round))
            g.stroke(way, with: .color(Self.c((0.78, 0.74, 0.7))), style: StrokeStyle(lineWidth: s * 0.34, lineCap: .round))
            g.stroke(way, with: .color(Self.c((0.88, 0.86, 0.84))), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round, dash: [s * 0.12, s * 0.1]))
        case .wall?:
            let w = s * 1.3, h = s * 0.42
            let face = CGRect(x: mid.x - w / 2, y: mid.y - h * 0.1, width: w, height: h)
            let top = CGRect(x: face.minX, y: face.minY - s * 0.2, width: w, height: s * 0.22)
            g.fill(Path(face), with: .linearGradient(Gradient(colors: [Self.c((0.66, 0.68, 0.74)), Self.c((0.5, 0.52, 0.58))]), startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.maxY)))
            var bricks = Path()
            for r in 1..<3 { bricks.move(to: CGPoint(x: face.minX, y: face.minY + face.height * CGFloat(r) / 3)); bricks.addLine(to: CGPoint(x: face.maxX, y: face.minY + face.height * CGFloat(r) / 3)) }
            for r in 0..<3 { var x = face.minX + (r % 2 == 0 ? s * 0.12 : s * 0.24); while x < face.maxX { bricks.move(to: CGPoint(x: x, y: face.minY + face.height * CGFloat(r) / 3)); bricks.addLine(to: CGPoint(x: x, y: face.minY + face.height * CGFloat(r + 1) / 3)); x += s * 0.24 } }
            g.stroke(bricks, with: .color(Self.c((0.4, 0.42, 0.48), 0.6)), lineWidth: max(0.5, s * 0.02))
            g.fill(Path(top), with: .color(Self.c((0.74, 0.76, 0.82))))
            var merlons = Path()
            var x = top.minX
            while x < top.maxX - s * 0.05 { merlons.addRect(CGRect(x: x, y: top.maxY - s * 0.14, width: s * 0.14, height: s * 0.14)); x += s * 0.26 }
            g.fill(merlons, with: .color(Self.c((0.6, 0.62, 0.68))))
            g.fill(Path(roundedRect: CGRect(x: top.minX, y: top.minY - s * 0.04, width: top.width, height: s * 0.14), cornerRadius: s * 0.06), with: .color(.white))
        case .bulldoze?:
            // Rubble, and a red cross over it.
            var rubble = Path()
            for (dx, dy, r) in [(-0.3, 0.22, 0.14), (-0.08, 0.26, 0.12), (0.16, 0.22, 0.15), (0.34, 0.27, 0.1), (0.02, 0.12, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
                rubble.addRoundedRect(in: CGRect(x: mid.x + dx * s - r * s, y: mid.y + dy * s - r * s * 0.7, width: 2 * r * s, height: 1.4 * r * s), cornerSize: CGSize(width: r * s * 0.3, height: r * s * 0.3))
            }
            g.fill(rubble, with: .color(Self.c((0.62, 0.58, 0.56))))
            g.fill(Path(ellipseIn: CGRect(x: mid.x - s * 0.3, y: mid.y - s * 0.42, width: s * 0.6, height: s * 0.6)), with: .color(Self.c((0.88, 0.26, 0.22))))
            g.stroke(Path { p in p.move(to: CGPoint(x: mid.x - s * 0.13, y: mid.y - s * 0.25)); p.addLine(to: CGPoint(x: mid.x + s * 0.13, y: mid.y + s * 0.01)); p.move(to: CGPoint(x: mid.x + s * 0.13, y: mid.y - s * 0.25)); p.addLine(to: CGPoint(x: mid.x - s * 0.13, y: mid.y + s * 0.01)) },
                     with: .color(.white), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
        default: break
        }
    }

    // MARK: Buildings

    /// A building's footprint turned into a front wall standing on its lower edge.
    private struct Frame {
        let F: CGRect, wall: CGRect
        init(_ F: CGRect, S: CGFloat, height: CGFloat, inset: CGFloat = 0.16) {
            self.F = F
            let bottom = F.maxY - S * 0.12
            wall = CGRect(x: F.minX + S * inset, y: bottom - S * height, width: F.width - 2 * S * inset, height: S * height)
        }
    }

    private func building(_ g: inout GraphicsContext, _ b: IceBuilding, _ S: CGFloat) {
        let n = CGFloat(b.kind.size)
        let F = CGRect(x: CGFloat(b.x) * S, y: CGFloat(b.y) * S, width: n * S, height: n * S)
        var draw = g
        if !b.done { draw.opacity = 0.3 + 0.6 * b.progress }
        switch b.kind {
        case .furnace: furnace(&g, b, F, S)
        case .house: house(&draw, b, F, S)
        case .storage: storage(&draw, b, F, S)
        case .lumber: lumber(&draw, b, F, S)
        case .coalMine, .ironMine: mine(&draw, b, F, S)
        case .quarry: quarry(&draw, b, F, S)
        case .hunter: hunter(&draw, b, F, S)
        case .fishery: fishery(&draw, b, F, S)
        case .greenhouse: greenhouse(&draw, b, F, S)
        case .clinic: clinic(&draw, b, F, S)
        case .barracks: barracks(&draw, b, F, S)
        case .tavern: tavern(&draw, b, F, S)
        }
        if !b.done {
            let cost = b.kind.cost, need = cost[1] + cost[3] + cost[4]
            let brought = need > 0 ? (b.delivered[1] + b.delivered[3] + b.delivered[4]) / need : 1
            Art.scaffold(&g, CGRect(x: F.minX + S * 0.2, y: F.minY - S * 0.2, width: F.width - S * 0.4, height: F.height - S * 0.1), S: S, progress: b.progress, brought: brought)
            if b.delivered[1] > 0 { logPile(&g, CGPoint(x: F.minX + S * 0.35, y: F.maxY - S * 0.05), S) }
            if b.delivered[3] > 0 {
                var blocks = Path()
                for k in 0..<min(3, Int(b.delivered[3] / 5) + 1) { blocks.addRoundedRect(in: CGRect(x: F.maxX - S * (0.45 + CGFloat(k) * 0.24), y: F.maxY - S * 0.3, width: S * 0.22, height: S * 0.16), cornerSize: CGSize(width: S * 0.03, height: S * 0.03)) }
                g.fill(blocks, with: .color(Self.c((0.74, 0.74, 0.76))))
            }
        }
    }

    /// A roof in the Three Kingdoms way over a front wall: grey tiles in rows, the eave's corners turned up, a ridge with curled ends, and snow on it all.
    private func roof(_ g: inout GraphicsContext, over wall: CGRect, rise: CGFloat, S: CGFloat, colour: RGB = IceCityScene.tileGrey, snow: Double = 1, overhang: CGFloat = 0.22) {
        let ov = S * overhang
        let eaveY = wall.minY + S * 0.05
        let l = wall.minX - ov, r = wall.maxX + ov
        let lift = S * 0.2
        let ridgeY = eaveY - rise
        let inset = min(wall.width * 0.22, S * 0.45)
        // The slope from the eave up to the ridge.
        let body = Path { p in
            p.move(to: CGPoint(x: l - S * 0.05, y: eaveY - lift))
            p.addQuadCurve(to: CGPoint(x: l + ov * 1.6, y: eaveY + S * 0.02), control: CGPoint(x: l + ov * 0.4, y: eaveY + S * 0.02))
            p.addLine(to: CGPoint(x: r - ov * 1.6, y: eaveY + S * 0.02))
            p.addQuadCurve(to: CGPoint(x: r + S * 0.05, y: eaveY - lift), control: CGPoint(x: r - ov * 0.4, y: eaveY + S * 0.02))
            p.addLine(to: CGPoint(x: wall.maxX - inset, y: ridgeY))
            p.addLine(to: CGPoint(x: wall.minX + inset, y: ridgeY))
            p.closeSubpath()
        }
        g.fill(body, with: .color(Self.c(Art.lit(colour, 0.92))))
        if S > 12 {
            var rows = Path()
            let count = max(4, Int((r - l) / (S * 0.16)))
            for k in 2..<(count - 1) {
                let t = CGFloat(k) / CGFloat(count)
                let bx = l + (r - l) * t
                let tx = wall.minX + inset + (wall.width - 2 * inset) * t
                rows.move(to: CGPoint(x: bx, y: eaveY)); rows.addLine(to: CGPoint(x: tx, y: ridgeY))
            }
            g.stroke(rows, with: .color(Self.c(Art.lit(colour, 0.66), 0.55)), lineWidth: max(0.5, S * 0.03))
        }
        // Snow: a thick cap on the upper slope with a soft wavy hem, a line along the eave.
        if snow > 0 {
            let hem = ridgeY + rise * 0.62
            let cap = Path { p in
                p.move(to: CGPoint(x: wall.minX + inset - S * 0.06, y: ridgeY - S * 0.06))
                p.addLine(to: CGPoint(x: wall.maxX - inset + S * 0.06, y: ridgeY - S * 0.06))
                p.addLine(to: CGPoint(x: r - S * 0.02, y: hem - lift * 0.3))
                let steps = max(3, Int((r - l) / (S * 0.45)))
                for k in 0..<steps {
                    let x1 = r - (r - l) * CGFloat(k + 1) / CGFloat(steps), x0 = r - (r - l) * CGFloat(k) / CGFloat(steps)
                    p.addQuadCurve(to: CGPoint(x: x1, y: hem - (k == steps - 1 ? lift * 0.3 : 0)), control: CGPoint(x: (x0 + x1) / 2, y: hem + S * 0.13))
                }
                p.closeSubpath()
            }
            g.fill(cap, with: .color(.white.opacity(snow)))
            g.fill(Path(roundedRect: CGRect(x: l + ov * 1.2, y: eaveY - S * 0.06, width: r - l - ov * 2.4, height: S * 0.08), cornerRadius: S * 0.04), with: .color(.white.opacity(0.9 * snow)))
        }
        // The eave's edge, and the ridge with its curled ends.
        g.stroke(Path { p in
            p.move(to: CGPoint(x: l - S * 0.05, y: eaveY - lift))
            p.addQuadCurve(to: CGPoint(x: l + ov * 1.6, y: eaveY + S * 0.02), control: CGPoint(x: l + ov * 0.4, y: eaveY + S * 0.02))
            p.addLine(to: CGPoint(x: r - ov * 1.6, y: eaveY + S * 0.02))
            p.addQuadCurve(to: CGPoint(x: r + S * 0.05, y: eaveY - lift), control: CGPoint(x: r - ov * 0.4, y: eaveY + S * 0.02))
        }, with: .color(Self.c(Art.lit(colour, 0.5))), style: StrokeStyle(lineWidth: max(1, S * 0.07), lineCap: .round))
        let ridgeL = wall.minX + inset - S * 0.1, ridgeR = wall.maxX - inset + S * 0.1
        let band = CGRect(x: ridgeL, y: ridgeY - S * 0.1, width: ridgeR - ridgeL, height: S * 0.13)
        g.fill(Path(roundedRect: band, cornerRadius: S * 0.04), with: .color(Self.c(Art.lit(colour, 0.55))))
        var hooks = Path()
        for (x, s1) in [(ridgeL, -1.0), (ridgeR, 1.0)] as [(CGFloat, CGFloat)] {
            hooks.move(to: CGPoint(x: x - s1 * S * 0.02, y: ridgeY + S * 0.02))
            hooks.addQuadCurve(to: CGPoint(x: x + s1 * S * 0.12, y: ridgeY - S * 0.26), control: CGPoint(x: x + s1 * S * 0.16, y: ridgeY - S * 0.02))
            hooks.addLine(to: CGPoint(x: x + s1 * S * 0.02, y: ridgeY - S * 0.12))
            hooks.closeSubpath()
        }
        g.fill(hooks, with: .color(Self.c(Art.lit(colour, 0.5))))
        if snow > 0 { g.fill(Path(roundedRect: CGRect(x: ridgeL + S * 0.06, y: ridgeY - S * 0.16, width: ridgeR - ridgeL - S * 0.12, height: S * 0.1), cornerRadius: S * 0.05), with: .color(.white.opacity(snow))) }
    }

    /// A wall of cream plaster between red pillars, on a grey stone footing, a dark beam under the eave.
    private func pillared(_ g: inout GraphicsContext, _ wall: CGRect, S: CGFloat, pillars: Int, plaster: RGB = IceCityScene.plaster, pillar: RGB = IceCityScene.pillar, cold: Bool = false) {
        let face: RGB = cold ? Art.mix(plaster, (0.78, 0.84, 0.94), 0.55) : plaster
        g.fill(Path(wall), with: .color(Self.c(face)))
        g.fill(Path(CGRect(x: wall.maxX - wall.width * 0.22, y: wall.minY, width: wall.width * 0.22, height: wall.height)), with: .color(Self.c(Art.lit(face, 0.9))))
        g.fill(Path(CGRect(x: wall.minX - S * 0.03, y: wall.maxY - S * 0.1, width: wall.width + S * 0.06, height: S * 0.12)), with: .color(Self.c((0.62, 0.62, 0.66))))
        var posts = Path()
        let pw = max(1.5, S * 0.09)
        for k in 0..<pillars {
            let x = pillars == 1 ? wall.midX : wall.minX + (wall.width - pw) * CGFloat(k) / CGFloat(pillars - 1)
            posts.addRect(CGRect(x: x - (pillars == 1 ? pw / 2 : 0), y: wall.minY, width: pw, height: wall.height - S * 0.08))
        }
        g.fill(posts, with: .color(Self.c(cold ? Art.mix(pillar, (0.6, 0.6, 0.7), 0.4) : pillar)))
        g.fill(Path(CGRect(x: wall.minX, y: wall.minY, width: wall.width, height: max(1.5, S * 0.07))), with: .color(Self.c(Self.timber)))
    }

    private func window(_ g: inout GraphicsContext, _ r: CGRect, S: CGFloat, lit: Bool, frosted: Bool = false) {
        g.fill(Path(r.insetBy(dx: -S * 0.025, dy: -S * 0.025)), with: .color(Self.c(Self.timber)))
        if lit {
            let flicker = 0.9 + 0.1 * sin(now * 3.1 + Double(r.minX))
            g.fill(Path(ellipseIn: r.insetBy(dx: -r.width * 0.9, dy: -r.height * 0.9)), with: .color(Color(red: 1, green: 0.78, blue: 0.4).opacity(0.22 * flicker)))
            g.fill(Path(r), with: .color(Color(red: 1, green: 0.8 * flicker + 0.04, blue: 0.42)))
        } else {
            g.fill(Path(r), with: .color(Self.c((0.3, 0.38, 0.52))))
        }
        if S > 14 {
            var lattice = Path()
            lattice.move(to: CGPoint(x: r.midX, y: r.minY)); lattice.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            lattice.move(to: CGPoint(x: r.minX, y: r.midY)); lattice.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            g.stroke(lattice, with: .color(Self.c(Self.timber)), lineWidth: max(0.5, S * 0.02))
        }
        if frosted { g.fill(Path(r), with: .color(.white.opacity(0.45))) }
    }

    private func lantern(_ g: inout GraphicsContext, _ at: CGPoint, S: CGFloat, lit: Bool = true) {
        let sway = CGFloat(sin(now * 2 + Double(at.x))) * S * 0.02
        let r = CGRect(x: at.x - S * 0.09 + sway, y: at.y, width: S * 0.18, height: S * 0.22)
        g.stroke(Path { p in p.move(to: CGPoint(x: at.x, y: at.y - S * 0.06)); p.addLine(to: CGPoint(x: r.midX, y: r.minY)) }, with: .color(Self.c(Self.timber)), lineWidth: max(0.5, S * 0.015))
        if lit { g.fill(Path(ellipseIn: r.insetBy(dx: -S * 0.14, dy: -S * 0.14)), with: .color(Color(red: 1, green: 0.5, blue: 0.3).opacity(0.25))) }
        g.fill(Path(ellipseIn: r), with: .color(Self.c(lit ? Self.lanternRed : (0.5, 0.26, 0.28))))
        g.fill(Path(CGRect(x: r.minX + S * 0.03, y: r.minY - S * 0.015, width: r.width - S * 0.06, height: S * 0.035)), with: .color(Self.c(Self.gold)))
        g.fill(Path(CGRect(x: r.minX + S * 0.03, y: r.maxY - S * 0.02, width: r.width - S * 0.06, height: S * 0.035)), with: .color(Self.c(Self.gold)))
    }

    /// A tall banner on a pole with a character on it, waving.
    private func flag(_ g: inout GraphicsContext, _ foot: CGPoint, S: CGFloat, colour: RGB, text: String, height: CGFloat = 1.3) {
        let top = CGPoint(x: foot.x, y: foot.y - S * height)
        g.stroke(Path { p in p.move(to: foot); p.addLine(to: top) }, with: .color(Self.c((0.36, 0.26, 0.18))), lineWidth: max(1, S * 0.05))
        g.fill(Path(ellipseIn: CGRect(x: top.x - S * 0.05, y: top.y - S * 0.07, width: S * 0.1, height: S * 0.1)), with: .color(Self.c(Self.gold)))
        let wave = CGFloat(sin(now * 3.2 + Double(foot.x) * 0.1)) * S * 0.05
        let w = S * 0.36, h = S * 0.5
        let cloth = Path { p in
            p.move(to: CGPoint(x: top.x, y: top.y + S * 0.04))
            p.addQuadCurve(to: CGPoint(x: top.x + w, y: top.y + S * 0.04 + wave), control: CGPoint(x: top.x + w / 2, y: top.y + S * 0.04 - wave))
            p.addLine(to: CGPoint(x: top.x + w + wave * 0.5, y: top.y + h))
            p.addLine(to: CGPoint(x: top.x + w * 0.5, y: top.y + h - S * 0.08))
            p.addLine(to: CGPoint(x: top.x, y: top.y + h))
            p.closeSubpath()
        }
        g.fill(cloth, with: .color(Self.c(colour)))
        g.stroke(cloth, with: .color(Self.c(Self.gold, 0.9)), lineWidth: max(0.5, S * 0.02))
        if S > 12 {
            g.draw(Text(text).font(.system(size: S * 0.26, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: top.x + w * 0.5, y: top.y + h * 0.48 + wave * 0.5))
        }
    }

    private func chimney(_ g: inout GraphicsContext, at p: CGPoint, S: CGFloat, smoking: Bool, seed: Int) {
        let r = CGRect(x: p.x - S * 0.09, y: p.y - S * 0.26, width: S * 0.18, height: S * 0.3)
        g.fill(Path(r), with: .color(Self.c((0.56, 0.5, 0.5))))
        g.fill(Path(roundedRect: CGRect(x: r.minX - S * 0.03, y: r.minY - S * 0.05, width: r.width + S * 0.06, height: S * 0.08), cornerRadius: S * 0.03), with: .color(.white))
        guard smoking else { return }
        var puffs = Path()
        let wind = storm ? 2.6 : 1
        for k in 0..<4 {
            let t = (now * 0.32 + Double(k) * 0.25 + Double(seed % 10) / 10).truncatingRemainder(dividingBy: 1)
            let q = CGPoint(x: r.midX + CGFloat(t * t * wind) * S * 0.9 + CGFloat(sin(now * 1.3 + Double(k))) * S * 0.04, y: r.minY - CGFloat(t) * S * 1.1)
            let rr = S * CGFloat(0.07 + t * 0.17)
            puffs.addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr))
        }
        g.fill(puffs, with: .color(Color(white: 0.94).opacity(0.55)))
    }

    private func icicles(_ g: inout GraphicsContext, from l: CGFloat, to r: CGFloat, y: CGFloat, S: CGFloat, long: CGFloat, seed: Int) {
        var p = Path()
        var x = l, k = 0
        while x < r {
            let len = long * CGFloat(0.5 + Double(Art.hash(k, seed) % 10) / 20)
            p.move(to: CGPoint(x: x - S * 0.025, y: y)); p.addLine(to: CGPoint(x: x, y: y + len)); p.addLine(to: CGPoint(x: x + S * 0.025, y: y))
            x += S * 0.13; k += 1
        }
        g.fill(p, with: .color(Color(red: 0.86, green: 0.95, blue: 1).opacity(0.95)))
    }

    /// Is this house lived in and warm right now?
    private func warmHouse(_ b: IceBuilding) -> (lived: Bool, warm: Bool) {
        if icon { return (true, true) }
        let lived = city.people.contains { $0.home == b.id }
        return (lived, lived && b.done && city.burning && city.warmed(b))
    }

    private func house(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let (lived, warm) = warmHouse(b)
        let cold = b.done && lived && !warm
        let fr = Frame(F, S: S, height: 0.8, inset: 0.14)
        softShadow(&g, F, S, strength: 0.14 + 0.06)
        pillared(&g, fr.wall, S: S, pillars: 2, plaster: [(0.97, 0.92, 0.83), (0.96, 0.88, 0.78), (0.98, 0.94, 0.86)][b.id % 3], cold: cold || !lived)
        // A door with red couplets, windows either side.
        let door = CGRect(x: fr.wall.midX - S * 0.16, y: fr.wall.maxY - S * 0.5, width: S * 0.32, height: S * 0.42)
        g.fill(Path(roundedRect: door, cornerRadius: S * 0.03), with: .color(Self.c(warm ? (0.55, 0.3, 0.18) : (0.42, 0.36, 0.38))))
        g.stroke(Path { p in p.move(to: CGPoint(x: door.midX, y: door.minY)); p.addLine(to: CGPoint(x: door.midX, y: door.maxY)) }, with: .color(Self.c((0.3, 0.18, 0.12))), lineWidth: max(0.5, S * 0.02))
        if S > 12, lived {
            let red = Self.c(warm ? (0.86, 0.16, 0.14) : (0.6, 0.3, 0.32))
            g.fill(Path(CGRect(x: door.minX - S * 0.07, y: door.minY, width: S * 0.045, height: door.height * 0.85)), with: .color(red))
            g.fill(Path(CGRect(x: door.maxX + S * 0.025, y: door.minY, width: S * 0.045, height: door.height * 0.85)), with: .color(red))
            g.fill(Path(CGRect(x: door.minX - S * 0.02, y: door.minY - S * 0.07, width: door.width + S * 0.04, height: S * 0.045)), with: .color(red))
        }
        let wy = fr.wall.minY + fr.wall.height * 0.26
        window(&g, CGRect(x: fr.wall.minX + S * 0.18, y: wy, width: S * 0.3, height: S * 0.24), S: S, lit: warm, frosted: cold)
        window(&g, CGRect(x: fr.wall.maxX - S * 0.48, y: wy, width: S * 0.3, height: S * 0.24), S: S, lit: warm, frosted: cold)
        if cold || !lived {
            // Snow banked against the wall.
            g.fill(Path(ellipseIn: CGRect(x: fr.wall.minX - S * 0.1, y: fr.wall.maxY - S * 0.18, width: fr.wall.width * 0.5, height: S * 0.26)), with: .color(.white))
        }
        let colours: [RGB] = [(0.38, 0.42, 0.52), (0.3, 0.44, 0.46), (0.46, 0.34, 0.32)]
        roof(&g, over: fr.wall, rise: S * 1.0, S: S, colour: colours[b.id % 3], snow: 1, overhang: 0.24)
        icicles(&g, from: fr.wall.minX, to: fr.wall.maxX, y: fr.wall.minY + S * 0.07, S: S, long: S * (cold || !lived ? 0.24 : 0.09), seed: b.id)
        chimney(&g, at: CGPoint(x: fr.wall.maxX - S * 0.34, y: fr.wall.minY - S * 0.56), S: S, smoking: warm, seed: b.id)
        if warm { lantern(&g, CGPoint(x: fr.wall.minX - S * 0.02, y: fr.wall.minY + S * 0.08), S: S) }
    }

    private func storage(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let fr = Frame(F, S: S, height: 0.84, inset: 0.12)
        softShadow(&g, F, S, strength: 0.14 + 0.06)
        Art.wall(&g, fr.wall, .planks, S: S, tint: (0.64, 0.44, 0.3))
        let door = CGRect(x: fr.wall.midX - S * 0.28, y: fr.wall.maxY - S * 0.52, width: S * 0.56, height: S * 0.46)
        g.fill(Path(door), with: .color(Self.c((0.46, 0.26, 0.18))))
        g.stroke(Path { p in p.move(to: CGPoint(x: door.minX, y: door.minY)); p.addLine(to: CGPoint(x: door.maxX, y: door.maxY)); p.move(to: CGPoint(x: door.maxX, y: door.minY)); p.addLine(to: CGPoint(x: door.minX, y: door.maxY)) },
                 with: .color(Self.c((0.9, 0.82, 0.66))), lineWidth: max(0.6, S * 0.03))
        roof(&g, over: fr.wall, rise: S * 0.9, S: S, colour: (0.46, 0.36, 0.3))
        if S > 12 {
            let sign = CGRect(x: fr.wall.midX - S * 0.15, y: fr.wall.minY + S * 0.02, width: S * 0.3, height: S * 0.17)
            g.fill(Path(roundedRect: sign, cornerRadius: S * 0.02), with: .color(Self.c((0.2, 0.18, 0.2))))
            g.draw(Text("仓").font(.system(size: S * 0.14, weight: .heavy)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.4)), at: CGPoint(x: sign.midX, y: sign.midY))
        }
        goods(&g, b, CGRect(x: F.minX + S * 0.05, y: F.maxY - S * 0.3, width: F.width - S * 0.1, height: S * 0.3), S)
    }

    /// Goods piled in front of a storage by how much there is: coal, wood, sacks of food, stone, iron.
    private func goods(_ g: inout GraphicsContext, _ b: IceBuilding, _ strip: CGRect, _ S: CGFloat) {
        var x = strip.minX
        for gd in 0..<5 where b.stock[gd] >= 1 {
            let piles = min(3, Int(b.stock[gd] / 120) + 1)
            for k in 0..<piles {
                let r = CGRect(x: x + CGFloat(k) * S * 0.05, y: strip.maxY - S * 0.18 - CGFloat(k) * S * 0.08, width: S * 0.2, height: S * 0.15)
                switch gd {
                case 0: g.fill(Path(ellipseIn: r), with: .color(Self.c((0.16, 0.16, 0.18))))
                case 1: g.fill(Path(roundedRect: r, cornerRadius: S * 0.03), with: .color(Self.c((0.58, 0.4, 0.22)))); g.fill(Path(ellipseIn: CGRect(x: r.maxX - S * 0.06, y: r.minY, width: S * 0.07, height: r.height)), with: .color(Self.c((0.9, 0.76, 0.52))))
                case 2: g.fill(Path(roundedRect: r, cornerRadius: S * 0.07), with: .color(Self.c((0.92, 0.84, 0.64))))
                case 3: g.fill(Path(roundedRect: r, cornerRadius: S * 0.02), with: .color(Self.c((0.76, 0.76, 0.78))))
                default: g.fill(Path(roundedRect: r.insetBy(dx: S * 0.02, dy: S * 0.03), cornerRadius: S * 0.02), with: .color(Self.c((0.36, 0.36, 0.42))))
                }
            }
            x += S * 0.3
            if x > strip.maxX - S * 0.2 { break }
        }
    }

    private func logPile(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat) {
        var ends = Path(), rings = Path()
        for row in 0..<2 { for k in 0..<(3 - row) {
            let d = S * 0.17
            let p = CGPoint(x: foot.x - d * 1.5 + CGFloat(row) * d * 0.5 + CGFloat(k) * d, y: foot.y - CGFloat(row + 1) * d * 0.9)
            ends.addEllipse(in: CGRect(x: p.x, y: p.y, width: d, height: d))
            rings.addEllipse(in: CGRect(x: p.x + d * 0.22, y: p.y + d * 0.22, width: d * 0.56, height: d * 0.56))
        } }
        g.fill(ends, with: .color(Self.c((0.56, 0.38, 0.22))))
        g.fill(rings, with: .color(Self.c((0.9, 0.76, 0.52))))
        g.fill(Path(roundedRect: CGRect(x: foot.x - S * 0.28, y: foot.y - S * 0.36, width: S * 0.44, height: S * 0.07), cornerRadius: S * 0.03), with: .color(.white))
    }

    private func lumber(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let fr = Frame(F, S: S, height: 0.6, inset: 0.18)
        softShadow(&g, F, S, strength: 0.12 + 0.06)
        let back = CGRect(x: fr.wall.minX, y: fr.wall.minY - S * 0.1, width: fr.wall.width, height: fr.wall.height + S * 0.1)
        Art.wall(&g, back, .logs, S: S, tint: (0.52, 0.36, 0.24))
        // Posts, a lean-to roof, a stack of split wood under it.
        for x in [back.minX + S * 0.04, back.maxX - S * 0.1] { g.fill(Path(CGRect(x: x, y: back.minY, width: S * 0.07, height: back.height)), with: .color(Self.c(Self.timber))) }
        roof(&g, over: CGRect(x: back.minX, y: back.minY + S * 0.05, width: back.width, height: back.height), rise: S * 0.5, S: S, colour: (0.44, 0.36, 0.3))
        logPile(&g, CGPoint(x: fr.wall.midX, y: fr.wall.maxY), S)
        // A block with an axe.
        let block = CGRect(x: F.maxX - S * 0.4, y: F.maxY - S * 0.32, width: S * 0.28, height: S * 0.18)
        g.fill(Path(ellipseIn: block), with: .color(Self.c((0.55, 0.4, 0.26))))
        g.stroke(Path { p in p.move(to: CGPoint(x: block.midX, y: block.minY + S * 0.04)); p.addLine(to: CGPoint(x: block.midX + S * 0.14, y: block.minY - S * 0.18)) }, with: .color(Self.c((0.5, 0.36, 0.22))), lineWidth: max(1, S * 0.04))
        g.fill(Path(CGRect(x: block.midX + S * 0.08, y: block.minY - S * 0.22, width: S * 0.1, height: S * 0.07)), with: .color(Self.c((0.7, 0.72, 0.76))))
    }

    private func mine(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let coal = b.kind == .coalMine
        // A snowy knoll with a timbered mouth.
        let knoll = Path { p in
            p.move(to: CGPoint(x: F.minX + S * 0.1, y: F.maxY - S * 0.15))
            p.addQuadCurve(to: CGPoint(x: F.minX + F.width * 0.62, y: F.maxY - S * 0.15), control: CGPoint(x: F.minX + F.width * 0.3, y: F.minY - S * 0.2))
            p.closeSubpath()
        }
        g.fill(knoll, with: .linearGradient(Gradient(colors: [Self.c((0.62, 0.62, 0.66)), Self.c((0.42, 0.42, 0.48))]), startPoint: CGPoint(x: F.minX, y: F.minY), endPoint: CGPoint(x: F.midX, y: F.maxY)))
        g.fill(Path { p in
            p.move(to: CGPoint(x: F.minX + S * 0.35, y: F.minY + F.height * 0.45))
            p.addQuadCurve(to: CGPoint(x: F.minX + F.width * 0.52, y: F.minY + F.height * 0.45), control: CGPoint(x: F.minX + F.width * 0.3, y: F.minY - S * 0.05))
            p.closeSubpath()
        }, with: .color(.white))
        let mouth = CGRect(x: F.minX + F.width * 0.2, y: F.maxY - S * 0.95, width: S * 0.7, height: S * 0.78)
        g.fill(Path(roundedRect: mouth, cornerRadii: RectangleCornerRadii(topLeading: S * 0.35, bottomLeading: 0, bottomTrailing: 0, topTrailing: S * 0.35)), with: .color(Self.c((0.07, 0.06, 0.06))))
        g.stroke(Path { p in p.move(to: CGPoint(x: mouth.minX, y: mouth.maxY)); p.addLine(to: CGPoint(x: mouth.minX, y: mouth.minY + S * 0.16)); p.addLine(to: CGPoint(x: mouth.maxX, y: mouth.minY + S * 0.16)); p.addLine(to: CGPoint(x: mouth.maxX, y: mouth.maxY)) },
                 with: .color(Self.c((0.56, 0.4, 0.24))), lineWidth: max(1.2, S * 0.08))
        if coal {
            // The headframe: a timber A-frame with its wheel turning.
            let foot = CGPoint(x: F.maxX - S * 0.8, y: F.maxY - S * 0.2), top = CGPoint(x: F.maxX - S * 0.8, y: F.minY - S * 0.35)
            g.stroke(Path { p in
                p.move(to: CGPoint(x: foot.x - S * 0.45, y: foot.y)); p.addLine(to: top); p.addLine(to: CGPoint(x: foot.x + S * 0.45, y: foot.y))
                p.move(to: CGPoint(x: foot.x - S * 0.3, y: foot.y - S * 0.6)); p.addLine(to: CGPoint(x: foot.x + S * 0.3, y: foot.y - S * 0.6))
                p.move(to: CGPoint(x: foot.x - S * 0.16, y: foot.y - S * 1.3)); p.addLine(to: CGPoint(x: foot.x + S * 0.16, y: foot.y - S * 1.3))
            }, with: .color(Self.c((0.48, 0.32, 0.2))), style: StrokeStyle(lineWidth: max(1.2, S * 0.08), lineCap: .round))
            var wheel = g
            wheel.translateBy(x: top.x, y: top.y + S * 0.14)
            wheel.rotate(by: .radians(now * (workersAt(b) > 0 ? 1.6 : 0)))
            wheel.stroke(Path(ellipseIn: CGRect(x: -S * 0.24, y: -S * 0.24, width: S * 0.48, height: S * 0.48)), with: .color(Self.c((0.3, 0.22, 0.16))), lineWidth: max(1, S * 0.05))
            wheel.stroke(Path { p in p.move(to: CGPoint(x: -S * 0.24, y: 0)); p.addLine(to: CGPoint(x: S * 0.24, y: 0)); p.move(to: CGPoint(x: 0, y: -S * 0.24)); p.addLine(to: CGPoint(x: 0, y: S * 0.24)) }, with: .color(Self.c((0.3, 0.22, 0.16))), lineWidth: max(0.8, S * 0.03))
            g.fill(Path(ellipseIn: CGRect(x: top.x - S * 0.12, y: top.y - S * 0.12, width: S * 0.24, height: S * 0.1)), with: .color(.white))
        } else {
            // A little bloomery with a glow, for the iron.
            let kiln = CGRect(x: F.maxX - S * 1.0, y: F.maxY - S * 1.1, width: S * 0.6, height: S * 0.9)
            g.fill(Path(roundedRect: kiln, cornerRadii: RectangleCornerRadii(topLeading: S * 0.2, bottomLeading: 0, bottomTrailing: 0, topTrailing: S * 0.2)), with: .color(Self.c((0.56, 0.44, 0.4))))
            let glow = 0.7 + 0.3 * sin(now * 5 + Double(b.id))
            g.fill(Path(roundedRect: CGRect(x: kiln.midX - S * 0.12, y: kiln.maxY - S * 0.36, width: S * 0.24, height: S * 0.26), cornerRadius: S * 0.08), with: .color(Color(red: 1, green: 0.5 + 0.2 * glow, blue: 0.15)))
            g.fill(Path(roundedRect: CGRect(x: kiln.minX - S * 0.04, y: kiln.minY - S * 0.06, width: kiln.width + S * 0.08, height: S * 0.12), cornerRadius: S * 0.05), with: .color(.white))
        }
        // Rails and a cart heaped with coal or ore.
        let cart = CGRect(x: F.minX + F.width * 0.42, y: F.maxY - S * 0.46, width: S * 0.5, height: S * 0.28)
        g.stroke(Path { p in p.move(to: CGPoint(x: mouth.midX, y: mouth.maxY)); p.addLine(to: CGPoint(x: cart.maxX + S * 0.3, y: cart.maxY + S * 0.05)) }, with: .color(Self.c((0.4, 0.38, 0.4))), lineWidth: max(0.8, S * 0.03))
        g.fill(Path(roundedRect: cart, cornerRadius: S * 0.04), with: .color(Self.c((0.46, 0.32, 0.2))))
        var heap = Path()
        heap.addEllipse(in: CGRect(x: cart.minX + S * 0.02, y: cart.minY - S * 0.12, width: S * 0.26, height: S * 0.2))
        heap.addEllipse(in: CGRect(x: cart.minX + S * 0.2, y: cart.minY - S * 0.14, width: S * 0.26, height: S * 0.22))
        g.fill(heap, with: .color(coal ? Self.c((0.13, 0.13, 0.16)) : Self.c((0.5, 0.36, 0.3))))
        if !coal { g.fill(Path(ellipseIn: CGRect(x: cart.midX - S * 0.05, y: cart.minY - S * 0.1, width: S * 0.09, height: S * 0.07)), with: .color(Self.c((0.9, 0.46, 0.2)))) }
        if b.done, b.reserve <= 0 { JevDraw.text(g, "挖空了", at: CGPoint(x: F.midX, y: F.midY), size: max(10, S * 0.36)) }
    }

    private func quarry(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let pit = F.insetBy(dx: S * 0.14, dy: S * 0.14)
        // A pit cut in steps: a snowy rim, then grey ledges darker as they go down.
        g.fill(Path(ellipseIn: pit.insetBy(dx: -S * 0.12, dy: -S * 0.06)), with: .color(.white))
        for k in 0..<3 {
            let r = pit.insetBy(dx: CGFloat(k) * S * 0.3, dy: CGFloat(k) * S * 0.24).offsetBy(dx: 0, dy: CGFloat(k) * S * 0.05)
            g.fill(Path(ellipseIn: r), with: .color(Self.c(Art.lit((0.6, 0.6, 0.66), 1 - Double(k) * 0.18))))
            g.stroke(Path { p in p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false) }
                        .applying(CGAffineTransform(translationX: -r.midX, y: -r.midY).concatenating(CGAffineTransform(scaleX: 1, y: r.height / r.width)).concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))),
                     with: .color(.white.opacity(0.8)), lineWidth: max(0.8, S * 0.05))
        }
        var blocks = Path(), sides = Path()
        for k in 0..<5 {
            let r = CGRect(x: pit.minX + S * (0.15 + CGFloat(k % 3) * 0.55), y: pit.maxY - S * (0.42 + CGFloat(k / 3) * 0.28), width: S * 0.42, height: S * 0.24)
            blocks.addRoundedRect(in: r, cornerSize: CGSize(width: S * 0.03, height: S * 0.03))
            sides.addRect(CGRect(x: r.minX, y: r.maxY - S * 0.07, width: r.width, height: S * 0.07))
        }
        g.fill(blocks, with: .color(Self.c((0.86, 0.86, 0.88))))
        g.fill(sides, with: .color(Self.c((0.62, 0.62, 0.66))))
        let foot = CGPoint(x: pit.maxX - S * 0.4, y: pit.maxY - S * 0.2)
        g.stroke(Path { p in p.move(to: foot); p.addLine(to: CGPoint(x: foot.x, y: foot.y - S * 1.4)); p.addLine(to: CGPoint(x: foot.x - S * 1.0, y: foot.y - S * 1.1)) }, with: .color(Self.c((0.5, 0.36, 0.22))), lineWidth: max(1, S * 0.07))
        g.stroke(Path { p in p.move(to: CGPoint(x: foot.x - S * 1.0, y: foot.y - S * 1.1)); p.addLine(to: CGPoint(x: foot.x - S * 1.0, y: foot.y - S * 0.5)) }, with: .color(Self.c(Art.ink, 0.7)), lineWidth: max(0.5, S * 0.02))
        if b.done, b.reserve <= 0 { JevDraw.text(g, "挖空了", at: CGPoint(x: F.midX, y: F.midY), size: max(10, S * 0.36)) }
    }

    private func hunter(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let fr = Frame(F, S: S, height: 0.76, inset: 0.16)
        softShadow(&g, F, S, strength: 0.14 + 0.06)
        Art.wall(&g, fr.wall, .logs, S: S, tint: (0.56, 0.38, 0.24))
        let door = CGRect(x: fr.wall.midX - S * 0.13, y: fr.wall.maxY - S * 0.42, width: S * 0.26, height: S * 0.36)
        g.fill(Path(roundedRect: door, cornerRadius: S * 0.04), with: .color(Self.c((0.34, 0.2, 0.12))))
        roof(&g, over: fr.wall, rise: S * 0.86, S: S, colour: (0.46, 0.34, 0.26))
        // Antlers over the door.
        let a = CGPoint(x: fr.wall.midX, y: fr.wall.minY + S * 0.14)
        g.stroke(Path { p in
            for s in [-1.0, 1.0] as [CGFloat] {
                p.move(to: a); p.addQuadCurve(to: CGPoint(x: a.x + s * S * 0.24, y: a.y - S * 0.2), control: CGPoint(x: a.x + s * S * 0.22, y: a.y))
                p.move(to: CGPoint(x: a.x + s * S * 0.14, y: a.y - S * 0.05)); p.addLine(to: CGPoint(x: a.x + s * S * 0.12, y: a.y - S * 0.2))
            }
        }, with: .color(Self.c((0.96, 0.92, 0.82))), style: StrokeStyle(lineWidth: max(0.8, S * 0.04), lineCap: .round))
        // A pelt on its rack.
        let rack = CGPoint(x: F.maxX - S * 0.22, y: F.maxY - S * 0.1)
        g.stroke(Path { p in p.move(to: CGPoint(x: rack.x - S * 0.14, y: rack.y)); p.addLine(to: CGPoint(x: rack.x - S * 0.14, y: rack.y - S * 0.46)); p.move(to: CGPoint(x: rack.x + S * 0.14, y: rack.y)); p.addLine(to: CGPoint(x: rack.x + S * 0.14, y: rack.y - S * 0.46)); p.move(to: CGPoint(x: rack.x - S * 0.18, y: rack.y - S * 0.42)); p.addLine(to: CGPoint(x: rack.x + S * 0.18, y: rack.y - S * 0.42)) },
                 with: .color(Self.c((0.42, 0.28, 0.18))), lineWidth: max(0.8, S * 0.04))
        g.fill(Path(roundedRect: CGRect(x: rack.x - S * 0.12, y: rack.y - S * 0.42, width: S * 0.24, height: S * 0.3), cornerRadius: S * 0.08), with: .color(Self.c((0.74, 0.52, 0.32))))
    }

    private func fishery(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let fr = Frame(F, S: S, height: 0.7, inset: 0.2)
        // Runners under the hut, and its shadow on the ice.
        g.fill(Path(ellipseIn: CGRect(x: fr.wall.minX - S * 0.1, y: fr.wall.maxY - S * 0.06, width: fr.wall.width + S * 0.5, height: S * 0.24)), with: .color(Color(red: 0.2, green: 0.36, blue: 0.56).opacity(0.2)))
        g.stroke(Path { p in p.move(to: CGPoint(x: fr.wall.minX - S * 0.12, y: fr.wall.maxY + S * 0.02)); p.addQuadCurve(to: CGPoint(x: fr.wall.maxX + S * 0.1, y: fr.wall.maxY + S * 0.02), control: CGPoint(x: fr.wall.midX, y: fr.wall.maxY + S * 0.06)) },
                 with: .color(Self.c((0.4, 0.28, 0.2))), lineWidth: max(1, S * 0.05))
        Art.wall(&g, fr.wall, .planks, S: S, tint: (0.46, 0.56, 0.7))
        let door = CGRect(x: fr.wall.midX - S * 0.12, y: fr.wall.maxY - S * 0.38, width: S * 0.24, height: S * 0.32)
        g.fill(Path(roundedRect: door, cornerRadius: S * 0.04), with: .color(Self.c((0.86, 0.34, 0.24))))
        roof(&g, over: fr.wall, rise: S * 0.74, S: S, colour: (0.36, 0.4, 0.5))
        chimney(&g, at: CGPoint(x: fr.wall.minX + S * 0.3, y: fr.wall.minY - S * 0.34), S: S, smoking: icon || workersAt(b) > 0, seed: b.id)
        // Fish drying on a line.
        if S > 12 {
            let a = CGPoint(x: F.minX + S * 0.1, y: F.maxY - S * 0.5), z = CGPoint(x: F.minX + S * 0.1, y: F.maxY - S * 0.05)
            g.stroke(Path { p in p.move(to: z); p.addLine(to: a) }, with: .color(Self.c((0.42, 0.3, 0.2))), lineWidth: max(0.8, S * 0.035))
            var fish = Path()
            for k in 0..<2 { fish.addEllipse(in: CGRect(x: a.x + S * 0.04, y: a.y + S * (0.06 + CGFloat(k) * 0.13), width: S * 0.18, height: S * 0.08)) }
            g.fill(fish, with: .color(Self.c((0.72, 0.78, 0.86))))
        }
    }

    private func greenhouse(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let base = CGRect(x: F.minX + S * 0.15, y: F.maxY - S * 0.4, width: F.width - S * 0.3, height: S * 0.28)
        softShadow(&g, F, S, strength: 0.12 + 0.06)
        g.fill(Path(roundedRect: base, cornerRadius: S * 0.05), with: .color(Self.c((0.66, 0.66, 0.7))))
        let top = F.minY + S * 0.1
        let glass = Path { p in
            p.move(to: CGPoint(x: base.minX + S * 0.05, y: base.minY))
            p.addLine(to: CGPoint(x: base.minX + S * 0.05, y: base.minY - S * 0.9))
            p.addQuadCurve(to: CGPoint(x: base.maxX - S * 0.05, y: base.minY - S * 0.9), control: CGPoint(x: base.midX, y: top - S * 0.6))
            p.addLine(to: CGPoint(x: base.maxX - S * 0.05, y: base.minY))
            p.closeSubpath()
        }
        let lit = icon || city.burning && city.warmed(b)
        g.fill(glass, with: .linearGradient(Gradient(colors: [Self.c((0.74, 0.93, 0.92), 0.92), Self.c((0.5, 0.78, 0.7), 0.92)]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: base.minY)))
        var inside = g
        inside.clip(to: glass)
        var leaves = Path(), fruit = Path()
        for k in 0..<9 {
            let q = CGPoint(x: base.minX + S * 0.25 + CGFloat(k) * (base.width - S * 0.5) / 8, y: base.minY - S * 0.05)
            let h = S * CGFloat(0.26 + Double(k % 3) * 0.08)
            leaves.addEllipse(in: CGRect(x: q.x - S * 0.14, y: q.y - h, width: S * 0.28, height: h))
            if k % 2 == 1 { fruit.addEllipse(in: CGRect(x: q.x - S * 0.04, y: q.y - h * 0.8, width: S * 0.09, height: S * 0.09)) }
        }
        inside.fill(leaves, with: .color(Self.c((0.24, 0.6, 0.32))))
        inside.fill(fruit, with: .color(Self.c((0.96, 0.36, 0.24))))
        if lit { inside.fill(Path(ellipseIn: CGRect(x: base.minX, y: top - S * 0.4, width: base.width, height: base.minY - top + S * 0.4)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.6).opacity(0.35), .clear]), center: CGPoint(x: base.midX, y: base.minY - S * 0.5), startRadius: 0, endRadius: S * 1.3)) }
        else { inside.fill(Path(base.insetBy(dx: 0, dy: -S * 3)), with: .color(.white.opacity(0.4))) }
        var ribs = Path()
        for k in 1..<5 {
            let x = base.minX + S * 0.05 + (base.width - S * 0.1) * CGFloat(k) / 5
            ribs.move(to: CGPoint(x: x, y: base.minY)); ribs.addLine(to: CGPoint(x: x, y: base.minY - S * 1.3))
        }
        inside.stroke(ribs, with: .color(.white.opacity(0.75)), lineWidth: max(0.6, S * 0.025))
        g.stroke(glass, with: .color(Self.c((0.36, 0.4, 0.46))), lineWidth: max(0.8, S * 0.04))
        g.fill(Path(ellipseIn: CGRect(x: base.midX - S * 0.5, y: top - S * 0.28, width: S * 1.0, height: S * 0.2)), with: .color(.white))
    }

    private func clinic(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let fr = Frame(F, S: S, height: 0.84, inset: 0.14)
        softShadow(&g, F, S, strength: 0.14 + 0.06)
        pillared(&g, fr.wall, S: S, pillars: 3, plaster: (0.99, 0.98, 0.95))
        let door = CGRect(x: fr.wall.midX - S * 0.15, y: fr.wall.maxY - S * 0.44, width: S * 0.3, height: S * 0.38)
        g.fill(Path(roundedRect: door, cornerRadius: S * 0.04), with: .color(Self.c((0.44, 0.28, 0.2))))
        window(&g, CGRect(x: fr.wall.minX + S * 0.14, y: fr.wall.minY + S * 0.18, width: S * 0.22, height: S * 0.18), S: S, lit: true)
        roof(&g, over: fr.wall, rise: S * 0.92, S: S, colour: (0.26, 0.5, 0.48))
        flag(&g, CGPoint(x: F.maxX - S * 0.14, y: F.maxY - S * 0.1), S: S, colour: (0.96, 0.96, 0.94), text: "医", height: 1.25)
        if S > 12 { g.draw(Text("医").font(.system(size: S * 0.26, weight: .heavy)).foregroundColor(Color(red: 0.86, green: 0.18, blue: 0.16)), at: CGPoint(x: F.maxX - S * 0.14 + S * 0.18, y: F.maxY - S * 1.25 + S * 0.25)) }
        // A gourd by the door.
        g.fill(Path(ellipseIn: CGRect(x: door.maxX + S * 0.05, y: door.minY + S * 0.1, width: S * 0.14, height: S * 0.14)), with: .color(Self.c((0.92, 0.66, 0.24))))
        g.fill(Path(ellipseIn: CGRect(x: door.maxX + S * 0.07, y: door.minY + S * 0.02, width: S * 0.1, height: S * 0.1)), with: .color(Self.c((0.92, 0.66, 0.24))))
    }

    private func barracks(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let fr = Frame(F, S: S, height: 1.0, inset: 0.24)
        softShadow(&g, F, S, strength: 0.16 + 0.06)
        Art.wall(&g, fr.wall, .stone, S: S, tint: (0.66, 0.66, 0.7))
        var posts = Path()
        for k in 0..<4 { posts.addRect(CGRect(x: fr.wall.minX + (fr.wall.width - S * 0.1) * CGFloat(k) / 3, y: fr.wall.minY, width: S * 0.1, height: fr.wall.height - S * 0.06)) }
        g.fill(posts, with: .color(Self.c(Self.pillar)))
        let door = CGRect(x: fr.wall.midX - S * 0.26, y: fr.wall.maxY - S * 0.56, width: S * 0.52, height: S * 0.5)
        g.fill(Path(roundedRect: door, cornerRadii: RectangleCornerRadii(topLeading: S * 0.22, bottomLeading: 0, bottomTrailing: 0, topTrailing: S * 0.22)), with: .color(Self.c((0.66, 0.16, 0.12))))
        var studs = Path()
        for yy in 0..<3 { for xx in 0..<3 { studs.addEllipse(in: CGRect(x: door.minX + S * (0.08 + CGFloat(xx) * 0.15), y: door.minY + S * (0.14 + CGFloat(yy) * 0.1), width: S * 0.05, height: S * 0.05)) } }
        g.fill(studs, with: .color(Self.c(Self.gold)))
        roof(&g, over: fr.wall, rise: S * 1.15, S: S, colour: (0.32, 0.36, 0.42), overhang: 0.28)
        flag(&g, CGPoint(x: F.minX + S * 0.18, y: F.maxY - S * 0.12), S: S, colour: Self.shu, text: "蜀", height: 1.7)
        flag(&g, CGPoint(x: F.maxX - S * 0.52, y: F.maxY - S * 0.12), S: S, colour: Self.shu, text: "蜀", height: 1.7)
        // A spear rack.
        var spears = Path(), tips = Path()
        for k in 0..<4 {
            let x = F.maxX - S * 0.28 + CGFloat(k) * S * 0.06
            spears.move(to: CGPoint(x: x, y: F.maxY - S * 0.12)); spears.addLine(to: CGPoint(x: x + S * 0.03, y: F.maxY - S * 0.95))
            tips.move(to: CGPoint(x: x + S * 0.03, y: F.maxY - S * 1.08)); tips.addLine(to: CGPoint(x: x + S * 0.06, y: F.maxY - S * 0.95)); tips.addLine(to: CGPoint(x: x, y: F.maxY - S * 0.95)); tips.closeSubpath()
        }
        g.stroke(spears, with: .color(Self.c((0.5, 0.36, 0.22))), lineWidth: max(0.8, S * 0.03))
        g.fill(tips, with: .color(Self.c((0.84, 0.86, 0.9))))
        if b.batch > 0 { JevDraw.text(g, "操练中 \(b.batch)", at: CGPoint(x: F.midX, y: F.minY - S * 0.35), size: max(10, S * 0.3), colour: Color(red: 1, green: 0.92, blue: 0.7)) }
    }

    private func tavern(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let fr = Frame(F, S: S, height: 1.05, inset: 0.14)
        softShadow(&g, F, S, strength: 0.14 + 0.06)
        Art.wall(&g, fr.wall, .planks, S: S, tint: (0.72, 0.52, 0.34))
        g.fill(Path(CGRect(x: fr.wall.minX, y: fr.wall.midY - S * 0.03, width: fr.wall.width, height: S * 0.06)), with: .color(Self.c(Self.timber)))
        for x in [fr.wall.minX + S * 0.12, fr.wall.maxX - S * 0.38] { window(&g, CGRect(x: x, y: fr.wall.minY + S * 0.12, width: S * 0.26, height: S * 0.2), S: S, lit: true) }
        let door = CGRect(x: fr.wall.midX - S * 0.14, y: fr.wall.maxY - S * 0.4, width: S * 0.28, height: S * 0.36)
        g.fill(Path(roundedRect: door, cornerRadius: S * 0.04), with: .color(Self.c((0.44, 0.24, 0.14))))
        g.fill(Path(ellipseIn: door.insetBy(dx: -S * 0.2, dy: -S * 0.1)), with: .color(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.18)))
        roof(&g, over: fr.wall, rise: S * 0.9, S: S, colour: (0.62, 0.26, 0.22))
        lantern(&g, CGPoint(x: fr.wall.minX + S * 0.02, y: fr.wall.minY + S * 0.1), S: S)
        lantern(&g, CGPoint(x: fr.wall.maxX - S * 0.02, y: fr.wall.minY + S * 0.1), S: S)
        // The wine flag.
        let pole = CGPoint(x: F.minX + S * 0.08, y: F.maxY - S * 0.1)
        g.stroke(Path { p in p.move(to: pole); p.addLine(to: CGPoint(x: pole.x, y: pole.y - S * 1.5)) }, with: .color(Self.c((0.4, 0.28, 0.18))), lineWidth: max(1, S * 0.05))
        let wave = CGFloat(sin(now * 3)) * S * 0.04
        let cloth = Path { p in p.move(to: CGPoint(x: pole.x, y: pole.y - S * 1.45)); p.addLine(to: CGPoint(x: pole.x + S * 0.34 + wave, y: pole.y - S * 1.42)); p.addLine(to: CGPoint(x: pole.x + S * 0.34 - wave, y: pole.y - S * 0.92)); p.addLine(to: CGPoint(x: pole.x, y: pole.y - S * 0.95)); p.closeSubpath() }
        g.fill(cloth, with: .color(Self.c((0.97, 0.92, 0.8))))
        g.stroke(cloth, with: .color(Self.c((0.8, 0.2, 0.16))), lineWidth: max(0.6, S * 0.025))
        if S > 12 { g.draw(Text("酒").font(.system(size: S * 0.24, weight: .heavy)).foregroundColor(Color(red: 0.8, green: 0.16, blue: 0.12)), at: CGPoint(x: pole.x + S * 0.17, y: pole.y - S * 1.18)) }
    }

    /// The great furnace: a drum of riveted iron on a stone footing, fire in its arched mouth, a cone roof under snow, the stack smoking — bigger for every level.
    private func furnace(_ g: inout GraphicsContext, _ b: IceBuilding, _ F: CGRect, _ S: CGFloat) {
        let level = max(1, b.level)
        let lit = city.burning
        let s = S * CGFloat(1.12 + 0.07 * Double(level))
        let foot = CGPoint(x: F.midX, y: F.maxY - S * 0.35)
        let flicker = 0.82 + 0.18 * sin(now * 9) * sin(now * 5.3 + 1)
        // Warm light pooled on the plaza.
        if lit { g.fill(Path(ellipseIn: CGRect(x: foot.x - s * 2.1, y: foot.y - s * 0.9, width: s * 4.2, height: s * 1.7)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.24).opacity(0.4 * flicker), .clear]), center: foot, startRadius: 0, endRadius: s * 2.1)) }
        // Stone footing, two steps.
        g.fill(Path(ellipseIn: CGRect(x: foot.x - s * 1.35, y: foot.y - s * 0.34, width: s * 2.7, height: s * 0.74)), with: .color(Self.c((0.44, 0.44, 0.5))))
        g.fill(Path(ellipseIn: CGRect(x: foot.x - s * 1.28, y: foot.y - s * 0.42, width: s * 2.56, height: s * 0.66)), with: .color(Self.c((0.7, 0.7, 0.76))))
        g.fill(Path(ellipseIn: CGRect(x: foot.x - s * 1.05, y: foot.y - s * 0.52, width: s * 2.1, height: s * 0.56)), with: .color(Self.c((0.58, 0.58, 0.64))))
        // The drum.
        let tall = s * (1.55 + 0.1 * CGFloat(level))
        let body = CGRect(x: foot.x - s * 0.78, y: foot.y - s * 0.28 - tall, width: s * 1.56, height: tall)
        g.fill(Path(roundedRect: body, cornerRadius: s * 0.2), with: .linearGradient(Gradient(stops: [.init(color: Self.c((0.46, 0.48, 0.56)), location: 0), .init(color: Self.c((0.33, 0.34, 0.41)), location: 0.55), .init(color: Self.c((0.2, 0.2, 0.26)), location: 1)]),
                                                                              startPoint: CGPoint(x: body.minX, y: body.midY), endPoint: CGPoint(x: body.maxX, y: body.midY)))
        if lit { g.fill(Path(roundedRect: body, cornerRadius: s * 0.2), with: .linearGradient(Gradient(colors: [.clear, Color(red: 1, green: 0.5, blue: 0.2).opacity(0.25 * flicker)]), startPoint: CGPoint(x: body.midX, y: body.minY), endPoint: CGPoint(x: body.midX, y: body.maxY))) }
        // Copper bands with rivets, one for each level.
        var bands = Path(), rivets = Path()
        for k in 0..<min(level + 1, 5) {
            let y = body.maxY - s * 0.3 - CGFloat(k) * tall / (CGFloat(min(level + 1, 5)) + 0.6)
            bands.addRoundedRect(in: CGRect(x: body.minX - s * 0.04, y: y, width: body.width + s * 0.08, height: s * 0.11), cornerSize: CGSize(width: s * 0.05, height: s * 0.05))
            if S > 12 { for r in 0..<7 { rivets.addEllipse(in: CGRect(x: body.minX + s * 0.1 + CGFloat(r) * s * 0.22, y: y + s * 0.03, width: s * 0.05, height: s * 0.05)) } }
        }
        g.fill(bands, with: .color(Self.c((0.8, 0.5, 0.26))))
        g.fill(rivets, with: .color(Self.c((1, 0.82, 0.52))))
        // The fire's mouth.
        let mouth = CGRect(x: foot.x - s * 0.36, y: foot.y - s * 0.3 - s * 0.84, width: s * 0.72, height: s * 0.8)
        let arch = Path(roundedRect: mouth, cornerRadii: RectangleCornerRadii(topLeading: s * 0.36, bottomLeading: s * 0.04, bottomTrailing: s * 0.04, topTrailing: s * 0.36))
        g.fill(arch, with: .color(Self.c((0.12, 0.08, 0.08))))
        if lit {
            g.fill(arch, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.72), Color(red: 1, green: 0.64, blue: 0.18), Color(red: 0.86, green: 0.26, blue: 0.08)]),
                                              center: CGPoint(x: mouth.midX, y: mouth.maxY - s * 0.1), startRadius: 0, endRadius: s * 0.7 * CGFloat(flicker)))
            var flames = Path()
            for k in 0..<3 {
                let x = mouth.minX + s * 0.18 + CGFloat(k) * s * 0.18, h = s * 0.3 * CGFloat(0.7 + 0.3 * sin(now * 8 + Double(k) * 2))
                flames.move(to: CGPoint(x: x - s * 0.08, y: mouth.maxY)); flames.addQuadCurve(to: CGPoint(x: x, y: mouth.maxY - h - s * 0.16), control: CGPoint(x: x - s * 0.11, y: mouth.maxY - h))
                flames.addQuadCurve(to: CGPoint(x: x + s * 0.08, y: mouth.maxY), control: CGPoint(x: x + s * 0.11, y: mouth.maxY - h)); flames.closeSubpath()
            }
            g.fill(flames, with: .color(Color(red: 1, green: 0.92, blue: 0.55).opacity(0.9)))
        } else {
            var embers = Path()
            for k in 0..<4 { embers.addEllipse(in: CGRect(x: mouth.minX + s * (0.12 + CGFloat(k) * 0.13), y: mouth.maxY - s * 0.12, width: s * 0.08, height: s * 0.06)) }
            g.fill(embers, with: .color(Color(red: 0.5, green: 0.2, blue: 0.14)))
        }
        g.stroke(arch, with: .color(Self.c((0.82, 0.52, 0.28))), lineWidth: max(1, s * 0.06))
        // The cone roof under snow, and the stack.
        let cone = Path { p in
            p.move(to: CGPoint(x: body.minX - s * 0.12, y: body.minY + s * 0.08))
            p.addQuadCurve(to: CGPoint(x: body.maxX + s * 0.12, y: body.minY + s * 0.08), control: CGPoint(x: foot.x, y: body.minY + s * 0.26))
            p.addLine(to: CGPoint(x: foot.x + s * 0.22, y: body.minY - s * 0.56))
            p.addLine(to: CGPoint(x: foot.x - s * 0.22, y: body.minY - s * 0.56))
            p.closeSubpath()
        }
        g.fill(cone, with: .linearGradient(Gradient(colors: [Self.c((0.52, 0.54, 0.62)), Self.c((0.26, 0.27, 0.33))]), startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0)))
        g.fill(Path { p in
            p.move(to: CGPoint(x: body.minX - s * 0.06, y: body.minY + s * 0.02))
            p.addQuadCurve(to: CGPoint(x: foot.x - s * 0.1, y: body.minY - s * 0.4), control: CGPoint(x: body.minX + s * 0.14, y: body.minY - s * 0.26))
            p.addLine(to: CGPoint(x: foot.x + s * 0.18, y: body.minY - s * 0.34))
            p.addQuadCurve(to: CGPoint(x: body.maxX - s * 0.2, y: body.minY - s * 0.02), control: CGPoint(x: foot.x + s * 0.12, y: body.minY - s * 0.1))
            p.closeSubpath()
        }, with: .color(.white))
        let stack = CGRect(x: foot.x - s * 0.17, y: body.minY - s * 1.3, width: s * 0.34, height: s * 0.8)
        g.fill(Path(stack), with: .linearGradient(Gradient(colors: [Self.c((0.44, 0.44, 0.52)), Self.c((0.22, 0.22, 0.28))]), startPoint: CGPoint(x: stack.minX, y: 0), endPoint: CGPoint(x: stack.maxX, y: 0)))
        g.fill(Path(roundedRect: CGRect(x: stack.minX - s * 0.06, y: stack.minY - s * 0.06, width: stack.width + s * 0.12, height: s * 0.14), cornerRadius: s * 0.05), with: .color(Self.c((0.8, 0.5, 0.26))))
        if lit {
            g.fill(Path(ellipseIn: CGRect(x: stack.minX, y: stack.minY - s * 0.06, width: stack.width, height: s * 0.1)), with: .color(Color(red: 1, green: 0.62, blue: 0.2).opacity(flicker)))
            // Smoke rolling up and away — sideways in the storm — steam from the vents, sparks.
            let wind = storm ? 3.0 : 1
            var smoke = [Path](repeating: Path(), count: 3)
            for k in 0..<10 {
                let t = (now * 0.2 + Double(k) / 10).truncatingRemainder(dividingBy: 1)
                let q = CGPoint(x: foot.x + CGFloat(t * t * wind) * s * 2.2 + CGFloat(sin(now * 0.7 + Double(k))) * s * 0.1, y: stack.minY - s * 0.1 - CGFloat(t) * s * 2.6)
                let rr = s * CGFloat(0.16 + t * 0.5)
                smoke[min(2, Int(t * 3))].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr * 0.85, width: 2 * rr, height: 1.7 * rr))
            }
            for (k, path) in smoke.enumerated() { g.fill(path, with: .color(Color(white: 0.7 + 0.1 * Double(k)).opacity(0.55 - 0.15 * Double(k)))) }
            var sparks = Path()
            for k in 0..<6 {
                let t = (now * 0.9 + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
                let q = CGPoint(x: foot.x + CGFloat(sin(Double(k) * 2.3 + now)) * s * 0.25, y: stack.minY - CGFloat(t) * s * 1.2)
                sparks.addEllipse(in: CGRect(x: q.x - s * 0.03, y: q.y - s * 0.03, width: s * 0.06, height: s * 0.06))
            }
            g.fill(sparks, with: .color(Color(red: 1, green: 0.8, blue: 0.3).opacity(0.9)))
            if level >= 3 {
                var steam = Path()
                for side in [-1.0, 1.0] as [CGFloat] {
                    let vent = CGPoint(x: foot.x + side * s * 0.84, y: body.minY + s * 0.5)
                    g.fill(Path(roundedRect: CGRect(x: vent.x - s * 0.08, y: vent.y - s * 0.06, width: s * 0.16, height: s * 0.28), cornerRadius: s * 0.04), with: .color(Self.c((0.66, 0.42, 0.24))))
                    for k in 0..<3 {
                        let t = (now * 0.5 + Double(k) / 3 + (side > 0 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                        let q = CGPoint(x: vent.x + side * CGFloat(t) * s * 0.4, y: vent.y - s * 0.1 - CGFloat(t) * s * 0.45)
                        let rr = s * CGFloat(0.06 + t * 0.16)
                        steam.addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr))
                    }
                }
                g.fill(steam, with: .color(.white.opacity(0.5)))
            }
        } else if S > 10 {
            JevDraw.text(g, "熄灭了", at: CGPoint(x: foot.x, y: stack.minY - s * 0.35), size: max(11, S * 0.4), colour: Color(red: 0.7, green: 0.85, blue: 1))
        }
        // Lanterns on posts at the plaza's corners, and the level badge.
        for dx in [-1.0, 1.0] as [CGFloat] {
            let post = CGPoint(x: foot.x + dx * s * 1.55, y: foot.y + s * 0.1)
            g.stroke(Path { p in p.move(to: post); p.addLine(to: CGPoint(x: post.x, y: post.y - s * 0.9)) }, with: .color(Self.c(Self.timber)), lineWidth: max(1, s * 0.05))
            lantern(&g, CGPoint(x: post.x, y: post.y - s * 0.86), S: s * 1.2, lit: lit)
        }
        if b.upgrading {
            let c = IceCity.upgradeCost(to: b.level + 1)
            let need = c[1] + c[3] + c[4]
            let brought = need > 0 ? (b.delivered[1] + b.delivered[3] + b.delivered[4]) / need : 1
            Art.bar(&g, CGRect(x: foot.x - s * 0.8, y: stack.minY - s * 0.5, width: s * 1.6, height: max(3, S * 0.12)), brought < 0.999 ? brought : b.progress,
                    colour: brought < 0.999 ? Color(red: 0.55, green: 0.72, blue: 1) : Color(red: 0.98, green: 0.78, blue: 0.2))
            if S > 12 { JevDraw.text(g, "升级中 → \(b.level + 1) 级", at: CGPoint(x: foot.x, y: stack.minY - s * 0.8), size: max(10, S * 0.3), colour: Color(red: 1, green: 0.92, blue: 0.7)) }
        }
        badge(&g, CGPoint(x: foot.x, y: foot.y + s * 0.2), level, S: S)
    }

    private func badge(_ g: inout GraphicsContext, _ p: CGPoint, _ level: Int, S: CGFloat) {
        let d = max(3.5, S * 0.14)
        let w = CGFloat(level) * d * 1.5 + d
        let r = CGRect(x: p.x - w / 2, y: p.y - d, width: w, height: d * 2)
        g.fill(Path(roundedRect: r, cornerRadius: d), with: .color(Color(red: 0.14, green: 0.2, blue: 0.34).opacity(0.85)))
        var pips = Path()
        for k in 0..<level { pips.addEllipse(in: CGRect(x: r.minX + d * 0.5 + CGFloat(k) * d * 1.5 + d * 0.1, y: r.midY - d * 0.5, width: d, height: d)) }
        g.fill(pips, with: .color(Self.c(Self.gold)))
    }

    /// A soft blue shadow thrown to the lower right on the snow.
    private func softShadow(_ g: inout GraphicsContext, _ F: CGRect, _ S: CGFloat, strength: Double = 0.2) {
        g.fill(Path(ellipseIn: CGRect(x: F.minX + S * 0.25, y: F.maxY - S * 0.55, width: F.width + S * 0.1, height: S * 0.62)), with: .color(Color(red: 0.36, green: 0.46, blue: 0.66).opacity(strength)))
    }

    private func workersAt(_ b: IceBuilding) -> Int { city.people.reduce(0) { $0 + ($1.job == b.id ? 1 : 0) } }

    // MARK: People in fur

    private func person(_ g: inout GraphicsContext, _ p: IcePerson, _ S: CGFloat) {
        let foot = CGPoint(x: CGFloat(p.x) * S, y: CGFloat(p.y) * S)
        let job = p.job.flatMap { city.building($0) }?.kind
        let walking = !p.path.isEmpty
        let working = !walking && p.swung < 0.5 && p.amount == 0 && !p.kid
        var coat = Self.coats[p.coat % Self.coats.count]
        if p.sick { coat = Art.mix(coat, (0.7, 0.76, 0.86), 0.5) }
        var tool: Int
        switch job {
        case .lumber?: tool = 1
        case .coalMine?, .ironMine?, .quarry?: tool = 2
        case .fishery?: tool = 3
        case .hunter?: tool = 4
        default: tool = 0
        }
        if case .build = p.task { tool = 2 }
        chibi(&g, foot: foot, h: S * (p.kid ? 0.5 : 0.66), coat: coat, fur: (0.98, 0.97, 0.94), facing: p.facing, walking: walking, phase: now * 9 + Double(p.id),
              carry: p.amount > 0 ? p.carrying : nil, swing: working ? p.swung : nil, tool: tool, seed: p.id, pale: p.sick, S: S)
    }

    /// A little round person in a puffy coat and a fur hat, big head, rosy cheeks.
    private func chibi(_ g: inout GraphicsContext, foot: CGPoint, h: CGFloat, coat: RGB, fur: RGB, facing: Double, walking: Bool, phase: Double,
                       carry: IceGood?, swing: Double?, tool: Int, seed: Int, pale: Bool, S: CGFloat) {
        let f = CGFloat(facing >= 0 ? 1 : -1)
        let bob = walking ? CGFloat(abs(sin(phase))) * h * 0.05 : 0
        g.fill(Path(ellipseIn: CGRect(x: foot.x - h * 0.3, y: foot.y - h * 0.08, width: h * 0.64, height: h * 0.16)), with: .color(Color(red: 0.3, green: 0.38, blue: 0.56).opacity(0.25)))
        // Boots stepping.
        let step = walking ? CGFloat(sin(phase)) * h * 0.1 : 0
        var boots = Path()
        boots.addEllipse(in: CGRect(x: foot.x - h * 0.2 + step, y: foot.y - h * 0.1, width: h * 0.18, height: h * 0.12))
        boots.addEllipse(in: CGRect(x: foot.x + h * 0.02 - step, y: foot.y - h * 0.1, width: h * 0.18, height: h * 0.12))
        g.fill(boots, with: .color(Self.c((0.34, 0.24, 0.2))))
        // The puffy coat.
        let body = CGRect(x: foot.x - h * 0.27, y: foot.y - h * 0.62 - bob, width: h * 0.54, height: h * 0.56)
        g.fill(Path(roundedRect: body, cornerRadius: h * 0.22), with: .color(Self.c(coat)))
        g.fill(Path(roundedRect: CGRect(x: body.minX + h * 0.04, y: body.minY + h * 0.06, width: body.width * 0.4, height: body.height * 0.7), cornerRadius: h * 0.14), with: .color(Self.c(Art.lit(coat, 1.18))))
        g.fill(Path(roundedRect: CGRect(x: body.minX - h * 0.02, y: body.maxY - h * 0.12, width: body.width + h * 0.04, height: h * 0.13), cornerRadius: h * 0.06), with: .color(Self.c(fur)))
        if S > 16 { g.fill(Path(CGRect(x: foot.x - h * 0.02, y: body.minY + h * 0.14, width: h * 0.04, height: body.height - h * 0.26)), with: .color(Self.c(Art.lit(coat, 0.72)))) }
        // A tool swung, or arms at rest.
        if let swing {
            let a = -Double.pi / 2 - Double(f) * (0.5 - swing * 2.6)
            let shoulder = CGPoint(x: foot.x + f * h * 0.16, y: body.minY + h * 0.16)
            let hand = CGPoint(x: shoulder.x + CGFloat(cos(a)) * h * 0.22, y: shoulder.y + CGFloat(sin(a)) * h * 0.22)
            let head = CGPoint(x: hand.x + CGFloat(cos(a)) * h * 0.3, y: hand.y + CGFloat(sin(a)) * h * 0.3)
            g.stroke(Path { p in p.move(to: shoulder); p.addLine(to: hand) }, with: .color(Self.c(coat)), style: StrokeStyle(lineWidth: max(1, h * 0.12), lineCap: .round))
            if tool == 3 {
                // A fishing rod over the hole, its line bobbing.
                let tip = CGPoint(x: hand.x + f * h * 0.5, y: hand.y - h * 0.2)
                g.stroke(Path { p in p.move(to: hand); p.addLine(to: tip); p.addLine(to: CGPoint(x: tip.x, y: foot.y + CGFloat(sin(phase * 0.3)) * h * 0.04)) }, with: .color(Self.c((0.4, 0.3, 0.2))), lineWidth: max(0.5, h * 0.03))
            } else if tool != 0 {
                g.stroke(Path { p in p.move(to: hand); p.addLine(to: head) }, with: .color(Self.c((0.5, 0.36, 0.22))), style: StrokeStyle(lineWidth: max(0.8, h * 0.06), lineCap: .round))
                g.fill(Path(ellipseIn: CGRect(x: head.x - h * 0.09, y: head.y - h * 0.06, width: h * 0.18, height: h * 0.12)), with: .color(Self.c(tool == 4 ? (0.5, 0.36, 0.22) : (0.66, 0.68, 0.74))))
            }
        }
        // What is carried, on the back.
        if let carry {
            let at = CGPoint(x: foot.x - f * h * 0.2, y: body.minY + h * 0.12)
            switch carry {
            case .wood:
                var logs = Path()
                for k in 0..<2 { logs.addRoundedRect(in: CGRect(x: at.x - h * 0.28, y: at.y - h * 0.12 - CGFloat(k) * h * 0.1, width: h * 0.56, height: h * 0.1), cornerSize: CGSize(width: h * 0.04, height: h * 0.04)) }
                g.fill(logs, with: .color(Self.c((0.58, 0.4, 0.22))))
            case .coal:
                g.fill(Path(roundedRect: CGRect(x: at.x - h * 0.16, y: at.y - h * 0.18, width: h * 0.32, height: h * 0.3), cornerRadius: h * 0.1), with: .color(Self.c((0.18, 0.18, 0.2))))
            case .food:
                g.fill(Path(ellipseIn: CGRect(x: at.x - h * 0.17, y: at.y - h * 0.14, width: h * 0.34, height: h * 0.22)), with: .color(Self.c((0.72, 0.54, 0.3))))
                g.fill(Path(ellipseIn: CGRect(x: at.x - h * 0.12, y: at.y - h * 0.2, width: h * 0.22, height: h * 0.1)), with: .color(Self.c((0.74, 0.8, 0.88))))
            case .stone:
                g.fill(Path(roundedRect: CGRect(x: at.x - h * 0.14, y: at.y - h * 0.16, width: h * 0.28, height: h * 0.22), cornerRadius: h * 0.04), with: .color(Self.c((0.78, 0.78, 0.8))))
            case .iron:
                g.fill(Path(roundedRect: CGRect(x: at.x - h * 0.16, y: at.y - h * 0.12, width: h * 0.32, height: h * 0.14), cornerRadius: h * 0.03), with: .color(Self.c((0.4, 0.34, 0.34))))
            }
        }
        // The head: a round face in a fur hat.
        let r = h * 0.25
        let head = CGPoint(x: foot.x + f * h * 0.02, y: body.minY - r * 0.55)
        g.fill(Path(ellipseIn: CGRect(x: head.x - r * 1.12, y: head.y - r * 1.1, width: r * 2.24, height: r * 2.1)), with: .color(Self.c(fur)))
        g.fill(Path(ellipseIn: CGRect(x: head.x - r * 0.8, y: head.y - r * 0.62, width: r * 1.6, height: r * 1.5)), with: .color(pale ? Self.c((0.92, 0.9, 0.94)) : Self.c(Art.skin[seed % 4])))
        // The hat's crown in the coat's colour, over the fur rim.
        g.fill(Path { p in p.move(to: CGPoint(x: head.x - r * 0.95, y: head.y - r * 0.35)); p.addQuadCurve(to: CGPoint(x: head.x + r * 0.95, y: head.y - r * 0.35), control: CGPoint(x: head.x, y: head.y - r * 1.9)); p.closeSubpath() },
               with: .color(Self.c(Art.lit(coat, 0.82))))
        g.fill(Path(roundedRect: CGRect(x: head.x - r * 1.0, y: head.y - r * 0.5, width: r * 2, height: r * 0.34), cornerRadius: r * 0.17), with: .color(Self.c(fur)))
        if S > 13 {
            var eyes = Path()
            eyes.addEllipse(in: CGRect(x: head.x - r * 0.38 + f * r * 0.12, y: head.y - r * 0.02, width: r * 0.2, height: r * 0.26))
            eyes.addEllipse(in: CGRect(x: head.x + r * 0.16 + f * r * 0.12, y: head.y - r * 0.02, width: r * 0.2, height: r * 0.26))
            g.fill(eyes, with: .color(Self.c((0.14, 0.1, 0.1))))
            if S > 22 {
                var cheeks = Path()
                cheeks.addEllipse(in: CGRect(x: head.x - r * 0.6, y: head.y + r * 0.28, width: r * 0.28, height: r * 0.16))
                cheeks.addEllipse(in: CGRect(x: head.x + r * 0.34, y: head.y + r * 0.28, width: r * 0.28, height: r * 0.16))
                g.fill(cheeks, with: .color(Color(red: 1, green: 0.5, blue: 0.52).opacity(0.55)))
            }
        }
        if pale, S > 14 { g.draw(Text("🤒").font(.system(size: h * 0.36)), at: CGPoint(x: head.x + r * 1.3, y: head.y - r * 1.2)) }
    }

    /// A soldier of 蜀 (or the raiders' colours): fur-trimmed armour, a helmet with a tassel, a spear, a little banner on the back.
    private func soldier(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, seed: Int, team: RGB, spear: Bool, walking: Bool, facing: Double) {
        let h = S * 0.66, f = CGFloat(facing >= 0 ? 1 : -1)
        if seed % 3 == 0 {
            // A back banner.
            let pole = CGPoint(x: foot.x - f * h * 0.18, y: foot.y - h * 0.5)
            g.stroke(Path { p in p.move(to: pole); p.addLine(to: CGPoint(x: pole.x, y: pole.y - h * 0.95)) }, with: .color(Self.c((0.36, 0.26, 0.18))), lineWidth: max(0.6, h * 0.04))
            g.fill(Path(CGRect(x: pole.x - (f > 0 ? h * 0.3 : 0), y: pole.y - h * 0.92, width: h * 0.3, height: h * 0.4)), with: .color(Self.c(team)))
        }
        chibi(&g, foot: foot, h: h, coat: team, fur: (0.96, 0.95, 0.92), facing: facing, walking: walking, phase: now * 10 + Double(seed), carry: nil, swing: nil, tool: 0, seed: seed, pale: false, S: S)
        // The helmet over the fur hat, with its red tassel.
        let r = h * 0.25, head = CGPoint(x: foot.x + f * h * 0.02, y: foot.y - h * 0.62 - r * 0.55)
        g.fill(Path { p in p.move(to: CGPoint(x: head.x - r * 1.0, y: head.y - r * 0.4)); p.addQuadCurve(to: CGPoint(x: head.x + r * 1.0, y: head.y - r * 0.4), control: CGPoint(x: head.x, y: head.y - r * 2.0)); p.closeSubpath() },
               with: .color(Self.c((0.7, 0.72, 0.78))))
        g.fill(Path(ellipseIn: CGRect(x: head.x - r * 0.18, y: head.y - r * 1.55, width: r * 0.36, height: r * 0.36)), with: .color(Self.c((0.9, 0.2, 0.16))))
        if spear {
            let hand = CGPoint(x: foot.x + f * h * 0.3, y: foot.y - h * 0.36)
            g.stroke(Path { p in p.move(to: CGPoint(x: hand.x, y: foot.y)); p.addLine(to: CGPoint(x: hand.x, y: foot.y - h * 1.5)) }, with: .color(Self.c((0.5, 0.36, 0.22))), lineWidth: max(0.8, h * 0.05))
            g.fill(Path { p in p.move(to: CGPoint(x: hand.x, y: foot.y - h * 1.72)); p.addLine(to: CGPoint(x: hand.x + h * 0.06, y: foot.y - h * 1.5)); p.addLine(to: CGPoint(x: hand.x - h * 0.06, y: foot.y - h * 1.5)); p.closeSubpath() }, with: .color(Self.c((0.86, 0.88, 0.92))))
            g.fill(Path(ellipseIn: CGRect(x: hand.x - h * 0.06, y: foot.y - h * 1.52, width: h * 0.12, height: h * 0.08)), with: .color(Self.c((0.9, 0.2, 0.16))))
        }
    }

    /// A general by the building they govern: a bigger figure in their own colours, with their name.
    private func general(_ g: inout GraphicsContext, _ h: Int, _ foot: CGPoint, _ S: CGFloat) {
        let o = iceOfficers[h]
        chibi(&g, foot: foot, h: S * 0.84, coat: o.coat, fur: o.fur, facing: 1, walking: false, phase: 0, carry: nil, swing: nil, tool: 0, seed: h, pale: false, S: S)
        let r = S * 0.84 * 0.25, head = CGPoint(x: foot.x + S * 0.84 * 0.02, y: foot.y - S * 0.84 * 0.62 - r * 0.55)
        switch o.mark {
        case 1: g.stroke(Path { p in for s in [-1.0, 1.0] as [CGFloat] { p.move(to: CGPoint(x: head.x + s * r * 0.3, y: head.y - r * 0.9)); p.addQuadCurve(to: CGPoint(x: head.x + s * r * 1.4, y: head.y - r * 2.4), control: CGPoint(x: head.x + s * r * 0.2, y: head.y - r * 2.4)) } },
                         with: .color(Self.c((0.95, 0.7, 0.2))), style: StrokeStyle(lineWidth: max(1, r * 0.2), lineCap: .round))
        case 3, 6, 7: g.fill(Path { p in p.move(to: CGPoint(x: head.x - r * 0.5, y: head.y + r * 0.35)); p.addQuadCurve(to: CGPoint(x: head.x + r * 0.5, y: head.y + r * 0.35), control: CGPoint(x: head.x, y: head.y + r * (o.mark == 3 ? 1.9 : 1.2))); p.closeSubpath() },
                              with: .color(o.mark == 7 ? .white : Self.c(o.hair)))
        case 5: g.fill(Path(ellipseIn: CGRect(x: head.x + r * 0.1, y: head.y - r * 1.9, width: r * 0.8, height: r * 0.5)), with: .color(Self.c((0.88, 0.2, 0.18))))
        case 8: g.fill(Path { p in let b = head.y - r * 0.9; p.move(to: CGPoint(x: head.x - r * 0.5, y: b)); p.addLine(to: CGPoint(x: head.x - r * 0.5, y: b - r * 0.5)); p.addLine(to: CGPoint(x: head.x, y: b - r * 0.2)); p.addLine(to: CGPoint(x: head.x + r * 0.5, y: b - r * 0.5)); p.addLine(to: CGPoint(x: head.x + r * 0.5, y: b)); p.closeSubpath() }, with: .color(Self.c(o.accent)))
        case 4: g.fill(Path(ellipseIn: CGRect(x: head.x + r * 0.6, y: head.y - r * 1.0, width: r * 0.5, height: r * 0.5)), with: .color(Self.c(o.accent)))
        case 2: g.fill(Path(ellipseIn: CGRect(x: foot.x + S * 0.3, y: foot.y - S * 0.7, width: S * 0.24, height: S * 0.34)), with: .color(.white))
        default: break
        }
        if S > 12 {
            let tag = CGRect(x: foot.x - S * 0.4, y: foot.y - S * 1.22, width: S * 0.8, height: S * 0.26)
            g.fill(Path(roundedRect: tag, cornerRadius: S * 0.13), with: .color(Self.c(Art.lit(o.coat, 0.6), 0.9)))
            g.draw(Text(o.name).font(.system(size: S * 0.18, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: tag.midX, y: tag.midY))
        }
    }

    // MARK: Who stands where, besides the workers

    /// Soldiers drilling in front of the barracks (or by the furnace before there is one), and two at the gate of each wall.
    private func soldiers() -> [(CGPoint, Bool)] {
        var out: [(CGPoint, Bool)] = []
        let S: CGFloat = 1
        let n = min(12, city.soldiers)
        let barracks = city.buildings.filter { $0.kind == .barracks && $0.done }
        if let b = barracks.first {
            let c = city.centre(b)
            for k in 0..<n {
                let row = k / 4, col = k % 4
                out.append((CGPoint(x: (CGFloat(c.x) - 1.1 + CGFloat(col) * 0.72 + CGFloat(row % 2) * 0.3) * S, y: (CGFloat(b.y + b.kind.size) + 0.55 + CGFloat(row) * 0.55) * S), true))
            }
        } else if let f = city.furnace {
            for k in 0..<min(4, n) {
                out.append((CGPoint(x: CGFloat(f.x) - 0.6 + CGFloat(k % 2) * 4.2, y: CGFloat(f.y) + 3.6 + CGFloat(k / 2) * 0.1), true))
            }
        }
        return out
    }

    /// Generals at home, standing by what they govern — or by the furnace.
    private func generals() -> [(Int, CGPoint)] {
        var out: [(Int, CGPoint)] = []
        for (k, hired) in city.officers.enumerated() where !hired.away {
            if let id = hired.governs, let b = city.building(id) {
                out.append((hired.officer, CGPoint(x: CGFloat(b.x) - 0.2, y: CGFloat(b.y + b.kind.size) + 0.1)))
            } else if let f = city.furnace {
                out.append((hired.officer, CGPoint(x: CGFloat(f.x) + 3.8 + CGFloat(k % 3) * 0.7, y: CGFloat(f.y) + 3.2 + CGFloat(k / 3) * 0.6)))
            }
        }
        return out
    }

    /// Raiders coming in from the east edge toward the city, clashing at the wall, then fleeing or looting.
    private func raiders() -> [(at: CGPoint, side: Int, seed: Int, fleeing: Bool)] {
        var out: [(at: CGPoint, side: Int, seed: Int, fleeing: Bool)] = []
        let h = city.hub
        for raid in city.raids {
            let age = city.time - raid.time
            guard age >= 0, age < 12 else { continue }
            let from = CGPoint(x: Double(raid.from.x) + 0.5, y: Double(raid.from.y) + 0.5)
            let to = CGPoint(x: h.x + 9, y: h.y + (Double(raid.from.y) - h.y) * 0.3)
            let t: CGFloat, fleeing: Bool
            if age < 5 { t = CGFloat(age / 5); fleeing = false }
            else if age < 7 { t = 1; fleeing = false }
            else { t = CGFloat(max(0, 1 - (age - 7) / 5)); fleeing = true }
            let n = min(10, max(4, raid.raiders / 5))
            for k in 0..<n {
                let jitter = CGPoint(x: CGFloat(k % 3) * 0.6 + CGFloat(Art.hash(k, raid.rival) % 10) * 0.03, y: CGFloat(k / 3) * 0.55 - 0.8)
                out.append((CGPoint(x: from.x + (to.x - from.x) * t + jitter.x, y: from.y + (to.y - from.y) * t + jitter.y), raid.rival, k + 7, fleeing))
            }
        }
        return out
    }

    /// A column of soldiers marching out to the east edge after an expedition sets off, and back in on its last day home.
    private func marchers() -> [(at: CGPoint, seed: Int, facing: Double)] {
        var out: [(at: CGPoint, seed: Int, facing: Double)] = []
        let h = city.hub
        let start = city.buildings.first { $0.kind == .barracks && $0.done }.map { city.centre($0) } ?? (x: h.x, y: h.y + 3)
        let edge = CGPoint(x: Double(IceCity.width) + 1, y: start.y)
        for e in city.expeditions {
            var t: Double?
            var facing = 1.0
            if !e.back, city.time - e.since < 8 { t = (city.time - e.since) / 8 }
            if e.back, e.left <= 1 { t = 1 - min(1, (city.day - Double(city.today))); facing = -1 }
            guard let t else { continue }
            let n = min(8, max(3, e.soldiers / 4))
            for k in 0..<n {
                let lag = Double(k) * 0.9
                let x = start.x + (edge.x - start.x) * t - lag * (facing > 0 ? 1 : -1) * 0.6
                guard x < Double(IceCity.width) + 0.5, x > start.x - 1 else { continue }
                out.append((CGPoint(x: x, y: start.y + 0.6 + Double(k % 2) * 0.4), k + 30, facing))
            }
        }
        return out
    }

    // MARK: What happened a moment ago

    private func moments(_ g: inout GraphicsContext, _ S: CGFloat) {
        var tributes = 0
        for e in city.moments.reversed() {
            let age = city.time - e.time
            let at = CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S)
            switch e.kind {
            case .died(let cause) where age < 5:
                JevDraw.text(g, cause == "cold" ? "✝︎ 冻" : cause == "hunger" ? "✝︎ 饿" : "✝︎ 病", at: CGPoint(x: at.x, y: at.y - S * (0.8 + CGFloat(age) * 0.1)), size: max(10, S * 0.42), colour: Color.white.opacity(1 - age / 5))
            case .finished where age < 2, .upgraded where age < 3:
                var stars = Path()
                for k in 0..<10 {
                    let a = Double(k) * 0.628 + age * 2
                    let r = S * CGFloat(0.8 + age * 1.1)
                    let p = CGPoint(x: at.x + CGFloat(cos(a)) * r, y: at.y - S * 0.5 + CGFloat(sin(a)) * r * 0.6)
                    stars.addEllipse(in: CGRect(x: p.x - S * 0.07, y: p.y - S * 0.07, width: S * 0.14, height: S * 0.14))
                }
                g.fill(stars, with: .color(Color(red: 1, green: 0.86, blue: 0.4).opacity(max(0, 1 - age / 2.5))))
                if case .upgraded(let level) = e.kind { JevDraw.text(g, "熔炉 \(level) 级！", at: CGPoint(x: at.x, y: at.y - S * (2.8 + CGFloat(age) * 0.3)), size: max(13, S * 0.6), colour: Color(red: 1, green: 0.9, blue: 0.5).opacity(1 - age / 3)) }
            case .felled where age < 0.9:
                let t = age / 0.9
                g.fill(Path(ellipseIn: CGRect(x: at.x - S * 0.5 * CGFloat(0.5 + t), y: at.y - S * 0.15, width: S * CGFloat(0.5 + t), height: S * 0.3)), with: .color(.white.opacity(0.7 * (1 - t))))
            case .arrived(let n) where age < 6:
                JevDraw.text(g, "新来了 \(n) 人", at: CGPoint(x: at.x, y: at.y - S * (0.5 + CGFloat(age) * 0.2)), size: max(12, S * 0.5), colour: .white.opacity(1 - age / 6))
            case .left(let n) where age < 6:
                JevDraw.text(g, "\(n) 人失望离开", at: CGPoint(x: at.x, y: at.y + S * 2), size: max(12, S * 0.46), colour: Color(red: 1, green: 0.8, blue: 0.7).opacity(1 - age / 6))
            case .sick where age < 3:
                JevDraw.text(g, "🤒", at: CGPoint(x: at.x, y: at.y - S * (1 + CGFloat(age) * 0.2)), size: max(10, S * 0.4), shadow: false)
            case .cured where age < 3:
                JevDraw.text(g, "病好了", at: CGPoint(x: at.x, y: at.y - S * (1 + CGFloat(age) * 0.2)), size: max(10, S * 0.36), colour: Color(red: 0.7, green: 1, blue: 0.75).opacity(1 - age / 3))
            case .tribute(let good, let n, let name) where age < 4 && tributes < 3:
                JevDraw.text(g, "\(name) 送来 \(good.name) +\(n)", at: CGPoint(x: at.x + S * 3, y: at.y - S * (3 + CGFloat(tributes) * 0.6 + CGFloat(age) * 0.2)), size: max(11, S * 0.38), colour: Color(red: 1, green: 0.95, blue: 0.75).opacity(1 - age / 4))
                tributes += 1
            default: break
            }
        }
    }

    // MARK: The weather, over the part in view

    private func weather(_ g: inout GraphicsContext, _ S: CGFloat, _ view: CGRect) {
        let area = CGRect(x: view.minX * S, y: view.minY * S, width: view.width * S, height: view.height * S)
        let storm = storminess
        let cold = max(0, min(1, (-city.temperature - 12) / 30))
        // The cold's blue tint deepening through the winter, heavier in the storm.
        if storm > 0 { g.fill(Path(area), with: .color(Color(red: 0.62, green: 0.76, blue: 1).opacity(0.1 * cold + 0.4 * storm))) }
        var sky = g
        sky.translateBy(x: area.minX, y: area.minY)
        let size = area.size
        let n = Int(Double(size.width * size.height) / (storm > 0 ? 1500 : 7000))
        var small = Path(), big = Path(), streaks = Path()
        for k in 0..<n {
            let speed = (storm > 0 ? 110 : 26) + Art.unit(k, 22) * (storm > 0 ? 80 : 22)
            let drift = storm > 0 ? 190.0 : 9.0
            let y = (Art.unit(k, 23) * Double(size.height) + now * speed).truncatingRemainder(dividingBy: Double(size.height))
            let x = (Art.unit(k, 21) * Double(size.width + 300) + now * drift + sin(now * 0.8 + Double(k)) * 7).truncatingRemainder(dividingBy: Double(size.width + 300)) - 150
            if storm > 0, k % 2 == 0 {
                streaks.move(to: CGPoint(x: x, y: y)); streaks.addLine(to: CGPoint(x: x - 30, y: y - 12))
            } else if Art.unit(k, 24) > 0.8 {
                big.move(to: CGPoint(x: x, y: y)); big.addLine(to: CGPoint(x: x + 0.01, y: y))
            } else {
                small.move(to: CGPoint(x: x, y: y)); small.addLine(to: CGPoint(x: x + 0.01, y: y))
            }
        }
        if storm > 0 {
            if let gust = IceGustSprite.gust {
                for k in 0..<3 {
                    let f = (now * 0.18 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    let x = CGFloat(-0.4 + f * 1.8) * size.width, y = size.height * (0.2 + 0.3 * CGFloat(k)) + CGFloat(f) * 60
                    var gg = sky
                    gg.opacity = storm
                    gg.draw(Image(decorative: gust, scale: 1), in: CGRect(x: x - size.width * 0.35, y: y - 70, width: size.width * 0.7, height: 140))
                }
            }
            sky.stroke(streaks, with: .color(.white.opacity(0.9 * storm)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        sky.stroke(small, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        sky.stroke(big, with: .color(.white), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
    }

    // MARK: The mouse: the building chosen, the one about to go down, the road or wall being drawn

    private func mouse(_ g: inout GraphicsContext, _ S: CGFloat) {
        func rect(_ x: Int, _ y: Int, _ n: Int = 1) -> CGRect { CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: CGFloat(n) * S, height: CGFloat(n) * S) }
        if let id = selected, let b = city.building(id) {
            let r = rect(b.x, b.y, b.kind.size)
            g.stroke(Path(roundedRect: r.insetBy(dx: -2, dy: -2), cornerRadius: S * 0.2), with: .color(.yellow), lineWidth: 2)
            if [.lumber, .hunter, .fishery].contains(b.kind) { reach(&g, CGPoint(x: r.midX, y: r.midY), S, b.kind == .fishery ? IceCity.fishReach : IceCity.reach) }
        }
        if let kind = placing, let hover {
            let n = kind.size, o = IceTile(x: hover.x - (n - 1) / 2, y: hover.y - (n - 1) / 2)
            let ok = city.fits(kind, at: o), r = rect(o.x, o.y, n)
            var ghost = g
            ghost.opacity = 0.6
            building(&ghost, IceBuilding(id: -1, kind: kind, x: o.x, y: o.y, done: true), S)
            g.fill(Path(roundedRect: r, cornerRadius: S * 0.2), with: .color((ok ? Color.green : Color.red).opacity(0.22)))
            g.stroke(Path(roundedRect: r, cornerRadius: S * 0.2), with: .color(ok ? .green : .red), lineWidth: 1.5)
            if [.lumber, .hunter, .fishery].contains(kind) { reach(&g, CGPoint(x: r.midX, y: r.midY), S, kind == .fishery ? IceCity.fishReach : IceCity.reach) }
        }
        if tool == .road || tool == .wall {
            for t in IceCityScene.line(drag?.0 ?? hover, drag?.1 ?? hover) {
                let ok = tool == .road ? IceCity.inside(t) && city.ground[IceCity.index(t)] == .snow && city.occupant[IceCity.index(t)] == nil : city.canWall(t)
                let colour: Color = ok ? (tool == .road ? Color(red: 0.8, green: 0.74, blue: 0.66) : Color(red: 0.62, green: 0.64, blue: 0.72)) : .red
                g.fill(Path(roundedRect: rect(t.x, t.y).insetBy(dx: S * 0.08, dy: S * 0.08), cornerRadius: S * 0.2), with: .color(colour.opacity(0.75)))
            }
        }
        if tool == .bulldoze, let hover, IceCity.inside(hover) {
            if let id = city.occupant[IceCity.index(hover)], let b = city.building(id), b.kind != .furnace {
                g.fill(Path(roundedRect: rect(b.x, b.y, b.kind.size), cornerRadius: S * 0.2), with: .color(Color.red.opacity(0.35)))
            } else {
                g.stroke(Path(roundedRect: rect(hover.x, hover.y), cornerRadius: S * 0.2), with: .color(.red), lineWidth: 1.5)
            }
        }
    }

    private func reach(_ g: inout GraphicsContext, _ c: CGPoint, _ S: CGFloat, _ tiles: Int) {
        let r = CGFloat(tiles) * S
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color.white.opacity(0.1)))
        g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.3, green: 0.45, blue: 0.7).opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
    }

    /// The tiles of a road or wall dragged from one tile to another: along, then down.
    static func line(_ a: IceTile?, _ b: IceTile?) -> [IceTile] {
        guard let a, let b else { return [] }
        var out: [IceTile] = []
        let sx = b.x >= a.x ? 1 : -1, sy = b.y >= a.y ? 1 : -1
        for x in stride(from: a.x, through: b.x, by: sx) { out.append(IceTile(x: x, y: a.y)) }
        for y in stride(from: a.y + sy, through: b.y, by: sy) where a.y != b.y { out.append(IceTile(x: b.x, y: y)) }
        return out
    }
}

/// Soft light painted once and then only placed: a gust of blown snow.
fileprivate enum IceGustSprite {
    nonisolated(unsafe) static var gust: CGImage? = make([(1, 1, 1, 0.55), (1, 1, 1, 0.18), (1, 1, 1, 0)], [0, 0.5, 1])

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

import SwiftUI

/// A general's chibi portrait: a round face in a fur hood with what marks them
/// out — feathers, a fan, a beard, a flower, a crest, a crown. Drawn from the
/// turn-based 冰河三国's portraits, for the chips along the top of the city.
enum IcePortrait {
    static func c(_ v: Art.RGB, _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }

    /// A general as a round-faced little figure in a fur hood, with what marks them out.
    static func draw(_ g: GraphicsContext, _ hero: IceOfficer, at p: CGPoint, size s: CGFloat, now: Double) {
        let fur = c(hero.fur), furDark = c(Art.lit(hero.fur, 0.82))
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
        g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.7, y: p.y + s * 0.75)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.7, y: p.y + s * 0.75), control: CGPoint(x: p.x, y: p.y + s * 0.35)); q.addLine(to: CGPoint(x: p.x + s * 0.55, y: p.y + s * 0.98)); q.addLine(to: CGPoint(x: p.x - s * 0.55, y: p.y + s * 0.98)); q.closeSubpath() }, with: .color(c(hero.coat)))
        // The face.
        let face = CGRect(x: p.x - s * 0.58, y: p.y - s * 0.52, width: s * 1.16, height: s * 1.1)
        g.fill(Path(ellipseIn: face), with: .color(c(hero.skin)))
        // Hair: a fringe, grey or dark.
        g.fill(Path { q in q.move(to: CGPoint(x: face.minX, y: face.midY - s * 0.05)); q.addQuadCurve(to: CGPoint(x: face.maxX, y: face.midY - s * 0.05), control: CGPoint(x: p.x, y: face.minY - s * 0.45)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.1, y: face.minY + s * 0.28), control: CGPoint(x: face.maxX - s * 0.1, y: face.minY + s * 0.1)); q.addQuadCurve(to: CGPoint(x: face.minX, y: face.midY - s * 0.05), control: CGPoint(x: face.minX + s * 0.2, y: face.minY + s * 0.2)); q.closeSubpath() },
               with: .color(c(hero.hair)))
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
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.3, y: face.minY - s * 0.28, width: s * 0.6, height: s * 0.3), cornerRadius: s * 0.08), with: .color(c(hero.accent)))
            var fan = g; fan.translateBy(x: p.x + s * 0.72, y: p.y + s * 0.45); fan.rotate(by: .radians(-0.5 + 0.1 * sin(now * 2)))
            fan.fill(Path { q in q.move(to: .zero); q.addQuadCurve(to: CGPoint(x: -s * 0.35, y: -s * 0.85), control: CGPoint(x: -s * 0.5, y: -s * 0.3)); q.addQuadCurve(to: CGPoint(x: s * 0.35, y: -s * 0.85), control: CGPoint(x: 0, y: -s * 1.05)); q.addQuadCurve(to: .zero, control: CGPoint(x: s * 0.5, y: -s * 0.3)); q.closeSubpath() }, with: .color(.white))
            fan.stroke(Path { q in for n in -2...2 { q.move(to: .zero); q.addLine(to: CGPoint(x: CGFloat(n) * s * 0.14, y: -s * 0.85)) } }, with: .color(Color(white: 0.75)), lineWidth: s * 0.03)
        case 3:      // a long beard
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.35, y: p.y + s * 0.3)); q.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s * 1.3), control: CGPoint(x: p.x - s * 0.4, y: p.y + s * 1)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.35, y: p.y + s * 0.3), control: CGPoint(x: p.x + s * 0.4, y: p.y + s * 1)); q.closeSubpath() }, with: .color(c(hero.hair)))
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.45, y: face.minY - s * 0.3, width: s * 0.9, height: s * 0.32), cornerRadius: s * 0.1), with: .color(c(hero.coat)))
        case 4:      // a flower in the hood
            let f = CGPoint(x: p.x + s * 0.62, y: p.y - s * 0.55)
            for n in 0..<5 { let a = Double(n) / 5 * 2 * .pi; g.fill(Path(ellipseIn: CGRect(x: f.x + CGFloat(cos(a)) * s * 0.16 - s * 0.13, y: f.y + CGFloat(sin(a)) * s * 0.16 - s * 0.13, width: s * 0.26, height: s * 0.26)), with: .color(c(hero.accent))) }
            g.fill(Path(ellipseIn: CGRect(x: f.x - s * 0.08, y: f.y - s * 0.08, width: s * 0.16, height: s * 0.16)), with: .color(Color(red: 1, green: 0.9, blue: 0.4)))
        case 5:      // a silver helmet with a red plume
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX - s * 0.05, y: face.midY - s * 0.12)); q.addQuadCurve(to: CGPoint(x: face.maxX + s * 0.05, y: face.midY - s * 0.12), control: CGPoint(x: p.x, y: face.minY - s * 0.55)); q.closeSubpath() },
                   with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(red: 0.62, green: 0.68, blue: 0.76)]), startPoint: CGPoint(x: face.minX, y: face.minY), endPoint: CGPoint(x: face.maxX, y: face.midY)))
            g.fill(Path { q in q.move(to: CGPoint(x: p.x, y: face.minY - s * 0.1)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.55, y: face.minY - s * 0.55), control: CGPoint(x: p.x + s * 0.1, y: face.minY - s * 0.6)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.1, y: face.minY), control: CGPoint(x: p.x + s * 0.4, y: face.minY - s * 0.2)); q.closeSubpath() }, with: .color(Color(red: 0.88, green: 0.2, blue: 0.18)))
        case 6, 7:   // a bushy beard, dark or white
            let beard = hero.mark == 7 ? Color(white: 0.96) : c(hero.hair)
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX + s * 0.05, y: p.y + s * 0.2)); q.addQuadCurve(to: CGPoint(x: face.maxX - s * 0.05, y: p.y + s * 0.2), control: CGPoint(x: p.x, y: p.y + s * 1.05)); q.addQuadCurve(to: CGPoint(x: face.minX + s * 0.05, y: p.y + s * 0.2), control: CGPoint(x: p.x, y: p.y + s * 0.5)); q.closeSubpath() }, with: .color(beard))
            if hero.mark == 6 { g.stroke(Path { q in for side in [-1.0, 1.0] as [CGFloat] { q.move(to: CGPoint(x: p.x + side * s * 0.1, y: p.y - s * 0.12)); q.addLine(to: CGPoint(x: p.x + side * s * 0.4, y: p.y - s * 0.2)) } }, with: .color(c(hero.hair)), lineWidth: s * 0.08) }
        case 8:      // a little gold crown
            g.fill(Path { q in let b = face.minY - s * 0.05; q.move(to: CGPoint(x: p.x - s * 0.35, y: b)); q.addLine(to: CGPoint(x: p.x - s * 0.35, y: b - s * 0.3)); q.addLine(to: CGPoint(x: p.x - s * 0.17, y: b - s * 0.15)); q.addLine(to: CGPoint(x: p.x, y: b - s * 0.38)); q.addLine(to: CGPoint(x: p.x + s * 0.17, y: b - s * 0.15)); q.addLine(to: CGPoint(x: p.x + s * 0.35, y: b - s * 0.3)); q.addLine(to: CGPoint(x: p.x + s * 0.35, y: b)); q.closeSubpath() }, with: .color(c(hero.accent)))
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.28, y: p.y + s * 0.32)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.28, y: p.y + s * 0.32), control: CGPoint(x: p.x, y: p.y + s * 0.62)); q.closeSubpath() }, with: .color(c(hero.hair)))
        default:     // a topknot tied with their colour
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.16, y: face.minY - s * 0.3, width: s * 0.32, height: s * 0.3)), with: .color(c(hero.hair)))
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.2, y: face.minY - s * 0.06, width: s * 0.4, height: s * 0.1), cornerRadius: s * 0.05), with: .color(c(hero.accent)))
        }
    }
}

/// What never moves, painted once with CoreGraphics and then only placed: the snowfield with its drifts and
/// sparkle, the darker snow under the pines, the frozen river and lake with their streaks and cracks — and the
/// furnace's warmth as a soft round sprite.
enum IceLand {
    nonisolated(unsafe) static var kept: (key: [UInt64], image: CGImage)?
    nonisolated(unsafe) static var heat: CGImage? = sprite([(1, 0.62, 0.3, 0.38), (1, 0.7, 0.42, 0.2), (1, 0.78, 0.54, 0.1), (1, 0.8, 0.56, 0)], [0, 0.55, 0.92, 1])
    /// Pixels to a tile in the land image.
    static let px: CGFloat = 48

    static func image(_ city: IceCity) -> CGImage? {
        let key: [UInt64] = [city.seed, UInt64(city.landVersion), UInt64(city.level), city.burning ? 1 : 0]
        if let kept, kept.key == key { return kept.image }
        guard let made = paint(city) else { return nil }
        kept = (key, made)
        return made
    }

    static func sprite(_ stops: [(Double, Double, Double, Double)], _ at: [CGFloat]) -> CGImage? {
        let side = 256
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: space, colors: stops.map { CGColor(srgbRed: CGFloat($0.0), green: CGFloat($0.1), blue: CGFloat($0.2), alpha: CGFloat($0.3)) } as CFArray, locations: at) else { return nil }
        let mid = CGPoint(x: side / 2, y: side / 2)
        c.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: CGFloat(side / 2), options: [])
        return c.makeImage()
    }

    private static func rgb(_ v: (Double, Double, Double), _ a: Double = 1) -> CGColor { CGColor(srgbRed: CGFloat(v.0), green: CGFloat(v.1), blue: CGFloat(v.2), alpha: CGFloat(a)) }

    private static func paint(_ city: IceCity) -> CGImage? {
        let W = IceCity.width, H = IceCity.height, S = px
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: Int(CGFloat(W) * S), height: Int(CGFloat(H) * S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // y down, like the map.
        c.translateBy(x: 0, y: CGFloat(H) * S)
        c.scaleBy(x: 1, y: -1)
        func fill(_ path: CGPath, _ colour: CGColor) { c.addPath(path); c.setFillColor(colour); c.fillPath() }
        c.setFillColor(rgb(IceCityScene.snow)); c.fill(CGRect(x: 0, y: 0, width: CGFloat(W) * S, height: CGFloat(H) * S))
        // Drifts: long low swells, lit on the upper edge, shaded under; sparkle.
        let shade = CGMutablePath(), light = CGMutablePath(), woods = CGMutablePath(), sparkle = CGMutablePath()
        var ice: [(Int, Int)] = []
        for y in 0..<H { for x in 0..<W {
            let i = y * W + x, h = Art.hash(x, y)
            switch city.ground[i] {
            case .forest: woods.addRoundedRect(in: CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: S, height: S).insetBy(dx: -S * 0.22, dy: -S * 0.22), cornerWidth: S * 0.55, cornerHeight: S * 0.55)
            case .ice: ice.append((x, y))
            default: break
            }
            if h % 4 == 0 {
                let p = CGPoint(x: (CGFloat(x) + CGFloat(h % 89) / 89) * S, y: (CGFloat(y) + CGFloat(h / 89 % 83) / 83) * S)
                let r = S * CGFloat(0.6 + Double(h % 7) * 0.12)
                shade.move(to: CGPoint(x: p.x - r * 1.3, y: p.y))
                shade.addQuadCurve(to: CGPoint(x: p.x + r * 1.3, y: p.y), control: CGPoint(x: p.x, y: p.y + r * 0.34))
                shade.addQuadCurve(to: CGPoint(x: p.x - r * 1.3, y: p.y), control: CGPoint(x: p.x, y: p.y + r * 0.1))
                light.move(to: CGPoint(x: p.x - r * 1.2, y: p.y - r * 0.05))
                light.addQuadCurve(to: CGPoint(x: p.x + r * 1.1, y: p.y - r * 0.05), control: CGPoint(x: p.x - r * 0.1, y: p.y - r * 0.3))
                light.addQuadCurve(to: CGPoint(x: p.x - r * 1.2, y: p.y - r * 0.05), control: CGPoint(x: p.x, y: p.y - r * 0.08))
            }
            if h % 5 == 1 {
                let p = CGPoint(x: (CGFloat(x) + CGFloat(h % 71) / 71) * S, y: (CGFloat(y) + CGFloat(h / 71 % 67) / 67) * S)
                sparkle.addEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
            }
        } }
        fill(shade, rgb(IceCityScene.snowShade, 0.38))
        fill(light, rgb((1, 1, 1), 0.9))
        fill(woods, rgb(IceCityScene.snowShade, 0.55))
        fill(sparkle, rgb((1, 1, 1), 0.95))
        if !ice.isEmpty { frozen(c, city, ice, S) }
        warmth(c, city, S)
        roads(c, city, S)
        return c.makeImage()
    }

    /// The furnace's glow on the snow as far as its heat reaches, and the paved round of its plaza.
    private static func warmth(_ c: CGContext, _ city: IceCity, _ S: CGFloat) {
        guard let f = city.furnace else { return }
        let m = city.centre(f)
        let centre = CGPoint(x: CGFloat(m.x) * S, y: CGFloat(m.y) * S), R = CGFloat(city.heatRadius) * S
        let lit = city.burning
        if lit, let space = CGColorSpace(name: CGColorSpace.sRGB),
           let glow = CGGradient(colorsSpace: space, colors: [rgb((1, 0.64, 0.34), 0.36), rgb((1, 0.72, 0.44), 0.18), rgb((1, 0.8, 0.56), 0.1), rgb((1, 0.8, 0.56), 0)] as CFArray, locations: [0, 0.55, 0.92, 1]) {
            c.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: R, options: [])
        }
        let pc = CGPoint(x: CGFloat(m.x) * S, y: (CGFloat(m.y) + 0.35) * S)
        let pr = CGFloat(f.kind.size) * S * 0.78
        let plaza = CGRect(x: pc.x - pr, y: pc.y - pr * 0.82, width: 2 * pr, height: 2 * pr * 0.82)
        c.addEllipse(in: plaza.insetBy(dx: -S * 0.12, dy: -S * 0.12)); c.setFillColor(rgb((0.86, 0.84, 0.84), lit ? 0.9 : 0.6)); c.fillPath()
        c.addEllipse(in: plaza); c.setFillColor(rgb(lit ? (0.64, 0.6, 0.6) : (0.7, 0.74, 0.8))); c.fillPath()
        let stones = CGMutablePath()
        for ring in 1...3 {
            let rr = pr * CGFloat(ring) / 3.4
            let count = 6 * ring + 4
            for k in 0..<count {
                let a = Double(k) / Double(count) * 2 * .pi + Double(ring) * 0.3
                let p = CGPoint(x: pc.x + CGFloat(cos(a)) * rr, y: pc.y + CGFloat(sin(a)) * rr * 0.82)
                stones.addRoundedRect(in: CGRect(x: p.x - S * 0.17, y: p.y - S * 0.12, width: S * 0.34, height: S * 0.24), cornerWidth: S * 0.07, cornerHeight: S * 0.07)
            }
        }
        c.addPath(stones); c.setFillColor(rgb(lit ? (0.74, 0.7, 0.68) : (0.8, 0.84, 0.9), 0.9)); c.fillPath()
        if !lit { c.addEllipse(in: plaza); c.setFillColor(rgb((1, 1, 1), 0.35)); c.fillPath() }
    }

    /// Roads of trodden snow over packed earth: one stroke for the rim, one for the way, a lighter middle; ruts.
    private static func roads(_ c: CGContext, _ city: IceCity, _ S: CGFloat) {
        let W = IceCity.width, H = IceCity.height
        func isRoad(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H && city.road[y * W + x] && !plaza(city, x, y) }
        let path = CGMutablePath(), ruts = CGMutablePath()
        var any = false
        for y in 0..<H { for x in 0..<W where isRoad(x, y) {
            any = true
            let p = CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.5) * S)
            path.move(to: p); path.addLine(to: CGPoint(x: p.x + 0.01, y: p.y))
            for (dx, dy) in [(1, 0), (0, 1), (1, 1), (-1, 1)] where isRoad(x + dx, y + dy) {
                if dx != 0, dy != 0, isRoad(x + dx, y) || isRoad(x, y + dy) { continue }
                path.move(to: p); path.addLine(to: CGPoint(x: p.x + CGFloat(dx) * S, y: p.y + CGFloat(dy) * S))
            }
            if Art.hash(x, y) % 2 == 0 {
                let q = CGPoint(x: (CGFloat(x) + 0.25 + CGFloat(Art.hash(x, y) % 40) / 100) * S, y: (CGFloat(y) + 0.3 + CGFloat(Art.hash(y, x) % 40) / 100) * S)
                ruts.addEllipse(in: CGRect(x: q.x, y: q.y, width: S * 0.1, height: S * 0.06))
            }
        } }
        guard any else { return }
        c.setLineCap(.round); c.setLineJoin(.round)
        c.addPath(path); c.setStrokeColor(rgb((0.8, 0.83, 0.9), 0.8)); c.setLineWidth(S * 0.8); c.strokePath()
        c.addPath(path); c.setStrokeColor(rgb((0.78, 0.74, 0.7))); c.setLineWidth(S * 0.56); c.strokePath()
        c.addPath(path); c.setStrokeColor(rgb((0.86, 0.84, 0.83), 0.8)); c.setLineWidth(S * 0.18); c.strokePath()
        c.addPath(ruts); c.setFillColor(rgb((0.62, 0.58, 0.56), 0.7)); c.fillPath()
    }

    /// Is this tile under the furnace's paved round?
    static func plaza(_ city: IceCity, _ x: Int, _ y: Int) -> Bool {
        guard let f = city.furnace else { return false }
        let c = city.centre(f), pr = Double(f.kind.size) * 0.78
        let dx = Double(x) + 0.5 - c.x, dy = (Double(y) + 0.5 - c.y - 0.35) / 0.82
        return hypot(dx, dy) < pr + 0.2
    }

    /// Frozen water as one body: a snowy rim, pale ice, deeper blue in the middle, streaks and cracks.
    private static func frozen(_ c: CGContext, _ city: IceCity, _ ice: [(Int, Int)], _ S: CGFloat) {
        func fill(_ path: CGPath, _ colour: CGColor) { c.addPath(path); c.setFillColor(colour); c.fillPath() }
        func body(_ grow: CGFloat, _ round: CGFloat) -> CGPath {
            let p = CGMutablePath()
            for (x, y) in ice { p.addRoundedRect(in: CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: S, height: S).insetBy(dx: -grow, dy: -grow), cornerWidth: round, cornerHeight: round) }
            return p
        }
        fill(body(S * 0.34, S * 0.62), rgb((0.86, 0.92, 0.98)))
        fill(body(S * 0.16, S * 0.52), rgb((0.66, 0.83, 0.94)))
        func depth(_ x: Int, _ y: Int) -> Int {
            for d in 1...2 { for dy in -d...d { for dx in -d...d where abs(dx) == d || abs(dy) == d {
                let t = IceTile(x: x + dx, y: y + dy)
                if IceCity.inside(t), city.ground[IceCity.index(t)] != .ice { return d }
            } } }
            return 3
        }
        let deep = CGMutablePath(), streaks = CGMutablePath(), cracks = CGMutablePath()
        for (x, y) in ice {
            let h = Art.hash(x + 3, y + 7)
            if depth(x, y) >= 2 {
                let m = CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.5) * S)
                deep.addEllipse(in: CGRect(x: m.x - S * 1.1, y: m.y - S * 0.8, width: S * 2.2, height: S * 1.6))
            }
            if h % 3 == 0 {
                let p = CGPoint(x: (CGFloat(x) + 0.1) * S, y: (CGFloat(y) + 0.3 + CGFloat(h % 5) * 0.1) * S)
                streaks.move(to: p); streaks.addLine(to: CGPoint(x: p.x + S * 0.8, y: p.y - S * 0.12))
            }
            if h % 4 == 1 {
                let p = CGPoint(x: (CGFloat(x) + 0.3) * S, y: (CGFloat(y) + 0.4) * S)
                cracks.move(to: p); cracks.addLine(to: CGPoint(x: p.x + S * 0.25, y: p.y + S * 0.14)); cracks.addLine(to: CGPoint(x: p.x + S * 0.5, y: p.y + S * 0.06))
                cracks.move(to: CGPoint(x: p.x + S * 0.25, y: p.y + S * 0.14)); cracks.addLine(to: CGPoint(x: p.x + S * 0.3, y: p.y + S * 0.34))
            }
        }
        c.saveGState()
        c.addPath(body(S * 0.02, S * 0.3)); c.clip()
        fill(deep, rgb((0.5, 0.72, 0.9), 0.4))
        c.setLineCap(.round)
        c.addPath(streaks); c.setStrokeColor(rgb((1, 1, 1), 0.55)); c.setLineWidth(S * 0.05); c.strokePath()
        c.addPath(cracks); c.setStrokeColor(rgb((1, 1, 1), 0.8)); c.setLineWidth(max(0.8, S * 0.02)); c.strokePath()
        c.restoreGState()
    }
}
