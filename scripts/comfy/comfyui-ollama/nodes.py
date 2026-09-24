"""ComfyUI nodes that think with the Ollama models already on the machine.

ComfyUI's own LLM templates load a language model's weights into ComfyUI —
another eight or thirty gigabytes, for a model Ollama next door is already
serving, with the cloud models besides. These nodes ask Ollama instead: text
in (and pictures, for a model that can see), text out, to wire into any
prompt input.

Which Ollamas: OLLAMA_HOSTS (comma-separated), else the lines of
~/.kinclaw/ollama-hosts, else this machine's. Models on the first host are
listed by name; on the others as "name @ host".
"""

from __future__ import annotations

import base64
import io
import json
import os
import re
import threading
import time
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

import comfy.model_management as mm


def _hosts() -> list[str]:
    listed = os.environ.get("OLLAMA_HOSTS", "")
    if not listed:
        f = Path.home() / ".kinclaw" / "ollama-hosts"
        if f.exists():
            listed = ",".join(line.strip() for line in f.read_text().splitlines() if line.strip() and not line.startswith("#"))
    hosts = [h.strip().rstrip("/") for h in listed.split(",") if h.strip()]
    return hosts or ["http://127.0.0.1:11434"]


def _get(url: str, timeout: float = 3.0, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read())


_catalog: tuple[float, dict[str, tuple[str, str, list[str]]]] | None = None
_refreshing = False


def _models() -> dict[str, tuple[str, str, list[str]]]:
    """label → (host, model, capabilities), embedding models left out. The last
    answer at once, a fresh one fetched in the background: ComfyUI's page waits
    for its node list, and this is asked every time the list is built."""
    global _catalog, _refreshing
    if _catalog is None:
        _catalog = (time.time(), _fetch_models())
    elif time.time() - _catalog[0] > 300 and not _refreshing:
        _refreshing = True
        def refresh():
            global _catalog, _refreshing
            try:
                _catalog = (time.time(), _fetch_models())
            finally:
                _refreshing = False
        threading.Thread(target=refresh, daemon=True).start()
    return _catalog[1]


def _fetch_models() -> dict[str, tuple[str, str, list[str]]]:
    from concurrent.futures import ThreadPoolExecutor
    found: dict[str, tuple[str, str, list[str]]] = {}
    for i, host in enumerate(_hosts()):
        try:
            names = [m["name"] for m in _get(host + "/api/tags", timeout=2).get("models", [])]
        except Exception:
            continue

        def caps_of(name):
            try:
                return name, _get(host + "/api/show", timeout=2, body={"model": name}).get("capabilities", [])
            except Exception:
                return name, ["completion"]

        with ThreadPoolExecutor(8) as pool:
            for name, caps in pool.map(caps_of, names):
                if "completion" not in caps:
                    continue
                label = name if i == 0 else f"{name} @ {host.split('://')[-1]}"
                found[label] = (host, name, caps)
    return found


def _labels(vision: bool = False) -> list[str]:
    models = _models()
    labels = [label for label, (_, _, caps) in models.items() if not vision or "vision" in caps]
    return sorted(labels, key=lambda l: (":cloud" in l, "@" in l, l)) or ["(no Ollama model found)"]


# What each task asks of the model. The same ideas the KinClaw film writer
# learned the hard way: concrete over abstract, the camera's words, the period
# with what must not appear, one continuous action for video.
TASKS = {
    "free": "",
    "image prompt": (
        "Rewrite the request as one dense paragraph, in English, for a photorealistic image model. 90 to 150 words. "
        "Cover in order: the camera (shot size, lens in mm, aperture, what is sharp and what falls away, height and "
        "angle, where the subject sits in the frame); the subject with its materials and textures; what is behind and "
        "around it; the light (source, direction, hard or soft, colour temperature, shadows, anything in the air); "
        "the grade (film stock, grain, palette, contrast). If it belongs to a time and place in history, say so and "
        "name what must not appear (modern clothing, plastic, printed text, power lines…). Describe only what a camera "
        "sees — no metaphors. Answer with the paragraph only."),
    "video prompt": (
        "Rewrite the request as a prompt for a video model that takes every word literally, in English, 40 to 90 "
        "words: one clear, continuous action large enough that the first and last frames plainly differ; what the "
        "camera does (or that it holds still); nothing new enters and there is no cut; end with the ambient sound. "
        "Answer with the prompt only."),
    "H3 video prompt (official guide)": "@h3",
    "translate to English": "Translate into natural English. Answer with the translation only.",
    "describe the image": (
        "Describe the image for someone who will recreate it with an image model: subject, materials, setting, light, "
        "framing, palette, style — concrete, in English, one paragraph. Answer with the description only."),
}

