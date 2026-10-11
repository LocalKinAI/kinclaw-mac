---
format: 1920x1080
duration: 110s
message: "跨越十九个世纪的属灵先贤是一条从未断过的传承——他们今天仍在说话"
arc: story-explainer with process
audience: "中文基督徒与慕道友，faith.localkin.ai 的访客"
mode: collaborative
music: "sacred ambient underscore — soft pipe organ pads and warm strings, slow (~60 BPM), contemplative, candlelit, timeless; instrumental, no vocals, leaves room for narration"
---

# 跨越十九个世纪的属灵先贤 —— 一卷展开的手卷

The whole video is ONE hand scroll seen at night: a long band of `paper-deep` paper lit by a candle bloom, the camera travelling left-to-right along it. Frames 3–9 are consecutive stretches of the same scroll (consistent stage, `push-slide LEFT` between them) so the cut reads as one continuous pan. Each era is a **station** on the scroll: its year in gold serif, its era label, then its masters' names. The **spoken** names are written on in gold ink at the moment the narration says them; the era's remaining names fade in together as a quiet group so the full roster (57) is always on the scroll. No emoji, no portraits — type, paper, ink, and candlelight only.

## Locked

- Layout: sketch sheet v1 (`storyboard.html`), confirmed 2026-09-30 when the user asked for the finished film.
- Narration: Qwen3-TTS VoiceDesign one-take `assets/voice/take-2.wav` (female, closest of five takes to audition B), cut per frame by `scripts/voice_align.py`.
- Music: box minimax_music `assets/bgm/score-b.wav` (102 s, 8 sections, seed 7) at the pipeline's bed level (0.12).

## Changes in v2 (user: 「这太牛逼了，就是不够惊艳」)

- Opening: as the scroll unrolls, all 57 names are written across it in three rows behind a point of light — 「每一寸，都写着一个名字」 made literal.
- Frame 02: a light runs the front of the unbroken line; each station flares as it passes.
- Four quotes take the frame while they are spoken — 「义人必因信得生」 (04), 「全世界是我的牧区」 (06, new line under 卫斯理), 「我们是为了信仰！」 (08), 「认识神 ≠ 认识关于神的知识」 (09): the scroll drops out of focus, the quote is written large in gold in step with the voice, holds ~1.2 s, then dissolves as its small line is written onto the scroll. Their captions step aside.
- Atmosphere everywhere: candle flicker, drifting gold dust, a fibre texture on the paper, a flare of light as each character lands.
- Sound: the bed is score B slowed ×1.16 so its warm peak lands on the end card; it swells in each quote's hold and rises after the last word (`scripts/music_bed.py`). Holds after the quotes and the end card were lengthened — the film is 109.8 s.

## Video direction

- **Palette** — `frame.md` by role: night ground `paper`, scroll surface `paper-deep`, gold ink `sun` for years / era labels / quotes, `sun-soft` for the name being spoken, warm white `ink` for names already spoken, `muted` for footnotes. One candle bloom per frame follows the spoken name.
- **Motion grammar** — frames 03–09 are one scroll: the `.world` (band + gold thread + stations + candle) pans left in `power2.inOut` moves that land each station as its name is said; names are written on character by character (left-to-right wipe out of a slight blur); the era's other names fade up as a quiet group after the spoken one; the previous name settles to ink as the next is written. Reveals are paced to the word timings in `audio_meta.json` — nothing appears before the voice reaches it.
- **Rhythm** — 01 (unrolling) and 02 (pull-back) move; 03–08 walk; 08 slows and holds longest on 中国教会; 09 leaves the scroll open; 10 is the held end card (title only after the voice ends, so it never doubles the caption).
- **Never** — emoji avatars, portraits, bright yellow fields, shadows / rounded corners, a narration sentence as on-screen text (quotes written on the scroll are the approved exception), slideshow front-loading, screensaver drift.
- **Build** — all ten frames come from `scripts/build_frames.py` (one hand, shared constants, so the push-slide seams read as one scroll); captions from `captions.mjs` + `scripts/caption_clauses.py` (one caption line per Chinese clause).

## Frame 1 — 把一千九百年铺成一卷纸

