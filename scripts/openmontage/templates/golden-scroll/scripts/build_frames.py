#!/usr/bin/env python3
"""Builds the ten frame compositions (compositions/frames/NN-*.html) — v2.

Written inline by one hand instead of per-frame workers: frames 03–09 are consecutive
stretches of ONE scroll joined by push-slide seams, so the band, the gold thread, the
station geometry and the write-on must be identical in every file — they come from the
same constants here. Layouts are the confirmed sketches (storyboard.html); every reveal
is cued to the real word timings in audio_meta.json.

v2 ("不够惊艳"): candlelight that flickers, gold dust drifting in it, a fibre texture on the
paper, names that flare as they are written, the opening scroll written full of all 57
names, a light running the length of the unbroken line, four quotes that take the whole
frame in large gold type while they are spoken (the caption steps aside for them), and an
end card whose light runs off the unfinished scroll. Everything is seeded — no clocks,
no Math.random — so every render is identical. Re-run after any timing change:

    python3 scripts/build_frames.py
"""
import html, json, pathlib, random, re

P = pathlib.Path(__file__).resolve().parents[1]
CQ = 19.2  # px per cqw on the 1920-wide canvas
e = html.escape

meta = json.loads((P / "audio_meta.json").read_text(encoding="utf-8"))
WORDS = {v["frame"]: v["words"] for v in meta["voices"]}
FR = {}
cur = None
for ln in (P / "STORYBOARD.md").read_text(encoding="utf-8").splitlines():
    m = re.match(r"^## Frame (\d+)", ln)
    if m:
        cur = int(m.group(1)); FR[cur] = {}; continue
    m = re.match(r"^\s*-\s*duration:\s*([\d.]+)s", ln)
    if m and cur: FR[cur]["dur"] = float(m.group(1))
    m = re.match(r"^\s*-\s*src:\s*(\S+)", ln)
    if m and cur: FR[cur]["src"] = m.group(1)

# every master in timeline order — the opening writes them all across the scroll
NAMES = [m.group(1) for m in re.finditer(r"^- (.+?)（", (P / "capture/extracted/visible-text.txt").read_text(encoding="utf-8"), re.M)]
assert len(NAMES) == 57, len(NAMES)


def word(n, text, nth=0):
    hits = [w for w in WORDS[n] if w["text"] == text]
    if len(hits) <= nth:
        raise SystemExit(f"frame {n}: no word {text!r} (#{nth}) in audio_meta.json")
    return hits[nth]


def cue(n, text, nth=0, end=False):
    return round(word(n, text, nth)["end" if end else "start"], 3)


def last_word_end(n):
    return WORDS[n][-1]["end"]


def chars(text, p, cls="c"):
    return "".join(f'<span class="{p}-{cls}">{e(c)}</span>' for c in text)


# paper fibre: seeded SVG turbulence, warm and faint
NOISE = ("url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='320' height='320'%3E"
         "%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9 0.26' numOctaves='3' seed='11' stitchTiles='stitch'/%3E"
         "%3CfeColorMatrix values='0 0 0 0 0.91 0 0 0 0 0.83 0 0 0 0 0.63 0 0 0 0.11 0'/%3E%3C/filter%3E"
         "%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")")
PAPER = (NOISE + ", linear-gradient(180deg, rgba(232,212,160,0.05), rgba(232,212,160,0) 16%, "
         "rgba(232,212,160,0) 84%, rgba(232,212,160,0.05)), #12121e")
GLOW_ON = "0 0 1.4cqw rgba(232,212,160,0.7)"
GLOW_REST = "0 0 0.55cqw rgba(232,212,160,0.24)"
GLOW_OFF = "0 0 0cqw rgba(232,212,160,0)"


# ── shared look (frame.md tokens; geometry = the confirmed sketch) ─────────────
def css(p):
    return """
    @font-face { font-family: "Cormorant Garamond"; src: url("assets/fonts/CormorantGaramond.woff2") format("woff2"); font-weight: 300 700; font-style: normal; }
    @font-face { font-family: "Noto Serif SC"; src: url("assets/fonts/NotoSerifSC-subset.woff2") format("woff2"); font-weight: 200 900; font-style: normal; }
    #root { position: relative; width: 100%; height: 100%; overflow: hidden; }
    .P-ground { position: absolute; inset: 0; background: #0a0a14; }
    .P-stage { position: absolute; inset: 0; overflow: hidden; container-type: size;
      font-family: "Cormorant Garamond", "Noto Serif SC", serif; color: #e8e4dc; }
    .P-world { position: absolute; inset: 0; transform-origin: 0 0; }
    .P-vignette { position: absolute; inset: 0; pointer-events: none;
      background: radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 52%, rgba(0,0,0,0.5) 100%); }
    .P-scroll { position: absolute; left: -40cqw; right: -40cqw; top: 7.5cqw; height: 37cqw; background: PAPER;
      border-top: 1px solid #8a7040; border-bottom: 1px solid #8a7040; }
    .P-edge { position: absolute; left: 0; right: 0; height: 0; border-top: 1px solid rgba(138,112,64,0.38); }
    .P-edge-t { top: 0.9cqw; }
    .P-edge-b { bottom: 0.9cqw; }
    .P-bl { position: absolute; pointer-events: none; }
    .P-bloom { position: absolute; inset: 0; border-radius: 50%;
      background: radial-gradient(closest-side, rgba(200,164,94,0.32), rgba(232,212,160,0.12) 45%, rgba(138,112,64,0.05) 72%, rgba(138,112,64,0)); }
    .P-bloom-deep { background: radial-gradient(closest-side, rgba(200,164,94,0.42), rgba(232,212,160,0.16) 45%, rgba(138,112,64,0.07) 72%, rgba(138,112,64,0)); }
    .P-bloom-ember { background: radial-gradient(closest-side, rgba(212,175,55,0.18), rgba(212,175,55,0.05) 60%, rgba(212,175,55,0)); }
    .P-bloom-hero { background: radial-gradient(closest-side, rgba(200,164,94,0.36), rgba(232,212,160,0.14) 42%, rgba(138,112,64,0.05) 70%, rgba(138,112,64,0)); }
    .P-thread { position: absolute; left: -40cqw; right: -40cqw; top: 16.95cqw; height: 1px; background: rgba(200,164,94,0.62); }
    .P-st { position: absolute; top: 12cqw; width: 31cqw; }
    .P-yr { font-family: "Cormorant Garamond", serif; font-size: 3.2cqw; line-height: 3.4cqw; height: 3.4cqw; color: #c8a45e; letter-spacing: -0.005em; }
    .P-dot { position: absolute; left: 0.15cqw; top: 4.6cqw; width: 0.7cqw; height: 0.7cqw; background: #c8a45e; rotate: 45deg; }
    .P-era { margin-top: 2.6cqw; font-family: "Noto Serif SC", serif; font-size: 1.45cqw; letter-spacing: 0.35em; color: #c8a45e; }
    .P-nm { margin-top: 0.7cqw; font-family: "Noto Serif SC", serif; font-size: 4.2cqw; line-height: 1.15; color: #e8d4a0; white-space: nowrap; }
    .P-c { display: inline-block; }
    .P-nt { display: inline-block; font-size: 1.55cqw; color: #8a8678; margin-left: 1.4cqw; letter-spacing: 0.06em; vertical-align: 0.5cqw; }
    .P-sub { margin-top: 0.5cqw; font-family: "Noto Serif SC", serif; font-size: 1.9cqw; color: #c8a45e; letter-spacing: 0.06em; white-space: nowrap; height: 2.3cqw; }
    .P-grp { margin-top: 1.4cqw; font-family: "Noto Serif SC", serif; font-size: 1.5cqw; line-height: 1.65; color: rgba(232,228,220,0.66); letter-spacing: 0.05em; }
    .P-grp-cols { display: flex; gap: 3.2cqw; }
    .P-g { display: inline-block; }
    .P-gcol .P-g { display: block; }
    .P-sep { display: inline-block; margin: 0 0.6em; color: #9a968a; }
    .P-dust { position: absolute; inset: 0; pointer-events: none; }
    .P-mote { position: absolute; border-radius: 50%; background: #e8d4a0; box-shadow: 0 0 0.5cqw 0.1cqw rgba(232,212,160,0.55); }
    .P-hero { position: absolute; left: 0; right: 0; top: 20cqw; text-align: center; font-family: "Noto Serif SC", serif;
      color: #e8d4a0; letter-spacing: 0.06em; white-space: nowrap; line-height: 1.2; }
    .P-hc { display: inline-block; }
    .P-comet { position: absolute; width: 0.9cqw; height: 0.9cqw; margin-left: -0.45cqw; margin-top: -0.45cqw; border-radius: 50%;
      background: #fff4d6; box-shadow: 0 0 1.2cqw 0.5cqw rgba(232,212,160,0.8), 0 0 3.5cqw 1.2cqw rgba(200,164,94,0.35); }
    .P-chrome { position: absolute; right: 4cqw; bottom: 2.3cqw; font-family: "Cormorant Garamond", serif; font-weight: 600;
      font-size: 0.72cqw; letter-spacing: 0.18em; color: rgba(200,164,94,0.75); }
""".replace("PAPER", PAPER).replace("P-", f"{p}-")


