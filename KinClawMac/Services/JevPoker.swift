import SwiftUI

/// 德州扑克 — no-limit Texas Hold'em, you against three computer players, as a
/// test of judgment when the cards are hidden and the money is real.
///
/// The measuring is the program's: what the hand is, how often it wins at a
/// showdown against what these opponents can be holding (a Monte Carlo deal
/// against ranges that narrow with every bet they make, read through the same
/// styles that make them play), what a call costs against what it can win, and
/// how often a bet makes them all fold. The judgment is the reader's: whether
/// a 30% chance is worth 40 chips into 180, whether to bet a pair into a man
/// who never folds.
///
/// The three at the table play simple, distinct styles, so there is something
/// to read: the rock plays few hands and bets them hard, the calling station
/// calls with nearly anything and seldom raises, the maniac bets and raises
/// all the time. They act instantly; the game only stops at your decisions,
/// and the picture plays back what they did in between.
@MainActor
final class JevPoker: JevGame {
    let id = "poker", title = "德州扑克", symbol = "suit.spade.fill"
    let rules = "No-limit Texas Hold'em at a table of four: you against three computer players, the rock (tight and aggressive), the calling station (loose and passive) and the maniac (loose and aggressive). Everyone starts with 1000 chips; the blinds start at 10 and 20 and go up every 20 hands. You get two cards of your own; five shared cards come face up in three rounds (three on the flop, one on the turn, one on the river), with a round of betting before the flop and after each round. A bet can be anything from the big blind to all your chips, and a raise must be at least as big as the last bet or raise. When everyone else folds, the last player takes the pot; otherwise the best five-card hand from a player's two cards and the five shared cards wins it. The game lasts up to 100 hands and what counts is how many chips you end with; losing all of them ends the game."
    let question = "Which action is best for ending the game with as many chips as possible?"
    let howToJudge = "Compare your chance of winning at showdown with the price: calling is worth it when that chance is clearly higher than the share of the final pot you would pay, and folding is right when it is clearly lower. A strong hand, one that wins well over half the time, should bet or raise, above all against the calling station, who pays off with worse hands. A raise also wins when everybody folds, so both the fold chance and the chance of winning when called count; bluffs work on the rock and fail on the calling station. A draw wins less often now but can improve on the cards to come. Do not put all your chips in with a hand that wins less than half the time when called: losing them all ends the game. With less than a pot left behind you are committed, so do not fold a decent hand then."

    nonisolated static let hands = 100, start = 1000
    /// The blinds, a level every twenty hands.
    nonisolated static let levels: [(small: Int, big: Int)] = [(10, 20), (15, 30), (25, 50), (40, 80), (60, 120)]
    /// The table, clockwise from your chair.
    nonisolated static let names = ["你", "岩石", "跟注站", "疯子"]
    nonisolated static let who = ["you", "the rock", "the calling station", "the maniac"]
    nonisolated static let manner = ["", "tight and aggressive: plays few hands, bets and raises only with strong ones, folds the rest",
                                     "loose and passive: plays most hands, calls with almost anything, seldom raises",
                                     "loose and aggressive: plays many hands, bets and raises very often, bluffing a lot"]
    nonisolated static let streets = ["before the flop", "on the flop", "on the turn", "on the river"]

    private var seats: [PokerSeat] = []
    private var board: [Int] = [], deck: [Int] = []
    private var button = 3, street = 0, small = 10, big = 20, toMatch = 0, minRaise = 20
    /// Whose move it is; nil when the betting round is over.
    private var actor: Int?
    private(set) var hand = 0
    private(set) var over = false
    private var seed: UInt64 = 1
    /// Actions so far this hand: what each computer player's dice are seeded by.
    private var acts = 0
    /// The hand is finished and the next one not yet dealt.
    private var done = true
    private var revealed = false
    /// Each player's likely hands, as a weight for each of the 1326 two-card hands.
    private var ranges: [[Double]] = []
    /// How strong each two-card hand is on this board, as the computer players see it.
    private var scores: [Double] = []
    /// What each player has done this hand, in words.
    private var history: [[String]] = []
    private var lastResult = ""
    private var moves: [PokerMove] = []
    private var cache: (key: Int, reading: PokerReading)?
    /// The showdown, for the picture.
    private var won = [0, 0, 0, 0], best: [Int] = [], verdict = "", made: [String] = ["", "", "", ""]
    /// For the picture: the table at the last decision, and everything that happened after it.
    fileprivate var opening = PokerView()
    fileprivate var script: [PokerStep] = []
    private(set) var ticked = Date.distantPast

    init() { reset(seed: 1) }

    // MARK: The game, as the arcade sees it

    var score: Int { seats.isEmpty ? Self.start : seats[0].stack + (done ? 0 : seats[0].put) }

    var status: String {
        guard !seats.isEmpty else { return "" }
        var line = over ? "打完 \(hand) 手 · 你的筹码 \(seats[0].stack)"
            : "第 \(hand)/\(Self.hands) 手 · 盲注 \(small)/\(big) · 你的筹码 \(seats[0].stack) · 底池 \(pot)"
        line += " · " + (1..<4).map { "\(Self.names[$0]) \(seats[$0].stack)" }.joined(separator: " ")
        if !lastResult.isEmpty { line += " · 上一手：\(lastResult)" }
        return line
    }

    var grid: [[JevCell]] {
        func cell(_ card: Int?) -> JevCell {
            guard let card else { return JevCell(colour: Color(red: 0.08, green: 0.36, blue: 0.22)) }
            return JevCell(colour: .white, text: PokerRules.face(card), ink: PokerRules.suit(card) < 2 ? Color(red: 0.78, green: 0.08, blue: 0.08) : .black)
        }
        let mine = seats.first?.cards ?? []
        return [(0..<5).map { cell($0 < board.count ? board[$0] : nil) }, (0..<5).map { $0 < mine.count ? cell(mine[$0]) : cell(nil) }]
    }

