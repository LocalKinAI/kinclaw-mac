"""Karaoke captions for a HyperFrames film, written as a sub-composition — right for Chinese.

Three things went wrong with Chinese captions the first time (faith.localkin.ai's timeline film,
2026-09-30) and are right here by construction:
  · lines broke by word count ("纸 每一寸 都 | 写着 一个 名字") — here a caption is one clause of
    the script, split at ，。；：！？ (box_narration groups them);
  · words were set apart with gaps — Chinese words sit flush;
  · a font stack came through as ONE quoted family name, so the text fell back to Georgia —
    here families are named one by one, each with an @font-face to a file that ships;
  · and the last caption stayed on screen through the silent end card — here it clears.

Captions show only what is not already on screen: pass `skip_texts` for lines the picture writes
out itself (a quote taking the whole frame), and they step aside.

The result gives the host <div> to put in index.html.
"""

from __future__ import annotations

import html
import json
import time
from pathlib import Path
from typing import Any

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

_TEMPLATE = """<template id="captions-template" data-composition-id="captions" data-width="{W}" data-height="{H}">
<script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
<style>
{FACES}
  #captions-root {{ position: absolute; inset: 0; pointer-events: none; }}
  .caption-layer {{ position: absolute; inset: 0; z-index: 20; pointer-events: none; }}
  .caption-stage {{ position: absolute; left: 0; right: 0; top: {BAND_TOP}px; height: {BAND_H}px;
    display: flex; align-items: center; justify-content: center; }}
  .caption-group {{ position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; opacity: 0; }}
  .caption-line {{ max-width: 80%; display: flex; flex-wrap: wrap; justify-content: center; gap: 0.1em 0;
    font-family: {STACK}; font-weight: {WEIGHT}; font-size: {SIZE}px; line-height: 1.3; letter-spacing: {TRACK}; }}
  .caption-word {{ display: inline-block; color: {UPCOMING}; }}
  .caption-word.is-active {{ color: {ACTIVE}; }}
  .caption-word.is-spoken {{ color: {SPOKEN}; }}
</style>
<div id="captions-root" data-composition-id="captions" data-timeline-locked data-start="0" data-duration="{DUR}"
  data-fps="30" data-width="{W}" data-height="{H}">
  <div class="caption-layer" aria-hidden="true"><div id="caption-stage" class="caption-stage"></div></div>
</div>
<script>
  var GROUPS = {GROUPS};
  var DURATION = {DUR};
  (function () {{
    var stage = document.getElementById("caption-stage");
    GROUPS.forEach(function (group, g) {{
      var groupEl = document.createElement("div");
      groupEl.className = "caption-group";
      groupEl.id = "caption-group-" + g;
      var line = document.createElement("div");
      line.className = "caption-line";
      group.words.forEach(function (w, i) {{
        var span = document.createElement("span");
        span.className = "caption-word";
        span.id = "caption-word-" + g + "-" + i;
        span.textContent = String(w.text);
        line.appendChild(span);
      }});
      groupEl.appendChild(line);
      stage.appendChild(groupEl);
    }});
    var tl = gsap.timeline({{ paused: true }});
    GROUPS.forEach(function (group, g) {{
      var groupEl = document.getElementById("caption-group-" + g);
      var words = group.words;
      var next = GROUPS[g + 1];
      var start = Math.max(0, Number(group.start));
      var end = Math.min(next ? Number(next.start) : DURATION, Number(group.end) + 0.3);
      if (end <= start) end = start + 0.01;
      tl.set(groupEl, {{ opacity: 1 }}, start);
      tl.set(groupEl, {{ opacity: 0 }}, end);
      words.forEach(function (w, i) {{
        var el = document.getElementById("caption-word-" + g + "-" + i);
        var at = Math.max(start, Number(w.start));
        tl.set(el, {{ className: "caption-word" }}, start);
        tl.set(el, {{ className: "caption-word is-active" }}, at);
        var after = i + 1 < words.length ? Math.max(start, Number(words[i + 1].start)) : Math.min(end, Number(w.end) + 0.1);
        tl.set(el, {{ className: "caption-word is-spoken" }}, after);
      }});
    }});
    tl.to({{}}, {{ duration: DURATION }}, 0);
    window.__timelines["captions"] = tl;
  }})();
</script>
</template>
"""


