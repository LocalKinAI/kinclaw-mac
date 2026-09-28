#!/usr/bin/env python3
"""Pixelle-Video on the LocalKin box, driven from this Mac (see SKILL.md).

Everything goes over ssh to the box (jackysub@192.168.0.21): the API listens on
the box's 127.0.0.1:8190 only. Results are copied to
/Volumes/Data/kinclaw/companion/pixelle/<run>/ on this Mac.

Commands (JSON bodies on stdin where noted):
  status                     API, ComfyUI queue, LLM, TTS servers, running jobs
  start | stop [--force] | restart
  templates                  frame templates (video size, picture size, parameters), BGM, image workflows
  voices                     TTS choices on the box
  script TOPIC [--scenes N --min A --max B]      narration from the box's LLM (ornith)
  prompts   < ["narration", ...]                 picture prompts from the box's LLM
  image PROMPT [--size WxH] [--full] [--prefix P]  one test picture (~45 s, --full ~2 min)
  voice TEXT [--instruct D] [--speaker S] [--url 8101|8102|URL] [--speed X] [--check]
  make [--file job.json] < job                   submit a video job, returns at once
  rework [--file job.json] < job                 remake a finished video from its own pictures:
                                                 {"source": OUTPUT_DIR, "revoice": true, "scene_motion": "ltx", ...}
  wait TASK [--timeout 540]                      follow a job; fetches the result when done
  fetch TASK|OUTPUT_DIR                          copy a finished job's files to this Mac
  tasks | cancel TASK | log [N]
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

BOX = os.environ.get("PIXELLE_BOX", "jackysub@192.168.0.21")
PORT = int(os.environ.get("PIXELLE_PORT", "8190"))
API = "http://127.0.0.1:%d" % PORT
REMOTE_ROOT = "Pixelle-Video"                      # under the box user's home
CTL = "~/.kinclaw/pixelle/pixelle-api.sh"
LOG = "~/Library/Logs/kinclaw/pixelle-api.log"
LOCAL_ROOT = os.environ.get("PIXELLE_OUT", "/Volumes/Data/kinclaw/companion/pixelle")
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", BOX]
PATHX = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; "
DEFAULT_TEMPLATE = "1080x1920/image_default.html"
TTS_URLS = {"8101": "http://127.0.0.1:8101", "8102": "http://127.0.0.1:8102"}


class Failure(Exception):
    pass


# ---------------------------------------------------------------- transport

def ssh(cmd, stdin=None, timeout=120, binary=False):
    """Run a shell command on the box. Returns (rc, stdout, stderr)."""
    try:
        r = subprocess.run(SSH + [PATHX + cmd], input=stdin, capture_output=True,
                           timeout=timeout, text=not binary)
    except subprocess.TimeoutExpired:
        raise Failure("the box did not answer within %d s (ssh %s)" % (timeout, BOX))
    return r.returncode, r.stdout, r.stderr


def api(method, path, body=None, timeout=120):
    """Call the Pixelle API on the box through curl over ssh; JSON in, JSON out."""
    cmd = "curl -sS -m %d -X %s -H 'Content-Type: application/json' -w '\\n%%{http_code}' %s" % (
        timeout, method, shlex.quote(API + path))
    data = None
    if body is not None:
        cmd += " --data-binary @-"
        data = json.dumps(body, ensure_ascii=False)
    rc, out, err = ssh(cmd, stdin=data, timeout=timeout + 30)
    if rc != 0:
        if rc == 7 or "Failed to connect" in (err or ""):
            raise Failure("Pixelle API is not running on the box (port %d). Start it: pv.py start" % PORT)
        raise Failure("box call failed (rc %d): %s" % (rc, (err or out).strip()[:400]))
    text, _, code = out.rstrip("\n").rpartition("\n")
    try:
        status = int(code)
    except ValueError:
        text, status = out, 0
    try:
        payload = json.loads(text) if text.strip() else {}
    except ValueError:
        payload = {"raw": text[:2000]}
    if status >= 400:
        detail = payload.get("detail") if isinstance(payload, dict) else None
        raise Failure("API %s %s -> HTTP %d: %s" % (method, path, status, detail or text[:800]))
    return payload


def box_bytes(url_or_path, timeout=120):
    """Bytes of a file on the box: a URL the box can reach, or a path under ~/Pixelle-Video."""
    if url_or_path.startswith("http"):
        cmd = "curl -sS -f -m %d %s" % (timeout, shlex.quote(url_or_path))
    else:
        cmd = "cat %s" % shlex.quote(remote_path(url_or_path))
    rc, out, err = ssh(cmd, timeout=timeout + 30, binary=True)
    if rc != 0:
        raise Failure("could not fetch %s from the box: %s" % (url_or_path, err.decode(errors="replace")[:300]))
    return out


def remote_path(path):
    """A path the box's shell understands: absolute as is, else under ~/Pixelle-Video."""
    return path if path.startswith("/") else "%s/%s" % (REMOTE_ROOT, path)


