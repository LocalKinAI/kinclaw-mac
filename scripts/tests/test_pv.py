"""pv.py's wait: a look that gets no answer is not a failure (2026-10-10: one slow curl read as a
failed film that ran on for an hour). Run: python3 -I scripts/tests/test_pv.py"""
import contextlib
import importlib.util
import io
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("pv", os.path.join(HERE, "../../KinClawMac/Resources/pixelle/pv.py"))
pv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pv)

clock = [0.0]
pv.time.time = lambda: clock[0]
pv.time.sleep = lambda s: None
pv.ssh = lambda *a, **k: (0, "(log)", "")          # never the real box
fetched = []
pv.fetch_result = lambda result, request=None: fetched.append(result)


def run(script, timeout=540, lost=900, every=6):
    clock[0] = 0.0
    steps = iter(script)

    def api(method, path, body=None, timeout=20):
        clock[0] += every
        step = next(steps)
        if isinstance(step, Exception):
            raise step
        return step
    pv.api = api
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            pv.cmd_wait(types.SimpleNamespace(task="t1", timeout=timeout, every=every, lost=lost))
        return 0, out.getvalue()
    except pv.Failure as e:
        code = pv.EXIT_UNREACHABLE if isinstance(e, pv.Unreachable) else pv.EXIT_FETCH if isinstance(e, pv.FetchFailed) else pv.EXIT_FAILED
        return code, out.getvalue() + str(e)


running = {"status": "running", "progress": {"message": "media", "percentage": 40}}
done = {"status": "completed", "result": {"output_dir": "x"}}
slow = pv.Unreachable("box call failed (rc 28): curl: (28) Operation timed out after 20011 milliseconds")
failures = 0


def check(name, ok, detail):
    global failures
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else "\n     " + detail[-300:]))
    failures += 0 if ok else 1


code, out = run([running, slow, slow, running, done])
check("a slow look, then done: followed through and fetched", code == 0 and fetched and "answers again" in out, out)
code, out = run([running] + [slow] * 400, timeout=540, lost=900)
check("long silence within the wait: 'still following', not failed", code == 0 and "still following" in out, out)
code, out = run([running] + [slow] * 400, timeout=5000, lost=120)
check("silence past --lost: exit 3 (lost contact), not 1", code == pv.EXIT_UNREACHABLE and "lost contact" in out, out)
code, out = run([running, {"status": "failed", "error": "bad scene"}])
check("the job failing on the box: exit 1", code == pv.EXIT_FAILED and "failed" in out, out)
check("curl's transport codes are Unreachable", {7, 28, 52, 56, 255} <= pv.TRANSPORT, str(pv.TRANSPORT))

# Finished pictures handed in (2026-10-12: a video drawn with the app's 画 and fixed with 改): copied to the
# box in one tar stream, sent as paths under Pixelle's folder, refused before anything is copied when wrong.
import json
import tarfile
import tempfile

work = tempfile.mkdtemp()
pv.LOCAL_ROOT = work
shots = []
for i in range(3):
    path = os.path.join(work, "pic%d.png" % i)
    open(path, "wb").write(b"picture %d" % i)
    shots.append(path)
sent, copied = [], []


def box(cmd, stdin=None, timeout=120, binary=False):
    if "tar -x" in cmd:
        packed = tarfile.open(fileobj=io.BytesIO(stdin))
        copied.append({m.name: packed.extractfile(m).read() for m in packed.getmembers() if m.isfile()})
    return 0, b"" if binary else "", b"" if binary else ""


def api(method, path, body=None, timeout=20):
    sent.append((path, json.loads(json.dumps(body))))
    return {"task_id": "t2"}


pv.ssh, pv.api = box, api
pv.box_bytes = lambda path, timeout=120: json.dumps({"title": "x", "frames": [{"index": i} for i in range(3)]}).encode()


def submit(command, job):
    out = io.StringIO()
    with open(os.path.join(work, "job.json"), "w") as f:
        json.dump(job, f)
    try:
        with contextlib.redirect_stdout(out):
            command(types.SimpleNamespace(file=os.path.join(work, "job.json")))
        return None, out.getvalue()
    except pv.Failure as e:
        return str(e), out.getvalue()


