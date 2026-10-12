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
sys.exit(1 if failures else 0)