def box_python(code, timeout=60):
    """Run a Python snippet on the box (its /usr/bin/python3); returns stdout."""
    rc, text, err = ssh("/usr/bin/python3 -", stdin=code, timeout=timeout)
    if rc != 0:
        raise Failure("box script failed: %s" % (err or text).strip()[:400])
    return text


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)
    return path


def read_stdin_json(what):
    if sys.stdin.isatty():
        raise Failure("give the %s as JSON on stdin (heredoc)" % what)
    raw = sys.stdin.read()
    try:
        return json.loads(raw)
    except ValueError as e:
        raise Failure("%s is not valid JSON: %s" % (what, e))


def out(obj):
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def probe_duration(path):
    if not shutil.which("ffprobe"):
        return None
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                            "default=nw=1:nk=1", path], capture_output=True, text=True, timeout=30)
        return round(float(r.stdout.strip()), 2)
    except Exception:
        return None


# ---------------------------------------------------------------- commands

def cmd_status(args):
    report = {}
    rc, text, err = ssh(CTL + " status", timeout=30)
    report["pixelle_api"] = text.strip() or err.strip()
    script = r"""
q=$(curl -s -m 5 http://127.0.0.1:8188/queue); echo "COMFY $q"
echo "KINFER $(curl -s -m 5 http://127.0.0.1:11590/api/ps)"
for p in 8101 8102; do echo "TTS$p $(curl -s -m 5 http://127.0.0.1:$p/health)"; done
echo "LTX $(curl -s -m 5 http://127.0.0.1:8001/api/health)"
"""
    rc, text, err = ssh(script, timeout=40)
    for line in text.splitlines():
        key, _, rest = line.partition(" ")
        try:
            val = json.loads(rest) if rest.strip() else None
        except ValueError:
            val = rest.strip() or None
        if key == "COMFY":
            if isinstance(val, dict):
                report["comfyui"] = {"running": len(val.get("queue_running", [])),
                                     "pending": len(val.get("queue_pending", []))}
            else:
                report["comfyui"] = "not answering on :8188"
        elif key == "KINFER":
            report["llm_kinfer_loaded"] = [m.get("name") for m in (val or {}).get("models", [])] if isinstance(val, dict) else "not answering on :11590"
        elif key.startswith("TTS"):
            report["tts_" + key[3:]] = val if val else "not answering"
        elif key == "LTX":
            report["ltx_8001"] = val if val else "not answering (scene_motion ltx needs it; the app starts it)"
    try:
        tasks = api("GET", "/api/tasks?limit=20", timeout=20)
        report["jobs"] = [{"task_id": t["task_id"], "status": t["status"],
                           "progress": (t.get("progress") or {}).get("message"),
                           "percent": (t.get("progress") or {}).get("percentage"),
                           "created": t.get("created_at")} for t in tasks]
    except Failure as e:
        report["jobs"] = str(e)
    out(report)


def cmd_start(args):
    rc, text, err = ssh(CTL + " start", timeout=120)
    print((text + err).strip())
    if rc != 0:
        raise Failure("start failed")


def running_jobs():
    try:
        return [t for t in api("GET", "/api/tasks?status=running", timeout=20)]
    except Failure:
        return []


def cmd_stop(args):
    busy = running_jobs()
    if busy and not args.force:
        raise Failure("%d job(s) still running (%s); they would be lost. Wait, or stop --force."
                      % (len(busy), ", ".join(t["task_id"] for t in busy)))
    rc, text, err = ssh(CTL + " stop", timeout=60)
    print((text + err).strip())


def cmd_restart(args):
    cmd_stop(args)
    cmd_start(args)


