import AppKit
import SwiftUI

/// The page's measure: 1 at 1200 points wide, growing with the window up to 1.7 and down to 0.8 for a small one.
enum WallScale {
    static func k(_ size: CGSize) -> CGFloat { min(1.7, max(0.8, min(size.width / 1200, size.height / 620))) }
}

/// Dark lacquer glass, edged in gold, that everything over the field sits on.
struct WallGlass: ViewModifier {
    var k: CGFloat
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius * k).fill(LinearGradient(colors: [Color(red: 0.26, green: 0.14, blue: 0.11).opacity(0.9), Color(red: 0.13, green: 0.07, blue: 0.06).opacity(0.92)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: radius * k).stroke(LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.5).opacity(0.55), Color(red: 1, green: 0.8, blue: 0.4).opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, 1.1 * k)))
            .compositingGroup()
            .shadow(color: .black.opacity(0.3), radius: 8 * k, y: 3 * k)
    }
}

extension View {
    func wallGlass(_ k: CGFloat, radius: CGFloat = 14) -> some View { modifier(WallGlass(k: k, radius: radius)) }
}

/// A key on the keyboard, drawn as a little cap.
struct WallKey: View {
    var text: String
    var k: CGFloat
    var body: some View {
        Text(text).font(.system(size: 10.5 * k, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.3, green: 0.16, blue: 0.1))
            .padding(.horizontal, 4.5 * k).frame(minWidth: 18 * k, minHeight: 17 * k)
            .background(RoundedRectangle(cornerRadius: 5 * k).fill(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.9), Color(red: 0.92, green: 0.84, blue: 0.7)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 5 * k).stroke(Color.black.opacity(0.25), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1.2 * k)
    }
}

/// A gold coin, painted.
struct WallCoin: View, Equatable {
    var body: some View {
        Canvas { g, size in
            let s = min(size.width, size.height), r = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
            g.fill(Path(ellipseIn: r), with: .color(Color(red: 0.8, green: 0.55, blue: 0.12)))
            g.fill(Path(ellipseIn: r.insetBy(dx: s * 0.08, dy: s * 0.08)), with: .color(Color(red: 1, green: 0.8, blue: 0.3)))
            g.fill(Path(CGRect(x: r.midX - s * 0.13, y: r.midY - s * 0.13, width: s * 0.26, height: s * 0.26)), with: .color(Color(red: 0.72, green: 0.46, blue: 0.1)))
            g.fill(Path(ellipseIn: CGRect(x: r.minX + s * 0.2, y: r.minY + s * 0.16, width: s * 0.26, height: s * 0.16)), with: .color(.white.opacity(0.5)))
        }
    }
}

/// A tower as a small picture: the scene's own drawing at the size of a card.
struct WallTowerIcon: View, Equatable {
    var kind: WallKind
    var level = 0
    var body: some View { Canvas { g, size in WallScene.icon(&g, kind: kind, level: level, size: size) } }
}

/// An enemy as a small picture.
struct WallFoeIcon: View, Equatable {
    var foe: WallFoe
    var body: some View {
        Canvas { g, size in
            let S = min(size.width / (foe == .siege || foe == .chanyu ? 1.7 : 1.2), size.height / (foe == .chanyu ? 2.1 : 1.3))
            let e = WallEnemy(id: 0, foe: foe, x: Double(size.width / 2 / S), y: Double((size.height - S * 0.26) / S), hp: 1, maxHP: 1, speed: 0, ox: 0, oy: 0, seed: 1, born: 0, wave: 1)
            WallScene(field: .empty, now: 0, icon: true).enemy(&g, e, S)
        }
    }
}

struct WallView: View {
    @ObservedObject private var game = WallGame.shared
    @State private var chatModels: [(host: String, models: [String])] = []
    /// The mouse catcher over the map; left out only when the page is drawn offscreen for a picture.
    private let mouse: Bool
    init(mouse: Bool = true) { self.mouse = mouse }

