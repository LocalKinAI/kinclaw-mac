import SwiftUI

/// 开车 — a highway seen from above, one tick a question.
///
/// Five lanes of one-way traffic: trucks at a row a tick, cars at two, each
/// straight on in its lane and slowing only behind something slower, so
/// everything on the road is where the program says it will be. The player's
/// car moves at most one lane a tick and goes one faster or slower, one to
/// four rows a tick. Fuel burns a unit a tick, and the cans that refill it lie
/// on the road — they come by the mile, not by the minute, so a driver who
/// dawdles runs dry. Every tick is a driver's choice: how fast, and in which
/// lane, against what is ahead.
///
/// The program measures what a driver sees: what is ahead in the lane and how
/// fast it is closing, whether there is still room to brake behind it, whether
/// a lane beside is open, where the fuel is — and, with every vehicle's future
/// known, whether a crash can still be avoided at all. The evaluator that plays
/// looks four ticks ahead over every combination of moves.
@MainActor
final class JevDrive: JevGame {
    let id = "drive", title = "开车", symbol = "car.fill"
    let rules = "Driving on a highway with five lanes, seen from above; all traffic goes the same way. Each tick the player's car may move one lane left or right and go one row a tick faster or slower; its speed is 1 to 4 rows a tick. Trucks drive 1 row a tick and cars 2, straight on in their lanes, slowing only behind something slower. Touching any vehicle ends the game. The tank holds 60 ticks of fuel and every tick uses one; driving over a fuel can adds 25, and running dry ends the game. The score is the distance driven, in rows."
    let question = "What should the driver do this tick, to drive as far as possible without crashing or running out of fuel?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: never choose an option that crashes, runs the tank dry, or after which a crash can no longer be avoided — each ends the game. Second: never end up too close to brake behind the vehicle ahead unless a lane beside is open. Third: when the fuel is low, driving over a fuel can, or getting a lane closer to one, comes before everything below. Fourth: faster is better — the score is the distance, and fuel cans only come to a driver who covers ground. Coming up behind a slower vehicle is fine while there is room to brake; the way past it is an open lane beside, not slowing down to sit behind it. Slow down only when there is no room to brake and no open lane."

    nonisolated static let lanes = 5, rows = 18, tank = 60, refill = 25, top = 4
    let clock: Double? = 0.22
    let controls = "←→ 换道 · ↑ 加速 · ↓ 减速 · 不按就保持"

    fileprivate struct Thing {
        enum Kind { case truck, car, can }
        var kind: Kind, lane: Int, y: Int, paint = 0, serial = 0
        var length: Int { kind == .truck ? 3 : kind == .car ? 2 : 1 }
        var pace: Int { kind == .truck ? 1 : kind == .car ? 2 : 0 }
        var front: Int { y + length - 1 }
        var name: String { kind == .truck ? "truck" : kind == .car ? "car" : "fuel can" }
    }