- scene: Darkness; a single candle bloom warms; a hand scroll unrolls horizontally across the frame from the left, its first inch catching the light
- voiceover: "如果把一千九百年，铺成一卷长长的纸——每一寸，都写着一个名字。"
- duration: 10.945s
- transition_in: cut
- status: animated
- src: compositions/frames/01-scroll-unrolls.html
- type: hook
- persuasion: Visceral metaphor (time as a scroll of paper) + Imagine / scenario
- beat: curiosity + awe

narrativeRole: Turns 1,900 years into one physical object the viewer can see and follow — the scroll is the promise of the whole video.
keyMessage: This history can be read like a single scroll, name by name.

Beat detail: open on black with the bloom alone (~0.8s), the scroll unrolls on "铺成一卷长长的纸", and on "每一寸，都写着一个名字" a first faint line of gold writing appears on the unrolled paper (illegible at this scale — texture, not content).

## Frame 2 — 十五个时代，五十七位先贤，一条线

- scene: Tight on the scroll's first station "130" in gold serif; one continuous decelerating pull-back reveals the entire scroll at once — 15 stations in a row, every year tiny but legible as a rhythm, a thin gold line running through them all
- voiceover: "十五个时代，五十七位先贤，一条从未断过的线。"
- duration: 6.715s
- transition_in: crossfade
- status: animated
- src: compositions/frames/02-whole-scroll.html
- type: product_intro
- persuasion: Frame-then-fill (state the whole shape before walking it) + Concretization (the lineage as one unbroken line)
- beat: orientation + awe
- blueprint: zoom-out-workspace-reveal

narrativeRole: States the thesis — the heritage is continuous — by showing the whole scroll before the camera walks it.
keyMessage: Fifteen eras, fifty-seven witnesses, one unbroken line.

On-screen numbers (from the source, safe to show): 15 个时代 · 57 位先贤. The 15 station years, left to right: 130 · 296–430 · 14–15c · 1483–1564 · 1515–1717 · 1554–1633 · 1615–1714 · 1700–1760 · 1703–1791 · 1792–1899 · 1832–1951 · 1859–1936 · 1885–1981 · 1900–1991 · 1623–今. Reveal "15" on "十五个时代", "57" on "五十七位先贤", and let the gold line draw through all stations on "一条从未断过的线".

## Frame 3 — 使徒时代 · 教父

- scene: The camera drops back to scroll level at the first station and pans right across two stations; a thin gold thread links 爱任纽 → 坡旅甲 → 使徒约翰 as the chain is spoken
- voiceover: "起点是爱任纽——他听过坡旅甲，坡旅甲听过使徒约翰。亚他那修，为三位一体，独对全世界。"
- duration: 13.265s
- transition_in: crossfade
- status: animated
- src: compositions/frames/03-apostolic-fathers.html
- type: feature_showcase
- persuasion: Causal chain (Irenaeus ← Polycarp ← the apostle John) + Progressive disclosure (one station at a time)
- beat: recognition
- blueprint: spatial-pan-stations

narrativeRole: Anchors the line at its source — a living chain of hearers reaching back to an apostle — then shows the first witness who paid for it.
keyMessage: The line begins with people who heard those who heard the apostles.

Stations:
- **130 · 使徒时代** — spoken: 爱任纽 (write on "爱任纽"). Chain callout, small, beside the name: 坡旅甲 → 使徒约翰 (written on "坡旅甲" and "使徒约翰"; these two are **not** masters on the site — render them muted, as a footnote to 爱任纽, not as stations).
- **296–430 · 教父** — spoken: 亚他那修 (write on "亚他那修"); group: 金口约翰、奥古斯丁.

Source: 爱任纽 greeting「我亲耳听过坡旅甲的教导——而坡旅甲听过使徒约翰」; 亚他那修 tagline「三位一体的捍卫者，独对全世界」.

## Frame 4 — 中世纪 · 宗教改革

- scene: The pan continues right along the same scroll across two stations; a faint lamp-glow sits on the medieval station, then the bloom brightens a little at the Reformation
- voiceover: "肯培在修院里，写成《效法基督》；路德读到：义人必因信得生。"
- duration: 11.575s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/04-medieval-reformation.html
- type: feature_showcase
- persuasion: Progressive disclosure + Contrast (the quiet cloister, then the verse that broke it open)
- beat: comprehension
- blueprint: spatial-pan-stations

