#!/usr/bin/env python3
"""OpenMontage on the box, for the KinClaw studio agent on the Mac.

An MCP server that speaks JSON-RPC on stdin and stdout, started by the agent
over ssh (`ssh -T box python3 ~/.kinclaw/om_bridge.py`). The agent thinks on
the Mac — on the subscription signed in there, or whichever model it was given
— and does OpenMontage's work here, where its Python, ffmpeg and Remotion are:
it runs commands in ~/OpenMontage with the venv active, reads and writes the
files there, starts long jobs in the background and asks after them, and looks
at the pictures and clips it made.

Standard library only; the app installs this file (KinClawMac/Resources) and
replaces it when it changes. Paths are ~/OpenMontage's: nothing outside it is
read or written through the file tools.
"""

import base64
import json
import os
import shlex
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = os.path.realpath(os.path.expanduser("~/OpenMontage"))
JOBS = os.path.expanduser("~/.kinclaw/om-jobs")
# PYTHONPATH: OpenMontage's scripts import `tools.…` and `lib.…` from its root;
# run from anywhere else they failed with "No module named 'tools'".
PREAMBLE = ('cd ~/OpenMontage && source .venv/bin/activate && '
            'export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH" BACKLOT_PORT=4750 '
            'PYTHONPATH="$HOME/OpenMontage${PYTHONPATH:+:$PYTHONPATH}" && ')
PICTURES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif"}
CLIPS = {".mp4", ".mov", ".m4v", ".webm", ".mkv"}
FFMPEG = "/opt/homebrew/bin/ffmpeg"

TOOLS = [
    {
        "name": "run",
        "description": "Run a shell command on the box in ~/OpenMontage, with its venv active and Homebrew on the PATH "
                       "(python, ffmpeg, node, npx). Waits for it, up to timeout_seconds (at most 900), and returns "
                       "the exit code and the end of its output. For anything that takes longer — a render, H3, "
                       "music — use start and job.",
        "inputSchema": {"type": "object", "required": ["command"], "properties": {
            "command": {"type": "string"},
            "timeout_seconds": {"type": "integer", "default": 300}}},
    },
    {
        "name": "start",
        "description": "Start a long shell command on the box in ~/OpenMontage in the background (venv active). "
                       "Returns a job id; ask after it with job.",
        "inputSchema": {"type": "object", "required": ["command"], "properties": {
            "command": {"type": "string"},
            "label": {"type": "string", "description": "A few words saying what it is."}}},
    },
    {
        "name": "job",
        "description": "A background job's state: running or finished with its exit code, how long it has run, and "
                       "the end of its output. With no id, lists the jobs.",
        "inputSchema": {"type": "object", "properties": {
            "id": {"type": "string"},
            "tail": {"type": "integer", "default": 4000, "description": "Characters of output from the end."}}},
    },
    {
        "name": "read",
        "description": "Read a text file under ~/OpenMontage (a path relative to it, or absolute inside it): numbered "
                       "lines from offset, at most limit of them.",
        "inputSchema": {"type": "object", "required": ["path"], "properties": {
            "path": {"type": "string"},
            "offset": {"type": "integer", "default": 1},
            "limit": {"type": "integer", "default": 400}}},
    },
    {
        "name": "look",
        "description": "Look at a picture or a clip under ~/OpenMontage. A picture comes back as itself (scaled to at "
                       "most 1568 px); a clip as one sheet of frames taken evenly through it, with its length and size.",
        "inputSchema": {"type": "object", "required": ["path"], "properties": {
            "path": {"type": "string"},
            "frames": {"type": "integer", "default": 6, "description": "For a clip: how many frames on the sheet (1–12)."}}},
    },
    {
        "name": "write",
        "description": "Write a text file under ~/OpenMontage, making its folders; replaces what was there.",
        "inputSchema": {"type": "object", "required": ["path", "content"], "properties": {
            "path": {"type": "string"},
            "content": {"type": "string"}}},
    },
    {
        "name": "list",
        "description": "List a folder under ~/OpenMontage: names, sizes, and which are folders.",
        "inputSchema": {"type": "object", "properties": {"path": {"type": "string", "default": "."}}},
    },
]


