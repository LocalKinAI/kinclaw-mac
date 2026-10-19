"""Her mouth as QuickTalk draws it — kin-face's mouth (server.py) since 2026-10-18.

QuickTalk is OpenTalking's realtime lip-sync model (github.com/datascale-ai/opentalking, its code
Apache-2.0; the weights, HF datascale-ai/quicktalk, state no licence and find faces with InsightFace's
buffalo_l, which is non-commercial: fine for her, not for a product). Beside MuseTalk on the same body
and voice its teeth and lips look photographed where MuseTalk's teeth were a white smear (Jacky:
「好太多了」). It runs in OpenTalking's own virtualenv (~/opentalking/.venv, torch on MPS), so server.py
re-execs itself there.

Each frame: the voice's HuBERT features from that frame's moment on (0.2 s) and the body frame the walk
is on go through the model, and the face it draws is pasted back into that body frame. The body clip is
used at its own 20 fps — OpenTalking converts every template to 25, and at 20 the mouth was the same
(2026-10-18) while 20 frames a second is what the Wi-Fi to the Mac carries.

A clip of her voice comes whole; its frames are drawn at once (28 a second on the M3 Ultra, warm) and
each is handed out at its own time — when the clip came, plus `latency`, plus its place in the clip —
since QuickTalk has a clip's first frame ready about 0.2 s after it comes, before the Mac plays it.

Every body frame is prepared once at start (her face found — cached on disk — and its paste-back
masks), then drawn once in the background while she is quiet: the GPU compiles its kernels per face
size, and a body frame drawn for the first time took four times as long (6 frames a second, 28 warm).
"""
import collections
import logging
import os
import threading
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from kornia.geometry.transform import warp_affine
from opentalking.models.quicktalk.runtime import RealtimeV3Worker

log = logging.getLogger("kin-quicktalk")

ASSETS = Path(os.environ.get("QUICKTALK_ASSETS", "~/opentalking/models/quicktalk")).expanduser()
SR = 16000
FADE_IN, FADE_OUT = 2, 3  # frames over which the drawn mouth comes in at a clip's start and goes at its end
QUIET_RESET = 2.0         # seconds of quiet after which the model's memory of her mouth (its LSTM) starts afresh
# HuBERT hears each clip padded to whole seconds, and every length up to WARM_S is heard once at start:
# the first clips of a fresh server took 0.3-0.5 s for their features (0.17 later), and their first
# frames were late.
WARM_S = 20


class _Worker(RealtimeV3Worker):
    """QuickTalk's realtime worker on her body clip at the clip's own frame rate, keeping less per frame:
    QuickTalk holds the face's region of each frame and two masks over it as three-channel float32 on
    the GPU — 31 MB a frame for her 1024x1312 body, 25 GB for both bodies. The masks as one float16
    channel and the region as uint8 are 6 MB."""

    def _ensure_25fps(self, video_path, workdir, max_seconds):
        return video_path

    def _build_fast_restore_context(self, frame, face, coords, affine):
        c = super()._build_fast_restore_context(frame=frame, face=face, coords=coords, affine=affine)
        c.hard_mask_roi_3d = c.hard_mask_roi_3d[0:1].to(torch.float16).contiguous()
        c.soft_mask_roi_3d = c.soft_mask_roi_3d[0:1].to(torch.float16).contiguous()
        c.frame_roi_t = c.frame_roi_t.to(torch.uint8).contiguous()
        c.face = None                                   # the crop is in face_input already
        c.face_input = c.face_input.astype(np.float16)  # an image: float16 holds it (the model gets float32)
        self._built = getattr(self, "_built", 0) + 1
        if self._built % 32 == 0:
            torch.mps.empty_cache()
        return c

    def fast_restore_img(self, context, patch_t, base_frame=None, paste_weight=None):
        x0, y0, x1, y1 = context.roi
        restorer = self.v2.image_processor.restorer
        face = warp_affine(patch_t.unsqueeze(0), context.inv_affine_roi, (y1 - y0, x1 - x0), mode="bilinear",
                           padding_mode="fill", fill_value=restorer.fill_value).squeeze(0)
        face = face.clamp(0, 1) * 255.0
        soft = context.soft_mask_roi_3d.float()
        if paste_weight is not None:
            soft = soft * paste_weight
        roi = soft * (context.hard_mask_roi_3d.float() * face) + (1.0 - soft) * context.frame_roi_t.float()
        out = context.frame.copy()
        out[y0:y1, x0:x1] = roi.permute(1, 2, 0).contiguous().to(torch.uint8).cpu().numpy()
        return out


