"""What the box's ComfyUI is doing, for every tab and tool that shares it.

Every Studio tab and every OpenMontage tool queues on this one ComfyUI, and
each could see only its own job, and only that it was "running": a score
waited 58 minutes behind someone else's H3 test without knowing it, a
25-step picture ran twenty minutes with no way to tell slow from stuck, and a
score was cut off halfway twice in one day with no word of who or why (the
Studio agents' notebooks, 2026-09-28). This keeps, for everyone:

  GET  /kinclaw/progress[?prompt_id=]  the running job — whose, what, which
       node, which step of how many, for how long — the queue in order, how
       the last jobs ended (an interruption with who and why when it is
       known), and with `prompt_id` where that one job stands;
  POST /kinclaw/interrupt {prompt_id?, by, why}  an interruption that says
       who and why.

A plain /interrupt and a queue deletion are noted too, with where they came
from (address and program). Nothing here changes what ComfyUI does: events
are only watched on their way out, requests only on their way in.
"""
import json
import threading
import time
from collections import deque

from aiohttp import web

import nodes
from server import PromptServer

_lock = threading.Lock()
_running = {}                 # prompt_id -> {"since", "node", "node_since", "value", "max", "step_since", "nodes_done"}
_ended = deque(maxlen=40)     # how the last jobs ended
_origin = {}                  # prompt_id -> {"from", "program", "client", "at"}
_stops = deque(maxlen=30)     # interruptions and deletions asked for: {"at", "prompt_id", "by", "why", "from", "program"}

# What a job is, from its nodes' class types (first match wins).
_WHAT = [("MiniMaxH3", "H3 镜头"), ("MiniMaxMusic3", "MiniMax 配乐"), ("YuE", "YuE2 歌"), ("AceStep", "ACE-Step 歌"),
         ("ACEStep", "ACE-Step 歌"), ("StableAudio", "Stable Audio"), ("MoGe", "白模（MoGe）"), ("SeedVR2", "SeedVR2 放大"),
         ("RIFE", "RIFE 补帧"), ("Trellis", "3D 模型"), ("Pixal3D", "3D 模型"), ("Hunyuan3D", "3D 模型"), ("LTXV", "LTX 视频"),
         ("Wan", "Wan 视频"), ("QwenImage", "Qwen 出图"), ("KSampler", "出图"), ("SamplerCustom", "生成")]
# Whose, from the client id or the names it saves under.
_WHOSE = [("kinclaw-film", "Film"), ("kinclaw-score", "Film"), ("kinclaw-motion", "Motion"), ("kinclaw-whole", "Motion"),
          ("kinclaw-comfy", "Comfy 标签"), ("pixelle", "Pixelle"), ("openmontage", "Montage"), ("montage", "Montage"),
          ("kinclaw", "KinClaw")]


def _program(ua):
    ua = ua or ""
    if "KinClaw" in ua or "CFNetwork" in ua:
        return "Mac 上的 KinClaw"
    if "Mozilla" in ua:
        return "浏览器（ComfyUI 页面）"
    if "python-requests" in ua or "aiohttp" in ua or "Python" in ua or "httpx" in ua:
        return "python 脚本"
    if "curl" in ua:
        return "curl"
    return ua[:40] or "不明"


def _where(remote):
    return "盒子本机" if remote in ("127.0.0.1", "::1", None) else remote


def _label(graph, client):
    """(tab, what) for a job: whose it is from its client id or the names it saves under, what it
    makes from its nodes."""
    graph = graph if isinstance(graph, dict) else {}
    client = str(client or "")
    saves = " ".join(str((n.get("inputs") or {}).get("filename_prefix", "")) for n in graph.values() if isinstance(n, dict))
    types = [str(n.get("class_type", "")) for n in graph.values() if isinstance(n, dict)]
    tab = next((name for key, name in _WHOSE if key in client.lower() or key in saves.lower()), None)
    what = next((label for key, label in _WHAT if any(key in t for t in types)), None)
    return tab, what


def _whose(item):
    """Whose a queued or running item is, and what it makes."""
    pid = item[1]
    graph = item[2] if len(item) > 2 and isinstance(item[2], dict) else {}
    extra = item[3] if len(item) > 3 and isinstance(item[3], dict) else {}
    client = str(extra.get("client_id") or "")
    tab, what = _label(graph, client)
    origin = _origin.get(pid, {})
    return {"prompt_id": pid, "tab": tab, "what": what, "client": client or None,
            "from": origin.get("from"), "program": origin.get("program"), "nodes": len(graph)}


