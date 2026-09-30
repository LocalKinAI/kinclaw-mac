import SwiftUI

/// What is on the map at a moment: the painted land and who holds it, the
/// roads with their crossings and passes, each city as a small walled town
/// under its lord's banner, armies marching down the roads behind their
/// flags with a bold arrow ahead of them, and — when a month's battles are
/// being told — smoke and crossed blades over the cities fought for.
struct WarlordScene {
    let world: WarlordWorld
    var selected: Int?
    /// The base layer's inputs: when they are the same, the base need not be drawn again.
    struct Key: Equatable {
        var owners: [Int], troops: [Int], selected: Int?, mine: Int?, lit: [Int]
        var S: CGFloat, origin: CGPoint, size: CGSize
    }
    var hover: Int?
    /// Cities to pick from now: enemy ones (red rings) or our own (green).
    var targets: Set<Int> = []
    var friendly = false
    /// How far this month's march has gone, 0–1.
    var march: Double = 0
    var fights: [WarlordBattle] = []
    var mine: Int?
    var now: Double

    typealias RGB = (Double, Double, Double)
    static func c(_ v: RGB, _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }
    static func colour(_ f: Int) -> RGB { f >= 0 ? warlordBanners[f].colour : warlordNeutralColour }
    static let ink: RGB = (0.2, 0.14, 0.1)
    static let frame: RGB = (0.16, 0.11, 0.08)

    /// Points to a map unit at this zoom, and how big the glyphs are drawn.
    static func glyph(_ S: CGFloat) -> CGFloat { min(1.6, max(0.85, pow(S / 0.75, 0.45))) }

    /// A road as a gentle curve: the same bend every time.
    static func road(_ r: WarlordRoad) -> (CGPoint, CGPoint, CGPoint) {
        let a = WarlordMap.at(r.a), b = WarlordMap.at(r.b)
        let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
        let bend = CGFloat(WarlordWorld.mixHash(r.a, r.b) % 1000) / 1000 - 0.5
        let mid = CGPoint(x: (a.x + b.x) / 2 - dy / max(len, 1) * len * bend * 0.22, y: (a.y + b.y) / 2 + dx / max(len, 1) * len * bend * 0.22)
        return (a, mid, b)
    }
    static func along(_ r: (CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * r.0.x + 2 * u * t * r.1.x + t * t * r.2.x, y: u * u * r.0.y + 2 * u * t * r.1.y + t * t * r.2.y)
    }

    /// Everything at once (for pictures drawn offscreen).
    func paint(_ g: inout GraphicsContext, S: CGFloat, size: CGSize) {
        paintBase(&g, S: S)
        paintLive(&g, S: S)
    }

    /// What changes only when a city changes hands or the camera moves: the paper, the roads, the walled towns, their names.
    func paintBase(_ g: inout GraphicsContext, S: CGFloat, view: CGRect? = nil) {
        let map = CGRect(x: 0, y: 0, width: WarlordMap.width * S, height: WarlordMap.height * S)
        // The lacquered frame round the paper.
        g.fill(Path(map.insetBy(dx: -4000, dy: -4000)), with: .color(Self.c(Self.frame)))
        g.fill(Path(map.insetBy(dx: -9, dy: -9)), with: .color(Self.c((0.5, 0.36, 0.2))))
        g.fill(Path(map.insetBy(dx: -6, dy: -6)), with: .color(Self.c((0.28, 0.19, 0.12))))
        if let land = WarlordLand.map(world.cities.map(\.owner)) {
            // Only the part in view is drawn: at a close zoom that is a small piece of a large picture.
            var shown = map
            if let view { shown = map.intersection(CGRect(x: view.minX * S, y: view.minY * S, width: view.width * S, height: view.height * S).insetBy(dx: -4, dy: -4)) }
            let k = WarlordLand.px / S
            let src = CGRect(x: floor(shown.minX * k), y: floor(shown.minY * k), width: ceil(shown.width * k), height: ceil(shown.height * k))
                .intersection(CGRect(x: 0, y: 0, width: land.width, height: land.height))
            if !src.isEmpty, let piece = land.cropping(to: src) {
                g.draw(Image(decorative: piece, scale: 1).interpolation(.medium), in: CGRect(x: src.minX / k, y: src.minY / k, width: src.width / k, height: src.height / k))
            }
        }
        g.stroke(Path(map.insetBy(dx: -2.5, dy: -2.5)), with: .color(Self.c((0.86, 0.72, 0.42))), lineWidth: 1.5)
        let z = Self.glyph(S)
        roads(&g, S, z)
        for c in Self.order { city(&g, c, S, z) }
        for c in Self.order { label(&g, c, S, z) }
    }

    /// What moves every frame: rings round the chosen city and the ones to pick, the banners, the armies, the battles.
    func paintLive(_ g: inout GraphicsContext, S: CGFloat) {
        let z = Self.glyph(S)
        for c in Self.order { rings(&g, c, S, z) }
        for c in Self.order { banner(&g, c, S, z) }
        armies(&g, S, z)
        for b in fights { battle(&g, b, S, z) }
    }

    static let order = warlordSites.indices.sorted { warlordSites[$0].lat > warlordSites[$1].lat }

    // MARK: Roads

    private func roads(_ g: inout GraphicsContext, _ S: CGFloat, _ z: CGFloat) {
        for r in warlordRoads {
            let k = Self.road(r)
            let p = Path { q in q.move(to: CGPoint(x: k.0.x * S, y: k.0.y * S)); q.addQuadCurve(to: CGPoint(x: k.2.x * S, y: k.2.y * S), control: CGPoint(x: k.1.x * S, y: k.1.y * S)) }
            let lit = targets.contains(r.a) && r.b == selected || targets.contains(r.b) && r.a == selected
            g.stroke(p, with: .color(Self.c((0.98, 0.94, 0.8), lit ? 0.9 : 0.55)), style: StrokeStyle(lineWidth: (lit ? 4.2 : 3) * z, lineCap: .round))
            let ink: RGB = r.kind == .river ? (0.2, 0.36, 0.5) : r.kind == .pass ? (0.42, 0.24, 0.14) : (0.36, 0.26, 0.16)
            g.stroke(p, with: .color(Self.c(ink, lit ? 1 : 0.85)), style: StrokeStyle(lineWidth: (lit ? 2.2 : 1.5) * z, lineCap: .round, dash: r.months > 1 ? [5 * z, 3.5 * z] : [9 * z, 2.5 * z]))
            let m = Self.along(k, 0.5), q = CGPoint(x: m.x * S, y: m.y * S)
            if r.kind == .pass {
                // A little gate across the pass.
                let w = 7 * z, h = 5 * z
                g.fill(Path(roundedRect: CGRect(x: q.x - w / 2, y: q.y - h / 2, width: w, height: h), cornerRadius: 1), with: .color(Self.c((0.64, 0.5, 0.34))))
                g.fill(Path { x in x.move(to: CGPoint(x: q.x - w * 0.62, y: q.y - h / 2)); x.addLine(to: CGPoint(x: q.x, y: q.y - h * 1.15)); x.addLine(to: CGPoint(x: q.x + w * 0.62, y: q.y - h / 2)); x.closeSubpath() }, with: .color(Self.c((0.32, 0.2, 0.14))))
                g.stroke(Path(CGRect(x: q.x - w / 2, y: q.y - h / 2, width: w, height: h)), with: .color(Self.c(Self.ink, 0.8)), lineWidth: 0.7)
            } else if r.kind == .river {
                // A ferry: a small boat on the crossing.
                var b = g
                b.translateBy(x: q.x, y: q.y)
                b.fill(Path { x in x.move(to: CGPoint(x: -5 * z, y: -1 * z)); x.addLine(to: CGPoint(x: 5 * z, y: -1 * z)); x.addQuadCurve(to: CGPoint(x: -5 * z, y: -1 * z), control: CGPoint(x: 0, y: 4.5 * z)) }, with: .color(Self.c((0.5, 0.32, 0.18))))
                b.stroke(Path { x in x.move(to: CGPoint(x: 0, y: -1 * z)); x.addLine(to: CGPoint(x: 0, y: -7 * z)) }, with: .color(Self.c(Self.ink)), lineWidth: 0.8 * z)
                b.fill(Path { x in x.move(to: CGPoint(x: 0.4 * z, y: -6.6 * z)); x.addLine(to: CGPoint(x: 4 * z, y: -2.2 * z)); x.addLine(to: CGPoint(x: 0.4 * z, y: -2.2 * z)); x.closeSubpath() }, with: .color(Self.c((0.96, 0.92, 0.8))))
            }
        }
    }

