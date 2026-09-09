import Foundation

/// The Kokoro voices worth offering. The model ships more (Spanish,
/// French, Hindi…) but the two languages this app is spoken in are
/// Chinese and English, and a picker with forty entries is a picker
/// nobody uses.
struct KokoroVoice: Identifiable, Hashable {
    let id: String
    let label: String
    /// "zh" / "en" — which half of a mixed reply this voice takes.
    var lang: String { TextSegmenter.language(forVoice: id) }

    static let all: [KokoroVoice] = [
        KokoroVoice(id: "zf_xiaoxiao", label: "晓晓 · 女"),
        KokoroVoice(id: "zf_xiaobei",  label: "晓北 · 女"),
        KokoroVoice(id: "zf_xiaoni",   label: "晓妮 · 女"),
        KokoroVoice(id: "zf_xiaoyi",   label: "晓伊 · 女"),
        KokoroVoice(id: "zm_yunxi",    label: "云希 · 男"),
        KokoroVoice(id: "zm_yunyang",  label: "云扬 · 男"),
        KokoroVoice(id: "zm_yunjian",  label: "云健 · 男"),
        KokoroVoice(id: "zm_yunxia",   label: "云夏 · 男"),
        KokoroVoice(id: "af_heart",    label: "Heart · F"),
        KokoroVoice(id: "af_bella",    label: "Bella · F"),
        KokoroVoice(id: "af_nicole",   label: "Nicole · F"),
        KokoroVoice(id: "af_sarah",    label: "Sarah · F"),
        KokoroVoice(id: "bf_emma",     label: "Emma · F (UK)"),
        KokoroVoice(id: "am_michael",  label: "Michael · M"),
        KokoroVoice(id: "am_adam",     label: "Adam · M"),
        KokoroVoice(id: "bm_george",   label: "George · M (UK)"),
    ]

    static var chinese: [KokoroVoice] { all.filter { $0.lang == "zh" } }
    static var english: [KokoroVoice] { all.filter { $0.lang == "en" } }

    /// A line to hear a voice with before committing to it.
    static func sample(for lang: String) -> String {
        lang == "zh" ? "你好呀，我是小美。今天过得怎么样？" : "Hi, I'm here. How was your day?"
    }

    /// Speeds that still sound like a person; Kokoro renders at the
    /// rate rather than time-stretching, so 1.2 is brisk, not chipmunk.
    static let speeds: [Double] = [0.9, 1.0, 1.1, 1.2, 1.3]
}
