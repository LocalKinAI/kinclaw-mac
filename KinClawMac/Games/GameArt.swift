import SwiftUI

/// Drawing for the building games — 帝国时代 and 放逐之城 — seen from above at
/// three-quarters: the sun at the top left, shadows falling to the lower
/// right, buildings standing up out of their plots with walls in front and
/// roofs above, trees with trunks and crowns, people with arms and legs. All
/// vector, so it stays sharp at any zoom; what is too small to see at the
/// current size is left out.
enum Art {
    typealias RGB = (Double, Double, Double)

    static func c(_ rgb: RGB, _ a: Double = 1) -> Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2).opacity(a) }
    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
    static func lit(_ rgb: RGB, _ k: Double) -> RGB {
        func f(_ v: Double) -> Double { k >= 1 ? v + (1 - v) * (k - 1) : v * k }
        return (f(rgb.0), f(rgb.1), f(rgb.2))
    }
    static func hash(_ a: Int, _ b: Int) -> Int { JevDraw.hash(a, b) }
    static func unit(_ a: Int, _ b: Int) -> Double { Double(hash(a, b) % 10_000) / 10_000 }

    static let ink: RGB = (0.16, 0.12, 0.1)
    static let skin: [RGB] = [(0.96, 0.8, 0.66), (0.88, 0.68, 0.52), (0.72, 0.52, 0.38), (0.98, 0.86, 0.74)]
    static let hair: [RGB] = [(0.2, 0.14, 0.1), (0.45, 0.3, 0.16), (0.7, 0.5, 0.25), (0.12, 0.1, 0.1), (0.62, 0.34, 0.2)]

    // MARK: The year

    /// What the season does to the land, for a month from 0 (start of spring) to 12 (end of winter).
    struct Season {
        let month: Double
        /// Snow lying: none until late autumn, all winter, melting at the very end.
        var snow: Double {
            if month < 8.9 { return 0 }
            if month < 9.4 { return (month - 8.9) / 0.5 }
            if month < 11.55 { return 1 }
            return max(0, 1 - (month - 11.55) / 0.45)
        }
        var grass: RGB {
            let keys: [(Double, RGB)] = [(0, (0.55, 0.74, 0.36)), (2.5, (0.47, 0.7, 0.3)), (3.5, (0.4, 0.62, 0.27)), (6, (0.47, 0.6, 0.27)),
                                        (7.4, (0.64, 0.61, 0.3)), (8.8, (0.6, 0.5, 0.3)), (12, (0.55, 0.74, 0.36))]
            for k in 1..<keys.count where month <= keys[k].0 {
                let t = (month - keys[k - 1].0) / (keys[k].0 - keys[k - 1].0)
                return mix(mix(keys[k - 1].1, keys[k].1, t), (0.92, 0.94, 0.97), snow)
            }
            return keys[0].1
        }
        /// A broadleaf's crown: fresh, deep, turning, gone.
        func leaves(_ variant: Int) -> RGB? {
            let autumn: [RGB] = [(0.93, 0.56, 0.14), (0.84, 0.28, 0.14), (0.96, 0.78, 0.22), (0.74, 0.4, 0.14)]
            if month < 2.2 { return mix((0.58, 0.8, 0.4), (0.36, 0.64, 0.28), month / 2.2) }
            if month < 6.2 { return (0.26, 0.52, 0.22) }
            if month < 8.9 { return mix((0.26, 0.52, 0.22), autumn[variant % 4], min(1, (month - 6.2) / 1.3)) }
            return nil
        }
        var blossom: Bool { month < 1.3 }
    }

    // MARK: Ground

    /// The grass: its colour, patches of lighter and darker, and — close enough to see them — tufts and flowers.
    static func ground(_ g: inout GraphicsContext, size: CGSize, S: CGFloat, season: Season, visible: CGRect, tiles: CGSize) {
        let base = season.grass
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c(base)))
        let count = Int(tiles.width * tiles.height / 6)
        for k in 0..<count {
            let x = unit(k, 11) * Double(tiles.width), y = unit(k, 12) * Double(tiles.height)
            guard visible.insetBy(dx: -3, dy: -3).contains(CGPoint(x: x, y: y)) else { continue }
            let r = S * CGFloat(0.9 + unit(k, 13) * 2.2)
            let tone = k % 3 == 0 ? lit(base, 0.9) : k % 3 == 1 ? lit(base, 1.07) : mix(base, (0.62, 0.66, 0.3), 0.3)
            g.fill(Path(ellipseIn: CGRect(x: CGFloat(x) * S - r, y: CGFloat(y) * S - r * 0.7, width: 2 * r, height: 1.4 * r)), with: .color(c(tone, 0.28)))
        }
        guard S >= 30 else { return }
        // Tufts, and flowers from spring into summer — close up only.
        let tuft = lit(base, season.snow > 0.5 ? 0.93 : 0.78)
        for y in Int(visible.minY)...Int(visible.maxY) {
            for x in Int(visible.minX)...Int(visible.maxX) {
                for k in 0..<2 {
                    let h = hash(x * 3 + k, y * 7)
                    let p = CGPoint(x: (CGFloat(x) + CGFloat(h % 97) / 97) * S, y: (CGFloat(y) + CGFloat(h / 97 % 89) / 89) * S)
                    g.stroke(Path { q in
                        q.move(to: p); q.addLine(to: CGPoint(x: p.x - S * 0.04, y: p.y - S * 0.1))
                        q.move(to: p); q.addLine(to: CGPoint(x: p.x + S * 0.03, y: p.y - S * 0.12))
                    }, with: .color(c(tuft, 0.7)), lineWidth: max(0.6, S * 0.018))
                    if season.snow < 0.2, season.month < 7, h % 23 == 0 {
                        let flower: [RGB] = [(1, 0.95, 0.5), (1, 1, 1), (0.95, 0.55, 0.7), (0.65, 0.6, 0.95)]
                        let r = S * 0.04
                        g.fill(Path(ellipseIn: CGRect(x: p.x + S * 0.1 - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(c(flower[h % 4])))
                    }
                }
            }
        }
    }

    /// Water drawn as one body: a sandy shore under it, shallows at the edge, deeper in the middle, glints on top — or ice.
    /// Each layer is one shape, the tiles merged, so no seams show between them.
    static func water(_ g: inout GraphicsContext, tiles: [(Int, Int, Int)], S: CGFloat, season: Season, now: Double) {
        // `tiles`: x, y, and how many steps to the nearest land (1 at the shore).
        let snow = season.snow
        func body(_ grow: CGFloat, _ round: CGFloat, _ keep: (Int) -> Bool) -> Path {
            var path = Path()
            for (x, y, d) in tiles where keep(d) {
                path.addRoundedRect(in: CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: S, height: S).insetBy(dx: -grow, dy: -grow), cornerSize: CGSize(width: round, height: round))
            }
            return path
        }
        let sand: RGB = mix((0.84, 0.76, 0.56), (0.9, 0.9, 0.92), snow)
        g.fill(body(S * 0.3, S * 0.45, { _ in true }), with: .color(c(sand)))
        g.fill(body(S * 0.14, S * 0.35, { _ in true }), with: .color(c(lit(sand, 0.84))))
        let shallow: RGB = mix((0.38, 0.68, 0.8), (0.74, 0.85, 0.92), snow * 0.9)
        let deep: RGB = mix((0.15, 0.42, 0.68), (0.62, 0.76, 0.88), snow * 0.9)
        g.fill(body(S * 0.06, S * 0.28, { _ in true }), with: .color(c(shallow)))
        // Deeper water as soft rounds, so the middle of a lake is not a stack of boxes.
        func pools(_ radius: CGFloat, _ keep: (Int) -> Bool) -> Path {
            var path = Path()
            for (x, y, d) in tiles where keep(d) {
                let c = CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.5) * S)
                path.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
            }
            return path
        }
        g.fill(pools(S * 1.3, { $0 >= 2 }), with: .color(c(mix(shallow, deep, 0.45), 0.55)))
        g.fill(pools(S * 1.25, { $0 >= 3 }), with: .color(c(deep, 0.55)))
        if snow > 0.3 {
            for (x, y, d) in tiles where hash(x, y) % 4 == 0 && d > 1 {
                let p = CGPoint(x: (CGFloat(x) + 0.2) * S, y: (CGFloat(y) + 0.4) * S)
                g.stroke(Path { q in q.move(to: p); q.addLine(to: CGPoint(x: p.x + S * 0.3, y: p.y + S * 0.12)); q.addLine(to: CGPoint(x: p.x + S * 0.55, y: p.y + S * 0.05)) },
                         with: .color(.white.opacity(0.5 * snow)), lineWidth: max(0.6, S * 0.025))
            }
            return
        }
        for (x, y, d) in tiles where hash(x, y + 5) % 3 == 0 {
            let phase = now * 0.9 + Double(hash(x, y) % 100) / 16
            let a = (sin(phase) + 1) / 2
            let p = CGPoint(x: (CGFloat(x) + 0.2 + CGFloat(sin(phase * 0.5)) * 0.1) * S, y: (CGFloat(y) + 0.5) * S)
            g.stroke(Path { q in q.move(to: p); q.addQuadCurve(to: CGPoint(x: p.x + S * 0.45, y: p.y), control: CGPoint(x: p.x + S * 0.22, y: p.y - S * 0.1)) },
                     with: .color(.white.opacity((d <= 1 ? 0.35 : 0.5) * a)), lineWidth: max(0.7, S * 0.03))
        }
    }

    /// Roads as paths of trodden earth: one stroke for the edge, one for the middle, round where they bend and meet.
    static func roads(_ g: inout GraphicsContext, _ tiles: [(Int, Int)], isRoad: (Int, Int) -> Bool, S: CGFloat, season: Season) {
        let snow = season.snow
        let edge: RGB = mix((0.62, 0.52, 0.38), (0.8, 0.82, 0.86), snow * 0.85)
        let fill: RGB = mix((0.78, 0.67, 0.5), (0.88, 0.89, 0.92), snow * 0.85)
        var path = Path()
        for (x, y) in tiles {
            let p = CGPoint(x: (CGFloat(x) + 0.5) * S, y: (CGFloat(y) + 0.5) * S)
            path.move(to: p); path.addLine(to: CGPoint(x: p.x + 0.01, y: p.y))
            for (dx, dy) in [(1, 0), (0, 1), (1, 1), (-1, 1)] where isRoad(x + dx, y + dy) {
                if dx != 0, dy != 0, isRoad(x + dx, y) || isRoad(x, y + dy) { continue }
                path.move(to: p); path.addLine(to: CGPoint(x: p.x + CGFloat(dx) * S, y: p.y + CGFloat(dy) * S))
            }
        }
        g.stroke(path, with: .color(c(edge, 0.9)), style: StrokeStyle(lineWidth: S * 0.72, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(c(fill)), style: StrokeStyle(lineWidth: S * 0.56, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(c(lit(fill, 1.08), 0.5)), style: StrokeStyle(lineWidth: S * 0.16, lineCap: .round, lineJoin: .round))
        guard S >= 18 else { return }
        for (x, y) in tiles where hash(x, y) % 2 == 0 {
            let p = CGPoint(x: (CGFloat(x) + 0.3 + CGFloat(hash(x, y) % 40) / 100) * S, y: (CGFloat(y) + 0.35 + CGFloat(hash(y, x) % 30) / 100) * S)
            g.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: S * 0.08, height: S * 0.05)), with: .color(c(lit(edge, 0.85))))
        }
    }

    /// Soft darker ground under a wood, the tiles merged into one shape.
    static func forestFloor(_ g: inout GraphicsContext, _ tiles: [(Int, Int)], S: CGFloat, season: Season) {
        let floor = mix(lit(season.grass, 0.74), (0.86, 0.88, 0.9), season.snow * 0.6)
        var path = Path()
        for (x, y) in tiles {
            path.addRoundedRect(in: CGRect(x: CGFloat(x) * S, y: CGFloat(y) * S, width: S, height: S).insetBy(dx: -S * 0.22, dy: -S * 0.22), cornerSize: CGSize(width: S * 0.55, height: S * 0.55))
        }
        g.fill(path, with: .color(c(floor, 0.5)))
    }

    // MARK: Trees

    /// A tree standing on its tile, its foot at `foot`: a pine or a broadleaf, grown `grown` of the way (a stump below 0.15).
    static func tree(_ g: inout GraphicsContext, foot: CGPoint, S: CGFloat, grown: Double, variant: Int, season: Season, conifer: Bool, now: Double) {
        if grown < 0.15 {
            let r = S * 0.16
            g.fill(Path(ellipseIn: CGRect(x: foot.x - r * 1.1, y: foot.y - r * 0.4, width: r * 2.6, height: r * 1)), with: .color(.black.opacity(0.16)))
            g.fill(Path(roundedRect: CGRect(x: foot.x - r, y: foot.y - r * 1.1, width: 2 * r, height: r * 1.2), cornerRadius: r * 0.3), with: .color(c((0.5, 0.36, 0.22))))
            g.fill(Path(ellipseIn: CGRect(x: foot.x - r, y: foot.y - r * 1.5, width: 2 * r, height: r * 0.8)), with: .color(c((0.86, 0.72, 0.5))))
            if S > 20 { g.stroke(Path(ellipseIn: CGRect(x: foot.x - r * 0.5, y: foot.y - r * 1.3, width: r, height: r * 0.4)), with: .color(c((0.6, 0.45, 0.28))), lineWidth: 0.7) }
            return
        }
        let size = CGFloat(0.4 + 0.6 * min(1, grown)) * CGFloat(0.92 + unit(variant, 3) * 0.2)
        let snow = season.snow
        if S < 22 {
            g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.2 * size, y: foot.y - S * 0.12 * size, width: S * 0.9 * size, height: S * 0.3 * size)), with: .color(.black.opacity(0.18)))
            if conifer {
                let green: RGB = (0.13 + unit(variant, 5) * 0.05, 0.36 + unit(variant, 6) * 0.08, 0.22)
                let w = S * 0.4 * size, top = foot.y - S * 1.15 * size
                g.fill(Path { p in p.move(to: CGPoint(x: foot.x, y: top)); p.addLine(to: CGPoint(x: foot.x + w, y: foot.y - S * 0.12 * size)); p.addLine(to: CGPoint(x: foot.x - w, y: foot.y - S * 0.12 * size)); p.closeSubpath() }, with: .color(c(green)))
                g.fill(Path { p in p.move(to: CGPoint(x: foot.x, y: top)); p.addLine(to: CGPoint(x: foot.x, y: foot.y - S * 0.12 * size)); p.addLine(to: CGPoint(x: foot.x - w, y: foot.y - S * 0.12 * size)); p.closeSubpath() }, with: .color(c(lit(green, 1.25))))
                if snow > 0 { g.fill(Path { p in p.move(to: CGPoint(x: foot.x, y: top)); p.addLine(to: CGPoint(x: foot.x + w * 0.5, y: top + S * 0.45 * size)); p.addLine(to: CGPoint(x: foot.x - w * 0.5, y: top + S * 0.45 * size)); p.closeSubpath() }, with: .color(.white.opacity(0.9 * snow))) }
            } else {
                let r = S * 0.4 * size, centre = CGPoint(x: foot.x, y: foot.y - S * 0.62 * size)
                g.fill(Path(CGRect(x: foot.x - S * 0.04, y: centre.y, width: S * 0.08, height: foot.y - centre.y)), with: .color(c((0.42, 0.3, 0.2))))
                if let leaf = season.leaves(variant) {
                    g.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)), with: .color(c(lit(leaf, 0.85))))
                    g.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.75, y: centre.y - r * 0.85, width: r * 1.2, height: r * 1.1)), with: .color(c(lit(leaf, 1.1))))
                } else {
                    g.stroke(Path(ellipseIn: CGRect(x: centre.x - r * 0.8, y: centre.y - r * 0.8, width: r * 1.6, height: r * 1.6)), with: .color(c((0.38, 0.28, 0.2), 0.8)), lineWidth: max(0.8, S * 0.05))
                    if snow > 0 { g.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.6, y: centre.y - r * 0.8, width: r * 1.2, height: r * 0.5)), with: .color(.white.opacity(0.8 * snow))) }
                }
            }
            return
        }
        // Shadow to the lower right.
        let sh = S * 0.46 * size
        g.fill(Path(ellipseIn: CGRect(x: foot.x - sh * 0.5, y: foot.y - sh * 0.3, width: sh * 2.1, height: sh * 0.75)), with: .color(.black.opacity(0.2)))
        if conifer {
            let trunk = CGRect(x: foot.x - S * 0.05 * size, y: foot.y - S * 0.22 * size, width: S * 0.1 * size, height: S * 0.24 * size)
            g.fill(Path(trunk), with: .color(c((0.38, 0.26, 0.16))))
            let green: RGB = (0.13 + unit(variant, 5) * 0.05, 0.36 + unit(variant, 6) * 0.08, 0.22)
            let tiers = 3
            for k in 0..<tiers {
                let t = CGFloat(k)
                let w = S * 0.46 * size * (1 - t * 0.24)
                let bottom = foot.y - S * (0.16 + t * 0.3) * size
                let top = bottom - S * 0.5 * size
                let left = Path { p in p.move(to: CGPoint(x: foot.x, y: top)); p.addLine(to: CGPoint(x: foot.x, y: bottom + S * 0.04 * size)); p.addLine(to: CGPoint(x: foot.x - w, y: bottom)); p.closeSubpath() }
                let right = Path { p in p.move(to: CGPoint(x: foot.x, y: top)); p.addLine(to: CGPoint(x: foot.x + w, y: bottom)); p.addLine(to: CGPoint(x: foot.x, y: bottom + S * 0.04 * size)); p.closeSubpath() }
                g.fill(left, with: .color(c(lit(green, 1.18 + Double(k) * 0.06))))
                g.fill(right, with: .color(c(lit(green, 0.82 + Double(k) * 0.05))))
                if snow > 0 {
                    let cap = Path { p in p.move(to: CGPoint(x: foot.x, y: top)); p.addLine(to: CGPoint(x: foot.x + w * 0.6, y: top + (bottom - top) * 0.62)); p.addLine(to: CGPoint(x: foot.x - w * 0.6, y: top + (bottom - top) * 0.62)); p.closeSubpath() }
                    g.fill(cap, with: .color(.white.opacity(0.92 * snow)))
                }
            }
            return
        }
        // A broadleaf: trunk, then a crown of overlapping rounds, light at the top left.
        let trunkTop = foot.y - S * 0.42 * size
        g.fill(Path { p in
            p.move(to: CGPoint(x: foot.x - S * 0.07 * size, y: foot.y)); p.addLine(to: CGPoint(x: foot.x - S * 0.04 * size, y: trunkTop))
            p.addLine(to: CGPoint(x: foot.x + S * 0.04 * size, y: trunkTop)); p.addLine(to: CGPoint(x: foot.x + S * 0.07 * size, y: foot.y)); p.closeSubpath()
        }, with: .color(c((0.42, 0.3, 0.2))))
        let centre = CGPoint(x: foot.x, y: foot.y - S * 0.62 * size)
        let r = S * 0.42 * size
        guard let leaf = season.leaves(variant) else {
            // Bare: branches, and snow along them.
            for k in 0..<5 {
                let a = -Double.pi / 2 + (Double(k) - 2) * 0.48
                let end = CGPoint(x: foot.x + CGFloat(cos(a)) * r * 1.05, y: trunkTop + CGFloat(sin(a)) * r * 1.05)
                g.stroke(Path { p in p.move(to: CGPoint(x: foot.x, y: trunkTop)); p.addLine(to: end) }, with: .color(c((0.36, 0.26, 0.18))), lineWidth: max(0.8, S * 0.035 * size))
                if S > 16 {
                    let twig = CGPoint(x: end.x + CGFloat(cos(a + 0.6)) * r * 0.3, y: end.y + CGFloat(sin(a + 0.6)) * r * 0.3)
                    g.stroke(Path { p in p.move(to: CGPoint(x: (end.x + foot.x) / 2, y: (end.y + trunkTop) / 2)); p.addLine(to: twig) }, with: .color(c((0.36, 0.26, 0.18))), lineWidth: max(0.5, S * 0.02 * size))
                }
            }
            if snow > 0 { g.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.7, y: centre.y - r * 0.9, width: r * 1.4, height: r * 0.5)), with: .color(.white.opacity(0.8 * snow))) }
            return
        }
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [(-0.45, 0.15, 0.62), (0.45, 0.18, 0.6), (0, -0.25, 0.7), (-0.2, 0.3, 0.55), (0.25, 0.32, 0.5)]
        for (dx, dy, rr) in blobs {
            let rad = r * rr
            g.fill(Path(ellipseIn: CGRect(x: centre.x + dx * r - rad, y: centre.y + dy * r - rad, width: 2 * rad, height: 2 * rad)), with: .color(c(lit(leaf, 0.78))))
        }
        for (dx, dy, rr) in blobs.prefix(3) {
            let rad = r * rr * 0.78
            g.fill(Path(ellipseIn: CGRect(x: centre.x + dx * r - rad - r * 0.1, y: centre.y + dy * r - rad - r * 0.12, width: 2 * rad, height: 2 * rad)), with: .color(c(leaf)))
        }
        g.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.55, y: centre.y - r * 0.62, width: r * 0.6, height: r * 0.45)), with: .color(c(lit(leaf, 1.28), 0.9)))
        if season.blossom {
            for k in 0..<6 {
                let a = Double(variant % 10 + k * 2)
                let p = CGPoint(x: centre.x + CGFloat(cos(a)) * r * 0.62, y: centre.y + CGFloat(sin(a)) * r * 0.5)
                g.fill(Path(ellipseIn: CGRect(x: p.x - S * 0.035, y: p.y - S * 0.035, width: S * 0.07, height: S * 0.07)), with: .color(c((1, 0.82, 0.9))))
            }
        }
    }

    // MARK: Rocks and what lies in them

    enum Deposit { case stone, ore, gold, berries }

    static func deposit(_ g: inout GraphicsContext, _ kind: Deposit, centre: CGPoint, S: CGFloat, left: Double, variant: Int, season: Season) {
        let size = CGFloat(0.55 + 0.45 * max(0.2, min(1, left)))
        if kind == .berries {
            let r = S * 0.4 * size
            g.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.8, y: centre.y - r * 0.1, width: r * 2, height: r * 0.8)), with: .color(.black.opacity(0.18)))
            for k in 0..<3 {
                let p = CGPoint(x: centre.x + CGFloat(k - 1) * r * 0.45, y: centre.y - r * 0.3 + CGFloat(k % 2) * r * 0.15)
                g.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.45, width: r, height: r * 0.9)), with: .color(c((0.2, 0.45, 0.22))))
                g.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.4, y: p.y - r * 0.45, width: r * 0.6, height: r * 0.5)), with: .color(c((0.3, 0.56, 0.28))))
            }
            for k in 0..<Int(3 + 5 * left) {
                let a = Double(variant + k * 3)
                let p = CGPoint(x: centre.x + CGFloat(cos(a)) * r * 0.7, y: centre.y - r * 0.25 + CGFloat(sin(a)) * r * 0.35)
                g.fill(Path(ellipseIn: CGRect(x: p.x - S * 0.045, y: p.y - S * 0.045, width: S * 0.09, height: S * 0.09)), with: .color(c((0.86, 0.14, 0.2))))
            }
            return
        }
        let body: RGB = kind == .stone ? (0.66, 0.66, 0.68) : kind == .ore ? (0.4, 0.37, 0.38) : (0.55, 0.5, 0.42)
        let r = S * 0.42 * size
        g.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.9 + S * 0.08, y: centre.y - r * 0.2, width: r * 2.2, height: r * 0.9)), with: .color(.black.opacity(0.22)))
        let stones: [(CGFloat, CGFloat, CGFloat)] = [(-0.35, 0.05, 0.62), (0.38, 0.1, 0.55), (0, -0.28, 0.7)]
        for (k, (dx, dy, rr)) in stones.enumerated() {
            let rad = r * rr * CGFloat(0.9 + unit(variant, k) * 0.25)
            let p = CGPoint(x: centre.x + dx * r, y: centre.y + dy * r - r * 0.2)
            let rock = Path(roundedRect: CGRect(x: p.x - rad, y: p.y - rad * 0.85, width: 2 * rad, height: 1.7 * rad), cornerRadius: rad * 0.7)
            g.fill(rock, with: .color(c(lit(body, 0.8))))
            g.fill(Path(roundedRect: CGRect(x: p.x - rad * 0.95, y: p.y - rad * 0.85, width: rad * 1.5, height: rad * 1.1), cornerRadius: rad * 0.6), with: .color(c(body)))
            g.fill(Path(roundedRect: CGRect(x: p.x - rad * 0.7, y: p.y - rad * 0.75, width: rad * 0.8, height: rad * 0.45), cornerRadius: rad * 0.3), with: .color(c(lit(body, 1.25))))
            if kind != .stone {
                let vein: RGB = kind == .ore ? (0.82, 0.44, 0.2) : (1, 0.84, 0.22)
                g.fill(Path(ellipseIn: CGRect(x: p.x - rad * 0.2, y: p.y - rad * 0.2, width: rad * 0.45, height: rad * 0.32)), with: .color(c(vein)))
                g.fill(Path(ellipseIn: CGRect(x: p.x + rad * 0.3, y: p.y + rad * 0.1, width: rad * 0.25, height: rad * 0.2)), with: .color(c(vein)))
            }
            if season.snow > 0 {
                g.fill(Path(roundedRect: CGRect(x: p.x - rad * 0.8, y: p.y - rad * 0.88, width: rad * 1.5, height: rad * 0.55), cornerRadius: rad * 0.3), with: .color(.white.opacity(0.9 * season.snow)))
            }
        }
    }

    // MARK: Buildings

    /// A plot of trodden ground under a building.
    static func plot(_ g: inout GraphicsContext, _ r: CGRect, S: CGFloat, season: Season) {
        let dirt: RGB = mix((0.6, 0.5, 0.36), (0.86, 0.86, 0.88), season.snow * 0.8)
        g.fill(Path(roundedRect: r.insetBy(dx: S * 0.05, dy: S * 0.05), cornerRadius: S * 0.3), with: .color(c(dirt, 0.55)))
    }

    enum Wall { case plaster, logs, planks, stone }
    enum Roof { case shingles, thatch, slate, planks }

    /// A building's front wall standing on the bottom of its footprint, with timber, planks, logs or stones.
    static func wall(_ g: inout GraphicsContext, _ r: CGRect, _ kind: Wall, S: CGFloat, tint: RGB? = nil) {
        let colour: RGB = tint ?? (kind == .plaster ? (0.93, 0.86, 0.72) : kind == .logs ? (0.58, 0.4, 0.24) : kind == .planks ? (0.62, 0.44, 0.28) : (0.66, 0.64, 0.6))
        g.fill(Path(r), with: .color(c(colour)))
        let line = c(lit(colour, 0.7))
        switch kind {
        case .plaster:
            let beam = c((0.4, 0.27, 0.17))
            g.stroke(Path(r), with: .color(beam), lineWidth: max(1, S * 0.05))
            g.stroke(Path { p in p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) }, with: .color(beam), lineWidth: max(0.8, S * 0.04))
            if S > 18 {
                g.stroke(Path { p in p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + r.height * 0.8, y: r.maxY)) }, with: .color(beam), lineWidth: max(0.6, S * 0.03))
                g.stroke(Path { p in p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - r.height * 0.8, y: r.maxY)) }, with: .color(beam), lineWidth: max(0.6, S * 0.03))
            }
        case .logs:
            let n = max(2, Int(r.height / (S * 0.12)))
            for k in 1..<n { let y = r.minY + r.height * CGFloat(k) / CGFloat(n); g.stroke(Path { p in p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)) }, with: .color(line), lineWidth: max(0.6, S * 0.025)) }
            for x in [r.minX, r.maxX] { g.fill(Path(ellipseIn: CGRect(x: x - S * 0.05, y: r.minY, width: S * 0.1, height: r.height)), with: .color(c(lit(colour, 1.2)))) }
        case .planks:
            let n = max(2, Int(r.width / (S * 0.14)))
            for k in 1..<n { let x = r.minX + r.width * CGFloat(k) / CGFloat(n); g.stroke(Path { p in p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)) }, with: .color(line), lineWidth: max(0.6, S * 0.02)) }
        case .stone:
            let rows = max(2, Int(r.height / (S * 0.13)))
            for row in 0..<rows {
                let y = r.minY + r.height * CGFloat(row) / CGFloat(rows)
                g.stroke(Path { p in p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)) }, with: .color(line), lineWidth: max(0.5, S * 0.018))
                var x = r.minX + (row % 2 == 0 ? 0 : S * 0.12)
                while x < r.maxX { g.stroke(Path { p in p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + r.height / CGFloat(rows))) }, with: .color(line), lineWidth: max(0.5, S * 0.018)); x += S * 0.24 }
            }
        }
        g.fill(Path(CGRect(x: r.minX, y: r.maxY - max(1.5, S * 0.05), width: r.width, height: max(1.5, S * 0.05))), with: .color(.black.opacity(0.18)))
    }

    /// A window, lit from inside when `lit` — at night and through the cold months.
    static func window(_ g: inout GraphicsContext, _ r: CGRect, S: CGFloat, glow: Bool) {
        g.fill(Path(r.insetBy(dx: -S * 0.02, dy: -S * 0.02)), with: .color(c((0.36, 0.24, 0.15))))
        g.fill(Path(r), with: .color(glow ? c((1, 0.82, 0.42)) : c((0.3, 0.42, 0.52))))
        if glow { g.fill(Path(ellipseIn: r.insetBy(dx: -r.width * 0.8, dy: -r.height * 0.8)), with: .color(c((1, 0.8, 0.4), 0.18))) }
        g.stroke(Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) },
                 with: .color(c((0.36, 0.24, 0.15))), lineWidth: max(0.5, S * 0.02))
    }

    static func door(_ g: inout GraphicsContext, _ r: CGRect, S: CGFloat, colour: RGB = (0.42, 0.27, 0.16)) {
        g.fill(Path(roundedRect: r, cornerRadii: RectangleCornerRadii(topLeading: r.width * 0.45, bottomLeading: 0, bottomTrailing: 0, topTrailing: r.width * 0.45)), with: .color(c(colour)))
        g.fill(Path(ellipseIn: CGRect(x: r.maxX - r.width * 0.3, y: r.midY, width: r.width * 0.14, height: r.width * 0.14)), with: .color(c((0.9, 0.78, 0.4))))
    }

    /// A roof over a footprint: two slopes meeting at a ridge, light and shade, rows of shingles, thatch or slate; snow on top.
    /// `gable`: the ridge runs away from the viewer and the front shows a triangle of wall.
    static func roof(_ g: inout GraphicsContext, _ r: CGRect, _ kind: Roof, colour: RGB, S: CGFloat, snow: Double, gable: Bool) {
        let dark = lit(colour, 0.72), light = lit(colour, 1.1)
        let line = c(lit(colour, 0.62))
        let over = S * 0.06
        let area = r.insetBy(dx: -over, dy: -over)
        if gable {
            // Ridge from the front down the middle to the back.
            let left = Path { p in p.move(to: CGPoint(x: area.minX, y: area.maxY)); p.addLine(to: CGPoint(x: area.midX, y: area.maxY - area.width * 0.18)); p.addLine(to: CGPoint(x: area.midX, y: area.minY)); p.addLine(to: CGPoint(x: area.minX, y: area.minY + area.width * 0.12)); p.closeSubpath() }
            let right = Path { p in p.move(to: CGPoint(x: area.maxX, y: area.maxY)); p.addLine(to: CGPoint(x: area.midX, y: area.maxY - area.width * 0.18)); p.addLine(to: CGPoint(x: area.midX, y: area.minY)); p.addLine(to: CGPoint(x: area.maxX, y: area.minY + area.width * 0.12)); p.closeSubpath() }
            g.fill(left, with: .color(c(light)))
            g.fill(right, with: .color(c(dark)))
            if S > 14 {
                let rows = max(3, Int(area.height / (S * (kind == .thatch ? 0.09 : 0.14))))
                for k in 1..<rows {
                    let t = CGFloat(k) / CGFloat(rows)
                    for side in [-1.0, 1.0] {
                        let edgeY = area.minY + area.width * 0.12 + (area.maxY - area.minY - area.width * 0.12) * t
                        let ridgeY = area.minY + (area.maxY - area.width * 0.18 - area.minY) * t
                        let xEdge = side < 0 ? area.minX : area.maxX
                        var clipped = g
                        clipped.clip(to: side < 0 ? left : right)
                        clipped.stroke(Path { p in p.move(to: CGPoint(x: xEdge, y: edgeY)); p.addLine(to: CGPoint(x: area.midX, y: ridgeY)) }, with: .color(line), lineWidth: max(0.5, S * 0.02))
                    }
                }
            }
            g.stroke(Path { p in p.move(to: CGPoint(x: area.midX, y: area.minY)); p.addLine(to: CGPoint(x: area.midX, y: area.maxY - area.width * 0.18)) }, with: .color(c(lit(colour, 1.3))), lineWidth: max(1, S * 0.04))
            g.stroke(left, with: .color(c(ink, 0.35)), lineWidth: max(0.5, S * 0.02))
            g.stroke(right, with: .color(c(ink, 0.35)), lineWidth: max(0.5, S * 0.02))
            if snow > 0 {
                g.fill(left, with: .color(.white.opacity(0.85 * snow)))
                g.fill(right, with: .color(Color(red: 0.86, green: 0.9, blue: 0.96).opacity(0.85 * snow)))
            }
        } else {
            // Ridge across: the back slope lit, the front slope in shade.
            let ridge = area.minY + area.height * 0.42
            let back = Path(roundedRect: CGRect(x: area.minX, y: area.minY, width: area.width, height: ridge - area.minY), cornerRadius: S * 0.05)
            let front = Path(CGRect(x: area.minX, y: ridge, width: area.width, height: area.maxY - ridge))
            g.fill(back, with: .color(c(light)))
            g.fill(front, with: .color(c(dark)))
            if S > 14 {
                var y = area.minY + S * 0.13
                while y < area.maxY - S * 0.05 {
                    if abs(y - ridge) > S * 0.05 { g.stroke(Path { p in p.move(to: CGPoint(x: area.minX, y: y)); p.addLine(to: CGPoint(x: area.maxX, y: y)) }, with: .color(line), lineWidth: max(0.5, S * 0.02)) }
                    y += S * (kind == .thatch ? 0.09 : 0.14)
                }
                if kind == .shingles || kind == .slate {
                    var row = 0
                    var yy = area.minY
                    while yy < area.maxY {
                        var x = area.minX + (row % 2 == 0 ? 0 : S * 0.1)
                        while x < area.maxX { g.stroke(Path { p in p.move(to: CGPoint(x: x, y: yy)); p.addLine(to: CGPoint(x: x, y: min(area.maxY, yy + S * 0.14))) }, with: .color(line), lineWidth: max(0.4, S * 0.012)); x += S * 0.2 }
                        yy += S * 0.14; row += 1
                    }
                }
            }
            g.stroke(Path { p in p.move(to: CGPoint(x: area.minX, y: ridge)); p.addLine(to: CGPoint(x: area.maxX, y: ridge)) }, with: .color(c(lit(colour, 1.35))), lineWidth: max(1, S * 0.045))
            g.stroke(Path(roundedRect: area, cornerRadius: S * 0.05), with: .color(c(ink, 0.35)), lineWidth: max(0.5, S * 0.02))
            if snow > 0 {
                g.fill(back, with: .color(.white.opacity(0.88 * snow)))
                g.fill(front, with: .color(Color(red: 0.84, green: 0.88, blue: 0.95).opacity(0.85 * snow)))
            }
        }
        // The eaves' shadow on the wall below.
        g.fill(Path(CGRect(x: area.minX, y: area.maxY, width: area.width, height: max(1.5, S * 0.06))), with: .color(.black.opacity(0.22)))
    }

    /// A chimney with smoke rising and drifting when there is a fire.
    static func chimney(_ g: inout GraphicsContext, at p: CGPoint, S: CGFloat, smoking: Bool, now: Double, seed: Int, snow: Double) {
        let r = CGRect(x: p.x - S * 0.1, y: p.y - S * 0.3, width: S * 0.2, height: S * 0.34)
        g.fill(Path(r), with: .color(c((0.55, 0.36, 0.3))))
        g.fill(Path(CGRect(x: r.minX - S * 0.02, y: r.minY, width: r.width + S * 0.04, height: S * 0.06)), with: .color(c((0.42, 0.28, 0.24))))
        if snow > 0 { g.fill(Path(CGRect(x: r.minX - S * 0.02, y: r.minY - S * 0.03, width: r.width + S * 0.04, height: S * 0.05)), with: .color(.white.opacity(snow))) }
        guard smoking else { return }
        for k in 0..<5 {
            let t = (now * 0.35 + Double(k) * 0.2 + Double(seed % 10) / 10).truncatingRemainder(dividingBy: 1)
            let q = CGPoint(x: r.midX + CGFloat(t * t) * S * 0.9 + CGFloat(sin(now * 1.3 + Double(k))) * S * 0.05, y: r.minY - CGFloat(t) * S * 1.3)
            let rr = S * CGFloat(0.08 + t * 0.2)
            g.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(Color(white: 0.9).opacity(0.6 * (1 - t))))
        }
    }

    /// Scaffolding over a building going up, and a bar for how far along it is.
    static func scaffold(_ g: inout GraphicsContext, _ r: CGRect, S: CGFloat, progress: Double, brought: Double) {
        let wood = c((0.62, 0.46, 0.28))
        let h = r.height * 0.9
        for k in 0...3 {
            let x = r.minX + r.width * CGFloat(k) / 3
            g.stroke(Path { p in p.move(to: CGPoint(x: x, y: r.maxY)); p.addLine(to: CGPoint(x: x, y: r.maxY - h)) }, with: .color(wood), lineWidth: max(1, S * 0.05))
        }
        for k in 1...2 {
            let y = r.maxY - h * CGFloat(k) / 2.5
            g.stroke(Path { p in p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)) }, with: .color(wood), lineWidth: max(1, S * 0.05))
        }
        g.stroke(Path { p in p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - h * 0.8)) }, with: .color(wood), lineWidth: max(0.8, S * 0.035))
        bar(&g, CGRect(x: r.minX, y: r.maxY - h - S * 0.3, width: r.width, height: max(3, S * 0.1)), brought < 0.999 ? brought : progress,
            colour: brought < 0.999 ? Color(red: 0.55, green: 0.72, blue: 1) : Color(red: 0.98, green: 0.78, blue: 0.2))
    }

    static func bar(_ g: inout GraphicsContext, _ r: CGRect, _ f: Double, colour: Color) {
        g.fill(Path(roundedRect: r, cornerRadius: r.height / 2), with: .color(.black.opacity(0.5)))
        g.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width * CGFloat(max(0, min(1, f))), height: r.height), cornerRadius: r.height / 2), with: .color(colour))
    }

    // MARK: People

    enum Item { case none, logs, stone, food, firewood, iron, tools, gold, basket }
    enum Hat { case none, straw, cap, hood, helmet }

    /// A person standing at `foot`, `height` tall: legs that step while walking, arms, clothes, a head and hair, a hat;
    /// a tool raised when working, and what is being carried.
    static func person(_ g: inout GraphicsContext, foot: CGPoint, height: CGFloat, clothes: RGB, facing: Double, walking: Bool, phase: Double,
                       seed: Int, hat: Hat = .none, carry: Item = .none, swing: Double? = nil, tool: RGB = (0.45, 0.32, 0.2), pale: Double = 1,
                       child: Bool = false, grey: Bool = false, trim: RGB? = nil) {
        let h = height, f = CGFloat(facing >= 0 ? 1 : -1)
        g.fill(Path(ellipseIn: CGRect(x: foot.x - h * 0.2, y: foot.y - h * 0.06, width: h * 0.45, height: h * 0.14)), with: .color(.black.opacity(0.22)))
        let step = walking ? CGFloat(sin(phase)) * h * 0.1 : 0
        let hip = CGPoint(x: foot.x, y: foot.y - h * 0.36)
        let legs = c(lit(clothes, 0.55))
        g.stroke(Path { p in p.move(to: hip); p.addLine(to: CGPoint(x: foot.x - h * 0.06 + step, y: foot.y)) }, with: .color(legs), style: StrokeStyle(lineWidth: max(1, h * 0.1), lineCap: .round))
        g.stroke(Path { p in p.move(to: hip); p.addLine(to: CGPoint(x: foot.x + h * 0.06 - step, y: foot.y)) }, with: .color(legs), style: StrokeStyle(lineWidth: max(1, h * 0.1), lineCap: .round))
        let body = CGRect(x: foot.x - h * 0.15, y: foot.y - h * 0.72, width: h * 0.3, height: h * 0.42)
        g.fill(Path(roundedRect: body, cornerRadius: h * 0.1), with: .color(c(clothes, pale)))
        g.fill(Path(roundedRect: CGRect(x: body.minX, y: body.minY, width: body.width * 0.45, height: body.height), cornerRadius: h * 0.1), with: .color(c(lit(clothes, 1.15), pale)))
        if let trim { g.fill(Path(CGRect(x: body.minX, y: body.midY, width: body.width, height: h * 0.06)), with: .color(c(trim))) }
        // Arms: swinging while walking, raised with a tool while working.
        let shoulder = CGPoint(x: foot.x + f * h * 0.1, y: body.minY + h * 0.06)
        if let swing {
            let a = -Double.pi / 2 - Double(f) * (0.4 - swing * 2.4)
            let hand = CGPoint(x: shoulder.x + CGFloat(cos(a)) * h * 0.26 * f * -1 * -1, y: shoulder.y + CGFloat(sin(a)) * h * 0.26)
            g.stroke(Path { p in p.move(to: shoulder); p.addLine(to: hand) }, with: .color(c(clothes)), style: StrokeStyle(lineWidth: max(1, h * 0.08), lineCap: .round))
            let head = CGPoint(x: hand.x + CGFloat(cos(a)) * h * 0.28, y: hand.y + CGFloat(sin(a)) * h * 0.28)
            g.stroke(Path { p in p.move(to: hand); p.addLine(to: head) }, with: .color(c((0.5, 0.36, 0.22))), style: StrokeStyle(lineWidth: max(0.8, h * 0.05), lineCap: .round))
            g.fill(Path(ellipseIn: CGRect(x: head.x - h * 0.07, y: head.y - h * 0.05, width: h * 0.14, height: h * 0.1)), with: .color(c(tool)))
        } else {
            let arm = walking ? CGFloat(sin(phase + .pi)) * h * 0.08 : 0
            g.stroke(Path { p in p.move(to: shoulder); p.addLine(to: CGPoint(x: shoulder.x + arm, y: shoulder.y + h * 0.26)) }, with: .color(c(lit(clothes, 0.85))), style: StrokeStyle(lineWidth: max(1, h * 0.08), lineCap: .round))
        }
        let headR = h * (child ? 0.15 : 0.13)
        let headC = CGPoint(x: foot.x + f * h * 0.01, y: body.minY - headR * 0.85)
        g.fill(Path(ellipseIn: CGRect(x: headC.x - headR, y: headC.y - headR, width: 2 * headR, height: 2 * headR)), with: .color(c(skin[seed % skin.count], pale)))
        let hairColour = grey ? (0.82, 0.82, 0.82) : hair[seed % hair.count]
        switch hat {
        case .straw:
            g.fill(Path(ellipseIn: CGRect(x: headC.x - headR * 1.7, y: headC.y - headR * 0.6, width: headR * 3.4, height: headR * 0.9)), with: .color(c((0.93, 0.82, 0.46))))
            g.fill(Path(ellipseIn: CGRect(x: headC.x - headR * 0.85, y: headC.y - headR * 1.2, width: headR * 1.7, height: headR * 1.1)), with: .color(c((0.88, 0.76, 0.4))))
        case .cap:
            g.fill(Path(ellipseIn: CGRect(x: headC.x - headR, y: headC.y - headR * 1.15, width: headR * 2, height: headR * 1.2)), with: .color(c(lit(clothes, 0.7))))
        case .hood:
            g.fill(Path(ellipseIn: CGRect(x: headC.x - headR * 1.15, y: headC.y - headR * 1.2, width: headR * 2.3, height: headR * 1.6)), with: .color(c(lit(clothes, 0.8))))
            g.fill(Path(ellipseIn: CGRect(x: headC.x - headR * 0.7 + f * headR * 0.2, y: headC.y - headR * 0.5, width: headR * 1.4, height: headR * 1.2)), with: .color(c(skin[seed % skin.count], pale)))
        case .helmet:
            g.fill(Path(ellipseIn: CGRect(x: headC.x - headR * 1.1, y: headC.y - headR * 1.25, width: headR * 2.2, height: headR * 1.4)), with: .color(c((0.62, 0.64, 0.68))))
            g.fill(Path(CGRect(x: headC.x - headR * 1.2, y: headC.y - headR * 0.2, width: headR * 2.4, height: headR * 0.22)), with: .color(c((0.5, 0.52, 0.56))))
        case .none:
            g.fill(Path(ellipseIn: CGRect(x: headC.x - headR * 1.02, y: headC.y - headR * 1.12, width: headR * 2.04, height: headR * 1.25)), with: .color(c(hairColour)))
        }
        // What is carried, on the shoulder or in the arms.
        let at = CGPoint(x: foot.x - f * h * 0.08, y: body.minY + h * 0.02)
        switch carry {
        case .none: break
        case .logs, .firewood:
            let colour: RGB = carry == .logs ? (0.58, 0.4, 0.22) : (0.72, 0.52, 0.3)
            for k in 0..<2 {
                let r = CGRect(x: at.x - h * 0.3, y: at.y - h * 0.08 - CGFloat(k) * h * 0.08, width: h * 0.6, height: h * 0.08)
                g.fill(Path(roundedRect: r, cornerRadius: h * 0.03), with: .color(c(colour)))
                g.fill(Path(ellipseIn: CGRect(x: r.maxX - h * 0.05, y: r.minY, width: h * 0.08, height: r.height)), with: .color(c((0.85, 0.7, 0.48))))
            }
        case .stone, .iron, .gold:
            let colour: RGB = carry == .stone ? (0.72, 0.72, 0.74) : carry == .iron ? (0.36, 0.33, 0.36) : (1, 0.84, 0.24)
            g.fill(Path(roundedRect: CGRect(x: at.x - h * 0.12, y: at.y - h * 0.14, width: h * 0.24, height: h * 0.18), cornerRadius: h * 0.05), with: .color(c(colour)))
        case .food, .basket:
            g.fill(Path(ellipseIn: CGRect(x: at.x - h * 0.15, y: at.y - h * 0.12, width: h * 0.3, height: h * 0.18)), with: .color(c((0.72, 0.54, 0.3))))
            g.fill(Path(ellipseIn: CGRect(x: at.x - h * 0.08, y: at.y - h * 0.16, width: h * 0.09, height: h * 0.09)), with: .color(c((0.88, 0.2, 0.2))))
            g.fill(Path(ellipseIn: CGRect(x: at.x + h * 0.01, y: at.y - h * 0.15, width: h * 0.09, height: h * 0.09)), with: .color(c((0.95, 0.75, 0.25))))
        case .tools:
            g.stroke(Path { p in p.move(to: CGPoint(x: at.x - h * 0.1, y: at.y + h * 0.05)); p.addLine(to: CGPoint(x: at.x + h * 0.1, y: at.y - h * 0.15)) }, with: .color(c((0.3, 0.3, 0.32))), lineWidth: max(1, h * 0.06))
        }
    }

    // MARK: Weather

    static func snowfall(_ g: inout GraphicsContext, size: CGSize, amount: Double, now: Double, S: CGFloat) {
        let n = Int(Double(size.width * size.height) / 9000 * amount)
        for k in 0..<n {
            let x0 = unit(k, 21) * Double(size.width)
            let speed = 20 + unit(k, 22) * 22
            let y = (unit(k, 23) * Double(size.height) + now * speed).truncatingRemainder(dividingBy: Double(size.height))
            let x = x0 + sin(now * 0.8 + Double(k)) * 7
            let r = CGFloat(0.8 + unit(k, 24) * 1.6)
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.85)))
        }
    }

    static func leaves(_ g: inout GraphicsContext, size: CGSize, now: Double, spring: Bool) {
        let colours: [RGB] = spring ? [(1, 0.8, 0.88), (1, 0.9, 0.94)] : [(0.92, 0.46, 0.15), (0.84, 0.26, 0.15), (0.95, 0.72, 0.2)]
        let n = Int(Double(size.width * size.height) / (spring ? 45000 : 30000))
        for k in 0..<n {
            let x0 = unit(k, 31) * Double(size.width)
            let y = (unit(k, 32) * Double(size.height) + now * 13).truncatingRemainder(dividingBy: Double(size.height))
            let x = (x0 + now * 8 + sin(now * 1.3 + Double(k)) * 10).truncatingRemainder(dividingBy: Double(size.width))
            var leaf = g
            leaf.translateBy(x: x, y: y); leaf.rotate(by: .radians(now * 2 + Double(k)))
            leaf.fill(Path(ellipseIn: CGRect(x: -3.2, y: -1.6, width: 6.4, height: 3.2)), with: .color(c(colours[k % colours.count], 0.85)))
        }
    }
}

