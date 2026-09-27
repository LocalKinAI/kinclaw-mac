import SwiftUI

/// 跑酷 — an endless runner on railway tracks, seen from behind, one tick a question.
///
/// Three lanes of track, and the runner goes a step a tick and never stops.
/// Barriers stand across the lanes — low ones to jump, high ones to roll
/// under — parked trains fill a lane for a stretch, and oncoming trains drive
/// at the runner, so the gap to them closes two steps a tick. Coins lie along
/// the rails and arc over the low barriers. Every tick is one choice of five:
/// run on, a lane left or right, jump or roll; a jump and a roll, once begun,
/// run their course, and a lane change is in both lanes for its step.
///
/// Everything on the course is where the program says it will be — even an
/// oncoming train's whole future is arithmetic — so the program looks ahead
/// over every way of moving, twelve steps deep, and says what each choice
/// leads to: what it clears or hits, what is next in the lane it leaves the
/// runner in, how many coins the best way on from it collects, and, plainly,
/// whether any way on survives at all. The evaluator that plays is the same
/// search. The course is laid a stretch at a time from the seed, and a stretch
/// is kept only if it can be got through from every way of arriving at it:
/// nothing is ever a wall across all three lanes.
@MainActor
final class JevRunner: JevGame {
    let id = "runner", title = "跑酷", symbol = "figure.run"
    let rules = "An endless runner on railway tracks, seen from behind. The runner goes forward one step every tick along three lanes, left, middle and right, and never stops; the further the run, the busier the tracks. Each tick the runner may keep running, move one lane left or right (the move takes that tick, and during it the runner is in both lanes), jump, or roll. A jump keeps the runner in the air for 3 steps and a roll keeps it low for 2; until it is over nothing else can be done. A low barrier is cleared only by a jump, a high barrier only by a roll. A parked train fills its lane for a stretch, and an oncoming train drives at the runner, closing 2 steps a tick: only a lane change gets past a train. Coins lie along the track and in the air over barriers: one on the ground is picked up by running or rolling through it, one in the air by jumping through it. Hitting anything ends the run. The score is the steps run plus the coins collected. Distances count steps from where the runner is now: 1 step ahead is the step it runs into this tick."
    let question = "What should the runner do this tick, to run as far as possible without crashing and collect coins on the way?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: never choose an option that hits something, or after which no move can avoid a crash: either ends the run. Second: among the safe options, prefer the one whose best way on collects more coins. Third: prefer the middle lane, and running on rather than jumping or rolling when there is nothing to get past. A barrier or a train further ahead is no danger while the option is safe: there is time to get past it."
    let controls = "←→ 换道 · ↑ 跳 · ↓ 滑铲"

    nonisolated static let lanes = 3, jump = 3, roll = 2
    /// How far the words and the evaluator look, in steps.
    nonisolated static let sight = 12
    /// How far ahead of the runner the course is laid, in steps.
    nonisolated static let ahead = 46
    /// How many steps ahead the picture shows: an oncoming train's lane stays clear that far in front of it.
    nonisolated static let view = 34
    /// The states the look ahead tells apart in a cell: a lane, and on the ground, in the air (two steps
    /// left, one left) or rolling (one left).
    nonisolated static let phases = jump + roll - 1
    nonisolated static let states = lanes * phases
    nonisolated static let laneNames = ["left", "middle", "right"]

    fileprivate enum Kind { case low, high, train, oncoming }

    /// Something on the track. A barrier or a parked train holds the cells from `cell` on; an oncoming
    /// train meets a runner in its lane at `cell`, and while the runner is at z its front is at 2·cell − z.
    fileprivate struct Thing {
        var kind: Kind, lane: Int, cell: Int, length = 1, paint = 0, serial = 0
        /// The last cell of its lane a runner cannot step into: an oncoming train, coming on as the runner
        /// goes, is past in half its length.
        var last: Int { kind == .oncoming ? cell + (length + 1) / 2 : cell + length - 1 }
        var bits: UInt8 {
            switch kind {
            case .low: return 1
            case .high: return 2
            case .train: return 4
            case .oncoming: return 8
            }
        }
        var name: String {
            switch kind {
            case .low: return "low barrier"
            case .high: return "high barrier"
            case .train: return "parked train"
            case .oncoming: return "oncoming train"
            }
        }
        var chinese: String {
            switch kind {
            case .low: return "低栏"
            case .high: return "高栏"
            case .train: return "停着的火车"
            case .oncoming: return "迎面来的火车"
            }
        }
    }

    fileprivate struct Coin { var cell: Int, lane: Int, high: Bool, serial: Int }

    fileprivate enum Act: Int { case run, left, right, jump, roll, keep }
    /// How a tick was moved: running, changing lane, in the air, rolling.
    fileprivate enum Posture { case run, shift, air, roll }

    /// The runner: the cell reached, the lane, and what is left of a jump or a roll.
    fileprivate struct Body: Equatable {
        var z = 0, lane = 1, air = 0, roll = 0
        var free: Bool { air == 0 && roll == 0 }
        var state: Int { lane * JevRunner.phases + (air > 0 ? air : roll > 0 ? JevRunner.jump - 1 + roll : 0) }
        static func of(_ state: Int, at z: Int) -> Body {
            let phase = state % JevRunner.phases
            return Body(z: z, lane: state / JevRunner.phases, air: phase > 0 && phase < JevRunner.jump ? phase : 0,
                        roll: phase >= JevRunner.jump ? phase - JevRunner.jump + 1 : 0)
        }
    }

    /// What the rest of a run can still make of a state: steps survived, then coins, then style.
    fileprivate struct Outlook: Comparable {
        var steps = 0, coins = 0, style = 0.0
        static func < (a: Outlook, b: Outlook) -> Bool { (a.steps, a.coins, a.style) < (b.steps, b.coins, b.style) }
    }

    /// The end of a run: what was hit, where the tick was taking the runner, and how far through it they met.
    fileprivate struct Crash { var thing: Thing; var next: Body; var contact: Double }

    private var body = Body()
    /// The runner before the last tick, and how that tick was moved, for the picture to glide from.
    private var previous = Body()
    private var posture = Posture.run
    private(set) var ticked = Date.distantPast
    private var things: [Thing] = []
    private var coins: [Coin] = []
    /// Coins picked up in the last tick, for the picture.
    private var taken: [Coin] = []
    /// What stands on each cell of each lane, as bits: 1 a low barrier, 2 a high one, 4 a parked train,
    /// 8 an oncoming train's reach. Keyed cell × 4 + lane.
    private var marks: [Int: UInt8] = [:]
    /// Coins by cell and lane, as bits: 1 on the ground, 2 in the air.
    private var purse: [Int: UInt8] = [:]
    /// No barrier or parked train may stand in a lane up to here: an oncoming train is coming down it.
    private var clearUntil = [Int](repeating: -1, count: 3)
    private var built = 0, made = 0
    private var dice = JevDice(seed: 1)
    private var acts: [Act] = []
    private var person = false
    /// A key pressed while the runner was in the air or rolling, done as soon as it is free.
    private var queued: JevPress?
    private(set) var over = false
    private var crash: Crash?
    private var ending = ""
    private(set) var collected = 0

    var score: Int { body.z + collected }
    /// How much faster than at the start the world goes by: a quarter faster by 1200 steps.
    var pace: Double { 1 + 0.25 * min(Double(body.z) / 1200, 1) }
    /// A person runs against the clock, faster as the run goes on.
    var clock: Double? { person ? 0.15 / pace : nil }

    var status: String {
        let line = "跑了 \(body.z) 步 · 金币 \(collected) · 分数 \(score) · 速度 ×\(String(format: "%.2f", pace))"
        return over ? "\(ending) · " + line : line
    }

    var situation: String {
        let lane = Self.laneNames[body.lane]
        let here = body.air > 0 ? "in the air over the \(lane) lane, landing in \(Self.steps(body.air))"
            : body.roll > 0 ? "rolling in the \(lane) lane, up again in \(Self.steps(body.roll))" : "running in the \(lane) lane"
        let lanes = (0..<Self.lanes).map { "\(Self.laneNames[$0]) lane: \(scan($0))" }.joined(separator: "; ")
        return "\(here); \(body.z) steps run, \(collected) coins. Ahead, \(lanes)"
    }

    /// The track as a chat model can read it: the next steps, nearest at the bottom.
    var position: String {
        var rows: [String] = []
        for ahead in stride(from: Self.sight, through: 1, by: -1) {
            let cell = body.z + ahead
            let row = (0..<Self.lanes).map { lane -> String in
                let bits = marks[Self.key(cell, lane)] ?? 0
                if bits & 12 != 0 { return bits & 8 != 0 ? "O" : "T" }
                if bits & 1 != 0 { return (purse[Self.key(cell, lane)] ?? 0) & 2 != 0 ? "L" : "l" }
                if bits & 2 != 0 { return "H" }
                let coin = purse[Self.key(cell, lane)] ?? 0
                return coin & 1 != 0 ? "c" : coin & 2 != 0 ? "*" : "."
            }
            rows.append(String(format: "%2d |", ahead) + row.joined(separator: " ") + "|")
        }
        let me = body.air > 0 ? "J" : body.roll > 0 ? "R" : "A"
        rows.append(" 0 |" + (0..<Self.lanes).map { $0 == body.lane ? me : " " }.joined(separator: " ") + "|")
        return rows.joined(separator: "\n") + "\n(Rows are steps ahead, lanes left to right. A is you, running (J in the air, R rolling); l a low barrier (L with coins over it); H a high barrier; T a parked train; O where an oncoming train will be; c a coin on the ground; * one in the air.)"
    }

    var grid: [[JevCell]] {
        (0..<Self.sight).reversed().map { ahead in
            (0..<Self.lanes).map { lane -> JevCell in
                let cell = body.z + ahead
                let bits = marks[Self.key(cell, lane)] ?? 0
                if ahead == 0, lane == body.lane { return JevCell(colour: over ? .red : .orange, text: over ? "💥" : "🏃", big: true) }
                if bits & 12 != 0 { return JevCell(colour: bits & 8 != 0 ? .red : .blue) }
                if bits & 1 != 0 { return JevCell(colour: Color(white: 0.5), text: "▁", ink: .white) }
                if bits & 2 != 0 { return JevCell(colour: Color(white: 0.5), text: "▔", ink: .white) }
                return JevCell(colour: Color(white: 0.35), text: (purse[Self.key(cell, lane)] ?? 0) != 0 ? "🪙" : "", big: true)
            }
        }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        dice = JevDice(seed: seed)
        body = Body(); previous = body; posture = .run
        things = []; coins = []; taken = []; marks = [:]; purse = [:]
        clearUntil = [-1, -1, -1]; made = 0
        over = false; crash = nil; ending = ""; collected = 0; queued = nil; acts = []
        // A clear start, with a line of coins down the middle to run into.
        built = 12
        for cell in 5...11 { addCoin(cell, 1, high: false) }
        populate()
        ticked = .distantPast
    }

    func prepare(person: Bool) { self.person = person }

    // MARK: The rules

    private static func key(_ cell: Int, _ lane: Int) -> Int { cell * 4 + lane }
    private static func steps(_ n: Int) -> String { n == 1 ? "1 step" : "\(n) steps" }

    private static let running: [[Act]] = [[.run, .right, .jump, .roll], [.run, .left, .right, .jump, .roll], [.run, .left, .jump, .roll]]
    private static let carried: [Act] = [.keep]

    /// What the runner can do: anything when free, only carry on in the middle of a jump or a roll.
    private func moves(_ b: Body) -> [Act] { b.free ? Self.running[b.lane] : Self.carried }

    /// One tick: where it takes the runner, and how it moves on the way.
    private func move(_ b: Body, _ act: Act) -> (body: Body, posture: Posture) {
        var n = b
        n.z += 1
        switch act {
        case .keep:
            if b.air > 0 { n.air -= 1; return (n, .air) }
            n.roll = max(b.roll - 1, 0)
            return (n, .roll)
        case .run: return (n, .run)
        case .left: n.lane -= 1; return (n, .shift)
        case .right: n.lane += 1; return (n, .shift)
        case .jump: n.air = Self.jump - 1; return (n, .air)
        case .roll: n.roll = Self.roll - 1; return (n, .roll)
        }
    }

    /// Does whatever stands on a cell stop a runner moving so? A train stops everything; only a jump
    /// clears a low barrier, and only a roll gets under a high one.
    private static func stops(_ bits: UInt8, _ posture: Posture) -> Bool {
        if bits & 12 != 0 { return true }
        if bits & 1 != 0, posture != .air { return true }
        if bits & 2 != 0, posture != .roll { return true }
        return false
    }

    /// Does the tick from `b` into `n` hit anything? A lane change is in both lanes for its step.
    private func crashes(_ b: Body, _ n: Body, _ posture: Posture) -> Bool {
        if Self.stops(marks[Self.key(n.z, n.lane)] ?? 0, posture) { return true }
        return posture == .shift && Self.stops(marks[Self.key(n.z, b.lane)] ?? 0, posture)
    }

    /// Is there a coin where the tick ends, at the height the runner goes through it?
    private func picks(_ n: Body, _ posture: Posture) -> Bool {
        (purse[Self.key(n.z, n.lane)] ?? 0) & (posture == .air ? 2 : 1) != 0
    }

    private func thing(at cell: Int, lane: Int) -> Thing? {
        things.first { $0.lane == lane && $0.cell <= cell && cell <= $0.last }
    }

    /// What the tick from `b` into `n` ran into.
    private func culprit(_ b: Body, _ n: Body, _ posture: Posture) -> Thing? {
        if Self.stops(marks[Self.key(n.z, n.lane)] ?? 0, posture), let hit = thing(at: n.z, lane: n.lane) { return hit }
        return thing(at: n.z, lane: b.lane)
    }