def cmd_templates(args):
    templates = api("GET", "/api/resources/templates").get("templates", [])
    text = box_python(r'''
import glob, json, os, re
root = os.path.expanduser("~/%s")
info = {}
for f in sorted(glob.glob(root + "/templates/*/*.html") + glob.glob(root + "/data/templates/*/*.html")):
    html = open(f, encoding="utf-8").read()
    w = re.search(r'template:media-width" content="(\d+)"', html)
    h = re.search(r'template:media-height" content="(\d+)"', html)
    params = sorted(set(re.findall(r"\{\{([^}]+)\}\}", html)))
    key = "/".join(f.split("/")[-2:])
    info[key] = {"picture": "%%sx%%s" %% (w.group(1), h.group(1)) if w and h else "1024x1024 (fallback)",
                 "params": [p for p in params if p.split("=")[0].split(":")[0] not in ("image", "text", "title", "index")]}
print(json.dumps(info))
''' % REMOTE_ROOT)
    extra = json.loads(text)
    rows = []
    for t in templates:
        info = extra.get(t["key"], {})
        kind = t["name"].split("_", 1)[0]
        rows.append({"template": t["key"], "video": t["size"], "kind": kind,
                     "picture": info.get("picture"), "params": info.get("params")})
    bgm = api("GET", "/api/resources/bgm").get("bgm_files", [])
    media = api("GET", "/api/resources/workflows/media").get("workflows", [])
    out({"templates": rows,
         "note": "kind image_ = AI picture per scene (the box can do these); static_ = text only; "
                 "video_ = needs a video workflow (none on the box yet). params such as author/brand/describe "
                 "carry Pixelle's own branding by default: override them in template_params ('' hides).",
         "bgm": [b["name"] for b in bgm],
         "image_workflows": [w["key"] for w in media if w.get("source") == "selfhost" and "qwen21" in w["key"]]})


def cmd_voices(args):
    rc, text, err = ssh("curl -s -m 5 http://127.0.0.1:8101/voices", timeout=20)
    try:
        presets = json.loads(text).get("voices", [])
    except ValueError:
        presets = "8101 not answering"
    out({"default": "localkin :8102 qwen3-tts 1.7b voicedesign — the voice is made from tts_instruct (a description "
                    "in words, e.g. 低沉厚重的老年男声，语速缓慢，庄重). The model makes a new voice on every call, so a "
                    "video is read in ONE take and cut at the pauses between lines (tts_one_take, default on): one "
                    "narrator for the whole video. tts_one_take false voices line by line (the voice changes).",
         "presets_8101": {"tts_url": TTS_URLS["8101"], "use": "tts_voice = id, tts_instruct = '' or a style (用平静的语气)",
                          "voices": presets},
         "edge": "tts_inference_mode 'local' = Microsoft Edge TTS (online, free, not local), tts_voice e.g. zh-CN-YunjianNeural"})


def cmd_script(args):
    res = api("POST", "/api/content/narration",
              {"text": args.topic, "n_scenes": args.scenes, "min_words": args.min, "max_words": args.max},
              timeout=300)
    out(res.get("narrations", res))


def cmd_prompts(args):
    narrations = read_stdin_json("narration list")
    res = api("POST", "/api/content/image-prompt",
              {"narrations": narrations, "min_words": args.min, "max_words": args.max}, timeout=600)
    out(res.get("image_prompts", res))


def cmd_image(args):
    w, h = [int(x) for x in args.size.lower().split("x")]
    prompt = ("%s, %s" % (args.prefix.strip(), args.prompt.strip())) if args.prefix else args.prompt
    workflow = "selfhost/image_qwen21_box_full.json" if args.full else "selfhost/image_qwen21_box.json"
    t0 = time.time()
    res = api("POST", "/api/image/generate", {"prompt": prompt, "width": w, "height": h, "workflow": workflow},
              timeout=1200)
    url = res.get("image_path")
    data = box_bytes(url)
    folder = ensure_dir(os.path.join(LOCAL_ROOT, "looks"))
    name = _dt.datetime.now().strftime("%Y%m%d-%H%M%S") + ".png"
    path = os.path.join(folder, name)
    with open(path, "wb") as f:
        f.write(data)
    with open(path + ".txt", "w") as f:
        f.write("workflow: %s\nsize: %dx%d\nprompt: %s\n" % (workflow, w, h, prompt))
    out({"picture": path, "seconds": round(time.time() - t0, 1), "workflow": workflow, "prompt_used": prompt,
         "look": "open it with the Read tool"})


