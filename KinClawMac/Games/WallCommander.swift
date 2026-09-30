import Foundation

/// Jev — or a chat model — as the defender of the pass: every few seconds one multiple-choice question, "what now?",
/// among options the program has found and measured: the best spot it found for each kind of tower, a line of
/// barricades that lengthens the enemies' walk the most, the upgrade that adds the most, calling the next wave early,
/// or keeping the gold. Each option says first what it does, then the numbers; keeping the gold is said as what it
/// is, with nothing good said of it. The program carries out whatever is chosen.
enum WallOrder: Equatable {
    case build(WallKind, WallTile)
    case line([WallTile])
    case upgrade(Int)
    case call
    case save
}

struct WallOption {
    var order: WallOrder
    /// Short, in Chinese, for the page.
    var title: String
    var words: String
    /// The script's own yardstick, for tests and for a tie: not shown to the chooser.
    var merit: Double
}

enum WallCommander {
    static let rules = "Tower defence at the Great Wall, a war without end. Raiders come down out of the northern grassland in waves through three gaps in the hills and make for the pass (关口) in the Wall on the south edge; every one that gets through costs lives (a siege cart 3, a guard rider 2, the Chanyu 10), and at 0 of 20 lives the pass is lost. They walk the shortest way over a field of 30 by 18 tiles, round rocks, across the river only at its fords, and round whatever is built — so towers are both guns and the walls of a maze, and nothing may shut every way. Towers: the arrow tower (箭楼, cheap, quick, one target at a time, its arrows do only 30% to shield men and 50% to siege carts), the ballista (弩车, long reach, a bolt goes through several enemies in a line), the trebuchet (投石机, slow, a stone that splashes a crowd, cannot hit within 1.6 tiles), the fire-oil thrower (火油, sets the ground burning under a crowd, 150% against wooden siege carts), the beacon tower (烽火台, no attack, raises nearby towers' damage and reach), and the spiked barricade (拒马, very cheap, shuts a tile to lengthen the way, spikes those beside it, but foot soldiers hack at it and siege carts smash it). Every tower can be raised twice. Enemies: cavalry (fast, light), foot soldiers, shield men (armoured against arrows), siege carts (slow, huge health, smash towers they pass), shamans (heal those near them); every tenth wave the Chanyu himself with his guard riders. Each wave has more enemies, tougher and a little faster. Kills and each wave pay gold; calling the next wave before its time pays extra."
    static let question = "What should the defenders of the pass do now?"
    static let howToJudge = "Choose what will let the fewest enemies through the pass over the coming waves. First: damage where it is needed now — enemies near the pass, or lives being lost. Then damage suited to the enemies coming next: arrows against shield men are nearly wasted, splash and fire are strong against crowds, fire and bolts against siege carts. Then time under fire: a longer walk inside the towers' reach means more damage to every enemy. Keeping gold does nothing by itself: it is right only when nothing affordable adds damage or path. Calling a wave early is right only when the field is quiet and the defence has room to spare."

    // MARK: The frontier, in words

    static func count(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) \(n == 1 ? one : (many ?? one + "s"))" }
    static func tiles(_ x: Double) -> String { "\(Int(x.rounded())) tile\(Int(x.rounded()) == 1 ? "" : "s")" }

    /// Where a tile is, said so a reader can picture it.
    static func place(_ f: WallField, _ t: WallTile) -> String {
        var s = "column \(t.x + 1), row \(t.y + 1)"
        let d = f.dist[WallField.index(t)]
        if let ford = f.fords.first(where: { abs($0 - t.x) <= 2 }), abs(t.y - f.riverBottom) <= 3, t.y <= f.riverBottom + 2 { s += ", by the ford at column \(ford + 1)" }
        else if t.y >= WallField.wallRow - 3, abs(t.x - 14) <= 4 { s += ", close before the pass" }
        else if t.y <= 3 { s += ", near the gaps in the hills" }
        if d > 0 { s += " (\(tiles(Double(d) / 10)) from the pass)" }
        return s
    }

