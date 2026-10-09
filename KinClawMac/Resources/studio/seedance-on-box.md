# Seedance prompts, filmed on the box (H3, LTX, Qwen-Image)

awesome-seedance (learnprompt/awesome-seedance — code MIT, curation CC BY 4.0, from goodcase.ai) is a library of
Seedance 2.0/2.5 prompts that worked: 27 templates, each a way of writing one kind of video, and 760 cases with
their whole prompts. Kept on this Mac in `guides/awesome-seedance/` (templates/zh, templates/en, cases.json).
Credit the case's creator and link the source when a film follows one closely.

**Seedance is not on the box.** What films here: MiniMax H3 (ref2va, with sound), LTX-2.3 and Qwen-Image 2.1
for stills — free, local, slower. A Seedance prompt is a plan to translate, not text to paste.

## First look at the H3 retest

355 of the cases were retested on MiniMax H3 (mostly "H3 Max 768p") with a verdict: `reproduced` (272),
`degraded`, `failed`. In `cases.json`: `retests[].model` containing "H3" and its `verdict`. Start from
`reproduced` ones; a `failed` one needs the idea rebuilt, not the prompt reused.

## What changes on the box

| Seedance | on the box |
|---|---|
| text alone makes video | **H3 needs a picture**: a first frame (pinned) or reference portraits. Make it with `qwen_image` (edit mode composes set + cast) |
| one generation up to 15–30 s with a time-coded script | **one shot per time segment**, 4–15 s each (5–6 s is the sweet spot), joined in the cut |
| `@Image1` / `@Video1` reference tokens | H3 `referenceImage` portraits (≤ 9) — the same portrait in every shot of that person |
| 1080p, 2K | H3 at 0.5 MP (draft, ~10 min per 5 s shot) or 768p (2–3× longer); LTX faster for b-roll |
| native dialogue and sound | H3 makes ambient sound; dialogue from the box's voices (`box_tts`) — then H3 with the line as audio, or a talking head (Ditto) / lip-sync (MuseTalk) |
| music in the prompt | score separately: `music_gen` (ACE-Step 1.5, exactly the cut's length) or YuE2 for songs |

## Template by template

- **逐秒时间轴分镜 timeline-shot-script** — keep its structure (global block, fixed block, one action per
  segment, constraints last) as the *shot list*: each segment becomes one shot with its own first frame drawn
  from the fixed block. Segment hand-offs ("ends with…/starts from…") become the next shot's first frame.
- **参考图身份锁定 character-reference-lock** — the inherit / do-not-inherit lists go into the cast portraits
  (`qwen_image`: plain backdrop, head and shoulders, the clothes) and into every first-frame prompt.
- **分镜网格转视频 storyboard-grid-to-video** — draw the numbered grid with `qwen_image` to agree the order and
  framing; then redraw each panel as a full first frame. Do not feed the whole grid to H3 as one reference.
- **手持 UGC / POV / 早年 DV** — the camera defects are words H3 follows reasonably; grain, shake and colour can
  also be added after (`color_grade`, ffmpeg). Vlog b-roll: LTX from stills is quicker.
- **对白与表演节拍 dialogue-performance-beats** — lines in Chinese are fine: voice them with `box_tts`, then
  film the reaction shots with H3 and the speaking shots as a talking head or H3 with the line as audio.
- **电影级产品广告 product-commercial-shotlist / UGC 口播带货** — the product photo is the first frame or a
  reference; pin it at the end too when the hero shot must match; counts and labels must be pinned, H3 does
  not keep them by itself.
- **流程与变换 process-transformation / 时间冻结倒放** — H3 with **first and last frame** both pinned holds the
  start and end states; draw both with `qwen_image` edit from the same set.
- **音乐卡点 MV music-beat-sync** — the music first (exact length), cut the shots to its beats.
- **一镜到底 POV continuous take, 打斗编排** — longer than 15 s must be split at a natural occlusion; complex
  physics often degrades: check the case's H3 verdict before promising it.

Say the plan first — shots, which model, how long each takes on the box — and film after a yes.
