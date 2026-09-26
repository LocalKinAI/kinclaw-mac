"""Qwen-Image 2.1 on the box's ComfyUI: pictures from words, or a picture
changed with other pictures to go by (edit mode).

Edit mode is how a shot's first frame is made for H3: the set as image 1, the
cast portraits after it, and the moment described — the people standing in the
place, holding what they hold, before anything moves. Tested on 五饼二鱼: the
boy with five loaves and two fish came out right the first time (141 s).
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from tools._box import as_png, node, seed as pick_seed, size_for
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

_MODELS = [
    "qwen_image_2.1_int8_convrot.safetensors",
    "qwen3vl_8b_int8_convrot.safetensors",
    "qwen_image_2.1_vae_bf16.safetensors",
]

# PrunaAI's distilled 8-step LoRA for Qwen-Image 2.1 (huggingface.co/PrunaAI/Pruna-Qwen-Image-2.1),
# in the box's ComfyUI/models/loras; tested 2026-09-26: 3x faster, pictures as good in the two compared.
_FAST_LORA = "p_qwen_image_2.1_8step_v0.1.safetensors"
_FAST_SIGMAS = "1, 0.9333333333, 0.8571428571, 0.7692307692, 0.6666666667, 0.5454545455, 0.4, 0.2222222222, 0"


class QwenImage(BaseTool):
    name = "qwen_image"
    version = "0.1.0"
    tier = ToolTier.GENERATE
    capability = "image_generation"
    provider = "qwen_image_local"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.SEEDED
    runtime = ToolRuntime.LOCAL_GPU
    agent_skills = ["minimax-h3-local", "comfyui"]

    install_instructions = (
        "Runs on a ComfyUI server that has Qwen-Image 2.1 (int8) with its Qwen3-VL 8B encoder and VAE. "
        "Set COMFYUI_SERVER_URL (or COMFYUI_IMAGE_SERVER_URL)."
    )
    capabilities = ["text_to_image", "image_edit", "multi_image_compose"]
    supports = {"seed": True, "custom_size": True, "reference_images": True, "offline": True}
    best_for = [
        "photoreal film stills and sets, literal to the words (period pieces keep period detail)",
        "the first frame of an H3 shot: a set plus cast portraits composed into one picture",
        "changing a picture to match another (bread like the loaves in image 2)",
        "free local generation on the box",
    ]
    not_good_for = ["exact counts above about ten in one edit (it keeps the old layout)", "text rendering"]
    quality_score = 0.85
    latency_p50_seconds = 100

    input_schema = {
        "type": "object",
        "required": ["prompt"],
        "properties": {
            "prompt": {"type": "string", "description": (
                "What the picture shows, literally, in English. In edit mode say what to change and what to keep, "
                "and refer to the pictures as image 1, image 2 ...")},
            "reference_images": {"type": "array", "items": {"type": "string"}, "description": (
                "Edit mode: local picture paths. The first is the picture changed (its size is kept); "
                "the rest are what to go by — e.g. [set.png, portrait_boy.png, portrait_man.png].")},
            "aspect_ratio": {"type": "string", "default": "16:9", "description": "Text-to-image shape: 16:9, 9:16, 1:1, 4:3 ..."},
            "width": {"type": "integer", "description": "Text-to-image width (with height), else from aspect_ratio at ~1 MP"},
            "height": {"type": "integer"},
            "steps": {"type": "integer", "default": 25, "description": "Only without fast"},
            "fast": {"type": "boolean", "default": True, "description": (
                "8 steps with PrunaAI's distilled LoRA instead of 25: about three times faster (a set ~42 s, "
                "a first frame from two pictures ~37 s on the box), as good in the tests so far. False for the "
                "slow full-quality pass, e.g. a hero frame that came out soft.")},
            "seed": {"type": "integer", "description": "Random if omitted"},
            "output_path": {"type": "string", "description": "Where to save the PNG"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=2, ram_mb=30000, vram_mb=30000, disk_mb=50, network_required=False)
    retry_policy = RetryPolicy(max_retries=1, retryable_errors=["timeout"])
    idempotency_key_fields = ["prompt", "reference_images", "width", "height", "seed"]
    side_effects = ["writes a PNG to output_path"]
    user_visible_verification = ["Look at the picture: the count of anything the story counts, faces, period details"]

    def __init__(self) -> None:
        self._client = ComfyUIClient(capability="image")

    def get_status(self) -> ToolStatus:
        if not self._client.is_available():
            return ToolStatus.UNAVAILABLE
        _, missing = self._client.check_models(_MODELS)
        return ToolStatus.DEGRADED if missing else ToolStatus.AVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def estimate_runtime(self, inputs: dict[str, Any]) -> float:
        if inputs.get("fast", True):
            return 40.0 if inputs.get("reference_images") else 45.0
        return 140.0 if inputs.get("reference_images") else 90.0

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        if not self._client.is_available():
            return ToolResult(success=False, error=self._client.unavailable_reason())
        start = time.time()
        seed = pick_seed(inputs.get("seed"))
        # Fast unless told otherwise — and slow, not refused, where the LoRA or
        # the sigma node is not on this ComfyUI.
        fast = bool(inputs.get("fast", True))
        if fast:
            _, lacking = self._client.check_models([_FAST_LORA])
            fast = not lacking and self._client.has_node("ManualSigmas")
        references = [str(p) for p in inputs.get("reference_images") or []]
        output_path = Path(inputs.get("output_path") or f"qwen_image_{seed}.png")
        graph = {
            "1": node("UNETLoader", {"unet_name": _MODELS[0], "weight_dtype": "default"}),
            "2": node("CLIPLoader", {"clip_name": _MODELS[1], "type": "qwen_image", "device": "default"}),
            "3": node("VAELoader", {"vae_name": _MODELS[2]}),
            "7": node("VAEDecode", {"samples": ["6", 0], "vae": ["3", 0]}),
            "8": node("SaveImage", {"filename_prefix": f"openmontage/{output_path.stem}", "images": ["7", 0]}),
        }
        try:
            if references:
                encode = {"prompt": inputs["prompt"], "negative_prompt": "", "resolution": 0,
                          "clip": ["2", 0], "vae": ["3", 0]}
                for i, path in enumerate(references[:8]):
                    name = self._client.upload_image(as_png(path), f"om-{output_path.stem}-ref{i + 1}.png")
                    graph[str(100 + i)] = node("LoadImage", {"image": name})
                    encode[f"images.image_{i + 1}"] = [str(100 + i), 0]
                graph["4"] = node("QwenImage21Cache", {"device": "auto", "dtype": "default", "model": ["1", 0]})
                graph["5"] = node("TextEncodeQwenImage21", encode)
                latent, model = ["5", 2], ["4", 0]
                width = height = None
            else:
                width, height = size_for(inputs.get("aspect_ratio"), 1.0, 16, inputs.get("width"), inputs.get("height"))
                graph["5"] = node("TextEncodeQwenImage21", {"prompt": inputs["prompt"], "negative_prompt": "",
                                                            "resolution": 1024, "clip": ["2", 0]})
                graph["9"] = node("EmptyLatentImage", {"width": width, "height": height, "batch_size": 1})
                latent, model = ["9", 0], ["1", 0]
            if fast:
                # PrunaAI's 8-step LoRA: strength 2.0 (alpha 128 over rank 64,
                # which the file does not carry), its own sigmas, no CFG.
                graph["90"] = node("LoraLoaderModelOnly", {"model": ["1", 0], "lora_name": _FAST_LORA,
                                                           "strength_model": 2.0})
                if model == ["1", 0]:
                    model = ["90", 0]
                else:
                    graph["4"]["inputs"]["model"] = ["90", 0]
                graph["91"] = node("RandomNoise", {"noise_seed": seed})
                graph["92"] = node("CFGGuider", {"model": model, "positive": ["5", 0], "negative": ["5", 1], "cfg": 1.0})
                graph["93"] = node("KSamplerSelect", {"sampler_name": "euler"})
                graph["94"] = node("ManualSigmas", {"sigmas": _FAST_SIGMAS})
                graph["6"] = node("SamplerCustomAdvanced", {"noise": ["91", 0], "guider": ["92", 0], "sampler": ["93", 0],
                                                            "sigmas": ["94", 0], "latent_image": latent})
            else:
                graph["6"] = node("KSampler", {"seed": seed, "steps": int(inputs.get("steps", 25)), "cfg": 1,
                                               "sampler_name": "euler", "scheduler": "simple", "denoise": 1,
                                               "model": model, "positive": ["5", 0], "negative": ["5", 1],
                                               "latent_image": latent})
            paths = self._client.generate(graph, output_node="8", dest=output_path, timeout=900)
        except ComfyUIError as exc:
            return ToolResult(success=False, error=str(exc))
        except Exception as exc:
            return ToolResult(success=False, error=f"Qwen-Image on the box failed: {exc}")
        return ToolResult(
            success=True,
            data={"provider": self.provider, "model": "qwen-image-2.1-int8" + (" + pruna 8-step" if fast else ""),
                  "mode": "edit" if references else "text_to_image", "fast": fast,
                  "prompt": inputs["prompt"], "reference_images": references, "width": width, "height": height,
                  "output": str(paths[0])},
            artifacts=[str(p) for p in paths], cost_usd=0.0, duration_seconds=round(time.time() - start, 2),
            seed=seed, model="qwen-image-2.1-int8",
        )
