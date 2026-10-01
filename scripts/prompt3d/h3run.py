"""Film one prompt3d shot on the box's ComfyUI with MiniMax H3: the depth video through the
Fun ControlNet-Union (it follows the set and the camera frame for frame) and any number of
painted keyframes pinned with Add Guide (they say what the set looks like).

  venv/bin/python h3run.py --name prompt3d-1-A --depth prompt3d-1-depth.mp4 \
      --pin prompt3d-1-key-0000.png:0 --pin prompt3d-1-key-0061.png:61 --pin ... \
      --prompt "..." [--steps 4] [--seed 7] [--width 864 --height 480 --length 124]

Files named here are already in ComfyUI's input folder. The graph is FilmH3's (reference-to-video,
the 4-step LoRA for drafts, res_multistep) with the ControlNet patch put on the model the guider uses.
Progress goes only to the client that queued the prompt, so this script is that client.
"""
import argparse, asyncio, json, time, uuid
import aiohttp

p = argparse.ArgumentParser()
p.add_argument("--name", required=True)
p.add_argument("--depth", required=True)
p.add_argument("--pin", action="append", default=[])
p.add_argument("--prompt", required=True)
p.add_argument("--steps", type=int, default=4)
p.add_argument("--seed", type=int, default=7)
p.add_argument("--width", type=int, default=864)
p.add_argument("--height", type=int, default=480)
p.add_argument("--length", type=int, default=124)
p.add_argument("--strength", type=float, default=1.0)
p.add_argument("--port", type=int, default=8188)
# PyTorch's own attention for H3 through KinClaw's node (scripts/comfy), when
# the box has it: 75.6 -> 68.3 s a step at 640x640x124, the same picture.
p.add_argument("--no-fast-attention", action="store_true")
# The int8 ControlNet patch needs torch._int_mm, which MPS does not have; the bf16 one is the same
# weights dequantized (ConvRot rotated back) and runs on the GPU. Made once by dequantize_patch.py.
p.add_argument("--patch", default="minimax_h3_fun_controlnet_union_bf16_dequant.safetensors")
a = p.parse_args()

def node(t, inputs): return {"class_type": t, "inputs": inputs}
draft = a.steps <= 8
g = {
    "1": node("UNETLoader", {"unet_name": "minimax_h3_ref2va_pruned_int8_convrot.safetensors", "weight_dtype": "default"}),
    "2": node("CLIPLoader", {"clip_name": "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors", "type": "minimax", "device": "default"}),
    "3": node("VAELoader", {"vae_name": "minimax_h3_video_vae_fp16.safetensors"}),
    "4": node("VAELoader", {"vae_name": "minimax_h3_audio_vae_fp32.safetensors"}),
    "5": node("LoraLoaderModelOnly", {"lora_name": "minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors", "strength_model": 1, "model": ["1", 0]}),
    "20": node("ModelPatchLoader", {"name": a.patch}),
    "21": node("LoadVideo", {"file": a.depth}),
    "22": node("GetVideoComponents", {"video": ["21", 0]}),
    "23": node("MiniMaxH3FunControlNetApply", {"model": ["5", 0] if draft else ["1", 0], "model_patch": ["20", 0], "vae": ["3", 0],
                                                "strength": a.strength, "start_percent": 0.0, "end_percent": 1.0, "control_video": ["22", 0]}),
    "6": node("MiniMaxH3ReferenceToVideo", {"prompt": a.prompt, "width": a.width, "height": a.height, "length": a.length,
                                             "ref_image_size": "match", "clip": ["2", 0], "vae": ["3", 0], "audio_vae": ["4", 0]}),
    "7": node("RandomNoise", {"noise_seed": a.seed}),
    "8": node("KSamplerSelect", {"sampler_name": "res_multistep"}),
    "9": node("BasicScheduler", {"scheduler": "simple", "steps": a.steps, "denoise": 1, "model": ["23", 0]}),
    "11": node("SamplerCustomAdvanced", {"noise": ["7", 0], "guider": ["10", 0], "sampler": ["8", 0], "sigmas": ["9", 0], "latent_image": ["6", 1]}),
    "12": node("VAEDecode", {"samples": ["11", 0], "vae": ["3", 0]}),
    "13": node("VAEDecodeAudio", {"samples": ["11", 0], "vae": ["4", 0]}),
    "14": node("CreateVideo", {"fps": 24, "bit_depth": 8, "color_space": "sRGB", "codec": "none", "images": ["12", 0], "audio": ["13", 0]}),
    "15": node("SaveVideo", {"filename_prefix": f"video/{a.name}", "format": "auto", "codec": "auto", "format.codec": "auto", "video": ["14", 0]}),
}
conditioning = ["6", 0]
for i, pin in enumerate(a.pin):
    file, frame = pin.rsplit(":", 1)
    g[str(200 + i)] = node("LoadImage", {"image": file})
    g[str(300 + i)] = node("MiniMaxH3AddGuide", {"positive": conditioning, "latent": ["6", 1], "frame_idx": int(frame),
                                                  "vae": ["3", 0], "audio_vae": ["4", 0], "image": [str(200 + i), 0]})
    conditioning = [str(300 + i), 0]
g["10"] = node("BasicGuider", {"model": ["23", 0], "conditioning": conditioning})

async def main():
    cid = "prompt3d-" + uuid.uuid4().hex[:8]
    t0 = time.time()
    say = lambda s: print(f"{time.time() - t0:7.1f}s {s}", flush=True)
    async with aiohttp.ClientSession() as s:
        if not a.no_fast_attention:
            info = await (await s.get(f"http://127.0.0.1:{a.port}/object_info/KinClawPytorchAttention")).text()
            if '"KinClawPytorchAttention"' in info:
                g["24"] = node("KinClawPytorchAttention", {"model": g["10"]["inputs"]["model"]})
                g["10"]["inputs"]["model"] = ["24", 0]
                say("PyTorch attention (KinClawPytorchAttention)")
        async with s.ws_connect(f"http://127.0.0.1:{a.port}/ws?clientId={cid}") as ws:
            r = await s.post(f"http://127.0.0.1:{a.port}/prompt", json={"prompt": g, "client_id": cid})
            body = await r.json()
            pid = body.get("prompt_id")
            if not pid:
                say("refused " + json.dumps(body)[:1500]); return
            say(f"queued {pid}")
            last = None
            async for m in ws:
                if m.type != aiohttp.WSMsgType.TEXT: continue
                d = json.loads(m.data); t = d.get("type"); data = d.get("data") or {}
                if t == "executing" and data.get("node") and data["node"] != last:
                    last = data["node"]; say(f"node {last} {g.get(last, {}).get('class_type', '?')}")
                elif t == "progress" and data.get("value") in (1, data.get("max")):
                    say(f"  step {data.get('value')}/{data.get('max')}")
                elif t in ("execution_success", "execution_error", "execution_interrupted"):
                    say(t + " " + json.dumps(data)[:800]); break
            h = await (await s.get(f"http://127.0.0.1:{a.port}/history/{pid}")).json()
            out = h.get(pid, {}).get("outputs", {}).get("15", {})
            say("output " + json.dumps(out)[:400])

asyncio.run(main())
