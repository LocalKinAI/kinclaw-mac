"""The box's own voices — Qwen3-TTS behind localkin-service-audio — as an OpenMontage TTS provider.

Two services on the box's loopback:
  :8102  VoiceDesign (1.7B): a voice made from a description, `instruct` —
         "温柔清澈的中年女声，像在烛光下读一封旧信，语速缓慢，平静而有温度".
         Every call designs the voice anew: two calls are two different people. For a
         narration longer than one line use `box_narration`, which reads the whole script
         in one take and cuts it — one narrator from the first line to the last.
  :8101  preset voices (0.6B): vivian, serena, uncle_fu, … — the same person every call.
  :8103  a voice cloned from a recording (1.7B Base): `reference_audio`, a few seconds of the voice, and
         `reference_text`, what it says — that person, in any of its languages (2026-10-04).

Chinese is what these voices are best at; English works.
"""

from __future__ import annotations

import json
import os
import time
import urllib.request
import wave
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
    ToolStatus,
    ToolTier,
)

DESIGN_URL = os.environ.get("BOX_TTS_DESIGN_URL", "http://127.0.0.1:8102")
PRESET_URL = os.environ.get("BOX_TTS_PRESET_URL", "http://127.0.0.1:8101")
CLONE_URL = os.environ.get("BOX_TTS_CLONE_URL", "http://127.0.0.1:8103")