    var body: some View {
        GeometryReader { whole in
            let k = WallScale.k(whole.size)
            VStack(spacing: 0) {
                GeometryReader { space in
                    let size = space.size
                    ZStack(alignment: .topLeading) {
                        land(size)
                        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { timeline in
                            let mapSize = CGSize(width: size.width, height: size.height - game.inset)
                            let S = game.camera.tile(mapSize), origin = game.camera.origin(mapSize), view = game.camera.visible(mapSize).insetBy(dx: 0, dy: 0)
                            let scene = WallScene(field: game.field, selected: game.selected, hoverTower: game.placing == nil ? game.hoverTower : nil,
                                                  preview: game.me ? game.preview : nil, now: timeline.date.timeIntervalSinceReferenceDate, drawsLand: false)
                            let inset = game.inset
                            Canvas(rendersAsynchronously: true) { context, canvas in
                                context.translateBy(x: -origin.x * S, y: inset - origin.y * S)
                                scene.paint(&context, tile: S, view: view)
                            }
                        }
                        if mouse { WallMouse().frame(width: size.width, height: size.height) }
                        overlays(size, k)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10 * k))
                    .onAppear { settle(size, k) }
                    .onChange(of: size) { _, new in settle(new, k) }
                }
                .padding(.horizontal, 8 * k).padding(.top, 6 * k)
                WallBar(game: game, k: k)
            }
        }
        .onAppear { game.start(); WallKeys.install() }
        .onDisappear { game.stop(); WallKeys.remove() }
        .task { if chatModels.isEmpty { chatModels = await FilmStudio.candidates() } }
    }

    /// What never moves — steppe, hills, river, rocks, the Wall — as a picture of its own, placed by the camera:
    /// composited, not painted again every frame.
    @ViewBuilder private func land(_ size: CGSize) -> some View {
        let mapSize = CGSize(width: size.width, height: size.height - game.inset)
        let S = game.camera.tile(mapSize), origin = game.camera.origin(mapSize), R = WallLand.rect
        ZStack(alignment: .topLeading) {
            Color(red: 0.55, green: 0.66, blue: 0.36)
            if let image = WallLand.image(game.field) {
                Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                    .frame(width: R.width * S, height: R.height * S)
                    .offset(x: (R.minX + 0.5 - origin.x) * S, y: game.inset + (R.minY + WallGame.top - origin.y) * S)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private func settle(_ size: CGSize, _ k: CGFloat) {
        game.inset = 74 * k
        game.viewSize = CGSize(width: size.width, height: size.height - game.inset)
        game.scale = k
        game.camera.settle(size)
    }

    @ViewBuilder private func overlays(_ size: CGSize, _ k: CGFloat) -> some View {
        WallHUD(game: game, chatModels: chatModels, k: k)
            .padding(10 * k)
            .frame(width: size.width, alignment: .top)
        if let text = game.saying {
            Text(text).font(.system(size: 14.5 * k, weight: .bold, design: .rounded)).foregroundColor(.white)
                .padding(.horizontal, 18 * k).padding(.vertical, 8 * k)
                .background(Capsule().fill(Color(red: 0.2, green: 0.08, blue: 0.06).opacity(0.82)))
                .overlay(Capsule().stroke(Color(red: 1, green: 0.8, blue: 0.45).opacity(0.4), lineWidth: 1))
                .compositingGroup()
                .frame(width: size.width).padding(.top, 78 * k).allowsHitTesting(false)
        }
        if !game.field.over { WallInfoCard(game: game, k: k).frame(width: size.width, height: size.height, alignment: .bottomLeading) }
        WallTray(game: game, k: k).frame(width: size.width, height: size.height, alignment: .bottom)
        zoomButtons(k).frame(width: size.width, height: size.height, alignment: .bottomTrailing)
        if game.speed == 0, !game.field.over, game.placing == nil, game.field.time == 0 {
            startButton(k).padding(.bottom, 26 * k).frame(width: size.width, height: size.height, alignment: .bottom)
        }
        if game.field.over { ending(size, k) }
    }

    private func startButton(_ k: CGFloat) -> some View {
        Button { game.speed = 1 } label: {
            HStack(spacing: 12 * k) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 38 * k, height: 38 * k)
                    Image(systemName: "flag.fill").font(.system(size: 18 * k, weight: .bold)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1 * k) {
                    Text("开始").font(.system(size: 24 * k, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text("先造几座塔，敌人 \(Int(game.field.clock)) 秒后从北边山口下来").font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                }
                WallKey(text: "空格", k: k)
            }
            .padding(.leading, 12 * k).padding(.trailing, 18 * k).padding(.vertical, 11 * k)
            .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.92, green: 0.3, blue: 0.2), Color(red: 0.66, green: 0.12, blue: 0.1)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5).opacity(0.9), Color(red: 1, green: 0.8, blue: 0.4).opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5 * k))
            .compositingGroup()
            .shadow(color: Color(red: 0.9, green: 0.3, blue: 0.1).opacity(0.5), radius: 18 * k)
            .shadow(color: .black.opacity(0.25), radius: 4 * k, y: 3 * k)
        }
        .buttonStyle(.plain)
    }

    private func zoomButtons(_ k: CGFloat) -> some View {
        VStack(spacing: 4 * k) {
            ForEach([("plus", 1.25), ("minus", 0.8), ("scope", 0.0)], id: \.0) { item in
                Button { item.1 == 0 ? game.frame() : game.zoom(by: CGFloat(item.1)) } label: {
                    Image(systemName: item.0 == "scope" ? "arrow.up.left.and.arrow.down.right" : item.0).font(.system(size: 15 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.9, blue: 0.7))
                        .frame(width: 38 * k, height: 34 * k).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.0 == "plus" ? "放大（=）" : item.0 == "minus" ? "缩小（-）" : "看全关")
            }
        }
        .padding(4 * k)
        .wallGlass(k, radius: 12)
        .padding(12 * k)
    }

    private func ending(_ size: CGSize, _ k: CGFloat) -> some View {
        let f = game.field
        return VStack(spacing: 12 * k) {
            Text("关口失守").font(.system(size: 42 * k, weight: .heavy, design: .rounded))
            Text("守到第 \(f.wave) 波 · 最高 \(max(game.best, f.wave)) 波").font(.system(size: 19 * k, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
            Text("杀敌 \(f.kills) · 冲过关口 \(f.leaked) 个 · 斩单于 \(f.bossesKilled) 次 · \(f.towers.count) 座塔 · 敌人的路 \(Int(f.pathLength.rounded())) 格").font(.system(size: 15 * k, weight: .semibold))
            Button { game.restart() } label: {
                Text("再守一次").font(.system(size: 16 * k, weight: .heavy)).foregroundColor(.white)
                    .padding(.horizontal, 24 * k).padding(.vertical, 9 * k)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.92, green: 0.3, blue: 0.2), Color(red: 0.66, green: 0.12, blue: 0.1)], startPoint: .top, endPoint: .bottom)))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white).padding(34 * k)
        .wallGlass(k, radius: 20)
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.25))
    }
}

