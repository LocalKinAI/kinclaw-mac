import AppKit
import SwiftUI

/// The page's measure: 1 at 1200 points wide, growing with the window up to 1.7 and down to 0.8.
enum WarlordScale {
    static func k(_ size: CGSize) -> CGFloat { min(1.7, max(0.8, min(size.width / 1200, size.height / 640))) }
}

/// Dark lacquer with a gold rim: what every panel over the map sits on.
struct WarlordGlass: ViewModifier {
    var k: CGFloat
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius * k).fill(LinearGradient(colors: [Color(red: 0.2, green: 0.13, blue: 0.1).opacity(0.93), Color(red: 0.11, green: 0.07, blue: 0.06).opacity(0.93)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: radius * k).stroke(LinearGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.5).opacity(0.85), Color(red: 0.7, green: 0.5, blue: 0.24).opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, 1.2 * k)))
            .compositingGroup()
            .shadow(color: .black.opacity(0.4), radius: 8 * k, y: 3 * k)
    }
}

/// Warm paper with an ink rim: the battle reports and the victory scroll.
struct WarlordPaper: ViewModifier {
    var k: CGFloat
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius * k).fill(LinearGradient(colors: [Color(red: 0.98, green: 0.94, blue: 0.83), Color(red: 0.92, green: 0.85, blue: 0.68)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: radius * k).stroke(Color(red: 0.42, green: 0.26, blue: 0.14), lineWidth: max(1, 1.6 * k)))
            .overlay(RoundedRectangle(cornerRadius: (radius - 3) * k).stroke(Color(red: 0.7, green: 0.5, blue: 0.26).opacity(0.7), lineWidth: max(0.6, 0.8 * k)).padding(3.5 * k))
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 10 * k, y: 4 * k)
    }
}

extension View {
    func warlordGlass(_ k: CGFloat, radius: CGFloat = 12) -> some View { modifier(WarlordGlass(k: k, radius: radius)) }
    func warlordPaper(_ k: CGFloat, radius: CGFloat = 10) -> some View { modifier(WarlordPaper(k: k, radius: radius)) }
}

enum WarlordStyle {
    static let gold = Color(red: 0.98, green: 0.83, blue: 0.46)
    static let ink = Color(red: 0.2, green: 0.13, blue: 0.08)
    static let red = Color(red: 0.72, green: 0.14, blue: 0.1)
    static func title(_ size: CGFloat) -> Font { .custom("STSongti-SC-Black", size: size) }
    static func num(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func colour(_ f: Int) -> Color { WarlordScene.c(WarlordScene.colour(f)) }
}

/// A button in the style of the page: gold on lacquer, or red for the ones that start something.
struct WarlordButton: View {
    var title: String
    var symbol: String? = nil
    var k: CGFloat
    var hot = false
    var on = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4 * k) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11 * k, weight: .bold)) }
                Text(title).font(.system(size: 12.5 * k, weight: .heavy))
            }
            .foregroundColor(hot ? .white : Color(red: 0.24, green: 0.14, blue: 0.08))
            .padding(.horizontal, 9 * k).padding(.vertical, 5.5 * k)
            .frame(minWidth: 50 * k)
            .background(RoundedRectangle(cornerRadius: 7 * k).fill(hot ? LinearGradient(colors: [Color(red: 0.9, green: 0.3, blue: 0.2), Color(red: 0.62, green: 0.1, blue: 0.08)], startPoint: .top, endPoint: .bottom)
                                                                : LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.66), Color(red: 0.9, green: 0.72, blue: 0.36)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 7 * k).stroke(Color.black.opacity(0.35), lineWidth: 0.8))
            .opacity(on ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!on)
    }
}

// MARK: - The page

struct WarlordView: View {
    @ObservedObject private var game = WarlordGame.shared
    @State private var chatModels: [(host: String, models: [String])] = []
    /// The mouse catcher over the map; left out only when the page is drawn offscreen for a picture.
    private let mouse: Bool
    /// A fixed moment for pictures drawn offscreen.
    private let frozen: Double?
    init(mouse: Bool = true, frozen: Double? = nil) { self.mouse = mouse; self.frozen = frozen }

    var body: some View {
        GeometryReader { space in
            let size = space.size, k = WarlordScale.k(size)
            let S = game.camera.tile(size), origin = game.camera.origin(size)
            ZStack(alignment: .topLeading) {
                WarlordMapLayers(game: game, size: size, S: S, origin: origin, frozen: frozen)
                if mouse { WarlordMouse().frame(width: size.width, height: size.height) }
                WarlordOverlays(game: game, chatModels: chatModels, size: size, k: k)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .onAppear { game.viewSize = size; game.scale = k; game.camera.settle(size) }
            .onChange(of: size) { _, new in game.viewSize = new; game.scale = WarlordScale.k(new); game.camera.settle(new) }
        }
        .onAppear { if mouse { game.start(); WarlordKeys.install() } }
        .onDisappear { if mouse { game.stop(); WarlordKeys.remove() } }
        .task { if mouse, chatModels.isEmpty { chatModels = await FilmStudio.candidates() } }
    }
}

/// The map in two layers: a base SwiftUI keeps until a city changes hands or the camera moves, and a live one drawn every frame.
struct WarlordMapLayers: View {
    @ObservedObject var game: WarlordGame
    var size: CGSize
    var S: CGFloat
    var origin: CGPoint
    var frozen: Double?

    func scene(_ now: Double) -> WarlordScene {
        WarlordScene(world: game.world, selected: game.selected, hover: game.hover, targets: game.targets,
                     friendly: { if case .march = game.targeting { return false }; return true }(),
                     march: game.phase == .marching ? game.marchT : 0, fights: game.told, mine: game.mine, now: now)
    }