H3_GUIDE = "https://raw.githubusercontent.com/MiniMax-AI/MiniMax-H3/main/skills/h3-prompt-writing/references/base-en.txt"


def _h3_guide() -> str:
    """MiniMax's own prompting guide for H3, fetched once and kept — theirs to
    update, not copied into this pack."""
    cache = Path.home() / ".cache" / "comfyui-ollama" / "h3-base-en.txt"
    if cache.exists():
        return cache.read_text()
    with urllib.request.urlopen(H3_GUIDE, timeout=20) as response:
        text = response.read().decode()
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(text)
    return text


def _system(task: str, system: str) -> str:
    rule = TASKS.get(task, "")
    if rule == "@h3":
        rule = ("Write a MiniMax H3 text-to-video prompt in exactly the structure of this official guide (its field "
                "names, section order and timing notation), matching the requested length. Answer with the prompt "
                "only.\n<<<\n" + _h3_guide() + "\n>>>")
    return "\n\n".join(part for part in (system.strip(), rule) if part)


def _png64(image, index: int) -> str:
    array = (image[index].clamp(0, 1).cpu().numpy() * 255).round().astype(np.uint8)
    buffer = io.BytesIO()
    Image.fromarray(array).save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode()


class OllamaChat:
    DESCRIPTION = ("Ask an Ollama model — local or cloud, on this machine or another — and get its answer as text, "
                   "to wire into any prompt. Give it pictures if the model can see.")
    CATEGORY = "Ollama"
    RETURN_TYPES = ("STRING", "STRING")
    RETURN_NAMES = ("text", "thinking")
    FUNCTION = "run"

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "model": (_labels(),),
                "task": (list(TASKS),),
                "prompt": ("STRING", {"multiline": True, "default": ""}),
                "think": ("BOOLEAN", {"default": False, "tooltip": "Let a thinking model reason first (slower). Its reasoning comes out of the second output."}),
                "temperature": ("FLOAT", {"default": 0.7, "min": 0.0, "max": 2.0, "step": 0.05}),
                "seed": ("INT", {"default": 0, "min": 0, "max": 0xFFFFFFFF, "control_after_generate": True}),
            },
            "optional": {
                "system": ("STRING", {"multiline": True, "default": ""}),
                "context": ("STRING", {"forceInput": True, "tooltip": "More text for the model to work from, e.g. another node's output"}),
                "images": ("IMAGE",),
            },
        }

    def run(self, model, task, prompt, think, temperature, seed, system="", context=None, images=None):
        entry = _models().get(model)
        if entry is None:
            raise RuntimeError(f"Ollama has no {model!r} now; refresh the node list")
        host, name, caps = entry
        content = prompt if not context else f"{context}\n\n{prompt}".strip()
        message: dict = {"role": "user", "content": content or "(no text)"}
        if images is not None:
            if "vision" not in caps:
                seeing = ", ".join(_labels(vision=True)[:6])
                raise RuntimeError(f"{name} cannot see pictures. Models that can: {seeing}")
            message["images"] = [_png64(images, i) for i in range(min(images.shape[0], 8))]
        messages = [message]
        sys_text = _system(task, system)
        if sys_text:
            messages.insert(0, {"role": "system", "content": sys_text})
        body = {"model": name, "messages": messages, "stream": False,
                "options": {"temperature": temperature, "seed": seed}}
        if "thinking" in caps:
            body["think"] = bool(think)

        result: dict = {}

        def call():
            try:
                result["reply"] = _get(host + "/api/chat", timeout=900, body=body)
            except Exception as e:
                result["error"] = e

        worker = threading.Thread(target=call, daemon=True)
        worker.start()
        while worker.is_alive():
            worker.join(0.5)
            mm.throw_exception_if_processing_interrupted()
        if "error" in result:
            raise RuntimeError(f"Ollama ({name}): {result['error']}")
        said = result["reply"].get("message", {})
        text = said.get("content", "")
        thinking = said.get("thinking", "") or ""
        # Models that think out loud without the API's separate field.
        inline = re.search(r"<think>(.*?)</think>", text, flags=re.S)
        if inline:
            thinking = thinking or inline.group(1).strip()
            text = text.replace(inline.group(0), "")
        return (text.strip(), thinking.strip())


NODE_CLASS_MAPPINGS = {"OllamaChat": OllamaChat}
NODE_DISPLAY_NAME_MAPPINGS = {"OllamaChat": "Ollama · Chat"}
