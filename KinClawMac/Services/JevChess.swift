import SwiftUI
import CoreText

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

/// Walnut and maple squares in a raised walnut frame with the coordinates cut into it in gold, and
/// pieces cut from a font's chess glyphs, turned in ivory and ebony.
fileprivate struct ChessScene {
    let board: [Int8], previous: [Int8], last: (from: Int, to: Int)?, picked: Int?, targets: Set<Int>, check: Int?, movable: Set<Int>
    let t: Double, over: Bool, result: String

    /// How wide the frame round the squares is, in squares.
    static let rim: CGFloat = 0.5

    static func geometry(_ size: CGSize) -> (origin: CGPoint, cell: CGFloat) {
        let cell = min(size.width, size.height) / (8 + 2 * rim)
        return (CGPoint(x: (size.width - 8 * cell) / 2, y: (size.height - 8 * cell) / 2), cell)
    }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let (origin, cell) = Self.geometry(size)
        let field = CGRect(x: origin.x, y: origin.y, width: 8 * cell, height: 8 * cell)
        func square(_ index: Int) -> CGRect { CGRect(x: origin.x + CGFloat(index % 8) * cell, y: origin.y + CGFloat(index / 8) * cell, width: cell, height: cell) }
        func centre(_ index: Int) -> CGPoint { CGPoint(x: square(index).midX, y: square(index).midY) }

        ChessArt.frame(g, size: size, field: field, cell: cell)
        ChessArt.squares(g, field: field, cell: cell)
        if let last {
            g.fill(Path(square(last.from)), with: .color(ChessArt.amber.opacity(0.30)))
            g.fill(Path(square(last.to)), with: .color(ChessArt.amber.opacity(0.44)))
        }
        if let picked { g.fill(Path(square(picked)), with: .color(ChessArt.chosen.opacity(0.55))) }
        ChessArt.surface(g, field: field, cell: cell)
        if let check {
            let p = centre(check)
            g.fill(Path(square(check)), with: .radialGradient(Gradient(stops: [.init(color: Color(red: 1, green: 0.2, blue: 0.1).opacity(0.95), location: 0),
                                                                              .init(color: Color(red: 0.9, green: 0.08, blue: 0.04).opacity(0.55), location: 0.55),
                                                                              .init(color: Color(red: 0.8, green: 0, blue: 0).opacity(0), location: 1)]),
                                                            center: p, startRadius: 0, endRadius: cell * 0.74))
        }
        // Mid-move the board is the one before it, the piece on its way.
        let moving = last != nil && t < 1
        let shown = moving ? previous : board
        var standing: [(piece: Int8, at: CGPoint)] = []
        var fading: (piece: Int8, at: CGPoint)?
        for index in 0..<64 where shown[index] != 0 {
            if moving, let last {
                if index == last.from { continue }
                if index == last.to { fading = (shown[index], centre(index)); continue }
            }
            standing.append((shown[index], centre(index)))
        }
        ChessArt.shadows(g, standing, cell: cell)
        for one in standing { ChessArt.piece(g, one.piece, at: one.at, cell: cell) }
        if let fading {
            g.drawLayer { layer in
                layer.opacity = 1 - t
                ChessArt.shadows(layer, [fading], cell: cell)
                ChessArt.piece(layer, fading.piece, at: fading.at, cell: cell)
            }
        }
        if moving, let last {
            let from = centre(last.from), to = centre(last.to), e = JevDraw.smooth(t)
            let at = CGPoint(x: JevDraw.mix(Double(from.x), Double(to.x), e), y: JevDraw.mix(Double(from.y), Double(to.y), e))
            let lift = CGFloat(sin(Double.pi * e))
            ChessArt.shadows(g, [(previous[last.from], at)], cell: cell, lift: lift)
            ChessArt.piece(g, previous[last.from], at: at, cell: cell, lift: lift)
        }
        for index in movable where index != picked {
            g.stroke(Path(roundedRect: square(index).insetBy(dx: 2.5, dy: 2.5), cornerRadius: cell * 0.08),
                     with: .color(ChessArt.chosen.opacity(0.95)), lineWidth: max(2, cell * 0.045))
        }
        for target in targets {
            let p = centre(target)
            if board[target] != 0 {
                let r = cell * 0.46
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(ChessArt.chosen.opacity(0.85)), lineWidth: cell * 0.07)
            } else {
                let r = cell * 0.15
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .radialGradient(Gradient(colors: [ChessArt.chosen.opacity(0.9), ChessArt.chosen.opacity(0.7)]), center: p, startRadius: 0, endRadius: r))
            }
        }
        if over { JevDraw.curtain(g, size, title: result.components(separatedBy: " · ").first ?? result, detail: result.components(separatedBy: " · ").dropFirst().joined(separator: " · ")) }
    }
}