base = {"text": "一\n\n二\n\n三", "mode": "fixed", "frame_template": "1920x1080/image_full.html"}
error, out = submit(pv.cmd_make, dict(base, images=shots))
body = sent[-1][1] if sent else {}
names = sorted(copied[-1]) if copied else []
check("every scene given: one tar with 01..03, sent as data/uploads paths, nothing to draw",
      error is None and names == ["./01.png", "./02.png", "./03.png"] and copied[-1]["./02.png"] == b"picture 1"
      and all(p.startswith("data/uploads/") and p.endswith("%02d.png" % (i + 1)) for i, p in enumerate(body.get("images", [])))
      and "nothing to draw" in out, "%s %s %s" % (error, names, out))
sent.clear(); copied.clear()
error, out = submit(pv.cmd_make, dict(base, images=[shots[0], None, shots[2]]))
check("a scene left out with no image_prompts: refused, nothing copied or sent",
      bool(error) and "have no picture" in error and not sent and not copied, str(error))
error, out = submit(pv.cmd_make, dict(base, images=[shots[0], None, shots[2]], image_prompts=["a", "b", "c"]))
check("a scene left out with image_prompts: drawn, the others given",
      error is None and bool(sent) and sent[-1][1]["images"][1] is None and "scenes [2] drawn" in out, "%s %s" % (error, out))
sent.clear(); copied.clear()
error, out = submit(pv.cmd_make, dict(base, images=shots[:2]))
check("one picture short: refused before copying", bool(error) and "splits into 3 scenes" in error and not copied, str(error))
error, out = submit(pv.cmd_make, dict(base, images=[shots[0], os.path.join(work, "gone.png"), shots[2]]))
check("a missing file: refused before copying", bool(error) and "not a file" in error and not copied, str(error))
error, out = submit(pv.cmd_rework, {"source": "20261012_220000_ab12", "images": {"2": shots[1]}})
check("rework with one picture: copied, sent as {'2': path}, enough on its own",
      error is None and list(sent[-1][1]["images"]) == ["2"] and sent[-1][1]["images"]["2"].endswith("/02.png")
      and sorted(copied[-1]) == ["./02.png"], "%s %s" % (error, out))
sent.clear(); copied.clear()
error, out = submit(pv.cmd_rework, {"source": "20261012_220000_ab12", "images": {"2": shots[1]}, "redraw": [2]})
check("rework: a scene both redrawn and given: refused", bool(error) and "not both" in error and not copied, str(error))

# Finished voice-overs (a narrator read and checked line by line), the same way as pictures.
lines = []
for i in range(3):
    path = os.path.join(work, "line%d.wav" % i)
    open(path, "wb").write(b"RIFF voice %d" % i)
    lines.append(path)
sent.clear(); copied.clear()
error, out = submit(pv.cmd_make, dict(base, images=shots, audios=lines))
body = sent[-1][1] if sent else {}
check("pictures and voice-overs for every scene: two tars, audios sent as .wav paths, nothing to voice",
      error is None and len(copied) == 2 and sorted(copied[-1]) == ["./01.wav", "./02.wav", "./03.wav"]
      and all(p.endswith("%02d.wav" % (i + 1)) for i, p in enumerate(body.get("audios", [])))
      and "nothing to voice" in out, "%s %s" % (error, out))
sent.clear(); copied.clear()
error, out = submit(pv.cmd_make, dict(base, images=shots, audios=[lines[0], shots[1], lines[2]]))
check("a picture given as a voice-over: refused before copying", bool(error) and "not a wav" in error and not copied, str(error))
error, out = submit(pv.cmd_rework, {"source": "20261012_220000_ab12", "audios": {"3": lines[2]}, "revoice": True})
check("rework: audios with revoice: refused", bool(error) and "not both" in error and not copied, str(error))
error, out = submit(pv.cmd_rework, {"source": "20261012_220000_ab12", "audios": {"3": lines[2]}})
check("rework with one voice-over: enough on its own, sent as {'3': path}",
      error is None and sent[-1][1]["audios"] == {"3": sent[-1][1]["audios"]["3"]} and sent[-1][1]["audios"]["3"].endswith("/03.wav"),
      "%s %s" % (error, out))
sys.exit(1 if failures else 0)
