#!/bin/zsh
# OpenMontage's own avatar and face tools on the box — Jacky, 2026-10-04: 「两个都要」 (mediapipe in its
# own env) and 「也装 SadTalker 和 Wav2Lip」. Sources: the download links on each project's GitHub page.
export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH
set -u
echo "$(date '+%F %T') talkers setup: SadTalker checkpoints (~2.5 GB), Wav2Lip GAN + s3fd (~0.52 GB), py3.10 env (~0.3 GB), mediapipe 0.10.21 env (~0.2 GB) — approved by Jacky" >> ~/.kinclaw/downloads.log
get() {
  mkdir -p "$(dirname "$2")"
  if [ -s "$2" ]; then echo "have $2"; return 0; fi
  curl -L --fail --retry 3 -C - -s -S -o "$2.part" "$1" && mv "$2.part" "$2" && echo "got $2 $(du -h "$2" | cut -f1)"
}
cd ~/kin-avatar/sadtalker || exit 1
R=https://github.com/OpenTalker/SadTalker/releases/download/v0.0.2-rc
for f in mapping_00109-model.pth.tar mapping_00229-model.pth.tar SadTalker_V0.0.2_256.safetensors SadTalker_V0.0.2_512.safetensors; do
  get "$R/$f" "checkpoints/$f"
done
get https://github.com/xinntao/facexlib/releases/download/v0.1.0/alignment_WFLW_4HG.pth gfpgan/weights/alignment_WFLW_4HG.pth
get https://github.com/xinntao/facexlib/releases/download/v0.1.0/detection_Resnet50_Final.pth gfpgan/weights/detection_Resnet50_Final.pth
get https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth gfpgan/weights/GFPGANv1.4.pth
get https://github.com/xinntao/facexlib/releases/download/v0.2.2/parsing_parsenet.pth gfpgan/weights/parsing_parsenet.pth
cd ~/kin-avatar/wav2lip || exit 1
get https://www.adrianbulat.com/downloads/python-fan/s3fd-619a316812.pth face_detection/detection/sfd/s3fd.pth

echo "== env for SadTalker and Wav2Lip (py3.10)"
cd ~/kin-avatar
[ -x talkers/.venv/bin/python ] || uv venv -q --python 3.10 talkers/.venv
uv pip install -q --python talkers/.venv/bin/python torch==2.1.2 torchvision==0.16.2 numpy==1.23.4 scipy==1.10.1 \
  librosa==0.9.2 resampy==0.3.1 "numba<0.57" face_alignment==1.3.5 imageio==2.19.3 imageio-ffmpeg==0.4.7 pydub==0.25.1 \
  kornia==0.6.8 tqdm yacs==0.1.8 pyyaml joblib==1.1.0 scikit-image==0.19.3 facexlib==0.3.0 av safetensors \
  opencv-python gdown addict future lmdb yapf requests Pillow tb-nightly "setuptools<80" wheel && echo "env: base ok"
# torch and torchvision pinned again here: left free, gfpgan pulled torch 2.14 / torchvision 0.29, which
# dropped the functional_tensor module basicsr imports (and torch >= 2.6 loads weights_only).
# setuptools < 80: librosa 0.9 still imports pkg_resources.
uv pip install -q --python talkers/.venv/bin/python --no-build-isolation basicsr==1.4.2 gfpgan \
  torch==2.1.2 torchvision==0.16.2 "setuptools<80" && echo "env: basicsr gfpgan ok"

echo "== Wav2Lip GAN weights (Google Drive, linked from its README)"
mkdir -p wav2lip/checkpoints
[ -s wav2lip/checkpoints/wav2lip_gan.pth ] || talkers/.venv/bin/gdown -q 15G3U08c8xsCkOqQxE38Z2XXDnPcOptNk -O wav2lip/checkpoints/wav2lip_gan.pth
ls -la wav2lip/checkpoints/
# Its README's weights are TorchScript now, and the box has no CUDA: patches/wav2lip-mps-torchscript.patch
(cd wav2lip && git apply ~/kin-avatar/wav2lip-mps-torchscript.patch 2>/dev/null || true)

echo "== mediapipe 0.10.21 in its own env (py3.12)"
[ -x mediapipe/.venv/bin/python ] || uv venv -q --python 3.12 mediapipe/.venv
uv pip install -q --python mediapipe/.venv/bin/python mediapipe==0.10.21 && mediapipe/.venv/bin/python -c "import mediapipe as mp; print('mediapipe', mp.__version__, 'solutions', hasattr(mp, 'solutions'))"
du -sh sadtalker wav2lip talkers mediapipe
echo "== done $(date '+%F %T')"
