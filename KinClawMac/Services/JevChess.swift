import SwiftUI

/// Chess for two players who read words.
///
/// The same division of labour as the other games, with more to measure: the
/// program generates the legal moves (the engine's move generator agrees with
/// the published perft counts on five standard positions), looks one reply
/// ahead for each — and one recapture past that — and says what it found:
/// what is captured, whether it is check or mate, what it does for
/// development, and how the material stands after the opponent's best reply.
/// The players choose among a dozen candidates. A dozen because that is what
/// Laya can read at once, and both sides must be asked the same question; and
/// not simply the evaluator's best dozen, which would be the evaluator playing
/// — every check, every castle and the tempting captures are in the list
/// whether they are good or not, so there is something to judge.
@MainActor
final class JevChess: JevGame {
    let id = "chess", title = "国际象棋", symbol = "crown"
    let rules = "Chess. Each option is one legal move for the side to play. The game is won by checkmate; it is drawn by stalemate, threefold repetition, fifty moves without a capture or pawn move, or when neither side has enough left to mate."
    let question = "Which move is best for the side to play?"
    let howToJudge = "Compare the options in this order, and let nothing lower in the list outweigh anything higher. First: checkmate wins at once and is always best; a forced checkmate is next best. Second: never choose a move that allows checkmate. Third: the material result decides — a move that comes out behind in material is worse than every move that keeps material the same, whatever else it does; a move that comes out ahead is better than every move that does not, and further ahead is better. A queen is worth 9, a rook 5, a bishop or a knight 3, a pawn 1. Fourth, and only among moves with the same material result: prefer a move that threatens checkmate, then one that threatens to win material, the bigger threat first — the opponent has to answer a threat. Fifth: prefer castling early, developing knights and bishops, and pawns in the center; avoid bringing the queen out early, moving the king and giving up castling, retreating, and repeating a position unless you are behind — but only when it costs nothing above."
    let sides = ["白方", "黑方"]

    private var position_ = ChessPosition()
    private var seen: [String: Int] = [:]
    private var moves: [ChessPosition.Move] = []
    private var last: ChessPosition.Move?
    /// The board before the last move, for the picture: the piece slides from there.
    private var previous = [Int8](repeating: 0, count: 64)
    private(set) var ticked = Date.distantPast
    private var played: [String] = []
    private(set) var plies = 0
    private(set) var result: String?
    private var dice = JevDice(seed: 1)
    /// How many plies past the move the words look, when somebody insists (the
    /// test harness does). Otherwise: three for a reader, one — what the
    /// evaluator that plays looks — for anybody else. See `JevXiangqi`, where
    /// this was worked out: a reader beats the evaluator only by being told
    /// something the evaluator does not know.
    nonisolated(unsafe) static var foresight: Int?
    private var reader = false
    private var depth: Int { Self.foresight ?? (reader ? 3 : 1) }

    func prepare(reader: Bool) { self.reader = reader }

    // MARK: Played by a person

    private var person = false
    private var picked: Int?
    /// Where the piece picked up can go.
    private var targets: Set<Int> { picked.map { from in Set(moves.filter { $0.from == from }.map(\.to)) } ?? [] }
    func prepare(person: Bool) { self.person = person }
    let controls = "点自己的一个棋子，再点它要去的格子（兵升变自动升后）"

    func tap(row: Int, col: Int, among options: [JevOption]) -> JevReaction {
        let square = row * 8 + col
        if let from = picked, let option = options.first(where: {
            let move = moves[$0.move]
            return move.from == from && move.to == square && (move.promotion == 0 || move.promotion == 5)
        }) { picked = nil; return .choose(option) }
        if moves.contains(where: { $0.from == square }) { picked = square; return .redraw }
        let mine: Int8 = position_.whiteToMove ? 1 : -1
        if position_.board[square] * mine > 0 { picked = nil; return .explain(stuck(square)) }
        if let from = picked { picked = nil; return .explain(cannot(from, square)) }
        return .nothing
    }

    nonisolated private static let chinese = ["", "兵", "马", "象", "车", "后", "王"]

    /// One of the person's pieces that has no move: why.
    private func stuck(_ square: Int) -> String {
        let white = position_.whiteToMove, name = Self.chinese[Int(abs(position_.board[square]))]
        if position_.inCheck(white: white) { return "你正被将军：这个\(name)解不了将。能解将的子圈出来了" }
        var without = position_
        without.board[square] = 0
        if without.inCheck(white: white) { return "这个\(name)被牵制了：它一走开，你的王就会被将军" }
        return "这个\(name)现在没有地方可走"
    }

