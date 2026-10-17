# FLUX 3 Image Klein on the box

The box's second picture model, beside Qwen-Image-2.1-Turbo: Settings → 画·改·拍·声音 → 「盒子·FLUX 3」 for 画 and/or
改, or `model: flux3` on one `image_generate` / `image_edit` call. `flux3_server.py` serves it on port 8004 with the
OllamaDiffuser API the app already speaks (`/api/health`, `/api/generate`, `/api/generate/img2img`); BoxServices
starts it on demand (`.flux`) and lets it take turns with Qwen's 画 and 改 servers.

| | |
|---|---|
| Model | [black-forest-labs/flux-3-image-klein](https://huggingface.co/black-forest-labs/flux-3-image-klein) (2026-10-13): 5.6B distilled transformer, 16 steps, Qwen3-VL-4B text encoder; t2i, edit, up to 10 references, boxes in the prompt |
| Runtime | [mflux](https://github.com/mflux-community/mflux) 0.23.0 (MLX), bf16, in its own virtualenv — not OllamaDiffuser's |
| Captions | FLUX 3 draws from a whole scene described. A short request, and every edit, is first written into one by the box's Ollama (`ornith-1.5:35b`, thinking off, `keep_alive` 2 min) with BFL's prompt-upsampler instructions (`system_prompts.json` of `flux-3-image-klein-pup`). A long caption or one with a box list goes as written; `upsample` true/false overrides. The caption used comes back in `X-Flux-Caption` (base64) and the app keeps it in the picture's sidecar. |
| Memory | about 37 GB while drawing (38.6 GB editing with references); the model is let go after 10 minutes idle (`--keep`) |
| Licence | FLUX Kommunity License v1.0: non-commercial use, plus commercial output for users under US$5M annual revenue. Each user accepts it on Hugging Face themselves and logs in on the box (`hf auth login`). |

Measured on the box (M3 Ultra, 2026-10-16): 1664×928 64–75 s a picture; 1024×768 35 s + 15 s caption (the
first one loads ornith); an edit with one reference 67–74 s, two references 190 s. Against Qwen-Image-2.1-Turbo on
the 人造太阳 pictures: more photographic, boxes placed exactly, references composed well, numbers and English
lettering right — Chinese lettering wrong in 4 of 7 (Qwen 1 of 7).

## Set up

```sh
# on the box, after accepting the licence on the model page and `hf auth login`
mkdir -p ~/.kinclaw/flux3 && cd ~/.kinclaw/flux3
uv venv venv --python 3.12
uv pip install --python venv/bin/python "mflux==0.23.0"
# from this repo
scp scripts/flux3/flux3_server.py jackysub@192.168.0.21:.kinclaw/flux3/
```

The weights (~20 GB: transformer 11.1, text encoder 8.9, VAE 0.3) download on the first picture; the app's 90-second
start wait does not cover that, so the first time run one picture by hand:

```sh
cd ~/.kinclaw/flux3 && venv/bin/python flux3_server.py --port 8004   # then POST /api/generate once
```

Logs: `~/Library/Logs/kinclaw/flux.log` on the box.