    var body: some View {
        let base = scene(0)
        let w = game.world
        let key = WarlordScene.Key(owners: w.cities.map(\.owner), troops: w.cities.map(\.troops), selected: game.selected, mine: game.mine,
                                   lit: game.targets.sorted(), S: S, origin: origin, size: size)
        return ZStack {
            WarlordBaseLayer(key: key, scene: base).equatable()
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: frozen != nil)) { timeline in
                let live = scene(frozen ?? timeline.date.timeIntervalSinceReferenceDate)
                Canvas(rendersAsynchronously: true) { g, _ in
                    g.translateBy(x: -origin.x * S, y: -origin.y * S)
                    live.paintLive(&g, S: S)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The still part of the map, drawn again only when its key changes.
struct WarlordBaseLayer: View, Equatable {
    let key: WarlordScene.Key
    let scene: WarlordScene
    static func == (a: Self, b: Self) -> Bool { a.key == b.key }
    var body: some View {
        Canvas(rendersAsynchronously: true) { g, _ in
            g.translateBy(x: -key.origin.x * key.S, y: -key.origin.y * key.S)
            scene.paintBase(&g, S: key.S, view: CGRect(x: key.origin.x, y: key.origin.y, width: key.size.width / key.S, height: key.size.height / key.S))
        }
    }
}

/// Everything over the map, sized by `k`.
struct WarlordOverlays: View {
    @ObservedObject var game: WarlordGame
    var chatModels: [(host: String, models: [String])]
    var size: CGSize
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let w = game.world
        return ZStack(alignment: .topLeading) {
            WarlordHUD(game: game, chatModels: chatModels, k: k).padding(8 * k).frame(width: size.width, alignment: .top)
            HStack(alignment: .top, spacing: 0) {
                if let c = game.selected { WarlordCityPanel(game: game, city: c, k: k).frame(width: 300 * k) }
                Spacer(minLength: 0)
                if game.showFactions { WarlordFactionPanel(game: game, k: k).frame(width: 238 * k) }
            }
            .padding(.horizontal, 8 * k).padding(.top, 70 * k).padding(.bottom, 62 * k)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            WarlordTurnBar(game: game, k: k).padding(.bottom, 10 * k).frame(width: size.width, height: size.height, alignment: .bottom)
            zoomButtons.padding(.trailing, 10 * k).padding(.bottom, 12 * k).frame(width: size.width, height: size.height, alignment: .bottomTrailing)
            if let text = game.saying {
                Text(text).font(.system(size: 14 * k, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 16 * k).padding(.vertical, 8 * k)
                    .background(Capsule().fill(Color(red: 0.14, green: 0.08, blue: 0.06).opacity(0.88)))
                    .overlay(Capsule().stroke(WarlordStyle.gold.opacity(0.6), lineWidth: 1))
                    .frame(width: size.width).padding(.top, 78 * k).allowsHitTesting(false)
            }
            if game.draft != nil { WarlordDraftCard(game: game, k: k).frame(width: size.width, height: size.height) }
            if game.shipment != nil { WarlordShipmentCard(game: game, k: k).frame(width: size.width, height: size.height) }
            if game.showDiplomacy, let c = game.selected { WarlordDiplomacyCard(game: game, city: c, k: k).frame(width: size.width, height: size.height) }
            if !game.told.isEmpty { WarlordReports(game: game, k: k, width: size.width).frame(width: size.width, height: size.height) }
            if game.showSeats { WarlordSeatsCard(game: game, chatModels: chatModels, k: k).frame(width: size.width, height: size.height) }
            if game.showChronicle { WarlordChronicle(game: game, k: k).frame(width: size.width, height: size.height) }
            if !game.started, w.turns == 0, game.myTurn == nil, !game.showSeats { WarlordStartCard(game: game, k: k).frame(width: size.width, height: size.height) }
            if w.over { WarlordEndCard(game: game, k: k).frame(width: size.width, height: size.height) }
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 3 * k) {
            ForEach([("plus", 1.25), ("minus", 0.8), ("scope", 0.0)], id: \.0) { item in
                Button { if item.1 == 0 { game.camera.zoom = 1; game.camera.settle(game.viewSize) } else { game.zoom(by: CGFloat(item.1)) } } label: {
                    Image(systemName: item.0).font(.system(size: 15 * k, weight: .bold)).foregroundColor(WarlordStyle.gold)
                        .frame(width: 32 * k, height: 28 * k).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.0 == "plus" ? "放大（=）" : item.0 == "minus" ? "缩小（-）" : "看全图")
            }
        }
        .padding(4 * k)
        .warlordGlass(k, radius: 11)
    }
}

// MARK: - Along the top

struct WarlordHUD: View {
    @ObservedObject var game: WarlordGame
    var chatModels: [(host: String, models: [String])]
    var k: CGFloat

    var body: some View {
        let w = game.world, f = game.shown
        return HStack(spacing: 0) {
            // The date and the season.
            HStack(spacing: 8 * k) {
                ZStack {
                    Circle().fill(seasonColour(w.month)).frame(width: 30 * k, height: 30 * k)
                    Text(w.season).font(WarlordStyle.title(15 * k)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(w.year)年 \(w.month)月").font(WarlordStyle.title(17 * k)).foregroundColor(WarlordStyle.gold).fixedSize()
                    Text(w.month == 9 ? "秋收" : w.month < 9 ? "秋收还有 \(9 - w.month) 月" : "来年 9 月秋收").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.7)).fixedSize()
                }
            }
            .padding(.horizontal, 10 * k)
            rule
            // The faction shown: the person's, or the one watched.
            HStack(spacing: 7 * k) {
                WarlordFace(officer: w.factions[f].lord, faction: f).equatable().frame(width: 36 * k, height: 36 * k)
                VStack(alignment: .leading, spacing: 0) {
                    Text(w.lordName(f)).font(WarlordStyle.title(15 * k)).foregroundColor(.white).fixedSize()
                    Text(game.mine == f ? "我的势力" : "观战").font(.system(size: 10 * k, weight: .bold)).foregroundColor(game.mine == f ? Color(red: 0.6, green: 0.95, blue: 0.6) : WarlordStyle.gold.opacity(0.8)).fixedSize()
                }
                stat("金", "\(w.gold(of: f))", Color(red: 1, green: 0.84, blue: 0.4))
                stat("粮", WarlordCommander.troops(w.grain(of: f)), Color(red: 0.9, green: 0.78, blue: 0.5))
                stat("兵", WarlordCommander.troops(w.troops(of: f)), Color(red: 1, green: 0.55, blue: 0.45))
                stat("城", "\(w.held(f))", Color(red: 0.7, green: 0.88, blue: 1))
                stat("将", "\(w.staff(of: f).count)", Color(red: 0.72, green: 0.95, blue: 0.7))
            }
            .padding(.horizontal, 10 * k)
            Spacer(minLength: 4 * k)
            // Who plays whom.
            Button { game.showSeats.toggle() } label: {
                HStack(spacing: 5 * k) {
                    Image(systemName: "person.2.fill").font(.system(size: 12 * k, weight: .bold))
                    Text(seatSummary(w)).font(.system(size: 11.5 * k, weight: .bold)).lineLimit(1)
                }
                .foregroundColor(WarlordStyle.gold)
                .padding(.horizontal, 8 * k).padding(.vertical, 5 * k)
                .background(RoundedRectangle(cornerRadius: 7 * k).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain).help("谁来当哪一路诸侯（S）")
            if game.seats.contains(.llm) {
                Menu {
                    Button("自动") { game.model = "" }
                    ForEach(chatModels, id: \.host) { entry in
                        Section(BoxServices.place(of: entry.host)) {
                            ForEach(entry.models, id: \.self) { name in Button(name + (name.hasSuffix(":cloud") ? " ☁︎" : "")) { game.model = "\(entry.host)|\(name)" } }
                        }
                    }
                } label: { Text(game.model.isEmpty ? "模型：自动" : String(game.model.split(separator: "|").last ?? "")).font(.system(size: 11 * k, weight: .semibold)).lineLimit(1) }
                .menuStyle(.borderlessButton).fixedSize().foregroundColor(.white).padding(.leading, 6 * k)
            }
            rule.padding(.horizontal, 6 * k)
            HStack(spacing: 2 * k) {
                ForEach([("⏸", 0.0), ("1×", 1.0), ("2×", 2.0), ("4×", 4.0)], id: \.0) { item in
                    Button { game.speed = item.1 } label: {
                        Text(item.0).font(.system(size: 12 * k, weight: .bold, design: .rounded)).foregroundColor(game.speed == item.1 ? WarlordStyle.ink : .white).fixedSize()
                            .padding(.horizontal, 6.5 * k).padding(.vertical, 4.5 * k)
                            .background(RoundedRectangle(cornerRadius: 6 * k).fill(game.speed == item.1 ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.62), Color(red: 0.93, green: 0.72, blue: 0.34)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.08))))
                    }
                    .buttonStyle(.plain)
                }
                Button { game.showFactions.toggle() } label: {
                    Image(systemName: "flag.2.crossed.fill").font(.system(size: 12 * k, weight: .bold)).foregroundColor(game.showFactions ? WarlordStyle.gold : .white.opacity(0.7))
                        .frame(width: 27 * k, height: 25 * k).background(RoundedRectangle(cornerRadius: 6 * k).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain).help("诸侯一览（F）").padding(.leading, 4 * k)
                Button { game.showChronicle.toggle() } label: {
                    Image(systemName: "scroll.fill").font(.system(size: 12 * k, weight: .bold)).foregroundColor(game.showChronicle ? WarlordStyle.gold : .white.opacity(0.7))
                        .frame(width: 27 * k, height: 25 * k).background(RoundedRectangle(cornerRadius: 6 * k).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain).help("史书（L）")
                Button { game.restart() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12 * k, weight: .bold)).foregroundColor(.white)
                        .frame(width: 27 * k, height: 25 * k).background(RoundedRectangle(cornerRadius: 6 * k).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain).help("重新开始")
            }
            .padding(.trailing, 8 * k)
        }
        .padding(.vertical, 7 * k)
        .warlordGlass(k, radius: 14)
    }

    private var rule: some View { Rectangle().fill(WarlordStyle.gold.opacity(0.25)).frame(width: 1, height: 34 * k) }

    private func stat(_ label: String, _ value: String, _ colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(WarlordStyle.num(15 * k)).monospacedDigit().foregroundColor(.white).fixedSize()
            Text(label).font(.system(size: 10 * k, weight: .heavy)).foregroundColor(colour).fixedSize()
        }
        .padding(.leading, 5 * k)
    }

