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
        let scene = Scene(before: previous, after: road, t: t, since: since, now: now, crash: wreck, over: over, ending: ending)
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    /// The traffic's paint: blue, teal, purple, yellow, white, green. Red is the player's alone.
    nonisolated private static let tints: [(Double, Double, Double)] = [
        (0.16, 0.42, 0.85), (0.10, 0.62, 0.62), (0.55, 0.30, 0.78), (0.95, 0.76, 0.15), (0.90, 0.91, 0.93), (0.20, 0.62, 0.30),
    ]
    /// What a lorry carries, as its roof shows it: a white box, a steel one, containers in colour.
    nonisolated private static let loads: [(Double, Double, Double)] = [
        (0.91, 0.91, 0.88), (0.68, 0.71, 0.74), (0.86, 0.43, 0.17), (0.21, 0.39, 0.65), (0.66, 0.19, 0.16), (0.31, 0.53, 0.37),
    ]

    /// The road from above, the car near the bottom, the world rolling toward it.
    /// The sun is high on the left: everything is lit from the top left and
    /// drops a soft shadow down and to the right.
    fileprivate struct Scene {
        let before: Road, after: Road, t: Double, since: Double, now: Double
        let crash: (lane: Int, y: Int)?, over: Bool, ending: String

        /// Where the world is on the canvas this frame.
        struct Frame {
            let width: CGFloat, height: CGFloat, verge: CGFloat, road: CGFloat, lane: CGFloat, row: CGFloat
            let camera: Double, base: CGFloat, first: Int, last: Int

            init(_ size: CGSize, camera: Double) {
                width = size.width; height = size.height
                verge = width * 0.13; road = width - 2 * verge
                lane = road / CGFloat(JevDrive.lanes); row = height / 17.5
                self.camera = camera
                base = height - row * 1.15
                first = Int(floor(camera)) - 4; last = Int(ceil(camera)) + 20
            }
            func y(_ world: Double) -> CGFloat { base - CGFloat(world - camera) * row }
            func x(_ lane: Double) -> CGFloat { verge + (CGFloat(lane) + 0.5) * self.lane }
            /// The kerb stones, the gravel beyond them, and the grass beyond that, on each side.
            var kerb: CGFloat { max(4, lane * 0.13) }
            var shoulder: CGFloat { verge * 0.2 }
            var grass: CGFloat { verge - kerb - shoulder }
            /// From the outer edge of the picture (0) to the gravel (1), on either side.
            func across(_ side: Int, _ u: Double) -> CGFloat { side == 0 ? grass * CGFloat(u) : width - grass * CGFloat(u) }
        }

        /// A vehicle or a can, where it is this frame, and whether it braked this tick.
        struct Placed { let thing: Thing, at: Double, braking: Bool }

        /// Something standing beside the road.
        struct Prop {
            enum Kind { case tree, pine, bush, lamp }
            let kind: Kind, at: CGPoint, size: CGFloat, seed: Int, side: Int
        }

        func paint(_ g: inout GraphicsContext, _ size: CGSize) {
            // The camera follows the car at an even pace through the tick.
            let f = Frame(size, camera: JevDraw.mix(Double(before.y), Double(after.y), t))
            let things = placed().filter { f.y($0.at) > -f.row * 4 && f.y($0.at + Double($0.thing.length)) < f.height + f.row * 4 }
            let props = scenery(f)
            // The car: gliding into its lane, leaning into the turn.
            let swerve = Double(after.lane - before.lane)
            let me = CGPoint(x: f.x(JevDraw.mix(Double(before.lane), Double(after.lane), JevDraw.smooth(t))), y: f.y(f.camera + 1))
            let wrecked = crash != nil && over
            let lean = wrecked ? 0.5 : sin(t * .pi) * 0.16 * swerve
            // How fast the world is going by: nothing below two rows a tick, everything at four.
            let pace = over ? 0 : JevDraw.mix(Double(before.speed), Double(after.speed), t)
            let rush = CGFloat(min(max((pace - 2) / 2, 0), 1))

            verges(g, f)
            asphalt(g, f, rush: rush)
            kerbs(g, f)
            shadows(g, f, things: things, props: props, me: me, lean: lean)
            for prop in props where prop.kind != .lamp { standing(g, prop) }

            for item in things { vehicle(g, f, item) }
            let red = (0.86, 0.10, 0.12)
            if wrecked, let crash {
                let spot = CGPoint(x: f.x(Double(crash.lane)), y: f.y(f.camera + 1.6))
                scorch(g, at: spot, size: f.row)
                skids(g, f, from: me, lean: lean)
                car(g, at: me, width: f.lane * 0.6, length: f.row * 1.9, tint: red, body: .sport, lean: lean)
                debris(g, at: spot, size: f.row, tint: red)
                JevDraw.blast(g, at: spot, size: f.row * 1.1, age: since)
            } else {
                wind(g, f, around: me, rush: rush)
                car(g, at: me, width: f.lane * 0.6, length: f.row * 1.9, tint: red, body: .sport, lean: lean,
                    braking: after.speed < before.speed, blink: t < 1 ? after.lane - before.lane : 0)
            }
            for prop in props where prop.kind == .lamp { lamp(g, f, prop) }

            rushing(g, f, rush: rush)
            light(g, f)
            dashboard(g, size)
            if over { JevDraw.curtain(g, size, title: ending + "！", detail: "开了 \(after.y) 格 · 超车 \(after.passed) 辆") }
        }

        /// Everything on the road, where it was plus how far it has come this tick.
        private func placed() -> [Placed] {
            let old = Dictionary(before.things.map { ($0.serial, $0) }, uniquingKeysWith: { a, _ in a })
            let ticked = after.y != before.y        // the car always moves: a tick that went by moved it
            var out = after.things.map { thing -> Placed in
                let was = old[thing.serial]
                let from = Double(was?.y ?? thing.y)
                let braking = ticked && was.map { thing.y - $0.y < thing.pace } ?? false   // held back behind something slower
                return Placed(thing: thing, at: JevDraw.mix(from, Double(thing.y), t), braking: braking)
            }
            let still = Set(after.things.map(\.serial))
            for thing in before.things where !still.contains(thing.serial) && thing.kind != .can {
                out.append(Placed(thing: thing, at: Double(thing.y) + Double(thing.pace) * t, braking: false))   // overtaken: it slides away behind
            }
            return out
        }

        // MARK: The ground

        /// Grass and the gravel shoulders either side of the road.
        private func verges(_ g: GraphicsContext, _ f: Frame) {
            g.fill(Path(CGRect(x: 0, y: 0, width: f.width, height: f.height)), with: .color(DriveArt.grass))
            // Patches of lusher and of drier grass.
            var lush = Path(), dry = Path()
            for r in f.first...f.last {
                for side in 0..<2 {
                    let h = JevDraw.hash(r, 300 + side)
                    guard h % 5 < 3 else { continue }
                    let w = f.grass * CGFloat(0.5 + 0.8 * DriveArt.unit(r, 310 + side))
                    let tall = f.row * CGFloat(0.8 + 1.5 * DriveArt.unit(r, 320 + side))
                    let centre = CGPoint(x: f.across(side, DriveArt.unit(r, 330 + side)), y: f.y(Double(r) + DriveArt.unit(r, 340 + side)))
                    let oval = CGRect(x: centre.x - w / 2, y: centre.y - tall / 2, width: w, height: tall)
                    if h % 5 == 0 { dry.addEllipse(in: oval) } else { lush.addEllipse(in: oval) }
                }
            }
            g.fill(lush, with: .color(DriveArt.lush.opacity(0.30)))
            g.fill(dry, with: .color(DriveArt.dry.opacity(0.30)))
            // Mown in bands, two rows wide.
            var mown = Path()
            var band = f.first - ((f.first % 4) + 4) % 4
            while band <= f.last {
                let top = f.y(Double(band) + 2), bottom = f.y(Double(band))
                mown.addRect(CGRect(x: 0, y: top, width: f.grass, height: bottom - top))
                mown.addRect(CGRect(x: f.width - f.grass, y: top, width: f.grass, height: bottom - top))
                band += 4
            }
            g.fill(mown, with: .color(.white.opacity(0.07)))

            // Gravel, from the grass to under the kerb.
            let shoulders = [CGRect(x: f.grass, y: -1, width: f.shoulder + f.kerb * 0.5, height: f.height + 2),
                             CGRect(x: f.width - f.grass - f.shoulder - f.kerb * 0.5, y: -1, width: f.shoulder + f.kerb * 0.5, height: f.height + 2)]
            var gravel = Path()
            for shoulder in shoulders { gravel.addRect(shoulder) }
            g.fill(gravel, with: .color(DriveArt.gravel))
            var pale = Path(), dark = Path(), fringe = Path()
            for r in f.first...f.last {
                for k in 0..<12 {
                    let side = k & 1
                    let d = f.row * CGFloat(0.04 + 0.05 * DriveArt.unit(r, 740 + k))
                    let x = f.grass + (side == 0 ? 0 : f.width - 2 * f.grass - f.shoulder) + f.shoulder * CGFloat(DriveArt.unit(r, 700 + k))
                    let grain = CGRect(x: x - d / 2, y: f.y(Double(r) + DriveArt.unit(r, 720 + k)) - d / 2, width: d, height: d)
                    if k % 3 == 0 { pale.addEllipse(in: grain) } else { dark.addEllipse(in: grain) }
                }
                // The grass edge is ragged: it creeps over the gravel.
                for k in 0..<6 {
                    let side = k & 1
                    let edge = side == 0 ? f.grass : f.width - f.grass
                    let reach = f.shoulder * CGFloat(0.12 + 0.25 * DriveArt.unit(r, 760 + k))
                    let tall = f.row * CGFloat(0.12 + 0.2 * DriveArt.unit(r, 790 + k))
                    let y = f.y(Double(r) + DriveArt.unit(r, 780 + k))
                    fringe.addEllipse(in: CGRect(x: edge - reach, y: y - tall / 2, width: reach * 2, height: tall))
                }
            }
            g.fill(dark, with: .color(.black.opacity(0.2)))
            g.fill(pale, with: .color(.white.opacity(0.28)))
            g.fill(fringe, with: .color(DriveArt.grass))

            // Tufts, and flowers here and there.
            var deep = Path(), bright = Path()
            var blooms = [Path](repeating: Path(), count: DriveArt.flowers.count)
            for r in f.first...f.last {
                for k in 0..<8 {
                    let side = k & 1
                    let root = CGPoint(x: f.across(side, 1.05 * DriveArt.unit(r, 400 + k)), y: f.y(Double(r) + DriveArt.unit(r, 420 + k)))
                    let s = f.row * CGFloat(0.06 + 0.06 * DriveArt.unit(r, 440 + k))
                    if k % 3 == 0 { DriveArt.tuft(&bright, at: root, size: s) } else { DriveArt.tuft(&deep, at: root, size: s) }
                }
                for side in 0..<2 where JevDraw.hash(r, 600 + side) % 4 == 0 {
                    let colour = JevDraw.hash(r, 610 + side) % blooms.count
                    let u = 0.1 + 0.8 * DriveArt.unit(r, 620 + side), v = DriveArt.unit(r, 630 + side)
                    for k in 0..<5 {
                        let x = f.across(side, u) + f.row * CGFloat(DriveArt.unit(r, 640 + side * 8 + k) - 0.5) * 0.5
                        let y = f.y(Double(r) + v + (DriveArt.unit(r, 660 + side * 8 + k) - 0.5) * 0.5)
                        let d = f.row * CGFloat(0.06 + 0.04 * DriveArt.unit(r, 680 + side * 8 + k))
                        blooms[colour].addEllipse(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
                    }
                }
            }
            let blade = StrokeStyle(lineWidth: max(0.7, f.row * 0.022), lineCap: .round, lineJoin: .round)
            g.stroke(deep, with: .color(DriveArt.lush.opacity(0.6)), style: blade)
            g.stroke(bright, with: .color(DriveArt.dry.opacity(0.75)), style: blade)
            for (index, bloom) in blooms.enumerated() { g.fill(bloom, with: .color(DriveArt.flowers[index])) }
        }

        /// The road: asphalt with its grit, cracks and patches, lanes polished by the tyres, worn paint.
        private func asphalt(_ g: GraphicsContext, _ f: Frame, rush: CGFloat) {
            let left = f.verge, right = f.verge + f.road
            g.fill(Path(CGRect(x: left - 1, y: -1, width: f.road + 2, height: f.height + 2)),
                   with: .linearGradient(Gradient(stops: DriveArt.asphaltStops), startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0)))
            var grit = Path(), glints = Path(), patches = Path(), tar = Path()
            for r in f.first...f.last {
                // The surface has worn unevenly: soft stains, darker and lighter.
                let stain = f.lane * CGFloat(0.5 + 0.8 * DriveArt.unit(r, 820))
                let centre = CGPoint(x: left + f.road * CGFloat(DriveArt.unit(r, 800)), y: f.y(Double(r) + DriveArt.unit(r, 810)))
                let tone: Color = r & 1 == 0 ? .black : .white
                g.fill(Path(ellipseIn: CGRect(x: centre.x - stain, y: centre.y - stain, width: 2 * stain, height: 2 * stain)),
                       with: .radialGradient(Gradient(colors: [tone.opacity(r & 1 == 0 ? 0.1 : 0.035), tone.opacity(0)]),
                                             center: centre, startRadius: 0, endRadius: stain))
                for k in 0..<18 {
                    let d = f.row * CGFloat(0.035 + 0.045 * DriveArt.unit(r, 900 + k))
                    let speck = CGRect(x: left + f.road * CGFloat(DriveArt.unit(r, 840 + k)), y: f.y(Double(r) + DriveArt.unit(r, 870 + k)),
                                       width: d, height: d * 0.8)
                    if k % 3 == 0 { glints.addRect(speck) } else { grit.addRect(speck) }
                }
                // A patched repair now and then.
                if JevDraw.hash(r, 930) % 13 == 0 {
                    let w = f.lane * CGFloat(0.45 + 0.4 * DriveArt.unit(r, 932)), tall = f.row * CGFloat(0.6 + 1.1 * DriveArt.unit(r, 933))
                    let x = f.x(Double(JevDraw.hash(r, 931) % JevDrive.lanes)) + f.lane * CGFloat(DriveArt.unit(r, 934) - 0.5) * 0.5
                    patches.addRoundedRect(in: CGRect(x: x - w / 2, y: f.y(Double(r)) - tall, width: w, height: tall), cornerSize: CGSize(width: 2, height: 2))
                }
                // Cracks, sealed with tar.
                if JevDraw.hash(r, 940) % 7 == 0 {
                    var p = CGPoint(x: left + f.road * CGFloat(0.04 + 0.92 * DriveArt.unit(r, 941)), y: f.y(Double(r) + DriveArt.unit(r, 942)))
                    tar.move(to: p)
                    for k in 0..<4 {
                        p = CGPoint(x: p.x + f.lane * CGFloat(DriveArt.unit(r, 943 + k) - 0.5) * 0.3,
                                    y: p.y - f.row * CGFloat(0.18 + 0.25 * DriveArt.unit(r, 947 + k)))
                        tar.addLine(to: p)
                        if k == 1 {
                            let side: CGFloat = DriveArt.unit(r, 951) < 0.5 ? -1 : 1
                            tar.addLine(to: CGPoint(x: p.x + side * f.lane * 0.14, y: p.y - f.row * 0.1))
                            tar.move(to: p)
                        }
                    }
                }
            }
            g.fill(patches, with: .color(.black.opacity(0.07)))
            g.stroke(patches, with: .color(.black.opacity(0.13)), lineWidth: max(0.7, f.row * 0.025))
            g.fill(grit, with: .color(.black.opacity(0.26)))
            g.fill(glints, with: .color(.white.opacity(0.12)))
            g.stroke(tar, with: .color(Color(red: 0.07, green: 0.075, blue: 0.085).opacity(0.5)),
                     style: StrokeStyle(lineWidth: max(0.8, f.row * 0.03), lineCap: .round, lineJoin: .round))
            g.stroke(tar.offsetBy(dx: -0.6, dy: -0.6), with: .color(.white.opacity(0.06)), lineWidth: 0.5)

            // The paint: solid lines along the edges, dashes between the lanes, both worn;
            // at speed the dashes smear into the direction they run.
            let paint = max(1.5, f.lane * 0.055)
            let edges = [left + f.lane * 0.08, right - f.lane * 0.08 - paint]
            var solid = Path(), dashes = [Path(), Path(), Path()], near = Path(), far = Path(), worn = Path()
            for x in edges { solid.addRect(CGRect(x: x, y: -2, width: paint, height: f.height + 4)) }
            let corner = CGSize(width: paint * 0.4, height: paint * 0.4)
            for l in 1..<JevDrive.lanes {
                let x = left + CGFloat(l) * f.lane - paint / 2
                var r = f.first - ((f.first % 3) + 3) % 3
                while r <= f.last {
                    let top = f.y(Double(r) + 1.7), bottom = f.y(Double(r))
                    let dash = CGRect(x: x, y: top, width: paint, height: bottom - top)
                    dashes[JevDraw.hash(r, 950 + l) % 3].addRoundedRect(in: dash, cornerSize: corner)
                    if rush > 0.01 {
                        near.addRoundedRect(in: dash.insetBy(dx: 0, dy: -f.row * 0.16 * rush), cornerSize: corner)
                        far.addRoundedRect(in: dash.insetBy(dx: paint * 0.1, dy: -f.row * 0.4 * rush), cornerSize: corner)
                    }
                    for k in 0..<5 {
                        let d = paint * CGFloat(0.35 + 0.45 * DriveArt.unit(r * 8 + l, 980 + k))
                        worn.addEllipse(in: CGRect(x: x + paint * CGFloat(DriveArt.unit(r * 8 + l, 970 + k)) - d / 2,
                                                   y: top + (bottom - top) * CGFloat(DriveArt.unit(r * 8 + l, 960 + k)), width: d, height: d * 0.8))
                    }
                    r += 3
                }
            }
            for r in f.first...f.last {
                for (side, x) in edges.enumerated() {
                    for k in 0..<2 {
                        let d = paint * CGFloat(0.35 + 0.45 * DriveArt.unit(r * 2 + side, 990 + k))
                        worn.addEllipse(in: CGRect(x: x + paint * CGFloat(DriveArt.unit(r * 2 + side, 993 + k)) - d / 2,
                                                   y: f.y(Double(r) + DriveArt.unit(r * 2 + side, 996 + k)), width: d, height: d * 0.8))
                    }
                }
            }
            if rush > 0.01 {
                g.fill(far, with: .color(DriveArt.paint.opacity(0.07 * Double(rush))))
                g.fill(near, with: .color(DriveArt.paint.opacity(0.14 * Double(rush))))
            }
            g.fill(solid, with: .color(DriveArt.paint.opacity(0.88)))
            for (index, dash) in dashes.enumerated() { g.fill(dash, with: .color(DriveArt.paint.opacity([0.9, 0.8, 0.7][index]))) }
            g.fill(worn, with: .color(DriveArt.asphalt.opacity(0.6)))
        }

        /// Kerb stones, red and white, rounded on top: lit on the left, shaded on the right, and each dropping a shadow to its right.
        private func kerbs(_ g: GraphicsContext, _ f: Frame) {
            let lefts = [f.verge - f.kerb, f.verge + f.road]
            var red = Path(), white = Path(), joints = Path()
            for r in f.first...f.last {
                let top = f.y(Double(r) + 1), bottom = f.y(Double(r))
                for x in lefts {
                    let stone = CGRect(x: x, y: top, width: f.kerb, height: bottom - top)
                    if r & 1 == 0 { red.addRect(stone) } else { white.addRect(stone) }
                    joints.addRect(CGRect(x: x, y: bottom - 0.6, width: f.kerb, height: 1.2))
                }
            }
            for x in lefts {
                let edge = x + f.kerb, fall = f.kerb * 0.8
                g.fill(Path(CGRect(x: edge, y: 0, width: fall, height: f.height)),
                       with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .black.opacity(0)]),
                                             startPoint: CGPoint(x: edge, y: 0), endPoint: CGPoint(x: edge + fall, y: 0)))
            }
            g.fill(red, with: .color(DriveArt.kerbRed))
            g.fill(white, with: .color(DriveArt.kerbWhite))
            for x in lefts {
                g.fill(Path(CGRect(x: x, y: 0, width: f.kerb, height: f.height)),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.32), .white.opacity(0), .black.opacity(0.3)]),
                                             startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + f.kerb, y: 0)))
            }
            g.fill(joints, with: .color(.black.opacity(0.28)))
        }

        // MARK: Shadows

        /// Every shadow in one soft pass, so where two meet they do not darken twice.
        private func shadows(_ g: GraphicsContext, _ f: Frame, things: [Placed], props: [Prop], me: CGPoint, lean: Double) {
            var shade = Path()
            for prop in props { shadow(of: prop, f, into: &shade) }
            for item in things {
                let x = f.x(Double(item.thing.lane))
                switch item.thing.kind {
                case .can:
                    let centre = CGPoint(x: x + f.row * 0.1, y: f.y(item.at + 0.5) + f.row * 0.14)
                    shade.addRoundedRect(in: CGRect(x: centre.x - f.row * 0.3, y: centre.y - f.row * 0.32, width: f.row * 0.6, height: f.row * 0.72),
                                         cornerSize: CGSize(width: f.row * 0.1, height: f.row * 0.1))
                case .car:
                    shade.addPath(DriveArt.shell(width: f.lane * 0.56, length: f.row * 1.85, body: DriveArt.body(of: item.thing.serial)),
                                  transform: CGAffineTransform(translationX: x + f.row * 0.12, y: f.y(item.at + 1) + f.row * 0.17))
                case .truck:
                    let w = f.lane * 0.66, l = f.row * 2.85
                    shade.addRoundedRect(in: CGRect(x: x - w / 2 + f.row * 0.22, y: f.y(item.at + 1.5) - l / 2 + f.row * 0.3, width: w, height: l),
                                         cornerSize: CGSize(width: w * 0.12, height: w * 0.12))
                }
            }
            shade.addPath(DriveArt.shell(width: f.lane * 0.6, length: f.row * 1.9, body: .sport),
                          transform: CGAffineTransform(translationX: me.x + f.row * 0.12, y: me.y + f.row * 0.17).rotated(by: CGFloat(lean)))
            var soft = g
            soft.addFilter(.blur(radius: f.row * 0.09))
            soft.fill(shade, with: .color(DriveArt.shadow.opacity(0.4)))
        }

        private func shadow(of prop: Prop, _ f: Frame, into shade: inout Path) {
            let r = prop.size
            switch prop.kind {
            case .tree: shade.addPath(canopy(prop, scale: 1, dx: 0.45, dy: 0.62))
            case .pine: shade.addPath(star(prop, scale: 1, turn: 0, dx: 0.5, dy: 0.7))
            case .bush: shade.addPath(canopy(prop, scale: 1, dx: 0.3, dy: 0.42))
            case .lamp:
                // A tall pole: its shadow is long, and the arm's falls well away from the arm.
                let fall = CGSize(width: f.row * 0.75, height: f.row * 1.05)
                let head = lampHead(prop, f)
                var pole = Path()
                pole.move(to: prop.at)
                pole.addLine(to: CGPoint(x: prop.at.x + fall.width, y: prop.at.y + fall.height))
                pole.addLine(to: CGPoint(x: head.x + fall.width, y: head.y + fall.height))
                shade.addPath(pole.strokedPath(StrokeStyle(lineWidth: r * 0.1, lineCap: .round, lineJoin: .round)))
                shade.addRoundedRect(in: lampHousing(prop, f).offsetBy(dx: fall.width, dy: fall.height), cornerSize: CGSize(width: r * 0.06, height: r * 0.06))
            }
        }

        // MARK: Beside the road

        /// The trees, bushes and lamp posts in view.
        private func scenery(_ f: Frame) -> [Prop] {
            var props: [Prop] = []
            for r in stride(from: f.last, through: f.first, by: -1) {
                for side in 0..<2 {
                    let h = JevDraw.hash(r, 20 + side)
                    // Lamp posts on the shoulders every ten rows, the two sides staggered.
                    if ((r % 10) + 10) % 10 == side * 5 {
                        let x = side == 0 ? f.grass + f.shoulder * 0.45 : f.width - f.grass - f.shoulder * 0.45
                        props.append(Prop(kind: .lamp, at: CGPoint(x: x, y: f.y(Double(r) + 0.5)), size: f.row, seed: h, side: side))
                    }
                    if h % 20 < 9 {
                        let radius = f.verge * CGFloat(0.32 + 0.2 * DriveArt.unit(r, 30 + side))
                        let reach = min(f.grass * CGFloat(0.2 + 0.7 * DriveArt.unit(r, 40 + side)), f.grass + f.shoulder * 0.8 - radius)
                        props.append(Prop(kind: (h / 20) % 4 == 0 ? .pine : .tree, at: CGPoint(x: side == 0 ? reach : f.width - reach, y: f.y(Double(r) + DriveArt.unit(r, 50 + side))),
                                          size: radius, seed: h, side: side))
                    } else if h % 20 < 13 {
                        let radius = f.verge * CGFloat(0.13 + 0.07 * DriveArt.unit(r, 60 + side))
                        let reach = min(f.grass * CGFloat(0.3 + 0.7 * DriveArt.unit(r, 70 + side)), f.grass + f.shoulder * 0.3 - radius)
                        props.append(Prop(kind: .bush, at: CGPoint(x: side == 0 ? reach : f.width - reach, y: f.y(Double(r) + DriveArt.unit(r, 80 + side))),
                                          size: radius, seed: h, side: side))
                    }
                }
            }
            return props
        }

        /// A cloud of leaves: the tree's lobes, scaled and moved in units of its radius.
        private func canopy(_ prop: Prop, scale: CGFloat, dx: CGFloat, dy: CGFloat) -> Path {
            let lobes = DriveArt.canopies[(prop.seed / 7) % DriveArt.canopies.count]
            var path = Path()
            for lobe in lobes {
                let r = lobe.r * scale * prop.size
                let x = prop.at.x + (lobe.x * scale + dx) * prop.size, y = prop.at.y + (lobe.y * scale + dy) * prop.size
                path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            return path
        }

        /// A pine's star of branches, scaled, turned and moved in units of its radius.
        private func star(_ prop: Prop, scale: CGFloat, turn: Double, dx: CGFloat, dy: CGFloat) -> Path {
            let c = CGFloat(cos(turn + Double(prop.seed % 10) * 0.3)), s = CGFloat(sin(turn + Double(prop.seed % 10) * 0.3))
            var path = Path()
            for (index, point) in DriveArt.pine.enumerated() {
                let x = (point.x * c - point.y * s) * scale + dx, y = (point.x * s + point.y * c) * scale + dy
                let at = CGPoint(x: prop.at.x + x * prop.size, y: prop.at.y + y * prop.size)
                if index == 0 { path.move(to: at) } else { path.addLine(to: at) }
            }
            path.closeSubpath()
            return path
        }

        /// A tree, a pine or a bush, in layers lit from the top left.
        private func standing(_ g: GraphicsContext, _ prop: Prop) {
            let r = prop.size
            let sun = CGPoint(x: prop.at.x - r * 0.4, y: prop.at.y - r * 0.45)
            switch prop.kind {
            case .tree, .bush:
                // Each lobe of leaves is a ball: a dark rim where it turns from the sun, a body, and the sun on its upper left.
                let leaves = DriveArt.foliage[prop.seed % DriveArt.foliage.count]
                let lobes = DriveArt.canopies[(prop.seed / 7) % DriveArt.canopies.count]
                var rim = Path(), body = Path(), lit = Path(), glints = Path()
                for (index, lobe) in lobes.enumerated() {
                    let c = CGPoint(x: prop.at.x + lobe.x * r, y: prop.at.y + lobe.y * r), lr = lobe.r * r
                    rim.addEllipse(in: CGRect(x: c.x - lr, y: c.y - lr, width: 2 * lr, height: 2 * lr))
                    let br = lr * 0.84, bc = CGPoint(x: c.x - lr * 0.1, y: c.y - lr * 0.13)
                    body.addEllipse(in: CGRect(x: bc.x - br, y: bc.y - br, width: 2 * br, height: 2 * br))
                    guard lobe.x + lobe.y < 0.3 else { continue }
                    let hr = lr * (index == 0 ? 0.42 : 0.5), hc = CGPoint(x: c.x - lr * 0.3, y: c.y - lr * 0.34)
                    lit.addEllipse(in: CGRect(x: hc.x - hr, y: hc.y - hr, width: 2 * hr, height: 2 * hr))
                    let gr = lr * 0.12, gc = CGPoint(x: c.x - lr * 0.42, y: c.y - lr * 0.48)
                    glints.addEllipse(in: CGRect(x: gc.x - gr, y: gc.y - gr, width: 2 * gr, height: 2 * gr))
                }
                g.fill(rim, with: .color(leaves.dark))
                g.fill(body, with: .radialGradient(Gradient(colors: [leaves.mid, JevDraw.shade(leaves.midRGB, 0.8)]), center: sun,
                                                   startRadius: r * 0.3, endRadius: r * 1.6))
                g.fill(lit, with: .color(leaves.light.opacity(0.8)))
                if prop.kind == .bush && prop.seed % 3 == 0 {
                    // Some bushes are in flower.
                    var petals = Path()
                    for k in 0..<6 {
                        let angle = Double(k) * 1.2 + Double(prop.seed % 11)
                        let at = CGPoint(x: prop.at.x + CGFloat(cos(angle)) * r * 0.55, y: prop.at.y + CGFloat(sin(angle)) * r * 0.5)
                        petals.addEllipse(in: CGRect(x: at.x - r * 0.11, y: at.y - r * 0.11, width: r * 0.22, height: r * 0.22))
                    }
                    g.fill(petals, with: .color(DriveArt.flowers[(prop.seed / 3) % DriveArt.flowers.count]))
                } else {
                    g.fill(glints, with: .color(.white.opacity(0.28)))
                }
            case .pine:
                // Branches in a star, tier on tier toward the sun, the tip catching it.
                let needles = DriveArt.needles
                g.fill(star(prop, scale: 1, turn: 0, dx: 0, dy: 0),
                       with: .radialGradient(Gradient(colors: [needles.mid, needles.dark]), center: sun, startRadius: 0, endRadius: r * 1.5))
                var boughs = Path()
                for k in 0..<11 {
                    let angle = Double(k) / 11 * 2 * .pi + Double(prop.seed % 10) * 0.3
                    boughs.move(to: prop.at)
                    boughs.addLine(to: CGPoint(x: prop.at.x + CGFloat(cos(angle)) * r * 0.9, y: prop.at.y + CGFloat(sin(angle)) * r * 0.9))
                }
                g.stroke(boughs, with: .color(needles.dark.opacity(0.7)), lineWidth: max(0.6, r * 0.05))
                g.fill(star(prop, scale: 0.76, turn: 0.2, dx: -0.06, dy: -0.07), with: .color(needles.mid))
                g.fill(star(prop, scale: 0.52, turn: 0.4, dx: -0.11, dy: -0.13), with: .color(JevDraw.shade(needles.lightRGB, 0.82)))
                g.fill(star(prop, scale: 0.3, turn: 0.6, dx: -0.15, dy: -0.18), with: .color(needles.light))
                let tip = CGRect(x: prop.at.x - r * 0.24, y: prop.at.y - r * 0.28, width: r * 0.14, height: r * 0.14)
                g.fill(Path(ellipseIn: tip), with: .color(JevDraw.shade(needles.lightRGB, 1.3)))
            case .lamp: break
            }
        }

        private func lampHead(_ prop: Prop, _ f: Frame) -> CGPoint {
            CGPoint(x: prop.side == 0 ? f.verge + f.lane * 0.02 : f.verge + f.road - f.lane * 0.02, y: prop.at.y)
        }

        /// The lamp at the end of the arm, reaching on a little further out over the road.
        private func lampHousing(_ prop: Prop, _ f: Frame) -> CGRect {
            let head = lampHead(prop, f), long = f.row * 0.36, thick = f.row * 0.13
            return CGRect(x: prop.side == 0 ? head.x - long * 0.3 : head.x - long * 0.7, y: head.y - thick / 2, width: long, height: thick)
        }

        /// A street lamp, over everything on the road: a pole on the shoulder, an arm reaching out over the edge line.
        private func lamp(_ g: GraphicsContext, _ f: Frame, _ prop: Prop) {
            let s = f.row, head = lampHead(prop, f)
            var arm = Path()
            arm.move(to: prop.at)
            arm.addQuadCurve(to: head, control: CGPoint(x: (prop.at.x + head.x) / 2, y: prop.at.y - s * 0.06))
            g.stroke(arm, with: .color(Color(white: 0.32)), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
            g.stroke(arm.offsetBy(dx: 0, dy: -s * 0.012), with: .color(Color(white: 0.82).opacity(0.7)), style: StrokeStyle(lineWidth: s * 0.018, lineCap: .round))
            let cap = CGRect(x: prop.at.x - s * 0.085, y: prop.at.y - s * 0.085, width: s * 0.17, height: s * 0.17)
            g.fill(Path(ellipseIn: cap), with: .radialGradient(Gradient(colors: [Color(white: 0.8), Color(white: 0.28)]),
                                                                center: CGPoint(x: cap.minX + cap.width * 0.35, y: cap.minY + cap.height * 0.3),
                                                                startRadius: 0, endRadius: cap.width * 0.7))
            let housing = lampHousing(prop, f)
            let shape = Path(roundedRect: housing, cornerRadius: housing.height / 2)
            g.fill(shape, with: .linearGradient(Gradient(colors: [Color(white: 0.78), Color(white: 0.42), Color(white: 0.3)]),
                                                startPoint: CGPoint(x: housing.midX, y: housing.minY), endPoint: CGPoint(x: housing.midX, y: housing.maxY)))
            g.stroke(shape, with: .color(.black.opacity(0.4)), lineWidth: max(0.5, s * 0.018))
        }

        // MARK: On the road

        private func vehicle(_ g: GraphicsContext, _ f: Frame, _ item: Placed) {
            let x = f.x(Double(item.thing.lane))
            switch item.thing.kind {
            case .can:
                can(g, at: CGPoint(x: x, y: f.y(item.at + 0.5)), size: f.row)
            case .car:
                let body = DriveArt.body(of: item.thing.serial), paint = item.thing.paint % JevDrive.tints.count
                car(g, at: CGPoint(x: x, y: f.y(item.at + 1)), width: f.lane * 0.56, length: f.row * 1.85, tint: JevDrive.tints[paint],
                    body: body, braking: item.braking, taxi: paint == 3 && body == .sedan)
            case .truck:
                truck(g, at: CGPoint(x: x, y: f.y(item.at + 1.5)), width: f.lane * 0.66, length: f.row * 2.85,
                      tint: JevDrive.tints[(item.thing.paint + 2) % JevDrive.tints.count],
                      load: JevDrive.loads[item.thing.serial % JevDrive.loads.count], braking: item.braking)
            }
        }

        /// A car from above, nose up: tyres, a body shaded round, glass, a roof in the sun, lights.
        private func car(_ g: GraphicsContext, at centre: CGPoint, width w: CGFloat, length l: CGFloat, tint: (Double, Double, Double),
                         body: DriveArt.Body, lean: Double = 0, braking: Bool = false, blink: Int = 0, taxi: Bool = false) {
            var g = g
            g.translateBy(x: centre.x, y: centre.y)
            if lean != 0 { g.rotate(by: .radians(lean)) }
            let hw = w / 2, hl = l / 2
            func along(_ share: CGFloat) -> CGFloat { -hl + l * share }

            // Tyres, just showing at the four corners.
            var tyres = Path()
            for axle in [along(0.2), along(0.79)] {
                for side in [-1, 1] as [CGFloat] {
                    tyres.addRoundedRect(in: CGRect(x: side * (hw - w * 0.07) - w * 0.1, y: axle - l * 0.07, width: w * 0.2, height: l * 0.14),
                                         cornerSize: CGSize(width: w * 0.05, height: w * 0.05))
                }
            }
            g.fill(tyres, with: .color(Color(white: 0.09)))

            // The body: round across, lit from the left, a little brighter toward the nose.
            let shell = DriveArt.shell(width: w, length: l, body: body)
            g.fill(shell, with: .linearGradient(Gradient(stops: DriveArt.paintwork(tint)), startPoint: CGPoint(x: -hw, y: 0), endPoint: CGPoint(x: hw, y: 0)))
            g.fill(shell, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0), .black.opacity(0.16)]),
                                                startPoint: CGPoint(x: 0, y: -hl), endPoint: CGPoint(x: 0, y: hl)))
            var inside = g
            inside.clip(to: shell)
            if body == .sport {
                // Racing stripes, nose to tail.
                var stripes = Path()
                for side in [-1, 1] as [CGFloat] { stripes.addRect(CGRect(x: side * w * 0.085 - w * 0.045, y: -hl, width: w * 0.09, height: l)) }
                inside.fill(stripes, with: .color(.white.opacity(0.9)))
            } else if body != .van {
                // The creases in the bonnet.
                var creases = Path()
                for side in [-1, 1] as [CGFloat] {
                    creases.move(to: CGPoint(x: side * w * 0.2, y: along(0.05)))
                    creases.addLine(to: CGPoint(x: side * w * 0.25, y: along(DriveArt.cabin(body).0 - 0.02)))
                }
                inside.stroke(creases, with: .color(.black.opacity(0.13)), lineWidth: max(0.5, w * 0.025))
            }

            // Lights: headlamps at the nose, tail lamps that flare when it brakes.
            var heads = Path(), tails = Path()
            for side in [-1, 1] as [CGFloat] {
                heads.addEllipse(in: CGRect(x: side * hw * 0.6 - w * 0.13, y: -hl + l * 0.01, width: w * 0.26, height: l * 0.055))
                tails.addRoundedRect(in: CGRect(x: side * hw * 0.62 - w * 0.14, y: hl - l * 0.045, width: w * 0.28, height: l * 0.04),
                                     cornerSize: CGSize(width: w * 0.04, height: w * 0.04))
            }
            inside.fill(heads, with: .color(Color(red: 1, green: 0.97, blue: 0.84)))
            inside.fill(tails, with: .color(braking ? Color(red: 1, green: 0.28, blue: 0.2) : Color(red: 0.7, green: 0.05, blue: 0.07)))

            // The glasshouse: a windscreen bowed at its foot, thin side windows, a rear window narrowing to the tail, and the roof over them.
            let cabin = DriveArt.cabin(body)
            let front = along(cabin.0), roofFront = along(cabin.1), roofBack = along(cabin.2), back = along(cabin.3)
            let van = body == .van
            let roofWidth = w * (van ? 0.74 : 0.6), screenFoot = w * (van ? 0.78 : 0.74), tail = w * (van ? 0.7 : 0.5)
            let bow = l * (van ? 0.012 : 0.03)
            var windscreen = Path()
            windscreen.move(to: CGPoint(x: -screenFoot / 2, y: front + bow))
            windscreen.addQuadCurve(to: CGPoint(x: screenFoot / 2, y: front + bow), control: CGPoint(x: 0, y: front - bow))
            windscreen.addLine(to: CGPoint(x: roofWidth / 2 + w * 0.02, y: roofFront + l * 0.01))
            windscreen.addLine(to: CGPoint(x: -roofWidth / 2 - w * 0.02, y: roofFront + l * 0.01))
            windscreen.closeSubpath()
            var rearWindow = Path()
            rearWindow.move(to: CGPoint(x: -roofWidth / 2 - w * 0.02, y: roofBack - l * 0.01))
            rearWindow.addLine(to: CGPoint(x: roofWidth / 2 + w * 0.02, y: roofBack - l * 0.01))
            rearWindow.addLine(to: CGPoint(x: tail / 2, y: back - bow * 0.5))
            rearWindow.addQuadCurve(to: CGPoint(x: -tail / 2, y: back - bow * 0.5), control: CGPoint(x: 0, y: back + bow * 0.6))
            rearWindow.closeSubpath()
            var sides = Path()
            for side in [-1, 1] as [CGFloat] {
                sides.addRoundedRect(in: CGRect(x: side * (roofWidth / 2 + w * 0.012) - w * 0.035, y: roofFront - l * 0.01, width: w * 0.07,
                                                height: roofBack - roofFront + l * 0.02), cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
            }
            let rounded = StrokeStyle(lineWidth: w * 0.04, lineJoin: .round)
            let sky = GraphicsContext.Shading.linearGradient(Gradient(colors: [DriveArt.glass[0], DriveArt.glass[1], DriveArt.glass[2]]),
                                                             startPoint: CGPoint(x: -screenFoot / 2, y: front), endPoint: CGPoint(x: screenFoot * 0.3, y: roofFront))
            let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: [DriveArt.glass[2], DriveArt.glass[3]]),
                                                               startPoint: CGPoint(x: -roofWidth / 2, y: roofBack), endPoint: CGPoint(x: roofWidth / 2, y: back))
            g.fill(sides, with: .color(DriveArt.glass[3]))
            g.fill(windscreen, with: sky)
            g.stroke(windscreen, with: sky, style: rounded)
            g.fill(rearWindow, with: shade)
            g.stroke(rearWindow, with: shade, style: rounded)
            // The sky in the windscreen.
            var glare = Path()
            glare.move(to: CGPoint(x: -screenFoot * 0.34, y: front + bow * 0.9))
            glare.addLine(to: CGPoint(x: -screenFoot * 0.14, y: front + bow * 0.1))
            glare.addLine(to: CGPoint(x: -roofWidth * 0.18, y: roofFront))
            glare.addLine(to: CGPoint(x: -roofWidth * 0.4, y: roofFront))
            glare.closeSubpath()
            g.fill(glare, with: .color(.white.opacity(0.25)))
            let roofRect = CGRect(x: -roofWidth / 2, y: roofFront, width: roofWidth, height: roofBack - roofFront)
            let roof = Path(roundedRect: roofRect, cornerRadius: w * 0.09)
            g.fill(roof, with: .linearGradient(Gradient(stops: DriveArt.paintwork(tint, lift: 1.04, soft: true)),
                                               startPoint: CGPoint(x: -roofWidth / 2, y: 0), endPoint: CGPoint(x: roofWidth / 2, y: 0)))
            if body == .sport {
                var roofStripes = g
                roofStripes.clip(to: roof)
                var stripes = Path()
                for side in [-1, 1] as [CGFloat] { stripes.addRect(CGRect(x: side * w * 0.085 - w * 0.045, y: roofRect.minY, width: w * 0.09, height: roofRect.height)) }
                roofStripes.fill(stripes, with: .color(.white.opacity(0.92)))
            }
            g.fill(Path(roundedRect: CGRect(x: roofRect.minX + w * 0.015, y: roofRect.minY + l * 0.02, width: w * 0.035, height: roofRect.height - l * 0.04),
                        cornerRadius: w * 0.015), with: .color(.white.opacity(0.4)))
            // Sun on the roof.
            let sheen = CGRect(x: roofRect.minX + roofWidth * 0.1, y: roofRect.minY + roofRect.height * 0.08, width: roofWidth * 0.34, height: roofRect.height * 0.62)
            g.fill(Path(roundedRect: sheen, cornerRadius: w * 0.08),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.4), .white.opacity(0)]),
                                         startPoint: CGPoint(x: sheen.minX, y: sheen.minY), endPoint: CGPoint(x: sheen.maxX, y: sheen.maxY)))
            if body == .van {
                // Roof rails.
                var rails = Path()
                for side in [-1, 1] as [CGFloat] {
                    rails.addRoundedRect(in: CGRect(x: side * roofWidth * 0.36 - w * 0.025, y: roofRect.minY + l * 0.04, width: w * 0.05, height: roofRect.height - l * 0.08),
                                         cornerSize: CGSize(width: w * 0.02, height: w * 0.02))
                }
                g.fill(rails, with: .color(Color(white: 0.18).opacity(0.8)))
            }
            if taxi {
                let sign = CGRect(x: -w * 0.18, y: roofRect.midY - l * 0.035, width: w * 0.36, height: l * 0.07)
                g.fill(Path(roundedRect: sign, cornerRadius: w * 0.04), with: .color(Color(red: 1, green: 0.97, blue: 0.82)))
                g.stroke(Path(roundedRect: sign, cornerRadius: w * 0.04), with: .color(.black.opacity(0.45)), lineWidth: max(0.5, w * 0.02))
            }
            g.stroke(shell, with: .color(JevDraw.shade(tint, 0.32).opacity(0.75)), lineWidth: max(0.6, w * 0.028))

            // Mirrors, and a wing on the sports car.
            var mirrors = Path()
            for side in [-1, 1] as [CGFloat] {
                mirrors.addEllipse(in: CGRect(x: side * (hw + w * 0.03) - w * 0.08, y: front + l * 0.015, width: w * 0.16, height: l * 0.05))
            }
            g.fill(mirrors, with: .color(JevDraw.shade(tint, 0.6)))
            if body == .sport {
                let wing = CGRect(x: -hw * 1.02, y: hl - l * 0.13, width: w * 1.02, height: l * 0.05)
                g.fill(Path(roundedRect: wing, cornerRadius: w * 0.04),
                       with: .linearGradient(Gradient(colors: [JevDraw.shade(tint, 0.75), JevDraw.shade(tint, 0.4)]),
                                             startPoint: CGPoint(x: 0, y: wing.minY), endPoint: CGPoint(x: 0, y: wing.maxY)))
                g.fill(Path(CGRect(x: wing.minX + w * 0.06, y: wing.minY + l * 0.006, width: wing.width * 0.5, height: l * 0.01)), with: .color(.white.opacity(0.35)))
            }
            if braking {
                // The glow of the brake lights on the road behind.
                for side in [-1, 1] as [CGFloat] {
                    let light = CGPoint(x: side * hw * 0.62, y: hl)
                    let r = w * 0.42
                    g.fill(Path(ellipseIn: CGRect(x: light.x - r, y: light.y - r * 0.8, width: 2 * r, height: 1.6 * r)),
                           with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.2, blue: 0.1).opacity(0.55), Color(red: 1, green: 0.1, blue: 0.05).opacity(0)]),
                                                 center: light, startRadius: 0, endRadius: r))
                }
            }
            if blink != 0, (now * 3).truncatingRemainder(dividingBy: 1) < 0.55 {
                // Indicators, on the side it is turning to.
                let side = CGFloat(blink > 0 ? 1 : -1)
                var amber = Path()
                amber.addEllipse(in: CGRect(x: side * hw * 0.86 - w * 0.07, y: -hl + l * 0.03, width: w * 0.14, height: l * 0.05))
                amber.addEllipse(in: CGRect(x: side * hw * 0.86 - w * 0.07, y: hl - l * 0.07, width: w * 0.14, height: l * 0.05))
                g.fill(amber, with: .color(Color(red: 1, green: 0.72, blue: 0.1)))
                g.fill(Path(ellipseIn: CGRect(x: side * hw - w * 0.25, y: -hl - w * 0.1, width: w * 0.5, height: w * 0.4)),
                       with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.75, blue: 0.2).opacity(0.5), Color(red: 1, green: 0.75, blue: 0.2).opacity(0)]),
                                             center: CGPoint(x: side * hw * 0.86, y: -hl + l * 0.05), startRadius: 0, endRadius: w * 0.28))
            }
        }

        /// A lorry from above: a cab and a long box, ribbed across the roof, on three axles.
        private func truck(_ g: GraphicsContext, at centre: CGPoint, width w: CGFloat, length l: CGFloat, tint: (Double, Double, Double),
                           load: (Double, Double, Double), braking: Bool) {
            var g = g
            g.translateBy(x: centre.x, y: centre.y)
            let hw = w / 2, hl = l / 2
            func along(_ share: CGFloat) -> CGFloat { -hl + l * share }

            var tyres = Path()
            for axle in [along(0.11), along(0.3), along(0.8), along(0.9)] {
                for side in [-1, 1] as [CGFloat] {
                    tyres.addRoundedRect(in: CGRect(x: side * (hw - w * 0.06) - w * 0.09, y: axle - l * 0.035, width: w * 0.18, height: l * 0.07),
                                         cornerSize: CGSize(width: w * 0.04, height: w * 0.04))
                }
            }
            g.fill(tyres, with: .color(Color(white: 0.09)))

            // The cab.
            let cab = CGRect(x: -hw * 0.92, y: along(0), width: w * 0.92, height: l * 0.21)
            g.fill(Path(roundedRect: cab, cornerRadius: w * 0.16),
                   with: .linearGradient(Gradient(stops: DriveArt.paintwork(tint)), startPoint: CGPoint(x: cab.minX, y: 0), endPoint: CGPoint(x: cab.maxX, y: 0)))
            let windscreen = CGRect(x: cab.minX + w * 0.07, y: cab.minY + l * 0.02, width: cab.width - w * 0.14, height: l * 0.045)
            g.fill(Path(roundedRect: windscreen, cornerRadius: w * 0.05),
                   with: .linearGradient(Gradient(colors: DriveArt.glass), startPoint: CGPoint(x: windscreen.minX, y: windscreen.minY),
                                         endPoint: CGPoint(x: windscreen.maxX, y: windscreen.maxY)))
            // The roof, with its wind deflector.
            let deflector = CGRect(x: cab.minX + w * 0.1, y: cab.minY + l * 0.08, width: cab.width - w * 0.2, height: l * 0.11)
            g.fill(Path(roundedRect: deflector, cornerRadius: w * 0.14),
                   with: .linearGradient(Gradient(stops: DriveArt.paintwork(tint, lift: 1.12)),
                                         startPoint: CGPoint(x: deflector.minX, y: 0), endPoint: CGPoint(x: deflector.maxX, y: 0)))
            g.fill(Path(roundedRect: CGRect(x: deflector.minX + w * 0.06, y: deflector.minY + l * 0.01, width: deflector.width * 0.3, height: deflector.height * 0.6),
                        cornerRadius: w * 0.06), with: .color(.white.opacity(0.28)))
            var markers = Path(), mirrors = Path(), heads = Path()
            for k in -1...1 { markers.addEllipse(in: CGRect(x: CGFloat(k) * w * 0.14 - w * 0.035, y: cab.minY + l * 0.068, width: w * 0.07, height: w * 0.07)) }
            for side in [-1, 1] as [CGFloat] {
                mirrors.addRoundedRect(in: CGRect(x: side * (hw * 0.92 + w * 0.06) - w * 0.06, y: cab.minY + l * 0.035, width: w * 0.12, height: l * 0.045),
                                       cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
                heads.addRoundedRect(in: CGRect(x: side * hw * 0.62 - w * 0.12, y: cab.minY + l * 0.004, width: w * 0.24, height: l * 0.018),
                                     cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
            }
            g.fill(markers, with: .color(Color(red: 1, green: 0.7, blue: 0.15)))
            g.fill(mirrors, with: .color(Color(white: 0.2)))
            g.fill(heads, with: .color(Color(red: 1, green: 0.97, blue: 0.84)))

            // The coupling, then the box.
            g.fill(Path(CGRect(x: -w * 0.2, y: along(0.2), width: w * 0.4, height: l * 0.04)), with: .color(Color(white: 0.16)))
            let box = CGRect(x: -hw, y: along(0.235), width: w, height: l * 0.765)
            let shape = Path(roundedRect: box, cornerRadius: w * 0.07)
            g.fill(shape, with: .linearGradient(Gradient(stops: DriveArt.paintwork(load, soft: true)),
                                                startPoint: CGPoint(x: box.minX, y: 0), endPoint: CGPoint(x: box.maxX, y: 0)))
            var grooves = Path(), ridges = Path()
            let rib = box.height / 15, thin = max(0.7, l * 0.005)
            var y = box.minY + rib
            while y < box.maxY - rib * 0.5 {
                grooves.addRect(CGRect(x: box.minX + w * 0.07, y: y, width: box.width - w * 0.14, height: thin))
                ridges.addRect(CGRect(x: box.minX + w * 0.07, y: y + thin, width: box.width - w * 0.14, height: thin))
                y += rib
            }
            g.fill(grooves, with: .color(.black.opacity(0.16)))
            g.fill(ridges, with: .color(.white.opacity(0.24)))
            // Sun along the box's roof.
            g.fill(Path(roundedRect: CGRect(x: box.minX + w * 0.1, y: box.minY + l * 0.02, width: w * 0.22, height: box.height - l * 0.04), cornerRadius: w * 0.08),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.26), .white.opacity(0)]),
                                         startPoint: CGPoint(x: 0, y: box.minY), endPoint: CGPoint(x: 0, y: box.maxY)))
            g.stroke(shape, with: .color(.black.opacity(0.35)), lineWidth: max(0.6, w * 0.025))

            var tails = Path()
            for side in [-1, 1] as [CGFloat] {
                tails.addRoundedRect(in: CGRect(x: side * hw * 0.7 - w * 0.1, y: box.maxY - l * 0.022, width: w * 0.2, height: l * 0.016),
                                     cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
            }
            g.fill(tails, with: .color(braking ? Color(red: 1, green: 0.28, blue: 0.2) : Color(red: 0.75, green: 0.06, blue: 0.07)))
            if braking {
                for side in [-1, 1] as [CGFloat] {
                    let light = CGPoint(x: side * hw * 0.7, y: box.maxY)
                    let r = w * 0.4
                    g.fill(Path(ellipseIn: CGRect(x: light.x - r, y: light.y - r * 0.8, width: 2 * r, height: 1.6 * r)),
                           with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.2, blue: 0.1).opacity(0.5), Color(red: 1, green: 0.1, blue: 0.05).opacity(0)]),
                                                 center: light, startRadius: 0, endRadius: r))
                }
            }
        }

        /// A red jerry can, glowing and pulsing so it can be seen coming from far off.
        private func can(_ g: GraphicsContext, at p: CGPoint, size: CGFloat) {
            let beat = CGFloat(0.5 + 0.5 * sin(now * 5))
            let glow = size * (1.0 + 0.18 * beat)
            g.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: 2 * glow, height: 2 * glow)),
                   with: .radialGradient(Gradient(stops: [.init(color: Color(red: 1, green: 0.88, blue: 0.4).opacity(0.55 + 0.25 * Double(beat)), location: 0),
                                                          .init(color: Color(red: 1, green: 0.62, blue: 0.12).opacity(0.3), location: 0.45),
                                                          .init(color: Color(red: 1, green: 0.5, blue: 0.1).opacity(0), location: 1)]),
                                         center: p, startRadius: 0, endRadius: glow))
            // A ring going out from it, again and again.
            let phase = (now / 1.3).truncatingRemainder(dividingBy: 1)
            let ring = size * CGFloat(0.5 + 0.8 * phase)
            g.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: 2 * ring, height: 2 * ring)),
                     with: .color(Color(red: 1, green: 0.9, blue: 0.55).opacity(0.75 * (1 - phase))), lineWidth: max(1, size * 0.07 * CGFloat(1 - phase)))

            var c = g
            c.translateBy(x: p.x, y: p.y)
            let bob = 1 + 0.06 * CGFloat(sin(now * 4))
            c.scaleBy(x: bob, y: bob)
            let w = size * 0.6, h = size * 0.72
            let body = CGRect(x: -w / 2, y: -h / 2 + size * 0.07, width: w, height: h)
            // The handle and the spout, on top.
            c.fill(Path(roundedRect: CGRect(x: -w * 0.44, y: body.minY - size * 0.15, width: w * 0.58, height: size * 0.22), cornerRadius: size * 0.07),
                   with: .color(Color(red: 0.62, green: 0.05, blue: 0.05)))
            c.fill(Path(roundedRect: CGRect(x: -w * 0.33, y: body.minY - size * 0.09, width: w * 0.36, height: size * 0.08), cornerRadius: size * 0.03),
                   with: .color(Color(red: 0.2, green: 0.02, blue: 0.02)))
            let spout = CGRect(x: w * 0.2, y: body.minY - size * 0.16, width: w * 0.24, height: size * 0.22)
            c.fill(Path(roundedRect: spout, cornerRadius: size * 0.05),
                   with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), Color(red: 0.75, green: 0.55, blue: 0.1)]),
                                         startPoint: CGPoint(x: spout.minX, y: 0), endPoint: CGPoint(x: spout.maxX, y: 0)))
            // The can: shaded round, an X pressed into its side, a glint of sun.
            let shape = Path(roundedRect: body, cornerRadius: size * 0.1)
            c.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.4, blue: 0.3), Color(red: 0.88, green: 0.1, blue: 0.08), Color(red: 0.55, green: 0.03, blue: 0.04)]),
                                                startPoint: CGPoint(x: body.minX, y: body.minY), endPoint: CGPoint(x: body.maxX, y: body.maxY)))
            var cross = Path()
            let inset = CGSize(width: w * 0.2, height: h * 0.18)
            cross.move(to: CGPoint(x: body.minX + inset.width, y: body.minY + inset.height))
            cross.addLine(to: CGPoint(x: body.maxX - inset.width, y: body.maxY - inset.height))
            cross.move(to: CGPoint(x: body.maxX - inset.width, y: body.minY + inset.height))
            cross.addLine(to: CGPoint(x: body.minX + inset.width, y: body.maxY - inset.height))
            c.stroke(cross.offsetBy(dx: size * 0.025, dy: size * 0.025), with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
            c.stroke(cross, with: .color(Color(red: 1, green: 0.58, blue: 0.48).opacity(0.9)), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
            c.stroke(shape, with: .color(Color(red: 0.38, green: 0.02, blue: 0.02)), lineWidth: max(0.8, size * 0.03))
            c.fill(Path(roundedRect: CGRect(x: body.minX + w * 0.1, y: body.minY + h * 0.08, width: w * 0.12, height: h * 0.5), cornerRadius: w * 0.06),
                   with: .color(.white.opacity(0.4)))
            // Sparkles winking round it.
            for k in 0..<3 {
                let wink = max(0, sin(now * 3.4 + Double(k) * 2.1))
                guard wink > 0.05 else { continue }
                let angle = now * 0.8 + Double(k) * 2.1
                let at = CGPoint(x: p.x + CGFloat(cos(angle)) * size * 0.62, y: p.y + CGFloat(sin(angle)) * size * 0.58)
                let s = size * 0.2 * CGFloat(wink)
                var spark = Path()
                spark.move(to: CGPoint(x: at.x, y: at.y - s))
                spark.addQuadCurve(to: CGPoint(x: at.x + s, y: at.y), control: at)
                spark.addQuadCurve(to: CGPoint(x: at.x, y: at.y + s), control: at)
                spark.addQuadCurve(to: CGPoint(x: at.x - s, y: at.y), control: at)
                spark.addQuadCurve(to: CGPoint(x: at.x, y: at.y - s), control: at)
                g.fill(spark, with: .color(.white.opacity(0.9 * wink)))
            }
        }

        /// Rubber laid down behind the wreck as it slewed round.
        private func skids(_ g: GraphicsContext, _ f: Frame, from me: CGPoint, lean: Double) {
            var marks = Path()
            for side in [-1, 1] as [CGFloat] {
                let wheel = CGPoint(x: me.x + side * f.lane * 0.24, y: me.y + f.row * 0.6)
                marks.move(to: CGPoint(x: wheel.x - f.lane * 0.12, y: wheel.y + f.row * 1.8))
                marks.addQuadCurve(to: wheel, control: CGPoint(x: wheel.x - f.lane * 0.14, y: wheel.y + f.row * 0.6))
            }
            g.stroke(marks, with: .color(.black.opacity(0.4)), style: StrokeStyle(lineWidth: f.lane * 0.09, lineCap: .round))
        }

        /// Bits of car thrown out from the crash, flying outward and settling.
        private func debris(_ g: GraphicsContext, at p: CGPoint, size: CGFloat, tint: (Double, Double, Double)) {
            let out = CGFloat(1 - pow(1 - min(max(since, 0) / 0.5, 1), 2))
            var paint = Path(), dark = Path(), glass = Path()
            for k in 0..<12 {
                let angle = Double(k) / 12 * 2 * .pi + DriveArt.unit(k, 1400) * 0.5
                let reach = size * CGFloat(0.5 + 1.3 * DriveArt.unit(k, 1401)) * out
                let at = CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach * 0.9)
                let d = size * CGFloat(0.06 + 0.1 * DriveArt.unit(k, 1402))
                let bit = CGRect(x: at.x - d / 2, y: at.y - d / 3, width: d, height: d * 0.66)
                let turn = CGAffineTransform(translationX: at.x, y: at.y).rotated(by: CGFloat(angle * 3)).translatedBy(x: -at.x, y: -at.y)
                switch k % 3 {
                case 0: paint.addRect(bit, transform: turn)
                case 1: dark.addRect(bit, transform: turn)
                default: glass.addEllipse(in: bit.insetBy(dx: d * 0.2, dy: d * 0.1))
                }
            }
            g.fill(dark, with: .color(Color(white: 0.12)))
            g.fill(paint, with: .color(JevDraw.shade(tint, 0.9)))
            g.fill(glass, with: .color(Color(red: 0.75, green: 0.85, blue: 0.95).opacity(0.85)))
        }

        /// A burnt patch where the crash was.
        private func scorch(_ g: GraphicsContext, at p: CGPoint, size: CGFloat) {
            let r = size * 1.3
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.85, width: 2 * r, height: 1.7 * r)),
                   with: .radialGradient(Gradient(colors: [.black.opacity(0.55), .black.opacity(0)]), center: p, startRadius: 0, endRadius: r))
        }

        // MARK: Speed

        /// Wind past the car: streaks down its flanks, faster and more of them the faster it goes.
        private func wind(_ g: GraphicsContext, _ f: Frame, around me: CGPoint, rush: CGFloat) {
            guard rush > 0.01 else { return }
            var streaks = Path()
            for k in 0..<Int(3 + 5 * rush) {
                let side: CGFloat = k & 1 == 0 ? -1 : 1
                let reach = f.lane * CGFloat(0.36 + 0.14 * DriveArt.unit(k, 1300))
                let phase = (now * (2.2 + DriveArt.unit(k, 1301)) + DriveArt.unit(k, 1302)).truncatingRemainder(dividingBy: 1)
                let length = f.row * CGFloat(0.6 + 0.9 * DriveArt.unit(k, 1303)) * (0.5 + rush)
                let y = me.y - f.row * 0.7 + f.row * 2.4 * CGFloat(phase)
                streaks.addRoundedRect(in: CGRect(x: me.x + side * reach, y: y, width: max(1, f.row * 0.035), height: length),
                                       cornerSize: CGSize(width: 0.6, height: 0.6))
            }
            g.fill(streaks, with: .color(.white.opacity(0.3 * Double(rush))))
        }

        /// At speed the edges of the picture darken and blur into streaks.
        private func rushing(_ g: GraphicsContext, _ f: Frame, rush: CGFloat) {
            guard rush > 0.01 else { return }
            let edge = f.verge * 1.25
            for (from, to) in [(CGFloat(0), edge), (f.width, f.width - edge)] {
                g.fill(Path(CGRect(x: min(from, to), y: 0, width: edge, height: f.height)),
                       with: .linearGradient(Gradient(colors: [.black.opacity(0.16 * Double(rush)), .black.opacity(0)]),
                                             startPoint: CGPoint(x: from, y: 0), endPoint: CGPoint(x: to, y: 0)))
            }
            for k in 0..<Int(2 + 6 * rush) {
                let side = k & 1
                let u = DriveArt.unit(k, 1200)
                let x = side == 0 ? f.verge * CGFloat(0.04 + 0.9 * u) : f.width - f.verge * CGFloat(0.04 + 0.9 * u)
                let phase = (now * (1.3 + 1.2 * DriveArt.unit(k, 1201)) + DriveArt.unit(k, 1202)).truncatingRemainder(dividingBy: 1)
                let length = f.row * CGFloat(0.9 + 1.4 * DriveArt.unit(k, 1203)) * (0.5 + rush)
                let top = -length + (f.height + length) * CGFloat(phase)
                let streak = CGRect(x: x, y: top, width: max(1, f.row * 0.04), height: length)
                g.fill(Path(roundedRect: streak, cornerRadius: streak.width / 2),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.28 * Double(rush)), .white.opacity(0)]),
                                             startPoint: CGPoint(x: 0, y: streak.minY), endPoint: CGPoint(x: 0, y: streak.maxY)))
            }
        }

        /// Warm sun from the top left, and the corners falling away.
        private func light(_ g: GraphicsContext, _ f: Frame) {
            let all = Path(CGRect(x: 0, y: 0, width: f.width, height: f.height))
            g.fill(all, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.72).opacity(0.12), Color(red: 1, green: 0.93, blue: 0.72).opacity(0)]),
                                              startPoint: .zero, endPoint: CGPoint(x: f.width * 0.55, y: f.height * 0.45)))
            g.fill(all, with: .radialGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.18)]), center: CGPoint(x: f.width * 0.5, y: f.height * 0.52),
                                              startRadius: f.width * 0.55, endRadius: f.height * 0.75))
        }

        // MARK: The dashboard

        /// Speed, distance and fuel, on glass panels across the top.
        private func dashboard(_ g: GraphicsContext, _ size: CGSize) {
            let unit = size.width / 26
            let top: CGFloat = 10, tall = unit * 3.4, gap = unit * 0.4
            let speedBox = CGRect(x: 10, y: top, width: unit * 7.6, height: tall)
            let fuelBox = CGRect(x: size.width - 10 - unit * 9.2, y: top, width: unit * 9.2, height: tall)
            let tripBox = CGRect(x: speedBox.maxX + gap, y: top, width: fuelBox.minX - speedBox.maxX - 2 * gap, height: tall)
            for box in [speedBox, tripBox, fuelBox] { glass(g, box, radius: unit * 0.8) }

            // Speed: the number, and a bar for each of the four speeds.
            hud(g, "\(after.speed * 30)", at: CGPoint(x: speedBox.minX + unit * 0.7, y: speedBox.midY - unit * 0.3), size: unit * 1.75, anchor: .leading)
            hud(g, "km/h", at: CGPoint(x: speedBox.minX + unit * 0.78, y: speedBox.midY + unit * 1.05), size: unit * 0.62, weight: .bold,
                colour: .white.opacity(0.72), anchor: .leading)
            let bar = unit * 0.4, spacing = unit * 0.2
            for k in 0..<JevDrive.top {
                let high = unit * (0.8 + 0.45 * CGFloat(k))
                let rect = CGRect(x: speedBox.maxX - unit * 0.65 - CGFloat(JevDrive.top - k) * (bar + spacing) + spacing,
                                  y: speedBox.midY + unit * 1.15 - high, width: bar, height: high)
                let shape = Path(roundedRect: rect, cornerRadius: bar * 0.4)
                if k < after.speed {
                    g.fill(shape, with: .linearGradient(Gradient(colors: [DriveArt.gauge[k].opacity(1), JevDraw.shade(DriveArt.gaugeRGB[k], 0.7)]),
                                                        startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                    g.fill(Path(roundedRect: CGRect(x: rect.minX + bar * 0.15, y: rect.minY + bar * 0.15, width: bar * 0.3, height: rect.height * 0.55),
                                cornerRadius: bar * 0.15), with: .color(.white.opacity(0.35)))
                } else {
                    g.fill(shape, with: .color(.white.opacity(0.12)))
                }
            }

            // The trip: how far, and how many passed.
            hud(g, String(format: "%.1f km", Double(after.y) * 0.005), at: CGPoint(x: tripBox.midX, y: tripBox.midY - unit * 0.35), size: unit * 1.05)
            hud(g, "超车 \(after.passed)", at: CGPoint(x: tripBox.midX, y: tripBox.midY + unit * 0.95), size: unit * 0.65, weight: .bold,
                colour: .white.opacity(0.72))

            // Fuel: a pump, and a gauge from red to green that empties toward the red; it blinks when nearly dry.
            let fuel = Double(max(after.fuel, 0)) / Double(JevDrive.tank)
            let low = fuel <= 0.2
            let blink = low && Int(since * 4) % 2 == 1
            let red = Color(red: 1, green: 0.3, blue: 0.25)
            pump(g, at: CGPoint(x: fuelBox.minX + unit * 1.1, y: fuelBox.midY - unit * 0.05), size: unit * 1.35,
                 colour: low ? red.opacity(blink ? 0.45 : 1) : .white.opacity(0.9))
            let gauge = CGRect(x: fuelBox.minX + unit * 2.2, y: fuelBox.midY - unit * 0.78, width: fuelBox.width - unit * 2.85, height: unit * 0.82)
            let trough = Path(roundedRect: gauge, cornerRadius: gauge.height / 2)
            g.fill(trough, with: .linearGradient(Gradient(colors: [.black.opacity(0.55), .black.opacity(0.3)]),
                                                 startPoint: CGPoint(x: 0, y: gauge.minY), endPoint: CGPoint(x: 0, y: gauge.maxY)))
            if fuel > 0 {
                let level = CGRect(x: gauge.minX, y: gauge.minY, width: max(gauge.height, gauge.width * CGFloat(fuel)), height: gauge.height)
                var tank = g
                tank.clip(to: Path(roundedRect: level, cornerRadius: gauge.height / 2))
                tank.opacity = blink ? 0.4 : 1
                tank.fill(trough, with: .linearGradient(Gradient(colors: DriveArt.fuelColours), startPoint: CGPoint(x: gauge.minX, y: 0),
                                                        endPoint: CGPoint(x: gauge.maxX, y: 0)))
                tank.fill(Path(roundedRect: CGRect(x: gauge.minX + gauge.height * 0.3, y: gauge.minY + gauge.height * 0.14,
                                                   width: gauge.width - gauge.height * 0.6, height: gauge.height * 0.3), cornerRadius: gauge.height * 0.15),
                          with: .color(.white.opacity(0.35)))
            }
            var ticks = Path()
            for k in 1..<4 {
                let x = gauge.minX + gauge.width * CGFloat(k) / 4
                ticks.addRect(CGRect(x: x - 0.5, y: gauge.minY + gauge.height * 0.2, width: 1, height: gauge.height * 0.6))
            }
            g.fill(ticks, with: .color(.black.opacity(0.35)))
            g.stroke(trough, with: .color(.white.opacity(0.22)), lineWidth: 1)
            hud(g, "\(max(after.fuel, 0))", at: CGPoint(x: gauge.maxX, y: gauge.maxY + unit * 0.78), size: unit * 0.68, weight: .bold,
                colour: low ? red : .white.opacity(0.8), anchor: .trailing)
            hud(g, "E", at: CGPoint(x: gauge.minX + unit * 0.1, y: gauge.maxY + unit * 0.78), size: unit * 0.55, weight: .bold,
                colour: .white.opacity(0.45), anchor: .leading)
        }

        /// A panel of smoked glass, lit along its top edge.
        private func glass(_ g: GraphicsContext, _ rect: CGRect, radius: CGFloat) {
            let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            g.fill(Path(roundedRect: rect.offsetBy(dx: 1.5, dy: 2.5), cornerRadius: radius, style: .continuous), with: .color(.black.opacity(0.22)))
            g.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.25).opacity(0.8), Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.72)]),
                                                startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            let sheen = CGRect(x: rect.minX + 1.5, y: rect.minY + 1.5, width: rect.width - 3, height: rect.height * 0.46)
            g.fill(Path(roundedRect: sheen, cornerRadius: max(radius - 1.5, 1), style: .continuous),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.17), .white.opacity(0.02)]),
                                         startPoint: CGPoint(x: 0, y: sheen.minY), endPoint: CGPoint(x: 0, y: sheen.maxY)))
            g.stroke(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.4), .white.opacity(0.07)]),
                                                  startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)), lineWidth: 1)
        }

        /// A petrol pump, for the fuel gauge.
        private func pump(_ g: GraphicsContext, at p: CGPoint, size s: CGFloat, colour: Color) {
            let body = CGRect(x: p.x - s * 0.36, y: p.y - s * 0.42, width: s * 0.5, height: s * 0.84)
            g.fill(Path(roundedRect: body, cornerRadius: s * 0.09), with: .color(colour))
            g.fill(Path(roundedRect: CGRect(x: body.minX + s * 0.09, y: body.minY + s * 0.1, width: body.width - s * 0.18, height: s * 0.22), cornerRadius: s * 0.04),
                   with: .color(.black.opacity(0.6)))
            var hose = Path()
            hose.move(to: CGPoint(x: body.maxX, y: body.minY + s * 0.2))
            hose.addLine(to: CGPoint(x: body.maxX + s * 0.16, y: body.minY + s * 0.34))
            hose.addLine(to: CGPoint(x: body.maxX + s * 0.16, y: body.maxY - s * 0.18))
            hose.addQuadCurve(to: CGPoint(x: body.maxX + s * 0.02, y: body.maxY - s * 0.2), control: CGPoint(x: body.maxX + s * 0.1, y: body.maxY - s * 0.02))
            g.stroke(hose, with: .color(colour), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round, lineJoin: .round))
            g.fill(Path(roundedRect: CGRect(x: body.minX - s * 0.06, y: body.maxY - s * 0.05, width: body.width + s * 0.12, height: s * 0.1), cornerRadius: s * 0.03),
                   with: .color(colour))
        }

        /// Figures on the dashboard: rounded, their digits all one width so they do not jitter.
        private func hud(_ g: GraphicsContext, _ text: String, at point: CGPoint, size: CGFloat, weight: Font.Weight = .heavy,
                         colour: Color = .white, anchor: UnitPoint = .center) {
            let font = Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
            g.draw(Text(text).font(font).foregroundColor(.black.opacity(0.5)), at: CGPoint(x: point.x + size * 0.03, y: point.y + size * 0.07), anchor: anchor)
            g.draw(Text(text).font(font).foregroundColor(colour), at: point, anchor: anchor)
        }
    }
}

