"""KinClaw's small nodes for the box's ComfyUI (Apple silicon, MPS).

KinClawCLIPLoaderGPU — a text encoder on the GPU. On a Mac ComfyUI counts
memory as shared and puts every text encoder on the CPU. For one that writes
hundreds of tokens one at a time — MiniMax Music 3's acoustic planner, 25 a
second of music — that is nearly all of a cue's time: 2.7 s a token, 402 of a
6-second cue's 415 s (2026-09-29). It needs a plain file (bf16): the Apple GPU
has no int8 matmul (aten::_int_mm) and no float8, so int8/nvfp4 encoders stay
on the CPU with the stock loader.

KinClawCheckpointLoaderGPU — a whole checkpoint with its text encoder on the
GPU. YuE2 is one: its ABC score and its music tokens are written one token at
a time by that encoder, 2.4 tokens/s on the CPU. Needs a plain (bf16) file,
as above.

KinClawPytorchAttention — the model passing through uses PyTorch's own
scaled-dot-product attention (PyTorch 2.14's Metal flash kernel) instead of
ComfyUI's default on a Mac, sub-quadratic. Only that model: every other
workflow keeps the default. H3, 640x640, 124 frames, 4 steps: 75.6 -> 68.3 s
a step (2026-09-29).
"""
import torch

import comfy.ldm.modules.attention as attention
import comfy.model_management
import comfy.sd
import folder_paths
import nodes

DTYPES = {"bf16": torch.bfloat16, "fp16": torch.float16, "fp32": torch.float32}


class KinClawCLIPLoaderGPU:
    @classmethod
    def INPUT_TYPES(cls):
        stock = nodes.CLIPLoader.INPUT_TYPES()["required"]
        return {"required": {"clip_name": stock["clip_name"], "type": stock["type"],
                             "dtype": (list(DTYPES), {"default": "bf16"})}}

    RETURN_TYPES = ("CLIP",)
    FUNCTION = "load_clip"
    CATEGORY = "KinClaw"
    DESCRIPTION = "CLIPLoader with the text encoder kept on the GPU (MPS), for a plain bf16/fp16 file."

    def load_clip(self, clip_name, type, dtype="bf16"):
        device = comfy.model_management.get_torch_device()
        clip_type = getattr(comfy.sd.CLIPType, type.upper(), comfy.sd.CLIPType.STABLE_DIFFUSION)
        options = {"load_device": device, "offload_device": device, "dtype": DTYPES[dtype]}
        path = folder_paths.get_full_path_or_raise("text_encoders", clip_name)
        clip = comfy.sd.load_clip(ckpt_paths=[path], embedding_directory=folder_paths.get_folder_paths("embeddings"),
                                  clip_type=clip_type, model_options=options)
        return (clip,)


class KinClawCheckpointLoaderGPU:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"ckpt_name": (folder_paths.get_filename_list("checkpoints"),),
                             "dtype": (list(DTYPES), {"default": "bf16"})}}

    RETURN_TYPES = ("MODEL", "CLIP", "VAE")
    FUNCTION = "load_checkpoint"
    CATEGORY = "KinClaw"
    DESCRIPTION = "CheckpointLoaderSimple with the checkpoint's text encoder kept on the GPU (MPS), for a plain bf16/fp16 file."

    def load_checkpoint(self, ckpt_name, dtype="bf16"):
        device = comfy.model_management.get_torch_device()
        path = folder_paths.get_full_path_or_raise("checkpoints", ckpt_name)
        out = comfy.sd.load_checkpoint_guess_config(
            path, output_vae=True, output_clip=True, embedding_directory=folder_paths.get_folder_paths("embeddings"),
            te_model_options={"load_device": device, "offload_device": device, "dtype": DTYPES[dtype]})
        return out[:3]


class KinClawPytorchAttention:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"model": ("MODEL",)}}

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "patch"
    CATEGORY = "KinClaw"
    DESCRIPTION = "This model only: PyTorch scaled-dot-product attention instead of ComfyUI's default."

    def patch(self, model):
        patched = model.clone()
        patched.set_model_optimized_attention(attention.attention_pytorch)
        return (patched,)


NODE_CLASS_MAPPINGS = {
    "KinClawCLIPLoaderGPU": KinClawCLIPLoaderGPU,
    "KinClawCheckpointLoaderGPU": KinClawCheckpointLoaderGPU,
    "KinClawPytorchAttention": KinClawPytorchAttention,
}
NODE_DISPLAY_NAME_MAPPINGS = {
    "KinClawCLIPLoaderGPU": "Load CLIP on the GPU (KinClaw)",
    "KinClawCheckpointLoaderGPU": "Load Checkpoint, text encoder on the GPU (KinClaw)",
    "KinClawPytorchAttention": "PyTorch attention, this model (KinClaw)",
}
