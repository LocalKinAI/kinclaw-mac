import SwiftUI

/// Blackjack — 21 点 — as a test of judgment about risk, with a yardstick that
/// is right.
///
/// At chess the yardstick is a shallow search, and a day went into finding out
/// what a player has to be told to beat it; one game is one data point, and a
/// lucky one was taken for a result. Here every hand is its own game, two
/// hundred of them are a minute, and the yardstick is not an opinion: what each
/// action is worth is worked out exactly (an endless shoe, the dealer stands on
/// every 17), which is what "basic strategy" is. So a disagreement with it is
/// a mistake, by a known amount, and how a player did is a number of chips that
/// means something.
///
/// The division of labour is the usual one, and deliberately not complete. The
/// program says what can be measured at a glance — how often the dealer busts
/// from that card, how often one more card busts the player, how often standing
/// wins — and does NOT say what each action is worth, because a program that
/// knows that has no question left to ask. Weighing a 62% chance of busting
/// against a 77% chance of losing by standing is the judgment.
@MainActor
final class JevBlackjack: JevGame {
    let id = "blackjack", title = "21 点", symbol = "suit.spade"
    let rules = "Blackjack against the dealer, one hand at a time, ten chips a hand. Cards count their number, face cards 10, an ace 1 or 11. Going over 21 loses at once. The dealer draws to 17 and stands on every 17. A two-card 21 pays three to two. Doubling down doubles the bet for exactly one more card. There is no splitting and no surrender."
    let question = "What should the player do with this hand?"
    let howToJudge = "The dealer has to draw until 17, so the dealer's card decides how much risk is worth taking. Against a dealer's 2 to 6 the dealer busts often: with 12 to 16 that could bust, stand and let the dealer bust; with 9, 10 or 11, double down. Against a dealer's 7, 8, 9, 10 or ace the dealer usually finishes on 17 or more: standing on 12 to 16 mostly loses, so hit, even though hitting often busts. Always hit 11 or less when not doubling; never hit a hard 17 or more. A soft hand (an ace counted as 11) cannot bust with one card: hit soft 17 or less, stand on soft 19 or more, and on soft 18 stand against 2 to 8 but hit against 9, 10 or ace. Double 11 against everything but an ace, 10 against 2 to 9, 9 against 3 to 6."

    nonisolated static let hands = 200, stake = 10

    fileprivate struct Card { var rank: Int; var suit: Int }    // rank 1…13; suit ♥ ♦ ♠ ♣
    private var shoe: [Card] = []
    private var dice = JevDice(seed: 1)
    private var player: [Card] = [], dealer: [Card] = []
    private var bet = JevBlackjack.stake
    private var revealed = false
    private var actions: [String] = []
    private(set) var chips = 1000
    private(set) var dealt = 0
    private(set) var over = false
    private var lastResult = ""
    /// For the picture: the table before the last move, and the hand that move finished.
    private var previous = BlackjackTable(player: [], dealer: [], revealed: false, dealt: 0)
    private var finished: BlackjackTable?
    private(set) var ticked = Date.distantPast
    private var table: BlackjackTable { BlackjackTable(player: player, dealer: dealer, revealed: revealed, dealt: dealt, bet: bet) }
    /// What perfect play would have made of the same decisions, in chips: the
    /// sum of what the best action was worth, against what the chosen one was.
    private(set) var given = 0.0

    var score: Int { chips }
    var status: String {
        let held = Self.total(player)
        return (over ? "打完 \(dealt) 手 · 筹码 \(chips)" : "第 \(dealt) 手 · 筹码 \(chips) · 你 \(held.soft ? "软" : "")\(held.value) 对庄家 \(Self.name(dealer.first))")
            + String(format: " · 因为选错少拿 %.0f", given) + (lastResult.isEmpty ? "" : " · 上一手：\(lastResult)")
    }
    var situation: String {
        let held = Self.total(player), up = Self.points(dealer[0])
        let bust = Self.dealerFinish(up: up)[22] ?? 0
        return "the player holds \(held.soft ? "soft" : "hard") \(held.value) (\(player.map { Self.word($0) }.joined(separator: ", "))); the dealer shows \(Self.word(dealer[0])); "
            + "a dealer showing that card busts \(Self.percent(bust)) of the time and finishes on 17 or more otherwise"
    }

    var grid: [[JevCell]] {
        func cell(_ card: Card?, hidden: Bool = false) -> JevCell {
            guard let card else { return JevCell(colour: Color(red: 0.10, green: 0.36, blue: 0.22)) }
            if hidden { return JevCell(colour: Color(red: 0.55, green: 0.12, blue: 0.14), text: "?", ink: .white) }
            return JevCell(colour: .white, text: Self.face(card), ink: card.suit < 2 ? Color(red: 0.78, green: 0.08, blue: 0.08) : .black)
        }
        let width = 7
        func row(_ cards: [Card], hideSecond: Bool) -> [JevCell] {
            (0..<width).map { i in i < cards.count ? cell(cards[i], hidden: hideSecond && i == 1) : cell(nil) }
        }
        return [row(dealer, hideSecond: !revealed), (0..<width).map { _ in cell(nil) }, row(player, hideSecond: false)]
    }

    init() { reset(seed: 1) }

    let controls = "H 要牌 · S 停牌 · D 加倍（或者点右边的选项）"
    let letters: Set<Character> = ["h", "s", "d"]

    func react(_ pressed: [JevPress], held: Set<JevPress>, among options: [JevOption]) -> JevReaction {
        guard case .letter(let letter)? = pressed.last,
              let action = ["h": "hit", "s": "stand", "d": "double"][letter],
              let index = actions.firstIndex(of: action),
              let option = options.first(where: { $0.move == index }) else { return .nothing }
        return .choose(option)
    }

    func reset(seed: UInt64) {
        dice = JevDice(seed: seed); shoe = []; chips = 1000; dealt = 0; over = false; lastResult = ""; given = 0
        deal()
        previous = table; finished = nil; ticked = .distantPast
    }

    func options() -> [JevOption] {
        guard !over else { return [] }
        let held = Self.total(player), up = Self.points(dealer[0])
        let worth = Self.worth(total: held.value, soft: held.soft, up: up, canDouble: player.count == 2 && chips >= 2 * Self.stake)
        actions = worth.map(\.action)
        let finish = Self.dealerFinish(up: up)
        let bustNext = Self.bustChance(total: held.value, soft: held.soft)
        return worth.enumerated().map { index, item in
            var words: String
            switch item.action {
            case "stand":
                let win = finish.filter { $0.key == 22 || $0.key < held.value }.values.reduce(0, +), tie = finish[held.value] ?? 0
                words = "stand on \(held.soft ? "soft" : "hard") \(held.value): wins \(Self.percent(win)) of the time, ties \(Self.percent(tie)), loses the rest"
                    + (held.value <= 16 ? " — it wins only when the dealer busts" : "")
            case "hit":
                words = "hit: \(bustNext == 0 ? "cannot bust with one more card" : "busts at once \(Self.percent(bustNext)) of the time"); otherwise the hand goes on with a higher total"
            default:
                let reach = Self.reach17(total: held.value, soft: held.soft)
                words = "double down: the bet doubles and exactly one more card is drawn; that card makes 17 or more \(Self.percent(reach)) of the time"
                    + (bustNext > 0 ? " and busts \(Self.percent(bustNext))" : "")
            }
            return JevOption(id: String(format: "p%02d", index + 1), label: words, merit: item.value, move: index)
        }
    }

    func play(_ option: JevOption) {
        guard actions.indices.contains(option.move), !over else { return }
        previous = table; finished = nil
        defer { ticked = Date() }
        let held = Self.total(player), up = Self.points(dealer[0])
        let worth = Self.worth(total: held.value, soft: held.soft, up: up, canDouble: player.count == 2 && chips >= 2 * Self.stake)
        if let best = worth.map(\.value).max(), let mine = worth.first(where: { $0.action == actions[option.move] })?.value {
            given += (best - mine) * Double(Self.stake)
        }
        switch actions[option.move] {
        case "hit":
            player.append(draw())
            let now = Self.total(player).value
            if now > 21 { settle() } else if now == 21 { finishDealer(); settle() }
        case "double":
            bet = 2 * Self.stake
            player.append(draw())
            if Self.total(player).value <= 21 { finishDealer() }
            settle()
        default:
            finishDealer(); settle()
        }
    }