def tts_url(value):
    if not value:
        return None
    return TTS_URLS.get(str(value), value)


def cmd_voice(args):
    body = {"text": args.text, "inference_mode": args.mode}
    if args.instruct is not None:
        body["instruct"] = args.instruct
    if args.speaker is not None:
        body["voice"] = args.speaker
    if args.url:
        body["tts_url"] = tts_url(args.url)
    if args.speed is not None:
        body["speed"] = args.speed
    if args.language:
        body["language"] = args.language
    t0 = time.time()
    res = api("POST", "/api/tts/synthesize", body, timeout=600)
    remote = res["audio_path"]
    data = box_bytes(remote)
    folder = ensure_dir(os.path.join(LOCAL_ROOT, "voices"))
    path = os.path.join(folder, _dt.datetime.now().strftime("%Y%m%d-%H%M%S") + os.path.splitext(remote)[1])
    with open(path, "wb") as f:
        f.write(data)
    result = {"audio": path, "duration": res.get("duration"), "seconds": round(time.time() - t0, 1), "sent": body}
    if args.check:
        # The box's speech recogniser (qwen3-asr :8100) says what it hears.
        rc, text, err = ssh("curl -s -m 120 -F file=@%s http://127.0.0.1:8100/transcribe"
                            % shlex.quote(remote_path(remote)), timeout=150)
        try:
            heard = json.loads(text)
            result["heard"] = heard.get("text") or heard.get("transcription") or heard
        except ValueError:
            result["heard"] = (text or err).strip()[:500]
    out(result)


def split_scenes(text, mode):
    if mode == "line":
        return [l.strip() for l in text.split("\n") if l.strip()]
    if mode == "sentence":
        cleaned = re.sub(r"\s+", " ", text.strip())
        return [s.strip() for s in re.split(r"(?<=[。.!?！？])\s*", cleaned) if s.strip()]
    return [p for p in re.split(r"\n\s*\n", text) if p.strip()]


