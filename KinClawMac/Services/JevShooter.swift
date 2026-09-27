import SwiftUI

/// 飞机大战 — a shooter seen from above, one tick a question.
///
/// The plane flies along the bottom of the sky and may move a column a tick
/// and fire straight up; the gun fires every other tick at most, so a shot
/// that hits nothing costs something. Every enemy flies a fixed pattern —
/// fighters straight down, swoopers on the diagonal off the walls, bombers
/// slowly, dropping bombs on a beat — so where everything will be is known,
/// and the program says it: whether the plane is hit this tick, whether a hit
/// can still be dodged, how long it is safe where it is, what a shot fired now
/// will hit and when, and what the next one would. What is worth a life and
/// what is worth a shot is the player's call. The evaluator that plays looks
/// four ticks ahead over every move and every shot.
@MainActor
final class JevShooter: JevGame {
    let id = "shooter", title = "飞机大战", symbol = "airplane"
    let rules = "A shooter seen from above. The player's plane flies along the bottom row of a sky 11 columns wide; each tick it may move one column left or right, and fire straight up. A shot flies 2 rows a tick, and the gun fires at most every other tick. Enemies come down from the top: fighters fly straight down a row a tick (10 points), swoopers fly down diagonally and bounce off the sides (20 points), bombers come down a row every other tick and drop bombs (30 points). A bomb falls a row a tick. Anything that touches the plane costs one of its three lives; with none left the game is over. The score is the points for enemies shot down."
    let question = "What should the plane do this tick, to score as many points as possible without being shot down?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: never choose an option in which the plane is hit this tick, nor one after which a hit can no longer be dodged. Second: prefer a place where nothing will hit the plane soon if it stays. Third: a shot that hits is worth its points — a bomber 30, a swooper 20, a fighter 10 — and a shot that will hit nothing is wasted, because the gun then needs a tick to reload. Fourth: prefer a column from which the next shot would hit something."

    nonisolated static let width = 11, height = 16, bottom = 15, lives = 3
    let clock: Double? = 0.16
    let controls = "←→ 移动 · 空格 开火（按住连发）"

    fileprivate struct Foe { var kind: Int, x: Int, y: Int, dx: Int, age = 0, serial = 0 }
    fileprivate struct Shot { var x: Int, y: Int, serial: Int }

    /// The sky as it stands. Nothing in it moves at random: only what comes
    /// in over the top is new, and that is the game's business, not this.
    fileprivate struct Sky {
        static let points = [10, 20, 30], names = ["fighter", "swooper", "bomber"]
        var x = 5, lives = JevShooter.lives, gun = 0, score = 0, downed = 0, time = 0, fired = 0
        var shots: [Shot] = [], foes: [Foe] = [], bombs: [(x: Int, y: Int)] = []
        /// For drawing: what was shot down this tick, and where the plane was hit.
        var booms: [(x: Int, y: Int)] = []
        var hurt = false

        struct Tick { var hits: [String] = []; var gained = 0; var downed: [(shot: Int, kind: Int)] = [] }

        var moves: [(move: Int, fire: Bool)] {
            var out: [(move: Int, fire: Bool)] = []
            for move in [0, -1, 1] where (0..<JevShooter.width).contains(x + move) {
                for fire in (gun == 0 ? [true, false] : [false]) { out.append((move, fire)) }
            }
            return out
        }

        mutating func step(move: Int, fire: Bool) -> Tick {
            var tick = Tick()
            booms = []; hurt = false
            x = min(max(x + move, 0), JevShooter.width - 1)
            if fire, gun == 0 { fired += 1; shots.append(Shot(x: x, y: JevShooter.bottom, serial: fired)); gun = 2 }
            collide(&tick)                                            // flew into something
            for _ in 0..<2 {                                          // shots climb, a row at a time
                for index in shots.indices { shots[index].y -= 1 }
                strike(&tick)
            }
            shots.removeAll { $0.y < 0 }
            for index in foes.indices {
                var foe = foes[index]
                switch foe.kind {
                case 0: foe.y += 1
                case 1:
                    if !(0..<JevShooter.width).contains(foe.x + foe.dx) { foe.dx = -foe.dx }
                    foe.x += foe.dx; foe.y += 1
                default:
                    if foe.age % 2 == 1 { foe.y += 1 }
                    if foe.age % 4 == 3 { bombs.append((foe.x, foe.y + 1)) }
                }
                foe.age += 1
                foes[index] = foe
            }
            strike(&tick)
            for index in bombs.indices { bombs[index].y += 1 }
            collide(&tick)
            foes.removeAll { $0.y > JevShooter.bottom }
            bombs.removeAll { $0.y > JevShooter.bottom }
            if gun > 0 { gun -= 1 }
            time += 1
            return tick
        }

        /// Shots against enemies in the same square.
        private mutating func strike(_ tick: inout Tick) {
            for shot in shots {
                guard let index = foes.firstIndex(where: { $0.x == shot.x && $0.y == shot.y }) else { continue }
                let foe = foes.remove(at: index)
                shots.removeAll { $0.serial == shot.serial }
                score += Self.points[foe.kind]; downed += 1
                tick.gained += Self.points[foe.kind]
                tick.downed.append((shot.serial, foe.kind))
                booms.append((foe.x, foe.y))
            }
        }

        /// Anything in the plane's square costs a life.
        private mutating func collide(_ tick: inout Tick) {
            while let index = foes.firstIndex(where: { $0.x == x && $0.y == JevShooter.bottom }) {
                tick.hits.append("the " + Self.names[foes[index].kind]); foes.remove(at: index); lives -= 1; hurt = true
            }
            while let index = bombs.firstIndex(where: { $0.x == x && $0.y == JevShooter.bottom }) {
                tick.hits.append("a bomb"); bombs.remove(at: index); lives -= 1; hurt = true
            }
        }

        /// Staying put and holding fire, the ticks until something hits the plane.
        func hitIn(_ horizon: Int) -> Int? {
            var sky = self
            for k in 1...horizon where !sky.step(move: 0, fire: false).hits.isEmpty { return k }
            return nil
        }

        /// Can the plane get through `ticks` more untouched, moving and shooting as well as it can?
        func dodges(_ ticks: Int) -> Bool {
            guard ticks > 0 else { return true }
            for move in moves {
                var next = self
                if next.step(move: move.move, fire: move.fire).hits.isEmpty, next.dodges(ticks - 1) { return true }
            }
            return false
        }

        /// What a shot already flying will hit, and in how many ticks, if the plane stays and holds fire.
        func target(of serial: Int, within horizon: Int = 9) -> (kind: Int, ticks: Int)? {
            var sky = self
            for k in 0..<max(horizon, 0) {
                guard sky.shots.contains(where: { $0.serial == serial }) else { return nil }
                if let down = sky.step(move: 0, fire: false).downed.first(where: { $0.shot == serial }) { return (down.kind, k + 1) }
            }
            return nil
        }

        /// What the next shot from here would hit: the plane stays put and fires as soon as it can.
        func nextShot(within horizon: Int = 8) -> (kind: Int, ticks: Int)? {
            var sky = self
            for k in 1...horizon {
                let fire = sky.gun == 0, serial = sky.fired + 1
                let tick = sky.step(move: 0, fire: fire)
                guard fire else { continue }
                if let down = tick.downed.first(where: { $0.shot == serial }) { return (down.kind, k) }
                return sky.target(of: serial, within: horizon - k).map { ($0.kind, k + $0.ticks) }
            }
            return nil
        }

        /// What the evaluator makes of the sky `depth` ticks on, best line first.
        func value(_ depth: Int) -> Double {
            guard depth > 0 else { return hitIn(2).map { $0 == 1 ? -60 : -25 } ?? 0 }
            var best = -Double.infinity
            for move in moves {
                var next = self
                let tick = next.step(move: move.move, fire: move.fire)
                best = max(best, Double(tick.gained) - Double(tick.hits.count) * 150 + next.value(depth - 1))
            }
            return best
        }
    }

    private var sky = Sky()
    /// The sky before the last tick, for the picture to glide from.
    private var previous = Sky()
    private(set) var ticked = Date.distantPast
    private var made = 0
    private var dice = JevDice(seed: 1)
    private var moves: [(move: Int, fire: Bool)] = []
    var over: Bool { sky.lives <= 0 }
    var score: Int { sky.score }
    var status: String {
        (over ? "被击落了 · " : "") + "得分 \(sky.score) · 命 \(String(repeating: "♥", count: max(sky.lives, 0))) · 打下 \(sky.downed) 架 · 第 \(sky.time) 步"
    }

