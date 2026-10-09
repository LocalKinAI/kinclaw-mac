# OpenMontage on the box

[OpenMontage](https://github.com/calesthio/OpenMontage) (AGPL-3.0) is a toolkit a coding agent drives to make
videos. It is installed on the box at `~/OpenMontage` (Python 3.12 venv via uv, Remotion, Piper; install script
`~/.kinclaw/openmontage-install.sh`). These files plug the box's own ComfyUI into it, so it can generate with the
models already there instead of paid APIs:

| file | copied to | registers |
|---|---|---|
| `tools/_box.py` | `~/OpenMontage/tools/_box.py` | shared helpers (sizes, pinned-frame pictures) |
| `tools/graphics/qwen_image.py` | `~/OpenMontage/tools/graphics/` | `qwen_image` — Qwen-Image 2.1, text-to-image and edit with reference pictures |
| `tools/video/h3_video.py` | `~/OpenMontage/tools/video/` | `h3_video` — MiniMax H3 ref2va, cast portraits as references, first frame pinned, `hold` |
| `tools/audio/minimax_music.py` | `~/OpenMontage/tools/audio/` | `minimax_music` — MiniMax Music 3 |
| `tools/audio/music_extend.py` | `~/OpenMontage/tools/audio/` | `music_extend` — a score made as long as the film: loops back where the music matches itself (one or two seams, crossfaded), keeps its own ending unless `exact` |
| `patches/checkpoint-all-errors.patch` | `git apply` in `~/OpenMontage` | `lib/checkpoint.py`: every schema problem listed at once (not one per try), and a project folder passed as `pipeline_dir` refused instead of nesting the checkpoints |
| `skills/minimax-h3-local/SKILL.md` | `~/OpenMontage/.agents/skills/minimax-h3-local/` | how to film with them (the pinned-first-frame method) |

OpenMontage finds tools by walking its `tools` package, so copying a file in is all it takes. `.env` on the box sets
`COMFYUI_SERVER_URL=http://127.0.0.1:8188`.

Install or update from this Mac:

```sh
cd scripts/openmontage
scp tools/_box.py jackysub@192.168.0.21:OpenMontage/tools/
scp tools/graphics/qwen_image.py jackysub@192.168.0.21:OpenMontage/tools/graphics/
scp tools/video/h3_video.py jackysub@192.168.0.21:OpenMontage/tools/video/
scp tools/audio/minimax_music.py jackysub@192.168.0.21:OpenMontage/tools/audio/
ssh jackysub@192.168.0.21 'mkdir -p ~/OpenMontage/.agents/skills/minimax-h3-local'
scp skills/minimax-h3-local/SKILL.md jackysub@192.168.0.21:OpenMontage/.agents/skills/minimax-h3-local/
```

Check on the box: `cd ~/OpenMontage && source .venv/bin/activate && make preflight` — the three tools are listed as
available under image_generation, video_generation and music_generation.

Tested on the box on 2026-09-25 with a shot of 五饼二鱼 (`projects/box-test`): `qwen_image` edit composed the first
frame from the set and two portraits in 135 s; `h3_video` filmed 141 frames from it in 712 s with the first frame
pinned exactly, faces kept and its own ambient sound; `minimax_music` wrote a 14 s cue in 982 s (−26.5 LUFS,
peak −6.4 dBFS).

## All twelve pipelines on the box (2026-10-04)

Jacky: 「一个一个链接吧，把他们都弄上」 and 「不可以用的就弄可用啊」 — every pipeline's tools made to run on the box,
with OpenMontage's own tools kept and the box's models added where its backends were missing (cloud keys,
CUDA, a dependency its environment had moved past). What runs on what, for the agent:
`skills/localkin-pipelines/SKILL.md`.

| file | goes to | what |
|---|---|---|
| `patches/localkin-box-backends.patch` | `git apply` in `~/OpenMontage` | transcriber `engine: box` (Qwen3-ASR's words, whisper's timing), Chinese captions in subtitle_gen and remotion_caption_burn (and its `public/` path fix), text-drawing ffmpeg in `run_command`, face_tracker Vision → MediaPipe, eye_enhance in MediaPipe's env, talking_head Ditto / SadTalker, lip_sync MuseTalk / Wav2Lip, music_gen ACE-Step 1.5, blender_world on Blender 5 (EEVEE renamed back; a render that wrote nothing now fails) |
| `tools/subtitle/cjk.py` | `~/OpenMontage/tools/subtitle/` | CJK joins, clause cues, even splits, multi-character corrections |
| `tools/_mediapipe_env.py` | `~/OpenMontage/tools/` | runs a tool's own `execute()` in MediaPipe 0.10's environment |
| `localkin/kin-faces.swift` | build, then `~/OpenMontage/.localkin/bin/kin-faces` | faces by Apple's Vision in face_tracker's JSON (`swiftc -O -target arm64-apple-macos14 …`) |
| `skills/localkin-pipelines/SKILL.md` | `~/OpenMontage/.agents/skills/localkin-pipelines/` | which pipeline runs on what, and how to call the changed tools |
| `tools/video/video_translate.py` | `~/OpenMontage/tools/video/` | `video_translate` — a video into another language: the speaker's own voice cloned from a few seconds of it (Qwen3-TTS Base, :8103), the face drawn again by Ditto to say the new words, an .srt; 10 s in about a minute |
| `setup/talkers_setup.sh` | `~/kin-avatar/` | SadTalker (checkpoints 2.5 GB) and Wav2Lip (GAN weights + s3fd) with one Python 3.10 env (`~/kin-avatar/talkers`), MediaPipe 0.10.21 in its own (`~/kin-avatar/mediapipe`) |
| `patches/wav2lip-mps-torchscript.patch` | `git apply` in `~/kin-avatar/wav2lip` | its README's weights are TorchScript now; Apple's GPU for inference and face detection |
| `setup/om_tools_setup.sh` | `~/kin-avatar/` | Pygments, Playwright (+ its Chromium), torch + transformers + CLIP ViT-B/32, cairo (Homebrew) + manim, into OpenMontage's venv |

Also on the box, not in git: `~/OpenMontage/.localkin/bin/ffmpeg-libass` is imageio-ffmpeg's static ffmpeg 7.1
(libass, freetype) copied from MuseTalk's venv — Homebrew's ffmpeg 9 has neither, so no caption or title card
burnt; `.env` has `BLENDER_PATH` (the box's Blender 5.2.1). The face tools need `~/kin-avatar/face/kin_lipsync.py`
and `~/kin-avatar/ditto/ditto-talkinghead/kin_ditto_talk.py` (scripts/kin-face). `.agents/skills/huashu-art-motion` and
`.agents/skills/onetake` (2026-10-08) are installed as their authors ship them — onetake's licence is PolyForm
Noncommercial, private use only — and render with OpenMontage's own venv, which got opencv-python and matplotlib
for them.

Measured on the box: transcriber 75 s of narration in 25 s (98 % of characters timed directly); a Chinese 口播 clip
captioned with Remotion in 9 s; silence cut 26.8 → 10.3 s in 1.2 s; Ditto 5 s of speech in 30 s, SadTalker in
170 s; MuseTalk lip-sync 17 s in 62 s, Wav2Lip 5 s in 13 s; a Chinese → English dub (transcribe, voice, lip-sync,
captions) in 55 s; ACE-Step 30 s of music in 121 s, exactly 30.0 s; a cartoon character waving and nodding in 7 s.
