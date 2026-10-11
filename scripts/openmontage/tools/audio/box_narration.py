"""A whole narration in the box's own voice: one take, one narrator, cut per line, timed to the character.

Why one take: 8102 designs the voice anew on every call, so a script read line by line is a
different person on every line. Read in one take it is one person — but a whole take is a new
draw too: the voice auditioned and liked is not the voice the full script comes back in
(2026-09-30, faith.localkin.ai's timeline film: the audition was 201 Hz and slow, five full takes
came back 164–188 Hz and faster). So the script is read `takes` times and the take closest to
what was wanted is kept — to `reference_audio` (the audition the person picked) in pitch and
pace, or to `target_chars_per_second`, or else the most typical of the takes.

Then the take is timed: faster-whisper (small, on the box) hears it and its timings are pinned
onto the script's OWN characters — it mishears names (爱任纽 → 爱任牛) and writes numbers as
digits, so its text is only a clock. The take is cut at the quietest point between lines, one
clip per line, every pause between lines at least `min_pause_seconds`; a line can hold longer
after it (`extra_tail_seconds`, for a quote that should land) and the last one holds
`tail_seconds` for the end card.

Out, in output_dir: take-N.wav, line-NN.wav and narration.json — each line's clip, its start in
the film, the time of every character in its line (and of every word, when the lines mark words
with "/"), and the captions grouped by Chinese clause in film time. Reveal what the voice names
when it names it: find the name in lines[i].chars and cue on its first character.
"""

from __future__ import annotations

import difflib
import json
import math
import re
import time
import wave
from pathlib import Path
from typing import Any

import numpy as np

from tools.audio.box_tts import DESIGN_URL, PRESET_URL, synthesize, up
from tools.base_tool import (
    BaseTool,
    Determinism,
    ExecutionMode,
    ResourceProfile,
    RetryPolicy,
    ToolResult,
    ToolRuntime,
    ToolStability,
    ToolStatus,
    ToolTier,
)

KEEP = re.compile(r"[一-鿿A-Za-z0-9]")      # what is spoken, and aligned
CLAUSE_END = re.compile(r"[，。；：！？、—…,.;:!?]+$")  # a caption line ends here
STRIP = re.compile(r"[，。；：！？、—…,.;:!?「」『』“”\"]")  # not shown in a caption (《》 stays: a title)
SENTENCE_END = re.compile(r"[。！？!?.…；;]$")
CN_DIGIT = dict(zip("0123456789", "〇一二三四五六七八九"))
PROMPT_ZH = "以下是普通话的句子，使用简体中文。"

_whisper_models: dict[str, Any] = {}


def _whisper(size: str):
    if size not in _whisper_models:
        from faster_whisper import WhisperModel
        _whisper_models[size] = WhisperModel(size, device="cpu", compute_type="int8")
    return _whisper_models[size]


def _mono(path: Path) -> tuple[np.ndarray, int, int, int]:
    """Samples as float mono, plus the file's rate, width and channel count (to write clips back alike)."""
    with wave.open(str(path)) as w:
        sr, ch, sw, n = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        raw = np.frombuffer(w.readframes(n), dtype=np.int16)
    x = raw.astype(np.float32).reshape(-1, ch).mean(1) / 32768.0 if ch > 1 else raw.astype(np.float32) / 32768.0
    return x, sr, sw, ch