    let controls = "F 弃牌 · C 过牌或跟注 · R 最小加注 · A 全下（或者点右边的选项）"
    let letters: Set<Character> = ["f", "c", "r", "a"]

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        guard case .letter(let letter)? = pressed.last else { return .nothing }
        let wanted: Int?
        switch letter {
        case "f": wanted = moves.firstIndex(of: .fold)
        case "c": wanted = moves.firstIndex { if case .call = $0 { return true }; return $0 == .check }
        case "r": wanted = moves.firstIndex { if case .raise = $0 { return true }; return false }
        case "a": wanted = moves.firstIndex { if case .raise(let to) = $0 { return to == seats[0].stack + seats[0].bet }; return false }
            ?? moves.firstIndex { if case .call(let x) = $0 { return x == seats[0].stack }; return false }
        default: return .nothing
        }
        guard let index = wanted, let option = options.first(where: { $0.move == index }) else {
            switch letter {
            case "f": return .explain("现在可以免费过牌，不用弃牌")
            case "r", "a": return .explain("现在不能加注")
            default: return .nothing
            }
        }
        return .choose(option)
    }

    func reset(seed: UInt64) {
        self.seed = seed
        seats = (0..<4).map { _ in PokerSeat(stack: Self.start) }
        hand = 0; over = false; button = 3; lastResult = ""; board = []; done = true; cache = nil; moves = []
        script = []
        advance()
        opening = view()
        script = []
        ticked = .distantPast
    }

    func options() -> [JevOption] {
        advance()
        guard !over, actor == 0 else { return [] }
        let reading = read()
        return moves.enumerated().map { index, move in
            JevOption(id: String(format: "p%02d", index + 1), label: words(move, index, reading), merit: reading.merit[index],
                      move: index, title: title(move))
        }
    }

    func play(_ option: JevOption) {
        guard !over, actor == 0, moves.indices.contains(option.move) else { return }
        opening = view()
        script = []
        apply(0, moves[option.move])
        advance()
        ticked = Date()
    }

    // MARK: Dealing and betting

    private var pot: Int { seats.reduce(0) { $0 + $1.put } }
    private func live(_ i: Int) -> Bool { !seats[i].out && !seats[i].folded }
    private var liveCount: Int { (0..<4).filter(live).count }

    /// A die for one purpose in one hand: the same seed deals the same cards to every player.
    private func dice(_ a: Int, _ b: Int, _ c: Int) -> JevDice {
        var d = JevDice(seed: seed &* 0x100000001B3 ^ UInt64(a) &* 0x9E3779B97F4A7C15 ^ UInt64(b) &* 0xC2B2AE3D27D4EB4F ^ UInt64(c) &* 0x165667B19E3779F9)
        _ = d.next()
        return d
    }

    /// The computer players act until it is your move, or the game is over.
    private func advance() {
        while !over {
            if done { startHand(); continue }
            guard let seat = actor else { endRound(); continue }
            if seat == 0 { return }
            botAct(seat)
        }
    }

    private func next(after i: Int, _ wanted: (Int) -> Bool) -> Int? {
        for step in 1...4 { let j = (i + step) % 4; if wanted(j) { return j } }
        return nil
    }

    private func startHand() {
        let bots = (1..<4).filter { seats[$0].stack > 0 }
        guard hand < Self.hands, seats[0].stack > 0, !bots.isEmpty else {
            over = true; done = true; actor = nil
            record(.end)
            return
        }
        hand += 1
        (small, big) = Self.levels[min((hand - 1) / 20, Self.levels.count - 1)]
        button = next(after: button) { self.seats[$0].stack > 0 }!
        var d = dice(hand, 0, 0)
        deck = Array(0..<52)
        for i in stride(from: 51, to: 0, by: -1) { deck.swapAt(i, d.below(i + 1)) }
        board = []; street = 0; acts = 0; revealed = false; done = false
        won = [0, 0, 0, 0]; best = []; verdict = ""; made = ["", "", "", ""]
        history = [[], [], [], []]
        for i in 0..<4 {
            seats[i] = PokerSeat(stack: seats[i].stack)
            seats[i].out = seats[i].stack == 0
            seats[i].folded = seats[i].out
        }
        for _ in 0..<2 {
            var j = button
            for _ in 0..<4 { j = (j + 1) % 4; if !seats[j].out { seats[j].cards.append(deck.removeLast()) } }
        }
        ranges = Array(repeating: Array(repeating: 1, count: PokerRules.pairs.count), count: 4)
        scores = []
        // Two players: the button posts the small blind and acts first before the flop.
        let players = (0..<4).filter { !seats[$0].out }.count
        let sb = players == 2 ? button : next(after: button) { !self.seats[$0].out }!
        let bb = next(after: sb) { !self.seats[$0].out }!
        post(sb, small, "小盲"); post(bb, big, "大盲")
        toMatch = big; minRaise = big
        actor = next(after: bb, needsToAct)
        record(.deal)
    }

    private func post(_ i: Int, _ amount: Int, _ name: String) {
        let paid = min(amount, seats[i].stack)
        seats[i].stack -= paid; seats[i].bet = paid; seats[i].put = paid
        seats[i].allIn = seats[i].stack == 0
        seats[i].label = "\(name) \(paid)"
        history[i].append("posted the \(name == "小盲" ? "small" : "big") blind of \(paid)")
    }

    /// Whether a player still has something to do in this betting round.
    private func needsToAct(_ i: Int) -> Bool {
        let s = seats[i]
        guard live(i), !s.allIn, liveCount > 1 else { return false }
        if s.bet < toMatch { return true }
        return !s.acted && (0..<4).contains { $0 != i && live($0) && !seats[$0].allIn }
    }

    private func canRaise(_ i: Int) -> Bool {
        let s = seats[i]
        guard live(i), !s.allIn, s.mayRaise, s.stack > max(0, toMatch - s.bet) else { return false }
        return (0..<4).contains { $0 != i && live($0) && !seats[$0].allIn }
    }

    private func apply(_ i: Int, _ move: PokerMove) {
        acts += 1
        var s = seats[i]
        let before = toMatch
        switch move {
        case .fold:
            s.folded = true; s.label = "弃牌"
        case .check:
            s.label = "过牌"
            history[i].append("checked \(Self.streets[street])")
        case .call(let wanted):
            let paid = min(wanted, s.stack)
            s.stack -= paid; s.bet += paid; s.put += paid
            s.allIn = s.stack == 0
            s.label = s.allIn ? "全下 \(s.bet)" : "跟注 \(paid)"
            history[i].append(s.allIn ? "called all-in for \(paid) \(Self.streets[street])" : "called \(paid) \(Self.streets[street])")
        case .raise(let to):
            let paid = min(to - s.bet, s.stack)
            let level = s.bet + paid
            if level - toMatch >= minRaise {
                minRaise = level - toMatch
                for j in 0..<4 where j != i { seats[j].mayRaise = true }
            }
            for j in 0..<4 where j != i && live(j) && !seats[j].allIn { seats[j].acted = false }
            toMatch = max(toMatch, level)
            s.stack -= paid; s.bet = level; s.put += paid
            s.allIn = s.stack == 0
            s.label = s.allIn ? "全下 \(level)" : before == 0 ? "下注 \(level)" : "加注到 \(level)"
            history[i].append(s.allIn ? "went all-in for \(level) \(Self.streets[street])"
                              : before == 0 ? "bet \(level) \(Self.streets[street])" : "raised to \(level) \(Self.streets[street])")
        }
        s.acted = true; s.mayRaise = false
        seats[i] = s
        record(.act, seat: i)
        actor = next(after: i, needsToAct)
    }

    /// The end of a betting round: what nobody matched goes back, the bets go into the pot, and the next card comes — or the hand ends.
    private func endRound() {
        let bets = (0..<4).map { seats[$0].bet }.sorted(by: >)
        if let top = (0..<4).first(where: { seats[$0].bet == bets[0] }), bets[0] > bets[1] {
            let back = bets[0] - bets[1]
            seats[top].stack += back; seats[top].bet -= back; seats[top].put -= back
            if seats[top].stack > 0 { seats[top].allIn = false }
        }
        for i in 0..<4 { seats[i].bet = 0 }
        if bets[0] > 0 { record(.collect) }
        let players = (0..<4).filter(live)
        if players.count == 1 { award(to: players[0]); return }
        if street == 3 { showdown(); return }
        // Nobody left to bet against: the cards are turned up and the rest is dealt.
        if players.filter({ !seats[$0].allIn }).count <= 1, !revealed {
            revealed = true
            record(.reveal)
        }
        street += 1
        _ = deck.removeLast()
        for _ in 0..<(street == 1 ? 3 : 1) { board.append(deck.removeLast()) }
        scores = PokerRules.strength(board: board)
        toMatch = 0; minRaise = big
        for i in 0..<4 {
            seats[i].acted = false; seats[i].mayRaise = true
            if live(i), !seats[i].allIn { seats[i].label = "" }
        }
        record(.deal)
        actor = next(after: button, needsToAct)
    }

    private func award(to winner: Int) {
        won[winner] = pot
        seats[winner].stack += pot
        verdict = "\(Self.names[winner]) 赢 \(won[winner])（其他人都弃牌了）"
        finish()
    }

    /// Every pot and side pot to the best hand among those who put in enough for it; a tie splits it, odd chips first to the left of the button.
    private func showdown() {
        let players = (0..<4).filter(live)
        if !revealed { revealed = true; record(.reveal) }
        var value = [Int](repeating: -1, count: 4)
        for i in players { value[i] = PokerRules.value(PokerRules.mask(seats[i].cards + board)); made[i] = PokerRules.name(value[i]) }
        won = PokerRules.split(put: seats.map(\.put), value: value, button: button)
        for i in 0..<4 { seats[i].stack += won[i] }
        let takers = (0..<4).filter { won[$0] > 0 }.sorted { won[$0] > won[$1] }
        guard let top = takers.first else { finish(); return }
        best = PokerRules.bestFive(seats[top].cards + board)
        let name = PokerRules.name(value[top])
        let tied = takers.filter { value[$0] == value[top] }
        if tied.count > 1, takers.count == tied.count {
            verdict = tied.map { Self.names[$0] }.joined(separator: " 和 ") + " 平分 \(tied.reduce(0) { $0 + won[$1] }) · \(name)"
        } else {
            verdict = takers.map { "\(Self.names[$0]) 赢 \(won[$0])" }.joined(separator: " · ") + " · \(name)"
        }
        finish()
    }

    private func finish() {
        for i in 0..<4 { seats[i].bet = 0 }
        done = true; actor = nil
        lastResult = verdict
        record(.award)
    }

    // MARK: The computer players

    private func spot(for i: Int) -> PokerSpot {
        let s = seats[i]
        return PokerSpot(style: i - 1, preflop: street == 0, raised: street == 0 && toMatch > big, need: min(max(toMatch - s.bet, 0), s.stack),
                         pot: pot, stack: s.stack, opponents: liveCount - 1, canRaise: canRaise(i))
    }

    private func botAct(_ i: Int) {
        let s = seats[i]
        let owe = toMatch - s.bet
        let here = spot(for: i)
        let hole = PokerRules.pair(s.cards[0], s.cards[1])
        let lean = PokerStyle.lean(here, street == 0 ? PokerRules.preScore[hole] : scores[hole])
        var d = dice(hand, acts + 1, i)
        let u = Double(d.next() >> 11) * 0x1p-53
        let move: PokerMove
        if u < lean.raise, here.canRaise { move = .raise(size(for: i)) }
        else if u < lean.raise + lean.call || owe <= 0 { move = owe > 0 ? .call(min(owe, s.stack)) : .check }
        else { move = .fold }
        narrow(i, move, here)
        apply(i, move)
    }

    /// What each style bets: the rock two thirds of the pot, the station half, the maniac nearly all of it.
    private func size(for i: Int) -> Int {
        let s = seats[i], style = i - 1
        let most = s.stack + s.bet, least = min(toMatch + minRaise, most)
        var to: Int
        if street == 0 {
            let limpers = (0..<4).filter { $0 != i && live($0) && seats[$0].bet == big && toMatch == big }.count
            to = toMatch <= big ? [3, 3, 4][style] * big + max(0, limpers - 1) * big : Int(Double(toMatch) * [3, 2.5, 3.5][style])
        } else if toMatch == 0 {
            to = Int(Double(pot) * [0.66, 0.5, 0.9][style])
        } else {
            to = style == 1 ? least : Int(Double(toMatch) * 3)
        }
        to = max(least, (to + 2) / 5 * 5)
        if to >= most * 3 / 4 || s.stack <= 12 * big { to = most }
        return min(to, most)
    }

    /// What a player's action says about their cards: every hand they could hold is weighted by how likely they were to do this with it.
    private func narrow(_ i: Int, _ move: PokerMove, _ here: PokerSpot) {
        if move == .fold { return }
        let raising: Bool
        if case .raise = move { raising = true } else { raising = false }
        let table = street == 0 ? PokerRules.preScore : scores
        for k in 0..<table.count {
            let lean = PokerStyle.lean(here, table[k])
            ranges[i][k] *= max(raising ? lean.raise : lean.call, 0.003)
        }
    }

    // MARK: Your options

    private func legal() -> [PokerMove] {
        let me = seats[0]
        let owe = toMatch - me.bet
        let out: [PokerMove] = owe > 0 ? [.fold, .call(min(owe, me.stack))] : [.check]
        guard canRaise(0) else { return out }
        let most = me.stack + me.bet, least = min(toMatch + minRaise, most)
        let after = pot + min(max(owe, 0), me.stack)
        // Half the pot, the pot, all-in and the smallest raise, in that order of preference; a raise that would leave next
        // to nothing behind is all-in, and sizes that nearly coincide are one option.
        var kept: [Int] = []
        for size in [(toMatch + after / 2 + 2) / 5 * 5, (toMatch + after + 2) / 5 * 5, most, least] {
            var to = min(max(size, least), most)
            if most - to < max(big, most / 10) { to = most }
            guard to > toMatch, !kept.contains(where: { $0 == to || (to != most && $0 != most && Double(max($0, to)) < Double(min($0, to)) * 1.3) }) else { continue }
            kept.append(to)
        }
        return out + kept.sorted().map { .raise($0) }
    }

    private func title(_ move: PokerMove) -> String {
        let me = seats[0]
        switch move {
        case .fold: return "弃牌"
        case .check: return "过牌"
        case .call(let x): return x == me.stack ? "全下跟注 \(x)" : "跟注 \(x)"
        case .raise(let to): return to == me.stack + me.bet ? "全下 \(to)" : toMatch == 0 ? "下注 \(to)" : "加注到 \(to)"
        }
    }

    /// The Monte Carlo reading of this decision: the opponents' hands drawn from their ranges, the board finished, and every option played out against how each style answers it.
    private func read() -> PokerReading {
        if actor == 0 { moves = legal() }
        let key = hand * 1000 + acts
        if let cache, cache.key == key { return cache.reading }
        let me = seats[0]
        let others = (1..<4).filter(live)
        let reading = PokerRules.reading(mine: me.cards, board: board, moves: moves, myBet: me.bet, myStack: me.stack, toMatch: toMatch,
                                         others: others.map { PokerRules.Rival(seat: $0, bet: seats[$0].bet, stack: seats[$0].stack, allIn: seats[$0].allIn, range: ranges[$0]) },
                                         pot: pot, big: big, preflop: street == 0, scores: scores, dice: dice(hand, acts, 99))
        cache = (key, reading)
        return reading
    }

    // MARK: Words

    var situation: String {
        guard !seats.isEmpty, !over, !done else { return "the game is over" }
        let me = seats[0], reading = read()
        var parts = ["hand \(hand) of \(Self.hands), blinds \(small)/\(big), \(Self.streets[min(street, 3)])"]
        parts.append("you have \(me.stack) chips behind (\(PokerWords.depth(me.stack, big: big))) and sit \(chair)")
        parts.append("your cards: \(PokerWords.cards(me.cards)); " + PokerWords.hand(me.cards, board))
        if !board.isEmpty {
            parts.append("the board: \(PokerWords.cards(board)) (\(PokerWords.texture(board)))")
            let draw = PokerWords.draw(me.cards, board)
            if !draw.isEmpty { parts.append("you also have " + draw) }
        }
        let owe = toMatch - me.bet
        parts.append("the pot is \(pot)" + (owe > 0 ? " and it costs \(min(owe, me.stack)) to call" : " and there is nothing to call"))
        if !history[0].isEmpty { parts.append("so far you " + history[0].joined(separator: ", ")) }
        for i in 1..<4 where live(i) {
            let s = seats[i]
            var line = "\(Self.who[i]) (\(Self.manner[i]); \(s.allIn ? "all-in" : "\(s.stack) chips behind"))"
            line += history[i].isEmpty ? " has not acted yet" : ": " + history[i].joined(separator: ", ")
            parts.append(line)
        }
        let behind = (1..<4).filter(needsToAct)
        if !behind.isEmpty { parts.append("still to act after you: " + behind.map { Self.who[$0] }.joined(separator: " and ")) }
        parts.append("against their likely hands you win \(PokerWords.percent(reading.equity)) at showdown")
        return parts.joined(separator: "; ")
    }

    private var chair: String {
        let players = (0..<4).filter { !seats[$0].out }
        if button == 0 { return players.count == 2 ? "on the button, in the small blind" : "on the button, last to act after the flop" }
        let sb = players.count == 2 ? button : next(after: button) { !self.seats[$0].out }!
        let bb = next(after: sb) { !self.seats[$0].out }!
        if sb == 0 { return "in the small blind" }
        if bb == 0 { return "in the big blind" }
        return "under the gun, first to act before the flop"
    }

    private func words(_ move: PokerMove, _ index: Int, _ reading: PokerReading) -> String {
        let me = seats[0]
        let against = reading.against == 1 ? "against \(Self.who[(1..<4).first(where: live) ?? 1]) alone" : "against the \(reading.against) opponents still in"
        let win = "you win \(PokerWords.percent(reading.equity)) at showdown \(against)"
        switch move {
        case .fold:
            return me.put > 0 ? "fold: give up the hand; the \(me.put) chips you have put in stay in the pot and you lose nothing more"
                : "fold: give up the hand without putting in a chip"
        case .check:
            return "check: put in nothing more and " + (street < 3 ? "see the next card if nobody bets" : "show down if the others check too") + "; " + win
        case .call(let x):
            let total = pot + x
            var line = "call \(x): pay \(x) to win a pot of \(total), which is worth it if you win more than \(Int((Double(x) * 100 / Double(total)).rounded()))% of the time; " + win
            if x == me.stack {
                line += covered ? "; it puts in all your chips, and losing ends your game" : "; it puts in all your chips, but you have more than any of them"
            } else if me.stack - x < total {
                line += "; it leaves you \(me.stack - x) behind, less than the pot: you would be committed"
            }
            let behind = (1..<4).filter(needsToAct)
            if !behind.isEmpty { line += "; " + behind.map { Self.who[$0] }.joined(separator: " and ") + " can still raise after you" }
            return line
        case .raise(let to):
            let add = to - me.bet
            let allIn = add == me.stack
            var line = allIn ? "go all-in for \(to)" : toMatch == 0 ? "bet \(to)" : "raise to \(to)"
            if add != to { line += " (\(add) more)" }
            line += allIn ? "" : ", \(PokerWords.portion(add, of: me.stack))"
            let fold = reading.foldAll[index]
            let each = reading.folds[index].enumerated().filter { $0.element >= 0 }
            if fold >= 0, each.count == 1 {
                line += ": \(Self.who[each[0].offset]) folds \(PokerWords.percent(fold)) of the time"
            } else if fold >= 0 {
                line += ": the others all fold \(PokerWords.percent(fold)) of the time"
                if each.count > 1 {
                    line += " (" + each.map { "\(Self.who[$0.offset]) folds \(PokerWords.percent($0.element))" }.joined(separator: ", ") + ")"
                }
            } else {
                line += ": somebody all-in stays in whatever happens"
            }
            line += "; when called you win \(PokerWords.percent(reading.calledWin[index])) at showdown"
            if allIn {
                line += covered ? "; losing ends your game" : "; you have more chips than any of them, so losing does not end your game"
            } else {
                let left = me.stack - add, grown = pot + add + (to - toMatch)
                if left < grown { line += "; it leaves you \(left) behind, less than the pot if called: you would be committed" }
            }
            return line
        }
    }

    /// Whether some opponent still in has as many chips as you: an all-in against them can end your game.
    private var covered: Bool {
        let mine = seats[0].stack + seats[0].bet
        return (1..<4).contains { live($0) && seats[$0].stack + seats[$0].bet >= mine }
    }

    // MARK: For the picture

    fileprivate func view() -> PokerView {
        var v = PokerView()
        v.hand = hand; v.small = small; v.big = big; v.button = button
        v.stacks = seats.map(\.stack); v.bets = seats.map(\.bet)
        v.cards = seats.map(\.cards); v.folded = seats.map { $0.folded || $0.out }; v.out = seats.map(\.out)
        v.labels = seats.map(\.label)
        v.board = board
        v.pot = done ? 0 : seats.reduce(0) { $0 + $1.put - $1.bet }
        v.shown = (0..<4).map { $0 == 0 || (revealed && live($0)) }
        v.won = won; v.best = best; v.verdict = verdict; v.made = made
        v.turn = !done && actor == 0 ? 0 : nil
        v.over = over; v.chips = seats.first?.stack ?? 0
        return v
    }

    private func record(_ kind: PokerStep.Kind, seat: Int = -1) {
        script.append(PokerStep(kind: kind, seat: seat, view: view()))
    }
}

// MARK: - Rules

/// One chair at the table.
fileprivate struct PokerSeat {
    var stack: Int
    var bet = 0, put = 0
    var cards: [Int] = []
    var folded = false, allIn = false, out = false
    var acted = false, mayRaise = true
    var label = ""
}

fileprivate enum PokerMove: Equatable {
    case fold, check, call(Int), raise(Int)
}

/// What the Monte Carlo made of a decision: the chance of winning at showdown, and for each option its worth in chips, how often everybody folds to it (−1 when somebody all-in stays in regardless), how often it wins when called, and each opponent's own fold chance (−1 for one who is not asked).
fileprivate struct PokerReading {
    var equity = 0.0
    var against = 0
    var ev: [Double] = [], foldAll: [Double] = [], calledWin: [Double] = []
    /// What each option is worth to the heuristic: the chips it can end the hand with, each valued on the curve, less what folding keeps.
    var merit: [Double] = []
    var folds: [[Double]] = []
}

/// Where a computer player stands when it decides.
fileprivate struct PokerSpot {
    var style: Int                  // 0 the rock, 1 the calling station, 2 the maniac
    var preflop: Bool, raised: Bool
    var need: Int, pot: Int, stack: Int, opponents: Int
    var canRaise: Bool
}

/// How each style plays, as chances: of folding, of calling (or checking), of raising (or betting), for a hand of a given strength.
/// The computer players play by it, and the same function is how the reader's options measure what they will do.
fileprivate enum PokerStyle {
    static func lean(_ p: PokerSpot, _ score: Double) -> (fold: Double, call: Double, raise: Double) {
        func soft(_ x: Double) -> Double { 1 / (1 + exp(-x / 0.035)) }
        var s = score
        // After the flop a hand has to beat everybody still in.
        if !p.preflop, p.opponents > 1 { s = pow(score, 1 + 0.6 * Double(p.opponents - 1)) }
        if p.need <= 0 {
            let (t, bluff): (Double, Double)
            switch (p.style, p.preflop) {
            case (0, true): (t, bluff) = (0.86, 0)
            case (0, false): (t, bluff) = (0.7, 0.08)
            case (1, true): (t, bluff) = (0.95, 0)
            case (1, false): (t, bluff) = (0.85, 0)
            case (_, true): (t, bluff) = (0.5, 0.15)
            default: (t, bluff) = (0.5, 0.45)
            }
            let v = soft(s - t)
            let raise = p.canRaise ? v + (1 - v) * bluff : 0
            return (0, 1 - raise, raise)
        }
        let commit = min(1, Double(p.need) / Double(max(p.stack, 1)))
        let odds = Double(p.need) / Double(p.pot + p.need)
        let tCall: Double, tRaise: Double, bluff: Double
        if p.preflop, !p.raised {
            switch p.style {
            case 0: (tCall, tRaise, bluff) = (2, 0.85, 0)
            case 1: (tCall, tRaise, bluff) = (0.3, 0.95, 0)
            default: (tCall, tRaise, bluff) = (0.28, 0.5, 0.12)
            }
        } else if p.preflop {
            switch p.style {
            // Facing a raise: a bigger one is called with fewer hands.
            case 0: (tCall, tRaise, bluff) = (0.82 + 0.2 * odds + 0.03 * commit, 0.965, 0)
            case 1: (tCall, tRaise, bluff) = (0.3 + 0.35 * odds + 0.25 * commit, 0.985, 0)
            default: (tCall, tRaise, bluff) = (0.3 + 0.3 * odds + 0.25 * commit, 0.75, 0.08)
            }
        } else {
            switch p.style {
            case 0: (tCall, tRaise, bluff) = (odds + 0.25 + 0.1 * commit, 0.9, 0)
            case 1: (tCall, tRaise, bluff) = (0.12 + odds * 0.5 + 0.15 * commit, 0.95, 0)
            default: (tCall, tRaise, bluff) = (odds - 0.05 + 0.15 * commit, 0.78, 0.12)
            }
        }
        var raise = 0.0
        if p.canRaise { let v = soft(s - tRaise); raise = v + (1 - v) * bluff }
        let call = (1 - raise) * soft(s - tCall)
        return (max(0, 1 - raise - call), call, raise)
    }
}

