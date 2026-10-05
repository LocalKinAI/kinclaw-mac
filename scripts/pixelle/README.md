# KinClaw's changes to Pixelle-Video on the box

Pixelle-Video runs on the box (`~/Pixelle-Video`, its API on 127.0.0.1:8190) with LocalKin's own changes —
the one-take narrator, moving scenes, `rework` — made there on 2026-09-28. The app drives it through
`KinClawMac/Resources/pixelle/pv.py` over ssh.

| file | what |
|---|---|
| `rework-redraw.patch` | `rework` draws chosen scenes again (`redraw`, with new words in `image_prompts`) and composes their cards again; every other scene keeps its picture, voice and clip. The box's Qwen workflow seeds its noise from the scene number (`$index.noise_seed`), so a redraw with the same words passes a fresh `index` — passing `seed` alone gave the same picture byte for byte. |

Apply in `~/Pixelle-Video` (after LocalKin's own changes are there), then `pv.py restart` with no job running:

```sh
scp rework-redraw.patch jackysub@192.168.0.21:.kinclaw/
ssh jackysub@192.168.0.21 'cd ~/Pixelle-Video && patch -p1 < ~/.kinclaw/rework-redraw.patch'
```

Tested 2026-09-30 on 「小龙虾不爱住脏水」 (7 scenes): `redraw: [1]` gave scene 1 a new picture and left the six
others byte for byte as they were, in about a minute.