    /// The road as it stands: everything the car can meet, by rows from the start.
    fileprivate struct Road {
        var lane = 2, y = 0, speed = 2, fuel = JevDrive.tank, passed = 0
        var things: [Thing] = []

        struct Tick { var crash: Thing?; var cans = 0; var dry = false }

        /// The moves open to the car: a lane either way, a speed either way.
        var moves: [(steer: Int, throttle: Int)] {
            var out: [(steer: Int, throttle: Int)] = []
            for steer in [0, -1, 1] where (0..<JevDrive.lanes).contains(lane + steer) {
                for throttle in [0, 1, -1] where (1...JevDrive.top).contains(speed + throttle) { out.append((steer, throttle)) }
            }
            return out
        }

        /// One tick: the car steers and changes speed, and everything moves on.
        /// Nothing new appears — the program's look ahead is of what is there.
        mutating func step(steer: Int, throttle: Int) -> Tick {
            var tick = Tick()
            lane += steer
            speed = min(max(speed + throttle, 1), JevDrive.top)
            let rear = y
            y += speed
            fuel -= 1
            // Traffic, front to back in each lane: nobody drives into the one ahead.
            var moved = things, ahead = [Int?](repeating: nil, count: JevDrive.lanes)
            for index in things.indices.sorted(by: { things[$0].y > things[$1].y }) where things[index].kind != .can {
                var thing = things[index]
                var next = thing.y + thing.pace
                if let limit = ahead[thing.lane] { next = min(next, limit - 1 - thing.length) }
                thing.y = max(next, thing.y)
                moved[index] = thing
                ahead[thing.lane] = thing.y
            }
            // The car against whatever is in its lane: touching at the start or the
            // end of the tick, or driving right through it in between.
            var taken: Set<Int> = []
            for index in things.indices where things[index].lane == lane {
                let before = things[index], after = moved[index]
                let atStart = before.y <= rear + 1 && before.front >= rear
                let atEnd = after.y <= y + 1 && after.front >= y
                let through = before.y > rear + 1 && after.front < y
                guard atStart || atEnd || through else { continue }
                if before.kind == .can { tick.cans += 1; taken.insert(index) }
                else if tick.crash == nil { tick.crash = before }
            }
            things = moved.enumerated().filter { !taken.contains($0.offset) }.map { $0.element }
            // What is behind the car is gone; what got far ahead is out of the story.
            let before = things.count
            things.removeAll { $0.front < y && $0.kind != .can }
            passed += before - things.count
            things.removeAll { $0.front < y || $0.y > y + 40 }
            fuel = min(fuel + tick.cans * JevDrive.refill, JevDrive.tank)
            tick.dry = fuel <= 0
            return tick
        }

        /// Can the car still get through `ticks` more without touching anything?
        func survives(_ ticks: Int) -> Bool {
            guard ticks > 0 else { return true }
            // Braking first: it is the answer far more often than not, and the search stops at the first way out.
            for move in moves.sorted(by: { $0.throttle < $1.throttle }) {
                var next = self
                if next.step(steer: move.steer, throttle: move.throttle).crash == nil, next.survives(ticks - 1) { return true }
            }
            return false
        }

        /// The nearest vehicle ahead in a lane, how many empty rows lie between
        /// the car's nose and it, and how many rows a tick the gap is closing
        /// by if the car keeps its speed.
        /// `exact` plays the tick out, so that a car stuck behind a truck is seen
        /// to go at the truck's pace; otherwise each is taken at its own.
        func ahead(in lane: Int, exact: Bool = true) -> (thing: Thing, gap: Int, closing: Int)? {
            guard let thing = things.filter({ $0.lane == lane && $0.kind != .can && $0.y > y + 1 }).min(by: { $0.y < $1.y }) else { return nil }
            let gap = thing.y - (y + 1) - 1
            guard exact else { return (thing, gap, speed - thing.pace) }
            var next = self
            next.lane = lane
            _ = next.step(steer: 0, throttle: 0)
            guard let later = next.things.first(where: { $0.serial == thing.serial }) else { return (thing, gap, speed - thing.pace) }
            return (thing, gap, gap - (later.y - (next.y + 1) - 1))
        }

        /// Rows the gap closes by while braking down to the pace of the vehicle ahead.
        static func braking(from speed: Int, to pace: Int) -> Int {
            let excess = max(speed - 1 - pace, 0)
            return excess * (excess + 1) / 2
        }

        /// Is a lane free beside the car — nothing alongside, nothing just ahead?
        func open(_ lane: Int) -> Bool {
            guard (0..<JevDrive.lanes).contains(lane) else { return false }
            return !things.contains { $0.lane == lane && $0.kind != .can && $0.front >= y - 1 && $0.y <= y + 1 + speed + 2 }
        }

        /// What the evaluator makes of a position `depth` ticks on, best line first.
        func value(_ depth: Int, fuelWorth: Double) -> Double {
            guard depth > 0 else { return settle() }
            var best = -Double.infinity
            for move in moves {
                var next = self
                let tick = next.step(steer: move.steer, throttle: move.throttle)
                let value: Double = tick.crash != nil ? -10_000 - Double(depth) * 100
                    : tick.dry ? -8_000
                    : Double(next.speed) + Double(tick.cans) * fuelWorth + next.value(depth - 1, fuelWorth: fuelWorth)
                best = max(best, value)
            }
            return best
        }

        /// At the end of the look ahead: trouble that is coming but not yet here.
        private func settle() -> Double {
            guard let near = ahead(in: lane, exact: false), near.closing > 0 else { return 0 }
            if near.gap >= Road.braking(from: speed, to: near.thing.pace) { return 0 }
            return open(lane - 1) || open(lane + 1) ? -4 : -40
        }
    }

    private var road = Road()
    /// The road before the last tick, for the picture to glide from.
    private var previous = Road()
    private(set) var ticked = Date.distantPast
    private var built = 0, made = 0
    private var dice = JevDice(seed: 1)
    private var moves: [(steer: Int, throttle: Int)] = []
    private var wreck: (lane: Int, y: Int)?
    private(set) var over = false
    private var ending = ""

