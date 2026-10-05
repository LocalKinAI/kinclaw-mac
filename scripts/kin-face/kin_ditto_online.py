"""Ditto through its online (streaming) pipeline on the box, timed: can it keep up with speech?

The upstream inference.py always builds the offline SDK, whose audio-to-motion worker
takes one whole feature and stops, so --online_mode there renders five frames. This
uses stream_pipeline_online.StreamSDK with the same chunking (3, 5, 2): 200 ms of new
audio per step, 120 ms looked back, 80 ms ahead.
Usage: python kin_ditto_online.py <cfg_pkl> <image> <audio.wav> <out.mp4> [--paced]
"""
import math, os, sys, threading, time
import librosa, numpy as np, torch
sys.path.insert(0, os.getcwd())
from inference import resolve_device
from stream_pipeline_online import StreamSDK

cfg, image, audio_path, out = sys.argv[1:5]
paced = "--paced" in sys.argv
device = resolve_device("auto")
t0 = time.time()
sdk = StreamSDK(cfg, "./checkpoints/ditto_pytorch", device=device)
print(f"loaded on {device} in {time.time() - t0:.1f} s", flush=True)

# PyTorch's MPS backend has one command queue and is not safe to drive from several
# threads at once ("A command encoder is already encoding to this command buffer"):
# the online pipeline's workers take turns on the GPU, each finishing its work first.
gpu = threading.Lock()
spent = {}
def serialize(obj):
    cls = type(obj)
    original = cls.__call__
    def locked(self, *a, **k):
        with gpu:
            t = time.time()
            out = original(self, *a, **k)
            if device == "mps":
                torch.mps.synchronize()
            n, total = spent.get(cls.__name__, (0, 0.0))
            spent[cls.__name__] = (n + 1, total + time.time() - t)
            return out
    cls.__call__ = locked
for name in ("audio2motion", "motion_stitch", "warp_f3d", "decode_f3d"):
    serialize(getattr(sdk, name))
t1 = time.time()
sdk.setup(image, out)
print(f"setup (source registered) {time.time() - t1:.1f} s", flush=True)
audio, _ = librosa.core.load(audio_path, sr=16000)
num_f = math.ceil(len(audio) / 16000 * 25)
sdk.setup_Nd(N_d=num_f, fade_in=-1, fade_out=-1, ctrl_info={})

# Count frames as the writer receives them.
frames = []
put = sdk.writer_queue.put
def counting_put(item, *a, **k):
    frames.append(time.time())
    return put(item, *a, **k)
sdk.writer_queue.put = counting_put

chunksize = (3, 5, 2)
audio = np.concatenate([np.zeros((chunksize[0] * 640,), dtype=np.float32), audio], 0)
split_len = int(sum(chunksize) * 0.04 * 16000) + 80
start = time.time()
for n, i in enumerate(range(0, len(audio), chunksize[1] * 640)):
    if paced:  # feed at the speed of speech, as a live call would
        time.sleep(max(0, start + n * chunksize[1] * 0.04 - time.time()))
    chunk = audio[i:i + split_len]
    if len(chunk) < split_len:
        chunk = np.pad(chunk, (0, split_len - len(chunk)), mode="constant")
    sdk.run_chunk(chunk, chunksize)
fed = time.time() - start
sdk.close()
total = time.time() - start
speech = len(audio) / 16000
print(f"speech {speech:.1f} s, frames {len(frames)} (expected {num_f}), fed in {fed:.1f} s, all frames in {total:.1f} s", flush=True)
if len(frames) > 30:
    gaps = np.diff(frames[10:])
    print(f"steady {1 / gaps.mean():.1f} fps (median gap {np.median(gaps) * 1000:.0f} ms); first frame {frames[0] - start:.2f} s after the first chunk", flush=True)
for name, (n, total) in spent.items():
    print(f"{name}: {n} calls, {total / max(1, n) * 1000:.0f} ms each, {total:.1f} s in all", flush=True)
os.system(f'ffmpeg -loglevel error -y -i "{sdk.tmp_output_path}" -i "{audio_path}" -map 0:v -map 1:a -c:v copy -c:a aac "{out}"')
print(out)