def synthesize(text: str, *, instruct: str | None = None, voice: str | None = None, preset: bool = False,
               language: str = "Chinese", speed: float = 1.0, timeout: int = 900,
               reference_audio: str | None = None, reference_text: str | None = None) -> bytes:
    """One call to the box: WAV bytes back. `reference_audio` speaks in that recording's voice
    (8103); `preset` in `voice` (8101); otherwise a voice is designed from `instruct` (8102)."""
    body: dict[str, Any] = {"text": text, "language": language, "speed": speed}
    if reference_audio:
        body["reference_audio"] = reference_audio
        if reference_text:
            body["reference_text"] = reference_text
        base = CLONE_URL
    elif preset:
        if voice:
            body["speaker"] = voice
        base = PRESET_URL
    else:
        body["instruct"] = instruct or "温和清晰的普通话旁白，语速适中"
        base = DESIGN_URL
    request = urllib.request.Request(f"{base}/synthesize", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
    return urllib.request.urlopen(request, timeout=timeout).read()


def wav_seconds(path: str | Path) -> float:
    with wave.open(str(path)) as w:
        return w.getnframes() / w.getframerate()


def presets() -> list[str]:
    """The ids 8101 speaks in (vivian, serena, uncle_fu, …)."""
    try:
        data = json.load(urllib.request.urlopen(f"{PRESET_URL}/voices", timeout=5))
        return [v["id"] for v in data.get("voices", [])]
    except Exception:
        return []


def up(url: str) -> bool:
    try:
        return urllib.request.urlopen(f"{url}/health", timeout=4).status == 200
    except Exception:
        return False


class BoxTTS(BaseTool):
    name = "box_tts"
    version = "0.1.0"
    tier = ToolTier.VOICE
    capability = "tts"
    provider = "qwen3_tts_box"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.STOCHASTIC
    runtime = ToolRuntime.LOCAL_GPU
    agent_skills = ["narrated-motion-film", "text-to-speech"]

    install_instructions = (
        "The box's localkin-service-audio: `kin audio serve qwen3-tts:1.7b-voicedesign` on :8102 and the preset "
        "voices on :8101 (KinClaw's 盒子 panel starts both). Override with BOX_TTS_DESIGN_URL / BOX_TTS_PRESET_URL."
    )
    capabilities = ["text_to_speech", "voice_design", "offline_generation", "chinese"]
    supports = {"voice_cloning": True, "voice_design": True, "multilingual": True, "offline": True,
                "native_audio": True}
    best_for = [
        "Chinese narration in a voice described in words (8102), free and on the box",
        "a steady preset voice for short lines (8101)",
    ]
    not_good_for = [
        "a long narration read line by line on 8102 — every call is a different voice; use box_narration",
    ]
    quality_score = 0.9
    latency_p50_seconds = 8

    input_schema = {
        "type": "object",
        "required": ["text"],
        "properties": {
            "text": {"type": "string"},
            "instruct": {"type": "string", "description": "8102: the voice in words, in Chinese works best"},
            "voice": {"type": "string", "description": "8101: a preset id (vivian, serena, uncle_fu, …)"},
            "preset": {"type": "boolean", "default": False, "description": "true: speak in `voice` on 8101"},
            "reference_audio": {"type": "string", "description": "8103: a recording of the voice to speak in (a path on the box), 3–12 s"},
            "reference_text": {"type": "string", "description": "8103: what the recording says — the clone is far closer with it"},
            "language": {"type": "string", "default": "Chinese"},
            "speed": {"type": "number", "default": 1.0},
            "output_path": {"type": "string"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=1, ram_mb=256, vram_mb=0, disk_mb=50, network_required=False)
    retry_policy = RetryPolicy(max_retries=1, retryable_errors=[])
    idempotency_key_fields = ["text", "instruct", "voice", "preset", "speed"]
    side_effects = ["writes a WAV file to output_path"]
    user_visible_verification = ["Listen: names, numbers and 多音字 read right; the voice is the one described"]

    def get_status(self) -> ToolStatus:
        design, preset = up(DESIGN_URL), up(PRESET_URL)
        if design and preset:
            return ToolStatus.AVAILABLE
        return ToolStatus.DEGRADED if (design or preset) else ToolStatus.UNAVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        start = time.time()
        text = (inputs.get("text") or "").strip()
        if not text:
            return ToolResult(success=False, error="text is empty")
        out = Path(inputs.get("output_path") or f"box_tts_{int(start)}.wav")
        out.parent.mkdir(parents=True, exist_ok=True)
        instruct = (inputs.get("instruct") or "").strip()
        reference = (inputs.get("reference_audio") or "").strip()
        if reference:
            try:
                data = synthesize(text, reference_audio=reference, reference_text=inputs.get("reference_text"),
                                  language=inputs.get("language", "Chinese"), speed=float(inputs.get("speed", 1.0)))
            except Exception as exc:
                return ToolResult(success=False, error=f"the box's voice cloning ({CLONE_URL}) failed: {exc}")
            out.write_bytes(data)
            return ToolResult(success=True, artifacts=[str(out)], duration_seconds=round(time.time() - start, 2),
                              model="qwen3-tts-1.7b-base",
                              data={"provider": self.provider, "output": str(out), "audio_seconds": round(wav_seconds(out), 2),
                                    "voice": f"cloned from {reference}", "service": "8103 voice clone"})
        # Without a description the voice is a preset: 8102 with no brief would be a new stranger every
        # call — the trap when tts_selector sends a film's lines here one at a time.
        preset = bool(inputs.get("preset")) or not instruct
        voice = inputs.get("voice") if preset else None
        if preset and voice and voice not in presets():
            voice = None  # another provider's voice id, passed on by tts_selector: the box's default preset
        note = None if preset else "8102 makes a new voice every call — for more than one line use box_narration"
        try:
            data = synthesize(text, instruct=instruct or None, voice=voice, preset=preset,
                              language=inputs.get("language", "Chinese"), speed=float(inputs.get("speed", 1.0)))
        except Exception as exc:
            return ToolResult(success=False, error=f"the box's TTS ({PRESET_URL if preset else DESIGN_URL}) failed: {exc}")
        out.write_bytes(data)
        seconds = round(wav_seconds(out), 2)
        return ToolResult(success=True, artifacts=[str(out)], duration_seconds=round(time.time() - start, 2),
                          model="qwen3-tts-0.6b" if preset else "qwen3-tts-1.7b-voicedesign",
                          data={"provider": self.provider, "output": str(out), "audio_seconds": seconds,
                                "voice": (voice or "default preset") if preset else instruct,
                                "service": "8101 preset" if preset else "8102 voice design", "note": note})
