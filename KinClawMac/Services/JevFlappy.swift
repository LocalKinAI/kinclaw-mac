import SwiftUI

/// 像素鸟 — Flappy Bird, one tick a question: flap or glide.
///
/// The smallest choice there is, and the one that decides everything: a flap
/// sends the bird up two rows, and gliding it falls a row faster each tick.
/// The bird's whole future is arithmetic, so the program does the arithmetic
/// — where each choice puts it, where gliding on from there would meet the
/// next pipe, and whether any way of flapping can still get it through, with
/// how much room to spare. Which margin to trust is the player's judgment. The
/// evaluator that plays looks past the next pipe to the one after it; the
/// words stop at the next.
@MainActor
final class JevFlappy: JevGame {
    let id = "flappy", title = "像素鸟", symbol = "bird.fill"
    let rules = "Flappy Bird, seen from the side. The bird flies right one column a tick past pipes that stand between the ground and the sky, each with one gap four rows tall. Each tick the bird either flaps, which sends it up two rows, or glides, and falls: a row faster every tick, two rows a tick at most. Heights count from the ground, 0, to the sky, 12. Touching a pipe or the ground ends the game; the sky only stops the bird. The score is the number of pipes passed."
    let question = "Should the bird flap or glide this tick, to pass as many pipes as possible?"
    let howToJudge = "Compare the options in this order. First: never choose an option that hits a pipe or the ground, nor one from which the next pipe can no longer be passed. Second: prefer the option from which the next pipe can be passed with more room to spare — through the middle of its gap rather than along an edge. Third: keep near the height of the gap rather than far above or below it."

    nonisolated static let columns = 15, sky = 12, gap = 4, bird = 3
    let clock: Double? = 0.2
    let controls = "空格或 ↑ 扇一下翅膀 · 不按就往下掉"

    /// The bird and the pipes. Rows count down from the top of the sky, as drawn;
    /// the words speak of heights, which count up from the ground.
    fileprivate struct Flight {
        var y = 5, v = 0, x = 0, passed = 0
        /// Each pipe's column and the top row of its gap.
        var pipes: [(x: Int, top: Int)] = []
        enum Fate { case flying, pipe, ground }

        func blocked(_ column: Int, _ row: Int) -> Bool {
            guard let pipe = pipes.first(where: { $0.x == column }) else { return false }
            return row < pipe.top || row >= pipe.top + JevFlappy.gap
        }

        /// Up or down within the column the bird is in, then one column on.
        mutating func step(flap: Bool) -> Fate {
            let from = y
            v = flap ? -2 : min(v + 1, 2)
            y += v
            if y < 0 { y = 0; v = 0 }
            if y >= JevFlappy.sky { y = JevFlappy.sky; return .ground }
            for row in min(from, y)...max(from, y) where blocked(x, row) { return .pipe }
            x += 1
            if blocked(x, y) { return .pipe }
            if pipes.contains(where: { $0.x == x - 1 }) { passed += 1 }
            return .flying
        }

        /// The most room to spare — rows between the bird and the nearer edge of
        /// each gap as it goes in — with which some way of flapping gets it past
        /// every pipe before column `until`; nil when none does.
        func room(until: Int, memo: inout [Int: Int?]) -> Int? {
            if x >= until { return 99 }
            let key = (x * 64 + y + 16) * 8 + v + 3
            if let known = memo[key] { return known }
            var best: Int?
            for flap in [false, true] {
                var next = self
                guard next.step(flap: flap) == .flying else { continue }
                var here = 99
                if let pipe = next.pipes.first(where: { $0.x == next.x }) { here = min(next.y - pipe.top, pipe.top + JevFlappy.gap - 1 - next.y) }
                guard let rest = next.room(until: until, memo: &memo) else { continue }
                best = max(best ?? -1, min(here, rest))
            }
            memo[key] = best
            return best
        }

        /// The pipes still ahead of the bird, or the one it is in, nearest first.
        var ahead: [(x: Int, top: Int)] { pipes.filter { $0.x >= x }.sorted { $0.x < $1.x } }
    }

    private var flight = Flight()
    /// The flight before the last tick, for the picture to glide from.
    private var previous = Flight()
    private(set) var ticked = Date.distantPast
    private var dice = JevDice(seed: 1)
    private var laid = 0
    private(set) var over = false
    private var fate = Flight.Fate.flying

    var score: Int { flight.passed }
    var status: String {
        (over ? (fate == .ground ? "掉到地上了 · " : "撞上了管子 · ") : "") + "过了 \(flight.passed) 根管子 · 飞了 \(flight.x) 格 · 高度 \(max(Self.sky - flight.y, 0))"
    }
    var situation: String {
        let motion = flight.v < 0 ? "rising" : flight.v == 0 ? "level" : "falling \(flight.v) row\(flight.v == 1 ? "" : "s") a tick"
        return "the bird is at height \(Self.sky - flight.y), \(motion); \(flight.passed) pipes passed"
    }
    var position: String {
        (0...Self.sky).map { row in
            (0..<Self.columns).map { col -> String in
                let at = flight.x - Self.bird + col
                if col == Self.bird, row == flight.y { return "B" }
                if row == Self.sky { return "=" }
                return flight.blocked(at, row) ? "#" : "."
            }.joined()
        }.joined(separator: "\n") + "\n(B is the bird, flying right; # a pipe; = the ground. The top row is height 12, the row above the ground height 1.)"
    }

    private static let air = Color(red: 0.55, green: 0.80, blue: 0.95), pipe = Color(red: 0.36, green: 0.70, blue: 0.24)
    private static let sand = Color(red: 0.87, green: 0.76, blue: 0.52), sand2 = Color(red: 0.80, green: 0.68, blue: 0.44)
    var grid: [[JevCell]] {
        (0...Self.sky).map { row in
            (0..<Self.columns).map { col -> JevCell in
                let at = flight.x - Self.bird + col
                if col == Self.bird, row == flight.y { return JevCell(colour: row == Self.sky ? Self.sand : Self.air, text: over ? "💥" : "🐥", big: true) }
                if row == Self.sky { return JevCell(colour: (at % 2 + 2) % 2 == 0 ? Self.sand : Self.sand2) }
                if flight.blocked(at, row) { return JevCell(colour: Self.pipe) }
                let cloud = row < 5 && ((at * 7 + row * 13) % 41 + 41) % 41 == 0
                return JevCell(colour: Self.air, text: cloud ? "☁️" : "", big: true)
            }
        }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        flight = Flight(); dice = JevDice(seed: seed); laid = 0; over = false; fate = .flying
        lay()
        previous = flight; ticked = .distantPast
    }

