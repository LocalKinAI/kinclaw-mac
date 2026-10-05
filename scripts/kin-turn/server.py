"""kin-turn — the companion's mini-turns, on the box.

Griffin (Tavus, 2026-10-01) decides every few hundred milliseconds whether to stay
quiet, nod, say 嗯, or take the turn. This is the open-source half of that for
KinClawMac's companion: two small models listen to the microphone the app streams here.

- Smart Turn v3.2 (pipecat-ai, BSD-2): after a pause, is the speaker done?
  About 7 ms on the CPU, judged on the last 8 s of audio.
- MaAI backchannel model, Chinese (Kyoto University, MIT): every 100 ms, how likely
  a listener is to say 嗯 or nod right now (p_bc).

WS /listen
  client → binary  1 byte channel (1 = the user's microphone, 2 = her own voice)
                   + s16le mono 16 kHz PCM, any length, in real time
  client → text    {"type": "turn", "id": n}   is the user done? (on the last 8 s)
                   {"type": "reset"}           a new conversation
  server → text    {"type": "bc", "t": s, "p": p_bc}       ten a second while audio flows
                   {"type": "turn", "id": n, "p": P(complete), "ms": t}
POST /turn   body s16le mono 16 kHz PCM (8 s at most) → {"p": P(complete), "ms": t}
GET  /health

One conversation at a time: a new /listen closes the one before.
"""
import asyncio
import json
import logging
import os
import sys
import threading
import time

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "shim"))

import onnxruntime as ort  # noqa: E402
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect  # noqa: E402
from transformers import WhisperFeatureExtractor  # noqa: E402

log = logging.getLogger("kin-turn")
logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(asctime)s %(message)s")

RATE = 16000
SMART_TURN = os.path.expanduser("~/kin-avatar/smart-turn/smart-turn-v3.2-cpu.onnx")
FRAME = 160  # MaAI's input frame: 10 ms

app = FastAPI()
_features = WhisperFeatureExtractor(chunk_length=8)
_turn = ort.InferenceSession(SMART_TURN, providers=["CPUExecutionProvider"])
_maai = None
_ch1 = _ch2 = None
_lock = threading.Lock()
_active = None


def complete(pcm: np.ndarray) -> tuple[float, float]:
    """P(the turn is complete) for float32 16 kHz audio that ends now."""
    a = pcm[-8 * RATE:]
    if len(a) < 8 * RATE:
        a = np.pad(a, (8 * RATE - len(a), 0))
    f = _features(a, sampling_rate=RATE, return_tensors="np", padding="max_length",
                  max_length=8 * RATE, truncation=True, do_normalize=True)
    t = time.time()
    p = _turn.run(None, {"input_features": f.input_features.astype(np.float32)})[0]
    return float(np.ravel(p)[0]), (time.time() - t) * 1000


def load_maai():
    """MaAI prints a line per frame from its worker thread, so stdout goes nowhere here."""
    global _maai, _ch1, _ch2
    from maai import Maai, MaaiInput
    sys.stdout = open(os.devnull, "w")
    t = time.time()
    _ch1, _ch2 = MaaiInput.Chunk(), MaaiInput.Chunk()
    _maai = Maai(mode="bc", lang="ch", frame_rate=10, context_len_sec=20,
                 audio_ch1=_ch1, audio_ch2=_ch2, device="cpu")
    _maai.start()
    log.info("MaAI bc (ch) ready in %.1f s", time.time() - t)


@app.on_event("startup")
async def startup():
    await asyncio.to_thread(load_maai)


@app.get("/health")
async def health():
    return {"ok": True, "maai": _maai is not None, "listening": _active is not None}


@app.post("/turn")
async def turn(request: Request):
    pcm = np.frombuffer(await request.body(), dtype="<i2").astype(np.float32) / 32768.0
    p, ms = complete(pcm)
    return {"p": round(p, 4), "ms": round(ms, 1)}


@app.websocket("/listen")
async def listen(ws: WebSocket):
    global _active
    await ws.accept()
    if _active is not None:
        try:
            await _active.close(code=4000, reason="another conversation started")
        except Exception:
            pass
    _active = ws
    with _lock:
        while not _maai.result_dict_queue.empty():
            _maai.result_dict_queue.get_nowait()
        try:
            _maai.reset_runtime_state()
        except Exception as e:
            log.info("reset: %s", e)
    user = np.zeros(0, np.float32)      # the user's last 8 s, for Smart Turn
    hers = np.zeros(0, np.float32)      # her voice not yet paired with user frames
    pending = np.zeros(0, np.float32)   # user samples short of a whole frame
    fed = [0]                           # user frames fed = time since connecting
    log.info("listening to %s", ws.client)

    async def pump():
        while True:
            await asyncio.sleep(0.02)
            while not _maai.result_dict_queue.empty():
                r = _maai.result_dict_queue.get_nowait()
                p = r.get("p_bc")
                if p is None:
                    continue
                await ws.send_text(json.dumps({"type": "bc", "t": round(fed[0] * FRAME / RATE, 2),
                                               "p": round(float(np.ravel(p)[-1]), 3)}))

    sender = asyncio.create_task(pump())
    try:
        while True:
            msg = await ws.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if msg.get("bytes"):
                data = msg["bytes"]
                pcm = np.frombuffer(data[1:], dtype="<i2").astype(np.float32) / 32768.0
                if data[0] == 2:
                    hers = np.concatenate([hers, pcm])[-RATE * 2:]
                    continue
                user = np.concatenate([user, pcm])[-8 * RATE:]
                pending = np.concatenate([pending, pcm])
                n = len(pending) // FRAME
                for i in range(n):
                    _ch1.put_chunk(pending[i * FRAME:(i + 1) * FRAME])
                    if len(hers) >= FRAME:
                        _ch2.put_chunk(hers[:FRAME])
                        hers = hers[FRAME:]
                    else:
                        _ch2.put_chunk(np.zeros(FRAME, np.float32))
                pending = pending[n * FRAME:]
                fed[0] += n
            elif msg.get("text"):
                cmd = json.loads(msg["text"])
                if cmd.get("type") == "turn":
                    p, ms = await asyncio.to_thread(complete, user.copy())
                    await ws.send_text(json.dumps({"type": "turn", "id": cmd.get("id"),
                                                   "p": round(p, 4), "ms": round(ms, 1)}))
                elif cmd.get("type") == "reset":
                    user = np.zeros(0, np.float32)
                    with _lock:
                        _maai.reset_runtime_state()
    except WebSocketDisconnect:
        pass
    finally:
        sender.cancel()
        if _active is ws:
            _active = None
        log.info("stopped listening to %s", ws.client)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8104")), log_level="warning")