    private func seasonColour(_ m: Int) -> Color {
        m <= 3 ? Color(red: 0.4, green: 0.7, blue: 0.4) : m <= 6 ? Color(red: 0.2, green: 0.55, blue: 0.3) : m <= 9 ? Color(red: 0.85, green: 0.5, blue: 0.16) : Color(red: 0.5, green: 0.62, blue: 0.8)
    }

    private func seatSummary(_ w: WarlordWorld) -> String {
        let special = w.factions.indices.filter { w.factions[$0].alive && game.seats[$0] != .computer }
        if special.isEmpty { return "全部电脑 · 观战" }
        return special.prefix(3).map { "\(game.seats[$0].title)：\(w.lordName($0))" }.joined(separator: " · ") + (special.count > 3 ? " …" : "")
    }
}

// MARK: - Along the bottom: whose turn, and the person's 结束回合

struct WarlordTurnBar: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var body: some View {
        let w = game.world
        return HStack(spacing: 10 * k) {
            if let f = w.winner {
                WarlordFace(officer: w.factions[f].lord, faction: f).equatable().frame(width: 30 * k, height: 30 * k)
                Text("\(w.lordName(f))统一天下 · \(w.date)").font(WarlordStyle.title(14 * k)).foregroundColor(WarlordStyle.gold)
            } else if let f = game.myTurn {
                WarlordFace(officer: w.factions[f].lord, faction: f).equatable().frame(width: 30 * k, height: 30 * k)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(w.lordName(f)) 的回合").font(WarlordStyle.title(14 * k)).foregroundColor(WarlordStyle.gold)
                    Text(hint(f, w)).font(.system(size: 11 * k, weight: .semibold)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                }
                WarlordButton(title: "结束回合", symbol: "checkmark.seal.fill", k: k, hot: true) { game.endTurn() }
                Text("⏎").font(.system(size: 11 * k, weight: .heavy)).foregroundColor(.white.opacity(0.5))
            } else if let f = game.current {
                Circle().fill(WarlordStyle.colour(f)).frame(width: 12 * k, height: 12 * k).overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                Text("\(w.lordName(f)) 行动中（\(game.seats[f].title)）").font(.system(size: 13 * k, weight: .heavy)).foregroundColor(.white)
                if let said = game.words[f] { Text(said).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(WarlordStyle.gold).lineLimit(1) }
                else if let last = w.chronicle.last, last.faction == f, last.year == w.year, last.month == w.month { Text(last.text).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(.white.opacity(0.75)).lineLimit(1) }
                if game.speed == 0 { Text("· 暂停中，空格继续").font(.system(size: 12 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.7, blue: 0.5)) }
            } else if game.phase == .marching {
                Image(systemName: "figure.walk.motion").font(.system(size: 14 * k, weight: .bold)).foregroundColor(WarlordStyle.gold)
                Text("各路大军行进中… \(w.armies.count) 支").font(.system(size: 13 * k, weight: .heavy)).foregroundColor(.white)
            } else {
                Image(systemName: "scroll.fill").font(.system(size: 14 * k, weight: .bold)).foregroundColor(WarlordStyle.gold)
                Text("本月战报 \(game.told.count) 场").font(.system(size: 13 * k, weight: .heavy)).foregroundColor(.white)
            }
        }
        .padding(.horizontal, 14 * k).padding(.vertical, 8 * k)
        .warlordGlass(k, radius: 14)
        .frame(maxWidth: 760 * k)
    }

    private func hint(_ f: Int, _ w: WarlordWorld) -> String {
        let idle = w.cities(of: f).reduce(0) { $0 + w.idle($1).count }
        let danger = w.cities(of: f).filter { c in w.armies.contains { $0.to == c && $0.faction != f } }
        if !danger.isEmpty { return "⚠️ 敌军正开往" + danger.map { warlordSites[$0].name }.joined(separator: "、") }
        return idle > 0 ? "点城下令 · 还有 \(idle) 员武将待命 · Tab 换城" : "武将都有了差事"
    }
}

// MARK: - The chosen city

struct WarlordCityPanel: View {
    @ObservedObject var game: WarlordGame
    var city: Int
    var k: CGFloat

