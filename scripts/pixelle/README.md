# KinClaw's changes to Pixelle-Video on the box

Pixelle-Video runs on the box (`~/Pixelle-Video`, its API on 127.0.0.1:8190) with LocalKin's own changes —
the one-take narrator, moving scenes, `rework` — made there on 2026-09-28. The app drives it through
`KinClawMac/Resources/pixelle/pv.py` over ssh.

| file | what |
|---|---|
| `rework-redraw.patch` | `rework` draws chosen scenes again (`redraw`, with new words in `image_prompts`) and composes their cards again; every other scene keeps its picture, voice and clip. The box's Qwen workflow seeds its noise from the scene number (`$index.noise_seed`), so a redraw with the same words passes a fresh `index` — passing `seed` alone gave the same picture byte for byte. |
| `given-pictures.patch` | `images` on a new video (one picture per scene, null to draw it) and on `rework` (`{"6": path}`): finished pictures — drawn with the app's 画 and fixed with 改, Qwen-Image-2.1-Turbo — used as they are, only composed into the card. `given_picture` takes only a picture file under Pixelle's own folder (pv.py copies the Mac's files to `data/uploads/<stamp>/` in one tar stream) and saves it as the task's `frames/NN_image.png`; the frame processor no longer draws a frame that already has a picture. Applied on top of `rework-redraw.patch`; the files it replaced are in the box's `~/.kinclaw/pixelle/before-pictures-20261012/`. |

| `given-voiceovers.patch` | `audios` the same way for the narration: one sound file per scene on a new video (null voices it), `{"6": path}` on `rework` (not with `revoice`). `given_sound` takes only a sound file under Pixelle's root, saved as `frames/NN_audio.<ext>`; the scene lasts as long as it, and the storyboard's `voice` says `given`. Files it replaced: the box's `~/.kinclaw/pixelle/before-voiceovers-20261012/`. |

Apply in `~/Pixelle-Video` (after LocalKin's own changes are there), in this order, then `pv.py restart` with no
job running:

```sh
scp rework-redraw.patch given-pictures.patch given-voiceovers.patch jackysub@192.168.0.21:.kinclaw/
ssh jackysub@192.168.0.21 'cd ~/Pixelle-Video && for p in rework-redraw given-pictures given-voiceovers; do patch -p1 < ~/.kinclaw/$p.patch || break; done'
```

Tested 2026-09-30 on 「小龙虾不爱住脏水」 (7 scenes): `redraw: [1]` gave scene 1 a new picture and left the six
others byte for byte as they were, in about a minute. `images` tested 2026-10-12: two given pictures, 1920x1080
image_full, pan, a two-scene video in about a minute with nothing drawn.
