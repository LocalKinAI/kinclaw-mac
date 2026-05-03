import Foundation

/// Per-agent / per-domain "suggested prompts" surfaced on the empty
/// welcome card. Click → input gets filled, ⌘⏎ sends. Same pattern
/// ChatGPT / Claude / Perplexity use to give users a starting point
/// rather than dumping them in front of a blank text field.
///
/// Lookup order:
///   1. Per-slug overrides (3-4 hand-written prompts for marquee
///      agents — Pilot / Coder / Critic / Guyon / 黄帝 etc.)
///   2. Per-domain fallback (kinclaw / spiritual / tcm / core)
///   3. Generic fallback ("Hi", "Help me with X", etc.)
enum AgentSuggestions {

    /// Up to 4 prompts per agent. Bilingual where the agent is
    /// bilingual (Selah masters / Heal masters / Core 中文 tutors).
    static func suggestions(for agent: Agent) -> [String] {
        // 1. Slug-specific overrides (ordered by user-facing weight)
        if let slug = bySlug[agent.slug] { return slug }

        // 2. Domain fallback
        if let dom = byDomain[agent.domain ?? ""] {
            return dom
        }

        // 3. Generic
        return generic
    }

    // MARK: - Per-slug curated prompts

    private static let bySlug: [String: [String]] = [
        // ── KinClaw computer-use souls ──
        "pilot": [
            "打开 System Settings 切到深色模式",
            "Take a screenshot of the frontmost window",
            "Search Hacker News for the top story today",
            "List the apps in /Applications by size",
        ],
        "coder": [
            "Write a Go HTTP server with one /health endpoint",
            "Refactor this Python script to use async",
            "Explain this regex: ^[a-z][a-z0-9_]*$",
            "Generate a Dockerfile for a Node 22 service",
        ],
        "critic": [
            "Review my last commit — what would you change?",
            "Find redundant code in this file",
            "What's wrong with this API design?",
        ],
        "curator": [
            "Organize my Downloads folder by file type",
            "Summarize the last 3 days of my Notes",
            "Find duplicates in ~/Documents",
        ],
        "eye": [
            "What's on my screen right now?",
            "Read the highlighted text",
            "Describe this image (drag-drop one)",
        ],
        "marketer": [
            "Write a tweet announcing a new Mac app",
            "Draft a Reddit post for r/LocalLLaMA",
            "ProductHunt tagline for an AI agent dock",
        ],
        "researcher": [
            "Find recent papers on local LLM agents",
            "Summarize the latest macOS accessibility APIs",
            "What's new in MLX this week?",
        ],

        // ── Selah / Faith — most-clicked masters ──
        "guyon": [
            "什么是默观祈祷?",
            "我对神感到枯干 — 怎么办?",
            "What does the dark night of the soul mean?",
            "如何放下自我意志?",
        ],
        "lawrence": [
            "How do I practice the presence of God in daily life?",
            "我洗碗的时候怎么默想神?",
            "Is it normal to feel nothing during prayer?",
        ],
        "augustine": [
            "What is restless heart? Confessions Book 1.",
            "如何理解原罪?",
            "On the Trinity — give me a 3-min summary",
        ],
        "watchman_nee": [
            "什么是属灵人 vs 属魂人?",
            "如何分辨魂与灵?",
            "Explain the threefold man",
        ],

        // ── Heal / 岐黄 — most-clicked TCM masters ──
        "huang_di": [
            "什么是阴阳?用日常生活举例",
            "How do the 5 elements relate to organs?",
            "我手脚冰凉是什么体质?",
        ],
        "zhang_zhongjing": [
            "感冒初起怎么辨证?",
            "桂枝汤和麻黄汤区别在哪?",
            "What is 六经辨证 in plain English?",
        ],
        "li_shizhen": [
            "如何辨认伪劣中药材?",
            "Tell me about ginseng — 真假鉴别",
            "本草纲目里最神奇的一味药是什么?",
        ],
        "sun_simiao": [
            "How does diet relate to longevity?",
            "失眠最简单的食疗方法?",
            "千金方里关于女性养生的核心原则?",
        ],

        // ── Core — api.localkin.dev/ headliners ──
        "english": [
            "Roleplay: ordering coffee at Starbucks, slow",
            "Correct my last paragraph",
            "Practice job interview — software engineer",
            "Explain the difference: 'a few' vs 'few'",
        ],
        "tcm": [
            "我手脚冰凉,中医怎么解释?",
            "How does TCM differ from Western medicine?",
            "Explain 气血两虚 in everyday terms",
        ],
        "citizen": [
            "Quiz me on the 100 USCIS questions",
            "What are the 3 branches of government?",
            "请用中文解释美国宪法第一修正案",
        ],
        "spanish": [
            "Roleplay: ordering tacos in Mexico City",
            "Correct my Spanish: voy a la escuela ayer",
            "Teach me 5 useful phrases for travel",
        ],
        "chinese-tutor": [
            "教我用中文点菜",
            "What's the difference between 你好 and 您好?",
            "Roleplay: lost in 北京 asking for directions",
        ],
        "house": [
            "湾区现在 750k 以下有什么 SFH listings?",
            "What's the property tax in Sunnyvale vs Mountain View?",
            "What should I check before offering on a 1970s home?",
        ],
        "wanshitong": [
            "Find recent ArXiv papers on agentic computer use",
            "What's the most-cited paper on Mixture of Experts?",
            "Today's HuggingFace daily — top 3",
        ],
        "art-guardian": [
            "How does invisible watermarking work?",
            "Apply Glaze-style protection to this image",
            "What's the difference between Glaze and Nightshade?",
        ],
        "meal": [
            "本周给 4 口之家定个晚餐计划,$80 预算内",
            "What's a 15-min protein-heavy lunch?",
            "我家有过敏 (花生),怎么计划?",
        ],
        "kids": [
            "South Bay 这周末适合 5 岁孩子的免费活动?",
            "Best library story-time hours in Mountain View",
            "下雨天室内活动推荐",
        ],
        "events": [
            "What's happening this weekend in Palo Alto?",
            "Free concerts in San Jose this month",
            "Family-friendly events near Cupertino Saturday",
        ],
        "food": [
            "South Bay 现在最热的 ramen 店?",
            "Best dim sum within 10 miles",
            "我想约会,fancy but not stiff,$80/人 around",
        ],
        "grocery": [
            "Trader Joe's 这周有啥好的特价?",
            "Costco 哪些 deal 现在最值得?",
            "South Bay 哪家亚洲超市最便宜?",
        ],
        "camping": [
            "NorCal 这周末适合露营的地方?",
            "Big Sur 现在 permits 还有吗?",
            "Tahoe 适合新手的车 camping 营地?",
        ],
        "travel-rescue": [
            "我的航班取消了 — 怎么办?",
            "丢了护照在欧洲,help",
            "What's the fastest visa-free route home from Tokyo?",
        ],
        "scout-web": [
            "Today's GitHub trending — top 5",
            "What's blowing up on r/LocalLLaMA right now?",
            "Find me an MLX local-agent repo with > 500 stars",
        ],
    ]

    // MARK: - Per-domain fallbacks

    private static let byDomain: [String: [String]] = [
        "kinclaw": [
            "What can you do?",
            "Take a screenshot of the frontmost app",
            "Open Notes and write 'Hello from KinClaw'",
        ],
        "spiritual": [
            "What was your most important teaching?",
            "我应该读你的哪本书?",
            "你那个时代的人和现在的人最大的差别?",
        ],
        "tcm": [
            "我体质偏寒,日常应该注意什么?",
            "What's your signature formula?",
            "Diagnose me — 我最近老是失眠",
        ],
        "core": [
            "What can you help with?",
            "Show me your specialty in one example",
            "Quick start — 3 useful things you do",
        ],
    ]

    // MARK: - Generic last-resort

    private static let generic: [String] = [
        "Hi — what can you do?",
        "Tell me about yourself",
        "Give me a 3-line summary of your specialty",
    ]
}
