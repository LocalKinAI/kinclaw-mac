---
name: minimax-h3-local
description: Use when a video should be generated on the local box instead of a paid API — h3_video (MiniMax H3 with cast portraits and pinned frames, native sound), qwen_image (stills, sets and composed first frames) and minimax_music (MiniMax Music 3 scores). Covers the pinned-first-frame method, hold shots for things that must not change, H3's prompt form, and how long each takes.
---

# Local generation on the box: H3, Qwen-Image, MiniMax Music 3

Three tools run on the box's own ComfyUI (an M3 Ultra; free, no API key):

| tool | what | time |
|---|---|---|
| `qwen_image` | stills from words; **edit mode** with `reference_images` composes or changes a picture | ~40–45 s (fast, the default); 1.5–2.5 min with `fast: false` |
| `h3_video` | MiniMax H3 video **with sound** from reference pictures, with frames pinned | ~10 min per 5 s shot |
| `minimax_music` | MiniMax Music 3 score, instrumental or with lyrics, up to 5 min | ~70 s of compute per second of music |

`qwen_image` is fast by default: PrunaAI's 8-step LoRA for Qwen-Image 2.1 (strength 2.0, its own sigmas, no CFG) — about three times quicker than the old 25 steps, and as good in the tests so far (2026-09-26). Use `fast: false` for a hero frame that came out soft or wrong; it falls back to the slow way by itself where the LoRA is not installed.

`h3_video` is not the hosted `minimax_h3_api` Partner Node in `comfyui_video` (that bills a Comfy account).
H3 on the box cannot make video from words alone — every shot needs a picture.

## Filming a story shot: the pinned-first-frame method

H3 keeps **faces and clothes** from portraits; it does **not** keep things or numbers unless they are pinned.
Measured on a Bible short (five loaves and two fish, twelve baskets):

1. **Cast once.** One `qwen_image` portrait per person who comes back: tight head-and-shoulders, plain light
   backdrop, face filling a third of the frame, period clothes. Same portrait in every shot of that person.
2. **The set.** One `qwen_image` picture per shot of the place with the props, nobody in it — framed as the camera
   will be. Anything the story counts is drawn apart, whole and easy to count ("exactly five (5) round loaves").
3. **The first frame** — `qwen_image` in edit mode: `reference_images: [set, portrait_1, portrait_2]`, and a prompt
   that says "Image 1 is the place and what is in it; image 2 is the boy; image 3 is Jesus. Make one photograph of
   them together — the first frame of a film shot: <camera>. <what the moment shows>. They keep exactly the faces,
   hair and clothes of their pictures." **Look at it and count** before filming (it takes minutes to film a wrong one).
4. **Film** — `h3_video` with `reference_image_path: first_frame.png` (pinned at frame 0) and
   `reference_images: [portrait_1, portrait_2, set]`. The shot starts exactly there; H3 moves it, keeps the faces, and
   brings its own sound.
5. **Shots with nobody in them** start from the set itself.
6. **Shots where nothing may change** (a row of baskets, a counted table) → `hold: true`: the same frame is pinned at
   the start, middle and end. Pinned only at both ends, H3 wandered off to another slope with fourteen baskets and
   came back; held, the count stayed twelve at every half second while the mist moved on the lake.
7. **Check every second of every take**: count what the story counts (a frame per second, one at a time), look for a
   jump to another place half way, faces against the portraits. A reviewer that scores 10 is not proof.

Changing a thing to match another shot (shot 7's bread as shot 4's loaves): take a frame from the start of the take,
`qwen_image` edit with `reference_images: [that_frame, frame_from_shot_4]` and "make the bread in image 1 exactly like
the loaves in image 2 — <colour, shape, surface as they really look>", then film from it with `h3_video`
(`reference_image_path`). Describe the look from the picture, not from memory: "dark, cracked" for smooth tan loaves
gave the wrong bread.

## H3's prompt form

H3 was trained on six sections; write them in this order, naming pictures as `<Picture N>` in the order of
`reference_images` (the first frame, when not in that list, is added after them):

```
subject_definitions:
<Subject 1> is the boy, … wearing …, from <Picture 1>.
<Subject 2> is …, from <Picture 2>.
<Subject 3> is the hillside set in <Picture 3>, featuring …
summary:
[reference generation] The target video shows <Subject 1> … and <Subject 2> ….
retention_analysis:
<Subject 1> (appears in [Shot 1]): fully_preserved - the face, hair and clothes are retained.
detailed_description:
The target video is in the visual tone of <a real film> (<year>), cinematography by <DP>: <light, palette, texture>.
[Shot 1] <camera>. <one clear action that plainly changes the frame>. The camera holds static.
overall_soundscape:
<the place's own sound: wind, cloth, a crowd far away — never music>
non_diegetic_music:
N/A
```

One shot per call, no cuts; nobody speaks (narration and music are laid on afterwards); nothing modern, no text.
Say counted numbers exactly and say the camera holds still in a counted shot.

## Music

`minimax_music` wants a brief in MiniMax's structure:

```
Global Metadata: Sacred cinematic score for <the film>. Around 60 BPM rising to 72, D Phrygian dominant resolving to
D major. Arc: hushed start, slow build of wonder, radiant swell at <the moment>, peace at the end. Recorded in a stone
hall: natural reverb, wide stereo.
Vocal Details: No lead vocals and no words. A soft wordless choir hum joins only in the swell.
Arrangement: Opens with a low drone and solo oud … frame drums enter … strings and choir swell … fades on the ney.
```

Ask for it as soon as the length of the film is known — it runs for tens of minutes — and lay it under the narration
lower while someone speaks (about 9 dB under the voice).

## Sizes and speed

- `h3_video` default 928×544 (0.5 MP, 16:9), 24 fps, 124 frames minimum (≈5.2 s); a `duration` goes to the nearest
  17k+5 frames (5.2 s → 124, 6 s → 141). `megapixels: 0.98` is H3's 768p at 2–3× the time. `full_quality` (20 steps,
  no LoRA) is ~5× slower — for a shot already approved.
- `minimax_music` comes back up to 2 s longer than asked (room for its own ending); trim it at the cut.
- One H3 job at a time; ComfyUI unloads Qwen when H3 needs the memory and the other way round.
- A timed-out job is still running on the box: pass the error's `prompt_id` back as `resume_prompt_id`.