def cmd_make(args):
    if args.file:
        with open(args.file) as f:
            job = json.load(f)
    else:
        job = read_stdin_json("job")
    if not isinstance(job, dict) or not job.get("text"):
        raise Failure("the job needs at least 'text' (a topic, or the script in mode 'fixed')")
    notes = []
    if not job.get("frame_template"):
        job["frame_template"] = DEFAULT_TEMPLATE
        notes.append("frame_template not given: using %s" % DEFAULT_TEMPLATE)
    if job.get("tts_url"):
        job["tts_url"] = tts_url(job["tts_url"])
    mode = job.get("mode", "generate")
    if mode == "fixed":
        scenes = split_scenes(job["text"], job.get("split_mode") or "paragraph")
        prompts = job.get("image_prompts")
        if prompts is not None and len(prompts) != len(scenes):
            raise Failure("image_prompts has %d entries but the text splits into %d scenes (%s): %s"
                          % (len(prompts), len(scenes), job.get("split_mode") or "paragraph",
                             [s[:12] for s in scenes]))
        n = len(scenes)
    else:
        n = job.get("n_scenes", 5)
        if job.get("image_prompts"):
            notes.append("image_prompts only line up with scenes you wrote: use mode 'fixed'")
    motion = job.get("scene_motion") or "none"
    if motion not in ("none", "pan", "ltx"):
        raise Failure("scene_motion is none, pan (a slow push/drift, seconds) or ltx (real motion, ~3 min a scene)")
    if job.get("motion_prompts") is not None and mode == "fixed" and len(job["motion_prompts"]) != n:
        raise Failure("motion_prompts has %d entries but the text splits into %d scenes" % (len(job["motion_prompts"]), n))
    if motion == "ltx":
        ltx = ltx_health()
        if ltx:
            raise Failure("scene_motion ltx needs LTX on the box's :8001, which %s (the app starts it; or use pan)" % ltx)
    res = api("POST", "/api/video/generate/async", job, timeout=60)
    task = res["task_id"]
    folder = ensure_dir(os.path.join(LOCAL_ROOT, "jobs"))
    with open(os.path.join(folder, task + ".json"), "w") as f:
        json.dump(job, f, ensure_ascii=False, indent=2)
    if os.path.basename(job["frame_template"]).startswith("static_"):
        estimate = "under a minute (text-only template: no pictures, ComfyUI not used)"
    else:
        per = 150 if "full" in (job.get("media_workflow") or "") else 60
        per += {"ltx": 190, "pan": 5}.get(motion, 0)
        estimate = ("about %d-%d min if ComfyUI is free (≈45-50 s picture%s per scene, the voice-over in one "
                    "take); longer when other tabs' jobs are in ComfyUI's queue (pv.py status)"
                    % (max(1, n * per // 60 - 1), n * per // 60 + 2,
                       " + ≈3 min of LTX motion" if motion == "ltx" else ""))
    out({"task_id": task, "scenes": n, "estimate": estimate,
         "next": "pv.py wait %s" % task, "notes": notes})


def ltx_health():
    """None when LTX answers on the box's :8001, else what is wrong."""
    rc, text, err = ssh("curl -s -m 5 http://127.0.0.1:8001/api/health", timeout=20)
    try:
        health = json.loads(text)
    except ValueError:
        return "is not answering"
    return None if health.get("model_loaded") else "has no model loaded (%s)" % text.strip()[:120]


def cmd_rework(args):
    if args.file:
        with open(args.file) as f:
            job = json.load(f)
    else:
        job = read_stdin_json("rework job")
    if not isinstance(job, dict) or not job.get("source"):
        raise Failure("the rework job needs 'source': a finished video's output_dir (e.g. 20260928_093131_db14)")
    m = re.match(r"^(\d{8}_\d{6}_[0-9a-f]+)", str(job["source"]))
    if not m:
        raise Failure("source is an output_dir like 20260928_093131_db14 (the run folder's name before the title)")
    job["source"] = m.group(1)
    motion = job.get("scene_motion") or "none"
    if motion not in ("none", "pan", "ltx"):
        raise Failure("scene_motion is none, pan or ltx")
    if not job.get("revoice") and motion == "none":
        raise Failure("nothing to redo: revoice true (one narrator) and/or scene_motion pan|ltx")
    sb = json.loads(box_bytes("output/%s/storyboard.json" % job["source"]).decode())
    frames = sb.get("frames", [])
    n = len(frames)
    if job.get("motion_prompts") is not None and len(job["motion_prompts"]) != n:
        raise Failure("motion_prompts has %d entries but %s has %d scenes" % (len(job["motion_prompts"]), job["source"], n))
    chosen = [int(x) for x in (job.get("scenes") or range(1, n + 1))]
    if any(not 1 <= x <= n for x in chosen):
        raise Failure("scenes are numbered 1..%d" % n)
    if motion == "ltx":
        ltx = ltx_health()
        if ltx:
            raise Failure("scene_motion ltx needs LTX on the box's :8001, which %s (the app starts it; or use pan)" % ltx)
    seconds = 20 + (45 if job.get("revoice") else 0)
    for f in frames:
        length = float(f.get("duration") or 6.0)
        if motion == "ltx" and f["index"] + 1 in chosen:
            seconds += 15 + 31 * min(length + 0.1, 6.0)
        else:
            seconds += 6
    title = job.pop("title", None) or sb.get("title")
    res = api("POST", "/api/video/rework/async", job, timeout=60)
    task = res["task_id"]
    folder = ensure_dir(os.path.join(LOCAL_ROOT, "jobs"))
    with open(os.path.join(folder, task + ".json"), "w") as f:
        json.dump(dict(job, title=title), f, ensure_ascii=False, indent=2)
    out({"task_id": task, "source": job["source"], "title": title, "scenes": n,
         "moving": sorted(chosen) if motion != "none" else [], "motion": motion, "revoice": bool(job.get("revoice")),
         "estimate": "about %d min%s" % (max(1, round(seconds / 60)),
                                          " (LTX ≈3 min a scene)" if motion == "ltx" else ""),
         "next": "pv.py wait %s" % task})


def cmd_tasks(args):
    out([{"task_id": t["task_id"], "status": t["status"], "progress": t.get("progress"),
          "error": t.get("error"), "created": t.get("created_at")}
         for t in api("GET", "/api/tasks?limit=50", timeout=20)])


def cmd_cancel(args):
    out(api("DELETE", "/api/tasks/%s" % args.task, timeout=20))
    print("note: a picture already sent to ComfyUI still finishes there; see pv.py status", file=sys.stderr)


def cmd_log(args):
    rc, text, err = ssh("tail -n %d %s | grep -v '| DEBUG '" % (args.n, LOG), timeout=30)
    print(text)


def comfy_queue():
    rc, text, err = ssh("curl -s -m 5 http://127.0.0.1:8188/queue", timeout=20)
    try:
        q = json.loads(text)
        return len(q.get("queue_running", [])), len(q.get("queue_pending", []))
    except ValueError:
        return None


def cmd_wait(args):
    t0 = time.time()
    last_msg, last_change = None, time.time()
    while True:
        task = api("GET", "/api/tasks/%s" % args.task, timeout=20)
        status = task["status"]
        prog = task.get("progress") or {}
        msg = "%s %s%%" % (prog.get("message") or status, int(prog.get("percentage") or 0))
        if msg != last_msg:
            print("[%4ds] %s" % (time.time() - t0, msg), flush=True)
            last_msg, last_change = msg, time.time()
        elif time.time() - last_change > 150:
            q = comfy_queue()
            if q:
                print("[%4ds] still on '%s' — ComfyUI has %d running, %d waiting (other tabs share it)"
                      % (time.time() - t0, prog.get("message"), q[0], q[1]), flush=True)
            last_change = time.time()
        if status == "completed":
            result = task.get("result") or {}
            fetch_result(result, task.get("request_params"))
            return
        if status in ("failed", "cancelled"):
            rc, text, err = ssh("grep -E 'ERROR|Error|error' %s | tail -n 8" % LOG, timeout=30)
            raise Failure("job %s %s: %s\nlog:\n%s" % (args.task, status, task.get("error"), text.strip()))
        if time.time() - t0 > args.timeout:
            print("still %s after %d s — run `pv.py wait %s` again (the job keeps going on the box)"
                  % (msg, args.timeout, args.task))
            return
        time.sleep(args.every)


def slug(text):
    text = re.sub(r"[\\/:*?\"<>|\s]+", "-", (text or "").strip())
    return text[:40].strip("-") or "video"


def fetch_result(result, request=None):
    output_dir = result.get("output_dir")
    if not output_dir:
        m = re.search(r"/api/files/([^/]+)/", result.get("video_url", ""))
        output_dir = m.group(1) if m else None
    if not output_dir:
        raise Failure("no output folder in the result: %s" % result)
    local = os.path.join(LOCAL_ROOT, "%s-%s" % (output_dir, slug(result.get("title"))))
    ensure_dir(local)
    src = "%s:%s/output/%s/" % (BOX, REMOTE_ROOT, output_dir)
    r = subprocess.run(["rsync", "-a", "--exclude=.window/", "--exclude=probe-*.wav", "-e", "ssh -o BatchMode=yes",
                        src, local + "/"], capture_output=True, text=True)
    if r.returncode != 0:
        r = subprocess.run(["scp", "-q", "-r", "-o", "BatchMode=yes", src.rstrip("/") + "/.", local],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise Failure("copy from the box failed: %s" % (r.stderr.strip()[:400]))
    with open(os.path.join(local, "result.json"), "w") as f:
        json.dump({"result": result, "request": request}, f, ensure_ascii=False, indent=2)
    final = os.path.join(local, "final.mp4")
    sheet = None
    frames = os.path.join(local, "frames")
    composed = sorted(p for p in os.listdir(frames) if p.endswith("_composed.png")) if os.path.isdir(frames) else []
    if composed and shutil.which("ffmpeg"):
        sheet = os.path.join(local, "sheet.png")
        listfile = os.path.join(local, ".sheet.txt")
        with open(listfile, "w") as f:
            for p in composed:
                f.write("file '%s'\n" % os.path.join(frames, p))
        cols = min(len(composed), 5)
        rows = (len(composed) + cols - 1) // cols
        r = subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", listfile,
                            "-vf", "scale=270:-1,tile=%dx%d:padding=6:color=white" % (cols, rows),
                            "-frames:v", "1", sheet], capture_output=True, text=True)
        os.replace(listfile, listfile + ".last")
        if r.returncode != 0:
            sheet = None
    scenes = []
    for fr in result.get("frames") or []:
        entry = {"scene": fr.get("index"), "seconds": fr.get("duration"), "narration": fr.get("narration"),
                 "image_prompt": fr.get("image_prompt")}
        for key in ("image", "audio", "composed"):
            if fr.get(key):
                entry[key] = os.path.join(LOCAL_ROOT, "%s-%s" % (output_dir, slug(result.get("title"))),
                                          fr[key].split("/", 1)[1] if "/" in fr[key] else fr[key])
        scenes.append(entry)
    master = result.get("audio_master") or {}
    loudness = ("%.1f LUFS before, finished to %s LUFS" % (master["measured_lufs"], master["target_lufs"])
                if master.get("measured_lufs") is not None else "not finished (master_audio off or failed)")
    out({"video": final if os.path.exists(final) else None,
         "duration_s": probe_duration(final) if os.path.exists(final) else result.get("duration"),
         "title": result.get("title"), "folder": local, "sheet": sheet, "loudness": loudness, "scenes": scenes,
         "look": "Read sheet.png (all scenes) or frames/NN_image.png; `open` the video for the user"})


