#!/usr/bin/env python3
"""One box narration take → ten frame clips + audio_meta.json.

The whole SCRIPT.md is spoken in ONE VoiceDesign take (scripts/box_narrate.py) so the
designed voice stays one voice. This script:
  1. gets token timestamps for that take from whisper.cpp (the ggml-small model that
     `hyperframes transcribe` downloads),
  2. pins them onto the script's OWN characters — whisper mishears names (爱任纽 → 爱任牛)
     and writes some numbers as digits, so its text is only used for timing,
  3. cuts the take at the quietest point between lines, one clip per frame, padding each
     pause between frames to at least MIN_PAUSE_S, and
  4. writes the frame-keyed audio_meta.json that captions.mjs / assemble-index.mjs read
     (words are frame-relative seconds). An existing bgm entry is kept.

    python3 scripts/voice_align.py --take assets/voice/take-2.wav
"""
import difflib, json, pathlib, re, subprocess, sys, tempfile, wave

import numpy as np

P = pathlib.Path(__file__).resolve().parents[1]
WHISPER = pathlib.Path.home() / ".local/bin/whisper-cli"
MODEL = pathlib.Path.home() / ".cache/hyperframes/whisper/models/ggml-small.bin"
LEAD_S = 0.8        # frame 1 opens on the candle bloom alone before the first word
TAIL_S = 5.5        # the end card holds this long after the last word (the music rises into it)
MIN_PAUSE_S = 0.9   # breathing room between frames (the pan needs a beat)
# Extra hold after a frame's last word: the four quote frames land a full-screen gold quote
# and need a beat after it is spoken; the opening lets the written-out scroll register.
EXTRA_TAIL_S = {1: 0.6, 4: 2.0, 6: 1.7, 8: 2.0, 9: 1.8}

# Word units for captions and write-on cues, hand-cut; "/" marks a boundary. Joined
# without "/" each line must equal SCRIPT.md exactly (asserted below).
WORDS = [
    "如果/把/一千九百年，/铺成/一卷/长长的/纸——/每一寸，/都/写着/一个/名字。",
    "十五个/时代，/五十七位/先贤，/一条/从未/断过的/线。",
    "起点/是/爱任纽——/他/听过/坡旅甲，/坡旅甲/听过/使徒约翰。/亚他那修，/为/三位一体，/独对/全世界。",
    "肯培/在/修院里，/写成/《效法基督》；/路德/读到：/义人/必/因信/得生。",
    "大德兰/走进/灵心城堡的/七重居所；/安德鲁斯，/钦定本/圣经的/主译者。",
    "监狱里的/补锅匠/本仁约翰，/写了/天路历程；/辛生道夫/点起/百年/祷告链；/卫斯理/说：/全世界/是/我的/牧区。",
    "司布真，/只传/十字架；/戴德生，/为中国/焚烧的/宣教士。",
    "古约翰，/东北/复兴的/火炬手；/潘霍华，/付上/作门徒的/代价；/王明道/说：/我们/是为了/信仰！",
    "一直/到今天——/巴刻/说：/认识神，/不等于/认识/关于神的/知识。",
    "这卷纸/还没有/写完。/他们/今天，/仍在/说话。",
]
HAN = re.compile(r"[一-鿿]")
CN_DIGIT = dict(zip("0123456789", "〇一二三四五六七八九"))


def die(msg):
    sys.exit(f"✗ voice_align: {msg}")


def script_lines():
    out, cur = [], None
    for ln in (P / "SCRIPT.md").read_text(encoding="utf-8").splitlines():
        if re.match(r"^#{2,3}\s+.*?\(frame\s+\d+\)", ln, re.I):
            if cur is not None: out.append(cur)
            cur = ""; continue
        if cur is None or ln.lstrip().startswith("**"): continue
        m = re.match(r"^(?: {4,}|\t)(.+)$", ln)
        if m: cur += m.group(1).strip()
    if cur is not None: out.append(cur)
    return out