    static func situation(_ f: WallField, best: Int) -> String {
        var parts: [String] = []
        parts.append("wave \(f.wave) so far (best ever \(max(best, f.wave)))")
        parts.append("\(f.lives) of \(WallField.startLives) lives left, \(f.gold) gold")
        if f.enemies.isEmpty { parts.append("the field is clear") }
        else {
            let nearest = f.enemies.map { f.remaining($0) }.min() ?? 0
            var kinds: [String] = []
            for foe in WallFoe.allCases {
                let n = f.enemies.filter { $0.foe == foe }.count
                if n > 0 { kinds.append(foe == .chanyu ? "the Chanyu" : n == 1 ? WallFoe.one[foe.rawValue] : "\(n) \(foe.english)") }
            }
            parts.append("\(count(f.enemies.count, "enemy", "enemies")) on the field (\(kinds.joined(separator: ", "))), the nearest \(tiles(nearest)) from the pass")
        }
        let w = f.coming
        parts.append((f.spawned ? "the next wave (\(w.number)) comes in \(Int(max(0, f.clock).rounded())) s" : "wave \(f.wave) is still coming out of the hills; then wave \(w.number)") + ": \(w.described) — \(w.english)")
        parts.append(String(format: "the enemies' walk from the gaps to the pass averages %.0f tiles", f.pathLength))
        var built: [String] = []
        for k in WallKind.allCases {
            let ts = f.towers.filter { $0.kind == k }
            guard !ts.isEmpty else { continue }
            let raised = ts.filter { $0.level > 0 }.count
            built.append("\(ts.count) \(k.english)\(ts.count == 1 ? "" : "s")" + (raised > 0 ? " (\(raised) raised)" : ""))
        }
        parts.append(built.isEmpty ? "nothing is built yet" : "built: " + built.joined(separator: ", "))
        let hurt = f.towers.filter { $0.hp < $0.stats.hp * 0.6 }
        if !hurt.isEmpty { parts.append("\(count(hurt.count, "tower")) badly damaged") }
        return parts.joined(separator: "; ")
    }

    /// What a kind of tower does against the enemies coming next, when it matters.
    static func against(_ kind: WallKind, _ w: WallWave) -> String? {
        guard kind.shoots || kind == .barricade else { return nil }
        let d = kind.damageKind
        var worst: (WallFoe, Double)?, bestOne: (WallFoe, Double)?
        for foe in WallFoe.allCases where w.count(foe) > 0 {
            let m = foe.takes(d)
            if m < 0.95, worst == nil || m < worst!.1 { worst = (foe, m) }
            if m > 1.05, bestOne == nil || m > bestOne!.1 { bestOne = (foe, m) }
        }
        var s: [String] = []
        if let (foe, m) = worst { s.append("its \(damageNames[d.rawValue]) do only \(Int(m * 100))% to the \(foe.english) coming next") }
        if let (foe, m) = bestOne { s.append("its \(damageNames[d.rawValue]) do \(Int(m * 100))% to the \(foe.english) coming next") }
        return s.isEmpty ? nil : s.joined(separator: " and ")
    }
    static let damageNames = ["arrows", "bolts", "stones", "flames", "spikes"]

    static func kindWords(_ k: WallKind) -> String { "a \(k.name) (\(k.english))" }

    // MARK: The options