    var score: Int { road.y }
    var status: String {
        let line = "里程 \(road.y) · 车速 \(road.speed) · 油 \(max(road.fuel, 0))/\(Self.tank) · 超车 \(road.passed)"
        return over ? "\(ending) · " + line : line
    }

    var situation: String {
        let fuel = road.fuel <= 12 ? "very low" : road.fuel <= 25 ? "low" : "enough"
        var parts = ["speed \(road.speed) rows a tick, in lane \(road.lane + 1) of 5", "fuel for \(road.fuel) more ticks (\(fuel))"]
        if let can = road.things.filter({ $0.kind == .can && $0.y > road.y + 1 }).min(by: { $0.y < $1.y }) {
            parts.append("the nearest fuel can is in lane \(can.lane + 1), \(can.y - road.y - 2) rows ahead")
        } else { parts.append("no fuel can in sight") }
        return parts.joined(separator: "; ")
    }

    var position: String {
        var rows: [String] = []
        for row in 0..<Self.rows {
            let at = road.y + (Self.rows - 1 - row)
            let cells = (0..<Self.lanes).map { lane -> String in
                if lane == road.lane, at == road.y || at == road.y + 1 { return "A" }
                guard let thing = road.things.first(where: { $0.lane == lane && $0.y <= at && at <= $0.front }) else { return "." }
                return thing.kind == .truck ? "T" : thing.kind == .car ? "C" : "F"
            }
            rows.append("|" + cells.joined(separator: " ") + "|")
        }
        return rows.joined(separator: "\n") + "\n(A is your car, driving up the page; T a truck, 1 row a tick; C a car, 2; F a fuel can. Lanes 1–5 from the left.)"
    }

    private static let asphalt = Color(white: 0.27), verge = Color(red: 0.29, green: 0.52, blue: 0.24)
    private static let paints: [Color] = [.blue, .teal, .purple, .yellow, Color(white: 0.92), .green]
    var grid: [[JevCell]] {
        var cells = (0..<Self.rows).map { row in
            (0..<(Self.lanes + 2)).map { col -> JevCell in
                guard col == 0 || col == Self.lanes + 1 else { return JevCell(colour: Self.asphalt) }
                let at = road.y + (Self.rows - 1 - row)                 // the verge rolls by as the car drives
                return JevCell(colour: Self.verge, text: (at * 3 + col * 5) % 11 == 0 ? "🌲" : "", big: true)
            }
        }
        func put(_ lane: Int, _ at: Int, _ cell: JevCell) {
            let row = Self.rows - 1 - (at - road.y)
            guard (0..<Self.rows).contains(row) else { return }
            cells[row][lane + 1] = cell
        }
        for thing in road.things {
            for at in thing.y...thing.front {
                switch thing.kind {
                case .can: put(thing.lane, at, JevCell(colour: Self.asphalt, text: "⛽", big: true))
                case .truck: put(thing.lane, at, JevCell(colour: at == thing.front ? .orange : Color(red: 0.55, green: 0.47, blue: 0.40)))
                case .car: put(thing.lane, at, JevCell(colour: Self.paints[thing.paint % Self.paints.count]))
                }
            }
        }
        put(road.lane, road.y, JevCell(colour: .red))
        put(road.lane, road.y + 1, JevCell(colour: .red, text: "▲", ink: .white))
        if let wreck { put(wreck.lane, wreck.y, JevCell(colour: .red, text: "💥", big: true)) }
        return cells
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        road = Road(); dice = JevDice(seed: seed); over = false; wreck = nil; ending = ""; made = 0
        built = road.y + 8                                          // a clear stretch to start on
        populate()
        previous = road; ticked = .distantPast
    }

    /// Lay the road ahead, a row at a time: traffic thickens with the distance
    /// driven, and cans come by the row, so fuel is found by driving.
    private func populate() {
        while built < road.y + Self.rows + 6 {
            built += 1
            let thick = min(Double(road.y) / 4000, 1)
            for lane in 0..<Self.lanes where Double(dice.below(10_000)) < (0.030 + 0.035 * thick) * 10_000 && free(lane, built) {
                made += 1
                road.things.append(Thing(kind: dice.below(10) < 4 ? .truck : .car, lane: lane, y: built, paint: dice.below(6), serial: made))
            }
            if dice.below(28) == 0 {
                let lane = dice.below(Self.lanes)
                if free(lane, built) { made += 1; road.things.append(Thing(kind: .can, lane: lane, y: built, serial: made)) }
            }
        }
    }

