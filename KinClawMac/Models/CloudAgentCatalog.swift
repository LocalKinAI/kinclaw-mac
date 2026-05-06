import Foundation

/// Static catalog of cloud LocalKin agents — the spiritual + TCM
/// masters served by `api.localkin.dev/v1/chat?agent=<slug>`.
///
/// Why static and not /v1/agents discovery: the cloud no longer
/// exposes a public agent-list endpoint (it returned 404 as of
/// 2026-05-03). Each vertical app — faith.localkin.ai, heal.localkin.ai
/// — ships its OWN hardcoded master list inside the Next.js bundle
/// (see `localkin-player/src/app/{selah,heal}/masters.ts`). KinClaw
/// Mac mirrors that pattern: a baked-in catalog refreshed on each
/// release rather than a live fetch.
///
/// Generated 2026-05-03 from localkin-player commit at the time;
/// 42 spiritual + 39 TCM = 81 masters total.
struct CloudMaster: Codable, Identifiable, Hashable {
    let slug: String
    let nameZh: String
    let nameEn: String
    let era: String
    let avatar: String
    let domain: String

    var id: String { slug }
}

extension CloudMaster {
    /// Bridge to the existing `Agent` model so AgentListView /
    /// SpotlightContentView render cloud masters without a parallel
    /// rendering path.
    var asAgent: Agent {
        Agent(
            name: nameEn,
            slug: slug,
            port: nil,
            model: nil,
            online: true,
            // Marker — the new chat URL is built from this hostname
            // plus the slug query param in SSEClient.
            hostname: "api.localkin.dev",
            domain: domain,
            // nil tells ChatView/SpotlightContentView to use the
            // cloud transport.
            localSoulPath: nil
        )
    }

    /// Brief one-line description for gallery cards. Layered:
    ///
    ///   1. Hardcoded `notableTagline` for the most famous masters
    ///      ("Doctor of grace, City of God") — gives the gallery
    ///      faith.localkin.ai-style content density.
    ///   2. Otherwise: derived period from start year + era
    ///      ("Patristic · 354-430") — works for any master we
    ///      haven't hand-written a tagline for.
    ///   3. Core / non-spiritual / non-TCM domains: era is already
    ///      a tagline (e.g. "Soul anchor & inner way"), pass through.
    var tagline: String {
        if let notable = Self.notableTagline[slug] {
            return notable
        }
        switch domain {
        case "spiritual":
            if let period = spiritualPeriod {
                return "\(period) · \(era)"
            }
        case "tcm":
            if let dynasty = tcmDynasty {
                return "\(dynasty) · \(era)"
            }
        default:
            break
        }
        return era
    }

    /// Map start year → spiritual era. Crude (Patristic / Medieval
    /// / Reformation / Modern / Contemporary) but useful — a single
    /// year-range like "354-430" reads better as "Patristic · 354-430".
    private var spiritualPeriod: String? {
        guard let year = startYear else { return nil }
        switch year {
        case ..<500:    return "Patristic"
        case 500..<1300: return "Medieval"
        case 1300..<1517: return "Late Medieval"
        case 1517..<1700: return "Reformation"
        case 1700..<1900: return "Modern"
        default:        return "Contemporary"
        }
    }

    /// Map start year → Chinese dynasty for TCM masters.
    private var tcmDynasty: String? {
        guard let year = startYear else { return nil }
        switch year {
        case ..<221:    return "汉 · Han"
        case 221..<618: return "魏晋南北朝 · Pre-Tang"
        case 618..<907: return "唐 · Tang"
        case 907..<1279: return "宋 · Song"
        case 1279..<1368: return "元 · Yuan"
        case 1368..<1644: return "明 · Ming"
        case 1644..<1912: return "清 · Qing"
        default:        return "近现代 · Modern"
        }
    }

    /// Parse the leading 4-digit year out of an era string. Handles
    /// "354-430", "145-208 AD", "14世纪", "1954-" etc. Returns nil
    /// for non-numeric eras (e.g. "Daily trending scan" used by
    /// Core agents — they fall through to .era directly).
    private var startYear: Int? {
        let scanner = Scanner(string: era)
        scanner.charactersToBeSkipped = .whitespaces
        var n: Int = 0
        if scanner.scanInt(&n) { return n }
        return nil
    }

