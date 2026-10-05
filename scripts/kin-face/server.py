"""kin-face — the companion's face, lip-synced on the box as she speaks.

Her body is rendered once by Ditto from her photograph, the camera still, each
clip looped forward and back so the loop has no seam — two bodies, as HeyGen
films its presenters: one that listens (lips closed, a tilt of the head, a
blink: base.mp4) and one that talks (her head moving with a voice, the lips held
as in the photograph: speak.mp4). Her mouth is MuseTalk 1.5 on MLX, made from
her voice as it arrives, over whichever body she is in: 20 frames a second at
full quality on the M3 Ultra, 0.31 s after a whole sentence is pushed. Measured
2026-10-02; tuning and fixes from ~/kin-avatar/musetalk/KIN-NOTES.md (async
submit, exact mask cache, no audio prefix, chin margin, 1 s windows).

WS /face — one viewer at a time
  server → binary   1 byte kind (1 idle, 2 speaking, 3 waiting) + float64 pts
                    (seconds of her voice consumed) + JPEG, twenty a second
           /face?v=2  the same with a second float64 after pts: the frame's slot on
                    the box's clock (seconds), so the viewer can show the frames at
                    the pace they were sent whatever the network did to them (Wi-Fi
                    to the Mac held some back 0.4 s and more, 2026-10-02)
  client → text     {"type": "seen", "slot": s}  (v2) frame s arrived. While the
                    oldest frame not yet seen is over CONGESTED old the link is full
                    and frames are dropped instead of queued behind it: on a Wi-Fi
                    that fell to 5 Mbit/s every frame had been sent, and they arrived
                    up to 16 s late
  client → binary   her voice: s16le mono 16 kHz, pushed as it is to be heard;
                    the client plays it `latency_s` later so lips and sound meet
  client → text     {"type": "end"}        no more voice for now (renders the tail)
                    {"type": "interrupt"}  she was cut off: drop what is pending
GET /health  {"ready", "fps", "latency_s", "look", "bodies", "viewing"}

MLX work stays on the session's own render thread: the I/O side only pushes
numpy and pops finished frames (KIN-NOTES, problem 2).
"""
import asyncio
import json
import logging
import os
import struct
import subprocess
import sys
import threading
import time

os.environ.setdefault("MT_SMART_CONV", "1")
os.environ.setdefault("FUSION_MUSETALK_GRAPH_PATTERNS", "0")
os.environ.setdefault("MT_BG_POOL_MAX_FRAMES", "1000")
# A 1024x1312 body is 4 MB a frame: every frame of both bodies (318 + 478) must sit in the pool
# and be precomputed, or the ones past the default 1 GB are decoded and re-analysed as she
# speaks and the mouth falls behind.
os.environ.setdefault("MT_BG_POOL_BUDGET_MB", "4500")

import cv2  # noqa: E402
import imageio  # noqa: E402
import imageio_ffmpeg  # noqa: E402
import numpy as np  # noqa: E402

sys.path.insert(0, os.path.expanduser("~/kin-avatar/musetalk/kin"))
import kin_tuning as kt  # noqa: E402
from musetalk_mlx import MuseTalkSession, config  # noqa: E402
from musetalk_mlx.utils.audio import AudioWindower  # noqa: E402
from fastapi import FastAPI, WebSocket, WebSocketDisconnect  # noqa: E402

import musetalk_mlx.face.mask as mt_mask  # noqa: E402

# The mouth and the jaw are MuseTalk's; the cheeks, the nose and the rest stay the body's.
# MuseTalk draws the lower face at 256 px, and pasted over the whole lower face of a 1024x1312
# body (a face about 450 px wide) the cheeks, chin and nose went soft below a sharp upper face
# (「图片太low了」). Cut down to the lips alone, the mouth opened while the chin stayed shut
# (「对口型不自然」). So: the lips with room round them, and the skin below them as wide as the
# mouth — the chin and jaw, which drop when she speaks — from BiSeNet's labels, feathered.
_LIPS = (11, 12, 13)


