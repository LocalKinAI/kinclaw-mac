"""An int8_convrot text encoder written out again as plain bf16, so it can run
on the Apple GPU (which has no int8 matmul): every quantized linear weight
un-rotated and un-scaled with comfy_kitchen's own dequantizer, everything else
copied as it was, the file's metadata kept. Run with ComfyUI's venv:
    venv/bin/python dequant_te.py <in.safetensors> <out.safetensors>
"""
import json
import sys
import time

import torch
import comfy_kitchen  # noqa: F401  (registers torch.ops.comfy_kitchen)
from comfy_kitchen.tensor.int8 import _INT8_DEQUANT_DTYPE_TO_CODE
from safetensors import safe_open
from safetensors.torch import save_file

src, dst = sys.argv[1], sys.argv[2]
t0 = time.time()
out, done = {}, 0
with safe_open(src, "pt") as f:
    metadata = f.metadata() or {}
    keys = list(f.keys())
    quantized = {k[: -len(".comfy_quant")] for k in keys if k.endswith(".comfy_quant")}
    for key in keys:
        if key.endswith(".comfy_quant") or key.endswith(".weight_scale"):
            continue
        base = key[: -len(".weight")] if key.endswith(".weight") else None
        if base in quantized:
            spec = json.loads(bytes(f.get_tensor(base + ".comfy_quant").tolist()))
            if spec.get("format") != "int8_tensorwise":
                sys.exit(f"{base}: format {spec} is not int8_tensorwise")
            q, scale = f.get_tensor(key), f.get_tensor(base + ".weight_scale")
            code = _INT8_DEQUANT_DTYPE_TO_CODE.get(torch.bfloat16, 0)
            if spec.get("convrot"):
                w = torch.ops.comfy_kitchen.dequantize_int8_convrot_weight_dtype(q, scale, spec.get("convrot_groupsize", 256), code)
            else:
                w = torch.ops.comfy_kitchen.dequantize_int8_simple_dtype(q, scale, code)
            out[key] = w.to(torch.bfloat16).contiguous()
            done += 1
        else:
            out[key] = f.get_tensor(key)
print(f"dequantized {done} of {len(quantized)} layers in {time.time() - t0:.0f} s; writing", flush=True)
save_file(out, dst, metadata=metadata)
print(f"wrote {dst} in {time.time() - t0:.0f} s", flush=True)
