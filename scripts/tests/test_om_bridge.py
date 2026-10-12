"""om_bridge's jobs: one whose shell is gone without an exit code is not "running" for ever.
Run: python3 -I scripts/tests/test_om_bridge.py"""
import importlib.util
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("om", os.path.join(HERE, "../../KinClawMac/Resources/om_bridge.py"))
om = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(om)
except SystemExit:
    pass
om.JOBS = tempfile.mkdtemp()


def job(name, pid, exit_code=None):
    base = os.path.join(om.JOBS, name)
    json.dump({"id": name, "command": "x", "started": time.time()}, open(base + ".json", "w"))
    open(base + ".pid", "w").write(str(pid))
    if exit_code is not None:
        open(base + ".exit", "w").write(str(exit_code))


job("live", os.getpid())
job("dead", 999_999)
job("done", 999_999, 0)
expected = {"live": "running", "dead": "ended without an exit code", "done": "finished, exit 0"}
failures = 0
for name, want in expected.items():
    state = om.job_state(name, 0)[1]
    ok = state.startswith(want)
    print(("ok   " if ok else "FAIL ") + f"{name}: {state}")
    failures += 0 if ok else 1
sys.exit(1 if failures else 0)