def _mouth_and_jaw(labels):
    lips = np.isin(labels, _LIPS)
    ys, xs = np.nonzero(lips)
    if len(ys) == 0:
        return np.zeros(labels.shape, np.float32)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = max(1, y1 - y0), max(1, x1 - x0)
    region = np.zeros(labels.shape, np.uint8)
    cv2.ellipse(region, (int((x0 + x1) / 2), int(y0 + h * 0.5)), (int(w * 0.72), int(h * 1.1)), 0, 0, 360, 1, -1)
    jaw = np.zeros(labels.shape, bool)
    jaw[int(y0 + h * 0.5):, max(0, x0 - int(w * 0.12)):x1 + int(w * 0.12)] = True
    region |= (jaw & np.isin(labels, (1,) + _LIPS)).astype(np.uint8)
    return region.astype(np.float32)


def _mouth_mask(self, frame_bgr, face_box):
    crop_box = mt_mask._expand_crop_box(face_box, frame_bgr.shape)
    x_s, y_s, x_e, y_e = crop_box
    ph, pw = y_e - y_s, x_e - x_s
    if ph <= 0 or pw <= 0:
        return np.zeros((0, 0), dtype=np.float32), crop_box
    try:
        labels, _ = self.backend.parse(frame_bgr[y_s:y_e, x_s:x_e])
    except Exception as e:
        log.warning("face-parse failed (%s); feather fallback this frame", e)
        return np.zeros((0, 0), dtype=np.float32), crop_box
    if labels.shape[:2] != (ph, pw):
        labels = cv2.resize(labels.astype(np.uint8), (pw, ph), interpolation=cv2.INTER_NEAREST)
    mask = _mouth_and_jaw(labels)
    k = max(1, int(0.08 * ph // 2) * 2 + 1)
    mask = cv2.GaussianBlur(mask, (k, k), 0)
    with self._cache_lock:
        self._cache_key = (pw, ph, x_s, y_s)
        self._cache_mask = mask
    return mask, crop_box


mt_mask.FaceParseMask.mouth_mask = _mouth_mask

# How far the mouth opens. Over a closed-mouth body MuseTalk's mouth keeps close to the body's
# own and she mumbles (2 s of 「你好呀，今天过得怎么样」: lips parted a little on every frame).
# MuseTalk's bbox_shift moves the line its crop is centred on. Measured here the opposite way round
# from its authors' account: +24 px closed her mouth further, -24 opened it a little more (more
# frames with teeth showing). It has to be set before the session measures the body.
import musetalk_mlx.face.crop as mt_crop  # noqa: E402

BBOX_SHIFT = int(os.environ.get("FACE_BBOX_SHIFT", "-24"))
_crop_init = mt_crop.FaceCropper.__init__


def _shifted_init(self, size=config.PATCH, upperbondrange=0):
    _crop_init(self, size, upperbondrange or BBOX_SHIFT)


mt_crop.FaceCropper.__init__ = _shifted_init

# And the mouth itself sharper (「还是有点糊，再试试锐化」): MuseTalk's 256 px patch is enlarged to
# the face (about 1.75x here) with a cubic filter instead of a linear one, given an unsharp mask
# scaled to that enlargement, and in the feathered ring round it the body's own skin texture
# (its detail above a 1.6 px blur) is laid back, so the patch does not read as a smooth smear in
# a face with pores. The middle — the lips, whose shape changes — gets none of that texture.
import musetalk_mlx.pipeline.blending as mt_blend  # noqa: E402

SHARPEN = float(os.environ.get("FACE_SHARPEN", "0.6"))
DETAIL = float(os.environ.get("FACE_DETAIL", "0.8"))


def _sharp_paste_alpha(frame_bgr, face, bbox, alpha):
    # Only the rectangle the mouth mask covers is touched: done over the whole face box the
    # filters cost the render thread enough that it fell below twenty frames a second.
    out = frame_bgr.copy()
    x, y, x1, y1 = bbox
    x_s, y_s, x_e, y_e = mt_blend._expand_crop_box(bbox, frame_bgr.shape)
    if x_e <= x_s or y_e <= y_s:
        return mt_blend._paste_feather(frame_bgr, face, bbox)
    fx, fy = x1 - x, y1 - y
    ox, oy = x - x_s, y - y_s
    p_x0, p_y0 = max(0, ox), max(0, oy)
    p_x1, p_y1 = min(x_e - x_s, ox + fx), min(y_e - y_s, oy + fy)
    if p_x1 <= p_x0 or p_y1 <= p_y0:
        return mt_blend._paste_feather(frame_bgr, face, bbox)
    a = alpha[p_y0:p_y1, p_x0:p_x1]
    if a.shape[:2] != (p_y1 - p_y0, p_x1 - p_x0):
        a = cv2.resize(a, (p_x1 - p_x0, p_y1 - p_y0), interpolation=cv2.INTER_LINEAR)
    rows = np.nonzero(a.max(axis=1) > 0.004)[0]
    cols = np.nonzero(a.max(axis=0) > 0.004)[0]
    if len(rows) == 0 or len(cols) == 0:
        return out
    r0, r1, c0, c1 = rows[0], rows[-1] + 1, cols[0], cols[-1] + 1
    face_resized = cv2.resize(face, (fx, fy), interpolation=cv2.INTER_CUBIC)
    src = face_resized[p_y0 - oy + r0:p_y0 - oy + r1, p_x0 - ox + c0:p_x0 - ox + c1]
    dst = out[y_s + p_y0 + r0:y_s + p_y0 + r1, x_s + p_x0 + c0:x_s + p_x0 + c1]
    af = np.clip(a[r0:r1, c0:c1], 0.0, 1.0).astype(np.float32)
    if SHARPEN > 0:
        soft = cv2.GaussianBlur(src, (0, 0), max(0.8, fx / 256 * 0.9))
        src = cv2.addWeighted(src, 1 + SHARPEN, soft, -SHARPEN, 0)
    if DETAIL > 0:
        body = dst.astype(np.float32)
        texture = body - cv2.GaussianBlur(body, (0, 0), 1.6)
        ring = (4.0 * af * (1.0 - af))[..., None]
        src = np.clip(src.astype(np.float32) + texture * ring * DETAIL, 0, 255).astype(np.uint8)
    elif src.dtype != dst.dtype:
        src = src.astype(dst.dtype)
    out[y_s + p_y0 + r0:y_s + p_y0 + r1, x_s + p_x0 + c0:x_s + p_x0 + c1] = \
        cv2.blendLinear(src, dst, af, 1.0 - af).astype(dst.dtype)
    return out


mt_blend._paste_alpha = _sharp_paste_alpha

log = logging.getLogger("kin-face")
logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(asctime)s %(message)s")

FPS = 20
LATENCY = float(os.environ.get("LATENCY_S", "0.35"))
LOOK = os.path.realpath(os.environ.get("LOOK", os.path.expanduser("~/kin-avatar/face/looks/current")))
MLX_DIR = os.path.expanduser("~/kin-avatar/musetalk/weights-mlx-fp16")

# With one body her head idled while her mouth talked, and the face read wrong without anyone
# being able to say why (「说不上来的感觉」). A cut from one body to the other lands on the frame
# most like the one that would have come next — and like the frames either side of it, so she
# keeps moving the way she was — and is cross-faded over FADE frames. When she stops she stays
# in the talking body a moment (between two sentences she does not drop back to listening),
# then goes back at a frame that matches well: from HOLD_MIN frames on, at HOLD_MAX at the latest.
FADE = 4
HOLD_MIN, HOLD_MAX = 10, 30
CONGESTED = 0.25  # seconds a frame may go unseen before the next ones are dropped (v2)


def bodies_clip():
    """The clip MuseTalk measures, and how many of its frames are the listening body (None when
    the look has only that one). Both bodies go in one clip, listening first."""
    base, speak = os.path.join(LOOK, "base.mp4"), os.path.join(LOOK, "speak.mp4")
    if not os.path.exists(speak):
        return base, None
    both = os.path.join(LOOK, "bodies.mp4")
    if not os.path.exists(both) or os.path.getmtime(both) < max(os.path.getmtime(base), os.path.getmtime(speak)):
        part = both + ".part.mp4"
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-loglevel", "error", "-y", "-i", base, "-i", speak,
                        "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0", "-an", "-c:v", "libx264",
                        "-crf", "14", "-pix_fmt", "yuv420p", part], check=True)
        os.replace(part, both)
    reader = imageio.get_reader(base)
    try:
        return both, reader.count_frames()
    finally:
        reader.close()