    // MARK: The table

    private func draw() -> Card {
        if shoe.count < 78 {                                     // six decks, shuffled again when a quarter is left
            shoe = (0..<6).flatMap { _ in (0..<4).flatMap { suit in (1...13).map { Card(rank: $0, suit: suit) } } }
            for index in stride(from: shoe.count - 1, to: 0, by: -1) { shoe.swapAt(index, dice.below(index + 1)) }
        }
        return shoe.removeLast()
    }

    /// Hands that need no decision — a natural on either side — are played out
    /// here, so that whenever anybody is asked there is something to decide.
    private func deal() {
        while true {
            guard dealt < Self.hands, chips >= Self.stake else { over = true; revealed = true; return }
            dealt += 1; bet = Self.stake; revealed = false
            player = [draw(), draw()]; dealer = [draw(), draw()]
            let mine = Self.total(player).value == 21, theirs = Self.total(dealer).value == 21
            if !mine, !theirs { return }
            revealed = true
            if mine, !theirs { chips += Self.stake * 3 / 2; lastResult = "天生 21 点，赢 \(Self.stake * 3 / 2)" }
            else if theirs, !mine { chips -= Self.stake; lastResult = "庄家天生 21 点，输 \(Self.stake)" }
            else { lastResult = "双方都是 21 点，平" }
            finished = BlackjackTable(player: player, dealer: dealer, revealed: true, dealt: dealt, bet: Self.stake, result: lastResult)
        }
    }

    private func finishDealer() {
        revealed = true
        while true {
            let now = Self.total(dealer)
            if now.value >= 17 { break }
            dealer.append(draw())
        }
    }

    private func settle() {
        revealed = true
        let mine = Self.total(player).value, theirs = Self.total(dealer).value
        if mine > 21 { chips -= bet; lastResult = "\(mine) 点爆了，输 \(bet)" }
        else if theirs > 21 { chips += bet; lastResult = "庄家 \(theirs) 点爆了，赢 \(bet)" }
        else if mine > theirs { chips += bet; lastResult = "\(mine) 对 \(theirs)，赢 \(bet)" }
        else if mine < theirs { chips -= bet; lastResult = "\(mine) 对 \(theirs)，输 \(bet)" }
        else { lastResult = "\(mine) 对 \(theirs)，平" }
        finished = BlackjackTable(player: player, dealer: dealer, revealed: true, dealt: dealt, bet: bet, result: lastResult)
        deal()
    }

    // MARK: Counting

    private static func points(_ card: Card) -> Int { card.rank == 1 ? 11 : min(card.rank, 10) }
    private static func total(_ cards: [Card]) -> (value: Int, soft: Bool) {
        var sum = cards.reduce(0) { $0 + min($1.rank, 10) }
        let soft = cards.contains { $0.rank == 1 } && sum + 10 <= 21
        if soft { sum += 10 }
        return (sum, soft)
    }
    private static func face(_ card: Card) -> String {
        ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][card.rank - 1] + ["♥", "♦", "♠", "♣"][card.suit]
    }
    private static func word(_ card: Card) -> String {
        card.rank == 1 ? "an ace" : card.rank >= 11 ? "a \(["jack", "queen", "king"][card.rank - 11])" : "a \(card.rank)"
    }
    private static func name(_ card: Card?) -> String { card.map { $0.rank == 1 ? "A" : String(min($0.rank, 10)) } ?? "?" }
    /// Small counts as numbers a reader can hold: to the nearest five in a hundred.
    private static func percent(_ chance: Double) -> String { "about \(Int((chance * 20).rounded()) * 5)%" }

    // MARK: What everything is worth — the yardstick

    /// A card's chance in an endless shoe: a tenth-value card four times in thirteen.
    nonisolated private static let chances: [(points: Int, chance: Double)] = (1...10).map { ($0 == 1 ? 11 : $0, $0 == 10 ? 4.0 / 13 : 1.0 / 13) }

    private static func add(_ total: Int, _ soft: Bool, _ card: Int) -> (Int, Bool) {
        var value = total + (card == 11 ? 1 : card), softNow = soft
        if card == 11, value + 10 <= 21 { value += 10; softNow = true }
        if value > 21, softNow { value -= 10; softNow = false }
        return (value, softNow)
    }

    private static var finishes: [Int: [Int: Double]] = [:]
    /// Where a dealer showing `up` finishes, given no natural (the hand would be over): 17…21, or 22 for bust.
    static func dealerFinish(up: Int) -> [Int: Double] {
        if let known = finishes[up] { return known }
        func run(_ total: Int, _ soft: Bool, first: Bool) -> [Int: Double] {
            if total >= 17 { return [min(total, 22): 1] }
            var out: [Int: Double] = [:]
            var cards = chances
            if first {                                           // the hole card is known not to make a natural
                cards = cards.filter { !((up == 11 && $0.points == 10) || (up == 10 && $0.points == 11)) }
                let left = cards.reduce(0) { $0 + $1.chance }
                cards = cards.map { ($0.points, $0.chance / left) }
            }
            for (card, chance) in cards {
                let (next, nextSoft) = add(total, soft, card)
                for (end, p) in run(next, nextSoft, first: false) { out[end, default: 0] += chance * p }
            }
            return out
        }
        let result = run(up == 11 ? 11 : up, up == 11, first: true)
        finishes[up] = result
        return result
    }

    private static func standWorth(_ total: Int, up: Int) -> Double {
        dealerFinish(up: up).reduce(0) { $0 + $1.value * ($1.key == 22 || $1.key < total ? 1 : $1.key == total ? 0 : -1) }
    }
    private static var hitMemo: [String: Double] = [:]
    private static func bestWorth(_ total: Int, _ soft: Bool, up: Int) -> Double {
        let key = "\(total)\(soft)\(up)"
        if let known = hitMemo[key] { return known }
        let value = max(standWorth(total, up: up), hitWorth(total, soft, up: up))
        hitMemo[key] = value
        return value
    }
    private static func hitWorth(_ total: Int, _ soft: Bool, up: Int) -> Double {
        chances.reduce(0) { sum, card in
            let (next, nextSoft) = add(total, soft, card.points)
            return sum + card.chance * (next > 21 ? -1 : bestWorth(next, nextSoft, up: up))
        }
    }
    /// Each action open to the player and what it is worth, in bets.
    static func worth(total: Int, soft: Bool, up: Int, canDouble: Bool) -> [(action: String, value: Double)] {
        var out = [("stand", standWorth(total, up: up)), ("hit", hitWorth(total, soft, up: up))]
        if canDouble {
            out.append(("double", 2 * chances.reduce(0) { sum, card in
                let (next, _) = add(total, soft, card.points)
                return sum + card.chance * (next > 21 ? -1 : standWorth(next, up: up))
            }))
        }
        return out
    }
    private static func bustChance(total: Int, soft: Bool) -> Double {
        chances.reduce(0) { $0 + (add(total, soft, $1.points).0 > 21 ? $1.chance : 0) }
    }
    private static func reach17(total: Int, soft: Bool) -> Double {
        chances.reduce(0) { let next = add(total, soft, $1.points).0; return $0 + (next >= 17 && next <= 21 ? $1.chance : 0) }
    }
}

// MARK: - The picture

/// A table at one moment: the hands, whether the dealer's second card is up, which hand of the session it is.
fileprivate struct BlackjackTable {
    var player: [JevBlackjack.Card], dealer: [JevBlackjack.Card], revealed: Bool, dealt: Int, bet = JevBlackjack.stake, result = ""
}