    /// A piece picked up, and a square it may not go to: why.
    private func cannot(_ from: Int, _ to: Int) -> String {
        if position_.isPseudoLegal(from: from, to: to) {
            return position_.inCheck(white: position_.whiteToMove) ? "你正被将军：这一步解不了将" : "走了这一步，你的王会被将军，不能走"
        }
        switch Int(abs(position_.board[from])) {
        case 1: return "兵只能往前走一格（第一次可以走两格），吃子要斜着往前吃"
        case 2: return "马走日字"
        case 3: return "象只能斜着走，路上不能有子"
        case 4: return "车只能横竖走，路上不能有子"
        case 5: return "后可以横竖斜着走，路上不能有子"
        default: return "王只能走一格；王车易位要王和车都没动过、中间没有子、王不经过被攻击的格子"
        }
    }

    var turn: Int { position_.whiteToMove ? 0 : 1 }
    var over: Bool { result != nil }
    var score: Int { position_.material }
    var status: String {
        let balance = position_.material == 0 ? "子力相当" : position_.material > 0 ? "白方多 \(position_.material) 分" : "黑方多 \(-position_.material) 分"
        return result ?? "第 \(plies / 2 + 1) 回合 · 轮到\(sides[turn]) · \(balance)" + (position_.inCheck(white: position_.whiteToMove) ? " · 将军" : "")
    }
    var situation: String {
        let me = position_.whiteToMove ? "White" : "Black", mine = position_.whiteToMove ? 1 : -1
        let balance = mine * position_.material
        return "\(me) to play, move \(plies / 2 + 1); material: \(balance == 0 ? "even" : balance > 0 ? "\(me) is up \(balance)" : "\(me) is down \(-balance)")"
            + (position_.inCheck(white: position_.whiteToMove) ? "; \(me) is in check" : "")
    }

    var position: String {
        let letters = Array(".PNBRQK"), diagram = (0..<8).map { row in
            "\(8 - row) " + (0..<8).map { col -> String in
                let piece = position_.board[row * 8 + col], letter = String(letters[Int(abs(piece))])
                return piece < 0 ? letter.lowercased() : letter
            }.joined(separator: " ")
        }.joined(separator: "\n")
        return "FEN: \(position_.fen(move: plies / 2 + 1))\n\(diagram)\n  a b c d e f g h   (uppercase is White)\n"
            + "Moves so far: " + (played.isEmpty ? "none" : played.suffix(24).joined(separator: " "))
    }

    private static let glyphs = ["", "♟", "♞", "♝", "♜", "♛", "♚"]
    var grid: [[JevCell]] {
        (0..<8).map { row in (0..<8).map { col in
            let index = row * 8 + col, piece = position_.board[index]
            if picked == index || targets.contains(index) {
                return JevCell(colour: picked == index ? Color.blue.opacity(0.55) : Color.green.opacity(0.6), text: Self.glyphs[Int(abs(piece))],
                               ink: piece > 0 ? .white : .black, big: true)
            }
            let moved = last.map { $0.from == index || $0.to == index } ?? false
            let base = (row + col) % 2 == 0 ? Color(red: 0.93, green: 0.86, blue: 0.72) : Color(red: 0.62, green: 0.46, blue: 0.32)
            return JevCell(colour: moved ? Color.yellow.opacity(0.75) : base, text: Self.glyphs[Int(abs(piece))],
                           ink: piece > 0 ? .white : .black, big: true)
        } }
    }

    init() { reset(seed: 1) }

    func reset(seed: UInt64) {
        position_ = ChessPosition(); seen = [position_.key: 1]; last = nil; played = []; plies = 0; result = nil; picked = nil
        dice = JevDice(seed: seed)
    }

