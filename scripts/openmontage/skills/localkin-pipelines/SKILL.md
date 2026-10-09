---
name: localkin-pipelines
description: Use before choosing a pipeline on the LocalKin box — which of OpenMontage's 12 pipelines run here and on what (local models in place of paid APIs), the Chinese-ready tools (transcriber engine box, CJK captions), the avatar and lip-sync models (Ditto, MuseTalk, SadTalker, Wav2Lip), ACE-Step music of exact length, face tracking, Blender, manim, CLIP footage search, and the few that still need an account.
---

# The 12 pipelines on the LocalKin box

Everything below runs on the box itself (M3 Ultra, ComfyUI at 127.0.0.1:8188, free). Measured 2026-10-04.
`source .venv/bin/activate` first — manim and a few others are found on the venv's PATH.

| pipeline | on the box | what backs it |
|---|---|---|
| talking-head (口播精剪) | ready | transcriber (box), subtitle_gen / remotion_caption_burn (Chinese), silence_cutter, auto_reframe + face_tracker, color_grade, eye_enhance |
| clip-factory (长视频切片) | ready | transcriber (box), video_trimmer, subtitle_gen, video_compose (captions burn) |
| podcast-repurpose | ready | same, plus music_gen (ACE-Step) |
| avatar-spokesperson (数字人口播) | ready | talking_head (Ditto; SadTalker), lip_sync (Ditto; MuseTalk, Wav2Lip), box_tts |
| localization-dub (翻译配音) | ready | **video_translate** (one tool: the speaker's own voice cloned, the face redrawn speaking it by Ditto, .srt); or by hand: transcriber → your translation → box_tts → lip_sync (Ditto) → subtitle_gen |
| character-animation | ready | character_* tools, HyperFrames, Playwright previews |
| hybrid | ready | your footage + qwen_image / h3_video inserts, code_snippet, music_gen |
| screen-demo | ready (synthetic) | Remotion terminal/screenshot scenes; real screen capture happens on the Mac |
| animated-explainer | ready | box_tts, qwen_image, math_animate (manim, no LaTeX), code_snippet, music_gen |
| documentary-montage | ready, keyless sources | clip_search (CLIP ViT-B/32, local), corpus_builder: archive_org, nasa, wikimedia (Pexels/Unsplash need keys) |
| animation, cinematic | ready (as used since 09) | + blender_world (Blender 5.2.1), music_gen; atlas_3d / fal_3d / fal_elevenlabs_music / freesound_music need accounts |

## Art animation and one-take films (installed 2026-10-08)

**huashu-art-motion** (`.agents/skills/huashu-art-motion`, MIT; read its SKILL.md — Chinese — first): pictures drawn
and animated in code — 35 art styles (`风格配方/INDEX.md`: cave painting to vaporwave, 水墨, 敦煌, Klimt, Ghibli…),
8 explainer grammars with demos (`scripts/engine/demos/`: Kurzgesagt, Vox, whiteboard, 3b1b, keynote UI, finance
chart, storytime, kinetic type), long scrolls, exact-length clips for a narration (`render.py --spec clip.json`,
`--alpha` for ProRes with transparency). Render with the venv's own Python, which already has Playwright and its
Chromium: `cd scripts/engine && ~/OpenMontage/.venv/bin/python render.py --out …` — NOT `uv run --with playwright`,
which downloads Playwright and a new Chromium. Its 14 s art-history speedrun (16 eras, 1080p60) renders in 1:45; its
code-synthesised score `scripts/audio/synth_艺术史速通.py` runs the same way in 3 s. Voices from the box (box_tts,
box_narration — not its optional Volcengine clone), pictures from qwen_image, timings from transcriber, music from
music_gen (ACE-Step) or its synth scripts. Its bundled Chinese fonts are Simplified only: for Traditional or Cantonese
words (嘅、咗、喺) make a subset of PingFang TC/HK with `scripts/font_subset.py` first, or the render stops on a
missing glyph.

**onetake** (`.agents/skills/onetake`): one continuous camera through a product or a UI rebuilt in HTML from
screenshots, every beat growing out of the last, real motion blur (1080p30 drafts, 4K60), synthesised sound effects,
and an oracle that fails a slideshow. Licence PolyForm Noncommercial: the person's private projects only — never for
LocalKin's own promotion (that needs the paid onetake Pro licence); say so if asked to. Run its scripts with the venv's
Python (opencv and matplotlib are installed there). Its narration default (Kokoro) speaks English and Japanese only —
use box_tts / box_narration and transcriber instead; Chinese text needs `--cjk <font file>`.

**JIZURA** (on the Mac, not the box: `~/Documents/Workspace/jizura/index.html`, MIT): a lyric video (文字PV) from a
song and its lyrics in a browser page — layouts, entrances and camera moves per line, beats found by itself, MP4
out. It has no API: prepare the song and an LRC (lines timed by transcriber on the box) and the person opens the page
and exports.

## The tools that changed, and how to call them

**video_translate** — a talking video into another language, HeyGen's way, all on the box (2026-10-04). Call it
with `video_path` alone: it returns the lines with their times (Qwen3-ASR). Translate them yourself — the meaning,
about as long as the original (English runs longer than Chinese: shorten rather than pad) — and call again with
`segments` (each line's original `start`/`end`, the new `text`) and `language` ("en", "ja", …). It cuts the
clearest 4–12 s of the speaker as the voice to clone (Qwen3-TTS 1.7B Base on :8103; `reference` {start, end, text}
picks another span), speaks every line in that voice, fits each to its place (up to 1.35× faster; `lines[].tempo`
and `late_by` say what it did — a note names lines to shorten), replaces the soundtrack, has Ditto draw the face again over every frame speaking it
(`lip_sync_model: "musetalk"` redraws only the mouth — it blurred lips and lost the teeth on a 640×640 口播 where
Ditto's stayed as sharp as the original; `lip_sync: false` for the voice only) and writes an .srt
(`burn_subtitles: true` draws it on). 10 s of video in about a minute. One speaker per video; the old soundtrack goes (it carries the old voice) — lay music back with
music_bed. `box_tts` takes `reference_audio` + `reference_text` too: any line in a voice from a recording.

**transcriber** — `engine: "auto"` (default) on the box = the words from the box's Qwen3-ASR 1.7B (:8100; far better
than whisper in Chinese, English fine too) with faster-whisper small's timing pinned onto them, one Chinese
character (or Latin word) to a "word". 75 s of narration in 25 s, 98 % of characters timed directly. `engine:
"whisper"` for whisper alone. Default model is `small` (cached); another size is downloaded at first use.

**subtitle_gen / remotion_caption_burn** — Chinese, Japanese, Korean are detected: no spaces between characters,
a cue / caption page per clause (cut at ，。！？), a clause wider than 16 characters (14 per page when burning)
split into even parts, the clause's comma or full stop not shown. `corrections` may span characters:
`{"克劳德": "Claude"}`. English works as before. remotion_caption_burn's Remotion path works again (it passed
a `public/` prefix that Remotion refuses).

**video_compose / showcase_card captions and text** — the box's Homebrew ffmpeg has no libass or drawtext; any
ffmpeg command that draws text is run with `.localkin/bin/ffmpeg-libass` automatically. Chinese renders (the
font falls back to one with CJK glyphs).

**face_tracker** — `method: "auto"`: Apple's Vision (`.localkin/bin/kin-faces`, 27 s of video in 2.6 s), else
MediaPipe 0.10 in its own environment (`method: "mediapipe"`), else OpenCV. **eye_enhance** runs in that
MediaPipe environment (Face Mesh), unchanged. auto_reframe can follow the face for 9:16.

**talking_head** — `model: "auto"` = Ditto (photo + voice → the whole face talking, lips included; 5 s of
speech in 30 s, at the photo's size). `model: "sadtalker"` = SadTalker itself (CPU, 5 s in ~3 min, 256 px crop
unless `preprocess: "full"`). `expression_scale`, `still_mode` (head keeps the photo's pose) and `crop_scale`
(Ditto: how much around the face moves) work.

**lip_sync** — `model: "auto"` = Ditto with the video as its source: the whole face drawn again speaking the
audio, lips and teeth as sharp as the original, the head as the video moves it (frames repeat if the audio is
longer; 25 fps out, 10 s in about a minute). `model: "musetalk"` = MuseTalk 1.5, only the mouth, as tuned for the
companion's live face — it blurs a small or turned face (17 s in ~60 s). `model: "wav2lip"` / `"wav2lip_gan"` =
Wav2Lip itself on the GPU (blurrier mouth patch; only the GAN weights are on the box, `wav2lip` uses them).

**music_gen** — without an ElevenLabs key: ACE-Step 1.5 XL Turbo on ComfyUI. It keeps **exactly** the
`duration_seconds` asked (MiniMax Music 3 picks its own length — use this when the length matters). Optional
`lyrics` (with [Verse]/[Chorus]; Chinese works, `language: "zh"`), `bpm` (else read from "95 BPM" in the
prompt), `keyscale`, `seed`. 30 s in about 2 minutes. Instrumental unless lyrics are given.

**blender_world** — the box's Blender 5.2.1 (BLENDER_PATH in .env). Written for 4.5; check a still first.

**math_animate** — manim 0.21 without LaTeX: `Text` works, `MathTex` / `Tex` do not.

**character_rig_renderer** — `output_path` must end in `.html` (the preview page Playwright films).

**corpus_builder** — NASA hands over its original renditions (often hundreds of MB each): keep `max_new_clips`
small and prefer archive_org / wikimedia for a first pass.

## Chinese short-video habits (抖音 / 小红书 / B站 / 视频号)

- 9:16 by default (`auto_reframe target_aspect: "portrait"`, face-tracked); captions on, a clause per caption.
- Voices: box_tts — `instruct` describes a voice in Chinese words (8102), or a preset `voice` (8101).
- A score of exactly the cut's length: music_gen (ACE-Step), then audio_mixer to duck it under the voice.
- Ask before heavy steps: H3 ~10 min per 5 s shot, Ditto ~6 s per spoken second, MuseTalk ~3.5 s per second.