extension JevBlackjack: JevPainted {
    var aspect: Double { 1.3 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let scene = BlackjackScene(previous: previous, table: table, finished: finished, since: since, chips: chips, over: over)
        return JevPicture { context, size in scene.paint(&context, size) }
    }
}

/// A casino table seen from the player's chair: green baize with the house's
/// words printed on it in gold, a padded rail round the players' end, the
/// dealer's chip rack and shoe, and real cards and chips. It is drawn in a
/// frame 640 wide and scaled to the canvas. The light hangs over the table, so
/// every shadow falls a little down it.
fileprivate struct BlackjackScene {
    let previous: BlackjackTable, table: BlackjackTable, finished: BlackjackTable?, since: Double, chips: Int, over: Bool
    /// How long a finished hand stays on the table before the next is dealt.
    static let linger = 1.3

    static let width: CGFloat = 640
    static let cardWidth: CGFloat = 72, cardHeight: CGFloat = 72 * 1.4
    static let dealerRow: CGFloat = 132, playerRow: CGFloat = 338
    static let betSpot = CGPoint(x: 128, y: 344), bankSpot = CGPoint(x: 512, y: 336)
    static let shoeCentre = CGPoint(x: 534, y: 80), shoeAngle = 0.55
    static let rackCentre = CGPoint(x: 320, y: 12)
    static let rail: CGFloat = 30
    static let gold = Color(red: 0.95, green: 0.8, blue: 0.46)

    /// One card as it lies (or flies) this frame.
    struct Lie { var at: CGPoint; var angle: Double; var face: JevBlackjack.Card?; var squeeze: CGFloat; var lift: CGFloat }

    static func total(_ cards: [JevBlackjack.Card]) -> (value: Int, soft: Bool) {
        var sum = cards.reduce(0) { $0 + min($1.rank, 10) }
        let soft = cards.contains { $0.rank == 1 } && sum + 10 <= 21
        if soft { sum += 10 }
        return (sum, soft)
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let scale = size.width / Self.width
        g.scaleBy(x: scale, y: scale)
        let w = Self.width, h = size.height / scale
        Self.room(g, w: w, h: h)
        Self.rack(g)
        Self.discards(g)
        let mouth = Self.shoe(g)

        // A finished hand lingers, dealer's cards up and the verdict on it; then the next is dealt.
        let showingEnd = finished != nil && since < Self.linger
        let hand = showingEnd ? finished! : table
        let sameHand = hand.dealt == previous.dealt
        let clock = showingEnd ? since : since - (finished != nil ? Self.linger : 0)
        // Cards already down shuffle over to make room while a new one comes.
        let shift = JevDraw.smooth(min(max(clock / 0.3, 0), 1))

        var resting: [Lie] = [], flying: [Lie] = []
        for (row, cards, old, dealer) in [(Self.dealerRow, hand.dealer, previous.dealer.count, true), (Self.playerRow, hand.player, previous.player.count, false)] {
            let seed = hand.dealt * 2 + (dealer ? 1 : 0)
            for (index, face) in cards.enumerated() {
                // Dealt in the order a dealer deals: you, the dealer, you, the dealer — then one at a time.
                let order = sameHand ? Double(index - old) : Double(index * 2 + (dealer ? 1 : 0))
                let fresh = !sameHand || index >= old
                let arrive = fresh ? JevDraw.smooth(min(max((clock - order * 0.14) / 0.3, 0), 1)) : 1
                guard arrive > 0 else { continue }
                var rest = Self.place(index, cards.count, row: row, seed: seed)
                if !fresh, old < cards.count {
                    let before = Self.place(index, old, row: row, seed: seed)
                    rest.point.x = Self.mix(before.point.x, rest.point.x, shift)
                }
                let hidden = dealer && index == 1 && !hand.revealed
                // The hole card turns over when the dealer plays.
                let turning = dealer && index == 1 && hand.revealed && !previous.revealed && sameHand
                var squeeze: CGFloat = 1, shown: JevBlackjack.Card? = hidden ? nil : face
                if turning {
                    squeeze = CGFloat(abs(cos(min(max(clock, 0) / 0.3, 1) * .pi)))
                    if clock < 0.15 { shown = nil }
                } else if arrive < 1, !hidden {
                    // Out of the shoe face down, turned over on the way.
                    let turn = JevDraw.smooth((arrive - 0.35) / 0.5)
                    squeeze = CGFloat(abs(cos(turn * .pi)))
                    if turn < 0.5 { shown = nil }
                }
                let lie = Lie(at: CGPoint(x: Self.mix(mouth.x, rest.point.x, arrive), y: Self.mix(mouth.y, rest.point.y, arrive)),
                              angle: JevDraw.mix(Self.shoeAngle, rest.angle, arrive), face: shown, squeeze: squeeze,
                              lift: CGFloat(sin(arrive * .pi)) * 9)
                if arrive < 1 { flying.append(lie) } else { resting.append(lie) }
            }
        }

        // The bet in its circle, and what the dealer does with it once the hand is over.
        let age = showingEnd ? since : 0
        let result = showingEnd ? (finished?.result ?? "") : ""
        let won = result.contains("赢"), lost = result.contains("输")
        let sweep = JevDraw.smooth((age - 0.5) / 0.35)
        let betChips = BlackjackChip.worth(hand.bet)
        if lost, sweep > 0 {
            if sweep < 1 {
                let at = CGPoint(x: Self.mix(Self.betSpot.x, Self.rackCentre.x, sweep), y: Self.mix(Self.betSpot.y, Self.rackCentre.y + 20, sweep))
                var going = g
                going.opacity = 1 - sweep * sweep
                Self.stack(going, base: at, chips: betChips, radius: 20, seed: hand.dealt, lift: CGFloat(sin(sweep * .pi)) * 6)
            }
        } else if !over {
            Self.stack(g, base: Self.betSpot, chips: betChips, radius: 20, seed: hand.dealt)
        }
        Self.bank(g, chips: chips)

        for lie in resting { Self.card(g, lie) }

        // What each hand counts, once a new hand's cards are down.
        let up = hand.dealer.first.map { $0.rank == 1 ? 11 : min($0.rank, 10) } ?? 0
        let theirs = Self.total(hand.dealer), mine = Self.total(hand.player)
        var counts = g
        counts.opacity = sameHand ? 1 : JevDraw.smooth((clock - 0.56) / 0.2)
        Self.badge(counts, hand.revealed ? "庄家 \(theirs.value)" : "庄家 \(up) + ?", at: CGPoint(x: w / 2, y: Self.dealerRow - Self.cardHeight / 2 - 20), size: 14,
                   tone: hand.revealed && theirs.value > 21 ? .red : hand.revealed && theirs.value == 21 ? .gold : .plain)
        counts.opacity = sameHand ? 1 : JevDraw.smooth((clock - 0.42) / 0.2)
        Self.badge(counts, "你 " + (mine.soft ? "软 " : "") + "\(mine.value)", at: CGPoint(x: w / 2, y: Self.playerRow + Self.cardHeight / 2 + 21), size: 15,
                   tone: mine.value > 21 ? .red : mine.value == 21 ? .gold : .plain)
        Self.badge(g, "第 \(hand.dealt) / \(JevBlackjack.hands) 手", at: CGPoint(x: 48, y: 24), size: 12, leading: true)
        Self.badge(g, "筹码 \(chips)", at: CGPoint(x: Self.bankSpot.x - 10, y: Self.bankSpot.y + 52), size: 14)

        for lie in flying { Self.card(g, lie) }

        // The payout comes over from the rack and is set beside the bet.
        if won, sweep > 0 {
            // The verdict ends with what was won: the bet, or half as much again for a natural.
            let pay = BlackjackChip.worth(Int(result.split(separator: " ").last ?? "") ?? hand.bet)
            let beside = CGPoint(x: Self.betSpot.x + 40, y: Self.betSpot.y + 8)
            let at = CGPoint(x: Self.mix(Self.rackCentre.x, beside.x, sweep), y: Self.mix(Self.rackCentre.y + 20, beside.y, sweep))
            Self.stack(g, base: at, chips: pay, radius: 20, seed: hand.dealt + 7, lift: CGFloat(sin(sweep * .pi)) * 6)
        }

        if showingEnd, !result.isEmpty { Self.banner(g, result, age: since, won: won, lost: lost) }
        if over { JevDraw.curtain(g, CGSize(width: w, height: h), title: "打完了", detail: "剩下 \(chips) 个筹码") }
    }

    // MARK: Layout

    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    /// How far apart the cards of a hand of `count` lie: overlapping, closer when there are many.
    static func span(_ count: Int) -> CGFloat { count > 1 ? min(cardWidth * 0.7, (264 - cardWidth) / CGFloat(count - 1)) : 0 }

    /// Where a card of a hand rests, and how it lies: spread from the middle, each a touch askew.
    static func place(_ index: Int, _ count: Int, row: CGFloat, seed: Int) -> (point: CGPoint, angle: Double) {
        let x = width / 2 + (CGFloat(index) - CGFloat(count - 1) / 2) * span(count)
        let wobble = Double(JevDraw.hash(seed, index) % 101 - 50) / 50
        let drift = CGFloat(JevDraw.hash(index, seed) % 5 - 2) * 0.6
        return (CGPoint(x: x + CGFloat(wobble) * 0.8, y: row + drift), wobble * 0.028)
    }

    // MARK: The room and the table

    /// The rail's centre line: down both sides from the dealer's end, round the players' end.
    static func railLine(w: CGFloat, h: CGFloat) -> Path {
        let side = 7 + rail / 2, bottom = h - 7 - rail / 2, knee = h * 0.52
        let kx = (w / 2 - side) * 0.64, ky = (bottom - knee) * 0.64
        return Path { p in
            p.move(to: CGPoint(x: side, y: -rail))
            p.addLine(to: CGPoint(x: side, y: knee))
            p.addCurve(to: CGPoint(x: w / 2, y: bottom), control1: CGPoint(x: side, y: knee + ky), control2: CGPoint(x: w / 2 - kx, y: bottom))
            p.addCurve(to: CGPoint(x: w - side, y: knee), control1: CGPoint(x: w / 2 + kx, y: bottom), control2: CGPoint(x: w - side, y: knee + ky))
            p.addLine(to: CGPoint(x: w - side, y: -rail))
        }
    }

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

    /// The floor, the table's shadow on it, the baize with its weave, light, printing and spots, and the rail.
    static func room(_ g: GraphicsContext, w: CGFloat, h: CGFloat) {
        let all = Path(CGRect(x: 0, y: 0, width: w, height: h))
        g.fill(all, with: .linearGradient(Gradient(colors: [Color(red: 0.13, green: 0.085, blue: 0.07), Color(red: 0.04, green: 0.028, blue: 0.026)]),
                                          startPoint: CGPoint(x: w / 2, y: h * 0.45), endPoint: CGPoint(x: w / 2, y: h)))
        let line = railLine(w: w, h: h)
        var baize = line
        baize.closeSubpath()
        // The table's shadow on the floor.
        g.stroke(line.offsetBy(dx: 0, dy: 10), with: .color(.black.opacity(0.2)), lineWidth: rail + 18)
        g.stroke(line.offsetBy(dx: 0, dy: 5), with: .color(.black.opacity(0.3)), lineWidth: rail + 6)

        var felt = g
        felt.clip(to: baize)
        felt.fill(all, with: .radialGradient(Gradient(stops: [.init(color: Color(red: 0.11, green: 0.52, blue: 0.31), location: 0),
                                                                .init(color: Color(red: 0.055, green: 0.39, blue: 0.22), location: 0.5),
                                                                .init(color: Color(red: 0.02, green: 0.24, blue: 0.13), location: 1)]),
                                             center: CGPoint(x: w / 2, y: h * 0.4), startRadius: 0, endRadius: w * 0.66))
        felt.stroke(fibres.light, with: .color(Color(red: 0.6, green: 0.95, blue: 0.7).opacity(0.08)), lineWidth: 0.6)
        felt.stroke(fibres.dark, with: .color(.black.opacity(0.12)), lineWidth: 0.7)
        // The lamp over the table, and the corners falling away into shade.
        felt.fill(all, with: .radialGradient(Gradient(colors: [.white.opacity(0.07), .clear]), center: CGPoint(x: w / 2, y: h * 0.3), startRadius: 0, endRadius: w * 0.45))
        felt.fill(all, with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.32), location: 1)]),
                                             center: CGPoint(x: w / 2, y: h * 0.42), startRadius: 0, endRadius: w * 0.7))
        printing(felt)
        spots(felt)
        // The rail's shade on the felt.
        for (spread, alpha) in [(26.0, 0.07), (15.0, 0.11), (7.0, 0.17)] as [(CGFloat, Double)] {
            felt.stroke(line, with: .color(.black.opacity(alpha)), lineWidth: rail + spread)
        }
        padded(g, line)
    }

    /// The house's words, printed in gold along arcs round the dealer.
    static func printing(_ g: GraphicsContext) {
        let centre = CGPoint(x: width / 2, y: -250)
        arcText(g, "BLACKJACK PAYS 3 TO 2", centre: centre, radius: 470, size: 17, weight: .heavy, design: .serif,
                colour: gold.opacity(0.9), tracking: 2.2, glyphs: true)
        let reach = 0.5
        var band = Path()
        for radius in [494.0, 514.0] as [CGFloat] {
            band.move(to: CGPoint(x: centre.x + radius * CGFloat(sin(-reach)), y: centre.y + radius * CGFloat(cos(reach))))
            band.addRelativeArc(center: centre, radius: radius, startAngle: .radians(.pi / 2 + reach), delta: .radians(-2 * reach))
        }
        g.stroke(band, with: .color(gold.opacity(0.55)), lineWidth: 1.1)
        var ends = Path()
        for side in [-1.0, 1.0] {
            let a = side * (reach + 0.012)
            let p = CGPoint(x: centre.x + 504 * CGFloat(sin(a)), y: centre.y + 504 * CGFloat(cos(a)))
            ends.move(to: CGPoint(x: p.x, y: p.y - 5)); ends.addLine(to: CGPoint(x: p.x + 3.5, y: p.y))
            ends.addLine(to: CGPoint(x: p.x, y: p.y + 5)); ends.addLine(to: CGPoint(x: p.x - 3.5, y: p.y)); ends.closeSubpath()
        }
        g.fill(ends, with: .color(gold.opacity(0.6)))
        arcText(g, "DEALER STANDS ON ALL 17 · 庄家到 17 点停", centre: centre, radius: 504, size: 10.5, weight: .semibold, design: .default,
                colour: gold.opacity(0.78), tracking: 0.6, glyphs: false)
    }

    /// Text set along the bottom of a circle, each piece turned to follow it.
    static func arcText(_ g: GraphicsContext, _ text: String, centre: CGPoint, radius: CGFloat, size: CGFloat, weight: Font.Weight,
                        design: Font.Design, colour: Color, tracking: CGFloat, glyphs: Bool) {
        let font = Font.system(size: size, weight: weight, design: design)
        let pieces = glyphs ? text.map { String($0) } : text.components(separatedBy: " ")
        let space = size * 0.3
        var widths: [CGFloat] = [], drawn: [GraphicsContext.ResolvedText?] = []
        for piece in pieces {
            if piece.trimmingCharacters(in: .whitespaces).isEmpty { widths.append(space); drawn.append(nil); continue }
            let resolved = g.resolve(Text(piece).font(font).foregroundColor(colour))
            widths.append(resolved.measure(in: CGSize(width: 1000, height: 200)).width)
            drawn.append(resolved)
        }
        let gap = glyphs ? tracking : space + tracking
        var along = -(widths.reduce(0, +) + gap * CGFloat(pieces.count - 1)) / 2
        for (index, piece) in drawn.enumerated() {
            let middle = along + widths[index] / 2
            along += widths[index] + gap
            guard let piece else { continue }
            let phi = Double(middle / radius)
            var c = g
            c.translateBy(x: centre.x + radius * CGFloat(sin(phi)), y: centre.y + radius * CGFloat(cos(phi)))
            c.rotate(by: .radians(-phi))
            c.draw(piece, at: .zero, anchor: .center)
        }
    }

    /// The outlines printed where the cards go, and the betting circle.
    static func spots(_ g: GraphicsContext) {
        for row in [dealerRow, playerRow] {
            let r = CGRect(x: width / 2 - cardWidth * 0.85 - 10, y: row - cardHeight / 2 - 8, width: cardWidth * 1.7 + 20, height: cardHeight + 16)
            g.stroke(Path(roundedRect: r, cornerRadius: 11), with: .color(gold.opacity(0.3)), lineWidth: 1.2)
        }
        let ring = CGRect(x: betSpot.x - 37, y: betSpot.y - 37, width: 74, height: 74)
        g.stroke(Path(ellipseIn: ring), with: .color(gold.opacity(0.6)), lineWidth: 1.6)
        g.stroke(Path(ellipseIn: ring.insetBy(dx: 5, dy: 5)), with: .color(gold.opacity(0.28)), lineWidth: 0.8)
    }

    /// A padded leather roll: dark at its edges, catching the light along its crown, stitched down both sides.
    static func padded(_ g: GraphicsContext, _ line: Path) {
        g.stroke(line, with: .color(Color(red: 0.05, green: 0.025, blue: 0.015)), lineWidth: rail + 2)
        let leather = (0.36, 0.16, 0.09)
        for step in 0..<8 {
            let f = Double(step) / 7
            g.stroke(line.offsetBy(dx: 0, dy: -CGFloat(f) * 3), with: .color(JevDraw.shade(leather, 0.4 + 0.75 * sin(f * .pi / 2))),
                     lineWidth: rail * CGFloat(1 - f * 0.88))
        }
        g.stroke(line.offsetBy(dx: 0, dy: -4), with: .color(Color(red: 1, green: 0.88, blue: 0.74).opacity(0.2)), lineWidth: 1.6)
        g.stroke(line.strokedPath(StrokeStyle(lineWidth: rail - 7)), with: .color(Color(red: 0.92, green: 0.74, blue: 0.52).opacity(0.42)),
                 style: StrokeStyle(lineWidth: 0.8, dash: [3.2, 2.4]))
    }

    /// The dealer's chip rack, set into the table at the dealer's end.
    static func rack(_ g: GraphicsContext) {
        let tray = CGRect(x: rackCentre.x - 104, y: -14, width: 208, height: 46)
        g.fill(Path(roundedRect: tray.offsetBy(dx: 0, dy: 5).insetBy(dx: -3, dy: -3), cornerRadius: 11), with: .color(.black.opacity(0.18)))
        g.fill(Path(roundedRect: tray.offsetBy(dx: 0, dy: 2.5), cornerRadius: 9), with: .color(.black.opacity(0.35)))
        g.fill(Path(roundedRect: tray, cornerRadius: 9), with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.08)]),
                                                                            startPoint: CGPoint(x: 0, y: tray.minY), endPoint: CGPoint(x: 0, y: tray.maxY)))
        let slots = [100, 100, 25, 25, 10, 10, 5, 5]
        for (slot, value) in slots.enumerated() {
            let chip = BlackjackChip.of(value)
            let tube = CGRect(x: tray.minX + 6 + CGFloat(slot) * 24.6, y: tray.minY, width: 22, height: tray.height - 6)
            g.fill(Path(roundedRect: tube, cornerRadius: 4), with: .color(.black.opacity(0.6)))
            let roll = CGRect(x: tube.minX + 1.5, y: tube.minY, width: tube.width - 3, height: tube.height - 2 - CGFloat(JevDraw.hash(slot, 5) % 9))
            g.fill(Path(roundedRect: roll, cornerRadius: 2), with: .linearGradient(Gradient(stops: [
                .init(color: JevDraw.shade(chip.body, 0.45), location: 0), .init(color: JevDraw.shade(chip.body, 1), location: 0.3),
                .init(color: JevDraw.shade(chip.body, 1.4), location: 0.45), .init(color: JevDraw.shade(chip.body, 0.9), location: 0.7),
                .init(color: JevDraw.shade(chip.body, 0.4), location: 1)]), startPoint: CGPoint(x: roll.minX, y: 0), endPoint: CGPoint(x: roll.maxX, y: 0)))
            var edges = Path(), marks = Path()
            var y = roll.maxY - 3.2, n = 0
            while y > roll.minY {
                edges.move(to: CGPoint(x: roll.minX, y: y)); edges.addLine(to: CGPoint(x: roll.maxX, y: y))
                marks.addRect(CGRect(x: roll.minX + 3 + CGFloat((n * 5 + slot * 3) % 11), y: y + 0.7, width: 3, height: 1.8))
                y -= 3.2; n += 1
            }
            g.stroke(edges, with: .color(.black.opacity(0.38)), lineWidth: 0.5)
            g.fill(marks, with: .color(chip.insert.opacity(0.7)))
        }
        g.stroke(Path(roundedRect: tray, cornerRadius: 9), with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.42)]),
                                                                              startPoint: CGPoint(x: 0, y: tray.minY), endPoint: CGPoint(x: 0, y: tray.maxY)), lineWidth: 1.6)
    }

    /// The dealing shoe, turned towards the table: a smoked box, the deck dim under its lid, the next card showing at
    /// the mouth. Returns where a dealt card starts from.
    static func shoe(_ g: GraphicsContext) -> CGPoint {
        let body = CGRect(x: -43, y: -56, width: 86, height: 112)
        var shade = g
        shade.translateBy(x: shoeCentre.x + 5, y: shoeCentre.y + 9)
        shade.rotate(by: .radians(shoeAngle))
        shade.fill(Path(roundedRect: body.insetBy(dx: -3, dy: -3), cornerRadius: 13), with: .color(.black.opacity(0.2)))
        shade.fill(Path(roundedRect: body.offsetBy(dx: 0, dy: -3), cornerRadius: 10), with: .color(.black.opacity(0.32)))
        var s = g
        s.translateBy(x: shoeCentre.x, y: shoeCentre.y)
        s.rotate(by: .radians(shoeAngle))
        s.fill(Path(roundedRect: body, cornerRadius: 10), with: .linearGradient(Gradient(colors: [Color(red: 0.22, green: 0.21, blue: 0.24), Color(red: 0.04, green: 0.04, blue: 0.05)]),
                                                                             startPoint: CGPoint(x: body.minX, y: body.minY), endPoint: CGPoint(x: body.maxX, y: body.maxY)))
        // The next card, on the ramp and a little way out of the mouth.
        var mouth = s
        mouth.clip(to: Path(CGRect(x: -50, y: 10, width: 100, height: 70)))
        back(mouth, CGRect(x: -cardWidth / 2, y: body.maxY + 6 - cardHeight, width: cardWidth, height: cardHeight), corner: cardWidth * 0.085)
        // The lid over the deck, notched where the dealer's finger slides the card out.
        let edge: CGFloat = 22, notch: CGFloat = 13
        let lid = Path { p in
            p.move(to: CGPoint(x: -37, y: -50))
            p.addLine(to: CGPoint(x: 37, y: -50))
            p.addLine(to: CGPoint(x: 37, y: edge))
            p.addLine(to: CGPoint(x: notch, y: edge))
            p.addRelativeArc(center: CGPoint(x: 0, y: edge), radius: notch, startAngle: .zero, delta: .degrees(-180))
            p.addLine(to: CGPoint(x: -37, y: edge))
            p.closeSubpath()
        }
        mouth.fill(lid.offsetBy(dx: 0, dy: 3.5), with: .color(.black.opacity(0.45)))
        s.fill(lid, with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.29, blue: 0.33), Color(red: 0.1, green: 0.1, blue: 0.12)]),
                                          startPoint: CGPoint(x: -37, y: -50), endPoint: CGPoint(x: 37, y: edge)))
        var smoke = s
        smoke.clip(to: lid)
        smoke.fill(Path(CGRect(x: -cardWidth / 2, y: -46, width: cardWidth, height: 72)), with: .color(Color(red: 0.62, green: 0.06, blue: 0.1).opacity(0.1)))
        smoke.fill(Path(CGRect(x: -37, y: -50, width: 26, height: 80)), with: .linearGradient(Gradient(colors: [.white.opacity(0.1), .clear]),
                                                                                            startPoint: CGPoint(x: -37, y: 0), endPoint: CGPoint(x: -11, y: 0)))
        // The weight that keeps the deck pressed forward.
        let weight = CGRect(x: -30, y: -46, width: 60, height: 17)
        s.fill(Path(roundedRect: weight.offsetBy(dx: 0, dy: 2), cornerRadius: 5), with: .color(.black.opacity(0.4)))
        s.fill(Path(roundedRect: weight, cornerRadius: 5), with: .linearGradient(Gradient(colors: [Color(white: 0.46), Color(white: 0.17)]),
                                                                              startPoint: CGPoint(x: 0, y: weight.minY), endPoint: CGPoint(x: 0, y: weight.maxY)))
        s.stroke(lid, with: .color(.white.opacity(0.2)), lineWidth: 0.9)
        s.stroke(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10), with: .color(.white.opacity(0.2)), lineWidth: 1)
        s.stroke(Path { p in p.move(to: CGPoint(x: -34, y: body.maxY - 1.5)); p.addLine(to: CGPoint(x: 34, y: body.maxY - 1.5)) },
                 with: .color(gold.opacity(0.7)), lineWidth: 1.2)
        let start = body.maxY + 6 - cardHeight / 2 + cardHeight * 0.4
        return CGPoint(x: shoeCentre.x - CGFloat(sin(shoeAngle)) * start, y: shoeCentre.y + CGFloat(cos(shoeAngle)) * start)
    }

    /// The discard holder at the dealer's right, with the cards of hands already played in it.
    static func discards(_ g: GraphicsContext) {
        var d = g
        d.translateBy(x: 108, y: 110)
        d.rotate(by: .radians(-0.38))
        let holder = CGRect(x: -cardWidth / 2 - 6, y: -cardHeight / 2 - 6, width: cardWidth + 12, height: cardHeight + 12)
        d.fill(Path(roundedRect: holder.offsetBy(dx: -2, dy: 5), cornerRadius: 9), with: .color(.black.opacity(0.25)))
        d.fill(Path(roundedRect: holder, cornerRadius: 9), with: .color(Color(red: 0.75, green: 0.9, blue: 0.85).opacity(0.12)))
        for layer in 0..<4 {
            let jitter = CGFloat(JevDraw.hash(layer, 17) % 7 - 3) * 0.6
            var card = d
            card.translateBy(x: jitter, y: CGFloat(layer) * -0.8)
            card.rotate(by: .radians(Double(JevDraw.hash(layer, 29) % 9 - 4) * 0.012))
            card.fill(Path(roundedRect: CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight).offsetBy(dx: 0, dy: 1.2),
                           cornerRadius: cardWidth * 0.085), with: .color(.black.opacity(0.25)))
            back(card, CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight), corner: cardWidth * 0.085)
        }
        d.fill(Path(roundedRect: holder, cornerRadius: 9), with: .linearGradient(Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.62), Color(red: 0.02, green: 0.02, blue: 0.03).opacity(0.72)]),
                                                                             startPoint: CGPoint(x: holder.minX, y: holder.minY), endPoint: CGPoint(x: holder.maxX, y: holder.maxY)))
        d.fill(Path(roundedRect: CGRect(x: holder.minX + 3, y: holder.minY + 3, width: holder.width * 0.4, height: holder.height - 6), cornerRadius: 7),
               with: .linearGradient(Gradient(colors: [.white.opacity(0.12), .clear]), startPoint: CGPoint(x: holder.minX, y: 0), endPoint: CGPoint(x: holder.minX + holder.width * 0.4, y: 0)))
        d.stroke(Path(roundedRect: holder.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 9), with: .color(.white.opacity(0.22)), lineWidth: 1)
    }

    // MARK: Cards

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

    /// A card lying on the table (or in the air): its shadow, then its face or its back.
    static func card(_ g: GraphicsContext, _ lie: Lie) {
        let w = cardWidth, h = cardHeight, corner = w * 0.085
        var c = g
        c.translateBy(x: lie.at.x, y: lie.at.y)
        c.rotate(by: .radians(lie.angle))
        let lifted = 1 + lie.lift * 0.006
        c.scaleBy(x: max(lie.squeeze, 0.02) * lifted, y: lifted)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        // A soft shadow that falls down the table whichever way the card is turned.
        let sa = CGFloat(sin(lie.angle)), ca = CGFloat(cos(lie.angle))
        for (reach, grow, alpha) in [(1.0, 2.4, 0.09), (0.6, 1.1, 0.13), (0.25, 0.2, 0.2)] as [(CGFloat, CGFloat, Double)] {
            let dx = (0.5 + lie.lift * 0.45) * reach, dy = (2.2 + lie.lift) * reach
            c.fill(Path(roundedRect: rect.insetBy(dx: -grow, dy: -grow).offsetBy(dx: dx * ca + dy * sa, dy: -dx * sa + dy * ca), cornerRadius: corner + grow),
                   with: .color(.black.opacity(alpha)))
        }
        guard let face = lie.face else { back(c, rect, corner: corner); return }
        c.fill(Path(roundedRect: rect, cornerRadius: corner),
               with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.994, blue: 0.975), Color(red: 0.95, green: 0.935, blue: 0.9)]),
                                     startPoint: CGPoint(x: 0, y: -h / 2), endPoint: CGPoint(x: 0, y: h / 2)))
        c.stroke(Path(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: corner), with: .color(Color(red: 0.36, green: 0.31, blue: 0.25).opacity(0.5)), lineWidth: 0.6)
        guard lie.squeeze > 0.25 else { return }
        let red = face.suit < 2
        let ink = red ? Color(red: 0.8, green: 0.07, blue: 0.11) : Color(red: 0.09, green: 0.09, blue: 0.12)
        let rank = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][face.rank - 1]
        // The index in two corners.
        let label = c.resolve(Text(rank).font(.system(size: w * 0.25, weight: .bold, design: .serif)).foregroundColor(ink))
        let indexX = -w * 0.395, indexY = -h / 2 + w * 0.165
        var corners = Path()
        for turned in [false, true] {
            var k = c
            if turned { k.rotate(by: .radians(.pi)) }
            k.translateBy(x: indexX, y: indexY)
            if rank == "10" { k.scaleBy(x: 0.8, y: 1) }
            k.draw(label, at: .zero)
            corners.addPath(suit(face.suit, at: CGPoint(x: turned ? -indexX : indexX, y: turned ? h / 2 - w * 0.39 : -h / 2 + w * 0.39), size: w * 0.15, turned: turned))
        }
        c.fill(corners, with: .color(ink))
        switch face.rank {
        case 1 where face.suit == 2:
            // The ace of spades, as ornate as a card gets: a big spade with a line engraved in it, in a gilt ring.
            let ring = CGRect(x: -w * 0.37, y: -w * 0.44, width: w * 0.74, height: w * 0.88)
            c.stroke(Path(ellipseIn: ring), with: .color(Color(red: 0.8, green: 0.6, blue: 0.2).opacity(0.8)), lineWidth: 1)
            c.stroke(Path(ellipseIn: ring.insetBy(dx: 2.5, dy: 2.5)), with: .color(ink.opacity(0.3)), lineWidth: 0.6)
            c.fill(suit(2, at: .zero, size: w * 0.6), with: .color(ink))
            c.stroke(suit(2, at: CGPoint(x: 0, y: -w * 0.012), size: w * 0.45), with: .color(.white.opacity(0.85)), lineWidth: 0.8)
        case 1:
            c.fill(suit(face.suit, at: .zero, size: w * 0.46), with: .color(ink))
        case 11...13:
            court(c, face, rank: rank, ink: ink, red: red)
        default:
            var marks = Path()
            for (column, row) in pips[face.rank] {
                marks.addPath(suit(face.suit, at: CGPoint(x: column * w * 0.2, y: row * h * 0.31), size: w * 0.19, turned: row > 0.01))
            }
            c.fill(marks, with: .color(ink))
        }
    }

    /// The crowns of the court: the king's with three points, the queen's with pearls, the jack's cap with a plume.
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
    static func court(_ c: GraphicsContext, _ face: JevBlackjack.Card, rank: String, ink: Color, red: Bool) {
        let w = cardWidth, h = cardHeight
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
        // The crown.
        let crown = CGRect(x: -frame.width * 0.36, y: frame.minY + frame.height * 0.1, width: frame.width * 0.72, height: frame.width * 0.46)
        let fit = CGAffineTransform(a: crown.width, b: 0, c: 0, d: crown.height, tx: crown.midX, ty: crown.midY)
        let parts = crowns[face.rank - 11]
        let gilt = GraphicsContext.Shading.linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), Color(red: 0.8, green: 0.55, blue: 0.12)]),
                                                         startPoint: CGPoint(x: 0, y: crown.minY), endPoint: CGPoint(x: 0, y: crown.maxY))
        let shape = parts.shape.applying(fit), beads = parts.beads.applying(fit)
        c.fill(shape, with: gilt)
        c.stroke(shape, with: .color(Color(red: 0.45, green: 0.28, blue: 0.05)), lineWidth: 0.6)
        c.fill(beads, with: face.rank == 12 ? .color(.white) : gilt)
        c.stroke(beads, with: .color(Color(red: 0.45, green: 0.28, blue: 0.05)), lineWidth: 0.5)
        let bandTop = crown.minY + crown.height * 0.74
        c.fill(Path(CGRect(x: crown.minX + crown.width * 0.06, y: bandTop, width: crown.width * 0.88, height: crown.maxY - bandTop)), with: .color(trim))
        var gems = Path()
        for gx in [-0.25, 0, 0.25] as [CGFloat] {
            gems.addEllipse(in: CGRect(x: crown.midX + crown.width * gx - 1.4, y: (bandTop + crown.maxY) / 2 - 1.4, width: 2.8, height: 2.8))
        }
        c.fill(gems, with: .color(Color(red: 1, green: 0.88, blue: 0.5)))
        // The letter, and the suit beneath it.
        c.draw(c.resolve(Text(rank).font(.system(size: w * 0.42, weight: .heavy, design: .serif)).foregroundColor(ink)),
               at: CGPoint(x: 0, y: frame.midY + frame.height * 0.06))
        c.fill(suit(face.suit, at: CGPoint(x: 0, y: frame.maxY - frame.height * 0.15), size: w * 0.15), with: .color(ink))
        c.stroke(Path(frame), with: .color(trim), lineWidth: 1.4)
        c.stroke(Path(frame.insetBy(dx: 2.2, dy: 2.2)), with: .color(Color(red: 0.84, green: 0.64, blue: 0.22)), lineWidth: 0.7)
    }

    /// A card's back: deep red lattice inside a white border, with a medallion in the middle.
    static func back(_ c: GraphicsContext, _ rect: CGRect, corner: CGFloat) {
        let w = rect.width
        c.fill(Path(roundedRect: rect, cornerRadius: corner), with: .color(Color(red: 0.99, green: 0.98, blue: 0.955)))
        c.stroke(Path(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: corner), with: .color(Color(red: 0.36, green: 0.31, blue: 0.25).opacity(0.5)), lineWidth: 0.6)
        let inner = rect.insetBy(dx: w * 0.075, dy: w * 0.075)
        let field = Path(roundedRect: inner, cornerRadius: corner * 0.5)
        c.fill(field, with: .linearGradient(Gradient(colors: [Color(red: 0.74, green: 0.1, blue: 0.15), Color(red: 0.48, green: 0.03, blue: 0.08)]),
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
        lattice.stroke(lines.offsetBy(dx: step / 2, dy: 0), with: .color(Color(red: 0.28, green: 0, blue: 0.03).opacity(0.45)), lineWidth: 1.3)
        lattice.stroke(lines, with: .color(Color(red: 1, green: 0.86, blue: 0.84).opacity(0.36)), lineWidth: 0.7)
        lattice.stroke(Path(roundedRect: inner.insetBy(dx: 2.2, dy: 2.2), cornerRadius: 2), with: .color(.white.opacity(0.6)), lineWidth: 0.8)
        let oval = CGRect(x: rect.midX - w * 0.17, y: rect.midY - w * 0.24, width: w * 0.34, height: w * 0.48)
        lattice.fill(Path(ellipseIn: oval), with: .color(Color(red: 0.55, green: 0.04, blue: 0.09)))
        lattice.stroke(Path(ellipseIn: oval), with: .color(.white.opacity(0.75)), lineWidth: 0.9)
        lattice.stroke(Path(ellipseIn: oval.insetBy(dx: 2.3, dy: 2.3)), with: .color(Color(red: 0.96, green: 0.8, blue: 0.45).opacity(0.75)), lineWidth: 0.6)
        lattice.fill(suit(2, at: CGPoint(x: rect.midX, y: rect.midY), size: w * 0.16), with: .color(Color(red: 1, green: 0.92, blue: 0.8).opacity(0.9)))
    }

    // MARK: Chips

    /// A stack of chips seen a little from the side: each an edge striped with its inserts, the top one's face printed.
    static func stack(_ g: GraphicsContext, base: CGPoint, chips: [BlackjackChip], radius r: CGFloat, seed: Int, lift: CGFloat = 0) {
        guard !chips.isEmpty else { return }
        let tilt: CGFloat = 0.6, ry = r * tilt, thick = r * 0.2
        let floor = CGRect(x: base.x - r, y: base.y - ry, width: 2 * r, height: 2 * ry)
        g.fill(Path(ellipseIn: floor.insetBy(dx: -2, dy: -1.5).offsetBy(dx: 2 + lift * 0.4, dy: 3 + lift)), with: .color(.black.opacity(0.2)))
        g.fill(Path(ellipseIn: floor.offsetBy(dx: 1 + lift * 0.3, dy: 1.5 + lift * 0.8)), with: .color(.black.opacity(0.3)))
        let k: CGFloat = 0.5523
        for (i, chip) in chips.enumerated() {
            let cx = base.x + CGFloat(JevDraw.hash(seed, i) % 9 - 4) * 0.25
            let top = base.y - lift - CGFloat(i + 1) * thick + CGFloat(JevDraw.hash(i, seed) % 3 - 1) * 0.2
            // The edge: from the face down one chip's thickness.
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
    static func chipFace(_ g: GraphicsContext, centre: CGPoint, radius r: CGFloat, tilt: CGFloat, chip: BlackjackChip, turn: Double) {
        var f = g
        f.translateBy(x: centre.x, y: centre.y)
        f.scaleBy(x: 1, y: tilt)
        let disc = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        f.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: [JevDraw.shade(chip.body, 1.2), JevDraw.shade(chip.body, 0.9)]),
                                                           startPoint: CGPoint(x: 0, y: -r), endPoint: CGPoint(x: 0, y: r)))
        let rim = r * 0.85, around = 2 * CGFloat.pi * rim
        f.stroke(Path(ellipseIn: CGRect(x: -rim, y: -rim, width: 2 * rim, height: 2 * rim)), with: .color(chip.insert),
                 style: StrokeStyle(lineWidth: r * 0.26, dash: [around / 12, around / 12], dashPhase: CGFloat(turn) * rim))
        f.stroke(Path(ellipseIn: disc.insetBy(dx: r * 0.34, dy: r * 0.34)), with: .color(chip.insert.opacity(0.8)), style: StrokeStyle(lineWidth: 0.9, dash: [1.3, 1.2]))
        let inlay = disc.insetBy(dx: r * 0.44, dy: r * 0.44)
        f.fill(Path(ellipseIn: inlay), with: .color(Color(red: 0.98, green: 0.96, blue: 0.91)))
        f.stroke(Path(ellipseIn: inlay), with: .color(JevDraw.shade(chip.body, 0.6)), lineWidth: 0.6)
        let digits = "\(chip.value)"
        f.draw(Text(digits).font(.system(size: r * (digits.count > 2 ? 0.5 : 0.64), weight: .heavy, design: .rounded)).foregroundColor(chip.ink), at: .zero)
        f.stroke(Path(ellipseIn: disc.insetBy(dx: 0.3, dy: 0.3)), with: .color(.black.opacity(0.35)), lineWidth: 0.6)
    }

    /// The player's chips as a player keeps them: some fives and twenty-fives for betting, the rest in hundreds,
    /// in stacks of a colour each — hundreds at the back.
    static func bank(_ g: GraphicsContext, chips: Int) {
        let fives = (chips % 25) / 5 + (chips >= 150 && chips % 25 < 10 ? 5 : 0)
        let rest = chips - 5 * fives
        let quarters = (rest % 100) / 25 + (rest >= 300 && rest % 100 < 75 ? 4 : 0)
        let hundreds = (rest - 25 * quarters) / 100
        func stacks(_ count: Int, _ value: Int, most: Int) -> [[BlackjackChip]] {
            guard count > 0 else { return [] }
            let piles = min((count + 5) / 6, most)
            return (0..<piles).map { i in Array(repeating: .of(value), count: min(count / piles + (i < count % piles ? 1 : 0), 8)) }
        }
        let rear = stacks(hundreds, 100, most: 3), front = stacks(quarters, 25, most: 1) + stacks(fives, 5, most: 1)
        for (row, line) in [(-12.0, rear), (12.0, front)] as [(CGFloat, [[BlackjackChip]])] {
            for (i, pile) in line.enumerated() {
                let x = bankSpot.x + (CGFloat(i) - CGFloat(line.count - 1) / 2) * 38 + (row > 0 ? 8 : 0)
                stack(g, base: CGPoint(x: x, y: bankSpot.y + row), chips: pile, radius: 16, seed: i * 31 + Int(row) + pile.count)
            }
        }
    }

    // MARK: Words on the table

    enum Tone { case plain, gold, red }

    /// A number on a dark pill with a gold edge.
    static func badge(_ g: GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat, tone: Tone = .plain, leading: Bool = false) {
        let ink: Color = tone == .gold ? Color(red: 0.28, green: 0.16, blue: 0.02) : .white
        let label = g.resolve(Text(text).font(.system(size: size, weight: .bold, design: .rounded)).foregroundColor(ink))
        let m = label.measure(in: CGSize(width: 600, height: 200))
        let width = m.width + size * 1.5, height = size * 1.7
        let pill = CGRect(x: leading ? p.x : p.x - width / 2, y: p.y - height / 2, width: width, height: height)
        let shape = Path(roundedRect: pill, cornerRadius: height / 2)
        var colours = [Color(red: 0.13, green: 0.12, blue: 0.11).opacity(0.9), Color(red: 0.03, green: 0.03, blue: 0.03).opacity(0.9)]
        switch tone {
        case .gold: colours = [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.86, green: 0.62, blue: 0.2)]
        case .red: colours = [Color(red: 0.85, green: 0.2, blue: 0.18), Color(red: 0.55, green: 0.06, blue: 0.07)]
        case .plain: break
        }
        g.fill(shape.offsetBy(dx: 0, dy: 2.5), with: .color(.black.opacity(0.3)))
        g.fill(shape, with: .linearGradient(Gradient(colors: colours), startPoint: CGPoint(x: 0, y: pill.minY), endPoint: CGPoint(x: 0, y: pill.maxY)))
        g.stroke(Path(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), cornerRadius: height / 2 - 0.5), with: .color(gold.opacity(0.8)), lineWidth: 1)
        g.stroke(Path(roundedRect: pill.insetBy(dx: 2, dy: 2), cornerRadius: height / 2 - 2), with: .color(.white.opacity(0.1)), lineWidth: 1)
        g.draw(label, at: CGPoint(x: pill.midX, y: pill.midY))
    }

    /// The verdict on a hand, popping up over the middle of the table.
    static func banner(_ g: GraphicsContext, _ result: String, age: Double, won: Bool, lost: Bool) {
        let appear = JevDraw.smooth(age / 0.18), leave = 1 - JevDraw.smooth((age - (linger - 0.2)) / 0.2)
        let pop = 0.84 + 0.16 * appear + 0.05 * sin(min(age / 0.36, 1) * .pi)
        var b = g
        b.opacity = min(appear * 1.5, 1) * leave
        b.translateBy(x: width / 2, y: 238)
        b.scaleBy(x: CGFloat(pop), y: CGFloat(pop))
        let label = b.resolve(Text(result).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundColor(.white))
        let shadow = b.resolve(Text(result).font(.system(size: 21, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.45)))
        let m = label.measure(in: CGSize(width: 600, height: 200))
        let rect = CGRect(x: -max(130, m.width / 2 + 34), y: -28, width: 2 * max(130, m.width / 2 + 34), height: 56)
        let colours = won ? [Color(red: 0.2, green: 0.66, blue: 0.36), Color(red: 0.04, green: 0.38, blue: 0.17)]
            : lost ? [Color(red: 0.86, green: 0.22, blue: 0.19), Color(red: 0.5, green: 0.05, blue: 0.07)]
            : [Color(white: 0.5), Color(white: 0.26)]
        b.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 7).insetBy(dx: -3, dy: -2), cornerRadius: 17), with: .color(.black.opacity(0.18)))
        b.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3.5), cornerRadius: 15), with: .color(.black.opacity(0.3)))
        b.fill(Path(roundedRect: rect, cornerRadius: 15), with: .linearGradient(Gradient(colors: colours), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        b.fill(Path(roundedRect: CGRect(x: rect.minX + 3, y: rect.minY + 3, width: rect.width - 6, height: rect.height * 0.45), cornerRadius: 12),
               with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.02)]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.midY)))
        b.stroke(Path(roundedRect: rect.insetBy(dx: 0.8, dy: 0.8), cornerRadius: 14), with: .color(gold), lineWidth: 1.6)
        b.stroke(Path(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 11), with: .color(gold.opacity(0.45)), lineWidth: 0.7)
        b.draw(shadow, at: CGPoint(x: 1.2, y: 1.8))
        b.draw(label, at: .zero)
    }
}

