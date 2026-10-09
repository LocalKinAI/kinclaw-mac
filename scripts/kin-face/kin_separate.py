"""The voice out of a song, for lip-sync: Demucs (htdemucs, Meta, MIT) on the LocalKin box — vocals.wav
(what the face is driven by) and accompaniment.wav (everything else) in the folder given.

A song's accompaniment moves a lip-sync model's mouth too — it sings through the solo — so the
face is driven by the voice alone and the whole song is laid under the finished video.

Run in its own venv (~/kin-avatar/demucs/.venv: torch 2.14, demucs 4.1):
  python kin_separate.py <song> <out_dir>
"""
import os
import subprocess
import sys
import time

import numpy as np
import soundfile as sf
import torch
from demucs.apply import apply_model
from demucs.pretrained import get_model

source, folder = sys.argv[1], sys.argv[2]
os.makedirs(folder, exist_ok=True)
began = time.time()
model = get_model("htdemucs")
model.eval()
rate = model.samplerate
# Any format ffmpeg reads, as float stereo at the model's rate.
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", source, "-f", "f32le", "-ac", "2", "-ar", str(rate), "-"],
                     capture_output=True, check=True).stdout
audio = np.frombuffer(raw, dtype="<f4").reshape(-1, 2).T.copy()
wav = torch.from_numpy(audio)
ref = wav.mean(0)
mean, std = ref.mean(), ref.std() + 1e-8
device = "mps" if torch.backends.mps.is_available() else "cpu"
try:
    with torch.no_grad():
        stems = apply_model(model, ((wav - mean) / std)[None], device=device, split=True, overlap=0.25)[0]
except Exception as exc:  # an op MPS lacks: the CPU, slower but sure
    print(f"{device} failed ({exc}); on the CPU", file=sys.stderr)
    device = "cpu"
    with torch.no_grad():
        stems = apply_model(model, ((wav - mean) / std)[None], device=device, split=True, overlap=0.25)[0]
stems = stems * std + mean
vocals = stems[model.sources.index("vocals")]
rest = sum(stems[i] for i, name in enumerate(model.sources) if name != "vocals")
sf.write(os.path.join(folder, "vocals.wav"), vocals.T.numpy(), rate)
sf.write(os.path.join(folder, "accompaniment.wav"), rest.T.numpy(), rate)
print(f"separated {audio.shape[1] / rate:.1f} s on {device} in {time.time() - began:.1f} s -> {folder}")