/// The camera over a building game's map: how far in (1 shows the whole map), and which tile is in the
/// middle of the view. Everything in tiles or in points of the view the map is shown in.
struct GameCamera {
    let map: CGSize
    var zoom: CGFloat = 2
    var focus: CGPoint

    static let closest: CGFloat = 3.2

    init(map: CGSize, focus: CGPoint, zoom: CGFloat = 2) { self.map = map; self.focus = focus; self.zoom = zoom }

    /// Points to a tile.
    func tile(_ view: CGSize) -> CGFloat { min(view.width / map.width, view.height / map.height) * zoom }

    /// The map's tile at the view's top-left corner: the focus in the middle, the map's edges never pulled inside the view.
    func origin(_ view: CGSize) -> CGPoint {
        let S = tile(view), cols = view.width / S, rows = view.height / S
        func axis(_ f: CGFloat, _ span: CGFloat, _ size: CGFloat) -> CGFloat { span >= size ? (size - span) / 2 : min(max(f - span / 2, 0), size - span) }
        return CGPoint(x: axis(focus.x, cols, map.width), y: axis(focus.y, rows, map.height))
    }

    /// What is in view, in tiles.
    func visible(_ view: CGSize) -> CGRect {
        let S = tile(view), o = origin(view)
        return CGRect(x: o.x, y: o.y, width: view.width / S, height: view.height / S)
    }

