"""Chinese, Japanese and Korean in captions (LocalKin, 2026-10).

A transcript of Chinese has a character to a "word". Joined with spaces as English words are, a
caption read 「你 好 呀」; cut every eight words, every line was eight characters and ended
mid-word. Here: no space next to a CJK character (one between two Latin words, so English comes
out as before), a caption or a page ends with its clause — at a comma or a full stop — a clause
too long for one line is cut into even parts, and a clause's comma or full stop is not shown at
the end of a caption. Corrections may span several characters: {"克劳德": "Claude"}.
Used by subtitle_gen and remotion_caption_burn.
"""

from __future__ import annotations

import math
import re

_CJK = re.compile(r"[㐀-鿿豈-﫿぀-ヿ가-힯]")
CLAUSE_END = "，,。！？!?；;：:、…"
DROP_AT_END = "，,。；;：:、"
_PUNCT = "，,。！？!?；;：:、…“”‘’\"'（）()《》「」『』—·. "


def is_cjk(text: str) -> bool:
    return bool(_CJK.search(text or ""))


def mostly_cjk(texts: list[str]) -> bool:
    """Whether a transcript is written in CJK: a third of its spoken characters or more."""
    spoken = [c for t in texts for c in (t or "") if c.isalnum()]
    return bool(spoken) and sum(1 for c in spoken if _CJK.match(c)) >= len(spoken) / 3


def join(texts: list[str]) -> str:
    """Words as they are written: a space between two words, none next to a CJK character."""
    out = ""
    for t in texts:
        if out and t and not (_CJK.match(out[-1]) or _CJK.match(t[0])):
            out += " "
        out += t
    return out


def width(text: str) -> float:
    """How wide a caption is, in CJK characters."""
    return sum(1.0 if _CJK.match(c) else 0.55 for c in text if not c.isspace())


def ends_clause(word: str) -> bool:
    w = (word or "").strip()
    return bool(w) and w[-1] in CLAUSE_END


def shown(word: str, last: bool) -> str:
    """A word as shown: the clause's comma or full stop dropped when it ends the caption."""
    w = (word or "").strip()
    return w.rstrip(DROP_AT_END) if last else w


def clauses(words: list[dict], key: str = "word", gap: float = 0.6, start: str = "start", end: str = "end") -> list[list[dict]]:
    """Words grouped by clause: after a comma or a full stop, or where the speaker paused."""
    out: list[list[dict]] = []
    cur: list[dict] = []
    for w in words:
        if cur and w.get(start, 0) - cur[-1].get(end, 0) > gap:
            out.append(cur)
            cur = []
        cur.append(w)
        if ends_clause(w.get(key, "")):
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return out


def even_parts(clause: list[dict], limit: float, key: str = "word") -> list[list[dict]]:
    """A clause too wide for `limit` cut into the fewest even parts that fit."""
    total = width(join([w.get(key, "").strip() for w in clause]))
    n = max(1, math.ceil(total / max(1.0, limit)))
    if n == 1:
        return [clause]
    target = total / n
    parts: list[list[dict]] = [[]]
    acc = 0.0
    for w in clause:
        wide = width(w.get(key, "").strip())
        if parts[-1] and acc + wide / 2 > target * len(parts) and len(parts) < n:
            parts.append([])
        parts[-1].append(w)
        acc += wide
    return parts


def correct(words: list[dict], corrections: dict[str, str], key: str = "word") -> list[dict]:
    """Corrections whose wrong side is CJK, across words: the first word of the span takes the
    right side (and any punctuation the last one carried) and the span's time."""
    fixes = {k: v for k, v in (corrections or {}).items() if is_cjk(k)}
    if not fixes or not words:
        return words
    out = [dict(w) for w in words]
    for wrong, right in fixes.items():
        target = "".join(c for c in wrong if c not in _PUNCT)
        i = 0
        while i < len(out):
            acc, j = "", i
            while j < len(out) and len(acc) < len(target):
                acc += out[j].get(key, "").strip().strip(_PUNCT)
                j += 1
            if acc == target and j > i:
                last = out[j - 1].get(key, "").strip()
                trailing = last[len(last.rstrip(_PUNCT)):]
                out[i] = dict(out[i], **{key: right + trailing})
                for end_key in ("end", "endMs"):
                    if end_key in out[j - 1]:
                        out[i][end_key] = out[j - 1][end_key]
                del out[i + 1:j]
            i += 1
    return out