class HyperFramesCaptions(BaseTool):
    name = "hf_captions"
    version = "0.1.0"
    tier = ToolTier.CORE
    capability = "subtitle"
    provider = "hyperframes"
    stability = ToolStability.BETA
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.DETERMINISTIC
    runtime = ToolRuntime.LOCAL
    agent_skills = ["narrated-motion-film", "hyperframes"]

    install_instructions = "Nothing to install: writes one HTML sub-composition."
    capabilities = ["karaoke_captions", "chinese_clause_captions", "hyperframes_subcomposition"]
    supports = {"chinese": True, "offline": True}
    best_for = ["captions for a HyperFrames film narrated with box_narration, Chinese above all"]
    not_good_for = ["burning captions into an existing video file (use subtitle_gen)"]
    quality_score = 0.85
    latency_p50_seconds = 1

    input_schema = {
        "type": "object",
        "required": ["output_path", "fonts"],
        "properties": {
            "narration_json": {"type": "string", "description": "box_narration's narration.json (its captions)"},
            "captions": {"type": "array", "description": "Or the groups themselves: [{start, end, words: [{text, start, end}]}] in film time"},
            "output_path": {"type": "string", "description": "e.g. <project>/hyperframes/compositions/captions.html"},
            "fonts": {"type": "array", "description": (
                "[{family, file}] — every family named, each with its font file relative to the HyperFrames "
                "project root (the render machine has no system CJK fonts): "
                "[{\"family\": \"Noto Serif SC\", \"file\": \"assets/fonts/NotoSerifSC-subset.woff2\"}]")},
            "width": {"type": "integer", "default": 1920},
            "height": {"type": "integer", "default": 1080},
            "duration_seconds": {"type": "number", "description": "Defaults to the narration's total"},
            "size_px": {"type": "integer", "default": 48},
            "weight": {"type": "integer", "default": 400},
            "letter_spacing": {"type": "string", "default": "0.04em"},
            "colors": {"type": "object", "description": "{spoken, active, upcoming} — default warm white / gold / dimmed"},
            "band_top_px": {"type": "integer", "description": "Default: 83 % of the height (content stays above)"},
            "skip_texts": {"type": "array", "items": {"type": "string"}, "description": "Caption lines the picture writes out itself (without punctuation)"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=1, ram_mb=64, vram_mb=0, disk_mb=5, network_required=False)
    retry_policy = RetryPolicy(max_retries=0, retryable_errors=[])
    idempotency_key_fields = ["narration_json", "captions", "fonts", "skip_texts"]
    side_effects = ["writes the captions sub-composition to output_path"]
    user_visible_verification = ["Snapshot a spoken line: one clause, the font right, the current word lit, nothing lingers at the end"]

    def get_status(self) -> ToolStatus:
        return ToolStatus.AVAILABLE

    def estimate_cost(self, inputs: dict[str, Any]) -> float:
        return 0.0

    def execute(self, inputs: dict[str, Any]) -> ToolResult:
        t0 = time.time()
        total = inputs.get("duration_seconds")
        groups = inputs.get("captions")
        if inputs.get("narration_json"):
            doc = json.loads(Path(inputs["narration_json"]).read_text())
            groups = groups or doc.get("captions")
            total = total or doc.get("total_s")
        if not groups:
            return ToolResult(success=False, error="no captions: give narration_json or captions")
        skip = {s.strip() for s in inputs.get("skip_texts") or []}
        kept = [g for g in groups if "".join(w["text"] for w in g["words"]) not in skip]
        fonts = inputs.get("fonts") or []
        if not fonts:
            return ToolResult(success=False, error="name the fonts with their files — a CJK caption without a shipped font renders in the wrong face")
        faces = "\n".join(
            f'  @font-face {{ font-family: "{f["family"]}"; src: url("{f["file"]}") format("{Path(f["file"]).suffix.lstrip(".").replace("ttf", "truetype").replace("otf", "opentype")}"); '
            f'font-weight: {f.get("weight", "200 900")}; font-style: normal; font-display: block; }}' for f in fonts)
        stack = ", ".join(f'"{f["family"]}"' for f in fonts) + ", serif"
        c = {"spoken": "#e8e4dc", "active": "#e8d4a0", "upcoming": "rgba(232, 228, 220, 0.45)", **(inputs.get("colors") or {})}
        W, H = int(inputs.get("width", 1920)), int(inputs.get("height", 1080))
        band_top = int(inputs.get("band_top_px") or round(H * 0.833))
        dur = float(total or (kept[-1]["end"] + 1.0))
        clean = [{"start": g["start"], "end": g["end"], "words": [{"text": w["text"], "start": w["start"], "end": w["end"]} for w in g["words"]]}
                 for g in kept]
        text = _TEMPLATE.format(W=W, H=H, FACES=faces, BAND_TOP=band_top, BAND_H=H - band_top, STACK=stack,
                                WEIGHT=int(inputs.get("weight", 400)), SIZE=int(inputs.get("size_px", 48)),
                                TRACK=inputs.get("letter_spacing", "0.04em"), UPCOMING=c["upcoming"], ACTIVE=c["active"],
                                SPOKEN=c["spoken"], DUR=round(dur, 3),
                                GROUPS=json.dumps(clean, ensure_ascii=False, separators=(",", ":")))
        out = Path(inputs["output_path"])
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        host = (f'<div id="el-captions" data-track-kind="captions" class="scene" data-composition-id="captions" '
                f'data-composition-src="compositions/{html.escape(out.name)}" data-start="0" data-duration="{round(dur, 3)}" '
                f'data-track-index="2"></div>')
        return ToolResult(success=True, artifacts=[str(out)], duration_seconds=round(time.time() - t0, 2),
                          data={"output": str(out), "captions": len(clean), "skipped": len(groups) - len(clean),
                                "host_element": host, "band_top_px": band_top})
