"""MiniMax H3 on the box's own ComfyUI — local and free, not the hosted
Partner Node (`minimax_h3_api` in comfyui_video, which bills a Comfy account).

The model on the box is ref2va: video with sound from reference pictures — up
to nine — and a prompt. It keeps faces and clothes from portraits; things and
numbers it keeps only when they are pinned: a picture fixed to a frame of the
output with MiniMaxH3AddGuide. So a shot is filmed from a first frame made
beforehand (qwen_image in edit mode: the set plus the cast portraits), pinned
at frame 0. A shot where nothing may change (twelve baskets) is `hold`: the
same frame pinned at its start, middle and end — pinned only at both ends it
wandered to another slope and came back with fourteen.

Measured on the box (M3 Ultra): a 5.2 s shot at 928×544, 4-step LoRA, about
9–10 minutes including the model load; native stereo sound.
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from tools._box import as_png, filled, node, seed as pick_seed, size_for
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

_MODEL = "minimax_h3_ref2va_pruned_int8_convrot.safetensors"
_ENCODER = "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
_VIDEO_VAE = "minimax_h3_video_vae_fp16.safetensors"
_AUDIO_VAE = "minimax_h3_audio_vae_fp32.safetensors"
_LORA = "minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"


def frames_for(seconds: float) -> int:
    """H3 wants 17k + 5 frames at 24 fps, and at least 124 (about 5.2 s).

    The nearest such count, not the next one up: 5.2 s is 124.8 frames, and
    rounding up made it 141 — a shot asked for at 5.2 s came back at 5.9.
    """
    k = round((seconds * 24 - 5) / 17)
    return max(124, 17 * k + 5)


class H3Video(BaseTool):
    name = "h3_video"
    version = "0.1.0"
    tier = ToolTier.GENERATE
    capability = "video_generation"
    provider = "minimax_h3_local"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.SEEDED
    runtime = ToolRuntime.LOCAL_GPU
    agent_skills = ["minimax-h3-local", "comfyui"]

    install_instructions = (
        "Runs on a ComfyUI server that has MiniMax H3 ref2va (pruned int8), its Qwen3-VL 32B encoder, the video "
        "and audio VAEs and the ref2v 4-step LoRA. Set COMFYUI_SERVER_URL (or COMFYUI_VIDEO_SERVER_URL)."
    )
    capabilities = ["image_to_video", "reference_to_video", "pinned_frames", "native_audio"]
    supports = {"seed": True, "reference_images": 9, "pinned_frames": True, "native_audio": True,
                "offline": True, "text_to_video": False}
    best_for = [
        "story shots with the same people in every shot (cast portraits as references)",
        "a shot that must start exactly on a checked first frame (pinned)",
        "a shot where nothing may change — counted things, a still set with living light (hold)",
        "free local video with native sound, no API key",
    ]
    not_good_for = [
        "text-only prompts with no picture at all (make one with qwen_image first)",
        "fast iteration (about 10 minutes a shot)",
        "shots longer than about 15 seconds",
    ]
    quality_score = 0.9
    latency_p50_seconds = 580

    input_schema = {
        "type": "object",
        "required": ["prompt"],
        "properties": {
            "prompt": {"type": "string", "description": (
                "What happens, in English. H3's own form works best (subject_definitions / summary / "
                "retention_analysis / detailed_description / overall_soundscape / non_diegetic_music), naming the "
                "reference pictures as <Picture 1>, <Picture 2> ... in the order of reference_images.")},
            "operation": {"type": "string", "enum": ["image_to_video", "reference_to_video"], "description": (
                "image_to_video: reference_image_path is the first frame, pinned. reference_to_video: only references.")},
            "reference_image_path": {"type": "string", "description": "The first frame, pinned at frame 0 (a checked picture)."},
            "reference_images": {"type": "array", "items": {"type": "string"}, "description": (
                "Up to 9 reference pictures: cast portraits (faces and clothes are kept), the set. Named <Picture 1>... "
                "in this order. The first frame is added after them when it is not already one of them.")},
            "pin_frames": {"type": "array", "description": "More pictures pinned to frames: [{\"image_path\": ..., \"frame\": 62} or {\"image_path\": ..., \"seconds\": 2.5}]. Negative frames count from the end.",
                           "items": {"type": "object"}},
            "hold": {"type": "boolean", "default": False, "description": (
                "Pin the first frame at the start, middle and end: the shot stays that picture, only light, air and "
                "small things move. For shots where a count or an arrangement must not change.")},
            "duration": {"type": "number", "default": 5.2, "description": "Seconds (at least ~5.2; H3 uses 17k+5 frames at 24 fps)."},
            "aspect_ratio": {"type": "string", "default": "16:9"},
            "megapixels": {"type": "number", "default": 0.5, "description": "0.5 → 928×544 at 16:9; 0.98 is H3's 768p but takes 2–3× as long."},
            "width": {"type": "integer"},
            "height": {"type": "integer"},
            "full_quality": {"type": "boolean", "default": False, "description": "20 steps without the 4-step LoRA: cleaner, ~5× slower."},
            "seed": {"type": "integer", "description": "Random if omitted"},
            "output_path": {"type": "string", "description": "Where to save the MP4 (with sound)"},
            "timeout_seconds": {"type": "integer", "default": 3600},
            "resume_prompt_id": {"type": "string", "description": "Resume waiting on a job after a timeout"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=2, ram_mb=60000, vram_mb=60000, disk_mb=50, network_required=False)
    retry_policy = RetryPolicy(max_retries=0)
    idempotency_key_fields = ["prompt", "reference_image_path", "reference_images", "hold", "duration", "seed"]
    side_effects = ["writes an MP4 with sound to output_path"]
    user_visible_verification = [
        "Look at a frame every second: the people are the cast, the counted things are still the right number, "
        "the shot does not jump to another place half way",
    ]

    def __init__(self) -> None:
        self._client = ComfyUIClient(capability="video")

    def get_status(self) -> ToolStatus:
        if not self._client.is_available():
            return ToolStatus.UNAVAILABLE
        _, missing = self._client.check_models([_MODEL, _ENCODER, _VIDEO_VAE, _AUDIO_VAE, _LORA])
        return ToolStatus.DEGRADED if missing else ToolStatus.AVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def estimate_runtime(self, inputs: dict[str, Any]) -> float:
        base = 580.0 * (frames_for(float(inputs.get("duration", 5.2))) / 124)
        return base * (5 if inputs.get("full_quality") else 1) * max(1.0, float(inputs.get("megapixels", 0.5)) / 0.5) ** 1.5

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        first = inputs.get("reference_image_path")
        references = [str(p) for p in inputs.get("reference_images") or []]
        if not first and not references:
            return ToolResult(success=False, error=(
                "H3 on the box films from pictures (reference-to-video): give reference_images and/or "
                "reference_image_path. Make a first frame with qwen_image first — a set, or a set with the cast "
                "portraits composed in (edit mode)."))
        if not self._client.is_available():
            return ToolResult(success=False, error=self._client.unavailable_reason())

        start = time.time()
        seed = pick_seed(inputs.get("seed"))
        output_path = Path(inputs.get("output_path") or f"h3_{seed}.mp4")
        width, height = size_for(inputs.get("aspect_ratio"), float(inputs.get("megapixels", 0.5)), 32,
                                 inputs.get("width"), inputs.get("height"))
        length = frames_for(float(inputs.get("duration", 5.2)))
        full = bool(inputs.get("full_quality"))
        if first and first not in references:
            references = references + [str(first)]

        # Where the shot is pinned.
        pins: list[tuple[str, int]] = []
        if first and (inputs.get("operation") in (None, "image_to_video") or inputs.get("hold")):
            pins.append((str(first), 0))
            if inputs.get("hold"):
                pins += [(str(first), length // 2), (str(first), -1)]
        for extra in inputs.get("pin_frames") or []:
            frame = extra.get("frame")
            if frame is None and extra.get("seconds") is not None:
                frame = min(length - 1, round(float(extra["seconds"]) * 24))
            if extra.get("image_path") and frame is not None:
                pins.append((str(extra["image_path"]), int(frame)))

        stem = output_path.stem
        model = ["1", 0] if full else ["5", 0]
        graph: dict[str, Any] = {
            "1": node("UNETLoader", {"unet_name": _MODEL, "weight_dtype": "default"}),
            "2": node("CLIPLoader", {"clip_name": _ENCODER, "type": "minimax", "device": "default"}),
            "3": node("VAELoader", {"vae_name": _VIDEO_VAE}),
            "4": node("VAELoader", {"vae_name": _AUDIO_VAE}),
            "5": node("LoraLoaderModelOnly", {"lora_name": _LORA, "strength_model": 1, "model": ["1", 0]}),
            "7": node("RandomNoise", {"noise_seed": seed}),
            "8": node("KSamplerSelect", {"sampler_name": "res_multistep"}),
            "9": node("BasicScheduler", {"scheduler": "simple", "steps": 20 if full else 4, "denoise": 1, "model": model}),
            "12": node("VAEDecode", {"samples": ["11", 0], "vae": ["3", 0]}),
            "13": node("VAEDecodeAudio", {"samples": ["11", 0], "vae": ["4", 0]}),
            "14": node("CreateVideo", {"fps": 24, "bit_depth": 8, "color_space": "sRGB", "codec": "none",
                                       "images": ["12", 0], "audio": ["13", 0]}),
            "15": node("SaveVideo", {"filename_prefix": f"video/openmontage-{stem}", "format": "auto", "codec": "auto",
                                     "format.codec": "auto", "video": ["14", 0]}),
        }
        try:
            reference = {"prompt": inputs["prompt"], "width": width, "height": height, "length": length,
                         "ref_image_size": "match", "clip": ["2", 0], "vae": ["3", 0], "audio_vae": ["4", 0]}
            for i, path in enumerate(references[:9]):
                name = self._client.upload_image(as_png(path), f"om-{stem}-ref{i + 1}.png")
                graph[str(100 + i)] = node("LoadImage", {"image": name})
                reference[f"ref_images.ref_image_{i}"] = [str(100 + i), 0]
            graph["6"] = node("MiniMaxH3ReferenceToVideo", reference)
            conditioning: list[Any] = ["6", 0]
            uploaded: dict[str, str] = {}
            for i, (path, frame) in enumerate(pins):
                if path not in uploaded:
                    sized = filled(path, width, height)
                    uploaded[path] = self._client.upload_image(sized, f"om-{stem}-pin{len(uploaded) + 1}.png")
                    sized.unlink(missing_ok=True)
                graph[str(200 + i)] = node("LoadImage", {"image": uploaded[path]})
                graph[str(300 + i)] = node("MiniMaxH3AddGuide", {
                    "positive": conditioning, "latent": ["6", 1], "frame_idx": frame,
                    "vae": ["3", 0], "audio_vae": ["4", 0], "image": [str(200 + i), 0]})
                conditioning = [str(300 + i), 0]
            graph["10"] = node("BasicGuider", {"model": model, "conditioning": conditioning})
            graph["11"] = node("SamplerCustomAdvanced", {"noise": ["7", 0], "guider": ["10", 0], "sampler": ["8", 0],
                                                         "sigmas": ["9", 0], "latent_image": ["6", 1]})
            paths = self._client.generate(graph, output_node="15", dest=output_path,
                                          timeout=int(inputs.get("timeout_seconds", 3600)),
                                          resume_prompt_id=inputs.get("resume_prompt_id"))
        except ComfyUIError as exc:
            return ToolResult(success=False, data={"prompt_id": exc.prompt_id}, error=str(exc))
        except Exception as exc:
            return ToolResult(success=False, error=f"H3 on the box failed: {exc}")
        return ToolResult(
            success=True,
            data={"provider": self.provider, "model": "minimax-h3-ref2va-int8", "prompt": inputs["prompt"],
                  "width": width, "height": height, "frames": length, "seconds": round(length / 24, 2),
                  "references": references[:9], "pins": [{"image_path": p, "frame": f} for p, f in pins],
                  "steps": 20 if full else 4, "output": str(paths[0]), "has_audio": True},
            artifacts=[str(p) for p in paths], cost_usd=0.0, duration_seconds=round(time.time() - start, 2),
            seed=seed, model="minimax-h3-ref2va-int8",
        )