def inside(path):
    """The path, resolved inside ~/OpenMontage — or an error."""
    full = os.path.realpath(os.path.join(ROOT, os.path.expanduser(path or ".")))
    if full != ROOT and not full.startswith(ROOT + os.sep):
        raise ValueError(f"{path} is outside ~/OpenMontage")
    return full


def text(message, error=False):
    return {"content": [{"type": "text", "text": message}], "isError": error}


def shell(command, timeout):
    return subprocess.run(["/bin/zsh", "-c", PREAMBLE + command], capture_output=True, text=True, timeout=timeout)


def run(args):
    timeout = max(5, min(int(args.get("timeout_seconds") or 300), 900))
    started = time.time()
    try:
        done = shell(args["command"], timeout)
    except subprocess.TimeoutExpired:
        return text(f"still running after {timeout} s — stopped. Use start and job for long commands.", True)
    out = (done.stdout or "")[-20000:]
    err = (done.stderr or "")[-6000:]
    body = f"exit {done.returncode} · {time.time() - started:.1f} s\n" + out + (("\n[stderr]\n" + err) if err.strip() else "")
    return text(body, done.returncode != 0)


def start(args):
    os.makedirs(JOBS, exist_ok=True)
    job = time.strftime("%H%M%S-") + uuid.uuid4().hex[:4]
    base = os.path.join(JOBS, job)
    with open(base + ".json", "w") as f:
        json.dump({"id": job, "label": args.get("label", ""), "command": args["command"], "started": time.time()}, f)
    # The exit code is written when the command ends; the pid is the job's shell.
    wrapped = f"( {PREAMBLE}{args['command']} ) > {shlex.quote(base + '.log')} 2>&1; echo $? > {shlex.quote(base + '.exit')}"
    process = subprocess.Popen(["/bin/zsh", "-c", wrapped], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    with open(base + ".pid", "w") as f:
        f.write(str(process.pid))
    return text(f"started job {job}" + (f" ({args['label']})" if args.get("label") else ""))


def job_state(job, tail):
    base = os.path.join(JOBS, job)
    if not os.path.exists(base + ".json"):
        return None
    meta = json.load(open(base + ".json"))
    ran = time.time() - meta.get("started", time.time())
    if os.path.exists(base + ".exit"):
        state = f"finished, exit {open(base + '.exit').read().strip()}"
    else:
        state = "running"
    log = ""
    if tail and os.path.exists(base + ".log"):
        with open(base + ".log", "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - tail))
            log = f.read().decode("utf-8", "replace")
    return meta, state, ran, log


def job(args):
    tail = int(args.get("tail") or 4000)
    if not args.get("id"):
        if not os.path.isdir(JOBS):
            return text("no jobs")
        lines = []
        for name in sorted(os.listdir(JOBS), reverse=True):
            if name.endswith(".json"):
                found = job_state(name[:-5], 0)
                if found:
                    meta, state, ran, _ = found
                    lines.append(f"{meta['id']} · {state} · {ran / 60:.1f} min · {meta.get('label') or meta['command'][:80]}")
        return text("\n".join(lines[:30]) or "no jobs")
    found = job_state(args["id"], tail)
    if not found:
        return text(f"no job {args['id']}", True)
    meta, state, ran, log = found
    return text(f"{meta['id']} · {state} · {ran / 60:.1f} min\n{meta['command']}\n---\n{log}")


def read(args):
    path = inside(args["path"])
    if os.path.isdir(path):
        return text(f"{args['path']} is a folder: use list", True)
    offset = max(1, int(args.get("offset") or 1))
    limit = max(1, min(int(args.get("limit") or 400), 4000))
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    chosen = lines[offset - 1: offset - 1 + limit]
    body = "".join(f"{offset + i:6}\t{line}" for i, line in enumerate(chosen))
    more = len(lines) - (offset - 1 + len(chosen))
    return text(body + (f"\n… {more} more lines" if more > 0 else ""))


def picture(path, mime):
    """A picture for the model: scaled down with sips when it is big."""
    data = open(path, "rb").read()
    if len(data) > 1_500_000 or mime not in ("image/png", "image/jpeg"):
        out = tempfile.mktemp(suffix=".jpg")
        subprocess.run(["sips", "-Z", "1568", "-s", "format", "jpeg", path, "--out", out], capture_output=True)
        if os.path.exists(out):
            data, mime = open(out, "rb").read(), "image/jpeg"
            os.remove(out)
    return {"type": "image", "data": base64.b64encode(data).decode(), "mimeType": mime}


def look(args):
    path = inside(args["path"])
    ext = os.path.splitext(path)[1].lower()
    if ext in PICTURES:
        return {"content": [picture(path, PICTURES[ext]), {"type": "text", "text": args["path"]}], "isError": False}
    if ext in CLIPS:
        frames = max(1, min(int(args.get("frames") or 6), 12))
        probe = subprocess.run(["/opt/homebrew/bin/ffprobe", "-v", "error", "-show_entries", "format=duration:stream=width,height",
                                "-of", "json", path], capture_output=True, text=True)
        info = json.loads(probe.stdout or "{}")
        seconds = float(info.get("format", {}).get("duration", 0) or 0)
        size = next((f"{s['width']}×{s['height']}" for s in info.get("streams", []) if "width" in s), "?")
        columns = min(frames, 3)
        rows = (frames + columns - 1) // columns
        rate = frames / seconds if seconds > 0 else 1
        sheet = tempfile.mktemp(suffix=".jpg")
        subprocess.run([FFMPEG, "-loglevel", "error", "-y", "-i", path, "-vf",
                        f"fps={rate:.4f},scale=512:-2,tile={columns}x{rows}", "-frames:v", "1", "-q:v", "4", sheet],
                       capture_output=True)
        if not os.path.exists(sheet):
            return text(f"could not take frames from {args['path']}", True)
        content = [picture(sheet, "image/jpeg"),
                   {"type": "text", "text": f"{args['path']} · {seconds:.1f} s · {size} · {frames} frames, left to right, top to bottom"}]
        os.remove(sheet)
        return {"content": content, "isError": False}
    return text(f"{args['path']} is not a picture or a clip: use read", True)


def write(args):
    path = inside(args["path"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(args["content"])
    return text(f"wrote {len(args['content'])} characters to {args['path']}")


def listing(args):
    path = inside(args.get("path") or ".")
    rows = []
    for name in sorted(os.listdir(path)):
        full = os.path.join(path, name)
        if os.path.isdir(full):
            rows.append(f"{name}/")
        else:
            rows.append(f"{name}  {os.path.getsize(full):,} B")
    return text("\n".join(rows) or "(empty)")


CALLS = {"run": run, "start": start, "job": job, "read": read, "look": look, "write": write, "list": listing}


def answer(message):
    method, ident = message.get("method"), message.get("id")
    if ident is None:
        return None                                   # a notification: nothing to say
    if method == "initialize":
        version = (message.get("params") or {}).get("protocolVersion") or "2025-06-18"
        result = {"protocolVersion": version, "capabilities": {"tools": {}},
                  "serverInfo": {"name": "openmontage-box", "version": "1.0"}}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        params = message.get("params") or {}
        call = CALLS.get(params.get("name"))
        if not call:
            return {"jsonrpc": "2.0", "id": ident, "error": {"code": -32602, "message": f"no tool {params.get('name')}"}}
        try:
            result = call(params.get("arguments") or {})
        except Exception as e:                        # the tool's trouble is the model's to read
            result = text(f"{type(e).__name__}: {e}", True)
    elif method == "ping":
        result = {}
    else:
        return {"jsonrpc": "2.0", "id": ident, "error": {"code": -32601, "message": f"no method {method}"}}
    return {"jsonrpc": "2.0", "id": ident, "result": result}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except ValueError:
            continue
        reply = answer(message)
        if reply is not None:
            sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