def _observe(event, data):
    if not isinstance(data, dict):
        return
    pid = data.get("prompt_id")
    if not pid:
        return
    now = time.time()
    with _lock:
        if event == "execution_start":
            _running.setdefault(pid, {"since": now, "nodes_done": 0})
        elif event == "executing":
            st = _running.setdefault(pid, {"since": now, "nodes_done": 0})
            node = data.get("node")
            if node is None:
                return
            if st.get("node") != node:
                if st.get("node") is not None:
                    st["nodes_done"] = st.get("nodes_done", 0) + 1
                st.update(node=node, node_since=now, value=None, max=None, step_since=None)
        elif event == "progress":
            st = _running.setdefault(pid, {"since": now, "nodes_done": 0})
            node = data.get("node")
            if node is not None and node != st.get("node"):
                st.update(node=node, node_since=now)
            value = data.get("value")
            if value != st.get("value"):
                st["step_since"] = now
            st.update(value=value, max=data.get("max"))
        elif event in ("execution_success", "execution_error", "execution_interrupted"):
            _end(pid, {"execution_success": "done", "execution_error": "error", "execution_interrupted": "interrupted"}[event],
                 data, now)


def _end(pid, how, data, now):
    """A job's end, kept with who stopped it when somebody said so (call with _lock held)."""
    if any(e["prompt_id"] == pid for e in _ended):
        _running.pop(pid, None)
        return
    st = _running.pop(pid, {})
    entry = {"prompt_id": pid, "end": how, "at": now, "took_s": round(now - st["since"], 1) if "since" in st else None,
             "node": data.get("node_id") or st.get("node"), "class": data.get("node_type")}
    if how == "error":
        entry["error"] = str(data.get("exception_message", ""))[:300]
    if how == "interrupted":
        # The stop that was asked for this job — or, unnamed, any stop just before it ended.
        stop = next((s for s in reversed(_stops) if s.get("prompt_id") == pid), None) or \
            next((s for s in reversed(_stops) if not s.get("prompt_id") and now - s["at"] < 120), None)
        if stop:
            entry.update(by=stop.get("by"), why=stop.get("why"), stop_from=stop.get("from"), stop_program=stop.get("program"))
    origin = _origin.get(pid)
    if origin:
        # The job's name and where it came from; `at` stays the time it ended.
        entry.update({("queued_at" if k == "at" else k): v for k, v in origin.items()})
    _ended.append(entry)


def _from_history(pid):
    """A finished job ComfyUI sent no events about (queued without a client id)."""
    item = PromptServer.instance.prompt_queue.history.get(pid)
    if not item:
        return None
    status = item.get("status") or {}
    events = [m[0] for m in status.get("messages", []) if isinstance(m, (list, tuple)) and m]
    how = "interrupted" if "execution_interrupted" in events else "error" if status.get("status_str") == "error" else "done"
    return {"prompt_id": pid, "end": how}