    /// A small cost for moving about, so that among equal ways on the evaluator keeps things simple.
    private static func style(_ act: Act) -> Double {
        switch act {
        case .run, .keep: return 0
        case .left, .right: return -0.2
        case .jump, .roll: return -0.3
        }
    }

    /// Every way on from every state, cell by cell back from `start + depth` to `start`: `table[i][state]`
    /// is the best a runner in that state at cell `start + i` can still make of the cells up to the end.
    private func outlook(from start: Int, depth: Int) -> [[Outlook]] {
        var table = [[Outlook]](repeating: [], count: depth + 1)
        table[depth] = (0..<Self.states).map { Outlook(steps: 0, coins: 0, style: $0 / Self.phases == 1 ? 1 : 0) }
        for i in stride(from: depth - 1, through: 0, by: -1) {
            table[i] = (0..<Self.states).map { state in
                let b = Body.of(state, at: start + i)
                var best = Outlook(steps: 0, coins: 0, style: -100)
                for act in moves(b) {
                    let (n, how) = move(b, act)
                    guard !crashes(b, n, how) else { continue }
                    var on = table[i + 1][n.state]
                    on.steps += 1
                    if picks(n, how) { on.coins += 1 }
                    on.style += Self.style(act)
                    if on > best { best = on }
                }
                return best
            }
        }
        return table
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        acts = moves(body)
        let table = outlook(from: body.z + 1, depth: Self.sight - 1)
        return acts.enumerated().map { index, act in
            let seen = foresee(act, table)
            return JevOption(id: String(format: "p%02d", index + 1), label: seen.words, merit: seen.merit, move: act.rawValue, title: name(act))
        }
    }

    private func name(_ act: Act) -> String {
        switch act {
        case .run: return "继续跑"
        case .left: return "往左"
        case .right: return "往右"
        case .jump: return "跳"
        case .roll: return "滑铲"
        case .keep: return body.air > 0 ? "在空中" : "滑铲中"
        }
    }

    func play(_ option: JevOption) {
        guard !over, let act = Act(rawValue: option.move), moves(body).contains(act) else { return }
        previous = body
        taken = []
        let (next, how) = move(body, act)
        posture = how
        ticked = Date()
        if crashes(body, next, how) {
            over = true
            let hit = culprit(body, next, how) ?? Thing(kind: .low, lane: next.lane, cell: next.z)
            // Where the two meet: at the face of what stands still, part way for a train coming on.
            let contact = hit.kind == .oncoming && hit.cell == next.z ? 0.62 : hit.kind == .oncoming || hit.lane == body.lane && how == .shift ? 0.18 : 0.3
            crash = Crash(thing: hit, next: next, contact: contact)
            ending = "撞上了\(hit.chinese)"
            return
        }
        body = next
        if picks(next, how) {
            let high = how == .air
            if let index = coins.firstIndex(where: { $0.cell == next.z && $0.lane == next.lane && $0.high == high }) {
                taken.append(coins.remove(at: index))
            }
            purse[Self.key(next.z, next.lane)] = (purse[Self.key(next.z, next.lane)] ?? 0) & ~(high ? 2 : 1)
            collected += 1
        }
        populate()
    }

    // MARK: The words

    /// One way to move this tick, played out as far as it is certain — a jump's three steps, a roll's
    /// two — and then looked past by the search: what it clears or hits, whether a way on survives,
    /// what is next in the lane it leaves the runner in, and the coins.
    private func foresee(_ act: Act, _ table: [[Outlook]]) -> (words: String, merit: Double) {
        let head = heading(act)
        var b = body, steps = 0, got = 0
        var passed: [Thing] = []
        repeat {
            let (n, how) = move(b, steps == 0 ? act : .keep)
            if crashes(b, n, how) {
                let hit = culprit(b, n, how)
                let merit = steps == 0 ? -10_000 : -5_000 + Double(steps) * 100
                return (head + ": " + crashWords(hit, ahead: n.z - body.z, how: how), merit)
            }
            if let t = thing(at: n.z, lane: n.lane), t.kind == .low || t.kind == .high { passed.append(t) }
            if picks(n, how) { got += 1 }
            b = n
            steps += 1
        } while !b.free && steps < Self.sight
        let on = table[steps - 1][b.state]
        let total = steps + on.steps, gold = got + on.coins
        let merit = total >= Self.sight ? 1_000 + Double(gold) * 10 + Self.style(act) + on.style : -5_000 + Double(total) * 100
        var parts: [String] = []
        if total >= Self.sight {
            parts.append("safe for at least \(Self.sight) steps")
        } else {
            parts.append("after this no move can avoid a crash: the run ends within \(Self.steps(total + 1))")
        }
        for t in passed {
            let n = Self.steps(t.cell - body.z)
            parts.append(t.kind == .low ? "clears the low barrier \(n) ahead" : "passes under the high barrier \(n) ahead")
        }
        parts.append(next(after: b))
        if total >= Self.sight {
            parts.append(gold == 0 ? "no coins on the way" : "the best way on collects \(gold == 1 ? "1 coin" : "\(gold) coins") in the next \(Self.sight) steps")
        }
        return (head + ": " + parts.joined(separator: "; "), merit)
    }

    private func heading(_ act: Act) -> String {
        let lane = Self.laneNames[body.lane]
        switch act {
        case .run: return "keep running in the \(lane) lane"
        case .left: return "move left into the \(Self.laneNames[body.lane - 1]) lane (it takes this step)"
        case .right: return "move right into the \(Self.laneNames[body.lane + 1]) lane (it takes this step)"
        case .jump: return "jump (in the air for the next \(Self.jump) steps; no lane change until you land)"
        case .roll: return "roll (low for the next \(Self.roll) steps)"
        case .keep: return body.air > 0 ? "stay in the air (you land in \(Self.steps(body.air)))" : "keep rolling (up again in \(Self.steps(body.roll)))"
        }
    }

    private func crashWords(_ hit: Thing?, ahead: Int, how: Posture) -> String {
        guard let hit else { return "hits something: the run ends" }
        let place = "\(Self.steps(ahead)) ahead in the \(Self.laneNames[hit.lane]) lane"
        switch how {
        case .air: return "while still in the air, hits the \(hit.name) \(place): the run ends"
        case .roll: return "rolls into the \(hit.name) \(place): the run ends"
        case .shift: return "hits the \(hit.name) \(place) while changing lane: the run ends"
        case .run: return "runs into the \(hit.name) \(place): the run ends"
        }
    }

    /// What is next in the lane a move leaves the runner in, and what gets past it.
    private func next(after b: Body) -> String {
        let lane = Self.laneNames[b.lane]
        let ahead = things.filter { $0.lane == b.lane && $0.last > b.z && $0.cell <= body.z + Self.sight }.min { $0.cell < $1.cell }
        guard let t = ahead else { return "nothing else in the \(lane) lane up to \(Self.sight) steps ahead" }
        let way: String
        switch t.kind {
        case .low: way = "a jump clears it, a roll does not"
        case .high: way = "a roll passes under it, a jump does not"
        case .train, .oncoming: way = "only a lane change gets past it"
        }
        return "next in the \(lane) lane: \(report(t)) (\(way))"
    }

    /// One thing on the track, from where the runner is now.
    private func report(_ t: Thing) -> String {
        let a = t.cell - body.z, b = t.last - body.z
        switch t.kind {
        case .low: return "a low barrier \(Self.steps(a)) ahead"
        case .high: return "a high barrier \(Self.steps(a)) ahead"
        case .train: return a <= 0 ? "a parked train alongside, until \(Self.steps(b)) ahead" : "a parked train from \(a) to \(b) steps ahead"
        case .oncoming:
            return a <= 0 ? "an oncoming train going past, the lane clear again after \(Self.steps(b))"
                : "an oncoming train that reaches you \(Self.steps(a)) ahead, blocking the lane from \(a) to \(b) steps ahead"
        }
    }

    /// What a lane holds over the next steps, nearest first.
    private func scan(_ lane: Int) -> String {
        let seen = things.filter { $0.lane == lane && $0.last > body.z && $0.cell <= body.z + Self.sight }.sorted { $0.cell < $1.cell }
        guard !seen.isEmpty else { return "clear for \(Self.sight) steps" }
        return seen.prefix(2).map(report).joined(separator: ", then ")
    }

    // MARK: Played by a person

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        let key = pressed.last { [.left, .right, .up, .down, .space].contains($0) }
        // In the air or rolling there is nothing to choose; a key pressed now is done on landing.
        if !body.free {
            if let key { queued = key }
            return options.first.map { .choose($0) } ?? .nothing
        }
        let wanted = key ?? queued
        queued = nil
        let act: Act
        switch wanted {
        case .left?: act = .left
        case .right?: act = .right
        case .up?, .space?: act = .jump
        case .down?: act = .roll
        default: act = .run
        }
        // A lane that is not there is running on.
        let option = options.first { $0.move == act.rawValue } ?? options.first { $0.move == Act.run.rawValue }
        return option.map { .choose($0) } ?? .nothing
    }

    // MARK: Laying the course

    private enum Pattern { case barrier, pair, row, train, trains, oncoming, coins }

    /// A stretch of course, before it is kept.
    private struct Plan {
        var things: [Thing] = []
        var coins: [(cell: Int, lane: Int, high: Bool)] = []
        var end = 0
        var reserve: (lane: Int, until: Int)?
    }

    /// Lay the course ahead, a stretch at a time, until it reaches far enough; forget what is behind.
    private func populate() {
        while built < body.z + Self.ahead { lay() }
        let gone = body.z - 8
        for lane in 0..<Self.lanes {
            marks[Self.key(gone, lane)] = nil
            purse[Self.key(gone, lane)] = nil
        }
        things.removeAll { $0.kind == .oncoming ? 2 * $0.cell - body.z + $0.length < gone : $0.last < gone }
        coins.removeAll { $0.cell < gone }
    }

    private func addCoin(_ cell: Int, _ lane: Int, high: Bool) {
        made += 1
        coins.append(Coin(cell: cell, lane: lane, high: high, serial: made))
        purse[Self.key(cell, lane)] = (purse[Self.key(cell, lane)] ?? 0) | (high ? 2 : 1)
    }

    /// One stretch: a gap, then a pattern of barriers, trains and coins. The busier patterns come in as
    /// the run goes on and the gaps shorten. A stretch that cannot be got through from every way of
    /// arriving at it is laid again with a longer gap before it.
    private func lay() {
        let level = min(Double(built) / 1500, 1)
        let weights: [(Pattern, Double)] = [
            (.barrier, 3), (.pair, 1.5 + 2 * level), (.row, level > 0.08 ? 0.8 + 1.5 * level : 0),
            (.train, 2.5), (.trains, level > 0.05 ? 1 + 2.5 * level : 0), (.oncoming, built > 40 ? 1.2 + 2.5 * level : 0),
            (.coins, 1.6 - level),
        ]
        var pick = Double(dice.below(10_000)) / 10_000 * weights.reduce(0) { $0 + $1.1 }
        var pattern = Pattern.barrier
        for (candidate, weight) in weights {
            if pick < weight { pattern = candidate; break }
            pick -= weight
        }
        var gap = (level < 0.25 ? 5 : level < 0.6 ? 4 : 3) + dice.below(3)
        for _ in 0..<6 {
            if let plan = plan(pattern, at: built + gap + 1, level: level), place(plan) { return }
            gap += 1
        }
        built += 4                                                  // nothing fitted: a quiet stretch
    }

    private func plan(_ pattern: Pattern, at s: Int, level: Double) -> Plan? {
        var p = Plan()
        func usable(_ lane: Int, from cell: Int) -> Bool { clearUntil[lane] < cell }
        func lane(from cell: Int, except: [Int] = []) -> Int? {
            let open = (0..<Self.lanes).filter { usable($0, from: cell) && !except.contains($0) }
            return open.isEmpty ? nil : open[dice.below(open.count)]
        }
        func put(_ kind: Kind, _ lane: Int, _ cell: Int, _ length: Int = 1) {
            p.things.append(Thing(kind: kind, lane: lane, cell: cell, length: length, paint: dice.below(64)))
        }
        func line(_ lane: Int, _ from: Int, _ to: Int, high: Bool = false) {
            guard from <= to else { return }
            for cell in from...to { p.coins.append((cell, lane, high)) }
        }
        func barrier() -> Kind { dice.below(2) == 0 ? .low : .high }

        switch pattern {
        case .barrier:
            guard let l = lane(from: s) else { return nil }
            let kind = barrier()
            put(kind, l, s)
            if kind == .low, dice.below(3) > 0 { line(l, s - 1, s + 1, high: true) }
            else if kind == .high, dice.below(2) == 0 { line(l, s - 2, s + 2) }
            p.end = s + 1
        case .pair:
            guard let a = lane(from: s), let b = lane(from: s, except: [a]) else { return nil }
            put(barrier(), a, s)
            put(barrier(), b, s + (dice.below(2) == 0 ? 0 : 2 + dice.below(3)))
            let c = 3 - a - b
            if usable(c, from: s - 2), dice.below(2) == 0 { line(c, s - 2, s + 3) }
            p.end = s + 5
        case .row:
            guard (0..<Self.lanes).allSatisfy({ usable($0, from: s) }) else { return nil }
            let kinds = (0..<Self.lanes).map { _ in barrier() }
            for l in 0..<Self.lanes { put(kinds[l], l, s) }
            let low = (0..<Self.lanes).filter { kinds[$0] == .low }
            if !low.isEmpty { line(low[dice.below(low.count)], s - 1, s + 1, high: true) }
            p.end = s + 1
        case .train:
            guard let l = lane(from: s) else { return nil }
            let length = 6 + dice.below(7)
            put(.train, l, s, length)
            let beside = [l - 1, l + 1].filter { (0..<Self.lanes).contains($0) && usable($0, from: s) }
            let coinLane = beside.isEmpty || dice.below(3) == 0 ? nil : beside[dice.below(beside.count)]
            if let coinLane { line(coinLane, s + 1, s + length - 2) }
            if level > 0.15, dice.below(2) == 0, let other = lane(from: s, except: [l] + (coinLane.map { [$0] } ?? [])) {
                put(barrier(), other, s + 2 + dice.below(max(length - 3, 1)))
            }
            p.end = s + length
        case .trains:
            guard let a = lane(from: s), let b = lane(from: s, except: [a]) else { return nil }
            let la = 6 + dice.below(6), lb = 6 + dice.below(6), offset = dice.below(la - 1)
            put(.train, a, s, la)
            put(.train, b, s + offset, lb)
            let c = 3 - a - b, end = s + max(la, offset + lb)
            if usable(c, from: s) {
                if dice.below(2) == 0 { line(c, s, end - 1) } else if level > 0.3 { put(barrier(), c, s + 1 + dice.below(end - s - 1)) }
            }
            p.end = end
        case .oncoming:
            guard let l = lane(from: s - 1) else { return nil }
            let length = 6 + dice.below(5), meet = s + dice.below(3)
            p.things.append(Thing(kind: .oncoming, lane: l, cell: meet, length: length, paint: dice.below(64)))
            p.reserve = (l, meet + Self.view / 2 + length + 2)
            if level > 0.3, dice.below(2) == 0, let other = lane(from: s, except: [l]) {
                put(barrier(), other, meet - 1 + dice.below(3))
            } else if let other = lane(from: s, except: [l]) {
                line(other, meet - 2, meet + 3)
            }
            p.end = meet + (length + 1) / 2 + 1
        case .coins:
            guard let l = lane(from: s) else { return nil }
            let n = 5 + dice.below(4)
            line(l, s, s + n - 1)
            p.end = s + n
        }
        return p
    }

    /// Keep a stretch if it fits: nothing in an oncoming train's way, and a way through from every state.
    private func place(_ plan: Plan) -> Bool {
        for t in plan.things where t.kind != .oncoming && t.cell <= clearUntil[t.lane] { return false }
        var touched: [Int] = []
        func undo() { for key in touched { marks[key] = nil } }
        for t in plan.things {
            for cell in t.cell...t.last {
                let key = Self.key(cell, t.lane)
                guard marks[key] == nil else { undo(); return false }
                marks[key] = t.bits
                touched.append(key)
            }
        }
        guard passable(from: built, to: plan.end) else { undo(); return false }
        for var t in plan.things {
            made += 1
            t.serial = made
            things.append(t)
        }
        if let reserve = plan.reserve { clearUntil[reserve.lane] = max(clearUntil[reserve.lane], reserve.until) }
        for coin in plan.coins where coin.cell > built && clearUntil[coin.lane] < coin.cell {
            let bits = marks[Self.key(coin.cell, coin.lane)] ?? 0
            // On the ground, only where a runner can be on the ground (under a high barrier is fine);
            // in the air, only over nothing or a low barrier.
            guard coin.high ? bits & ~1 == 0 : bits & ~2 == 0 else { continue }
            addCoin(coin.cell, coin.lane, high: coin.high)
        }
        built = plan.end
        return true
    }

    /// Can a runner get from cell `start` to cell `end` whatever state it arrives in: any lane, on the
    /// ground, in the air or rolling?
    private func passable(from start: Int, to end: Int) -> Bool {
        var alive = [Bool](repeating: true, count: Self.states)
        var cell = end
        while cell > start {
            cell -= 1
            alive = (0..<Self.states).map { state in
                let b = Body.of(state, at: cell)
                return moves(b).contains { act in
                    let (n, how) = move(b, act)
                    return !crashes(b, n, how) && alive[n.state]
                }
            }
        }
        return !alive.contains(false)
    }
}