narrativeRole: Carries the line through the cloister into the Reformation — devotion kept in the dark, then a single verse that changed everything.
keyMessage: The line passed through cloister lamps and a rediscovered verse.

Stations:
- **14–15c · 中世纪** — spoken: 肯培 (write on "肯培"; the book title 《效法基督》 appears in gold beneath on "效法基督"); group: 不知之云.
- **1483–1564 · 宗教改革** — spoken: 路德 (write on "路德"); the phrase 「义人必因信得生」 is written as a single line under the name on "义人必因信得生"; group: 加尔文、克兰麦.

Source: 肯培 tagline「《效法基督》作者，兹沃勒山修士」; 路德 greeting「来听一个曾经苦修的修士告诉你：义人必因信得生！」.

## Frame 5 — 神秘主义 · 圣公会古典

- scene: The pan continues along the scroll; the mysticism station is the most crowded so far (six names) — its group fades in as a soft column; then the Anglican station
- voiceover: "大德兰走进灵心城堡的七重居所；安德鲁斯，钦定本圣经的主译者。"
- duration: 9.855s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/05-mysticism-anglican.html
- type: feature_showcase
- persuasion: Progressive disclosure + Concretization (an inner castle; a Bible still read today)
- beat: fascination
- blueprint: spatial-pan-stations