    private func free(_ lane: Int, _ at: Int) -> Bool {
        !road.things.contains { $0.lane == lane && $0.y - 4 <= at && at <= $0.front + 4 }
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        moves = road.moves
        let fuelWorth: Double = road.fuel <= 15 ? 80 : road.fuel <= 30 ? 20 : 4
        return moves.enumerated().map { index, move in
            var next = road
            let tick = next.step(steer: move.steer, throttle: move.throttle)
            let merit: Double = tick.crash != nil ? -10_000 : tick.dry ? -9_000
                : Double(next.speed) + Double(tick.cans) * fuelWorth + next.value(3, fuelWorth: fuelWorth)
            return JevOption(id: String(format: "p%02d", index + 1), label: describe(move, next, tick), merit: merit, move: index)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move), !over else { return }
        let move = moves[option.move]
        previous = road
        let tick = road.step(steer: move.steer, throttle: move.throttle)
        ticked = Date()
        if let crash = tick.crash {
            over = true
            wreck = (road.lane, road.y + 1)
            ending = "撞上了\(crash.kind == .truck ? "货车" : "轿车")"
        } else if tick.dry {
            over = true; ending = "没油了"
        }
        populate()
    }

    /// One way to drive this tick, in words: what it does, and what it leaves.
    private func describe(_ move: (steer: Int, throttle: Int), _ next: Road, _ tick: Road.Tick) -> String {
        let lane = next.lane + 1
        var doing = move.steer == 0 ? "stays in lane \(lane)" : "moves \(move.steer < 0 ? "left" : "right") into lane \(lane)"
        let pace = next.speed == Self.top ? " (top speed)" : next.speed == 1 ? " (crawling)" : ""
        doing += (move.throttle > 0 ? " and speeds up to \(next.speed)" : move.throttle < 0 ? " and slows down to \(next.speed)" : " at speed \(next.speed)") + pace
        if let crash = tick.crash { return doing + ": crashes into the \(crash.name) in lane \(lane) at once: the game ends" }
        if tick.dry { return doing + ": the tank runs dry: the game ends" }
        var parts: [String] = []
        if tick.cans > 0 { parts.append("picks up a fuel can (+\(Self.refill) fuel)") }
        if !next.survives(5) {
            parts.append("after it a crash can no longer be avoided: the game ends within a few ticks")
            return doing + ": " + parts.joined(separator: "; ")
        }
        if let near = next.ahead(in: next.lane) {
            var words = "the \(near.thing.name) ahead in this lane is \(near.gap) rows away"
            if near.closing > 0 {
                let ticks = max(1, near.gap / near.closing)
                words += near.gap >= Road.braking(from: next.speed, to: near.thing.pace)
                    ? " and slower than you (you catch it in about \(ticks) tick\(ticks == 1 ? "" : "s"), with room to brake behind it)"
                    : " and slower than you, too close to brake behind it: you will have to change lanes"
            } else { words += near.closing == 0 ? ", going your speed: you are stuck behind it" : ", pulling away" }
            parts.append(words)
        } else { parts.append("lane \(lane) is clear as far as can be seen") }
        // The fuel: in this lane, or a lane nearer to it or further from it than before.
        if let can = next.things.filter({ $0.kind == .can && $0.y > next.y + 1 }).min(by: { $0.y < $1.y }) {
            let rows = can.y - next.y - 2, now = abs(can.lane - next.lane), before = abs(can.lane - road.lane)
            if now == 0 { parts.append("a fuel can lies \(rows) rows ahead in this lane") }
            else if now < before { parts.append("gets a lane closer to the fuel can in lane \(can.lane + 1), \(rows) rows ahead") }
            else if now > before { parts.append("moves a lane away from the fuel can in lane \(can.lane + 1)") }
        }
        let beside = [next.lane - 1, next.lane + 1].filter { next.open($0) }
        parts.append(beside.isEmpty ? "no open lane beside it" : "an open lane beside it (lane \(beside.map { String($0 + 1) }.joined(separator: " or ")))")
        return doing + ": " + parts.joined(separator: "; ")
    }

    // MARK: Played by a person

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let steer = pressed.latest(of: [.left, .right], held: held).map { $0 == .left ? -1 : 1 } ?? 0
        let throttle = pressed.latest(of: [.up, .down], held: held).map { $0 == .up ? 1 : -1 } ?? 0
        // A key that cannot be obeyed — off the road, past top speed — is not pressed.
        let wanted = [(steer, throttle), (0, throttle), (steer, 0), (0, 0)]
        for (s, t) in wanted {
            if let index = moves.firstIndex(where: { $0.steer == s && $0.throttle == t }),
               let option = options.first(where: { $0.move == index }) { return .choose(option) }
        }
        return options.first.map { .choose($0) } ?? .nothing
    }
}