/// Cards, hands and pots. A card is 0…51: its rank (0 a two … 12 an ace) is `card % 13`, its suit (♥ ♦ ♠ ♣) `card / 13`.
fileprivate enum PokerRules {
    static func rank(_ c: Int) -> Int { c % 13 }
    static func suit(_ c: Int) -> Int { c / 13 }
    /// Each card as a bit: sixteen bits a suit, so that a suit's ranks are one shift away.
    static let bit: [UInt64] = (0..<52).map { c -> UInt64 in let shift = (c / 13) * 16 + c % 13; return UInt64(1) << UInt64(shift) }
    static func mask(_ cards: [Int]) -> UInt64 { cards.reduce(0) { $0 | bit[$1] } }
    static func face(_ c: Int) -> String {
        ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"][rank(c)] + ["♥", "♦", "♠", "♣"][suit(c)]
    }

    /// Every two-card hand, in a fixed order.
    static let pairs: [(a: Int, b: Int)] = {
        var out: [(a: Int, b: Int)] = []
        for a in 0..<52 { for b in (a + 1)..<52 { out.append((a, b)) } }
        return out
    }()
    static let pairMask: [UInt64] = pairs.map { bit[$0.a] | bit[$0.b] }
    static func pair(_ x: Int, _ y: Int) -> Int { let a = min(x, y), b = max(x, y); return a * 51 - a * (a - 1) / 2 + (b - a - 1) }

    // MARK: The value of a hand

    static func top(_ m: Int) -> Int { Int.bitWidth - 1 - m.leadingZeroBitCount }
    /// The top card of the best straight in a set of ranks, or −1; the ace also counts low.
    static func straight(_ ranks: Int) -> Int {
        let m = (ranks << 1) | ((ranks >> 12) & 1)
        let s = m & (m >> 1) & (m >> 2) & (m >> 3) & (m >> 4)
        return s == 0 ? -1 : top(s) + 3
    }
    /// The highest `n` ranks of a set, four bits each, from `shift` down.
    static func pack(_ ranks: Int, _ n: Int, _ shift: Int) -> Int {
        var m = ranks, out = 0, at = shift
        for _ in 0..<n where m != 0 { let r = top(m); out |= r << at; m &= ~(1 << r); at -= 4 }
        return out
    }

    /// The best five cards among five to seven, as a number: higher is better, equal is a tie. The kind
    /// of hand (0 high card … 8 straight flush) is the top, then the ranks that decide between two of a kind.
    static func value(_ cards: UInt64) -> Int {
        let s0 = Int(cards & 0x1FFF), s1 = Int((cards >> 16) & 0x1FFF), s2 = Int((cards >> 32) & 0x1FFF), s3 = Int((cards >> 48) & 0x1FFF)
        let any = s0 | s1 | s2 | s3
        let two = (s0 & s1) | (s0 & s2) | (s0 & s3) | (s1 & s2) | (s1 & s3) | (s2 & s3)
        let three = (s0 & s1 & s2) | (s0 & s1 & s3) | (s0 & s2 & s3) | (s1 & s2 & s3)
        let four = s0 & s1 & s2 & s3
        var flush = 0
        if s0.nonzeroBitCount >= 5 { flush = s0 } else if s1.nonzeroBitCount >= 5 { flush = s1 }
        else if s2.nonzeroBitCount >= 5 { flush = s2 } else if s3.nonzeroBitCount >= 5 { flush = s3 }
        if flush != 0 {
            let high = straight(flush)
            if high >= 0 { return 8 << 20 | high << 16 }
        }
        if four != 0 {
            let q = top(four)
            return 7 << 20 | q << 16 | pack(any & ~(1 << q), 1, 12)
        }
        if three != 0 {
            let t = top(three), rest = two & ~(1 << t)
            if rest != 0 { return 6 << 20 | t << 16 | top(rest) << 12 }
        }
        if flush != 0 { return 5 << 20 | pack(flush, 5, 16) }
        let high = straight(any)
        if high >= 0 { return 4 << 20 | high << 16 }
        if three != 0 { let t = top(three); return 3 << 20 | t << 16 | pack(any & ~(1 << t), 2, 12) }
        if two.nonzeroBitCount >= 2 {
            let p = top(two), q = top(two & ~(1 << p))
            return 2 << 20 | p << 16 | q << 12 | pack(any & ~(1 << p) & ~(1 << q), 1, 8)
        }
        if two != 0 { let p = top(two); return 1 << 20 | p << 16 | pack(any & ~(1 << p), 3, 12) }
        return pack(any, 5, 16)
    }

    static let kinds = ["高牌", "一对", "两对", "三条", "顺子", "同花", "葫芦", "四条", "同花顺"]
    static func name(_ value: Int) -> String { value >> 20 == 8 && (value >> 16) & 15 == 12 ? "皇家同花顺" : kinds[value >> 20] }

    /// The five cards that make the hand.
    static func bestFive(_ cards: [Int]) -> [Int] {
        guard cards.count > 5 else { return cards }
        let want = value(mask(cards)), n = cards.count
        for a in 0..<n { for b in (a + 1)..<n {
            let five = cards.enumerated().filter { $0.offset != a && $0.offset != b }.map(\.element)
            if value(mask(five)) == want { return five }
        } }
        return Array(cards.prefix(5))
    }

    /// Who gets what from the pot: each layer of what was put in goes to the best hand among the players still in who put in that much.
    /// `value` is −1 for a player who folded. Odd chips go to the winners nearest the button's left.
    static func split(put: [Int], value: [Int], button: Int) -> [Int] {
        var won = [Int](repeating: 0, count: put.count)
        let levels = Set(put.filter { $0 > 0 }).sorted()
        var below = 0
        let order = (1...put.count).map { (button + $0) % put.count }
        for level in levels {
            let layer = put.reduce(0) { $0 + max(0, min($1, level) - below) }
            var eligible = order.filter { value[$0] >= 0 && put[$0] >= level }
            if eligible.isEmpty {
                // Only folded players put this much in: it goes to whoever is still in and put in most.
                let most = order.filter { value[$0] >= 0 }.map { put[$0] }.max() ?? 0
                eligible = order.filter { value[$0] >= 0 && put[$0] == most }
            }
            guard let top = eligible.map({ value[$0] }).max() else { break }
            let winners = eligible.filter { value[$0] == top }
            for (n, w) in winners.enumerated() { won[w] += layer / winners.count + (n < layer % winners.count ? 1 : 0) }
            below = level
        }
        return won
    }

    // MARK: Strength, as the computer players judge it

    /// Bill Chen's formula for two cards, a little finer: what the players' starting hands are ranked by.
    static func chen(_ x: Int, _ y: Int) -> Double {
        let hi = max(rank(x), rank(y)), lo = min(rank(x), rank(y))
        let points: [Double] = [1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 10]
        if hi == lo { return max(5, points[hi] * 2) + 0.01 * Double(hi) }
        var s = points[hi]
        if suit(x) == suit(y) { s += 2 }
        let gap = hi - lo - 1
        s -= [0, 1, 2, 4, 5][min(gap, 4)]
        if gap <= 1, hi < 10 { s += 1 }
        return s + 0.01 * Double(lo)
    }

    /// Each starting hand's place among all 1326: 0 the worst, 1 the best.
    static let preScore: [Double] = {
        let chens = pairs.map { chen($0.a, $0.b) }
        let sorted = chens.sorted()
        return chens.map { v in
            let below = lower(sorted, v), same = upper(sorted, v) - below
            return (Double(below) + Double(same) / 2) / Double(sorted.count)
        }
    }()

    static func lower(_ a: [Int], _ v: Int) -> Int { var lo = 0, hi = a.count; while lo < hi { let m = (lo + hi) / 2; if a[m] < v { lo = m + 1 } else { hi = m } }; return lo }
    static func upper(_ a: [Int], _ v: Int) -> Int { var lo = 0, hi = a.count; while lo < hi { let m = (lo + hi) / 2; if a[m] <= v { lo = m + 1 } else { hi = m } }; return lo }
    static func lower(_ a: [Double], _ v: Double) -> Int { var lo = 0, hi = a.count; while lo < hi { let m = (lo + hi) / 2; if a[m] < v { lo = m + 1 } else { hi = m } }; return lo }
    static func upper(_ a: [Double], _ v: Double) -> Int { var lo = 0, hi = a.count; while lo < hi { let m = (lo + hi) / 2; if a[m] <= v { lo = m + 1 } else { hi = m } }; return lo }

    /// Each two-card hand's strength on a board: the share of other hands it beats now, lifted by its draws.
    static func strength(board: [Int]) -> [Double] {
        let known = mask(board)
        var values = [Int](repeating: -1, count: pairs.count), all: [Int] = []
        all.reserveCapacity(pairs.count)
        for k in 0..<pairs.count where pairMask[k] & known == 0 {
            let v = value(known | pairMask[k]); values[k] = v; all.append(v)
        }
        all.sort()
        let boardRanks = board.reduce(0) { $0 | 1 << rank($1) }
        var suits = [0, 0, 0, 0]
        for c in board { suits[suit(c)] += 1 }
        var out = [Double](repeating: 0, count: pairs.count)
        for k in 0..<pairs.count where values[k] >= 0 {
            let lo = lower(all, values[k]), hi = upper(all, values[k])
            var s = (Double(lo) + Double(hi - lo) / 2) / Double(all.count)
            if board.count < 5, values[k] >> 20 < 4 {
                let (a, b) = pairs[k]
                var outs = 0
                if (suits[suit(a)] + 1 + (suit(b) == suit(a) ? 1 : 0)) == 4 || (suits[suit(b)] + 1 + (suit(b) == suit(a) ? 1 : 0)) == 4 { outs += 9 }
                let ranks = boardRanks | 1 << rank(a) | 1 << rank(b)
                var fill = 0
                for r in 0..<13 where ranks & (1 << r) == 0 && straight(ranks | 1 << r) >= 0 && straight(boardRanks | 1 << r) < 0 { fill += 1 }
                outs += min(fill, 2) * 4
                if outs > 0 { s += (1 - s) * min(0.5, Double(outs) * (board.count == 3 ? 0.04 : 0.022)) }
            }
            out[k] = s
        }
        return out
    }

    // MARK: The Monte Carlo

    struct Rival { var seat: Int, bet: Int, stack: Int, allIn: Bool, range: [Double] }

    /// How much chips are worth: less and less as they pile up, so that no single coin flip for everything looks good. A player
    /// with an edge who goes broke loses every hand still to come, and one who shoves every small edge goes broke.
    static let curve = 0.5
    static func worth(_ chips: Double) -> Double { pow(max(chips, 0), curve) }

    static func reading(mine: [Int], board: [Int], moves: [PokerMove], myBet: Int, myStack: Int, toMatch: Int, others: [Rival],
                        pot: Int, big: Int, preflop: Bool, scores: [Double], dice start: JevDice) -> PokerReading {
        var dice = start
        let n = moves.count, m = others.count
        var r = PokerReading(equity: 0, against: m, ev: Array(repeating: 0, count: n), foldAll: Array(repeating: 0, count: n),
                             calledWin: Array(repeating: 0, count: n), merit: Array(repeating: 0, count: n), folds: Array(repeating: [-1, -1, -1, -1], count: n))
        guard m > 0 else { return r }
        let myMask = mask(mine), boardMask = mask(board), known = myMask | boardMask
        // Each opponent's hands, less the cards we can see, as running totals to draw from.
        var sums: [[Double]] = [], keys: [[Int]] = []
        for rival in others {
            var s: [Double] = [], k: [Int] = []
            s.reserveCapacity(pairs.count); k.reserveCapacity(pairs.count)
            var total = 0.0
            for c in 0..<pairs.count where pairMask[c] & known == 0 && rival.range[c] > 0 { total += rival.range[c]; s.append(total); k.append(c) }
            sums.append(s); keys.append(k)
        }
        let pool = (0..<52).filter { known & bit[$0] == 0 }
        // What I put in with each move, and the bet the others then face.
        let adds = moves.map { move -> Int in
            switch move { case .fold, .check: return 0; case .call(let x): return x; case .raise(let to): return to - myBet }
        }
        let levels = moves.map { move -> Int in if case .raise(let to) = move { return to }; return toMatch }
        // For each move, the opponents who have to decide, with what it costs them.
        var asked: [[(j: Int, add: Int, spot: PokerSpot)]] = [], free = [Int](repeating: 0, count: n)
        for (index, move) in moves.enumerated() {
            var list: [(j: Int, add: Int, spot: PokerSpot)] = []
            if move != .fold {
                for (j, rival) in others.enumerated() {
                    let owe = max(0, levels[index] - rival.bet)
                    if rival.allIn || owe == 0 { free[index] |= 1 << j; continue }
                    let add = min(owe, rival.stack)
                    list.append((j, add, PokerSpot(style: rival.seat - 1, preflop: preflop, raised: preflop && levels[index] > big, need: add,
                                                   pot: pot + adds[index], stack: rival.stack, opponents: m, canRaise: add < rival.stack)))
                }
            }
            asked.append(list)
        }
        var staySum = Array(repeating: [0.0, 0.0, 0.0, 0.0], count: n)
        var calledShare = [Double](repeating: 0, count: n), calledWeight = [Double](repeating: 0, count: n)
        var hands = [Int](repeating: 0, count: m), values = [Int](repeating: 0, count: m)
        var stay = [Double](repeating: 0, count: 3)
        let samples = 600
        for _ in 0..<samples {
            var used = known
            for j in 0..<m {
                var pick = -1
                if let last = sums[j].last {
                    for _ in 0..<16 {
                        let u = Double(dice.next() >> 11) * 0x1p-53 * last
                        let c = keys[j][min(upper(sums[j], u), keys[j].count - 1)]
                        if pairMask[c] & used == 0 { pick = c; break }
                    }
                }
                if pick < 0 {
                    var a = 0, b = 0
                    repeat { a = pool[dice.below(pool.count)] } while used & bit[a] != 0
                    repeat { b = pool[dice.below(pool.count)] } while used & bit[b] != 0 || b == a
                    pick = pair(a, b)
                }
                used |= pairMask[pick]; hands[j] = pick
            }
            var full = boardMask, missing = 5 - board.count
            while missing > 0 {
                let c = pool[dice.below(pool.count)]
                if used & bit[c] == 0 { used |= bit[c]; full |= bit[c]; missing -= 1 }
            }
            let mv = value(full | myMask)
            for j in 0..<m { values[j] = value(full | pairMask[hands[j]]) }
            r.equity += share(mv, values, (1 << m) - 1)
            for index in 0..<n where moves[index] != .fold {
                let deciding = asked[index]
                for (d, x) in deciding.enumerated() {
                    let lean = PokerStyle.lean(x.spot, preflop ? preScore[hands[x.j]] : scores[hands[x.j]])
                    stay[d] = lean.call + lean.raise
                    staySum[index][others[x.j].seat] += stay[d]
                }
                var ev = 0.0, allFold = 0.0, utility = 0.0
                for subset in 0..<(1 << deciding.count) {
                    var p = 1.0, inHand = free[index], extra = 0, reach = 0
                    for (d, x) in deciding.enumerated() {
                        if subset & (1 << d) != 0 { p *= stay[d]; inHand |= 1 << x.j; extra += x.add; reach = max(reach, others[x.j].bet + x.add) }
                        else { p *= 1 - stay[d] }
                    }
                    if p <= 0 { continue }
                    if inHand == 0 { ev += p * Double(pot); utility += p * worth(Double(myStack + pot)); allFold += p; continue }
                    for j in 0..<m where free[index] & (1 << j) != 0 { reach = max(reach, others[j].bet) }
                    // Chips nobody can match come back.
                    let risk = min(adds[index], max(0, reach - myBet))
                    let w = share(mv, values, inHand)
                    ev += p * (w * Double(pot + risk + extra) - Double(risk))
                    utility += p * worth(Double(myStack - risk) + w * Double(pot + risk + extra))
                    calledShare[index] += p * w; calledWeight[index] += p
                }
                r.ev[index] += ev
                r.merit[index] += utility
                r.foldAll[index] += allFold
            }
        }
        let k = Double(samples)
        r.equity /= k
        let kept = worth(Double(myStack))
        for index in 0..<n {
            r.ev[index] /= k
            r.merit[index] = moves[index] == .fold ? 0 : r.merit[index] / k - kept
            r.foldAll[index] = free[index] != 0 ? -1 : r.foldAll[index] / k
            r.calledWin[index] = calledWeight[index] > 0 ? calledShare[index] / calledWeight[index] : r.equity
            for x in asked[index] { r.folds[index][others[x.j].seat] = 1 - staySum[index][others[x.j].seat] / k }
        }
        return r
    }

    /// My share of the pot against a set of opponents at a showdown: all of it, part of a tie, or nothing.
    static func share(_ mine: Int, _ values: [Int], _ set: Int) -> Double {
        var ties = 0
        for j in 0..<values.count where set & (1 << j) != 0 {
            if values[j] > mine { return 0 }
            if values[j] == mine { ties += 1 }
        }
        return 1 / Double(ties + 1)
    }
}