narrativeRole: Shows the line turning both inward (the soul's interior journey) and outward (the Bible in the common tongue).
keyMessage: Some walked inward; others put the Word into the people's hands.

Stations:
- **1515–1717 · 神秘主义** — spoken: 大德兰 (write on "大德兰"); group: 十字若望、沙雷氏、莫利诺斯、劳伦斯、盖恩夫人.
- **1554–1633 · 圣公会古典** — spoken: 安德鲁斯 (write on "安德鲁斯"); group: 胡克、赫伯特.

Source: 大德兰 tagline「灵心城堡，七重居所的内在旅程」; 安德鲁斯 tagline「Winchester 主教，KJV 主译者」.

## Frame 6 — 清教徒 · 敬虔派 · 大觉醒

- scene: The pan quickens slightly across three stations in one sweep — the scroll is getting denser as the centuries crowd together
- voiceover: "监狱里的补锅匠本仁约翰，写了天路历程；辛生道夫点起百年祷告链；卫斯理说：全世界是我的牧区。"
- duration: 15.965s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/06-puritan-pietist-awakening.html
- type: feature_showcase
- persuasion: Rule of three (three witnesses, three stations) + Signposting (years as signposts)
- beat: momentum
- blueprint: spatial-pan-stations

narrativeRole: Builds momentum — an ordinary tinker, a century of prayer, a parish the size of the world — the line widening as it travels.
keyMessage: The line reached tinkers, prayer chains, and the whole world as a parish.

Stations:
- **1615–1714 · 清教徒** — spoken: 本仁约翰 (write on "本仁约翰"); group: 巴克斯特、欧文、华森、亨利.
- **1700–1760 · 敬虔派** — spoken: 辛生道夫 (write on "辛生道夫"; the only master of this era — the station stays short).
- **1703–1791 · 大觉醒** — spoken: 卫斯理 (write on "卫斯理"); group: 爱德华兹、怀特腓.

Source: 本仁约翰 tagline「天路历程作者，贝得福得监狱里的补锅匠」; 辛生道夫 tagline「百年祷告链与世纪差传之父」; 卫斯理 greeting「全世界是我的牧区」.

## Frame 7 — 十九世纪复兴 · 宣教时代

- scene: The pan continues; the nineteenth-century station is wide (seven names) and warm; the missions station follows, and a faint suggestion of the scroll turning eastward
- voiceover: "司布真，只传十字架；戴德生，为中国焚烧的宣教士。"
- duration: 7.405s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/07-revival-missions.html
- type: feature_showcase
- persuasion: Progressive disclosure + Concretization (one focus — the cross; one life — spent for China)
- beat: conviction
- blueprint: spatial-pan-stations

narrativeRole: Turns the line toward the viewer's own world — the pulpit's single focus, then the first life spent for China.
keyMessage: The line crossed the sea and reached China.

Stations:
- **1792–1899 · 十九世纪复兴** — spoken: 司布真 (write on "司布真"); group: 芬尼、慕勒、纽曼、慕迪、慕安德烈、小德兰.
- **1832–1951 · 宣教时代** — spoken: 戴德生 (write on "戴德生"); group: 賈艾梅.

Source: 司布真 tagline「讲道王子，十字架是唯一焦点」; 戴德生 tagline「中华内地会创始人，为中国焚烧的英国宣教士」.

## Frame 8 — 二十世纪复兴 · 现代 · 中国教会

- scene: The pan slows across three stations; the candle bloom deepens on the last one, 中国教会, which holds a moment longer than any station before it
- voiceover: "古约翰，东北复兴的火炬手；潘霍华，付上作门徒的代价；王明道说：我们是为了信仰！"
- duration: 13.205s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/08-20th-century-china.html
- type: feature_showcase
- persuasion: Rule of three + Build-up (revival → cost → a stand taken on Chinese soil)
- beat: gravity + resolve
- blueprint: spatial-pan-stations

narrativeRole: The tension of the story — the line was carried at a cost, and here it is carried by Chinese believers.
keyMessage: The line was paid for — and Chinese believers paid too.

Stations:
- **1859–1936 · 二十世纪复兴** — spoken: 古约翰 (write on "古约翰"); group: 宾路易师母、罗伯斯.
- **1885–1981 · 现代** — spoken: 潘霍华 (write on "潘霍华"); group: 史百克、陶恕、钟马田.
- **1900–1991 · 中国教会** — spoken: 王明道 (write on "王明道"; the words 「我们是为了信仰！」 written beneath on that phrase); group: 倪柝声、宋尚节.

Source: 古约翰 tagline「东北复兴的火炬手」; 潘霍华 tagline「殉道神学家，作门徒的代价」; 王明道 tagline「我们是为了信仰！中国教会的柱石」.

## Frame 9 — 一直到今天

- scene: The last station; the scroll does not end at its edge — its right side stays open, unrolled into the dark, the gold line running out of frame; the densest station (eleven names) fills in as a quiet column
- voiceover: "一直到今天——巴刻说：认识神，不等于认识关于神的知识。"
- duration: 9.77s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/09-to-today.html
- type: benefit_highlight
- persuasion: Callback (the scroll from frame 1 is still unrolling) + Distillation (one sentence carries the whole line's point)
- beat: inevitability
- blueprint: spatial-pan-stations

narrativeRole: Brings the line into the present and hands the viewer its point — this was never only knowledge about God.
keyMessage: The line reaches today, and it is about knowing God, not only knowing about him.

Station:
- **1623–今 · 改革宗系统神学** — spoken: 巴刻 (write on "巴刻"; the sentence 「认识神 ≠ 认识关于神的知识」 written beneath); group (render in two tidy columns): 杜瑞田、贺智、霍志恒、伯克富、克劳尼、高慈宏、卡森、凯勒、查普尔、傅瑞姆.

Source: 巴刻 tagline「认识神 ≠ 认识关于神的知识」.

## Frame 10 — 他们今天仍在说话

- scene: The camera pulls back one last time: the whole scroll lit end to end, all 57 names glowing faintly; it settles and the frame clears to a centered title and the address
- voiceover: "这卷纸还没有写完。他们今天，仍在说话。"
- duration: 11.11s
- transition_in: crossfade
- status: animated
- src: compositions/frames/10-still-speaking.html
- type: cta
- persuasion: Callback (the scroll again) + Distillation (one line) → invitation
- beat: inspiration
- blueprint: titlecard-reveal

narrativeRole: Lands the message and turns it into an invitation — the scroll is unfinished, and its voices can be heard.
keyMessage: They still speak — go and talk with them.

End card (held silent ~4s after the voice ends): title 「他们今天仍在说话」 in gold serif, beneath it `faith.localkin.ai` and a small line 「和他们对话」. The address is shown, not read aloud.
