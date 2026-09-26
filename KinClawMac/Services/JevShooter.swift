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

    /// Deep space, streaming stars, and everything in it gliding a tick at a time.
    fileprivate struct Scene {
        let before: Sky, after: Sky, t: Double, since: Double, now: Double, over: Bool

        func paint(_ g: inout GraphicsContext, _ size: CGSize) {
            let width = size.width, height = size.height
            let column = width / CGFloat(JevShooter.width), row = height / CGFloat(JevShooter.height)
            func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (CGFloat(x) + 0.5) * column, y: (CGFloat(y) + 0.5) * row) }

            g.fill(Path(CGRect(origin: .zero, size: size)),
                   with: .linearGradient(Gradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.12), Color(red: 0.07, green: 0.04, blue: 0.20),
                                                          Color(red: 0.10, green: 0.05, blue: 0.22)]),
                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))
            // Nebulae drifting down slowly, and three layers of stars at three speeds.
            for cloud in 0..<3 {
                let cx = width * CGFloat(0.2 + 0.3 * Double(cloud)), drift = CGFloat(now * 6).truncatingRemainder(dividingBy: height * 1.6)
                let cy = (height * CGFloat(0.3 * Double(cloud)) + drift).truncatingRemainder(dividingBy: height * 1.6) - height * 0.3
                let r = width * CGFloat(0.45 + 0.1 * Double(cloud))
                let tint = [Color(red: 0.4, green: 0.2, blue: 0.7), Color(red: 0.1, green: 0.3, blue: 0.7), Color(red: 0.6, green: 0.15, blue: 0.4)][cloud]
                g.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                       with: .radialGradient(Gradient(colors: [tint.opacity(0.22), .clear]), center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
            }
            for layer in 0..<3 {
                let speed = CGFloat(20 + 45 * layer), dot = CGFloat(0.8 + 0.7 * Double(layer))
                for star in 0..<(46 - 12 * layer) {
                    let sx = CGFloat(JevDraw.hash(star, layer) % 1000) / 1000 * width
                    let sy = (CGFloat(JevDraw.hash(star, layer + 10) % 1000) / 1000 * height + CGFloat(now) * speed).truncatingRemainder(dividingBy: height)
                    let twinkle = 0.45 + 0.35 * sin(now * 3 + Double(star))
                    g.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: dot, height: dot * (layer == 2 ? 2.2 : 1))), with: .color(.white.opacity(twinkle)))
                }
            }

            // Shots climb two rows a tick, bombs fall one: each is drawn where it was plus how far it has come.
            for shot in after.shots {
                let p = at(Double(shot.x), Double(shot.y) + 2 * (1 - t))
                let bolt = CGRect(x: p.x - 2, y: p.y - row * 0.35, width: 4, height: row * 0.7)
                g.fill(Path(roundedRect: bolt.insetBy(dx: -4, dy: -4), cornerRadius: 6), with: .color(Color.yellow.opacity(0.25)))
                g.fill(Path(roundedRect: bolt, cornerRadius: 2),
                       with: .linearGradient(Gradient(colors: [.white, .yellow, .orange]), startPoint: CGPoint(x: p.x, y: bolt.minY), endPoint: CGPoint(x: p.x, y: bolt.maxY)))
            }
            for bomb in after.bombs {
                let p = at(Double(bomb.x), Double(bomb.y) - 1 + t), r = row * 0.2
                g.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.2, y: p.y - r * 2.2, width: r * 4.4, height: r * 4.4)),
                       with: .radialGradient(Gradient(colors: [Color.orange.opacity(0.5), .clear]), center: p, startRadius: 0, endRadius: r * 2.2))
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .radialGradient(Gradient(colors: [.white, .yellow, .red]), center: p, startRadius: 0, endRadius: r))
            }
            let old = Dictionary(before.foes.map { ($0.serial, $0) }, uniquingKeysWith: { a, _ in a })
            for foe in after.foes {
                let from = old[foe.serial]
                let p = at(JevDraw.mix(Double(from?.x ?? foe.x), Double(foe.x), t), JevDraw.mix(Double(from?.y ?? foe.y - 1), Double(foe.y), t))
                switch foe.kind {
                case 0: jet(g, at: p, size: column * 0.95, pointing: .pi, colours: [Color(red: 1, green: 0.45, blue: 0.35), Color(red: 0.75, green: 0.1, blue: 0.12)])
                case 1: dart(g, at: p, size: column * 0.9, lean: Double(foe.dx) * 0.4)
                default: bomber(g, at: p, size: column * 1.25, glowing: foe.age % 4 == 3)
                }
            }
            for boom in after.booms { JevDraw.blast(g, at: at(Double(boom.x), Double(boom.y)), size: column * 0.55, age: since * 1.4) }

            // The plane, gliding to its column, its engines burning.
            let plane = at(JevDraw.mix(Double(before.x), Double(after.x), JevDraw.smooth(t)), Double(JevShooter.bottom))
            if !over {
                let flicker = CGFloat(0.75 + 0.25 * sin(now * 47))
                for side in [-1.0, 1.0] {
                    let base = CGPoint(x: plane.x + CGFloat(side) * column * 0.13, y: plane.y + column * 0.45)
                    let flame = Path { path in
                        path.move(to: CGPoint(x: base.x - column * 0.07, y: base.y))
                        path.addLine(to: CGPoint(x: base.x, y: base.y + column * 0.55 * flicker))
                        path.addLine(to: CGPoint(x: base.x + column * 0.07, y: base.y))
                    }
                    g.fill(flame, with: .linearGradient(Gradient(colors: [.white, .yellow, Color.orange.opacity(0)]),
                                                        startPoint: base, endPoint: CGPoint(x: base.x, y: base.y + column * 0.55)))
                }
                jet(g, at: plane, size: column * 1.05, pointing: 0, colours: [Color(red: 0.85, green: 0.97, blue: 1), Color(red: 0.15, green: 0.55, blue: 0.95)])
            } else {
                JevDraw.blast(g, at: plane, size: column * 0.9, age: since)
            }
            if after.hurt, since < 0.45 {
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.red.opacity(0.35 * (1 - since / 0.45))))
            }

            // Score, lives, and whether the gun is loaded.
            let unit = width / 22
            let box = CGRect(x: 10, y: 10, width: width - 20, height: unit * 2.6)
            JevDraw.panel(g, box)
            JevDraw.text(g, "\(after.score)", at: CGPoint(x: box.minX + unit * 0.7, y: box.midY), size: unit * 1.5, anchor: .leading)
            JevDraw.text(g, "打下 \(after.downed)", at: CGPoint(x: box.midX, y: box.midY), size: unit * 0.8, weight: .bold, colour: .white.opacity(0.8))
            for life in 0..<JevShooter.lives {
                let p = CGPoint(x: box.maxX - unit * (1 + 1.3 * CGFloat(life)), y: box.midY)
                if life < after.lives {
                    jet(g, at: p, size: unit * 1.0, pointing: 0, colours: [Color(red: 0.85, green: 0.97, blue: 1), Color(red: 0.15, green: 0.55, blue: 0.95)])
                } else {
                    g.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.white.opacity(0.25)))
                }
            }
            let ready = after.gun == 0
            g.fill(Path(roundedRect: CGRect(x: plane.x - column * 0.35, y: height - 6, width: column * 0.7, height: 3), cornerRadius: 1.5),
                   with: .color(ready ? Color.yellow.opacity(0.9) : Color.white.opacity(0.2)))
            if over { JevDraw.curtain(g, size, title: "被击落了！", detail: "得分 \(after.score) · 打下 \(after.downed) 架") }
        }

        /// A jet seen from above: fuselage, swept wings, tail. `pointing` 0 is up the screen.
        private func jet(_ g: GraphicsContext, at p: CGPoint, size: CGFloat, pointing: Double, colours: [Color]) {
            var g = g
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(pointing))
            let half: [(CGFloat, CGFloat)] = [(0, -0.5), (0.07, -0.33), (0.09, -0.08), (0.48, 0.14), (0.48, 0.22), (0.09, 0.16),
                                              (0.08, 0.34), (0.22, 0.45), (0.22, 0.5), (0, 0.44)]
            let body = Path { path in
                path.move(to: CGPoint(x: 0, y: -0.5 * size))
                for (x, y) in half.dropFirst() { path.addLine(to: CGPoint(x: x * size, y: y * size)) }
                for (x, y) in half.reversed().dropFirst() { path.addLine(to: CGPoint(x: -x * size, y: y * size)) }
                path.closeSubpath()
            }
            g.fill(body.offsetBy(dx: 2, dy: 3), with: .color(.black.opacity(0.35)))
            g.fill(body, with: .linearGradient(Gradient(colors: colours), startPoint: CGPoint(x: 0, y: -size * 0.5), endPoint: CGPoint(x: 0, y: size * 0.5)))
            g.stroke(body, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
            g.fill(Path(ellipseIn: CGRect(x: -size * 0.045, y: -size * 0.3, width: size * 0.09, height: size * 0.2)),
                   with: .linearGradient(Gradient(colors: [Color(red: 0.6, green: 0.9, blue: 1), Color(red: 0.05, green: 0.1, blue: 0.3)]),
                                         startPoint: CGPoint(x: 0, y: -size * 0.3), endPoint: CGPoint(x: 0, y: -size * 0.1)))
        }

        /// The swooper: a golden dart, banking the way it flies.
        private func dart(_ g: GraphicsContext, at p: CGPoint, size: CGFloat, lean: Double) {
            var g = g
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(.pi + lean))
            let body = Path { path in
                path.move(to: CGPoint(x: 0, y: -size * 0.5))
                path.addLine(to: CGPoint(x: size * 0.45, y: size * 0.42))
                path.addLine(to: CGPoint(x: 0, y: size * 0.22))
                path.addLine(to: CGPoint(x: -size * 0.45, y: size * 0.42))
                path.closeSubpath()
            }
            g.fill(body.offsetBy(dx: 2, dy: 3), with: .color(.black.opacity(0.35)))
            g.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 0.9, green: 0.55, blue: 0.05)]),
                                               startPoint: CGPoint(x: 0, y: -size * 0.5), endPoint: CGPoint(x: 0, y: size * 0.4)))
            g.fill(Path(ellipseIn: CGRect(x: -size * 0.06, y: -size * 0.12, width: size * 0.12, height: size * 0.12)), with: .color(Color(red: 0.2, green: 0.05, blue: 0)))
        }

        /// The bomber: broad and slow, its bomb bay glowing just before it drops.
        private func bomber(_ g: GraphicsContext, at p: CGPoint, size: CGFloat, glowing: Bool) {
            var g = g
            g.translateBy(x: p.x, y: p.y)
            if glowing {
                g.fill(Path(ellipseIn: CGRect(x: -size * 0.35, y: -size * 0.1, width: size * 0.7, height: size * 0.7)),
                       with: .radialGradient(Gradient(colors: [Color.orange.opacity(0.6), .clear]), center: CGPoint(x: 0, y: size * 0.25), startRadius: 0, endRadius: size * 0.35))
            }
            let wing = Path(roundedRect: CGRect(x: -size * 0.5, y: -size * 0.12, width: size, height: size * 0.22), cornerRadius: size * 0.1)
            let hull = Path(roundedRect: CGRect(x: -size * 0.13, y: -size * 0.42, width: size * 0.26, height: size * 0.84), cornerRadius: size * 0.12)
            for part in [wing, hull] { g.fill(part.offsetBy(dx: 2, dy: 3), with: .color(.black.opacity(0.35))) }
            let purple = Gradient(colors: [Color(red: 0.75, green: 0.55, blue: 1), Color(red: 0.35, green: 0.12, blue: 0.6)])
            g.fill(wing, with: .linearGradient(purple, startPoint: CGPoint(x: 0, y: -size * 0.12), endPoint: CGPoint(x: 0, y: size * 0.1)))
            g.fill(hull, with: .linearGradient(purple, startPoint: CGPoint(x: -size * 0.13, y: 0), endPoint: CGPoint(x: size * 0.13, y: 0)))
            for engine in [-0.36, -0.2, 0.2, 0.36] {
                g.fill(Path(ellipseIn: CGRect(x: size * CGFloat(engine) - 3, y: -size * 0.02, width: 6, height: 6)), with: .color(Color(red: 1, green: 0.4, blue: 0.3)))
            }
            g.fill(Path(ellipseIn: CGRect(x: -size * 0.06, y: size * 0.18, width: size * 0.12, height: size * 0.14)), with: .color(Color(red: 0.1, green: 0.05, blue: 0.2)))
        }
    }
}
