# kin-turn — the companion's mini-turns, on the box

`TurnTaker` (KinClawMac/Services/TurnTaker.swift) streams the microphone here while it is
the user's turn. Two small open models answer:

- **Smart Turn v3.2** (pipecat-ai, BSD-2): after a pause, is the sentence finished?
  About 7 ms on the CPU, from the last 8 s of audio.
- **MaAI back-channel model, Chinese** (Kyoto University, MIT code): every 100 ms, how likely
  a listener is to say 嗯 or nod now.

The API is in `server.py`'s docstring (WS `/listen`, POST `/turn`, GET `/health`).

## On the box

```
~/kin-avatar/turn/
  server.py            this directory's server.py
  shim/pyaudio.py      pyaudio_shim.py — MaAI imports PyAudio, the box has no portaudio
  shim/pygame.py       pygame_shim.py  — MaAI imports pygame to play wav files
  .venv/               uv venv --python 3.12
~/kin-avatar/smart-turn/smart-turn-v3.2-cpu.onnx   hf download pipecat-ai/smart-turn-v3
~/.cache/cpc/60k_epoch4-d0f474de.pt                MaAI's CPC encoder (7.4 MB, Meta's file server;
                                                   torch.hub hung on it — fetched with curl)
```

```
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python --no-deps maai
uv pip install --python .venv/bin/python einops huggingface-hub numpy onnxruntime pydub soundfile \
    "torch>=2.6" "transformers==5.5.3" fastapi "uvicorn[standard]"
```

MaAI's own requirements also pull PyQt5, pygame, PyAudio, matplotlib and seaborn for its
desktop demos; the server needs none of them. MaAI downloads `maai-kyoto/vap_bc_ch` itself
on first start (its 20-second-context model: `context_len_sec=20`).

Started and stopped like the other box services: Settings → Backend → 盒子上的服务 in
KinClaw, or the console's 盒子 panel (localhost:9000). Log: ~/Library/Logs/kinclaw/turn.log.