class Bodies:
    """Which body she is in and where: the frames MuseTalk renders on and the ones shown while
    she is quiet both come from here, one walk through the pool."""

    def __init__(self, pool, n_idle):
        self.pool, self.n_idle, self.n_speak = pool, n_idle, len(pool) - n_idle
        small = np.stack([
            cv2.GaussianBlur(cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (96, 123),
                                        interpolation=cv2.INTER_AREA), (0, 0), 1.0).ravel()
            for f in pool]).astype(np.float64)
        a, b = small[:n_idle], small[n_idle:]
        d = np.maximum((a * a).sum(1)[:, None] + (b * b).sum(1)[None, :] - 2 * a @ b.T, 0) / small.shape[1]
        # d[i, j]: listening frame i against talking frame j; w adds the pairs either side of it.
        w = d + 0.5 * (np.roll(d, (1, 1), axis=(0, 1)) + np.roll(d, (-1, -1), axis=(0, 1)))
        before = np.roll(w, -1, axis=0)                            # after listening i: most like listening i+1
        self.to_speak, self.cost_in = np.argmin(before, axis=1), before.min(axis=1)
        after = np.roll(w, -1, axis=1)                             # after talking j: most like talking j+1
        self.to_idle = np.argmin(after, axis=0)
        self.cost = after.min(axis=0)
        self.good = float(np.percentile(self.cost, 30))
        step = np.mean((small[1:] - small[:-1]) ** 2, axis=1)
        step = np.delete(step, n_idle - 1)  # not the seam between the two clips
        log.info("two bodies: %d listening, %d talking frames; a cut to talking costs %.1f (median), "
                 "back %.1f, against %.1f for one frame to the next",
                 n_idle, self.n_speak, float(np.median(self.cost_in)), float(np.median(self.cost)),
                 float(np.median(step)))
        self.lock = threading.Lock()
        self.at = 0            # the frame handed out last (a pool index)
        self.quiet = 0         # frames shown in the talking body since the renderer last took one
        self.spoke = 0.0       # when it did
        self.cut = False       # the renderer cut to the talking body; the sender fades it in

    def _next(self, k):
        if k < self.n_idle:
            return (k + 1) % self.n_idle
        return self.n_idle + (k - self.n_idle + 1) % self.n_speak

    def speaking(self, downscale=1):
        """MuseTalk's renderer takes its frames here, in place of BackgroundStore.get_frame."""
        with self.lock:
            if self.at < self.n_idle:
                i = self.at
                self.at = self.n_idle + int(self.to_speak[i])
                self.cut = True
                log.info("talking: listening frame %d -> talking %d (cost %.2f)",
                         i, self.at - self.n_idle, float(self.cost_in[i]))
            else:
                self.at = self._next(self.at)
            self.quiet = 0
            self.spoke = time.monotonic()
            k = self.at
        frame = self.pool[k]
        if downscale > 1:
            h, w = frame.shape[:2]
            small = cv2.resize(frame, (w // downscale, h // downscale), interpolation=cv2.INTER_AREA)
            frame = cv2.resize(small, (w, h), interpolation=cv2.INTER_LINEAR)
        return frame, k

    def listening(self):
        """The frame to show while nothing is being said, and whether it is a cut; (None, False)
        just after the renderer took a frame (a sentence may be starting)."""
        with self.lock:
            if self.at >= self.n_idle:
                if time.monotonic() - self.spoke < 0.15:
                    return None, False
                self.quiet += 1
                j = self.at - self.n_idle
                if self.quiet >= HOLD_MAX or (self.quiet >= HOLD_MIN and self.cost[j] <= self.good):
                    self.at = int(self.to_idle[j])
                    self.cut = False
                    log.info("listening after %d quiet frames: talking %d -> listening %d (cost %.2f)",
                             self.quiet, j, self.at, float(self.cost[j]))
                    return self.pool[self.at], True
                cut, self.cut = self.cut, False  # cut to the talking body but cut off before it showed
                self.at = self._next(self.at)
                return self.pool[self.at], cut
            self.at = self._next(self.at)
            return self.pool[self.at], False

    def take_cut(self) -> bool:
        with self.lock:
            cut, self.cut = self.cut, False
            return cut


def build():
    t = time.time()
    kt.enable_async_submit()
    kt.enable_chin_margin(0.06)
    clip, n_idle = bodies_clip()
    s = MuseTalkSession(None, clip, fps=FPS, mlx_dir=MLX_DIR, mask_provider=kt.make_exact_mask())
    kt.disable_audio_prefix(s)
    s._windower = AudioWindower(sr=16000, fps=FPS, window_s=1.0, overlap_s=0.2)
    s._out_q_cap = config.RENDER_HIGH_WATER + 2 * config.BATCH
    kt.wait_precompute(s)
    kt.prefill_masks(s)
    # Trace the compiled graph once, so her first sentence does not pay for it.
    s.push_audio(np.zeros(16000, dtype=np.float32))
    deadline = time.time() + 60
    while time.time() < deadline:
        if s.get_output_frame() is None and s.idle and not s._windower.has_window():
            break
    s.interrupt()
    b = None
    pool = s._bg_store._bg_pool or []
    if n_idle and len(pool) > n_idle:
        b = Bodies(pool, n_idle)
        s._bg_store.get_frame = b.speaking
    elif n_idle:
        log.warning("only %d frames in the pool for %d listening + talking ones: one body", len(pool), n_idle)
    log.info("face ready in %.1f s (%s)", time.time() - t, LOOK)
    return s, b


session, bodies = build()
app = FastAPI()
viewer = None


@app.get("/health")
async def health():
    return {"ready": True, "fps": FPS, "latency_s": LATENCY, "look": os.path.basename(LOOK),
            "bodies": 2 if bodies else 1, "viewing": viewer is not None}


@app.websocket("/face")
async def face(ws: WebSocket):
    global viewer
    await ws.accept()
    if viewer is not None:
        try:
            await viewer.close(code=4000, reason="another viewer")
        except Exception:
            pass
    viewer = ws
    session.interrupt()
    last = None
    sent = {1: 0, 2: 0, 3: 0}
    slots = ws.query_params.get("v") == "2"
    unseen = []   # (slot, when sent) of frames the viewer has not said it got (v2)
    dropped = 0

    async def frames():
        nonlocal last, dropped
        start = time.monotonic()
        n = 0
        fade, fade_from = 0, None
        while True:
            n += 1
            await asyncio.sleep(max(0.0, start + n / FPS - time.monotonic()))
            kind, pts, cut, frame = 3, 0.0, False, None
            if session._out_q:
                frame, pts = session._out_q.popleft()
                kind = 2
                cut = bodies is not None and bodies.take_cut()
            elif session.idle:
                if bodies is not None:
                    frame, cut = bodies.listening()
                else:
                    frame, _ = session._bg_store.get_frame()
                kind = 1
            if frame is None:
                frame, kind = last, 3
            if frame is None:
                continue
            if cut and last is not None:
                fade, fade_from = FADE, last
            if fade and kind != 3:
                a = (FADE + 1 - fade) / (FADE + 1)
                frame = cv2.addWeighted(frame, a, fade_from, 1 - a, 0)
                fade -= 1
            last = frame
            if slots and unseen:
                waited = time.monotonic() - unseen[0][1]
                if waited > 2.0:      # no word for two seconds: not a viewer that answers
                    unseen.clear()
                elif waited > CONGESTED:
                    dropped += 1
                    continue
            ok, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
            if ok:
                sent[kind] += 1
                slot = start + n / FPS
                head = struct.pack("<Bdd", kind, float(pts), slot) if slots \
                    else struct.pack("<Bd", kind, float(pts))
                if slots:
                    unseen.append((slot, time.monotonic()))
                await ws.send_bytes(head + jpeg.tobytes())

    sender = asyncio.create_task(frames())
    log.info("viewer %s", ws.client)
    try:
        while True:
            msg = await ws.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if msg.get("bytes"):
                pcm = np.frombuffer(msg["bytes"], dtype="<i2").astype(np.float32) / 32768.0
                session.push_audio(pcm)
            elif msg.get("text"):
                body = json.loads(msg["text"])
                cmd = body.get("type")
                if cmd == "seen":
                    seen = float(body.get("slot", 0))
                    unseen[:] = [u for u in unseen if u[0] > seen]
                elif cmd == "end":
                    kt.flush_tail(session)
                elif cmd == "interrupt":
                    session.interrupt()
    except WebSocketDisconnect:
        pass
    finally:
        sender.cancel()
        session.interrupt()
        if viewer is ws:
            viewer = None
        log.info("viewer gone (idle %d, speaking %d, waiting %d frames; %d dropped on a full link)",
                 sent[1], sent[2], sent[3], dropped)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8105")), log_level="warning")
