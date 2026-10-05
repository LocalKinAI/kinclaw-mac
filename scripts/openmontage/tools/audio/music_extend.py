"""A score made as long as the film: lengthened where it repeats itself, so nobody hears the seam.

MiniMax Music 3 decides a piece's length itself: asked four times for 62 s
for the Selah promo it gave 50.4, 31.4, 44.7 and 43.2, and asking for more
changes almost nothing. What saved that film was looping back by hand — from
a strong beat to an earlier one where the music just before and just after
both sound alike — found by projects/faith-selah-promo/splice.py (Montage's
notebook, 2026-09-30). This is that, as a tool that also renders:

  1. Strong low-end onsets (the drum hits) are the only places a jump may
     start or land.
  2. A jump back from b to a is scored by how alike two seconds before and
     two after each point are: chroma, timbre (MFCC) and loudness.
  3. One jump, or two that do not overlap, adding what is missing (within
     two seconds); failing that, the best section repeated.
  4. Each seam is a short equal-power crossfade; the piece keeps its own
     ending unless an exact length is asked for.

Shorter is easier: a piece already long enough is ended on the target with
a fade (exact) or left as it is.
"""

from __future__ import annotations

import itertools
import time
from pathlib import Path
from typing import Any

from tools.base_tool import (
    BaseTool,
    Determinism,
    ExecutionMode,
    ResourceProfile,
    RetryPolicy,
    ToolResult,
    ToolRuntime,
    ToolStability,
    ToolTier,
)