    /// Hand-written taglines for the most famous masters. Kept as a
    /// flat dict so anyone can drop in a new line without code
    /// changes. Conservative — only added when the description is
    /// well-known and accurate; obscure masters fall through to
    /// auto-derived "Period · era".
    private static let notableTagline: [String: String] = [
        // Spiritual
        "augustine":           "Doctor of grace · City of God",
        "john_calvin":         "Reformed theology · Institutes",
        "martin_luther":       "Reformation founder · sola fide",
        "john_wesley":         "Methodist movement · holiness",
        "dietrich_bonhoeffer": "Cost of discipleship",
        "watchman_nee":        "Spiritual man · inner life",
        "aw_tozer":            "Pursuit of God",
        "austin_sparks":       "Eternal purpose · church",
        "guyon":               "Quietism · sweet release",
        "lawrence":            "Practice of God's presence",
        "charles_spurgeon":    "Prince of preachers",
        "kempis":              "Imitation of Christ",
        "therese":             "Little way · 小德兰",
        "newman":              "Apologia · Tractarian",
        "song_shangjie":       "China revival · 1930s",
        "wang_mingdao":        "Chinese house church",
        "hudson_taylor":       "China Inland Mission",
        "george_muller":       "Faith orphan houses",
        // TCM
        "zhang_zhongjing":     "伤寒杂病论 · classical 辨证",
        "sun_simiao":          "药王 · 千金方 · 备急药方",
        "li_shizhen":          "本草纲目 · herbal compendium",
        "hua_tuo":             "外科 · 麻沸散 anesthetic",
        "ni_haixia":           "近代经方 · 视频教学",
        "huang_huang":         "经方 · 体质医学",
        "huangdi_neijing":     "黄帝内经 · 中医起源",
    ]
}