# ── building blocks ─────────────────────────────────────────────────────────────
def bloom(p, i, x, y, size=58, kind=""):
    """Outer div carries position / follow / fade; the inner disc carries the flicker."""
    cls = f"{p}-bloom" + (f" {p}-bloom-{kind}" if kind else "")
    return (f'<div class="{p}-bl" id="{p}-bloom{i}" style="left:{x}cqw;top:{y}cqw;width:{size}cqw;height:{size}cqw;'
            f'margin-left:{-size / 2}cqw;margin-top:{-size / 2}cqw"><div class="{cls}" id="{p}-bloom{i}-in"></div></div>')


def flicker(p, i, dur, seed, amp=1.0):
    """Candlelight: a seeded chain of small breaths in brightness and size, the whole frame long."""
    rng, t, kfs = random.Random(seed), 0.0, []
    while t < dur:
        d = rng.uniform(0.28, 0.66)
        kfs.append({"opacity": round(rng.uniform(1 - 0.18 * amp, 1.0), 3),
                    "scale": round(rng.uniform(1 - 0.03 * amp, 1 + 0.03 * amp), 4),
                    "duration": round(d, 3), "ease": "sine.inOut"})
        t += d
    return f'tl.to($("#{p}-bloom{i}-in"), {{ keyframes: {json.dumps(kfs)} }}, 0);'


def dust(p, dur, seed, region=(6, 94, 9, 46), count=26):
    """Gold dust in the candlelight — seeded positions, slow rise and sway."""
    rng = random.Random(seed)
    motes, js = [], []
    for k in range(count):
        x, y = rng.uniform(*region[:2]), rng.uniform(*region[2:])
        s, o = rng.uniform(0.12, 0.3), rng.uniform(0.22, 0.7)
        t0 = rng.uniform(0.0, min(2.0, dur * 0.25))
        rise, sway = rng.uniform(2.5, 7.5) * CQ, rng.uniform(-2.2, 2.2) * CQ
        motes.append(f'<div class="{p}-mote" style="left:{x:.2f}cqw;top:{y:.2f}cqw;width:{s:.2f}cqw;height:{s:.2f}cqw"></div>')
        js.append(f'tl.fromTo(M[{k}], {{ opacity: 0 }}, {{ opacity: {o:.2f}, duration: 1.6, ease: "power1.out" }}, {t0:.2f});')
        js.append(f'tl.fromTo(M[{k}], {{ x: 0, y: 0 }}, {{ x: {sway:.1f}, y: {-rise:.1f}, duration: {dur - t0:.2f}, ease: "none" }}, {t0:.2f});')
    return f'<div class="{p}-dust">{"".join(motes)}</div>', [f'const M = $$(".{p}-mote");'] + js