/// The hand, the board and the numbers, in words a reader can hold.
fileprivate enum PokerWords {
    static let ranks = ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king", "ace"]
    static let plurals = ["twos", "threes", "fours", "fives", "sixes", "sevens", "eights", "nines", "tens", "jacks", "queens", "kings", "aces"]
    static let suits = ["hearts", "diamonds", "spades", "clubs"]

    static func card(_ c: Int) -> String { "\(ranks[PokerRules.rank(c)]) of \(suits[PokerRules.suit(c)])" }
    static func cards(_ cs: [Int]) -> String { cs.map(card).joined(separator: ", ") }
    static func article(_ r: Int) -> String { r == 12 || r == 6 ? "an" : "a" }

    /// To the nearest five in a hundred.
    static func percent(_ x: Double) -> String {
        x < 0.025 ? "under 5%" : x > 0.975 ? "over 95%" : "about \(Int((x * 20).rounded()) * 5)%"
    }

    static func depth(_ chips: Int, big: Int) -> String {
        let n = chips / max(big, 1)
        return (n == 1 ? "1 big blind, " : "\(n) big blinds, ") + (n < 10 ? "very short" : n < 25 ? "short" : n < 60 ? "medium" : "deep")
    }

    static func portion(_ part: Int, of whole: Int) -> String {
        let x = Double(part) / Double(max(whole, 1))
        return x < 0.08 ? "a small part of your chips" : x < 0.18 ? "about a tenth of your chips" : x < 0.3 ? "about a quarter of your chips"
            : x < 0.42 ? "about a third of your chips" : x < 0.6 ? "about half your chips" : "most of your chips"
    }

    /// Two cards before the flop, and where they stand among all starting hands.
    static func start(_ hole: [Int]) -> String {
        let a = PokerRules.rank(hole[0]), b = PokerRules.rank(hole[1])
        let hi = max(a, b), lo = min(a, b)
        let name = a == b ? "a pair of \(plurals[a])" : "\(ranks[hi])-\(ranks[lo]) \(PokerRules.suit(hole[0]) == PokerRules.suit(hole[1]) ? "suited" : "offsuit")"
        let top = 1 - PokerRules.preScore[PokerRules.pair(hole[0], hole[1])]
        let place = top < 0.04 ? "one of the very best starting hands" : top < 0.1 ? "a strong starting hand, in the best tenth"
            : top < 0.22 ? "a good starting hand, in the best fifth" : top < 0.4 ? "a playable starting hand, better than most"
            : top < 0.6 ? "an average starting hand" : "a weak starting hand, in the worse half"
        return "\(name): \(place)"
    }

    /// What two cards make with the board, said the way a player would say it.
    static func hand(_ hole: [Int], _ board: [Int]) -> String {
        guard board.count >= 3 else { return start(hole) }
        let value = PokerRules.value(PokerRules.mask(hole + board))
        let kind = value >> 20, r1 = (value >> 16) & 15, r2 = (value >> 12) & 15
        let mine = hole.map(PokerRules.rank), shared = board.map(PokerRules.rank)
        let boardTop = shared.max() ?? 0
        if board.count == 5, PokerRules.value(PokerRules.mask(board)) == value { return "you only play the board: \(kindWords(value))" }
        switch kind {
        case 0:
            let over = mine.filter { $0 > boardTop }.count
            return "no pair, \(ranks[r1]) high" + (over == 2 ? " (two cards higher than the board)" : over == 1 && board.count < 5 ? " (one card higher than the board)" : "")
        case 1:
            let kicker = mine.filter { $0 != r1 }.max()
            if mine[0] == mine[1] {
                if r1 > boardTop { return "an overpair: a pair of \(plurals[r1]), higher than any card on the board" }
                let above = Set(shared.filter { $0 > r1 }).count
                return "a pair of \(plurals[r1]) in your hand, with \(above) higher \(above == 1 ? "card" : "cards") on the board"
            }
            if !mine.contains(r1) {
                return "only the board's pair of \(plurals[r1]); your best card is \(article(mine.max()!)) \(ranks[mine.max()!])"
            }
            let higher = Set(shared.filter { $0 > r1 }).count
            let where_ = higher == 0 ? "top pair" : higher == 1 ? "second pair" : "a low pair"
            return "a pair of \(plurals[r1])" + (kicker.map { " with \(article($0)) \(ranks[$0]) kicker" } ?? "") + " (\(where_))"
        case 2:
            let fromBoard = shared.filter { $0 == r1 }.count >= 2 || shared.filter { $0 == r2 }.count >= 2
            return "two pair, \(plurals[r1]) and \(plurals[r2])" + (fromBoard ? " (one of the pairs is on the board)" : "")
        case 3:
            if mine[0] == mine[1] { return "three \(plurals[r1]): a set, with a pair in your hand" }
            if mine.contains(r1) { return "three \(plurals[r1]): trips, with the board's pair" }
            return "three \(plurals[r1]), all on the board"
        default:
            return kindWords(value)
        }
    }

    static func kindWords(_ value: Int) -> String {
        let r1 = (value >> 16) & 15, r2 = (value >> 12) & 15
        switch value >> 20 {
        case 0: return "\(ranks[r1]) high"
        case 1: return "a pair of \(plurals[r1])"
        case 2: return "two pair, \(plurals[r1]) and \(plurals[r2])"
        case 3: return "three \(plurals[r1])"
        case 4: return "a straight, \(ranks[r1]) high"
        case 5: return "a flush, \(ranks[r1]) high"
        case 6: return "a full house, \(plurals[r1]) full of \(plurals[r2])"
        case 7: return "four \(plurals[r1])"
        default: return r1 == 12 ? "a royal flush" : "a straight flush, \(ranks[r1]) high"
        }
    }

    /// Cards to come that would make a straight or a flush.
    static func draw(_ hole: [Int], _ board: [Int]) -> String {
        guard board.count >= 3, board.count < 5 else { return "" }
        let mine = PokerRules.mask(hole + board), shared = PokerRules.mask(board)
        guard PokerRules.value(mine) >> 20 < 4 else { return "" }
        var flush = 0, straight = 0, ranks = Set<Int>()
        for c in 0..<52 where mine & PokerRules.bit[c] == 0 {
            let kind = PokerRules.value(mine | PokerRules.bit[c]) >> 20
            guard kind == 4 || kind == 5 || kind == 8 else { continue }
            if board.count == 4, PokerRules.value(shared | PokerRules.bit[c]) >> 20 >= kind { continue }
            if kind == 4 { straight += 1; ranks.insert(PokerRules.rank(c)) } else { flush += 1 }
        }
        let outs = flush + straight
        if flush > 0, straight > 0 { return "a flush draw and a straight draw: \(outs) outs" }
        if flush > 0 { return "a flush draw: \(outs) outs" }
        if ranks.count >= 2 { return "an open-ended straight draw: \(outs) outs" }
        if ranks.count == 1 { return "a gutshot straight draw: \(outs) outs" }
        return ""
    }

    /// What the board lets people make.
    static func texture(_ board: [Int]) -> String {
        var suits = [0, 0, 0, 0], counts = [Int](repeating: 0, count: 13)
        for c in board { suits[PokerRules.suit(c)] += 1; counts[PokerRules.rank(c)] += 1 }
        let most = suits.max() ?? 0
        let ranks = counts.indices.filter { counts[$0] > 0 }.reduce(0) { $0 | 1 << $1 }
        var run = 0
        for low in -1...8 {
            let window = (0..<5).map { $0 + low }.map { $0 < 0 ? 12 : $0 }
            run = max(run, window.filter { ranks & (1 << $0) != 0 }.count)
        }
        var parts: [String] = []
        parts.append(most >= 4 ? "four of one suit" : most == 3 ? "three of one suit, so a flush is possible"
                     : most == 2 && board.count < 5 ? "two of one suit" : "no flush possible")
        if counts.contains(where: { $0 >= 3 }) { parts.append("three of a kind on the board") }
        else if counts.contains(where: { $0 == 2 }) { parts.append("paired, so a full house is possible") }
        parts.append(run >= 4 ? "four cards to a straight" : run == 3 ? "a straight is possible" : "no straight possible")
        let wet = most >= 3 || run >= 3 || (most == 2 && board.count < 5 && run >= 2)
        let dry = most < 2 && run < 3 && !counts.contains(where: { $0 >= 2 })
        return (wet ? "wet: " : dry ? "dry: " : "") + parts.joined(separator: ", ")
    }
}

// MARK: - The picture

/// The table at one moment.
fileprivate struct PokerView {
    var hand = 0, small = 10, big = 20, button = 0
    var stacks = [0, 0, 0, 0], bets = [0, 0, 0, 0]
    var cards: [[Int]] = [[], [], [], []]
    var folded = [false, false, false, false], out = [false, false, false, false]
    var labels = ["", "", "", ""]
    var board: [Int] = []
    var pot = 0
    var shown = [true, false, false, false]
    var won = [0, 0, 0, 0], best: [Int] = [], verdict = "", made = ["", "", "", ""]
    var turn: Int?
    var over = false, chips = 0
}

/// One thing that happened, and the table after it.
fileprivate struct PokerStep {
    enum Kind { case deal, act, collect, reveal, award, end }
    var kind: Kind
    var seat: Int
    var view: PokerView
}

