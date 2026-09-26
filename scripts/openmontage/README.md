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