class QuickTalkMouth:
    """kin-face's mouth: clips of her voice in (float32, 16 kHz), frames out, each at its time.

    `walk` (server.py's Bodies) gives the body frame each drawn frame goes on."""

    def __init__(self, clip, latency):
        t = time.time()
        self.w = _Worker(asset_root=ASSETS, template_video=Path(clip), face_cache_dir=ASSETS / ".face_cache_v3",
                         device="mps", output_transform="bgr", scale_h=1.6, scale_w=3.6, resolution=256,
                         neck_fade_start=0.72, neck_fade_end=0.88, model_backend="auto")
        self.w.face_det_results = None  # what the contexts were built from
        torch.mps.empty_cache()
        self.fps = int(round(self.w.fps))
        self.pool = self.w.frames
        self.latency = latency
        self.walk = None
        self._lock = threading.Lock()
        self._wake = threading.Event()
        self._clips = collections.deque()  # (samples, when it came, generation)
        self._out = collections.deque()    # (due, frame, pts)
        self._gen = 0
        self._busy = False
        self._fresh = True
        self._next_due = 0.0               # the earliest the next clip's first frame may be shown
        self._last_due = -1e9              # when the last clip's frames end
        self._voice = 0.0                  # seconds of her voice taken in: each frame's pts
        self._state = self.w.make_state()
        self._unwarmed = list(range(len(self.pool)))
        log.info("QuickTalk ready in %.1f s: %d body frames at %d fps, %.1f GB on the GPU", time.time() - t,
                 len(self.pool), self.fps, torch.mps.current_allocated_memory() / 1e9)
        threading.Thread(target=self._run, name="quicktalk", daemon=True).start()

    # -- what server.py calls

    def push(self, samples):
        with self._lock:
            self._clips.append((samples, time.monotonic(), self._gen))
        self._wake.set()

    def end(self):
        """Nothing waits for more: every clip is drawn whole as it comes."""

    def interrupt(self):
        with self._lock:
            self._gen += 1
            self._clips.clear()
            self._out.clear()
            self._next_due = 0.0
            self._fresh = True

    def take(self, now):
        """The drawn frame whose time has come — the newest, when the sender fell behind — or None."""
        with self._lock:
            while len(self._out) > 1 and self._out[1][0] <= now:
                self._out.popleft()
            if self._out and self._out[0][0] <= now:
                _, frame, pts = self._out.popleft()
                return frame, pts
        return None

    @property
    def idle(self):
        with self._lock:
            return not (self._clips or self._busy or self._out)

    # -- the drawing thread

    def _run(self):
        warm_state = self.w.make_state()
        warm_rep = np.zeros((10, 1024), dtype=np.float32)
        warm_start = time.time()
        with torch.inference_mode():
            for seconds in range(1, WARM_S + 1):
                self.w.v2.extract_representations_pcm(np.zeros(seconds * SR, dtype=np.float32), SR)
        torch.mps.empty_cache()  # the GPU allocator keeps what the longest one needed otherwise
        log.info("voice features warmed for clips up to %d s (%.0f s)", WARM_S, time.time() - warm_start)
        while True:
            with self._lock:
                job = self._clips.popleft() if self._clips else None
                self._busy = job is not None
            if job is not None:
                try:
                    self._draw(*job)
                except Exception:
                    log.exception("QuickTalk could not draw a clip")
                finally:
                    with self._lock:
                        self._busy = False
                        done = not self._clips
                    if done:
                        torch.mps.empty_cache()
                continue
            if self._unwarmed:
                k = self._unwarmed.pop()
                try:
                    with torch.inference_mode():
                        self._frame(self.w.restore_contexts[k], warm_rep, 1.0, warm_state)
                except Exception:
                    log.exception("QuickTalk could not draw body frame %d", k)
                if not self._unwarmed:
                    torch.mps.empty_cache()
                    log.info("every body frame drawn once (%.0f s): her mouth is at full speed",
                             time.time() - warm_start)
                continue
            self._wake.wait(1.0)
            self._wake.clear()

    def _features(self, samples):
        """One feature window per frame of the clip (QuickTalk's prepare_pcm_features, on whole seconds)."""
        n = max(1, int(len(samples) / SR * self.fps))
        padded = np.zeros(int(np.ceil(len(samples) / SR)) * SR or SR, dtype=np.float32)
        padded[:len(samples)] = samples
        with torch.inference_mode():
            heard = self.w.v2.extract_representations_pcm(padded, SR)
        return self.w.v2.build_rep_chunks(heard, n, self.fps)

    def _draw(self, samples, came, gen):
        t0 = time.monotonic()
        reps = self._features(samples)
        n = len(reps)
        with self._lock:
            if gen != self._gen:
                return
            start = max(came + self.latency, self._next_due)
            if self._fresh or start - self._last_due > QUIET_RESET:
                self._state = self.w.make_state()
                self._fresh = False
            self._next_due = self._last_due = start + n / self.fps
            voice0 = self._voice
            self._voice += len(samples) / SR
        features = time.monotonic() - t0
        first, late = None, 0
        with torch.inference_mode():
            for i, rep in enumerate(reps):
                if gen != self._gen:
                    return
                k = self.walk.speaking()[1] if self.walk is not None else i % len(self.pool)
                alpha = min(1.0, (i + 1) / (FADE_IN + 1), (n - i) / (FADE_OUT + 1))
                frame = self._frame(self.w.restore_contexts[k], rep, alpha, self._state)
                due = start + i / self.fps
                now = time.monotonic()
                if first is None:
                    first = now - came
                late += now > due
                with self._lock:
                    if gen != self._gen:
                        return
                    self._out.append((due, frame, voice0 + (i + 1) / self.fps))
        log.info("clip %.1f s: %d frames in %.2f s (features %.2f), first %.2f s after it came, shown from %.2f s; %d late",
                 len(samples) / SR, n, time.monotonic() - t0, features, first or 0.0, start - came, late)

    def _frame(self, ctx, rep, alpha, state):
        g, state.hn, state.cn = self.w.v2.run_model(rep[None, ...].astype(np.float32), ctx.face_input,
                                                    state.hn, state.cn)
        patch = torch.from_numpy(g.squeeze(0)).to(device=self.w.v2.device, dtype=self.w.v2.dtype)
        patch = self.w.v2.transform_output_torch(patch)
        x1, y1, x2, y2 = ctx.coords
        patch = F.interpolate(patch.unsqueeze(0), size=(int(y2 - y1), int(x2 - x1)), mode="bicubic",
                              align_corners=False, antialias=True).squeeze(0)
        weight = None if alpha >= 1.0 else torch.full((1, 1, 1), float(alpha), device=patch.device)
        return self.w.fast_restore_img(ctx, patch, paste_weight=weight)