extension JevPoker: JevPainted {
    var aspect: Double { 1.3 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = PokerScene(opening: opening, steps: script, since: since)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

/// A card-room table seen from above your chair: an oval of green baize with a
/// betting line printed on it, a padded leather rail, four players' plates
/// round the edge, and real cards and chips. What the computer players did
/// since your last decision is played back step by step — each action with its
/// chips pushed out, the bets gathered into the pot, the cards dealt from the
/// deck, the hands turned up, the pot pushed to the winner — on the clock of
/// `since`, like the Blackjack table. It is drawn in a frame 640 wide and
/// scaled to the canvas; the light hangs over the middle of the table.
fileprivate struct PokerScene {
    let opening: PokerView, steps: [PokerStep], since: Double

    static let width: CGFloat = 640, height: CGFloat = 640 / 1.3
    static let gold = Color(red: 0.95, green: 0.8, blue: 0.46)
    /// The rail's centre line: a stadium round the middle of the frame.
    static let railRect = CGRect(x: 30, y: 58, width: 580, height: 356)
    static let rail: CGFloat = 26
    // Seats, clockwise from yours: 0 you at the bottom, 1 left, 2 top, 3 right.
    static let plates = [CGPoint(x: 320, y: 461), CGPoint(x: 66, y: 262), CGPoint(x: 320, y: 30), CGPoint(x: 574, y: 262)]
    static let holes = [CGPoint(x: 320, y: 398), CGPoint(x: 66, y: 204), CGPoint(x: 320, y: 84), CGPoint(x: 574, y: 204)]
    static let betSpots = [CGPoint(x: 320, y: 334), CGPoint(x: 160, y: 272), CGPoint(x: 320, y: 133), CGPoint(x: 480, y: 272)]
    static let buttonSpots = [CGPoint(x: 236, y: 352), CGPoint(x: 150, y: 322), CGPoint(x: 398, y: 112), CGPoint(x: 490, y: 322)]
    static let tagSpots = [CGPoint(x: 438, y: 461), CGPoint(x: 66, y: 302), CGPoint(x: 438, y: 30), CGPoint(x: 574, y: 302)]
    static let potSpot = CGPoint(x: 320, y: 170)
    static let deckSpot = CGPoint(x: 452, y: 168)
    static let boardY: CGFloat = 254, boardCard: CGFloat = 50
    static func boardX(_ i: Int) -> CGFloat { width / 2 + CGFloat(i - 2) * 57 }
    static let holeWidth: [CGFloat] = [60, 44, 44, 44]
    static let names = JevPoker.names
    static let styles = ["", "紧凶", "松弱", "松凶"]
    /// Each player's colour and emblem: you the spade in gold, the rock a club in slate, the station a diamond in blue, the maniac a heart in red.
    static let tints: [(Double, Double, Double)] = [(0.8, 0.6, 0.18), (0.4, 0.44, 0.5), (0.2, 0.42, 0.78), (0.8, 0.16, 0.16)]
    static let emblems = [2, 3, 1, 0]

    /// How long each thing takes to happen, in seconds.
    static func duration(_ step: PokerStep) -> Double {
        switch step.kind {
        case .deal: return step.view.board.isEmpty ? 1.05 : step.view.board.count == 3 ? 0.75 : 0.5
        case .act: return step.view.folded[step.seat] ? 0.42 : 0.5
        case .collect: return 0.42
        case .reveal: return 0.55
        case .award: return 1.9
        case .end: return 0.8
        }
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let scale = size.width / Self.width
        g.scaleBy(x: scale, y: scale)
        let w = Self.width, h = size.height / scale
        // Where the playback has got to. A long stretch of play is hurried to fit in a few seconds; the last hand of a game in two.
        let total = steps.reduce(0) { $0 + Self.duration($1) }
        let limit = steps.last?.kind == .end ? 2.3 : 7
        let hurry = total > limit ? limit / total : 1
        var clock = since, before = opening, step: PokerStep?, span = 1.0
        for s in steps {
            let d = Self.duration(s) * hurry
            if clock < d { step = s; span = d; break }
            clock -= d; before = s.view
        }
        let view = step?.view ?? before
        let kind = step?.kind, seat = step?.seat ?? -1
        let local = step == nil ? 99 : max(clock, 0) / hurry        // seconds into this step, at its own pace
        let p = step == nil ? 1 : min(max(clock / span, 0), 1)
        let newHand = kind == .deal && view.board.isEmpty && view.hand != before.hand

        if let backdrop = Self.backdrop {
            g.draw(Image(decorative: backdrop, scale: 2), in: CGRect(x: 0, y: 0, width: w, height: CGFloat(backdrop.height) / 2))
        } else {
            g.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(red: 0.05, green: 0.3, blue: 0.18)))
        }
        Self.printing(g)
        Self.deck(g)

        // The pot in the middle, and the chips on their way.
        var flying: [(from: CGPoint, to: CGPoint, amount: Int, t: Double, seed: Int)] = []
        var potAmount = view.pot
        if kind == .collect {
            potAmount = p < 0.92 ? before.pot : view.pot
            for i in 0..<4 where before.bets[i] > 0 && p < 0.92 {
                flying.append((Self.betSpots[i], Self.potSpot, before.bets[i], JevDraw.smooth(p / 0.92), view.hand * 7 + i))
            }
        } else if kind == .award {
            let push = JevDraw.smooth((local - 0.25) / 0.5)
            potAmount = push <= 0 ? before.pot : 0
            if push > 0, push < 1 {
                for i in 0..<4 where view.won[i] > 0 {
                    flying.append((Self.potSpot, Self.plates[i], view.won[i], push, view.hand * 11 + i))
                }
            }
        }
        if potAmount > 0 {
            Self.pile(g, at: Self.potSpot, amount: potAmount, radius: 13, seed: view.hand)
            Self.badge(g, "底池 \(potAmount)", at: CGPoint(x: Self.potSpot.x, y: Self.potSpot.y + 27), size: 11)
        }

        // The bets in front of each player.
        for i in 0..<4 {
            var amount = view.bets[i]
            if kind == .collect { amount = 0 }
            if kind == .act, i == seat {
                let move = JevDraw.smooth((local - 0.04) / 0.34)
                let added = view.bets[i] - before.bets[i]
                if added > 0, move < 1 {
                    amount = before.bets[i]
                    flying.append((Self.chipsFrom(i), Self.betSpots[i], added, move, view.hand * 13 + i))
                }
            }
            if newHand {
                let move = JevDraw.smooth((local - 0.72) / 0.28)
                if move < 1 {
                    amount = 0
                    if view.bets[i] > 0, move > 0 { flying.append((Self.chipsFrom(i), Self.betSpots[i], view.bets[i], move, view.hand * 17 + i)) }
                }
            }
            if amount > 0 { Self.pile(g, at: Self.betSpots[i], amount: amount, radius: 11, seed: view.hand * 5 + i) }
        }

        // The dealer's button, moving on with each hand.
        var dealer = Self.buttonSpots[view.button]
        if newHand {
            let move = JevDraw.smooth(local / 0.35)
            dealer = CGPoint(x: Self.mix(Self.buttonSpots[before.button].x, dealer.x, move), y: Self.mix(Self.buttonSpots[before.button].y, dealer.y, move))
        }
        Self.button(g, at: dealer)

        // The players' plates.
        let showdown = !view.best.isEmpty || view.won.contains { $0 > 0 }
        let paid = kind != .award || JevDraw.smooth((local - 0.25) / 0.5) >= 1
        for i in 0..<4 {
            var stack = view.stacks[i]
            if kind == .award, !paid { stack = before.stacks[i] }
            if newHand, local < 0.8 { stack += view.bets[i] }
            let acting = (kind == .act && i == seat) || (step == nil && view.turn == i)
            let winner = showdown && view.won[i] > 0 && (kind != .award || local > 0.2)
            Self.plate(g, i, stack: stack, out: view.out[i], folded: view.folded[i] && !(kind == .act && i == seat && p < 0.5),
                       acting: acting, winner: winner)
        }

        // Cards: the players', then the board, each lying where it belongs or on its way there.
        var resting: [PokerLie] = [], moving: [PokerLie] = []
        let highlight = Set(view.best)
        let lit = showdown && (kind != .award || local > 0.15) && !highlight.isEmpty
        // A new hand clears the last one away first.
        if newHand, local < 0.3 {
            let fade = 1 - JevDraw.smooth(local / 0.3)
            for i in 0..<4 where !before.folded[i] {
                for (n, card) in before.cards[i].enumerated() {
                    var lie = Self.holeLie(i, n, card: before.shown[i] ? card : nil)
                    lie.alpha = fade
                    resting.append(lie)
                }
            }
            for (n, card) in before.board.enumerated() {
                resting.append(PokerLie(at: CGPoint(x: Self.boardX(n), y: Self.boardY), angle: 0, face: card, width: Self.boardCard, alpha: fade))
            }
        }
        // The order cards are dealt in: from the button's left, one card each, then another.
        let order = (1...4).map { (view.button + $0) % 4 }.filter { !view.cards[$0].isEmpty }
        for i in 0..<4 where !view.cards[i].isEmpty {
            let foldingNow = kind == .act && i == seat && view.folded[i]
            if view.folded[i], !foldingNow { continue }
            for (n, card) in view.cards[i].enumerated() {
                let face = view.shown[i] ? card : nil
                var lie = Self.holeLie(i, n, card: face)
                if lit, view.shown[i] { if highlight.contains(card) { lie.glow = true } else { lie.dim = true } }
                if foldingNow {
                    // Thrown in towards the middle.
                    let go = JevDraw.smooth(local / 0.38)
                    lie.face = nil
                    lie.at = CGPoint(x: Self.mix(lie.at.x, Self.potSpot.x, go * 0.55), y: Self.mix(lie.at.y, Self.potSpot.y + 30, go * 0.55))
                    lie.angle += go * (n == 0 ? -0.9 : 0.7)
                    lie.alpha = 1 - go
                    moving.append(lie)
                    continue
                }
                if newHand {
                    let index = Double(n * order.count + (order.firstIndex(of: i) ?? 0))
                    let arrive = JevDraw.smooth((local - 0.22 - index * 0.07) / 0.3)
                    guard arrive > 0 else { continue }
                    if arrive < 1 {
                        lie = Self.flight(from: Self.deckSpot, to: lie, arrive: arrive, turnOver: face != nil)
                        moving.append(lie)
                        continue
                    }
                }
                if kind == .reveal, view.shown[i], !before.shown[i] {
                    lie.squeeze = CGFloat(abs(cos(p * .pi)))
                    if p < 0.5 { lie.face = nil }
                    lie.lift = CGFloat(sin(p * .pi)) * 6
                }
                resting.append(lie)
            }
        }
        for (n, card) in view.board.enumerated() {
            var lie = PokerLie(at: CGPoint(x: Self.boardX(n), y: Self.boardY), angle: 0, face: card, width: Self.boardCard)
            lie.angle = Double(JevDraw.hash(view.hand, n) % 11 - 5) * 0.004
            if lit { if highlight.contains(card) { lie.glow = true } else { lie.dim = true } }
            if kind == .deal, !newHand, n >= before.board.count {
                let arrive = JevDraw.smooth((local - Double(n - before.board.count) * 0.12) / 0.34)
                guard arrive > 0 else { continue }
                if arrive < 1 { moving.append(Self.flight(from: Self.deckSpot, to: lie, arrive: arrive, turnOver: true)); continue }
            }
            resting.append(lie)
        }
        for lie in resting { Self.card(g, lie) }
        for chips in flying {
            let at = CGPoint(x: Self.mix(chips.from.x, chips.to.x, chips.t), y: Self.mix(chips.from.y, chips.to.y, chips.t))
            var c = g
            if kind == .award { c.opacity = 1 - pow(chips.t, 6) }
            Self.pile(c, at: at, amount: chips.amount, radius: 11, seed: chips.seed, lift: CGFloat(sin(chips.t * .pi)) * 7)
        }
        for lie in moving { Self.card(g, lie) }

        // What each player just did.
        for i in 0..<4 where !view.labels[i].isEmpty && !view.out[i] {
            var pop = 1.0
            if kind == .act, i == seat { pop = JevDraw.smooth(local / 0.18) }
            if newHand { pop = JevDraw.smooth((local - 0.75) / 0.18) }
            guard pop > 0 else { continue }
            Self.tag(g, view.labels[i], at: Self.tagSpots[i], pop: pop, bright: kind == .act && i == seat)
        }
        // At a showdown, what each hand made.
        if !view.best.isEmpty, kind != .reveal {
            for i in 0..<4 where !view.made[i].isEmpty && view.shown[i] {
                let spot = Self.holes[i]
                // Over the cards, except at the top of the table, where there is room under them.
                let below = CGPoint(x: spot.x, y: i == 2 ? spot.y + Self.holeWidth[i] * 0.7 + 12 : spot.y - Self.holeWidth[i] * 0.7 - 12)
                Self.badge(g, view.made[i], at: below, size: 11, tone: view.won[i] > 0 ? .gold : .plain)
            }
        }
        if !view.verdict.isEmpty, kind == .award || step == nil {
            Self.banner(g, view.verdict, age: kind == .award ? local : 9, won: view.won[0] > 0, lost: view.won[0] == 0 && !view.folded[0])
        }
        Self.badge(g, "第 \(view.hand)/\(JevPoker.hands) 手 · 盲注 \(view.small)/\(view.big)", at: CGPoint(x: 12, y: 18), size: 11, leading: true)
        if view.over {
            var c = g
            c.opacity = kind == .end ? JevDraw.smooth(local / 0.6) : 1
            let title = view.chips == 0 ? "你出局了" : view.stacks[1...].allSatisfy({ $0 == 0 }) ? "你赢光了全桌" : "打满 \(JevPoker.hands) 手"
            JevDraw.curtain(c, CGSize(width: w, height: h), title: title, detail: "剩下 \(view.chips) 个筹码 · 打了 \(view.hand) 手")
        }
    }

    // MARK: Layout

    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    /// Where a player's chips come from when they bet: the edge of their plate nearest the middle.
    static func chipsFrom(_ i: Int) -> CGPoint {
        let p = plates[i]
        switch i {
        case 0: return CGPoint(x: p.x, y: p.y - 30)
        case 1: return CGPoint(x: p.x + 50, y: p.y)
        case 2: return CGPoint(x: p.x, y: p.y + 30)
        default: return CGPoint(x: p.x - 50, y: p.y)
        }
    }

    /// Where one of a player's two cards lies: fanned a little, yours spread to be read.
    static func holeLie(_ i: Int, _ n: Int, card: Int?) -> PokerLie {
        let width = holeWidth[i], side: CGFloat = n == 0 ? -1 : 1
        let spread = i == 0 ? width * 0.54 : width * 0.3
        let at = CGPoint(x: holes[i].x + side * spread, y: holes[i].y + (i == 0 ? 0 : abs(side) * 2))
        return PokerLie(at: at, angle: Double(side) * (i == 0 ? 0.05 : 0.1), face: card, width: width)
    }

    /// A card on its way from the deck: face down out of it, turned over on the way if it is one to be seen.
    static func flight(from: CGPoint, to rest: PokerLie, arrive: Double, turnOver: Bool) -> PokerLie {
        var lie = rest
        lie.at = CGPoint(x: mix(from.x, rest.at.x, arrive), y: mix(from.y, rest.at.y, arrive))
        lie.angle = JevDraw.mix(0.3, rest.angle, arrive)
        lie.lift = CGFloat(sin(arrive * .pi)) * 9
        lie.width = mix(boardCard * 0.8, rest.width, arrive)
        lie.glow = false; lie.dim = false
        if turnOver {
            let turn = JevDraw.smooth((arrive - 0.35) / 0.5)
            lie.squeeze = CGFloat(abs(cos(turn * .pi)))
            if turn < 0.5 { lie.face = nil }
        } else {
            lie.face = nil
        }
        return lie
    }

    // MARK: The room and the table

    /// Fibres of the baize: short strokes, light and dark, scattered the same way every frame.
    static let fibres: (light: Path, dark: Path) = {
        var light = Path(), dark = Path()
        for i in 0..<1800 {
            let x = CGFloat(JevDraw.hash(i, 1) % 6400) / 10, y = CGFloat(JevDraw.hash(i, 2) % 5000) / 10
            let a = Double(JevDraw.hash(i, 3) % 628) / 100, half = 0.6 + CGFloat(JevDraw.hash(i, 4) % 16) / 10
            let d = CGPoint(x: CGFloat(cos(a)) * half, y: CGFloat(sin(a)) * half)
            if i % 5 < 3 {
                light.move(to: CGPoint(x: x - d.x, y: y - d.y)); light.addLine(to: CGPoint(x: x + d.x, y: y + d.y))
            } else {
                dark.move(to: CGPoint(x: x - d.x, y: y - d.y)); dark.addLine(to: CGPoint(x: x + d.x, y: y + d.y))
            }
        }
        return (light, dark)
    }()

    static var railLine: Path { Path(roundedRect: railRect, cornerRadius: railRect.height / 2) }