    var situation: String {
        let kinds = (0..<3).compactMap { kind -> String? in
            let n = sky.foes.filter { $0.kind == kind }.count
            return n == 0 ? nil : "\(n) \(Sky.names[kind])\(n == 1 ? "" : "s")"
        } + (sky.bombs.isEmpty ? [] : ["\(sky.bombs.count) bomb\(sky.bombs.count == 1 ? "" : "s")"])
        return "the plane is in column \(sky.x + 1) of 11 with \(sky.lives) li\(sky.lives == 1 ? "fe" : "ves") left; score \(sky.score); "
            + (sky.gun == 0 ? "the gun is ready" : "the gun is reloading, ready next tick") + "; in the sky: "
            + (kinds.isEmpty ? "nothing" : kinds.joined(separator: ", "))
    }

    var position: String {
        var rows = (0..<Self.height).map { _ in Array(repeating: ".", count: Self.width) }
        for shot in sky.shots where (0..<Self.height).contains(shot.y) { rows[shot.y][shot.x] = "|" }
        for bomb in sky.bombs where (0..<Self.height).contains(bomb.y) { rows[bomb.y][bomb.x] = "o" }
        for foe in sky.foes where (0..<Self.height).contains(foe.y) { rows[foe.y][foe.x] = ["F", "S", "B"][foe.kind] }
        rows[Self.bottom][sky.x] = "A"
        return rows.map { $0.joined(separator: " ") }.joined(separator: "\n")
            + "\n(A is your plane on the bottom row; F fighter, S swooper, B bomber, o a falling bomb, | your shot. Columns 1–11 from the left.)"
    }

    private static let night = Color(red: 0.05, green: 0.07, blue: 0.18)
    private static let inks: [Color] = [Color(red: 1, green: 0.35, blue: 0.3), .yellow, Color(red: 0.8, green: 0.55, blue: 1)]
    var grid: [[JevCell]] {
        var cells = (0..<Self.height).map { row in
            (0..<Self.width).map { col -> JevCell in
                let star = ((col * 7 + (row - sky.time) * 13) % 29 + 29) % 29 == 0      // the stars stream past
                return JevCell(colour: Self.night, text: star ? "·" : "", ink: .white.opacity(0.6))
            }
        }
        func put(_ x: Int, _ y: Int, _ cell: JevCell) {
            guard (0..<Self.height).contains(y), (0..<Self.width).contains(x) else { return }
            cells[y][x] = cell
        }
        for shot in sky.shots { put(shot.x, shot.y, JevCell(colour: Self.night, text: "|", ink: .yellow, big: true)) }
        for bomb in sky.bombs { put(bomb.x, bomb.y, JevCell(colour: Self.night, text: "●", ink: .orange)) }
        for foe in sky.foes { put(foe.x, foe.y, JevCell(colour: Self.night, text: ["▼", "◆", "■"][foe.kind], ink: Self.inks[foe.kind], big: true)) }
        for boom in sky.booms { put(boom.x, boom.y, JevCell(colour: Self.night, text: "✸", ink: .orange, big: true)) }
        put(sky.x, Self.bottom, sky.hurt ? JevCell(colour: Self.night, text: "💥", big: true)
            : JevCell(colour: Self.night, text: "▲", ink: .cyan, big: true))
        return cells
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        sky = Sky(); previous = sky; ticked = .distantPast; made = 0; dice = JevDice(seed: seed)
    }

    /// Enemies come in over the top, more of them the longer the plane lasts.
    private func spawn() {
        let level = min(Double(sky.time) / 900, 1)
        guard Double(dice.below(1000)) < (0.20 + 0.30 * level) * 1000 else { return }
        let x = dice.below(Self.width), roll = dice.below(100), dx = dice.below(2) == 0 ? -1 : 1
        guard !sky.foes.contains(where: { $0.y <= 1 && abs($0.x - x) <= 1 }) else { return }
        made += 1
        sky.foes.append(Foe(kind: roll < 55 ? 0 : roll < 80 ? 1 : 2, x: x, y: 0, dx: dx, serial: made))
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        moves = sky.moves
        return moves.enumerated().map { index, move in
            var next = sky
            let tick = next.step(move: move.move, fire: move.fire)
            var merit = Double(tick.gained) - Double(tick.hits.count) * 150 - (next.lives <= 0 ? 10_000 : 0)
            if next.lives > 0 {
                merit += next.value(3)
                if let shot = next.nextShot(within: 6) { merit += 0.3 * Double(Sky.points[shot.kind]) }
            }
            return JevOption(id: String(format: "p%02d", index + 1), label: describe(move, next, tick), merit: merit, move: index)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move), !over else { return }
        let move = moves[option.move]
        previous = sky
        _ = sky.step(move: move.move, fire: move.fire)
        ticked = Date()
        if !over { spawn() }
    }

    /// One tick's move, in words: what happens now, and what it leaves.
    private func describe(_ move: (move: Int, fire: Bool), _ next: Sky, _ tick: Sky.Tick) -> String {
        let column = next.x + 1
        var doing = move.move == 0 ? "stays in column \(column)" : "moves \(move.move < 0 ? "left" : "right") to column \(column)"
        doing += move.fire ? " and fires" : sky.gun == 0 ? " and holds fire" : ""
        var parts: [String] = []
        if !tick.hits.isEmpty {
            parts.append("is hit by \(tick.hits.joined(separator: " and ")) this tick: "
                         + (next.lives <= 0 ? "loses its last life: the game ends" : "loses a life (\(next.lives) left)"))
        }
        if move.fire {
            let serial = next.fired
            if let down = tick.downed.first(where: { $0.shot == serial }) {
                parts.append("the shot hits the \(Sky.names[down.kind]) at once (\(Sky.points[down.kind]) points)")
            } else if let hit = next.target(of: serial) {
                parts.append("the shot will hit the \(Sky.names[hit.kind]) in \(hit.ticks) tick\(hit.ticks == 1 ? "" : "s") (\(Sky.points[hit.kind]) points)")
            } else { parts.append("the shot will hit nothing") }
        }
        if next.lives > 0 {
            if !next.dodges(3) { parts.append("after it a hit can no longer be dodged: a life will be lost") }
            else if let k = next.hitIn(4) { parts.append("if the plane stays there it is hit in \(k) tick\(k == 1 ? "" : "s")") }
            else { parts.append("nothing reaches that column for 4 ticks") }
            if !move.fire, let shot = next.nextShot() {
                parts.append("from there the next shot would hit the \(Sky.names[shot.kind]) (\(Sky.points[shot.kind]) points)")
            }
        }
        return doing + ": " + parts.joined(separator: "; ")
    }

    // MARK: Played by a person

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let move = pressed.latest(of: [.left, .right], held: held).map { $0 == .left ? -1 : 1 } ?? 0
        let fire = pressed.contains(.space) || held.contains(.space)
        for (m, f) in [(move, fire), (0, fire), (move, false), (0, false)] {
            if let index = moves.firstIndex(where: { $0.move == m && $0.fire == f }),
               let option = options.first(where: { $0.move == index }) { return .choose(option) }
        }
        return options.first.map { .choose($0) } ?? .nothing
    }
}

// MARK: - The picture

