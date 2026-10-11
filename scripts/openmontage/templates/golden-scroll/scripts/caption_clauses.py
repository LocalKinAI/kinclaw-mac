#!/usr/bin/env python3
"""Regroup the caption track by Chinese clause (run right after captions.mjs build).

captions.mjs ends a caption line only on ASCII punctuation, so Chinese lines were being cut
by word count ("纸 每一寸 都 | 写着 一个 名字"). Here each caption line is one clause of
SCRIPT.md — split at ，。；：！—— — with the words set flush (no spaces between them).
Rewrites the GROUPS array inside compositions/captions.html and caption_groups.json.
"""
import importlib.util, json, pathlib, re

P = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("va", P / "scripts" / "voice_align.py")
va = importlib.util.module_from_spec(spec); spec.loader.exec_module(va)
ENDS = re.compile(r"[，。；：！？—]$")

html_path = P / "compositions" / "captions.html"
src = html_path.read_text(encoding="utf-8")
m = re.search(r"var GROUPS = (\[.*?\]);\n", src, re.S)
flat = [w for g in json.loads(m.group(1)) for w in g["words"]]
frames = [g["frame"] for g in json.loads(m.group(1)) for _ in g["words"]]
script_words = [w for line in va.WORDS for w in line.split("/")]
assert len(script_words) == len(flat), (len(script_words), len(flat))

groups, cur = [], []
for sw, w, fr in zip(script_words, flat, frames):
    assert va.caption_text(sw) == w["text"], (sw, w["text"])
    cur.append((w, fr))
    if ENDS.search(sw):
        groups.append(cur); cur = []
if cur: groups.append(cur)

# the four quotes are written full-frame in step with the voice — their caption steps aside
HERO = {"义人必因信得生", "全世界是我的牧区", "我们是为了信仰", "认识神", "不等于认识关于神的知识"}
groups = [g for g in groups if "".join(w["text"] for w, _ in g) not in HERO]
out = []
for gi, g in enumerate(groups):
    nxt = groups[gi + 1][0][0]["start"] if gi + 1 < len(groups) else None
    end = round(g[-1][0]["end"] + 0.12, 3)
    if nxt is not None and nxt < end: end = nxt
    out.append({"id": f"caption-group-{gi}", "frame": g[0][1], "start": g[0][0]["start"], "end": end,
                "text": "".join(w["text"] for w, _ in g),
                "words": [{"id": f"caption-word-{gi}-{wi}", "text": w["text"], "start": w["start"], "end": w["end"]}
                          for wi, (w, _) in enumerate(g)]})
new = src[:m.start(1)] + json.dumps(out, ensure_ascii=False, separators=(",", ":")) + src[m.end(1):]
# captions.mjs quotes frame.md's whole stack as ONE family ("'Cormorant Garamond', 'Noto Serif SC', serif"),
# which matches no @font-face — the text would fall back to Georgia. Unwrap it.
new = new.replace("\"'Cormorant Garamond', 'Noto Serif SC', serif\"", '"Cormorant Garamond", "Noto Serif SC", serif')
html_path.write_text(new, encoding="utf-8")
cg = json.loads((P / "caption_groups.json").read_text())
cg["groups"] = out
(P / "caption_groups.json").write_text(json.dumps(cg, ensure_ascii=False, indent=2))
print(f"✓ {len(out)} clause captions (was {len(json.loads(m.group(1)))})")
for g in out[:8]: print(f"    {g['start']:6.2f}–{g['end']:6.2f}  {g['text']}")