    var body: some View {
        let w = game.world, x = w.cities[city], site = warlordSites[city]
        let mine = game.mayCommand(city)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8 * k) {
                // Name and master.
                HStack(alignment: .center, spacing: 8 * k) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6 * k).fill(WarlordStyle.colour(x.owner)).frame(width: 34 * k, height: 34 * k)
                        Text(x.owner >= 0 ? warlordBanners[x.owner].mark : "空").font(WarlordStyle.title(19 * k)).foregroundColor(.white).shadow(radius: 1)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6 * k) {
                            Text(site.name).font(WarlordStyle.title(22 * k)).foregroundColor(WarlordStyle.gold)
                            Text(site.province).font(.system(size: 11 * k, weight: .bold)).foregroundColor(.white.opacity(0.6))
                        }
                        Text(x.owner >= 0 ? "\(w.lordName(x.owner))（\(game.seats[x.owner].title)）" + (x.owner == game.mine ? "" : w.allied(game.mine ?? -9, x.owner) ? " · 盟友" : "") : "无主之城").font(.system(size: 11.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Button { game.selected = nil; game.cancel() } label: { Image(systemName: "xmark").font(.system(size: 11 * k, weight: .bold)).foregroundColor(.white.opacity(0.6)) }.buttonStyle(.plain)
                }
                // The numbers.
                Grid(alignment: .leading, horizontalSpacing: 8 * k, verticalSpacing: 3 * k) {
                    GridRow { number("兵", WarlordCommander.troops(x.troops)); number("训练", "\(x.train)"); number("民忠", "\(x.loyalty)") }
                    GridRow { number("金", "\(x.gold)"); number("粮", WarlordCommander.troops(x.grain)); number("人口", WarlordCommander.troops(x.people)) }
                }
                VStack(spacing: 3 * k) {
                    bar("农业", x.farm, Color(red: 0.55, green: 0.8, blue: 0.35))
                    bar("商业", x.trade, Color(red: 1, green: 0.78, blue: 0.3))
                    bar("城防", x.wall, Color(red: 0.7, green: 0.74, blue: 0.82))
                }
                let threat = w.threat(to: city)
                if x.owner >= 0, threat > 0 {
                    Text("⚔︎ 周边敌兵约 \(WarlordCommander.troops(threat))" + (w.armies.contains { $0.to == city && $0.faction != x.owner } ? " · 敌军来袭！" : ""))
                        .font(.system(size: 11 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.62, blue: 0.5))
                }
                // Orders.
                if mine { commands(w) }
                else if let f = game.myTurn, x.owner != f, warlordLinks[city].contains(where: { w.cities[$0.city].owner == f }), !w.allied(f, x.owner) {
                    Text("与我方城池相邻：选中我方城池后「出征」").font(.system(size: 11 * k, weight: .semibold)).foregroundColor(.white.opacity(0.65))
                }
                // The generals here.
                let here = w.present(city)
                if !here.isEmpty {
                    section("武将 \(here.count)" + (mine ? " · 可点选" : ""))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 4 * k), GridItem(.flexible(), spacing: 4 * k)], spacing: 4 * k) {
                        ForEach(here, id: \.self) { o in
                            WarlordOfficerChip(game: game, officer: o, k: k, picked: game.picked == o) { game.picked = game.picked == o ? nil : o }
                        }
                    }
                }
                let marching = w.officers.indices.filter { w.officers[$0].state == .serving && w.officers[$0].army != nil && w.officers[$0].city == city && w.officers[$0].faction == x.owner }
                if !marching.isEmpty { Text("出征在外：" + marching.map { w.name($0) }.joined(separator: "、")).font(.system(size: 11 * k, weight: .semibold)).foregroundColor(.white.opacity(0.65)) }
                // Captives and free generals.
                let held = w.captives(city).filter { w.officers[$0].faction == x.owner }
                let free = w.freeKnown(city)
                if !held.isEmpty {
                    section("俘虏 \(held.count)")
                    ForEach(held, id: \.self) { t in person(t, captive: true, mine: mine) }
                }
                if !free.isEmpty {
                    section("在野 \(free.count)")
                    ForEach(free, id: \.self) { t in person(t, captive: false, mine: mine) }
                }
            }
            .padding(11 * k)
        }
        .warlordGlass(k)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func number(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3 * k) {
            Text(label).font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(WarlordStyle.gold.opacity(0.85))
            Text(value).font(WarlordStyle.num(14 * k)).monospacedDigit().foregroundColor(.white)
        }
        .frame(minWidth: 80 * k, alignment: .leading)
    }

    private func bar(_ label: String, _ v: Int, _ colour: Color) -> some View {
        HStack(spacing: 6 * k) {
            Text(label).font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(WarlordStyle.gold.opacity(0.85)).frame(width: 30 * k, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.4))
                Capsule().fill(colour).frame(width: max(4, 190 * k * CGFloat(v) / 100))
            }
            .frame(width: 190 * k, height: 8 * k)
            Text("\(v)").font(WarlordStyle.num(11 * k)).foregroundColor(.white).frame(width: 26 * k, alignment: .trailing)
        }
    }

    private func section(_ title: String) -> some View {
        HStack(spacing: 6 * k) {
            Text(title).font(WarlordStyle.title(12.5 * k)).foregroundColor(WarlordStyle.gold).lineLimit(1).fixedSize()
            Rectangle().fill(WarlordStyle.gold.opacity(0.3)).frame(height: 1)
        }
        .padding(.top, 2 * k)
    }

    private func commands(_ w: WarlordWorld) -> some View {
        let idle = !w.idle(city).isEmpty
        let who = game.picked.map { w.name($0) } ?? "自动选将"
        return VStack(alignment: .leading, spacing: 5 * k) {
            section("命令 · \(who)")
            let jobs: [(WarlordWork, String)] = [(.farm, "leaf.fill"), (.trade, "bitcoinsign.circle.fill"), (.wall, "building.columns.fill"), (.draft, "person.3.fill"), (.drill, "figure.fencing"), (.search, "magnifyingglass")]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5 * k), count: 3), spacing: 5 * k) {
                ForEach(jobs, id: \.0) { job in
                    WarlordButton(title: job.0.name, symbol: job.1, k: k, on: idle) { game.work(job.0, in: city) }
                        .help(help(job.0, w))
                }
                WarlordButton(title: "移动", symbol: "arrow.left.arrow.right", k: k, on: idle) { game.beginMove(from: city, send: false) }.help("武将带着兵、金、粮搬去相邻的自己的城")
                WarlordButton(title: "运输", symbol: "shippingbox.fill", k: k, on: idle) { game.beginMove(from: city, send: true) }.help("派人把兵、金、粮送到相邻的自己的城")
                WarlordButton(title: "外交", symbol: "scroll", k: k, on: idle) { game.showDiplomacy = true }.help("同盟、离间、劝降")
            }
            WarlordButton(title: "出征", symbol: "flag.fill", k: k, hot: true, on: idle) { game.beginMarch(from: city) }
                .frame(maxWidth: .infinity).help("带兵攻打相邻的敌城或空城")
        }
    }

    private func help(_ job: WarlordWork, _ w: WarlordWorld) -> String {
        switch job {
        case .farm: return "农业提高：秋收的粮更多（50 金）"
        case .trade: return "商业提高：每月的金更多（50 金）"
        case .wall: return "城防提高：守城更牢（60 金）"
        case .draft: return "征兵：约 \(game.officer(for: .draft, in: city).map { w.draftSize($0) } ?? 0) 人，每 10 人 1 金，民忠 −4"
        case .drill: return "训练：兵更能打"
        case .search: return "搜索：寻找人才、宝物"
        }
    }

    private func person(_ t: Int, captive: Bool, mine: Bool) -> some View {
        let w = game.world
        let asker = w.idle(city).max { w.recruitChance($0, t) < w.recruitChance($1, t) }
        let p = asker.map { w.recruitChance($0, t) }
        return HStack(spacing: 6 * k) {
            WarlordOfficerRow(game: game, officer: t, k: k, picked: false, dim: false, compact: true) {}
            if mine {
                VStack(spacing: 3 * k) {
                    WarlordButton(title: "登用" + (p.map { " \(Int($0 * 100))%" } ?? ""), k: k, on: asker != nil) { game.recruit(t, in: city) }
                    if captive {
                        HStack(spacing: 3 * k) {
                            WarlordButton(title: "放", k: k) { game.release(t) }
                            WarlordButton(title: "斩", k: k, hot: true) { game.execute(t) }
                        }
                    }
                }
            }
        }
    }
}

/// A general in two short lines: portrait, name, skill, the four numbers; greyed once they have their order.
struct WarlordOfficerChip: View {
    @ObservedObject var game: WarlordGame
    var officer: Int
    var k: CGFloat
    var picked: Bool
    var tap: () -> Void
    var body: some View {
        let w = game.world, p = warlordPeople[officer], o = w.officers[officer]
        let lord = w.factions.indices.contains(o.faction) && w.factions[o.faction].lord == officer
        return Button(action: tap) {
            HStack(spacing: 5 * k) {
                WarlordFace(officer: officer, faction: o.faction).equatable().frame(width: 30 * k, height: 30 * k)
                VStack(alignment: .leading, spacing: 1 * k) {
                    HStack(spacing: 3 * k) {
                        Text(p.name).font(WarlordStyle.title(12 * k)).foregroundColor(lord ? WarlordStyle.gold : .white).lineLimit(1).fixedSize()
                        if let s = p.skill { Text(s.name).font(.system(size: 8.5 * k, weight: .heavy)).foregroundColor(WarlordStyle.ink).padding(.horizontal, 2.5 * k).background(Capsule().fill(WarlordStyle.gold)).lineLimit(1).fixedSize().help(s.says) }
                        Spacer(minLength: 0)
                        Text(o.done ? "✓" : o.rest > 0 ? "休" : "").font(.system(size: 9 * k, weight: .heavy)).foregroundColor(o.done ? .white.opacity(0.6) : Color(red: 1, green: 0.7, blue: 0.5))
                    }
                    Text("武\(w.war(officer)) 智\(w.wit(officer)) 统\(w.lead(officer)) 政\(w.pol(officer))").font(.system(size: 9 * k, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.8)).lineLimit(1).fixedSize()
                }
            }
            .padding(3.5 * k)
            .background(RoundedRectangle(cornerRadius: 7 * k).fill(picked ? WarlordStyle.gold.opacity(0.3) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7 * k).stroke(picked ? WarlordStyle.gold : .clear, lineWidth: 1.3))
            .opacity(o.done ? 0.5 : 1)
            .help((o.item.map { "◆\(warlordItems[$0].name)：\(warlordItems[$0].says) · " } ?? "") + (lord ? "君主" : "忠诚 \(o.loyalty)"))
        }
        .buttonStyle(.plain)
    }
}

/// A general: portrait, name, the four numbers, skill, treasure and loyalty.
struct WarlordOfficerRow: View {
    @ObservedObject var game: WarlordGame
    var officer: Int
    var k: CGFloat
    var picked: Bool
    var dim: Bool
    var compact = false
    var tap: () -> Void