def caption_text(w):
    return re.sub(r"[，。；：！？、—]", "", w)  # keep 《》 — a book title reads as one


def whisper_chars(take16):
    """[(char, start_s, end_s)] from whisper.cpp token offsets. Tokens can split a
    character's UTF-8 bytes, so bytes are re-joined before decoding."""
    with tempfile.TemporaryDirectory() as td:
        base = pathlib.Path(td) / "w"
        r = subprocess.run([str(WHISPER), "-m", str(MODEL), "-f", str(take16), "-l", "zh",
                            "--prompt", "以下是普通话的句子，使用简体中文。", "-ojf", "-dtw", "small",
                            "-of", str(base)], capture_output=True)
        if r.returncode != 0: die(f"whisper-cli failed: {r.stderr[-400:]!r}")
        d = json.loads((base.with_suffix(".json")).read_bytes().decode("latin-1"))
    out = []
    for seg in d["transcription"]:
        buf, t0 = b"", None
        for tok in seg["tokens"]:
            if tok["text"].startswith("[_"): continue
            if not buf: t0 = tok["offsets"]["from"]
            buf += tok["text"].encode("latin-1")
            try:
                s = buf.decode("utf-8")
            except UnicodeDecodeError:
                continue
            t1 = tok["offsets"]["to"]
            s = "".join(CN_DIGIT.get(c, c) for c in s)
            for i, c in enumerate(s):
                out.append((c, (t0 + (t1 - t0) * i / len(s)) / 1000, (t0 + (t1 - t0) * (i + 1) / len(s)) / 1000))
            buf = b""
    return [c for c in out if HAN.match(c[0])]