class MusicExtend(BaseTool):
    name = "music_extend"
    version = "0.1.0"
    tier = ToolTier.ENHANCE
    capability = "music_editing"
    provider = "librosa_local"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.DETERMINISTIC
    runtime = ToolRuntime.LOCAL

    install_instructions = "Needs librosa, soundfile and numpy in OpenMontage's venv (already there on the box)."
    capabilities = ["lengthen_music", "loop_points", "fit_music_to_length"]
    supports = {"max_jumps": 2, "offline": True}
    best_for = [
        "a generated score that came out shorter than the film (MiniMax Music 3 picks its own length)",
        "a cue that has to land on an exact length",
    ]
    not_good_for = ["music with no beat or no repetition (a drone, a solo voice): there is no seam to hide"]
    quality_score = 0.8
    latency_p50_seconds = 20

    input_schema = {
        "type": "object",
        "required": ["audio_path", "target_seconds"],
        "properties": {
            "audio_path": {"type": "string", "description": "The score to lengthen (wav, flac, mp3)."},
            "target_seconds": {"type": "number", "description": "How long it should be."},
            "output_path": {"type": "string", "description": "Where to write the wav. Default: beside it, <name>_<target>s.wav"},
            "max_jumps": {"type": "integer", "default": 2, "description": "1 or 2 loop-backs."},
            "crossfade_ms": {"type": "integer", "default": 40, "description": "Each seam's crossfade."},
            "exact": {"type": "boolean", "default": False,
                      "description": "Cut to exactly target_seconds with a fade. Default keeps the piece's own ending "
                                     "and lands within about two seconds of the target."},
            "fade_out_seconds": {"type": "number", "default": 2.0, "description": "The fade when it is cut (exact)."},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=2, ram_mb=2000, vram_mb=0, disk_mb=50, network_required=False)
    retry_policy = RetryPolicy(max_retries=0)
    idempotency_key_fields = ["audio_path", "target_seconds", "max_jumps", "crossfade_ms", "exact"]
    side_effects = ["writes a wav file to output_path"]
    user_visible_verification = ["Listen across each seam (the result lists where they are): no stumble, no click"]

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        import librosa
        import numpy as np
        import soundfile as sf

        started = time.time()
        source = Path(inputs["audio_path"]).expanduser()
        if not source.exists():
            return ToolResult(success=False, error=f"no such file: {source}")
        target = float(inputs["target_seconds"])
        jumps_allowed = max(1, min(int(inputs.get("max_jumps") or 2), 2))
        crossfade = max(0, int(inputs.get("crossfade_ms") or 40)) / 1000
        exact = bool(inputs.get("exact"))
        out = Path(inputs.get("output_path") or source.with_name(f"{source.stem}_{int(round(target))}s.wav")).expanduser()

        audio, rate = sf.read(str(source), always_2d=True)          # the piece as it is, every channel
        length = len(audio) / rate

        jumps: list[tuple[float, float, float]] = []                 # (a, b, score): play to b, carry on from a
        if length < target - 0.25:
            y, sr = librosa.load(str(source), sr=22050, mono=True)
            hop = 256
            spectrum = np.abs(librosa.stft(y, n_fft=2048, hop_length=hop))
            freqs = librosa.fft_frequencies(sr=sr, n_fft=2048)
            low = librosa.amplitude_to_db(spectrum[freqs < 150].sum(0) + 1e-6)
            rise = np.diff(low)
            onsets = librosa.onset.onset_detect(y=y, sr=sr, hop_length=hop, units="time", backtrack=False)
            chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop)
            mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13, hop_length=hop)
            rms = librosa.feature.rms(y=y, hop_length=hop)[0]

            def frame(t: float) -> int:
                return max(0, int(t * sr / hop))

            def features(a: float, b: float):
                i, j = frame(a), max(frame(a) + 1, frame(b))
                c = chroma[:, i:j].mean(1)
                return c / (np.linalg.norm(c) + 1e-9), mfcc[1:, i:j].mean(1), rms[i:j].mean()

            def alike(t1: float, t2: float, w: float = 2.0) -> float:
                # The music just before and just after must both match.
                score = 0.0
                for a, b in ((-w, 0.0), (0.0, w)):
                    c1, m1, r1 = features(t1 + a, t1 + b)
                    c2, m2, r2 = features(t2 + a, t2 + b)
                    score += float(c1 @ c2) - 0.004 * float(np.linalg.norm(m1 - m2)) - 2 * abs(np.log((r1 + 1e-6) / (r2 + 1e-6)))
                return float(score / 2)          # numpy's float32 does not go into JSON

            strength = {float(t): float(rise[max(0, frame(t) - 3):frame(t) + 3].max()) for t in onsets}
            candidates = [t for t in onsets if 2.5 < t < length - 6 and strength[float(t)] > 1.5]
            if len(candidates) < 2:          # a quiet piece: take every onset clear of the ends
                candidates = [t for t in onsets if 2.5 < t < length - 6]
            need = target - length
            # Every section longer than four seconds, best match first; those that fit what is missing.
            pairs = sorted(((alike(a, b), float(a), float(b)) for a, b in itertools.combinations(candidates, 2)
                            if b - a > 4), reverse=True)
            fitting = [p for p in pairs if p[2] - p[1] <= need + 0.8]
            best = None
            for score, a, b in fitting[:40]:
                if abs((b - a) - need) < 2.0:
                    value = 2 * score - 0.2 * abs((b - a) - need) + 0.1
                    if best is None or value > best[0]:
                        best = (value, [(a, b, score)])
            if jumps_allowed == 2:
                for (s1, a1, b1), (s2, a2, b2) in itertools.combinations(fitting[:40], 2):
                    total = (b1 - a1) + (b2 - a2)
                    if abs(total - need) < 2.0 and (b1 <= a2 or b2 <= a1):
                        value = s1 + s2 - 0.2 * abs(total - need)
                        if best is None or value > best[0]:
                            best = (value, sorted([(a1, b1, s1), (a2, b2, s2)], key=lambda p: p[1]))
            if best:
                jumps = best[1]
            elif pairs:
                # Nothing adds up: the best-matching section played again until the piece is long enough.
                score, a, b = pairs[0]
                times = max(1, min(4, int(round(need / (b - a)))))
                jumps = [(a, b, score)] * times
            else:
                return ToolResult(success=False, error="no beat to loop on: the piece has no strong onsets to jump between")

        # Render: play to b, carry on from a — each seam an equal-power crossfade.
        fade = int(crossfade * rate)
        pieces: list = []
        cursor = 0
        for a, b, _ in jumps:
            end = int(b * rate)
            pieces.append(audio[cursor:min(len(audio), end + fade)])
            cursor = int(a * rate)
        pieces.append(audio[cursor:])
        result = pieces[0]
        for piece in pieces[1:]:
            if fade and len(result) >= fade and len(piece) >= fade:
                t = np.linspace(0, np.pi / 2, fade)[:, None]
                seam = result[-fade:] * np.cos(t) + piece[:fade] * np.sin(t)
                result = np.concatenate([result[:-fade], seam, piece[fade:]])
            else:
                result = np.concatenate([result, piece])

        natural = len(result) / rate
        if exact or natural > target + 2.5:
            keep = int(target * rate)
            result = result[:keep]
            if len(result) < keep:                      # a little short: silence to the frame
                result = np.concatenate([result, np.zeros((keep - len(result), result.shape[1]))])
            ramp = min(len(result), int(float(inputs.get("fade_out_seconds") or 2.0) * rate))
            if ramp > 0 and natural > target + 0.05:
                result[-ramp:] *= np.linspace(1, 0, ramp)[:, None]

        out.parent.mkdir(parents=True, exist_ok=True)
        sf.write(str(out), result, rate, subtype="PCM_16")
        seconds = len(result) / rate
        data = {
            "output": str(out), "original_seconds": round(length, 2), "seconds": round(seconds, 2),
            "target_seconds": target,
            "seams": [{"plays_to": round(b, 2), "back_to": round(a, 2), "adds_seconds": round(b - a, 2),
                       "match": round(score, 3)} for a, b, score in jumps],
            "ending": "cut with a fade" if (exact or natural > target + 2.5) and natural > target + 0.05 else "its own",
        }
        if not jumps and length >= target - 0.25:
            data["note"] = "already long enough" + (": cut to the target" if exact else "; pass exact: true to cut it")
        return ToolResult(success=True, data=data, artifacts=[str(out)], cost_usd=0.0,
                          duration_seconds=round(time.time() - started, 2))