    /// Pipes ahead, closer together as the game goes on, each gap within reach of the last.
    private func lay() {
        while (flight.pipes.last?.x ?? 0) < flight.x + Self.columns + 2 {
            let spacing = laid < 15 ? 7 : laid < 40 ? 6 : 5
            let last = flight.pipes.last
            var top = 1 + dice.below(Self.sky - Self.gap - 1)
            if let last { top = min(max(top, last.top - spacing), last.top + spacing) }
            flight.pipes.append(((last?.x ?? flight.x + 8) + (last == nil ? 0 : spacing), top))
            laid += 1
        }
        let behind = flight.x - Self.bird - 1
        flight.pipes.removeAll { $0.x < behind }
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        return [false, true].enumerated().map { index, flap in
            var next = flight
            let fate = next.step(flap: flap)
            var merit = -10_000.0
            if fate == .flying, let first = next.ahead.first {
                var near: [Int: Int?] = [:], far: [Int: Int?] = [:]
                let one = next.room(until: first.x + 1, memo: &near)
                let two = next.ahead.count > 1 ? next.room(until: next.ahead[1].x + 1, memo: &far) : one
                let middle = Double(first.top) + Double(Self.gap - 1) / 2
                merit = (one.map { Double(min($0, 3)) * 10 } ?? -5_000) + (two.map { Double(min($0, 3)) * 3 } ?? -2_000)
                    - abs(Double(next.y) - middle) * 0.5
            }
            return JevOption(id: String(format: "p%02d", index + 1), label: describe(flap, next, fate), merit: merit, move: index)
        }
    }

    func play(_ option: JevOption) {
        guard !over, option.move == 0 || option.move == 1 else { return }
        previous = flight
        fate = flight.step(flap: option.move == 1)
        ticked = Date()
        if fate != .flying { over = true }
        lay()
    }

    /// Flap or glide, in words: where it puts the bird, and what it leaves.
    private func describe(_ flap: Bool, _ next: Flight, _ fate: Flight.Fate) -> String {
        let height = Self.sky - next.y
        let doing = flap ? "flap: the bird rises to height \(height)"
            : next.v > 0 ? "glide: the bird drops to height \(height)" : next.v == 0 ? "glide: the bird hangs at height \(height)" : "glide: the bird still rises, to height \(height)"
        if fate == .ground { return "glide: the bird hits the ground: the game ends" }
        if fate == .pipe { return doing + ": it hits the pipe: the game ends" }
        guard let pipe = next.ahead.first else { return doing }
        let low = Self.sky - (pipe.top + Self.gap - 1), high = Self.sky - pipe.top, distance = pipe.x - next.x
        var parts = [distance == 0 ? "it is inside the pipe's gap (heights \(low) to \(high))"
                     : "the next pipe is \(distance) column\(distance == 1 ? "" : "s") ahead, its gap at heights \(low) to \(high)"]
        if distance > 0 {
            // Where gliding on from there would meet the pipe.
            var drift = next, fell = Flight.Fate.flying
            while drift.x < pipe.x, fell == .flying { fell = drift.step(flap: false) }
            let meets = Self.sky - drift.y
            parts.append(fell == .ground ? "gliding on from there it would hit the ground before the pipe"
                         : meets > high ? "gliding on from there it would meet the pipe \(meets - high) above the gap"
                         : meets < low ? "gliding on from there it would meet the pipe \(low - meets) below the gap"
                         : "gliding on from there it would meet the pipe inside the gap")
        }
        var memo: [Int: Int?] = [:]
        if let room = next.room(until: pipe.x + 1, memo: &memo) {
            parts.append(room == 0 ? "from there it can still get through, but only skimming an edge of the gap"
                         : "from there it can still get through with \(room) row\(room == 1 ? "" : "s") to spare")
        } else { parts.append("from there it can no longer get through the pipe: the game ends there") }
        return doing + ": " + parts.joined(separator: "; ")
    }

    // MARK: Played by a person

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        // A press, not a hold: a bird does not flap for as long as a key is down.
        let flap = pressed.contains(.space) || pressed.contains(.up)
        return options.first(where: { $0.move == (flap ? 1 : 0) }).map { .choose($0) } ?? .nothing
    }
}

// MARK: - The picture