// MARK: - The picture

extension JevDrive: JevPainted {
    var aspect: Double { 0.62 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = Scene(before: previous, after: road, t: t, since: since, crash: wreck, over: over, ending: ending)
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    nonisolated private static let tints: [(Double, Double, Double)] = [
        (0.16, 0.42, 0.85), (0.10, 0.62, 0.62), (0.55, 0.30, 0.78), (0.95, 0.78, 0.15), (0.92, 0.92, 0.94), (0.20, 0.62, 0.30),
    ]

    /// The road from above, the car near the bottom, the world rolling toward it.
    fileprivate struct Scene {
        let before: Road, after: Road, t: Double, since: Double
        let crash: (lane: Int, y: Int)?, over: Bool, ending: String

        func paint(_ g: inout GraphicsContext, _ size: CGSize) {
            let width = size.width, height = size.height
            let verge = width * 0.13, road = width - 2 * verge, lane = road / CGFloat(JevDrive.lanes), row = height / 17.5
            // The camera follows the car at an even pace through the tick.
            let camera = JevDraw.mix(Double(before.y), Double(after.y), t)
            let base = height - row * 1.15
            func y(_ world: Double) -> CGFloat { base - CGFloat(world - camera) * row }
            func x(_ lane: Double) -> CGFloat { verge + (CGFloat(lane) + 0.5) * road / CGFloat(JevDrive.lanes) }
            let first = Int(floor(camera)) - 4, last = Int(ceil(camera)) + 20

            // Grass, striped by the mile so that it rolls by.
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.30, green: 0.55, blue: 0.25)))
            for r in first...last where (r / 2 + 1000) % 2 == 0 {
                let top = y(Double(r) + 1), bottom = y(Double(r))
                for left in [0, width - verge] {
                    g.fill(Path(CGRect(x: left, y: top, width: verge, height: bottom - top)), with: .color(Color(red: 0.34, green: 0.60, blue: 0.28)))
                }
            }
            // Asphalt, a little lighter down the middle of each lane where the wheels polish it.
            g.fill(Path(CGRect(x: verge, y: 0, width: road, height: height)), with: .color(Color(white: 0.25)))
            for l in 0..<JevDrive.lanes {
                let middle = x(Double(l))
                g.fill(Path(CGRect(x: middle - lane * 0.3, y: 0, width: lane * 0.6, height: height)),
                       with: .linearGradient(Gradient(colors: [Color(white: 0.25), Color(white: 0.29), Color(white: 0.25)]),
                                             startPoint: CGPoint(x: middle - lane * 0.3, y: 0), endPoint: CGPoint(x: middle + lane * 0.3, y: 0)))
            }
            // Kerbs, red and white.
            for r in first...last {
                let top = y(Double(r) + 1), bottom = y(Double(r))
                let colour = (r + 1000) % 2 == 0 ? Color(red: 0.86, green: 0.16, blue: 0.14) : Color(white: 0.95)
                g.fill(Path(CGRect(x: verge - 7, y: top, width: 7, height: bottom - top)), with: .color(colour))
                g.fill(Path(CGRect(x: verge + road, y: top, width: 7, height: bottom - top)), with: .color(colour))
            }
            // Edge lines and the dashes between lanes, painted on the road.
            for edge in [verge + 5, verge + road - 8] {
                g.fill(Path(CGRect(x: edge, y: 0, width: 3, height: height)), with: .color(.white.opacity(0.9)))
            }
            for l in 1..<JevDrive.lanes {
                let left = verge + CGFloat(l) * lane - 1.5
                var r = first - (first % 3 + 3) % 3
                while r <= last {
                    let top = y(Double(r) + 1.7), bottom = y(Double(r))
                    g.fill(Path(roundedRect: CGRect(x: left, y: top, width: 3, height: bottom - top), cornerRadius: 1.5), with: .color(.white.opacity(0.8)))
                    r += 3
                }
            }
            // Trees along the verges.
            for r in first...last {
                for side in 0..<2 where JevDraw.hash(r, side) % 3 == 0 {
                    let offset = verge * (0.25 + 0.5 * CGFloat(JevDraw.hash(r, side + 5) % 100) / 100)
                    let centre = CGPoint(x: side == 0 ? offset : width - offset, y: y(Double(r) + 0.5))
                    tree(g, at: centre, radius: verge * (0.24 + 0.1 * CGFloat(JevDraw.hash(r, side + 9) % 4) / 3))
                }
            }

