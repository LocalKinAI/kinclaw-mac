import AppKit
import CoreGraphics
import CoreText

/// The land of 190 AD, painted once with CoreGraphics and then only placed:
/// the seas and coasts, the 黄河 and the 长江 and their tributaries, the lakes,
/// the mountains drawn as inked peaks, the deserts of the north-west and the
/// high plateau of the west, the Great Wall, the provinces' names in faint
/// brush script — on warm paper. And the tint of who holds what, repainted only
/// when a city changes hands.
enum WarlordLand {
    typealias RGB = (Double, Double, Double)
    /// Pixels to a map unit in the painted land.
    static let px: CGFloat = 2.4
    nonisolated(unsafe) static var kept: CGImage?
    nonisolated(unsafe) static var tinted: (key: [Int], image: CGImage)?

    static func image() -> CGImage? {
        if let kept { return kept }
        kept = paint()
        return kept
    }

    static func ll(_ lon: Double, _ lat: Double) -> CGPoint { WarlordMap.point(lon, lat) }

    // MARK: Geography, in longitude and latitude

    /// The mainland's coast, from the top-left corner of the map round by the north, down the coast to the Gulf of Tonkin.
    static let coast: [(Double, Double)] = [
        (96, 44), (127, 44), (127, 37.2), (126.6, 37.0), (126.3, 37.7), (125.9, 37.8), (125.1, 38.6), (125.3, 39.5), (124.8, 39.6), (124.3, 39.9),
        (123.4, 39.7), (122.6, 39.4), (121.7, 39.0), (121.2, 38.75), (121.5, 39.3), (122.0, 39.9), (122.2, 40.5), (121.4, 40.9), (120.6, 40.5),
        (119.7, 39.95), (119.0, 39.25), (118.2, 39.1), (117.8, 38.9), (117.6, 38.4), (118.1, 38.1), (118.9, 37.5), (119.2, 37.15), (119.8, 37.3),
        (120.7, 37.8), (121.5, 37.5), (122.6, 37.4), (122.2, 36.9), (121.0, 36.5), (120.3, 36.05), (119.6, 35.5), (119.2, 34.7), (120.3, 33.6),
        (120.9, 32.6), (121.9, 31.9), (121.95, 30.9), (121.1, 30.45), (121.8, 29.95), (121.7, 29.2), (121.4, 28.5), (120.7, 27.9), (120.2, 26.8),
        (119.65, 25.95), (119.0, 25.1), (118.1, 24.45), (117.2, 23.65), (116.5, 23.05), (115.4, 22.75), (114.3, 22.35), (113.6, 22.2), (112.8, 21.85),
        (111.8, 21.55), (110.9, 21.35), (110.4, 21.0), (110.15, 20.35), (109.8, 20.7), (109.7, 21.45), (109.0, 21.6), (108.3, 21.6), (107.7, 21.5),
        (107.0, 21.0), (106.5, 20.4), (106.0, 19.9), (105.7, 19.2), (96, 19.2),
    ]
    static let islands: [[(Double, Double)]] = [
        [(108.6, 19.2), (109.4, 18.3), (110.4, 18.6), (111.0, 19.6), (110.6, 20.1), (109.6, 20.05), (108.7, 19.8)],           // 海南
        [(120.1, 23.0), (120.7, 22.0), (121.3, 22.8), (121.7, 24.0), (121.9, 25.1), (121.1, 25.2), (120.3, 24.2)],            // 台湾
        [(129.0, 33.2), (130.4, 32.5), (131.2, 33.6), (130.6, 34.4), (129.6, 34.0)],                                           // 九州 (a corner of it)
    ]
    static let yellowRiver: [(Double, Double)] = [
        (96.5, 34.6), (98.6, 34.9), (100.4, 35.6), (101.8, 36.0), (103.8, 36.15), (104.9, 37.3), (106.2, 38.3), (106.8, 39.4), (107.6, 40.65),
        (109.8, 40.6), (111.1, 40.3), (111.5, 39.3), (110.6, 37.8), (110.45, 36.2), (110.35, 34.62), (111.2, 34.8), (112.5, 34.9), (113.7, 34.92),
        (114.6, 35.3), (115.1, 35.85), (115.9, 36.45), (116.7, 36.95), (117.5, 37.3), (118.5, 37.62),
    ]
    static let yangtze: [(Double, Double)] = [
        (96.5, 33.2), (97.8, 32.8), (98.8, 31.2), (99.1, 29.4), (99.6, 27.6), (100.2, 26.9), (101.1, 26.4), (102.2, 26.3), (102.9, 26.9),
        (103.6, 27.9), (104.6, 28.75), (105.45, 28.9), (106.55, 29.56), (107.4, 29.9), (108.4, 30.8), (109.5, 31.0), (110.3, 30.9), (111.3, 30.7),
        (112.2, 30.3), (112.8, 29.75), (113.15, 29.45), (113.9, 30.2), (114.3, 30.6), (115.0, 30.2), (116.0, 29.8), (117.05, 30.5), (118.2, 31.3),
        (118.78, 32.05), (119.4, 32.2), (120.3, 32.0), (121.2, 31.75), (121.9, 31.5),
    ]
    static let tributaries: [[(Double, Double)]] = [
        [(106.3, 33.2), (107.0, 33.07), (107.8, 32.8), (109.0, 32.7), (110.3, 32.6), (111.5, 32.35), (112.14, 32.08), (112.6, 31.2), (113.3, 30.7), (114.3, 30.6)], // 汉水
        [(104.2, 35.0), (105.72, 34.62), (107.2, 34.4), (108.9, 34.38), (110.35, 34.62)],                                     // 渭水
        [(112.8, 32.9), (114.4, 32.45), (115.6, 32.5), (116.8, 32.62), (117.5, 33.0), (118.6, 33.4), (119.5, 33.75), (120.3, 33.85)], // 淮河
        [(110.9, 25.6), (111.6, 26.4), (112.6, 27.0), (112.94, 28.25), (112.95, 29.0)],                                        // 湘江
        [(114.9, 25.8), (115.0, 27.0), (115.7, 28.2), (115.95, 28.7), (116.2, 29.3)],                                          // 赣江
        [(106.2, 23.2), (107.9, 22.9), (109.5, 23.4), (110.8, 23.5), (112.2, 23.2), (113.3, 22.75)],                           // 珠江
        [(105.6, 33.4), (105.8, 32.4), (106.1, 30.8), (106.55, 29.56)],                                                          // 嘉陵江
        [(103.5, 32.2), (103.7, 30.9), (103.8, 29.7), (104.6, 28.75)],                                                          // 岷江
        [(123.9, 42.7), (123.3, 41.8), (122.6, 41.2), (122.2, 40.7)],                                                          // 辽河
        [(111.4, 29.0), (110.2, 28.4), (109.0, 28.2)],                                                                          // 沅水
        [(113.8, 36.9), (114.9, 37.5), (116.0, 38.4), (117.4, 38.9)],                                                           // 漳水 to the sea
    ]
    static let lakes: [(Double, Double, Double, Double)] = [(112.75, 29.25, 0.75, 0.42), (116.3, 29.1, 0.35, 0.62), (120.2, 31.2, 0.32, 0.28), (117.6, 31.6, 0.22, 0.12), (100.2, 36.9, 0.75, 0.35), (103.0, 24.9, 0.18, 0.28)]
    /// Mountain ranges: a line of peaks, how tall, how thick.
    static let ranges: [(line: [(Double, Double)], height: Double, spread: Double, snow: Bool)] = [
        ([(104.2, 34.1), (106.0, 33.9), (107.5, 33.85), (109.0, 33.9), (110.5, 34.0), (111.8, 33.8)], 1.1, 0.35, false),       // 秦岭
        ([(106.2, 32.3), (107.6, 32.0), (109.0, 31.8), (110.3, 31.6)], 0.9, 0.3, false),                                    // 大巴山
        ([(113.2, 35.2), (113.6, 36.2), (113.8, 37.3), (114.2, 38.4), (114.8, 39.5)], 1.0, 0.25, false),                     // 太行山
        ([(115.3, 40.4), (116.5, 40.6), (117.8, 40.4), (119.0, 40.3)], 0.85, 0.25, false),                                    // 燕山
        ([(111.0, 36.0), (111.3, 37.2), (111.6, 38.4), (112.2, 39.3)], 0.8, 0.22, false),                                     // 吕梁山
        ([(110.0, 25.2), (111.5, 25.1), (113.0, 25.2), (114.5, 25.0), (116.0, 24.8)], 0.85, 0.3, false),                     // 南岭
        ([(116.2, 26.0), (117.0, 27.0), (117.8, 27.8), (118.6, 28.6)], 0.85, 0.3, false),                                    // 武夷山
        ([(109.3, 30.7), (110.0, 31.2), (110.7, 31.6)], 0.8, 0.22, false),                                                   // 巫山
        ([(110.4, 26.3), (110.6, 27.4), (110.9, 28.4)], 0.7, 0.2, false),                                                    // 雪峰山
        ([(114.2, 31.2), (115.2, 31.3), (116.2, 31.2)], 0.65, 0.18, false),                                                  // 大别山
        ([(113.6, 26.3), (114.2, 27.2), (114.4, 28.3)], 0.6, 0.18, false),                                                   // 罗霄山
        ([(97.5, 39.3), (99.0, 38.9), (100.5, 38.3), (102.0, 37.6), (103.2, 37.0)], 1.25, 0.35, true),                     // 祁连山
        ([(98.3, 31.8), (99.0, 30.0), (99.5, 28.3), (100.0, 26.8)], 1.35, 0.45, true),                                     // 横断山
        ([(101.3, 31.5), (102.4, 30.6), (102.9, 29.5), (102.6, 28.3)], 1.05, 0.3, true),                                   // 邛崃山
        ([(109.0, 41.2), (110.5, 41.4), (112.0, 41.3), (113.4, 41.2)], 0.65, 0.2, false),                                   // 阴山
        ([(119.8, 42.6), (120.8, 42.3), (121.6, 42.0)], 0.6, 0.2, false),                                                   // 医巫闾
        ([(123.8, 40.6), (124.5, 41.2), (125.3, 41.8)], 0.6, 0.25, false),                                                  // 长白 foothills
        ([(117.0, 36.25), (117.6, 36.2)], 0.6, 0.12, false),                                                                // 泰山
        ([(104.6, 26.0), (105.6, 26.6), (106.8, 26.9), (108.2, 27.0)], 0.6, 0.35, false),                                   // 云贵
        ([(101.5, 24.5), (102.5, 23.8), (104.0, 23.4)], 0.6, 0.3, false),
        ([(106.2, 35.6), (106.4, 36.5)], 0.6, 0.15, false),                                                                 // 六盘山
        ([(111.6, 33.6), (112.6, 33.5), (113.2, 33.3)], 0.55, 0.18, false),                                                // 伏牛山
    ]
    static let greatWall: [(Double, Double)] = [
        (98.3, 39.8), (100.4, 39.1), (102.2, 38.4), (103.6, 37.6), (104.8, 37.7), (106.2, 38.6), (107.8, 38.1), (109.7, 38.4), (110.9, 39.3),
        (111.8, 39.6), (113.3, 40.2), (114.9, 40.8), (116.1, 40.45), (117.2, 40.75), (118.6, 40.3), (119.8, 40.02),
    ]
    static let provinces: [(String, Double, Double, Double)] = [
        ("司隶", 110.6, 35.2, 1), ("冀州", 115.3, 37.8, 1), ("幽州", 119.0, 41.3, 1), ("并州", 111.4, 38.9, 1), ("青州", 118.9, 36.2, 0.85),
        ("兖州", 116.0, 35.3, 0.85), ("豫州", 115.2, 33.7, 0.85), ("徐州", 118.8, 33.8, 0.85), ("扬州", 118.3, 29.4, 1.1), ("荆州", 112.3, 27.4, 1.1),
        ("益州", 103.2, 28.4, 1.2), ("凉州", 101.0, 36.2, 1.1), ("交州", 109.8, 22.8, 1), ("雍州", 107.2, 36.2, 0.8), ("鲜卑", 110.0, 42.4, 0.9),
        ("乌桓", 119.6, 43.3, 0.8), ("羌", 97.9, 34.0, 0.9), ("南蛮", 101.2, 23.0, 0.9), ("山越", 118.2, 27.0, 0.7), ("高句丽", 125.6, 41.8, 0.7),
    ]
    /// Broad washes of colour for the kind of land: (lon, lat, radius°, colour, strength).
    static let washes: [(Double, Double, Double, RGB, Double)] = [
        (115.5, 36.0, 4.2, (0.86, 0.78, 0.55), 0.55),     // the yellow plain
        (109.5, 36.8, 3.2, (0.84, 0.72, 0.5), 0.55),      // loess
        (104.3, 30.2, 2.3, (0.62, 0.72, 0.46), 0.55),     // 天府之国
        (113.0, 27.5, 5.5, (0.58, 0.7, 0.45), 0.5),       // the green south
        (118.5, 29.0, 3.5, (0.58, 0.7, 0.46), 0.45),
        (111.0, 23.5, 3.5, (0.52, 0.68, 0.42), 0.5),
        (100.0, 31.0, 4.2, (0.66, 0.6, 0.5), 0.55),       // the high plateau
        (98.0, 35.5, 3.6, (0.7, 0.64, 0.52), 0.5),
        (101.0, 40.8, 3.4, (0.9, 0.8, 0.58), 0.7),       // 巴丹吉林
        (104.4, 38.6, 1.8, (0.9, 0.8, 0.58), 0.6),       // 腾格里
        (108.6, 38.8, 1.6, (0.88, 0.8, 0.6), 0.55),      // 毛乌素
        (112.0, 42.6, 4.2, (0.8, 0.78, 0.55), 0.5),      // the steppe
        (122.5, 42.0, 3.0, (0.66, 0.72, 0.5), 0.45),      // 辽东
        (104.5, 24.5, 3.0, (0.6, 0.66, 0.46), 0.45),     // 南中
    ]

