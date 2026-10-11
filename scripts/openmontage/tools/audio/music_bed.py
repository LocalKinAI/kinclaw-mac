"""A score laid under a narrated film, with the mix baked in: one WAV to put at volume 1.0.

A generated score has its own shape — MiniMax Music 3 builds, peaks and fades where it likes,
and it rarely knows where the film's end card is. Played straight under faith.localkin.ai's
timeline film, the score had faded out by the time the title came up and the last four seconds
sat in near-silence. So the bed is fitted to the film:

  · slowed or quickened (pitch kept, ffmpeg atempo) so the score's warmest moment — found in its
    loudness curve, or given as `peak_at_seconds` — lands just after the last spoken word;
  · kept under the voice (`base_gain`, ≈ −18 dB), lifted in the holds after lines that should
    land (`hold_lines`: a quote, a turn) and risen for the end card (`end_gain`);
  · faded out with the picture.

Read the voice from box_narration's narration.json (its lines' starts, clips and last words) —
or give `voice_end_seconds` and `duration_seconds` directly for a film narrated some other way.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import time
import wave
from pathlib import Path
from typing import Any

import numpy as np

from tools.base_tool import (
    BaseTool,
    Determinism,
    ExecutionMode,
    ResourceProfile,
    RetryPolicy,
    ToolResult,
    ToolRuntime,
    ToolStability,
    ToolStatus,
    ToolTier,
)


# the agent's shell has Homebrew on PATH; a bare ssh shell does not
FFMPEG = shutil.which("ffmpeg") or next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg")
                                        if Path(p).exists()), None)


def _atempo_chain(speed: float) -> str:
    """ffmpeg's atempo takes 0.5–2.0 per stage."""
    parts = []
    while speed < 0.5:
        parts.append("atempo=0.5"); speed /= 0.5
    while speed > 2.0:
        parts.append("atempo=2.0"); speed /= 2.0
    parts.append(f"atempo={speed:.5f}")
    return ",".join(parts)


def _read(path: Path) -> tuple[np.ndarray, int, int]:
    with wave.open(str(path)) as w:
        sr, ch = w.getframerate(), w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(np.float32)
    return x, sr, ch


def warmest(x: np.ndarray, sr: int, window: float = 6.0, after: float = 0.45) -> float:
    """Start of the loudest `window` seconds in the back part of the piece (its climax)."""
    mono = x.mean(1) / 32768.0
    step = int(sr * 0.5)
    energy = np.sqrt(np.convolve(mono ** 2, np.ones(step) / step, "same")[::step] + 1e-12)
    w = max(1, int(window / 0.5))
    smooth = np.convolve(energy, np.ones(w) / w, "valid")
    first = int(len(smooth) * after)
    return (first + int(np.argmax(smooth[first:]))) * 0.5 if len(smooth) > first else 0.0