    func options() -> [JevOption] {
        guard result == nil else { return [] }
        let legal = position_.legalMoves()
        if legal.isEmpty {
            result = position_.inCheck(white: position_.whiteToMove) ? "将死 · \(sides[1 - turn])赢了（\(plies / 2 + 1) 回合）" : "逼和 · 和棋"
            return []
        }
        let judged = legal.map { ($0, position_.outcome(of: $0)) }
        let mine = position_.whiteToMove ? 1 : -1, now = mine * position_.material
        if person {
            // A person may play any legal move, not the shortlist the models choose from.
            moves = legal
            return legal.enumerated().map { index, move in
                JevOption(id: String(format: "p%02d", index + 1), label: describe(move, outcome: judged[index].1, further: nil, now: now),
                          merit: Double(judged[index].1.value), move: index)
            }
        }
        // The shortlist: the evaluator's best eight, then whatever a player is
        // likely to be tempted by and must be allowed to get wrong.
        let depth = self.depth
        var keep = Set(judged.sorted { $0.1.value > $1.1.value }.prefix(depth > 1 ? 5 : 8).map { legal.firstIndex(of: $0.0)! })
        // For a reader the words look further than the evaluator that plays does,
        // and what looks best further on belongs on the list too.
        let further = depth > 1 ? legal.map { position_.foresight(of: $0, plies: depth) } : []
        if depth > 1 {
            for index in further.indices.sorted(by: { further[$0].value > further[$1].value }).prefix(4) { keep.insert(index) }
        }
        func also(_ wanted: (ChessPosition.Move) -> Bool, atMost: Int) {
            for (index, move) in legal.enumerated() where wanted(move) && keep.count < 12 && !keep.contains(index) {
                keep.insert(index)
                if keep.count >= 12 || legal.enumerated().filter({ keep.contains($0.offset) && wanted($0.element) }).count >= atMost { break }
            }
        }
        also({ $0.castle }, atMost: 2)
        also({ position_.board[$0.to] != 0 }, atMost: 4)
        also({ var next = self.position_; next.play($0); return next.inCheck(white: next.whiteToMove) }, atMost: 3)
        var chosen = keep.sorted()                               // in board order, which favours nobody
        if depth > 1 {
            // The program does not ask what it already knows: moves that come out
            // worse in material than another on the list are taken off it, and a
            // forced mate is the only thing offered.
            let sound = chosen.filter { further[$0].value > -1_000_000 }
            let pool = sound.isEmpty ? chosen : sound
            if let mate = pool.first(where: { further[$0].value >= 1_000_000 }) { chosen = [mate] }
            else {
                let top = pool.map { further[$0].material }.max() ?? 0
                chosen = pool.filter { further[$0].material >= top }
            }
        }
        moves = chosen.map { legal[$0] }
        return chosen.enumerated().map { index, which in
            let found = judged[which].1
            return JevOption(id: String(format: "p%02d", index + 1),
                             label: describe(legal[which], outcome: found, further: depth > 1 ? further[which] : nil, now: now),
                             merit: Double(found.value) + Double(dice.below(3)) * 0.001, move: index,
                             insight: depth > 1 ? Double(further[which].value) : nil)
        }
    }

    func play(_ option: JevOption) {
        guard moves.indices.contains(option.move) else { return }
        let move = moves[option.move]
        played.append(ChessPosition.square(move.from) + ChessPosition.square(move.to)
                      + (move.promotion != 0 ? String(Array("pnbrqk")[Int(move.promotion) - 1]) : ""))
        previous = position_.board
        position_.play(move)
        ticked = Date()
        last = move; plies += 1; picked = nil
        seen[position_.key, default: 0] += 1
        if position_.legalMoves().isEmpty {
            result = position_.inCheck(white: position_.whiteToMove) ? "将死 · \(sides[1 - turn])赢了（\((plies + 1) / 2) 回合）" : "逼和 · 和棋"
        } else if seen[position_.key, default: 0] >= 3 { result = "同一局面出现三次 · 和棋"
        } else if position_.halfmoves >= 100 { result = "五十回合没有吃子也没有动兵 · 和棋"
        } else if position_.deadPosition { result = "双方都将不死了 · 和棋"
        } else if plies >= 400 { result = "下满 200 回合 · 和棋" }
    }

