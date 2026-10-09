"""MediaPipe 0.10 in an environment of its own (LocalKin box, 2026-10).

OpenMontage's face_tracker and eye_enhance use MediaPipe's legacy Solutions API: gone in MediaPipe
1.0, and its 0.10 releases want numpy < 2 and protobuf < 5, which OpenMontage's own environment
has moved past. So MediaPipe 0.10.21 lives in ~/kin-avatar/mediapipe/.venv (MEDIAPIPE_PYTHON to
point elsewhere — Jacky, 2026-10-04: 「两个都要」), and a tool that needs it runs its own
execute() there: the same code, unchanged, in an environment that has what it imports.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any, Optional

ROOT = Path(__file__).resolve().parent.parent
_MARK = "@@OPENMONTAGE_RESULT@@"


def python() -> Optional[str]:
    exe = os.environ.get("MEDIAPIPE_PYTHON") or os.path.expanduser("~/kin-avatar/mediapipe/.venv/bin/python")
    return exe if os.path.exists(exe) else None


def importable() -> bool:
    """MediaPipe with its Solutions API and OpenCV, in this environment."""
    try:
        import cv2  # noqa: F401
        import mediapipe as mp

        return hasattr(mp, "solutions")
    except ImportError:
        return False


def execute(module: str, cls: str, inputs: dict[str, Any], timeout: int = 7200):
    """`cls().execute(inputs)` in the MediaPipe environment, and the ToolResult it returned."""
    from tools.base_tool import ToolResult

    exe = python()
    if exe is None:
        return ToolResult(success=False, error="MediaPipe's environment is not set up "
                                               "(MEDIAPIPE_PYTHON, or ~/kin-avatar/mediapipe/.venv)")
    code = (
        "import json, sys\n"
        f"sys.path.insert(0, {str(ROOT)!r})\n"
        f"from {module} import {cls}\n"
        f"r = {cls}().execute(json.loads(sys.stdin.read()))\n"
        "out = {'success': r.success, 'data': r.data, 'artifacts': r.artifacts, 'error': r.error}\n"
        f"print({_MARK!r} + json.dumps(out, default=str))\n"
    )
    try:
        done = subprocess.run([exe, "-c", code], input=json.dumps(inputs), capture_output=True,
                              text=True, timeout=timeout, cwd=str(ROOT))
    except subprocess.TimeoutExpired:
        return ToolResult(success=False, error=f"MediaPipe environment: no answer in {timeout} s")
    for line in reversed(done.stdout.splitlines()):
        if line.startswith(_MARK):
            out = json.loads(line[len(_MARK):])
            data = dict(out.get("data") or {}, environment="mediapipe 0.10 (" + exe + ")")
            return ToolResult(success=out["success"], data=data, artifacts=out.get("artifacts") or [],
                              error=out.get("error"))
    return ToolResult(success=False, error="MediaPipe environment: " + (done.stderr[-1500:] or done.stdout[-500:]))
