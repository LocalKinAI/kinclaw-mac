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

    static let hands = 200, stake = 10

    private struct Card { var rank: Int; var suit: Int }        // rank 1…13
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

    func reset(seed: UInt64) {
        dice = JevDice(seed: seed); shoe = []; chips = 1000; dealt = 0; over = false; lastResult = ""; given = 0
        deal()
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
