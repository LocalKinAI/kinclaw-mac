"""Video translation the way HeyGen sells it, made on the LocalKin box: the same person saying it in
another language, in their own voice, their lips moving to the new words — 「视频翻译 + 对口型」
(2026-10-04).

Two calls:
  1. {video_path} → what is said, line by line with its times (the box's Qwen3-ASR), to translate.
     The translating is the agent's: each line's meaning, about as long as the original.
  2. {video_path, segments: [{start, end, text}] in the target language, language} → the dubbed video:
     - a reference of the speaker's voice is cut from the video — the clearest 4–12 s, with what it
       says (or `reference`: {start, end, text}) — and every line is spoken in that voice by
       Qwen3-TTS 1.7B Base (:8103, localkin-service-audio, voice cloning);
     - each line is fitted to its place: sped up to 1.35× at most when it runs into the next one,
       and when it is still too long the next line waits for it (the video's last frames repeat
       if the new speech outlasts them);
     - the new speech replaces the soundtrack (the old one carries the old voice; lay music under
       it with music_bed), and Ditto draws the face again over every frame, speaking it — crisp lips
       and teeth, the head as the video moves it. MuseTalk (`lip_sync_model: "musetalk"`) redraws
       only the mouth and blurs it on a small or turned face: on her 640×640 口播 the lips came out
       smeared where Ditto's were as sharp as the original (2026-10-04, 「这个不行，刚才那个好」);
     - an .srt of the new lines at their new times comes with it; `burn_subtitles` draws them on.

Measured on the box: a 10 s Chinese 口播 to English in about a minute and a half (Ditto: 25 frames a
second of video at about 6.5 a second, so a minute of video is four of work).
"""

from __future__ import annotations

import json
import os
import time
import urllib.request
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

CLONE_URL = os.environ.get("BOX_TTS_CLONE_URL", "http://127.0.0.1:8103")
FFMPEG = os.environ.get("FFMPEG", "/opt/homebrew/bin/ffmpeg")
FFPROBE = os.environ.get("FFPROBE", "/opt/homebrew/bin/ffprobe")
DITTO = Path(os.environ.get("DITTO_PATH", os.path.expanduser("~/kin-avatar/ditto/ditto-talkinghead")))
RATE = 24000
MOST_TEMPO = 1.35


def up(url: str) -> bool:
    try:
        return urllib.request.urlopen(f"{url}/health", timeout=4).status == 200
    except Exception:
        return False


def clone(text: str, reference: Path, reference_text: str, language: str, timeout: int = 600) -> bytes:
    body = {"text": text, "language": language, "speed": 1.0,
            "reference_audio": str(reference), "reference_text": reference_text}
    request = urllib.request.Request(f"{CLONE_URL}/synthesize", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(request, timeout=timeout).read()


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path)) as w:
        frames = w.readframes(w.getnframes())
        rate, channels, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
    if width != 2:
        raise ValueError(f"{path}: {8 * width}-bit WAV, 16-bit expected")
    audio = np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768
    if channels > 1:
        audio = audio.reshape(-1, channels).mean(axis=1)
    if rate != RATE:
        audio = np.interp(np.arange(0, len(audio), rate / RATE), np.arange(len(audio)), audio).astype(np.float32)
    return audio


