import SwiftUI

/// 长城守卫 at one moment, from above at three-quarters like the other building games: the steppe running up to a
/// ridge of hills in the north with three gaps, a river winding across with its fords, grey boulders, and along the
/// south the Great Wall — its walkway, crenellations and brick face, beacon-towers on it, and over the pass a
/// two-storey gate tower with red pillars and a double-eaved roof. Towers of timber and stone with Han roofs and
/// banners; raiders on horseback and on foot with fur caps and hide shields, siege carts, shamans, the Chanyu on a
/// white horse under his wolf banner. Arrows, bolts, stones arcing, fire pots bursting into burning ground.
struct WallScene {
    let field: WallField
    var selected: Int? = nil
    var hoverTower: Int? = nil
    var preview: WallPreview? = nil
    /// Seconds, for what moves by itself (flames, banners): the wall clock.
    let now: Double
    /// Drawn as a card's picture.
    var icon = false
    /// Paint the land too — false when the page shows it as a picture of its own under the Canvas.
    var drawsLand = true

    typealias RGB = Art.RGB
    static func c(_ v: RGB, _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }
    static let timber: RGB = (0.5, 0.33, 0.2), timberDark: RGB = (0.34, 0.22, 0.14), stone: RGB = (0.66, 0.63, 0.58), stoneDark: RGB = (0.47, 0.45, 0.42)
    static let roofTile: RGB = (0.25, 0.27, 0.31), red: RGB = (0.78, 0.18, 0.14), gold: RGB = (0.98, 0.78, 0.3), brick: RGB = (0.62, 0.56, 0.48)
    static let han: RGB = (0.8, 0.16, 0.12)
    static let steppe: [RGB] = [(0.5, 0.36, 0.22), (0.42, 0.32, 0.24), (0.56, 0.44, 0.3), (0.36, 0.3, 0.26)]

    var t: Double { field.time }

    // MARK: The whole picture

    /// Paint the part of the world in `view` (in the camera's tiles), `S` points to a tile, the world's corner at the origin.
    func paint(_ g: inout GraphicsContext, tile S: CGFloat, view: CGRect) {
        // The field's corner.
        g.translateBy(x: 0.5 * S, y: WallGame.top * S)
        let seen = view.offsetBy(dx: -0.5, dy: -WallGame.top)
        land(&g, S, seen)
        fires(&g, S)
        fallen(&g, S)
        ways(&g, S)
        reaches(&g, S)

        // Standing things, back to front.
        enum Thing { case tower(WallTower), enemy(WallEnemy), gate, watch(Double) }
        var things: [(Double, Thing)] = []
        for tw in field.towers { things.append((Double(tw.y) + 0.9, .tower(tw))) }
        for e in field.enemies where e.x > Double(seen.minX) - 2 && e.x < Double(seen.maxX) + 2 { things.append((e.y, .enemy(e))) }
        things.append((19.35, .gate))
        for x in [3.5, 26.5, -7.5, 37.5] { things.append((19.3, .watch(x))) }
        things.sort { $0.0 < $1.0 }
        for (_, thing) in things {
            switch thing {
            case .tower(let tw): tower(&g, tw, S)
            case .enemy(let e): enemy(&g, e, S)
            case .gate: gateTower(&g, S)
            case .watch(let x): watchTower(&g, x, S)
            }
        }
        ghost(&g, S)
        shots(&g, S)
        effects(&g, S)
    }

    // MARK: The land

    private func land(_ g: inout GraphicsContext, _ S: CGFloat, _ seen: CGRect) {
        if drawsLand, let image = WallLand.image(field) {
            let r = WallLand.rect
            let magnified = S * g.environment.displayScale / WallLand.px
            g.draw(Image(decorative: image, scale: 1).interpolation(magnified <= 1.3 ? .none : .medium),
                   in: CGRect(x: r.minX * S, y: r.minY * S, width: r.width * S, height: r.height * S))
        }
        // Water glints, moving.
        guard S >= 12 else { return }
        var glints = Path()
        for y in 0..<WallField.height { for x in 0..<WallField.width where field.ground(WallTile(x: x, y: y)) == .water && Art.hash(x, y + 5) % 2 == 0 {
            let phase = now * 0.9 + Double(Art.hash(x, y) % 100) / 16
            let a = (sin(phase) + 1) / 2
            guard a > 0.45 else { continue }
            let p = CGPoint(x: (CGFloat(x) + 0.2 + CGFloat(sin(phase * 0.5)) * 0.12) * S, y: (CGFloat(y) + 0.5) * S)
            glints.move(to: p); glints.addQuadCurve(to: CGPoint(x: p.x + S * 0.42, y: p.y), control: CGPoint(x: p.x + S * 0.21, y: p.y - S * 0.1))
        } }
        g.stroke(glints, with: .color(.white.opacity(0.55)), lineWidth: max(0.7, S * 0.035))
    }