/// A casino chip: what it is worth, its colour, the inserts round its edge, the ink of its value.
fileprivate struct BlackjackChip {
    let value: Int, body: (Double, Double, Double), insert: Color, ink: Color

    /// The fewest chips that make `amount`, largest at the bottom of the stack.
    static func worth(_ amount: Int) -> [BlackjackChip] {
        var left = max(amount, 5), out: [BlackjackChip] = []
        for value in [25, 10, 5] { while left >= value { out.append(.of(value)); left -= value } }
        return out
    }

    static func of(_ value: Int) -> BlackjackChip {
        switch value {
        case 5: return BlackjackChip(value: 5, body: (0.78, 0.09, 0.11), insert: .white, ink: Color(red: 0.62, green: 0.05, blue: 0.08))
        case 10: return BlackjackChip(value: 10, body: (0.14, 0.32, 0.74), insert: .white, ink: Color(red: 0.1, green: 0.22, blue: 0.56))
        case 25: return BlackjackChip(value: 25, body: (0.07, 0.5, 0.26), insert: .white, ink: Color(red: 0.04, green: 0.36, blue: 0.17))
        default: return BlackjackChip(value: 100, body: (0.14, 0.14, 0.15), insert: Color(red: 0.93, green: 0.9, blue: 0.84), ink: Color(white: 0.1))
        }
    }
}