def write_wav(audio: np.ndarray, path: Path) -> None:
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def srt_time(seconds: float) -> str:
    ms = int(round(seconds * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def pick_reference(segments: list[dict]) -> dict | None:
    """The span of the speaker's voice to clone: neighbouring lines joined while the gap is short,
    the one closest to 8 s between 3 and 12, else the longest."""
    spans: list[dict] = []
    for i, first in enumerate(segments):
        span = {"start": first["start"], "end": first["end"], "text": first["text"]}
        spans.append(dict(span))
        for nxt in segments[i + 1:]:
            if nxt["start"] - span["end"] > 0.6 or nxt["end"] - span["start"] > 12:
                break
            span = {"start": span["start"], "end": nxt["end"], "text": span["text"] + nxt["text"]}
            spans.append(dict(span))
    if not spans:
        return None
    fitting = [s for s in spans if 3 <= s["end"] - s["start"] <= 12]
    if fitting:
        return min(fitting, key=lambda s: abs(s["end"] - s["start"] - 8))
    return max(spans, key=lambda s: s["end"] - s["start"])


class VideoTranslate(BaseTool):
    name = "video_translate"
    version = "0.1.0"
    tier = ToolTier.VOICE
    capability = "dubbing"
    provider = "localkin_box"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.STOCHASTIC
    runtime = ToolRuntime.LOCAL_GPU
    agent_skills = ["localkin-pipelines"]

    install_instructions = (
        "The box's voice-cloning service: `kin audio serve qwen3-tts:1.7b-base --port 8103` in "
        "~/localkin-service-audio (KinClaw's 盒子 panel, 克隆声音), the box's Qwen3-ASR (:8100) and MuseTalk "
        "for lip_sync. Override the service with BOX_TTS_CLONE_URL."
    )
    capabilities = ["video_translation", "voice_cloning", "lip_sync", "dubbing", "offline_generation"]
    supports = {"voice_cloning": True, "lip_sync": True, "multilingual": True, "offline": True}
    best_for = [
        "a talking-head video in another language: the speaker's own voice, lips moved to the new words",
        "localization-dub in one step once the lines are translated",
    ]
    not_good_for = [
        "several people speaking — the voice is cloned from one (give `reference` to choose whose)",
        "keeping music under the speech: the old soundtrack goes; lay music back with music_bed",
    ]
    quality_score = 0.85
    latency_p50_seconds = 90

    input_schema = {
        "type": "object",
        "required": ["video_path"],
        "properties": {
            "video_path": {"type": "string", "description": "The video, one person speaking, face visible."},
            "segments": {
                "type": "array",
                "description": (
                    "The lines translated, each with the start and end of the line it replaces (from the first "
                    "call). Omit to get the lines to translate."
                ),
                "items": {"type": "object", "required": ["start", "end", "text"],
                          "properties": {"start": {"type": "number"}, "end": {"type": "number"},
                                         "text": {"type": "string"}}},
            },
            "language": {"type": "string", "description": "The new language, ISO code: en, zh, ja, ko, fr, de, es…"},
            "source_language": {"type": "string", "description": "The video's language, ISO code (default: detected)."},
            "reference": {
                "type": "object",
                "description": "The span to clone the voice from, {start, end, text} — default: the clearest 4–12 s.",
            },
            "burn_subtitles": {"type": "boolean", "default": False},
            "lip_sync": {"type": "boolean", "default": True, "description": "false: only the new voice, the picture as it was."},
            "lip_sync_model": {"type": "string", "enum": ["ditto", "musetalk"], "default": "ditto",
                               "description": "ditto: the whole face drawn again speaking the new words, sharp (default); "
                                              "musetalk: only the mouth — blurs a small or turned face"},
            "output_path": {"type": "string"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=2, ram_mb=4096, vram_mb=0, disk_mb=500, network_required=False)
    retry_policy = RetryPolicy(max_retries=0, retryable_errors=[])
    idempotency_key_fields = ["video_path", "segments", "language", "reference", "burn_subtitles", "lip_sync"]
    side_effects = ["writes the dubbed video, its .srt, the new speech and the voice reference beside output_path"]
    user_visible_verification = [
        "Watch: the voice is the speaker's, the words are the translation, the lips move with them",
    ]

    def get_status(self) -> ToolStatus:
        return ToolStatus.AVAILABLE if up(CLONE_URL) else ToolStatus.UNAVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def _transcribe(self, video: Path, language: str | None, folder: Path) -> dict:
        from tools.analysis.transcriber import Transcriber
        result = Transcriber().execute({"input_path": str(video), "engine": "auto", "language": language,
                                        "output_dir": str(folder)})
        if not result.success:
            raise RuntimeError(f"transcriber: {result.error}")
        return result.data

    def _seconds(self, path: Path) -> float:
        out = self.run_command([FFPROBE, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)])
        return float(out.stdout.strip())

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        try:
            return self._execute(inputs)
        except Exception as exc:  # an ffmpeg or a service failing mid-way: said, not raised
            detail = getattr(exc, "stderr", "") or ""
            return ToolResult(success=False, error=f"{type(exc).__name__}: {exc} {str(detail)[-800:]}".strip())

    def _execute(self, inputs: dict[str, Any]) -> ToolResult:
        began = time.time()
        video = Path(inputs["video_path"]).expanduser()
        if not video.exists():
            return ToolResult(success=False, error=f"no video at {video}")
        out = Path(inputs.get("output_path") or video.with_name(f"{video.stem}_{inputs.get('language') or 'dub'}.mp4"))
        out.parent.mkdir(parents=True, exist_ok=True)
        work = out.with_suffix("")
        work = work.parent / f"{work.name}_work"
        work.mkdir(parents=True, exist_ok=True)
        try:
            source = self._transcribe(video, inputs.get("source_language"), work)
        except Exception as exc:
            return ToolResult(success=False, error=str(exc))
        lines = [{"start": round(s["start"], 2), "end": round(s["end"], 2), "text": s["text"]}
                 for s in source.get("segments", []) if s.get("text", "").strip()]
        segments = inputs.get("segments")
        if not segments:
            return ToolResult(success=True, duration_seconds=round(time.time() - began, 2), data={
                "step": "translate these lines, then call again with segments (same start/end, the text translated) and language",
                "language": source.get("language"), "duration_seconds": source.get("duration_seconds"),
                "segments": lines})
        language = (inputs.get("language") or "en").strip()
        if not up(CLONE_URL):
            return ToolResult(success=False, error=f"the box's voice-cloning service ({CLONE_URL}) is not up: "
                                                   "kin audio serve qwen3-tts:1.7b-base --port 8103")

        # The voice: the span chosen, cut from the video at the service's rate.
        reference = inputs.get("reference") or pick_reference(lines)
        if not reference:
            return ToolResult(success=False, error="no speech found in the video to clone the voice from")
        ref_wav = work / "voice_reference.wav"
        self.run_command([FFMPEG, "-v", "error", "-y", "-ss", f"{max(0, reference['start'] - 0.05):.2f}",
                          "-to", f"{reference['end'] + 0.12:.2f}", "-i", str(video), "-vn", "-ac", "1", "-ar", str(RATE),
                          "-c:a", "pcm_s16le", str(ref_wav)])

        # Every line in that voice, fitted to its place.
        length = self._seconds(video)
        ordered = sorted(segments, key=lambda s: float(s["start"]))
        placed: list[dict] = []
        cursor = 0.0
        track = np.zeros(int(length * RATE) + 1, dtype=np.float32)
        for i, seg in enumerate(ordered):
            text = str(seg["text"]).strip()
            if not text:
                continue
            raw = work / f"line_{i + 1:02d}.wav"
            try:
                raw.write_bytes(clone(text, ref_wav, reference["text"], language))
            except Exception as exc:
                return ToolResult(success=False, error=f"line {i + 1} could not be spoken ({CLONE_URL}): {exc}")
            spoken = len(read_wav(raw)) / RATE
            start = max(float(seg["start"]), cursor)
            room = (float(ordered[i + 1]["start"]) if i + 1 < len(ordered) else max(length, float(seg["end"]))) - start
            tempo = min(MOST_TEMPO, spoken / room) if room > 0 and spoken > room else 1.0
            fitted = raw
            if tempo > 1.0:
                fitted = work / f"line_{i + 1:02d}_fit.wav"
                self.run_command([FFMPEG, "-v", "error", "-y", "-i", str(raw), "-filter:a", f"atempo={tempo:.3f}",
                                  "-ar", str(RATE), "-ac", "1", "-c:a", "pcm_s16le", str(fitted)])
            audio = read_wav(fitted)
            a = int(start * RATE)
            if a + len(audio) > len(track):
                track = np.concatenate([track, np.zeros(a + len(audio) - len(track), dtype=np.float32)])
            track[a:a + len(audio)] += audio
            cursor = start + len(audio) / RATE + 0.08
            placed.append({"start": round(start, 2), "end": round(start + len(audio) / RATE, 2), "text": text,
                           "spoken_seconds": round(spoken, 2), "tempo": round(tempo, 3),
                           "late_by": round(start - float(seg["start"]), 2)})
        if not placed:
            return ToolResult(success=False, error="every segment was empty")
        speech = work / "speech.wav"
        write_wav(track, speech)
        srt = out.with_suffix(".srt")
        srt.write_text("\n".join(f"{n}\n{srt_time(p['start'])} --> {srt_time(p['end'])}\n{p['text']}\n"
                                 for n, p in enumerate(placed, 1)), encoding="utf-8")

        # The lips, then the words on screen if asked.
        lipped = work / "lipsync.mp4"
        ditto = (inputs.get("lip_sync_model") or "ditto") == "ditto" and (DITTO / "kin_ditto_talk.py").exists()
        if inputs.get("lip_sync", True) and ditto:
            # The video itself as Ditto's source: each frame kept, the face in it speaking the new
            # speech; frames repeat if the speech outlasts them. 25 fps out.
            self.run_command([str(DITTO / ".venv312" / "bin" / "python"), "kin_ditto_talk.py",
                              "./checkpoints/ditto_cfg/v0.4_hubert_cfg_pytorch.pkl", str(video), str(speech), str(lipped)],
                             cwd=DITTO, timeout=3600)
            if not lipped.exists():
                return ToolResult(success=False, error="Ditto wrote no video", data={"speech": str(speech), "srt": str(srt)})
        elif inputs.get("lip_sync", True):
            from tools.avatar.lip_sync import LipSync
            synced = LipSync().execute({"video_path": str(video), "audio_path": str(speech), "model": "musetalk",
                                        "output_path": str(lipped)})
            if not synced.success:
                return ToolResult(success=False, error=f"lip_sync: {synced.error}",
                                  data={"speech": str(speech), "srt": str(srt), "lines": placed})
        else:
            self.run_command([FFMPEG, "-v", "error", "-y", "-stream_loop", "-1", "-i", str(video), "-i", str(speech),
                              "-map", "0:v", "-map", "1:a", "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                              "-c:a", "aac", "-b:a", "192k", str(lipped)])
        final = lipped
        if inputs.get("burn_subtitles"):
            final = work / "subtitled.mp4"
            style = "FontName=PingFang SC,FontSize=13,Outline=1.2,Shadow=0,MarginV=24"
            # Plain "ffmpeg": run_command runs a command that draws text with the box's libass build.
            self.run_command(["ffmpeg", "-v", "error", "-y", "-i", str(lipped),
                              "-vf", f"subtitles={srt}:force_style='{style}'", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                              "-c:a", "copy", str(final)])
        if out.exists():
            out.unlink()
        final.replace(out)
        late = [p for p in placed if p["late_by"] > 0.3]
        return ToolResult(
            success=True,
            artifacts=[str(out), str(srt), str(speech), str(ref_wav)],
            duration_seconds=round(time.time() - began, 2),
            model="qwen3-tts-1.7b-base + " + ("ditto" if ditto else "musetalk"),
            data={"output": str(out), "srt": str(srt), "speech": str(speech), "language": language,
                  "voice_reference": {**reference, "file": str(ref_wav)},
                  "source_language": source.get("language"), "lines": placed,
                  "speech_seconds": round(len(track) / RATE, 2), "video_seconds": round(length, 2),
                  "note": (f"{len(late)} line(s) start later than the original — shorten them for a closer fit"
                           if late else None)},
        )