    // MARK: Armies

    private func armies(_ g: inout GraphicsContext, _ S: CGFloat, _ z: CGFloat) {
        for a in world.armies {
            guard let road = warlordRoad(a.from, a.to) else { continue }
            var k = Self.road(road)
            if road.a != a.from { k = (k.2, k.1, k.0) }
            let done = Double(a.months - a.left) + 0.12 + 0.8 * march
            let t = CGFloat(min(0.92, done / Double(a.months)))
            let col = Self.colour(a.faction)
            // The arrow of the march: the whole road, bold, in the lord's colour.
            let steps = 24
            var arrow = Path()
            let end: CGFloat = 0.84
            for i in 0...steps {
                let p = Self.along(k, CGFloat(i) / CGFloat(steps) * end)
                if i == 0 { arrow.move(to: CGPoint(x: p.x * S, y: p.y * S)) } else { arrow.addLine(to: CGPoint(x: p.x * S, y: p.y * S)) }
            }
            g.stroke(arrow, with: .color(Self.c((0.1, 0.06, 0.04), 0.35)), style: StrokeStyle(lineWidth: 9.5 * z, lineCap: .round, lineJoin: .round))
            g.stroke(arrow, with: .color(Self.c(col, 0.78)), style: StrokeStyle(lineWidth: 6.5 * z, lineCap: .round, lineJoin: .round))
            g.stroke(arrow, with: .color(Self.c(WarlordLand.lit(col, 1.45), 0.7)), style: StrokeStyle(lineWidth: 1.6 * z, lineCap: .round, dash: [6 * z, 5 * z], dashPhase: -CGFloat(now * 14) * z))
            let tip = Self.along(k, end + 0.1), back = Self.along(k, end - 0.03)
            let ang = atan2(tip.y - back.y, tip.x - back.x)
            let T = CGPoint(x: tip.x * S, y: tip.y * S)
            let head = Path { p in
                p.move(to: CGPoint(x: T.x + cos(ang) * 6 * z, y: T.y + sin(ang) * 6 * z))
                p.addLine(to: CGPoint(x: T.x + cos(ang + 2.5) * 10 * z, y: T.y + sin(ang + 2.5) * 10 * z))
                p.addLine(to: CGPoint(x: T.x + cos(ang - 2.5) * 10 * z, y: T.y + sin(ang - 2.5) * 10 * z))
                p.closeSubpath()
            }
            g.fill(head, with: .color(Self.c(col)))
            g.stroke(head, with: .color(Self.c((0.1, 0.06, 0.04), 0.55)), lineWidth: 1)
            // The column itself, where it has got to.
            let at = Self.along(k, t), P = CGPoint(x: at.x * S, y: at.y * S)
            Self.troop(&g, at: P, z: z, colour: col, mark: warlordBanners[a.faction].mark, facing: cos(ang) >= 0 ? 1 : -1, now: now)
            let words = "\(world.name(a.officers.first ?? 0)) \(WarlordCommander.troops(a.troops))"
            let text = g.resolve(Text(words).font(.system(size: 9.5 * z, weight: .heavy, design: .rounded)).foregroundColor(.white))
            let ts = text.measure(in: CGSize(width: 300, height: 40))
            let tag = CGRect(x: P.x - ts.width / 2 - 5 * z, y: P.y + 11 * z, width: ts.width + 10 * z, height: ts.height + 3 * z)
            g.fill(Path(roundedRect: tag, cornerRadius: tag.height / 2), with: .color(Self.c(WarlordLand.lit(col, 0.45), 0.9)))
            g.stroke(Path(roundedRect: tag, cornerRadius: tag.height / 2), with: .color(Self.c(col)), lineWidth: 1)
            g.draw(text, at: CGPoint(x: tag.midX, y: tag.midY))
        }
    }

    /// A marching column: three soldiers with spears under the lord's flag.
    static func troop(_ g: inout GraphicsContext, at P: CGPoint, z: CGFloat, colour col: RGB, mark: String, facing: CGFloat, now: Double) {
        g.fill(Path(ellipseIn: CGRect(x: P.x - 15 * z, y: P.y + 4 * z, width: 30 * z, height: 7 * z)), with: .color(.black.opacity(0.25)))
        for i in 0..<3 {
            let dx = CGFloat(i - 1) * 8 * z - facing * CGFloat(i % 2) * 2 * z
            let bob = CGFloat(sin(now * 9 + Double(i) * 2)) * 1.2 * z
            let foot = CGPoint(x: P.x + dx, y: P.y + 7 * z + (i == 1 ? 1.5 * z : 0))
            // Legs, body, head, spear.
            g.stroke(Path { p in p.move(to: CGPoint(x: foot.x - 1.6 * z, y: foot.y)); p.addLine(to: CGPoint(x: foot.x - 0.6 * z, y: foot.y - 4 * z + bob)); p.move(to: CGPoint(x: foot.x + 1.6 * z, y: foot.y)); p.addLine(to: CGPoint(x: foot.x + 0.6 * z, y: foot.y - 4 * z + bob)) }, with: .color(c(ink)), lineWidth: 1.3 * z)
            g.fill(Path(roundedRect: CGRect(x: foot.x - 2.6 * z, y: foot.y - 9.5 * z + bob, width: 5.2 * z, height: 6 * z), cornerRadius: 1.6 * z), with: .color(c(col)))
            g.fill(Path(ellipseIn: CGRect(x: foot.x - 2.3 * z, y: foot.y - 13.6 * z + bob, width: 4.6 * z, height: 4.6 * z)), with: .color(c((0.96, 0.8, 0.64))))
            g.fill(Path { p in p.move(to: CGPoint(x: foot.x - 2.8 * z, y: foot.y - 11.8 * z + bob)); p.addQuadCurve(to: CGPoint(x: foot.x + 2.8 * z, y: foot.y - 11.8 * z + bob), control: CGPoint(x: foot.x, y: foot.y - 16.5 * z + bob)); p.closeSubpath() }, with: .color(c((0.34, 0.34, 0.38))))
            g.stroke(Path { p in p.move(to: CGPoint(x: foot.x + facing * 3 * z, y: foot.y - 3 * z + bob)); p.addLine(to: CGPoint(x: foot.x + facing * 5.5 * z, y: foot.y - 19 * z + bob)) }, with: .color(c((0.45, 0.32, 0.2))), lineWidth: 1 * z)
            g.fill(Path { p in let t = CGPoint(x: foot.x + facing * 5.5 * z, y: foot.y - 19 * z + bob); p.move(to: CGPoint(x: t.x, y: t.y - 3 * z)); p.addLine(to: CGPoint(x: t.x - 1.2 * z, y: t.y + 0.5 * z)); p.addLine(to: CGPoint(x: t.x + 1.2 * z, y: t.y + 0.5 * z)); p.closeSubpath() }, with: .color(c((0.85, 0.87, 0.9))))
        }
        flag(&g, pole: CGPoint(x: P.x - facing * 13 * z, y: P.y + 8 * z), height: 26 * z, z: z, colour: col, mark: mark, now: now, facing: facing)
    }