class MusicBed(BaseTool):
    name = "music_bed"
    version = "0.1.0"
    tier = ToolTier.CORE
    capability = "audio_processing"
    provider = "ffmpeg_numpy"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.DETERMINISTIC
    runtime = ToolRuntime.LOCAL
    agent_skills = ["narrated-motion-film", "music"]
    dependencies = ["cmd:ffmpeg", "python:numpy"]

    install_instructions = "ffmpeg on PATH and numpy in the venv."
    capabilities = ["music_fitting", "ducking", "swell", "end_card_rise"]
    supports = {"offline": True}
    best_for = ["fitting a generated score under a narrated film: peak on the end card, lifts where lines land"]
    not_good_for = ["beat-cut edits (cut the picture to the music instead)", "songs with vocals under narration"]
    quality_score = 0.85
    latency_p50_seconds = 15

    input_schema = {
        "type": "object",
        "required": ["music_path", "output_path"],
        "properties": {
            "music_path": {"type": "string"},
            "output_path": {"type": "string", "description": ".wav"},
            "narration_json": {"type": "string", "description": "box_narration's narration.json — gives the film's length, where the voice is, and the last word"},
            "duration_seconds": {"type": "number", "description": "Film length, without narration_json"},
            "voice_end_seconds": {"type": "number", "description": "Film time of the last spoken word, without narration_json"},
            "hold_lines": {"type": "array", "items": {"type": "integer"}, "description": "1-based lines whose hold after them should lift (a quote that lands)"},
            "peak_at_seconds": {"type": "number", "description": "Where in the score its climax is; found from its loudness if omitted"},
            "land_peak": {"type": "boolean", "default": True, "description": "Change the score's speed so its climax arrives just after the last word"},
            "max_speed_change": {"type": "number", "default": 0.18, "description": "Largest tempo change allowed (0.18 = ±18 %)"},
            "base_gain": {"type": "number", "default": 0.13},
            "hold_gain": {"type": "number", "default": 0.22},
            "end_gain": {"type": "number", "default": 0.42},
            "fade_out_seconds": {"type": "number", "default": 1.2},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=1, ram_mb=800, vram_mb=0, disk_mb=100, network_required=False)
    retry_policy = RetryPolicy(max_retries=0, retryable_errors=[])
    idempotency_key_fields = ["music_path", "narration_json", "hold_lines", "peak_at_seconds"]
    side_effects = ["writes the fitted bed to output_path"]
    user_visible_verification = ["Listen to the last seconds: the music carries the end card and fades with the picture"]

    def get_status(self) -> ToolStatus:
        return ToolStatus.AVAILABLE if FFMPEG else ToolStatus.UNAVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        t0 = time.time()
        src, out = Path(inputs["music_path"]), Path(inputs["output_path"])
        holds: list[tuple[float, float, float]] = []  # (voice ends, line ends, next voice starts)
        if inputs.get("narration_json"):
            doc = json.loads(Path(inputs["narration_json"]).read_text())
            lines = doc["lines"]
            total = float(doc["total_s"])
            vo_end = lines[-1]["start_s"] + lines[-1]["voice_end_s"]
            for n in inputs.get("hold_lines") or []:
                if 1 <= n <= len(lines):
                    l = lines[n - 1]
                    nxt = lines[n]["start_s"] + lines[n]["voice_start_s"] if n < len(lines) else l["start_s"] + l["duration_s"]
                    holds.append((l["start_s"] + l["voice_end_s"], l["start_s"] + l["duration_s"], nxt))
        else:
            if not inputs.get("duration_seconds"):
                return ToolResult(success=False, error="give narration_json, or duration_seconds (+ voice_end_seconds)")
            total = float(inputs["duration_seconds"])
            vo_end = float(inputs.get("voice_end_seconds") or total - 4.0)

        x, sr, ch = _read(src) if src.suffix.lower() == ".wav" else (None, 0, 0)
        with tempfile.TemporaryDirectory() as td:
            if x is None:
                wav = Path(td) / "src.wav"
                subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", str(src), str(wav)], check=True)
                x, sr, ch = _read(wav)
            peak = float(inputs["peak_at_seconds"]) if inputs.get("peak_at_seconds") is not None else warmest(x, sr)
            speed = 1.0
            if inputs.get("land_peak", True) and peak > 1.0:
                want = vo_end + 0.4                      # film time the climax should reach
                speed = peak / want                      # < 1 slows the score down
                cap = float(inputs.get("max_speed_change", 0.18))
                speed = min(1 + cap, max(1 - cap, speed))
            # it must also last the whole film
            speed = min(speed, (len(x) / sr) / total)
            fitted = Path(td) / "fitted.wav"
            subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", str(src), "-af", _atempo_chain(speed),
                            "-ar", "48000", "-ac", "2", str(fitted)], check=True)
            y, sr, ch = _read(fitted)

        need = int(round(total * sr))
        if len(y) < need:
            y = np.concatenate([y, np.zeros((need - len(y), ch), np.float32)])
        y = y[:need]
        base, hold, end = (float(inputs.get("base_gain", 0.13)), float(inputs.get("hold_gain", 0.22)),
                           float(inputs.get("end_gain", 0.42)))
        fade = float(inputs.get("fade_out_seconds", 1.2))
        pts = [(0.0, base)]
        for v_end, l_end, nxt in holds:
            pts += [(v_end + 0.1, base), (v_end + 0.7, hold), (l_end - 0.2, hold), (min(nxt, l_end + 0.8), base)]
        pts += [(vo_end + 0.1, base), (vo_end + 1.6, end), (max(vo_end + 1.7, total - fade), end), (total, 0.0)]
        pts.sort()
        gain = np.interp(np.arange(need) / sr, [a for a, _ in pts], [g for _, g in pts]).astype(np.float32)
        z = np.clip(y * gain[:, None], -32768, 32767).astype(np.int16)
        out.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(out), "wb") as w:
            w.setnchannels(ch); w.setsampwidth(2); w.setframerate(sr); w.writeframes(z.tobytes())
        return ToolResult(success=True, artifacts=[str(out)], duration_seconds=round(time.time() - t0, 2),
                          data={"output": str(out), "duration_s": round(total, 3), "speed": round(speed, 4),
                                "tempo_change_pct": round((speed - 1) * 100, 1), "score_peak_s": round(peak, 2),
                                "peak_in_film_s": round(peak / speed, 2), "last_word_s": round(vo_end, 2),
                                "holds": len(holds), "volume_to_use": 1.0})
