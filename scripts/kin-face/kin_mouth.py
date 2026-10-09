"""Her mouth as MuseTalk draws it, tuned on the box (2026-10-02) — for kin-face (server.py) and for
the offline lip-sync OpenMontage uses (kin_lipsync.py). `install()` patches MuseTalk once.

The mouth and the jaw are MuseTalk's; the cheeks, the nose and the rest stay the body's. MuseTalk
draws the lower face at 256 px, and pasted over the whole lower face of a 1024x1312 body (a face
about 450 px wide) the cheeks, chin and nose went soft below a sharp upper face (「图片太low了」).
Cut down to the lips alone, the mouth opened while the chin stayed shut (「对口型不自然」). So: the
lips with room round them, and the skin below them as wide as the mouth — the chin and jaw, which
drop when she speaks — from BiSeNet's labels, feathered.

How far the mouth opens: over a closed-mouth body MuseTalk's mouth keeps close to the body's own
and she mumbles. MuseTalk's bbox_shift moves the line its crop is centred on — measured here the
opposite way round from its authors' account: +24 px closed her mouth further, -24 opened it a
little more (FACE_BBOX_SHIFT). It has to be set before a session measures the body.

And the mouth itself sharper (「还是有点糊，再试试锐化」): MuseTalk's 256 px patch is enlarged to the
face with a cubic filter instead of a linear one, given an unsharp mask scaled to that enlargement
(FACE_SHARPEN), and in the feathered ring round it the body's own skin texture (its detail above
a 1.6 px blur, FACE_DETAIL) is laid back, so the patch does not read as a smooth smear in a face
with pores. The middle — the lips, whose shape changes — gets none of that texture.
"""
import logging
import os

import cv2
import numpy as np

import musetalk_mlx.face.crop as mt_crop
import musetalk_mlx.face.mask as mt_mask
import musetalk_mlx.pipeline.blending as mt_blend
from musetalk_mlx import config

log = logging.getLogger("kin-mouth")

_LIPS = (11, 12, 13)
BBOX_SHIFT = int(os.environ.get("FACE_BBOX_SHIFT", "-24"))
SHARPEN = float(os.environ.get("FACE_SHARPEN", "0.6"))
DETAIL = float(os.environ.get("FACE_DETAIL", "0.8"))
_installed = False
_crop_init = mt_crop.FaceCropper.__init__


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


def _shifted_init(self, size=config.PATCH, upperbondrange=0):
    _crop_init(self, size, upperbondrange or BBOX_SHIFT)


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


def install():
    """The mouth+jaw mask, the crop line and the sharper paste, into MuseTalk (once)."""
    global _installed
    if _installed:
        return
    mt_mask.FaceParseMask.mouth_mask = _mouth_mask
    mt_crop.FaceCropper.__init__ = _shifted_init
    mt_blend._paste_alpha = _sharp_paste_alpha
    _installed = True