    /// A banner on a pole, waving, with the lord's character on it.
    static func flag(_ g: inout GraphicsContext, pole foot: CGPoint, height: CGFloat, z: CGFloat, colour col: RGB, mark: String, now: Double, facing: CGFloat = 1) {
        let top = CGPoint(x: foot.x, y: foot.y - height)
        g.stroke(Path { p in p.move(to: foot); p.addLine(to: top) }, with: .color(c((0.3, 0.2, 0.12))), lineWidth: 1.3 * z)
        g.fill(Path(ellipseIn: CGRect(x: top.x - 1.6 * z, y: top.y - 1.6 * z, width: 3.2 * z, height: 3.2 * z)), with: .color(c((0.95, 0.78, 0.3))))
        let w = 13 * z * facing, h = 11 * z
        let wave = CGFloat(sin(now * 4 + Double(foot.x) * 0.1)) * 1.6 * z
        let cloth = Path { p in
            p.move(to: CGPoint(x: top.x, y: top.y + 1 * z))
            p.addQuadCurve(to: CGPoint(x: top.x + w, y: top.y + 1 * z + wave), control: CGPoint(x: top.x + w / 2, y: top.y - 1 * z - wave))
            p.addLine(to: CGPoint(x: top.x + w * 0.9, y: top.y + h / 2 + wave))
            p.addLine(to: CGPoint(x: top.x + w, y: top.y + h + wave))
            p.addQuadCurve(to: CGPoint(x: top.x, y: top.y + h), control: CGPoint(x: top.x + w / 2, y: top.y + h - 2 * z - wave))
            p.closeSubpath()
        }
        g.fill(cloth, with: .color(c(col)))
        g.stroke(cloth, with: .color(c(WarlordLand.lit(col, 0.55))), lineWidth: 0.8 * z)
        g.stroke(Path { p in p.move(to: CGPoint(x: top.x + 1.2 * z * facing, y: top.y + 2 * z)); p.addLine(to: CGPoint(x: top.x + 1.2 * z * facing, y: top.y + h - 1 * z)) }, with: .color(c((0.95, 0.8, 0.35), 0.9)), lineWidth: 1.2 * z)
        let dark = col.0 * 0.3 + col.1 * 0.55 + col.2 * 0.15 > 0.62
        g.draw(Text(mark).font(.custom("STSongti-SC-Black", size: 8.6 * z)).foregroundColor(dark ? Color(red: 0.2, green: 0.12, blue: 0.08) : .white),
               at: CGPoint(x: top.x + w * 0.5, y: top.y + h / 2 + wave * 0.5))
    }

    // MARK: Cities

    func radius(_ c: Int, _ z: CGFloat) -> CGFloat { (8 + CGFloat(warlordSites[c].size) * 1.5) * z }

    private func rings(_ g: inout GraphicsContext, _ c: Int, _ S: CGFloat, _ z: CGFloat) {
        guard targets.contains(c) || selected == c || hover == c else { return }
        let at = WarlordMap.at(c), P = CGPoint(x: at.x * S, y: at.y * S), r = radius(c, z)
        // Rings: chosen, hovered, or waiting to be picked.
        if targets.contains(c) {
            let pulse = 0.5 + 0.5 * sin(now * 5)
            let ring: RGB = friendly ? (0.4, 0.95, 0.5) : (1, 0.3, 0.2)
            g.fill(Path(ellipseIn: CGRect(x: P.x - r * 1.9, y: P.y - r * 1.25, width: r * 3.8, height: r * 2.5)), with: .color(Self.c(ring, 0.1 + 0.08 * pulse)))
            g.stroke(Path(ellipseIn: CGRect(x: P.x - r * 1.9, y: P.y - r * 1.25, width: r * 3.8, height: r * 2.5)), with: .color(Self.c(ring, 0.9)), style: StrokeStyle(lineWidth: 2.2 * z, dash: [5 * z, 3 * z], dashPhase: CGFloat(now * 12)))
        }
        if selected == c || hover == c {
            let glow: RGB = selected == c ? (1, 0.86, 0.4) : (1, 1, 1)
            g.fill(Path(ellipseIn: CGRect(x: P.x - r * 2, y: P.y - r * 1.3, width: r * 4, height: r * 2.6)), with: .radialGradient(Gradient(colors: [Self.c(glow, selected == c ? 0.3 : 0.18), Self.c(glow, 0)]), center: P, startRadius: 0, endRadius: r * 2))
            if selected == c { g.stroke(Path(ellipseIn: CGRect(x: P.x - r * 1.75, y: P.y - r * 1.12, width: r * 3.5, height: r * 2.24)), with: .color(Self.c(glow)), lineWidth: 2 * z) }
        }
    }

    private func banner(_ g: inout GraphicsContext, _ c: Int, _ S: CGFloat, _ z: CGFloat) {
        let at = WarlordMap.at(c), P = CGPoint(x: at.x * S, y: at.y * S), r = radius(c, z)
        let owner = world.cities[c].owner
        let w = r * 2, top = r * 0.95
        Self.flag(&g, pole: CGPoint(x: P.x - w / 2 + r * 0.1, y: P.y - top * 0.55), height: r * 1.75, z: z * (0.8 + CGFloat(warlordSites[c].size) * 0.06), colour: Self.colour(owner), mark: owner >= 0 ? warlordBanners[owner].mark : "", now: now)
    }