enum CloudAgentCatalog {
    /// All baked-in cloud masters. Order: Core (api.localkin.dev/
    /// landing) → Selah → Heal.
    static let all: [CloudMaster] = [
        // ── Core — `localkin/scripts/serve.sh` AGENTS array
        //          (17 agents publicly tunneled to *.localkin.dev) ──
        // Source of truth: the AGENTS=( ) bash array in serve.sh
        // (each line `internal_name:port:subdomain` — we use the
        // subdomain as the gateway slug, which is what
        // `?agent=<slug>` expects). Re-mirror this list when serve.sh
        // changes.
        //
        // Some slugs overlap with Selah (guyon = spiritual master)
        // and Heal (tcm = TCM general entry point). Agent.id includes
        // the domain so they don't collide in lists.
        .init(slug: "english",
              nameZh: "英语导师",
              nameEn: "English Tutor",
              era: "Immersive AI English coach",
              avatar: "🎓",
              domain: "core"),
        .init(slug: "tcm",
              nameZh: "中医大师",
              nameEn: "TCM Master",
              era: "张仲景 · classical 辨证",
              avatar: "🏥",
              domain: "core"),
        .init(slug: "guyon",
              nameZh: "盖恩夫人",
              nameEn: "Madame Guyon",
              era: "Soul anchor & inner way",
              avatar: "🕊️",
              domain: "core"),
        .init(slug: "citizen",
              nameZh: "入籍教练",
              nameEn: "Citizenship Coach",
              era: "US citizenship test prep",
              avatar: "🇺🇸",
              domain: "core"),
        .init(slug: "spanish",
              nameZh: "西班牙语导师",
              nameEn: "Spanish Tutor",
              era: "Bilingual fun for kids",
              avatar: "🇪🇸",
              domain: "core"),
        .init(slug: "chinese-tutor",
              nameZh: "中文导师",
              nameEn: "Chinese Tutor",
              era: "ABC kids · 25 scenarios",
              avatar: "🇨🇳",
              domain: "core"),
        .init(slug: "house",
              nameZh: "猎房官",
              nameEn: "House Hunter",
              era: "湾区 real-estate scout",
              avatar: "🏠",
              domain: "core"),
        .init(slug: "scout-web",
              nameZh: "GitHub 侦察",
              nameEn: "GitHub Scout Web",
              era: "Daily trending scan",
              avatar: "🛰",
              domain: "core"),
        .init(slug: "art-guardian",
              nameZh: "艺术守护",
              nameEn: "Art Guardian",
              era: "Invisible watermark for artists",
              avatar: "🎨",
              domain: "core"),
        .init(slug: "grocery",
              nameZh: "买菜侦察",
              nameEn: "Grocery Scout",
              era: "South Bay deal hunter",
              avatar: "🛒",
              domain: "core"),
        .init(slug: "kids",
              nameZh: "亲子雷达",
              nameEn: "Kids Radar",
              era: "South Bay family activities",
              avatar: "🧒",
              domain: "core"),
        .init(slug: "meal",
              nameZh: "膳食规划",
              nameEn: "Meal Planner",
              era: "Family nutritionist & chef",
              avatar: "🍽️",
              domain: "core"),
        .init(slug: "camping",
              nameZh: "露营猎手",
              nameEn: "Camping Hunter",
              era: "NorCal outdoor scout",
              avatar: "⛺",
              domain: "core"),
        .init(slug: "events",
              nameZh: "活动雷达",
              nameEn: "Event Scout",
              era: "South Bay weekend curator",
              avatar: "📅",
              domain: "core"),
        .init(slug: "food",
              nameZh: "美食评论",
              nameEn: "Food Critic",
              era: "South Bay restaurant intel",
              avatar: "🍕",
              domain: "core"),
        .init(slug: "wanshitong",
              nameZh: "万事通",
              nameEn: "Wan Shi Tong",
              era: "ArXiv paper scout",
              avatar: "📚",
              domain: "core"),
        .init(slug: "travel-rescue",
              nameZh: "旅行救援",
              nameEn: "Travel Rescue",
              era: "Emergency rescue protocol",
              avatar: "🚨",
              domain: "core"),

        // ── Selah / Faith — spiritual (42 masters) ──
        .init(slug: "irenaeus", nameZh: "爱任纽", nameEn: "Irenaeus", era: "130-202", avatar: "📜", domain: "spiritual"),
        .init(slug: "athanasius", nameZh: "亚他那修", nameEn: "Athanasius", era: "296-373", avatar: "⚔️", domain: "spiritual"),
        .init(slug: "chrysostom", nameZh: "金口约翰", nameEn: "John Chrysostom", era: "347-407", avatar: "🎙️", domain: "spiritual"),
        .init(slug: "guyon", nameZh: "盖恩夫人", nameEn: "Madame Guyon", era: "1648-1717", avatar: "🕊", domain: "spiritual"),
        .init(slug: "murray", nameZh: "慕安德烈", nameEn: "Andrew Murray", era: "1828-1917", avatar: "🔥", domain: "spiritual"),
        .init(slug: "lawrence", nameZh: "劳伦斯弟兄", nameEn: "Brother Lawrence", era: "1614-1691", avatar: "☕", domain: "spiritual"),
        .init(slug: "john_cross", nameZh: "十字若望", nameEn: "St. John of the Cross", era: "1542-1591", avatar: "🌙", domain: "spiritual"),
        .init(slug: "teresa_avila", nameZh: "大德兰", nameEn: "St. Teresa of Avila", era: "1515-1582", avatar: "🏰", domain: "spiritual"),
        .init(slug: "therese", nameZh: "小德兰", nameEn: "St. Thérèse of Lisieux", era: "1873-1897", avatar: "🌹", domain: "spiritual"),
        .init(slug: "molinos", nameZh: "莫利诺斯", nameEn: "Miguel de Molinos", era: "1628-1696", avatar: "🕌", domain: "spiritual"),
        .init(slug: "cloud_author", nameZh: "不知之云", nameEn: "Cloud of Unknowing", era: "14世纪", avatar: "☁", domain: "spiritual"),
        .init(slug: "charles_spurgeon", nameZh: "司布真", nameEn: "Charles Spurgeon", era: "1834-1892", avatar: "👑", domain: "spiritual"),
        .init(slug: "dl_moody", nameZh: "慕迪", nameEn: "D.L. Moody", era: "1837-1899", avatar: "📢", domain: "spiritual"),
        .init(slug: "aw_tozer", nameZh: "陶恕", nameEn: "A.W. Tozer", era: "1897-1963", avatar: "🔥", domain: "spiritual"),
        .init(slug: "jonathan_edwards", nameZh: "爱德华兹", nameEn: "Jonathan Edwards", era: "1703-1758", avatar: "🔥", domain: "spiritual"),
        .init(slug: "martyn_lloyd_jones", nameZh: "钟马田", nameEn: "Martyn Lloyd-Jones", era: "1899-1981", avatar: "📖", domain: "spiritual"),
        .init(slug: "charles_finney", nameZh: "芬尼", nameEn: "Charles Finney", era: "1792-1875", avatar: "💥", domain: "spiritual"),
        .init(slug: "john_wesley", nameZh: "卫斯理", nameEn: "John Wesley", era: "1703-1791", avatar: "❤️", domain: "spiritual"),
        .init(slug: "dietrich_bonhoeffer", nameZh: "潘霍华", nameEn: "Dietrich Bonhoeffer", era: "1906-1945", avatar: "✝️", domain: "spiritual"),
        .init(slug: "martin_luther", nameZh: "路德", nameEn: "Martin Luther", era: "1483-1546", avatar: "📜", domain: "spiritual"),
        .init(slug: "augustine", nameZh: "奥古斯丁", nameEn: "Augustine", era: "354-430", avatar: "📚", domain: "spiritual"),
        .init(slug: "watchman_nee", nameZh: "倪柝声", nameEn: "Watchman Nee", era: "1903-1972", avatar: "🕎", domain: "spiritual"),
        .init(slug: "wang_mingdao", nameZh: "王明道", nameEn: "Wang Mingdao", era: "1900-1991", avatar: "🏰", domain: "spiritual"),
        .init(slug: "song_shangjie", nameZh: "宋尚节", nameEn: "John Sung", era: "1901-1944", avatar: "💧", domain: "spiritual"),
        .init(slug: "john_calvin", nameZh: "加尔文", nameEn: "John Calvin", era: "1509-1564", avatar: "📖", domain: "spiritual"),
        .init(slug: "john_bunyan", nameZh: "本仁约翰", nameEn: "John Bunyan", era: "1628-1688", avatar: "🛡️", domain: "spiritual"),
        .init(slug: "george_whitefield", nameZh: "怀特腓", nameEn: "George Whitefield", era: "1714-1770", avatar: "🔥", domain: "spiritual"),
        .init(slug: "zinzendorf", nameZh: "辛生道夫", nameEn: "Nikolaus von Zinzendorf", era: "1700-1760", avatar: "💘", domain: "spiritual"),
        .init(slug: "george_muller", nameZh: "慕勒", nameEn: "George Müller", era: "1805-1898", avatar: "🍽️", domain: "spiritual"),
        .init(slug: "hudson_taylor", nameZh: "戴德生", nameEn: "Hudson Taylor", era: "1832-1905", avatar: "🌾", domain: "spiritual"),
        .init(slug: "jonathan_goforth", nameZh: "古约翰", nameEn: "Jonathan Goforth", era: "1859-1936", avatar: "💨", domain: "spiritual"),
        .init(slug: "amy_carmichael", nameZh: "賈艾梅", nameEn: "Amy Carmichael", era: "1867-1951", avatar: "🌺", domain: "spiritual"),
        .init(slug: "evan_roberts", nameZh: "罗伯斯", nameEn: "Evan Roberts", era: "1878-1951", avatar: "⛰️", domain: "spiritual"),
        .init(slug: "jessie_penn_lewis", nameZh: "宾路易师母", nameEn: "Jessie Penn-Lewis", era: "1861-1927", avatar: "✝️", domain: "spiritual"),
        .init(slug: "kempis", nameZh: "肯培多默", nameEn: "Thomas à Kempis", era: "1380-1471", avatar: "📖", domain: "spiritual"),
        .init(slug: "desales", nameZh: "方济各·沙雷氏", nameEn: "Francis de Sales", era: "1567-1622", avatar: "🍯", domain: "spiritual"),
        .init(slug: "austin_sparks", nameZh: "史百克", nameEn: "T. Austin-Sparks", era: "1885-1971", avatar: "📕", domain: "spiritual"),
        .init(slug: "cranmer", nameZh: "克兰麦", nameEn: "Thomas Cranmer", era: "1489-1556", avatar: "📜", domain: "spiritual"),
        .init(slug: "hooker", nameZh: "胡克", nameEn: "Richard Hooker", era: "1554-1600", avatar: "📘", domain: "spiritual"),
        .init(slug: "andrewes", nameZh: "安德鲁斯", nameEn: "Lancelot Andrewes", era: "1555-1626", avatar: "📙", domain: "spiritual"),
        .init(slug: "george_herbert", nameZh: "乔治·赫伯特", nameEn: "George Herbert", era: "1593-1633", avatar: "📝", domain: "spiritual"),
        .init(slug: "newman", nameZh: "纽曼", nameEn: "John Henry Newman", era: "1801-1890", avatar: "🕯", domain: "spiritual"),

        // ── Heal / 岐黄 — TCM (39 masters) ──
        .init(slug: "huang_di", nameZh: "黄帝", nameEn: "Huang Di", era: "~2500 BC", avatar: "👑", domain: "tcm"),
        .init(slug: "zhang_zhongjing", nameZh: "张仲景", nameEn: "Zhang Zhongjing", era: "150-219 AD", avatar: "📜", domain: "tcm"),
        .init(slug: "hua_tuo", nameZh: "华佗", nameEn: "Hua Tuo", era: "145-208 AD", avatar: "⚗️", domain: "tcm"),
        .init(slug: "huangfu_mi", nameZh: "皇甫谧", nameEn: "Huangfu Mi", era: "215-282 AD", avatar: "📍", domain: "tcm"),
        .init(slug: "sun_simiao", nameZh: "孙思邈", nameEn: "Sun Simiao", era: "581-682 AD", avatar: "💐", domain: "tcm"),
        .init(slug: "liu_wansu", nameZh: "刘完素", nameEn: "Liu Wansu", era: "1110-1200", avatar: "❄️", domain: "tcm"),
        .init(slug: "zhang_zihe", nameZh: "张子和", nameEn: "Zhang Zihe", era: "1156-1228", avatar: "⛃", domain: "tcm"),
        .init(slug: "li_dongyuan", nameZh: "李东垣", nameEn: "Li Dongyuan", era: "1180-1251", avatar: "🌾", domain: "tcm"),
        .init(slug: "zhu_danxi", nameZh: "朱丹溪", nameEn: "Zhu Danxi", era: "1281-1358", avatar: "💧", domain: "tcm"),
        .init(slug: "li_shizhen", nameZh: "李时珍", nameEn: "Li Shizhen", era: "1518-1593", avatar: "🌿", domain: "tcm"),
        .init(slug: "zhang_jingyue", nameZh: "张景岳", nameEn: "Zhang Jingyue", era: "1563-1640", avatar: "🔥", domain: "tcm"),
        .init(slug: "wu_jutong", nameZh: "吴鞠通", nameEn: "Wu Jutong", era: "1758-1836", avatar: "🌡️", domain: "tcm"),
        .init(slug: "ye_tianshi", nameZh: "叶天士", nameEn: "Ye Tianshi", era: "1667-1746", avatar: "📖", domain: "tcm"),
        .init(slug: "wang_qingren", nameZh: "王清任", nameEn: "Wang Qingren", era: "1768-1831", avatar: "🩸", domain: "tcm"),
        .init(slug: "huang_yuanyu", nameZh: "黄元御", nameEn: "Huang Yuanyu", era: "1705-1758", avatar: "🔄", domain: "tcm"),
        .init(slug: "fu_qingzhu", nameZh: "傅青主", nameEn: "Fu Qingzhu", era: "1607-1684", avatar: "🌹", domain: "tcm"),
        .init(slug: "zheng_qinan", nameZh: "郑钦安", nameEn: "Zheng Qinan", era: "1824-1911", avatar: "🔥", domain: "tcm"),
        .init(slug: "zhang_xichun", nameZh: "张锡纯", nameEn: "Zhang Xichun", era: "1860-1933", avatar: "🌏", domain: "tcm"),
        .init(slug: "cao_yingfu", nameZh: "曹颖甫", nameEn: "Cao Yingfu", era: "1866-1938", avatar: "⚜️", domain: "tcm"),
        .init(slug: "lu_yuanlei", nameZh: "陆渊雷", nameEn: "Lu Yuanlei", era: "1894-1955", avatar: "🔬", domain: "tcm"),
        .init(slug: "pu_fuzhou", nameZh: "蒲辅周", nameEn: "Pu Fuzhou", era: "1888-1975", avatar: "🌟", domain: "tcm"),
        .init(slug: "ding_ganren", nameZh: "丁甘仁", nameEn: "Ding Ganren", era: "1866-1926", avatar: "🌸", domain: "tcm"),
        .init(slug: "hu_xishu", nameZh: "胡希恕", nameEn: "Hu Xishu", era: "1898-1984", avatar: "📚", domain: "tcm"),
        .init(slug: "liu_duzhou", nameZh: "刘渡舟", nameEn: "Liu Duzhou", era: "1917-2001", avatar: "🎓", domain: "tcm"),
        .init(slug: "huang_huang", nameZh: "黄煌", nameEn: "Huang Huang", era: "1954-", avatar: "🧬", domain: "tcm"),
        .init(slug: "fan_zhonglin", nameZh: "范中林", nameEn: "Fan Zhonglin", era: "1895-1989", avatar: "🔥", domain: "tcm"),
        .init(slug: "liu_lihong", nameZh: "刘力红", nameEn: "Liu Lihong", era: "1958-", avatar: "📖", domain: "tcm"),
        .init(slug: "ni_haixia", nameZh: "倪海厦", nameEn: "Ni Haixia", era: "1954-2012", avatar: "🎬", domain: "tcm"),
        .init(slug: "hao_wanshan", nameZh: "郝万山", nameEn: "Hao Wanshan", era: "1944-", avatar: "🏫", domain: "tcm"),
        .init(slug: "deng_tietao", nameZh: "邓铁涛", nameEn: "Deng Tietao", era: "1916-2019", avatar: "❤️", domain: "tcm"),
        .init(slug: "zhu_liangchun", nameZh: "朱良春", nameEn: "Zhu Liangchun", era: "1917-2015", avatar: "🕸️", domain: "tcm"),
        .init(slug: "jiao_shude", nameZh: "焦树德", nameEn: "Jiao Shude", era: "1922-2008", avatar: "🦴", domain: "tcm"),
        .init(slug: "yan_dexin", nameZh: "颜德馨", nameEn: "Yan Dexin", era: "1920-2017", avatar: "🍃", domain: "tcm"),
        .init(slug: "zhou_zhongying", nameZh: "周仲瑛", nameEn: "Zhou Zhongying", era: "1928-", avatar: "🚨", domain: "tcm"),
        .init(slug: "wang_qi", nameZh: "王琦", nameEn: "Wang Qi", era: "1943-", avatar: "🧬", domain: "tcm"),
        .init(slug: "lu_zhizheng", nameZh: "路志正", nameEn: "Lu Zhizheng", era: "1920-2023", avatar: "🌱", domain: "tcm"),
        .init(slug: "ren_jixue", nameZh: "任继学", nameEn: "Ren Jixue", era: "1926-2010", avatar: "🧠", domain: "tcm"),
        .init(slug: "gan_zuwang", nameZh: "干祖望", nameEn: "Gan Zuwang", era: "1912-2015", avatar: "👂", domain: "tcm"),
        .init(slug: "qiu_peiran", nameZh: "裘沛然", nameEn: "Qiu Peiran", era: "1913-2010", avatar: "🧩", domain: "tcm"),
    ]

    /// Lookup by slug. nil if the catalog doesn't include this slug
    /// (typical for new masters added cloud-side after our last
    /// release).
    static func master(for slug: String) -> CloudMaster? {
        all.first { $0.slug == slug }
    }
}