extension JevShooter: JevPainted {
    var aspect: Double { 0.72 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = Scene(before: previous, after: sky, t: t, since: since, now: now, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    /// Deep space — nebulae and a ringed planet drifting by, three layers of
    /// stars streaming past at three speeds — and everything in play gliding a
    /// tick at a time. The light comes from the top left, as it does in every
    /// game here: lit faces up and to the left, shadows down and to the right.
    fileprivate struct Scene {
        let before: Sky, after: Sky, t: Double, since: Double, now: Double, over: Bool

        typealias RGB = (Double, Double, Double)

        func paint(_ g: inout GraphicsContext, _ size: CGSize) {
            let width = size.width, height = size.height
            // Some room spare under the bottom row, so the plane and its flame are seen whole.
            let column = width / CGFloat(JevShooter.width), row = height / (CGFloat(JevShooter.height) + 0.7)
            func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (CGFloat(x) + 0.5) * column, y: (CGFloat(y) + 0.5) * row) }

            space(g, size)

            // Every enemy glides from where it was to where it is.
            let old = Dictionary(before.foes.map { ($0.serial, $0) }, uniquingKeysWith: { a, _ in a })
            for foe in after.foes {
                let from = old[foe.serial]
                let p = at(JevDraw.mix(Double(from?.x ?? foe.x), Double(foe.x), t), JevDraw.mix(Double(from?.y ?? foe.y - 1), Double(foe.y), t))
                switch foe.kind {
                case 0: fighter(g, at: p, size: column * 0.98)
                case 1:
                    // Nose along the way it is going, turning quickly where it bounced off a wall.
                    let moved = from.map { Double(foe.x - $0.x) } ?? 0
                    let lean = from.map { JevDraw.mix(Double($0.dx), moved, JevDraw.smooth(t / 0.35)) } ?? Double(foe.dx)
                    swooper(g, at: p, size: column * 1.0, lean: lean, trail: CGVector(dx: CGFloat(moved) * column, dy: row))
                default: bomber(g, at: p, size: column * 1.34, arming: foe.age % 4 == 3)
                }
            }
            // Bombs fall a row a tick and shots climb two: each is drawn where it was plus how far it has come.
            for bomb in after.bombs { plasma(g, at: at(Double(bomb.x), Double(bomb.y) - 1 + t), radius: row * 0.19) }
            for shot in after.shots { laser(g, at: at(Double(shot.x), Double(shot.y) + 2 * (1 - t)), length: row * 0.82, width: column * 0.12) }

            // What was shot down this tick, and — while the ticks come fast — what the last one left still burning.
            for boom in after.booms { burst(g, at: at(Double(boom.x), Double(boom.y)), size: column * 0.55, age: since * 1.4, seed: boom.x * 31 + boom.y) }
            if t > 0.02, t < 1, since / t < 0.5 {
                for boom in before.booms { burst(g, at: at(Double(boom.x), Double(boom.y)), size: column * 0.55, age: (since + since / t) * 1.4, seed: boom.x * 31 + boom.y) }
            }

            // The plane, gliding to its column and banking as it goes, riding a little on its engines.
            let plane = CGPoint(x: at(JevDraw.mix(Double(before.x), Double(after.x), JevDraw.smooth(t)), 0).x,
                                y: at(0, Double(JevShooter.bottom)).y + CGFloat(sin(now * 2.4)) * row * 0.05)
            if !over {
                gun(g, under: plane, column: column, bottom: height)
                let bank = Double(after.x - before.x) * sin(Double.pi * min(max(t, 0), 1))
                var ship = g
                if after.hurt, since < 0.6, Int(since * 16) % 2 == 1 { ship.opacity = 0.35 }     // blinking, just hit
                hero(ship, at: plane, size: column * 1.12, bank: bank, burning: true)
                if after.hurt { burst(g, at: CGPoint(x: plane.x, y: plane.y - column * 0.2), size: column * 0.3, age: since * 1.6, seed: 5) }
            } else {
                burst(g, at: plane, size: column * 0.9, age: since, seed: 9)
            }
            if after.hurt, since < 0.5 {
                let fade = 1 - since / 0.5
                g.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .radialGradient(Gradient(colors: [Color.red.opacity(0.06 * fade), Color.red.opacity(0.5 * fade)]),
                                             center: CGPoint(x: width / 2, y: height / 2), startRadius: min(width, height) * 0.3, endRadius: max(width, height) * 0.72))
            }

            hud(g, size)
            if over { JevDraw.curtain(g, size, title: "被击落了！", detail: "得分 \(after.score) · 打下 \(after.downed) 架") }
        }

        private func rgb(_ c: RGB, _ a: Double = 1) -> Color { Color(red: c.0, green: c.1, blue: c.2).opacity(a) }

        // MARK: Space

        /// A few clouds of glowing gas, each a handful of soft blobs drifting together.
        private static let nebulae: [(x: Double, phase: Double, blobs: [(dx: Double, dy: Double, r: Double, stretch: Double, rgb: RGB, a: Double)])] = [
            (0.22, 0.12, [(0, 0, 0.42, 1.45, (0.52, 0.18, 0.72), 0.3), (0.18, 0.12, 0.26, 1.2, (0.85, 0.28, 0.58), 0.2),
                          (-0.14, -0.14, 0.24, 1.3, (0.28, 0.24, 0.85), 0.22)]),
            (0.8, 0.62, [(0, 0, 0.38, 1.35, (0.08, 0.42, 0.78), 0.28), (-0.12, 0.15, 0.24, 1.1, (0.12, 0.68, 0.78), 0.18)]),
        ]

        private struct Speck { let x: Double, y: Double, r: Double, group: Int }
        /// Far, middle and near stars, placed once.
        private static let specks: [[Speck]] = (0..<3).map { layer in
            (0..<[120, 44, 14][layer]).map { i in
                func u(_ k: Int) -> Double { Double(JevDraw.hash(i + 1, layer * 10 + k) % 10_000) / 10_000 }
                return Speck(x: u(1), y: u(2), r: [0.5, 0.85, 1.1][layer] * (0.65 + 0.7 * u(3)), group: JevDraw.hash(i + 1, layer * 10 + 4) % 4)
            }
        }