    private func city(_ g: inout GraphicsContext, _ c: Int, _ S: CGFloat, _ z: CGFloat) {
        let at = WarlordMap.at(c), P = CGPoint(x: at.x * S, y: at.y * S)
        let x = world.cities[c], r = radius(c, z)
        let owner = x.owner, col = Self.colour(owner)
        let capital = owner >= 0 && world.officers[world.factions[owner].lord].city == c && world.officers[world.factions[owner].lord].state == .serving
        // The shadow, the walls seen a little from above, the front face with its gate.
        g.fill(Path(ellipseIn: CGRect(x: P.x - r * 1.25, y: P.y + r * 0.1, width: r * 2.7, height: r * 0.95)), with: .color(.black.opacity(0.28)))
        let w = r * 2, top = r * 0.95, face = r * 0.62
        let yard = CGRect(x: P.x - w / 2, y: P.y - top, width: w, height: top)
        let stone: RGB = owner >= 0 ? (0.8, 0.74, 0.62) : (0.72, 0.7, 0.66)
        g.fill(Path(yard), with: .color(Self.c(WarlordLand.lit(stone, 0.84))))
        g.fill(Path(yard.insetBy(dx: r * 0.18, dy: r * 0.12)), with: .color(Self.c(WarlordLand.lit(col, 0.9), owner >= 0 ? 0.35 : 0.15)))
        // Houses inside: a few roofs.
        for i in 0..<(2 + warlordSites[c].size / 2) {
            let hx = P.x - w * 0.3 + CGFloat(i % 3) * w * 0.3, hy = P.y - top * 0.72 + CGFloat(i / 3) * top * 0.34
            g.fill(Path(CGRect(x: hx - r * 0.18, y: hy, width: r * 0.36, height: r * 0.2)), with: .color(Self.c((0.9, 0.86, 0.76))))
            g.fill(Path { p in p.move(to: CGPoint(x: hx - r * 0.24, y: hy + r * 0.02)); p.addLine(to: CGPoint(x: hx, y: hy - r * 0.16)); p.addLine(to: CGPoint(x: hx + r * 0.24, y: hy + r * 0.02)); p.closeSubpath() }, with: .color(Self.c((0.36, 0.36, 0.42))))
        }
        // The front wall with merlons.
        let front = CGRect(x: P.x - w / 2, y: P.y - face * 0.2, width: w, height: face)
        g.fill(Path(front), with: .color(Self.c(WarlordLand.lit(stone, 0.72))))
        for side in [-1.0, 1.0] as [CGFloat] {
            g.fill(Path(CGRect(x: P.x + side * w / 2 - (side > 0 ? r * 0.14 : 0), y: P.y - top, width: r * 0.14, height: top)), with: .color(Self.c(WarlordLand.lit(stone, 0.95))))
        }
        g.fill(Path(CGRect(x: P.x - w / 2, y: P.y - top, width: w, height: r * 0.12)), with: .color(Self.c(WarlordLand.lit(stone, 0.95))))
        let merlons = 7
        for i in 0..<merlons {
            let mx = P.x - w / 2 + (CGFloat(i) + 0.25) * w / CGFloat(merlons)
            g.fill(Path(CGRect(x: mx, y: front.minY - r * 0.16, width: w / CGFloat(merlons) * 0.5, height: r * 0.18)), with: .color(Self.c(WarlordLand.lit(stone, 0.82))))
        }
        g.stroke(Path(front), with: .color(Self.c(Self.ink, 0.7)), lineWidth: 0.7 * z)
        g.stroke(Path(yard), with: .color(Self.c(Self.ink, 0.55)), lineWidth: 0.6 * z)
        // The gate and its tower.
        let gate = CGRect(x: P.x - r * 0.22, y: front.maxY - face * 0.62, width: r * 0.44, height: face * 0.62)
        g.fill(Path(roundedRect: gate, cornerRadii: RectangleCornerRadii(topLeading: r * 0.22, bottomLeading: 0, bottomTrailing: 0, topTrailing: r * 0.22)), with: .color(Self.c((0.24, 0.16, 0.12))))
        let tower = CGRect(x: P.x - r * 0.44, y: front.minY - r * 0.52, width: r * 0.88, height: r * 0.4)
        g.fill(Path(tower), with: .color(Self.c((0.66, 0.26, 0.2))))
        let roof: RGB = capital ? (0.86, 0.66, 0.2) : (0.3, 0.3, 0.36)
        let eave = Path { p in
            p.move(to: CGPoint(x: tower.minX - r * 0.3, y: tower.minY + r * 0.06))
            p.addQuadCurve(to: CGPoint(x: tower.midX, y: tower.minY - r * 0.34), control: CGPoint(x: tower.minX + r * 0.05, y: tower.minY - r * 0.05))
            p.addQuadCurve(to: CGPoint(x: tower.maxX + r * 0.3, y: tower.minY + r * 0.06), control: CGPoint(x: tower.maxX - r * 0.05, y: tower.minY - r * 0.05))
            p.closeSubpath()
        }
        g.fill(eave, with: .color(Self.c(roof)))
        g.stroke(eave, with: .color(Self.c(Self.ink, 0.6)), lineWidth: 0.6 * z)
    }

    private func label(_ g: inout GraphicsContext, _ c: Int, _ S: CGFloat, _ z: CGFloat) {
        let at = WarlordMap.at(c), P = CGPoint(x: at.x * S, y: at.y * S)
        let x = world.cities[c], r = radius(c, z)
        let name = warlordSites[c].name
        let fs = (warlordSites[c].size >= 4 ? 11.5 : 10.5) * z
        let wide = CGFloat(name.count) * fs + 10 * z
        let plate = CGRect(x: P.x - wide / 2, y: P.y + r * 0.5, width: wide, height: fs + 5 * z)
        let col = Self.colour(x.owner)
        g.fill(Path(roundedRect: plate, cornerRadius: 3 * z), with: .color(Self.c((0.97, 0.93, 0.82), 0.92)))
        g.fill(Path(roundedRect: CGRect(x: plate.minX, y: plate.minY, width: 3 * z, height: plate.height), cornerRadius: 1.5 * z), with: .color(Self.c(col)))
        g.stroke(Path(roundedRect: plate, cornerRadius: 3 * z), with: .color(Self.c(Self.ink, 0.7)), lineWidth: 0.8 * z)
        g.draw(Text(name).font(.custom("STSongti-SC-Black", size: fs)).foregroundColor(Self.c(Self.ink)), at: CGPoint(x: plate.midX + 1.5 * z, y: plate.midY))
        if S >= 1.6 || selected == c || x.owner == mine && mine != nil {
            let t = g.resolve(Text(WarlordCommander.troops(x.troops)).font(.system(size: 8.5 * z, weight: .heavy, design: .rounded)).foregroundColor(.white))
            let ts = t.measure(in: CGSize(width: 200, height: 30))
            let tag = CGRect(x: plate.midX - ts.width / 2 - 4 * z, y: plate.maxY + 1 * z, width: ts.width + 8 * z, height: ts.height + 1 * z)
            g.fill(Path(roundedRect: tag, cornerRadius: tag.height / 2), with: .color(Color.black.opacity(0.55)))
            g.draw(t, at: CGPoint(x: tag.midX, y: tag.midY))
        }
    }

    // MARK: Battles being told

