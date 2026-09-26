"""MiniMax Music 3 on the box's own ComfyUI: a score from a written brief,
instrumental or with lyrics, stereo, up to five minutes.

It is slow and good. Its text stage writes about one token every 2.7 s on the
box — a 24 s piece took 29 minutes, 45 s about 50 — and the first score it made
for a film was called "非常的惊艳" by the person who heard it. Plan for it: ask
for the music early and do other work while it runs.

The brief works best in MiniMax's own structure:
    Global Metadata: genre, tempo (BPM), key, instruments, mood, the arc, the room.
    Vocal Details: "Instrumental. No vocals." or the voice for the lyrics.
    Arrangement: what enters when, the climax, how it ends.
"""

from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from tools._box import node, seed as pick_seed
from tools._comfyui.client import ComfyUIClient, ComfyUIError
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

_DIT = "minimax_music3_dit_fp16.safetensors"
_ENCODER = "minimax_music3_text_encoder_pruned_int8_convrot.safetensors"
_VAE = "minimax_music3_dav.safetensors"
_INSTRUMENTAL = "[intro]\n\n[instrumental]\n\n[outro]"


class MiniMaxMusic(BaseTool):
    name = "minimax_music"
    version = "0.1.0"
    tier = ToolTier.GENERATE
    capability = "music_generation"
    provider = "minimax_music3_local"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.SEEDED
    runtime = ToolRuntime.LOCAL_GPU
    agent_skills = ["minimax-h3-local", "comfyui"]

    install_instructions = (
        "Runs on a ComfyUI server that has MiniMax Music 3 (DiT fp16, the int8 text encoder and the DAV). "
        "Set COMFYUI_SERVER_URL (or COMFYUI_MUSIC_SERVER_URL)."
    )
    capabilities = ["text_to_music", "instrumental", "songs_with_lyrics"]
    supports = {"seed": True, "lyrics": True, "max_duration_seconds": 300, "offline": True}
    best_for = [
        "a cinematic score written for this film (structured brief: metadata, vocals, arrangement)",
        "free local music with a quality people notice",
    ]
    not_good_for = ["anything that has to be ready in minutes (about 70 s of compute per second of music)"]
    quality_score = 0.92
    latency_p50_seconds = 1800

    input_schema = {
        "type": "object",
        "required": ["prompt"],
        "properties": {
            "prompt": {"type": "string", "description": (
                "The brief, in English. Best as 'Global Metadata: … / Vocal Details: … / Arrangement: …'; a plain "
                "description is wrapped as an instrumental piece that builds and fades.")},
            "lyrics": {"type": "string", "description": "Lyrics with [verse]/[chorus] tags; omit for an instrumental."},
            "duration_seconds": {"type": "number", "default": 30.0, "description": "10–300 seconds"},
            "seed": {"type": "integer", "description": "Random if omitted"},
            "output_path": {"type": "string", "description": "Where to save the audio (.wav converted with ffmpeg, else .flac)"},
            "timeout_seconds": {"type": "integer", "default": 10800},
            "resume_prompt_id": {"type": "string", "description": "Resume waiting on a job after a timeout"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=2, ram_mb=20000, vram_mb=20000, disk_mb=50, network_required=False)
    retry_policy = RetryPolicy(max_retries=0)
    idempotency_key_fields = ["prompt", "lyrics", "duration_seconds", "seed"]
    side_effects = ["writes an audio file to output_path"]
    user_visible_verification = ["Listen: it fits the film's time and place, the build lands where the picture does"]

    def __init__(self) -> None:
        self._client = ComfyUIClient(capability="music")

    def get_status(self) -> ToolStatus:
        if not self._client.is_available():
            return ToolStatus.UNAVAILABLE
        _, missing = self._client.check_models([_DIT, _ENCODER, _VAE])
        return ToolStatus.DEGRADED if missing else ToolStatus.AVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def estimate_runtime(self, inputs: dict[str, Any]) -> float:
        return 72.0 * float(inputs.get("duration_seconds", 30.0))

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        if not self._client.is_available():
            return ToolResult(success=False, error=self._client.unavailable_reason())
        start = time.time()
        seed = pick_seed(inputs.get("seed"))
        seconds = min(300.0, max(10.0, float(inputs.get("duration_seconds", 30.0))))
        brief = inputs["prompt"].strip()
        lyrics = (inputs.get("lyrics") or "").strip()
        if "Global Metadata" not in brief:
            brief = (f"Global Metadata: {brief}\n\n"
                     + ("Vocal Details: Sung lyrics.\n\n" if lyrics else "Vocal Details: Instrumental. No vocals, no choir words.\n\n")
                     + "Arrangement: Quiet opening, a gentle build in the middle, a peaceful ending that fades out.")
        wanted = Path(inputs.get("output_path") or f"minimax_music_{seed}.wav")
        flac = wanted.with_suffix(".flac")
        graph = {
            "1": node("UNETLoader", {"unet_name": _DIT, "weight_dtype": "default"}),
            "2": node("CLIPLoader", {"clip_name": _ENCODER, "type": "minimax", "device": "default"}),
            "3": node("VAELoader", {"vae_name": _VAE}),
            "4": node("MiniMaxMusic3TextEncode", {"clip": ["2", 0], "caption": brief, "lyrics": lyrics or _INSTRUMENTAL,
                                                  "seed": seed, "max_duration": seconds + 2, "cfg_scale": 1.7, "top_k": 50}),
            "5": node("ConditioningZeroOut", {"conditioning": ["4", 0]}),
            "6": node("EmptyMiniMaxMusic3LatentAudio", {"seconds": ["4", 1], "batch_size": 1}),
            "7": node("KSampler", {"model": ["1", 0], "seed": seed, "steps": 30, "cfg": 1.7, "sampler_name": "euler",
                                   "scheduler": "simple", "positive": ["4", 0], "negative": ["5", 0],
                                   "latent_image": ["6", 0], "denoise": 1.0}),
            "8": node("VAEDecodeAudio", {"samples": ["7", 0], "vae": ["3", 0]}),
            "9": node("SaveAudioAdvanced", {"audio": ["8", 0], "filename_prefix": f"audio/openmontage-{wanted.stem}",
                                            "format": "flac"}),
        }
        try:
            paths = self._client.generate(graph, output_node="9", dest=flac,
                                          timeout=int(inputs.get("timeout_seconds", 10800)),
                                          resume_prompt_id=inputs.get("resume_prompt_id"))
        except ComfyUIError as exc:
            return ToolResult(success=False, data={"prompt_id": exc.prompt_id}, error=str(exc))
        except Exception as exc:
            return ToolResult(success=False, error=f"MiniMax Music 3 on the box failed: {exc}")
        output = paths[0]
        if wanted.suffix.lower() != ".flac" and shutil.which("ffmpeg"):
            done = subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(output), str(wanted)])
            if done.returncode == 0:
                output = wanted
        return ToolResult(
            success=True,
            data={"provider": self.provider, "model": "minimax-music-3", "prompt": brief, "lyrics": lyrics,
                  "duration_seconds": seconds, "output": str(output)},
            artifacts=[str(output)], cost_usd=0.0, duration_seconds=round(time.time() - start, 2),
            seed=seed, model="minimax-music-3",
        )