    /// The tile (with fractions) under a point of the view.
    func at(_ p: CGPoint, _ view: CGSize) -> CGPoint {
        let S = tile(view), o = origin(view)
        return CGPoint(x: p.x / S + o.x, y: p.y / S + o.y)
    }

    /// Closer or further, keeping the tile under `p` where it is.
    mutating func zoom(by factor: CGFloat, at p: CGPoint, _ view: CGSize) {
        let before = at(p, view)
        zoom = min(Self.closest, max(1, zoom * factor))
        let S = tile(view)
        let o = CGPoint(x: before.x - p.x / S, y: before.y - p.y / S)
        focus = CGPoint(x: o.x + view.width / S / 2, y: o.y + view.height / S / 2)
        settle(view)
    }

    /// Slide the map by points.
    mutating func pan(_ dx: CGFloat, _ dy: CGFloat, _ view: CGSize) {
        let S = tile(view)
        focus = CGPoint(x: focus.x - dx / S, y: focus.y - dy / S)
        settle(view)
    }

    /// Keep the focus where the view can actually be.
    mutating func settle(_ view: CGSize) {
        let o = origin(view), S = tile(view)
        focus = CGPoint(x: o.x + view.width / S / 2, y: o.y + view.height / S / 2)
    }
}

// MARK: - Buildings and soldiers the strategy games share