    static func options(_ f: WallField, best: Int = 0) -> [WallOption] {
        let judge = WallJudge(f)
        let moves = judge.moves()
        let w = f.coming
        var out: [WallOption] = []
        var used = Set<WallTile>()

        // Builds: the most gain for each shooting kind, and a beacon if it lifts two or more.
        let builds = moves.filter { if case .build = $0.act { return $0.cost <= f.gold && $0.gain > 0.5 }; return false }
        let topGain = builds.filter { if case .build(let k, _) = $0.act { return k.shoots }; return false }.map { $0.gain }.max() ?? 0
        var perKind: [(WallMove, WallKind, WallTile)] = []
        for kind in [WallKind.arrow, .ballista, .trebuchet, .fire, .beacon] {
            guard let m = builds.filter({ if case .build(let k, _) = $0.act { return k == kind }; return false }).max(by: { $0.gain < $1.gain }),
                  case .build(_, let t) = m.act else { continue }
            if kind == .beacon, m.lifts < 2 { continue }
            perKind.append((m, kind, t))
        }
        perKind.sort { $0.0.gain > $1.0.gain }
        for (m, kind, t) in perKind.prefix(4) where !used.contains(t) || kind == .beacon {
            used.insert(t)
            out.append(WallOption(order: .build(kind, t), title: "\(kind.name) · \(t.x + 1),\(t.y + 1)", words: buildWords(f, m, kind, t, top: m.gain >= topGain - 0.01 && kind.shoots, w), merit: m.value))
        }

        // A line of barricades: the one that lengthens the walk the most for the gold.
        if let line = bestLine(f), line.cost <= f.gold {
            let from = line.tiles.first!, to = line.tiles.last!
            let across = from.y == to.y ? "across row \(from.y + 1) from column \(min(from.x, to.x) + 1) to \(max(from.x, to.x) + 1)" : "down column \(from.x + 1) from row \(min(from.y, to.y) + 1) to \(max(from.y, to.y) + 1)"
            let words = String(format: "lengthens the enemies' walk from %.0f to %.0f tiles: a line of %d 拒马 (spiked barricades) %@; ", f.pathLength, line.after, line.tiles.count, across)
                + "passing foot soldiers hack at barricades and siege carts smash them; costs \(line.cost), leaving \(f.gold - line.cost) gold"
            out.append(WallOption(order: .line(line.tiles), title: "拒马×\(line.tiles.count) · 第\(from.y + 1)行", words: words, merit: (line.after - f.pathLength) / Double(line.cost)))
        }

        // The upgrade that adds the most.
        let ups = moves.filter { if case .upgrade = $0.act { return $0.cost <= f.gold && $0.gain > 0.5 }; return false }
        if let m = ups.max(by: { $0.gain < $1.gain }), case .upgrade(let id) = m.act, let t = f.tower(id) {
            out.append(WallOption(order: .upgrade(id), title: "升级\(t.kind.name) · \(t.x + 1),\(t.y + 1)", words: upgradeWords(f, t, m, w), merit: m.value))
        }

        // Calling the next wave early.
        if f.spawned, f.wave >= 1, f.clock > 3 {
            let bonus = f.earlyBonus
            let words = "calls wave \(w.number) now, \(Int(f.clock.rounded())) s early, for \(bonus) extra gold on top of the wave's \(WallField.waveBonus(w.number)): \(w.described) come"
                + (f.enemies.isEmpty ? " onto a clear field" : " while \(count(f.enemies.count, "enemy", "enemies")) are still on the field, the nearest \(tiles(f.enemies.map { f.remaining($0) }.min() ?? 0)) from the pass")
            out.append(WallOption(order: .call, title: "下一波 +\(bonus)", words: words, merit: 0))
        }

        // Keeping the gold: said as what it is.
        var keep = "keep the gold, building nothing: \(f.gold) gold stays unspent"
        if let cheapest = WallKind.allCases.filter({ $0.shoots }).map({ $0.cost }).min(), f.gold < cheapest { keep += " (the cheapest tower, an arrow tower, costs \(cheapest): \(cheapest - f.gold) more needed)" }
        keep += "; " + (f.spawned ? "wave \(w.number) comes in \(Int(max(0, f.clock).rounded())) s" : "wave \(w.number) comes after this one") + ": \(w.described)"
        if !f.enemies.isEmpty { keep += "; \(count(f.enemies.count, "enemy", "enemies")) on the field walk on as they are" }
        out.append(WallOption(order: .save, title: "攒金", words: keep, merit: 0))
        return out
    }

    static func buildWords(_ f: WallField, _ m: WallMove, _ kind: WallKind, _ t: WallTile, top: Bool, _ w: WallWave) -> String {
        let s = kind.stats(0)
        var verdict: String
        var parts: [String] = []
        if kind == .beacon {
            verdict = "raises \(count(m.lifts, "tower")) nearby by \(Int(s.boost * 100))% damage and \(Int(s.reach * 100))% reach"
        } else if m.after.rounded() > m.before.rounded() {
            verdict = String(format: "lengthens the walk from %.0f to %.0f tiles and has %@ of it in reach", m.before, m.after, tiles(m.cover))
        } else if m.cover < 0.5 {
            verdict = "has none of the enemies' way in reach"
        } else {
            verdict = (top ? "adds the most damage of any spot found: " : "adds damage: ") + "the way passes within its reach for \(tiles(m.cover))"
        }
        if m.after.rounded() < m.before.rounded() { parts.append(String(format: "shortens the walk from %.0f to %.0f tiles", m.before, m.after)) }
        parts.append("\(kindWords(kind)) at \(place(f, t))")
        switch kind {
        case .arrow: parts.append(String(format: "%.0f damage a shot, %.1f shots a second, reach %.1f tiles", s.damage, s.rate, s.range))
        case .ballista: parts.append(String(format: "%.0f damage a bolt through up to %d enemies, a bolt every %.1f s, reach %.1f tiles", s.damage, s.pierce, 1 / s.rate, s.range))
        case .trebuchet: parts.append(String(format: "%.0f damage splashing %.1f tiles, a stone every %.1f s, reach %.1f tiles but nothing nearer than %.1f", s.damage, s.splash, 1 / s.rate, s.range, s.minRange))
        case .fire: parts.append(String(format: "sets %.1f tiles burning for %.0f s at %.0f damage a second, a pot every %.1f s, reach %.1f tiles", s.splash, s.burn, s.damage, 1 / s.rate, s.range))
        case .beacon: parts.append("no attack of its own")
        case .barricade: break
        }
        if let a = against(kind, w) { parts.append(a) }
        parts.append("costs \(kind.cost), leaving \(f.gold - kind.cost) gold")
        return verdict + ": " + parts.joined(separator: "; ")
    }