/// The board's woods and the pieces' shapes, worked out once.
fileprivate enum ChessArt {
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.24)
    static let chosen = Color(red: 0.16, green: 0.52, blue: 0.36)
    static let maple: (Double, Double, Double) = (0.93, 0.81, 0.62)
    static let walnut: (Double, Double, Double) = (0.52, 0.32, 0.19)
    static let frameWood: (Double, Double, Double) = (0.4, 0.22, 0.115)

    /// Wood lit more (k > 1) or less: brighter or darker without going grey.
    static func wood(_ rgb: (Double, Double, Double), _ k: Double) -> Color {
        Color(red: min(1, rgb.0 * k), green: min(1, rgb.1 * k), blue: min(1, rgb.2 * k))
    }

    // MARK: Glyphs

    /// The first of these fonts that is installed.
    static func font(_ names: [String], size: CGFloat) -> CTFont? {
        for name in names {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            if CTFontCopyPostScriptName(font) as String == name { return font }
        }
        return nil
    }

    /// One character's outline, y up, as the font has it.
    static func outline(_ font: CTFont, _ character: UniChar) -> CGPath? {
        var character = character, glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), glyph != 0 else { return nil }
        return CTFontCreatePathForGlyph(font, glyph, nil)
    }

    /// An outline's contours, each with its signed area: the outer edge goes one way round, the holes in it the other.
    static func contours(_ path: CGPath) -> [(path: CGPath, area: CGFloat)] {
        var result: [(path: CGPath, area: CGFloat)] = []
        var current = CGMutablePath(), points: [CGPoint] = []
        func finish() {
            guard points.count > 2 else { return }
            var area: CGFloat = 0
            for k in points.indices {
                let a = points[k], b = points[(k + 1) % points.count]
                area += a.x * b.y - b.x * a.y
            }
            result.append((current, area / 2))
        }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                finish(); current = CGMutablePath(); points = [e.points[0]]; current.move(to: e.points[0])
            case .addLineToPoint:
                current.addLine(to: e.points[0]); points.append(e.points[0])
            case .addQuadCurveToPoint:
                current.addQuadCurve(to: e.points[1], control: e.points[0]); points += [e.points[0], e.points[1]]
            case .addCurveToPoint:
                current.addCurve(to: e.points[2], control1: e.points[0], control2: e.points[1]); points += [e.points[0], e.points[1], e.points[2]]
            case .closeSubpath:
                current.closeSubpath()
            @unknown default:
                break
            }
        }
        finish()
        return result
    }

    /// A piece's shape, one square to the unit, centred on x = 0 and standing on y = 0.
    struct Figure {
        /// The solid glyph, its detail lines cut out of it.
        var body = Path()
        /// Its outer edge alone.
        var silhouette = Path()
        /// The detail lines, as shapes of their own.
        var lines = Path()
        /// The outlined glyph: a white piece's lines.
        var drawn = Path()
        var width: CGFloat = 0.5
    }

    /// The six pieces, the king standing 0.8 of a square tall; empty if no font has them.
    static let figures: [Figure]? = {
        guard let font = font(["ArialUnicodeMS", "AppleSymbols", "Menlo-Regular"], size: 100), let king = outline(font, 0x265A) else { return nil }
        let scale = 0.8 / king.boundingBox.height
        var figures = [Figure](repeating: Figure(), count: 7)
        for kind in 1...6 {
            guard let solid = outline(font, UniChar(0x2660 - kind)), let open = outline(font, UniChar(0x265A - kind)) else { return nil }
            let box = solid.boundingBox
            let place = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: -box.midX * scale, ty: box.minY * scale)
            var figure = Figure(body: Path(solid).applying(place), drawn: Path(open).applying(place), width: box.width * scale)
            let parts = contours(solid)
            let outer = parts.max { abs($0.area) < abs($1.area) }?.area ?? 1
            for part in parts {
                if (part.area > 0) == (outer > 0) { figure.silhouette.addPath(Path(part.path), transform: place) }
                else { figure.lines.addPath(Path(part.path), transform: place) }
            }
            figures[kind] = figure
        }
        return figures
    }()

    /// The coordinates, each centred on (0, 0), one point of type to the unit: a to h, then 8 down to 1.
    static let labels: [Path] = {
        guard let font = font(["Baskerville-SemiBold", "Palatino-Bold", "Georgia-Bold"], size: 100) else { return [] }
        let x = CTFontGetXHeight(font), cap = CTFontGetCapHeight(font)
        return ("abcdefgh".unicodeScalars.map { ($0, x) } + "87654321".unicodeScalars.map { ($0, cap) }).map { scalar, height in
            guard let glyph = outline(font, UniChar(scalar.value)) else { return Path() }
            let box = glyph.boundingBox
            return Path(glyph).applying(CGAffineTransform(a: 0.01, b: 0, c: 0, d: -0.01, tx: -box.midX * 0.01, ty: height / 2 * 0.01))
        }
    }()

    // MARK: Wood

    /// A strand of grain: where it runs, its colour, and how wide it is (in squares).
    struct Strand { let path: Path, colour: Color, width: CGFloat }

    /// The squares' grain, eight squares to the board: along the rank on the maple, along the file on the walnut,
    /// each square cut a little askew, its growth lines bunched, with broad bands of lighter and darker wood.
    static let squareGrain: [Strand] = {
        var paths = [Path](repeating: Path(), count: 8)
        for index in 0..<64 {
            let row = CGFloat(index / 8), col = CGFloat(index % 8), light = (index / 8 + index % 8) % 2 == 0
            let tilt = (CGFloat(JevDraw.hash(index, 3) % 100) / 100 - 0.5) * 0.1
            func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
                let a = min(max(across + tilt * (along - 0.5), 0.015), 0.985)
                return light ? CGPoint(x: col + along, y: row + a) : CGPoint(x: col + a, y: row + along)
            }
            func strand(_ across: CGFloat, _ seed: Int) -> Path {
                let bow = (CGFloat(seed % 100) / 100 - 0.5) * (light ? 0.05 : 0.09)
                var p = Path()
                p.move(to: at(0, across))
                p.addCurve(to: at(1, across + bow * 0.3), control1: at(0.35, across + bow), control2: at(0.7, across - bow * 0.7))
                return p
            }
            let base = light ? 4 : 0
            for k in 0..<3 {
                let h = JevDraw.hash(index * 7 + k, 211)
                paths[base + 2 + h % 2].addPath(strand(0.12 + 0.76 * CGFloat(h / 2 % 100) / 100, h / 200))
            }
            var across = 0.02 + CGFloat(JevDraw.hash(index, 9) % 10) / 100, k = 0
            while across < 0.97 {
                let h = JevDraw.hash(index * 31 + k, 223)
                paths[base + (h % 4 == 0 ? 1 : 0)].addPath(strand(across, h / 4))
                across += 0.025 + CGFloat(h / 400 % 100) / 100 * (h % 3 == 0 ? 0.22 : 0.06)
                k += 1
            }
        }
        let dark = Color(red: 0.18, green: 0.09, blue: 0.04), late = Color(red: 0.6, green: 0.4, blue: 0.2)
        return [Strand(path: paths[0], colour: dark.opacity(0.22), width: 0.009), Strand(path: paths[1], colour: dark.opacity(0.38), width: 0.02),
                Strand(path: paths[2], colour: dark.opacity(0.1), width: 0.16), Strand(path: paths[3], colour: Color(red: 0.9, green: 0.62, blue: 0.4).opacity(0.1), width: 0.13),
                Strand(path: paths[4], colour: late.opacity(0.16), width: 0.008), Strand(path: paths[5], colour: late.opacity(0.26), width: 0.016),
                Strand(path: paths[6], colour: late.opacity(0.08), width: 0.17), Strand(path: paths[7], colour: Color.white.opacity(0.16), width: 0.13)]
    }()

    /// Long grain for a strip of frame, 0…1 along it and 0…1 across it.
    static let stripGrain: [Strand] = {
        var fine = Path(), bold = Path(), light = Path()
        var across: CGFloat = 0.03, k = 0
        while across < 0.98 {
            let h = JevDraw.hash(k, 313)
            var p = Path()
            let wave = (CGFloat(h / 60 % 100) / 100 - 0.5) * 0.3, phase = CGFloat(h % 60) / 60
            p.move(to: CGPoint(x: -0.02, y: across))
            p.addCurve(to: CGPoint(x: 0.5, y: across + wave * 0.2), control1: CGPoint(x: 0.12 + 0.1 * phase, y: across + wave), control2: CGPoint(x: 0.3, y: across - wave * 0.5))
            p.addCurve(to: CGPoint(x: 1.02, y: across), control1: CGPoint(x: 0.7, y: across + wave * 0.6), control2: CGPoint(x: 0.85 - 0.1 * phase, y: across - wave))
            if h % 5 == 0 { light.addPath(p) } else if h % 3 == 0 { bold.addPath(p) } else { fine.addPath(p) }
            across += 0.04 + CGFloat(h / 6000 % 100) / 100 * 0.09
            k += 1
        }
        return [Strand(path: fine, colour: Color.black.opacity(0.26), width: 0.01), Strand(path: bold, colour: Color.black.opacity(0.34), width: 0.028),
                Strand(path: light, colour: Color(red: 1, green: 0.78, blue: 0.55).opacity(0.13), width: 0.035)]
    }()

    // MARK: Painting

    /// The table, and the raised frame with the coordinates cut into it.
    static func frame(_ g: GraphicsContext, size: CGSize, field: CGRect, cell: CGFloat) {
        let outer = CGRect(origin: .zero, size: size), corner = min(size.width, size.height) * 0.022
        g.fill(Path(outer), with: .color(Color(red: 0.08, green: 0.06, blue: 0.045)))
        var c = g
        c.clip(to: Path(roundedRect: outer, cornerRadius: corner))
        // Four mitred sides, lit as a raised moulding is lit from the top left: each runs from its outer edge in to the squares.
        let o = outer, f = field
        let sides: [(corners: [CGPoint], light: Double, along: Bool, outside: CGPoint, inside: CGPoint)] = [
            ([CGPoint(x: o.minX, y: o.minY), CGPoint(x: o.maxX, y: o.minY), CGPoint(x: f.maxX, y: f.minY), CGPoint(x: f.minX, y: f.minY)], 1.2, true,
             CGPoint(x: 0, y: o.minY), CGPoint(x: 0, y: f.minY)),
            ([CGPoint(x: o.minX, y: o.maxY), CGPoint(x: o.maxX, y: o.maxY), CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)], 0.8, true,
             CGPoint(x: 0, y: o.maxY), CGPoint(x: 0, y: f.maxY)),
            ([CGPoint(x: o.minX, y: o.minY), CGPoint(x: o.minX, y: o.maxY), CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.minX, y: f.minY)], 1.05, false,
             CGPoint(x: o.minX, y: 0), CGPoint(x: f.minX, y: 0)),
            ([CGPoint(x: o.maxX, y: o.minY), CGPoint(x: o.maxX, y: o.maxY), CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.maxX, y: f.minY)], 0.88, false,
             CGPoint(x: o.maxX, y: 0), CGPoint(x: f.maxX, y: 0))]
        for side in sides {
            let shape = Path { p in p.addLines(side.corners); p.closeSubpath() }
            let box = shape.boundingRect
            var s = c
            s.clip(to: shape)
            let k = side.light
            s.fill(Path(box), with: .linearGradient(Gradient(stops: [.init(color: wood(frameWood, 0.62 * k), location: 0), .init(color: wood(frameWood, 1.5 * k), location: 0.2),
                                                                     .init(color: wood(frameWood, 1.12 * k), location: 0.46), .init(color: wood(frameWood, 0.92 * k), location: 0.8),
                                                                     .init(color: wood(frameWood, 0.6 * k), location: 1)]),
                                                   startPoint: side.outside, endPoint: side.inside))
            let place = side.along ? CGAffineTransform(a: box.width, b: 0, c: 0, d: box.height, tx: box.minX, ty: box.minY)
                                   : CGAffineTransform(a: 0, b: box.height, c: box.width, d: 0, tx: box.minX, ty: box.minY)
            for strand in stripGrain { s.stroke(strand.path.applying(place), with: .color(strand.colour), lineWidth: strand.width * cell) }
        }
        // The mitres.
        var mitres = Path()
        for (a, b) in [(CGPoint(x: outer.minX, y: outer.minY), CGPoint(x: field.minX, y: field.minY)), (CGPoint(x: outer.maxX, y: outer.minY), CGPoint(x: field.maxX, y: field.minY)),
                       (CGPoint(x: outer.minX, y: outer.maxY), CGPoint(x: field.minX, y: field.maxY)), (CGPoint(x: outer.maxX, y: outer.maxY), CGPoint(x: field.maxX, y: field.maxY))] {
            mitres.move(to: a); mitres.addLine(to: b)
        }
        c.stroke(mitres, with: .color(Color.black.opacity(0.35)), lineWidth: 0.8)
        // The outer edge catches the light at the top left.
        c.stroke(Path(roundedRect: outer.insetBy(dx: 1, dy: 1), cornerRadius: corner - 1),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.06), Color.black.opacity(0.35)]),
                                       startPoint: outer.origin, endPoint: CGPoint(x: outer.maxX, y: outer.maxY)), lineWidth: 1.6)
        // A gold inlay round the squares, and the frame's inner edge stepping down to them.
        let inlay = field.insetBy(dx: -cell * 0.1, dy: -cell * 0.1)
        c.stroke(Path(inlay), with: .color(Color.black.opacity(0.35)), lineWidth: 2.6)
        c.stroke(Path(inlay), with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.52), Color(red: 0.72, green: 0.52, blue: 0.24), Color(red: 0.93, green: 0.76, blue: 0.43)]),
                                                   startPoint: inlay.origin, endPoint: CGPoint(x: inlay.maxX, y: inlay.maxY)), lineWidth: 1.2)
        let lip = field.insetBy(dx: -1.5, dy: -1.5)
        c.stroke(Path(lip), with: .linearGradient(Gradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.3), Color.white.opacity(0.22)]),
                                                 startPoint: lip.origin, endPoint: CGPoint(x: lip.maxX, y: lip.maxY)), lineWidth: 3)
        // The coordinates, cut in and gilded.
        guard labels.count == 16 else { return }
        let type = cell * 0.3, band = (field.minY - outer.minY) / 2
        // One fill each: small type merged into one long path comes out with its curves coarsely cut.
        let gold = Gradient(colors: [Color(red: 0.98, green: 0.86, blue: 0.58), Color(red: 0.78, green: 0.58, blue: 0.3)])
        for k in 0..<16 {
            let at = k < 8 ? CGPoint(x: field.minX + (CGFloat(k) + 0.5) * cell, y: field.maxY + band) : CGPoint(x: field.minX - band, y: field.minY + (CGFloat(k - 8) + 0.5) * cell)
            let mark = labels[k].applying(CGAffineTransform(a: type, b: 0, c: 0, d: type, tx: at.x, ty: at.y))
            c.fill(mark.applying(CGAffineTransform(translationX: 0.7, y: 0.9)), with: .color(Color(red: 1, green: 0.85, blue: 0.62).opacity(0.28)))
            c.fill(mark.applying(CGAffineTransform(translationX: -0.5, y: -0.6)), with: .color(Color.black.opacity(0.6)))
            c.fill(mark, with: .linearGradient(gold, startPoint: CGPoint(x: 0, y: at.y - type * 0.4), endPoint: CGPoint(x: 0, y: at.y + type * 0.4)))
        }
    }

    /// Sixty-four squares of maple and walnut, each its own piece of wood.
    static func squares(_ g: GraphicsContext, field: CGRect, cell: CGFloat) {
        for index in 0..<64 {
            let row = index / 8, col = index % 8, light = (row + col) % 2 == 0
            let rect = CGRect(x: field.minX + CGFloat(col) * cell, y: field.minY + CGFloat(row) * cell, width: cell, height: cell)
            let tone = Double(JevDraw.hash(index, 5) % 100) / 100 - 0.5
            let base = light ? maple : walnut
            g.fill(Path(rect), with: .linearGradient(Gradient(colors: [wood(base, 1.03 + 0.07 * tone), wood(base, 0.95 + 0.07 * tone)]),
                                                     startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        }
        let place = CGAffineTransform(a: cell, b: 0, c: 0, d: cell, tx: field.minX, ty: field.minY)
        for strand in squareGrain { g.stroke(strand.path.applying(place), with: .color(strand.colour), lineWidth: strand.width * cell) }
    }

    /// The varnish over the squares, and the frame's shadow on them along the top and the left.
    static func surface(_ g: GraphicsContext, field: CGRect, cell: CGFloat) {
        g.fill(Path(field), with: .linearGradient(Gradient(stops: [.init(color: Color.white.opacity(0.12), location: 0), .init(color: Color.white.opacity(0), location: 0.42),
                                                                   .init(color: Color.black.opacity(0), location: 0.6), .init(color: Color.black.opacity(0.14), location: 1)]),
                                                  startPoint: field.origin, endPoint: CGPoint(x: field.maxX, y: field.maxY)))
        let fall = cell * 0.16
        g.fill(Path(CGRect(x: field.minX, y: field.minY, width: field.width, height: fall)),
               with: .linearGradient(Gradient(colors: [Color.black.opacity(0.4), Color.black.opacity(0)]), startPoint: CGPoint(x: 0, y: field.minY), endPoint: CGPoint(x: 0, y: field.minY + fall)))
        g.fill(Path(CGRect(x: field.minX, y: field.minY, width: fall, height: field.height)),
               with: .linearGradient(Gradient(colors: [Color.black.opacity(0.32), Color.black.opacity(0)]), startPoint: CGPoint(x: field.minX, y: 0), endPoint: CGPoint(x: field.minX + fall, y: 0)))
    }

    /// Where a piece standing on the square centred at `p` has its base, and how big it is drawn.
    static func stand(_ g: GraphicsContext, at p: CGPoint, cell: CGFloat, lift: CGFloat) -> GraphicsContext {
        var c = g
        c.translateBy(x: p.x, y: p.y + cell * (0.4 - 0.1 * lift))
        c.scaleBy(x: cell * (1 + 0.08 * lift), y: cell * (1 + 0.08 * lift))
        return c
    }

    /// The pieces' shadows, blurred together: cast down and to the right, and dark where each stands.
    static func shadows(_ g: GraphicsContext, _ pieces: [(piece: Int8, at: CGPoint)], cell: CGFloat, lift: CGFloat = 0) {
        guard let figures else { return }
        for one in pieces {
            let w = figures[Int(abs(one.piece))].width * cell * 0.62, base = CGPoint(x: one.at.x + cell * 0.03, y: one.at.y + cell * 0.4)
            g.fill(Path(ellipseIn: CGRect(x: base.x - w, y: base.y - cell * 0.07, width: 2 * w, height: cell * 0.14)),
                   with: .radialGradient(Gradient(colors: [Color.black.opacity(0.45 * Double(1 - lift)), Color.black.opacity(0)]), center: base, startRadius: 0, endRadius: w))
        }
        var soft = g
        soft.addFilter(.blur(radius: cell * (0.035 + 0.05 * lift)))
        soft.drawLayer { layer in
            for one in pieces {
                var c = stand(layer, at: CGPoint(x: one.at.x + cell * (0.05 + 0.12 * lift), y: one.at.y + cell * (0.03 + 0.2 * lift)), cell: cell, lift: 0)
                c.scaleBy(x: 1, y: 0.94)
                c.fill(figures[Int(abs(one.piece))].silhouette, with: .color(Color.black.opacity(0.42 - 0.12 * Double(lift))))
            }
        }
    }

    static let ivory = Gradient(stops: [.init(color: Color(red: 1, green: 0.995, blue: 0.97), location: 0), .init(color: Color(red: 0.97, green: 0.93, blue: 0.83), location: 0.5),
                                        .init(color: Color(red: 0.8, green: 0.7, blue: 0.53), location: 1)])
    static let ebony = Gradient(stops: [.init(color: Color(red: 0.45, green: 0.41, blue: 0.38), location: 0), .init(color: Color(red: 0.18, green: 0.16, blue: 0.15), location: 0.42),
                                        .init(color: Color(red: 0.04, green: 0.035, blue: 0.03), location: 1)])

    /// A piece standing on the square centred at `p`: ivory with its lines drawn in, or ebony with its lines picked out.
    static func piece(_ g: GraphicsContext, _ piece: Int8, at p: CGPoint, cell: CGFloat, lift: CGFloat = 0) {
        let white = piece > 0
        guard let figures else {
            let glyph = ["", "♟", "♞", "♝", "♜", "♛", "♚"][Int(abs(piece))] + "\u{FE0E}"
            g.draw(Text(glyph).font(.system(size: cell * 0.9)).foregroundColor(white ? .white : .black), at: p)
            return
        }
        let figure = figures[Int(abs(piece))]
        let c = stand(g, at: p, cell: cell, lift: lift)
        let from = CGPoint(x: -0.3, y: -0.78), to = CGPoint(x: 0.28, y: 0)
        if white {
            c.fill(figure.silhouette, with: .linearGradient(ivory, startPoint: from, endPoint: to))
            sheen(c, figure, strength: 0.7)
            c.fill(figure.drawn, with: .color(Color(red: 0.15, green: 0.11, blue: 0.08)))
        } else {
            c.fill(figure.lines, with: .color(Color(red: 0.82, green: 0.76, blue: 0.66)))
            c.fill(figure.body, with: .linearGradient(ebony, startPoint: from, endPoint: to))
            sheen(c, figure, strength: 0.3)
            c.stroke(figure.silhouette, with: .color(Color.black.opacity(0.8)), lineWidth: 0.012)
        }
    }

    /// Light falling on the upper left of a piece.
    static func sheen(_ c: GraphicsContext, _ figure: Figure, strength: Double) {
        var lit = c
        lit.clip(to: figure.silhouette)
        let centre = CGPoint(x: -0.16, y: -0.5)
        lit.fill(Path(ellipseIn: CGRect(x: centre.x - 0.3, y: centre.y - 0.42, width: 0.6, height: 0.84)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(strength), Color.white.opacity(0)]), center: centre, startRadius: 0, endRadius: 0.36))
    }
}