def main():
    args = sys.argv[1:]
    take = P / (args[args.index("--take") + 1] if "--take" in args else "assets/voice/take-2.wav")
    lines = script_lines()
    if len(lines) != len(WORDS): die(f"SCRIPT.md has {len(lines)} lines, WORDS has {len(WORDS)}")
    for i, (ln, w) in enumerate(zip(lines, WORDS), 1):
        if w.replace("/", "") != ln: die(f"line {i}: WORDS drifted from SCRIPT.md\n  script: {ln}\n  words:  {w}")

    # script characters, each tagged (line, word)
    scr = []
    for li, w in enumerate(WORDS):
        for wi, word in enumerate(w.split("/")):
            scr += [(c, li, wi) for c in word if HAN.match(c)]

    with wave.open(str(take)) as wf:
        sr, sw, ch = wf.getframerate(), wf.getsampwidth(), wf.getnchannels()
        pcm = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16).reshape(-1, ch)
    take_dur = len(pcm) / sr

    with tempfile.TemporaryDirectory() as td:
        t16 = pathlib.Path(td) / "t16.wav"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(take), "-ar", "16000", "-ac", "1", str(t16)], check=True)
        rec = whisper_chars(t16)

    # pin whisper timings onto script characters
    sm = difflib.SequenceMatcher(None, "".join(c for c, *_ in rec), "".join(c for c, *_ in scr), autojunk=False)
    times = [None] * len(scr)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1): times[j1 + k] = rec[i1 + k][1:]
        elif tag == "replace":
            a, b = rec[i1][1], rec[i2 - 1][2]
            for k in range(j2 - j1): times[j1 + k] = (a + (b - a) * k / (j2 - j1), a + (b - a) * (k + 1) / (j2 - j1))
    matched = sum(bl.size for bl in sm.get_matching_blocks())
    k = 0
    while k < len(times):  # script chars whisper never heard: spread them between neighbours
        if times[k] is not None: k += 1; continue
        j = k
        while j < len(times) and times[j] is None: j += 1
        a = times[k - 1][1] if k else 0.0
        b = times[j][0] if j < len(times) else take_dur
        for q in range(k, j): times[q] = (a + (b - a) * (q - k) / (j - k), a + (b - a) * (q - k + 1) / (j - k))
        k = j

    # word and line spans (take-absolute)
    words = []  # per line: [(text, start, end)]
    for li, w in enumerate(WORDS):
        row = []
        for wi, word in enumerate(w.split("/")):
            idx = [n for n, (_, l2, w2) in enumerate(scr) if l2 == li and w2 == wi]
            row.append((caption_text(word), times[idx[0]][0], times[idx[-1]][1]))
        words.append(row)

    # cut between lines at the middle of the longest silence near the boundary
    hop = int(sr * 0.01)
    x = pcm.astype(np.float32).mean(1) / 32768
    rms = np.sqrt(np.convolve(x ** 2, np.ones(hop) / hop, "same")[::hop] + 1e-12)
    db = 20 * np.log10(rms)
    silent = db < np.percentile(db, 95) - 35
    cuts, gaps = [0.0], []
    for li in range(len(words) - 1):
        a, b = words[li][-1][2] - 0.25, words[li + 1][0][1] + 0.25
        fa, fb = max(0, int(a / 0.01)), min(len(silent), int(b / 0.01))
        best, run_start = (0, fa, fa), None
        for f in range(fa, fb + 1):
            if f < fb and silent[f]:
                run_start = f if run_start is None else run_start
            elif run_start is not None:
                if f - run_start > best[0]: best = (f - run_start, run_start, f)
                run_start = None
        if best[0] == 0:
            f = fa + int(np.argmin(db[fa:fb])); best = (0, f, f)
        cuts.append((best[1] + best[2]) / 2 * 0.01)
        gaps.append(best[0] * 0.01)
    cuts.append(take_dur)

    out_dir = P / "assets/voice"
    voices, report = [], []
    for li in range(len(words)):
        s, e = int(cuts[li] * sr), int(cuts[li + 1] * sr)
        clip = pcm[s:e]
        lead = LEAD_S if li == 0 else 0.0
        if li < len(words) - 1:
            tail = max(0.0, MIN_PAUSE_S - gaps[li]) + EXTRA_TAIL_S.get(li + 1, 0.0)
        else:
            tail = max(0.0, TAIL_S - (cuts[-1] - words[li][-1][2]))
        clip = np.concatenate([np.zeros((int(lead * sr), ch), np.int16), clip, np.zeros((int(tail * sr), ch), np.int16)])
        path = out_dir / f"{li + 1:02d}.wav"
        with wave.open(str(path), "wb") as wf:
            wf.setnchannels(ch); wf.setsampwidth(sw); wf.setframerate(sr); wf.writeframes(clip.tobytes())
        dur = round(len(clip) / sr, 3)
        base = cuts[li] - lead
        voices.append({
            "frame": li + 1, "path": f"assets/voice/{li + 1:02d}.wav", "duration_s": dur,
            "words": [{"id": f"w{n}", "text": t, "start": round(a - base, 3), "end": round(b - base, 3)}
                      for n, (t, a, b) in enumerate(words[li])],
        })
        lm = sum(1 for n, (_, l2, _w) in enumerate(scr) if l2 == li)
        report.append(f"  {li + 1:02d}  {dur:5.2f}s  voice {words[li][0][1] - base:4.2f}–{words[li][-1][2] - base:5.2f}s"
                      + (f"  pause {gaps[li]:.2f}s{' → +' + format(tail, '.2f') + 's' if tail else ''}" if li < len(words) - 1 else f"  hold {TAIL_S:.1f}s")
                      + f"  ({lm} 字)")

    meta_path = P / "audio_meta.json"
    old = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    meta = {"bgm": old.get("bgm"), "bgm_pending": bool(old.get("bgm_pending")), "voices": voices, "sfx": old.get("sfx", [])}
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    total = sum(v["duration_s"] for v in voices)
    print(f"✓ {take.name}: whisper heard {matched}/{len(scr)} script characters exactly; the rest were pinned by position")
    print("\n".join(report))
    print(f"✓ 10 clips → assets/voice/NN.wav · audio_meta.json · total {total:.1f}s")


if __name__ == "__main__":
    main()