extension Art {
    /// A building's footprint turned into a front wall and the roof above it, and the shadow it throws.
    struct Frame {
        let footprint: CGRect, wall: CGRect, roof: CGRect, bottom: CGFloat
        init(_ F: CGRect, S: CGFloat, tall: Bool) {
            let m = S * 0.15, h = S * (tall ? 0.78 : 0.56)
            footprint = F; bottom = F.maxY - m
            wall = CGRect(x: F.minX + m, y: bottom - h, width: F.width - 2 * m, height: h)
            roof = CGRect(x: F.minX + m, y: F.minY + m - h * 0.45, width: F.width - 2 * m, height: wall.minY - (F.minY + m - h * 0.45))
        }
    }

    static func shadow(_ g: inout GraphicsContext, _ f: Frame, S: CGFloat, strength: Double = 0.2) {
        g.fill(Path { p in
            p.move(to: CGPoint(x: f.wall.maxX, y: f.roof.minY + S * 0.2)); p.addLine(to: CGPoint(x: f.wall.maxX + S * 0.35, y: f.roof.minY + S * 0.45))
            p.addLine(to: CGPoint(x: f.wall.maxX + S * 0.35, y: f.bottom + S * 0.18)); p.addLine(to: CGPoint(x: f.wall.minX + S * 0.25, y: f.bottom + S * 0.18))
            p.addLine(to: CGPoint(x: f.wall.minX, y: f.bottom)); p.addLine(to: CGPoint(x: f.wall.maxX, y: f.bottom)); p.closeSubpath()
        }, with: .color(.black.opacity(strength)))
    }

