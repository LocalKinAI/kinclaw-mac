---
name: narrated-motion-film
description: Use for a narrated film made of designed motion rather than AI pictures — an explainer, a mini-documentary, a timeline, a heritage or knowledge film, Chinese above all — built in HyperFrames and voiced by the box. Covers box_narration (one take, several takes, the closest kept, every character timed), writing reveals on the word, full-frame quote moments, light, hf_captions (Chinese captions by clause) and music_bed (a score fitted under the voice), and templates — saving a finished film and making another like it.
---

# Narrated motion film: voice from the box, picture from code

The worked example is faith.localkin.ai's timeline film (2026-09-30, `templates/golden-scroll`): a hand
scroll lit by a candle, fifteen eras, fifty-seven names written in gold ink as the narrator says them, 110 s.
Its first cut was called 「太牛逼了，就是不够惊艳」; the second, 「这版好太多了」. What changed between them is
in **Stunning, not just tidy** below — plan for it from the start.

Use this when the picture is type, light, diagrams and set pieces authored in HyperFrames (`pipeline_type:
animation`, `render_runtime: hyperframes`, atelier composition) and a voice carries the story. For story
shots with people use `minimax-h3-local`; for page captures `website-to-video`.

## The tools (all on the box, free)

| tool | what | time |
|---|---|---|
| `box_narration` | the whole script read in ONE take by the box's voice, `takes` times; the take closest to the wanted voice kept; cut per line; every character (and "/"-marked word) timed; captions grouped by clause | ~25 s a take for 300 字 + ~10 s timing |
| `box_tts` | one line in a box voice (8102 from a description, 8101 presets) — also a `tts` provider for tts_selector | seconds |
| `minimax_music` | the score (see its tool) | ~6 s per second of music |
| `music_bed` | the score fitted under the film: climax moved onto the end card, low under the voice, lifted in holds, risen at the end | seconds |
| `hf_captions` | the captions sub-composition for HyperFrames, right for Chinese | instant |

```python
from tools.tool_registry import registry
registry.discover()
r = registry.get("box_narration").execute({
    "lines": [...],                      # one line per frame, as read; "/" marks words: "起点/是/爱任纽——/他/听过/坡旅甲，"
    "output_dir": "projects/<id>/assets/voice",
    "instruct": "温柔清澈的中年女声，像在烛光下读一封旧信，语速缓慢，平静而有温度",
    "takes": 4,
    "reference_audio": "projects/<id>/assets/voice/audition-b.wav",   # the audition the person chose, if any
    "extra_tail_seconds": {"4": 2.0},    # a line whose quote should land holds longer after it
    "tail_seconds": 5.5,                 # the end card
})
```

## The voice

- **8102 designs a new voice on every call.** Line-by-line reading is a different person every line — never do
  it for a narration. Even whole takes differ: an audition the person liked (201 Hz, slow) came back as full
  takes at 164–188 Hz and faster. So audition two or three voices on one line (`box_tts`), let the person
  choose, then read the script 3–5 times with `reference_audio` = the chosen audition; `box_narration` keeps
  the closest. Tell the person the chosen take's length — it sets the film's length.
- Give the person the whole chosen take to hear before building on it.
- Whisper mishears names and near-homophones (爱任纽 → 爱任牛, 义人 → 一人); the timings are pinned onto the
  script's own characters, so captions and cues use the right words. A take that truly drops or repeats words
  shows as `matched` well under 0.9 — listen to it.

## The picture

- **One hand writes every frame from shared constants** when frames are stretches of one place (one scroll, one
  map, one table): the band, the line, the type sizes and the motion must match across the seams. A script
  that generates all frames (see `templates/golden-scroll/build_frames.py`) beats N workers writing N frames.
- **Reveal on the word.** `narration.json` gives every line's characters with times inside its clip: write a
  name on at its first character, a number when it is said. Nothing appears before the voice reaches it.
- Frame length = its line clip's `duration_s` (voice plus its pauses); the film's timeline is the clips back to
  back (`start_s`).
- Keep content in the top 83 %: captions own the band below.
- Fonts ship with the project: the render machine is a clean headless Chrome with no CJK fonts. Subset the
  families to the characters used (fontTools → woff2; the template's `subset.py`). Every `font-family` in a
  composition needs its own `@font-face` in that file.

## Stunning, not just tidy

The first cut of the example was elegant and flat: the same station layout seven times, still light, the
quotes small under the names. What made the second one land:

1. **Two to four hero moments.** The lines the film is about — a quote, a number, a turn — take the whole
   frame: the scene behind drops out of focus (blur ~9px, dim to ~30 %), the words are written large in gold
   *in step with the voice*, hold ~1.2 s after the line ends (give that line `extra_tail_seconds`), then
   dissolve as they settle back into their small place. Their captions step aside (`hf_captions` `skip_texts`).
2. **Light that moves.** A candle bloom that flickers (a seeded chain of small opacity/scale breaths), fine
   dust drifting in it, a flare of glow as each character lands and settles. Seeded, never `Math.random`.
3. **The metaphor made literal.** 「每一寸，都写着一个名字」 — so the opening scroll is written full of all the
   names, row by row, behind a point of light.
4. **A light that runs.** 「一条从未断过的线」 — a bright point travels the line as it draws, and each station
   flares as it passes.
5. **Music with a shape** — see below. The end card must not sit in silence.
6. **Vary the frames.** A layout repeated frame after frame is the flatness; change scale, framing or the hero
   between neighbours.

Show the person the finished cut early: they judge the film, not the plan (「成片呢」「给我看最后啊」).

## Music

- MiniMax Music 3 picks its own length from the section tags; `max_duration` is only a ceiling. Three tags
  (`[intro][instrumental][outro]`) came back 36 s for a 101 s ask; seven or eight sections (intro,
  instrumental, interlude, instrumental, interlude, instrumental, bridge, outro) came back 102 s. Ask for a
  little longer than the film.
- Then `music_bed` with `narration_json`, `hold_lines` = the hero-moment lines: the climax lands after the last
  word, the voice sits on top (≈ −18 dB bed), the holds lift, the end rises and fades with the picture. Put
  the bed in the film at volume 1.0 — the mix is in it.
- Master the whole film to −14 LUFS for delivery.

## Captions

`hf_captions` with `narration_json`, the fonts with their files, and `skip_texts` for the hero lines; put the
`host_element` it returns into `index.html` (captions track). It gets right what went wrong before: Chinese
lines break at clauses, words sit flush, each family is its own `@font-face`, the last caption clears.

## Templates — "save this", "make another like X"

A finished film the person likes is a template: `~/OpenMontage/templates/<name>/`.

- **Save** (「存成模板」): copy in the design spec (palette, type, set pieces), the frame builder script, the
  storyboard with its structure (keep the example content — it shows the intent), the voice (`instruct` and
  the chosen take's pitch and pace from `narration.json`), the music brief and sections, the caption settings,
  the fonts and `subset.py`, and a contact sheet of the final frames. Write `TEMPLATE.md`: what the film is,
  what makes it work, what to change for a new subject, what never to change.
- **Make another like X** (「照 X 再做一部」): read `templates/X/TEMPLATE.md` and look at its contact sheet
  first. Keep the look, the structure, the voice and the music's shape; write the new content into it; tell
  the person only what differs.
- List what exists with `ls ~/OpenMontage/templates`.

## Checks before render

- `npx hyperframes lint` 0 errors; `npx hyperframes check` passes (contrast included).
- Snapshot the hero moments and the end card: nothing collides with the big type (blur the scene behind it),
  no caption lingers over the end card, every name is fully written before its frame leaves.
