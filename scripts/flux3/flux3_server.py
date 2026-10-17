#!/usr/bin/env python3
"""FLUX 3 Image Klein for the KinClaw app's 画 and 改, on the box.

It speaks the OllamaDiffuser API the app already uses for Qwen-Image:
  GET  /api/health
  POST /api/generate          JSON {prompt, width, height, seed?, steps?, upsample?}        -> PNG
  POST /api/generate/img2img  multipart: prompt, image (1st reference), images (2nd, 3rd…),
                              seed?, num_inference_steps?, upsample?                         -> PNG, image 1's size
One model serves both (mflux 0.23, MLX, bf16): drawing and editing share one denoiser, an edit only adds the
encoded references. It loads on the first request and is let go after KEEP idle seconds, so an idle server
holds no 37 GB.

FLUX 3 wants a full scene caption — framing, subjects with colours, materials and places, light, camera — and
gives generic pictures for a short request. A short drawing request, and every edit (whose caption must describe
the references with the change folded in), is first expanded by the box's own vision LLM (Ollama) with Black
Forest Labs' prompt-upsampler instructions (system_prompts.json of flux-3-image-klein-pup). A long caption, or one
that carries a box layout, goes as written; `upsample` true/false decides it instead. The caption used comes back
in the X-Flux-Caption header (base64 of UTF-8)."""
import argparse, base64, email.parser, email.policy, gc, io, json, os, re, tempfile, threading, time, traceback
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import mlx.core as mx
from huggingface_hub import hf_hub_download
from mflux.models.common.config import ModelConfig
from mflux.models.flux3.variants import Flux3KleinEdit

ap = argparse.ArgumentParser()
ap.add_argument("--host", default="0.0.0.0")
ap.add_argument("--port", type=int, default=8004)
ap.add_argument("--keep", type=int, default=600, help="seconds idle before the model is let go")
ap.add_argument("--llm", default="ornith-1.5:35b", help="Ollama vision model that writes the captions")
ap.add_argument("--ollama", default="http://127.0.0.1:11434")
args = ap.parse_args()

MODEL_NAME = "flux3-image-klein"
PROMPTS = json.load(open(hf_hub_download("black-forest-labs/flux-3-image-klein-pup", "system_prompts.json")))
lock = threading.Lock()            # one picture at a time; others wait their turn
state = {"model": None, "last": 0.0, "busy": False, "loads": 0}


def log(text):
    print(time.strftime("%Y-%m-%d %H:%M:%S ") + text, flush=True)


def model():
    if state["model"] is None:
        t = time.time()
        state["model"] = Flux3KleinEdit(model_config=ModelConfig.flux3_image_klein())
        state["loads"] += 1
        log("model loaded in %.1f s" % (time.time() - t))
    state["last"] = time.time()
    return state["model"]


def let_go():
    """Free the model's memory after KEEP idle seconds; the next request loads it again."""
    while True:
        time.sleep(15)
        with lock:
            if state["model"] is not None and not state["busy"] and time.time() - state["last"] > args.keep:
                state["model"] = None
                gc.collect()
                try:
                    mx.clear_cache()
                except AttributeError:
                    mx.metal.clear_cache()
                log("idle %d s: model let go" % args.keep)


def short(prompt):
    words = len(re.findall(r"[A-Za-z0-9']+", prompt))
    han = len(re.findall(r"[㐀-鿿]", prompt))
    return words + han / 2 < 45