    /// One move, in words: what it is, what it does, and how it comes out.
    private func describe(_ move: ChessPosition.Move, outcome: (value: Int, material: Int),
                          further: (value: Int, material: Int)?, now: Int) -> String {
        let depth = self.depth
        let board = position_.board, piece = Int(abs(board[move.from])), white = position_.whiteToMove
        var parts: [String] = []
        if move.castle { parts.append(move.to > move.from ? "castles kingside: king to safety, rook into play" : "castles queenside: king to safety, rook into play") }
        if move.enPassant { parts.append("captures a pawn en passant") }
        else if board[move.to] != 0 { parts.append("captures the \(ChessPosition.names[Int(abs(board[move.to]))])") }
        if move.promotion != 0 { parts.append("promotes to a \(ChessPosition.names[Int(move.promotion)])") }
        var next = position_
        next.play(move)
        if outcome.value >= 1_000_000 { parts.append("checkmate: wins the game at once") }
        else if next.inCheck(white: next.whiteToMove) { parts.append("gives check") }
        let home = white ? 7 : 0, opening = plies < 20
        if (piece == 2 || piece == 3), move.from / 8 == home, move.to / 8 != home { parts.append("develops the \(ChessPosition.names[piece])") }
        if piece == 1, [27, 28, 35, 36].contains(move.to) { parts.append("puts a pawn in the center") }
        if piece == 5, opening, board[move.to] == 0 { parts.append("brings the queen out early") }
        if piece == 6, !move.castle, white ? (position_.castling.wk || position_.castling.wq) : (position_.castling.bk || position_.castling.bq) {
            parts.append("moves the king and gives up castling")
        }
        if seen[next.key, default: 0] >= 1 {
            parts.append("repeats a position that has already occurred" + (seen[next.key, default: 0] >= 2 ? ": the third time, which ends the game as a draw" : ""))
        }
        var outcome = outcome
        var horizon = "after the best reply"
        if let further, outcome.value < 1_000_000, outcome.value > -1_000_000 {
            // What the move is up to, further than the evaluator looks when it chooses for itself.
            let threat = position_.threat(after: move)
            if threat.mate { parts.append("threatens checkmate next move") }
            else if threat.gain >= 1 { parts.append("threatens to win \(threat.gain) in material next move") }
            outcome = further
            horizon = depth == 2 ? "after the best reply and your best answer to it" : "\(depth) moves on, with best play by both sides"
            if outcome.value >= 1_000_000 { parts.append("forces checkmate within \(depth) moves") }
        }
        if outcome.value <= -1_000_000 { parts.append(further != nil ? "allows a forced checkmate: loses the game" : "allows checkmate next move: loses the game") }
        else if outcome.value < 1_000_000 {
            let change = outcome.material - now
            parts.append(change >= 1 ? "\(horizon) comes out \(change) ahead in material"
                         : change <= -1 ? "\(horizon) comes out \(-change) behind in material: it loses material"
                         : "material stays the same \(horizon)")
        }
        return "\(ChessPosition.names[piece]) \(ChessPosition.square(move.from)) to \(ChessPosition.square(move.to)): " + parts.joined(separator: "; ")
    }
}

// MARK: - The picture

extension JevChess: JevPainted {
    var aspect: Double { 1 }

    func picture(t: Double, since: Double, now: Double) -> JevPicture {
        let white = position_.whiteToMove
        let king = position_.inCheck(white: white) ? position_.board.firstIndex(of: white ? 6 : -6) : nil
        let movable = person && king != nil ? Set(moves.map(\.from)) : []
        let scene = ChessScene(board: position_.board, previous: previous, last: last.map { ($0.from, $0.to) }, picked: picked,
                               targets: targets, check: king, movable: movable, t: t, over: over, result: result ?? "")
        return JevPicture { context, size in scene.paint(&context, size) }
    }

    func spot(at point: CGPoint, in size: CGSize) -> (row: Int, col: Int)? {
        let (origin, cell) = ChessScene.geometry(size)
        let col = Int(floor((point.x - origin.x) / cell)), row = Int(floor((point.y - origin.y) / cell))
        guard (0..<8).contains(row), (0..<8).contains(col) else { return nil }
        return (row, col)
    }
}