extension JevFlappy: JevPainted {
    var aspect: Double { 1.36 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = Scene(before: previous, after: flight, t: t, since: since, now: now, over: over, grounded: fate == .ground)
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    /// A summer afternoon: the sun at the top left, two rows of clouds, a far
    /// city and a near one, and trees, each rolling past at its own speed; the
    /// pipes and the ground at the bird's. Everything is lit from the sun, and
    /// its shadows fall down and to the right.
    fileprivate struct Scene {
        let before: Flight, after: Flight, t: Double, since: Double, now: Double, over: Bool, grounded: Bool

        func paint(_ g: inout GraphicsContext, _ size: CGSize) {
            let width = size.width, height = size.height
            let column = width / CGFloat(JevFlappy.columns), row = height / CGFloat(JevFlappy.sky + 1)
            let camera = JevDraw.mix(Double(before.x), Double(after.x), t)
            func x(_ world: Double) -> CGFloat { (CGFloat(world - camera) + CGFloat(JevFlappy.bird) + 0.5) * column }
            func y(_ row: Double) -> CGFloat { (CGFloat(row) + 0.5) * height / CGFloat(JevFlappy.sky + 1) }
            let ground = CGFloat(JevFlappy.sky) * row, turf = row * 0.3, k = width / 640
            let rolled = camera * Double(column)           // how far the world has gone by, in points

            sky(g, size, ground: ground)
            clouds(g, size, rolled: rolled * 0.06 + now * 2.5 * Double(k), far: true, k: k)
            flock(g, size, rolled: rolled * 0.1, k: k)
            city(g, size, ground: ground, rolled: rolled * 0.14, near: false, k: k)
            clouds(g, size, rolled: rolled * 0.2 + now * 5 * Double(k), far: false, k: k)
            city(g, size, ground: ground, rolled: rolled * 0.3, near: true, k: k)
            trees(g, size, ground: ground, rolled: rolled * 0.62, k: k)

            // The pipes, with a lip at each end of the gap.
            let pipes = after.pipes.filter { abs(x(Double($0.x)) - width / 2) < width / 2 + column * 1.2 }
            for pipe in pipes {
                self.pipe(g, centre: x(Double(pipe.x)), top: CGFloat(pipe.top) * row, bottom: CGFloat(pipe.top + JevFlappy.gap) * row,
                          ground: ground, row: row, column: column, k: k)
            }
            land(g, size, ground: ground, turf: turf, column: column, camera: camera, k: k)
            // Each pipe's shadow on the grass, falling away from the sun.
            var shadows = Path()
            for pipe in pipes {
                let right = x(Double(pipe.x)) + column * 0.45
                shadows.move(to: CGPoint(x: right, y: ground))
                shadows.addLine(to: CGPoint(x: right + column * 0.42, y: ground))
                shadows.addLine(to: CGPoint(x: right + column * 0.72, y: ground + turf))
                shadows.addLine(to: CGPoint(x: right, y: ground + turf))
                shadows.closeSubpath()
            }
            g.fill(shadows, with: .color(Color(red: 0.1, green: 0.25, blue: 0.05).opacity(0.22)))

            // The bird, nose up when it climbs and down when it falls, its wing beating.
            let level = JevDraw.mix(Double(before.y), Double(after.y), t)
            let speed = JevDraw.mix(Double(before.v), Double(after.v), t)
            let tilt = over ? 1.3 : min(max(speed * 0.32, -0.5), 1.1)
            let flapping = after.v < 0 || before.v < 0
            let body = column * 0.98
            let bird = CGPoint(x: x(camera), y: y(min(level, Double(JevFlappy.sky) - 0.35)))
            // Its shadow on the grass, smaller and fainter the higher it flies.
            let up = min(max((ground - bird.y) / ground, 0), 1)
            let blob = body * (0.85 - 0.45 * up)
            g.fill(Path(ellipseIn: CGRect(x: bird.x + 3 * k - blob / 2, y: ground + turf * 0.5 - turf * 0.22, width: blob, height: turf * 0.44)),
                   with: .color(Color(red: 0.1, green: 0.25, blue: 0.05).opacity(0.3 * Double(1 - 0.75 * up))))
            if after.v == -2, !over, since < 0.4 { puffs(g, behind: bird, size: body, age: since) }
            drawBird(g, at: bird, size: body, tilt: tilt, wing: flapping ? sin(now * 28) * 0.85 : -0.12 + 0.06 * sin(now * 5), dead: over)
            if over, !grounded {
                JevDraw.blast(g, at: CGPoint(x: bird.x + column * 0.4, y: y(level)), size: column * 0.4, age: since * 1.5)
                feathers(g, from: bird, size: body, age: since)
            }
            if over, grounded {
                dust(g, at: CGPoint(x: bird.x, y: ground + turf * 0.3), size: body, age: since)
                if since > 0.25 { dizzy(g, over: bird, size: body) }
            }

            // The score, jumping when a pipe is passed.
            let pop = after.passed > before.passed ? max(0, 1 - since / 0.35) : 0
            number(g, "\(after.passed)", at: CGPoint(x: width / 2, y: height * 0.12), size: height * 0.11 * CGFloat(1 + 0.28 * pop * pop))
            if over { JevDraw.curtain(g, size, title: grounded ? "掉下去了！" : "撞上管子了！", detail: "过了 \(after.passed) 根管子") }
        }

        private func unit(_ a: Int, _ b: Int) -> Double { Double(JevDraw.hash(a, b) % 1000) / 1000 }

        // MARK: The sky

        private func sky(_ g: GraphicsContext, _ size: CGSize, ground: CGFloat) {
            let width = size.width, height = size.height
            g.fill(Path(CGRect(origin: .zero, size: size)),
                   with: .linearGradient(Gradient(stops: [.init(color: Color(red: 0.2, green: 0.5, blue: 0.9), location: 0),
                                                          .init(color: Color(red: 0.42, green: 0.72, blue: 0.98), location: 0.42),
                                                          .init(color: Color(red: 0.74, green: 0.89, blue: 1), location: 0.78),
                                                          .init(color: Color(red: 1, green: 0.92, blue: 0.78), location: 1)]),
                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: ground)))
            // The sun, top left, its rays turning slowly.
            let sun = CGPoint(x: width * 0.12, y: height * 0.14), r = height * 0.058
            var rays = Path()
            for i in 0..<12 {
                let a = now * 0.05 + Double(i) * .pi / 6
                rays.move(to: sun)
                rays.addLine(to: CGPoint(x: sun.x + CGFloat(cos(a - 0.07)) * r * 5.5, y: sun.y + CGFloat(sin(a - 0.07)) * r * 5.5))
                rays.addLine(to: CGPoint(x: sun.x + CGFloat(cos(a + 0.07)) * r * 5.5, y: sun.y + CGFloat(sin(a + 0.07)) * r * 5.5))
                rays.closeSubpath()
            }
            g.fill(rays, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)]), center: sun, startRadius: r, endRadius: r * 5.5))
            g.fill(Path(ellipseIn: CGRect(x: sun.x - r * 3.4, y: sun.y - r * 3.4, width: r * 6.8, height: r * 6.8)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.85).opacity(0.9), Color(red: 1, green: 0.93, blue: 0.62).opacity(0.3),
                                                           Color(red: 1, green: 0.93, blue: 0.62).opacity(0)]), center: sun, startRadius: r * 0.8, endRadius: r * 3.4))
            g.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [.white, Color(red: 1, green: 0.96, blue: 0.72)]), center: sun, startRadius: 0, endRadius: r))
        }

        /// A cloud's puffs: x, y and radius, in units of the cloud's size.
        private static let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-0.95, 0.12, 0.42), (-0.45, -0.16, 0.58), (0.15, -0.32, 0.7), (0.72, -0.06, 0.55), (1.12, 0.16, 0.38)]

        private func clouds(_ g: GraphicsContext, _ size: CGSize, rolled: Double, far: Bool, k: CGFloat) {
            let spacing = Double((far ? 170 : 270) * k)
            let first = Int(floor(rolled / spacing)) - 1
            for slot in first..<(first + Int(Double(size.width) / spacing) + 3) {
                let salt = far ? 40 : 60
                if !far, unit(slot, salt + 4) < 0.2 { continue }
                let s = (far ? 15 : 28) * k * CGFloat(0.75 + 0.5 * unit(slot, salt + 3))
                let cx = CGFloat(Double(slot) * spacing - rolled + unit(slot, salt + 1) * spacing * 0.5)
                let cy = size.height * CGFloat((far ? 0.08 : 0.13) + (far ? 0.2 : 0.28) * unit(slot, salt + 2))
                var cloud = Path()
                for (dx, dy, r) in Self.puffs { cloud.addEllipse(in: CGRect(x: cx + (dx - r) * s, y: cy + (dy - r) * s, width: 2 * r * s, height: 2 * r * s)) }
                cloud.addRoundedRect(in: CGRect(x: cx - 1.2 * s, y: cy - 0.05 * s, width: 2.4 * s, height: 0.6 * s), cornerSize: CGSize(width: 0.3 * s, height: 0.3 * s))
                // Shade underneath, down and to the right, then the cloud: white on top, blue-grey below.
                g.fill(cloud.applying(CGAffineTransform(translationX: 0.08 * s, y: 0.12 * s)), with: .color(Color(red: 0.45, green: 0.6, blue: 0.85).opacity(far ? 0.12 : 0.2)))
                g.fill(cloud, with: .linearGradient(Gradient(colors: [Color.white.opacity(far ? 0.8 : 1), Color(red: 0.84, green: 0.9, blue: 0.99).opacity(far ? 0.8 : 1)]),
                                                    startPoint: CGPoint(x: cx, y: cy - s), endPoint: CGPoint(x: cx, y: cy + 0.55 * s)))
            }
        }

        /// Three birds far off, drifting along and flapping lazily.
        private func flock(_ g: GraphicsContext, _ size: CGSize, rolled: Double, k: CGFloat) {
            let lap = Double(size.width + 80 * k)
            var birds = Path()
            for i in 0..<3 {
                let along = (now * 11 * Double(k) + rolled + Double(i) * lap * 0.37).truncatingRemainder(dividingBy: lap)
                let c = CGPoint(x: size.width + 40 * k - CGFloat(along) - CGFloat(i % 2) * 14 * k,
                                y: size.height * CGFloat(0.24 + 0.045 * Double(i)) + CGFloat(sin(now * 1.3 + Double(i) * 2)) * 4 * k)
                let span = (5 + CGFloat(i % 2)) * k, lift = CGFloat(sin(now * 8 + Double(i) * 1.7)) * 3 * k
                birds.move(to: CGPoint(x: c.x - span, y: c.y - lift))
                birds.addQuadCurve(to: c, control: CGPoint(x: c.x - span * 0.45, y: c.y - lift - 2 * k))
                birds.addQuadCurve(to: CGPoint(x: c.x + span, y: c.y - lift), control: CGPoint(x: c.x + span * 0.45, y: c.y - lift - 2 * k))
            }
            g.stroke(birds, with: .color(Color(red: 0.2, green: 0.3, blue: 0.48).opacity(0.55)), style: StrokeStyle(lineWidth: 1.4 * k, lineCap: .round, lineJoin: .round))
        }

        /// A skyline, far and pale or near with lit windows, blocks of it standing along the ground.
        private func city(_ g: GraphicsContext, _ size: CGSize, ground: CGFloat, rolled: Double, near: Bool, k: CGFloat) {
            let slot = Double((near ? 46 : 32) * k), salt = near ? 300 : 500
            let first = Int(floor(rolled / slot)) - 1
            var blocks = Path(), masts = Path(), beacons = Path(), lit = Path(), shade = Path(), windows = Path(), glass = Path()
            for i in first..<(first + Int(Double(size.width) / slot) + 3) {
                func u(_ n: Int) -> Double { unit(i, salt + n) }
                let w = CGFloat(slot) * CGFloat(near ? 0.62 + 0.3 * u(1) : 0.85 + 0.45 * u(1))
                let tall = ground * CGFloat(near ? 0.13 + 0.3 * u(2) * u(2) + 0.06 * u(5) : 0.26 + 0.32 * u(2))
                let left = CGFloat(Double(i) * slot - rolled) + (CGFloat(slot) - w) * CGFloat(u(3)) * (near ? 1 : 0.5)
                let top = ground - tall
                blocks.addRect(CGRect(x: left, y: top, width: w, height: tall + 1))
                switch JevDraw.hash(i, salt + 9) % 6 {
                case 0:     // a narrower storey on top
                    blocks.addRect(CGRect(x: left + w * 0.2, y: top - tall * 0.12, width: w * 0.6, height: tall * 0.12 + 1))
                case 1:     // a mast with a light
                    masts.addRect(CGRect(x: left + w * 0.5 - k, y: top - 16 * k, width: 2 * k, height: 16 * k))
                    beacons.addEllipse(in: CGRect(x: left + w * 0.5 - 2.3 * k, y: top - 18.5 * k, width: 4.6 * k, height: 4.6 * k))
                case 2:     // a water tank on legs
                    blocks.addRoundedRect(in: CGRect(x: left + w * 0.58, y: top - 12 * k, width: 9 * k, height: 7 * k), cornerSize: CGSize(width: 2 * k, height: 2 * k))
                    masts.addRect(CGRect(x: left + w * 0.58 + 1.5 * k, y: top - 5 * k, width: 1.2 * k, height: 5 * k))
                    masts.addRect(CGRect(x: left + w * 0.58 + 6.3 * k, y: top - 5 * k, width: 1.2 * k, height: 5 * k))
                case 3:     // a pitched roof
                    blocks.move(to: CGPoint(x: left, y: top + 0.5))
                    blocks.addLine(to: CGPoint(x: left + w / 2, y: top - w * 0.28))
                    blocks.addLine(to: CGPoint(x: left + w, y: top + 0.5))
                    blocks.closeSubpath()
                default: break
                }
                guard near else { continue }
                lit.addRect(CGRect(x: left, y: top, width: max(2 * k, w * 0.1), height: tall))
                shade.addRect(CGRect(x: left + w * 0.86, y: top, width: w * 0.14, height: tall))
                let columns = max(1, Int((w - 6 * k) / (7 * k))), floors = max(0, Int((tall - 12 * k) / (9 * k)))
                let gap = (w - CGFloat(columns) * 3.5 * k) / CGFloat(columns + 1)
                for f in 0..<floors {
                    for c in 0..<columns {
                        let pane = CGRect(x: left + gap + CGFloat(c) * (3.5 * k + gap), y: top + 7 * k + CGFloat(f) * 9 * k, width: 3.5 * k, height: 5 * k)
                        switch JevDraw.hash(i * 64 + c, f + salt) % 6 {
                        case 0: windows.addRect(pane)
                        case 1, 2, 3: glass.addRect(pane)
                        default: break
                        }
                    }
                }
            }
            let body = near ? Color(red: 0.5, green: 0.62, blue: 0.82) : Color(red: 0.71, green: 0.8, blue: 0.93)
            g.fill(blocks, with: .color(body))
            g.fill(masts, with: .color(body))
            if near {
                g.fill(lit, with: .color(Color(red: 0.62, green: 0.74, blue: 0.93)))
                g.fill(shade, with: .color(Color(red: 0.42, green: 0.53, blue: 0.75)))
                g.fill(glass, with: .color(Color(red: 0.8, green: 0.9, blue: 1).opacity(0.55)))
                g.fill(windows, with: .color(Color(red: 1, green: 0.88, blue: 0.55)))
            }
            g.fill(beacons, with: .color(Color(red: 1, green: 0.3, blue: 0.25).opacity(sin(now * 3 + (near ? 0 : 1.5)) > 0 ? 0.95 : 0.3)))
        }

        /// Bushes and round trees along the ground, rimmed dark and lit on top.
        private func trees(_ g: GraphicsContext, _ size: CGSize, ground: CGFloat, rolled: Double, k: CGFloat) {
            let spacing = Double(27 * k)
            let first = Int(floor(rolled / spacing)) - 2
            var crowns = Path(), rims = Path(), shine = Path(), trunks = Path()
            for i in first..<(first + Int(Double(size.width) / spacing) + 5) {
                let cx = CGFloat(Double(i) * spacing - rolled)
                let crown: CGRect
                if JevDraw.hash(i, 709) % 6 == 0 {
                    let r = (12 + 5 * CGFloat(unit(i, 702))) * k, trunk = (18 + 8 * CGFloat(unit(i, 703))) * k
                    trunks.addRect(CGRect(x: cx - 2 * k, y: ground - trunk, width: 4 * k, height: trunk))
                    crown = CGRect(x: cx - r, y: ground - trunk - r * 1.5, width: 2 * r, height: 2 * r * 1.08)
                } else {
                    let r = (13 + 11 * CGFloat(unit(i, 701))) * k
                    crown = CGRect(x: cx - r, y: ground - r * 1.28, width: 2 * r, height: 2 * r)
                }
                crowns.addEllipse(in: crown)
                rims.addEllipse(in: crown.insetBy(dx: -1.6 * k, dy: -1.6 * k))
                shine.addEllipse(in: CGRect(x: crown.minX + crown.width * 0.14, y: crown.minY + crown.height * 0.08, width: crown.width * 0.52, height: crown.height * 0.4))
            }
            g.fill(rims, with: .color(Color(red: 0.19, green: 0.44, blue: 0.2)))
            g.fill(trunks, with: .color(Color(red: 0.48, green: 0.32, blue: 0.18)))
            g.fill(crowns, with: .color(Color(red: 0.32, green: 0.65, blue: 0.3)))
            // Each light patch lies inside its own crown, so it needs no clipping (which would cost more than all the rest).
            g.fill(shine, with: .color(Color(red: 0.48, green: 0.8, blue: 0.38)))
        }

        // MARK: Pipes and ground

        /// Round green pipe: dark at the edges, a bright stripe of sun down its left third.
        private static let pipeGreen = Gradient(stops: [.init(color: Color(red: 0.22, green: 0.5, blue: 0.11), location: 0),
                                                        .init(color: Color(red: 0.52, green: 0.84, blue: 0.29), location: 0.1),
                                                        .init(color: Color(red: 0.76, green: 0.97, blue: 0.5), location: 0.24),
                                                        .init(color: Color(red: 0.53, green: 0.84, blue: 0.29), location: 0.42),
                                                        .init(color: Color(red: 0.38, green: 0.7, blue: 0.2), location: 0.7),
                                                        .init(color: Color(red: 0.23, green: 0.49, blue: 0.1), location: 0.9),
                                                        .init(color: Color(red: 0.15, green: 0.36, blue: 0.07), location: 1)])

        private func pipe(_ g: GraphicsContext, centre: CGFloat, top: CGFloat, bottom: CGFloat, ground: CGFloat, row: CGFloat, column: CGFloat, k: CGFloat) {
            let body = column * 0.9, lip = column * 1.14, cap = row * 0.56
            let edge = Color(red: 0.07, green: 0.21, blue: 0.04), rim = max(1.5, 2 * k)
            func shaded(_ r: CGRect) -> GraphicsContext.Shading { .linearGradient(Self.pipeGreen, startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)) }
            for part in [CGRect(x: centre - body / 2, y: -rim, width: body, height: top + rim), CGRect(x: centre - body / 2, y: bottom, width: body, height: ground - bottom + rim)] {
                g.fill(Path(part), with: shaded(part))
                g.fill(Path(CGRect(x: part.minX + part.width * 0.19, y: part.minY, width: part.width * 0.05, height: part.height)), with: .color(.white.opacity(0.4)))
                g.stroke(Path(part), with: .color(edge), lineWidth: rim)
            }
            // The lower pipe stands in its lip's shadow.
            let under = CGRect(x: centre - body / 2 + rim / 2, y: bottom + cap, width: body - rim, height: row * 0.32)
            g.fill(Path(under), with: .linearGradient(Gradient(colors: [.black.opacity(0.3), .black.opacity(0)]),
                                                      startPoint: CGPoint(x: 0, y: under.minY), endPoint: CGPoint(x: 0, y: under.maxY)))
            for end in [CGRect(x: centre - lip / 2, y: top - cap, width: lip, height: cap), CGRect(x: centre - lip / 2, y: bottom, width: lip, height: cap)] {
                let shape = Path(roundedRect: end, cornerRadius: 3 * k)
                g.fill(shape, with: shaded(end))
                g.fill(Path(CGRect(x: end.minX + end.width * 0.19, y: end.minY + rim, width: end.width * 0.05, height: end.height - 2 * rim)), with: .color(.white.opacity(0.5)))
                g.fill(Path(CGRect(x: end.minX + rim, y: end.minY + rim * 0.6, width: end.width - 2 * rim, height: 2.2 * k)), with: .color(.white.opacity(0.35)))
                g.fill(Path(CGRect(x: end.minX + rim, y: end.maxY - rim * 0.6 - 2.6 * k, width: end.width - 2 * rim, height: 2.6 * k)), with: .color(.black.opacity(0.18)))
                g.stroke(shape, with: .color(edge), lineWidth: rim)
            }
        }

        /// Sand under a lip of turf, striped and pebbled, rolling at the bird's speed.
        private func land(_ g: GraphicsContext, _ size: CGSize, ground: CGFloat, turf: CGFloat, column: CGFloat, camera: Double, k: CGFloat) {
            let width = size.width, height = size.height
            let shift = CGFloat(camera) * column
            g.fill(Path(CGRect(x: 0, y: ground, width: width, height: height - ground)),
                   with: .linearGradient(Gradient(colors: [Color(red: 0.92, green: 0.83, blue: 0.58), Color(red: 0.8, green: 0.66, blue: 0.42)]),
                                         startPoint: CGPoint(x: 0, y: ground + turf), endPoint: CGPoint(x: 0, y: height)))
            let stripe = column * 0.6
            var stripes = Path()
            var sx = -(shift.truncatingRemainder(dividingBy: stripe)) - stripe
            while sx < width + stripe {
                stripes.move(to: CGPoint(x: sx, y: ground + turf))
                stripes.addLine(to: CGPoint(x: sx + stripe * 0.5, y: ground + turf))
                stripes.addLine(to: CGPoint(x: sx + stripe * 0.2, y: height))
                stripes.addLine(to: CGPoint(x: sx - stripe * 0.3, y: height))
                stripes.closeSubpath()
                sx += stripe
            }
            g.fill(stripes, with: .color(Color(red: 0.74, green: 0.6, blue: 0.36).opacity(0.3)))
            // Pebbles, a few to a column, each with a glint of sun on its top left.
            var pebbles = Path(), glints = Path()
            let firstColumn = Int(floor(camera)) - JevFlappy.bird - 1
            for c in firstColumn...(firstColumn + JevFlappy.columns + 2) {
                for n in 0..<3 {
                    let h = JevDraw.hash(c, n + 900)
                    let px = (CGFloat(Double(c) - camera) + CGFloat(Double(h % 100) / 100) + CGFloat(JevFlappy.bird) + 0.5) * column
                    let py = ground + turf + 6 * k + CGFloat(h / 100 % 100) / 100 * max(height - ground - turf - 10 * k, 1)
                    let r = (1.3 + CGFloat(h / 10_000 % 10) / 10 * 1.6) * k
                    pebbles.addEllipse(in: CGRect(x: px - r, y: py - r * 0.7, width: 2 * r, height: 1.4 * r))
                    glints.addEllipse(in: CGRect(x: px - r * 0.65, y: py - r * 0.55, width: r * 0.7, height: r * 0.5))
                }
            }
            g.fill(pebbles, with: .color(Color(red: 0.6, green: 0.47, blue: 0.3).opacity(0.75)))
            g.fill(glints, with: .color(.white.opacity(0.5)))
            // The turf: tufts hanging over the sand, a bright top, a dark seam where it meets the air.
            g.fill(Path(CGRect(x: 0, y: ground + turf, width: width, height: 6 * k)),
                   with: .linearGradient(Gradient(colors: [.black.opacity(0.14), .clear]), startPoint: CGPoint(x: 0, y: ground + turf), endPoint: CGPoint(x: 0, y: ground + turf + 6 * k)))
            let tuft = 9 * k
            var tufts = Path()
            var tx = -(shift.truncatingRemainder(dividingBy: tuft)) - tuft
            while tx < width + tuft {
                tufts.move(to: CGPoint(x: tx, y: ground + turf - 1))
                tufts.addLine(to: CGPoint(x: tx + tuft * 0.5, y: ground + turf + 4 * k))
                tufts.addLine(to: CGPoint(x: tx + tuft, y: ground + turf - 1))
                tufts.closeSubpath()
                tx += tuft
            }
            g.fill(tufts, with: .color(Color(red: 0.33, green: 0.6, blue: 0.2)))
            g.fill(Path(CGRect(x: 0, y: ground, width: width, height: turf)),
                   with: .linearGradient(Gradient(colors: [Color(red: 0.58, green: 0.87, blue: 0.35), Color(red: 0.4, green: 0.71, blue: 0.24)]),
                                         startPoint: CGPoint(x: 0, y: ground), endPoint: CGPoint(x: 0, y: ground + turf)))
            g.fill(Path(CGRect(x: 0, y: ground + 1.5 * k, width: width, height: 2 * k)), with: .color(Color(red: 0.78, green: 0.97, blue: 0.55).opacity(0.9)))
            g.fill(Path(CGRect(x: 0, y: ground - 0.5 * k, width: width, height: 2 * k)), with: .color(Color(red: 0.2, green: 0.42, blue: 0.14)))
        }

        // MARK: The bird

        private func drawBird(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat, tilt: Double, wing: Double, dead: Bool) {
            var g = g
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(tilt))
            let ink = Color(red: 0.33, green: 0.18, blue: 0.04), line = max(1.3, s * 0.045)
            // Tail feathers, fanned out behind.
            var tail = Path()
            for (dy, turn) in [(CGFloat(-0.1), -0.4), (0.03, 0.0), (0.15, 0.4)] {
                let pivot = CGPoint(x: -0.36 * s, y: dy * s)
                tail.addEllipse(in: CGRect(x: -0.64 * s, y: (dy - 0.07) * s, width: 0.34 * s, height: 0.14 * s),
                                transform: CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: CGFloat(turn)).translatedBy(x: -pivot.x, y: -pivot.y))
            }
            g.fill(tail, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.3), Color(red: 0.93, green: 0.56, blue: 0.08)]),
                                               startPoint: CGPoint(x: 0, y: -0.2 * s), endPoint: CGPoint(x: 0, y: 0.25 * s)))
            g.stroke(tail, with: .color(ink), lineWidth: line)
            // The body: round and yellow, lit from the top left.
            let round = Path(ellipseIn: CGRect(x: -0.46 * s, y: -0.37 * s, width: 0.92 * s, height: 0.74 * s))
            g.fill(round.applying(CGAffineTransform(translationX: 0.05 * s, y: 0.08 * s)), with: .color(.black.opacity(0.12)))
            g.fill(round, with: .radialGradient(Gradient(stops: [.init(color: Color(red: 1, green: 0.98, blue: 0.72), location: 0),
                                                                 .init(color: Color(red: 1, green: 0.85, blue: 0.22), location: 0.42),
                                                                 .init(color: Color(red: 0.95, green: 0.6, blue: 0.08), location: 1)]),
                                                center: CGPoint(x: -0.12 * s, y: -0.2 * s), startRadius: 0, endRadius: 0.64 * s))
            var inside = g
            inside.clip(to: round)
            inside.fill(Path(ellipseIn: CGRect(x: -0.16 * s, y: 0.04 * s, width: 0.62 * s, height: 0.46 * s)),
                        with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.86), Color(red: 1, green: 0.88, blue: 0.6)]),
                                              startPoint: CGPoint(x: 0, y: 0.04 * s), endPoint: CGPoint(x: 0, y: 0.42 * s)))
            // Feathers on its back: three small scallops.
            var scallops = Path()
            for (fx, fy) in [(CGFloat(-0.3), CGFloat(-0.16)), (-0.16, -0.24), (-0.33, 0.0)] {
                scallops.move(to: CGPoint(x: (fx - 0.075) * s, y: fy * s))
                scallops.addQuadCurve(to: CGPoint(x: (fx + 0.075) * s, y: fy * s), control: CGPoint(x: fx * s, y: (fy + 0.1) * s))
            }
            inside.stroke(scallops, with: .color(Color(red: 0.86, green: 0.52, blue: 0.06).opacity(0.7)), lineWidth: line * 0.75)
            g.stroke(round, with: .color(ink), lineWidth: line)
            // A big eye with a glint in it, or crosses once it has crashed.
            let eye = CGRect(x: 0.04 * s, y: -0.35 * s, width: 0.34 * s, height: 0.34 * s)
            g.fill(Path(ellipseIn: eye), with: .radialGradient(Gradient(colors: [.white, Color(red: 0.88, green: 0.9, blue: 0.94)]),
                                                               center: CGPoint(x: eye.midX - 0.05 * s, y: eye.midY - 0.06 * s), startRadius: 0, endRadius: 0.22 * s))
            g.stroke(Path(ellipseIn: eye), with: .color(ink), lineWidth: line)
            if dead {
                var cross = Path()
                let c = CGPoint(x: eye.midX + 0.02 * s, y: eye.midY), r = 0.075 * s
                cross.move(to: CGPoint(x: c.x - r, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
                cross.move(to: CGPoint(x: c.x + r, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
                g.stroke(cross, with: .color(ink), style: StrokeStyle(lineWidth: line * 1.2, lineCap: .round))
            } else {
                g.fill(Path(ellipseIn: CGRect(x: 0.2 * s, y: -0.26 * s, width: 0.12 * s, height: 0.16 * s)), with: .color(Color(red: 0.08, green: 0.05, blue: 0.03)))
                g.fill(Path(ellipseIn: CGRect(x: 0.222 * s, y: -0.245 * s, width: 0.048 * s, height: 0.052 * s)), with: .color(.white))
            }
            g.fill(Path(ellipseIn: CGRect(x: 0.07 * s, y: 0.04 * s, width: 0.17 * s, height: 0.1 * s)), with: .color(Color(red: 1, green: 0.42, blue: 0.3).opacity(0.4)))
            // The beak: an orange upper half over a red lower one.
            var upper = Path(), lower = Path()
            upper.move(to: CGPoint(x: 0.26 * s, y: -0.07 * s))
            upper.addQuadCurve(to: CGPoint(x: 0.66 * s, y: 0.04 * s), control: CGPoint(x: 0.58 * s, y: -0.11 * s))
            upper.addLine(to: CGPoint(x: 0.3 * s, y: 0.07 * s))
            upper.closeSubpath()
            lower.move(to: CGPoint(x: 0.3 * s, y: 0.06 * s))
            lower.addLine(to: CGPoint(x: 0.6 * s, y: 0.07 * s))
            lower.addQuadCurve(to: CGPoint(x: 0.3 * s, y: 0.19 * s), control: CGPoint(x: 0.54 * s, y: 0.19 * s))
            lower.closeSubpath()
            g.fill(lower, with: .color(Color(red: 0.93, green: 0.3, blue: 0.12)))
            g.stroke(lower, with: .color(ink), lineWidth: line)
            g.fill(upper, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.74, blue: 0.32), Color(red: 1, green: 0.5, blue: 0.12)]),
                                                startPoint: CGPoint(x: 0.3 * s, y: -0.09 * s), endPoint: CGPoint(x: 0.3 * s, y: 0.07 * s)))
            g.stroke(upper, with: .color(ink), lineWidth: line)
            // The wing, over the body, beating about its shoulder.
            var w = g
            w.translateBy(x: -0.06 * s, y: 0.03 * s)
            w.rotate(by: .radians(wing))
            var feather = Path()
            feather.move(to: CGPoint(x: 0.06 * s, y: -0.05 * s))
            feather.addQuadCurve(to: CGPoint(x: -0.42 * s, y: 0.0), control: CGPoint(x: -0.2 * s, y: -0.21 * s))
            feather.addQuadCurve(to: CGPoint(x: 0.06 * s, y: 0.1 * s), control: CGPoint(x: -0.16 * s, y: 0.17 * s))
            feather.closeSubpath()
            w.fill(feather, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 1, blue: 0.94), Color(red: 1, green: 0.88, blue: 0.56)]),
                                                  startPoint: CGPoint(x: 0, y: -0.15 * s), endPoint: CGPoint(x: 0, y: 0.12 * s)))
            var quills = Path()
            quills.move(to: CGPoint(x: -0.1 * s, y: 0.03 * s)); quills.addLine(to: CGPoint(x: -0.27 * s, y: 0.03 * s))
            quills.move(to: CGPoint(x: -0.06 * s, y: 0.075 * s)); quills.addLine(to: CGPoint(x: -0.2 * s, y: 0.08 * s))
            w.stroke(quills, with: .color(Color(red: 0.88, green: 0.6, blue: 0.18)), style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round))
            w.stroke(feather, with: .color(ink), lineWidth: line)
        }

        /// Little puffs of air pushed down and back by a flap.
        private func puffs(_ g: GraphicsContext, behind p: CGPoint, size s: CGFloat, age: Double) {
            let k = CGFloat(age / 0.4)
            var air = Path()
            for (dx, dy, r) in [(CGFloat(-0.55), CGFloat(0.3), CGFloat(0.12)), (-0.78, 0.18, 0.09), (-0.42, 0.5, 0.08)] {
                let c = CGPoint(x: p.x + (dx - 0.25 * k) * s, y: p.y + (dy + 0.2 * k) * s), rr = r * s * (1 + k)
                air.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
            }
            g.fill(air, with: .color(.white.opacity(0.7 * Double(1 - k))))
        }

        /// Feathers knocked loose by a pipe, flung out, then drifting down.
        private func feathers(_ g: GraphicsContext, from p: CGPoint, size s: CGFloat, age: Double) {
            guard age < 2.5 else { return }
            let fade = max(0, 1 - age / 2.5), out = CGFloat(1 - exp(-age * 3.5))
            for i in 0..<7 {
                let a = Double(i) * 0.9 + 0.4, reach = s * CGFloat(1.1 + 0.3 * Double(i % 3))
                var f = g
                f.translateBy(x: p.x + CGFloat(cos(a)) * reach * out, y: p.y + CGFloat(sin(a)) * reach * out * 0.7 + CGFloat(age * age) * s * 0.3)
                f.rotate(by: .radians(sin(age * 4 + Double(i)) * 0.8 + Double(i)))
                let quill = Path(ellipseIn: CGRect(x: -0.15 * s, y: -0.055 * s, width: 0.3 * s, height: 0.11 * s))
                f.fill(quill, with: .color((i % 2 == 0 ? Color(red: 1, green: 0.86, blue: 0.3) : Color(red: 1, green: 0.97, blue: 0.84)).opacity(fade)))
                f.stroke(quill, with: .color(Color(red: 0.5, green: 0.3, blue: 0.06).opacity(0.8 * fade)), lineWidth: 1)
            }
        }

        /// Sand thrown up where it hit the ground.
        private func dust(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat, age: Double) {
            guard age < 1 else { return }
            let spread = CGFloat(1 - exp(-age * 5))
            var cloud = Path()
            for i in 0..<6 {
                let side: CGFloat = i % 2 == 0 ? -1 : 1, step = CGFloat(i / 2)
                let r = s * (0.13 + 0.05 * step) * CGFloat(0.6 + age)
                let c = CGPoint(x: p.x + side * s * (0.2 + (0.3 + 0.28 * step) * spread), y: p.y - r * 0.6 - CGFloat(age) * s * 0.18)
                cloud.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
            g.fill(cloud, with: .color(Color(red: 0.94, green: 0.88, blue: 0.72).opacity(0.8 * (1 - age))))
        }

        /// Stars going round its head.
        private func dizzy(_ g: GraphicsContext, over p: CGPoint, size s: CGFloat) {
            var stars = Path()
            for i in 0..<3 {
                let a = now * 4 + Double(i) * 2 * .pi / 3
                let c = CGPoint(x: p.x + 0.05 * s + CGFloat(cos(a)) * 0.5 * s, y: p.y - 0.66 * s + CGFloat(sin(a)) * 0.16 * s)
                let r = 0.15 * s * CGFloat(0.8 + 0.2 * sin(a))
                for n in 0..<10 {
                    let b = Double(n) * .pi / 5 - .pi / 2, rr = n % 2 == 0 ? r : r * 0.45
                    let q = CGPoint(x: c.x + CGFloat(cos(b)) * rr, y: c.y + CGFloat(sin(b)) * rr)
                    if n == 0 { stars.move(to: q) } else { stars.addLine(to: q) }
                }
                stars.closeSubpath()
            }
            g.fill(stars, with: .color(Color(red: 1, green: 0.9, blue: 0.3)))
            g.stroke(stars, with: .color(Color(red: 0.55, green: 0.35, blue: 0.05)), lineWidth: 1)
        }

        /// The score: fat white numerals with a dark outline and a soft drop shadow, readable on sky or cloud.
        private func number(_ g: GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat) {
            let font = Font.system(size: size, weight: .black, design: .rounded)
            let ink = g.resolve(Text(text).font(font).foregroundColor(Color(red: 0.22, green: 0.13, blue: 0.06)))
            let paper = g.resolve(Text(text).font(font).foregroundColor(.white))
            let o = max(2, size * 0.06)
            var shadow = g
            shadow.opacity = 0.28
            shadow.draw(ink, at: CGPoint(x: p.x + o * 0.7, y: p.y + o * 1.8), anchor: .center)
            for i in 0..<12 {
                let a = Double(i) * .pi / 6
                g.draw(ink, at: CGPoint(x: p.x + CGFloat(cos(a)) * o, y: p.y + CGFloat(sin(a)) * o), anchor: .center)
            }
            g.draw(paper, at: p, anchor: .center)
        }
    }
}
