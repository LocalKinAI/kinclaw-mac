#!/usr/bin/env python3
"""Cut the template's two families to the characters a film actually uses, as woff2.

The full Noto Serif SC is 25 MB; a film's text is a few hundred characters. The render machine is
a clean headless Chrome with no CJK fonts, so the subset ships with the project.

    python subset.py --text STORYBOARD.md SCRIPT.md ... --out <hyperframes project>/assets/fonts

The full variable fonts (OFL) come from github.com/google/fonts once, into ~/.cache/kinclaw-fonts.
"""
import argparse
import pathlib
import urllib.request

from fontTools import subset

CACHE = pathlib.Path.home() / ".cache" / "kinclaw-fonts"
RAW = "https://raw.githubusercontent.com/google/fonts/main/ofl/"
SOURCES = {
    "NotoSerifSC[wght].ttf": RAW + "notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
    "CormorantGaramond[wght].ttf": RAW + "cormorantgaramond/CormorantGaramond%5Bwght%5D.ttf",
    "CormorantGaramond-Italic[wght].ttf": RAW + "cormorantgaramond/CormorantGaramond-Italic%5Bwght%5D.ttf",
}
PUNCT = set("·—–‘’“”…≠→←《》「」『』（）【】，。、；：！？　％")


def source(name: str) -> pathlib.Path:
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(SOURCES[name], path)
    return path


def cut(name: str, out: pathlib.Path, text: str) -> None:
    opts = subset.Options(); opts.flavor = "woff2"; opts.layout_features = ["*"]; opts.name_IDs = ["*"]
    font = subset.load_font(str(source(name)), opts)
    s = subset.Subsetter(opts); s.populate(text=text); s.subset(font)
    subset.save_font(font, str(out), opts)
    print(f"  {out.name}: {out.stat().st_size // 1024} KB")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", nargs="+", required=True, help="files whose characters appear on screen or in captions")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    chars = set()
    for f in a.text:
        chars |= set(pathlib.Path(f).read_text(encoding="utf-8"))
    chars |= {chr(c) for c in range(0x20, 0x7F)} | PUNCT
    chars = {c for c in chars if c.isprintable() or c == "　"}
    latin = "".join(sorted(c for c in chars if ord(c) < 0x3000 and c not in PUNCT - set("·—–‘’“”…≠→←")))
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    cut("NotoSerifSC[wght].ttf", out / "NotoSerifSC-subset.woff2", "".join(sorted(chars)))
    cut("CormorantGaramond[wght].ttf", out / "CormorantGaramond.woff2", latin)
    cut("CormorantGaramond-Italic[wght].ttf", out / "CormorantGaramond-Italic.woff2", latin)
    print(f"  {len(chars)} characters")


if __name__ == "__main__":
    main()
