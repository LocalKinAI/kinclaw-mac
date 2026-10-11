# golden-scroll — 一卷展开的手卷

A narrated mini-documentary that walks a long timeline as ONE hand scroll lit by a candle: every era a station on
the scroll, every name written in gold ink the moment the narrator says it, the lines the film is about taking the
whole frame. Made 2026-09-30 for faith.localkin.ai's timeline (15 eras, 57 masters, 110 s, 1920×1080, Chinese).
The person's verdict on the second cut: 「这版好太多了」. Look at `contact-sheet.jpg` before anything else.

Good for: any history told as a sequence — a lineage, a church's story, a dynasty, a scientist's century, a book of
the Bible walked chapter by chapter. Poor for: a story with people acting (Film / H3), a product tour (website-to-video).

## What makes it work (keep these)

- **One continuous object.** The scroll is the spine: frames 3–9 are consecutive stretches of it joined by
  `push-slide` seams, so the band, the gold thread and the station geometry are identical in every frame — they all
  come from one script (`scripts/build_frames.py`), never from separate hands.
- **Names written on the word.** Each era's one or two spoken names are written character by character (a
  left-to-right wipe out of a slight blur, a flare of glow as each lands) at the first character of the name in the
  narration's timing; the era's other names fade up as a quiet group after. The previous name settles to warm white.
- **Hero quotes.** Four lines take the frame while they are spoken (「义人必因信得生」「全世界是我的牧区」「我们是为了
  信仰！」「认识神 ≠ 认识关于神的知识」): the scroll blurs (9px) and dims (~32 %), the quote is written large in gold in
  step with the voice, holds ~1.2 s, dissolves while its small line is written under the name. Their captions step
  aside. Give those lines `extra_tail_seconds` ≈ 1.7–2.0.
- **Candlelight.** One bloom per frame that follows the spoken station and flickers; gold dust drifting; a fibre
  texture on the paper (seeded SVG turbulence). The end card's light runs off the right edge — the scroll is
  unfinished.
- **Opening = the metaphor made literal**: as the scroll unrolls, all names are written across it in three rows
  behind a point of light. Frame 2 pulls back from the first station to the whole scroll; a light runs the line.
- **The end card holds** (tail 5.5 s) with the music risen under it, then fades with the picture.

## The look (`frame.md`)

Night ground `#0a0a14`, scroll `#12121e` with `#8a7040` hairlines, gold ink `#c8a45e`, the spoken name `#e8d4a0`,
names already spoken `#e8e4dc`, secondary `#8a8678`. Cormorant Garamond for years and Latin, 思源宋体 (Noto Serif SC)
for names and text — both shipped as woff2 subsets in `assets/fonts/` (re-cut for a new text with
`scripts/subset.py`). No emoji, no portraits, no bright yellow fields.

## The voice

8102 VoiceDesign, `instruct`: 「温柔清澈的中年女声，像在烛光下读一封旧信，语速缓慢，平静而有温度」 — the person chose it
over a warm male documentary voice and an old pastor's voice. The kept take ran **~188 Hz, 2.8 字/s** (the audition was
201 Hz, 2.6 字/s; full takes ranged 164–188 Hz). With `box_narration`: `takes` 4–5, `reference_audio` = the chosen
audition, lead 0.8 s, pauses ≥ 0.9 s, tail 5.5 s.

## The music

`minimax_music`, instrumental, 8 sections (intro, instrumental, interlude, instrumental, interlude, instrumental,
bridge, outro — three sections came back 36 s long), about 5 s longer than the film:

> Sacred ambient underscore for a quiet documentary about nineteen centuries of Christian witness. Soft pipe organ
> pads and warm, sustained strings; slow, around 60 BPM; contemplative, reverent, candlelit, timeless. Understated
> and spacious so a gentle spoken narration sits clearly on top.

Then `music_bed` with `hold_lines` = the hero-quote lines (bed 0.13, holds 0.22, end 0.42; the score was slowed 14 %
so its warm peak landed on the end card).

## Captions

`hf_captions`: fonts Cormorant Garamond + Noto Serif SC, 48 px, spoken `#e8e4dc`, current word `#e8d4a0`, upcoming
dimmed, no box behind them, one clause per caption, `skip_texts` = the hero quotes.

## Files

| file | what |
|---|---|
| `contact-sheet.jpg` | twelve moments of the approved cut |
| `STORYBOARD.md` | the frames, with the v2 changes and the video direction written above them |
| `SCRIPT.md` / `BRIEF.md` | the narration (one line per frame) and the brief |
| `frame.md` | the design spec (colors, type, set pieces) |
| `storyboard.html` | the sketch sheet the layout was confirmed on |
| `scripts/build_frames.py` | every frame's HTML from shared constants; reads word timings (written for the HyperFrames faceless layout — `audio_meta.json` + `STORYBOARD.md`; feed it `narration.json`'s lines instead) |
| `scripts/voice_align.py`, `music_bed.py`, `caption_clauses.py` | the first versions of what are now `box_narration`, `music_bed` and `hf_captions` — read, don't run |
| `scripts/subset.py` | cut the fonts to a new text |
| `caption-skin.html` | the caption look as first built |

## Making another

Keep: the scroll, the station anatomy (year · era · spoken name · group), the write-on, the hero moments, the light,
the voice, the music's shape, the open end. Change: the stations and names, the narration (one line per frame; each
era's line names one or two people and says one true thing about them), which 2–4 lines become hero quotes, the
title and address on the end card. Densest station seen: 11 names (two columns); more than that, split the era.