            // Everything on the road, where it was plus how far it has come this tick.
            let old = Dictionary(before.things.map { ($0.serial, $0) }, uniquingKeysWith: { a, _ in a })
            var things = after.things.map { thing in (thing, JevDraw.mix(Double(old[thing.serial]?.y ?? thing.y), Double(thing.y), t)) }
            let still = Set(after.things.map(\.serial))
            for thing in before.things where !still.contains(thing.serial) && thing.kind != .can {
                things.append((thing, Double(thing.y) + Double(thing.pace) * t))       // overtaken: it slides away behind
            }
            for (thing, at) in things where y(at) > -row * 4 && y(at + Double(thing.length)) < height + row * 4 {
                let middle = x(Double(thing.lane))
                switch thing.kind {
                case .can: can(g, at: CGPoint(x: middle, y: y(at + 0.5)), size: row, since: since)
                case .car: car(g, at: CGPoint(x: middle, y: y(at + 1)), width: lane * 0.56, length: row * 1.85,
                               tint: JevDrive.tints[thing.paint % JevDrive.tints.count])
                case .truck: truck(g, at: CGPoint(x: middle, y: y(at + 1.5)), width: lane * 0.66, length: row * 2.85,
                                   tint: JevDrive.tints[(thing.paint + 2) % JevDrive.tints.count])
                }
            }

            // The car: gliding into its lane, leaning into the turn.
            let swerve = Double(after.lane - before.lane)
            let at = CGPoint(x: x(JevDraw.mix(Double(before.lane), Double(after.lane), JevDraw.smooth(t))), y: y(camera + 1))
            if let crash, over {
                car(g, at: at, width: lane * 0.6, length: row * 1.9, tint: (0.86, 0.10, 0.12), lean: 0.5, sport: true)
                JevDraw.blast(g, at: CGPoint(x: x(Double(crash.lane)), y: y(camera + 1.6)), size: row * 1.1, age: since)
            } else {
                if after.speed >= 3 {                                                // wind past the car
                    for streak in 0..<(after.speed == 4 ? 6 : 3) {
                        let sx = at.x + CGFloat(JevDraw.hash(streak, 1) % 100 - 50) / 50 * lane * 0.45
                        let phase = (Double(JevDraw.hash(streak, 2) % 100) / 100 + t).truncatingRemainder(dividingBy: 1)
                        let sy = at.y + row * CGFloat(0.4 + 1.8 * phase)
                        g.fill(Path(roundedRect: CGRect(x: sx, y: sy, width: 1.5, height: row * 0.7), cornerRadius: 0.75),
                               with: .color(.white.opacity(0.35 * (1 - phase))))
                    }
                }
                car(g, at: at, width: lane * 0.6, length: row * 1.9, tint: (0.86, 0.10, 0.12), lean: sin(t * .pi) * 0.16 * swerve, sport: true)
            }