/// The road's colours and shapes, worked out once.
fileprivate enum DriveArt {
    enum Body { case sedan, hatch, van, sport }

    /// A number in 0..<1 that is the same every time for the same inputs.
    static func unit(_ a: Int, _ b: Int) -> Double { Double(JevDraw.hash(a, b)) / 1_000_003 }
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static let grass = rgb(0.4, 0.64, 0.28), lush = rgb(0.24, 0.47, 0.18), dry = rgb(0.63, 0.77, 0.34)
    static let gravel = rgb(0.61, 0.56, 0.47)
    static let kerbRed = rgb(0.80, 0.16, 0.14), kerbWhite = rgb(0.95, 0.94, 0.90)
    static let asphalt = rgb(0.255, 0.265, 0.28), paint = rgb(0.95, 0.95, 0.91)
    static let shadow = rgb(0.03, 0.05, 0.1)
    static let flowers: [Color] = [rgb(0.98, 0.97, 0.93), rgb(1, 0.84, 0.24), rgb(0.96, 0.56, 0.72), rgb(0.68, 0.6, 0.96)]
    /// Leaves: oak, lime and olive greens, each dark, mid and light.
    static let foliage: [(dark: Color, mid: Color, midRGB: (Double, Double, Double), light: Color)] = [
        ((0.09, 0.27, 0.12), (0.2, 0.47, 0.19), (0.44, 0.7, 0.29)),
        ((0.12, 0.31, 0.09), (0.31, 0.56, 0.16), (0.62, 0.8, 0.3)),
        ((0.15, 0.28, 0.1), (0.34, 0.5, 0.18), (0.54, 0.66, 0.27)),
    ].map { (rgb($0.0.0, $0.0.1, $0.0.2), rgb($0.1.0, $0.1.1, $0.1.2), $0.1, rgb($0.2.0, $0.2.1, $0.2.2)) }
    static let needles: (dark: Color, mid: Color, light: Color, lightRGB: (Double, Double, Double)) =
        (rgb(0.08, 0.27, 0.19), rgb(0.15, 0.41, 0.29), rgb(0.32, 0.6, 0.42), (0.32, 0.6, 0.42))
    static let glass: [Color] = [rgb(0.56, 0.68, 0.8), rgb(0.27, 0.35, 0.46), rgb(0.12, 0.15, 0.22), rgb(0.07, 0.09, 0.14)]
    static let gaugeRGB: [(Double, Double, Double)] = [(0.35, 0.85, 0.4), (0.75, 0.9, 0.3), (1, 0.7, 0.2), (1, 0.32, 0.25)]
    static let gauge: [Color] = gaugeRGB.map { rgb($0.0, $0.1, $0.2) }
    static let fuelColours: [Color] = [rgb(0.95, 0.25, 0.2), rgb(1, 0.62, 0.15), rgb(0.98, 0.86, 0.25), rgb(0.45, 0.85, 0.35), rgb(0.25, 0.8, 0.45)]

    /// Across the road: each lane polished lighter in two tracks where the tyres run, a darker oily strip
    /// between them, and grime toward the kerbs.
    static let asphaltStops: [Gradient.Stop] = {
        let base = (0.255, 0.265, 0.28)
        let pattern: [(Double, Double)] = [(0, 0.97), (0.12, 1), (0.2, 1.1), (0.31, 1.1), (0.39, 1), (0.44, 0.97), (0.5, 0.9),
                                           (0.56, 0.97), (0.61, 1), (0.69, 1.1), (0.8, 1.1), (0.88, 1), (1, 0.97)]
        var stops: [Gradient.Stop] = []
        for lane in 0..<JevDrive.lanes {
            for (u, k) in pattern where lane == 0 || u > 0 {
                let x = (Double(lane) + u) / Double(JevDrive.lanes)
                let grime = 1 - 0.2 * max(0, 1 - min(x, 1 - x) / 0.035)
                let shade = k * grime
                stops.append(Gradient.Stop(color: Color(red: base.0 * shade, green: base.1 * shade, blue: base.2 * shade), location: CGFloat(x)))
            }
        }
        return stops
    }()

    /// Tree tops: lobes (x, y, radius) in units of the tree's radius, overlapping into a cloud.
    static let canopies: [[(x: CGFloat, y: CGFloat, r: CGFloat)]] = (0..<5).map { variant in
        let count = 6 + variant % 3
        var lobes: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [(0, 0, 0.66)]
        for k in 0..<count {
            let angle = (Double(k) + 0.4 * unit(variant, k)) / Double(count) * 2 * .pi
            let reach = 0.4 + 0.14 * unit(variant, k + 50)
            lobes.append((CGFloat(cos(angle) * reach), CGFloat(sin(angle) * reach), CGFloat(0.38 + 0.18 * unit(variant, k + 90))))
        }
        return lobes
    }

    /// A pine from above: a star of branches, their tips uneven.
    static let pine: [CGPoint] = (0..<36).map { k in
        let angle = Double(k) / 36 * 2 * .pi
        let reach = k % 2 == 0 ? 0.88 + 0.14 * unit(k, 5) : 0.74
        return CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
    }

    /// Which body a car of the traffic has: most are saloons, some hatchbacks, a few vans.
    static func body(of serial: Int) -> Body { [.sedan, .hatch, .sedan, .van, .hatch][serial % 5] }

    /// Along a car from the nose, as shares of its length: the front of the glass, the front of the roof,
    /// the back of the roof, the back of the glass.
    static func cabin(_ body: Body) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        switch body {
        case .sedan: return (0.28, 0.42, 0.68, 0.79)
        case .hatch: return (0.26, 0.4, 0.78, 0.88)
        case .van: return (0.12, 0.22, 0.88, 0.94)
        case .sport: return (0.31, 0.45, 0.66, 0.76)
        }
    }

    /// Paint across a curved body: dark at the flanks, brightest a little left of the middle where the sun catches it.
    static func paintwork(_ tint: (Double, Double, Double), lift: Double = 1, soft: Bool = false) -> [Gradient.Stop] {
        let bands: [(Double, CGFloat)] = soft
            ? [(0.72, 0), (0.95, 0.08), (1.08, 0.3), (1, 0.6), (0.9, 0.92), (0.75, 1)]
            : [(0.55, 0), (0.92, 0.1), (1.28, 0.3), (1.08, 0.5), (0.9, 0.72), (0.7, 0.9), (0.5, 1)]
        return bands.map { Gradient.Stop(color: JevDraw.shade(tint, $0.0 * lift), location: $0.1) }
    }

    /// A car's outline from above, nose up, centred on the origin: the nose rounder than the tail,
    /// and a sports car pinched at the waist between its wheels.
    static func shell(width w: CGFloat, length l: CGFloat, body: Body) -> Path {
        let hw = w / 2, hl = l / 2
        let (nose, bend, tail): (CGFloat, CGFloat, CGFloat) = {
            switch body {
            case .sedan: return (0.8, 0.15, 0.09)
            case .hatch: return (0.8, 0.14, 0.06)
            case .van: return (0.9, 0.09, 0.04)
            case .sport: return (0.66, 0.2, 0.08)
            }
        }()
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -hl))
        p.addCurve(to: CGPoint(x: hw, y: -hl + l * bend), control1: CGPoint(x: hw * nose, y: -hl), control2: CGPoint(x: hw, y: -hl + l * bend * 0.35))
        if body == .sport {
            p.addCurve(to: CGPoint(x: hw, y: hl - l * 0.26), control1: CGPoint(x: hw * 0.9, y: -hl + l * 0.42), control2: CGPoint(x: hw * 0.9, y: hl - l * 0.42))
        }
        p.addLine(to: CGPoint(x: hw, y: hl - l * tail))
        p.addCurve(to: CGPoint(x: 0, y: hl), control1: CGPoint(x: hw, y: hl - l * tail * 0.1), control2: CGPoint(x: hw * 0.72, y: hl))
        p.addCurve(to: CGPoint(x: -hw, y: hl - l * tail), control1: CGPoint(x: -hw * 0.72, y: hl), control2: CGPoint(x: -hw, y: hl - l * tail * 0.1))
        if body == .sport {
            p.addLine(to: CGPoint(x: -hw, y: hl - l * 0.26))
            p.addCurve(to: CGPoint(x: -hw, y: -hl + l * bend), control1: CGPoint(x: -hw * 0.9, y: hl - l * 0.42), control2: CGPoint(x: -hw * 0.9, y: -hl + l * 0.42))
        } else {
            p.addLine(to: CGPoint(x: -hw, y: -hl + l * bend))
        }
        p.addCurve(to: CGPoint(x: 0, y: -hl), control1: CGPoint(x: -hw, y: -hl + l * bend * 0.35), control2: CGPoint(x: -hw * nose, y: -hl))
        p.closeSubpath()
        return p
    }

    /// A tuft of grass: three blades from one root.
    static func tuft(_ path: inout Path, at p: CGPoint, size s: CGFloat) {
        path.move(to: CGPoint(x: p.x - s * 0.5, y: p.y - s * 0.75))
        path.addLine(to: p)
        path.addLine(to: CGPoint(x: p.x + s * 0.08, y: p.y - s * 1.1))
        path.move(to: p)
        path.addLine(to: CGPoint(x: p.x + s * 0.55, y: p.y - s * 0.7))
    }
}