    private func battle(_ g: inout GraphicsContext, _ b: WarlordBattle, _ S: CGFloat, _ z: CGFloat) {
        let at = WarlordMap.at(b.city), P = CGPoint(x: at.x * S, y: at.y * S - 10 * z)
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi + now * 0.6
            let r = (9 + 3 * sin(now * 2 + Double(i))) * Double(z)
            let q = CGPoint(x: P.x + CGFloat(cos(a) * r), y: P.y + CGFloat(sin(a) * r * 0.6) - CGFloat(i % 2) * 3 * z)
            g.fill(Path(ellipseIn: CGRect(x: q.x - 7 * z, y: q.y - 7 * z, width: 14 * z, height: 14 * z)), with: .color(Color(white: 0.35 + 0.1 * Double(i % 3)).opacity(0.5)))
        }
        let flash = 0.5 + 0.5 * sin(now * 8)
        g.fill(Path(ellipseIn: CGRect(x: P.x - 12 * z, y: P.y - 12 * z, width: 24 * z, height: 24 * z)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.7, blue: 0.2).opacity(0.8 * flash), .clear]), center: P, startRadius: 0, endRadius: 14 * z))
        for s in [-1.0, 1.0] as [CGFloat] {
            var blade = g
            blade.translateBy(x: P.x, y: P.y)
            blade.rotate(by: .radians(Double(s) * 0.8))
            blade.fill(Path(roundedRect: CGRect(x: -1.4 * z, y: -13 * z, width: 2.8 * z, height: 18 * z), cornerRadius: 1.2 * z), with: .color(Color(white: 0.92)))
            blade.fill(Path(CGRect(x: -4 * z, y: 4 * z, width: 8 * z, height: 2 * z)), with: .color(Self.c((0.85, 0.66, 0.2))))
            blade.fill(Path(CGRect(x: -1.2 * z, y: 6 * z, width: 2.4 * z, height: 5 * z)), with: .color(Self.c((0.4, 0.22, 0.12))))
        }
    }

    /// The city under a point of the view, if one is near enough to mean it.
    static func hit(_ p: CGPoint, S: CGFloat, origin: CGPoint) -> Int? {
        let z = glyph(S)
        var best: (Int, CGFloat)?
        for c in warlordSites.indices {
            let at = WarlordMap.at(c)
            let q = CGPoint(x: (at.x - origin.x) * S, y: (at.y - origin.y) * S)
            let d = hypot(p.x - q.x, p.y - (q.y - 2 * z))
            if d < max(18, 22 * z), best == nil || d < best!.1 { best = (c, d) }
        }
        return best?.0
    }
}

// MARK: - Portraits

/// A general as a round-faced chibi: their headgear — a helmet with a red
/// tassel, a scholar's silk cap, a lord's crown, a headband, 吕布's pheasant
/// feathers, a lady's hair and pins — their beard, their armour or robe in
/// their lord's colour, and what marks them out: 夏侯惇's eyepatch, 诸葛亮's
/// feather fan, 董卓's heavy jowls, 关羽's red face.
enum WarlordPortrait {
    typealias RGB = (Double, Double, Double)
    static func c(_ v: RGB, _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }
    static func lit(_ v: RGB, _ k: Double) -> RGB { WarlordLand.lit(v, k) }

    /// The coat a general wears: their own, or their lord's colour, or a traveller's brown.
    static func coat(_ o: Int, faction: Int) -> RGB {
        if let own = warlordPeople[o].look.coat { return own }
        return faction >= 0 ? warlordBanners[faction].colour : (0.56, 0.46, 0.34)
    }