    // MARK: Painting

    static func path(_ pts: [(Double, Double)], closed: Bool, scale s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let xy = pts.map { ll($0.0, $0.1) }.map { CGPoint(x: $0.x * s, y: $0.y * s) }
        guard xy.count > 1 else { return p }
        p.move(to: xy[0])
        // A smooth curve through the points (Catmull-Rom as Béziers).
        let n = xy.count
        for i in 0..<(closed ? n : n - 1) {
            let p0 = xy[closed ? (i - 1 + n) % n : max(0, i - 1)], p1 = xy[i], p2 = xy[(i + 1) % n], p3 = xy[closed ? (i + 2) % n : min(n - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { p.closeSubpath() }
        return p
    }

    static func cg(_ c: RGB, _ a: Double = 1) -> CGColor { CGColor(srgbRed: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2), alpha: CGFloat(a)) }

    static func noise(_ i: Int, _ j: Int) -> Double { Double(WarlordWorld.mixHash(i, j) % 10_000) / 10_000 }

    static let paper: RGB = (0.86, 0.8, 0.64)
    static let sea: RGB = (0.47, 0.62, 0.66)

    static func paint() -> CGImage? {
        let W = Int(WarlordMap.width * Double(px)), H = Int(WarlordMap.height * Double(px))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let g = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Map units, y down.
        g.translateBy(x: 0, y: CGFloat(H)); g.scaleBy(x: 1, y: -1)
        let s = px
        let full = CGRect(x: 0, y: 0, width: W, height: H)
        let land = CGMutablePath()
        land.addPath(path(coast, closed: true, scale: s))
        for i in islands { land.addPath(path(i, closed: true, scale: s)) }

        // The sea: deeper away from the coast, with the coast's shallows round the land.
        g.setFillColor(cg(sea)); g.fill(full)
        if let grad = CGGradient(colorsSpace: space, colors: [cg((0.42, 0.57, 0.63)), cg((0.36, 0.5, 0.58))] as CFArray, locations: [0, 1]) {
            g.saveGState(); g.addRect(full); g.clip()
            g.drawLinearGradient(grad, start: CGPoint(x: 0.6 * CGFloat(W), y: 0.3 * CGFloat(H)), end: CGPoint(x: CGFloat(W), y: CGFloat(H)), options: [.drawsAfterEndLocation])
            g.restoreGState()
        }
        for (width, alpha) in [(46.0, 0.10), (30.0, 0.13), (18.0, 0.16), (9.0, 0.2)] {
            g.addPath(land); g.setStrokeColor(cg((0.72, 0.84, 0.84), alpha)); g.setLineWidth(CGFloat(width) * s / 2.4); g.setLineJoin(.round); g.strokePath()
        }
        // Ripples: short curved strokes on the open sea, like an old map's.
        g.setStrokeColor(cg((0.86, 0.93, 0.92), 0.35)); g.setLineWidth(1.3 * s / 2.4); g.setLineCap(.round)
        for i in 0..<260 {
            let x = noise(i, 1) * Double(W), y = noise(i, 2) * Double(H)
            let p = CGPoint(x: x, y: y)
            if land.contains(p) { continue }
            // Keep the ripples off the coast.
            let near = (0..<8).contains { k in let a = Double(k) / 8 * 2 * .pi; return land.contains(CGPoint(x: x + cos(a) * 30 * Double(s), y: y + sin(a) * 30 * Double(s))) }
            if near { continue }
            let w = (8 + noise(i, 3) * 10) * Double(s)
            let wave = CGMutablePath()
            wave.move(to: CGPoint(x: x - w, y: y))
            wave.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - w / 2, y: y - w * 0.45))
            wave.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - w * 0.45))
            g.addPath(wave); g.strokePath()
        }

        // The land: paper, washed with the colour of each kind of country.
        g.saveGState()
        g.addPath(land); g.clip()
        g.setFillColor(cg(paper)); g.fill(full)
        for wsh in washes {
            let c = ll(wsh.0, wsh.1), r = CGFloat(wsh.2) * 1000 / 29 * s
            let cc = CGPoint(x: c.x * s, y: c.y * s)
            if let grad = CGGradient(colorsSpace: space, colors: [cg(wsh.3, wsh.4), cg(wsh.3, wsh.4 * 0.6), cg(wsh.3, 0)] as CFArray, locations: [0, 0.55, 1]) {
                g.drawRadialGradient(grad, startCenter: cc, startRadius: 0, endCenter: cc, endRadius: r, options: [])
            }
        }
        // Paper grain: faint flecks and blotches.
        for i in 0..<5_000 {
            let x = noise(i, 11) * Double(W), y = noise(i, 12) * Double(H), r = (0.6 + noise(i, 13) * 1.8) * Double(s)
            let dark = noise(i, 14) < 0.5
            g.setFillColor(cg(dark ? (0.45, 0.36, 0.22) : (1, 0.98, 0.9), dark ? 0.06 : 0.1))
            g.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        for i in 0..<90 {
            let x = noise(i, 21) * Double(W), y = noise(i, 22) * Double(H), r = (20 + noise(i, 23) * 60) * Double(s)
            g.setFillColor(cg((0.6, 0.5, 0.3), 0.035))
            g.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.7, width: 2 * r, height: 1.4 * r))
        }
        // Dunes in the deserts: little arcs.
        g.setStrokeColor(cg((0.7, 0.56, 0.34), 0.35)); g.setLineWidth(1.1 * s / 2.4)
        for i in 0..<420 {
            let lon = 97 + noise(i, 31) * 13, lat = 37.3 + noise(i, 32) * 5.2
            let inSand = washes.enumerated().contains { k, wsh in [8, 9, 10].contains(k) && hypot(lon - wsh.0, (lat - wsh.1) * 1.2) < wsh.2 * 0.8 }
            guard inSand else { continue }
            let p = ll(lon, lat), w = (4 + noise(i, 33) * 5) * Double(s)
            let arc = CGMutablePath()
            arc.move(to: CGPoint(x: p.x * s - w, y: p.y * s)); arc.addQuadCurve(to: CGPoint(x: p.x * s + w, y: p.y * s), control: CGPoint(x: p.x * s, y: p.y * s - w * 0.7))
            g.addPath(arc); g.strokePath()
        }
        // Woods in the south and the north-east: clumps of little round trees.
        for i in 0..<900 {
            let lon = 103 + noise(i, 41) * 22, lat = 22 + noise(i, 42) * 20
            let south = lat < 31.5 && lon > 106, east = lat > 40.6 && lon > 120
            guard south || east || (lat < 30 && lon > 103.5 && lon < 106 && noise(i, 44) < 0.4) else { continue }
            let p = ll(lon, lat), r = (2.2 + noise(i, 43) * 1.6) * Double(s)
            let q = CGPoint(x: p.x * s, y: p.y * s)
            guard land.contains(q) else { continue }
            g.setFillColor(cg((0.3, 0.44, 0.24), 0.28)); g.fillEllipse(in: CGRect(x: q.x - r, y: q.y - r * 0.6, width: r * 2, height: r * 1.5))
            g.setFillColor(cg((0.42, 0.58, 0.3), 0.45)); g.fillEllipse(in: CGRect(x: q.x - r * 0.8, y: q.y - r * 1.2, width: r * 1.6, height: r * 1.5))
        }
        g.restoreGState()

        // The coast, inked.
        g.addPath(land); g.setStrokeColor(cg((0.3, 0.24, 0.16), 0.75)); g.setLineWidth(1.6 * s / 2.4); g.setLineJoin(.round); g.strokePath()
        g.addPath(land); g.setStrokeColor(cg((0.98, 0.95, 0.84), 0.5)); g.setLineWidth(0.8 * s / 2.4)
        g.saveGState(); g.addPath(land); g.clip()
        g.addPath(land); g.setLineWidth(5 * s / 2.4); g.setStrokeColor(cg((0.98, 0.94, 0.8), 0.28)); g.strokePath()
        g.restoreGState()

        // Lakes.
        for l in lakes {
            let c = ll(l.0, l.1)
            let rx = CGFloat(l.2) * 1000 / 29 * s, ry = CGFloat(l.3) * 933 / 23 * s
            let r = CGRect(x: c.x * s - rx, y: c.y * s - ry, width: 2 * rx, height: 2 * ry)
            g.setFillColor(cg((0.5, 0.66, 0.72))); g.fillEllipse(in: r)
            g.setStrokeColor(cg((0.28, 0.4, 0.46), 0.7)); g.setLineWidth(1.1 * s / 2.4); g.strokeEllipse(in: r)
        }

        // Rivers: an ink bank and the water, wider downstream.
        func river(_ pts: [(Double, Double)], water: RGB, width: CGFloat) {
            let n = pts.count
            for k in 0..<(n - 1) {
                let seg = Array(pts[max(0, k - 1)...min(n - 1, k + 2)])
                let t = CGFloat(k) / CGFloat(max(1, n - 2))
                let wdt = width * (0.45 + 0.55 * t) * s / 2.4
                let sub = CGMutablePath()
                let whole = path(seg, closed: false, scale: s)
                sub.addPath(whole)
                _ = sub
                // Draw only the piece between pts[k] and pts[k+1] of the smoothed curve: approximate with the local curve.
                let a = ll(pts[k].0, pts[k].1), b = ll(pts[k + 1].0, pts[k + 1].1)
                let p0 = ll(pts[max(0, k - 1)].0, pts[max(0, k - 1)].1), p3 = ll(pts[min(n - 1, k + 2)].0, pts[min(n - 1, k + 2)].1)
                let piece = CGMutablePath()
                piece.move(to: CGPoint(x: a.x * s, y: a.y * s))
                piece.addCurve(to: CGPoint(x: b.x * s, y: b.y * s), control1: CGPoint(x: (a.x + (b.x - p0.x) / 6) * s, y: (a.y + (b.y - p0.y) / 6) * s),
                               control2: CGPoint(x: (b.x - (p3.x - a.x) / 6) * s, y: (b.y - (p3.y - a.y) / 6) * s))
                g.addPath(piece); g.setStrokeColor(cg((0.22, 0.26, 0.26), 0.7)); g.setLineWidth(wdt + 2.2 * s / 2.4); g.setLineCap(.round); g.strokePath()
                g.addPath(piece); g.setStrokeColor(cg(water)); g.setLineWidth(wdt); g.strokePath()
            }
        }
        for t in tributaries { river(t, water: (0.46, 0.64, 0.74), width: 3.2) }
        river(yangtze, water: (0.38, 0.6, 0.74), width: 7.5)
        river(yellowRiver, water: (0.82, 0.66, 0.34), width: 6.5)

        // The Great Wall: a crenellated line along the north.
        let wall = path(greatWall, closed: false, scale: s)
        g.addPath(wall); g.setStrokeColor(cg((0.3, 0.22, 0.16), 0.85)); g.setLineWidth(5 * s / 2.4); g.setLineCap(.round); g.setLineJoin(.round); g.strokePath()
        g.addPath(wall); g.setStrokeColor(cg((0.84, 0.76, 0.6), 1)); g.setLineWidth(2.6 * s / 2.4); g.strokePath()
        g.addPath(wall); g.setStrokeColor(cg((0.3, 0.22, 0.16), 0.8)); g.setLineWidth(2.6 * s / 2.4); g.setLineDash(phase: 0, lengths: [1.2 * s, 1.6 * s]); g.strokePath()
        g.setLineDash(phase: 0, lengths: [])
        for (k, pt) in greatWall.enumerated() where k % 2 == 0 {
            let q = ll(pt.0, pt.1)
            let r = CGRect(x: q.x * s - 2.4 * s, y: q.y * s - 2.2 * s, width: 4.8 * s, height: 4.4 * s)
            g.setFillColor(cg((0.8, 0.72, 0.56))); g.fill(r)
            g.setStrokeColor(cg((0.36, 0.28, 0.2), 0.8)); g.setLineWidth(0.9 * s / 2.4); g.stroke(r)
        }

        // Mountains: inked peaks, lit from the upper left, back to front.
        var peaks: [(CGPoint, CGFloat, Bool, Int)] = []
        for (ri, r) in ranges.enumerated() {
            let pts = r.line.map { ll($0.0, $0.1) }
            var length = 0.0
            for k in 1..<pts.count { length += Double(hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y)) }
            let count = Int(length / 9.5 * (0.6 + r.spread))
            for i in 0..<count {
                var t = (Double(i) + noise(ri * 1000 + i, 51)) / Double(count) * length
                var k = 1
                while k < pts.count - 1 {
                    let seg = Double(hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y))
                    if t <= seg { break }
                    t -= seg; k += 1
                }
                let seg = max(0.001, Double(hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y)))
                let f = CGFloat(min(1, t / seg))
                var p = CGPoint(x: pts[k - 1].x + (pts[k].x - pts[k - 1].x) * f, y: pts[k - 1].y + (pts[k].y - pts[k - 1].y) * f)
                let spread = CGFloat(r.spread) * 40
                p.x += CGFloat(noise(ri * 1000 + i, 52) - 0.5) * spread
                p.y += CGFloat(noise(ri * 1000 + i, 53) - 0.5) * spread
                let h = CGFloat(r.height) * CGFloat(10 + noise(ri * 1000 + i, 54) * 9)
                peaks.append((p, h, r.snow && noise(ri * 1000 + i, 55) < 0.8, ri * 1000 + i))
            }
        }
        // The high plateau: scattered peaks all over the far west.
        for i in 0..<120 {
            let lon = 96.6 + noise(i, 61) * 5.6, lat = 26.5 + noise(i, 62) * 10.5
            if lon > 101.5 && lat < 32 { continue }
            let p = ll(lon, lat)
            peaks.append((p, CGFloat(11 + noise(i, 63) * 9), noise(i, 64) < 0.7, 90_000 + i))
        }
        peaks.sort { $0.0.y < $1.0.y }
        for (p, h, snow, seed) in peaks {
            let c = CGPoint(x: p.x * s, y: p.y * s), H = h * s, Wd = H * (1.1 + CGFloat(noise(seed, 71)) * 0.5)
            guard land.contains(c) else { continue }
            let top = CGPoint(x: c.x + (CGFloat(noise(seed, 72)) - 0.5) * Wd * 0.3, y: c.y - H)
            let left = CGPoint(x: c.x - Wd / 2, y: c.y), right = CGPoint(x: c.x + Wd / 2, y: c.y)
            let body = CGMutablePath()
            body.move(to: left); body.addQuadCurve(to: top, control: CGPoint(x: c.x - Wd * 0.2, y: c.y - H * 0.55)); body.addQuadCurve(to: right, control: CGPoint(x: c.x + Wd * 0.22, y: c.y - H * 0.5)); body.closeSubpath()
            // A soft shadow to the lower right.
            g.saveGState(); g.translateBy(x: Wd * 0.18, y: H * 0.08)
            g.addPath(body); g.setFillColor(cg((0.3, 0.24, 0.14), 0.12)); g.fillPath()
            g.restoreGState()
            let rock: RGB = snow ? (0.62, 0.58, 0.54) : (0.6, 0.54, 0.38)
            g.addPath(body); g.setFillColor(cg(Self.lit(rock, 1.18))); g.fillPath()
            let shade = CGMutablePath()
            shade.move(to: top); shade.addQuadCurve(to: right, control: CGPoint(x: c.x + Wd * 0.22, y: c.y - H * 0.5))
            shade.addLine(to: CGPoint(x: c.x + Wd * 0.05, y: c.y)); shade.addQuadCurve(to: top, control: CGPoint(x: top.x + Wd * 0.05, y: c.y - H * 0.45)); shade.closeSubpath()
            g.addPath(shade); g.setFillColor(cg(Self.lit(rock, 0.68))); g.fillPath()
            if snow {
                let cap = CGMutablePath()
                cap.move(to: top)
                cap.addLine(to: CGPoint(x: top.x - Wd * 0.17, y: top.y + H * 0.34))
                cap.addLine(to: CGPoint(x: top.x - Wd * 0.05, y: top.y + H * 0.26))
                cap.addLine(to: CGPoint(x: top.x + Wd * 0.04, y: top.y + H * 0.36))
                cap.addLine(to: CGPoint(x: top.x + Wd * 0.18, y: top.y + H * 0.3)); cap.closeSubpath()
                g.addPath(cap); g.setFillColor(cg((0.97, 0.97, 0.98), 0.95)); g.fillPath()
            }
            // The brush line along the ridge.
            let ridge = CGMutablePath()
            ridge.move(to: left); ridge.addQuadCurve(to: top, control: CGPoint(x: c.x - Wd * 0.2, y: c.y - H * 0.55)); ridge.addQuadCurve(to: right, control: CGPoint(x: c.x + Wd * 0.22, y: c.y - H * 0.5))
            g.addPath(ridge); g.setStrokeColor(cg((0.24, 0.18, 0.12), 0.7)); g.setLineWidth(max(1, 1.05 * s / 2.4)); g.setLineCap(.round); g.strokePath()
            let crease = CGMutablePath()
            crease.move(to: top); crease.addQuadCurve(to: CGPoint(x: c.x + Wd * 0.05, y: c.y - H * 0.05), control: CGPoint(x: top.x + Wd * 0.05, y: c.y - H * 0.45))
            g.addPath(crease); g.setStrokeColor(cg((0.24, 0.18, 0.12), 0.35)); g.setLineWidth(max(0.8, 0.8 * s / 2.4)); g.strokePath()
        }

        // The provinces' names, faint, in brush script.
        g.saveGState()
        g.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (name, lon, lat, size) in provinces {
            let p = ll(lon, lat)
            let foreign = ["鲜卑", "乌桓", "羌", "南蛮", "山越", "高句丽"].contains(name)
            text(g, name, at: CGPoint(x: p.x * s, y: p.y * s), size: CGFloat(size) * (foreign ? 22 : 30) * s, colour: foreign ? cg((0.38, 0.28, 0.18), 0.28) : cg((0.42, 0.24, 0.14), 0.3), spacing: foreign ? 0.3 : 0.6)
        }
        // The seas' names.
        for (name, lon, lat, size) in [("东  海", 123.6, 29.2, 1.0), ("黄  海", 122.6, 35.2, 1.0), ("渤海", 120.0, 38.8, 0.75), ("南  海", 115.2, 20.9, 1.0)] {
            let p = ll(lon, lat)
            text(g, name, at: CGPoint(x: p.x * s, y: p.y * s), size: CGFloat(size) * 24 * s, colour: cg((0.9, 0.96, 0.96), 0.55), spacing: 0.2)
        }
        g.restoreGState()

        // A compass rose in the eastern sea.
        compass(g, at: { let p = ll(124.4, 24.4); return CGPoint(x: p.x * s, y: p.y * s) }(), r: 34 * s)

        // The edges of the paper darken.
        if let grad = CGGradient(colorsSpace: space, colors: [cg((0.2, 0.14, 0.08), 0), cg((0.2, 0.14, 0.08), 0.28)] as CFArray, locations: [0.62, 1]) {
            let mid = CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2)
            g.drawRadialGradient(grad, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: hypot(CGFloat(W), CGFloat(H)) / 2, options: [.drawsAfterEndLocation])
        }
        return g.makeImage()
    }

    static func lit(_ c: RGB, _ k: Double) -> RGB {
        func f(_ v: Double) -> Double { k >= 1 ? v + (1 - v) * (k - 1) : v * k }
        return (f(c.0), f(c.1), f(c.2))
    }

    static func font(_ size: CGFloat) -> CTFont {
        for name in ["STKaitiSC-Black", "STKaitiSC-Bold", "STXingkaiSC-Bold", "STSongti-SC-Black", "STSongti-SC-Bold"] {
            let f = CTFontCreateWithName(name as CFString, size, nil)
            if (CTFontCopyPostScriptName(f) as String) == name { return f }
        }
        return CTFontCreateWithName("PingFangSC-Semibold" as CFString, size, nil)
    }

    static func text(_ g: CGContext, _ s: String, at p: CGPoint, size: CGFloat, colour: CGColor, spacing: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font(size), .foregroundColor: colour, .kern: size * spacing]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        g.textPosition = CGPoint(x: p.x - b.width / 2 - b.minX, y: p.y + b.height / 2 + b.minY)
        CTLineDraw(line, g)
    }

    static func compass(_ g: CGContext, at c: CGPoint, r: CGFloat) {
        g.saveGState()
        g.setStrokeColor(cg((0.3, 0.22, 0.14), 0.6)); g.setLineWidth(r * 0.03)
        g.strokeEllipse(in: CGRect(x: c.x - r * 0.72, y: c.y - r * 0.72, width: r * 1.44, height: r * 1.44))
        g.strokeEllipse(in: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24))
        for k in 0..<8 {
            let a = CGFloat(k) * .pi / 4 - .pi / 2
            let long = k % 2 == 0 ? r : r * 0.55
            let tip = CGPoint(x: c.x + cos(a) * long, y: c.y + sin(a) * long)
            let side = CGFloat.pi / 2
            let l = CGPoint(x: c.x + cos(a - side) * r * 0.12, y: c.y + sin(a - side) * r * 0.12)
            let rr = CGPoint(x: c.x + cos(a + side) * r * 0.12, y: c.y + sin(a + side) * r * 0.12)
            let half1 = CGMutablePath(); half1.move(to: c); half1.addLine(to: l); half1.addLine(to: tip); half1.closeSubpath()
            let half2 = CGMutablePath(); half2.move(to: c); half2.addLine(to: rr); half2.addLine(to: tip); half2.closeSubpath()
            g.addPath(half1); g.setFillColor(k == 0 ? cg((0.72, 0.18, 0.14), 0.85) : cg((0.3, 0.22, 0.14), 0.7)); g.fillPath()
            g.addPath(half2); g.setFillColor(cg((0.95, 0.9, 0.78), 0.85)); g.fillPath()
        }
        g.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        text(g, "北", at: CGPoint(x: c.x, y: c.y - r * 1.25), size: r * 0.42, colour: cg((0.4, 0.14, 0.1), 0.85), spacing: 0)
        g.restoreGState()
    }

    // MARK: The land and who holds it, as one picture

    nonisolated(unsafe) static var together: (key: [Int], image: CGImage)?
    /// The painted land with the owners' tint laid over it: one image to place a frame, repainted when a city changes hands.
    static func map(_ owners: [Int]) -> CGImage? {
        if let together, together.key == owners { return together.image }
        guard let land = image(), let tint = territory(owners), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let g = CGContext(data: nil, width: land.width, height: land.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: land.width, height: land.height)
        g.draw(land, in: r)
        g.interpolationQuality = .high
        g.draw(tint, in: r)
        guard let made = g.makeImage() else { return nil }
        together = (owners, made)
        return made
    }

    // MARK: Who holds what

    /// Smooth value noise in 0…1.
    static func smooth(_ x: Double, _ y: Double, _ seed: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        func h(_ a: Int, _ b: Int) -> Double { noise(a &* 7919 &+ seed, b &* 104_729 &+ seed * 31) }
        let a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1)
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }

    /// For each cell of a grid over the map (a map unit each), the city whose land it is (−1 for the sea), and how far it is from the city.
    static let gridW = Int(WarlordMap.width), gridH = Int(WarlordMap.height)
    nonisolated(unsafe) static var cellsKept: (city: [Int8], far: [Float])?
    static func cells() -> (city: [Int8], far: [Float]) {
        if let cellsKept { return cellsKept }
        let W = gridW, H = gridH
        var mask = [UInt8](repeating: 0, count: W * H)
        let space = CGColorSpaceCreateDeviceGray()
        mask.withUnsafeMutableBytes { buf in
            guard let g = CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            g.translateBy(x: 0, y: CGFloat(H)); g.scaleBy(x: 1, y: -1)
            g.addPath(path(coast, closed: true, scale: 1)); g.setFillColor(gray: 1, alpha: 1); g.fillPath()
        }
        let centres = warlordSites.indices.map { (Double(WarlordMap.at($0).x), Double(WarlordMap.at($0).y)) }
        var city = [Int8](repeating: -1, count: W * H), far = [Float](repeating: 0, count: W * H)
        for j in 0..<H {
            for i in 0..<W where mask[j * W + i] > 127 {
                // Warped a little, so borders wander like real ones.
                let x = Double(i) + (smooth(Double(i) / 46, Double(j) / 46, 3) - 0.5) * 34 + (smooth(Double(i) / 13, Double(j) / 13, 5) - 0.5) * 8
                let y = Double(j) + (smooth(Double(i) / 46, Double(j) / 46, 9) - 0.5) * 34 + (smooth(Double(i) / 13, Double(j) / 13, 11) - 0.5) * 8
                var best = -1, bd = Double.infinity
                for (c, p) in centres.enumerated() {
                    let d = (p.0 - x) * (p.0 - x) + (p.1 - y) * (p.1 - y)
                    if d < bd { bd = d; best = c }
                }
                city[j * W + i] = Int8(best); far[j * W + i] = Float(bd.squareRoot())
            }
        }
        cellsKept = (city, far)
        return (city, far)
    }

    /// The owners' colours over the land: a wash that deepens toward each border and a bold line along it.
    static func territory(_ owners: [Int]) -> CGImage? {
        if let tinted, tinted.key == owners { return tinted.image }
        let W = gridW, H = gridH
        let (cell, far) = cells()
        func owner(_ k: Int) -> Int { let c = Int(cell[k]); return c < 0 ? -2 : owners[c] }
        // Distance (in cells) to the nearest border between different owners, up to 9.
        var dist = [UInt8](repeating: 9, count: W * H)
        var county = [Bool](repeating: false, count: W * H)
        for j in 0..<H {
            for i in 0..<W {
                let k = j * W + i
                let c = Int(cell[k])
                guard c >= 0 else { continue }
                let o = owners[c]
                if i + 1 < W { let n = Int(cell[k + 1]); if n >= 0, owners[n] != o { dist[k] = 0; dist[k + 1] = 0 } else if n >= 0, n != c { county[k] = true } }
                if j + 1 < H { let n = Int(cell[k + W]); if n >= 0, owners[n] != o { dist[k] = 0; dist[k + W] = 0 } else if n >= 0, n != c { county[k] = true } }
            }
        }
        for j in 0..<H { for i in 0..<W { let k = j * W + i; if i > 0 { dist[k] = min(dist[k], dist[k - 1] &+ 1) }; if j > 0 { dist[k] = min(dist[k], dist[k - W] &+ 1) } } }
        for j in stride(from: H - 1, through: 0, by: -1) { for i in stride(from: W - 1, through: 0, by: -1) { let k = j * W + i; if i < W - 1 { dist[k] = min(dist[k], dist[k + 1] &+ 1) }; if j < H - 1 { dist[k] = min(dist[k], dist[k + W] &+ 1) } } }
        var px = [UInt8](repeating: 0, count: W * H * 4)
        for k in 0..<(W * H) {
            let o = owner(k)
            guard o > -2 else { continue }
            let col: RGB = o >= 0 ? warlordBanners[o].colour : warlordNeutralColour
            let d = Double(dist[k])
            var a: Double, rgb = col
            if o >= 0 {
                if d < 1 { a = 0.95; rgb = lit(col, 0.62) }
                else if d < 2 { a = 0.7; rgb = lit(col, 0.85) }
                else { a = 0.2 + 0.3 * max(0, 1 - (d - 2) / 7) }
                if county[k], d >= 2 { a = max(a, 0.36); rgb = lit(col, 0.75) }
            } else {
                a = d < 1 ? 0.35 : 0.0
                rgb = (0.4, 0.34, 0.26)
            }
            // Far from any city the tint fades out into the wilds.
            let f = Double(far[k])
            if f > 70 { a *= max(0, 1 - (f - 70) / 45) }
            let i = k * 4
            px[i] = UInt8(min(255, rgb.0 * a * 255)); px[i + 1] = UInt8(min(255, rgb.1 * a * 255)); px[i + 2] = UInt8(min(255, rgb.2 * a * 255)); px[i + 3] = UInt8(min(255, a * 255))
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: Data(px) as CFData),
              let image = CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        tinted = (owners, image)
        return image
    }
}
