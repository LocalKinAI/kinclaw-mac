import SwiftUI

/// The map of 帝国时代 at one moment, drawn from above: ground, trees, rocks
/// and water, the buildings of both towns in the style of their age, every
/// villager and soldier, arrows in the air, and what the player is doing with
/// the mouse — the selection, a box being dragged, a building about to be put down.
struct RTSScene {
    let world: RTSWorld
    /// The side whose view this is: whose rally point shows, whose age and stock a building being placed is judged by.
    let viewer: Int
    let selected: Set<Int>, building: Int?
    let placing: RTSBuildingKind?, hover: RTSTile?
    let box: (CGPoint, CGPoint)?
    let now: Double

    static let team = [Color(red: 0.2, green: 0.45, blue: 0.98), Color(red: 0.9, green: 0.18, blue: 0.16)]
    static let roofs = [Color(red: 0.55, green: 0.38, blue: 0.2), Color(red: 0.8, green: 0.32, blue: 0.2), Color(red: 0.3, green: 0.4, blue: 0.58)]
    static let walls = [Color(red: 0.8, green: 0.66, blue: 0.46), Color(red: 0.9, green: 0.84, blue: 0.72), Color(red: 0.75, green: 0.75, blue: 0.77)]

    func paint(_ g: inout GraphicsContext, tile T: CGFloat) {
        let width = CGFloat(RTSWorld.width) * T, height = CGFloat(RTSWorld.height) * T
        func rect(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) -> CGRect { CGRect(x: CGFloat(x) * T, y: CGFloat(y) * T, width: CGFloat(w) * T, height: CGFloat(h) * T) }

        // Ground.
        g.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)), with: .color(Color(red: 0.42, green: 0.64, blue: 0.3)))
        for patch in 0..<140 {
            let x = CGFloat(JevDraw.hash(patch, 5) % 1000) / 1000 * width, y = CGFloat(JevDraw.hash(patch, 6) % 1000) / 1000 * height
            let r = T * CGFloat(0.6 + Double(JevDraw.hash(patch, 7) % 100) / 60)
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.7, width: 2 * r, height: 1.4 * r)),
                   with: .color((patch % 2 == 0 ? Color(red: 0.36, green: 0.58, blue: 0.25) : Color(red: 0.5, green: 0.72, blue: 0.35)).opacity(0.4)))
        }
        // Water, then everything growing or lying on the ground.
        for y in 0..<RTSWorld.height {
            for x in 0..<RTSWorld.width where world.terrain[y * RTSWorld.width + x] == .water {
                g.fill(Path(rect(x, y).insetBy(dx: -0.5, dy: -0.5)), with: .color(Color(red: 0.2, green: 0.46, blue: 0.78)))
                if (x * 7 + y * 3) % 5 == 0 {
                    let wave = CGFloat(sin(now * 1.5 + Double(x + y))) * T * 0.15
                    g.stroke(Path { p in
                        p.move(to: CGPoint(x: CGFloat(x) * T + T * 0.2 + wave, y: CGFloat(y) * T + T * 0.5))
                        p.addLine(to: CGPoint(x: CGFloat(x) * T + T * 0.7 + wave, y: CGFloat(y) * T + T * 0.5))
                    }, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
                }
            }
        }
        for y in 0..<RTSWorld.height {
            for x in 0..<RTSWorld.width {
                let i = y * RTSWorld.width + x, c = CGPoint(x: (CGFloat(x) + 0.5) * T, y: (CGFloat(y) + 0.5) * T)
                switch world.terrain[i] {
                case .forest:
                    let r = T * CGFloat(0.42 + 0.2 * min(world.amount[i], 100) / 100)
                    disc(g, CGPoint(x: c.x + T * 0.12, y: c.y + T * 0.16), r, .black.opacity(0.22))
                    disc(g, c, r, Color(red: 0.12, green: 0.36 + 0.04 * Double(JevDraw.hash(x, y) % 3), blue: 0.15))
                    disc(g, CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.32), r * 0.55, Color(red: 0.22, green: 0.5, blue: 0.22))
                case .gold, .stone:
                    let gold = world.terrain[i] == .gold, left = CGFloat(min(world.amount[i] / (gold ? 400 : 350), 1))
                    let r = T * (0.25 + 0.2 * left)
                    disc(g, CGPoint(x: c.x + 2, y: c.y + 3), r, .black.opacity(0.25))
                    disc(g, c, r, gold ? Color(red: 0.55, green: 0.48, blue: 0.35) : Color(white: 0.55))
                    for k in 0..<3 {
                        let a = Double(k) * 2.1 + Double(x)
                        disc(g, CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.45, y: c.y + CGFloat(sin(a)) * r * 0.45), r * 0.28,
                             gold ? Color(red: 1, green: 0.84, blue: 0.2) : Color(white: 0.78))
                    }
                case .berries:
                    disc(g, c, T * 0.4, Color(red: 0.18, green: 0.42, blue: 0.2))
                    for k in 0..<4 where world.amount[i] > Double(k) * 30 {
                        disc(g, CGPoint(x: c.x + CGFloat(k % 2) * T * 0.3 - T * 0.15, y: c.y + CGFloat(k / 2) * T * 0.3 - T * 0.15), T * 0.09, Color(red: 0.88, green: 0.12, blue: 0.22))
                    }
                default: break
                }
            }
        }

        // Buildings: fields flat on the ground first, then the rest from the back.
        let recentHits = Set(world.events.filter { $0.kind == .attacked && world.time - $0.time < 0.25 }.map { Int($0.x) * 1000 + Int($0.y) })
        for b in world.buildings.sorted(by: { ($0.kind == .farm ? 0 : 1, $0.y) < ($1.kind == .farm ? 0 : 1, $1.y) }) {
            let n = RTSWorld.size(b.kind), area = rect(b.x, b.y, n, n)
            let age = world.players[b.owner].age
            if !b.done {
                // A foundation: the outline, scaffolding, and as much as is built.
                g.stroke(Path(roundedRect: area.insetBy(dx: 2, dy: 2), cornerRadius: 3), with: .color(Color(red: 0.45, green: 0.32, blue: 0.18)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                var partial = g
                partial.opacity = 0.35 + 0.6 * b.progress
                draw(partial, b.kind, area, age: age, owner: b.owner)
                for k in 0..<3 {
                    let x = area.minX + area.width * CGFloat(k + 1) / 4
                    g.stroke(Path { p in p.move(to: CGPoint(x: x, y: area.minY + 3)); p.addLine(to: CGPoint(x: x, y: area.maxY - 3)) },
                             with: .color(Color(red: 0.5, green: 0.36, blue: 0.2)), lineWidth: 1.4)
                }
                bar(g, area, b.progress, Color(red: 0.95, green: 0.75, blue: 0.2))
            } else {
                draw(g, b.kind, area, age: age, owner: b.owner, farmed: b.farmer != nil)
                if b.hp < RTSWorld.health(b.kind) - 1 || b.id == building { bar(g, area, b.hp / RTSWorld.health(b.kind), b.owner == viewer ? .green : .red) }
            }
            if recentHits.contains(b.x * 1000 + b.y) || recentHits.contains((b.x + 1) * 1000 + b.y + 1) {
                g.fill(Path(roundedRect: area, cornerRadius: 4), with: .color(Color.red.opacity(0.25)))
            }
            if b.id == building {
                g.stroke(Path(roundedRect: area.insetBy(dx: -2, dy: -2), cornerRadius: 5), with: .color(.yellow), lineWidth: 2)
                if let rally = b.rally {
                    let to = CGPoint(x: (CGFloat(rally.x) + 0.5) * T, y: (CGFloat(rally.y) + 0.5) * T)
                    g.stroke(Path { p in p.move(to: CGPoint(x: area.midX, y: area.midY)); p.addLine(to: to) }, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    flag(g, to, T, Self.team[b.owner])
                }
            }
        }

        // People, from the back.
        for u in world.units.sorted(by: { $0.y < $1.y }) {
            let p = CGPoint(x: CGFloat(u.x) * T, y: CGFloat(u.y) * T)
            if selected.contains(u.id) {
                g.stroke(Path(ellipseIn: CGRect(x: p.x - T * 0.42, y: p.y - T * 0.05, width: T * 0.84, height: T * 0.4)), with: .color(.green), lineWidth: 1.6)
            }
            person(g, u, p, T)
            if selected.contains(u.id) || u.hp < RTSWorld.unitHP(u.kind) - 0.5 {
                let bar = CGRect(x: p.x - T * 0.35, y: p.y - T * 0.75, width: T * 0.7, height: 3)
                g.fill(Path(bar), with: .color(.black.opacity(0.5)))
                g.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(max(u.hp, 0) / RTSWorld.unitHP(u.kind)), height: bar.height)),
                       with: .color(u.owner == viewer ? .green : .red))
            }
        }

        // What happened in the last moments: arrows in flight, blows, the fallen, an age reached.
        for e in world.events {
            let age = world.time - e.time
            switch e.kind {
            case .arrow(let from, let to):
                guard age < 0.35 else { continue }
                let f = CGFloat(age / 0.35)
                let a = CGPoint(x: (CGFloat(from.x) + 0.5) * T, y: (CGFloat(from.y) + 0.5) * T), b = CGPoint(x: (CGFloat(to.x) + 0.5) * T, y: (CGFloat(to.y) + 0.5) * T)
                let head = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f - sin(f * .pi) * T * 0.8)
                let tail = CGPoint(x: head.x - (b.x - a.x) * 0.08, y: head.y - (b.y - a.y) * 0.08)
                g.stroke(Path { p in p.move(to: tail); p.addLine(to: head) }, with: .color(Color(red: 0.35, green: 0.25, blue: 0.1)), lineWidth: 1.5)
            case .hit:
                guard age < 0.25 else { continue }
                let p = CGPoint(x: CGFloat(e.x) * T, y: CGFloat(e.y) * T - T * 0.3)
                for k in 0..<5 {
                    let a = Double(k) * 1.26
                    g.stroke(Path { path in path.move(to: p); path.addLine(to: CGPoint(x: p.x + CGFloat(cos(a)) * T * 0.3, y: p.y + CGFloat(sin(a)) * T * 0.3)) },
                             with: .color(Color.yellow.opacity(1 - age / 0.25)), lineWidth: 1.5)
                }
            case .death:
                guard age < 1.5 else { continue }
                JevDraw.text(g, "✕", at: CGPoint(x: CGFloat(e.x) * T, y: CGFloat(e.y) * T - CGFloat(age) * T * 0.4), size: T * 0.6,
                             colour: Self.team[e.owner].opacity(1 - age / 1.5), shadow: false)
            case .age(let n):
                guard age < 2.5 else { continue }
                JevDraw.text(g, RTSWorld.ageNames[n] + "！", at: CGPoint(x: CGFloat(e.x) * T, y: CGFloat(e.y) * T - T * (1.8 + CGFloat(age) * 0.5)), size: T * 0.8,
                             colour: Color.yellow.opacity(1 - age / 2.5))
            case .finished:
                guard age < 0.8 else { continue }
                JevDraw.text(g, "✨", at: CGPoint(x: CGFloat(e.x) * T, y: CGFloat(e.y) * T - T), size: T * 0.8, shadow: false)
            case .attacked:
                break
            }
        }

        // A building about to be put down: where it would go, green if it fits.
        if let kind = placing, let hover {
            let n = RTSWorld.size(kind), origin = RTSTile(x: hover.x - (n - 1) / 2, y: hover.y - (n - 1) / 2)
            let fits = world.fits(kind, at: origin) && world.afford(RTSWorld.cost(kind), viewer)
            let area = rect(origin.x, origin.y, n, n)
            var ghost = g
            ghost.opacity = 0.55
            draw(ghost, kind, area, age: world.players[viewer].age, owner: viewer)
            g.fill(Path(roundedRect: area, cornerRadius: 3), with: .color((fits ? Color.green : Color.red).opacity(0.3)))
            g.stroke(Path(roundedRect: area, cornerRadius: 3), with: .color(fits ? .green : .red), lineWidth: 2)
        }
        if let box {
            let r = CGRect(x: min(box.0.x, box.1.x), y: min(box.0.y, box.1.y), width: abs(box.1.x - box.0.x), height: abs(box.1.y - box.0.y))
            g.fill(Path(r), with: .color(Color.green.opacity(0.12)))
            g.stroke(Path(r), with: .color(.green), lineWidth: 1)
        }
    }

    // MARK: Pieces

    private func disc(_ g: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ colour: Color) {
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(colour))
    }

    private func bar(_ g: GraphicsContext, _ area: CGRect, _ fraction: Double, _ colour: Color) {
        let r = CGRect(x: area.minX + 3, y: area.minY - 6, width: area.width - 6, height: 4)
        g.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(.black.opacity(0.5)))
        g.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width * CGFloat(max(0, min(fraction, 1))), height: r.height), cornerRadius: 2), with: .color(colour))
    }

    private func flag(_ g: GraphicsContext, _ at: CGPoint, _ T: CGFloat, _ colour: Color) {
        g.fill(Path(CGRect(x: at.x, y: at.y - T * 0.8, width: 1.4, height: T * 0.8)), with: .color(Color(white: 0.25)))
        let wave = CGFloat(sin(now * 5)) * T * 0.05
        g.fill(Path { p in p.move(to: CGPoint(x: at.x + 1.4, y: at.y - T * 0.8)); p.addLine(to: CGPoint(x: at.x + T * 0.5, y: at.y - T * 0.66 + wave)); p.addLine(to: CGPoint(x: at.x + 1.4, y: at.y - T * 0.52)); p.closeSubpath() },
               with: .color(colour))
    }

    /// A wall and a roof in an area, the style of the owner's age.
    private func block(_ g: GraphicsContext, _ area: CGRect, age: Int, inset: CGFloat = 0.12) {
        let body = CGRect(x: area.minX + area.width * inset, y: area.minY + area.height * 0.34, width: area.width * (1 - 2 * inset), height: area.height * 0.58)
        g.fill(Path(roundedRect: body.offsetBy(dx: 3, dy: 4), cornerRadius: 2), with: .color(.black.opacity(0.25)))
        g.fill(Path(roundedRect: body, cornerRadius: 2), with: .color(Self.walls[age]))
        g.fill(Path { p in
            p.move(to: CGPoint(x: body.minX - area.width * 0.05, y: body.minY + 2))
            p.addLine(to: CGPoint(x: body.midX, y: area.minY + area.height * 0.06))
            p.addLine(to: CGPoint(x: body.maxX + area.width * 0.05, y: body.minY + 2))
            p.closeSubpath()
        }, with: .color(Self.roofs[age]))
        g.fill(Path(CGRect(x: body.midX - body.width * 0.1, y: body.maxY - body.height * 0.45, width: body.width * 0.2, height: body.height * 0.45)), with: .color(Color(red: 0.3, green: 0.2, blue: 0.12)))
    }

    private func draw(_ g: GraphicsContext, _ kind: RTSBuildingKind, _ area: CGRect, age: Int, owner: Int, farmed: Bool = false) {
        let T = area.width / CGFloat(RTSWorld.size(kind)), colour = Self.team[owner]
        switch kind {
        case .farm:
            g.fill(Path(roundedRect: area.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 3), with: .color(Color(red: 0.55, green: 0.4, blue: 0.22)))
            for row in 0..<6 {
                g.fill(Path(CGRect(x: area.minX + 4, y: area.minY + 4 + CGFloat(row) * (area.height - 8) / 6, width: area.width - 8, height: (area.height - 8) / 12)),
                       with: .color(farmed ? Color(red: 0.55, green: 0.78, blue: 0.3) : Color(red: 0.42, green: 0.3, blue: 0.16)))
            }
            g.stroke(Path(roundedRect: area.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 3), with: .color(colour.opacity(0.6)), lineWidth: 1)
        case .tower:
            let body = CGRect(x: area.minX + T * 0.2, y: area.minY - T * 0.4, width: T * 0.6, height: T * 1.3)
            g.fill(Path(roundedRect: body.offsetBy(dx: 3, dy: 3), cornerRadius: 2), with: .color(.black.opacity(0.25)))
            g.fill(Path(roundedRect: body, cornerRadius: 2), with: .color(Self.walls[max(age, 1)]))
            for k in 0..<3 { g.fill(Path(CGRect(x: body.minX + CGFloat(k) * body.width * 0.38, y: body.minY - T * 0.12, width: body.width * 0.24, height: T * 0.16)), with: .color(Self.walls[max(age, 1)])) }
            flag(g, CGPoint(x: body.midX, y: body.minY - T * 0.1), T * 0.8, colour)
        case .townCenter:
            block(g, area, age: age, inset: 0.06)
            block(g, CGRect(x: area.midX - T * 0.6, y: area.minY - T * 0.55, width: T * 1.2, height: T * 1.3), age: age, inset: 0.1)
            flag(g, CGPoint(x: area.midX, y: area.minY - T * 0.45), T * 1.3, colour)
        case .mill:
            block(g, area, age: age)
            let hub = CGPoint(x: area.midX, y: area.minY + area.height * 0.42)
            for k in 0..<4 {
                let a = now * 1.6 + Double(k) * .pi / 2
                g.stroke(Path { p in p.move(to: hub); p.addLine(to: CGPoint(x: hub.x + CGFloat(cos(a)) * T * 0.9, y: hub.y + CGFloat(sin(a)) * T * 0.9)) },
                         with: .color(Color(red: 0.95, green: 0.92, blue: 0.85)), lineWidth: T * 0.12)
            }
            disc(g, hub, T * 0.1, Color(red: 0.35, green: 0.25, blue: 0.15))
        default:
            block(g, area, age: age)
            let mark: String? = [RTSBuildingKind.lumberCamp: "🪓", .miningCamp: "⛏", .barracks: "⚔️", .range: "🎯", .stable: "🐴"][kind]
            if let mark { JevDraw.text(g, mark, at: CGPoint(x: area.midX, y: area.minY + area.height * 0.7), size: T * 0.62, shadow: false) }
            if [.barracks, .range, .stable].contains(kind) { flag(g, CGPoint(x: area.maxX - T * 0.35, y: area.minY + T * 0.5), T, colour) }
            if kind == .lumberCamp {
                for k in 0..<3 { g.fill(Path(roundedRect: CGRect(x: area.minX + T * 0.2, y: area.maxY - T * (0.3 + CGFloat(k) * 0.14), width: T * 0.7, height: T * 0.12), cornerRadius: 2), with: .color(Color(red: 0.5, green: 0.32, blue: 0.15))) }
            }
        }
    }

    /// A villager or a soldier, in its owner's colours, doing what it does.
    private func person(_ g: GraphicsContext, _ u: RTSUnit, _ p: CGPoint, _ T: CGFloat) {
        let colour = Self.team[u.owner], skin = Color(red: 0.95, green: 0.8, blue: 0.65), s = T / 22, facing = CGFloat(u.facing)
        let working = u.swung < 0.3
        let swing = working ? CGFloat(sin(now * 14)) : 0
        if u.kind == .knight {
            g.fill(Path(ellipseIn: CGRect(x: p.x - 9 * s, y: p.y - 3 * s, width: 18 * s, height: 9 * s)), with: .color(Color(red: 0.45, green: 0.3, blue: 0.18)))
            g.fill(Path(ellipseIn: CGRect(x: p.x + facing * 7 * s - 3.5 * s, y: p.y - 8 * s, width: 7 * s, height: 7 * s)), with: .color(Color(red: 0.45, green: 0.3, blue: 0.18)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - 3.5 * s, y: p.y - 11 * s, width: 7 * s, height: 9 * s)), with: .color(colour))
            disc(g, CGPoint(x: p.x, y: p.y - 13 * s), 2.6 * s, Color(white: 0.78))
            g.stroke(Path { path in path.move(to: CGPoint(x: p.x, y: p.y - 7 * s)); path.addLine(to: CGPoint(x: p.x + facing * 14 * s, y: p.y - (11 + 3 * swing) * s)) },
                     with: .color(Color(white: 0.85)), lineWidth: 1.4 * s)
            return
        }
        g.fill(Path(ellipseIn: CGRect(x: p.x - 4 * s, y: p.y - 3 * s, width: 8 * s, height: 10 * s)), with: .color(colour))
        disc(g, CGPoint(x: p.x, y: p.y - 6 * s), 3 * s, u.kind == .spearman ? Color(white: 0.75) : skin)
        switch u.kind {
        case .villager:
            if working {
                g.stroke(Path { path in path.move(to: CGPoint(x: p.x + facing * 3 * s, y: p.y)); path.addLine(to: CGPoint(x: p.x + facing * (7 + 2 * swing) * s, y: p.y - (7 - 4 * swing) * s)) },
                         with: .color(Color(red: 0.45, green: 0.3, blue: 0.15)), lineWidth: 1.6 * s)
            }
            if u.load > 0.5, let r = u.carrying {
                disc(g, CGPoint(x: p.x - facing * 4 * s, y: p.y - 1 * s), 3 * s * CGFloat(0.5 + 0.5 * min(u.load / RTSWorld.carry, 1)),
                     [Color(red: 0.9, green: 0.25, blue: 0.25), Color(red: 0.55, green: 0.35, blue: 0.15), Color(red: 1, green: 0.82, blue: 0.2), Color(white: 0.7)][r.rawValue])
            }
        case .spearman:
            g.stroke(Path { path in path.move(to: CGPoint(x: p.x + facing * 5 * s, y: p.y + 6 * s)); path.addLine(to: CGPoint(x: p.x + facing * (6 + 3 * swing) * s, y: p.y - 14 * s)) },
                     with: .color(Color(red: 0.5, green: 0.35, blue: 0.2)), lineWidth: 1.4 * s)
        case .archer:
            g.stroke(Path { path in path.addArc(center: CGPoint(x: p.x + facing * 3 * s, y: p.y - 1 * s), radius: 6 * s,
                                                startAngle: .degrees(facing > 0 ? -70 : 110), endAngle: .degrees(facing > 0 ? 70 : 250), clockwise: false) },
                     with: .color(Color(red: 0.5, green: 0.32, blue: 0.15)), lineWidth: 1.4 * s)
        case .knight: break
        }
    }
}
