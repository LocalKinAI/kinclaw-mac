#!/bin/zsh
# OpenMontage's remaining tools on the box — Jacky, 2026-10-04: Pygments, manim (no LaTeX), Python Playwright,
# torch + transformers + CLIP ViT-B/32.
export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH
set -u
cd ~/OpenMontage || exit 1
echo "$(date '+%F %T') OpenMontage tools: pygments, manim, playwright, torch, transformers, CLIP ViT-B/32 (~0.8 GB) — approved by Jacky" >> ~/.kinclaw/downloads.log
.venv/bin/python -m pip freeze > ~/kin-avatar/attic/openmontage/pip-freeze-before-20261004.txt
uv pip install --python .venv/bin/python pygments playwright torch transformers 2>&1 | tail -5
# manim needs pycairo, which builds from source here: cairo from Homebrew first (no cleanup, no auto-update)
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install cairo pkgconf
uv pip install --python .venv/bin/python manim 2>&1 | tail -3
.venv/bin/python -m pip freeze > ~/kin-avatar/attic/openmontage/pip-freeze-after-20261004.txt
echo "== changed besides additions:"; diff ~/kin-avatar/attic/openmontage/pip-freeze-before-20261004.txt ~/kin-avatar/attic/openmontage/pip-freeze-after-20261004.txt | grep "^<" || echo "none"
echo "== CLIP"
.venv/bin/python -c "from huggingface_hub import snapshot_download; print(snapshot_download('openai/clip-vit-base-patch32', allow_patterns=['*.json', '*.txt', 'pytorch_model.bin']))"
echo "== playwright chromium"
.venv/bin/python -m playwright install chromium 2>&1 | tail -3
echo "== done $(date '+%F %T')"