    /// The ways from the gaps to the pass: faint dotted lines, the dots flowing towards the pass.
    private func ways(_ g: inout GraphicsContext, _ S: CGFloat) {
        guard !icon else { return }
        let placing = preview?.routes != nil
        func path(_ r: [WallTile]) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: (CGFloat(r.first?.x ?? 0) + 0.5) * S, y: -0.6 * S))
            for t in r { p.addLine(to: CGPoint(x: (CGFloat(t.x) + 0.5) * S, y: (CGFloat(t.y) + 0.5) * S)) }
            return p
        }
        let phase = CGFloat(now.truncatingRemainder(dividingBy: 100)) * S * 0.9
        for r in field.routes {
            let p = path(r)
            g.stroke(p, with: .color(Color(red: 0.98, green: 0.95, blue: 0.8).opacity(placing ? 0.14 : 0.2)), style: StrokeStyle(lineWidth: S * 0.2, lineCap: .round, lineJoin: .round))
            g.stroke(p, with: .color(.white.opacity(placing ? 0.3 : 0.62)), style: StrokeStyle(lineWidth: max(1.2, S * 0.07), lineCap: .round, lineJoin: .round, dash: [S * 0.1, S * 0.32], dashPhase: -phase))
        }
        if let routes = preview?.routes {
            for r in routes {
                let p = path(r)
                g.stroke(p, with: .color(Color(red: 1, green: 0.6, blue: 0.15).opacity(0.3)), style: StrokeStyle(lineWidth: S * 0.22, lineCap: .round, lineJoin: .round))
                g.stroke(p, with: .color(Color(red: 1, green: 0.72, blue: 0.2)), style: StrokeStyle(lineWidth: max(1.4, S * 0.08), lineCap: .round, lineJoin: .round, dash: [S * 0.14, S * 0.26], dashPhase: -phase))
            }
        }
    }

    /// Reach circles: the tower selected or under the mouse, and a beacon's glow on the towers it lifts.
    private func reaches(_ g: inout GraphicsContext, _ S: CGFloat) {
        for id in Set([selected, hoverTower].compactMap { $0 }) {
            guard let tw = field.tower(id), tw.kind != .barricade else { continue }
            let c = CGPoint(x: (CGFloat(tw.x) + 0.5) * S, y: (CGFloat(tw.y) + 0.5) * S)
            let r = CGFloat(tw.kind == .beacon ? tw.stats.range : field.range(of: tw)) * S
            circle(&g, c, r, S, beacon: tw.kind == .beacon, strong: id == selected)
            if tw.stats.minRange > 0 {
                let m = CGFloat(tw.stats.minRange) * S
                g.fill(Path(ellipseIn: CGRect(x: c.x - m, y: c.y - m, width: 2 * m, height: 2 * m)), with: .color(Color.red.opacity(0.12)))
            }
            if tw.kind == .beacon {
                for o in field.towers where o.kind.shoots && hypot(Double(o.x - tw.x), Double(o.y - tw.y)) <= tw.stats.range + 0.01 {
                    let p = CGRect(x: CGFloat(o.x) * S, y: CGFloat(o.y) * S, width: S, height: S).insetBy(dx: S * 0.04, dy: S * 0.04)
                    g.stroke(Path(roundedRect: p, cornerRadius: S * 0.2), with: .color(Self.c(Self.gold, 0.8)), lineWidth: max(1, S * 0.05))
                }
            }
        }
    }

    private func circle(_ g: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ S: CGFloat, beacon: Bool, strong: Bool) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        g.fill(Path(ellipseIn: rect), with: .color((beacon ? Color(red: 1, green: 0.7, blue: 0.3) : Color.white).opacity(strong ? 0.16 : 0.1)))
        g.stroke(Path(ellipseIn: rect), with: .color((beacon ? Color(red: 1, green: 0.62, blue: 0.2) : Color(red: 1, green: 0.92, blue: 0.6)).opacity(strong ? 0.95 : 0.6)),
                 style: StrokeStyle(lineWidth: max(1.2, S * 0.05), dash: [S * 0.22, S * 0.14]))
    }

    /// The tower being placed: its picture on the tile, green or red, its reach, and a word when it is refused.
    private func ghost(_ g: inout GraphicsContext, _ S: CGFloat) {
        guard let p = preview else { return }
        let r = CGRect(x: CGFloat(p.tile.x) * S, y: CGFloat(p.tile.y) * S, width: S, height: S)
        let blocked = p.refusal == .blocks
        let ok = p.refusal == nil
        let short: Bool = { if case .gold = p.refusal { return true }; return false }()
        let colour: Color = ok ? Color(red: 0.3, green: 0.9, blue: 0.4) : short ? Color(red: 1, green: 0.78, blue: 0.3) : Color(red: 1, green: 0.25, blue: 0.2)
        if p.refusal != .land, p.refusal != .outside, p.refusal != .taken {
            let s = p.kind.stats(0)
            let c = CGPoint(x: r.midX, y: r.midY)
            if p.kind != .barricade { circle(&g, c, CGFloat(s.range) * S, S, beacon: p.kind == .beacon, strong: true) }
            var ghost = g
            ghost.opacity = blocked ? 0.45 : 0.72
            tower(&ghost, WallTower(id: -1, kind: p.kind, x: p.tile.x, y: p.tile.y, hp: s.hp, invested: 0), S)
        }
        g.fill(Path(roundedRect: r.insetBy(dx: S * 0.04, dy: S * 0.04), cornerRadius: S * 0.18), with: .color(colour.opacity(0.28)))
        g.stroke(Path(roundedRect: r.insetBy(dx: S * 0.04, dy: S * 0.04), cornerRadius: S * 0.18), with: .color(colour), lineWidth: max(1.5, S * 0.07))
        if blocked {
            // A red cross, and the reason by the mouse.
            var x = Path()
            x.move(to: CGPoint(x: r.minX + S * 0.2, y: r.minY + S * 0.2)); x.addLine(to: CGPoint(x: r.maxX - S * 0.2, y: r.maxY - S * 0.2))
            x.move(to: CGPoint(x: r.maxX - S * 0.2, y: r.minY + S * 0.2)); x.addLine(to: CGPoint(x: r.minX + S * 0.2, y: r.maxY - S * 0.2))
            g.stroke(x, with: .color(Color(red: 1, green: 0.2, blue: 0.15)), style: StrokeStyle(lineWidth: max(2, S * 0.12), lineCap: .round))
            label(g, "会堵死去关口的路", at: CGPoint(x: r.midX, y: r.minY - S * 0.85), S: S, colour: Color(red: 1, green: 0.4, blue: 0.3))
        } else if ok, p.routes != nil {
            let before = field.pathLength
            let d = p.after - before
            label(g, d >= 0.5 ? String(format: "路 %.0f → %.0f 格", before, p.after) : "路不变", at: CGPoint(x: r.midX, y: r.minY - S * 1.35), S: S, colour: Color(red: 1, green: 0.85, blue: 0.4))
        }
    }

    private func label(_ g: GraphicsContext, _ text: String, at p: CGPoint, S: CGFloat, colour: Color) {
        let size = max(11, min(17, S * 0.42))
        let w = CGFloat(text.count) * size * 0.95 + size
        let r = CGRect(x: p.x - w / 2, y: p.y - size * 0.8, width: w, height: size * 1.6)
        g.fill(Path(roundedRect: r, cornerRadius: size * 0.8), with: .color(Color(red: 0.1, green: 0.08, blue: 0.08).opacity(0.78)))
        g.draw(Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundColor(colour), at: p)
    }

    /// A stone or brick face: one fill, one stroke of all its joints.
    private func bricks(_ g: inout GraphicsContext, _ r: CGRect, S: CGFloat, colour: RGB) {
        g.fill(Path(r), with: .color(Self.c(colour)))
        guard S >= 10 else { return }
        let rows = max(2, Int(r.height / (S * 0.13)))
        let h = r.height / CGFloat(rows)
        var p = Path()
        for row in 0..<rows {
            let y = r.minY + h * CGFloat(row)
            if row > 0 { p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)) }
            var x = r.minX + (row % 2 == 0 ? S * 0.24 : S * 0.12)
            while x < r.maxX { p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + h)); x += S * 0.24 }
        }
        g.stroke(p, with: .color(Self.c(Art.lit(colour, 0.72))), lineWidth: max(0.5, S * 0.018))
        g.fill(Path(CGRect(x: r.minX, y: r.maxY - max(1.5, S * 0.05), width: r.width, height: max(1.5, S * 0.05))), with: .color(.black.opacity(0.18)))
    }

    private func planks(_ g: inout GraphicsContext, _ r: CGRect, S: CGFloat, colour: RGB) {
        g.fill(Path(r), with: .color(Self.c(colour)))
        var p = Path()
        var x = r.minX + S * 0.14
        while x < r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += S * 0.14 }
        g.stroke(p, with: .color(Self.c(Art.lit(colour, 0.7))), lineWidth: max(0.5, S * 0.02))
    }

    // MARK: The Wall's standing parts

    /// The gate tower over the pass: a brick base on the walkway, two storeys of red pillars and white walls, and a
    /// double-eaved roof with upturned corners and a ridge; banners either side.
    private func gateTower(_ g: inout GraphicsContext, _ S: CGFloat) {
        let cx = CGFloat(WallField.gateX[0] + 1) * S
        let baseY = 18.95 * S
        // Brick platform on the walkway.
        let plat = CGRect(x: cx - S * 1.7, y: baseY - S * 0.55, width: S * 3.4, height: S * 0.55)
        g.fill(Path(CGRect(x: plat.minX + S * 0.2, y: plat.maxY - S * 0.1, width: plat.width + S * 0.2, height: S * 0.25)), with: .color(.black.opacity(0.2)))
        bricks(&g, plat, S: S * 0.7, colour: Self.brick)
        // First storey.
        let one = CGRect(x: cx - S * 1.35, y: plat.minY - S * 0.62, width: S * 2.7, height: S * 0.62)
        storey(&g, one, S, pillars: 5)
        roofBand(&g, over: one, S, overhang: S * 0.34, rise: S * 0.32)
        // Second storey.
        let two = CGRect(x: cx - S * 1.0, y: one.minY - S * 0.36 - S * 0.52, width: S * 2.0, height: S * 0.52)
        storey(&g, two, S, pillars: 4)
        hipRoof(&g, over: two, S, overhang: S * 0.36, rise: S * 0.62, colour: Self.roofTile)
        // A plaque.
        let plaque = CGRect(x: cx - S * 0.32, y: two.minY + S * 0.08, width: S * 0.64, height: S * 0.2)
        g.fill(Path(roundedRect: plaque, cornerRadius: S * 0.03), with: .color(Self.c((0.16, 0.2, 0.36))))
        g.stroke(Path(roundedRect: plaque, cornerRadius: S * 0.03), with: .color(Self.c(Self.gold)), lineWidth: max(0.6, S * 0.02))
        if S >= 18 { g.draw(Text("关").font(.system(size: S * 0.16, weight: .heavy)).foregroundColor(Self.c(Self.gold)), at: CGPoint(x: plaque.midX, y: plaque.midY)) }
        for x in [plat.minX + S * 0.12, plat.maxX - S * 0.12] { flag(&g, CGPoint(x: x, y: plat.minY + S * 0.02), S, colour: Self.han, char: "汉") }
    }

    private func storey(_ g: inout GraphicsContext, _ r: CGRect, _ S: CGFloat, pillars: Int) {
        g.fill(Path(r), with: .color(Self.c((0.93, 0.88, 0.78))))
        g.fill(Path(CGRect(x: r.minX, y: r.maxY - r.height * 0.3, width: r.width, height: r.height * 0.3)), with: .color(Self.c((0.62, 0.2, 0.15))))
        for k in 0..<pillars {
            let x = r.minX + r.width * CGFloat(k) / CGFloat(pillars - 1)
            g.fill(Path(CGRect(x: x - S * 0.05, y: r.minY, width: S * 0.1, height: r.height)), with: .color(Self.c(Self.red)))
        }
        // Lattice windows.
        for k in 0..<(pillars - 1) {
            let x0 = r.minX + r.width * (CGFloat(k) + 0.25) / CGFloat(pillars - 1), w = r.width * 0.5 / CGFloat(pillars - 1)
            let win = CGRect(x: x0, y: r.minY + r.height * 0.15, width: w, height: r.height * 0.42)
            g.fill(Path(win), with: .color(Self.c((0.42, 0.26, 0.18))))
            if S >= 16 {
                var l = Path()
                for j in 1..<3 { let xx = win.minX + win.width * CGFloat(j) / 3; l.move(to: CGPoint(x: xx, y: win.minY)); l.addLine(to: CGPoint(x: xx, y: win.maxY)) }
                l.move(to: CGPoint(x: win.minX, y: win.midY)); l.addLine(to: CGPoint(x: win.maxX, y: win.midY))
                g.stroke(l, with: .color(Self.c((0.86, 0.66, 0.4))), lineWidth: max(0.5, S * 0.015))
            }
        }
        g.fill(Path(CGRect(x: r.minX - S * 0.05, y: r.minY, width: r.width + S * 0.1, height: S * 0.06)), with: .color(Self.c((0.28, 0.5, 0.52))))
    }

    /// A band of roof between two storeys: a short slope with upturned ends.
    private func roofBand(_ g: inout GraphicsContext, over r: CGRect, _ S: CGFloat, overhang: CGFloat, rise: CGFloat) {
        let l = r.minX - overhang, rr = r.maxX + overhang, eave = r.minY + S * 0.06
        let p = Path { q in
            q.move(to: CGPoint(x: l - S * 0.08, y: eave - S * 0.14))
            q.addQuadCurve(to: CGPoint(x: l + S * 0.3, y: eave), control: CGPoint(x: l, y: eave))
            q.addLine(to: CGPoint(x: rr - S * 0.3, y: eave))
            q.addQuadCurve(to: CGPoint(x: rr + S * 0.08, y: eave - S * 0.14), control: CGPoint(x: rr, y: eave))
            q.addLine(to: CGPoint(x: r.maxX - S * 0.1, y: eave - rise))
            q.addLine(to: CGPoint(x: r.minX + S * 0.1, y: eave - rise))
            q.closeSubpath()
        }
        g.fill(p, with: .color(Self.c(Self.roofTile)))
        g.fill(Path(CGRect(x: l + S * 0.2, y: eave - S * 0.06, width: rr - l - S * 0.4, height: S * 0.06)), with: .color(Self.c(Art.lit(Self.roofTile, 1.35))))
        tileLines(&g, p, from: r.minX, to: r.maxX, top: eave - rise, bottom: eave, S)
    }

    /// A hip roof with curving upturned eaves (a Han hall's roof): the front slope, its tiles, the ridge with its ends.
    private func hipRoof(_ g: inout GraphicsContext, over r: CGRect, _ S: CGFloat, overhang: CGFloat, rise: CGFloat, colour: RGB, ridge: Bool = true) {
        let l = r.minX - overhang, rr = r.maxX + overhang, eave = r.minY + S * 0.05
        let top = eave - rise, inset = (r.width + 2 * overhang) * 0.24
        let front = Path { q in
            q.move(to: CGPoint(x: l - S * 0.1, y: eave - S * 0.18))
            q.addQuadCurve(to: CGPoint(x: l + S * 0.28, y: eave), control: CGPoint(x: l - S * 0.02, y: eave))
            q.addLine(to: CGPoint(x: rr - S * 0.28, y: eave))
            q.addQuadCurve(to: CGPoint(x: rr + S * 0.1, y: eave - S * 0.18), control: CGPoint(x: rr + S * 0.02, y: eave))
            q.addQuadCurve(to: CGPoint(x: rr - inset, y: top), control: CGPoint(x: rr - inset * 0.55, y: eave - rise * 0.35))
            q.addLine(to: CGPoint(x: l + inset, y: top))
            q.addQuadCurve(to: CGPoint(x: l - S * 0.1, y: eave - S * 0.18), control: CGPoint(x: l + inset * 0.55, y: eave - rise * 0.35))
            q.closeSubpath()
        }
        g.fill(front, with: .color(Self.c(colour)))
        // The right half in shade.
        var shade = g
        shade.clip(to: Path(CGRect(x: (l + rr) / 2 + S * 0.1, y: top - S, width: rr - l, height: rise + S * 2)))
        shade.fill(front, with: .color(.black.opacity(0.14)))
        tileLines(&g, front, from: l, to: rr, top: top, bottom: eave, S)
        g.fill(Path(CGRect(x: l + S * 0.25, y: eave - S * 0.05, width: rr - l - S * 0.5, height: S * 0.05)), with: .color(Self.c(Art.lit(colour, 1.4))))
        if ridge {
            let rw = max(1.2, S * 0.07)
            g.stroke(Path { q in q.move(to: CGPoint(x: l + inset - S * 0.04, y: top)); q.addLine(to: CGPoint(x: rr - inset + S * 0.04, y: top)) }, with: .color(Self.c(Art.lit(colour, 0.7))), style: StrokeStyle(lineWidth: rw * 1.6, lineCap: .round))
            for (x, f) in [(l + inset, CGFloat(-1)), (rr - inset, CGFloat(1))] {
                g.stroke(Path { q in q.move(to: CGPoint(x: x, y: top)); q.addQuadCurve(to: CGPoint(x: x + f * S * 0.1, y: top - S * 0.14), control: CGPoint(x: x + f * S * 0.1, y: top)) },
                         with: .color(Self.c(Art.lit(colour, 0.7))), style: StrokeStyle(lineWidth: rw * 1.3, lineCap: .round))
            }
        }
    }

    private func tileLines(_ g: inout GraphicsContext, _ roof: Path, from l: CGFloat, to r: CGFloat, top: CGFloat, bottom: CGFloat, _ S: CGFloat) {
        guard S >= 14 else { return }
        var clipped = g
        clipped.clip(to: roof)
        var p = Path()
        var x = l
        while x < r { p.move(to: CGPoint(x: x, y: bottom)); p.addLine(to: CGPoint(x: x + (x - (l + r) / 2) * 0.12, y: top)); x += S * 0.13 }
        clipped.stroke(p, with: .color(.black.opacity(0.22)), lineWidth: max(0.5, S * 0.018))
    }

    /// A banner on a pole: a red field with a character.
    private func flag(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, colour: RGB, char: String? = nil, height: CGFloat = 1.1) {
        let top = CGPoint(x: foot.x, y: foot.y - S * height)
        g.stroke(Path { p in p.move(to: foot); p.addLine(to: top) }, with: .color(Self.c((0.28, 0.2, 0.14))), lineWidth: max(1, S * 0.045))
        let wave = CGFloat(sin(now * 3.4 + Double(foot.x) * 0.1)) * S * 0.05
        let w = S * 0.46, h = S * 0.36
        let cloth = Path { p in
            p.move(to: CGPoint(x: top.x, y: top.y + S * 0.04))
            p.addQuadCurve(to: CGPoint(x: top.x + w, y: top.y + S * 0.04 + wave), control: CGPoint(x: top.x + w / 2, y: top.y - wave))
            p.addLine(to: CGPoint(x: top.x + w - S * 0.04, y: top.y + h + wave))
            p.addQuadCurve(to: CGPoint(x: top.x, y: top.y + h), control: CGPoint(x: top.x + w / 2, y: top.y + h - wave))
            p.closeSubpath()
        }
        g.fill(cloth, with: .color(Self.c(colour)))
        g.stroke(cloth, with: .color(Self.c(Self.gold, 0.8)), lineWidth: max(0.5, S * 0.02))
        if char != nil {
            // An emblem: a gold ring with a bar, cheaper than a character drawn every frame.
            let e = CGPoint(x: top.x + w * 0.46, y: top.y + h * 0.52 + wave * 0.4), r = S * 0.09
            g.stroke(Path(ellipseIn: CGRect(x: e.x - r, y: e.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.c(Self.gold)), lineWidth: max(0.6, S * 0.03))
            g.fill(Path(CGRect(x: e.x - r * 0.55, y: e.y - r * 0.15, width: r * 1.1, height: r * 0.3)), with: .color(Self.c(Self.gold)))
        }
        g.fill(Path(ellipseIn: CGRect(x: top.x - S * 0.04, y: top.y - S * 0.06, width: S * 0.08, height: S * 0.08)), with: .color(Self.c(Self.gold)))
    }

    /// A watch-tower (敌楼) standing on the Wall.
    private func watchTower(_ g: inout GraphicsContext, _ x: Double, _ S: CGFloat) {
        let cx = CGFloat(x) * S, base = 19.0 * S
        let body = CGRect(x: cx - S * 0.8, y: base - S * 1.05, width: S * 1.6, height: S * 1.05)
        g.fill(Path(CGRect(x: body.maxX, y: body.minY + S * 0.2, width: S * 0.3, height: body.height)), with: .color(.black.opacity(0.16)))
        bricks(&g, body, S: S * 0.7, colour: Self.brick)
        for k in 0..<2 {
            let w = CGRect(x: body.minX + S * 0.3 + CGFloat(k) * S * 0.7, y: body.minY + S * 0.3, width: S * 0.28, height: S * 0.34)
            g.fill(Path(roundedRect: w, cornerRadii: RectangleCornerRadii(topLeading: S * 0.14, bottomLeading: 0, bottomTrailing: 0, topTrailing: S * 0.14)), with: .color(Self.c((0.18, 0.14, 0.12))))
        }
        merlons(&g, from: body.minX, to: body.maxX, y: body.minY, S, colour: Self.brick)
    }

    private func merlons(_ g: inout GraphicsContext, from l: CGFloat, to r: CGFloat, y: CGFloat, _ S: CGFloat, colour: RGB) {
        var p = Path(), top = Path()
        var x = l
        while x < r - S * 0.1 {
            let w = min(S * 0.24, r - x)
            p.addRect(CGRect(x: x, y: y - S * 0.24, width: w, height: S * 0.24))
            top.addRect(CGRect(x: x, y: y - S * 0.24, width: w, height: S * 0.06))
            x += S * 0.38
        }
        g.fill(p, with: .color(Self.c(colour)))
        g.fill(top, with: .color(Self.c(Art.lit(colour, 1.2))))
    }

    // MARK: Towers

    /// A tower standing on its tile: its foot at the bottom middle.
    func tower(_ g: inout GraphicsContext, _ tw: WallTower, _ S: CGFloat) {
        let F = CGRect(x: CGFloat(tw.x) * S, y: CGFloat(tw.y) * S, width: S, height: S)
        let foot = CGPoint(x: F.midX, y: F.maxY - S * 0.1)
        let since = t - tw.fired
        switch tw.kind {
        case .arrow: arrowTower(&g, foot, S, tw.level, since: since, angle: tw.angle)
        case .ballista: ballista(&g, foot, S, tw.level, since: since, angle: tw.angle, reload: tw.cooldown * tw.stats.rate)
        case .trebuchet: trebuchet(&g, foot, S, tw.level, since: since, angle: tw.angle)
        case .fire: fireTower(&g, foot, S, tw.level, since: since)
        case .beacon: beacon(&g, foot, S, tw.level, seed: tw.id)
        case .barricade: barricade(&g, foot, S, tw.level, health: tw.hp / tw.stats.hp)
        }
        if !icon {
            if tw.level > 0 { pips(&g, CGPoint(x: foot.x, y: foot.y + S * 0.02), tw.level, S) }
            if tw.hp < tw.stats.hp - 1 {
                let f = tw.hp / tw.stats.hp
                Art.bar(&g, CGRect(x: F.minX + S * 0.15, y: F.minY - S * (tw.kind == .barricade ? 0.1 : 1.1), width: S * 0.7, height: max(3, S * 0.09)), f,
                        colour: f > 0.5 ? Color(red: 0.4, green: 0.85, blue: 0.4) : f > 0.25 ? Color(red: 1, green: 0.75, blue: 0.2) : Color(red: 1, green: 0.3, blue: 0.2))
            }
            if tw.id == selected {
                g.stroke(Path(roundedRect: F.insetBy(dx: -S * 0.02, dy: -S * 0.02), cornerRadius: S * 0.2), with: .color(Color(red: 1, green: 0.9, blue: 0.4)), lineWidth: max(1.5, S * 0.07))
            }
        }
    }

    private func pips(_ g: inout GraphicsContext, _ p: CGPoint, _ level: Int, _ S: CGFloat) {
        let r = max(2, S * 0.07)
        for k in 0..<level {
            let x = p.x + (CGFloat(k) - CGFloat(level - 1) / 2) * r * 2.6
            let d = Path { q in q.move(to: CGPoint(x: x, y: p.y - r)); q.addLine(to: CGPoint(x: x + r, y: p.y)); q.addLine(to: CGPoint(x: x, y: p.y + r)); q.addLine(to: CGPoint(x: x - r, y: p.y)); q.closeSubpath() }
            g.fill(d, with: .color(Self.c(Self.gold)))
            g.stroke(d, with: .color(Self.c((0.45, 0.3, 0.1))), lineWidth: max(0.5, r * 0.3))
        }
    }

    private func plinth(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, width: CGFloat, height: CGFloat, colour: RGB = WallScene.stone) -> CGRect {
        g.fill(Path(ellipseIn: CGRect(x: foot.x - width * 0.5, y: foot.y - S * 0.1, width: width * 1.3, height: S * 0.26)), with: .color(.black.opacity(0.24)))
        let top = CGRect(x: foot.x - width / 2, y: foot.y - height - S * 0.16, width: width, height: S * 0.2)
        let face = CGRect(x: foot.x - width / 2, y: foot.y - height, width: width, height: height)
        bricks(&g, face, S: S * 0.6, colour: colour)
        g.fill(Path(roundedRect: top, cornerRadius: S * 0.04), with: .color(Self.c(Art.lit(colour, 1.15))))
        return CGRect(x: face.minX, y: top.minY, width: face.width, height: face.maxY - top.minY)
    }

    /// 箭楼: a timber watch-tower on a stone plinth, a railed platform with an archer, a Han roof and a red banner.
    private func arrowTower(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ level: Int, since: Double, angle: Double) {
        let base = plinth(&g, foot, S, width: S * 0.78, height: S * (level >= 1 ? 0.3 : 0.16), colour: level >= 1 ? Self.stone : (0.6, 0.55, 0.48))
        let legTop = base.minY - S * (0.62 + 0.08 * CGFloat(level))
        let l = foot.x - S * 0.3, r = foot.x + S * 0.3
        var legs = Path()
        for x in [l, r] { legs.move(to: CGPoint(x: x, y: base.minY + S * 0.06)); legs.addLine(to: CGPoint(x: x + (x < foot.x ? S * 0.04 : -S * 0.04), y: legTop)) }
        g.stroke(legs, with: .color(Self.c(Self.timberDark)), lineWidth: max(1.2, S * 0.08))
        var braces = Path()
        braces.move(to: CGPoint(x: l, y: base.minY)); braces.addLine(to: CGPoint(x: r - S * 0.04, y: legTop + S * 0.1))
        braces.move(to: CGPoint(x: r, y: base.minY)); braces.addLine(to: CGPoint(x: l + S * 0.04, y: legTop + S * 0.1))
        g.stroke(braces, with: .color(Self.c(Self.timber)), lineWidth: max(0.8, S * 0.045))
        // The platform box.
        let box = CGRect(x: foot.x - S * 0.4, y: legTop - S * 0.3, width: S * 0.8, height: S * 0.34)
        // The archer behind the parapet.
        let aim = CGFloat(cos(angle) >= 0 ? 1 : -1)
        let head = CGPoint(x: foot.x + aim * S * 0.08, y: box.minY - S * 0.1)
        g.fill(Path(ellipseIn: CGRect(x: head.x - S * 0.1, y: head.y - S * 0.1, width: S * 0.2, height: S * 0.2)), with: .color(Self.c((0.92, 0.76, 0.6))))
        g.fill(Path(ellipseIn: CGRect(x: head.x - S * 0.11, y: head.y - S * 0.14, width: S * 0.22, height: S * 0.11)), with: .color(Self.c((0.2, 0.2, 0.24))))
        if since < 0.25 {
            g.stroke(Path { p in p.addArc(center: CGPoint(x: head.x + aim * S * 0.14, y: head.y + S * 0.06), radius: S * 0.14, startAngle: .degrees(aim > 0 ? -70 : 110), endAngle: .degrees(aim > 0 ? 70 : 250), clockwise: false) },
                     with: .color(Self.c((0.45, 0.28, 0.12))), lineWidth: max(0.8, S * 0.035))
        }
        planks(&g, box, S: S * 0.7, colour: Self.timber)
        g.fill(Path(CGRect(x: box.minX - S * 0.03, y: box.minY - S * 0.03, width: box.width + S * 0.06, height: S * 0.06)), with: .color(Self.c(Self.timberDark)))
        g.fill(Path(CGRect(x: box.midX - S * 0.04, y: box.minY + S * 0.1, width: S * 0.08, height: S * 0.16)), with: .color(Self.c((0.14, 0.1, 0.08))))
        // Roof on four posts.
        let postTop = box.minY - S * 0.34
        var posts = Path()
        for x in [box.minX + S * 0.04, box.maxX - S * 0.04] { posts.move(to: CGPoint(x: x, y: box.minY)); posts.addLine(to: CGPoint(x: x, y: postTop)) }
        g.stroke(posts, with: .color(Self.c(Self.red)), lineWidth: max(0.8, S * 0.045))
        let roofBase = CGRect(x: box.minX + S * 0.06, y: postTop, width: box.width - S * 0.12, height: S * 0.1)
        if level >= 2 {
            hipRoof(&g, over: roofBase, S, overhang: S * 0.14, rise: S * 0.16, colour: Self.roofTile, ridge: false)
            let upper = CGRect(x: roofBase.minX + S * 0.14, y: postTop - S * 0.2, width: roofBase.width - S * 0.28, height: S * 0.1)
            hipRoof(&g, over: upper, S, overhang: S * 0.12, rise: S * 0.2, colour: Self.roofTile)
            g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.05, y: upper.minY - S * 0.3, width: S * 0.1, height: S * 0.1)), with: .color(Self.c(Self.gold)))
        } else {
            hipRoof(&g, over: roofBase, S, overhang: S * 0.14, rise: S * 0.24, colour: level >= 1 ? Self.roofTile : (0.36, 0.28, 0.22))
        }
        flag(&g, CGPoint(x: box.maxX - S * 0.02, y: box.minY + S * 0.02), S * 0.7, colour: Self.han, height: 1.35)
    }

    /// 弩车: a great crossbow on a wheeled carriage on a stone platform, turning to aim, a bolt laid when loaded.
    private func ballista(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ level: Int, since: Double, angle: Double, reload: Double) {
        let base = plinth(&g, foot, S, width: S * 0.86, height: S * (0.2 + 0.06 * CGFloat(level)))
        // Carriage and wheels.
        let deck = CGRect(x: foot.x - S * 0.34, y: base.minY - S * 0.18, width: S * 0.68, height: S * 0.18)
        for x in [deck.minX + S * 0.04, deck.maxX - S * 0.2] {
            let w = CGRect(x: x, y: deck.maxY - S * 0.12, width: S * 0.18, height: S * 0.18)
            g.fill(Path(ellipseIn: w), with: .color(Self.c(Self.timberDark)))
            g.stroke(Path(ellipseIn: w.insetBy(dx: S * 0.03, dy: S * 0.03)), with: .color(Self.c(Self.timber)), lineWidth: max(0.6, S * 0.025))
        }
        g.fill(Path(roundedRect: deck, cornerRadius: S * 0.03), with: .color(Self.c(Self.timber)))
        g.fill(Path(CGRect(x: deck.minX, y: deck.minY, width: deck.width, height: S * 0.05)), with: .color(Self.c(Art.lit(Self.timber, 1.2))))
        // The bow turning: its stock along the aim, squashed in depth.
        let pivot = CGPoint(x: foot.x, y: deck.minY - S * 0.1)
        g.stroke(Path { p in p.move(to: CGPoint(x: pivot.x, y: deck.minY)); p.addLine(to: pivot) }, with: .color(Self.c(Self.timberDark)), lineWidth: max(1, S * 0.07))
        let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle)) * 0.6
        let len = S * (0.48 + 0.06 * CGFloat(level))
        let front = CGPoint(x: pivot.x + dx * len * 0.62, y: pivot.y + dy * len * 0.62), back = CGPoint(x: pivot.x - dx * len * 0.42, y: pivot.y - dy * len * 0.42)
        let recoil = since < 0.2 ? CGFloat(1 - since / 0.2) * S * 0.05 : 0
        g.stroke(Path { p in p.move(to: CGPoint(x: back.x - dx * recoil, y: back.y - dy * recoil)); p.addLine(to: front) }, with: .color(Self.c((0.4, 0.26, 0.15))), style: StrokeStyle(lineWidth: max(1.4, S * 0.09), lineCap: .round))
        // Bow arms across the front, bent back.
        let nx = -dy / 0.6 * 0.6, ny = dx * 0.6
        let span = S * (0.36 + 0.05 * CGFloat(level))
        let a1 = CGPoint(x: front.x + nx * span - dx * S * 0.12, y: front.y + ny * span - dy * S * 0.12)
        let a2 = CGPoint(x: front.x - nx * span - dx * S * 0.12, y: front.y - ny * span - dy * S * 0.12)
        let bowColour: RGB = level >= 2 ? (0.32, 0.32, 0.36) : (0.36, 0.22, 0.12)
        g.stroke(Path { p in p.move(to: a1); p.addQuadCurve(to: a2, control: CGPoint(x: front.x + dx * S * 0.1, y: front.y + dy * S * 0.1)) }, with: .color(Self.c(bowColour)), style: StrokeStyle(lineWidth: max(1.2, S * 0.07), lineCap: .round))
        let drawn = min(1, reload > 0 ? 1 - reload : 1)
        let nock = CGPoint(x: front.x - dx * S * (0.12 + 0.28 * CGFloat(drawn)), y: front.y - dy * S * (0.12 + 0.28 * CGFloat(drawn)))
        g.stroke(Path { p in p.move(to: a1); p.addLine(to: nock); p.addLine(to: a2) }, with: .color(.white.opacity(0.75)), lineWidth: max(0.5, S * 0.018))
        if drawn > 0.6 {
            g.stroke(Path { p in p.move(to: nock); p.addLine(to: CGPoint(x: front.x + dx * S * 0.18, y: front.y + dy * S * 0.18)) }, with: .color(Self.c((0.3, 0.3, 0.32))), lineWidth: max(1, S * 0.04))
        }
        if level >= 1 { g.fill(Path(ellipseIn: CGRect(x: pivot.x - S * 0.06, y: pivot.y - S * 0.06, width: S * 0.12, height: S * 0.12)), with: .color(Self.c((0.55, 0.55, 0.6)))) }
        flag(&g, CGPoint(x: deck.minX + S * 0.02, y: deck.minY), S * 0.6, colour: Self.han, height: 1.3)
    }

    /// 投石机: an A-frame of timber, a long throwing arm with a counterweight, swinging after each throw.
    private func trebuchet(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ level: Int, since: Double, angle: Double) {
        let base = plinth(&g, foot, S, width: S * 0.88, height: S * 0.14, colour: (0.58, 0.52, 0.44))
        let face: CGFloat = cos(angle) >= 0 ? 1 : -1
        let h = S * (0.95 + 0.1 * CGFloat(level))
        let pivot = CGPoint(x: foot.x, y: base.minY - h)
        // Frame: two A-legs, a crossbar.
        var frame = Path()
        for d in [-0.34, 0.34] as [CGFloat] { frame.move(to: CGPoint(x: foot.x + d * S, y: base.minY + S * 0.04)); frame.addLine(to: pivot) }
        frame.move(to: CGPoint(x: foot.x - S * 0.22, y: base.minY - h * 0.4)); frame.addLine(to: CGPoint(x: foot.x + S * 0.22, y: base.minY - h * 0.4))
        g.stroke(frame, with: .color(Self.c(Self.timberDark)), style: StrokeStyle(lineWidth: max(1.2, S * 0.075), lineCap: .round))
        // The arm: at rest the long end down behind, flung up forward after a throw, easing back as it reloads.
        let throwT = since < 0.35 ? since / 0.35 : max(0, 1 - (since - 0.35) / 1.4)
        let rest = Double.pi * 0.72, up = -Double.pi * 0.38
        let a = rest + (up - rest) * JevDraw.smooth(throwT)
        let long = S * (0.95 + 0.08 * CGFloat(level)), short = S * 0.36
        let tip = CGPoint(x: pivot.x + face * CGFloat(cos(a)) * long, y: pivot.y + CGFloat(sin(a)) * long * 0.9)
        let tail = CGPoint(x: pivot.x - face * CGFloat(cos(a)) * short, y: pivot.y - CGFloat(sin(a)) * short * 0.9)
        g.stroke(Path { p in p.move(to: tail); p.addLine(to: tip) }, with: .color(Self.c(Self.timber)), style: StrokeStyle(lineWidth: max(1.2, S * 0.07), lineCap: .round))
        // Counterweight box.
        let box = CGRect(x: tail.x - S * 0.15, y: tail.y - S * 0.02, width: S * 0.3, height: S * 0.26)
        g.fill(Path(roundedRect: box, cornerRadius: S * 0.03), with: .color(Self.c(level >= 1 ? (0.4, 0.4, 0.44) : Self.timberDark)))
        g.stroke(Path(roundedRect: box, cornerRadius: S * 0.03), with: .color(.black.opacity(0.3)), lineWidth: max(0.5, S * 0.02))
        // The sling with its stone, when loaded.
        if since > 1.2 {
            let stone = CGPoint(x: tip.x - face * S * 0.08, y: tip.y + S * 0.16)
            g.stroke(Path { p in p.move(to: tip); p.addLine(to: stone) }, with: .color(Self.c((0.7, 0.62, 0.48))), lineWidth: max(0.5, S * 0.02))
            g.fill(Path(ellipseIn: CGRect(x: stone.x - S * 0.08, y: stone.y - S * 0.06, width: S * 0.16, height: S * 0.14)), with: .color(Self.c((0.5, 0.48, 0.46))))
        }
        g.fill(Path(ellipseIn: CGRect(x: pivot.x - S * 0.05, y: pivot.y - S * 0.05, width: S * 0.1, height: S * 0.1)), with: .color(Self.c((0.3, 0.3, 0.34))))
        // A pile of stones at its foot.
        for k in 0..<(2 + level) {
            let p = CGPoint(x: foot.x - face * S * (0.26 - CGFloat(k) * 0.1), y: foot.y - S * 0.06 - CGFloat(k % 2) * S * 0.06)
            g.fill(Path(ellipseIn: CGRect(x: p.x - S * 0.07, y: p.y - S * 0.06, width: S * 0.14, height: S * 0.12)), with: .color(Self.c(k % 2 == 0 ? (0.56, 0.54, 0.5) : (0.46, 0.44, 0.42))))
        }
        if level >= 2 { flag(&g, CGPoint(x: foot.x + face * S * 0.38, y: base.minY + S * 0.04), S * 0.6, colour: Self.han, height: 1.4) }
    }

    /// 火油: a squat stone fire-tower with a bronze cauldron blazing on top and jars of oil stacked beside.
    private func fireTower(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ level: Int, since: Double) {
        let base = plinth(&g, foot, S, width: S * 0.72, height: S * (0.42 + 0.08 * CGFloat(level)), colour: (0.56, 0.5, 0.46))
        // Soot on the stone.
        g.fill(Path(ellipseIn: CGRect(x: base.midX - S * 0.2, y: base.minY + S * 0.05, width: S * 0.4, height: S * 0.2)), with: .color(.black.opacity(0.18)))
        // The cauldron.
        let pot = CGRect(x: foot.x - S * 0.28, y: base.minY - S * 0.24, width: S * 0.56, height: S * 0.3)
        g.fill(Path { p in
            p.move(to: CGPoint(x: pot.minX, y: pot.minY)); p.addLine(to: CGPoint(x: pot.maxX, y: pot.minY))
            p.addQuadCurve(to: CGPoint(x: pot.midX, y: pot.maxY), control: CGPoint(x: pot.maxX, y: pot.maxY)); p.addQuadCurve(to: CGPoint(x: pot.minX, y: pot.minY), control: CGPoint(x: pot.minX, y: pot.maxY)); p.closeSubpath()
        }, with: .color(Self.c((0.58, 0.42, 0.2))))
        g.fill(Path(ellipseIn: CGRect(x: pot.minX, y: pot.minY - S * 0.05, width: pot.width, height: S * 0.1)), with: .color(Self.c((0.3, 0.14, 0.06))))
        g.fill(Path(CGRect(x: pot.minX + S * 0.05, y: pot.minY + S * 0.06, width: pot.width - S * 0.1, height: S * 0.035)), with: .color(Self.c((0.78, 0.6, 0.3))))
        // Flames.
        let big = 1 + (since < 0.3 ? 0.5 * (1 - since / 0.3) : 0) + 0.12 * Double(level)
        flames(&g, CGPoint(x: pot.midX, y: pot.minY), S * 0.3 * CGFloat(big), seed: Int(foot.x))
        // Jars.
        for k in 0..<(2 + level) {
            let x = foot.x + (k % 2 == 0 ? S * 0.36 : -S * 0.42) + CGFloat(k / 2) * S * 0.06
            let y = foot.y - S * 0.02 - CGFloat(k / 2) * S * 0.08
            let jar = CGRect(x: x - S * 0.09, y: y - S * 0.22, width: S * 0.18, height: S * 0.22)
            g.fill(Path(ellipseIn: jar), with: .color(Self.c((0.52, 0.3, 0.16))))
            g.fill(Path(CGRect(x: jar.midX - S * 0.04, y: jar.minY - S * 0.04, width: S * 0.08, height: S * 0.06)), with: .color(Self.c((0.4, 0.22, 0.12))))
            g.fill(Path(ellipseIn: CGRect(x: jar.minX + S * 0.03, y: jar.minY + S * 0.05, width: S * 0.05, height: S * 0.08)), with: .color(.white.opacity(0.25)))
        }
    }

    func flames(_ g: inout GraphicsContext, _ at: CGPoint, _ size: CGFloat, seed: Int) {
        let colours: [(Double, Double, Double)] = [(0.9, 0.25, 0.05), (1, 0.55, 0.1), (1, 0.85, 0.35)]
        for (k, col) in colours.enumerated() {
            let s = size * CGFloat(1 - Double(k) * 0.28)
            let flick = CGFloat(sin(now * 13 + Double(seed + k * 7))) * s * 0.12
            let p = Path { q in
                q.move(to: CGPoint(x: at.x - s * 0.5, y: at.y))
                q.addQuadCurve(to: CGPoint(x: at.x + flick, y: at.y - s * 1.3), control: CGPoint(x: at.x - s * 0.55, y: at.y - s * 0.7))
                q.addQuadCurve(to: CGPoint(x: at.x + s * 0.5, y: at.y), control: CGPoint(x: at.x + s * 0.55, y: at.y - s * 0.7))
                q.closeSubpath()
            }
            g.fill(p, with: .color(Color(red: col.0, green: col.1, blue: col.2).opacity(0.95)))
        }
    }

    /// 烽火台: a tapering tower of rammed earth, a fire basket on top and a column of smoke rising.
    private func beacon(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ level: Int, seed: Int) {
        let h = S * (1.25 + 0.15 * CGFloat(level))
        g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.4, y: foot.y - S * 0.1, width: S * 1.05, height: S * 0.26)), with: .color(.black.opacity(0.24)))
        let bw = S * 0.8, tw = S * 0.52
        let body = Path { p in
            p.move(to: CGPoint(x: foot.x - bw / 2, y: foot.y)); p.addLine(to: CGPoint(x: foot.x + bw / 2, y: foot.y))
            p.addLine(to: CGPoint(x: foot.x + tw / 2, y: foot.y - h)); p.addLine(to: CGPoint(x: foot.x - tw / 2, y: foot.y - h)); p.closeSubpath()
        }
        let earth: RGB = (0.74, 0.6, 0.42)
        g.fill(body, with: .color(Self.c(earth)))
        var right = g
        right.clip(to: Path(CGRect(x: foot.x + S * 0.08, y: foot.y - h - S, width: S, height: h + S * 2)))
        right.fill(body, with: .color(.black.opacity(0.12)))
        // Layers of rammed earth.
        var layers = Path()
        var y = foot.y - S * 0.13
        while y > foot.y - h + S * 0.05 { let f = (foot.y - y) / h; let half = bw / 2 - (bw - tw) / 2 * f; layers.move(to: CGPoint(x: foot.x - half, y: y)); layers.addLine(to: CGPoint(x: foot.x + half, y: y)); y -= S * 0.13 }
        g.stroke(layers, with: .color(Self.c(Art.lit(earth, 0.78))), lineWidth: max(0.5, S * 0.02))
        // The door.
        g.fill(Path(roundedRect: CGRect(x: foot.x - S * 0.1, y: foot.y - S * 0.3, width: S * 0.2, height: S * 0.3), cornerRadii: RectangleCornerRadii(topLeading: S * 0.1, bottomLeading: 0, bottomTrailing: 0, topTrailing: S * 0.1)), with: .color(Self.c((0.26, 0.18, 0.12))))
        // Parapet and fire basket.
        let top = foot.y - h
        merlons(&g, from: foot.x - tw / 2, to: foot.x + tw / 2 + S * 0.05, y: top + S * 0.04, S * 0.7, colour: Art.lit(earth, 0.95))
        flames(&g, CGPoint(x: foot.x, y: top - S * 0.06), S * (0.22 + 0.04 * CGFloat(level)), seed: seed)
        // Smoke.
        guard !icon || true else { return }
        for k in 0..<5 {
            let t0 = (now * 0.3 + Double(k) * 0.2 + Double(seed % 7) / 7).truncatingRemainder(dividingBy: 1)
            let q = CGPoint(x: foot.x + CGFloat(t0 * t0) * S * 0.9 + CGFloat(sin(now + Double(k))) * S * 0.05, y: top - S * 0.3 - CGFloat(t0) * S * (1.4 + 0.3 * CGFloat(level)))
            let rr = S * CGFloat(0.1 + t0 * 0.24)
            g.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(Color(white: 0.35 + 0.3 * t0).opacity(0.55 * (1 - t0))))
        }
        flag(&g, CGPoint(x: foot.x + tw / 2, y: top + S * 0.04), S * 0.6, colour: Self.han, height: 1.2)
    }

    /// 拒马: sharpened stakes crossed on a log, fewer and leaning as it is hacked down.
    private func barricade(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ level: Int, health: Double) {
        g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.45, y: foot.y - S * 0.12, width: S * 1.0, height: S * 0.24)), with: .color(.black.opacity(0.2)))
        let log = CGRect(x: foot.x - S * 0.44, y: foot.y - S * 0.3, width: S * 0.88, height: S * 0.14)
        let wood: RGB = level >= 2 ? (0.42, 0.3, 0.2) : (0.56, 0.4, 0.24)
        let n = max(1, Int((3 + Double(level)) * max(0.34, health) + 0.5))
        for k in 0..<n {
            let x = log.minX + S * 0.1 + (log.width - S * 0.2) * CGFloat(k) / CGFloat(max(1, n - 1))
            let lean = CGFloat(1 - health) * S * 0.1 * (k % 2 == 0 ? 1 : -1)
            for d in [-1.0, 1.0] as [CGFloat] {
                let bottom = CGPoint(x: x - d * S * 0.2, y: foot.y - S * 0.04)
                let tip = CGPoint(x: x + d * S * 0.2 + lean, y: foot.y - S * 0.62)
                g.stroke(Path { p in p.move(to: bottom); p.addLine(to: tip) }, with: .color(Self.c(d < 0 ? wood : Art.lit(wood, 0.8))), style: StrokeStyle(lineWidth: max(1.2, S * 0.07), lineCap: .round))
                g.fill(Path(ellipseIn: CGRect(x: tip.x - S * 0.03, y: tip.y - S * 0.03, width: S * 0.06, height: S * 0.06)), with: .color(Self.c(level >= 1 ? (0.72, 0.72, 0.76) : (0.86, 0.74, 0.54))))
            }
        }
        g.fill(Path(roundedRect: log, cornerRadius: S * 0.06), with: .color(Self.c(Self.timberDark)))
        g.fill(Path(ellipseIn: CGRect(x: log.maxX - S * 0.08, y: log.minY, width: S * 0.12, height: log.height)), with: .color(Self.c((0.82, 0.66, 0.44))))
        if level >= 1 {
            g.stroke(Path { p in p.move(to: CGPoint(x: log.minX + S * 0.2, y: log.minY)); p.addLine(to: CGPoint(x: log.minX + S * 0.2, y: log.maxY)); p.move(to: CGPoint(x: log.maxX - S * 0.25, y: log.minY)); p.addLine(to: CGPoint(x: log.maxX - S * 0.25, y: log.maxY)) },
                     with: .color(Self.c((0.5, 0.5, 0.55))), lineWidth: max(0.8, S * 0.04))
        }
    }

    // MARK: Enemies

    func enemy(_ g: inout GraphicsContext, _ e: WallEnemy, _ S: CGFloat) {
        let foot = CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S + S * 0.18)
        let f = e.facing
        let phase = t * 9 * e.speed + Double(e.seed)
        let flash = t - e.hit < 0.12
        let coat = Self.steppe[e.seed % Self.steppe.count]
        var top: CGFloat
        switch e.foe {
        case .cavalry:
            horse(&g, foot, S * 0.9, f, phase: phase, coat: [(0.46, 0.32, 0.2), (0.3, 0.22, 0.16), (0.7, 0.6, 0.48)][e.seed % 3], flash: flash)
            rider(&g, CGPoint(x: foot.x, y: foot.y - S * 0.34), S * 0.9, f, coat: coat, hat: .fur, weapon: .bow, flash: flash, seed: e.seed)
            top = foot.y - S * 1.05
        case .guard:
            horse(&g, foot, S * 0.95, f, phase: phase, coat: (0.14, 0.12, 0.12), flash: flash, barding: (0.55, 0.12, 0.1))
            rider(&g, CGPoint(x: foot.x, y: foot.y - S * 0.36), S * 0.95, f, coat: (0.24, 0.22, 0.24), hat: .helm, weapon: .lance, flash: flash, seed: e.seed)
            top = foot.y - S * 1.15
        case .foot:
            man(&g, foot, S * 0.72, f, phase: phase, coat: coat, hat: .fur, weapon: .sabre, flash: flash, seed: e.seed)
            top = foot.y - S * 0.78
        case .shield:
            man(&g, foot, S * 0.74, f, phase: phase, coat: (0.44, 0.4, 0.36), hat: .helm, weapon: .shield, flash: flash, seed: e.seed)
            top = foot.y - S * 0.8
        case .shaman:
            man(&g, foot, S * 0.74, f, phase: phase, coat: (0.5, 0.16, 0.24), hat: .feathers, weapon: .staff, flash: flash, seed: e.seed)
            if t - e.healed < 0.6 {
                let a = 1 - (t - e.healed) / 0.6
                let r = S * CGFloat(0.4 + (1 - a) * 1.4)
                g.stroke(Path(ellipseIn: CGRect(x: foot.x - r, y: foot.y - S * 0.3 - r * 0.6, width: 2 * r, height: 1.2 * r)), with: .color(Color(red: 0.4, green: 1, blue: 0.5).opacity(0.7 * a)), lineWidth: max(1, S * 0.05))
            }
            top = foot.y - S * 0.95
        case .siege:
            siege(&g, foot, S, f, phase: phase, flash: flash, ramming: t - e.ramming < 0.4)
            top = foot.y - S * 1.0
        case .chanyu:
            g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.9, y: foot.y - S * 0.3, width: S * 1.8, height: S * 0.6)), with: .color(Color(red: 1, green: 0.8, blue: 0.3).opacity(0.18 + 0.08 * sin(now * 4))))
            horse(&g, foot, S * 1.35, f, phase: phase, coat: (0.94, 0.92, 0.88), flash: flash, barding: (0.72, 0.12, 0.1))
            rider(&g, CGPoint(x: foot.x, y: foot.y - S * 0.5), S * 1.35, f, coat: (0.78, 0.6, 0.2), hat: .wolf, weapon: .sabre, flash: flash, seed: e.seed, cape: (0.72, 0.1, 0.08))
            wolfBanner(&g, CGPoint(x: foot.x - CGFloat(f) * S * 0.45, y: foot.y - S * 0.35), S)
            top = foot.y - S * 1.75
        }
        if t - e.burning < 0.3 { flames(&g, CGPoint(x: foot.x, y: foot.y - S * 0.1), S * 0.22, seed: e.seed) }
        if e.hp < e.maxHP || e.foe == .chanyu {
            let w = S * (e.foe == .chanyu ? 1.4 : e.foe == .siege ? 0.9 : 0.6)
            let fr = e.hp / e.maxHP
            Art.bar(&g, CGRect(x: foot.x - w / 2, y: top - S * 0.14, width: w, height: max(3, S * (e.foe == .chanyu ? 0.13 : 0.08))), fr,
                    colour: fr > 0.5 ? Color(red: 0.95, green: 0.3, blue: 0.25) : fr > 0.25 ? Color(red: 1, green: 0.6, blue: 0.2) : Color(red: 1, green: 0.85, blue: 0.3))
        }
    }

    enum Hat { case fur, helm, feathers, wolf }
    enum Weapon { case bow, sabre, shield, staff, lance }

    private func tint(_ c: RGB, _ flash: Bool) -> RGB { flash ? Art.mix(c, (1, 1, 1), 0.75) : c }

    private func horse(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ facing: Double, phase: Double, coat: RGB, flash: Bool, barding: RGB? = nil) {
        let f = CGFloat(facing >= 0 ? 1 : -1)
        let coat = tint(coat, flash)
        g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.45, y: foot.y - S * 0.1, width: S * 0.95, height: S * 0.22)), with: .color(.black.opacity(0.22)))
        let gallop = CGFloat(sin(phase)) * S * 0.1
        var legs = Path()
        for (dx, s) in [(-0.28, gallop), (-0.16, -gallop), (0.2, -gallop), (0.3, gallop)] as [(CGFloat, CGFloat)] {
            legs.move(to: CGPoint(x: foot.x + f * S * dx, y: foot.y - S * 0.3)); legs.addLine(to: CGPoint(x: foot.x + f * S * dx + s, y: foot.y))
        }
        g.stroke(legs, with: .color(Self.c(Art.lit(coat, 0.72))), style: StrokeStyle(lineWidth: max(1, S * 0.07), lineCap: .round))
        let bob = CGFloat(abs(sin(phase))) * S * 0.03
        let body = CGRect(x: foot.x - S * 0.38, y: foot.y - S * 0.54 - bob, width: S * 0.76, height: S * 0.3)
        g.fill(Path(roundedRect: body, cornerRadius: S * 0.14), with: .color(Self.c(coat)))
        g.fill(Path(roundedRect: CGRect(x: body.minX + S * 0.05, y: body.minY, width: body.width - S * 0.1, height: body.height * 0.4), cornerRadius: S * 0.1), with: .color(Self.c(Art.lit(coat, 1.15))))
        if let barding { g.fill(Path(roundedRect: CGRect(x: body.minX + S * 0.14, y: body.minY + S * 0.06, width: body.width - S * 0.3, height: body.height * 0.75), cornerRadius: S * 0.06), with: .color(Self.c(tint(barding, flash)))) }
        let neck = CGPoint(x: foot.x + f * S * 0.3, y: body.minY + S * 0.06)
        g.stroke(Path { p in p.move(to: neck); p.addLine(to: CGPoint(x: neck.x + f * S * 0.14, y: neck.y - S * 0.24)) }, with: .color(Self.c(coat)), style: StrokeStyle(lineWidth: max(1.5, S * 0.15), lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: neck.x + f * S * 0.1 - S * 0.1, y: neck.y - S * 0.36, width: S * 0.26, height: S * 0.14)), with: .color(Self.c(coat)))
        // Mane and tail.
        let dark = tint((0.16, 0.12, 0.1), flash)
        g.stroke(Path { p in p.move(to: CGPoint(x: neck.x - f * S * 0.02, y: neck.y)); p.addLine(to: CGPoint(x: neck.x + f * S * 0.1, y: neck.y - S * 0.26)) }, with: .color(Self.c(dark)), lineWidth: max(1, S * 0.05))
        g.stroke(Path { p in p.move(to: CGPoint(x: foot.x - f * S * 0.37, y: body.minY + S * 0.08)); p.addQuadCurve(to: CGPoint(x: foot.x - f * S * 0.52, y: body.maxY + S * 0.02), control: CGPoint(x: foot.x - f * S * 0.55 - gallop * 0.3, y: body.minY)) },
                 with: .color(Self.c(dark)), lineWidth: max(1, S * 0.06))
    }

    private func rider(_ g: inout GraphicsContext, _ seat: CGPoint, _ S: CGFloat, _ facing: Double, coat: RGB, hat: Hat, weapon: Weapon, flash: Bool, seed: Int, cape: RGB? = nil) {
        let f = CGFloat(facing >= 0 ? 1 : -1)
        let coat = tint(coat, flash)
        if let cape {
            let wave = CGFloat(sin(now * 6 + Double(seed))) * S * 0.04
            g.fill(Path { p in p.move(to: CGPoint(x: seat.x, y: seat.y - S * 0.42)); p.addQuadCurve(to: CGPoint(x: seat.x - f * S * 0.4, y: seat.y + S * 0.02 + wave), control: CGPoint(x: seat.x - f * S * 0.34, y: seat.y - S * 0.3)); p.addLine(to: CGPoint(x: seat.x - f * S * 0.02, y: seat.y - S * 0.05)); p.closeSubpath() },
                   with: .color(Self.c(tint(cape, flash))))
        }
        // Leg over the horse, body, arm.
        g.stroke(Path { p in p.move(to: CGPoint(x: seat.x, y: seat.y - S * 0.06)); p.addLine(to: CGPoint(x: seat.x + f * S * 0.06, y: seat.y + S * 0.14)) }, with: .color(Self.c(Art.lit(coat, 0.6))), style: StrokeStyle(lineWidth: max(1, S * 0.07), lineCap: .round))
        let body = CGRect(x: seat.x - S * 0.12, y: seat.y - S * 0.4, width: S * 0.24, height: S * 0.36)
        g.fill(Path(roundedRect: body, cornerRadius: S * 0.08), with: .color(Self.c(coat)))
        g.fill(Path(CGRect(x: body.minX, y: body.maxY - S * 0.1, width: body.width, height: S * 0.05)), with: .color(Self.c(tint((0.3, 0.2, 0.12), flash))))
        head(&g, CGPoint(x: seat.x + f * S * 0.02, y: body.minY - S * 0.1), S, f, hat: hat, flash: flash, seed: seed)
        weaponDraw(&g, CGPoint(x: seat.x + f * S * 0.12, y: body.minY + S * 0.1), S, f, weapon, flash: flash, mounted: true)
    }

    private func man(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ facing: Double, phase: Double, coat: RGB, hat: Hat, weapon: Weapon, flash: Bool, seed: Int) {
        let f = CGFloat(facing >= 0 ? 1 : -1)
        let coat = tint(coat, flash)
        g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.2, y: foot.y - S * 0.07, width: S * 0.46, height: S * 0.14)), with: .color(.black.opacity(0.22)))
        let step = CGFloat(sin(phase)) * S * 0.12
        let hip = CGPoint(x: foot.x, y: foot.y - S * 0.36)
        var legs = Path()
        legs.move(to: hip); legs.addLine(to: CGPoint(x: foot.x - S * 0.06 + step, y: foot.y))
        legs.move(to: hip); legs.addLine(to: CGPoint(x: foot.x + S * 0.06 - step, y: foot.y))
        g.stroke(legs, with: .color(Self.c(tint((0.28, 0.22, 0.18), flash))), style: StrokeStyle(lineWidth: max(1, S * 0.1), lineCap: .round))
        let body = CGRect(x: foot.x - S * 0.16, y: foot.y - S * 0.74, width: S * 0.32, height: S * 0.44)
        g.fill(Path(roundedRect: body, cornerRadius: S * 0.1), with: .color(Self.c(coat)))
        g.fill(Path(roundedRect: CGRect(x: body.minX, y: body.minY, width: body.width * 0.45, height: body.height), cornerRadius: S * 0.1), with: .color(Self.c(Art.lit(coat, 1.15))))
        g.fill(Path(CGRect(x: body.minX, y: body.midY + S * 0.04, width: body.width, height: S * 0.06)), with: .color(Self.c(tint((0.3, 0.2, 0.12), flash))))
        if hat != .feathers { g.fill(Path(CGRect(x: body.minX - S * 0.01, y: body.minY + S * 0.02, width: body.width + S * 0.02, height: S * 0.07)), with: .color(Self.c(tint((0.86, 0.8, 0.7), flash)))) }
        head(&g, CGPoint(x: foot.x + f * S * 0.01, y: body.minY - S * 0.11), S, f, hat: hat, flash: flash, seed: seed)
        weaponDraw(&g, CGPoint(x: foot.x + f * S * 0.14, y: body.minY + S * 0.14), S, f, weapon, flash: flash, mounted: false, phase: phase)
    }

    private func head(_ g: inout GraphicsContext, _ c: CGPoint, _ S: CGFloat, _ f: CGFloat, hat: Hat, flash: Bool, seed: Int) {
        let r = S * 0.12
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.c(tint((0.86, 0.66, 0.5), flash))))
        switch hat {
        case .fur:
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.25, y: c.y - r * 1.45, width: r * 2.5, height: r * 1.5)), with: .color(Self.c(tint((0.62, 0.46, 0.3), flash))))
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r * 1.9, width: r * 1.4, height: r * 1.0)), with: .color(Self.c(tint((0.34, 0.24, 0.3), flash))))
        case .helm:
            g.fill(Path { p in p.move(to: CGPoint(x: c.x - r * 1.15, y: c.y - r * 0.1)); p.addQuadCurve(to: CGPoint(x: c.x + r * 1.15, y: c.y - r * 0.1), control: CGPoint(x: c.x, y: c.y - r * 2.4)); p.closeSubpath() },
                   with: .color(Self.c(tint((0.5, 0.5, 0.54), flash))))
            g.stroke(Path { p in p.move(to: CGPoint(x: c.x, y: c.y - r * 1.2)); p.addLine(to: CGPoint(x: c.x - f * r * 0.3, y: c.y - r * 1.9)) }, with: .color(Self.c(tint((0.8, 0.16, 0.12), flash))), lineWidth: max(1, S * 0.04))
        case .feathers:
            for k in -2...2 {
                let a = Double(k) * 0.28 - Double.pi / 2
                g.stroke(Path { p in p.move(to: CGPoint(x: c.x, y: c.y - r * 0.6)); p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r * 2.1, y: c.y - r * 0.6 + CGFloat(sin(a)) * r * 2.1)) },
                         with: .color(Self.c(tint(k % 2 == 0 ? (0.95, 0.9, 0.8) : (0.2, 0.5, 0.45), flash))), style: StrokeStyle(lineWidth: max(1, S * 0.045), lineCap: .round))
            }
            g.fill(Path(CGRect(x: c.x - r * 1.05, y: c.y - r * 0.75, width: r * 2.1, height: r * 0.4)), with: .color(Self.c(tint((0.8, 0.3, 0.15), flash))))
        case .wolf:
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.2, y: c.y - r * 1.5, width: r * 2.4, height: r * 1.6)), with: .color(Self.c(tint((0.92, 0.74, 0.26), flash))))
            for d in [-0.6, 0.6] as [CGFloat] {
                g.fill(Path { p in p.move(to: CGPoint(x: c.x + d * r - r * 0.25, y: c.y - r * 1.2)); p.addLine(to: CGPoint(x: c.x + d * r * 1.1, y: c.y - r * 2.1)); p.addLine(to: CGPoint(x: c.x + d * r + r * 0.25, y: c.y - r * 1.2)); p.closeSubpath() },
                       with: .color(Self.c(tint((0.92, 0.74, 0.26), flash))))
            }
            g.fill(Path(ellipseIn: CGRect(x: c.x + f * r * 0.5, y: c.y - r * 1.05, width: r * 0.9, height: r * 0.55)), with: .color(Self.c(tint((0.8, 0.6, 0.18), flash))))
        }
    }

    private func weaponDraw(_ g: inout GraphicsContext, _ hand: CGPoint, _ S: CGFloat, _ f: CGFloat, _ w: Weapon, flash: Bool, mounted: Bool, phase: Double = 0) {
        switch w {
        case .bow:
            g.stroke(Path { p in p.addArc(center: CGPoint(x: hand.x + f * S * 0.04, y: hand.y), radius: S * 0.2, startAngle: .degrees(f > 0 ? -65 : 115), endAngle: .degrees(f > 0 ? 65 : 245), clockwise: false) },
                     with: .color(Self.c((0.42, 0.26, 0.12))), lineWidth: max(0.8, S * 0.04))
        case .sabre:
            let swing = CGFloat(sin(phase * 0.5)) * S * 0.06
            g.stroke(Path { p in p.move(to: hand); p.addQuadCurve(to: CGPoint(x: hand.x + f * S * 0.34, y: hand.y - S * 0.32 + swing), control: CGPoint(x: hand.x + f * S * 0.3, y: hand.y - S * 0.06)) },
                     with: .color(Self.c((0.86, 0.88, 0.92))), style: StrokeStyle(lineWidth: max(1, S * 0.045), lineCap: .round))
        case .shield:
            let c = CGPoint(x: hand.x + f * S * 0.06, y: hand.y + S * 0.08)
            let r = S * 0.24
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r, width: r * 1.6, height: r * 2)), with: .color(Self.c(tint((0.56, 0.4, 0.24), flash))))
            g.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r, width: r * 1.6, height: r * 2)), with: .color(Self.c(tint((0.3, 0.2, 0.12), flash))), lineWidth: max(1, S * 0.04))
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.25, y: c.y - r * 0.25, width: r * 0.5, height: r * 0.5)), with: .color(Self.c(tint((0.72, 0.72, 0.76), flash))))
            g.stroke(Path { p in p.move(to: CGPoint(x: c.x, y: c.y - r * 0.95)); p.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.95)) }, with: .color(Self.c(tint((0.36, 0.24, 0.14), flash))), lineWidth: max(0.5, S * 0.02))
        case .staff:
            g.stroke(Path { p in p.move(to: CGPoint(x: hand.x, y: hand.y + S * 0.3)); p.addLine(to: CGPoint(x: hand.x + f * S * 0.04, y: hand.y - S * 0.44)) }, with: .color(Self.c((0.44, 0.3, 0.18))), lineWidth: max(1, S * 0.04))
            g.fill(Path(ellipseIn: CGRect(x: hand.x + f * S * 0.04 - S * 0.07, y: hand.y - S * 0.52, width: S * 0.14, height: S * 0.14)), with: .color(Color(red: 0.4, green: 1, blue: 0.55).opacity(0.6 + 0.4 * sin(now * 5))))
        case .lance:
            g.stroke(Path { p in p.move(to: CGPoint(x: hand.x - f * S * 0.3, y: hand.y + S * 0.1)); p.addLine(to: CGPoint(x: hand.x + f * S * 0.62, y: hand.y - S * 0.3)) }, with: .color(Self.c((0.4, 0.28, 0.16))), lineWidth: max(1, S * 0.04))
            g.fill(Path(ellipseIn: CGRect(x: hand.x + f * S * 0.58 - S * 0.05, y: hand.y - S * 0.35, width: S * 0.1, height: S * 0.1)), with: .color(Self.c((0.85, 0.86, 0.9))))
        }
    }

    /// 攻城车: a covered ram on four wheels, hide over a peaked roof, the ram's iron head in front, two men pushing.
    private func siege(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ facing: Double, phase: Double, flash: Bool, ramming: Bool) {
        let f = CGFloat(facing >= 0 ? 1 : -1)
        g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.7, y: foot.y - S * 0.14, width: S * 1.5, height: S * 0.3)), with: .color(.black.opacity(0.26)))
        // Pushers behind.
        for k in 0..<2 {
            man(&g, CGPoint(x: foot.x - f * S * (0.62 + CGFloat(k) * 0.08), y: foot.y - CGFloat(k) * S * 0.12), S * 0.6, facing, phase: phase + Double(k) * 2, coat: Self.steppe[k], hat: .fur, weapon: .staff, flash: false, seed: k)
        }
        let body = CGRect(x: foot.x - S * 0.55, y: foot.y - S * 0.62, width: S * 1.1, height: S * 0.46)
        let wood = tint((0.46, 0.32, 0.2), flash)
        // Ram.
        let thrust = ramming ? CGFloat(sin(now * 18)) * S * 0.1 : 0
        g.stroke(Path { p in p.move(to: CGPoint(x: foot.x - f * S * 0.2, y: body.midY + S * 0.04)); p.addLine(to: CGPoint(x: foot.x + f * (S * 0.78 + thrust), y: body.midY + S * 0.04)) },
                 with: .color(Self.c(tint((0.36, 0.24, 0.14), flash))), style: StrokeStyle(lineWidth: max(2, S * 0.12), lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: foot.x + f * (S * 0.78 + thrust) - S * 0.1, y: body.midY - S * 0.06, width: S * 0.2, height: S * 0.2)), with: .color(Self.c((0.36, 0.36, 0.4))))
        g.fill(Path(body), with: .color(Self.c(wood)))
        var planks = Path()
        var x = body.minX + S * 0.14
        while x < body.maxX { planks.move(to: CGPoint(x: x, y: body.minY)); planks.addLine(to: CGPoint(x: x, y: body.maxY)); x += S * 0.16 }
        g.stroke(planks, with: .color(Self.c(Art.lit(wood, 0.7))), lineWidth: max(0.5, S * 0.02))
        // Hide roof.
        let hide = tint((0.62, 0.5, 0.36), flash)
        g.fill(Path { p in p.move(to: CGPoint(x: body.minX - S * 0.06, y: body.minY + S * 0.04)); p.addLine(to: CGPoint(x: body.midX, y: body.minY - S * 0.36)); p.addLine(to: CGPoint(x: body.maxX + S * 0.06, y: body.minY + S * 0.04)); p.closeSubpath() },
               with: .color(Self.c(hide)))
        g.fill(Path { p in p.move(to: CGPoint(x: body.midX, y: body.minY - S * 0.36)); p.addLine(to: CGPoint(x: body.maxX + S * 0.06, y: body.minY + S * 0.04)); p.addLine(to: CGPoint(x: body.midX, y: body.minY + S * 0.04)); p.closeSubpath() },
               with: .color(.black.opacity(0.14)))
        g.stroke(Path { p in for k in 1..<4 { let xx = body.minX + body.width * CGFloat(k) / 4; p.move(to: CGPoint(x: xx, y: body.minY + S * 0.04)); p.addLine(to: CGPoint(x: xx + (body.midX - xx) * 0.5, y: body.minY - S * 0.16)) } },
                 with: .color(Self.c((0.36, 0.26, 0.18))), lineWidth: max(0.5, S * 0.025))
        // Wheels.
        for wx in [body.minX + S * 0.18, body.maxX - S * 0.18] {
            let r = S * 0.17, c = CGPoint(x: wx, y: foot.y - S * 0.15)
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.c(tint((0.3, 0.2, 0.12), flash))))
            let a = phase * 0.4
            g.stroke(Path { p in for k in 0..<3 { let aa = a + Double(k) * .pi / 3; p.move(to: CGPoint(x: c.x - CGFloat(cos(aa)) * r, y: c.y - CGFloat(sin(aa)) * r)); p.addLine(to: CGPoint(x: c.x + CGFloat(cos(aa)) * r, y: c.y + CGFloat(sin(aa)) * r)) } },
                     with: .color(Self.c((0.55, 0.4, 0.24))), lineWidth: max(0.6, S * 0.03))
        }
    }

    /// The Chanyu's standard: a black banner with a golden wolf's head.
    private func wolfBanner(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat) {
        let top = CGPoint(x: foot.x, y: foot.y - S * 1.9)
        g.stroke(Path { p in p.move(to: foot); p.addLine(to: top) }, with: .color(Self.c((0.3, 0.22, 0.14))), lineWidth: max(1.2, S * 0.05))
        let wave = CGFloat(sin(now * 3)) * S * 0.06
        let cloth = Path { p in
            p.move(to: CGPoint(x: top.x, y: top.y + S * 0.05)); p.addQuadCurve(to: CGPoint(x: top.x + S * 0.6, y: top.y + S * 0.1 + wave), control: CGPoint(x: top.x + S * 0.3, y: top.y - wave))
            p.addLine(to: CGPoint(x: top.x + S * 0.5, y: top.y + S * 0.62 + wave)); p.addLine(to: CGPoint(x: top.x + S * 0.3, y: top.y + S * 0.5)); p.addLine(to: CGPoint(x: top.x, y: top.y + S * 0.62)); p.closeSubpath()
        }
        g.fill(cloth, with: .color(Self.c((0.14, 0.12, 0.14))))
        g.stroke(cloth, with: .color(Self.c(Self.gold)), lineWidth: max(0.6, S * 0.025))
        let h = CGPoint(x: top.x + S * 0.28, y: top.y + S * 0.3 + wave * 0.5)
        g.fill(Path { p in p.move(to: CGPoint(x: h.x - S * 0.12, y: h.y + S * 0.1)); p.addLine(to: CGPoint(x: h.x - S * 0.1, y: h.y - S * 0.12)); p.addLine(to: CGPoint(x: h.x - S * 0.02, y: h.y - S * 0.04)); p.addLine(to: CGPoint(x: h.x + S * 0.06, y: h.y - S * 0.12)); p.addLine(to: CGPoint(x: h.x + S * 0.08, y: h.y + S * 0.02)); p.addLine(to: CGPoint(x: h.x + S * 0.18, y: h.y + S * 0.08)); p.addLine(to: CGPoint(x: h.x, y: h.y + S * 0.16)); p.closeSubpath() },
               with: .color(Self.c(Self.gold)))
    }

    // MARK: On the ground: fire, the fallen

    private func fires(_ g: inout GraphicsContext, _ S: CGFloat) {
        for (k, fire) in field.fires.enumerated() {
            let c = CGPoint(x: CGFloat(fire.x) * S, y: CGFloat(fire.y) * S)
            let life = min(1, (fire.until - t) / 0.6, (t - fire.from) / 0.2 + 0.3)
            let r = CGFloat(fire.radius) * S
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.7, width: 2 * r, height: 1.4 * r)), with: .color(Color(red: 0.2, green: 0.1, blue: 0.05).opacity(0.35 * life)))
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.9, y: c.y - r * 0.62, width: 1.8 * r, height: 1.24 * r)), with: .color(Color(red: 1, green: 0.45, blue: 0.1).opacity(0.28 * life)))
            for j in 0..<5 {
                let a = Double(j) * 1.26 + Double(k)
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.55, y: c.y + CGFloat(sin(a)) * r * 0.38 + S * 0.08)
                var fl = g
                fl.opacity = life
                flames(&fl, p, S * CGFloat(0.16 + 0.06 * sin(now * 7 + a)), seed: j + k * 5)
            }
        }
    }

    private func fallen(_ g: inout GraphicsContext, _ S: CGFloat) {
        for e in field.effects {
            guard case .fallen(let foe, let facing) = e.kind else { continue }
            let age = t - e.at
            let fade = min(1, (e.life - age) / 0.7)
            let c = CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S + S * 0.12)
            let f = CGFloat(facing)
            let big: CGFloat = foe == .chanyu ? 1.4 : foe == .siege ? 1.3 : foe.mounted ? 1 : 0.7
            var h = g
            h.opacity = fade * 0.85
            if foe == .siege {
                h.fill(Path(roundedRect: CGRect(x: c.x - S * 0.5, y: c.y - S * 0.2, width: S * 1.0, height: S * 0.26), cornerRadius: S * 0.04), with: .color(Self.c((0.34, 0.24, 0.16))))
                h.fill(Path(ellipseIn: CGRect(x: c.x - S * 0.3, y: c.y - S * 0.4, width: S * 0.5, height: S * 0.3)), with: .color(Color(white: 0.35).opacity(0.5)))
                continue
            }
            if foe.mounted {
                h.fill(Path(ellipseIn: CGRect(x: c.x - S * 0.4 * big, y: c.y - S * 0.2 * big, width: S * 0.8 * big, height: S * 0.26 * big)), with: .color(Self.c(foe == .chanyu ? (0.86, 0.84, 0.8) : (0.4, 0.28, 0.18))))
            }
            h.fill(Path(roundedRect: CGRect(x: c.x - S * 0.26 * big + f * S * 0.1, y: c.y - S * 0.1 * big, width: S * 0.44 * big, height: S * 0.14 * big), cornerRadius: S * 0.05), with: .color(Self.c(foe == .shaman ? (0.5, 0.16, 0.24) : (0.5, 0.4, 0.3))))
            h.fill(Path(ellipseIn: CGRect(x: c.x + f * S * 0.22 * big, y: c.y - S * 0.1 * big, width: S * 0.13, height: S * 0.13)), with: .color(Self.c((0.86, 0.66, 0.5))))
        }
    }

    // MARK: In the air

    private func shots(_ g: inout GraphicsContext, _ S: CGFloat) {
        for s in field.shots {
            let x = CGFloat(s.x) * S, yGround = CGFloat(s.y) * S
            switch s.kind {
            case .arrow:
                let d = hypot(s.toX - s.fromX, s.toY - s.fromY)
                let lift = CGFloat(0.9 * (1 - s.t) + 0.5 * d * 0.25 * 4 * s.t * (1 - s.t)) * S
                let p = CGPoint(x: x, y: yGround - lift - S * 0.2)
                var dx = CGFloat(s.toX - s.fromX), dy = CGFloat(s.toY - s.fromY) * 0.8 - CGFloat(0.5 - s.t) * 0.9
                let L = max(0.01, hypot(dx, dy)); dx /= L; dy /= L
                let tail = CGPoint(x: p.x - dx * S * 0.36, y: p.y - dy * S * 0.36)
                g.stroke(Path { q in q.move(to: tail); q.addLine(to: p) }, with: .color(Self.c((0.3, 0.22, 0.14))), style: StrokeStyle(lineWidth: max(1, S * 0.035), lineCap: .round))
                g.stroke(Path { q in q.move(to: tail); q.addLine(to: CGPoint(x: tail.x + dx * S * 0.08, y: tail.y + dy * S * 0.08)) }, with: .color(.white), style: StrokeStyle(lineWidth: max(1.2, S * 0.06)))
            case .bolt:
                let p = CGPoint(x: x, y: yGround - S * 0.45)
                let dx = CGFloat(s.dx), dy = CGFloat(s.dy)
                let tail = CGPoint(x: p.x - dx * S * 0.62, y: p.y - dy * S * 0.62)
                g.stroke(Path { q in q.move(to: CGPoint(x: p.x - dx * S * 1.6, y: p.y - dy * S * 1.6)); q.addLine(to: tail) }, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: max(1, S * 0.05), lineCap: .round))
                g.stroke(Path { q in q.move(to: tail); q.addLine(to: p) }, with: .color(Self.c((0.34, 0.24, 0.14))), style: StrokeStyle(lineWidth: max(1.5, S * 0.07), lineCap: .round))
                g.fill(Path { q in q.move(to: CGPoint(x: p.x + dx * S * 0.14, y: p.y + dy * S * 0.14)); q.addLine(to: CGPoint(x: p.x - dy * S * 0.07, y: p.y + dx * S * 0.07)); q.addLine(to: CGPoint(x: p.x + dy * S * 0.07, y: p.y - dx * S * 0.07)); q.closeSubpath() },
                       with: .color(Self.c((0.7, 0.72, 0.76))))
            case .stone, .pot:
                let peak = s.kind == .stone ? 2.4 : 1.3
                let lift = CGFloat((s.kind == .stone ? 1.2 : 0.8) * (1 - s.t) + peak * 4 * s.t * (1 - s.t)) * S
                let r = S * (s.kind == .stone ? 0.16 : 0.13)
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: yGround - r * 0.4, width: 2 * r, height: r * 0.8)), with: .color(.black.opacity(0.22)))
                let p = CGPoint(x: x, y: yGround - lift)
                if s.kind == .stone {
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.c((0.46, 0.44, 0.42))))
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.6, y: p.y - r * 0.7, width: r * 0.8, height: r * 0.6)), with: .color(Self.c((0.66, 0.64, 0.6))))
                } else {
                    for k in 1...3 {
                        let back = Double(k) * 0.05
                        let tt = max(0, s.t - back)
                        let q = CGPoint(x: CGFloat(s.fromX + (s.toX - s.fromX) * tt) * S, y: CGFloat(s.fromY + (s.toY - s.fromY) * tt) * S - CGFloat(0.8 * (1 - tt) + peak * 4 * tt * (1 - tt)) * S)
                        let rr = r * CGFloat(1 - Double(k) * 0.22)
                        g.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(Color(red: 1, green: 0.5 + 0.1 * Double(k), blue: 0.1).opacity(0.7 - Double(k) * 0.18)))
                    }
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.c((0.5, 0.3, 0.16))))
                    flames(&g, CGPoint(x: p.x, y: p.y - r * 0.6), r * 1.1, seed: 3)
                }
            }
        }
    }

    private func effects(_ g: inout GraphicsContext, _ S: CGFloat) {
        for e in field.effects {
            let age = t - e.at
            let p = CGPoint(x: CGFloat(e.x) * S, y: CGFloat(e.y) * S)
            switch e.kind {
            case .blast(let size):
                JevDraw.blast(g, at: p, size: CGFloat(size) * S, age: age)
            case .dust(let size):
                let a = max(0, 1 - age / e.life)
                for k in 0..<4 {
                    let ang = Double(k) * 1.57 + 0.4
                    let r = CGFloat(size) * S * CGFloat(0.3 + age * 1.2)
                    let q = CGPoint(x: p.x + CGFloat(cos(ang)) * r * 0.6, y: p.y + CGFloat(sin(ang)) * r * 0.3 - CGFloat(age) * S * 0.4)
                    g.fill(Path(ellipseIn: CGRect(x: q.x - r * 0.5, y: q.y - r * 0.5, width: r, height: r)), with: .color(Color(red: 0.72, green: 0.66, blue: 0.56).opacity(0.55 * a)))
                }
            case .gold(let n):
                guard !icon else { continue }
                let a = max(0, 1 - age / e.life)
                JevDraw.text(g, "+\(n)", at: CGPoint(x: p.x, y: p.y - CGFloat(age) * S * 0.9), size: max(10, S * 0.36), colour: Color(red: 1, green: 0.86, blue: 0.3).opacity(a), shadow: a > 0.5)
            case .leak(let n):
                let a = max(0, 1 - age / e.life)
                JevDraw.text(g, "−\(n) ♥", at: CGPoint(x: p.x, y: p.y - S * 1.4 - CGFloat(age) * S * 0.9), size: max(12, S * 0.5), colour: Color(red: 1, green: 0.3, blue: 0.25).opacity(a))
            case .heal:
                let a = max(0, 1 - age / e.life)
                for k in 0..<3 {
                    let q = CGPoint(x: p.x + CGFloat(k - 1) * S * 0.3, y: p.y - S * 0.6 - CGFloat(age) * S * 0.8 - CGFloat(k % 2) * S * 0.15)
                    var plus = Path()
                    plus.move(to: CGPoint(x: q.x - S * 0.07, y: q.y)); plus.addLine(to: CGPoint(x: q.x + S * 0.07, y: q.y))
                    plus.move(to: CGPoint(x: q.x, y: q.y - S * 0.07)); plus.addLine(to: CGPoint(x: q.x, y: q.y + S * 0.07))
                    g.stroke(plus, with: .color(Color(red: 0.4, green: 1, blue: 0.5).opacity(a)), lineWidth: max(1.2, S * 0.05))
                }
            case .crumble(let kind):
                let a = max(0, 1 - age / e.life)
                for k in 0..<7 {
                    let ang = Double(Art.hash(k, kind.rawValue) % 628) / 100
                    let v = 0.6 + Double(Art.hash(k, 9) % 50) / 100
                    let q = CGPoint(x: p.x + CGFloat(cos(ang) * v * age) * S, y: p.y - CGFloat(sin(ang) * v * age * 1.5 - 2.2 * age * age) * S - S * 0.4)
                    g.fill(Path(CGRect(x: q.x - S * 0.07, y: q.y - S * 0.04, width: S * 0.14, height: S * 0.08)), with: .color(Self.c(k % 2 == 0 ? Self.timber : Self.stone, a)))
                }
            case .spark, .fallen:
                break
            }
        }
    }

    // MARK: Cards

    /// A tower as a small picture for a card: the scene's own drawing.
    static func icon(_ g: inout GraphicsContext, kind: WallKind, level: Int = 0, size: CGSize, now: Double = 0) {
        let S = min(size.width / 1.15, size.height / 1.85)
        g.translateBy(x: size.width / 2 - S / 2, y: size.height - S * 1.0)
        var field = WallField.empty
        field.gold = 0
        let scene = WallScene(field: field, now: now, icon: true)
        scene.tower(&g, WallTower(id: -1, kind: kind, x: 0, y: 0, level: level, hp: kind.stats(level).hp, invested: 0), S)
    }
}