    static func upgradeWords(_ f: WallField, _ t: WallTower, _ m: WallMove, _ w: WallWave) -> String {
        let a = t.stats, b = t.kind.stats(t.level + 1)
        var change: String
        switch t.kind {
        case .beacon: change = "its lift \(Int(a.boost * 100))% → \(Int(b.boost * 100))% damage, reaching \(String(format: "%.1f", b.range)) tiles, over \(count(m.lifts, "tower"))"
        case .barricade: change = "its strength \(Int(a.hp)) → \(Int(b.hp)), spikes \(Int(a.damage)) → \(Int(b.damage)) a second"
        case .fire: change = "burning \(Int(a.damage)) → \(Int(b.damage)) damage a second over \(String(format: "%.1f → %.1f", a.splash, b.splash)) tiles"
        case .trebuchet: change = "damage \(Int(a.damage)) → \(Int(b.damage)), splash \(String(format: "%.1f → %.1f", a.splash, b.splash)) tiles"
        case .ballista: change = "damage \(Int(a.damage)) → \(Int(b.damage)), through up to \(b.pierce) enemies"
        case .arrow: change = "damage \(Int(a.damage)) → \(Int(b.damage)), \(String(format: "%.1f → %.1f", a.rate, b.rate)) shots a second"
        }
        var s = "raises the \(t.kind.name) (\(t.kind.english)) at \(place(f, t.tile)) from level \(t.level + 1) to \(t.level + 2): \(change)"
        if t.kind.shoots { s += String(format: ", reach %.1f → %.1f tiles, with %@ of the way in reach", a.range, b.range, tiles(m.cover)) }
        if t.kind.shoots, t.kills > 0 { s += "; it has killed \(t.kills) so far" }
        if let x = against(t.kind, w) { s += "; " + x }
        s += "; costs \(m.cost), leaving \(f.gold - m.cost) gold"
        return s
    }

    /// Straight lines of 3 to 7 barricades through the way, across or down: the one lengthening the walk most a gold.
    static func bestLine(_ f: WallField) -> (tiles: [WallTile], after: Double, cost: Int)? {
        let before = f.pathLength
        var best: (tiles: [WallTile], after: Double, cost: Int, score: Double)?
        var seen = Set<[WallTile]>()
        let cost = WallKind.barricade.cost
        for r in f.routes {
            for (k, t) in r.enumerated() where k % 2 == 0 && t.y >= 2 && t.y < WallField.wallRow {
                for n in [3, 5, 7] where n * cost <= f.gold {
                    for (dx, dy) in [(1, 0), (0, 1)] {
                        for shift in [-(n / 2), -(n - 1), 0] {
                            var line: [WallTile] = []
                            for j in 0..<n {
                                let c = WallTile(x: t.x + dx * (shift + j), y: t.y + dy * (shift + j))
                                if f.buildable(c) { line.append(c) }
                            }
                            guard line.count >= 2, !seen.contains(line) else { continue }
                            seen.insert(line)
                            if f.enemies.contains(where: { e in line.contains { abs(e.x - Double($0.x) - 0.5) < 0.75 && abs(e.y - Double($0.y) - 0.5) < 0.75 } }) { continue }
                            guard let routes = f.routes(blocking: line) else { continue }
                            // Enemies on the field must keep a way too.
                            var shut = Array(repeating: false, count: WallField.width * WallField.height)
                            for c in line { shut[WallField.index(c)] = true }
                            if f.enemies.contains(where: { e in f.route(from: e.tile.y < 0 ? (e.route.first ?? e.tile) : e.tile, shut: shut).isEmpty && f.open(e.tile) }) { continue }
                            let after = routes.map { WallField.length($0) }.reduce(0, +) / Double(routes.count)
                            let score = (after - before) / Double(line.count * cost)
                            if after - before >= 2, best == nil || score > best!.score { best = (line, after, line.count * cost, score) }
                        }
                    }
                }
            }
        }
        return best.map { ($0.tiles, $0.after, $0.cost) }
    }

    /// Carry out an order. Says what happened, in Chinese, or why it could not be done.
    @discardableResult
    static func execute(_ order: WallOrder, _ f: inout WallField) -> String {
        switch order {
        case .build(let kind, let t):
            if f.build(kind, at: t) != nil { return "造\(kind.name)（\(t.x + 1),\(t.y + 1)）" }
            return "\(kind.name)没造成"
        case .line(let tiles):
            var n = 0
            for t in tiles where f.build(.barricade, at: t) != nil { n += 1 }
            return "摆了 \(n) 个拒马"
        case .upgrade(let id):
            guard let t = f.tower(id) else { return "那座塔没了" }
            return f.upgrade(id) ? "\(t.kind.name)升到 \(t.level + 2) 级" : "升级没成"
        case .call:
            guard f.spawned else { return "这一波还没出完" }
            let bonus = f.earlyBonus
            f.call()
            return "提前叫第 \(f.wave) 波，多得 \(bonus) 金"
        case .save:
            return "攒着金子"
        }
    }
}