    static func draw(_ g: GraphicsContext, _ o: Int, faction: Int, at p: CGPoint, size s: CGFloat, now: Double = 0) {
        let person = warlordPeople[o], look = person.look
        let coat = coat(o, faction: faction)
        let warrior = look.hat == 1 || look.hat == 5 || (person.war >= 70 && person.war >= person.wit && look.hat != 2 && look.hat != 6)
        let hair = look.beard == 4 || look.hat == 7 ? (0.9, 0.9, 0.88) : look.hair
        // Shoulders: armour with pauldrons, or a robe with a crossed collar.
        let body = Path { q in
            q.move(to: CGPoint(x: p.x - s * 0.98, y: p.y + s * 1.5))
            q.addQuadCurve(to: CGPoint(x: p.x - s * 0.38, y: p.y + s * 0.62), control: CGPoint(x: p.x - s * 0.96, y: p.y + s * 0.72))
            q.addLine(to: CGPoint(x: p.x + s * 0.38, y: p.y + s * 0.62))
            q.addQuadCurve(to: CGPoint(x: p.x + s * 0.98, y: p.y + s * 1.5), control: CGPoint(x: p.x + s * 0.96, y: p.y + s * 0.72))
            q.closeSubpath()
        }
        g.fill(body, with: .linearGradient(Gradient(colors: [c(lit(coat, 1.08)), c(lit(coat, 0.72))]), startPoint: CGPoint(x: p.x, y: p.y + s * 0.6), endPoint: CGPoint(x: p.x, y: p.y + s * 1.5)))
        if warrior {
            let metal: RGB = look.hat == 5 ? (0.9, 0.72, 0.3) : (0.74, 0.76, 0.8)
            for side in [-1.0, 1.0] as [CGFloat] {
                let pad = CGRect(x: p.x + side * s * 0.66 - s * 0.3, y: p.y + s * 0.7, width: s * 0.6, height: s * 0.44)
                g.fill(Path(ellipseIn: pad), with: .linearGradient(Gradient(colors: [c(lit(metal, 1.2)), c(lit(metal, 0.7))]), startPoint: CGPoint(x: pad.minX, y: pad.minY), endPoint: CGPoint(x: pad.maxX, y: pad.maxY)))
                g.stroke(Path(ellipseIn: pad), with: .color(c((0.2, 0.16, 0.14), 0.5)), lineWidth: s * 0.03)
            }
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.3, y: p.y + s * 0.78, width: s * 0.6, height: s * 0.6), cornerRadius: s * 0.1), with: .color(c(lit(metal, 0.92))))
            for k in 0..<2 { g.stroke(Path { q in let y = p.y + s * (0.95 + CGFloat(k) * 0.2); q.move(to: CGPoint(x: p.x - s * 0.3, y: y)); q.addLine(to: CGPoint(x: p.x + s * 0.3, y: y)) }, with: .color(c((0.3, 0.26, 0.24), 0.45)), lineWidth: s * 0.03) }
        } else {
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.34, y: p.y + s * 0.64)); q.addLine(to: CGPoint(x: p.x + s * 0.1, y: p.y + s * 1.5)); q.addLine(to: CGPoint(x: p.x - s * 0.06, y: p.y + s * 1.5)); q.addLine(to: CGPoint(x: p.x - s * 0.44, y: p.y + s * 0.72)); q.closeSubpath() }, with: .color(c((0.96, 0.94, 0.88))))
            g.fill(Path { q in q.move(to: CGPoint(x: p.x + s * 0.34, y: p.y + s * 0.64)); q.addLine(to: CGPoint(x: p.x - s * 0.04, y: p.y + s * 1.2)); q.addLine(to: CGPoint(x: p.x + s * 0.44, y: p.y + s * 0.72)); q.closeSubpath() }, with: .color(c((0.96, 0.94, 0.88))))
        }
        // Hair behind the head.
        if [0, 4, 6, 7, 9].contains(look.hat) {
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.7, y: p.y - s * 0.76, width: s * 1.4, height: s * 1.3)), with: .color(c(hair)))
        }
        if look.hat == 6 {
            // Long hair down the back and sides.
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.72, y: p.y - s * 0.3, width: s * 1.44, height: s * 1.2), cornerRadius: s * 0.4), with: .color(c(hair)))
        }
        // Behind: the pheasant feathers, the tassel's fall, the kerchief's ribbons.
        if look.hat == 5 {
            for side in [-1.0, 1.0] as [CGFloat] {
                let feather = Path { q in q.move(to: CGPoint(x: p.x + side * s * 0.2, y: p.y - s * 0.75)); q.addQuadCurve(to: CGPoint(x: p.x + side * s * 1.25, y: p.y - s * 1.65), control: CGPoint(x: p.x + side * s * 0.15, y: p.y - s * 1.9)) }
                g.stroke(feather, with: .color(c((0.93, 0.74, 0.3))), style: StrokeStyle(lineWidth: s * 0.14, lineCap: .round))
                g.stroke(feather, with: .color(c((0.52, 0.18, 0.12))), style: StrokeStyle(lineWidth: s * 0.14, lineCap: .round, dash: [s * 0.08, s * 0.14]))
            }
        }
        if look.hat == 2 {
            for side in [-1.0, 1.0] as [CGFloat] {
                let wave = CGFloat(sin(now * 2 + Double(side))) * s * 0.06
                g.stroke(Path { q in q.move(to: CGPoint(x: p.x + side * s * 0.45, y: p.y - s * 0.55)); q.addQuadCurve(to: CGPoint(x: p.x + side * s * 0.95, y: p.y + s * 0.2 + wave), control: CGPoint(x: p.x + side * s * 0.95, y: p.y - s * 0.4)) }, with: .color(c(look.accent)), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
            }
        }
        // The face — heavy jowls for some.
        let jowl: CGFloat = look.extra == 3 ? 0.16 : 0
        let face = CGRect(x: p.x - s * (0.58 + jowl / 2), y: p.y - s * 0.55, width: s * (1.16 + jowl), height: s * (1.12 + jowl / 2))
        for side in [-1.0, 1.0] as [CGFloat] {
            g.fill(Path(ellipseIn: CGRect(x: p.x + side * face.width / 2 - s * 0.12, y: p.y - s * 0.02, width: s * 0.24, height: s * 0.28)), with: .color(c(lit(look.skin, 0.92))))
        }
        g.fill(Path(ellipseIn: face), with: .linearGradient(Gradient(colors: [c(lit(look.skin, 1.05)), c(lit(look.skin, 0.92))]), startPoint: CGPoint(x: p.x, y: face.minY), endPoint: CGPoint(x: p.x, y: face.maxY)))
        // A fringe for most; a lady's hair frames the face.
        if [0, 4, 7, 9].contains(look.hat) {
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX, y: face.midY - s * 0.08)); q.addQuadCurve(to: CGPoint(x: face.maxX, y: face.midY - s * 0.08), control: CGPoint(x: p.x, y: face.minY - s * 0.46)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.12, y: face.minY + s * 0.26), control: CGPoint(x: face.maxX - s * 0.12, y: face.minY + s * 0.08)); q.addQuadCurve(to: CGPoint(x: face.minX, y: face.midY - s * 0.08), control: CGPoint(x: face.minX + s * 0.18, y: face.minY + s * 0.2)); q.closeSubpath() }, with: .color(c(hair)))
        }
        if look.hat == 6 {
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX - s * 0.04, y: face.midY + s * 0.1)); q.addQuadCurve(to: CGPoint(x: face.maxX + s * 0.04, y: face.midY + s * 0.1), control: CGPoint(x: p.x, y: face.minY - s * 0.56)); q.addQuadCurve(to: CGPoint(x: p.x, y: face.minY + s * 0.3), control: CGPoint(x: face.maxX - s * 0.1, y: face.minY + s * 0.02)); q.addQuadCurve(to: CGPoint(x: face.minX - s * 0.04, y: face.midY + s * 0.1), control: CGPoint(x: face.minX + s * 0.1, y: face.minY + s * 0.02)); q.closeSubpath() }, with: .color(c(hair)))
        }
        // Brows, eyes with a shine, cheeks, a mouth.
        let fierce = person.war >= 88 && person.wit < 60
        for side in [-1.0, 1.0] as [CGFloat] {
            let e = CGPoint(x: p.x + side * s * 0.24, y: p.y + s * 0.1)
            if look.extra == 1 && side < 0 {
                g.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.15, y: e.y - s * 0.14, width: s * 0.3, height: s * 0.26)), with: .color(c((0.1, 0.08, 0.08))))
                g.stroke(Path { q in q.move(to: CGPoint(x: face.minX + s * 0.02, y: p.y - s * 0.14)); q.addLine(to: CGPoint(x: p.x + s * 0.4, y: p.y - s * 0.32)) }, with: .color(c((0.1, 0.08, 0.08))), lineWidth: s * 0.05)
                continue
            }
            g.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.1, y: e.y - s * 0.13, width: s * 0.2, height: s * 0.26)), with: .color(c((0.12, 0.08, 0.08))))
            g.fill(Path(ellipseIn: CGRect(x: e.x - s * 0.035, y: e.y - s * 0.1, width: s * 0.08, height: s * 0.08)), with: .color(.white))
            let browY = e.y - s * 0.22
            g.stroke(Path { q in
                q.move(to: CGPoint(x: e.x - side * s * 0.13, y: browY + (fierce ? s * 0.06 : 0)))
                q.addLine(to: CGPoint(x: e.x + side * s * 0.14, y: browY - (fierce ? s * 0.05 : s * 0.02)))
            }, with: .color(c(look.beard == 4 ? (0.85, 0.85, 0.82) : (0.14, 0.1, 0.08))), style: StrokeStyle(lineWidth: s * (fierce ? 0.09 : 0.06), lineCap: .round))
            g.fill(Path(ellipseIn: CGRect(x: e.x + side * s * 0.06 - s * 0.1, y: e.y + s * 0.15, width: s * 0.2, height: s * 0.1)), with: .color(Color(red: 1, green: 0.45, blue: 0.45).opacity(0.4)))
        }
        if ![2, 3, 4].contains(look.beard) {
            g.stroke(Path { q in q.move(to: CGPoint(x: p.x - s * 0.09, y: p.y + s * 0.34)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.09, y: p.y + s * 0.34), control: CGPoint(x: p.x, y: p.y + s * 0.42)) }, with: .color(c((0.5, 0.2, 0.2))), lineWidth: s * 0.05)
        }
        // Beards.
        let beardColour: RGB = look.beard == 4 ? (0.95, 0.95, 0.93) : look.hair
        switch look.beard {
        case 1:
            for side in [-1.0, 1.0] as [CGFloat] {
                g.stroke(Path { q in q.move(to: CGPoint(x: p.x + side * s * 0.03, y: p.y + s * 0.27)); q.addQuadCurve(to: CGPoint(x: p.x + side * s * 0.26, y: p.y + s * 0.34), control: CGPoint(x: p.x + side * s * 0.16, y: p.y + s * 0.22)) }, with: .color(c(beardColour)), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
            }
        case 2, 4:
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.4, y: p.y + s * 0.24)); q.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s * 1.45), control: CGPoint(x: p.x - s * 0.44, y: p.y + s * 1.05)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.4, y: p.y + s * 0.24), control: CGPoint(x: p.x + s * 0.44, y: p.y + s * 1.05)); q.addQuadCurve(to: CGPoint(x: p.x - s * 0.4, y: p.y + s * 0.24), control: CGPoint(x: p.x, y: p.y + s * 0.5)); q.closeSubpath() }, with: .color(c(beardColour)))
            g.stroke(Path { q in for k in -1...1 { let x0 = p.x + CGFloat(k) * s * 0.14; q.move(to: CGPoint(x: x0, y: p.y + s * 0.6)); q.addQuadCurve(to: CGPoint(x: x0 * 0.5 + p.x * 0.5, y: p.y + s * 1.3), control: CGPoint(x: x0, y: p.y + s * 1.0)) } }, with: .color(c(lit(beardColour, 0.8))), lineWidth: s * 0.03)
        case 3:
            var spikes = Path()
            spikes.move(to: CGPoint(x: face.minX + s * 0.02, y: p.y + s * 0.05))
            for k in 0...8 {
                let a = Double.pi * (0.05 + 0.9 * Double(k) / 8)
                let out: CGFloat = k % 2 == 0 ? 0.78 : 0.6
                spikes.addLine(to: CGPoint(x: p.x - CGFloat(cos(a)) * s * 0.62, y: p.y + s * 0.15 + CGFloat(sin(a)) * s * out))
            }
            spikes.addLine(to: CGPoint(x: face.maxX - s * 0.02, y: p.y + s * 0.05))
            spikes.addQuadCurve(to: CGPoint(x: face.minX + s * 0.02, y: p.y + s * 0.05), control: CGPoint(x: p.x, y: p.y + s * 0.62))
            g.fill(spikes, with: .color(c(beardColour)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.1, y: p.y + s * 0.32, width: s * 0.2, height: s * 0.1)), with: .color(c((0.5, 0.2, 0.2))))
        case 5:
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.12, y: p.y + s * 0.44)); q.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.82)); q.addLine(to: CGPoint(x: p.x + s * 0.12, y: p.y + s * 0.44)); q.closeSubpath() }, with: .color(c(beardColour)))
            for side in [-1.0, 1.0] as [CGFloat] {
                g.stroke(Path { q in q.move(to: CGPoint(x: p.x + side * s * 0.03, y: p.y + s * 0.27)); q.addQuadCurve(to: CGPoint(x: p.x + side * s * 0.3, y: p.y + s * 0.42), control: CGPoint(x: p.x + side * s * 0.2, y: p.y + s * 0.24)) }, with: .color(c(beardColour)), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
            }
        default: break
        }
        // Headgear.
        switch look.hat {
        case 0:
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.2, y: face.minY - s * 0.36, width: s * 0.4, height: s * 0.36)), with: .color(c(hair)))
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.22, y: face.minY - s * 0.08, width: s * 0.44, height: s * 0.1), cornerRadius: s * 0.05), with: .color(c(look.accent)))
        case 1, 5:
            let metal: RGB = look.hat == 5 ? (0.94, 0.76, 0.3) : (0.78, 0.8, 0.86)
            let dome = Path { q in q.move(to: CGPoint(x: face.minX - s * 0.08, y: face.midY - s * 0.1)); q.addQuadCurve(to: CGPoint(x: face.maxX + s * 0.08, y: face.midY - s * 0.1), control: CGPoint(x: p.x, y: face.minY - s * 0.62)); q.closeSubpath() }
            g.fill(dome, with: .linearGradient(Gradient(colors: [c(lit(metal, 1.25)), c(lit(metal, 0.7))]), startPoint: CGPoint(x: face.minX, y: face.minY - s * 0.3), endPoint: CGPoint(x: face.maxX, y: face.midY)))
            g.fill(Path(roundedRect: CGRect(x: face.minX - s * 0.1, y: face.midY - s * 0.2, width: face.width + s * 0.2, height: s * 0.13), cornerRadius: s * 0.06), with: .color(c(lit(metal, 0.62))))
            for side in [-1.0, 1.0] as [CGFloat] {
                g.fill(Path(roundedRect: CGRect(x: p.x + side * (face.width / 2 + s * 0.02) - s * 0.1, y: face.midY - s * 0.12, width: s * 0.2, height: s * 0.42), cornerRadius: s * 0.08), with: .color(c(lit(metal, 0.82))))
            }
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.12, y: face.midY - s * 0.2)); q.addLine(to: CGPoint(x: p.x, y: face.minY - s * 0.2)); q.addLine(to: CGPoint(x: p.x + s * 0.12, y: face.midY - s * 0.2)); q.closeSubpath() }, with: .color(c((0.95, 0.8, 0.35))))
            if look.hat == 1 {
                // The red tassel spilling from the top.
                let top = CGPoint(x: p.x, y: face.minY - s * 0.36)
                for k in -3...3 {
                    let wave = CGFloat(sin(now * 3 + Double(k))) * s * 0.03
                    g.stroke(Path { q in q.move(to: top); q.addQuadCurve(to: CGPoint(x: top.x + CGFloat(k) * s * 0.14 + wave, y: top.y + s * 0.2), control: CGPoint(x: top.x + CGFloat(k) * s * 0.06, y: top.y - s * 0.26)) }, with: .color(c((0.86, 0.14, 0.12))), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
                }
                g.fill(Path(ellipseIn: CGRect(x: top.x - s * 0.07, y: top.y - s * 0.05, width: s * 0.14, height: s * 0.12)), with: .color(c((0.95, 0.78, 0.3))))
            }
        case 2:
            let cap = Path { q in q.move(to: CGPoint(x: face.minX + s * 0.02, y: face.midY - s * 0.14)); q.addQuadCurve(to: CGPoint(x: face.maxX - s * 0.02, y: face.midY - s * 0.14), control: CGPoint(x: p.x, y: face.minY - s * 0.62)); q.closeSubpath() }
            g.fill(cap, with: .color(c(look.accent)))
            g.stroke(Path { q in for k in -1...1 { q.move(to: CGPoint(x: p.x + CGFloat(k) * s * 0.18, y: face.midY - s * 0.14)); q.addLine(to: CGPoint(x: p.x + CGFloat(k) * s * 0.1, y: face.minY - s * 0.2)) } }, with: .color(c(lit(look.accent, 0.7))), lineWidth: s * 0.04)
            g.fill(Path(roundedRect: CGRect(x: face.minX, y: face.midY - s * 0.2, width: face.width, height: s * 0.1), cornerRadius: s * 0.05), with: .color(c(lit(look.accent, 0.75))))
        case 3:
            // A lord's black cap with a golden crown and a jade pin across it.
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX + s * 0.08, y: face.midY - s * 0.14)); q.addQuadCurve(to: CGPoint(x: face.maxX - s * 0.08, y: face.midY - s * 0.14), control: CGPoint(x: p.x, y: face.minY - s * 0.3)); q.closeSubpath() }, with: .color(c(hair)))
            let crown = CGRect(x: p.x - s * 0.3, y: face.minY - s * 0.42, width: s * 0.6, height: s * 0.36)
            g.fill(Path(roundedRect: crown, cornerRadius: s * 0.08), with: .linearGradient(Gradient(colors: [c((1, 0.86, 0.4)), c((0.78, 0.56, 0.16))]), startPoint: CGPoint(x: crown.minX, y: crown.minY), endPoint: CGPoint(x: crown.maxX, y: crown.maxY)))
            g.fill(Path(roundedRect: CGRect(x: p.x - s * 0.5, y: face.minY - s * 0.3, width: s * 1.0, height: s * 0.07), cornerRadius: s * 0.035), with: .color(c((0.46, 0.76, 0.6))))
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.07, y: crown.minY + s * 0.1, width: s * 0.14, height: s * 0.14)), with: .color(c((0.86, 0.16, 0.18))))
        case 4:
            let band = CGRect(x: face.minX - s * 0.02, y: face.midY - s * 0.3, width: face.width + s * 0.04, height: s * 0.14)
            g.fill(Path(roundedRect: band, cornerRadius: s * 0.06), with: .color(c(look.accent == (0.9, 0.74, 0.3) ? lit(coat, 0.9) : look.accent)))
            for k in 0..<2 {
                let wave = CGFloat(sin(now * 3 + Double(k))) * s * 0.05
                g.stroke(Path { q in q.move(to: CGPoint(x: band.maxX, y: band.midY)); q.addQuadCurve(to: CGPoint(x: band.maxX + s * 0.4, y: band.midY + s * (0.15 + CGFloat(k) * 0.14) + wave), control: CGPoint(x: band.maxX + s * 0.2, y: band.midY - s * 0.1)) }, with: .color(c(look.accent == (0.9, 0.74, 0.3) ? lit(coat, 0.9) : look.accent)), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
            }
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.18, y: face.minY - s * 0.3, width: s * 0.36, height: s * 0.3)), with: .color(c(hair)))
        case 6:
            for side in [-1.0, 1.0] as [CGFloat] {
                g.fill(Path(ellipseIn: CGRect(x: p.x + side * s * 0.36 - s * 0.22, y: face.minY - s * 0.3, width: s * 0.44, height: s * 0.4)), with: .color(c(hair)))
            }
            let f = CGPoint(x: p.x + s * 0.5, y: face.minY - s * 0.06)
            for n in 0..<5 { let a = Double(n) / 5 * 2 * .pi; g.fill(Path(ellipseIn: CGRect(x: f.x + CGFloat(cos(a)) * s * 0.12 - s * 0.1, y: f.y + CGFloat(sin(a)) * s * 0.12 - s * 0.1, width: s * 0.2, height: s * 0.2)), with: .color(c(look.accent))) }
            g.fill(Path(ellipseIn: CGRect(x: f.x - s * 0.06, y: f.y - s * 0.06, width: s * 0.12, height: s * 0.12)), with: .color(c((1, 0.9, 0.4))))
            g.stroke(Path { q in q.move(to: CGPoint(x: p.x - s * 0.55, y: face.minY - s * 0.05)); q.addLine(to: CGPoint(x: p.x - s * 0.15, y: face.minY - s * 0.25)) }, with: .color(c((0.95, 0.8, 0.35))), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        case 7:
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX + s * 0.1, y: face.minY + s * 0.12)); q.addQuadCurve(to: CGPoint(x: face.maxX - s * 0.1, y: face.minY + s * 0.12), control: CGPoint(x: p.x, y: face.minY - s * 0.4)); q.closeSubpath() }, with: .color(c((0.46, 0.42, 0.38))))
        case 8:
            // An official's cap: black, with its ridge rising at the back.
            g.fill(Path { q in q.move(to: CGPoint(x: face.minX + s * 0.02, y: face.midY - s * 0.16)); q.addQuadCurve(to: CGPoint(x: face.maxX - s * 0.02, y: face.midY - s * 0.16), control: CGPoint(x: p.x, y: face.minY - s * 0.34)); q.closeSubpath() }, with: .color(c((0.12, 0.11, 0.13))))
            g.fill(Path { q in q.move(to: CGPoint(x: p.x - s * 0.32, y: face.minY - s * 0.02)); q.addLine(to: CGPoint(x: p.x + s * 0.12, y: face.minY - s * 0.5)); q.addLine(to: CGPoint(x: p.x + s * 0.34, y: face.minY - s * 0.42)); q.addLine(to: CGPoint(x: p.x + s * 0.3, y: face.minY + s * 0.02)); q.closeSubpath() }, with: .color(c((0.16, 0.15, 0.18))))
            g.fill(Path(roundedRect: CGRect(x: face.minX + s * 0.04, y: face.midY - s * 0.22, width: face.width - s * 0.08, height: s * 0.08), cornerRadius: s * 0.04), with: .color(c((0.3, 0.28, 0.32))))
        case 9:
            let wrap = CGRect(x: face.minX - s * 0.06, y: face.minY - s * 0.28, width: face.width + s * 0.12, height: s * 0.5)
            g.fill(Path(ellipseIn: wrap), with: .color(c((0.86, 0.36, 0.18))))
            for k in 0..<3 { g.stroke(Path { q in let y = wrap.minY + wrap.height * (0.3 + CGFloat(k) * 0.2); q.move(to: CGPoint(x: wrap.minX + s * 0.08, y: y)); q.addQuadCurve(to: CGPoint(x: wrap.maxX - s * 0.08, y: y), control: CGPoint(x: wrap.midX, y: y - s * 0.12)) }, with: .color(c((0.98, 0.84, 0.3))), lineWidth: s * 0.05) }
            g.stroke(Path { q in q.move(to: CGPoint(x: p.x + s * 0.3, y: wrap.minY + s * 0.05)); q.addQuadCurve(to: CGPoint(x: p.x + s * 0.72, y: wrap.minY - s * 0.55), control: CGPoint(x: p.x + s * 0.3, y: wrap.minY - s * 0.5)) }, with: .color(c((0.2, 0.5, 0.36))), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
        default: break
        }
        // In hand: 诸葛亮's feather fan.
        if look.extra == 2 {
            var fan = g
            fan.translateBy(x: p.x + s * 0.7, y: p.y + s * 1.25)
            fan.rotate(by: .radians(-0.4 + 0.08 * sin(now * 2)))
            fan.fill(Path { q in q.move(to: .zero); q.addQuadCurve(to: CGPoint(x: -s * 0.36, y: -s * 0.85), control: CGPoint(x: -s * 0.5, y: -s * 0.3)); q.addQuadCurve(to: CGPoint(x: s * 0.36, y: -s * 0.85), control: CGPoint(x: 0, y: -s * 1.08)); q.addQuadCurve(to: .zero, control: CGPoint(x: s * 0.5, y: -s * 0.3)); q.closeSubpath() }, with: .color(.white))
            fan.stroke(Path { q in for n in -2...2 { q.move(to: .zero); q.addLine(to: CGPoint(x: CGFloat(n) * s * 0.14, y: -s * 0.86)) } }, with: .color(Color(white: 0.72)), lineWidth: s * 0.03)
            fan.fill(Path(roundedRect: CGRect(x: -s * 0.05, y: -s * 0.05, width: s * 0.1, height: s * 0.3), cornerRadius: s * 0.04), with: .color(c((0.5, 0.32, 0.18))))
        }
    }
}