extension WallField {
    /// An empty field for drawing a card's picture.
    static let empty = WallField(seed: 1)
}

/// What never moves, painted once with CoreGraphics and then only placed: the steppe and its hills and gaps, the
/// river and fords, the rocks, and the Great Wall running the width of the picture with its walkway, crenellations
/// and brick face, the pass through it.
enum WallLand {
    nonisolated(unsafe) static var kept: (seed: UInt64, image: CGImage)?
    /// Pixels to a tile.
    static let px: CGFloat = 56
    /// The land painted, in the field's tiles: wide enough to fill a wide window, from the hills to below the Wall.
    static let rect = CGRect(x: -14, y: -3.2, width: 58, height: 25.6)

    static func image(_ f: WallField) -> CGImage? {
        if let kept, kept.seed == f.seed { return kept.image }
        guard let made = paint(f) else { return nil }
        kept = (f.seed, made)
        return made
    }

    private static func rgb(_ v: (Double, Double, Double), _ a: Double = 1) -> CGColor { CGColor(srgbRed: CGFloat(v.0), green: CGFloat(v.1), blue: CGFloat(v.2), alpha: CGFloat(a)) }

    private static func paint(_ f: WallField) -> CGImage? {
        let S = px, R = rect
        let W = Int(R.width * S), H = Int(R.height * S)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: 1, y: -1)
        c.translateBy(x: -R.minX * S, y: -R.minY * S)
        func fill(_ path: CGPath, _ colour: CGColor) { c.addPath(path); c.setFillColor(colour); c.fillPath() }
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * S, y: y * S) }
        let full = CGRect(x: R.minX * S, y: R.minY * S, width: R.width * S, height: R.height * S)
        // The steppe: drier and more golden to the north, greener near the Wall.
        if let grad = CGGradient(colorsSpace: space, colors: [rgb((0.78, 0.74, 0.46)), rgb((0.66, 0.72, 0.4)), rgb((0.5, 0.66, 0.34)), rgb((0.46, 0.62, 0.32))] as CFArray, locations: [0, 0.3, 0.7, 1]) {
            c.saveGState(); c.addRect(full); c.clip()
            c.drawLinearGradient(grad, start: P(0, -3), end: P(0, 19), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            c.restoreGState()
        }
        // Patches of lighter and darker grass, and tufts.
        let light = CGMutablePath(), dark = CGMutablePath(), tufts = CGMutablePath(), flowers = CGMutablePath()
        for k in 0..<900 {
            let x = R.minX + CGFloat(Art.unit(k, 11)) * R.width, y = R.minY + CGFloat(Art.unit(k, 12)) * R.height
            let r = CGFloat(0.6 + Art.unit(k, 13) * 1.8)
            (k % 2 == 0 ? light : dark).addEllipse(in: CGRect(x: (x - r) * S, y: (y - r * 0.55) * S, width: 2 * r * S, height: 1.1 * r * S))
        }
        for k in 0..<3200 {
            let x = R.minX + CGFloat(Art.unit(k, 21)) * R.width, y = R.minY + CGFloat(Art.unit(k, 22)) * R.height
            let p = P(x, y), l = S * 0.14
            tufts.move(to: p); tufts.addLine(to: CGPoint(x: p.x - l * 0.35, y: p.y - l))
            tufts.move(to: p); tufts.addLine(to: CGPoint(x: p.x + l * 0.3, y: p.y - l * 1.1))
            if k % 23 == 0 { flowers.addEllipse(in: CGRect(x: p.x + l, y: p.y - l * 0.4, width: S * 0.08, height: S * 0.08)) }
        }
        fill(light, rgb((0.86, 0.84, 0.52), 0.22))
        fill(dark, rgb((0.3, 0.46, 0.2), 0.16))
        c.addPath(tufts); c.setStrokeColor(rgb((0.32, 0.46, 0.2), 0.45)); c.setLineWidth(max(1, S * 0.03)); c.strokePath()
        fill(flowers, rgb((0.98, 0.92, 0.5), 0.9))

        // Distant mountains, then the ridge of hills along the north with its three gaps.
        let far = CGMutablePath()
        far.move(to: P(R.minX, -1.2))
        var x = R.minX
        while x <= R.maxX { let h = 1.5 + Art.unit(Int(x * 3) + 400, 5) * 1.4; far.addLine(to: P(x, -1.3 - CGFloat(h))); x += 1.2 + CGFloat(Art.unit(Int(x * 7), 3)) * 1.4 }
        far.addLine(to: P(R.maxX, -1.2)); far.addLine(to: P(R.maxX, R.minY)); far.addLine(to: P(R.minX, R.minY)); far.closeSubpath()
        fill(far, rgb((0.62, 0.68, 0.74)))
        let snowcaps = CGMutablePath()
        x = R.minX
        while x <= R.maxX { let h = 1.5 + Art.unit(Int(x * 3) + 400, 5) * 1.4; if h > 2.3 { snowcaps.addEllipse(in: CGRect(x: (x - 0.3) * S, y: (-1.3 - CGFloat(h)) * S, width: 0.6 * S, height: 0.3 * S)) }; x += 1.2 + CGFloat(Art.unit(Int(x * 7), 3)) * 1.4 }
        fill(snowcaps, rgb((0.9, 0.92, 0.95), 0.8))
        // Hills: two rows of rounded domes, lit on the upper left; none in the gaps.
        let gaps = f.entries.map { CGFloat($0) + 1 }
        for (rowIndex, (baseY, height, colour, litColour)) in [(CGFloat(-0.2), CGFloat(1.5), (0.44, 0.56, 0.3), (0.58, 0.68, 0.38)),
                                                               (CGFloat(0.55), CGFloat(1.15), (0.52, 0.64, 0.32), (0.68, 0.76, 0.42))].enumerated() {
            var hx = R.minX - 1
            var k = rowIndex * 100
            while hx < R.maxX + 1 {
                k += 1
                let w = 2.4 + CGFloat(Art.unit(k, 31)) * 2.4
                let cx = hx + w / 2
                if gaps.contains(where: { abs($0 - cx) < 0.9 + w * 0.5 }) { hx += 0.7; continue }
                let top = baseY - height * CGFloat(0.7 + Art.unit(k, 33) * 0.5)
                let dome = CGMutablePath()
                dome.move(to: P(hx, baseY))
                dome.addCurve(to: P(hx + w, baseY), control1: P(hx + w * 0.12, top), control2: P(hx + w * 0.88, top))
                dome.closeSubpath()
                fill(dome, rgb(colour))
                let lit = CGMutablePath()
                lit.move(to: P(hx + w * 0.08, baseY - 0.05))
                lit.addCurve(to: P(cx + w * 0.05, top + (baseY - top) * 0.28), control1: P(hx + w * 0.1, top + (baseY - top) * 0.3), control2: P(cx - w * 0.2, top + (baseY - top) * 0.2))
                lit.addCurve(to: P(hx + w * 0.3, baseY - 0.05), control1: P(cx - w * 0.1, top + (baseY - top) * 0.6), control2: P(hx + w * 0.3, baseY - 0.3))
                lit.closeSubpath()
                fill(lit, rgb(litColour, 0.85))
                fill(CGPath(rect: CGRect(x: hx * S, y: (baseY - 0.06) * S, width: w * S, height: 0.12 * S), transform: nil), rgb((0.3, 0.4, 0.2), 0.25))
                hx += w * 0.72
            }
        }
        // A trail down through each gap.
        let trail = CGMutablePath()
        for g in gaps {
            trail.move(to: P(g, -2.4)); trail.addQuadCurve(to: P(g, 1.2), control: P(g + 0.5, -0.8))
        }
        c.addPath(trail); c.setStrokeColor(rgb((0.72, 0.62, 0.44), 0.8)); c.setLineWidth(S * 1.0); c.setLineCap(.round); c.strokePath()
        c.addPath(trail); c.setStrokeColor(rgb((0.8, 0.7, 0.5), 0.7)); c.setLineWidth(S * 0.6); c.strokePath()

        // The river.
        var water: [(Int, Int)] = [], fords: [(Int, Int)] = []
        for y in 0..<WallField.height { for x in 0..<WallField.width {
            let g = f.ground(WallTile(x: x, y: y))
            if g == .water { water.append((x, y)) } else if g == .ford { fords.append((x, y)) }
        } }
        // The river runs on past the field's edges.
        let wet = water + fords
        func body(_ grow: CGFloat, _ round: CGFloat, extend: Bool = true) -> CGPath {
            let p = CGMutablePath()
            for (x, y) in wet { p.addRoundedRect(in: CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: S, height: S).insetBy(dx: -grow, dy: -grow), cornerWidth: round, cornerHeight: round) }
            if extend {
                for (x0, dir) in [(0, -1), (WallField.width - 1, 1)] {
                    guard let (_, y) = wet.first(where: { $0.0 == x0 }) else { continue }
                    for k in 1...15 { p.addRoundedRect(in: CGRect(x: CGFloat(x0 + dir * k) * S, y: CGFloat(y) * S, width: S, height: S).insetBy(dx: -grow, dy: -grow), cornerWidth: round, cornerHeight: round) }
                }
            }
            return p
        }
        fill(body(S * 0.26, S * 0.4), rgb((0.8, 0.74, 0.54)))
        fill(body(S * 0.12, S * 0.3), rgb((0.66, 0.62, 0.46)))
        fill(body(S * 0.04, S * 0.26), rgb((0.36, 0.62, 0.74)))
        // Deeper water down the middle, as one winding stroke.
        let mid = CGMutablePath()
        var cols: [(CGFloat, CGFloat)] = []
        for x in 0..<WallField.width {
            let rows = wet.filter { $0.0 == x }.map { CGFloat($0.1) }
            if !rows.isEmpty { cols.append((CGFloat(x) + 0.5, rows.reduce(0, +) / CGFloat(rows.count) + 0.5)) }
        }
        if let first = cols.first, let last = cols.last {
            mid.move(to: P(first.0 - 16, first.1))
            for (x, y) in cols { mid.addLine(to: P(x, y)) }
            mid.addLine(to: P(last.0 + 16, last.1))
            c.addPath(mid); c.setStrokeColor(rgb((0.24, 0.5, 0.68), 0.85)); c.setLineWidth(S * 0.5); c.setLineCap(.round); c.setLineJoin(.round); c.strokePath()
        }
        // Fords: stepping stones and a plank bridge.
        for (x, y) in fords {
            let r = CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: S, height: S)
            let deck = CGRect(x: r.minX - S * 0.08, y: r.minY - S * 0.12, width: S * 1.16, height: S * 1.24)
            fill(CGPath(rect: deck.offsetBy(dx: S * 0.06, dy: S * 0.1), transform: nil), rgb((0, 0, 0), 0.2))
            fill(CGPath(rect: deck, transform: nil), rgb((0.62, 0.46, 0.3)))
            let lines = CGMutablePath()
            for k in 1..<6 { let yy = deck.minY + deck.height * CGFloat(k) / 6; lines.move(to: CGPoint(x: deck.minX, y: yy)); lines.addLine(to: CGPoint(x: deck.maxX, y: yy)) }
            c.addPath(lines); c.setStrokeColor(rgb((0.42, 0.3, 0.18))); c.setLineWidth(max(1, S * 0.03)); c.strokePath()
            for side in [deck.minX, deck.maxX - S * 0.08] { fill(CGPath(rect: CGRect(x: side, y: deck.minY - S * 0.05, width: S * 0.08, height: deck.height + S * 0.1), transform: nil), rgb((0.4, 0.28, 0.16))) }
        }
        // Rocks.
        for y in 0..<WallField.height { for x in 0..<WallField.width where f.ground(WallTile(x: x, y: y)) == .rock {
            let cx = (CGFloat(x) + 0.5) * S, cy = (CGFloat(y) + 0.62) * S
            fill(CGPath(ellipseIn: CGRect(x: cx - S * 0.5, y: cy - S * 0.1, width: S * 1.15, height: S * 0.42), transform: nil), rgb((0, 0, 0), 0.22))
            for (j, (dx, dy, rr)) in [(-0.2, 0.0, 0.42), (0.22, 0.05, 0.36), (0.0, -0.22, 0.4)].enumerated() {
                let rad = S * CGFloat(rr) * CGFloat(0.9 + Art.unit(x * 7 + j, y) * 0.25)
                let p = CGPoint(x: cx + CGFloat(dx) * S, y: cy + CGFloat(dy) * S - S * 0.12)
                let body: (Double, Double, Double) = (0.6, 0.58, 0.56)
                fill(CGPath(roundedRect: CGRect(x: p.x - rad, y: p.y - rad * 0.85, width: 2 * rad, height: 1.7 * rad), cornerWidth: rad * 0.7, cornerHeight: rad * 0.7, transform: nil), rgb(Art.lit(body, 0.78)))
                fill(CGPath(roundedRect: CGRect(x: p.x - rad * 0.95, y: p.y - rad * 0.85, width: rad * 1.5, height: rad * 1.1), cornerWidth: rad * 0.55, cornerHeight: rad * 0.55, transform: nil), rgb(body))
                fill(CGPath(roundedRect: CGRect(x: p.x - rad * 0.7, y: p.y - rad * 0.75, width: rad * 0.8, height: rad * 0.42), cornerWidth: rad * 0.2, cornerHeight: rad * 0.2, transform: nil), rgb(Art.lit(body, 1.28)))
                if j == 1 { fill(CGPath(ellipseIn: CGRect(x: p.x - rad * 0.4, y: p.y + rad * 0.2, width: rad * 0.7, height: rad * 0.35), transform: nil), rgb((0.4, 0.52, 0.26), 0.8)) }
            }
        } }
        // A few shrubs on the field's far edges and willows by the river outside the field.
        for k in 0..<26 {
            let side = k % 2 == 0
            let xx = side ? -1.5 - CGFloat(Art.unit(k, 41)) * 11 : CGFloat(WallField.width) + 0.5 + CGFloat(Art.unit(k, 41)) * 11
            let yy = 1.5 + CGFloat(Art.unit(k, 42)) * 15
            if wet.contains(where: { abs(CGFloat($0.1) - yy) < 1.2 }) && k % 3 == 0 { continue }
            let r = S * CGFloat(0.35 + Art.unit(k, 43) * 0.3)
            let p = P(xx, yy)
            fill(CGPath(ellipseIn: CGRect(x: p.x - r * 0.8, y: p.y - r * 0.2, width: r * 2.2, height: r * 0.7), transform: nil), rgb((0, 0, 0), 0.18))
            fill(CGPath(rect: CGRect(x: p.x - S * 0.04, y: p.y - r * 1.2, width: S * 0.08, height: r * 1.2), transform: nil), rgb((0.42, 0.3, 0.2)))
            fill(CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 2.2, width: 2 * r, height: 1.8 * r), transform: nil), rgb((0.3, 0.5, 0.24)))
            fill(CGPath(ellipseIn: CGRect(x: p.x - r * 0.75, y: p.y - r * 2.2, width: 1.2 * r, height: 1.0 * r), transform: nil), rgb((0.44, 0.64, 0.3)))
        }

        // Beyond the field's edges: the steppe goes on, a shade darker, so the field reads as the place to build.
        for r in [CGRect(x: R.minX, y: R.minY, width: -R.minX, height: CGFloat(WallField.wallRow) - R.minY),
                  CGRect(x: CGFloat(WallField.width), y: R.minY, width: R.maxX - CGFloat(WallField.width), height: CGFloat(WallField.wallRow) - R.minY)] {
            fill(CGPath(rect: CGRect(x: r.minX * S, y: r.minY * S, width: r.width * S, height: r.height * S), transform: nil), rgb((0.12, 0.16, 0.08), 0.2))
        }
        let edge = CGMutablePath()
        for x in [0.0, CGFloat(WallField.width)] { edge.move(to: P(x, 0.4)); edge.addLine(to: P(x, CGFloat(WallField.wallRow))) }
        c.addPath(edge); c.setStrokeColor(rgb((1, 0.95, 0.75), 0.35)); c.setLineWidth(max(1, S * 0.05)); c.setLineDash(phase: 0, lengths: [S * 0.3, S * 0.2]); c.strokePath(); c.setLineDash(phase: 0, lengths: [])

        // The Great Wall along the whole width: walkway at rows 18–19, merlons on both parapets, the brick face below.
        let wallTop = CGFloat(WallField.wallRow), walkBottom = wallTop + 1.05, faceBottom = walkBottom + 1.15
        // Its shadow on the steppe to the north... and the ground inside to the south.
        fill(CGPath(rect: CGRect(x: R.minX * S, y: faceBottom * S, width: R.width * S, height: (R.maxY - faceBottom) * S), transform: nil), rgb((0.46, 0.58, 0.32)))
        let road = CGMutablePath()
        road.move(to: P(15, faceBottom)); road.addLine(to: P(15, R.maxY))
        c.addPath(road); c.setStrokeColor(rgb((0.72, 0.62, 0.46))); c.setLineWidth(S * 1.6); c.strokePath()
        fill(CGPath(rect: CGRect(x: R.minX * S, y: (wallTop - 0.3) * S, width: R.width * S, height: 0.3 * S), transform: nil), rgb((0.3, 0.36, 0.2), 0.3))
        // Walkway.
        let walk = CGRect(x: R.minX * S, y: wallTop * S, width: R.width * S, height: (walkBottom - wallTop) * S)
        fill(CGPath(rect: walk, transform: nil), rgb((0.7, 0.66, 0.58)))
        let pave = CGMutablePath()
        var px = R.minX
        while px < R.maxX { pave.move(to: P(px, wallTop + 0.12)); pave.addLine(to: P(px, walkBottom - 0.05)); px += 0.5 }
        pave.move(to: P(R.minX, wallTop + 0.55)); pave.addLine(to: P(R.maxX, wallTop + 0.55))
        c.addPath(pave); c.setStrokeColor(rgb((0.56, 0.52, 0.46))); c.setLineWidth(max(1, S * 0.025)); c.strokePath()
        // The pass: the walkway cut away over the gate passage, darker road through it.
        let gx0 = CGFloat(WallField.gateX[0]), gx1 = CGFloat(WallField.gateX[1] + 1)
        fill(CGPath(rect: CGRect(x: gx0 * S, y: wallTop * S, width: (gx1 - gx0) * S, height: (walkBottom - wallTop) * S), transform: nil), rgb((0.64, 0.56, 0.42)))
        // North parapet (the far one): merlons standing up from the walkway's back edge.
        let merl = CGMutablePath(), merlTop = CGMutablePath()
        px = R.minX
        while px < R.maxX {
            if !(px + 0.28 > gx0 && px < gx1) {
                merl.addRect(CGRect(x: px * S, y: (wallTop - 0.3) * S, width: 0.3 * S, height: 0.36 * S))
                merlTop.addRect(CGRect(x: px * S, y: (wallTop - 0.3) * S, width: 0.3 * S, height: 0.08 * S))
            }
            px += 0.5
        }
        fill(CGPath(rect: CGRect(x: R.minX * S, y: (wallTop - 0.08) * S, width: (gx0 - R.minX) * S, height: 0.14 * S), transform: nil), rgb((0.58, 0.54, 0.48)))
        fill(CGPath(rect: CGRect(x: gx1 * S, y: (wallTop - 0.08) * S, width: (R.maxX - gx1) * S, height: 0.14 * S), transform: nil), rgb((0.58, 0.54, 0.48)))
        fill(merl, rgb((0.6, 0.55, 0.48)))
        fill(merlTop, rgb((0.76, 0.72, 0.64)))
        // The brick face towards the viewer.
        let face = CGRect(x: R.minX * S, y: walkBottom * S, width: R.width * S, height: (faceBottom - walkBottom) * S)
        fill(CGPath(rect: face, transform: nil), rgb((0.56, 0.5, 0.43)))
        let bricks = CGMutablePath()
        var row = 0
        var by = walkBottom + 0.2
        while by < faceBottom {
            bricks.move(to: P(R.minX, by)); bricks.addLine(to: P(R.maxX, by))
            var bx = R.minX + (row % 2 == 0 ? 0 : 0.25)
            while bx < R.maxX { bricks.move(to: P(bx, by)); bricks.addLine(to: P(bx, min(faceBottom, by + 0.2))); bx += 0.5 }
            by += 0.2; row += 1
        }
        c.addPath(bricks); c.setStrokeColor(rgb((0.42, 0.37, 0.32))); c.setLineWidth(max(1, S * 0.022)); c.strokePath()
        // Weathering streaks and the base course.
        for k in 0..<60 {
            let sx = R.minX + CGFloat(Art.unit(k, 51)) * R.width
            fill(CGPath(rect: CGRect(x: sx * S, y: walkBottom * S, width: S * 0.12, height: (faceBottom - walkBottom) * S * CGFloat(0.4 + Art.unit(k, 52) * 0.6)), transform: nil), rgb((0.3, 0.28, 0.24), 0.12))
        }
        fill(CGPath(rect: CGRect(x: R.minX * S, y: (faceBottom - 0.16) * S, width: R.width * S, height: 0.16 * S), transform: nil), rgb((0.46, 0.42, 0.36)))
        fill(CGPath(rect: CGRect(x: R.minX * S, y: faceBottom * S, width: R.width * S, height: 0.2 * S), transform: nil), rgb((0, 0, 0), 0.18))
        // South parapet: merlons along the front edge of the walkway.
        let front = CGMutablePath(), frontTop = CGMutablePath()
        px = R.minX + 0.1
        while px < R.maxX {
            if !(px + 0.3 > gx0 - 1.6 && px < gx1 + 1.6) {
                front.addRect(CGRect(x: px * S, y: (walkBottom - 0.3) * S, width: 0.32 * S, height: 0.34 * S))
                frontTop.addRect(CGRect(x: px * S, y: (walkBottom - 0.3) * S, width: 0.32 * S, height: 0.08 * S))
            }
            px += 0.52
        }
        fill(CGPath(rect: CGRect(x: R.minX * S, y: (walkBottom - 0.06) * S, width: R.width * S, height: 0.1 * S), transform: nil), rgb((0.5, 0.45, 0.4)))
        fill(front, rgb((0.58, 0.52, 0.45)))
        fill(frontTop, rgb((0.74, 0.7, 0.62)))
        // The gate's arch through the face.
        let arch = CGMutablePath()
        let ax0 = gx0 + 0.25, ax1 = gx1 - 0.25
        arch.move(to: P(ax0, faceBottom)); arch.addLine(to: P(ax0, walkBottom + 0.45))
        arch.addQuadCurve(to: P(ax1, walkBottom + 0.45), control: P((ax0 + ax1) / 2, walkBottom - 0.25))
        arch.addLine(to: P(ax1, faceBottom)); arch.closeSubpath()
        fill(arch, rgb((0.14, 0.11, 0.1)))
        c.addPath(arch); c.setStrokeColor(rgb((0.78, 0.74, 0.66))); c.setLineWidth(S * 0.08); c.strokePath()
        // Open gate leaves.
        fill(CGPath(rect: CGRect(x: (ax0 - 0.05) * S, y: (walkBottom + 0.5) * S, width: 0.18 * S, height: (faceBottom - walkBottom - 0.5) * S), transform: nil), rgb((0.5, 0.18, 0.12)))
        fill(CGPath(rect: CGRect(x: (ax1 - 0.13) * S, y: (walkBottom + 0.5) * S, width: 0.18 * S, height: (faceBottom - walkBottom - 0.5) * S), transform: nil), rgb((0.5, 0.18, 0.12)))
        return c.makeImage()
    }
}
