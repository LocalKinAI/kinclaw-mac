import Foundation

/// 活山水: a living ink painting beside her in companion mode that paints what the conversation is about
/// (「陪伴模式里她边聊边画：你说到海，她旁边就慢慢洇出一幅水墨的海」, 2026-10-09). One scene of huashu's,
/// <art>/live/shanshui, drawn from 《倩影》's ink library; it changes by an ink bloom when the topic
/// does — what the person says goes to `SS.hear`, the subject of her reply (its tag) to `SS.paint` —
/// and its knobs are the play: 画题, 天气, 季节, 时辰, 风, and 回眸 (the woman in it turns back).
@MainActor
final class ShanShui: ObservableObject {
    static let shared = ShanShui()
    static let shownKey = "kinclaw.companion.shanshui"

    let player = LivePlayer()
    /// Beside her, or folded away to a chip.
    @Published var shown = UserDefaults.standard.object(forKey: ShanShui.shownKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(shown, forKey: Self.shownKey) }
    }
    private var loaded = false

    private init() {}

    /// The painting is on this Mac.
    var available: Bool {
        FileManager.default.fileExists(atPath: LiveFilm.folder.appendingPathComponent("shanshui/engine/eras_shanshui.js").path)
    }

    /// Loaded once and playing, looping.
    func start() {
        guard available else { return }
        if !loaded, let film = LiveFilm.shared.film(named: "shanshui"), film.id == "shanshui" {
            loaded = true
            LiveFilm.load(film, into: player)
            Task { [player] in
                await player.untilReady()
                player.setLoops(true)
                player.play()
            }
        } else if loaded, player.ready, !player.playing {
            player.play()
        }
    }

    func pause() { player.pause() }

    /// What the person said: the painting changes when it names something it can paint.
    func hear(_ text: String) { player.call("window.SS && SS.hear(\(Self.quoted(text)))") }

    /// What her reply is about (its tag's subject).
    func paint(_ subject: String) {
        guard !subject.isEmpty else { return }
        player.call("window.SS && SS.paint(\(Self.quoted(subject)))")
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [String(text.prefix(400))])) ?? Data("[\"\"]".utf8)
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }
}