def f0_median(x: np.ndarray, sr: int) -> float:
    """Median pitch of the voiced 40 ms frames (autocorrelation on an 8 kHz copy)."""
    k = max(1, sr // 8000)
    if k > 1:
        x = x[: len(x) // k * k].reshape(-1, k).mean(1)
        sr //= k
    n, lo, hi = int(0.04 * sr), int(sr / 400), int(sr / 70)
    thr = 0.3 * float(np.sqrt(np.mean(x ** 2)))
    out = []
    for s in range(0, len(x) - n, n // 2):
        fr = x[s:s + n] - x[s:s + n].mean()
        if np.sqrt(np.mean(fr ** 2)) < thr:
            continue
        ac = np.correlate(fr, fr, "full")[n - 1:]
        j = lo + int(np.argmax(ac[lo:hi]))
        if ac[j] > 0.4 * ac[0]:
            out.append(sr / j)
    return float(np.median(out)) if out else 0.0


def heard(path: Path, size: str, language: str) -> list[tuple[str, float, float]]:
    """(character, start, end) for every spoken character whisper hears."""
    segments, _ = _whisper(size).transcribe(str(path), language=language, word_timestamps=True,
                                            initial_prompt=PROMPT_ZH if language == "zh" else None)
    out: list[tuple[str, float, float]] = []
    for seg in segments:
        for w in seg.words or []:
            cs = [c.lower() for c in "".join(CN_DIGIT.get(c, c) for c in w.word.strip()) if KEEP.match(c)]
            if not cs:
                continue
            step = (w.end - w.start) / len(cs)
            out += [(c, w.start + i * step, w.start + (i + 1) * step) for i, c in enumerate(cs)]
    return out


def _units(line: str) -> list[str]:
    """A line's words: "/"-marked when the writer marked them, else one per spoken character
    (punctuation rides with the character before it)."""
    if "/" in line:
        return [w for w in line.split("/") if w]
    units: list[str] = []
    for c in line:
        if KEEP.match(c) or not units:
            units.append(c)
        else:
            units[-1] += c
    return units


def pin(rec: list[tuple[str, float, float]], script: list[str], total: float) -> tuple[list[tuple[float, float]], int]:
    """Times for every script character: whisper's where the characters agree, spread over
    whisper's span where they disagree, interpolated where whisper heard nothing."""
    sm = difflib.SequenceMatcher(None, "".join(c for c, *_ in rec), "".join(script), autojunk=False)
    times: list[tuple[float, float] | None] = [None] * len(script)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                times[j1 + k] = rec[i1 + k][1:]
        elif tag == "replace":
            a, b = rec[i1][1], rec[i2 - 1][2]
            for k in range(j2 - j1):
                times[j1 + k] = (a + (b - a) * k / (j2 - j1), a + (b - a) * (k + 1) / (j2 - j1))
    k = 0
    while k < len(times):
        if times[k] is not None:
            k += 1
            continue
        j = k
        while j < len(times) and times[j] is None:
            j += 1
        a = times[k - 1][1] if k else 0.0
        b = times[j][0] if j < len(times) else total
        for q in range(k, j):
            times[q] = (a + (b - a) * (q - k) / (j - k), a + (b - a) * (q - k + 1) / (j - k))
        k = j
    return times, sum(bl.size for bl in sm.get_matching_blocks())  # type: ignore[return-value]


class BoxNarration(BaseTool):
    name = "box_narration"
    version = "0.1.0"
    tier = ToolTier.VOICE
    capability = "narration"
    provider = "qwen3_tts_box"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.STOCHASTIC
    runtime = ToolRuntime.LOCAL_GPU
    agent_skills = ["narrated-motion-film"]
    dependencies = ["python:faster_whisper", "python:numpy"]

    install_instructions = (
        "The box's voices (:8102 VoiceDesign, :8101 presets — see box_tts) and faster-whisper with the "
        "Systran/faster-whisper-small model in the OpenMontage venv."
    )
    capabilities = ["narration", "one_take", "take_selection", "character_timing", "chinese_captions"]
    supports = {"voice_design": True, "offline": True, "chinese": True}
    best_for = [
        "a whole film's narration in one voice, with every line cut and every character timed",
        "reveals written on the word (names, numbers, quotes) and Chinese captions by clause",
    ]
    not_good_for = ["a single line (use box_tts)", "voice cloning"]
    quality_score = 0.92
    latency_p50_seconds = 90

    input_schema = {
        "type": "object",
        "required": ["lines", "output_dir"],
        "properties": {
            "lines": {"type": "array", "items": {"type": "string"}, "description": (
                "The script, one line per scene/frame, exactly as it should be read. Mark words with / to time "
                "words, not just characters: \"起点/是/爱任纽——/他/听过/坡旅甲，\". The / are never read.")},
            "output_dir": {"type": "string"},
            "instruct": {"type": "string", "description": "8102: the narrator in words (Chinese works best)"},
            "voice": {"type": "string", "description": "8101 preset id; with preset: true"},
            "preset": {"type": "boolean", "default": False},
            "takes": {"type": "integer", "default": 3, "description": "How many full takes to read and choose from (8102). 1–8."},
            "reference_audio": {"type": "string", "description": "The audition the person liked: keep the take closest to it in pitch and pace"},
            "target_chars_per_second": {"type": "number", "description": "Without a reference: the pace wanted (a calm documentary ≈ 3)"},
            "lead_seconds": {"type": "number", "default": 0.8, "description": "Silence before the first word"},
            "min_pause_seconds": {"type": "number", "default": 0.9, "description": "Least pause between lines"},
            "extra_tail_seconds": {"type": "object", "description": "{\"4\": 2.0} — line 4 (1-based) holds 2 s longer after it"},
            "tail_seconds": {"type": "number", "default": 4.0, "description": "How long the last line holds after its last word"},
            "language": {"type": "string", "default": "Chinese"},
            "whisper_model": {"type": "string", "default": "small"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=4, ram_mb=2000, vram_mb=0, disk_mb=200, network_required=False)
    retry_policy = RetryPolicy(max_retries=0, retryable_errors=[])
    idempotency_key_fields = ["lines", "instruct", "voice", "takes", "reference_audio"]
    side_effects = ["writes take-N.wav, line-NN.wav and narration.json to output_dir"]
    user_visible_verification = [
        "Listen to the chosen take whole: it is the voice that was picked, names and 多音字 read right",
        "Each line-NN.wav holds exactly its line — nothing clipped, nothing from the next",
    ]

    def get_status(self) -> ToolStatus:
        try:
            import faster_whisper  # noqa: F401
        except ImportError:
            return ToolStatus.UNAVAILABLE
        return ToolStatus.AVAILABLE if (up(DESIGN_URL) or up(PRESET_URL)) else ToolStatus.UNAVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def estimate_runtime(self, inputs: dict[str, Any]) -> float:
        chars = sum(len(l) for l in inputs.get("lines", []))
        return (8 + chars / 12) * int(inputs.get("takes", 3))

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        start = time.time()
        raw_lines = inputs.get("lines") or []
        if isinstance(raw_lines, str):
            raw_lines = [l for l in raw_lines.splitlines() if l.strip()]
        raw_lines = [l.strip() for l in raw_lines if l and l.strip()]
        if not raw_lines:
            return ToolResult(success=False, error="lines is empty")
        out_dir = Path(inputs["output_dir"])
        out_dir.mkdir(parents=True, exist_ok=True)
        preset = bool(inputs.get("preset"))
        takes = max(1, min(8, int(inputs.get("takes", 1 if preset else 3))))
        lang_tts = inputs.get("language", "Chinese")
        lang = "zh" if lang_tts.lower().startswith(("chinese", "zh", "mandarin")) else lang_tts[:2].lower()
        size = inputs.get("whisper_model", "small")

        units = [_units(l) for l in raw_lines]
        spoken = ["".join(u).replace("/", "") for u in units]
        tts_text = "".join(s if SENTENCE_END.search(s) else s + "。" for s in spoken)  # no newlines: nothing to split on
        script: list[str] = []
        owner: list[tuple[int, int]] = []  # (line, unit) of each script character
        for li, us in enumerate(units):
            for ui, u in enumerate(us):
                for c in u:
                    if KEEP.match(c):
                        script.append(c.lower())
                        owner.append((li, ui))
        if not script:
            return ToolResult(success=False, error="nothing in lines is spoken text")

        # ── read the whole script `takes` times ─────────────────────────────────────
        rows = []
        for k in range(1, takes + 1):
            path = out_dir / f"take-{k}.wav"
            try:
                path.write_bytes(synthesize(tts_text, instruct=inputs.get("instruct"), voice=inputs.get("voice"),
                                            preset=preset, language=lang_tts))
            except Exception as exc:
                return ToolResult(success=False, error=f"take {k}: the box's TTS failed: {exc}")
            x, sr, _sw, _ch = _mono(path)
            rec = heard(path, size, lang)
            dur = len(x) / sr
            _times, matched = pin(rec, script, dur)
            span = (rec[-1][2] - rec[0][1]) if len(rec) > 1 else dur
            rows.append({"take": k, "path": str(path), "duration_s": round(dur, 2), "f0_hz": round(f0_median(x, sr), 1),
                         "chars_per_s": round(len(script) / max(span, 0.1), 2), "matched": round(matched / len(script), 3),
                         "_rec": rec})

        # ── choose ──────────────────────────────────────────────────────────────────
        target = None
        ref = inputs.get("reference_audio")
        if ref:
            rx, rsr, _a, _b = _mono(Path(ref))
            rrec = heard(Path(ref), size, lang)
            rspan = (rrec[-1][2] - rrec[0][1]) if len(rrec) > 1 else len(rx) / rsr
            target = {"f0_hz": f0_median(rx, rsr), "chars_per_s": len(rrec) / max(rspan, 0.1)}
        elif inputs.get("target_chars_per_second"):
            target = {"chars_per_s": float(inputs["target_chars_per_second"])}
        whole = [r for r in rows if r["matched"] >= 0.75] or sorted(rows, key=lambda r: -r["matched"])[:1]
        median_pace = float(np.median([r["chars_per_s"] for r in whole]))

        def distance(r: dict) -> float:
            if target and "f0_hz" in target and target["f0_hz"] and r["f0_hz"]:
                return abs(math.log(r["f0_hz"] / target["f0_hz"])) + abs(math.log(r["chars_per_s"] / target["chars_per_s"]))
            aim = target["chars_per_s"] if target else median_pace
            return abs(math.log(r["chars_per_s"] / aim))

        best = min(whole, key=distance)
        warnings = []
        if best["matched"] < 0.75:
            warnings.append(f"no take was heard whole (best {best['matched']:.0%}) — listen for dropped or repeated words")

        # ── time the chosen take onto the script's own characters ───────────────────
        take_path = Path(best["path"])
        x, sr, sw, ch = _mono(take_path)
        with wave.open(str(take_path)) as w:
            pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch)
        total = len(pcm) / sr
        times, _m = pin(best["_rec"], script, total)
        per_line: list[list[tuple[str, float, float, int]]] = [[] for _ in units]
        for (li, ui), c, t in zip(owner, script, times):
            per_line[li].append((c, t[0], t[1], ui))

        # ── cut between lines at the middle of the longest silence near the seam ────
        hop = int(sr * 0.01)
        rms = np.sqrt(np.convolve(x ** 2, np.ones(hop) / hop, "same")[::hop] + 1e-12)
        db = 20 * np.log10(rms)
        silent = db < np.percentile(db, 95) - 35
        cuts, gaps = [0.0], []
        for li in range(len(units) - 1):
            a = per_line[li][-1][2] - 0.25 if per_line[li] else cuts[-1]
            b = per_line[li + 1][0][1] + 0.25 if per_line[li + 1] else a + 0.5
            fa, fb = max(0, int(a / 0.01)), min(len(silent), int(b / 0.01))
            best_run, run = (0, fa, fa), None
            for f in range(fa, fb + 1):
                if f < fb and silent[f]:
                    run = f if run is None else run
                elif run is not None:
                    if f - run > best_run[0]:
                        best_run = (f - run, run, f)
                    run = None
            if best_run[0] == 0 and fb > fa:
                f = fa + int(np.argmin(db[fa:fb]))
                best_run = (0, f, f)
            cuts.append((best_run[1] + best_run[2]) / 2 * 0.01)
            gaps.append(best_run[0] * 0.01)
        cuts.append(total)

        lead = float(inputs.get("lead_seconds", 0.8))
        min_pause = float(inputs.get("min_pause_seconds", 0.9))
        tail_last = float(inputs.get("tail_seconds", 4.0))
        extra = {int(k): float(v) for k, v in (inputs.get("extra_tail_seconds") or {}).items()}

        lines_out, film_t = [], 0.0
        for li in range(len(units)):
            s, e = int(cuts[li] * sr), int(cuts[li + 1] * sr)
            pad_front = lead if li == 0 else 0.0
            if li < len(units) - 1:
                pad_back = max(0.0, min_pause - gaps[li]) + extra.get(li + 1, 0.0)
            else:
                last_end = per_line[li][-1][2] if per_line[li] else cuts[-1]
                pad_back = max(0.0, tail_last - (cuts[-1] - last_end))
            clip = np.concatenate([np.zeros((int(pad_front * sr), ch), np.int16), pcm[s:e],
                                   np.zeros((int(pad_back * sr), ch), np.int16)])
            path = out_dir / f"line-{li + 1:02d}.wav"
            with wave.open(str(path), "wb") as w:
                w.setnchannels(ch); w.setsampwidth(sw); w.setframerate(sr); w.writeframes(clip.tobytes())
            base = cuts[li] - pad_front
            chars = [{"c": c, "start": round(a - base, 3), "end": round(b - base, 3)} for c, a, b, _u in per_line[li]]
            words = []
            for ui, u in enumerate(units[li]):
                mine = [(a, b) for _c, a, b, uu in per_line[li] if uu == ui]
                if mine:
                    words.append({"text": u, "start": round(mine[0][0] - base, 3), "end": round(mine[-1][1] - base, 3)})
            dur = round(len(clip) / sr, 3)
            lines_out.append({"index": li + 1, "text": raw_lines[li].replace("/", ""), "path": str(path),
                              "start_s": round(film_t, 3), "duration_s": dur,
                              "voice_start_s": chars[0]["start"] if chars else 0.0,
                              "voice_end_s": chars[-1]["end"] if chars else 0.0,
                              "chars": chars, "words": words})
            film_t += dur

        # ── captions: one per Chinese clause, words flush, film time ───────────────
        groups, cur = [], []
        for line in lines_out:
            for w in line["words"]:
                shown = STRIP.sub("", w["text"])
                if shown:
                    cur.append({"text": shown, "start": round(line["start_s"] + w["start"], 3),
                                "end": round(line["start_s"] + w["end"], 3)})
                if CLAUSE_END.search(w["text"]) and cur:
                    groups.append(cur); cur = []
            if cur:
                groups.append(cur); cur = []
        captions = []
        for gi, g in enumerate(groups):
            end = g[-1]["end"] + 0.12
            if gi + 1 < len(groups):
                end = min(end, groups[gi + 1][0]["start"])
            captions.append({"start": g[0]["start"], "end": round(end, 3), "text": "".join(w["text"] for w in g), "words": g})

        for r in rows:
            r.pop("_rec", None)
        doc = {"instruct": None if preset else inputs.get("instruct"), "voice": inputs.get("voice") if preset else None,
               "takes": rows, "chosen": best["path"], "chosen_by": ("reference_audio" if ref else
                                                                     "target_chars_per_second" if target else "typical pace"),
               "target": target, "lines": lines_out, "captions": captions, "total_s": round(film_t, 3),
               "warnings": warnings}
        meta = out_dir / "narration.json"
        meta.write_text(json.dumps(doc, ensure_ascii=False, indent=1))
        return ToolResult(
            success=True, artifacts=[str(meta), best["path"]] + [l["path"] for l in lines_out],
            duration_seconds=round(time.time() - start, 2), model="qwen3-tts + faster-whisper-" + size,
            data={"narration_json": str(meta), "chosen": best["path"], "total_s": round(film_t, 3),
                  "takes": rows, "lines": [{"index": l["index"], "duration_s": l["duration_s"], "path": l["path"]}
                                           for l in lines_out],
                  "captions": len(captions), "warnings": warnings})
