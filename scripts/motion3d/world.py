"""Vision's 3D joints -> a movement in a world. Third version.

  1. The pose: each frame against the last one believed — as it is, depth-mirrored, left and
     right swapped, or both — the nearest taken if a body could have got there, else the frame
     is dropped and filled in from its neighbours. (Side-on, front and back look alike.)
  2. Where she is: Vision's own estimate of where the pelvis is. Sideways and in height it is
     steady to millimetres; in depth it wanders by centimetres, so depth is averaged over most
     of a second. Chaining feet together step by step — the first idea — turned a sidestep
     into a metre's walk away from the camera, because it is the *relative depth* of the feet
     that one camera sees worst.
  3. Feet on the ground stay put, as a correction to (2) and no more: a planted foot's drift
     is taken out of the whole body, smoothly, and with both planted a small, slow turn is
     allowed so that both stay."""
import json, sys
import numpy as np

src, out = sys.argv[1], sys.argv[2]
data = json.load(open(src))
names = ["root", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle", "spine", "centerShoulder",
         "centerHead", "topHead", "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist"]
SWAP = [names.index(n.replace("left", "R_").replace("right", "left").replace("R_", "right")) for n in names]
LA, RA, TOP = names.index("leftAnkle"), names.index("rightAnkle"), names.index("topHead")
N = len(data["frames"])
raw, where = [None] * N, np.full((N, 3), np.nan)
for i, f in enumerate(data["frames"]):
    if not f: continue
    m = np.array(f["camera"]).T
    raw[i] = np.array([m[:3, :3] @ np.array(f["local"][n]) for n in names])       # pelvis-centred; x right, y up, z toward the camera
    where[i] = m[:3, 3]                                                          # the pelvis, in the camera's space

# ---- 1. the pose: believe, disguise, or drop
PER_FRAME = 0.055
kept, how = [None] * N, [""] * N
last, last_i = None, None
for i, p in enumerate(raw):
    if p is None: how[i] = "missing"; continue
    if last is None: kept[i], how[i], last, last_i = p, "as is", p, i; continue
    mirrored = p * np.array([1, 1, -1])
    options = {"as is": p, "mirrored": mirrored, "swapped": p[SWAP], "both": mirrored[SWAP]}
    dist = {k: np.linalg.norm(v - last, axis=1).mean() for k, v in options.items()}
    best = min(dist, key=dist.get); gap = i - last_i
    if dist[best] <= PER_FRAME * min(gap, 6) + 0.03: kept[i], how[i], last, last_i = options[best], best, options[best], i
    elif gap > 30: kept[i], how[i], last, last_i = p, "re-anchored", p, i
    else: how[i] = "dropped"
good = [i for i in range(N) if kept[i] is not None]
def fill(values, ok):
    ok = np.array(ok); xs = np.arange(len(values))
    return np.stack([np.interp(xs, xs[ok], values[ok][:, c]) for c in range(values.shape[1])], axis=1)
flat = np.stack([k.reshape(-1) if k is not None else np.zeros(len(names) * 3) for k in kept])
Q = fill(flat, [k is not None for k in kept]).reshape(N, len(names), 3)
from collections import Counter
print("frames:", dict(Counter(how)))

# ---- 2. where she is: a frame whose pose was not believed does not say where she is either
trusted = [how[i] in ("as is", "mirrored", "swapped", "both", "re-anchored") for i in range(N)]
T = fill(where, trusted)
def mean(v, k): return np.stack([v[max(0, i - k):i + k + 1].mean(axis=0) for i in range(len(v))])
def median(v, k): return np.stack([np.median(v[max(0, i - k):i + k + 1], axis=0) for i in range(len(v))])
T[:, :2] = mean(T[:, :2], 2)
T[:, 2:] = mean(median(T[:, 2:], 6), 9)                 # depth: spikes out first, then most of a second's average
W = Q + T[:, None, :]

