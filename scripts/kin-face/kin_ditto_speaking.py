"""Ditto's speaking body: her head, her eyes (and, with `face`, her brows) moved by a voice, her
mouth held as it is in the photograph.

kin-face shows this body while she speaks and the quiet one (Ditto on faint noise) while she does
not — what HeyGen and its kind do with filmed footage: a person who talks moves her head with the
words, one who listens hardly does. MuseTalk draws the mouth from her own voice over either; a
mouth that moved in the body as well would show round the edges of MuseTalk's, so the lip
keypoints stay the photograph's.

Run in ditto-talkinghead with its Python 3.12 venv:
  python kin_ditto_speaking.py <cfg.pkl> <photo> <speech.wav> <out.mp4> <crop_scale> [head|face]
    head  the head, the gaze and the blinks from the voice (Ditto's own choice for a photo)
    face  every keypoint but the lips: the brows and cheeks too
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.getcwd())
from inference import resolve_device, run  # noqa: E402
from stream_pipeline_offline import StreamSDK  # noqa: E402
from core.atomic_components import motion_stitch as ms  # noqa: E402
from kin_conv3d_as_2d import swap  # noqa: E402

cfg, image, audio, out, scale = sys.argv[1:6]
mode = sys.argv[6] if len(sys.argv) > 6 else "head"
LIP = [6, 12, 14, 17, 19, 20]

_setup = ms.MotionStitch.setup


def setup(self, *a, **k):
    # Ditto mixes each frame's expression as driven*a1 + photo*a2 + eye_delta*a3 (per keypoint).
    _setup(self, *a, **k)
    lip = np.zeros((21, 3), np.float32)
    lip[LIP] = 1
    lip = lip.reshape(1, -1)
    a3 = self.fix_exp_a3 if isinstance(self.fix_exp_a3, np.ndarray) else 0
    if mode == "face":
        self.fix_exp_a1 = (1 - lip) * (1 - a3)
        self.fix_exp_a2 = lip + a3 * (1 - lip)
    else:
        self.fix_exp_a1 = self.fix_exp_a1 * (1 - lip)
        self.fix_exp_a2 = self.fix_exp_a2 * (1 - lip) + lip
    if isinstance(self.fix_exp_a3, np.ndarray):
        self.fix_exp_a3 = self.fix_exp_a3 * (1 - lip)


ms.MotionStitch.setup = setup

sdk = StreamSDK(cfg, "./checkpoints/ditto_pytorch", device=resolve_device("auto"))
warp = sdk.warp_f3d.warp_net
if warp.model_type == "pytorch":
    swap(warp.model)  # its 7x7x7 Conv3d as seven Conv2d: 583 -> 63 ms a frame here
run(sdk, audio, image, out, more_kwargs={"setup_kwargs": {"crop_scale": float(scale)}, "run_kwargs": {}})