def snapshot(prompt_id=None):
    queue = PromptServer.instance.prompt_queue
    running, queued = queue.get_current_queue_volatile()
    queued = sorted(queued, key=lambda it: it[0])
    now = time.time()
    with _lock:
        run = []
        for item in running:
            entry = _whose(item)
            st = _running.get(item[1], {})
            node = st.get("node")
            graph = item[2] if isinstance(item[2], dict) else {}
            entry.update(
                for_s=round(now - st["since"], 1) if "since" in st else None,
                node=node, node_class=(graph.get(node) or {}).get("class_type") if node is not None else None,
                node_s=round(now - st["node_since"], 1) if st.get("node_since") else None,
                value=st.get("value"), max=st.get("max"),
                step_s=round(now - st["step_since"], 1) if st.get("step_since") else None,
                nodes_done=st.get("nodes_done", 0))
            run.append(entry)
        pending = []
        for item in queued:
            entry = _whose(item)
            at = _origin.get(item[1], {}).get("at")
            entry["waiting_s"] = round(now - at, 1) if at else None
            pending.append(entry)
        out = {"now": now, "running": run, "pending": pending, "ended": list(_ended)[-12:], "stops": list(_stops)[-8:]}
        if prompt_id:
            mine = None
            for entry in run:
                if entry["prompt_id"] == prompt_id:
                    mine = {"state": "running", **entry}
            for i, entry in enumerate(pending):
                if entry["prompt_id"] == prompt_id:
                    mine = {"state": "pending", "ahead": len(run) + i, **entry}
            if mine is None:
                ended = next((e for e in reversed(_ended) if e["prompt_id"] == prompt_id), None)
                mine = {"state": "ended", **ended} if ended else None
        # Jobs that ended with nothing said about them: read from ComfyUI's history.
        for pid in [p for p in _running if p not in {e["prompt_id"] for e in run}]:
            done = _from_history(pid)
            if done:
                _end(pid, done["end"], {}, now)
    if prompt_id and mine is None:
        done = _from_history(prompt_id)
        mine = {"state": "ended", **done} if done else {"state": "unknown", "prompt_id": prompt_id}
    if prompt_id:
        out["mine"] = mine
    return out


def _noted(path, request, body, response):
    now = time.time()
    program, where = _program(request.headers.get("User-Agent")), _where(request.remote)
    with _lock:
        if path == "/prompt":
            try:
                pid = json.loads(response.body).get("prompt_id")
            except Exception:
                pid = None
            if pid:
                tab, what = _label(body.get("prompt"), body.get("client_id"))
                _origin[pid] = {"from": where, "program": program, "client": body.get("client_id"), "at": now,
                                "tab": tab, "what": what}
                if len(_origin) > 400:
                    for old in list(_origin)[:100]:
                        _origin.pop(old, None)
        elif path == "/interrupt":
            pid = body.get("prompt_id")
            if not pid:
                running, _ = PromptServer.instance.prompt_queue.get_current_queue_volatile()
                pid = running[0][1] if running else None
            _stops.append({"at": now, "prompt_id": pid, "by": None, "why": None, "from": where, "program": program,
                           "how": "interrupt"})
        elif path == "/queue" and (body.get("clear") or body.get("delete")):
            _stops.append({"at": now, "prompt_id": None, "deleted": body.get("delete") or "all pending",
                           "by": None, "why": None, "from": where, "program": program, "how": "queue"})


@web.middleware
async def _watch_requests(request, handler):
    path = request.path[4:] if request.path.startswith("/api/") else request.path
    if request.method != "POST" or path not in ("/prompt", "/interrupt", "/queue"):
        return await handler(request)
    try:
        body = json.loads(await request.read() or b"{}")
        body = body if isinstance(body, dict) else {}
    except Exception:
        body = {}
    response = await handler(request)
    try:
        _noted(path, request, body, response)
    except Exception:
        pass
    return response


def install():
    server = PromptServer.instance
    if getattr(server, "_kinclaw_progress", False):
        return
    server._kinclaw_progress = True

    send = server.send_sync

    def send_sync(event, data, sid=None):
        try:
            _observe(event, data)
        except Exception:
            pass
        return send(event, data, sid)

    server.send_sync = send_sync
    try:
        server.app.middlewares.append(_watch_requests)
    except Exception:          # a frozen app: the requests go unwatched, the events still count
        pass

    @server.routes.get("/kinclaw/progress")
    async def progress(request):
        return web.json_response(snapshot(request.query.get("prompt_id")))

    @server.routes.post("/kinclaw/interrupt")
    async def interrupt(request):
        try:
            body = await request.json()
        except Exception:
            body = {}
        pid = body.get("prompt_id")
        running, _ = server.prompt_queue.get_current_queue_volatile()
        current = running[0][1] if running else None
        with _lock:
            _stops.append({"at": time.time(), "prompt_id": pid or current, "by": str(body.get("by") or "")[:80] or None,
                           "why": str(body.get("why") or "")[:300] or None, "from": _where(request.remote),
                           "program": _program(request.headers.get("User-Agent")), "how": "interrupt"})
        if pid:
            stopped = server.prompt_queue.interrupt_if_running(pid)
        else:
            nodes.interrupt_processing()
            stopped = current is not None
        return web.json_response({"stopped": bool(stopped), "prompt_id": pid or current})
