"""
One-off helper: download the Inter + Outfit variable fonts from the google/fonts
repo and instance the static weights the SILENCE app actually uses, named exactly
as the google_fonts package expects for asset bundling:

  Inter-Regular.ttf  (400)   Inter-Medium.ttf (500)
  Inter-SemiBold.ttf (600)   Inter-Bold.ttf   (700)
  Outfit-Regular.ttf (400)   Outfit-SemiBold.ttf (600)   Outfit-Bold.ttf (700)

Output -> assets/google_fonts/
Run:  python tools/build_static_fonts.py
"""
import os
import sys
import urllib.request
from fontTools import ttLib
from fontTools import subset
from fontTools.varLib import instancer

# Unicode ranges to KEEP after subsetting. Inter/Outfit are Latin-script fonts
# (no Devanagari), so Hindi names already fall back to the system font either
# way. We keep full Latin + the punctuation/symbols the app actually renders as
# text (notably the Rupee sign U+20B9, bullets, dashes, curly quotes, ✓/★).
KEEP_UNICODES = (
    "U+0000-00FF,"   # Basic Latin + Latin-1 Supplement
    "U+0100-017F,"   # Latin Extended-A
    "U+0180-024F,"   # Latin Extended-B (some transliterated names)
    "U+0300-036F,"   # Combining diacritical marks
    "U+2000-206F,"   # General punctuation (• — – … curly quotes)
    "U+20A0-20BF,"   # Currency symbols (₹ = U+20B9)
    "U+2100-214F,"   # Letterlike symbols (™ ℹ etc.)
    "U+2190-21FF,"   # Arrows
    "U+2200-22FF,"   # Mathematical operators (×, ÷, ≤, ≥)
    "U+2300-23FF,"   # Misc technical
    "U+2600-27BF"    # Misc symbols + dingbats (★ ☆ ✓ ✗)
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "google_fonts")
os.makedirs(OUT, exist_ok=True)

UA = {"User-Agent": "Mozilla/5.0 (font-build script)"}

SOURCES = {
    "Inter": {
        "url": "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf",
        # pin opsz to its default (14) so we get a single weight axis to set
        "pin": {"opsz": 14.0},
        "weights": {"Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700},
    },
    "Outfit": {
        "url": "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit%5Bwght%5D.ttf",
        "pin": {},
        "weights": {"Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700, "ExtraBold": 800},
    },
}


def download(url, dest):
    print(f"  download {url}")
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req) as r, open(dest, "wb") as f:
        f.write(r.read())


def main():
    cache = os.path.join(ROOT, "tools", "_var_cache")
    os.makedirs(cache, exist_ok=True)

    for family, cfg in SOURCES.items():
        var_path = os.path.join(cache, f"{family}-VF.ttf")
        if not os.path.exists(var_path):
            download(cfg["url"], var_path)

        for variant, wght in cfg["weights"].items():
            font = ttLib.TTFont(var_path)
            axes = dict(cfg["pin"])
            axes["wght"] = float(wght)
            instancer.instantiateVariableFont(font, axes, inplace=True)

            # Subset to the kept unicode ranges (keeps kerning/ligatures + names).
            opts = subset.Options()
            opts.layout_features = ["*"]
            opts.name_IDs = ["*"]
            opts.glyph_names = False
            opts.recalc_timestamp = False
            opts.notdef_outline = True
            ss = subset.Subsetter(options=opts)
            ss.populate(unicodes=subset.parse_unicodes(KEEP_UNICODES))
            ss.subset(font)

            out_path = os.path.join(OUT, f"{family}-{variant}.ttf")
            font.save(out_path)
            print(f"  wrote {out_path}  ({os.path.getsize(out_path)//1024} KB)")

    # ship the OFL license alongside the fonts (both are OFL-1.1)
    try:
        ofl = os.path.join(cache, "OFL.txt")
        if not os.path.exists(ofl):
            download("https://github.com/google/fonts/raw/main/ofl/inter/OFL.txt", ofl)
        with open(ofl, "r", encoding="utf-8") as a, open(os.path.join(OUT, "OFL.txt"), "w", encoding="utf-8") as b:
            b.write(a.read())
        print("  wrote OFL.txt")
    except Exception as e:
        print(f"  (OFL fetch skipped: {e})", file=sys.stderr)


if __name__ == "__main__":
    main()
