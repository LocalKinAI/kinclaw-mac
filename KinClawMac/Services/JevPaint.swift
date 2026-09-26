import SwiftUI

/// Games that draw a picture rather than a grid of squares.
///
/// A game still moves a tick at a time — that is what a question is — but the
/// picture does not: it is drawn sixty times a second, `t` of the way from the
/// state before the last tick to the state after it, so a car slides into the
/// next lane and a bird arcs instead of hopping from square to square.

/// One moment of a game, ready to be drawn. The closure holds copies of the
/// game's state, so it can be drawn wherever the Canvas draws.
struct JevPicture {
    let paint: (inout GraphicsContext, CGSize) -> Void
}

@MainActor
protocol JevPainted: AnyObject {
    /// Width over height.
    var aspect: Double { get }
    /// When the last tick came: the picture glides from the state before it.
    var ticked: Date { get }
    /// The picture `t` (0…1) of the way through the last tick. `since` is the
    /// time since that tick, for what moves by itself — a flame, an explosion.
    func picture(t: Double, since: Double, now: Double) -> JevPicture
    /// The square or point of the board under a click, for a game played by clicking.
    func spot(at point: CGPoint, in size: CGSize) -> (row: Int, col: Int)?
}

extension JevPainted {
    func spot(at point: CGPoint, in size: CGSize) -> (row: Int, col: Int)? { nil }
}

enum JevDraw {
    /// Ease in and out.
    static func smooth(_ t: Double) -> Double { let x = min(max(t, 0), 1); return x * x * (3 - 2 * x) }
    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// A number that looks random and is the same every time for the same inputs.
    static func hash(_ a: Int, _ b: Int) -> Int {
        var h = UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15 ^ UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F
        h ^= h >> 29; h &*= 0xBF58476D1CE4E5B9; h ^= h >> 32
        return Int(h % 1_000_003)
    }

    /// A colour, lighter (k > 1) or darker (k < 1).
    static func shade(_ rgb: (Double, Double, Double), _ k: Double) -> Color {
        func c(_ v: Double) -> Double { k >= 1 ? v + (1 - v) * (k - 1) : v * k }
        return Color(red: c(rgb.0), green: c(rgb.1), blue: c(rgb.2))
    }

    /// Text centred on a point, with a shadow so it reads on anything.
    static func text(_ g: GraphicsContext, _ text: String, at point: CGPoint, size: CGFloat, weight: Font.Weight = .heavy,
                     colour: Color = .white, anchor: UnitPoint = .center, shadow: Bool = true) {
        let font = Font.system(size: size, weight: weight, design: .rounded)
        if shadow {
            g.draw(Text(text).font(font).foregroundColor(.black.opacity(0.55)),
                   at: CGPoint(x: point.x + size * 0.06, y: point.y + size * 0.08), anchor: anchor)
        }
        g.draw(Text(text).font(font).foregroundColor(colour), at: point, anchor: anchor)
    }

    /// A rounded panel for numbers over the picture.
    static func panel(_ g: GraphicsContext, _ rect: CGRect) {
        g.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(.black.opacity(0.38)))
        g.stroke(Path(roundedRect: rect, cornerRadius: 10), with: .color(.white.opacity(0.18)), lineWidth: 1)
    }

    /// A fireball: a flash, rings of fire and smoke, growing and fading over `age` seconds.
    static func blast(_ g: GraphicsContext, at p: CGPoint, size: CGFloat, age: Double) {
        let a = min(max(age, 0), 1.2)
        let grow = CGFloat(1 - pow(1 - min(a / 0.6, 1), 3))
        let fade = max(0, 1 - a / 1.2)
        func disc(_ r: CGFloat, _ colour: Color) {
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(colour))
        }
        disc(size * (0.5 + 1.3 * grow), Color(white: 0.25).opacity(0.45 * fade))
        disc(size * (0.4 + 1.0 * grow), Color(red: 0.85, green: 0.2, blue: 0.05).opacity(0.8 * fade))
        disc(size * (0.3 + 0.7 * grow), Color(red: 1, green: 0.55, blue: 0.1).opacity(0.9 * fade))
        disc(size * (0.2 + 0.35 * grow), Color(red: 1, green: 0.95, blue: 0.6).opacity(fade))
        for spark in 0..<10 {
            let angle = Double(spark) * 0.628 + Double(hash(spark, 7) % 100) / 100
            let reach = size * (0.4 + 1.6 * grow) * CGFloat(0.7 + Double(hash(spark, 3) % 30) / 100)
            let q = CGPoint(x: p.x + CGFloat(cos(angle)) * reach, y: p.y + CGFloat(sin(angle)) * reach)
            g.fill(Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)), with: .color(Color(red: 1, green: 0.75, blue: 0.25).opacity(fade)))
        }
    }

    /// The end of a game, over the picture.
    static func curtain(_ g: GraphicsContext, _ size: CGSize, title: String, detail: String) {
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.42)))
        text(g, title, at: CGPoint(x: size.width / 2, y: size.height * 0.42), size: min(size.width, size.height) * 0.11)
        text(g, detail, at: CGPoint(x: size.width / 2, y: size.height * 0.52), size: min(size.width, size.height) * 0.05, weight: .bold)
    }
}