// MARK: - Along the top: gold, lives, the wave and the next, 下一波, who holds the pass, the speed

struct WallHUD: View {
    @ObservedObject var game: WallGame
    var chatModels: [(host: String, models: [String])]
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let f = game.field, w = f.coming
        return HStack(spacing: 0) {
            HStack(spacing: 6 * k) {
                WallCoin().equatable().frame(width: 24 * k, height: 24 * k)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(f.gold)").font(.system(size: 18 * k, weight: .heavy, design: .rounded)).monospacedDigit().fixedSize()
                    Text("金").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 10 * k)
            rule
            HStack(spacing: 6 * k) {
                Image(systemName: "heart.fill").font(.system(size: 18 * k, weight: .bold)).foregroundColor(f.lives <= 5 ? Color(red: 1, green: 0.3, blue: 0.25) : Color(red: 1, green: 0.45, blue: 0.45))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(f.lives)").font(.system(size: 18 * k, weight: .heavy, design: .rounded)).monospacedDigit().fixedSize()
                        .foregroundColor(f.lives <= 5 ? Color(red: 1, green: 0.55, blue: 0.5) : .white)
                    Text("/ \(WallField.startLives) 命").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.65)).fixedSize()
                }
            }
            .padding(.horizontal, 10 * k)
            rule
            VStack(alignment: .leading, spacing: 1 * k) {
                HStack(alignment: .firstTextBaseline, spacing: 6 * k) {
                    Text(f.wave == 0 ? "备战" : "第 \(f.wave) 波").font(.system(size: 17 * k, weight: .heavy, design: .rounded)).fixedSize()
                    Text("最高 \(max(game.best, f.wave))").font(.system(size: 11 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5)).fixedSize()
                }
                Text(coming(f, w)).font(.system(size: 11 * k, weight: .bold)).lineLimit(1).fixedSize()
                    .foregroundColor(w.boss ? Color(red: 1, green: 0.6, blue: 0.4) : .white.opacity(0.75))
            }
            .padding(.horizontal, 10 * k)
            nextButton
            Spacer(minLength: 6 * k)
            HStack(spacing: 5 * k) {
                Text("守关").font(.system(size: 11 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
                segmented(WallSeat.allCases.map { ($0.title, game.seat == $0) }) { game.seat = WallSeat.allCases[$0] }
                if game.seat == .llm {
                    Menu {
                        Button("自动") { game.model = "" }
                        ForEach(chatModels, id: \.host) { entry in
                            Section(BoxServices.place(of: entry.host)) {
                                ForEach(entry.models, id: \.self) { name in Button(name + (name.hasSuffix(":cloud") ? " ☁︎" : "")) { game.model = "\(entry.host)|\(name)" } }
                            }
                        }
                    } label: { Text(game.model.isEmpty ? "自动" : String(game.model.split(separator: "|").last ?? "")).font(.system(size: 11 * k, weight: .semibold)).lineLimit(1) }
                    .menuStyle(.borderlessButton).fixedSize().foregroundColor(.white)
                }
            }
            .padding(.horizontal, 8 * k)
            rule
            HStack(spacing: 5 * k) {
                segmented([("⏸", game.speed == 0), ("1×", game.speed == 1), ("2×", game.speed == 2), ("4×", game.speed == 4), ("8×", game.speed == 8)]) { game.speed = [0, 1, 2, 4, 8][$0] }
                Button { game.restart() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 13 * k, weight: .bold)).foregroundColor(.white)
                        .frame(width: 28 * k, height: 26 * k).background(RoundedRectangle(cornerRadius: 7 * k).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain).help("重新开始")
            }
            .padding(.horizontal, 8 * k)
        }
        .foregroundColor(.white)
        .padding(.vertical, 7 * k)
        .wallGlass(k, radius: 16)
    }

    private func coming(_ f: WallField, _ w: WallWave) -> String {
        let when = f.spawned ? "\(Int(max(0, f.clock).rounded())) 秒后" : "随后"
        return "下一波 \(when)：" + (w.boss ? "⚠️ 单于亲征" : w.theme) + " · \(w.total) 敌"
    }

    /// 下一波: the next wave now, for the gold its early coming pays.
    private var nextButton: some View {
        let f = game.field
        let can = f.spawned && !f.over && game.me
        return Button { game.callNext() } label: {
            HStack(spacing: 6 * k) {
                Image(systemName: "forward.fill").font(.system(size: 12 * k, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("下一波").font(.system(size: 13.5 * k, weight: .heavy))
                    Text(can ? "+\(WallField.waveBonus(f.wave + 1) + f.earlyBonus) 金" : f.spawned ? "观战中" : "还在出兵").font(.system(size: 10 * k, weight: .bold)).monospacedDigit().opacity(0.9)
                }
                WallKey(text: "N", k: k * 0.85)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10 * k).padding(.vertical, 5 * k)
            .background(Capsule().fill(can ? LinearGradient(colors: [Color(red: 0.92, green: 0.32, blue: 0.2), Color(red: 0.66, green: 0.14, blue: 0.1)], startPoint: .top, endPoint: .bottom)
                                          : LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(Color(red: 1, green: 0.84, blue: 0.5).opacity(can ? 0.7 : 0.2), lineWidth: 1))
            .opacity(can ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!can)
        .help("现在就叫下一波来：早来多给金子")
    }

    private var rule: some View { Rectangle().fill(Color(red: 1, green: 0.85, blue: 0.6).opacity(0.18)).frame(width: 1, height: 32 * k) }

    private func segmented(_ items: [(String, Bool)], _ pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2 * k) {
            ForEach(items.indices, id: \.self) { i in
                Button { pick(i) } label: {
                    Text(items[i].0).font(.system(size: 12.5 * k, weight: .bold, design: .rounded)).foregroundColor(items[i].1 ? Color(red: 0.36, green: 0.12, blue: 0.06) : .white).fixedSize()
                        .padding(.horizontal, 6.5 * k).padding(.vertical, 5 * k)
                        .background(RoundedRectangle(cornerRadius: 7 * k).fill(items[i].1 ? LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.58), Color(red: 1, green: 0.74, blue: 0.34)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Bottom left: the tower selected, what the keys do, or what the defender chose

struct WallInfoCard: View {
    @ObservedObject var game: WallGame
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let f = game.field
        return Group {
            if let id = game.selected, let t = f.tower(id) { selected(t, f) }
            else if !game.me { watching }
            else if game.placing == nil { hints }
        }
        .padding(12 * k)
        .frame(width: 300 * k, alignment: .leading)
        .wallGlass(k, radius: 16)
        .padding(12 * k)
        .opacity(game.placing != nil && game.selected == nil && game.me ? 0 : 1)
    }

    private var hints: some View {
        let rows: [[(String, String)]] = [[("空格", "暂停"), ("1–4", "速度"), ("N", "下一波")], [("U", "升级"), ("S", "卖掉"), ("Tab", "目标")], [("Esc", "取消"), ("⇧", "连续造"), ("= -", "缩放")]]
        return VStack(alignment: .leading, spacing: 7 * k) {
            HStack(spacing: 6 * k) {
                Image(systemName: "hand.point.up.left.fill").font(.system(size: 13 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
                Text("点下面的塔，再点草地造下").font(.system(size: 13.5 * k, weight: .heavy)).foregroundColor(.white)
            }
            Text("敌人绕塔走：用塔摆出迷宫，路越长挨打越久。不能把路全堵死。").font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5 * k) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { i in
                            HStack(spacing: 6 * k) {
                                WallKey(text: rows[r][i].0, k: k)
                                Text(rows[r][i].1).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                            }
                            .frame(width: 92 * k, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var watching: some View {
        VStack(alignment: .leading, spacing: 6 * k) {
            HStack(spacing: 6 * k) {
                Image(systemName: "eye.fill").font(.system(size: 13 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
                Text("观战：\(game.seat.title)守关").font(.system(size: 14 * k, weight: .heavy)).foregroundColor(.white)
            }
            if let b = game.ballot {
                VStack(alignment: .leading, spacing: 3 * k) {
                    ForEach(b.options.indices, id: \.self) { i in
                        HStack(spacing: 5 * k) {
                            Image(systemName: i == b.chosen ? "checkmark.circle.fill" : "circle").font(.system(size: 10.5 * k, weight: .bold))
                                .foregroundColor(i == b.chosen ? Color(red: 0.5, green: 0.95, blue: 0.55) : .white.opacity(0.35))
                            Text(b.options[i].title).font(.system(size: 11.5 * k, weight: i == b.chosen ? .heavy : .semibold)).lineLimit(1)
                                .foregroundColor(i == b.chosen ? .white : .white.opacity(0.6))
                            if i == b.chosen, let c = b.chance { Text("\(Int(c * 100))%").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5)) }
                        }
                    }
                }
            } else if game.seat == .computer {
                Text("电脑按脚本摆迷宫：塔和拒马排成折返的墙，把敌人的路拉长，再在路边补塔、升级。").font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
            if let note = game.note { Text(note).font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(Color(red: 1, green: 0.9, blue: 0.66)).lineLimit(2) }
            Text("右上角换成「我」就能自己守").font(.system(size: 11 * k, weight: .semibold)).foregroundColor(.white.opacity(0.6))
        }
    }

    private func selected(_ t: WallTower, _ f: WallField) -> some View {
        let s = t.stats
        let boost = f.boosts[t.id]
        return VStack(alignment: .leading, spacing: 8 * k) {
            HStack(alignment: .top, spacing: 10 * k) {
                WallTowerIcon(kind: t.kind, level: t.level).equatable().frame(width: 58 * k, height: 70 * k)
                    .background(RoundedRectangle(cornerRadius: 10 * k).fill(Color(red: 0.62, green: 0.72, blue: 0.42).opacity(0.9)))
                VStack(alignment: .leading, spacing: 3 * k) {
                    HStack(spacing: 6 * k) {
                        Text(t.kind.name).font(.system(size: 18 * k, weight: .heavy)).foregroundColor(.white)
                        Text("\(t.level + 1) 级").font(.system(size: 12 * k, weight: .heavy)).foregroundColor(Color(red: 0.36, green: 0.12, blue: 0.06))
                            .padding(.horizontal, 6 * k).padding(.vertical, 1 * k).background(Capsule().fill(Color(red: 1, green: 0.82, blue: 0.42)))
                    }
                    Text(stats(t, s, boost)).font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    if t.kind.shoots { Text("杀敌 \(t.kills) · 伤害 \(Int(t.dealt))").font(.system(size: 11 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5)) }
                    if t.hp < s.hp - 1 { Text("耐久 \(Int(t.hp))/\(Int(s.hp))").font(.system(size: 11 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.6, blue: 0.5)) }
                }
            }
            if t.kind.shoots {
                HStack(spacing: 5 * k) {
                    Text("打谁").font(.system(size: 11.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.7))
                    ForEach(WallAim.allCases, id: \.rawValue) { a in
                        Button { game.aim(a) } label: {
                            Text(a.title).font(.system(size: 12 * k, weight: .bold)).foregroundColor(t.aim == a ? Color(red: 0.36, green: 0.12, blue: 0.06) : .white)
                                .padding(.horizontal, 8 * k).padding(.vertical, 4 * k)
                                .background(RoundedRectangle(cornerRadius: 7 * k).fill(t.aim == a ? Color(red: 1, green: 0.82, blue: 0.42) : Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain).disabled(!game.me)
                    }
                    WallKey(text: "Tab", k: k * 0.85)
                }
            }
            if game.me {
                HStack(spacing: 8 * k) {
                    if let c = f.upgradeCost(t) {
                        action("升到 \(t.level + 2) 级 · \(c) 金", "arrow.up.circle.fill", warm: true, dim: f.gold < c) { game.upgrade() }
                            .help(next(t))
                    } else {
                        Text("已是最高级").font(.system(size: 12 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
                    }
                    action("卖 +\(f.refund(t))", "dollarsign.circle", warm: false, dim: false) { game.sell() }
                }
                if f.upgradeCost(t) != nil { Text(next(t)).font(.system(size: 10.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.6)).lineLimit(1) }
            }
        }
    }

    private func stats(_ t: WallTower, _ s: WallStats, _ boost: (damage: Double, range: Double)?) -> String {
        let plus = boost.map { " · 烽火 +\(Int($0.damage * 100))%" } ?? ""
        switch t.kind {
        case .arrow: return String(format: "伤害 %.0f · 每秒 %.1f 箭 · 射程 %.1f", s.damage * (1 + (boost?.damage ?? 0)), s.rate, s.range * (1 + (boost?.range ?? 0))) + plus
        case .ballista: return String(format: "伤害 %.0f · 穿透 %d 个 · 射程 %.1f", s.damage * (1 + (boost?.damage ?? 0)), s.pierce, s.range * (1 + (boost?.range ?? 0))) + plus
        case .trebuchet: return String(format: "伤害 %.0f · 溅射 %.1f 格 · 射程 %.1f（近 %.1f 内打不到）", s.damage * (1 + (boost?.damage ?? 0)), s.splash, s.range * (1 + (boost?.range ?? 0)), s.minRange) + plus
        case .fire: return String(format: "烧地 %.1f 格 %.0f 秒 · 每秒 %.0f 伤害 · 射程 %.1f", s.splash, s.burn, s.damage * (1 + (boost?.damage ?? 0)), s.range * (1 + (boost?.range ?? 0))) + plus
        case .beacon: return String(format: "%.1f 格内的塔：伤害 +%.0f%%，射程 +%.0f%%", s.range, s.boost * 100, s.reach * 100)
        case .barricade: return String(format: "挡路 · 刺伤身边的敌人 每秒 %.0f · 耐久 %.0f", s.damage, s.hp)
        }
    }

    private func next(_ t: WallTower) -> String {
        guard t.level < 2 else { return "" }
        let a = t.stats, b = t.kind.stats(t.level + 1)
        switch t.kind {
        case .beacon: return "升级后：加成 \(Int(a.boost * 100))% → \(Int(b.boost * 100))%，范围 \(String(format: "%.1f → %.1f", a.range, b.range))"
        case .barricade: return "升级后：耐久 \(Int(a.hp)) → \(Int(b.hp))，刺 \(Int(a.damage)) → \(Int(b.damage))"
        default: return "升级后：伤害 \(Int(a.damage)) → \(Int(b.damage))，射程 \(String(format: "%.1f → %.1f", a.range, b.range))"
        }
    }

    private func action(_ title: String, _ symbol: String, warm: Bool, dim: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5 * k) {
                Image(systemName: symbol).font(.system(size: 11 * k, weight: .bold))
                Text(title).font(.system(size: 12 * k, weight: .heavy)).monospacedDigit()
            }
            .foregroundColor(.white).padding(.horizontal, 10 * k).padding(.vertical, 6 * k)
            .background(Capsule().fill(warm ? LinearGradient(colors: [Color(red: 0.92, green: 0.32, blue: 0.2), Color(red: 0.66, green: 0.14, blue: 0.1)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(Color(red: 1, green: 0.84, blue: 0.5).opacity(0.4), lineWidth: 1))
            .opacity(dim ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom middle: what the mouse is doing

struct WallTray: View {
    @ObservedObject var game: WallGame
    var k: CGFloat
    var body: some View {
        _ = game.beat
        return VStack(spacing: 6 * k) {
            if let kind = game.placing, game.me {
                pill("点草地造\(kind.name)（\(kind.cost) 金）· 橙色虚线是造了以后的路 · ⇧ 连续造 · 右键取消")
            }
            if game.field.coming.boss, game.field.spawned, game.field.clock < 10, !game.field.over, game.field.wave > 0 {
                pill("⚠️ 单于亲征：\(Int(max(0, game.field.clock))) 秒后，带着亲卫骑兵", alarm: true)
            }
        }
        .padding(.bottom, 16 * k)
    }

    private func pill(_ text: String, alarm: Bool = false) -> some View {
        Text(text).font(.system(size: 13 * k, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 14 * k).padding(.vertical, 7 * k)
            .background(Capsule().fill(alarm ? Color(red: 0.7, green: 0.14, blue: 0.1).opacity(0.9) : Color(red: 0.2, green: 0.08, blue: 0.06).opacity(0.82)))
            .overlay(Capsule().stroke(Color(red: 1, green: 0.84, blue: 0.5).opacity(0.35), lineWidth: 1))
            .compositingGroup()
            .allowsHitTesting(false)
    }
}

// MARK: - Along the bottom: the tower cards, and the wave to come

struct WallBar: View {
    @ObservedObject var game: WallGame
    var k: CGFloat

    static func purpose(_ kind: WallKind) -> String {
        switch kind {
        case .arrow: return "便宜、射得快，一次打一个；盾兵只吃三成"
        case .ballista: return "射得远，一箭穿过一串敌人"
        case .trebuchet: return "石头砸一片，慢；太近的打不到"
        case .fire: return "火油罐落地烧一片，攻城车最怕火"
        case .beacon: return "不攻击：让附近的塔伤害和射程变大"
        case .barricade: return "很便宜，专门堵路拉长迷宫；步卒会砍，攻城车会撞"
        }
    }

    var body: some View {
        _ = game.beat
        return GeometryReader { space in
            let gap = 6 * k
            let waveWidth = min(300 * k, max(210 * k, space.size.width * 0.24))
            let fit = (space.size.width - 24 * k - waveWidth - gap * 8) / 6
            let width = min(108 * k, max(64 * k, fit))
            HStack(spacing: gap) {
                ForEach(WallKind.allCases, id: \.rawValue) { kind in card(kind, width) }
                Spacer(minLength: gap)
                wavePanel.frame(width: waveWidth)
            }
            .padding(.horizontal, 12 * k)
            .frame(width: space.size.width, height: space.size.height)
        }
        .frame(height: 120 * k)
        .background(
            LinearGradient(colors: [Color(red: 0.24, green: 0.12, blue: 0.09), Color(red: 0.12, green: 0.06, blue: 0.05)], startPoint: .top, endPoint: .bottom)
                .overlay(Rectangle().fill(Color(red: 1, green: 0.84, blue: 0.5).opacity(0.35)).frame(height: 1), alignment: .top)
        )
    }

    private func card(_ kind: WallKind, _ width: CGFloat) -> some View {
        let f = game.field
        let on = game.placing == kind
        let short = f.gold < kind.cost
        let blocked = !game.me
        return Button { if game.me { game.placing = on ? nil : kind } } label: {
            VStack(spacing: 2 * k) {
                ZStack(alignment: .topTrailing) {
                    WallTowerIcon(kind: kind).equatable().frame(width: width - 12 * k, height: 62 * k)
                    WallKey(text: kind.key, k: k * 0.82).offset(x: 3 * k, y: -3 * k)
                }
                Text(kind.name).font(.system(size: 12.5 * k, weight: .heavy)).foregroundColor(on ? Color(red: 0.36, green: 0.12, blue: 0.06) : .white).lineLimit(1)
                HStack(spacing: 2 * k) {
                    WallCoin().equatable().frame(width: 11 * k, height: 11 * k)
                    Text("\(kind.cost)").font(.system(size: 11.5 * k, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundColor(short ? Color(red: 1, green: 0.42, blue: 0.38) : on ? Color(red: 0.36, green: 0.2, blue: 0.08) : .white.opacity(0.92))
                }
            }
            .padding(.horizontal, 4 * k).padding(.vertical, 5 * k)
            .frame(width: width, height: 108 * k, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 12 * k).fill(on ? LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.6), Color(red: 1, green: 0.74, blue: 0.34)], startPoint: .top, endPoint: .bottom)
                                                                     : LinearGradient(colors: [Color(red: 0.62, green: 0.72, blue: 0.42).opacity(0.32), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(on ? Color(red: 1, green: 0.95, blue: 0.8) : Color(red: 1, green: 0.84, blue: 0.5).opacity(0.25), lineWidth: on ? 2 * k : 1))
            .shadow(color: on ? Color(red: 1, green: 0.7, blue: 0.3).opacity(0.6) : .clear, radius: 8 * k)
            .opacity(blocked ? 0.42 : short ? 0.62 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .help(blocked ? "观战中：右上角换成「我」才能造" : "\(kind.name)（\(kind.key)）：\(Self.purpose(kind))" + (short ? "\n金子不够：还差 \(kind.cost - f.gold)" : ""))
    }

    /// The wave to come: its name, when, and a picture of each kind in it with how many.
    private var wavePanel: some View {
        let f = game.field, w = f.coming
        let kinds = [WallFoe.chanyu, .guard, .siege, .shield, .cavalry, .shaman, .foot].filter { w.count($0) > 0 }
        return VStack(alignment: .leading, spacing: 4 * k) {
            HStack(spacing: 6 * k) {
                Text("第 \(w.number) 波").font(.system(size: 13 * k, weight: .heavy)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
                Text(w.theme).font(.system(size: 13 * k, weight: .heavy)).foregroundColor(w.boss ? Color(red: 1, green: 0.5, blue: 0.4) : .white)
                Spacer(minLength: 0)
                Text(f.spawned ? "\(Int(max(0, f.clock).rounded())) 秒" : "随后").font(.system(size: 12 * k, weight: .bold)).monospacedDigit().foregroundColor(.white.opacity(0.75))
            }
            HStack(spacing: 5 * k) {
                ForEach(kinds, id: \.rawValue) { foe in
                    VStack(spacing: 0) {
                        WallFoeIcon(foe: foe).equatable().frame(width: 46 * k, height: 50 * k)
                        Text(foe == .chanyu ? "单于" : "×\(w.count(foe))").font(.system(size: 11 * k, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    }
                    .help(foe.name)
                }
            }
        }
        .padding(.horizontal, 10 * k).padding(.vertical, 6 * k)
        .frame(height: 106 * k)
        .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color.black.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color(red: 1, green: 0.84, blue: 0.5).opacity(0.2), lineWidth: 1))
    }
}