// MARK: - The picture

extension JevRunner: JevPainted {
    var aspect: Double { 0.75 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let near = body.z - 4, far = body.z + Self.view + 2
        let seen = things.filter { thing in
            guard thing.kind == .oncoming else { return thing.last >= near && thing.cell <= far }
            let front = 2 * thing.cell - body.z
            return front <= far + 6 && front + thing.length >= near
        }
        let scene = RunnerScene(before: previous, after: crash?.next ?? body, posture: posture, things: seen,
                                coins: coins.filter { $0.cell >= near && $0.cell <= far }, taken: taken, crash: crash,
                                t: t, since: since, now: now, over: over, ending: ending, collected: collected, score: score, pace: pace)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

fileprivate typealias RunnerRGB = (Double, Double, Double)

/// Where the camera is this frame, and how the world lands on the picture: a pinhole behind and above
/// the runner, looking straight down the line, so everything shrinks toward one point on the horizon.
fileprivate struct RunnerLens {
    let size: CGSize, focal: Double, horizon: Double
    let camX: Double, camY: Double, camZ: Double
    var width: Double { Double(size.width) }
    var height: Double { Double(size.height) }
    /// The nearest and furthest world z drawn.
    var near: Double { camZ + 0.4 }
    var far: Double { camZ + RunnerArt.back + RunnerArt.reach }

    func at(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let d = max(z - camZ, 0.05)
        return CGPoint(x: width / 2 + (x - camX) * focal / d, y: horizon + (camY - y) * focal / d)
    }
    /// Points a metre at depth z.
    func scale(_ z: Double) -> Double { focal / max(z - camZ, 0.05) }
    /// How far into the haze a thing at z is: none close by, nearly all at the end of the view.
    func fog(_ z: Double) -> Double {
        let u = min(max((z - camZ - 22) / 75, 0), 1)
        return 0.88 * u * u * (3 - 2 * u)
    }
    func tone(_ c: RunnerRGB, at z: Double, light: Double = 1) -> Color { RunnerArt.tone(c, fog(z), light) }

    func add(_ p: inout Path, _ a: (Double, Double, Double), _ b: (Double, Double, Double), _ c: (Double, Double, Double), _ d: (Double, Double, Double)) {
        p.move(to: at(a.0, a.1, a.2)); p.addLine(to: at(b.0, b.1, b.2)); p.addLine(to: at(c.0, c.1, c.2)); p.addLine(to: at(d.0, d.1, d.2))
        p.closeSubpath()
    }
    func quad(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ c: (Double, Double, Double), _ d: (Double, Double, Double)) -> Path {
        var p = Path()
        add(&p, a, b, c, d)
        return p
    }
    /// A face square to the line of sight (constant z) is a plain rectangle on the picture.
    func front(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z: Double) -> CGRect {
        let a = at(x0, y1, z), b = at(x1, y0, z)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
    /// The haze over the ground: clear close by, thick toward the horizon.
    func haze() -> GraphicsContext.Shading {
        let span = height - horizon
        let depths: [Double] = [400, 95, 75, 60, 48, 38, 30, 22]
        let stops = depths.map { d in
            Gradient.Stop(color: RunnerArt.rgb(RunnerArt.haze).opacity(fog(camZ + d)), location: CGFloat(min(camY * focal / d / span, 1)))
        }
        return .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: height))
    }
    /// A face running along the line, shaded from its near end to its far end.
    func along(_ c: RunnerRGB, x: Double, y: Double, from z0: Double, to z1: Double, light: Double = 1) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [tone(c, at: z0, light: light), tone(c, at: (z0 + z1) / 2, light: light), tone(c, at: z1, light: light)]),
                        startPoint: at(x, y, z0), endPoint: at(x, y, z1))
    }
}

/// The course's colours, sizes and fixed tables, worked out once.
fileprivate enum RunnerArt {
    /// Metres: a step, from lane to lane, the camera behind and above the runner, how far the picture reaches.
    static let step = 2.0, gauge = 2.2, back = 7.2, eye = 4.2, reach = 72.0
    /// Across the line from the middle: the gravel bed, the walkway, the wall and the street.
    static let bed = 3.5, wall = 4.7, wallTop = 1.15, street = 7.0, block = 13.0
    static let haze: RunnerRGB = (0.96, 0.88, 0.8)

    static func unit(_ a: Int, _ b: Int) -> Double { Double(JevDraw.hash(a, b)) / 1_000_003 }
    static func rgb(_ c: RunnerRGB) -> Color { Color(red: c.0, green: c.1, blue: c.2) }
    /// A colour in the light (1 as it is, less in shade, more in the sun), then into the haze.
    static func tone(_ c: RunnerRGB, _ fog: Double, _ light: Double = 1) -> Color {
        func lit(_ v: Double) -> Double { light >= 1 ? v + (1 - v) * (light - 1) : v * light }
        let f = min(max(fog, 0), 1)
        return Color(red: lit(c.0) + (haze.0 - lit(c.0)) * f, green: lit(c.1) + (haze.1 - lit(c.1)) * f, blue: lit(c.2) + (haze.2 - lit(c.2)) * f)
    }

    static let sky: [Gradient.Stop] = [
        .init(color: rgb((0.27, 0.53, 0.9)), location: 0), .init(color: rgb((0.47, 0.71, 0.96)), location: 0.38),
        .init(color: rgb((0.77, 0.86, 0.95)), location: 0.72), .init(color: rgb((0.99, 0.9, 0.8)), location: 0.93),
        .init(color: rgb(haze), location: 1),
    ]
    /// Facades: sand, terracotta, sea green, cream, lilac, sage, salmon, stone.
    static let facades: [RunnerRGB] = [(0.9, 0.76, 0.58), (0.8, 0.46, 0.36), (0.45, 0.7, 0.72), (0.95, 0.9, 0.78),
                                       (0.7, 0.6, 0.8), (0.58, 0.7, 0.52), (0.93, 0.62, 0.52), (0.72, 0.73, 0.75)]
    static let signs: [RunnerRGB] = [(0.92, 0.22, 0.3), (1, 0.78, 0.15), (0.1, 0.65, 0.75), (0.45, 0.8, 0.3), (0.95, 0.45, 0.15)]
    static let paints: [RunnerRGB] = [(0.98, 0.3, 0.55), (0.25, 0.8, 0.95), (1, 0.85, 0.2), (0.55, 0.35, 0.95), (0.35, 0.9, 0.45), (1, 0.5, 0.15)]
    /// Train liveries: body, band and roof.
    static let liveries: [(body: RunnerRGB, band: RunnerRGB, roof: RunnerRGB)] = [
        ((0.2, 0.46, 0.82), (0.97, 0.97, 0.95), (0.8, 0.82, 0.86)), ((0.87, 0.25, 0.22), (1, 0.84, 0.28), (0.8, 0.79, 0.8)),
        ((0.98, 0.77, 0.2), (0.18, 0.32, 0.62), (0.84, 0.84, 0.84)), ((0.17, 0.63, 0.5), (0.97, 0.97, 0.95), (0.8, 0.84, 0.84)),
        ((0.83, 0.85, 0.89), (0.88, 0.22, 0.25), (0.72, 0.74, 0.78)), ((0.56, 0.32, 0.74), (1, 0.8, 0.32), (0.8, 0.8, 0.84)),
    ]
    static let glass: RunnerRGB = (0.16, 0.22, 0.3), sheen: RunnerRGB = (0.62, 0.74, 0.86)
    static let gravel: RunnerRGB = (0.56, 0.52, 0.48), ballast: RunnerRGB = (0.62, 0.58, 0.53), wood: RunnerRGB = (0.44, 0.32, 0.23)
    static let steel: RunnerRGB = (0.52, 0.54, 0.58), concrete: RunnerRGB = (0.8, 0.78, 0.74), pavement: RunnerRGB = (0.72, 0.7, 0.67)
    static let hoodie: RunnerRGB = (0.97, 0.45, 0.14), pack: RunnerRGB = (0.1, 0.6, 0.62), jeans: RunnerRGB = (0.2, 0.3, 0.52)
    static let skin: RunnerRGB = (0.93, 0.72, 0.56), hair: RunnerRGB = (0.24, 0.15, 0.1), cap: RunnerRGB = (0.86, 0.14, 0.18)

    /// The far city: towers along the horizon, (across from the middle in widths, width, height in heights).
    static let skyline: [(x: Double, w: Double, h: Double, far: Bool)] = (0..<46).map { k in
        let x = (unit(k, 1) - 0.5) * 1.3
        return (x, 0.018 + 0.04 * unit(k, 2), (0.012 + 0.07 * unit(k, 3)) * (1 - 0.55 * min(abs(x) / 0.65, 1)), k % 2 == 0)
    }
    /// Clouds: where they start across the sky, how high, how big, how fast they drift.
    static let clouds: [(x: Double, y: Double, w: Double, v: Double)] = (0..<6).map { k in
        (unit(k, 11) * 1.4, 0.04 + 0.16 * unit(k, 12), 0.16 + 0.16 * unit(k, 13), 0.004 + 0.006 * unit(k, 14))
    }
}