def cmd_fetch(args):
    ref = args.ref
    if re.match(r"^\d{8}_\d{6}_[0-9a-f]+$", ref):
        raw = box_bytes("output/%s/storyboard.json" % ref)
        sb = json.loads(raw.decode())
        try:
            done = json.loads(box_bytes("output/%s/metadata.json" % ref).decode()).get("result") or {}
        except (Failure, ValueError):
            done = {}
        result = {"output_dir": ref, "title": sb.get("title"), "duration": done.get("duration"),
                  "audio_master": done.get("audio_master"), "voice": sb.get("voice"),
                  "reworked_from": sb.get("reworked_from"), "frames": [
            {"index": f["index"] + 1, "narration": f.get("narration"), "image_prompt": f.get("image_prompt"),
             "duration": f.get("duration"), "motion": f.get("motion")} for f in sb.get("frames", [])]}
        fetch_result(result)
    else:
        task = api("GET", "/api/tasks/%s" % ref, timeout=20)
        if task["status"] != "completed":
            raise Failure("job is %s, nothing to fetch yet" % task["status"])
        fetch_result(task.get("result") or {}, task.get("request_params"))


def main():
    p = argparse.ArgumentParser(description="Pixelle-Video on the LocalKin box")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    sub.add_parser("start").set_defaults(fn=cmd_start)
    s = sub.add_parser("stop"); s.add_argument("--force", action="store_true"); s.set_defaults(fn=cmd_stop)
    s = sub.add_parser("restart"); s.add_argument("--force", action="store_true"); s.set_defaults(fn=cmd_restart)
    sub.add_parser("templates").set_defaults(fn=cmd_templates)
    sub.add_parser("voices").set_defaults(fn=cmd_voices)
    s = sub.add_parser("script"); s.add_argument("topic"); s.add_argument("--scenes", type=int, default=5)
    s.add_argument("--min", type=int, default=20); s.add_argument("--max", type=int, default=40)
    s.set_defaults(fn=cmd_script)
    s = sub.add_parser("prompts"); s.add_argument("--min", type=int, default=30); s.add_argument("--max", type=int, default=60)
    s.set_defaults(fn=cmd_prompts)
    s = sub.add_parser("image"); s.add_argument("prompt"); s.add_argument("--size", default="1024x1024")
    s.add_argument("--full", action="store_true"); s.add_argument("--prefix"); s.set_defaults(fn=cmd_image)
    s = sub.add_parser("voice"); s.add_argument("text"); s.add_argument("--instruct"); s.add_argument("--speaker")
    s.add_argument("--url"); s.add_argument("--speed", type=float); s.add_argument("--language")
    s.add_argument("--mode", default="localkin"); s.add_argument("--check", action="store_true")
    s.set_defaults(fn=cmd_voice)
    s = sub.add_parser("make"); s.add_argument("--file"); s.set_defaults(fn=cmd_make)
    s = sub.add_parser("rework"); s.add_argument("--file"); s.set_defaults(fn=cmd_rework)
    s = sub.add_parser("wait"); s.add_argument("task"); s.add_argument("--timeout", type=int, default=540)
    s.add_argument("--every", type=int, default=10); s.set_defaults(fn=cmd_wait)
    s = sub.add_parser("fetch"); s.add_argument("ref"); s.set_defaults(fn=cmd_fetch)
    sub.add_parser("tasks").set_defaults(fn=cmd_tasks)
    s = sub.add_parser("cancel"); s.add_argument("task"); s.set_defaults(fn=cmd_cancel)
    s = sub.add_parser("log"); s.add_argument("n", nargs="?", type=int, default=60); s.set_defaults(fn=cmd_log)
    args = p.parse_args()
    try:
        args.fn(args)
    except Failure as e:
        print("error: %s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
