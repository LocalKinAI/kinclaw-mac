# kin-face — her face lip-synced on the box as she speaks

`LiveFace` (KinClawMac/Services/LiveFace.swift) shows what this streams: twenty frames a second
of her photograph talking. The body is rendered once by Ditto — two bodies, as HeyGen films its
presenters: one that listens (lips closed, a tilt, a blink) and one whose head moves as she talks
(the lips held as in the photograph); the camera still in both. The mouth is MuseTalk 1.5 on MLX,
made from each sentence of her voice, over whichever body she is in.

Measured on the M3 Ultra, 2026-10-02:

| | |
|---|---|
| frames | 20 a second, steady on the box (MuseTalk full quality sustains ~22) |
| a whole sentence pushed at once | its frames leave the box 0.31 s later (0.49 at worst) |
| pushed at the speed of speech | 1.21 s later (MuseTalk's 1 s audio windows) — why the app pushes whole sentences |
| lips against voice | mouth a frame or two ahead, as a person's is |
| a cut between the bodies | 1.1 (median, mean square on a 96×123 grey thumbnail) against 0.2 for one frame to the next; cross-faded over 4 frames |
| start-up | 76 s (796 frames of both bodies precomputed, 3 GB of pool) |

## Why this split

- **Ditto** (Ant Group, Apache-2.0; `~/kin-avatar/ditto/ditto-talkinghead`, its Apple Silicon PR
  #92) makes the whole face from a voice, but on this GPU at 91 ms a frame at best — ten frames
  a second. Found on the way: its warp spent 543 of 583 ms in one 7×7×7 Conv3d; done as seven
  Conv2d (`kin_conv3d_as_2d.py`, identical output) it is 63 ms. FasterLivePortrait-MLX with
  Ditto's own weights converted (same picture, 0.5/255) was 91 ms. So Ditto renders the bodies,
  once.
- **MuseTalk** (`~/kin-avatar/musetalk`, setup and fixes in its KIN-NOTES.md) replaces only the
  mouth and jaw, in real time. Over a moving camera (H3, LTX) its mouth floated (Jacky: 「第二个
  飘了」); over Ditto's still camera it does not (「不飘了」).
- **Two bodies.** With one, her head idled while her mouth talked; the face read wrong without
  anyone being able to say why (「说不上来的感觉」). The talking body comes from Ditto driven by a
  voice with its six lip keypoints held at the photograph's (`kin_ditto_speaking.py`: Ditto
  mixes each keypoint as driven·a1 + photo·a2; the lips get a1 = 0). Its head moves about 2.5×
  as much as the listening body's. Taking the rest of the expression from the voice as well
  (`face` mode) moved the cheeks round MuseTalk's mouth to someone else's words and the brows
  hardly more (their motion 1.51 against 1.52), so it is `head`: pose, gaze and blinks.

## A look

```
~/kin-avatar/face/looks/<name>/
  photo.png           her photograph (1024×1312 for the companion panel)
  idle-source.mp4     Ditto from photo.png and 10 s of faint pink noise (kin_ditto_crop.py)
  speak-source.mp4    Ditto from photo.png and ~17 s of her speaking, lips held (kin_ditto_speaking.py)
  base.mp4            the listening body: 8 s of idle-source at 20 fps, forward then back (no seam)
  speak.mp4           the talking body: 12 s of speak-source, the same way
  bodies.mp4          both, listening first — made by the server when missing or older
```

```
# in ditto-talkinghead, .venv312
python kin_ditto_crop.py     checkpoints/ditto_cfg/v0.4_hubert_cfg_pytorch.pkl photo.png quiet10.wav idle-source.mp4 1.8
python kin_ditto_speaking.py checkpoints/ditto_cfg/v0.4_hubert_cfg_pytorch.pkl photo.png speech16k.wav speak-source.mp4 1.8 head
# in the look
ffmpeg -i idle-source.mp4 -filter_complex "[0:v]trim=0:8,setpts=PTS-STARTPTS,fps=20,split[a][b];[b]reverse,trim=start_frame=1,setpts=PTS-STARTPTS[r];[a][r]concat=n=2:v=1:a=0,trim=end_frame=318" -an -c:v libx264 -crf 14 -pix_fmt yuv420p base.mp4
ffmpeg -i speak-source.mp4 -filter_complex "[0:v]trim=0:12,setpts=PTS-STARTPTS,fps=20,split[a][b];[b]reverse,trim=start_frame=1,setpts=PTS-STARTPTS[r];[a][r]concat=n=2:v=1:a=0,trim=end_frame=478" -an -c:v libx264 -crf 14 -pix_fmt yuv420p speak.mp4
```

`LOOK=~/kin-avatar/face/looks/<name>` chooses one (default `looks/current`, a link). A look
without `speak.mp4` runs with one body, as before.

## Between the bodies

The renderer takes its frames from `Bodies.speaking` (in place of MuseTalk's own looped
serving), the frames shown while she is quiet come from `Bodies.listening`: one walk through the
pool. When she starts, the walk cuts to the talking frame most like the listening frame that
would have come next — and like the ones either side of it, so she keeps moving the way she was.
When she stops she stays in the talking body (closed lips: it is a pause between sentences, not
listening) for at least 10 frames, then goes back at a frame that matches well (cost in the best
30 %), after 30 at the latest. Each cut is cross-faded over 4 frames and logged
(`talking: listening frame i -> talking j`, `listening after n quiet frames: …`).

## The link to the Mac

Twenty 154 KB JPEGs a second are 25 Mbit/s. Both machines were on Wi-Fi (2026-10-02, Ethernet
unplugged on both; ping 5–205 ms): frames that left the box 50 ms apart arrived in bursts, held
back 0.4 s and more, and while the Wi-Fi fell to ~5 Mbit/s for a while every frame was still sent
and they arrived up to 16 s late. So, with `/face?v=2` (the app since then):

- each frame carries its slot on the box's clock, and the app shows it that long after the
  soonest any frame has come lately plus a buffer that follows the link (95 % on time, 0.08–0.5 s);
  her voice waits as much longer;
- the app answers every frame (`seen`), and while the oldest unanswered one is over 0.25 s old
  the box drops frames instead of queueing them: measured on the same Wi-Fi, 7 % dropped,
  lateness median 21 ms / p99 0.54 s / max 0.77 s instead of 16 s.

A cable on both is still the real fix.

## Running

`server.py` runs in MuseTalk's virtualenv (`~/kin-avatar/musetalk/.venv/bin/python`), :8105,
ready in about 76 s (precompute of both bodies + one warm-up window). Started and stopped like
the other box services: Settings → Backend → 盒子上的服务, or the console's 盒子 panel.
Log: ~/Library/Logs/kinclaw/face.log. Protocol in the server's docstring. One viewer at a time —
a test client takes the face away from the app.

`kin_ditto_online.py` drives Ditto's streaming pipeline with its GPU calls serialized (PyTorch's
MPS backend crashes when several threads encode at once) — kept for the measurements.

## For OpenMontage too (2026-10-04)

- `kin_mouth.py` — the mouth+jaw mask, the crop line (FACE_BBOX_SHIFT) and the sharper paste, as one
  `install()`: server.py and the offline lip-sync share it.
- `kin_lipsync.py` (in `~/kin-avatar/face`, MuseTalk's venv) — a video lip-synced to a voice, offline: OpenMontage's
  `lip_sync` model "musetalk" (avatar-spokesperson, localization-dub). The video is the body, looped when shorter
  than the voice; its own frame rate. 17 s of speech over a 512×656 clip in about a minute.
- `kin_ditto_talk.py` (in `ditto-talkinghead`, its `.venv312`) — Ditto from a photograph and a voice with the lips
  driven too: OpenMontage's `talking_head` model "ditto". `--still` keeps the photograph's pose, `--expression`
  scales the face's movement. 5 s of speech in 30 s. Given a video instead of a photograph it draws the face again
  over every frame (ping-pong when the voice is longer): the offline lip-sync now (`lip_sync` auto, video_translate)
  — sharper than MuseTalk's mouth, but each pass softens a face, so a video made from a photograph is redone from
  the photograph.
