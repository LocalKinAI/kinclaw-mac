"""A video lip-synced to a voice, offline: MuseTalk 1.5 on MLX with her mouth as tuned for kin-face
(kin_mouth.py) — OpenMontage's lip_sync (model "musetalk") on the LocalKin box, for
avatar-spokesperson and localization-dub.

Run in MuseTalk's venv (~/kin-avatar/musetalk/.venv), from ~/kin-avatar/face:
  python kin_lipsync.py --video V.mp4 --audio A.wav --out O.mp4 [--fps N]

The video is the body — looped from its start when shorter than the voice — and the mouth and jaw
come from the voice. The frame rate is the video's own unless given. This is
~/kin-avatar/musetalk/kin/kin_offline.py (MuseTalk's offline CLI with its two crashes fixed) with
the exact-mask cache, no audio prefix and the chin margin on, and a frame pool big enough to hold
a long video.
"""
import os
import sys

os.environ.setdefault("MT_SMART_CONV", "1")
os.environ.setdefault("FUSION_MUSETALK_GRAPH_PATTERNS", "0")
os.environ.setdefault("MT_BG_POOL_MAX_FRAMES", "3000")
os.environ.setdefault("MT_BG_POOL_BUDGET_MB", "8000")
sys.path.insert(0, os.path.expanduser("~/kin-avatar/musetalk/kin"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import imageio  # noqa: E402
import kin_mouth  # noqa: E402

kin_mouth.install()
import kin_offline  # noqa: E402

args = sys.argv[1:]
if "--mlx-dir" not in args:
    args += ["--mlx-dir", os.path.expanduser("~/kin-avatar/musetalk/weights-mlx-fp16")]
if "--fps" not in args and "--video" in args:
    reader = imageio.get_reader(args[args.index("--video") + 1])
    try:
        args += ["--fps", str(int(round(reader.get_meta_data().get("fps", 25))))]
    finally:
        reader.close()
for flag in ("--tuned", "--fix-prefix"):
    if flag not in args:
        args.append(flag)
if "--chin-margin" not in args:
    args += ["--chin-margin", "0.06"]
sys.argv = [sys.argv[0]] + args
sys.exit(kin_offline.main())