/// One moment of the run, drawn back to front: sky, city, the street and its buildings, the walls, the
/// track, the gantries, then everything on the line from the far end in, the runner among them.
fileprivate struct RunnerScene {
    typealias Thing = JevRunner.Thing
    let before: JevRunner.Body, after: JevRunner.Body, posture: JevRunner.Posture
    let things: [Thing], coins: [JevRunner.Coin], taken: [JevRunner.Coin], crash: JevRunner.Crash?
    let t: Double, since: Double, now: Double, over: Bool, ending: String
    let collected: Int, score: Int, pace: Double

    private var step: Double { RunnerArt.step }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        // How far through the tick the world has got: all the way, or to where the runner hit something.
        let u = crash.map { min(t, $0.contact) } ?? t
        let world = Double(before.z) + (crash == nil ? Double(after.z - before.z) * t : u)
        let bounce = crash == nil ? 0 : 0.35 * JevDraw.smooth((since - 0.04) / 0.3)
        let runnerZ = (world - bounce) * step
        let turn = JevDraw.smooth(u)
        let runnerX = (JevDraw.mix(Double(before.lane), Double(after.lane), turn) - 1) * RunnerArt.gauge
        let jump = posture == .air ? (Double(JevRunner.jump - after.air - 1) + u) / Double(JevRunner.jump) : -1
        let roll = posture == .roll ? (Double(JevRunner.roll - after.roll - 1) + u) / Double(JevRunner.roll) : -1
        let lift = jump >= 0 ? 4 * jump * (1 - jump) * 1.4 : 0
        let lens = RunnerLens(size: size, focal: Double(size.width) * 1.08, horizon: Double(size.height) * 0.25,
                              camX: runnerX * 0.55, camY: RunnerArt.eye + lift * 0.22, camZ: runnerZ - RunnerArt.back)

        sky(g, lens)
        city(g, lens)
        g.fill(Path(CGRect(x: 0, y: lens.horizon - 1, width: lens.width, height: lens.height - lens.horizon + 1)), with: .color(RunnerArt.tone(RunnerArt.pavement, 0.35)))
        buildings(g, lens)
        track(g, lens)
        walls(g, lens)
        gantries(g, lens, world: world)
        mist(g, lens)

        // Everything on the line, far to near, the runner among it.
        enum Item { case thing(Thing, Double, Double), coin(JevRunner.Coin), runner }
        var items: [(z: Double, item: Item)] = [(runnerZ, .runner)]
        for thing in things {
            var near = (Double(thing.cell) - 0.5) * step, far = (Double(thing.last) + 0.5) * step
            if thing.kind == .oncoming {
                near = (2 * Double(thing.cell) - world - 0.5) * step
                far = near + Double(thing.length) * step
            }
            guard far > lens.near, near < lens.far else { continue }
            items.append((thing.kind == .train || thing.kind == .oncoming ? far : near, .thing(thing, near, far)))
        }
        for coin in coins { items.append(((Double(coin.cell) - 0.5) * step, .coin(coin))) }
        if t < 0.5 { for coin in taken { items.append(((Double(coin.cell) - 0.5) * step, .coin(coin))) } }
        shadows(g, lens, world: world)
        for (_, item) in items.sorted(by: { $0.z > $1.z }) {
            switch item {
            case .thing(let thing, let near, let far):
                switch thing.kind {
                case .low, .high: barrier(g, lens, thing, at: near)
                case .train, .oncoming: train(g, lens, thing, from: near, to: far)
                }
            case .coin(let coin): self.coin(g, lens, coin)
            case .runner: kid(g, lens, x: runnerX, z: runnerZ, lift: lift, jump: jump, roll: roll, lean: lean(u))
            }
        }
        sparkle(g, lens, runnerZ: runnerZ)
        if let crash, since > 0.02 {
            let spot = lens.at(runnerX + (Double(crash.thing.lane) - 1 - runnerX / RunnerArt.gauge) * 0.4, 0.9 + lift, runnerZ + 0.55)
            JevDraw.blast(g, at: spot, size: CGFloat(lens.scale(runnerZ) * 0.32), age: since * 1.6)
        }
        rush(g, lens)
        light(g, lens)
        dashboard(g, size)
        if over {
            var c = g
            c.opacity = JevDraw.smooth((since - 0.7) / 0.5)
            JevDraw.curtain(c, size, title: ending + "！", detail: "跑了 \(after.z == before.z ? before.z : after.z) 步 · 金币 \(collected) · 分数 \(score)")
        }
    }

    /// Leaning into a lane change, or going over after a crash.
    private func lean(_ u: Double) -> Double {
        if crash != nil { return -1.25 * JevDraw.smooth((since - 0.08) / 0.5) }
        return sin(u * .pi) * 0.2 * Double(after.lane - before.lane)
    }

    // MARK: Sky and city

    private func sky(_ g: GraphicsContext, _ v: RunnerLens) {
        let w = v.width, h = v.height, horizon = v.horizon
        g.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 2)),
               with: .linearGradient(Gradient(stops: RunnerArt.sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        // The sun, low over the end of the line, and its glow.
        let sun = CGPoint(x: w * 0.55, y: horizon - h * 0.085)
        g.fill(Path(ellipseIn: CGRect(x: sun.x - w * 0.42, y: sun.y - w * 0.42, width: w * 0.84, height: w * 0.84)),
               with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.8).opacity(0.8), Color(red: 1, green: 0.88, blue: 0.7).opacity(0.28),
                                                       Color(red: 1, green: 0.85, blue: 0.7).opacity(0)]), center: sun, startRadius: 0, endRadius: w * 0.42))
        let r = w * 0.045
        g.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 1, green: 0.98, blue: 0.9)))
        // Clouds, drifting.
        var puffs = Path(), bellies = Path()
        for (k, cloud) in RunnerArt.clouds.enumerated() {
            let x = ((cloud.x + now * cloud.v).truncatingRemainder(dividingBy: 1.5) - 0.25) * w
            let y = cloud.y * h, cw = cloud.w * w
            for lobe in 0..<5 {
                let lx = x + cw * (Double(lobe) / 4 - 0.5), lr = cw * (0.16 + 0.12 * RunnerArt.unit(k, 20 + lobe))
                puffs.addEllipse(in: CGRect(x: lx - lr, y: y - lr * 0.8 - (lobe == 2 ? lr * 0.35 : 0), width: 2 * lr, height: 1.6 * lr))
            }
            bellies.addEllipse(in: CGRect(x: x - cw * 0.62, y: y - cw * 0.02, width: cw * 1.24, height: cw * 0.16))
        }
        g.fill(puffs, with: .color(.white.opacity(0.78)))
        g.fill(bellies, with: .color(Color(red: 0.86, green: 0.88, blue: 0.95).opacity(0.7)))
    }

    /// Towers far off at the end of the line, pale in the haze.
    private func city(_ g: GraphicsContext, _ v: RunnerLens) {
        var far = Path(), near = Path(), lights = Path()
        let base = v.horizon + 1
        for (k, tower) in RunnerArt.skyline.enumerated() {
            let x = v.width / 2 + tower.x * v.width, w = tower.w * v.width, h = tower.h * v.height * (tower.far ? 1.25 : 1)
            let rect = CGRect(x: x - w / 2, y: base - h, width: w, height: h)
            if tower.far { far.addRect(rect) } else {
                near.addRect(rect)
                if k % 3 == 0 { near.addRect(CGRect(x: x - w * 0.1, y: base - h - h * 0.12, width: w * 0.2, height: h * 0.12)) }
                if k % 4 == 1 { lights.addRect(CGRect(x: x - w * 0.3, y: base - h * 0.8, width: w * 0.6, height: max(1, h * 0.04))) }
            }
        }
        g.fill(far, with: .color(Color(red: 0.84, green: 0.84, blue: 0.9)))
        g.fill(near, with: .color(Color(red: 0.74, green: 0.76, blue: 0.84)))
        g.fill(lights, with: .color(.white.opacity(0.5)))
    }

    /// The haze lying at the end of the line, where it runs out of sight.
    private func mist(_ g: GraphicsContext, _ v: RunnerLens) {
        let centre = CGPoint(x: v.width / 2, y: v.horizon), rx = v.width * 0.32, ry = v.height * 0.05
        var c = g
        c.translateBy(x: centre.x, y: centre.y)
        c.scaleBy(x: 1, y: CGFloat(ry / rx))
        c.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: 2 * rx, height: 2 * rx)),
               with: .radialGradient(Gradient(colors: [RunnerArt.rgb(RunnerArt.haze).opacity(0.75), RunnerArt.rgb(RunnerArt.haze).opacity(0)]),
                                     center: .zero, startRadius: 0, endRadius: rx))
    }

    // MARK: The street

    /// Two rows of buildings along the line, far to near: facades with windows, shop signs, alleys between.
    /// The sun is ahead and to the right, so the left row's faces are in it and the right row's in shade.
    private func buildings(_ g: GraphicsContext, _ v: RunnerLens) {
        let block = RunnerArt.block
        let first = Int(floor(v.near / block)) - 1, last = Int(floor(v.far / block))
        var panes = [Path](repeating: Path(), count: 8), frames = Path()
        for k in stride(from: last, through: first, by: -1) {
            for side in [-1.0, 1.0] {
                let s = side < 0 ? 0 : 1, seed = JevDraw.hash(k, 70 + s)
                let alley = seed % 3 == 0 ? 2 + 2.5 * RunnerArt.unit(k, 80 + s) : 0.3
                let z0 = Double(k) * block + alley, z1 = Double(k + 1) * block
                guard z1 > v.near + 0.3, z0 < v.far else { continue }
                let tall = 7 + 8 * RunnerArt.unit(k, 90 + s)
                let facade = RunnerArt.facades[(seed / 3) % RunnerArt.facades.count]
                let x = side * RunnerArt.street, outer = side * (RunnerArt.street + 10)
                let light = side < 0 ? 1.06 : 0.8
                if z0 > v.near {
                    g.fill(v.quad((x, 0, z0), (outer, 0, z0), (outer, tall, z0), (x, tall, z0)), with: .color(v.tone(facade, at: z0, light: 0.64)))
                }
                let zn = max(z0, v.near)
                g.fill(v.quad((x, 0, zn), (x, tall, zn), (x, tall, z1), (x, 0, z1)), with: v.along(facade, x: x, y: tall / 2, from: zn, to: z1, light: light))
                // A cornice along the top, and a darker plinth.
                g.fill(v.quad((x, tall - 0.55, zn), (x, tall, zn), (x, tall, z1), (x, tall - 0.55, z1)),
                       with: .color(v.tone(facade, at: (zn + z1) / 2, light: side < 0 ? 1.25 : 0.95)))
                // Windows, floor by floor.
                var y = 2.9
                while y + 1.5 < tall - 0.8 {
                    var z = z0 + 1.1
                    while z + 1.2 < z1 - 0.5 {
                        if z > v.near + 0.4 {
                            let bucket = min(Int(v.fog(z) * 4), 3) + s * 4
                            v.add(&panes[bucket], (x, y, z), (x, y + 1.5, z), (x, y + 1.5, z + 1.15), (x, y, z + 1.15))
                            if v.fog(z) < 0.35 { v.add(&frames, (x, y - 0.12, z - 0.08), (x, y, z - 0.08), (x, y, z + 1.23), (x, y - 0.12, z + 1.23)) }
                        }
                        z += 2.3
                    }
                    y += 2.8
                }
                // A water tank on some roofs, an aerial on others, against the sky.
                if seed % 4 == 0, z0 + 5 < z1 {
                    let tx = side * (RunnerArt.street + 2.6), tz = z0 + 2.5
                    if tz > v.near + 0.5 {
                        let wood = RunnerArt.tone((0.55, 0.38, 0.26), v.fog(tz), light)
                        var legs = Path()
                        for dz in [0.3, 1.9] { v.add(&legs, (tx, tall, tz + dz), (tx, tall + 0.7, tz + dz), (tx, tall + 0.7, tz + dz + 0.12), (tx, tall, tz + dz + 0.12)) }
                        g.fill(legs, with: .color(RunnerArt.tone((0.3, 0.28, 0.28), v.fog(tz))))
                        g.fill(v.quad((tx, tall + 0.7, tz), (tx, tall + 2.5, tz), (tx, tall + 2.5, tz + 2.3), (tx, tall + 0.7, tz + 2.3)), with: .color(wood))
                        var hoops = Path()
                        for hy in [1.2, 1.9] { v.add(&hoops, (tx, tall + hy, tz), (tx, tall + hy + 0.08, tz), (tx, tall + hy + 0.08, tz + 2.3), (tx, tall + hy, tz + 2.3)) }
                        g.fill(hoops, with: .color(RunnerArt.tone((0.25, 0.2, 0.18), v.fog(tz))))
                        var cone = Path()
                        cone.move(to: v.at(tx, tall + 2.5, tz - 0.1)); cone.addLine(to: v.at(tx, tall + 3.2, tz + 1.15)); cone.addLine(to: v.at(tx, tall + 2.5, tz + 2.4))
                        cone.closeSubpath()
                        g.fill(cone, with: .color(RunnerArt.tone((0.4, 0.27, 0.2), v.fog(tz), light)))
                    }
                } else if seed % 4 == 1, z0 + 4 > v.near {
                    var aerial = Path()
                    let ax = side * (RunnerArt.street + 1.5), az = z0 + 4
                    aerial.move(to: v.at(ax, tall, az)); aerial.addLine(to: v.at(ax, tall + 2.6, az))
                    aerial.move(to: v.at(ax, tall + 1.9, az - 0.7)); aerial.addLine(to: v.at(ax, tall + 1.9, az + 0.7))
                    aerial.move(to: v.at(ax, tall + 2.3, az - 0.45)); aerial.addLine(to: v.at(ax, tall + 2.3, az + 0.45))
                    g.stroke(aerial, with: .color(RunnerArt.tone((0.3, 0.3, 0.34), v.fog(az))), lineWidth: 1)
                }
                // A shop sign on some.
                if seed % 5 < 2, z0 + 6 < z1 {
                    let sz = z0 + 1.5, colour = RunnerArt.signs[(seed / 7) % RunnerArt.signs.count]
                    if sz > v.near {
                        g.fill(v.quad((x, 1.7, sz), (x, 2.55, sz), (x, 2.55, sz + 4.5), (x, 1.7, sz + 4.5)), with: .color(v.tone(colour, at: sz + 2, light: side < 0 ? 1.1 : 0.9)))
                        g.fill(v.quad((x, 2.0, sz + 0.6), (x, 2.25, sz + 0.6), (x, 2.25, sz + 3.9), (x, 2.0, sz + 3.9)), with: .color(v.tone((1, 1, 1), at: sz + 2).opacity(0.75)))
                    }
                }
            }
        }
        for (index, pane) in panes.enumerated() {
            let lit = index < 4
            let glass: RunnerRGB = lit ? (0.55, 0.72, 0.9) : (0.3, 0.42, 0.56)
            g.fill(pane, with: .color(RunnerArt.tone(glass, (Double(index % 4) + 0.5) / 4 * 0.92)))
        }
        g.fill(frames, with: .color(.white.opacity(0.35)))
    }

    /// The gravel bed, the walkways, three tracks of sleepers and rails.
    private func track(_ g: GraphicsContext, _ v: RunnerLens) {
        let far = v.camZ + 400, near = v.near
        let bed = RunnerArt.bed, wall = RunnerArt.wall
        var walk = Path(), gravel = Path(), ballast = Path()
        v.add(&walk, (-wall, 0, near), (-bed, 0, near), (-bed, 0, far), (-wall, 0, far))
        v.add(&walk, (bed, 0, near), (wall, 0, near), (wall, 0, far), (bed, 0, far))
        g.fill(walk, with: .color(RunnerArt.rgb(RunnerArt.concrete)))
        v.add(&gravel, (-bed, 0, near), (bed, 0, near), (bed, 0, far), (-bed, 0, far))
        g.fill(gravel, with: .color(RunnerArt.rgb(RunnerArt.gravel)))
        for lane in -1...1 {
            let x = Double(lane) * RunnerArt.gauge
            v.add(&ballast, (x - 1.2, 0, near), (x + 1.2, 0, near), (x + 1.2, 0, far), (x - 1.2, 0, far))
        }
        g.fill(ballast, with: .color(RunnerArt.rgb(RunnerArt.ballast)))
        // The kerb of the walkway, and joints across it.
        var kerbs = Path(), joints = Path()
        for side in [-1.0, 1.0] {
            v.add(&kerbs, (side * bed, 0, near), (side * (bed + 0.18), 0, near), (side * (bed + 0.18), 0, far), (side * bed, 0, far))
        }
        var z = (floor(near / 3) + 1) * 3
        while z < v.camZ + 45 {
            for side in [-1.0, 1.0] { v.add(&joints, (side * (bed + 0.2), 0, z), (side * wall, 0, z), (side * wall, 0, z + 0.06), (side * (bed + 0.2), 0, z + 0.06)) }
            z += 3
        }
        g.fill(kerbs, with: .color(RunnerArt.rgb((0.9, 0.88, 0.84))))
        g.fill(joints, with: .color(.black.opacity(0.12)))

        // Grit, fixed to the ground so it rushes by.
        var dark = Path(), pale = Path()
        let firstCell = Int(floor(near / step))
        for cell in firstCell..<(firstCell + 22) {
            for k in 0..<9 {
                let x = (RunnerArt.unit(cell, 400 + k) - 0.5) * 2 * bed, zz = (Double(cell) + RunnerArt.unit(cell, 430 + k)) * step
                guard zz > near + 0.2 else { continue }
                let p = v.at(x, 0, zz), d = CGFloat(v.scale(zz) * (0.05 + 0.05 * RunnerArt.unit(cell, 460 + k)))
                let speck = CGRect(x: p.x - d / 2, y: p.y - d / 3, width: d, height: d * 0.6)
                if k % 3 == 0 { pale.addRect(speck) } else { dark.addRect(speck) }
            }
        }
        g.fill(dark, with: .color(.black.opacity(0.18)))
        g.fill(pale, with: .color(.white.opacity(0.2)))

        // Sleepers: a top in the light, and the near edge in shade.
        var tops = Path(), edges = Path()
        var s = (floor(near / 0.8) + 1) * 0.8
        while s < v.camZ + 55 {
            for lane in -1...1 {
                let x = Double(lane) * RunnerArt.gauge
                v.add(&tops, (x - 0.98, 0.07, s - 0.12), (x + 0.98, 0.07, s - 0.12), (x + 0.98, 0.07, s + 0.12), (x - 0.98, 0.07, s + 0.12))
                if s - v.camZ < 26 { edges.addRect(v.front(x - 0.98, x + 0.98, 0, 0.07, s - 0.12)) }
            }
            s += 0.8
        }
        g.fill(edges, with: .color(RunnerArt.rgb((0.26, 0.18, 0.13))))
        g.fill(tops, with: .color(RunnerArt.rgb(RunnerArt.wood)))

        // Rails: a dark web, and the polished top catching the sky.
        var webs = Path(), heads = Path()
        for lane in -1...1 {
            for side in [-1.0, 1.0] {
                let x = Double(lane) * RunnerArt.gauge + side * 0.74
                let inner = x < v.camX ? x + 0.035 : x - 0.035
                v.add(&webs, (inner, 0.05, near), (inner, 0.18, near), (inner, 0.18, far), (inner, 0.05, far))
                v.add(&heads, (x - 0.045, 0.18, near), (x + 0.045, 0.18, near), (x + 0.045, 0.18, far), (x - 0.045, 0.18, far))
            }
        }
        g.fill(webs, with: .color(RunnerArt.rgb((0.3, 0.26, 0.24))))
        g.fill(heads, with: .color(RunnerArt.rgb((0.8, 0.82, 0.86))))
        // All of it goes into the haze with the distance: one veil over the ground between the walls.
        g.fill(v.quad((-wall, 0, near), (wall, 0, near), (wall, 0, far), (-wall, 0, far)), with: v.haze())
    }

    /// A low wall each side of the line, painted over in places.
    private func walls(_ g: GraphicsContext, _ v: RunnerLens) {
        let near = v.near, far = v.far, top = RunnerArt.wallTop
        for side in [-1.0, 1.0] {
            let x = side * RunnerArt.wall
            let light = side < 0 ? 1.02 : 0.82
            g.fill(v.quad((x, 0, near), (x, top, near), (x, top, far), (x, 0, far)), with: v.along(RunnerArt.concrete, x: x, y: top / 2, from: near, to: far, light: light))
            g.fill(v.quad((x, top, near), (x + side * 0.35, top, near), (x + side * 0.35, top, far), (x, top, far)),
                   with: v.along((0.9, 0.89, 0.86), x: x, y: top, from: near, to: far, light: 1.08))
            // Its shadow on the walkway, on the shaded side.
            if side > 0 {
                g.fill(v.quad((x - 0.55, 0.005, near), (x, 0.005, near), (x, 0.005, far), (x - 0.55, 0.005, far)), with: .color(.black.opacity(0.1)))
            }
            // Graffiti: tags of fat bubble letters, outlined, along the wall.
            let firstPanel = Int(floor(near / 7)), lastPanel = Int(floor((v.camZ + 50) / 7))
            guard firstPanel <= lastPanel else { continue }
            for k in firstPanel...lastPanel {
                let seed = JevDraw.hash(k, side < 0 ? 500 : 501)
                guard seed % 5 < 3 else { continue }
                let z0 = Double(k) * 7 + 1 + 1.5 * RunnerArt.unit(k, 502), letters = 3 + seed % 3
                guard z0 > near + 0.5 else { continue }
                let fog = v.fog(z0), light = side < 0 ? 1.0 : 0.86
                let fill = RunnerArt.paints[(seed / 5) % RunnerArt.paints.count], rim = RunnerArt.paints[(seed / 7 + 2) % RunnerArt.paints.count]
                var bodies = Path(), shines = Path()
                var outline: CGFloat = 1
                for i in 0..<letters {
                    let zc = z0 + 0.62 * Double(i) + 0.3, yc = 0.58 + 0.07 * sin(Double(i) * 2.1 + Double(seed % 7))
                    let a = v.at(x, yc + 0.33, zc - 0.3), c = v.at(x, yc - 0.33, zc + 0.3)
                    let box = CGRect(x: min(a.x, c.x), y: a.y, width: abs(c.x - a.x), height: c.y - a.y)
                    guard box.width > 0.5 else { continue }
                    bodies.addRoundedRect(in: box, cornerSize: CGSize(width: box.width * 0.4, height: box.height * 0.4))
                    shines.addEllipse(in: CGRect(x: box.minX + box.width * 0.2, y: box.minY + box.height * 0.14, width: box.width * 0.28, height: box.height * 0.2))
                    outline = max(0.6, box.height * 0.09)
                }
                g.stroke(bodies, with: .color(RunnerArt.tone(rim, fog, light * 0.7)), lineWidth: outline * 2.2)
                g.fill(bodies, with: .color(RunnerArt.tone(fill, fog, light)))
                g.stroke(bodies, with: .color(RunnerArt.tone((0.12, 0.1, 0.16), fog)), lineWidth: outline * 0.7)
                g.fill(shines, with: .color(.white.opacity(0.6 * (1 - fog))))
            }
        }
    }

    /// Steel gantries over the line every sixteen metres, the wires strung between them, and signals.
    private func gantries(_ g: GraphicsContext, _ v: RunnerLens, world: Double) {
        var wires = Path()
        for x in [-RunnerArt.gauge, 0, RunnerArt.gauge] {
            let a = v.at(x, 5.15, v.near + 1.5), b = v.at(x, 5.15, v.camZ + 400)
            wires.move(to: a); wires.addLine(to: b)
        }
        g.stroke(wires, with: .color(Color(white: 0.18).opacity(0.55)), lineWidth: 1)
        let first = Int(floor(v.near / 16)), last = Int(floor(v.far / 16))
        guard first <= last else { return }
        for k in stride(from: last, through: first, by: -1) {
            let z = Double(k) * 16 + 6
            guard z > v.near + 0.6 else { continue }
            let fog = v.fog(z)
            let steel = RunnerArt.tone(RunnerArt.steel, fog), lit = RunnerArt.tone(RunnerArt.steel, fog, 1.35), dark = RunnerArt.tone(RunnerArt.steel, fog, 0.6)
            for side in [-1.0, 1.0] {
                let post = v.front(side * 4.05 - 0.13, side * 4.05 + 0.13, 0, 5.7, z)
                g.fill(Path(post), with: .color(steel))
                g.fill(Path(CGRect(x: post.minX, y: post.minY, width: post.width * 0.35, height: post.height)), with: .color(lit))
            }
            let beam = v.front(-4.2, 4.2, 5.4, 5.72, z)
            g.fill(Path(beam), with: .color(steel))
            g.fill(Path(CGRect(x: beam.minX, y: beam.maxY - beam.height * 0.3, width: beam.width, height: beam.height * 0.3)), with: .color(dark))
            var hangers = Path()
            for x in [-RunnerArt.gauge, 0, RunnerArt.gauge] { hangers.addRect(v.front(x - 0.03, x + 0.03, 5.12, 5.4, z)) }
            g.fill(hangers, with: .color(dark))
            // A signal on every third one, green for go.
            if k % 3 == 0 {
                let head = v.front(3.6, 3.95, 3.1, 3.95, z)
                g.fill(Path(roundedRect: head, cornerRadius: head.width * 0.3), with: .color(RunnerArt.tone((0.1, 0.1, 0.12), fog)))
                let r = head.width * 0.3
                let lamp = CGRect(x: head.midX - r, y: head.minY + head.height * 0.28 - r, width: 2 * r, height: 2 * r)
                g.fill(Path(ellipseIn: lamp.insetBy(dx: -r * 1.2, dy: -r * 1.2)),
                       with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 1, blue: 0.5).opacity(0.5 * (1 - fog)), .clear]),
                                             center: CGPoint(x: lamp.midX, y: lamp.midY), startRadius: 0, endRadius: r * 2.2))
                g.fill(Path(ellipseIn: lamp), with: .color(Color(red: 0.45, green: 1, blue: 0.55)))
            }
        }
    }

    // MARK: On the line

    /// Soft shadows of the trains, the barriers and the runner on the ground, cast toward the camera and to the left.
    private func shadows(_ g: GraphicsContext, _ v: RunnerLens, world: Double) {
        var shade = Path()
        for thing in things {
            let x = (Double(thing.lane) - 1) * RunnerArt.gauge
            var near = (Double(thing.cell) - 0.5) * step, far = (Double(thing.last) + 0.5) * step
            if thing.kind == .oncoming {
                near = (2 * Double(thing.cell) - world - 0.5) * step
                far = near + Double(thing.length) * step
            }
            let z0 = max(near - (thing.kind == .low ? 0.5 : thing.kind == .high ? 0.9 : 1.4), v.near), z1 = max(far, v.near)
            guard z1 > z0 else { continue }
            let w = thing.kind == .low || thing.kind == .high ? 0.98 : 1.02
            v.add(&shade, (x - w - 0.35, 0.01, z0), (x + w - 0.2, 0.01, z0), (x + w, 0.01, z1), (x - w, 0.01, z1))
        }
        // Softened at the edge by a faint wider rim rather than a blur, which costs a layer the size of the picture.
        let tint = Color(red: 0.12, green: 0.1, blue: 0.16)
        g.stroke(shade, with: .color(tint.opacity(0.08)), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
        g.fill(shade, with: .color(tint.opacity(0.24)))
    }

    private func barrier(_ g: GraphicsContext, _ v: RunnerLens, _ thing: Thing, at z: Double) {
        guard z > v.near + 0.2 else { return }
        let x = (Double(thing.lane) - 1) * RunnerArt.gauge, fog = v.fog(z)
        let high = thing.kind == .high
        let (y0, y1) = high ? (1.22, 1.95) : (0.5, 0.95)
        let postTop = high ? 2.12 : 0.95
        // Posts, with feet.
        var posts = Path(), feet = Path()
        for side in [-1.0, 1.0] {
            posts.addRect(v.front(x + side * 0.9 - 0.06, x + side * 0.9 + 0.06, 0, postTop, z))
            feet.addRect(v.front(x + side * 0.9 - 0.2, x + side * 0.9 + 0.2, 0, 0.1, z))
        }
        g.fill(feet, with: .color(RunnerArt.tone((0.25, 0.25, 0.28), fog)))
        g.fill(posts, with: .color(RunnerArt.tone((0.85, 0.86, 0.88), fog, 0.8)))
        // The board: its top in the light, then red and white stripes.
        let board = v.front(x - 1.0, x + 1.0, y0, y1, z)
        let lid = v.at(x, y1, z + 0.18)
        g.fill(Path(CGRect(x: board.minX, y: lid.y, width: board.width, height: board.minY - lid.y)), with: .color(RunnerArt.tone((0.95, 0.95, 0.95), fog)))
        g.fill(Path(board), with: .color(RunnerArt.tone((0.97, 0.96, 0.94), fog, 0.92)))
        var stripes = Path()
        let band = board.height * 1.1
        var sx = board.minX - board.height
        while sx < board.maxX {
            stripes.move(to: CGPoint(x: sx, y: board.maxY))
            stripes.addLine(to: CGPoint(x: sx + band * 0.5, y: board.maxY))
            stripes.addLine(to: CGPoint(x: sx + band * 0.5 + board.height, y: board.minY))
            stripes.addLine(to: CGPoint(x: sx + board.height, y: board.minY))
            stripes.closeSubpath()
            sx += band
        }
        var inside = g
        inside.clip(to: Path(board))
        inside.fill(stripes, with: .color(RunnerArt.tone((0.88, 0.14, 0.14), fog, 0.95)))
        inside.fill(Path(CGRect(x: board.minX, y: board.maxY - board.height * 0.18, width: board.width, height: board.height * 0.18)), with: .color(.black.opacity(0.15)))
        g.stroke(Path(board), with: .color(RunnerArt.tone((0.35, 0.08, 0.08), fog).opacity(0.6)), lineWidth: max(0.5, board.height * 0.05))
        // Lamps on the posts, blinking.
        let blink = (now * 2 + Double(thing.serial) * 0.37).truncatingRemainder(dividingBy: 1) < 0.5
        for side in [-1.0, 1.0] {
            let p = v.at(x + side * 0.9, postTop + 0.07, z), r = max(1.2, v.scale(z) * 0.075)
            let colour = high ? Color(red: 1, green: 0.25, blue: 0.15) : Color(red: 1, green: 0.72, blue: 0.1)
            if blink {
                g.fill(Path(ellipseIn: CGRect(x: p.x - r * 3.5, y: p.y - r * 3.5, width: r * 7, height: r * 7)),
                       with: .radialGradient(Gradient(colors: [colour.opacity(0.55 * (1 - fog)), colour.opacity(0)]), center: p, startRadius: 0, endRadius: r * 3.5))
            }
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(blink ? colour : colour.opacity(0.45)))
        }
    }

    /// A train: its side toward the camera, its roof, and its end — the front of an oncoming one, lit up.
    private func train(_ g: GraphicsContext, _ v: RunnerLens, _ thing: Thing, from near: Double, to far: Double) {
        let x = (Double(thing.lane) - 1) * RunnerArt.gauge, hw = 1.04, bottom = 0.2, roof = 2.85
        let coming = thing.kind == .oncoming
        let livery = RunnerArt.liveries[thing.paint % RunnerArt.liveries.count]
        let z0 = max(near, v.near + 0.05), z1 = far
        guard z1 > z0 else { return }
        // The side the camera sees, if any.
        if abs(v.camX - x) > hw {
            let sx = v.camX < x ? x - hw : x + hw
            let light = sx > x ? 1.08 : 0.82
            g.fill(v.quad((sx, 0.05, z0), (sx, roof, z0), (sx, roof, z1), (sx, 0.05, z1)), with: v.along(livery.body, x: sx, y: 1.4, from: z0, to: z1, light: light))
            let mid = v.fog((z0 + z1) / 2)
            g.fill(v.quad((sx, 0.05, z0), (sx, 0.42, z0), (sx, 0.42, z1), (sx, 0.05, z1)), with: .color(RunnerArt.tone((0.18, 0.18, 0.2), mid)))
            g.fill(v.quad((sx, 0.95, z0), (sx, 1.2, z0), (sx, 1.2, z1), (sx, 0.95, z1)), with: .color(RunnerArt.tone(livery.band, mid, light)))
            var panes = Path(), shine = Path(), gaps = Path(), doors = Path()
            var wz = near + 0.9
            while wz + 1.5 < far - 0.4 {
                let slot = Int(((wz - near) / 2.6).rounded())
                if wz > v.near + 0.3 {
                    if slot % 4 == 2 {
                        v.add(&doors, (sx, 0.45, wz), (sx, 2.45, wz), (sx, 2.45, wz + 1.4), (sx, 0.45, wz + 1.4))
                    } else {
                        v.add(&panes, (sx, 1.45, wz), (sx, 2.4, wz), (sx, 2.4, wz + 1.5), (sx, 1.45, wz + 1.5))
                        v.add(&shine, (sx, 2.05, wz + 0.1), (sx, 2.35, wz + 0.1), (sx, 2.35, wz + 0.9), (sx, 2.05, wz + 0.5))
                    }
                }
                if slot % 4 == 3, wz + 2 < far - 1 { v.add(&gaps, (sx, 0.05, wz + 1.95), (sx, roof, wz + 1.95), (sx, roof, wz + 2.2), (sx, 0.05, wz + 2.2)) }
                wz += 2.6
            }
            let fog = v.fog((z0 + z1) / 2)
            g.fill(doors, with: .color(RunnerArt.tone(livery.body, fog, light * 0.8)))
            g.stroke(doors, with: .color(RunnerArt.tone((0.1, 0.1, 0.12), fog).opacity(0.5)), lineWidth: 0.8)
            g.fill(panes, with: .color(RunnerArt.tone(RunnerArt.glass, fog)))
            g.fill(shine, with: .color(RunnerArt.tone(RunnerArt.sheen, fog).opacity(0.6)))
            g.fill(gaps, with: .color(RunnerArt.tone((0.12, 0.12, 0.14), fog)))
            // Paint on the silver ones.
            if thing.paint % RunnerArt.liveries.count == 4 {
                var tag = Path()
                for b in 0..<5 {
                    let zc = near + (far - near) * (0.2 + 0.13 * Double(b)), r = 0.35 + 0.2 * RunnerArt.unit(thing.serial, 600 + b)
                    guard zc - r > v.near else { continue }
                    let a = v.at(sx, 0.75 + r, zc - r), c = v.at(sx, 0.75 - r, zc + r)
                    tag.addEllipse(in: CGRect(x: min(a.x, c.x), y: a.y, width: abs(c.x - a.x), height: c.y - a.y))
                }
                g.fill(tag, with: .color(RunnerArt.tone(RunnerArt.paints[thing.serial % RunnerArt.paints.count], fog)))
            }
        }
        // The roof, with the boxes on it.
        g.fill(v.quad((x - hw, roof, z0), (x + hw, roof, z0), (x + hw, roof, z1), (x - hw, roof, z1)), with: v.along(livery.roof, x: x, y: roof, from: z0, to: z1, light: 1.05))
        var boxes = Path(), fronts = Path()
        var bz = near + 1.6
        while bz + 1.3 < far {
            if bz > v.near + 0.3 {
                v.add(&boxes, (x - 0.55, roof + 0.22, bz), (x + 0.55, roof + 0.22, bz), (x + 0.55, roof + 0.22, bz + 1.3), (x - 0.55, roof + 0.22, bz + 1.3))
                fronts.addRect(v.front(x - 0.55, x + 0.55, roof, roof + 0.22, bz))
            }
            bz += 5
        }
        let midFog = v.fog((z0 + z1) / 2)
        g.fill(fronts, with: .color(RunnerArt.tone((0.5, 0.52, 0.55), midFog)))
        g.fill(boxes, with: .color(RunnerArt.tone((0.7, 0.72, 0.75), midFog, 1.1)))
        // The end facing the camera.
        guard near > v.near + 0.05 else { return }
        let fog = v.fog(near)
        let face = v.front(x - hw, x + hw, bottom, roof, near)
        let corner = face.width * 0.12
        g.fill(Path(roundedRect: face, cornerRadius: corner), with: .color(RunnerArt.tone(livery.body, fog, 0.86)))
        g.fill(Path(v.front(x - hw, x + hw, 0.95, 1.2, near)), with: .color(RunnerArt.tone(livery.band, fog, 0.9)))
        g.fill(Path(v.front(x - hw, x + hw, 0.05, 0.42, near)), with: .color(RunnerArt.tone((0.15, 0.15, 0.17), fog)))
        let glassTone = RunnerArt.tone(RunnerArt.glass, fog), sheen = RunnerArt.tone(RunnerArt.sheen, fog)
        if coming {
            // Its headlamps light the track in front of it.
            let reachZ = max(near - 9, v.near + 0.2)
            if reachZ < near {
                let pool = v.quad((x - 0.95, 0.02, near), (x + 0.95, 0.02, near), (x + 1.35, 0.02, reachZ), (x - 1.35, 0.02, reachZ))
                g.fill(pool, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.7).opacity(0.5 * (1 - fog)), Color(red: 1, green: 0.95, blue: 0.7).opacity(0)]),
                                                   startPoint: v.at(x, 0, near), endPoint: v.at(x, 0, reachZ)))
            }
            // The cab: a wide windscreen, the route sign over it, headlamps blazing.
            let screen = v.front(x - 0.8, x + 0.8, 1.5, 2.5, near)
            g.fill(Path(roundedRect: screen, cornerRadius: screen.height * 0.18),
                   with: .linearGradient(Gradient(colors: [sheen, glassTone]), startPoint: CGPoint(x: screen.minX, y: screen.minY), endPoint: CGPoint(x: screen.maxX, y: screen.maxY)))
            let sign = v.front(x - 0.5, x + 0.5, 2.56, 2.76, near)
            g.fill(Path(roundedRect: sign, cornerRadius: sign.height * 0.2), with: .color(Color(white: 0.08)))
            g.fill(Path(sign.insetBy(dx: sign.width * 0.08, dy: sign.height * 0.25)), with: .color(Color(red: 1, green: 0.62, blue: 0.1).opacity(1 - fog * 0.5)))
            let wipers = v.at(x, 1.52, near)
            var wiper = Path()
            wiper.move(to: wipers); wiper.addLine(to: v.at(x - 0.5, 2.1, near))
            g.stroke(wiper, with: .color(.black.opacity(0.5)), lineWidth: max(0.6, CGFloat(v.scale(near) * 0.03)))
            for side in [-1.0, 1.0] {
                let p = v.at(x + side * 0.66, 0.72, near), r = CGFloat(v.scale(near) * 0.15)
                let pulse = 0.85 + 0.15 * sin(now * 9)
                g.fill(Path(ellipseIn: CGRect(x: p.x - r * 5, y: p.y - r * 5, width: r * 10, height: r * 10)),
                       with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.8).opacity(0.75 * pulse), Color(red: 1, green: 0.9, blue: 0.6).opacity(0.18), .clear]),
                                             center: p, startRadius: 0, endRadius: r * 5))
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
            }
        } else {
            // The back of a carriage: a door with a window, two small windows, tail lamps, a coupler.
            let door = v.front(x - 0.38, x + 0.38, 0.45, 2.5, near)
            g.fill(Path(roundedRect: door, cornerRadius: door.width * 0.08), with: .color(RunnerArt.tone(livery.body, fog, 0.72)))
            let doorPane = v.front(x - 0.28, x + 0.28, 1.5, 2.35, near)
            g.fill(Path(roundedRect: doorPane, cornerRadius: doorPane.width * 0.1), with: .color(glassTone))
            for side in [-1.0, 1.0] {
                let pane = v.front(x + side * 0.72 - 0.22, x + side * 0.72 + 0.22, 1.6, 2.35, near)
                g.fill(Path(roundedRect: pane, cornerRadius: pane.width * 0.15), with: .color(glassTone))
                g.fill(Path(CGRect(x: pane.minX + pane.width * 0.15, y: pane.minY + pane.height * 0.1, width: pane.width * 0.25, height: pane.height * 0.5)), with: .color(sheen.opacity(0.5)))
                let lamp = v.front(x + side * 0.8 - 0.1, x + side * 0.8 + 0.1, 0.55, 0.75, near)
                g.fill(Path(roundedRect: lamp, cornerRadius: lamp.width * 0.3), with: .color(RunnerArt.tone((0.95, 0.12, 0.1), fog)))
            }
            g.fill(Path(v.front(x - 0.12, x + 0.12, 0.25, 0.5, near)), with: .color(RunnerArt.tone((0.12, 0.12, 0.13), fog)))
        }
        g.stroke(Path(roundedRect: face, cornerRadius: corner), with: .color(.black.opacity(0.25 * (1 - fog))), lineWidth: 1)
    }

    /// A gold coin, spinning, its edge flashing as it turns.
    private func coin(_ g: GraphicsContext, _ v: RunnerLens, _ coin: JevRunner.Coin) {
        let z = (Double(coin.cell) - 0.5) * step
        guard z > v.near + 0.5 else { return }
        let x = (Double(coin.lane) - 1) * RunnerArt.gauge, y = coin.high ? 2.05 : 0.62
        let p = v.at(x, y + 0.06 * sin(now * 3 + Double(coin.cell)), z), r = CGFloat(v.scale(z) * 0.3)
        let fog = v.fog(z)
        let turn = cos(now * 3.4 + Double(coin.cell) * 0.8 + Double(coin.lane))
        let w = r * CGFloat(max(0.16, abs(turn)))
        if !coin.high {
            let q = v.at(x, 0, z), s = r * 0.9
            g.fill(Path(ellipseIn: CGRect(x: q.x - s, y: q.y - s * 0.22, width: 2 * s, height: s * 0.44)), with: .color(.black.opacity(0.16 * (1 - fog))))
        }
        let rim = CGRect(x: p.x - w, y: p.y - r, width: 2 * w, height: 2 * r)
        g.fill(Path(ellipseIn: rim.offsetBy(dx: w * 0.12 + 0.6, dy: 0)), with: .color(RunnerArt.tone((0.7, 0.42, 0.04), fog)))
        g.fill(Path(ellipseIn: rim), with: .linearGradient(Gradient(colors: [RunnerArt.tone((1, 0.95, 0.55), fog), RunnerArt.tone((1, 0.78, 0.18), fog), RunnerArt.tone((0.85, 0.55, 0.06), fog)]),
                                                        startPoint: CGPoint(x: rim.minX, y: rim.minY), endPoint: CGPoint(x: rim.maxX, y: rim.maxY)))
        if w > r * 0.3 {
            g.stroke(Path(ellipseIn: rim.insetBy(dx: w * 0.24, dy: r * 0.24)), with: .color(RunnerArt.tone((0.8, 0.5, 0.05), fog).opacity(0.7)), lineWidth: max(0.6, r * 0.1))
            g.fill(Path(ellipseIn: CGRect(x: rim.minX + w * 0.35, y: rim.minY + r * 0.25, width: w * 0.35, height: r * 0.5)), with: .color(.white.opacity(0.55 * (1 - fog))))
        }
        // Now and then a glint.
        let wink = sin(now * 2.3 + Double(coin.serial) * 1.7)
        if wink > 0.8, fog < 0.6 {
            let s = r * CGFloat((wink - 0.8) * 5) * 0.9, at = CGPoint(x: p.x + w * 0.5, y: p.y - r * 0.6)
            var star = Path()
            star.move(to: CGPoint(x: at.x, y: at.y - s))
            star.addQuadCurve(to: CGPoint(x: at.x + s, y: at.y), control: at)
            star.addQuadCurve(to: CGPoint(x: at.x, y: at.y + s), control: at)
            star.addQuadCurve(to: CGPoint(x: at.x - s, y: at.y), control: at)
            star.addQuadCurve(to: CGPoint(x: at.x, y: at.y - s), control: at)
            g.fill(star, with: .color(.white))
        }
    }

    /// Coins just picked up: a burst where they were, and the coin flying up to the counter.
    private func sparkle(_ g: GraphicsContext, _ v: RunnerLens, runnerZ: Double) {
        guard !taken.isEmpty, t >= 0.5, t < 1 else { return }
        let p = (t - 0.5) * 2, unit = v.width / 24
        let counter = CGPoint(x: v.width - 10 - unit * 6.6 + unit * 1.35, y: 10 + unit * 1.65)
        for coin in taken {
            let x = (Double(coin.lane) - 1) * RunnerArt.gauge, y = coin.high ? 2.05 : 0.62
            let z = max((Double(coin.cell) - 0.5) * step, runnerZ + 0.3)
            // It pops up over the runner's head, then away to the counter.
            let spot = v.at(x, y, z), from = v.at(x, max(y, 1.3) + 0.7, z), r0 = CGFloat(v.scale(z) * 0.24)
            // The burst.
            var rays = Path()
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi + 0.2, d0 = r0 * CGFloat(0.9 + 1.2 * p), d1 = r0 * CGFloat(1.3 + 2.4 * p)
                rays.move(to: CGPoint(x: spot.x + CGFloat(cos(a)) * d0, y: spot.y + CGFloat(sin(a)) * d0))
                rays.addLine(to: CGPoint(x: spot.x + CGFloat(cos(a)) * d1, y: spot.y + CGFloat(sin(a)) * d1))
            }
            g.stroke(rays, with: .color(Color(red: 1, green: 0.93, blue: 0.55).opacity(0.9 * (1 - p))), style: StrokeStyle(lineWidth: max(1, r0 * 0.14), lineCap: .round))
            // The coin, arcing up to the counter and shrinking into it.
            let e = JevDraw.smooth(p)
            let at = CGPoint(x: JevDraw.mix(Double(from.x), Double(counter.x), e), y: JevDraw.mix(Double(from.y), Double(counter.y), e) - Double(r0) * 3 * sin(p * .pi))
            let r = CGFloat(JevDraw.mix(Double(r0), Double(unit * 0.55), e))
            g.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r)),
                   with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.55), Color(red: 1, green: 0.76, blue: 0.16), Color(red: 0.86, green: 0.55, blue: 0.05)]),
                                         startPoint: CGPoint(x: at.x - r, y: at.y - r), endPoint: CGPoint(x: at.x + r, y: at.y + r)))
            g.stroke(Path(ellipseIn: CGRect(x: at.x - r * 0.66, y: at.y - r * 0.66, width: r * 1.32, height: r * 1.32)), with: .color(Color(red: 0.8, green: 0.5, blue: 0.05)), lineWidth: max(0.8, r * 0.12))
        }
    }

    // MARK: The runner

    /// The kid, from behind: sneakers, jeans, an orange hoodie and a backpack, a cap on backwards.
    /// Running, arms and legs swing with the clock; in the air the knees come up; rolling, a ball.
    private func kid(_ g: GraphicsContext, _ v: RunnerLens, x: Double, z: Double, lift: Double, jump: Double, roll: Double, lean: Double) {
        let k = v.scale(z)
        // The shadow stays on the ground, smaller the higher the kid goes.
        let foot = v.at(x, 0, z), spread = CGFloat(k * 0.42 / (1 + lift * 0.5))
        g.fill(Path(ellipseIn: CGRect(x: foot.x - spread, y: foot.y - spread * 0.3, width: 2 * spread, height: spread * 0.6)),
               with: .radialGradient(Gradient(colors: [Color.black.opacity(0.38 / (1 + lift * 0.6)), Color.black.opacity(0)]), center: foot, startRadius: 0, endRadius: spread))
        var c = g
        let base = v.at(x, lift, z)
        c.translateBy(x: base.x, y: base.y)
        c.rotate(by: .radians(lean))
        c.scaleBy(x: CGFloat(k), y: CGFloat(k))
        let hoodie = RunnerArt.rgb(RunnerArt.hoodie), hoodieDark = JevDraw.shade(RunnerArt.hoodie, 0.72)
        let pack = RunnerArt.rgb(RunnerArt.pack), packDark = JevDraw.shade(RunnerArt.pack, 0.66), packLight = JevDraw.shade(RunnerArt.pack, 1.25)
        let skin = RunnerArt.rgb(RunnerArt.skin), jeans = RunnerArt.rgb(RunnerArt.jeans), jeansDark = JevDraw.shade(RunnerArt.jeans, 0.7)

        if roll >= 0 {
            // Curled up tight and rolling: the pack on the back, the cap tucked in on top, the soles
            // underneath, arms hugging the knees, and the air swept round.
            let r = 0.4, wobble = sin(now * 22) * 0.06, spin = now * 13
            let middle = CGPoint(x: 0, y: -r * 0.95)
            c.fill(Path(ellipseIn: CGRect(x: -r, y: middle.y - r * 0.95, width: 2 * r, height: 2 * r * 0.95)),
                   with: .radialGradient(Gradient(colors: [JevDraw.shade(RunnerArt.hoodie, 1.15), hoodie, hoodieDark]),
                                         center: CGPoint(x: 0.1, y: middle.y - r * 0.4), startRadius: 0, endRadius: r * 1.25))
            var hug = Path()
            for side in [-1.0, 1.0] {
                hug.move(to: CGPoint(x: side * r * 0.72, y: middle.y - r * 0.55))
                hug.addQuadCurve(to: CGPoint(x: side * r * 0.35, y: middle.y + r * 0.8), control: CGPoint(x: side * r * 1.02, y: middle.y + r * 0.35))
            }
            c.stroke(hug, with: .color(hoodieDark), style: StrokeStyle(lineWidth: 0.09, lineCap: .round))
            for side in [-1.0, 1.0] {
                let sole = CGRect(x: side * 0.14 - 0.08, y: middle.y + r * 0.72, width: 0.16, height: 0.1)
                c.fill(Path(roundedRect: sole, cornerRadius: 0.04), with: .color(Color(white: 0.94)))
                c.fill(Path(CGRect(x: sole.minX, y: sole.minY, width: sole.width, height: 0.03)), with: .color(Color(red: 0.2, green: 0.55, blue: 0.95)))
            }
            c.fill(Path(ellipseIn: CGRect(x: -0.15, y: middle.y - r * 1.12, width: 0.3, height: 0.2)), with: .color(RunnerArt.rgb(RunnerArt.cap)))
            c.fill(Path(ellipseIn: CGRect(x: -0.1, y: middle.y - r * 0.98, width: 0.2, height: 0.07)), with: .color(JevDraw.shade(RunnerArt.cap, 0.6)))
            var bag = c
            bag.translateBy(x: 0, y: middle.y + 0.02)
            bag.rotate(by: .radians(wobble))
            let back = CGRect(x: -0.16, y: -0.17, width: 0.32, height: 0.33)
            bag.fill(Path(roundedRect: back, cornerRadius: 0.08), with: .linearGradient(Gradient(colors: [packDark, pack, packLight]),
                                                                                     startPoint: CGPoint(x: back.minX, y: 0), endPoint: CGPoint(x: back.maxX, y: 0)))
            bag.fill(Path(roundedRect: CGRect(x: back.minX, y: back.minY, width: back.width, height: 0.11), cornerRadius: 0.06), with: .color(packDark))
            bag.fill(Path(roundedRect: CGRect(x: back.minX + 0.05, y: back.minY + 0.17, width: back.width - 0.1, height: 0.12), cornerRadius: 0.04), with: .color(packLight))
            bag.fill(Path(roundedRect: CGRect(x: -0.03, y: back.minY + 0.09, width: 0.06, height: 0.045), cornerRadius: 0.01), with: .color(Color(red: 1, green: 0.8, blue: 0.2)))
            var swoosh = Path()
            for a in 0..<3 {
                let start = spin + Double(a) * 2.1
                swoosh.addArc(center: middle, radius: r * 1.28, startAngle: .radians(start), endAngle: .radians(start + 1.1), clockwise: false)
            }
            c.stroke(swoosh, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 0.045, lineCap: .round))
            return
        }

        let air = jump >= 0
        let phase = now * 2 * .pi * 2.3 * pace
        let bob = air ? 0 : -abs(cos(phase)) * 0.035
        let hip = -0.8 + bob
        // Legs and sneakers.
        for side in [-1.0, 1.0] {
            let up = air ? 1 : max(0, sin(phase + (side < 0 ? 0 : .pi)))
            let knee = air ? CGPoint(x: side * 0.15, y: hip + 0.22) : CGPoint(x: side * 0.12, y: hip + 0.38 - up * 0.12)
            let ankle = air ? CGPoint(x: side * 0.16, y: hip + 0.44) : CGPoint(x: side * 0.1, y: -0.08 - up * 0.3)
            var leg = Path()
            leg.move(to: CGPoint(x: side * 0.09, y: hip))
            leg.addLine(to: knee)
            leg.addLine(to: ankle)
            c.stroke(leg, with: .color(up > 0.5 ? jeansDark : jeans), style: StrokeStyle(lineWidth: 0.14, lineCap: .round, lineJoin: .round))
            if up > 0.35 {
                // Heel up: the sole shows.
                let sole = CGRect(x: ankle.x - 0.08, y: ankle.y - 0.02, width: 0.16, height: 0.15)
                c.fill(Path(roundedRect: sole, cornerRadius: 0.05), with: .color(Color(white: 0.93)))
                c.fill(Path(roundedRect: sole.insetBy(dx: 0.025, dy: 0.03), cornerRadius: 0.03), with: .color(Color(white: 0.72)))
                c.fill(Path(CGRect(x: sole.minX, y: sole.minY, width: sole.width, height: 0.035)), with: .color(Color(red: 0.2, green: 0.55, blue: 0.95)))
            } else {
                let heel = CGRect(x: ankle.x - 0.085, y: ankle.y - 0.02, width: 0.17, height: 0.1)
                c.fill(Path(roundedRect: heel, cornerRadius: 0.04), with: .color(.white))
                c.fill(Path(CGRect(x: heel.minX, y: heel.maxY - 0.03, width: heel.width, height: 0.03)), with: .color(Color(white: 0.75)))
                c.fill(Path(roundedRect: CGRect(x: heel.midX - 0.03, y: heel.minY, width: 0.06, height: 0.06), cornerRadius: 0.015),
                       with: .color(Color(red: 0.2, green: 0.55, blue: 0.95)))
            }
        }
        // Arms, swinging against the legs — or flung up in the air.
        var arms: [(shoulder: CGPoint, elbow: CGPoint, hand: CGPoint)] = []
        for side in [-1.0, 1.0] {
            let swing = sin(phase + (side < 0 ? .pi : 0))
            let shoulder = CGPoint(x: side * 0.22, y: -1.19 + bob)
            if air {
                arms.append((shoulder, CGPoint(x: side * 0.38, y: -1.34), CGPoint(x: side * 0.44, y: -1.56)))
            } else {
                arms.append((shoulder, CGPoint(x: side * (0.33 + 0.02 * swing), y: -0.99 + bob - 0.03 * swing),
                             CGPoint(x: side * (0.27 - 0.07 * swing), y: -0.86 + bob - 0.17 * max(swing, 0) + 0.05 * min(swing, 0))))
            }
        }
        // The body: the hoodie, its hood, and the pack on the back.
        var torso = Path()
        torso.move(to: CGPoint(x: -0.17, y: hip + 0.07))
        torso.addLine(to: CGPoint(x: 0.17, y: hip + 0.07))
        torso.addQuadCurve(to: CGPoint(x: 0.23, y: -1.18 + bob), control: CGPoint(x: 0.21, y: -0.98 + bob))
        torso.addQuadCurve(to: CGPoint(x: -0.23, y: -1.18 + bob), control: CGPoint(x: 0, y: -1.32 + bob))
        torso.addQuadCurve(to: CGPoint(x: -0.17, y: hip + 0.07), control: CGPoint(x: -0.21, y: -0.98 + bob))
        torso.closeSubpath()
        c.fill(torso, with: .linearGradient(Gradient(colors: [hoodieDark, hoodie, JevDraw.shade(RunnerArt.hoodie, 1.12)]),
                                            startPoint: CGPoint(x: -0.23, y: 0), endPoint: CGPoint(x: 0.23, y: 0)))
        c.fill(Path(roundedRect: CGRect(x: -0.18, y: hip, width: 0.36, height: 0.1), cornerRadius: 0.04), with: .color(hoodieDark))
        for arm in arms {
            var limb = Path()
            limb.move(to: arm.shoulder)
            limb.addLine(to: arm.elbow)
            limb.addLine(to: arm.hand)
            c.stroke(limb, with: .color(hoodie), style: StrokeStyle(lineWidth: 0.11, lineCap: .round, lineJoin: .round))
            c.fill(Path(ellipseIn: CGRect(x: arm.hand.x - 0.05, y: arm.hand.y - 0.05, width: 0.1, height: 0.1)), with: .color(skin))
        }
        let jolt = air ? 0 : -abs(sin(phase)) * 0.025
        let bag = CGRect(x: -0.175, y: -1.13 + bob + jolt, width: 0.35, height: 0.4)
        var straps = Path()
        for side in [-1.0, 1.0] { straps.addRoundedRect(in: CGRect(x: side * 0.13 - 0.03, y: -1.22 + bob, width: 0.06, height: 0.14), cornerSize: CGSize(width: 0.02, height: 0.02)) }
        c.fill(straps, with: .color(packDark))
        c.fill(Path(roundedRect: bag, cornerRadius: 0.08), with: .linearGradient(Gradient(colors: [packDark, pack, packLight]),
                                                                              startPoint: CGPoint(x: bag.minX, y: 0), endPoint: CGPoint(x: bag.maxX, y: 0)))
        let pocket = CGRect(x: bag.minX + 0.05, y: bag.minY + 0.2, width: bag.width - 0.1, height: 0.16)
        c.fill(Path(roundedRect: pocket, cornerRadius: 0.05), with: .color(packLight))
        c.stroke(Path(roundedRect: pocket, cornerRadius: 0.05), with: .color(packDark.opacity(0.6)), lineWidth: 0.012)
        var flap = Path()
        flap.move(to: CGPoint(x: bag.minX, y: bag.minY + 0.08))
        flap.addQuadCurve(to: CGPoint(x: bag.maxX, y: bag.minY + 0.08), control: CGPoint(x: bag.midX, y: bag.minY - 0.04))
        flap.addLine(to: CGPoint(x: bag.maxX, y: bag.minY + 0.13))
        flap.addQuadCurve(to: CGPoint(x: bag.minX, y: bag.minY + 0.13), control: CGPoint(x: bag.midX, y: bag.minY + 0.2))
        flap.closeSubpath()
        c.fill(flap, with: .color(packDark))
        c.fill(Path(roundedRect: CGRect(x: bag.midX - 0.035, y: bag.minY + 0.12, width: 0.07, height: 0.05), cornerRadius: 0.012), with: .color(Color(red: 1, green: 0.8, blue: 0.2)))
        c.fill(Path(ellipseIn: CGRect(x: -0.13, y: -1.3 + bob, width: 0.26, height: 0.12)), with: .color(hoodieDark))
        // The head: hair from behind, ears, a cap on backwards.
        let head = CGPoint(x: 0, y: -1.43 + bob)
        c.fill(Path(CGRect(x: -0.045, y: head.y + 0.08, width: 0.09, height: 0.07)), with: .color(JevDraw.shade(RunnerArt.skin, 0.85)))
        for side in [-1.0, 1.0] {
            c.fill(Path(ellipseIn: CGRect(x: head.x + side * 0.135 - 0.035, y: head.y - 0.03, width: 0.07, height: 0.08)), with: .color(skin))
        }
        c.fill(Path(ellipseIn: CGRect(x: head.x - 0.14, y: head.y - 0.14, width: 0.28, height: 0.29)), with: .color(RunnerArt.rgb(RunnerArt.hair)))
        var dome = Path()
        dome.move(to: CGPoint(x: head.x - 0.15, y: head.y - 0.01))
        dome.addQuadCurve(to: CGPoint(x: head.x + 0.15, y: head.y - 0.01), control: CGPoint(x: head.x, y: head.y - 0.33))
        dome.closeSubpath()
        c.fill(dome, with: .linearGradient(Gradient(colors: [JevDraw.shade(RunnerArt.cap, 0.75), RunnerArt.rgb(RunnerArt.cap), JevDraw.shade(RunnerArt.cap, 1.2)]),
                                           startPoint: CGPoint(x: head.x - 0.15, y: 0), endPoint: CGPoint(x: head.x + 0.15, y: 0)))
        c.fill(Path(ellipseIn: CGRect(x: head.x - 0.11, y: head.y - 0.06, width: 0.22, height: 0.08)), with: .color(JevDraw.shade(RunnerArt.cap, 0.6)))
        c.fill(Path(ellipseIn: CGRect(x: head.x - 0.035, y: head.y - 0.13, width: 0.07, height: 0.04)), with: .color(.white.opacity(0.85)))
        // Stars round the head after a crash.
        if crash != nil, since > 0.3 {
            var stars = Path()
            for s in 0..<5 {
                let a = now * 3 + Double(s) / 5 * 2 * .pi
                let p = CGPoint(x: head.x + CGFloat(cos(a)) * 0.36, y: head.y - 0.24 + CGFloat(sin(a)) * 0.1)
                let r = 0.09
                for q in 0..<5 {
                    let ang = Double(q) / 5 * 2 * .pi - .pi / 2, inner = ang + .pi / 5
                    let outer = CGPoint(x: p.x + CGFloat(cos(ang) * r), y: p.y + CGFloat(sin(ang) * r))
                    let dip = CGPoint(x: p.x + CGFloat(cos(inner) * r * 0.45), y: p.y + CGFloat(sin(inner) * r * 0.45))
                    if q == 0 { stars.move(to: outer) } else { stars.addLine(to: outer) }
                    stars.addLine(to: dip)
                }
                stars.closeSubpath()
            }
            c.fill(stars, with: .color(Color(red: 1, green: 0.88, blue: 0.2)))
        }
    }

    // MARK: Speed, light, numbers

    /// Streaks rushing out of the vanishing point toward the edges, more and brighter the faster the run.
    private func rush(_ g: GraphicsContext, _ v: RunnerLens) {
        guard !over else { return }
        let fast = 0.35 + 0.65 * min(max((pace - 1) / 0.25, 0), 1)
        let centre = CGPoint(x: v.width / 2, y: v.horizon)
        var streaks = Path()
        for k in 0..<Int(10 + 14 * fast) {
            let angle = 2 * .pi * RunnerArt.unit(k, 700)
            let phase = (now * (0.7 + 0.6 * RunnerArt.unit(k, 701)) * pace + RunnerArt.unit(k, 702)).truncatingRemainder(dividingBy: 1)
            let r0 = v.width * (0.45 + 0.6 * phase), len = v.width * (0.05 + 0.12 * phase) * fast
            let dx = cos(angle), dy = sin(angle)
            streaks.move(to: CGPoint(x: centre.x + dx * r0, y: centre.y + dy * r0))
            streaks.addLine(to: CGPoint(x: centre.x + dx * (r0 + len), y: centre.y + dy * (r0 + len)))
        }
        g.stroke(streaks, with: .color(.white.opacity(0.28 * fast)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    /// The corners falling away.
    private func light(_ g: GraphicsContext, _ v: RunnerLens) {
        // Only outside the clear middle, so that the shading covers what it darkens and no more.
        let centre = CGPoint(x: v.width / 2, y: v.height * 0.5), clear = v.width * 0.5
        var rim = Path(CGRect(x: 0, y: 0, width: v.width, height: v.height))
        rim.addEllipse(in: CGRect(x: centre.x - clear, y: centre.y - clear, width: 2 * clear, height: 2 * clear))
        g.fill(rim, with: .radialGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.2)]), center: centre, startRadius: clear, endRadius: v.height * 0.78),
               style: FillStyle(eoFill: true))
    }

    /// The score, the coins and the pace, on glass across the top.
    private func dashboard(_ g: GraphicsContext, _ size: CGSize) {
        let unit = size.width / 24, top: CGFloat = 10
        let scoreBox = CGRect(x: 10, y: top, width: unit * 8.2, height: unit * 3.3)
        let coinBox = CGRect(x: size.width - 10 - unit * 6.6, y: top, width: unit * 6.6, height: unit * 3.3)
        glass(g, scoreBox, radius: unit * 0.9)
        glass(g, coinBox, radius: unit * 0.9)
        number(g, "\(score)", at: CGPoint(x: scoreBox.minX + unit * 0.7, y: scoreBox.midY - unit * 0.35), size: unit * 1.55, anchor: .leading)
        number(g, "\(after.z) 步", at: CGPoint(x: scoreBox.minX + unit * 0.75, y: scoreBox.midY + unit * 0.95), size: unit * 0.62, weight: .bold,
               colour: .white.opacity(0.75), anchor: .leading)
        // The pace: how much faster than the start.
        let chip = CGRect(x: scoreBox.maxX + unit * 0.4, y: top + unit * 0.55, width: unit * 4, height: unit * 2.2)
        glass(g, chip, radius: chip.height / 2)
        number(g, String(format: "×%.2f", pace), at: CGPoint(x: chip.midX, y: chip.midY), size: unit * 0.85, colour: Color(red: 1, green: 0.84, blue: 0.3))
        // The coins: a coin, and the count.
        let icon = CGPoint(x: coinBox.minX + unit * 1.35, y: coinBox.midY), r = unit * 0.78
        g.fill(Path(ellipseIn: CGRect(x: icon.x - r + 1, y: icon.y - r + 1.5, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.6, green: 0.35, blue: 0.02)))
        g.fill(Path(ellipseIn: CGRect(x: icon.x - r, y: icon.y - r, width: 2 * r, height: 2 * r)),
               with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.55), Color(red: 1, green: 0.76, blue: 0.16), Color(red: 0.86, green: 0.55, blue: 0.05)]),
                                     startPoint: CGPoint(x: icon.x - r, y: icon.y - r), endPoint: CGPoint(x: icon.x + r, y: icon.y + r)))
        g.stroke(Path(ellipseIn: CGRect(x: icon.x - r * 0.68, y: icon.y - r * 0.68, width: r * 1.36, height: r * 1.36)), with: .color(Color(red: 0.8, green: 0.5, blue: 0.05)), lineWidth: 1.2)
        let bump = taken.isEmpty ? 0 : max(0, 1 - since / 0.3)
        number(g, "\(collected)", at: CGPoint(x: coinBox.maxX - unit * 0.7, y: coinBox.midY), size: unit * 1.35 * CGFloat(1 + 0.25 * bump), anchor: .trailing)
    }

    /// A panel of smoked glass, lit along its top edge.
    private func glass(_ g: GraphicsContext, _ rect: CGRect, radius: CGFloat) {
        let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        g.fill(Path(roundedRect: rect.offsetBy(dx: 1.5, dy: 2.5), cornerRadius: radius, style: .continuous), with: .color(.black.opacity(0.18)))
        g.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.3).opacity(0.72), Color(red: 0.05, green: 0.06, blue: 0.1).opacity(0.62)]),
                                            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        let sheen = CGRect(x: rect.minX + 1.5, y: rect.minY + 1.5, width: rect.width - 3, height: rect.height * 0.46)
        g.fill(Path(roundedRect: sheen, cornerRadius: max(radius - 1.5, 1), style: .continuous),
               with: .linearGradient(Gradient(colors: [.white.opacity(0.2), .white.opacity(0.02)]), startPoint: CGPoint(x: 0, y: sheen.minY), endPoint: CGPoint(x: 0, y: sheen.maxY)))
        g.stroke(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.45), .white.opacity(0.08)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)), lineWidth: 1)
    }

    /// Figures over the picture: rounded, their digits all one width so they do not jitter.
    private func number(_ g: GraphicsContext, _ text: String, at point: CGPoint, size: CGFloat, weight: Font.Weight = .heavy,
                        colour: Color = .white, anchor: UnitPoint = .center) {
        let font = Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
        g.draw(Text(text).font(font).foregroundColor(.black.opacity(0.45)), at: CGPoint(x: point.x + size * 0.03, y: point.y + size * 0.07), anchor: anchor)
        g.draw(Text(text).font(font).foregroundColor(colour), at: point, anchor: anchor)
    }
}
