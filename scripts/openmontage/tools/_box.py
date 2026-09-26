"""What the box's ComfyUI tools share: sizes, seeds and picture preparation.

The box is an M3 Ultra running ComfyUI with MiniMax H3 (ref2va), MiniMax Music 3
and Qwen-Image 2.1 already loaded on disk. These tools drive it through
OpenMontage's own ComfyUIClient, so they honour COMFYUI_SERVER_URL and the
per-capability overrides like every other ComfyUI tool here.
"""

from __future__ import annotations

import random
import tempfile
from pathlib import Path

from PIL import Image


def node(class_type: str, inputs: dict) -> dict:
    return {"class_type": class_type, "inputs": inputs}


def seed(value: int | None) -> int:
    return int(value) if value is not None else random.randint(1, 2**31 - 1)


def size_for(aspect_ratio: str | None, megapixels: float, multiple: int, width: int | None = None,
             height: int | None = None) -> tuple[int, int]:
    """A width and height of about `megapixels`, the given shape, in steps of
    `multiple` — or the width and height given, rounded to the steps."""
    if width and height:
        return (max(multiple, round(width / multiple) * multiple), max(multiple, round(height / multiple) * multiple))
    ratio = {"16:9": 16 / 9, "9:16": 9 / 16, "1:1": 1.0, "4:3": 4 / 3, "3:4": 3 / 4,
             "21:9": 21 / 9, "3:2": 1.5, "2:3": 2 / 3}.get((aspect_ratio or "16:9").strip(), 16 / 9)
    h = (megapixels * 1_000_000 / ratio) ** 0.5
    w = h * ratio
    return (max(multiple, round(w / multiple) * multiple), max(multiple, round(h / multiple) * multiple))


def filled(path: str | Path, width: int, height: int) -> Path:
    """The picture cut and scaled to fill exactly width × height, as a PNG in a
    temporary file: a pinned frame has to be the size the shot is filmed at."""
    image = Image.open(path).convert("RGB")
    scale = max(width / image.width, height / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    left, top = (resized.width - width) // 2, (resized.height - height) // 2
    out = Path(tempfile.mkstemp(suffix=".png", prefix="om-pin-")[1])
    resized.crop((left, top, left + width, top + height)).save(out)
    return out


def as_png(path: str | Path) -> Path:
    """Any picture as a PNG ComfyUI's LoadImage will take."""
    source = Path(path)
    if source.suffix.lower() == ".png":
        return source
    out = Path(tempfile.mkstemp(suffix=".png", prefix="om-ref-")[1])
    Image.open(source).convert("RGB").save(out)
    return out