    /// A house's front: the triangle of wall above the door under two roof slopes running back.
    static func gable(_ g: inout GraphicsContext, _ wall: CGRect, _ roofArea: CGRect, colour: RGB, kind: Roof, S: CGFloat, snow: Double, gableWall: RGB = (0.9, 0.83, 0.68)) {
        let rise = wall.width * 0.36
        let apex = CGPoint(x: wall.midX, y: wall.minY - rise)
        let over = S * 0.08
        let depth = max(S * 0.3, wall.minY - roofArea.minY - rise * 0.5)
        g.fill(Path { p in p.move(to: CGPoint(x: wall.minX, y: wall.minY)); p.addLine(to: apex); p.addLine(to: CGPoint(x: wall.maxX, y: wall.minY)); p.closeSubpath() }, with: .color(c(gableWall)))
        g.stroke(Path { p in p.move(to: CGPoint(x: wall.minX + wall.width * 0.25, y: wall.minY - rise * 0.5)); p.addLine(to: CGPoint(x: wall.maxX - wall.width * 0.25, y: wall.minY - rise * 0.5)) }, with: .color(c((0.4, 0.27, 0.17))), lineWidth: max(0.8, S * 0.035))
        let leftFront = CGPoint(x: wall.minX - over, y: wall.minY + over), rightFront = CGPoint(x: wall.maxX + over, y: wall.minY + over)
        let apexBack = CGPoint(x: apex.x, y: apex.y - depth)
        let left = Path { p in p.move(to: leftFront); p.addLine(to: CGPoint(x: apex.x, y: apex.y - over)); p.addLine(to: apexBack); p.addLine(to: CGPoint(x: leftFront.x, y: leftFront.y - depth)); p.closeSubpath() }
        let right = Path { p in p.move(to: rightFront); p.addLine(to: CGPoint(x: apex.x, y: apex.y - over)); p.addLine(to: apexBack); p.addLine(to: CGPoint(x: rightFront.x, y: rightFront.y - depth)); p.closeSubpath() }
        let lightSide = lit(colour, 1.1), darkSide = lit(colour, 0.74)
        g.fill(left, with: .color(c(lightSide)))
        g.fill(right, with: .color(c(darkSide)))
        if S > 14 {
            let rows = max(3, Int(depth / (S * (kind == .thatch ? 0.08 : 0.12))))
            for (side, shade, edge) in [(left, lightSide, leftFront), (right, darkSide, rightFront)] {
                var clipped = g
                clipped.clip(to: side)
                for k in 0...rows {
                    let t = CGFloat(k) / CGFloat(rows)
                    clipped.stroke(Path { p in p.move(to: CGPoint(x: edge.x, y: edge.y - depth * t)); p.addLine(to: CGPoint(x: apex.x, y: apex.y - over - depth * t)) },
                                   with: .color(c(lit(shade, 0.8))), lineWidth: max(0.5, S * (kind == .thatch ? 0.025 : 0.018)))
                }
            }
        }
        if snow > 0 {
            g.fill(left, with: .color(.white.opacity(0.9 * snow)))
            g.fill(right, with: .color(Color(red: 0.84, green: 0.88, blue: 0.95).opacity(0.9 * snow)))
        }
        g.stroke(Path { p in p.move(to: CGPoint(x: apex.x, y: apex.y - over)); p.addLine(to: apexBack) }, with: .color(c(lit(colour, 1.3))), lineWidth: max(1, S * 0.05))
        g.stroke(left, with: .color(c(ink, 0.3)), lineWidth: max(0.5, S * 0.02))
        g.stroke(right, with: .color(c(ink, 0.3)), lineWidth: max(0.5, S * 0.02))
    }