    var body: some View {
        let w = game.world, p = warlordPeople[officer], o = w.officers[officer]
        let f = o.state == .serving ? o.faction : o.state == .captive ? (w.lastFaction[officer] ?? -1) : -1
        return Button(action: tap) {
            HStack(spacing: 7 * k) {
                WarlordFace(officer: officer, faction: f).equatable().frame(width: 40 * k, height: 40 * k)
                VStack(alignment: .leading, spacing: 2 * k) {
                    HStack(spacing: 5 * k) {
                        Text(p.name).font(WarlordStyle.title(13.5 * k)).foregroundColor(.white)
                        if let s = p.skill { Text(s.name).font(.system(size: 9.5 * k, weight: .heavy)).foregroundColor(WarlordStyle.ink).padding(.horizontal, 4 * k).padding(.vertical, 1 * k).background(Capsule().fill(WarlordStyle.gold)).help(s.says) }
                        if let i = o.item { Text("◆" + warlordItems[i].name).font(.system(size: 9.5 * k, weight: .bold)).foregroundColor(Color(red: 0.6, green: 0.9, blue: 1)).help(warlordItems[i].says) }
                        if w.factions.indices.contains(o.faction), w.factions[o.faction].lord == officer, o.state == .serving { Text("君主").font(.system(size: 9.5 * k, weight: .heavy)).foregroundColor(.white).padding(.horizontal, 4 * k).background(Capsule().fill(WarlordStyle.red)) }
                        Spacer(minLength: 0)
                        if !compact {
                            Text(dim ? "✓已令" : o.rest > 0 ? "休整" : "待命").font(.system(size: 9.5 * k, weight: .bold)).foregroundColor(dim ? .white.opacity(0.5) : o.rest > 0 ? Color(red: 1, green: 0.7, blue: 0.5) : Color(red: 0.6, green: 0.95, blue: 0.6))
                        }
                    }
                    HStack(spacing: 6 * k) {
                        stat("武", w.war(officer)); stat("智", w.wit(officer)); stat("统", w.lead(officer)); stat("政", w.pol(officer))
                        if o.state == .serving, w.factions.indices.contains(o.faction), w.factions[o.faction].lord != officer { Text("忠\(o.loyalty)").font(.system(size: 9.5 * k, weight: .bold)).foregroundColor(o.loyalty < 60 ? Color(red: 1, green: 0.55, blue: 0.45) : .white.opacity(0.6)) }
                    }
                }
            }
            .padding(5 * k)
            .background(RoundedRectangle(cornerRadius: 8 * k).fill(picked ? WarlordStyle.gold.opacity(0.28) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8 * k).stroke(picked ? WarlordStyle.gold : .clear, lineWidth: 1.4))
            .opacity(dim ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }

    private func stat(_ l: String, _ v: Int) -> some View {
        HStack(spacing: 1.5 * k) {
            Text(l).font(.system(size: 9.5 * k, weight: .bold)).foregroundColor(WarlordStyle.gold.opacity(0.8))
            Text("\(v)").font(WarlordStyle.num(11 * k)).foregroundColor(v >= 90 ? Color(red: 1, green: 0.62, blue: 0.4) : .white)
        }
    }
}

// MARK: - The warlords at a glance

struct WarlordFactionPanel: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var body: some View {
        let w = game.world
        let alive = w.factions.indices.filter { w.factions[$0].alive }.sorted { (w.held($0), w.troops(of: $0)) > (w.held($1), w.troops(of: $1)) }
        let total = max(1, alive.reduce(0) { $0 + w.held($1) })
        return VStack(alignment: .leading, spacing: 5 * k) {
            HStack {
                Text("群雄 \(alive.count)").font(WarlordStyle.title(15 * k)).foregroundColor(WarlordStyle.gold)
                Spacer()
                Text("空城 \(w.cities(of: -1).count)").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.6))
            }
            // The realm as one bar, shared out.
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(alive, id: \.self) { f in Rectangle().fill(WarlordStyle.colour(f)).frame(width: geo.size.width * CGFloat(w.held(f)) / CGFloat(WarlordWorld.cityCount)) }
                    Rectangle().fill(Color.white.opacity(0.15))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8 * k)
            VStack(spacing: 2 * k) {
                ForEach(alive, id: \.self) { f in row(f, w, total) }
            }
        }
        .padding(10 * k)
        .warlordGlass(k)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ f: Int, _ w: WarlordWorld, _ total: Int) -> some View {
        Button { if let c = w.cities(of: f).first(where: { w.officers[w.factions[f].lord].city == $0 }) ?? w.cities(of: f).first { game.selected = c; game.look(at: c) } } label: {
            HStack(spacing: 6 * k) {
                WarlordFace(officer: w.factions[f].lord, faction: f).equatable().frame(width: 23 * k, height: 23 * k)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4 * k) {
                        Text(w.lordName(f)).font(WarlordStyle.title(11.5 * k)).foregroundColor(.white).lineLimit(1)
                        Text(game.seats[f].title).font(.system(size: 9 * k, weight: .heavy)).foregroundColor(game.seats[f] == .computer ? .white.opacity(0.5) : WarlordStyle.ink)
                            .padding(.horizontal, 3.5 * k).background(Capsule().fill(game.seats[f] == .computer ? Color.white.opacity(0.1) : WarlordStyle.gold))
                        if let m = game.mine, w.allied(m, f) { Text("盟").font(.system(size: 9 * k, weight: .heavy)).foregroundColor(Color(red: 0.6, green: 0.95, blue: 0.6)) }
                    }
                    Text("\(w.held(f))城 · \(WarlordCommander.troops(w.troops(of: f)))兵 · \(w.staff(of: f).count)将 · \(w.gold(of: f))金").font(.system(size: 9.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
                }
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2 * k).fill(WarlordStyle.colour(f)).frame(width: 5 * k, height: 20 * k)
            }
            .padding(.horizontal, 3 * k).padding(.vertical, 1.5 * k)
            .background(RoundedRectangle(cornerRadius: 7 * k).fill(game.current == f ? WarlordStyle.gold.opacity(0.22) : Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Making an army ready

struct WarlordDraftCard: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var body: some View {
        guard let d = game.draft else { return AnyView(EmptyView()) }
        let w = game.world, x = w.cities[d.to]
        let p = game.chance(d)
        let ready = w.idle(d.from).filter { w.officers[$0].rest == 0 }
        let road = warlordRoad(d.from, d.to)!
        return AnyView(VStack(alignment: .leading, spacing: 9 * k) {
            HStack(spacing: 8 * k) {
                Text("出征").font(WarlordStyle.title(22 * k)).foregroundColor(WarlordStyle.gold)
                Text("\(warlordSites[d.from].name) → \(warlordSites[d.to].name)").font(WarlordStyle.title(17 * k)).foregroundColor(.white)
                Spacer()
                Text(road.kind == .river ? "渡\(road.name)" : road.kind == .pass ? "过\(road.name)" : "平路").font(.system(size: 11 * k, weight: .bold)).foregroundColor(.white.opacity(0.7))
                Text("\(road.months) 月").font(.system(size: 11 * k, weight: .bold)).foregroundColor(.white.opacity(0.7))
            }
            HStack(spacing: 10 * k) {
                VStack(alignment: .leading, spacing: 2 * k) {
                    Text("敌：\(w.banner(x.owner))").font(.system(size: 12 * k, weight: .heavy)).foregroundColor(WarlordStyle.colour(x.owner))
                    Text("兵 \(x.troops) · 城防 \(x.wall) · 训练 \(x.train)").font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                    Text("守将：" + (w.defenders(d.to).map { w.name($0) }.joined(separator: "、").nilIfEmpty ?? "无")).font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(Int((p * 100).rounded()))%").font(WarlordStyle.num(34 * k)).foregroundColor(p >= 0.7 ? Color(red: 0.6, green: 0.95, blue: 0.55) : p >= 0.5 ? WarlordStyle.gold : Color(red: 1, green: 0.5, blue: 0.4))
                    Text("胜算").font(.system(size: 11 * k, weight: .heavy)).foregroundColor(.white.opacity(0.7))
                }
            }
            Text("武将（最多 3 员，第一位为主将）").font(.system(size: 11 * k, weight: .bold)).foregroundColor(WarlordStyle.gold.opacity(0.85))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4 * k) {
                ForEach(ready, id: \.self) { o in
                    let on = d.team.contains(o)
                    WarlordOfficerRow(game: game, officer: o, k: k * 0.9, picked: on, dim: false, compact: true) {
                        guard var nd = game.draft else { return }
                        if on { if nd.team.count > 1 { nd.team.removeAll { $0 == o } } } else if nd.team.count < 3 { nd.team.append(o) }
                        game.draft = nd
                    }
                }
            }
            HStack(spacing: 8 * k) {
                Text("兵力").font(.system(size: 12 * k, weight: .heavy)).foregroundColor(WarlordStyle.gold)
                WarlordSlider(value: Binding(get: { Double(game.draft?.troops ?? 0) }, set: { v in game.draft?.troops = max(300, Int(v) / 100 * 100) }), range: 300...Double(max(301, w.cities[d.from].troops)), colour: WarlordStyle.red, k: k)
                Text("\(d.troops) / \(w.cities[d.from].troops)").font(WarlordStyle.num(13 * k)).monospacedDigit().foregroundColor(.white).frame(width: 110 * k, alignment: .trailing)
            }
            let left = w.cities[d.from].troops - d.troops, threat = w.threat(to: d.from) - (x.owner >= 0 ? x.troops * 7 / 10 : 0)
            Text("行军粮 \(d.troops / 10 * road.months) · 留守 \(left) 兵" + (threat > left ? " · ⚠️ 周边敌兵约 \(threat)" : "")).font(.system(size: 11 * k, weight: .semibold)).foregroundColor(threat > left ? Color(red: 1, green: 0.62, blue: 0.5) : .white.opacity(0.7))
            HStack {
                Spacer()
                WarlordButton(title: "取消", k: k) { game.cancel() }
                WarlordButton(title: "出征！", symbol: "flag.fill", k: k, hot: true) { game.confirmDraft() }
            }
        }
        .padding(16 * k)
        .frame(width: 470 * k)
        .warlordGlass(k, radius: 16))
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

/// A slider drawn like the rest of the page (and drawn offscreen too): a track, its fill, a gold knob to drag.
struct WarlordSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var colour: Color
    var k: CGFloat
    var body: some View {
        GeometryReader { geo in
            let span = max(0.0001, range.upperBound - range.lowerBound)
            let f = CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span)
            let knob = 16 * k, track = geo.size.width - knob
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.45)).frame(height: 7 * k).padding(.horizontal, knob / 2)
                Capsule().fill(colour).frame(width: max(0, track * f), height: 7 * k).padding(.leading, knob / 2)
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.7), Color(red: 0.9, green: 0.68, blue: 0.3)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                    .frame(width: knob, height: knob).offset(x: track * f)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let t = Double(min(1, max(0, (g.location.x - knob / 2) / max(1, track))))
                value = range.lowerBound + t * span
            })
        }
        .frame(height: 20 * k)
    }
}