/// A portrait in a round frame of its lord's colour, as a view.
struct WarlordFace: View, Equatable {
    var officer: Int
    var faction: Int
    var ring = true
    var body: some View {
        Canvas { g, size in
            let s = min(size.width, size.height)
            let col = faction >= 0 ? warlordBanners[faction].colour : warlordNeutralColour
            if ring {
                let disc = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
                g.fill(Path(ellipseIn: disc), with: .radialGradient(Gradient(colors: [WarlordScene.c(WarlordLand.lit(col, 1.5)), WarlordScene.c(WarlordLand.lit(col, 0.85))]), center: CGPoint(x: disc.midX, y: disc.minY + s * 0.35), startRadius: 0, endRadius: s * 0.7))
                var inner = g
                inner.clip(to: Path(ellipseIn: disc))
                WarlordPortrait.draw(inner, officer, faction: faction, at: CGPoint(x: disc.midX, y: disc.midY - s * 0.02), size: s * 0.36)
                g.stroke(Path(ellipseIn: disc.insetBy(dx: 0.75, dy: 0.75)), with: .color(Color(red: 0.95, green: 0.82, blue: 0.5)), lineWidth: max(1.2, s * 0.045))
            } else {
                WarlordPortrait.draw(g, officer, faction: faction, at: CGPoint(x: size.width / 2, y: size.height * 0.42), size: s * 0.38)
            }
        }
    }
}