    /// A flag on a pole, its foot at `at`.
    static func banner(_ g: inout GraphicsContext, _ at: CGPoint, _ S: CGFloat, _ colour: RGB, now: Double) {
        g.stroke(Path { p in p.move(to: at); p.addLine(to: CGPoint(x: at.x, y: at.y - S * 0.9)) }, with: .color(c((0.3, 0.24, 0.18))), lineWidth: max(1, S * 0.05))
        let wave = CGFloat(sin(now * 4 + Double(at.x))) * S * 0.05
        g.fill(Path { p in
            p.move(to: CGPoint(x: at.x, y: at.y - S * 0.9)); p.addQuadCurve(to: CGPoint(x: at.x + S * 0.5, y: at.y - S * 0.78 + wave), control: CGPoint(x: at.x + S * 0.25, y: at.y - S * 0.95 - wave))
            p.addLine(to: CGPoint(x: at.x, y: at.y - S * 0.58)); p.closeSubpath()
        }, with: .color(c(colour)))
    }

    /// A small house on a footprint of about two tiles: wall, gable, door, windows, chimney.
    static func house(_ g: inout GraphicsContext, _ F: CGRect, S: CGFloat, wall: Wall, roof: Roof, roofColour: RGB, trim: RGB?, snow: Double, glow: Bool, smoke: Bool, now: Double, seed: Int) {
        let f = Frame(F, S: S, tall: false)
        shadow(&g, f, S: S)
        Art.wall(&g, f.wall, wall, S: S)
        gable(&g, f.wall, f.roof, colour: roofColour, kind: roof, S: S, snow: snow)
        door(&g, CGRect(x: f.wall.midX - S * 0.13, y: f.wall.maxY - f.wall.height * 0.62, width: S * 0.26, height: f.wall.height * 0.62), S: S)
        window(&g, CGRect(x: f.wall.minX + S * 0.16, y: f.wall.minY + f.wall.height * 0.28, width: S * 0.22, height: S * 0.19), S: S, glow: glow)
        if let trim { g.fill(Path(CGRect(x: f.wall.maxX - S * 0.34, y: f.wall.minY + f.wall.height * 0.25, width: S * 0.18, height: S * 0.26)), with: .color(c(trim))) }
        else { window(&g, CGRect(x: f.wall.maxX - S * 0.38, y: f.wall.minY + f.wall.height * 0.28, width: S * 0.22, height: S * 0.19), S: S, glow: glow) }
        chimney(&g, at: CGPoint(x: f.roof.maxX - S * 0.38, y: f.roof.minY + f.roof.height * 0.45), S: S, smoking: smoke, now: now, seed: seed, snow: snow)
    }