struct WarlordShipmentCard: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var body: some View {
        guard let s = game.shipment else { return AnyView(EmptyView()) }
        let w = game.world, from = w.cities[s.from]
        return AnyView(VStack(alignment: .leading, spacing: 9 * k) {
            HStack {
                Text(s.stay ? "移动" : "运输").font(WarlordStyle.title(22 * k)).foregroundColor(WarlordStyle.gold)
                Text("\(warlordSites[s.from].name) → \(warlordSites[s.to].name)").font(WarlordStyle.title(17 * k)).foregroundColor(.white)
                Spacer()
                Text(s.stay ? "\(w.name(s.officer))同去" : "\(w.name(s.officer))押运").font(.system(size: 12 * k, weight: .bold)).foregroundColor(.white.opacity(0.75))
            }
            slider("兵", \.troops, from.troops)
            slider("金", \.gold, from.gold)
            slider("粮", \.grain, from.grain)
            HStack {
                Spacer()
                WarlordButton(title: "取消", k: k) { game.cancel() }
                WarlordButton(title: s.stay ? "移动" : "运输", symbol: "checkmark", k: k, hot: true) { game.confirmShipment() }
            }
        }
        .padding(16 * k).frame(width: 420 * k).warlordGlass(k, radius: 16))
    }

    private func slider(_ label: String, _ key: WritableKeyPath<WarlordShipment, Int>, _ most: Int) -> some View {
        HStack(spacing: 8 * k) {
            Text(label).font(.system(size: 12 * k, weight: .heavy)).foregroundColor(WarlordStyle.gold).frame(width: 18 * k)
            WarlordSlider(value: Binding(get: { Double(game.shipment?[keyPath: key] ?? 0) }, set: { v in game.shipment?[keyPath: key] = Int(v) }), range: 0...Double(max(1, most)), colour: WarlordStyle.gold, k: k)
            Text("\(game.shipment?[keyPath: key] ?? 0) / \(most)").font(WarlordStyle.num(12 * k)).monospacedDigit().foregroundColor(.white).frame(width: 110 * k, alignment: .trailing)
        }
    }
}

// MARK: - Diplomacy

struct WarlordDiplomacyCard: View {
    @ObservedObject var game: WarlordGame
    var city: Int
    var k: CGFloat
    var body: some View {
        let w = game.world
        let f = w.cities[city].owner
        let idle = w.idle(city)
        let others = w.factions.indices.filter { $0 != f && w.factions[$0].alive }.sorted { w.strength($0) > w.strength($1) }
        let near = w.reachable(from: city).sorted { w.persuadeChance(idle.first ?? 0, $0) > w.persuadeChance(idle.first ?? 0, $1) }
        return VStack(alignment: .leading, spacing: 8 * k) {
            HStack {
                Text("外交").font(WarlordStyle.title(22 * k)).foregroundColor(WarlordStyle.gold)
                Text("自\(warlordSites[city].name)遣使 · 待命武将 \(idle.count)").font(.system(size: 12 * k, weight: .bold)).foregroundColor(.white.opacity(0.75))
                Spacer()
                Button { game.showDiplomacy = false } label: { Image(systemName: "xmark").font(.system(size: 13 * k, weight: .bold)).foregroundColor(.white.opacity(0.7)) }.buttonStyle(.plain)
            }
            Text("同盟（备礼 \(WarlordWorld.allyCost) 金，三年为期）").font(.system(size: 11.5 * k, weight: .heavy)).foregroundColor(WarlordStyle.gold.opacity(0.9))
            VStack(spacing: 3 * k) {
                    ForEach(others.prefix(9), id: \.self) { g in
                        HStack(spacing: 6 * k) {
                            WarlordFace(officer: w.factions[g].lord, faction: g).equatable().frame(width: 24 * k, height: 24 * k)
                            Text(w.lordName(g)).font(WarlordStyle.title(12.5 * k)).foregroundColor(.white).frame(width: 60 * k, alignment: .leading)
                            Text("\(w.held(g))城 \(WarlordCommander.troops(w.troops(of: g)))兵" + (w.bordering(f, g) ? " · 接壤" : "")).font(.system(size: 10.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                            Spacer()
                            if w.allied(f, g) {
                                Text("盟 \(w.factions[f].allies[g] ?? 0) 月").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(Color(red: 0.6, green: 0.95, blue: 0.6))
                                WarlordButton(title: "背盟", k: k * 0.9, hot: true) { game.breakAlliance(with: g) }
                            } else {
                                let p = idle.map { w.allyChance($0, with: g) }.max() ?? 0
                                WarlordButton(title: "结盟 \(Int(p * 100))%", k: k * 0.9, on: !idle.isEmpty && w.cities[city].gold >= WarlordWorld.allyCost) { game.ally(with: g, from: city) }
                            }
                        }
                    }
            }
            Text("离间 / 劝降（相邻敌城的武将）").font(.system(size: 11.5 * k, weight: .heavy)).foregroundColor(WarlordStyle.gold.opacity(0.9))
            VStack(spacing: 3 * k) {
                    if near.isEmpty { Text("附近没有敌方武将").font(.system(size: 11 * k)).foregroundColor(.white.opacity(0.6)) }
                    ForEach(near.prefix(8), id: \.self) { t in
                        let g = w.officers[t].faction
                        HStack(spacing: 6 * k) {
                            WarlordFace(officer: t, faction: g).equatable().frame(width: 24 * k, height: 24 * k)
                            Text(w.name(t)).font(WarlordStyle.title(12.5 * k)).foregroundColor(.white).frame(width: 52 * k, alignment: .leading)
                            Text("\(w.lordName(g)) · \(warlordSites[w.officers[t].city].name) · 忠\(w.officers[t].loyalty)").font(.system(size: 10.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                            Spacer()
                            let sow = idle.map { w.sowChance($0, t) }.max() ?? 0, pers = idle.map { w.persuadeChance($0, t) }.max() ?? 0
                            WarlordButton(title: "离间 \(Int(sow * 100))%", k: k * 0.85, on: sow > 0) { game.sow(t, from: city) }
                            WarlordButton(title: "劝降 \(Int(pers * 100))%", k: k * 0.85, hot: true, on: pers > 0) { game.persuade(t, from: city) }
                        }
                    }
            }
        }
        .padding(16 * k).frame(width: 520 * k).warlordGlass(k, radius: 16)
    }
}

// MARK: - The month's battles, as cards

struct WarlordReports: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var width: CGFloat
    var body: some View {
        let shown = Array(game.told.prefix(6))
        let columns = min(3, shown.count)
        return VStack(spacing: 10 * k) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(300 * k), spacing: 10 * k), count: max(1, columns)), spacing: 10 * k) {
                ForEach(shown.indices, id: \.self) { i in WarlordBattleCard(game: game, battle: shown[i], k: k) }
            }
            HStack(spacing: 8 * k) {
                if game.told.count > shown.count { Text("另有 \(game.told.count - shown.count) 场").font(.system(size: 12 * k, weight: .bold)).foregroundColor(.white) }
                WarlordButton(title: game.tellWaits ? "知道了" : "继续", symbol: "chevron.right", k: k, hot: true) { game.endTelling() }
            }
        }
        .padding(.top, 60 * k)
    }
}