# to the stage's axes, and the old camera's tilt undone (about the camera, which is where the tilt was)
B = np.stack([W[:, :, 0], -W[:, :, 2], W[:, :, 1]], axis=2)
lean = (B[:12, TOP] - (B[:12, LA] + B[:12, RA]) / 2).mean(axis=0)
pitch = np.arctan2(lean[1], lean[2]); c, s_ = np.cos(pitch), np.sin(pitch)
B = B @ np.array([[1, 0, 0], [0, c, -s_], [0, s_, c]]).T
ANKLE = 0.09
B[:, :, 2] += ANKLE - np.percentile(np.minimum(B[:, LA, 2], B[:, RA, 2]), 10)      # the ground is where her feet mostly are

# ---- 3. planted feet, as a correction
gapz = mean((B[:, LA, 2] - B[:, RA, 2])[:, None], 2)[:, 0]
Ldown = Rdown = True; Lrun = Rrun = 0
lockL, lockR = B[0, LA, :2].copy(), B[0, RA, :2].copy()
shift, turn, support = np.zeros((N, 2)), np.zeros(N), []
REACH = 0.10
carried = np.zeros(2)                                   # the correction in force, so that a newly landed foot is locked where it IS seen to land
for i in range(N):
    Ls, Rs = gapz[i] < 0.06, gapz[i] > -0.06
    Lrun = 0 if Ls == Ldown else Lrun + 1; Rrun = 0 if Rs == Rdown else Rrun + 1
    if Lrun >= 3: Ldown, Lrun = Ls, 0
    if Rrun >= 3: Rdown, Rrun = Rs, 0
    if not Ldown: lockL = None
    if not Rdown: lockR = None
    l, r = B[i, LA, :2], B[i, RA, :2]
    # A lock that would drag the whole body more than a hand's breadth is a lock on a bad
    # estimate (the depth of a foot, side-on): let the foot go and lock it again where it is.
    if lockL is not None and np.linalg.norm(lockL - l - carried) > REACH: lockL = None
    if lockR is not None and np.linalg.norm(lockR - r - carried) > REACH: lockR = None
    if Ldown and lockL is None: lockL = l + carried
    if Rdown and lockR is None: lockR = r + carried
    if Ldown and Rdown:
        carried = ((lockL - l) + (lockR - r)) / 2
        now, was = l - r, lockL - lockR
        if np.linalg.norm(was) > 0.25:
            a = np.arctan2(was[1], was[0]) - np.arctan2(now[1], now[0]); a = (a + np.pi) % (2 * np.pi) - np.pi
            turn[i] = np.clip(a, -np.radians(12), np.radians(12))
        else: turn[i] = turn[i - 1] if i else 0
    elif Ldown: carried = lockL - l; turn[i] = turn[i - 1] if i else 0
    elif Rdown: carried = lockR - r; turn[i] = turn[i - 1] if i else 0
    carried = carried * 0.97                              # what the feet ask for fades: a slow slide shows less than a body dragged off its path
    shift[i] = carried; support.append(("L" if Ldown else "-") + ("R" if Rdown else "-"))
shift, turn = mean(shift, 3), mean(turn[:, None], 4)[:, 0]
for i in range(N):
    mid = (B[i, LA, :2] + B[i, RA, :2]) / 2
    cz, sz = np.cos(turn[i]), np.sin(turn[i])
    B[i, :, :2] = (B[i, :, :2] - mid) @ np.array([[cz, -sz], [sz, cz]]).T + mid + shift[i]

S_ = mean(B, 2)
S_[:, :, :2] -= (S_[0, LA, :2] + S_[0, RA, :2]) / 2
step = np.linalg.norm(S_[1:] - S_[:-1], axis=2).max(axis=1)
print("largest move of any joint between frames: %.3f m at frame %d" % (step.max(), step.argmax() + 1))
print("pelvis travels: sideways %.2f m, in depth %.2f m | correction applied: at most %.3f m, turn at most %.1f deg" % (
    np.ptp(S_[:, 0, 0]), np.ptp(S_[:, 0, 1]), np.linalg.norm(shift, axis=1).max(), np.degrees(np.abs(turn).max())))
print("support (every 8th frame):", " ".join(support[::8]))
json.dump({"fps": data["fps"], "names": names, "frames": S_.round(4).tolist()}, open(out, "w"))
