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

    /// Sky, far towers, clouds and bushes rolling past at their own speeds; the
    /// pipes and the ground at the bird's.
    fileprivate struct Scene {
        let before: Flight, after: Flight, t: Double, since: Double, now: Double, over: Bool, grounded: Bool

        func paint(_ g: inout GraphicsContext, _ size: CGSize) {
            let width = size.width, height = size.height
            let column = width / CGFloat(JevFlappy.columns), row = height / CGFloat(JevFlappy.sky + 1)
            let camera = JevDraw.mix(Double(before.x), Double(after.x), t)
            func x(_ world: Double) -> CGFloat { (CGFloat(world - camera) + CGFloat(JevFlappy.bird) + 0.5) * column }
            func y(_ row: Double) -> CGFloat { (CGFloat(row) + 0.5) * height / CGFloat(JevFlappy.sky + 1) }
            let ground = CGFloat(JevFlappy.sky) * row

            g.fill(Path(CGRect(origin: .zero, size: size)),
                   with: .linearGradient(Gradient(colors: [Color(red: 0.29, green: 0.72, blue: 0.98), Color(red: 0.72, green: 0.91, blue: 1)]),
                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: ground)))
            let sun = CGPoint(x: width * 0.82, y: height * 0.16)
            g.fill(Path(ellipseIn: CGRect(x: sun.x - 60, y: sun.y - 60, width: 120, height: 120)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), Color.yellow.opacity(0.35), .clear]), center: sun, startRadius: 0, endRadius: 60))
            // Far towers, a quarter of the bird's speed.
            let far = camera * Double(column) * 0.25
            for tower in -2..<22 {
                let slot = Int(floor(far / 46)) + tower
                let left = CGFloat(Double(slot) * 46 - far)
                let tall = ground * CGFloat(0.18 + 0.22 * Double(JevDraw.hash(slot, 4) % 100) / 100)
                g.fill(Path(CGRect(x: left, y: ground - tall, width: 40, height: tall)), with: .color(Color(red: 0.62, green: 0.80, blue: 0.9)))
                for w in 0..<Int(tall / 14) where JevDraw.hash(slot, w) % 3 == 0 {
                    g.fill(Path(CGRect(x: left + 8, y: ground - tall + 6 + CGFloat(w) * 14, width: 6, height: 6)), with: .color(.white.opacity(0.5)))
                }
            }
            // Clouds, half speed.
            let near = camera * Double(column) * 0.5
            for cloud in -1..<6 {
                let slot = Int(floor(near / 150)) + cloud
                let cx = CGFloat(Double(slot) * 150 - near) + CGFloat(JevDraw.hash(slot, 1) % 60)
                let cy = height * CGFloat(0.1 + 0.3 * Double(JevDraw.hash(slot, 2) % 100) / 100)
                for (dx, dy, r) in [(0.0, 0.0, 22.0), (22, 6, 18), (-20, 6, 16), (8, -10, 17)] {
                    g.fill(Path(ellipseIn: CGRect(x: cx + CGFloat(dx) - CGFloat(r), y: cy + CGFloat(dy) - CGFloat(r), width: CGFloat(2 * r), height: CGFloat(2 * r))),
                           with: .color(.white.opacity(0.92)))
                }
            }
            // Bushes along the ground, most of the bird's speed.
            let bush = camera * Double(column) * 0.8
            for b in -2..<20 {
                let slot = Int(floor(bush / 38)) + b
                let cx = CGFloat(Double(slot) * 38 - bush), r = CGFloat(18 + JevDraw.hash(slot, 5) % 12)
                g.fill(Path(ellipseIn: CGRect(x: cx - r, y: ground - r * 0.9, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.38, green: 0.72, blue: 0.3)))
            }

            // The pipes, with a lip at each end of the gap.
            let body = column * 0.92, lip = column * 1.12
            for pipe in after.pipes {
                let centre = x(Double(pipe.x))
                guard centre > -lip, centre < width + lip else { continue }
                let top = CGFloat(pipe.top) * row, bottom = CGFloat(pipe.top + JevFlappy.gap) * row
                let shading = Gradient(colors: [Color(red: 0.33, green: 0.62, blue: 0.16), Color(red: 0.62, green: 0.9, blue: 0.35),
                                                Color(red: 0.4, green: 0.74, blue: 0.2), Color(red: 0.2, green: 0.45, blue: 0.1)])
                for part in [CGRect(x: centre - body / 2, y: -2, width: body, height: top + 2),
                             CGRect(x: centre - body / 2, y: bottom, width: body, height: ground - bottom)] {
                    g.fill(Path(part), with: .linearGradient(shading, startPoint: CGPoint(x: part.minX, y: 0), endPoint: CGPoint(x: part.maxX, y: 0)))
                    g.stroke(Path(part), with: .color(Color(red: 0.12, green: 0.28, blue: 0.06)), lineWidth: 2)
                }
                for cap in [CGRect(x: centre - lip / 2, y: top - row * 0.55, width: lip, height: row * 0.55),
                            CGRect(x: centre - lip / 2, y: bottom, width: lip, height: row * 0.55)] {
                    g.fill(Path(roundedRect: cap, cornerRadius: 3), with: .linearGradient(shading, startPoint: CGPoint(x: cap.minX, y: 0), endPoint: CGPoint(x: cap.maxX, y: 0)))
                    g.stroke(Path(roundedRect: cap, cornerRadius: 3), with: .color(Color(red: 0.12, green: 0.28, blue: 0.06)), lineWidth: 2)
                }
            }

            // The ground: grass on top, sand below, stripes rolling at the bird's speed.
            g.fill(Path(CGRect(x: 0, y: ground, width: width, height: height - ground)), with: .color(Color(red: 0.87, green: 0.8, blue: 0.55)))
            g.fill(Path(CGRect(x: 0, y: ground, width: width, height: row * 0.28)), with: .color(Color(red: 0.45, green: 0.78, blue: 0.3)))
            let stripe = column * 0.6, shift = CGFloat(camera) * column
            var sx = -(shift.truncatingRemainder(dividingBy: stripe)) - stripe
            while sx < width + stripe {
                g.fill(Path { path in
                    path.move(to: CGPoint(x: sx, y: ground + row * 0.28))
                    path.addLine(to: CGPoint(x: sx + stripe * 0.5, y: ground + row * 0.28))
                    path.addLine(to: CGPoint(x: sx + stripe * 0.2, y: height))
                    path.addLine(to: CGPoint(x: sx - stripe * 0.3, y: height))
                    path.closeSubpath()
                }, with: .color(Color(red: 0.8, green: 0.72, blue: 0.46)))
                sx += stripe
            }

            // The bird, nose up when it climbs and down when it falls, its wing beating.
            let level = JevDraw.mix(Double(before.y), Double(after.y), t)
            let speed = JevDraw.mix(Double(before.v), Double(after.v), t)
            let tilt = over ? 1.3 : min(max(speed * 0.32, -0.5), 1.1)
            let flapping = after.v < 0 || before.v < 0
            bird(g, at: CGPoint(x: x(camera), y: y(min(level, Double(JevFlappy.sky) - 0.35))), size: column * 0.95, tilt: tilt,
                 wing: flapping ? sin(now * 28) : -0.3)
            if over, !grounded { JevDraw.blast(g, at: CGPoint(x: x(camera) + column * 0.4, y: y(level)), size: column * 0.4, age: since * 1.5) }

            JevDraw.text(g, "\(after.passed)", at: CGPoint(x: width / 2, y: size.height * 0.12), size: size.height * 0.11)
            if over { JevDraw.curtain(g, size, title: grounded ? "掉下去了！" : "撞上管子了！", detail: "过了 \(after.passed) 根管子") }
        }

        private func bird(_ g: GraphicsContext, at p: CGPoint, size: CGFloat, tilt: Double, wing: Double) {
            var g = g
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(tilt))
            let body = CGRect(x: -size * 0.45, y: -size * 0.34, width: size * 0.9, height: size * 0.68)
            g.fill(Path(ellipseIn: body.offsetBy(dx: 2, dy: 3)), with: .color(.black.opacity(0.2)))
            g.fill(Path(ellipseIn: body), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.45), Color(red: 0.98, green: 0.72, blue: 0.1)]),
                                                                center: CGPoint(x: -size * 0.1, y: -size * 0.12), startRadius: 0, endRadius: size * 0.5))
            g.stroke(Path(ellipseIn: body), with: .color(Color(red: 0.45, green: 0.3, blue: 0.05)), lineWidth: 1.6)
            g.fill(Path(ellipseIn: CGRect(x: -size * 0.28, y: size * 0.02, width: size * 0.46, height: size * 0.26)), with: .color(Color(red: 1, green: 0.98, blue: 0.8)))
            var w = g
            w.translateBy(x: -size * 0.12, y: 0)
            w.rotate(by: .radians(wing * 0.6))
            let feather = CGRect(x: -size * 0.3, y: -size * 0.1, width: size * 0.36, height: size * 0.22)
            w.fill(Path(ellipseIn: feather), with: .color(Color(red: 1, green: 0.98, blue: 0.85)))
            w.stroke(Path(ellipseIn: feather), with: .color(Color(red: 0.45, green: 0.3, blue: 0.05)), lineWidth: 1.4)
            let eye = CGRect(x: size * 0.08, y: -size * 0.28, width: size * 0.3, height: size * 0.3)
            g.fill(Path(ellipseIn: eye), with: .color(.white))
            g.stroke(Path(ellipseIn: eye), with: .color(Color(red: 0.3, green: 0.2, blue: 0.05)), lineWidth: 1.2)
            g.fill(Path(ellipseIn: CGRect(x: size * 0.23, y: -size * 0.19, width: size * 0.11, height: size * 0.13)), with: .color(.black))
            let beak = Path { path in
                path.move(to: CGPoint(x: size * 0.3, y: -size * 0.02))
                path.addLine(to: CGPoint(x: size * 0.62, y: size * 0.06))
                path.addLine(to: CGPoint(x: size * 0.3, y: size * 0.16))
                path.closeSubpath()
            }
            g.fill(beak, with: .color(Color(red: 0.98, green: 0.4, blue: 0.15)))
            g.stroke(beak, with: .color(Color(red: 0.5, green: 0.15, blue: 0.02)), lineWidth: 1.2)
        }
    }
}