struct WarlordBattleCard: View {
    @ObservedObject var game: WarlordGame
    var battle: WarlordBattle
    var k: CGFloat
    var body: some View {
        let w = game.world, b = battle
        let ink = WarlordStyle.ink
        return VStack(spacing: 6 * k) {
            HStack {
                Text("\(warlordSites[b.city].name)之战").font(WarlordStyle.title(18 * k)).foregroundColor(ink)
                Spacer()
                Text("\(b.year)年\(b.month)月").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(ink.opacity(0.6))
            }
            HStack(alignment: .top, spacing: 6 * k) {
                side(b.attackers, b.attacker, troops: b.troopsA, left: b.leftA, label: "攻")
                VStack(spacing: 2 * k) {
                    Text("VS").font(.system(size: 14 * k, weight: .black, design: .serif)).foregroundColor(WarlordStyle.red)
                    Text("预估\(Int((b.chance * 100).rounded()))%").font(.system(size: 9 * k, weight: .bold)).foregroundColor(ink.opacity(0.55)).fixedSize()
                }
                .padding(.top, 16 * k)
                side(b.defenders, b.defender, troops: b.troopsD, left: b.leftD, label: "守")
            }
            if let duel = b.duel {
                HStack(spacing: 4 * k) {
                    Image(systemName: "bolt.fill").font(.system(size: 10 * k)).foregroundColor(WarlordStyle.red)
                    Text("单挑：\(w.name(duel.a)) 对 \(w.name(duel.b))，\(w.name(duel.aWon ? duel.a : duel.b))胜，\(w.name(duel.aWon ? duel.b : duel.a))\(duel.fate)")
                        .font(.system(size: 11 * k, weight: .bold)).foregroundColor(ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(5 * k).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5 * k).fill(WarlordStyle.red.opacity(0.1)))
            }
            let taken = b.captured
            if !taken.isEmpty || !b.fled.isEmpty || b.surrendered > 0 {
                Text([taken.isEmpty ? nil : "俘获 " + taken.map { w.name($0) }.joined(separator: "、"),
                      b.fled.isEmpty ? nil : "逃走 " + b.fled.map { w.name($0) }.joined(separator: "、"),
                      b.surrendered > 0 ? "降卒 \(b.surrendered)" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5 * k, weight: .semibold)).foregroundColor(ink.opacity(0.8)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(11 * k)
        .overlay(alignment: .bottomTrailing) {
            // The seal: 攻克 in red, or 击退 in ink.
            Text(b.won ? "攻克" : "击退").font(WarlordStyle.title(15 * k)).foregroundColor(b.won ? WarlordStyle.red : ink.opacity(0.75))
                .padding(.horizontal, 5 * k).padding(.vertical, 2 * k)
                .overlay(RoundedRectangle(cornerRadius: 3 * k).stroke(b.won ? WarlordStyle.red : ink.opacity(0.6), lineWidth: 2 * k))
                .rotationEffect(.degrees(-12)).padding(.bottom, 10 * k).padding(.trailing, 12 * k).opacity(0.85)
        }
        .warlordPaper(k)
    }

    private func side(_ team: [Int], _ f: Int, troops: Int, left: Int, label: String) -> some View {
        let w = game.world
        return VStack(spacing: 3 * k) {
            HStack(spacing: -8 * k) {
                if team.isEmpty {
                    ZStack { Circle().fill(WarlordStyle.colour(f)); Text(label).font(WarlordStyle.title(16 * k)).foregroundColor(.white) }.frame(width: 44 * k, height: 44 * k)
                }
                ForEach(team.prefix(2), id: \.self) { o in WarlordFace(officer: o, faction: f).equatable().frame(width: 44 * k, height: 44 * k) }
            }
            Text(w.banner(f)).font(.system(size: 10.5 * k, weight: .heavy)).foregroundColor(WarlordStyle.colour(f)).lineLimit(1)
            Text(team.first.map { w.name($0) } ?? "守军").font(WarlordStyle.title(12 * k)).foregroundColor(WarlordStyle.ink)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.15))
                Capsule().fill(WarlordStyle.colour(f)).frame(width: 90 * k * CGFloat(left) / CGFloat(max(1, troops)))
            }
            .frame(width: 90 * k, height: 7 * k)
            Text("\(troops) → \(left)").font(WarlordStyle.num(10.5 * k)).monospacedDigit().foregroundColor(WarlordStyle.ink.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Seats

struct WarlordSeatsCard: View {
    @ObservedObject var game: WarlordGame
    var chatModels: [(host: String, models: [String])]
    var k: CGFloat
    var body: some View {
        let w = game.world
        return VStack(alignment: .leading, spacing: 8 * k) {
            HStack {
                Text("谁当哪路诸侯").font(WarlordStyle.title(20 * k)).foregroundColor(WarlordStyle.gold)
                Spacer()
                WarlordButton(title: "全部电脑", k: k * 0.9) { for f in w.factions.indices { game.setSeat(f, .computer) } }
                Button { game.showSeats = false } label: { Image(systemName: "xmark").font(.system(size: 13 * k, weight: .bold)).foregroundColor(.white.opacity(0.7)) }.buttonStyle(.plain)
            }
            Text("我：用鼠标下令，按「结束回合」· 电脑：脚本 · Jev / 大模型：每月从量好的选项里挑一件先做的事，细节由脚本补").font(.system(size: 11 * k, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10 * k), GridItem(.flexible(), spacing: 10 * k)], spacing: 5 * k) {
                ForEach(w.factions.indices, id: \.self) { f in
                    HStack(spacing: 6 * k) {
                        WarlordFace(officer: w.factions[f].lord, faction: f).equatable().frame(width: 26 * k, height: 26 * k)
                        Text(w.lordName(f)).font(WarlordStyle.title(12.5 * k)).foregroundColor(w.factions[f].alive ? .white : .white.opacity(0.35)).frame(width: 48 * k, alignment: .leading)
                        Spacer(minLength: 0)
                        HStack(spacing: 2 * k) {
                            ForEach(WarlordSeat.allCases) { seat in
                                Button { game.setSeat(f, seat) } label: {
                                    Text(seat.title).font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(game.seats[f] == seat ? WarlordStyle.ink : .white.opacity(0.85)).fixedSize()
                                        .padding(.horizontal, 5 * k).padding(.vertical, 3.5 * k)
                                        .background(RoundedRectangle(cornerRadius: 5 * k).fill(game.seats[f] == seat ? AnyShapeStyle(WarlordStyle.gold) : AnyShapeStyle(Color.white.opacity(0.08))))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .opacity(w.factions[f].alive ? 1 : 0.5)
                }
            }
        }
        .padding(16 * k).frame(width: 620 * k).warlordGlass(k, radius: 16)
    }
}

// MARK: - The chronicle

struct WarlordChronicle: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var body: some View {
        let notes = game.world.chronicle.suffix(60).reversed()
        return VStack(alignment: .leading, spacing: 6 * k) {
            HStack {
                Text("史书").font(WarlordStyle.title(20 * k)).foregroundColor(WarlordStyle.ink)
                Spacer()
                Button { game.showChronicle = false } label: { Image(systemName: "xmark").font(.system(size: 13 * k, weight: .bold)).foregroundColor(WarlordStyle.ink.opacity(0.7)) }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 3 * k) {
                    ForEach(Array(notes.prefix(24).enumerated()), id: \.offset) { _, n in
                        HStack(alignment: .firstTextBaseline, spacing: 6 * k) {
                            Text("\(n.year).\(n.month)").font(.system(size: 10 * k, weight: .bold, design: .monospaced)).foregroundColor(WarlordStyle.ink.opacity(0.55))
                            Circle().fill(WarlordStyle.colour(n.faction)).frame(width: 7 * k, height: 7 * k)
                            Text(n.text).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(WarlordStyle.ink)
                        }
                    }
            }
            .frame(height: 400 * k, alignment: .top).clipped()
        }
        .padding(16 * k).frame(width: 440 * k).warlordPaper(k, radius: 12)
    }
}

// MARK: - Beginning and end

struct WarlordStartCard: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var body: some View {
        let mine = game.seats.indices.filter { game.seats[$0] == .me }
        return VStack(spacing: 10 * k) {
            Text("三国争霸").font(WarlordStyle.title(40 * k)).foregroundColor(WarlordStyle.gold).shadow(color: .black, radius: 2)
            Text("公元 190 年 · 董卓乱政，群雄并起").font(WarlordStyle.title(16 * k)).foregroundColor(.white)
            HStack(spacing: -6 * k) {
                ForEach([5, 0, 1, 2, 3, 4], id: \.self) { f in WarlordFace(officer: game.world.factions[f].lord, faction: f).equatable().frame(width: 50 * k, height: 50 * k) }
            }
            Text(mine.isEmpty ? "你在观战：十七路诸侯全由电脑、Jev 或大模型来下" : "你是 " + mine.map { game.world.lordName($0) }.joined(separator: "、") + " · 统一四十三城即胜")
                .font(.system(size: 13 * k, weight: .semibold)).foregroundColor(.white.opacity(0.85))
            HStack(spacing: 10 * k) {
                WarlordButton(title: "选势力 / 座位", symbol: "person.2.fill", k: k) { game.showSeats = true }
                Button { game.speed = 1 } label: {
                    HStack(spacing: 8 * k) {
                        Image(systemName: "flag.fill").font(.system(size: 16 * k, weight: .bold))
                        Text("开始").font(WarlordStyle.title(22 * k))
                        Text("空格").font(.system(size: 10 * k, weight: .heavy)).padding(.horizontal, 5 * k).padding(.vertical, 2 * k).background(RoundedRectangle(cornerRadius: 4 * k).fill(Color.white.opacity(0.25)))
                    }
                    .foregroundColor(.white).padding(.horizontal, 22 * k).padding(.vertical, 9 * k)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.92, green: 0.32, blue: 0.2), Color(red: 0.6, green: 0.1, blue: 0.08)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Capsule().stroke(WarlordStyle.gold.opacity(0.8), lineWidth: 1.5 * k))
                    .shadow(color: Color(red: 1, green: 0.4, blue: 0.2).opacity(0.5), radius: 12 * k)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(26 * k)
        .warlordGlass(k, radius: 20)
    }
}

struct WarlordEndCard: View {
    @ObservedObject var game: WarlordGame
    var k: CGFloat
    var body: some View {
        let w = game.world
        let winner = w.winner
        let me = game.seats.indices.filter { game.seats[$0] == .me }
        let title = winner.map { me.contains($0) ? "天下一统！" : "\(w.lordName($0))统一天下" } ?? "天下无主"
        return VStack(spacing: 10 * k) {
            if let f = winner {
                WarlordFace(officer: w.factions[f].lord, faction: f).equatable().frame(width: 120 * k, height: 120 * k)
            }
            Text(title).font(WarlordStyle.title(38 * k)).foregroundColor(WarlordStyle.red)
            if let f = winner {
                Text("\(w.date) · 历时 \(w.turns / 12) 年 \(w.turns % 12) 月 · \(game.seats[f].title)").font(WarlordStyle.title(15 * k)).foregroundColor(WarlordStyle.ink)
                Text("麾下 \(w.staff(of: f).count) 员武将 · 兵 \(w.troops(of: f)) · 金 \(w.gold(of: f))").font(.system(size: 13 * k, weight: .semibold)).foregroundColor(WarlordStyle.ink.opacity(0.8))
                let stars = w.staff(of: f).sorted { warlordPeople[$0].total > warlordPeople[$1].total }.prefix(8)
                HStack(spacing: -4 * k) { ForEach(Array(stars), id: \.self) { o in WarlordFace(officer: o, faction: f).equatable().frame(width: 40 * k, height: 40 * k) } }
            }
            if !me.isEmpty, winner.map({ !me.contains($0) }) ?? true { Text("我方势力已灭").font(.system(size: 13 * k, weight: .bold)).foregroundColor(WarlordStyle.ink.opacity(0.7)) }
            WarlordButton(title: "再来一局", symbol: "arrow.counterclockwise", k: k, hot: true) { game.restart() }
        }
        .padding(28 * k)
        .warlordPaper(k, radius: 16)
    }
}

// MARK: - The mouse

struct WarlordMouse: NSViewRepresentable {
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {}

    final class Catcher: NSView {
        private var down: CGPoint?
        private var dragged = false
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        }
        private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
        override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { WarlordGame.shared.hover = WarlordGame.shared.city(at: point(event)) } }
        override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { WarlordGame.shared.hover = nil } }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
            down = point(event); dragged = false
        }
        override func mouseDragged(with event: NSEvent) {
            MainActor.assumeIsolated {
                if let d = down, hypot(point(event).x - d.x, point(event).y - d.y) > 4 { dragged = true }
                if dragged { WarlordGame.shared.pan(event.deltaX, event.deltaY) }
            }
        }
        override func mouseUp(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = WarlordGame.shared
                if !dragged { game.click(game.city(at: point(event))) }
            }
            down = nil
        }
        override func rightMouseDown(with event: NSEvent) { MainActor.assumeIsolated { WarlordGame.shared.cancel() } }
        override func scrollWheel(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = WarlordGame.shared
                if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                    game.zoom(by: pow(1.02, event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.5 : 3)), at: point(event))
                } else { game.pan(event.scrollingDeltaX, event.scrollingDeltaY) }
            }
        }
        override func magnify(with event: NSEvent) { MainActor.assumeIsolated { WarlordGame.shared.zoom(by: 1 + event.magnification, at: point(event)) } }
    }
}