    enum Yard { case none, weapons, target, hay }

    /// A long hall on about three tiles: a big roof, a wide door, a band of the team's colour, banners, and what stands in the yard.
    static func hall(_ g: inout GraphicsContext, _ F: CGRect, S: CGFloat, wall: Wall, roof: Roof, roofColour: RGB, team: RGB?, yard: Yard, snow: Double, now: Double) {
        let f = Frame(F, S: S, tall: true)
        shadow(&g, f, S: S)
        Art.wall(&g, f.wall, wall, S: S)
        Art.roof(&g, f.roof, roof, colour: roofColour, S: S, snow: snow, gable: false)
        door(&g, CGRect(x: f.wall.midX - S * 0.26, y: f.wall.maxY - f.wall.height * 0.72, width: S * 0.52, height: f.wall.height * 0.72), S: S)
        if let team {
            g.fill(Path(CGRect(x: f.wall.minX, y: f.wall.minY + S * 0.04, width: f.wall.width, height: S * 0.1)), with: .color(c(team, 0.9)))
            banner(&g, CGPoint(x: f.wall.minX + S * 0.2, y: f.roof.minY + S * 0.4), S, team, now: now)
            banner(&g, CGPoint(x: f.wall.maxX - S * 0.2, y: f.roof.minY + S * 0.4), S, team, now: now)
        }
        let base = CGPoint(x: f.wall.minX + S * 0.45, y: f.bottom + S * 0.02)
        switch yard {
        case .weapons:
            for k in 0..<3 { g.stroke(Path { p in p.move(to: CGPoint(x: base.x + CGFloat(k) * S * 0.14, y: base.y)); p.addLine(to: CGPoint(x: base.x + CGFloat(k) * S * 0.14 + S * 0.05, y: base.y - S * 0.7)) }, with: .color(c((0.5, 0.36, 0.22))), lineWidth: max(1, S * 0.04)) }
        case .target:
            let t = CGPoint(x: f.wall.maxX - S * 0.55, y: f.bottom - S * 0.25)
            for (k, ring) in [RGB(0.95, 0.95, 0.9), (0.85, 0.2, 0.2), (0.95, 0.95, 0.9)].enumerated() {
                let r = S * CGFloat(0.22 - Double(k) * 0.07)
                g.fill(Path(ellipseIn: CGRect(x: t.x - r, y: t.y - r, width: 2 * r, height: 2 * r)), with: .color(c(ring)))
            }
        case .hay:
            g.fill(Path(roundedRect: CGRect(x: f.wall.maxX - S * 0.7, y: f.bottom - S * 0.3, width: S * 0.5, height: S * 0.26), cornerRadius: S * 0.08), with: .color(c((0.9, 0.78, 0.4))))
        case .none: break
        }
    }

    /// The town's heart on about three tiles: a hall and a keep in front of it with a spire and a flag.
    static func keep(_ g: inout GraphicsContext, _ F: CGRect, S: CGFloat, wall: Wall, roof: Roof, roofColour: RGB, team: RGB?, snow: Double, glow: Bool, now: Double) {
        let f = Frame(F, S: S, tall: true)
        shadow(&g, f, S: S)
        Art.wall(&g, f.wall, wall, S: S)
        Art.roof(&g, f.roof, roof, colour: roofColour, S: S, snow: snow, gable: false)
        let tower = CGRect(x: f.wall.midX - S * 0.5, y: f.roof.minY + f.roof.height * 0.2, width: S * 1.0, height: f.wall.minY - f.roof.minY - f.roof.height * 0.2 + S * 0.2)
        Art.wall(&g, tower, wall == .stone ? .stone : .plaster, S: S, tint: wall == .stone ? (0.8, 0.77, 0.7) : nil)
        let tip = CGPoint(x: tower.midX, y: tower.minY - S * 0.95)
        g.fill(Path { p in p.move(to: tip); p.addLine(to: CGPoint(x: tower.maxX + S * 0.1, y: tower.minY + S * 0.05)); p.addLine(to: CGPoint(x: tower.minX - S * 0.1, y: tower.minY + S * 0.05)); p.closeSubpath() }, with: .color(c(roofColour)))
        g.fill(Path { p in p.move(to: tip); p.addLine(to: CGPoint(x: tower.maxX + S * 0.1, y: tower.minY + S * 0.05)); p.addLine(to: CGPoint(x: tower.midX, y: tower.minY + S * 0.05)); p.closeSubpath() }, with: .color(c(lit(roofColour, 0.72))))
        if snow > 0 { g.fill(Path { p in p.move(to: tip); p.addLine(to: CGPoint(x: tip.x + S * 0.2, y: tip.y + S * 0.38)); p.addLine(to: CGPoint(x: tip.x - S * 0.2, y: tip.y + S * 0.38)); p.closeSubpath() }, with: .color(.white.opacity(snow))) }
        banner(&g, CGPoint(x: tip.x, y: tip.y + S * 0.02), S, team ?? (0.2, 0.62, 0.46), now: now)
        window(&g, CGRect(x: tower.midX - S * 0.14, y: tower.minY + S * 0.2, width: S * 0.28, height: S * 0.3), S: S, glow: glow)
        door(&g, CGRect(x: f.wall.midX - S * 0.22, y: f.wall.maxY - f.wall.height * 0.7, width: S * 0.44, height: f.wall.height * 0.7), S: S, colour: (0.36, 0.22, 0.14))
        for x in [f.wall.minX + S * 0.32, f.wall.maxX - S * 0.62] { window(&g, CGRect(x: x, y: f.wall.minY + f.wall.height * 0.25, width: S * 0.3, height: S * 0.26), S: S, glow: glow) }
        if let team { g.fill(Path(CGRect(x: f.wall.minX, y: f.wall.minY + S * 0.05, width: f.wall.width, height: S * 0.1)), with: .color(c(team, 0.85))) }
    }

