#!/usr/bin/env python3
"""Score B → the film's music bed, with the mix baked in (assets/bgm/bed.wav, volume 1.0).

Score B peaks warm around 89–95 s and has faded out by 96–100 s — played straight, the end
card sat in near-silence. The bed is slowed (pitch kept) so that peak lands on the end card,
then shaped over film time:
  · under the voice   0.13 (≈ −18 dB, the pipeline's bed level)
  · each quote's hold  swells to 0.22 after the quote is spoken, back under the next line
  · the end card       rises to 0.42 once the last word is said, fades out with the picture

    python3 scripts/music_bed.py        (re-run after any duration change, then assemble)
"""
import json, pathlib, subprocess, tempfile, wave

import numpy as np

P = pathlib.Path(__file__).resolve().parents[1]
SRC = P / "assets/bgm/score-b.wav"
OUT = P / "assets/bgm/bed.wav"
PEAK_RAW_S = 90.0          # where score B is warmest
BASE, HOLD, END = 0.13, 0.22, 0.42
QUOTE_FRAMES = {4, 6, 8, 9}

meta = json.loads((P / "audio_meta.json").read_text())
voices = sorted(meta["voices"], key=lambda v: v["frame"])
starts, t = {}, 0.0
for v in voices:
    starts[v["frame"]] = t; t += v["duration_s"]
total = t
last = voices[-1]
vo_end = starts[last["frame"]] + last["words"][-1]["end"]

factor = (vo_end + 0.4) / PEAK_RAW_S  # slow-down so the peak arrives just after the last word
with tempfile.TemporaryDirectory() as td:
    tmp = pathlib.Path(td) / "slow.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(SRC), "-af", f"atempo={1 / factor:.5f}", "-ar", "48000", str(tmp)], check=True)
    with wave.open(str(tmp)) as w:
        sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(np.float32)

need = int(round(total * sr))
if len(x) < need:
    raise SystemExit(f"✗ slowed score is {len(x) / sr:.1f}s, film is {total:.1f}s")
x = x[:need]

# gain breakpoints over film time
pts = [(0.0, BASE)]
for v in voices:
    if v["frame"] in QUOTE_FRAMES:
        a = starts[v["frame"]] + v["words"][-1]["end"] + 0.1
        b = starts[v["frame"]] + v["duration_s"]
        nxt = next((w for w in voices if w["frame"] == v["frame"] + 1), None)
        back = b + (nxt["words"][0]["start"] if nxt else 0.0)
        pts += [(a, BASE), (a + 0.6, HOLD), (b - 0.2, HOLD), (min(back, b + 0.8), BASE)]
pts += [(vo_end + 0.1, BASE), (vo_end + 1.6, END), (total - 1.2, END), (total, 0.0)]
pts.sort()
tt = np.arange(need) / sr
gain = np.interp(tt, [a for a, _ in pts], [g for _, g in pts]).astype(np.float32)
y = np.clip(x * gain[:, None], -32768, 32767).astype(np.int16)
with wave.open(str(OUT), "wb") as w:
    w.setnchannels(ch); w.setsampwidth(sw); w.setframerate(sr); w.writeframes(y.tobytes())

meta["bgm"] = {"path": "assets/bgm/bed.wav", "volume": 1.0, "duration_s": round(total, 3),
               "query": f"box minimax_music score B (seed 7), slowed ×{factor:.3f} so its peak lands on the end card; mix baked in by scripts/music_bed.py"}
meta["bgm_pending"] = False
(P / "audio_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
print(f"✓ bed.wav {total:.1f}s · score slowed ×{factor:.3f} (tempo −{(1 - 1 / factor) * 100:.0f}%) · last word at {vo_end:.2f}s → end-card swell")