def station(p, i, x, year, era, name, sub=None, notes=(), group=(), cols=0):
    notes_html = "".join(f'<span class="{p}-nt" id="{p}-nt{i}{k}">{e(t)}</span>' for k, t in enumerate(notes))
    grp = ""
    if group:
        if cols == 0:
            parts = []
            for k, g in enumerate(group):
                if k: parts.append(f'<span class="{p}-sep {p}-g">·</span>')
                parts.append(f'<span class="{p}-g">{e(g)}</span>')
            grp = f'<div class="{p}-grp" id="{p}-grp{i}">{"".join(parts)}</div>'
        else:
            per = -(-len(group) // cols)
            colhtml = "".join(
                f'<div class="{p}-gcol">' + "".join(f'<div class="{p}-g">{e(g)}</div>' for g in group[c * per:(c + 1) * per]) + "</div>"
                for c in range(cols))
            grp = f'<div class="{p}-grp {p}-grp-cols" id="{p}-grp{i}">{colhtml}</div>'
    return (f'<div class="{p}-st" id="{p}-st{i}" style="left:{x}cqw">'
            f'<div class="{p}-yr">{e(year)}</div><div class="{p}-dot" id="{p}-dot{i}"></div>'
            f'<div class="{p}-era">{e(era)}</div>'
            f'<div class="{p}-nm" id="{p}-nm{i}">{chars(name, p)}{notes_html}</div>'
            + (f'<div class="{p}-sub" id="{p}-sub{i}">{chars(sub, p)}</div>' if sub else "")
            + grp + "</div>")


# ── timeline helpers (emit GSAP statements) ────────────────────────────────────
WIPE_FROM, WIPE_TO = "inset(-60% 100% -60% -60%)", "inset(-60% -60% -60% -60%)"  # the negative insets keep the glow unclipped


def write_on(sel, t, per=0.13, dur=0.34, glow=True, rest=GLOW_REST):
    """Gold ink written on, character by character: a left-to-right wipe out of a slight
    blur, a flare of light as each character lands, settling to a soft glow."""
    if not glow:
        return (f'tl.fromTo($$("{sel}"), {{ clipPath: "{WIPE_FROM}", filter: "blur(4px)", opacity: 0.2 }},'
                f' {{ clipPath: "{WIPE_TO}", filter: "blur(0px)", opacity: 1, duration: {dur}, stagger: {per}, ease: "power2.out" }}, {t:.3f});')
    return (f'tl.fromTo($$("{sel}"), {{ clipPath: "{WIPE_FROM}", filter: "blur(4px)", opacity: 0.2, textShadow: "{GLOW_OFF}" }},'
            f' {{ clipPath: "{WIPE_TO}", filter: "blur(0px)", opacity: 1, textShadow: "{GLOW_ON}", duration: {dur}, stagger: {per}, ease: "power2.out" }}, {t:.3f});'
            f' tl.to($$("{sel}"), {{ textShadow: "{rest}", duration: 1.0, stagger: {per}, ease: "power2.out" }}, {t + dur:.3f});')


def write_chars_at(p, sel_ids, times, dur=0.36, rest=GLOW_REST):
    """One character per cue — the hero quote is written in step with the voice."""
    out = []
    for cid, t in zip(sel_ids, times):
        out.append(f'tl.fromTo($("#{cid}"), {{ clipPath: "{WIPE_FROM}", filter: "blur(6px)", opacity: 0.15, textShadow: "{GLOW_OFF}" }},'
                   f' {{ clipPath: "{WIPE_TO}", filter: "blur(0px)", opacity: 1, textShadow: "{GLOW_ON}", duration: {dur}, ease: "power2.out" }}, {t:.3f});')
        out.append(f'tl.to($("#{cid}"), {{ textShadow: "{rest}", duration: 1.1, ease: "power2.out" }}, {t + dur:.3f});')
    return out


def fade_in(sel, t, stagger=0.14, dur=0.8, y=10):
    return (f'tl.fromTo($$("{sel}"), {{ opacity: 0, y: {y} }},'
            f' {{ opacity: 1, y: 0, duration: {dur}, stagger: {stagger}, ease: "power3.out" }}, {t:.3f});')


def to_ink(p, i, t):
    return (f'tl.to($("#{p}-nm{i}"), {{ color: "#e8e4dc", duration: 0.9, ease: "power2.inOut" }}, {t:.3f});'
            f' tl.to($$("#{p}-nm{i} .{p}-c"), {{ textShadow: "{GLOW_OFF}", duration: 0.9, ease: "power2.inOut" }}, {t:.3f});')


def dot_on(sel, t):
    return (f'tl.fromTo($("{sel}"), {{ backgroundColor: "#c8a45e", scale: 1, boxShadow: "0 0 0cqw 0cqw rgba(232,212,160,0)" }},'
            f' {{ backgroundColor: "#e8d4a0", scale: 1.35, boxShadow: "0 0 1.2cqw 0.2cqw rgba(232,212,160,0.55)", duration: 0.6, ease: "power2.out" }}, {t:.3f});')


def dot_off(sel, t):
    return (f'tl.to($("{sel}"), {{ backgroundColor: "#c8a45e", scale: 1, boxShadow: "0 0 0cqw 0cqw rgba(232,212,160,0)",'
            f' duration: 0.6, ease: "power2.inOut" }}, {t:.3f});')


def frame_file(n, p, body, statements, *, chrome=True, extra_css=""):
    src = FR[n]["src"]
    fid = pathlib.Path(src).stem
    d = FR[n]["dur"]
    js = "\n      ".join(statements)
    return fid, src, f"""<template>
  <div id="root" data-composition-id="{fid}" data-width="1920" data-height="1080" data-duration="{d}">
    <style>{css(p)}{extra_css.replace("P-", f"{p}-")}
    </style>
    <div class="clip {p}-ground" id="{p}-ground" data-start="0" data-duration="{d}" data-track-index="0"></div>
    <div class="clip {p}-stage" id="{p}-stage" data-start="0" data-duration="{d}" data-track-index="1">
      {body}
      <div class="{p}-vignette"></div>
      {f'<div class="{p}-chrome">faith.localkin.ai</div>' if chrome else ""}
    </div>
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
    <script>
      (function () {{
      const root = document.querySelector('[data-composition-id="{fid}"]');
      const $ = (s) => root.querySelector(s);
      const $$ = (s) => Array.from(root.querySelectorAll(s));
      const tl = gsap.timeline({{ paused: true }});
      {js}
      tl.set({{}}, {{}}, {d});
      window.__timelines["{fid}"] = tl;
      }})();
    </script>
  </div>
</template>
"""


def scroll(p):
    return f'<div class="{p}-scroll"><div class="{p}-edge {p}-edge-t"></div><div class="{p}-edge {p}-edge-b"></div></div>'


def pan_frame(p, stations, blooms, *, start_shift, moves):
    """A stretch of the scroll: the world (band, thread, candle, stations) starts shifted
    right by start_shift cqw and pans left in `moves` [(t_arrive, shift_cqw, dur)] so each
    spoken station comes to its sketch position; the landed state IS the sketch."""
    body = (f'<div class="{p}-world" id="{p}-world">' + scroll(p) + "".join(blooms) + f'<div class="{p}-thread"></div>'
            + "".join(stations) + "</div>")
    st = [f'tl.fromTo($("#{p}-world"), {{ x: {start_shift * CQ:.1f} }}, {{ x: {start_shift * CQ:.1f}, duration: 0.01 }}, 0);']
    for t_arrive, shift, dur in moves:
        st.append(f'tl.to($("#{p}-world"), {{ x: {shift * CQ:.1f}, duration: {dur}, ease: "power2.inOut" }}, {max(0.0, t_arrive - dur):.3f});')
    return body, st


def station_beats(p, beats):
    """beats: [(i, t_name, x_bloom)] — write the name, light its dot, retire the previous name to ink."""
    out = []
    for k, (i, t, _x) in enumerate(beats):
        out.append(write_on(f"#{p}-nm{i} .{p}-c", t))
        out.append(dot_on(f"#{p}-dot{i}", t))
        if k:
            prev = beats[k - 1][0]
            out.append(to_ink(p, prev, t))
            out.append(dot_off(f"#{p}-dot{prev}", t))
    return out


def bloom_follow(p, beats):
    """The candle follows the spoken name: bloom0 starts on the first station and slides."""
    x0 = beats[0][2]
    out = [f'tl.fromTo($("#{p}-bloom0"), {{ opacity: 0 }}, {{ opacity: 1, duration: 1.2, ease: "power2.out" }}, {max(0.0, beats[0][1] - 0.6):.3f});']
    for _i, t, xb in beats[1:]:
        out.append(f'tl.to($("#{p}-bloom0"), {{ x: {(xb - x0) * CQ:.1f}, duration: 1.3, ease: "power2.inOut" }}, {max(0.0, t - 0.5):.3f});')
    return out


def hero(p, n, parts, size, sub_sel):
    """A quote takes the frame while it is spoken: the scroll dims, the quote is written in
    large gold type in step with the words, holds, then dissolves as its small line is
    written onto the scroll under the name. parts = [(display_text, word_text | None)] —
    None rides with the previous word (quote marks, the ≠ sign)."""
    d = FR[n]["dur"]
    ids, times, spans = [], [], []
    k = 0
    seq = []
    for disp, wtext in parts:
        if wtext is None:
            seq.append((disp, None))
            continue
        w = word(n, wtext)
        span = (w["end"] - w["start"]) / max(1, len(disp))
        for j, c in enumerate(disp):
            seq.append((c, w["start"] + j * span))
    # anchor-less marks take the neighbouring time (opening mark: just before the first char)
    first_t = next(t for _c, t in seq if t is not None)
    last_t = first_t
    for c, t in seq:
        cid = f"{p}-hc{k}"; k += 1
        if t is None:
            t = first_t - 0.12 if not times else last_t + 0.16
        last_t = max(last_t, t)
        ids.append(cid); times.append(t)
        spans.append(f'<span class="{p}-hc" id="{cid}">{e(c) if c != " " else "&#8201;"}</span>')
    t_dim = max(0.0, first_t - 0.55)
    t_out = d - 0.6
    body = (bloom(p, 9, 50, 27, 86, "hero")
            + f'<div class="{p}-hero" id="{p}-hero" style="font-size:{size}cqw">{"".join(spans)}</div>')
    js = [f'tl.fromTo($("#{p}-world"), {{ opacity: 1, filter: "blur(0px)" }}, {{ opacity: 0.32, filter: "blur(9px)", duration: 0.8, ease: "power2.inOut" }}, {t_dim:.3f});',
          f'tl.fromTo($("#{p}-bloom9"), {{ opacity: 0, scale: 0.85 }}, {{ opacity: 1, scale: 1, duration: 1.0, ease: "power2.out" }}, {t_dim:.3f});',
          flicker(p, 9, d, seed=n * 97 + 5, amp=1.2)]
    js += write_chars_at(p, ids, times)
    js += [f'tl.to($("#{p}-hero"), {{ opacity: 0, filter: "blur(8px)", scale: 0.94, duration: 0.5, ease: "power2.in" }}, {t_out:.3f});',
           f'tl.to($("#{p}-bloom9"), {{ opacity: 0, duration: 0.5, ease: "power2.in" }}, {t_out:.3f});',
           f'tl.to($("#{p}-world"), {{ opacity: 1, filter: "blur(0px)", duration: 0.5, ease: "power2.inOut" }}, {t_out:.3f});',
           write_on(sub_sel, t_out + 0.05, per=0.03, dur=0.25)]
    return body, js


frames_out = []

# ── 01 · the scroll unrolls, and is written full of names ───────────────────────
n, p = 1, "f01"
d1 = FR[1]["dur"]
t_roll, t_inch, t_name_end = cue(1, "铺成") - 0.15, cue(1, "每一寸"), cue(1, "名字", end=True)
rows = [NAMES[i * 19:(i + 1) * 19] for i in range(3)]
rows_html = "".join(
    f'<div class="{p}-row" id="{p}-row{r}" style="top:{9.9 + r * 4.3:.1f}cqw;opacity:{[0.5, 0.8, 0.5][r]}">'
    + "".join(f"<span>{e(nm)}</span>" for nm in row) + "</div>" for r, row in enumerate(rows))
body = (f'<div class="{p}-world" id="{p}-world">' + bloom(p, 0, 29, 27, 64)
        + f'<div class="{p}-paper" id="{p}-paper"><div class="{p}-edge {p}-edge-t"></div><div class="{p}-edge {p}-edge-b"></div>'
        + rows_html + f'<div class="{p}-pen" id="{p}-pen"></div></div>'
        + f'<div class="{p}-rod" id="{p}-rod" style="left:19.4cqw"></div><div class="{p}-roll" id="{p}-roll"></div></div>')
dust_html, dust_js = dust(p, d1, seed=101, region=(8, 62, 8, 46), count=24)
body += dust_html
unroll = 2.4
write_dur = max(3.2, t_name_end - t_inch)
st = [
    f'tl.fromTo($("#{p}-world"), {{ scale: 1 }}, {{ scale: 1.045, duration: {d1}, ease: "none" }}, 0);',
    f'tl.fromTo($("#{p}-bloom0"), {{ opacity: 0, scale: 0.6 }}, {{ opacity: 1, scale: 1, duration: 1.8, ease: "power2.out" }}, 0.05);',
    flicker(p, 0, d1, seed=11),
    f'tl.fromTo([$("#{p}-rod"), $("#{p}-roll")], {{ opacity: 0 }}, {{ opacity: 1, duration: 0.9, ease: "power2.out" }}, 0.35);',
    f'tl.fromTo($("#{p}-paper"), {{ clipPath: "inset(0% 100% 0% 0%)" }}, {{ clipPath: "inset(0% 0% 0% 0%)", duration: {unroll}, ease: "power2.inOut" }}, {t_roll:.3f});',
    f'tl.fromTo($("#{p}-roll"), {{ x: 0 }}, {{ x: {82 * CQ:.1f}, duration: {unroll}, ease: "power2.inOut" }}, {t_roll:.3f});',
    f'tl.fromTo($$(".{p}-row"), {{ clipPath: "inset(-40% 100% -40% 0%)" }}, {{ clipPath: "inset(-40% 0% -40% 0%)", duration: {write_dur:.2f}, stagger: 0.22, ease: "power1.inOut" }}, {t_inch:.3f});',
    f'tl.fromTo($("#{p}-pen"), {{ opacity: 0, x: 0 }}, {{ opacity: 1, duration: 0.3, ease: "power2.out" }}, {t_inch + 0.22:.3f});',
    f'tl.to($("#{p}-pen"), {{ x: {104 * CQ:.1f}, duration: {write_dur:.2f}, ease: "power1.inOut" }}, {t_inch + 0.22:.3f});',
]
st += dust_js
extra01 = """
    .P-paper { position: absolute; left: 20cqw; right: -2cqw; top: 13cqw; height: 28.8cqw; background: PAPER;
      border-top: 1px solid #8a7040; border-bottom: 1px solid #8a7040;
      -webkit-mask-image: linear-gradient(90deg, #000 38%, rgba(0,0,0,0.6) 78%, rgba(0,0,0,0.3));
      mask-image: linear-gradient(90deg, #000 38%, rgba(0,0,0,0.6) 78%, rgba(0,0,0,0.3)); }
    .P-rod { position: absolute; width: 1.15cqw; top: 12.2cqw; height: 30.4cqw;
      background: linear-gradient(90deg, #3a2f1a, #8a7040 45%, #5a4a2a 70%, #2a2213); }
    .P-roll { position: absolute; left: 19.4cqw; width: 1.9cqw; top: 11.9cqw; height: 31cqw; border-radius: 0.3cqw;
      background: linear-gradient(90deg, #2a2213, #6d5933 30%, #8a7040 55%, #3a2f1a); }
    .P-row { position: absolute; left: 2.2cqw; width: 104cqw; display: flex; justify-content: space-between; white-space: nowrap;
      font-family: "Noto Serif SC", serif; font-size: 1.15cqw; letter-spacing: 0.08em; color: #c8a45e;
      text-shadow: 0 0 0.6cqw rgba(232,212,160,0.35); }
    .P-pen { position: absolute; left: 2.2cqw; top: 15.1cqw; width: 0.7cqw; height: 0.7cqw; margin-left: -0.35cqw; margin-top: -0.35cqw; border-radius: 50%;
      background: #fff4d6; box-shadow: 0 0 1cqw 0.4cqw rgba(232,212,160,0.8), 0 0 3cqw 1cqw rgba(200,164,94,0.35); }
""".replace("PAPER", PAPER)
frames_out.append(frame_file(n, p, body, st, extra_css=extra01))

# ── 02 · the whole scroll, pulled back — one line, lit end to end ───────────────
n, p = 2, "f02"
d2 = FR[2]["dur"]
years = ["130", "296–430", "14–15c", "1483–1564", "1515–1717", "1554–1633", "1615–1714", "1700–1760",
         "1703–1791", "1792–1899", "1832–1951", "1859–1936", "1885–1981", "1900–1991", "1623–至今"]
xs = [6.2 + i * 6.3 for i in range(15)]
ticks = "".join(f'<div class="{p}-tk {p}-{"up" if i % 2 == 0 else "dn"}" style="left:{x:.2f}cqw"><div class="{p}-tk-d"></div>'
                f'<div class="{p}-tk-y">{e(y)}</div></div>' for i, (x, y) in enumerate(zip(xs, years)))
S0 = 5.0  # open tight on the first station, "130"
tx, ty = (50 - S0 * xs[0]) * CQ, (28 - S0 * 31.5) * CQ
body = (f'<div class="{p}-world" id="{p}-world">' + bloom(p, 0, 50, 31, 96)
        + f'<div class="{p}-band"><div class="{p}-edge {p}-edge-t"></div><div class="{p}-edge {p}-edge-b"></div></div>'
        + f'<div class="{p}-rod"></div><div class="{p}-line" id="{p}-line"></div>{ticks}'
        + f'<div class="{p}-comet" id="{p}-comet" style="left:3.4cqw;top:31.5cqw"></div></div>'
        + f'<div class="{p}-count"><div class="{p}-grp1" id="{p}-c1"><span class="{p}-num">15</span><span class="{p}-unit">个时代</span></div>'
        + f'<span class="{p}-sep2" id="{p}-c0">·</span>'
        + f'<div class="{p}-grp2" id="{p}-c2"><span class="{p}-num">57</span><span class="{p}-unit">位先贤</span></div></div>')
dust_html, dust_js = dust(p, d2, seed=202, region=(4, 96, 8, 46), count=30)
body += dust_html
t15, t57, tline = cue(2, "十五个"), cue(2, "五十七位"), cue(2, "一条")
line_dur = max(1.6, cue(2, "线", end=True) - tline)
st = [
    f'tl.fromTo($("#{p}-world"), {{ scale: {S0}, x: {tx:.1f}, y: {ty:.1f} }}, {{ scale: 1, x: 0, y: 0, duration: 3.0, ease: "expo.inOut" }}, 0);',
    f'tl.fromTo($("#{p}-bloom0"), {{ opacity: 0.5 }}, {{ opacity: 1, duration: 2.5, ease: "power2.out" }}, 0);',
    flicker(p, 0, d2, seed=22, amp=0.7),
    f'tl.fromTo($("#{p}-c1"), {{ opacity: 0, y: 14 }}, {{ opacity: 1, y: 0, duration: 0.8, ease: "power3.out" }}, {t15:.3f});',
    f'tl.fromTo([$("#{p}-c0"), $("#{p}-c2")], {{ opacity: 0, y: 14 }}, {{ opacity: 1, y: 0, duration: 0.8, stagger: 0.12, ease: "power3.out" }}, {t57:.3f});',
    f'tl.fromTo($("#{p}-line"), {{ scaleX: 0 }}, {{ scaleX: 1, duration: {line_dur:.2f}, ease: "power1.inOut" }}, {tline:.3f});',
    f'tl.fromTo($("#{p}-comet"), {{ opacity: 0, x: 0 }}, {{ opacity: 1, duration: 0.25, ease: "power2.out" }}, {tline:.3f});',
    f'tl.to($("#{p}-comet"), {{ x: {(102 - 3.4) * CQ:.1f}, duration: {line_dur:.2f}, ease: "power1.inOut" }}, {tline:.3f});',
    f'tl.fromTo($$(".{p}-tk-d"), {{ backgroundColor: "#c8a45e", scale: 1, boxShadow: "0 0 0cqw 0cqw rgba(232,212,160,0)" }}, {{ backgroundColor: "#fff4d6", scale: 1.45, boxShadow: "0 0 0.9cqw 0.25cqw rgba(232,212,160,0.7)", duration: 0.3, stagger: {line_dur / 15:.3f}, ease: "power2.out" }}, {tline + 0.08:.3f});',
    f'tl.to($$(".{p}-tk-d"), {{ backgroundColor: "#e8d4a0", scale: 1.25, boxShadow: "0 0 0.5cqw 0.1cqw rgba(232,212,160,0.4)", duration: 0.6, stagger: {line_dur / 15:.3f}, ease: "power2.out" }}, {tline + 0.4:.3f});',
]
st += dust_js
extra02 = """
    .P-band { position: absolute; left: 2.8cqw; right: -40cqw; top: 24.9cqw; height: 13.2cqw; background: PAPER;
      border-top: 1px solid #8a7040; border-bottom: 1px solid #8a7040; }
    .P-rod { position: absolute; left: 2.2cqw; top: 24.4cqw; width: 1.15cqw; height: 14.2cqw;
      background: linear-gradient(90deg, #3a2f1a, #8a7040 45%, #5a4a2a 70%, #2a2213); }
    .P-line { position: absolute; left: 3.4cqw; right: -2cqw; top: 31.5cqw; height: 1px; background: rgba(232,212,160,0.85); transform-origin: 0 50%;
      box-shadow: 0 0 0.4cqw rgba(232,212,160,0.5); }
    .P-tk { position: absolute; top: 31.5cqw; width: 0; height: 0; }
    .P-tk-d { position: absolute; left: -0.28cqw; top: -0.28cqw; width: 0.56cqw; height: 0.56cqw; background: #c8a45e; rotate: 45deg; }
    .P-tk-y { position: absolute; left: -5cqw; width: 10cqw; text-align: center; font-family: "Cormorant Garamond", "Noto Serif SC", serif;
      font-size: 1.18cqw; color: #c8a45e; white-space: nowrap; }
    .P-up .P-tk-y { bottom: 0.9cqw; }
    .P-dn .P-tk-y { top: 0.9cqw; }
    .P-count { position: absolute; left: 6.2cqw; top: 6.4cqw; display: flex; align-items: baseline; gap: 0.9cqw; white-space: nowrap; }
    .P-num { font-family: "Cormorant Garamond", serif; font-size: 7.5cqw; line-height: 0.92; color: #c8a45e; letter-spacing: -0.01em;
      text-shadow: 0 0 1.4cqw rgba(232,212,160,0.3); }
    .P-unit { font-family: "Noto Serif SC", serif; font-size: 2.4cqw; color: #e8e4dc; }
    .P-sep2 { font-family: "Cormorant Garamond", serif; font-size: 3cqw; color: #8a7040; margin: 0 1.6cqw; }
    .P-grp1, .P-grp2 { display: flex; align-items: baseline; gap: 0.9cqw; }
    .P-bloom { background: radial-gradient(closest-side, rgba(200,164,94,0.17), rgba(232,212,160,0.07) 50%, rgba(138,112,64,0.03) 75%, rgba(138,112,64,0)); }
""".replace("PAPER", PAPER)
frames_out.append(frame_file(n, p, body, st, extra_css=extra02))


# ── 03–09 · stations along the scroll ───────────────────────────────────────────
def pan_js(p, n, beats, extra_blooms=()):
    d = FR[n]["dur"]
    out = station_beats(p, beats) + bloom_follow(p, beats) + [flicker(p, 0, d, seed=n * 31 + 1)]
    for i, seed_off in extra_blooms:
        out.append(flicker(p, i, d, seed=n * 31 + seed_off, amp=0.8))
    return out


def with_dust(p, n, body, st, region=(4, 96, 9, 46)):
    dh, dj = dust(p, FR[n]["dur"], seed=n * 1009, region=region)
    return body + dh, st + dj


# 03 · apostolic · fathers
n, p = 3, "f03"
b = [(1, cue(3, "爱任纽"), 16), (2, cue(3, "亚他那修"), 61)]
stations = [station(p, 1, 7, "130", "使徒时代", "爱任纽", notes=["← 坡旅甲", "← 使徒约翰"]),
            station(p, 2, 52, "296–430", "教父", "亚他那修", group=["金口约翰", "奥古斯丁"])]
body, st = pan_frame(p, stations, [bloom(p, 0, 16, 24.5)], start_shift=12,
                     moves=[(b[0][1] + 0.3, 7, 1.6), (b[1][1] + 0.2, 0, 1.4)])
st += pan_js(p, n, b)
st += [fade_in(f"#{p}-nt10", cue(3, "坡旅甲", 0), dur=0.7, y=6), fade_in(f"#{p}-nt11", cue(3, "使徒约翰"), dur=0.7, y=6),
       fade_in(f"#{p}-grp2 .{p}-g", cue(3, "三位一体"))]
body, st = with_dust(p, n, body, st)
frames_out.append(frame_file(n, p, body, st))

# 04 · medieval · reformation — hero: 「义人必因信得生」
n, p = 4, "f04"
b = [(1, cue(4, "肯培"), 17), (2, cue(4, "路德"), 59)]
stations = [station(p, 1, 7, "14–15c", "中世纪", "肯培多默", sub="《效法基督》", group=["不知之云"]),
            station(p, 2, 52, "1483–1564", "宗教改革", "路德", sub="「义人必因信得生」", group=["加尔文", "克兰麦"])]
body, st = pan_frame(p, stations, [bloom(p, 0, 17, 24.5), bloom(p, 1, 17, 27.5, 30, "ember")], start_shift=10,
                     moves=[(b[1][1] + 0.2, 0, 1.6)])
st += pan_js(p, n, b, extra_blooms=[(1, 7)])
st += [f'tl.fromTo($("#{p}-bloom1"), {{ opacity: 0 }}, {{ opacity: 1, duration: 1.2, ease: "power2.out" }}, 0.1);',
       write_on(f"#{p}-sub1 .{p}-c", cue(4, "《效法基督》"), per=0.09, dur=0.3),
       fade_in(f"#{p}-grp1 .{p}-g", cue(4, "写成") + 0.2),
       fade_in(f"#{p}-grp2 .{p}-g", cue(4, "读到") + 0.3)]
hb, hj = hero(p, n, [("「", None), ("义人", "义人"), ("必", "必"), ("因信", "因信"), ("得生", "得生"), ("」", None)], 6.6, f"#{p}-sub2 .{p}-c")
body, st = with_dust(p, n, body + hb, st + hj)
frames_out.append(frame_file(n, p, body, st))

# 05 · mysticism · anglican
n, p = 5, "f05"
b = [(1, cue(5, "大德兰"), 16), (2, cue(5, "安德鲁斯"), 62)]
stations = [station(p, 1, 7, "1515–1717", "神秘主义", "大德兰", group=["十字若望", "方济各·沙雷氏", "莫利诺斯", "劳伦斯弟兄", "盖恩夫人"], cols=1),
            station(p, 2, 52, "1554–1633", "圣公会古典", "安德鲁斯", group=["胡克", "乔治·赫伯特"])]
body, st = pan_frame(p, stations, [bloom(p, 0, 16, 24.5)], start_shift=10, moves=[(b[1][1] + 0.2, 0, 1.6)])
st += pan_js(p, n, b)
st += [fade_in(f"#{p}-grp1 .{p}-g", cue(5, "灵心城堡的"), stagger=0.22),
       fade_in(f"#{p}-grp2 .{p}-g", cue(5, "圣经的"))]
body, st = with_dust(p, n, body, st)
frames_out.append(frame_file(n, p, body, st))

# 06 · puritans · pietists · awakening — hero: 「全世界是我的牧区」
n, p = 6, "f06"
b = [(1, cue(6, "本仁约翰"), 14), (2, cue(6, "辛生道夫"), 46), (3, cue(6, "卫斯理"), 76)]
stations = [station(p, 1, 5, "1615–1714", "清教徒", "本仁约翰", group=["巴克斯特", "约翰·欧文", "托马斯·华森", "马太·亨利"], cols=1),
            station(p, 2, 37, "1700–1760", "敬虔派", "辛生道夫"),
            station(p, 3, 69, "1703–1791", "大觉醒", "卫斯理", sub="「全世界是我的牧区」", group=["爱德华兹", "怀特腓"])]
body, st = pan_frame(p, stations, [bloom(p, 0, 14, 24.5, 50)], start_shift=16,
                     moves=[(b[0][1] + 0.2, 12, 1.4), (b[1][1] + 0.2, 6, 1.3), (b[2][1] + 0.2, 0, 1.3)])
st += pan_js(p, n, b)
st += [fade_in(f"#{p}-grp1 .{p}-g", cue(6, "天路历程"), stagger=0.2),
       fade_in(f"#{p}-grp3 .{p}-g", cue(6, "说") + 0.2)]
hb, hj = hero(p, n, [("「", None), ("全世界", "全世界"), ("是", "是"), ("我的", "我的"), ("牧区", "牧区"), ("」", None)], 6.2, f"#{p}-sub3 .{p}-c")
body, st = with_dust(p, n, body + hb, st + hj)
frames_out.append(frame_file(n, p, body, st))

# 07 · 19th-century revival · missions
n, p = 7, "f07"
b = [(1, cue(7, "司布真"), 15), (2, cue(7, "戴德生"), 60)]
stations = [station(p, 1, 7, "1792–1899", "十九世纪复兴", "司布真", group=["芬尼", "慕勒", "纽曼", "慕迪", "慕安德烈", "小德兰"], cols=2),
            station(p, 2, 52, "1832–1951", "宣教时代", "戴德生", group=["賈艾梅"])]
body, st = pan_frame(p, stations, [bloom(p, 0, 15, 24.5)], start_shift=10, moves=[(b[1][1] + 0.2, 0, 1.5)])
st += pan_js(p, n, b)
st += [fade_in(f"#{p}-grp1 .{p}-g", cue(7, "十字架"), stagger=0.16),
       fade_in(f"#{p}-grp2 .{p}-g", cue(7, "宣教士"))]
body, st = with_dust(p, n, body, st)
frames_out.append(frame_file(n, p, body, st))

# 08 · 20th-century revival · modern · Chinese church — hero: 「我们是为了信仰！」
n, p = 8, "f08"
b = [(1, cue(8, "古约翰"), 13), (2, cue(8, "潘霍华"), 45), (3, cue(8, "王明道"), 77)]
stations = [station(p, 1, 5, "1859–1936", "二十世纪复兴", "古约翰", group=["宾路易师母", "罗伯斯"]),
            station(p, 2, 37, "1885–1981", "现代", "潘霍华", group=["史百克", "陶恕", "钟马田"]),
            station(p, 3, 69, "1900–1991", "中国教会", "王明道", sub="「我们是为了信仰！」", group=["倪柝声", "宋尚节"])]
body, st = pan_frame(p, stations, [bloom(p, 0, 13, 24.5, 56), bloom(p, 1, 77, 24.5, 56, "deep")], start_shift=14,
                     moves=[(b[1][1] + 0.3, 7, 1.7), (b[2][1] + 0.3, 0, 1.9)])
st += pan_js(p, n, b, extra_blooms=[(1, 9)])
st += [f'tl.fromTo($("#{p}-bloom1"), {{ opacity: 0 }}, {{ opacity: 1, duration: 1.6, ease: "power2.inOut" }}, {b[2][1]:.3f});',
       f'tl.to($("#{p}-bloom0"), {{ opacity: 0, duration: 1.4, ease: "power2.inOut" }}, {b[2][1] + 0.2:.3f});',
       fade_in(f"#{p}-grp1 .{p}-g", cue(8, "火炬手")),
       fade_in(f"#{p}-grp2 .{p}-g", cue(8, "代价")),
       fade_in(f"#{p}-grp3 .{p}-g", cue(8, "王明道") + 1.2)]
hb, hj = hero(p, n, [("「", None), ("我们", "我们"), ("是为了", "是为了"), ("信仰", "信仰"), ("！」", None)], 6.2, f"#{p}-sub3 .{p}-c")
body, st = with_dust(p, n, body + hb, st + hj)
frames_out.append(frame_file(n, p, body, st))

# 09 · to today — the scroll is left open — hero: 「认识神 ≠ 认识关于神的知识」
n, p = 9, "f09"
b = [(1, cue(9, "巴刻"), 20)]
group9 = ["杜瑞田", "查理·贺智", "霍志恒", "伯克富", "克劳尼", "高慈宏", "卡森", "凯勒", "查普尔", "傅瑞姆"]
stations = [station(p, 1, 9, "1623–至今", "改革宗系统神学", "巴刻", sub="「认识神 ≠ 认识关于神的知识」", group=group9, cols=2)]
body, st = pan_frame(p, stations, [bloom(p, 0, 20, 24.5)], start_shift=8, moves=[(b[0][1], 0, 2.2)])
st += pan_js(p, n, b)
st += [fade_in(f"#{p}-grp1 .{p}-g", cue(9, "说"), stagger=0.16)]
hb, hj = hero(p, n, [("「", None), ("认识神", "认识神"), (" ≠ ", "不等于"), ("认识", "认识"), ("关于神的", "关于神的"), ("知识", "知识"), ("」", None)],
              4.9, f"#{p}-sub1 .{p}-c")
body, st = with_dust(p, n, body + hb, st + hj)
extra09 = """
    .P-scroll { -webkit-mask-image: linear-gradient(90deg, #000 53%, rgba(0,0,0,0.35) 71%, rgba(0,0,0,0) 78%);
      mask-image: linear-gradient(90deg, #000 53%, rgba(0,0,0,0.35) 71%, rgba(0,0,0,0) 78%); }
    .P-thread { -webkit-mask-image: linear-gradient(90deg, #000 55%, rgba(0,0,0,0.55) 80%);
      mask-image: linear-gradient(90deg, #000 55%, rgba(0,0,0,0.55) 80%); }
"""
frames_out.append(frame_file(n, p, body, st, extra_css=extra09))

# ── 10 · they still speak — the light runs off the unfinished scroll ────────────
n, p = 10, "f10"
d10 = FR[10]["dur"]
vo_end = last_word_end(10)
glints = "".join(f'<div class="{p}-glint" style="left:{6.2 + i * 6.3:.2f}cqw"></div>' for i in range(15))
title_ids = [f"{p}-tc{k}" for k in range(len("他们今天仍在说话"))]
title_html = "".join(f'<span class="{p}-tc" id="{cid}">{e(c)}</span>' for cid, c in zip(title_ids, "他们今天仍在说话"))
body = (f'<div class="{p}-fin" id="{p}-fin">' + f'<div class="{p}-band" id="{p}-band"></div>' + glints
        + f'<div class="{p}-comet" id="{p}-comet" style="left:2cqw;top:38.1cqw"></div>' + bloom(p, 0, 50, 23, 70)
        + f'<div class="{p}-end"><div class="{p}-title" id="{p}-title">{title_html}</div>'
        + f'<div class="{p}-url" id="{p}-url">faith.localkin.ai</div><div class="{p}-invite" id="{p}-invite">和他们对话</div></div>')
dust_html, dust_js = dust(p, d10, seed=1010, region=(14, 86, 4, 46), count=30)
body += dust_html + "</div>"
t_glint = cue(10, "这卷纸")
st = [
    f'tl.fromTo($("#{p}-band"), {{ opacity: 0 }}, {{ opacity: 0.5, duration: 0.9, ease: "power2.out" }}, 0.0);',
    f'tl.fromTo($$(".{p}-glint"), {{ opacity: 0, scale: 0.4 }}, {{ opacity: 0.9, scale: 1, duration: 0.5, stagger: 0.13, ease: "power2.out" }}, {t_glint:.3f});',
    f'tl.fromTo($("#{p}-comet"), {{ opacity: 0, x: 0 }}, {{ opacity: 1, duration: 0.3, ease: "power2.out" }}, {t_glint + 2.0:.3f});',
    f'tl.to($("#{p}-comet"), {{ x: {104 * CQ:.1f}, duration: 2.6, ease: "power1.in" }}, {t_glint + 2.0:.3f});',
    f'tl.fromTo($("#{p}-bloom0"), {{ opacity: 0.25, scale: 0.9 }}, {{ opacity: 1, scale: 1, duration: 2.4, ease: "power2.inOut" }}, {vo_end - 1.2:.3f});',
    flicker(p, 0, d10, seed=1001),
]
st += write_chars_at(p, title_ids, [vo_end + 0.15 + k * 0.12 for k in range(len(title_ids))], dur=0.42, rest="0 0 0.8cqw rgba(232,212,160,0.32)")
st += [
    f'tl.fromTo($("#{p}-url"), {{ opacity: 0, y: 10 }}, {{ opacity: 1, y: 0, duration: 0.9, ease: "power3.out" }}, {vo_end + 1.3:.3f});',
    f'tl.fromTo($("#{p}-invite"), {{ opacity: 0 }}, {{ opacity: 1, duration: 0.9, ease: "power2.out" }}, {vo_end + 1.8:.3f});',
    f'tl.to($("#{p}-fin"), {{ opacity: 0, duration: 1.0, ease: "power1.in" }}, {d10 - 1.0:.3f});',
]
st += dust_js
extra10 = """
    .P-band { position: absolute; left: -2cqw; right: -2cqw; top: 36cqw; height: 4.2cqw; background: PAPER;
      border-top: 1px solid #8a7040; border-bottom: 1px solid #8a7040; }
    .P-glint { position: absolute; top: 38.1cqw; width: 0.5cqw; height: 0.5cqw; margin-left: -0.25cqw; background: #e8d4a0;
      rotate: 45deg; box-shadow: 0 0 0.9cqw 0.15cqw rgba(232,212,160,0.5); }
    .P-end { position: absolute; left: 0; right: 0; top: 12.5cqw; text-align: center; }
    .P-title { font-family: "Noto Serif SC", serif; font-size: 5.2cqw; color: #c8a45e; letter-spacing: 0.12em; line-height: 1.1; }
    .P-tc { display: inline-block; }
    .P-url { margin-top: 2.2cqw; font-family: "Cormorant Garamond", serif; font-size: 2.5cqw; color: #e8e4dc; letter-spacing: 0.06em; }
    .P-invite { margin-top: 1.1cqw; font-family: "Noto Serif SC", serif; font-size: 1.5cqw; color: #8a8678; letter-spacing: 0.5em; }
    .P-fin { position: absolute; inset: 0; }
""".replace("PAPER", PAPER)
frames_out.append(frame_file(n, p, body, st, chrome=False, extra_css=extra10))

out_dir = P / "compositions" / "frames"
out_dir.mkdir(parents=True, exist_ok=True)
for fid, src, text in frames_out:
    (P / src).write_text(text, encoding="utf-8")
    print(f"  {src}  ({len(text) // 1024} KB)")
print(f"✓ {len(frames_out)} frames")