/// The keyboard while the map is showing: space pauses or goes on, Return ends the turn, 1–3 the speed, Esc lets go,
/// arrows move, = and - zoom, Tab the next city of one's own, F the warlords, S the seats, L the chronicle.
@MainActor
enum WarlordKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !(event.window?.firstResponder is NSText) else { return event }
            let game = WarlordGame.shared
            switch event.keyCode {
            case 53:
                if game.targeting != nil || game.draft != nil || game.shipment != nil { game.cancel() }
                else if game.showDiplomacy || game.showSeats || game.showChronicle { game.showDiplomacy = false; game.showSeats = false; game.showChronicle = false }
                else { game.selected = nil }
                return nil
            case 49: if game.phase == .telling { game.endTelling() } else { game.speed = game.speed == 0 ? 1 : 0 }; return nil
            case 36, 76:
                if game.draft != nil { game.confirmDraft() } else if game.shipment != nil { game.confirmShipment() }
                else if game.phase == .telling { game.endTelling() } else { game.endTurn() }
                return nil
            case 18, 19, 20: game.speed = [1, 2, 4][Int(event.keyCode) - 18]; return nil
            case 48: game.nextCity(); return nil
            case 3: game.showFactions.toggle(); return nil
            case 1: game.showSeats.toggle(); return nil
            case 37: game.showChronicle.toggle(); return nil
            case 123: game.pan(120, 0); return nil
            case 124: game.pan(-120, 0); return nil
            case 125: game.pan(0, -120); return nil
            case 126: game.pan(0, 120); return nil
            case 24: game.zoom(by: 1.25); return nil
            case 27: game.zoom(by: 0.8); return nil
            default: return event
            }
        }
    }
    static func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
