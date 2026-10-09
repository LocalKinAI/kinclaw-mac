"""Ditto from a photograph and a voice: the whole face, lips included — OpenMontage's talking_head
(model "ditto") on the LocalKin box, for avatar-spokesperson.

Run in ditto-talkinghead with its Python 3.12 venv:
  python kin_ditto_talk.py <cfg.pkl> <photo> <speech> <out.mp4> [--crop-scale 2.3] [--expression 1.0] [--still]
    --crop-scale  how much of the photograph around the face Ditto re-renders (2.3 its default)
    --expression  how far the face moves from the photograph's (1 as Ditto drives it)
    --still       the head keeps the photograph's pose; only the face moves
    --pose        how far the head moves (1 as Ditto drives it; more for singing)

About 6.5 frames a second on the box's GPU with the warp's Conv3d done as Conv2d
(kin_conv3d_as_2d.py): a 30-second script in about two minutes.
"""
import argparse
import os
import sys

sys.path.insert(0, os.getcwd())
from inference import resolve_device, run  # noqa: E402
from stream_pipeline_offline import StreamSDK  # noqa: E402
from kin_conv3d_as_2d import swap  # noqa: E402

parser = argparse.ArgumentParser()
parser.add_argument("cfg")
parser.add_argument("image")
parser.add_argument("audio")
parser.add_argument("out")
parser.add_argument("--crop-scale", type=float, default=2.3)
parser.add_argument("--expression", type=float, default=1.0)
parser.add_argument("--still", action="store_true")
parser.add_argument("--pose", type=float, default=1.0)
args = parser.parse_args()

sdk = StreamSDK(args.cfg, "./checkpoints/ditto_pytorch", device=resolve_device("auto"))
warp = sdk.warp_f3d.warp_net
if warp.model_type == "pytorch":
    swap(warp.model)

setup = {"crop_scale": args.crop_scale}
# Ditto moves each key by (driven - first frame) * weight; a key left out keeps the photograph's.
if args.still:
    setup["use_d_keys"] = {"exp": args.expression}
elif args.expression != 1.0 or args.pose != 1.0:
    p = args.pose
    setup["use_d_keys"] = {"exp": args.expression, "pitch": p, "yaw": p, "roll": p, "t": p}
run(sdk, args.audio, args.image, args.out, more_kwargs={"setup_kwargs": setup, "run_kwargs": {}})