    /// A stone tower on one tile: battlements, an arrow slit, a flag.
    static func tower(_ g: inout GraphicsContext, _ F: CGRect, S: CGFloat, team: RGB?, snow: Double, now: Double) {
        let body = CGRect(x: F.minX + S * 0.14, y: F.maxY - S * 1.9, width: S * 0.72, height: S * 1.8)
        g.fill(Path(ellipseIn: CGRect(x: body.minX + S * 0.1, y: F.maxY - S * 0.3, width: S * 1.1, height: S * 0.4)), with: .color(.black.opacity(0.22)))
        Art.wall(&g, body, .stone, S: S * 0.8)
        for k in 0..<3 { g.fill(Path(CGRect(x: body.minX + CGFloat(k) * body.width * 0.38, y: body.minY - S * 0.16, width: body.width * 0.24, height: S * 0.18)), with: .color(c((0.66, 0.64, 0.6)))) }
        if snow > 0 { for k in 0..<3 { g.fill(Path(CGRect(x: body.minX + CGFloat(k) * body.width * 0.38, y: body.minY - S * 0.2, width: body.width * 0.24, height: S * 0.06)), with: .color(.white.opacity(snow))) } }
        g.fill(Path(CGRect(x: body.midX - S * 0.06, y: body.minY + S * 0.35, width: S * 0.12, height: S * 0.28)), with: .color(c((0.15, 0.12, 0.1))))
        if let team { banner(&g, CGPoint(x: body.midX, y: body.minY - S * 0.1), S * 0.8, team, now: now) }
    }

    enum Pile { case logs, stone, gold }

    /// An open shed on about two tiles: a back wall, a lean-to roof, and what is stacked under it.
    static func shed(_ g: inout GraphicsContext, _ F: CGRect, S: CGFloat, pile: Pile, team: RGB?, snow: Double, now: Double) {
        let f = Frame(F, S: S, tall: false)
        let back = CGRect(x: f.wall.minX, y: f.roof.minY + S * 0.1, width: f.wall.width, height: f.bottom - f.roof.minY - S * 0.1)
        shadow(&g, f, S: S)
        Art.wall(&g, back, .planks, S: S)
        Art.roof(&g, CGRect(x: f.roof.minX - S * 0.05, y: f.roof.minY, width: f.roof.width + S * 0.1, height: f.roof.height * 0.7), .planks, colour: (0.52, 0.38, 0.26), S: S, snow: snow, gable: false)
        switch pile {
        case .logs:
            for row in 0..<2 { for k in 0..<(3 - row) {
                let d = S * 0.2, x = f.wall.minX + S * 0.1 + CGFloat(row) * d * 0.5 + CGFloat(k) * d, y = f.bottom - CGFloat(row + 1) * d * 0.9
                g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(c((0.58, 0.4, 0.22))))
                g.fill(Path(ellipseIn: CGRect(x: x + d * 0.2, y: y + d * 0.2, width: d * 0.6, height: d * 0.6)), with: .color(c((0.88, 0.74, 0.5))))
            } }
        case .stone, .gold:
            for k in 0..<3 {
                let gold = pile == .gold ? k != 1 : k == 1
                g.fill(Path(roundedRect: CGRect(x: f.wall.minX + S * (0.1 + CGFloat(k) * 0.28), y: f.bottom - S * 0.26, width: S * 0.24, height: S * 0.2), cornerRadius: S * 0.04), with: .color(gold ? c((0.95, 0.8, 0.25)) : c((0.74, 0.74, 0.72))))
            }
        }
        if let team { banner(&g, CGPoint(x: f.wall.maxX - S * 0.1, y: f.bottom - S * 0.05), S * 0.8, team, now: now) }
    }

    enum Soldier { case spearman, archer, knight }

    /// A soldier in its team's colours: a spearman with spear and shield, an archer with a bow, a knight on a horse.
    static func soldier(_ g: inout GraphicsContext, _ kind: Soldier, foot: CGPoint, S: CGFloat, team: RGB, facing: Double, walking: Bool, working: Bool, seed: Int, now: Double) {
        let phase = now * 11 + Double(seed)
        let f = CGFloat(facing >= 0 ? 1 : -1)
        switch kind {
        case .spearman:
            person(&g, foot: foot, height: S * 0.78, clothes: team, facing: facing, walking: walking, phase: phase, seed: seed, hat: .helmet, trim: (0.55, 0.55, 0.58))
            let thrust = working ? CGFloat(sin(now * 14)) * S * 0.12 : 0
            let hand = CGPoint(x: foot.x + f * S * 0.16, y: foot.y - S * 0.42)
            let tip = CGPoint(x: hand.x + f * (S * 0.2 + thrust), y: hand.y - S * 0.62)
            g.stroke(Path { p in p.move(to: CGPoint(x: hand.x - f * S * 0.1, y: hand.y + S * 0.3)); p.addLine(to: tip) }, with: .color(c((0.5, 0.36, 0.22))), lineWidth: max(1, S * 0.045))
            g.fill(Path { p in p.move(to: CGPoint(x: tip.x, y: tip.y - S * 0.14)); p.addLine(to: CGPoint(x: tip.x + S * 0.05, y: tip.y + S * 0.02)); p.addLine(to: CGPoint(x: tip.x - S * 0.05, y: tip.y + S * 0.02)); p.closeSubpath() }, with: .color(c((0.8, 0.82, 0.86))))
            g.fill(Path(ellipseIn: CGRect(x: foot.x - f * S * 0.3, y: foot.y - S * 0.62, width: S * 0.24, height: S * 0.3)), with: .color(c(lit(team, 0.8))))
        case .archer:
            person(&g, foot: foot, height: S * 0.74, clothes: lit(team, 0.85), facing: facing, walking: walking, phase: phase, seed: seed, hat: .hood, trim: (0.45, 0.32, 0.2))
            let centre = CGPoint(x: foot.x + f * S * 0.2, y: foot.y - S * 0.46)
            g.stroke(Path { p in p.addArc(center: centre, radius: S * 0.26, startAngle: .degrees(f > 0 ? -70 : 110), endAngle: .degrees(f > 0 ? 70 : 250), clockwise: false) }, with: .color(c((0.5, 0.32, 0.15))), lineWidth: max(1, S * 0.05))
            g.stroke(Path { p in p.move(to: CGPoint(x: centre.x + f * S * 0.09, y: centre.y - S * 0.24)); p.addLine(to: CGPoint(x: centre.x + f * S * (working ? -0.02 : 0.09), y: centre.y)); p.addLine(to: CGPoint(x: centre.x + f * S * 0.09, y: centre.y + S * 0.24)) }, with: .color(c((0.9, 0.9, 0.85), 0.8)), lineWidth: max(0.5, S * 0.015))
        case .knight:
            horse(&g, foot, S, facing, walking: walking, phase: phase)
            person(&g, foot: CGPoint(x: foot.x, y: foot.y - S * 0.36), height: S * 0.66, clothes: team, facing: facing, walking: false, phase: 0, seed: seed, hat: .helmet, trim: (0.8, 0.8, 0.84))
            let swing = working ? CGFloat(sin(now * 12)) * 0.4 : 0
            let hand = CGPoint(x: foot.x + f * S * 0.14, y: foot.y - S * 0.7)
            g.stroke(Path { p in p.move(to: hand); p.addLine(to: CGPoint(x: hand.x + f * S * 0.5, y: hand.y - S * (0.3 + swing))) }, with: .color(c((0.85, 0.86, 0.9))), lineWidth: max(1, S * 0.05))
        }
    }

    static func horse(_ g: inout GraphicsContext, _ foot: CGPoint, _ S: CGFloat, _ facing: Double, walking: Bool, phase: Double) {
        let f = CGFloat(facing >= 0 ? 1 : -1)
        let coat: RGB = (0.46, 0.32, 0.2)
        g.fill(Path(ellipseIn: CGRect(x: foot.x - S * 0.45, y: foot.y - S * 0.1, width: S * 0.95, height: S * 0.22)), with: .color(.black.opacity(0.22)))
        let step = walking ? CGFloat(sin(phase)) * S * 0.08 : 0
        for (dx, s) in [(-0.28, step), (-0.18, -step), (0.2, -step), (0.3, step)] as [(CGFloat, CGFloat)] {
            g.stroke(Path { p in p.move(to: CGPoint(x: foot.x + f * S * dx, y: foot.y - S * 0.3)); p.addLine(to: CGPoint(x: foot.x + f * S * dx + s, y: foot.y)) }, with: .color(c(lit(coat, 0.8))), style: StrokeStyle(lineWidth: max(1, S * 0.07), lineCap: .round))
        }
        let body = CGRect(x: foot.x - S * 0.38, y: foot.y - S * 0.52, width: S * 0.76, height: S * 0.3)
        g.fill(Path(roundedRect: body, cornerRadius: S * 0.14), with: .color(c(coat)))
        g.fill(Path(roundedRect: CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.45), cornerRadius: S * 0.1), with: .color(c(lit(coat, 1.15))))
        let neck = CGPoint(x: foot.x + f * S * 0.34, y: body.minY + S * 0.05)
        g.stroke(Path { p in p.move(to: neck); p.addLine(to: CGPoint(x: neck.x + f * S * 0.12, y: neck.y - S * 0.26)) }, with: .color(c(coat)), style: StrokeStyle(lineWidth: max(1.5, S * 0.14), lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: neck.x + f * S * 0.08 - S * 0.1, y: neck.y - S * 0.36, width: S * 0.24, height: S * 0.14)), with: .color(c(coat)))
        g.stroke(Path { p in p.move(to: CGPoint(x: foot.x - f * S * 0.38, y: body.minY + S * 0.08)); p.addQuadCurve(to: CGPoint(x: foot.x - f * S * 0.5, y: body.maxY), control: CGPoint(x: foot.x - f * S * 0.52, y: body.minY + S * 0.05)) }, with: .color(c((0.25, 0.18, 0.12))), lineWidth: max(1, S * 0.05))
    }
}