    /// The room and the table, which never change: the floor, the table's shadow on it, the baize with its weave, its light
    /// and its betting line, and the padded rail — drawn once, at twice the frame's size, and laid under every frame.
    static let backdrop: CGImage? = {
        let scale: CGFloat = 2, w = width, h = height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let c = CGContext(data: nil, width: Int((w * scale).rounded(.up)), height: Int((h * scale).rounded(.up)), bitsPerComponent: 8,
                                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(c.height)); c.scaleBy(x: scale, y: -scale)
        func colour(_ rgb: (Double, Double, Double), _ alpha: Double = 1) -> CGColor { CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha) }
        func shade(_ rgb: (Double, Double, Double), _ k: Double) -> CGColor {
            func v(_ x: Double) -> Double { k >= 1 ? x + (1 - x) * (k - 1) : x * k }
            return colour((v(rgb.0), v(rgb.1), v(rgb.2)))
        }
        func radial(_ stops: [(CGColor, CGFloat)], at centre: CGPoint, radius: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1)) else { return }
            c.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [.drawsAfterEndLocation])
        }
        func stroke(_ path: CGPath, _ ink: CGColor, _ lineWidth: CGFloat, dy: CGFloat = 0, dash: [CGFloat] = []) {
            c.saveGState()
            c.translateBy(x: 0, y: dy)
            c.addPath(path); c.setStrokeColor(ink); c.setLineWidth(lineWidth); c.setLineDash(phase: 0, lengths: dash)
            c.strokePath()
            c.restoreGState()
        }
        let black = (0.0, 0.0, 0.0), ivory = (1.0, 1.0, 1.0), brass = (0.95, 0.8, 0.46)
        radial([(colour((0.16, 0.1, 0.08)), 0), (colour((0.04, 0.028, 0.026)), 1)], at: CGPoint(x: w / 2, y: h * 0.45), radius: w * 0.62)
        let line = railLine.cgPath
        stroke(line, colour(black, 0.22), rail + 20, dy: 11)
        stroke(line, colour(black, 0.32), rail + 6, dy: 5)
        c.saveGState()
        c.addPath(line); c.clip()
        radial([(colour((0.12, 0.53, 0.32)), 0), (colour((0.06, 0.4, 0.23)), 0.5), (colour((0.02, 0.24, 0.13)), 1)], at: CGPoint(x: w / 2, y: 236), radius: w * 0.56)
        stroke(fibres.light.cgPath, colour((0.6, 0.95, 0.7), 0.08), 0.6)
        stroke(fibres.dark.cgPath, colour(black, 0.12), 0.7)
        radial([(colour(ivory, 0.08), 0), (colour(ivory, 0), 1)], at: CGPoint(x: w / 2, y: 200), radius: w * 0.4)
        // The betting line, and the rail's shade on the felt.
        let inner = railRect.insetBy(dx: 78, dy: 62)
        stroke(Path(roundedRect: inner, cornerRadius: inner.height / 2).cgPath, colour(brass, 0.32), 1.4)
        stroke(Path(roundedRect: inner.insetBy(dx: 5, dy: 5), cornerRadius: inner.height / 2 - 5).cgPath, colour(brass, 0.14), 0.8)
        for (spread, alpha) in [(28.0, 0.07), (16.0, 0.11), (7.0, 0.18)] as [(CGFloat, Double)] { stroke(line, colour(black, alpha), rail + spread) }
        c.restoreGState()
        // A padded leather roll: dark at its edges, catching the light along its crown, stitched down both sides.
        stroke(line, colour((0.05, 0.025, 0.015)), rail + 2)
        let leather = (0.36, 0.16, 0.09)
        for step in 0..<8 {
            let f = Double(step) / 7
            stroke(line, shade(leather, 0.4 + 0.75 * sin(f * .pi / 2)), rail * CGFloat(1 - f * 0.88), dy: -CGFloat(f) * 3)
        }
        stroke(line, colour((1, 0.88, 0.74), 0.2), 1.6, dy: -4)
        stroke(line.copy(strokingWithWidth: rail - 7, lineCap: .butt, lineJoin: .miter, miterLimit: 10), colour((0.92, 0.74, 0.52), 0.42), 0.8, dash: [3.2, 2.4])
        return c.makeImage()
    }()

    /// The house's words, and the outlines where the five shared cards go.
    static func printing(_ g: GraphicsContext) {
        let label = g.resolve(Text("NO LIMIT TEXAS HOLD'EM").font(.system(size: 10.5, weight: .heavy, design: .serif)).tracking(2.4)
            .foregroundColor(gold.opacity(0.5)))
        g.draw(label, at: CGPoint(x: width / 2, y: boardY + 49))
        let cardHeight = boardCard * 1.4
        for i in 0..<5 {
            let r = CGRect(x: boardX(i) - boardCard / 2 - 2, y: boardY - cardHeight / 2 - 2, width: boardCard + 4, height: cardHeight + 4)
            g.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(gold.opacity(0.22)), lineWidth: 1)
        }
    }

    /// The deck, squared up on the felt, that every card is dealt from.
    static func deck(_ g: GraphicsContext) {
        var d = g
        d.translateBy(x: deckSpot.x, y: deckSpot.y)
        d.rotate(by: .radians(0.3))
        let w = boardCard * 0.8, h = w * 1.4
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        d.fill(Path(roundedRect: rect.offsetBy(dx: 1.5, dy: 4).insetBy(dx: -2, dy: -2), cornerRadius: 6), with: .color(.black.opacity(0.25)))
        for layer in 0..<5 {
            let lift = CGFloat(layer) * 0.9
            d.fill(Path(roundedRect: rect.offsetBy(dx: -lift * 0.3, dy: -lift), cornerRadius: w * 0.085), with: .color(Color(white: layer % 2 == 0 ? 0.86 : 0.97)))
        }
        var top = d
        top.translateBy(x: -1.2, y: -4)
        back(top, rect, corner: w * 0.085, unit: w / 72)
    }

    /// The dealer's button: an ivory disc with DEALER round the edge.
    static func button(_ g: GraphicsContext, at p: CGPoint) {
        let r: CGFloat = 12
        g.fill(Path(ellipseIn: CGRect(x: p.x - r + 1.5, y: p.y - r + 3, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.35)))
        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r + 1.5, width: 2 * r, height: 2 * r)), with: .color(Color(white: 0.62)))
        let disc = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        g.fill(Path(ellipseIn: disc), with: .radialGradient(Gradient(colors: [Color(white: 1), Color(red: 0.9, green: 0.88, blue: 0.82)]),
                                                           center: CGPoint(x: p.x - 3, y: p.y - 4), startRadius: 0, endRadius: r * 1.3))
        g.stroke(Path(ellipseIn: disc.insetBy(dx: 2.2, dy: 2.2)), with: .color(Color(red: 0.15, green: 0.15, blue: 0.2).opacity(0.5)), lineWidth: 0.7)
        g.draw(Text("D").font(.system(size: 12, weight: .black, design: .serif)).foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18)), at: p)
    }

    // MARK: Players

    /// A player's plate on the rail: an avatar with the player's emblem, the name, the style, the chips.
    static func plate(_ g: GraphicsContext, _ i: Int, stack: Int, out: Bool, folded: Bool, acting: Bool, winner: Bool) {
        let centre = plates[i]
        let rect = CGRect(x: centre.x - 60, y: centre.y - 23, width: 120, height: 46)
        var c = g
        if out || folded { c.opacity = out ? 0.4 : 0.62 }
        let shape = Path(roundedRect: rect, cornerRadius: 12)
        if acting || winner {
            let glow = winner ? Color(red: 0.4, green: 1, blue: 0.55) : gold
            for (grow, alpha) in [(9.0, 0.1), (5.0, 0.18), (2.5, 0.3)] as [(CGFloat, Double)] {
                c.fill(Path(roundedRect: rect.insetBy(dx: -grow, dy: -grow), cornerRadius: 12 + grow), with: .color(glow.opacity(alpha)))
            }
        }
        c.fill(shape.offsetBy(dx: 0, dy: 3), with: .color(.black.opacity(0.4)))
        c.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.15, green: 0.14, blue: 0.13), Color(red: 0.03, green: 0.03, blue: 0.035)]),
                                            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        c.fill(Path(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width - 4, height: rect.height * 0.42), cornerRadius: 10),
               with: .linearGradient(Gradient(colors: [.white.opacity(0.12), .white.opacity(0.01)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.midY)))
        c.stroke(Path(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), cornerRadius: 11.5), with: .color((acting ? gold : gold.opacity(0.75))), lineWidth: acting ? 1.8 : 1.1)
        // The avatar.
        let face = CGPoint(x: rect.minX + 23, y: centre.y)
        let r: CGFloat = 16
        let disc = CGRect(x: face.x - r, y: face.y - r, width: 2 * r, height: 2 * r)
        c.fill(Path(ellipseIn: disc), with: .radialGradient(Gradient(colors: [JevDraw.shade(tints[i], 1.35), JevDraw.shade(tints[i], 0.55)]),
                                                           center: CGPoint(x: face.x - 5, y: face.y - 6), startRadius: 0, endRadius: r * 1.4))
        c.stroke(Path(ellipseIn: disc.insetBy(dx: 0.7, dy: 0.7)), with: .color(gold.opacity(0.85)), lineWidth: 1.2)
        c.fill(suit(emblems[i], at: CGPoint(x: face.x, y: face.y + 0.5), size: 17), with: .color(.white.opacity(0.92)))
        // The name, the style, the chips.
        let left = rect.minX + 46
        let name = c.resolve(Text(names[i]).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white))
        c.draw(name, at: CGPoint(x: left, y: centre.y - 9), anchor: .leading)
        if !styles[i].isEmpty {
            let nameWidth = name.measure(in: CGSize(width: 200, height: 40)).width
            c.draw(Text(styles[i]).font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.5)),
                   at: CGPoint(x: left + nameWidth + 5, y: centre.y - 8.5), anchor: .leading)
        }
        let chips = out ? "出局" : stack == 0 && !folded ? "全下" : "\(stack)"
        c.fill(Path(ellipseIn: CGRect(x: left, y: centre.y + 4.5, width: 9, height: 9)), with: .color(Color(red: 0.86, green: 0.2, blue: 0.2)))
        c.stroke(Path(ellipseIn: CGRect(x: left + 1.5, y: centre.y + 6, width: 6, height: 6)), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [1.4, 1.4]))
        c.draw(Text(chips).font(.system(size: 12.5, weight: .heavy, design: .rounded)).foregroundColor(gold), at: CGPoint(x: left + 13, y: centre.y + 9.5), anchor: .leading)
    }

    /// What a player just did, on a coloured tag that pops up by the plate.
    static func tag(_ g: GraphicsContext, _ text: String, at p: CGPoint, pop: Double, bright: Bool) {
        let colour: (Double, Double, Double)
        if text.hasPrefix("弃牌") { colour = (0.42, 0.42, 0.44) }
        else if text.hasPrefix("过牌") { colour = (0.25, 0.45, 0.62) }
        else if text.hasPrefix("跟注") { colour = (0.16, 0.56, 0.3) }
        else if text.hasPrefix("全下") { colour = (0.78, 0.12, 0.14) }
        else if text.hasPrefix("小盲") || text.hasPrefix("大盲") { colour = (0.35, 0.3, 0.5) }
        else { colour = (0.85, 0.46, 0.08) }
        var c = g
        let scale = 0.7 + 0.3 * pop + 0.08 * sin(min(pop, 1) * .pi)
        c.opacity = min(pop * 1.6, 1)
        c.translateBy(x: p.x, y: p.y)
        c.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let label = c.resolve(Text(text).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(.white))
        let m = label.measure(in: CGSize(width: 300, height: 40))
        let rect = CGRect(x: -m.width / 2 - 10, y: -11, width: m.width + 20, height: 22)
        let shape = Path(roundedRect: rect, cornerRadius: 11)
        c.fill(shape.offsetBy(dx: 0, dy: 2.5), with: .color(.black.opacity(0.35)))
        c.fill(shape, with: .linearGradient(Gradient(colors: [JevDraw.shade(colour, bright ? 1.3 : 1.12), JevDraw.shade(colour, 0.72)]),
                                            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        c.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10.5), with: .color(.white.opacity(0.35)), lineWidth: 0.9)
        c.draw(label, at: .zero)
    }

    // MARK: Cards

    /// One card as it lies (or flies) this frame.
    /// The four suits as shapes one unit tall, centred on the origin, in the game's order ♥ ♦ ♠ ♣.
    static let suits: [Path] = {
        func lobe(_ p: inout Path, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            let k = r * 0.5523
            p.move(to: CGPoint(x: cx + r, y: cy))
            p.addCurve(to: CGPoint(x: cx, y: cy + r), control1: CGPoint(x: cx + r, y: cy + k), control2: CGPoint(x: cx + k, y: cy + r))
            p.addCurve(to: CGPoint(x: cx - r, y: cy), control1: CGPoint(x: cx - k, y: cy + r), control2: CGPoint(x: cx - r, y: cy + k))
            p.addCurve(to: CGPoint(x: cx, y: cy - r), control1: CGPoint(x: cx - r, y: cy - k), control2: CGPoint(x: cx - k, y: cy - r))
            p.addCurve(to: CGPoint(x: cx + r, y: cy), control1: CGPoint(x: cx + k, y: cy - r), control2: CGPoint(x: cx + r, y: cy - k))
            p.closeSubpath()
        }
        func stem(_ p: inout Path, from top: CGFloat) {
            p.move(to: CGPoint(x: 0, y: top))
            p.addCurve(to: CGPoint(x: 0.17, y: 0.5), control1: CGPoint(x: 0.02, y: top + 0.2), control2: CGPoint(x: 0.08, y: 0.44))
            p.addLine(to: CGPoint(x: -0.17, y: 0.5))
            p.addCurve(to: CGPoint(x: 0, y: top), control1: CGPoint(x: -0.08, y: 0.44), control2: CGPoint(x: -0.02, y: top + 0.2))
            p.closeSubpath()
        }
        let heart = Path { p in
            p.move(to: CGPoint(x: 0, y: 0.5))
            p.addCurve(to: CGPoint(x: -0.47, y: -0.18), control1: CGPoint(x: -0.1, y: 0.36), control2: CGPoint(x: -0.47, y: 0.12))
            p.addCurve(to: CGPoint(x: -0.23, y: -0.5), control1: CGPoint(x: -0.47, y: -0.38), control2: CGPoint(x: -0.36, y: -0.5))
            p.addCurve(to: CGPoint(x: 0, y: -0.3), control1: CGPoint(x: -0.11, y: -0.5), control2: CGPoint(x: -0.03, y: -0.42))
            p.addCurve(to: CGPoint(x: 0.23, y: -0.5), control1: CGPoint(x: 0.03, y: -0.42), control2: CGPoint(x: 0.11, y: -0.5))
            p.addCurve(to: CGPoint(x: 0.47, y: -0.18), control1: CGPoint(x: 0.36, y: -0.5), control2: CGPoint(x: 0.47, y: -0.38))
            p.addCurve(to: CGPoint(x: 0, y: 0.5), control1: CGPoint(x: 0.47, y: 0.12), control2: CGPoint(x: 0.1, y: 0.36))
            p.closeSubpath()
        }
        let diamond = Path { p in
            p.move(to: CGPoint(x: 0, y: -0.5))
            p.addQuadCurve(to: CGPoint(x: 0.38, y: 0), control: CGPoint(x: 0.16, y: -0.22))
            p.addQuadCurve(to: CGPoint(x: 0, y: 0.5), control: CGPoint(x: 0.16, y: 0.22))
            p.addQuadCurve(to: CGPoint(x: -0.38, y: 0), control: CGPoint(x: -0.16, y: 0.22))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.5), control: CGPoint(x: -0.16, y: -0.22))
            p.closeSubpath()
        }
        var spade = Path { p in
            p.move(to: CGPoint(x: 0, y: -0.5))
            p.addCurve(to: CGPoint(x: 0.46, y: 0.08), control1: CGPoint(x: 0.1, y: -0.33), control2: CGPoint(x: 0.46, y: -0.15))
            p.addCurve(to: CGPoint(x: 0.22, y: 0.32), control1: CGPoint(x: 0.46, y: 0.24), control2: CGPoint(x: 0.34, y: 0.32))
            p.addCurve(to: CGPoint(x: 0, y: 0.18), control1: CGPoint(x: 0.12, y: 0.32), control2: CGPoint(x: 0.04, y: 0.26))
            p.addCurve(to: CGPoint(x: -0.22, y: 0.32), control1: CGPoint(x: -0.04, y: 0.26), control2: CGPoint(x: -0.12, y: 0.32))
            p.addCurve(to: CGPoint(x: -0.46, y: 0.08), control1: CGPoint(x: -0.34, y: 0.32), control2: CGPoint(x: -0.46, y: 0.24))
            p.addCurve(to: CGPoint(x: 0, y: -0.5), control1: CGPoint(x: -0.46, y: -0.15), control2: CGPoint(x: -0.1, y: -0.33))
            p.closeSubpath()
        }
        stem(&spade, from: 0.1)
        var club = Path()
        lobe(&club, 0, -0.255, 0.215)
        lobe(&club, -0.245, 0.085, 0.215)
        lobe(&club, 0.245, 0.085, 0.215)
        club.move(to: CGPoint(x: 0, y: -0.12)); club.addLine(to: CGPoint(x: 0.16, y: 0.12)); club.addLine(to: CGPoint(x: -0.16, y: 0.12)); club.closeSubpath()
        stem(&club, from: 0.05)
        return [heart, diamond, spade, club]
    }()

    /// A suit `size` tall at `p`, upside down if `turned`.
    static func suit(_ suit: Int, at p: CGPoint, size: CGFloat, turned: Bool = false) -> Path {
        let s = turned ? -size : size
        return suits[suit].applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: p.x, ty: p.y))
    }

    /// Where the pips of a 2 … 10 go: column −1 … 1, row −1 (top) … 1 (bottom).
    static let pips: [[(CGFloat, CGFloat)]] = [
        [], [],
        [(0, -1), (0, 1)],
        [(0, -1), (0, 0), (0, 1)],
        [(-1, -1), (1, -1), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (0, -0.5), (-1, 0), (1, 0), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (0, -0.5), (-1, 0), (1, 0), (0, 0.5), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (-1, -1.0 / 3), (1, -1.0 / 3), (0, 0), (-1, 1.0 / 3), (1, 1.0 / 3), (-1, 1), (1, 1)],
        [(-1, -1), (1, -1), (0, -2.0 / 3), (-1, -1.0 / 3), (1, -1.0 / 3), (-1, 1.0 / 3), (1, 1.0 / 3), (0, 2.0 / 3), (-1, 1), (1, 1)],
    ]

    /// A card lying on the table (or in the air): its shadow, then its face or its back — lit when it is part of the winning hand, dimmed when it is not.
    /// It is drawn in a frame 72 wide and scaled to its width.
    static func card(_ g: GraphicsContext, _ lie: PokerLie) {
        guard lie.alpha > 0.01 else { return }
        let w: CGFloat = 72, h = w * 1.4, corner = w * 0.085
        var c = g
        c.opacity = lie.alpha
        c.translateBy(x: lie.at.x, y: lie.at.y - (lie.glow ? 5 : 0))
        c.rotate(by: .radians(lie.angle))
        let lifted = (1 + lie.lift * 0.006) * lie.width / w
        c.scaleBy(x: max(lie.squeeze, 0.02) * lifted, y: lifted)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        // A soft shadow that falls down the table whichever way the card is turned.
        let sa = CGFloat(sin(lie.angle)), ca = CGFloat(cos(lie.angle))
        let rise = lie.lift + (lie.glow ? 5 : 0)
        for (reach, grow, alpha) in [(1.0, 2.4, 0.09), (0.6, 1.1, 0.13), (0.25, 0.2, 0.2)] as [(CGFloat, CGFloat, Double)] {
            let dx = (0.5 + rise * 0.45) * reach, dy = (2.2 + rise) * reach * 1.2
            c.fill(Path(roundedRect: rect.insetBy(dx: -grow, dy: -grow).offsetBy(dx: dx * ca + dy * sa, dy: -dx * sa + dy * ca), cornerRadius: corner + grow),
                   with: .color(.black.opacity(alpha)))
        }
        if lie.glow {
            for (grow, alpha) in [(9.0, 0.16), (5.0, 0.28), (2.2, 0.55)] as [(CGFloat, Double)] {
                c.fill(Path(roundedRect: rect.insetBy(dx: -grow, dy: -grow), cornerRadius: corner + grow), with: .color(Color(red: 1, green: 0.85, blue: 0.35).opacity(alpha)))
            }
        }
        defer {
            if lie.dim { c.fill(Path(roundedRect: rect, cornerRadius: corner), with: .color(.black.opacity(0.42))) }
        }
        guard let card = lie.face else { back(c, rect, corner: corner, unit: 1); return }
        c.fill(Path(roundedRect: rect, cornerRadius: corner),
               with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.994, blue: 0.975), Color(red: 0.95, green: 0.935, blue: 0.9)]),
                                     startPoint: CGPoint(x: 0, y: -h / 2), endPoint: CGPoint(x: 0, y: h / 2)))
        c.stroke(Path(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: corner), with: .color(Color(red: 0.36, green: 0.31, blue: 0.25).opacity(0.5)), lineWidth: 0.6)
        guard lie.squeeze > 0.25 else { return }
        let suitIndex = PokerRules.suit(card), rankIndex = PokerRules.rank(card)
        let red = suitIndex < 2
        let ink = red ? Color(red: 0.8, green: 0.07, blue: 0.11) : Color(red: 0.09, green: 0.09, blue: 0.12)
        let rank = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"][rankIndex]
        // The index in two corners, a little bigger than a casino card's so a small card still reads.
        let label = c.resolve(Text(rank).font(.system(size: w * 0.27, weight: .bold, design: .serif)).foregroundColor(ink))
        let indexX = -w * 0.385, indexY = -h / 2 + w * 0.175
        var corners = Path()
        for turned in [false, true] {
            var k = c
            if turned { k.rotate(by: .radians(.pi)) }
            k.translateBy(x: indexX, y: indexY)
            if rank == "10" { k.scaleBy(x: 0.78, y: 1) }
            k.draw(label, at: .zero)
            corners.addPath(suit(suitIndex, at: CGPoint(x: turned ? -indexX : indexX, y: turned ? h / 2 - w * 0.41 : -h / 2 + w * 0.41), size: w * 0.16, turned: turned))
        }
        c.fill(corners, with: .color(ink))
        switch rankIndex {
        case 12 where suitIndex == 2:
            // The ace of spades, as ornate as a card gets: a big spade with a line engraved in it, in a gilt ring.
            let ring = CGRect(x: -w * 0.37, y: -w * 0.44, width: w * 0.74, height: w * 0.88)
            c.stroke(Path(ellipseIn: ring), with: .color(Color(red: 0.8, green: 0.6, blue: 0.2).opacity(0.8)), lineWidth: 1)
            c.stroke(Path(ellipseIn: ring.insetBy(dx: 2.5, dy: 2.5)), with: .color(ink.opacity(0.3)), lineWidth: 0.6)
            c.fill(suit(2, at: .zero, size: w * 0.6), with: .color(ink))
            c.stroke(suit(2, at: CGPoint(x: 0, y: -w * 0.012), size: w * 0.45), with: .color(.white.opacity(0.85)), lineWidth: 0.8)
        case 12:
            c.fill(suit(suitIndex, at: .zero, size: w * 0.46), with: .color(ink))
        case 9...11:
            court(c, suitIndex, rankIndex, rank: rank, ink: ink, red: red)
        default:
            var marks = Path()
            for (column, row) in pips[rankIndex + 2] {
                marks.addPath(suit(suitIndex, at: CGPoint(x: column * w * 0.2, y: row * h * 0.31), size: w * 0.19, turned: row > 0.01))
            }
            c.fill(marks, with: .color(ink))
        }
    }

    /// The crowns of the court: the jack's cap with a plume, the queen's with pearls, the king's with three points.
    static let crowns: [(shape: Path, beads: Path)] = {
        func beads(_ spots: [(CGFloat, CGFloat)], _ r: CGFloat) -> Path {
            var p = Path()
            for (x, y) in spots { p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
            return p
        }
        let jack = Path { p in
            p.move(to: CGPoint(x: -0.44, y: 0.5)); p.addLine(to: CGPoint(x: -0.44, y: 0.08))
            p.addCurve(to: CGPoint(x: 0.44, y: 0.08), control1: CGPoint(x: -0.44, y: -0.36), control2: CGPoint(x: 0.44, y: -0.36))
            p.addLine(to: CGPoint(x: 0.44, y: 0.5)); p.closeSubpath()
            p.move(to: CGPoint(x: 0.02, y: -0.2))
            p.addQuadCurve(to: CGPoint(x: 0.56, y: -0.5), control: CGPoint(x: 0.22, y: -0.62))
            p.addQuadCurve(to: CGPoint(x: 0.02, y: -0.2), control: CGPoint(x: 0.34, y: -0.3))
            p.closeSubpath()
        }
        let queen = Path { p in
            p.move(to: CGPoint(x: -0.44, y: 0.5)); p.addLine(to: CGPoint(x: -0.5, y: -0.1))
            p.addQuadCurve(to: CGPoint(x: -0.25, y: -0.24), control: CGPoint(x: -0.36, y: 0.14))
            p.addQuadCurve(to: CGPoint(x: 0, y: -0.36), control: CGPoint(x: -0.12, y: 0.08))
            p.addQuadCurve(to: CGPoint(x: 0.25, y: -0.24), control: CGPoint(x: 0.12, y: 0.08))
            p.addQuadCurve(to: CGPoint(x: 0.5, y: -0.1), control: CGPoint(x: 0.36, y: 0.14))
            p.addLine(to: CGPoint(x: 0.44, y: 0.5)); p.closeSubpath()
        }
        let king = Path { p in
            p.move(to: CGPoint(x: -0.44, y: 0.5)); p.addLine(to: CGPoint(x: -0.5, y: -0.2)); p.addLine(to: CGPoint(x: -0.22, y: 0.06))
            p.addLine(to: CGPoint(x: 0, y: -0.38)); p.addLine(to: CGPoint(x: 0.22, y: 0.06)); p.addLine(to: CGPoint(x: 0.5, y: -0.2))
            p.addLine(to: CGPoint(x: 0.44, y: 0.5)); p.closeSubpath()
        }
        return [(jack, beads([(0.56, -0.5)], 0.07)),
                (queen, beads([(-0.5, -0.15), (-0.25, -0.3), (0, -0.43), (0.25, -0.3), (0.5, -0.15)], 0.065)),
                (king, beads([(-0.5, -0.27), (0, -0.46), (0.5, -0.27)], 0.08))]
    }()

    /// A court card's middle: a coloured frame, and in it a crown over the letter.
    static func court(_ c: GraphicsContext, _ suitIndex: Int, _ rankIndex: Int, rank: String, ink: Color, red: Bool) {
        let w: CGFloat = 72, h = w * 1.4
        let frame = CGRect(x: -w * 0.262, y: -h / 2 + w * 0.1, width: w * 0.524, height: h - w * 0.2)
        let trim = red ? Color(red: 0.76, green: 0.09, blue: 0.13) : Color(red: 0.14, green: 0.22, blue: 0.5)
        c.fill(Path(frame), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.965, blue: 0.87), Color(red: 0.97, green: 0.88, blue: 0.7)]),
                                                 startPoint: CGPoint(x: 0, y: frame.minY), endPoint: CGPoint(x: 0, y: frame.maxY)))
        var hatch = Path()
        var x = frame.minX - frame.height
        while x < frame.maxX { hatch.move(to: CGPoint(x: x, y: frame.maxY)); hatch.addLine(to: CGPoint(x: x + frame.height, y: frame.minY)); x += 3.2 }
        var inside = c
        inside.clip(to: Path(frame))
        inside.stroke(hatch, with: .color(trim.opacity(0.07)), lineWidth: 0.8)
        let crown = CGRect(x: -frame.width * 0.36, y: frame.minY + frame.height * 0.1, width: frame.width * 0.72, height: frame.width * 0.46)
        let fit = CGAffineTransform(a: crown.width, b: 0, c: 0, d: crown.height, tx: crown.midX, ty: crown.midY)
        let parts = crowns[rankIndex - 9]
        let gilt = GraphicsContext.Shading.linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), Color(red: 0.8, green: 0.55, blue: 0.12)]),
                                                         startPoint: CGPoint(x: 0, y: crown.minY), endPoint: CGPoint(x: 0, y: crown.maxY))
        let shape = parts.shape.applying(fit), beads = parts.beads.applying(fit)
        c.fill(shape, with: gilt)
        c.stroke(shape, with: .color(Color(red: 0.45, green: 0.28, blue: 0.05)), lineWidth: 0.6)
        c.fill(beads, with: rankIndex == 10 ? .color(.white) : gilt)
        c.stroke(beads, with: .color(Color(red: 0.45, green: 0.28, blue: 0.05)), lineWidth: 0.5)
        let bandTop = crown.minY + crown.height * 0.74
        c.fill(Path(CGRect(x: crown.minX + crown.width * 0.06, y: bandTop, width: crown.width * 0.88, height: crown.maxY - bandTop)), with: .color(trim))
        var gems = Path()
        for gx in [-0.25, 0, 0.25] as [CGFloat] {
            gems.addEllipse(in: CGRect(x: crown.midX + crown.width * gx - 1.4, y: (bandTop + crown.maxY) / 2 - 1.4, width: 2.8, height: 2.8))
        }
        c.fill(gems, with: .color(Color(red: 1, green: 0.88, blue: 0.5)))
        c.draw(c.resolve(Text(rank).font(.system(size: w * 0.42, weight: .heavy, design: .serif)).foregroundColor(ink)),
               at: CGPoint(x: 0, y: frame.midY + frame.height * 0.06))
        c.fill(suit(suitIndex, at: CGPoint(x: 0, y: frame.maxY - frame.height * 0.15), size: w * 0.15), with: .color(ink))
        c.stroke(Path(frame), with: .color(trim), lineWidth: 1.4)
        c.stroke(Path(frame.insetBy(dx: 2.2, dy: 2.2)), with: .color(Color(red: 0.84, green: 0.64, blue: 0.22)), lineWidth: 0.7)
    }

    /// A card's back: deep blue lattice inside a white border, with a medallion in the middle. `unit` is the card's width over 72.
    static func back(_ c: GraphicsContext, _ rect: CGRect, corner: CGFloat, unit: CGFloat) {
        let w = rect.width
        c.fill(Path(roundedRect: rect, cornerRadius: corner), with: .color(Color(red: 0.99, green: 0.98, blue: 0.955)))
        c.stroke(Path(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: corner), with: .color(Color(red: 0.36, green: 0.31, blue: 0.25).opacity(0.5)), lineWidth: 0.6 * unit)
        let inner = rect.insetBy(dx: w * 0.075, dy: w * 0.075)
        let field = Path(roundedRect: inner, cornerRadius: corner * 0.5)
        c.fill(field, with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.3, blue: 0.66), Color(red: 0.05, green: 0.12, blue: 0.36)]),
                                           startPoint: CGPoint(x: inner.minX, y: inner.minY), endPoint: CGPoint(x: inner.maxX, y: inner.maxY)))
        var lattice = c
        lattice.clip(to: field)
        let step = w * 0.1
        var lines = Path()
        var x = inner.minX - inner.height
        while x < inner.maxX + step {
            lines.move(to: CGPoint(x: x, y: inner.maxY)); lines.addLine(to: CGPoint(x: x + inner.height, y: inner.minY))
            lines.move(to: CGPoint(x: x, y: inner.minY)); lines.addLine(to: CGPoint(x: x + inner.height, y: inner.maxY))
            x += step
        }
        lattice.stroke(lines.offsetBy(dx: step / 2, dy: 0), with: .color(Color(red: 0, green: 0.03, blue: 0.2).opacity(0.45)), lineWidth: 1.3 * unit)
        lattice.stroke(lines, with: .color(Color(red: 0.84, green: 0.9, blue: 1).opacity(0.34)), lineWidth: 0.7 * unit)
        lattice.stroke(Path(roundedRect: inner.insetBy(dx: 2.2 * unit, dy: 2.2 * unit), cornerRadius: 2), with: .color(.white.opacity(0.6)), lineWidth: 0.8 * unit)
        let oval = CGRect(x: rect.midX - w * 0.17, y: rect.midY - w * 0.24, width: w * 0.34, height: w * 0.48)
        lattice.fill(Path(ellipseIn: oval), with: .color(Color(red: 0.07, green: 0.16, blue: 0.44)))
        lattice.stroke(Path(ellipseIn: oval), with: .color(.white.opacity(0.75)), lineWidth: 0.9 * unit)
        lattice.stroke(Path(ellipseIn: oval.insetBy(dx: 2.3 * unit, dy: 2.3 * unit)), with: .color(Color(red: 0.96, green: 0.8, blue: 0.45).opacity(0.75)), lineWidth: 0.6 * unit)
        lattice.fill(suit(2, at: CGPoint(x: rect.midX, y: rect.midY), size: w * 0.16), with: .color(Color(red: 1, green: 0.92, blue: 0.8).opacity(0.9)))
    }

    // MARK: Chips

    /// An amount as a small heap: a stack for each kind of chip in it, the biggest behind.
    static func pile(_ g: GraphicsContext, at centre: CGPoint, amount: Int, radius r: CGFloat, seed: Int, lift: CGFloat = 0) {
        let chips = PokerChip.worth(amount)
        var stacks: [[PokerChip]] = []
        for chip in chips {
            if let last = stacks.last, last[0].value == chip.value, last.count < 9 { stacks[stacks.count - 1].append(chip) } else { stacks.append([chip]) }
        }
        stacks = Array(stacks.prefix(5))
        // Side by side in a row, or two rows when there are many.
        let spots: [CGPoint]
        switch stacks.count {
        case 1: spots = [.zero]
        case 2: spots = [CGPoint(x: -r * 1.05, y: 0), CGPoint(x: r * 1.05, y: 0)]
        case 3: spots = [CGPoint(x: -r * 1.05, y: -r * 0.45), CGPoint(x: r * 1.05, y: -r * 0.45), CGPoint(x: 0, y: r * 0.55)]
        case 4: spots = [CGPoint(x: -r * 1.05, y: -r * 0.5), CGPoint(x: r * 1.05, y: -r * 0.5), CGPoint(x: -r * 1.05, y: r * 0.6), CGPoint(x: r * 1.05, y: r * 0.6)]
        default: spots = [CGPoint(x: -r * 2.1, y: -r * 0.3), CGPoint(x: 0, y: -r * 0.5), CGPoint(x: r * 2.1, y: -r * 0.3), CGPoint(x: -r * 1.05, y: r * 0.6), CGPoint(x: r * 1.05, y: r * 0.6)]
        }
        for (i, pile) in stacks.enumerated() {
            let at = CGPoint(x: centre.x + spots[i].x, y: centre.y + spots[i].y + CGFloat(pile.count) * r * 0.1)
            stack(g, base: at, chips: pile, radius: r, seed: seed &* 3 &+ i, lift: lift)
        }
    }

    /// A stack of chips seen a little from the side: each an edge striped with its inserts, the top one's face printed.
    static func stack(_ g: GraphicsContext, base: CGPoint, chips: [PokerChip], radius r: CGFloat, seed: Int, lift: CGFloat = 0) {
        guard !chips.isEmpty else { return }
        let tilt: CGFloat = 0.6, ry = r * tilt, thick = r * 0.2
        let floor = CGRect(x: base.x - r, y: base.y - ry, width: 2 * r, height: 2 * ry)
        g.fill(Path(ellipseIn: floor.insetBy(dx: -2, dy: -1.5).offsetBy(dx: 2 + lift * 0.4, dy: 3 + lift)), with: .color(.black.opacity(0.2)))
        g.fill(Path(ellipseIn: floor.offsetBy(dx: 1 + lift * 0.3, dy: 1.5 + lift * 0.8)), with: .color(.black.opacity(0.3)))
        let k: CGFloat = 0.5523
        for (i, chip) in chips.enumerated() {
            let cx = base.x + CGFloat(JevDraw.hash(seed, i) % 9 - 4) * 0.25
            let top = base.y - lift - CGFloat(i + 1) * thick + CGFloat(JevDraw.hash(i, seed) % 3 - 1) * 0.2
            let low = top + thick
            let edge = Path { p in
                p.move(to: CGPoint(x: cx - r, y: top))
                p.addLine(to: CGPoint(x: cx - r, y: low))
                p.addCurve(to: CGPoint(x: cx, y: low + ry), control1: CGPoint(x: cx - r, y: low + ry * k), control2: CGPoint(x: cx - r * k, y: low + ry))
                p.addCurve(to: CGPoint(x: cx + r, y: low), control1: CGPoint(x: cx + r * k, y: low + ry), control2: CGPoint(x: cx + r, y: low + ry * k))
                p.addLine(to: CGPoint(x: cx + r, y: top))
                p.closeSubpath()
            }
            g.fill(edge, with: .linearGradient(Gradient(colors: [JevDraw.shade(chip.body, 0.5), JevDraw.shade(chip.body, 0.8), JevDraw.shade(chip.body, 0.45)]),
                                              startPoint: CGPoint(x: cx - r, y: 0), endPoint: CGPoint(x: cx + r, y: 0)))
            let turn = Double(JevDraw.hash(seed &+ 7, i) % 628) / 100
            var inserts = Path()
            for s in 0..<6 {
                let a = turn + Double(s) * .pi / 3, sn = CGFloat(sin(a))
                guard sn > 0.12 else { continue }
                let x = cx + r * CGFloat(cos(a)), half = r * 0.16 * sn
                inserts.addRect(CGRect(x: x - half, y: top + ry * sn, width: 2 * half, height: thick))
            }
            g.fill(inserts, with: .color(chip.insert.opacity(0.9)))
            let faceRect = CGRect(x: cx - r, y: top - ry, width: 2 * r, height: 2 * ry)
            if i < chips.count - 1 {
                g.fill(Path(ellipseIn: faceRect), with: .color(JevDraw.shade(chip.body, 0.95)))
            } else {
                chipFace(g, centre: CGPoint(x: cx, y: top), radius: r, tilt: tilt, chip: chip, turn: turn)
            }
        }
    }

    /// The top of a chip: inserts round the rim, a printed ring, and the value on a cream inlay — laid back in perspective.
    static func chipFace(_ g: GraphicsContext, centre: CGPoint, radius r: CGFloat, tilt: CGFloat, chip: PokerChip, turn: Double) {
        var f = g
        f.translateBy(x: centre.x, y: centre.y)
        f.scaleBy(x: 1, y: tilt)
        let disc = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        f.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: [JevDraw.shade(chip.body, 1.2), JevDraw.shade(chip.body, 0.9)]),
                                                           startPoint: CGPoint(x: 0, y: -r), endPoint: CGPoint(x: 0, y: r)))
        let rim = r * 0.85, around = 2 * CGFloat.pi * rim
        f.stroke(Path(ellipseIn: CGRect(x: -rim, y: -rim, width: 2 * rim, height: 2 * rim)), with: .color(chip.insert),
                 style: StrokeStyle(lineWidth: r * 0.26, dash: [around / 12, around / 12], dashPhase: CGFloat(turn) * rim))
        let inlay = disc.insetBy(dx: r * 0.4, dy: r * 0.4)
        f.fill(Path(ellipseIn: inlay), with: .color(Color(red: 0.98, green: 0.96, blue: 0.91)))
        f.stroke(Path(ellipseIn: inlay), with: .color(JevDraw.shade(chip.body, 0.6)), lineWidth: 0.6)
        if r >= 12.5 {
            let digits = "\(chip.value)"
            f.draw(Text(digits).font(.system(size: r * (digits.count > 3 ? 0.36 : digits.count > 2 ? 0.46 : 0.62), weight: .heavy, design: .rounded)).foregroundColor(chip.ink), at: .zero)
        }
        f.stroke(Path(ellipseIn: disc.insetBy(dx: 0.3, dy: 0.3)), with: .color(.black.opacity(0.35)), lineWidth: 0.6)
    }

    // MARK: Words on the table

    enum Tone { case plain, gold }

    /// A number on a dark pill with a gold edge.
    static func badge(_ g: GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat, tone: Tone = .plain, leading: Bool = false) {
        let ink: Color = tone == .gold ? Color(red: 0.28, green: 0.16, blue: 0.02) : .white
        let label = g.resolve(Text(text).font(.system(size: size, weight: .bold, design: .rounded)).foregroundColor(ink))
        let m = label.measure(in: CGSize(width: 600, height: 200))
        let width = m.width + size * 1.5, height = size * 1.75
        let pill = CGRect(x: leading ? p.x : p.x - width / 2, y: p.y - height / 2, width: width, height: height)
        let shape = Path(roundedRect: pill, cornerRadius: height / 2)
        let colours = tone == .gold ? [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.86, green: 0.62, blue: 0.2)]
            : [Color(red: 0.13, green: 0.12, blue: 0.11).opacity(0.92), Color(red: 0.03, green: 0.03, blue: 0.03).opacity(0.92)]
        g.fill(shape.offsetBy(dx: 0, dy: 2.5), with: .color(.black.opacity(0.3)))
        g.fill(shape, with: .linearGradient(Gradient(colors: colours), startPoint: CGPoint(x: 0, y: pill.minY), endPoint: CGPoint(x: 0, y: pill.maxY)))
        g.stroke(Path(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), cornerRadius: height / 2 - 0.5), with: .color(gold.opacity(0.8)), lineWidth: 1)
        g.draw(label, at: CGPoint(x: pill.midX, y: pill.midY))
    }

    /// Who won the hand and with what, popping up over the middle of the table.
    static func banner(_ g: GraphicsContext, _ text: String, age: Double, won: Bool, lost: Bool) {
        let appear = JevDraw.smooth((age - 0.15) / 0.2)
        guard appear > 0 else { return }
        let pop = 0.84 + 0.16 * appear + 0.05 * sin(min(max(age - 0.15, 0) / 0.36, 1) * .pi)
        var b = g
        b.opacity = min(appear * 1.5, 1)
        b.translateBy(x: width / 2, y: potSpot.y - 6)
        b.scaleBy(x: CGFloat(pop), y: CGFloat(pop))
        let font = Font.system(size: 17, weight: .heavy, design: .rounded)
        let label = b.resolve(Text(text).font(font).foregroundColor(.white))
        let shadow = b.resolve(Text(text).font(font).foregroundColor(.black.opacity(0.45)))
        let m = label.measure(in: CGSize(width: 600, height: 200))
        let rect = CGRect(x: -max(110, m.width / 2 + 26), y: -21, width: 2 * max(110, m.width / 2 + 26), height: 42)
        let colours = won ? [Color(red: 0.2, green: 0.66, blue: 0.36), Color(red: 0.04, green: 0.38, blue: 0.17)]
            : lost ? [Color(red: 0.86, green: 0.22, blue: 0.19), Color(red: 0.5, green: 0.05, blue: 0.07)]
            : [Color(red: 0.3, green: 0.3, blue: 0.34), Color(red: 0.12, green: 0.12, blue: 0.15)]
        b.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 6).insetBy(dx: -3, dy: -2), cornerRadius: 15), with: .color(.black.opacity(0.18)))
        b.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3), cornerRadius: 13), with: .color(.black.opacity(0.3)))
        b.fill(Path(roundedRect: rect, cornerRadius: 13), with: .linearGradient(Gradient(colors: colours), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        b.fill(Path(roundedRect: CGRect(x: rect.minX + 3, y: rect.minY + 3, width: rect.width - 6, height: rect.height * 0.45), cornerRadius: 10),
               with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.02)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.midY)))
        b.stroke(Path(roundedRect: rect.insetBy(dx: 0.8, dy: 0.8), cornerRadius: 12), with: .color(gold), lineWidth: 1.5)
        b.draw(shadow, at: CGPoint(x: 1.1, y: 1.6))
        b.draw(label, at: .zero)
    }
}

