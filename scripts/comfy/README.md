# KinClaw's pieces for the box's ComfyUI

The box runs ComfyUI on Apple silicon (MPS). Two things there cost the Studio most of its time, and these files
take them away without touching ComfyUI itself (measured 2026-09-29, M3 Ultra, ComfyUI 0.37, PyTorch 2.14):

- **Text encoders run on the CPU.** ComfyUI counts a Mac's memory as shared and puts every text encoder on the
  CPU. For MiniMax Music 3 that is nearly all of a cue: its acoustic planner writes 25 tokens a second of music, one
  at a time, at 2.7 s a token — a 6-second cue took 419 s, 402 of them there. On the GPU: 37 s; a 30-second cue 179 s
  (about 34 minutes before). `--gpu-only` cannot do it: the Apple GPU has no int8 matmul (`aten::_int_mm`) for the
  int8 encoder, and no float8 for H3's nvfp4 one, which breaks.
- **Attention is ComfyUI's sub-quadratic fallback.** On a Mac ComfyUI only uses PyTorch's scaled-dot-product
  attention with `--use-pytorch-cross-attention`, and that flag is global. For H3 (640×640, 124 frames, 4 steps) it
  took a step from 75.6 s to 68.3 s — a shot from 350 s to 312 s — with the same picture (SSIM 0.94 at one seed).

| file | on the box | what |
|---|---|---|
| `kinclaw_nodes/__init__.py` | `~/ComfyUI/custom_nodes/kinclaw_nodes/__init__.py` | `KinClawCLIPLoaderGPU` (a plain bf16/fp16 text encoder kept on the GPU) and `KinClawPytorchAttention` (PyTorch attention for the one model passing through; every other workflow keeps the default) |
| `dequant_te.py` | run once with ComfyUI's venv | an `int8_convrot` text encoder written out as plain bf16, un-rotated with comfy_kitchen's own dequantizer |

Install or update from this Mac, then restart ComfyUI (the console's 盒子 panel) so it loads the nodes:

```sh
cd scripts/comfy
ssh jackysub@192.168.0.21 'mkdir -p ~/ComfyUI/custom_nodes/kinclaw_nodes ~/.kinclaw/comfy'
scp kinclaw_nodes/__init__.py jackysub@192.168.0.21:ComfyUI/custom_nodes/kinclaw_nodes/
scp dequant_te.py jackysub@192.168.0.21:.kinclaw/comfy/
ssh jackysub@192.168.0.21 'cd ~/ComfyUI && T=models/text_encoders && venv/bin/python ~/.kinclaw/comfy/dequant_te.py \
  $T/minimax_music3_text_encoder_pruned_int8_convrot.safetensors $T/minimax_music3_text_encoder_bf16_dequant.safetensors'
```

The conversion takes seconds and writes 16.7 GB. Film (`FilmSound.composeMiniMax`, `FilmStudio.renderH3`),
Motion's `scripts/prompt3d/h3run.py` and OpenMontage's `minimax_music` / `h3_video` use the nodes when the box
has them and the stock graph when it does not.