        private func space(_ g: GraphicsContext, _ size: CGSize) {
            let width = size.width, height = size.height
            // One flat colour underneath: a gradient over the whole of it would cost ten times as much, and the nebulae shade it anyway.
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.018, green: 0.022, blue: 0.075)))
            // The nebulae drift slowest of all.
            let reach = width * 0.75, span = Double(height + 2 * reach)
            for cloud in Self.nebulae {
                let cy = CGFloat((cloud.phase * span + now * Double(height) * 0.006).truncatingRemainder(dividingBy: span)) - reach
                for blob in cloud.blobs {
                    var c = g
                    c.translateBy(x: width * CGFloat(cloud.x + blob.dx), y: cy + width * CGFloat(blob.dy))
                    c.scaleBy(x: CGFloat(blob.stretch), y: 1)
                    let r = width * CGFloat(blob.r)
                    c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                           with: .radialGradient(Gradient(colors: [rgb(blob.rgb, blob.a), rgb(blob.rgb, blob.a * 0.4), rgb(blob.rgb, 0)]),
                                                 center: .zero, startRadius: 0, endRadius: r))
                }
            }
            planet(g, size)
            stars(g, size)
            // Shade along the top, behind the panel, and along the bottom, under the plane.
            for (from, to) in [(CGFloat(0), height * 0.13), (height, height * 0.9)] {
                g.fill(Path(CGRect(x: 0, y: min(from, to), width: width, height: abs(to - from))),
                       with: .linearGradient(Gradient(colors: [.black.opacity(0.4), .black.opacity(0)]), startPoint: CGPoint(x: 0, y: from), endPoint: CGPoint(x: 0, y: to)))
            }
        }

        private func stars(_ g: GraphicsContext, _ size: CGSize) {
            let width = size.width, height = Double(size.height)
            let scale = max(width / 400, 0.8)
            let speeds = [0.012, 0.035, 0.11], strength = [0.55, 0.85, 0.26]
            let tints = [Color(red: 0.72, green: 0.84, blue: 1), .white, Color(red: 1, green: 0.88, blue: 0.72), Color(red: 0.86, green: 0.9, blue: 1)]
            for layer in 0..<3 {
                let drift = now * speeds[layer] * height
                var paths = Array(repeating: Path(), count: 4)
                for speck in Self.specks[layer] {
                    let x = CGFloat(speck.x) * width, y = CGFloat((speck.y * height + drift).truncatingRemainder(dividingBy: height))
                    let r = CGFloat(speck.r) * scale
                    if layer == 2 {
                        // The nearest go by so fast they streak.
                        paths[speck.group].addRoundedRect(in: CGRect(x: x - r * 0.4, y: y - r * 6, width: r * 0.8, height: r * 6), cornerSize: CGSize(width: r * 0.4, height: r * 0.4))
                    } else if layer == 0 {
                        paths[speck.group].addRect(CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    } else {
                        paths[speck.group].addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    }
                }
                for group in 0..<4 {
                    let twinkle = layer == 2 ? 1 : 0.55 + 0.45 * sin(now * (1.1 + 0.6 * Double(group)) + Double(group * 2 + layer))
                    g.fill(paths[group], with: .color(tints[group].opacity(strength[layer] * twinkle)))
                }
            }
            // A few bright ones glint.
            var glow = g
            glow.blendMode = .plusLighter
            for i in 0..<5 {
                let speck = Self.specks[1][i]
                let x = CGFloat(speck.x) * width, y = CGFloat((speck.y * height + now * speeds[1] * height).truncatingRemainder(dividingBy: height))
                let pulse = 0.5 + 0.5 * sin(now * 2.1 + Double(i) * 1.9)
                let r = (3 + 4 * CGFloat(pulse)) * scale
                glow.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                          with: .radialGradient(Gradient(colors: [Color(red: 0.75, green: 0.85, blue: 1).opacity(0.45 * pulse), .clear]),
                                                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                var sparkle = Path()
                for (dx, dy) in [(CGFloat(0), CGFloat(1)), (1, 0)] {
                    sparkle.move(to: CGPoint(x: x - dx * r, y: y - dy * r))
                    sparkle.addLine(to: CGPoint(x: x + dy * r * 0.13, y: y + dx * r * 0.13))
                    sparkle.addLine(to: CGPoint(x: x + dx * r, y: y + dy * r))
                    sparkle.addLine(to: CGPoint(x: x - dy * r * 0.13, y: y - dx * r * 0.13))
                    sparkle.closeSubpath()
                }
                glow.fill(sparkle, with: .color(.white.opacity(0.35 + 0.55 * pulse)))
            }
        }

        /// A far gas giant with a ring, lit from the top left, sliding by very slowly.
        private func planet(_ g: GraphicsContext, _ size: CGSize) {
            let width = size.width, height = size.height
            let r = width * 0.155, reach = r * 1.9
            let span = Double(height + 2 * reach)
            let c = CGPoint(x: width * 0.86, y: CGFloat((0.3 * span + now * Double(height) * 0.004).truncatingRemainder(dividingBy: span)) - reach)
            ring(g, c, r, front: false)
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.4, y: c.y - r * 1.4, width: r * 2.8, height: r * 2.8)),
                   with: .radialGradient(Gradient(stops: [.init(color: Color(red: 0.45, green: 0.52, blue: 1).opacity(0.2), location: 0.68),
                                                          .init(color: Color(red: 0.45, green: 0.52, blue: 1).opacity(0), location: 1)]),
                                         center: c, startRadius: 0, endRadius: r * 1.4))
            let ball = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            g.fill(ball, with: .linearGradient(Gradient(colors: [Color(red: 0.5, green: 0.4, blue: 0.74), Color(red: 0.26, green: 0.18, blue: 0.48)]),
                                               startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
            // Bands of cloud, tilted with the ring.
            var bands = g
            bands.clip(to: ball)
            bands.translateBy(x: c.x, y: c.y)
            bands.rotate(by: .radians(-0.38))
            for (y, h, light) in [(-0.55, 0.12, true), (-0.2, 0.09, false), (0.1, 0.16, true), (0.45, 0.1, false)] as [(CGFloat, CGFloat, Bool)] {
                bands.fill(Path(ellipseIn: CGRect(x: -r * 1.4, y: r * (y - h), width: r * 2.8, height: r * h * 2)),
                           with: .color(light ? Color(red: 0.86, green: 0.76, blue: 1).opacity(0.16) : Color(red: 0.16, green: 0.08, blue: 0.3).opacity(0.22)))
            }
            // Night on the far side.
            g.fill(ball, with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.3), location: 0.32),
                                                               .init(color: .black.opacity(0.78), location: 0.62), .init(color: .black.opacity(0.94), location: 0.9)]),
                                               center: CGPoint(x: c.x - r * 0.55, y: c.y - r * 0.6), startRadius: 0, endRadius: r * 2.2))
            g.stroke(Path { p in p.addArc(center: c, radius: r - 0.8, startAngle: .degrees(150), endAngle: .degrees(300), clockwise: false) },
                     with: .color(Color(red: 0.85, green: 0.85, blue: 1).opacity(0.35)), lineWidth: 1.3)
            ring(g, c, r, front: true)
        }

        /// The ring: the half behind the ball drawn before it, the half in front after.
        private func ring(_ g: GraphicsContext, _ c: CGPoint, _ r: CGFloat, front: Bool) {
            var ring = g
            ring.translateBy(x: c.x, y: c.y)
            ring.rotate(by: .radians(-0.38))
            ring.scaleBy(x: 1, y: 0.25)
            ring.clip(to: Path(CGRect(x: -r * 3, y: front ? 0 : -r * 3, width: r * 6, height: r * 3)))
            var band = Path()
            band.addEllipse(in: CGRect(x: -r * 1.85, y: -r * 1.85, width: r * 3.7, height: r * 3.7))
            band.addEllipse(in: CGRect(x: -r * 1.3, y: -r * 1.3, width: r * 2.6, height: r * 2.6))
            ring.fill(band, with: .linearGradient(Gradient(colors: [Color(red: 0.8, green: 0.72, blue: 1).opacity(front ? 0.42 : 0.26),
                                                                    Color(red: 0.3, green: 0.22, blue: 0.5).opacity(front ? 0.2 : 0.1)]),
                                                  startPoint: CGPoint(x: -r * 1.85, y: 0), endPoint: CGPoint(x: r * 1.85, y: 0)),
                      style: FillStyle(eoFill: true))
            ring.stroke(Path(ellipseIn: CGRect(x: -r * 1.58, y: -r * 1.58, width: r * 3.16, height: r * 3.16)),
                        with: .color(Color(red: 0.04, green: 0.02, blue: 0.1).opacity(0.45)), lineWidth: r * 0.06)
        }

        // MARK: Ships

        /// Shapes a unit across, centred on the origin: the plane points up the screen, the enemies down it.
        private static func symmetric(_ half: [(CGFloat, CGFloat)]) -> Path {
            Path { path in
                path.move(to: CGPoint(x: half[0].0, y: half[0].1))
                for (x, y) in half.dropFirst() { path.addLine(to: CGPoint(x: x, y: y)) }
                for (x, y) in half.reversed() { path.addLine(to: CGPoint(x: -x, y: y)) }
                path.closeSubpath()
            }
        }
        private static func pairs(_ shapes: [[(CGFloat, CGFloat)]]) -> Path {
            Path { path in
                for shape in shapes {
                    for side: CGFloat in [1, -1] {
                        path.move(to: CGPoint(x: shape[0].0 * side, y: shape[0].1))
                        for (x, y) in shape.dropFirst() { path.addLine(to: CGPoint(x: x * side, y: y)) }
                        path.closeSubpath()
                    }
                }
            }
        }
        private static func place(_ path: Path, _ p: CGPoint, _ s: CGFloat, turn: Double = 0, squeeze: CGFloat = 1) -> Path {
            path.applying(CGAffineTransform(translationX: p.x, y: p.y).rotated(by: CGFloat(turn)).scaledBy(x: s * squeeze, y: s))
        }

        private static let heroBody = symmetric([(0, -0.55), (0.03, -0.47), (0.055, -0.36), (0.078, -0.2), (0.092, 0.02), (0.09, 0.3), (0.078, 0.42), (0.055, 0.47), (0, 0.47)])
        private static let heroWings = pairs([[(0.07, -0.12), (0.47, 0.15), (0.48, 0.25), (0.3, 0.26), (0.08, 0.29)]])
        private static let heroFins = pairs([[(0.07, -0.3), (0.17, -0.21), (0.17, -0.165), (0.075, -0.17)],
                                             [(0.07, 0.3), (0.22, 0.4), (0.22, 0.47), (0.065, 0.44)]])
        private static let heroTrim = pairs([[(0.12, -0.035), (0.43, 0.175), (0.435, 0.205), (0.12, 0.0)]])
        private static let heroCanopy = Path { p in
            p.move(to: CGPoint(x: 0, y: -0.42))
            p.addQuadCurve(to: CGPoint(x: 0.05, y: -0.24), control: CGPoint(x: 0.048, y: -0.38))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.1), control: CGPoint(x: 0.052, y: -0.13))
            p.addQuadCurve(to: CGPoint(x: -0.05, y: -0.24), control: CGPoint(x: -0.052, y: -0.13))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.42), control: CGPoint(x: -0.048, y: -0.38))
            p.closeSubpath()
        }
        private static let heroNozzles = Path { p in
            for x: CGFloat in [-0.045, 0.045] { p.addEllipse(in: CGRect(x: x - 0.032, y: 0.42, width: 0.064, height: 0.07)) }
        }
        private static let heroFlames: (outer: Path, core: Path) = {
            var outer = Path(), core = Path()
            for x: CGFloat in [-0.045, 0.045] {
                outer.move(to: CGPoint(x: x - 0.048, y: 0.45))
                outer.addQuadCurve(to: CGPoint(x: x, y: 1.1), control: CGPoint(x: x - 0.046, y: 0.78))
                outer.addQuadCurve(to: CGPoint(x: x + 0.048, y: 0.45), control: CGPoint(x: x + 0.046, y: 0.78))
                outer.closeSubpath()
                core.move(to: CGPoint(x: x - 0.024, y: 0.45))
                core.addQuadCurve(to: CGPoint(x: x, y: 0.86), control: CGPoint(x: x - 0.022, y: 0.66))
                core.addQuadCurve(to: CGPoint(x: x + 0.024, y: 0.45), control: CGPoint(x: x + 0.022, y: 0.66))
                core.closeSubpath()
            }
            return (outer, core)
        }()

        /// The player's fighter: white and silver with cyan trim, a glass canopy, twin engines burning.
        private func hero(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat, bank: Double, burning: Bool) {
            let squeeze = CGFloat(1 - 0.16 * abs(bank)), turn = bank * 0.07
            func place(_ path: Path) -> Path { Self.place(path, p, s, turn: turn, squeeze: squeeze) }
            if burning {
                // The flame: long and short by turns, drawn in light rather than paint.
                var fire = g
                fire.blendMode = .plusLighter
                let flicker = 0.8 + 0.14 * sin(now * 53) + 0.06 * sin(now * 31 + 1.3)
                let reach = 0.45 + 0.55 * flicker
                var stretch = CGAffineTransform(translationX: p.x, y: p.y + 0.45 * s).rotated(by: CGFloat(turn)).scaledBy(x: s * squeeze, y: s * CGFloat(reach))
                stretch = stretch.translatedBy(x: 0, y: -0.45)
                let top = CGPoint(x: p.x, y: p.y + 0.45 * s), end = CGPoint(x: p.x, y: p.y + (0.45 + 0.65 * CGFloat(reach)) * s)
                fire.fill(Path(ellipseIn: CGRect(x: p.x - 0.22 * s, y: p.y + 0.3 * s, width: 0.44 * s, height: 0.44 * s)),
                          with: .radialGradient(Gradient(colors: [Color(red: 0.3, green: 0.75, blue: 1).opacity(0.55), .clear]),
                                                center: CGPoint(x: p.x, y: p.y + 0.5 * s), startRadius: 0, endRadius: 0.24 * s))
                fire.fill(Self.heroFlames.outer.applying(stretch),
                          with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.92, blue: 1), Color(red: 0.2, green: 0.45, blue: 1).opacity(0.7),
                                                                  Color(red: 0.35, green: 0.2, blue: 1).opacity(0)]), startPoint: top, endPoint: end))
                fire.fill(Self.heroFlames.core.applying(stretch),
                          with: .linearGradient(Gradient(colors: [.white, Color(red: 0.75, green: 0.96, blue: 1).opacity(0.8), .clear]),
                                                startPoint: top, endPoint: CGPoint(x: p.x, y: p.y + (0.45 + 0.41 * CGFloat(reach)) * s)))
            }
            let wings = place(Self.heroWings), fins = place(Self.heroFins), body = place(Self.heroBody)
            var outline = Path()
            outline.addPath(wings); outline.addPath(fins); outline.addPath(body)
            g.fill(outline.applying(CGAffineTransform(translationX: s * 0.07, y: s * 0.11)), with: .color(.black.opacity(0.32)))
            let lit = CGPoint(x: p.x - 0.5 * s, y: p.y - 0.45 * s), dim = CGPoint(x: p.x + 0.5 * s, y: p.y + 0.45 * s)
            let metal = Gradient(colors: [Color(red: 0.95, green: 0.97, blue: 1), Color(red: 0.6, green: 0.68, blue: 0.82), Color(red: 0.24, green: 0.3, blue: 0.46)])
            let edge = Color(red: 0.04, green: 0.07, blue: 0.18), line = max(0.7, s * 0.02)
            g.fill(wings, with: .linearGradient(metal, startPoint: lit, endPoint: dim))
            g.fill(place(Self.heroTrim), with: .color(Color(red: 0.12, green: 0.78, blue: 1)))
            g.stroke(wings, with: .color(edge), lineWidth: line)
            g.fill(fins, with: .linearGradient(metal, startPoint: lit, endPoint: dim))
            g.stroke(fins, with: .color(edge), lineWidth: line)
            // The fuselage is round: lit down its left side, in shade down its right.
            g.fill(body, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.82, green: 0.87, blue: 0.95), Color(red: 0.42, green: 0.5, blue: 0.66)]),
                                               startPoint: CGPoint(x: p.x - 0.08 * s, y: p.y), endPoint: CGPoint(x: p.x + 0.09 * s, y: p.y)))
            g.stroke(body, with: .color(edge), lineWidth: line)
            g.fill(place(Path(CGRect(x: -0.012, y: 0.0, width: 0.024, height: 0.34))), with: .color(Color(red: 0.12, green: 0.78, blue: 1).opacity(0.9)))
            g.fill(place(Self.heroNozzles), with: .color(Color(red: 0.1, green: 0.12, blue: 0.2)))
            // The canopy: dark glass, a sky-blue rim of reflection, and a glint where the light falls.
            g.fill(place(Self.heroCanopy),
                   with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.94, blue: 1), Color(red: 0.1, green: 0.36, blue: 0.78), Color(red: 0.02, green: 0.06, blue: 0.24)]),
                                         startPoint: CGPoint(x: p.x - 0.05 * s, y: p.y - 0.4 * s), endPoint: CGPoint(x: p.x + 0.05 * s, y: p.y - 0.1 * s)))
            g.fill(place(Path(ellipseIn: CGRect(x: -0.03, y: -0.36, width: 0.022, height: 0.11))), with: .color(.white.opacity(0.85)))
            if burning {
                // Wingtip lights, port red and starboard green, blinking.
                let on = sin(now * 5) > -0.2
                for (x, colour) in [(-0.46, Color(red: 1, green: 0.3, blue: 0.3)), (0.46, Color(red: 0.35, green: 1, blue: 0.5))] as [(CGFloat, Color)] {
                    let q = place(Path(CGRect(x: x, y: 0.2, width: 0, height: 0))).boundingRect.origin
                    let r = s * (on ? 0.07 : 0.04)
                    g.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)),
                           with: .radialGradient(Gradient(colors: [.white, colour, colour.opacity(0)]), center: q, startRadius: 0, endRadius: r))
                }
            }
        }

        private static let fighterBody = symmetric([(0, 0.52), (0.04, 0.4), (0.075, 0.2), (0.085, -0.1), (0.065, -0.36), (0.035, -0.44), (0, -0.44)])
        private static let fighterWings = pairs([[(0.07, 0.02), (0.46, 0.17), (0.47, 0.07), (0.22, -0.2), (0.07, -0.26)]])
        private static let fighterFins = pairs([[(0.06, -0.24), (0.21, -0.4), (0.18, -0.46), (0.05, -0.4)]])
        private static let fighterStripes = pairs([[(0.12, -0.02), (0.4, 0.1), (0.39, 0.06), (0.13, -0.07)]])

        /// The fighter: a red forward-swept dart with one glowing yellow eye.
        private func fighter(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat) {
            func place(_ path: Path) -> Path { Self.place(path, p, s) }
            halo(g, p, s * 0.72, Color(red: 1, green: 0.22, blue: 0.18), 0.32)
            exhaust(g, at: CGPoint(x: p.x, y: p.y - 0.44 * s), size: s * 0.8, colour: Color(red: 1, green: 0.45, blue: 0.2), phase: Double(p.x))
            let wings = place(Self.fighterWings), fins = place(Self.fighterFins), body = place(Self.fighterBody)
            var outline = Path()
            outline.addPath(wings); outline.addPath(fins); outline.addPath(body)
            g.fill(outline.applying(CGAffineTransform(translationX: s * 0.07, y: s * 0.1)), with: .color(.black.opacity(0.32)))
            let red = Gradient(colors: [Color(red: 1, green: 0.52, blue: 0.44), Color(red: 0.84, green: 0.14, blue: 0.16), Color(red: 0.34, green: 0.02, blue: 0.07)])
            let lit = CGPoint(x: p.x - 0.5 * s, y: p.y - 0.4 * s), dim = CGPoint(x: p.x + 0.5 * s, y: p.y + 0.4 * s)
            let edge = Color(red: 0.2, green: 0.01, blue: 0.04), line = max(0.7, s * 0.02)
            g.fill(wings, with: .linearGradient(red, startPoint: lit, endPoint: dim))
            g.fill(place(Self.fighterStripes), with: .color(Color(red: 0.22, green: 0.02, blue: 0.06).opacity(0.75)))
            g.stroke(wings, with: .color(edge), lineWidth: line)
            g.fill(fins, with: .linearGradient(red, startPoint: lit, endPoint: dim))
            g.stroke(fins, with: .color(edge), lineWidth: line)
            g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.7, blue: 0.62), Color(red: 0.86, green: 0.2, blue: 0.2), Color(red: 0.42, green: 0.04, blue: 0.08)]),
                                               startPoint: CGPoint(x: p.x - 0.08 * s, y: p.y), endPoint: CGPoint(x: p.x + 0.085 * s, y: p.y)))
            g.stroke(body, with: .color(edge), lineWidth: line)
            // The eye: a glowing canopy looking down at the plane.
            let eye = CGPoint(x: p.x, y: p.y + 0.2 * s)
            var glow = g
            glow.blendMode = .plusLighter
            glow.fill(Path(ellipseIn: CGRect(x: eye.x - 0.2 * s, y: eye.y - 0.2 * s, width: 0.4 * s, height: 0.4 * s)),
                      with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.2).opacity(0.5), .clear]), center: eye, startRadius: 0, endRadius: 0.2 * s))
            g.fill(Path(ellipseIn: CGRect(x: eye.x - 0.042 * s, y: eye.y - 0.1 * s, width: 0.084 * s, height: 0.2 * s)),
                   with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.9, blue: 0.3), Color(red: 1, green: 0.42, blue: 0.05)]),
                                         center: CGPoint(x: eye.x - 0.012 * s, y: eye.y - 0.03 * s), startRadius: 0, endRadius: 0.1 * s))
        }

        private static let swooperWing = Path { p in
            p.move(to: CGPoint(x: 0, y: 0.42))
            p.addQuadCurve(to: CGPoint(x: 0.5, y: -0.3), control: CGPoint(x: 0.42, y: 0.2))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.06), control: CGPoint(x: 0.22, y: -0.12))
            p.addQuadCurve(to: CGPoint(x: -0.5, y: -0.3), control: CGPoint(x: -0.22, y: -0.12))
            p.addQuadCurve(to: CGPoint(x: 0, y: 0.42), control: CGPoint(x: -0.42, y: 0.2))
            p.closeSubpath()
        }
        private static let swooperPod = Path(ellipseIn: CGRect(x: -0.1, y: -0.2, width: 0.2, height: 0.56))
        private static let swooperVeins = Path { p in
            for side: CGFloat in [1, -1] {
                p.move(to: CGPoint(x: 0.1 * side, y: 0.12))
                p.addQuadCurve(to: CGPoint(x: 0.44 * side, y: -0.24), control: CGPoint(x: 0.3 * side, y: 0.02))
            }
        }

        /// The swooper: a golden crescent with a green heart, nose along its diagonal, a ribbon of light behind.
        private func swooper(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat, lean: Double, trail: CGVector) {
            let turn = -atan2(lean * 0.8, 1.0)
            func place(_ path: Path) -> Path { Self.place(path, p, s, turn: turn) }
            var glow = g
            glow.blendMode = .plusLighter
            let tail = CGPoint(x: p.x - trail.dx * 0.9, y: p.y - trail.dy * 0.9)
            var ribbon = Path()
            ribbon.move(to: tail)
            ribbon.addLine(to: p)
            glow.stroke(ribbon, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.75, blue: 0.2).opacity(0), Color(red: 1, green: 0.78, blue: 0.25).opacity(0.32)]),
                                                      startPoint: tail, endPoint: p), style: StrokeStyle(lineWidth: s * 0.4, lineCap: .round))
            halo(g, p, s * 0.72, Color(red: 1, green: 0.7, blue: 0.1), 0.3)
            let wing = place(Self.swooperWing), pod = place(Self.swooperPod)
            g.fill(wing.applying(CGAffineTransform(translationX: s * 0.07, y: s * 0.1)), with: .color(.black.opacity(0.32)))
            let lit = CGPoint(x: p.x - 0.45 * s, y: p.y - 0.4 * s), dim = CGPoint(x: p.x + 0.45 * s, y: p.y + 0.4 * s)
            g.fill(wing, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.62), Color(red: 0.98, green: 0.7, blue: 0.14), Color(red: 0.52, green: 0.26, blue: 0.02)]),
                                               startPoint: lit, endPoint: dim))
            g.stroke(place(Self.swooperVeins), with: .color(Color(red: 0.45, green: 0.22, blue: 0.0).opacity(0.55)), lineWidth: max(0.7, s * 0.022))
            g.stroke(wing, with: .color(Color(red: 0.3, green: 0.13, blue: 0.0)), lineWidth: max(0.7, s * 0.02))
            g.fill(pod, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.72, green: 0.42, blue: 0.04)]),
                                              startPoint: CGPoint(x: p.x - 0.1 * s, y: p.y), endPoint: CGPoint(x: p.x + 0.1 * s, y: p.y)))
            g.stroke(pod, with: .color(Color(red: 0.3, green: 0.13, blue: 0.0)), lineWidth: max(0.7, s * 0.02))
            // Its heart, pulsing.
            let pulse = 0.5 + 0.5 * sin(now * 7 + Double(p.x) * 0.1)
            let core = place(Path(CGRect(x: 0, y: 0.06, width: 0, height: 0))).boundingRect.origin
            let r = s * CGFloat(0.2 + 0.06 * pulse)
            glow.fill(Path(ellipseIn: CGRect(x: core.x - r, y: core.y - r, width: 2 * r, height: 2 * r)),
                      with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 1, blue: 0.75).opacity(0.7), .clear]), center: core, startRadius: 0, endRadius: r))
            g.fill(Path(ellipseIn: CGRect(x: core.x - 0.07 * s, y: core.y - 0.07 * s, width: 0.14 * s, height: 0.14 * s)),
                   with: .radialGradient(Gradient(colors: [.white, Color(red: 0.45, green: 1, blue: 0.7), Color(red: 0.05, green: 0.55, blue: 0.4)]),
                                         center: CGPoint(x: core.x - 0.02 * s, y: core.y - 0.02 * s), startRadius: 0, endRadius: 0.08 * s))
        }

        private static let bomberWing = symmetric([(0, 0.46), (0.2, 0.25), (0.5, 0.0), (0.5, -0.12), (0.4, -0.19), (0.3, -0.11), (0.2, -0.2), (0.1, -0.12), (0, -0.21)])
        private static let bomberSpine = symmetric([(0, 0.42), (0.06, 0.32), (0.095, 0.1), (0.09, -0.16), (0.055, -0.28), (0, -0.3)])
        private static let bomberPods = Path { p in
            for x: CGFloat in [-0.31, -0.18, 0.18, 0.31] { p.addRoundedRect(in: CGRect(x: x - 0.042, y: -0.27, width: 0.084, height: 0.28), cornerSize: CGSize(width: 0.04, height: 0.04)) }
        }
        private static let bomberLines = Path { p in
            for side: CGFloat in [1, -1] {
                p.move(to: CGPoint(x: 0.13 * side, y: 0.24)); p.addLine(to: CGPoint(x: 0.44 * side, y: -0.01))
                p.move(to: CGPoint(x: 0.24 * side, y: 0.06)); p.addLine(to: CGPoint(x: 0.24 * side, y: -0.14))
            }
            for y: CGFloat in [-0.2, 0.2] { p.move(to: CGPoint(x: -0.075, y: y)); p.addLine(to: CGPoint(x: 0.075, y: y)) }
        }

        /// The bomber: a broad armoured flying wing, four engines, its bomb bay glowing just before it drops.
        private func bomber(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat, arming: Bool) {
            func place(_ path: Path) -> Path { Self.place(path, p, s) }
            halo(g, p, s * 0.7, Color(red: 0.62, green: 0.3, blue: 1), 0.3)
            for x: CGFloat in [-0.31, -0.18, 0.18, 0.31] {
                exhaust(g, at: CGPoint(x: p.x + x * s, y: p.y - 0.27 * s), size: s * 0.46, colour: Color(red: 0.85, green: 0.4, blue: 1), phase: Double(x * 10))
            }
            let wing = place(Self.bomberWing), spine = place(Self.bomberSpine), pods = place(Self.bomberPods)
            g.fill(wing.applying(CGAffineTransform(translationX: s * 0.06, y: s * 0.09)), with: .color(.black.opacity(0.34)))
            let lit = CGPoint(x: p.x - 0.5 * s, y: p.y - 0.3 * s), dim = CGPoint(x: p.x + 0.5 * s, y: p.y + 0.35 * s)
            let edge = Color(red: 0.1, green: 0.02, blue: 0.2), line = max(0.8, s * 0.018)
            g.fill(wing, with: .linearGradient(Gradient(colors: [Color(red: 0.8, green: 0.64, blue: 1), Color(red: 0.5, green: 0.26, blue: 0.82), Color(red: 0.2, green: 0.07, blue: 0.38)]),
                                               startPoint: lit, endPoint: dim))
            g.stroke(place(Self.bomberLines), with: .color(edge.opacity(0.5)), lineWidth: line * 0.8)
            g.stroke(wing, with: .color(edge), lineWidth: line)
            g.fill(spine, with: .linearGradient(Gradient(colors: [Color(red: 0.92, green: 0.84, blue: 1), Color(red: 0.6, green: 0.38, blue: 0.9), Color(red: 0.26, green: 0.1, blue: 0.46)]),
                                                startPoint: CGPoint(x: p.x - 0.09 * s, y: p.y), endPoint: CGPoint(x: p.x + 0.1 * s, y: p.y)))
            g.stroke(spine, with: .color(edge), lineWidth: line)
            g.fill(pods, with: .linearGradient(Gradient(colors: [Color(red: 0.76, green: 0.66, blue: 0.92), Color(red: 0.3, green: 0.18, blue: 0.48)]), startPoint: lit, endPoint: dim))
            g.stroke(pods, with: .color(edge), lineWidth: line)
            // The cockpit, a magenta visor near the nose, and lights at the wingtips.
            var glow = g
            glow.blendMode = .plusLighter
            let visor = CGPoint(x: p.x, y: p.y + 0.29 * s)
            glow.fill(Path(ellipseIn: CGRect(x: visor.x - 0.16 * s, y: visor.y - 0.12 * s, width: 0.32 * s, height: 0.24 * s)),
                      with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.35, blue: 0.85).opacity(0.5), .clear]), center: visor, startRadius: 0, endRadius: 0.14 * s))
            g.fill(Path(ellipseIn: CGRect(x: visor.x - 0.045 * s, y: visor.y - 0.03 * s, width: 0.09 * s, height: 0.06 * s)),
                   with: .linearGradient(Gradient(colors: [.white, Color(red: 1, green: 0.45, blue: 0.9)]), startPoint: CGPoint(x: visor.x, y: visor.y - 0.03 * s), endPoint: CGPoint(x: visor.x, y: visor.y + 0.03 * s)))
            for x: CGFloat in [-0.47, 0.47] {
                let q = CGPoint(x: p.x + x * s, y: p.y - 0.06 * s), r = s * 0.045
                glow.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)),
                          with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.4, blue: 0.9), .clear]), center: q, startRadius: 0, endRadius: r))
            }
            // The bomb bay: shut and dark, or open and white hot the tick before a bomb.
            let bay = place(Path(roundedRect: CGRect(x: -0.05, y: 0.0, width: 0.1, height: 0.15), cornerRadius: 0.025))
            if arming {
                let pulse = 0.75 + 0.25 * sin(now * 18)
                let c = CGPoint(x: p.x, y: p.y + 0.08 * s)
                glow.fill(Path(ellipseIn: CGRect(x: c.x - 0.42 * s, y: c.y - 0.42 * s, width: 0.84 * s, height: 0.84 * s)),
                          with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.55, blue: 0.1).opacity(0.75 * pulse), .clear]), center: c, startRadius: 0, endRadius: 0.42 * s))
                g.fill(bay, with: .linearGradient(Gradient(colors: [.white, Color(red: 1, green: 0.8, blue: 0.3), Color(red: 1, green: 0.35, blue: 0.05)]),
                                                  startPoint: CGPoint(x: p.x, y: p.y), endPoint: CGPoint(x: p.x, y: p.y + 0.15 * s)))
            } else {
                g.fill(bay, with: .color(Color(red: 0.14, green: 0.05, blue: 0.25)))
            }
            g.stroke(bay, with: .color(edge), lineWidth: line * 0.8)
        }

        /// A soft glow in a ship's colour, so it reads against the dark.
        private func halo(_ g: GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ colour: Color, _ strength: Double) {
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [colour.opacity(strength), colour.opacity(strength * 0.35), colour.opacity(0)]), center: p, startRadius: 0, endRadius: r))
        }

        /// An enemy's engine: a short flickering flame pointing up the screen, behind it as it flies down.
        private func exhaust(_ g: GraphicsContext, at base: CGPoint, size s: CGFloat, colour: Color, phase: Double) {
            var fire = g
            fire.blendMode = .plusLighter
            let long = s * CGFloat(0.28 + 0.06 * sin(now * 41 + phase) + 0.04 * sin(now * 23 + phase * 2))
            let w = s * 0.12
            var flame = Path()
            flame.move(to: CGPoint(x: base.x - w, y: base.y))
            flame.addQuadCurve(to: CGPoint(x: base.x, y: base.y - long), control: CGPoint(x: base.x - w, y: base.y - long * 0.5))
            flame.addQuadCurve(to: CGPoint(x: base.x + w, y: base.y), control: CGPoint(x: base.x + w, y: base.y - long * 0.5))
            flame.closeSubpath()
            fire.fill(flame, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.9), colour.opacity(0.75), colour.opacity(0)]),
                                                   startPoint: base, endPoint: CGPoint(x: base.x, y: base.y - long)))
        }

        // MARK: Shots, bombs, fire

        /// The plane's shot: a white-hot bolt in a cyan glow, streaking.
        private func laser(_ g: GraphicsContext, at p: CGPoint, length: CGFloat, width w: CGFloat) {
            var glow = g
            glow.blendMode = .plusLighter
            let streak = CGRect(x: p.x - w * 0.45, y: p.y, width: w * 0.9, height: length * 1.4)
            glow.fill(Path(roundedRect: streak, cornerRadius: w * 0.45),
                      with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.8, blue: 1).opacity(0.55), Color(red: 0.2, green: 0.5, blue: 1).opacity(0)]),
                                            startPoint: CGPoint(x: p.x, y: streak.minY), endPoint: CGPoint(x: p.x, y: streak.maxY)))
            var halo = glow
            halo.translateBy(x: p.x, y: p.y)
            halo.scaleBy(x: w * 2.6 / (length * 0.8), y: 1)
            halo.fill(Path(ellipseIn: CGRect(x: -length * 0.8, y: -length * 0.8, width: length * 1.6, height: length * 1.6)),
                      with: .radialGradient(Gradient(colors: [Color(red: 0.3, green: 0.8, blue: 1).opacity(0.6), Color(red: 0.2, green: 0.5, blue: 1).opacity(0.18),
                                                              Color(red: 0.2, green: 0.5, blue: 1).opacity(0)]),
                                            center: .zero, startRadius: 0, endRadius: length * 0.8))
            let bolt = CGRect(x: p.x - w * 0.5, y: p.y - length * 0.5, width: w, height: length)
            g.fill(Path(roundedRect: bolt, cornerRadius: w * 0.5), with: .color(Color(red: 0.5, green: 0.92, blue: 1)))
            g.fill(Path(roundedRect: bolt.insetBy(dx: w * 0.24, dy: w * 0.3), cornerRadius: w * 0.26), with: .color(.white))
        }

        /// A bomb: a ball of orange plasma, pulsing, a faint trail above it.
        private func plasma(_ g: GraphicsContext, at p: CGPoint, radius r: CGFloat) {
            var glow = g
            glow.blendMode = .plusLighter
            let trail = CGRect(x: p.x - r * 0.6, y: p.y - r * 4, width: r * 1.2, height: r * 4)
            glow.fill(Path(roundedRect: trail, cornerRadius: r * 0.6),
                      with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.4, blue: 0.1).opacity(0), Color(red: 1, green: 0.45, blue: 0.1).opacity(0.45)]),
                                            startPoint: CGPoint(x: p.x, y: trail.minY), endPoint: CGPoint(x: p.x, y: trail.maxY)))
            let pulse = CGFloat(0.85 + 0.15 * sin(now * 14 + Double(p.x)))
            let halo = r * 2.8 * pulse
            glow.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: 2 * halo, height: 2 * halo)),
                      with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.45, blue: 0.08).opacity(0.7), Color(red: 1, green: 0.2, blue: 0.05).opacity(0)]),
                                            center: p, startRadius: 0, endRadius: halo))
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.9, blue: 0.45), Color(red: 1, green: 0.42, blue: 0.1), Color(red: 0.7, green: 0.08, blue: 0.04)]),
                                         center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
            // A spinning glint says: this one hurts.
            let spin = now * 5 + Double(p.x)
            var glint = Path()
            for k in 0..<2 {
                let a = spin + Double(k) * .pi / 2
                let dx = CGFloat(cos(a)) * r * 1.9, dy = CGFloat(sin(a)) * r * 1.9
                glint.move(to: CGPoint(x: p.x - dx, y: p.y - dy))
                glint.addLine(to: CGPoint(x: p.x + dx, y: p.y + dy))
            }
            glow.stroke(glint, with: .color(Color(red: 1, green: 0.8, blue: 0.5).opacity(0.5)), lineWidth: max(0.8, r * 0.14))
        }

        /// Something blown up: a flash, a shockwave, the fireball, and pieces flung out tumbling.
        private func burst(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat, age: Double, seed: Int) {
            guard age >= 0, age < 1.25 else { return }
            var glow = g
            glow.blendMode = .plusLighter
            if age < 0.2 {
                let f = 1 - age / 0.2, r = s * 2.8
                glow.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                          with: .radialGradient(Gradient(colors: [.white.opacity(0.9 * f), Color(red: 1, green: 0.8, blue: 0.5).opacity(0.35 * f), .clear]),
                                                center: p, startRadius: 0, endRadius: r))
            }
            if age < 0.7 {
                let k = age / 0.7, r = s * CGFloat(0.5 + 2.8 * (1 - (1 - k) * (1 - k)))
                glow.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                            with: .color(Color(red: 1, green: 0.8, blue: 0.55).opacity(0.6 * (1 - k))), lineWidth: s * 0.14 * CGFloat(1 - k) + 0.5)
            }
            JevDraw.blast(g, at: p, size: s, age: age)
            // Light over the fireball, so it burns rather than sits there painted.
            let fade = max(0, 1 - age / 1.1), travel = CGFloat(1 - exp(-age * 3.4))
            let fire = s * (0.7 + 1.5 * travel)
            glow.fill(Path(ellipseIn: CGRect(x: p.x - fire, y: p.y - fire, width: 2 * fire, height: 2 * fire)),
                      with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.5).opacity(0.55 * fade), Color(red: 1, green: 0.45, blue: 0.12).opacity(0.3 * fade), .clear]),
                                            center: p, startRadius: 0, endRadius: fire))
            var shards = Path(), embers = Path()
            for k in 0..<8 {
                func u(_ n: Int) -> Double { Double(JevDraw.hash(seed, k * 8 + n) % 1000) / 1000 }
                let angle = Double(k) * .pi / 4 + u(1) * 0.7
                let reach = s * CGFloat(1.4 + 1.8 * u(2)) * travel
                let q = CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach + CGFloat(age) * s * 0.6)
                let spin = age * (5 + 4 * u(3)) + u(4) * 6, long = s * CGFloat(0.14 + 0.14 * u(5))
                shards.move(to: CGPoint(x: q.x + CGFloat(cos(spin)) * long, y: q.y + CGFloat(sin(spin)) * long))
                shards.addLine(to: CGPoint(x: q.x + CGFloat(cos(spin + 2.3)) * long * 0.7, y: q.y + CGFloat(sin(spin + 2.3)) * long * 0.7))
                shards.addLine(to: CGPoint(x: q.x + CGFloat(cos(spin + 4.1)) * long * 0.55, y: q.y + CGFloat(sin(spin + 4.1)) * long * 0.55))
                shards.closeSubpath()
                let away = angle + 0.4, far = reach * 1.25, e = s * 0.07 * CGFloat(fade) + 0.5
                let ember = CGPoint(x: p.x + CGFloat(cos(away)) * far, y: p.y + CGFloat(sin(away)) * far + CGFloat(age) * s * 0.6)
                embers.addEllipse(in: CGRect(x: ember.x - e, y: ember.y - e, width: 2 * e, height: 2 * e))
            }
            let heat = max(0, 1 - age / 0.6)
            glow.stroke(shards, with: .color(Color(red: 1, green: 0.55, blue: 0.15).opacity(fade * 0.5 * heat)), lineWidth: max(1.5, s * 0.1))
            g.fill(shards, with: .color(Color(red: 0.3 + 0.7 * heat, green: 0.28 + 0.52 * heat, blue: 0.34 + 0.1 * heat).opacity(fade)))
            glow.fill(embers, with: .color(Color(red: 1, green: 0.72, blue: 0.3).opacity(fade)))
        }

        // MARK: The panel

        /// Frosted glass: dark and see-through, a sheen on its upper half, its edge catching the light at the top.
        private func glass(_ g: GraphicsContext, _ rect: CGRect) {
            let shape = Path(roundedRect: rect, cornerRadius: min(rect.height * 0.34, 12))
            g.fill(shape.applying(CGAffineTransform(translationX: 1.5, y: 2.5)), with: .color(.black.opacity(0.3)))
            g.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.18, green: 0.22, blue: 0.4).opacity(0.62), Color(red: 0.03, green: 0.04, blue: 0.13).opacity(0.72)]),
                                                startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            var sheen = g
            sheen.clip(to: shape)
            sheen.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.5)),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0.04)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.midY)))
            g.stroke(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0.08)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)),
                     lineWidth: 1)
        }

        /// The score and the kills at the top left, the lives at the top right.
        private func hud(_ g: GraphicsContext, _ size: CGSize) {
            let width = size.width
            let unit = min(width / 22, 26), margin = unit * 0.5
            let cyan = Color(red: 0.45, green: 0.88, blue: 1)
            let font = Font.system(size: unit * 1.3, weight: .heavy, design: .rounded).monospacedDigit()
            let digits = g.resolve(Text("\(after.score)").font(font).foregroundColor(.white))
            let shade = g.resolve(Text("\(after.score)").font(font).foregroundColor(Color(red: 0, green: 0.05, blue: 0.25).opacity(0.7)))
            let kills = g.resolve(Text("打下 \(after.downed)").font(.system(size: unit * 0.62, weight: .bold, design: .rounded)).foregroundColor(cyan))
            let big = digits.measure(in: size), small = kills.measure(in: size)
            let box = CGRect(x: margin, y: margin, width: max(big.width, small.width + unit * 0.8) + unit * 1.1, height: big.height + small.height + unit * 0.3)
            glass(g, box)
            let left = box.minX + unit * 0.55, top = box.minY + unit * 0.1
            g.draw(shade, at: CGPoint(x: left + 1, y: top + 1.6), anchor: .topLeading)
            g.draw(digits, at: CGPoint(x: left, y: top), anchor: .topLeading)
            // A small sight before the kills.
            let mark = CGPoint(x: left + unit * 0.27, y: top + big.height + small.height * 0.5 + unit * 0.02), r = unit * 0.24
            var sight = Path(ellipseIn: CGRect(x: mark.x - r * 0.62, y: mark.y - r * 0.62, width: r * 1.24, height: r * 1.24))
            for (dx, dy) in [(CGFloat(1), CGFloat(0)), (-1, 0), (0, 1), (0, -1)] {
                sight.move(to: CGPoint(x: mark.x + dx * r * 0.35, y: mark.y + dy * r * 0.35))
                sight.addLine(to: CGPoint(x: mark.x + dx * r, y: mark.y + dy * r))
            }
            g.stroke(sight, with: .color(cyan), lineWidth: max(1, unit * 0.07))
            g.draw(kills, at: CGPoint(x: left + unit * 0.72, y: mark.y), anchor: .leading)

            // A ship for each life left, the ghost of each one lost — the one just lost flashing red.
            let pod = CGRect(x: width - margin - unit * 4.6, y: margin, width: unit * 4.6, height: unit * 1.9)
            glass(g, pod)
            for life in 0..<JevShooter.lives {
                let c = CGPoint(x: pod.minX + unit * (0.9 + 1.4 * CGFloat(life)), y: pod.midY)
                if life < after.lives {
                    hero(g, at: c, size: unit * 1.2, bank: 0, burning: false)
                } else {
                    var ghost = Path()
                    for part in [Self.heroWings, Self.heroFins, Self.heroBody] { ghost.addPath(Self.place(part, c, unit * 1.2)) }
                    let lost = after.hurt && life == after.lives && since < 0.8
                    g.fill(ghost, with: .color(lost ? Color.red.opacity(0.35 + 0.35 * sin(since * 30)) : .white.opacity(0.1)))
                    g.stroke(ghost, with: .color(.white.opacity(0.22)), lineWidth: 0.8)
                }
            }
        }

        /// Whether the gun is loaded: a bar under the plane either side of its flame, lit when it can fire.
        private func gun(_ g: GraphicsContext, under plane: CGPoint, column: CGFloat, bottom: CGFloat) {
            var bar = Path()
            for side: CGFloat in [-1, 1] {
                bar.addRoundedRect(in: CGRect(x: plane.x + side * column * 0.24 - column * 0.12, y: bottom - 4.5, width: column * 0.24, height: 2.5), cornerSize: CGSize(width: 1.25, height: 1.25))
            }
            if after.gun == 0 {
                var glow = g
                glow.blendMode = .plusLighter
                glow.stroke(bar, with: .color(Color(red: 0.3, green: 0.8, blue: 1).opacity(0.4)), lineWidth: 3)
                g.fill(bar, with: .color(Color(red: 0.78, green: 0.97, blue: 1)))
            } else {
                g.fill(bar, with: .color(.white.opacity(0.18)))
            }
        }
    }
}