/// A card as it lies (or flies) this frame.
fileprivate struct PokerLie {
    var at: CGPoint
    var angle: Double
    var face: Int?
    var width: CGFloat
    var squeeze: CGFloat = 1
    var lift: CGFloat = 0
    var alpha: Double = 1
    var glow = false, dim = false
}

/// A casino chip: what it is worth, its colour, the inserts round its edge, the ink of its value.
fileprivate struct PokerChip {
    let value: Int, body: (Double, Double, Double), insert: Color, ink: Color

    /// The fewest chips that make `amount`, largest at the bottom of the stack.
    static func worth(_ amount: Int) -> [PokerChip] {
        var left = amount, out: [PokerChip] = []
        for value in [1000, 500, 100, 25, 5, 1] { while left >= value { out.append(.of(value)); left -= value } }
        return out
    }

    static func of(_ value: Int) -> PokerChip {
        switch value {
        case 1: return PokerChip(value: 1, body: (0.9, 0.9, 0.87), insert: Color(red: 0.2, green: 0.35, blue: 0.7), ink: Color(white: 0.25))
        case 5: return PokerChip(value: 5, body: (0.78, 0.09, 0.11), insert: .white, ink: Color(red: 0.62, green: 0.05, blue: 0.08))
        case 25: return PokerChip(value: 25, body: (0.07, 0.5, 0.26), insert: .white, ink: Color(red: 0.04, green: 0.36, blue: 0.17))
        case 100: return PokerChip(value: 100, body: (0.14, 0.14, 0.15), insert: Color(red: 0.93, green: 0.9, blue: 0.84), ink: Color(white: 0.1))
        case 500: return PokerChip(value: 500, body: (0.45, 0.2, 0.62), insert: Color(red: 1, green: 0.9, blue: 0.5), ink: Color(red: 0.33, green: 0.12, blue: 0.48))
        default: return PokerChip(value: 1000, body: (0.93, 0.62, 0.12), insert: Color(red: 0.35, green: 0.18, blue: 0.05), ink: Color(red: 0.45, green: 0.24, blue: 0.02))
        }
    }
}