fileprivate struct ChessScene {
    let board: [Int8], previous: [Int8], last: (from: Int, to: Int)?, picked: Int?, targets: Set<Int>, check: Int?, movable: Set<Int>
    let t: Double, over: Bool, result: String

    static func geometry(_ size: CGSize) -> (origin: CGPoint, cell: CGFloat) {
        let cell = min(size.width, size.height) / 8.9
        return (CGPoint(x: (size.width - 8 * cell) / 2 + cell * 0.2, y: (size.height - 8 * cell) / 2 - cell * 0.2), cell)
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let (origin, cell) = Self.geometry(size)
        func square(_ index: Int) -> CGRect { CGRect(x: origin.x + CGFloat(index % 8) * cell, y: origin.y + CGFloat(index / 8) * cell, width: cell, height: cell) }
        func centre(_ index: Int) -> CGPoint { CGPoint(x: square(index).midX, y: square(index).midY) }
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.2, green: 0.15, blue: 0.11)))
        let frame = CGRect(x: origin.x, y: origin.y, width: 8 * cell, height: 8 * cell)
        g.fill(Path(roundedRect: frame.insetBy(dx: -6, dy: -6), cornerRadius: 6), with: .color(Color(red: 0.36, green: 0.25, blue: 0.16)))
        for index in 0..<64 {
            let light = (index / 8 + index % 8) % 2 == 0
            g.fill(Path(square(index)), with: .color(light ? Color(red: 0.94, green: 0.85, blue: 0.71) : Color(red: 0.71, green: 0.53, blue: 0.39)))
        }
        if let last { for index in [last.from, last.to] { g.fill(Path(square(index)), with: .color(Color(red: 0.95, green: 0.9, blue: 0.2).opacity(0.38))) } }
        if let picked { g.fill(Path(square(picked)), with: .color(Color(red: 0.25, green: 0.5, blue: 0.95).opacity(0.5))) }
        if let check {
            let p = centre(check)
            g.fill(Path(square(check)), with: .radialGradient(Gradient(colors: [Color.red.opacity(0.9), Color.red.opacity(0)]), center: p, startRadius: 0, endRadius: cell * 0.7))
        }
        let ink = Color(white: 0.9)
        for k in 0..<8 {
            JevDraw.text(g, String("abcdefgh"[String.Index(utf16Offset: k, in: "abcdefgh")]), at: CGPoint(x: origin.x + (CGFloat(k) + 0.5) * cell, y: frame.maxY + cell * 0.3),
                         size: cell * 0.24, weight: .semibold, colour: ink, shadow: false)
            JevDraw.text(g, "\(8 - k)", at: CGPoint(x: origin.x - cell * 0.3, y: origin.y + (CGFloat(k) + 0.5) * cell), size: cell * 0.24, weight: .semibold, colour: ink, shadow: false)
        }
        // Mid-move the board is the one before it, the piece on its way.
        let moving = last != nil && t < 1
        let shown = moving ? previous : board
        for index in 0..<64 where shown[index] != 0 {
            if moving, let last {
                if index == last.from { continue }
                if index == last.to { piece(g, shown[index], at: centre(index), cell: cell, alpha: 1 - t); continue }
            }
            piece(g, shown[index], at: centre(index), cell: cell)
        }
        if moving, let last {
            let from = centre(last.from), to = centre(last.to), e = JevDraw.smooth(t)
            piece(g, previous[last.from], at: CGPoint(x: JevDraw.mix(Double(from.x), Double(to.x), e), y: JevDraw.mix(Double(from.y), Double(to.y), e)), cell: cell)
        }
        for index in movable where index != picked {
            g.stroke(Path(roundedRect: square(index).insetBy(dx: 2, dy: 2), cornerRadius: 4), with: .color(Color(red: 0.1, green: 0.7, blue: 0.3)), lineWidth: 3)
        }
        for target in targets {
            let p = centre(target)
            if board[target] != 0 {
                g.stroke(Path(ellipseIn: CGRect(x: p.x - cell * 0.44, y: p.y - cell * 0.44, width: cell * 0.88, height: cell * 0.88)), with: .color(.black.opacity(0.3)), lineWidth: cell * 0.08)
            } else {
                g.fill(Path(ellipseIn: CGRect(x: p.x - cell * 0.15, y: p.y - cell * 0.15, width: cell * 0.3, height: cell * 0.3)), with: .color(.black.opacity(0.25)))
            }
        }
        if over { JevDraw.curtain(g, size, title: result.components(separatedBy: " · ").first ?? result, detail: result.components(separatedBy: " · ").dropFirst().joined(separator: " · ")) }
    }

    /// A piece: the solid glyph, filled white or black and outlined in the other.
    private func piece(_ g: GraphicsContext, _ piece: Int8, at p: CGPoint, cell: CGFloat, alpha: Double = 1) {
        let glyph = ["", "♟", "♞", "♝", "♜", "♛", "♚"][Int(abs(piece))] + "\u{FE0E}"
        let white = piece > 0, font = Font.system(size: cell * 0.78)
        let edge = white ? Color(white: 0.12).opacity(alpha) : Color(white: 0.95).opacity(0.7 * alpha)
        g.draw(Text(glyph).font(font).foregroundColor(.black.opacity(0.3 * alpha)), at: CGPoint(x: p.x + 2, y: p.y + 3))
        for (dx, dy) in [(-1.2, 0.0), (1.2, 0), (0, -1.2), (0, 1.2), (-0.9, -0.9), (0.9, 0.9), (-0.9, 0.9), (0.9, -0.9)] {
            g.draw(Text(glyph).font(font).foregroundColor(edge), at: CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy)))
        }
        g.draw(Text(glyph).font(font).foregroundColor(white ? Color(white: 0.98).opacity(alpha) : Color(white: 0.1).opacity(alpha)), at: p)
    }
}