            dashboard(g, size)
            if over { JevDraw.curtain(g, size, title: ending + "！", detail: "开了 \(after.y) 格 · 超车 \(after.passed) 辆") }
        }

        /// Speed, distance and the fuel gauge, over the top of the road.
        private func dashboard(_ g: GraphicsContext, _ size: CGSize) {
            let unit = size.width / 26
            let box = CGRect(x: 10, y: 10, width: size.width - 20, height: unit * 3.4)
            JevDraw.panel(g, box)
            JevDraw.text(g, "\(after.speed * 30)", at: CGPoint(x: box.minX + unit * 0.8, y: box.midY - unit * 0.35), size: unit * 1.8, anchor: .leading)
            JevDraw.text(g, "km/h", at: CGPoint(x: box.minX + unit * 0.9, y: box.midY + unit * 1.0), size: unit * 0.65, weight: .bold,
                         colour: .white.opacity(0.75), anchor: .leading, shadow: false)
            JevDraw.text(g, String(format: "%.1f km", Double(after.y) * 0.005), at: CGPoint(x: box.midX - unit * 1.5, y: box.midY - unit * 0.35),
                         size: unit * 1.05, anchor: .center)
            JevDraw.text(g, "超车 \(after.passed)", at: CGPoint(x: box.midX - unit * 1.5, y: box.midY + unit * 0.95), size: unit * 0.65,
                         weight: .bold, colour: .white.opacity(0.75), shadow: false)
            // The gauge: green to red as it empties, and it blinks when nearly dry.
            let fuel = Double(max(after.fuel, 0)) / Double(JevDrive.tank)
            let gauge = CGRect(x: box.maxX - unit * 8.2, y: box.midY - unit * 0.35, width: unit * 7.4, height: unit * 0.9)
            JevDraw.text(g, "⛽", at: CGPoint(x: gauge.minX - unit * 0.1, y: gauge.midY), size: unit * 0.9, anchor: .trailing, shadow: false)
            g.fill(Path(roundedRect: gauge, cornerRadius: gauge.height / 2), with: .color(.white.opacity(0.15)))
            let colour = fuel > 0.5 ? Color.green : fuel > 0.25 ? Color.yellow : Color.red
            let blink = fuel <= 0.2 && Int(since * 4) % 2 == 1
            g.fill(Path(roundedRect: CGRect(x: gauge.minX, y: gauge.minY, width: max(gauge.height, gauge.width * fuel), height: gauge.height),
                        cornerRadius: gauge.height / 2), with: .color(colour.opacity(blink ? 0.35 : 0.95)))
            JevDraw.text(g, "\(max(after.fuel, 0))", at: CGPoint(x: gauge.midX, y: gauge.maxY + unit * 0.75), size: unit * 0.65, weight: .bold,
                         colour: .white.opacity(0.8), shadow: false)
        }

        /// A car from above, nose up: a shadow, a body shaded round, glass, lights.
        private func car(_ g: GraphicsContext, at centre: CGPoint, width: CGFloat, length: CGFloat,
                         tint: (Double, Double, Double), lean: Double = 0, sport: Bool = false) {
            var g = g
            g.translateBy(x: centre.x, y: centre.y)
            g.rotate(by: .radians(lean))
            let body = CGRect(x: -width / 2, y: -length / 2, width: width, height: length)
            g.fill(Path(roundedRect: body.offsetBy(dx: 3, dy: 5), cornerRadius: width * 0.38), with: .color(.black.opacity(0.3)))
            g.fill(Path(roundedRect: body, cornerRadius: width * 0.38),
                   with: .linearGradient(Gradient(colors: [JevDraw.shade(tint, 0.55), JevDraw.shade(tint, 1), JevDraw.shade(tint, 1.35),
                                                          JevDraw.shade(tint, 1), JevDraw.shade(tint, 0.55)]),
                                         startPoint: CGPoint(x: -width / 2, y: 0), endPoint: CGPoint(x: width / 2, y: 0)))
            let glass = Color(red: 0.10, green: 0.16, blue: 0.26)
            g.fill(Path(roundedRect: CGRect(x: -width * 0.37, y: -length * 0.27, width: width * 0.74, height: length * 0.2), cornerRadius: width * 0.12),
                   with: .linearGradient(Gradient(colors: [glass, Color(red: 0.3, green: 0.42, blue: 0.58)]),
                                         startPoint: CGPoint(x: 0, y: -length * 0.27), endPoint: CGPoint(x: 0, y: -length * 0.07)))
            g.fill(Path(roundedRect: CGRect(x: -width * 0.33, y: length * 0.2, width: width * 0.66, height: length * 0.13), cornerRadius: width * 0.1),
                   with: .color(glass.opacity(0.92)))
            g.fill(Path(roundedRect: CGRect(x: -width * 0.33, y: -length * 0.05, width: width * 0.66, height: length * 0.23), cornerRadius: width * 0.12),
                   with: .color(JevDraw.shade(tint, 1.15)))
            if sport {
                for side in [-1.0, 1.0] {
                    g.fill(Path(CGRect(x: CGFloat(side) * width * 0.1 - width * 0.04, y: -length / 2 + 3, width: width * 0.08, height: length - 6)),
                           with: .color(.white.opacity(0.85)))
                }
            }
            for side in [-1.0, 1.0] {
                let sx = CGFloat(side) * width * 0.29
                g.fill(Path(ellipseIn: CGRect(x: sx - width * 0.1, y: -length / 2 + 1.5, width: width * 0.2, height: length * 0.06)),
                       with: .color(Color(red: 1, green: 0.97, blue: 0.78)))
                g.fill(Path(roundedRect: CGRect(x: sx - width * 0.11, y: length / 2 - length * 0.06, width: width * 0.22, height: length * 0.045),
                            cornerRadius: 1.5), with: .color(Color(red: 0.95, green: 0.1, blue: 0.1)))
            }
        }

        /// A lorry from above: a cab in front, a long box behind it.
        private func truck(_ g: GraphicsContext, at centre: CGPoint, width: CGFloat, length: CGFloat, tint: (Double, Double, Double)) {
            var g = g
            g.translateBy(x: centre.x, y: centre.y)
            let cab = CGRect(x: -width * 0.46, y: -length / 2, width: width * 0.92, height: length * 0.24)
            let box = CGRect(x: -width / 2, y: -length / 2 + length * 0.27, width: width, height: length * 0.73)
            g.fill(Path(roundedRect: CGRect(x: box.minX + 4, y: -length / 2 + 6, width: width, height: length), cornerRadius: 6), with: .color(.black.opacity(0.3)))
            g.fill(Path(roundedRect: cab, cornerRadius: width * 0.2),
                   with: .linearGradient(Gradient(colors: [JevDraw.shade(tint, 0.6), JevDraw.shade(tint, 1.2), JevDraw.shade(tint, 0.6)]),
                                         startPoint: CGPoint(x: cab.minX, y: 0), endPoint: CGPoint(x: cab.maxX, y: 0)))
            g.fill(Path(roundedRect: CGRect(x: cab.minX + width * 0.1, y: cab.minY + cab.height * 0.12, width: cab.width - width * 0.2, height: cab.height * 0.3),
                        cornerRadius: 3), with: .color(Color(red: 0.12, green: 0.18, blue: 0.28)))
            g.fill(Path(roundedRect: box, cornerRadius: 4),
                   with: .linearGradient(Gradient(colors: [Color(white: 0.62), Color(white: 0.9), Color(white: 0.62)]),
                                         startPoint: CGPoint(x: box.minX, y: 0), endPoint: CGPoint(x: box.maxX, y: 0)))
            var ridge = box.minY + box.height / 7
            while ridge < box.maxY - 2 {
                g.fill(Path(CGRect(x: box.minX + 3, y: ridge, width: box.width - 6, height: 1.2)), with: .color(.black.opacity(0.12)))
                ridge += box.height / 7
            }
            for side in [-1.0, 1.0] {
                g.fill(Path(roundedRect: CGRect(x: CGFloat(side) * width * 0.34 - width * 0.08, y: box.maxY - 4, width: width * 0.16, height: 3),
                            cornerRadius: 1), with: .color(.red))
            }
        }

        /// A red fuel can that glows so it can be seen from a distance.
        private func can(_ g: GraphicsContext, at p: CGPoint, size: CGFloat, since: Double) {
            let pulse = 0.8 + 0.2 * sin(since * 6)
            let glow = size * 0.95 * CGFloat(pulse)
            g.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: 2 * glow, height: 2 * glow)),
                   with: .radialGradient(Gradient(colors: [Color.yellow.opacity(0.55), .clear]), center: p, startRadius: 0, endRadius: glow))
            let body = CGRect(x: p.x - size * 0.32, y: p.y - size * 0.38, width: size * 0.64, height: size * 0.8)
            g.fill(Path(roundedRect: body, cornerRadius: size * 0.1), with: .color(Color(red: 0.85, green: 0.1, blue: 0.1)))
            g.fill(Path(roundedRect: CGRect(x: body.minX + size * 0.08, y: body.minY - size * 0.14, width: size * 0.3, height: size * 0.2), cornerRadius: 3),
                   with: .color(Color(red: 0.6, green: 0.05, blue: 0.05)))
            g.stroke(Path { path in
                path.move(to: CGPoint(x: body.minX + size * 0.1, y: body.minY + size * 0.1))
                path.addLine(to: CGPoint(x: body.maxX - size * 0.1, y: body.maxY - size * 0.1))
                path.move(to: CGPoint(x: body.maxX - size * 0.1, y: body.minY + size * 0.1))
                path.addLine(to: CGPoint(x: body.minX + size * 0.1, y: body.maxY - size * 0.1))
            }, with: .color(.white.opacity(0.45)), lineWidth: 1.5)
        }

        private func tree(_ g: GraphicsContext, at p: CGPoint, radius: CGFloat) {
            func disc(_ c: CGPoint, _ r: CGFloat, _ colour: Color) {
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(colour))
            }
            disc(CGPoint(x: p.x + radius * 0.25, y: p.y + radius * 0.3), radius, .black.opacity(0.25))
            disc(p, radius, Color(red: 0.13, green: 0.38, blue: 0.16))
            disc(CGPoint(x: p.x - radius * 0.22, y: p.y - radius * 0.22), radius * 0.62, Color(red: 0.2, green: 0.5, blue: 0.2))
            disc(CGPoint(x: p.x - radius * 0.35, y: p.y - radius * 0.38), radius * 0.25, Color(red: 0.35, green: 0.65, blue: 0.3))
        }
    }
}