def upsample(prompt, images=()):
    """A full scene caption from the box's vision LLM with BFL's instructions; None when it cannot."""
    if images:
        text = ("Reference images follow in order (the first image, the second image, ...).\n"
                "User request: %s\nOutput the caption." % prompt)
        messages = [{"role": "system", "content": PROMPTS["i2i"]},
                    {"role": "user", "content": text, "images": [base64.b64encode(b).decode() for b in images]}]
    else:
        messages = [{"role": "system", "content": PROMPTS["t2i"]}, {"role": "user", "content": prompt}]
    body = {"model": args.llm, "messages": messages, "stream": False, "think": False, "keep_alive": "2m",
            "options": {"temperature": 0, "num_predict": 3584}}
    t = time.time()
    try:
        req = urllib.request.Request(args.ollama + "/api/chat", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        answer = json.loads(urllib.request.urlopen(req, timeout=300).read())
        caption = (answer.get("message") or {}).get("content", "").strip()
        caption = re.sub(r"^<think>.*?</think>\s*", "", caption, flags=re.S).strip()
        log("caption by %s in %.1f s (%d chars)" % (args.llm, time.time() - t, len(caption)))
        return caption or None
    except Exception as e:
        log("caption failed after %.1f s: %s" % (time.time() - t, e))
        return None


def decide(prompt, given, edit):
    if given is not None:
        return given
    if '"bbox"' in prompt or "<ref_image_" in prompt:
        return False
    return True if edit else short(prompt)


def flag(value):
    if value is None or value == "":
        return None
    return str(value).lower() in ("1", "true", "yes")


def round16(n):
    return max(256, int(round(int(n) / 16.0)) * 16)


def png(image):
    buffer = io.BytesIO()
    pil = getattr(image, "image", image)
    pil.save(buffer, format="PNG")
    return buffer.getvalue()


def draw(prompt, width, height, seed, steps, wanted):
    caption = (upsample(prompt) if decide(prompt, wanted, False) else None) or prompt
    with lock:
        state["busy"] = True
        try:
            t = time.time()
            image = model()._generate(seed=seed, prompt=caption, num_inference_steps=steps,
                                      height=round16(height), width=round16(width))
            log("drew %dx%d in %.1f s" % (round16(width), round16(height), time.time() - t))
            return png(image), caption
        finally:
            state["busy"], state["last"] = False, time.time()


def change(prompt, images, seed, steps, wanted):
    from PIL import Image
    first = Image.open(io.BytesIO(images[0]))
    caption = (upsample(prompt, images) if decide(prompt, wanted, True) else None) or prompt
    with tempfile.TemporaryDirectory() as folder:
        paths = []
        for n, data in enumerate(images):
            path = os.path.join(folder, "ref%d.png" % n)
            Image.open(io.BytesIO(data)).convert("RGB").save(path)
            paths.append(path)
        with lock:
            state["busy"] = True
            try:
                t = time.time()
                image = model().generate_image(seed=seed, prompt=caption, image_paths=paths, num_inference_steps=steps,
                                               width=round16(first.width), height=round16(first.height))
                log("edited with %d reference(s) in %.1f s" % (len(paths), time.time() - t))
                return png(image), caption
            finally:
                state["busy"], state["last"] = False, time.time()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        log("%s %s" % (self.client_address[0], fmt % a))

    def reply(self, code, body, kind="application/json", caption=None):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        if caption:
            self.send_header("X-Flux-Caption", base64.b64encode(caption.encode()).decode())
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/") in ("/api/health", "/health", ""):
            idle = time.time() - state["last"]
            self.reply(200, {"status": "healthy", "model_loaded": state["model"] is not None,
                             "current_model": MODEL_NAME, "engine": "mflux 0.23.0 (MLX, bf16)", "busy": state["busy"],
                             "captions_by": args.llm, "keep_alive_s": args.keep,
                             "unloads_in_s": max(0, int(args.keep - idle)) if state["model"] is not None else None})
        else:
            self.reply(404, {"detail": "no such path"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)
        try:
            if self.path == "/api/generate":
                body = json.loads(raw or b"{}")
                prompt = (body.get("prompt") or "").strip()
                if not prompt:
                    return self.reply(400, {"detail": "prompt is empty"})
                data, caption = draw(prompt, body.get("width", 1024), body.get("height", 1024),
                                     int(body.get("seed") if body.get("seed") is not None else time.time() % 2**31),
                                     body.get("steps"), flag(body.get("upsample")))
                return self.reply(200, data, "image/png", caption)
            if self.path == "/api/generate/img2img":
                kind = self.headers.get("Content-Type", "")
                message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
                    b"Content-Type: " + kind.encode() + b"\r\n\r\n" + raw)
                fields, images = {}, []
                for part in message.iter_parts():
                    name = part.get_param("name", header="content-disposition")
                    if name in ("image", "images"):
                        data = part.get_payload(decode=True)
                        if data:
                            images.insert(0, data) if name == "image" else images.append(data)
                    elif name:
                        # Form fields come as raw UTF-8 with no charset: read them as that, not as ASCII
                        # (a Chinese instruction arrived garbled and the caption invented an edit).
                        fields[name] = (part.get_payload(decode=True) or b"").decode("utf-8", errors="replace").strip()
                prompt = fields.get("prompt", "")
                if not prompt:
                    return self.reply(400, {"detail": "prompt is empty"})
                if not images:
                    return self.reply(400, {"detail": "image is missing: an edit needs the picture to change"})
                if len(images) > 10:
                    return self.reply(400, {"detail": "FLUX 3 takes at most 10 reference images"})
                steps = fields.get("num_inference_steps")
                data, caption = change(prompt, images,
                                       int(fields.get("seed") or time.time() % 2**31),
                                       int(steps) if steps else None, flag(fields.get("upsample")))
                return self.reply(200, data, "image/png", caption)
            return self.reply(404, {"detail": "no such path"})
        except Exception as e:
            log("failed: %s\n%s" % (e, traceback.format_exc()[-1500:]))
            return self.reply(500, {"detail": "%s: %s" % (type(e).__name__, str(e)[:400])})


threading.Thread(target=let_go, daemon=True).start()
log("FLUX 3 Image Klein on %s:%d (model loads on the first request, let go after %d s idle; captions by %s)"
    % (args.host, args.port, args.keep, args.llm))
ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
