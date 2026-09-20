#!/usr/bin/env python3
"""A second opinion, in numbers: Laya behind one small HTTP endpoint.

Laya (convaiinnovations/laya, Apache-2.0) is a 0.4B text decision model: give it
a state and typed questions, it answers with calibrated probabilities in one
forward pass — about 200 ms on this Mac's CPU. It cannot see. In the Film tab it
is shown what the reviewer with eyes *wrote down* about a take, beside the plan,
and its numbers are displayed next to the reviewer's verdict. Displayed, not
obeyed: measured on six takes whose faults were known, its readings did not
separate them (a take in which she walks off scored 0.36 for "does she walk
away"), which its own model card predicts for zero-shot use. The point of
showing them is to watch whether that changes — and every take now leaves
behind the description and the verdict it would need to be fine-tuned on.

    pip install laya fastapi uvicorn
    python3 scripts/laya_judge.py            # http://127.0.0.1:8005

    POST /decide  {"state": {...}, "questions": {...}}  ->  Laya's answers
    GET  /health

The weights come from the Hugging Face cache (HF_HUB_OFFLINE=1 by default here:
it serves what is on the disk and does not go looking).
"""
import os
import time

os.environ.setdefault("USE_TF", "0")               # TF's abseil can deadlock model construction
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="laya judge")
_router = None


def router():
    global _router
    if _router is None:
        from laya import Router
        _router = Router(max_loaded=2)             # english + multilingual both stay warm
    return _router


class Decide(BaseModel):
    state: dict
    questions: dict
    model: str | None = None


@app.get("/health")
def health():
    return {"ok": True, "loaded": _router is not None}


@app.post("/decide")
def decide(ask: Decide):
    started = time.time()
    try:
        result = router().predict(ask.state, ask.questions, **({"model": ask.model} if ask.model else {}))
    except Exception as error:                     # a bad question shape is the caller's to read
        raise HTTPException(status_code=400, detail=f"{type(error).__name__}: {error}")
    return {"answers": result.get("answers", {}), "routing": result.get("routing", {}),
            "ms": round((time.time() - started) * 1000)}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("LAYA_JUDGE_PORT", "8005")), log_level="warning")
