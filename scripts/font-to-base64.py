#!/usr/bin/env python3
"""font-to-base64.py: download a Google Font and print @font-face rules with the font embedded as
base64 (same origin, NO external call, so it loads before consent without breaking the Complianz block).

Usage:
  python3 scripts/font-to-base64.py "Nunito" "300 700" NunitoBanner > fontface.css
  python3 scripts/font-to-base64.py "Nunito" "600" --subsets latin,latin-ext > fontface.css
  python3 scripts/font-to-base64.py "Poppins" "600" PoppinsBanner --json

Arguments: <family> <weight-or-range> [css-family-name] [--subsets LIST] [--json]
- family: Google Font name (e.g. "Nunito", "Poppins")
- weight-or-range: "600", or a range "300 700". A range needs a variable font; for a static font the
  script falls back to the first weight and says so (declaring a range on one static file would make
  the browser fake the other weights).
- css-family-name: name for @font-face (default "<Family>Banner"). Use a UNIQUE name so it does not
  collide with the blocked external family of the same name.
- --subsets: comma-separated Google subsets, default "latin". Add "latin-ext" for letters such as
  a-ogonek, e-ogonek, l-stroke, s-caron or z-dot used in many European languages. One @font-face per
  subset, each with its unicode-range.
- --json: print {"family", "weight", "faces": [{"subset", "unicode_range", "b64"}]} instead of CSS.

WHY: when a font the banner copies is a Google Font, Complianz blocks it before consent (data-href). The
banner is shown BEFORE consent, so it renders a fallback instead of the brand font. A base64 self-host
fixes that in a GDPR-friendly way (a local font needs no consent). Most Google Fonts use the SIL Open
Font License, which allows embedding; check the license of the font you use.
See references/banner-design-match.md.
"""
import argparse, base64, json, re, sys, urllib.error, urllib.request

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"


def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=30).read()


def css2(family, axis):
    url = f"https://fonts.googleapis.com/css2?family={family.replace(' ', '+')}:wght@{axis}&display=swap"
    return fetch(url).decode()


def css2_or_exit(family, axis):
    try:
        return css2(family, axis)
    except urllib.error.HTTPError as e:
        sys.exit(f"Google Fonts has no '{family}' at weight {axis} (HTTP {e.code}). Check the family name "
                 f"and weight; a font that is not on Google Fonts cannot be fetched by this script.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('family')
    ap.add_argument('weight')
    ap.add_argument('css_name', nargs='?')
    ap.add_argument('--subsets', default='latin')
    ap.add_argument('--json', action='store_true')
    a = ap.parse_args()

    weights = a.weight.split()
    if not weights or not all(w.isdigit() for w in weights) or len(weights) > 2:
        sys.exit("weight must be one number (600) or a range of two numbers (\"300 700\")")
    css_name = a.css_name or re.sub(r'\s+', '', a.family) + "Banner"
    wanted = [s.strip() for s in a.subsets.split(',') if s.strip()]

    declared = weights[0]
    if len(weights) == 2:
        try:
            css = css2(a.family, f"{weights[0]}..{weights[1]}")
            declared = f"{weights[0]} {weights[1]}"
        except urllib.error.HTTPError:
            css = css2_or_exit(a.family, weights[0])
            sys.stderr.write(f"{a.family} is not a variable font for {weights[0]}..{weights[1]}: "
                             f"embedding weight {weights[0]} only\n")
    else:
        css = css2_or_exit(a.family, weights[0])

    # the css2 response is a series of "/* subset */ @font-face{...}" blocks
    blocks = re.split(r'/\*\s*([a-z0-9-]+)\s*\*/', css)
    found = {}
    for i in range(1, len(blocks) - 1, 2):
        url = re.search(r'url\((https://[^)]+\.woff2)\)', blocks[i + 1])
        rng = re.search(r'unicode-range:\s*([^;]+);', blocks[i + 1])
        if url:
            found[blocks[i]] = (url.group(1), rng.group(1).strip() if rng else None)
    missing = [s for s in wanted if s not in found]
    if missing:
        sys.exit(f"subset(s) not offered for {a.family}: {', '.join(missing)} (available: {', '.join(found) or 'none'})")

    faces = []
    for s in wanted:
        url, rng = found[s]
        data = fetch(url)
        faces.append({'subset': s, 'unicode_range': rng, 'b64': base64.b64encode(data).decode()})
        sys.stderr.write(f"{a.family} {declared} [{s}]: woff2 {len(data)} B -> base64 (CSS family: {css_name})\n")

    if a.json:
        print(json.dumps({'family': css_name, 'weight': declared, 'faces': faces}))
        return
    for f in faces:
        rng = f";unicode-range:{f['unicode_range']}" if f['unicode_range'] and len(faces) > 1 else ''
        print(f"@font-face{{font-family:'{css_name}';font-style:normal;font-weight:{declared};"
              f"font-display:swap;src:url(data:font/woff2;base64,{f['b64']}) format('woff2'){rng};}}")


if __name__ == "__main__":
    try:
        main()
    except (urllib.error.URLError, OSError) as e:
        sys.exit(f"Network error while contacting Google Fonts: {getattr(e, 'reason', e)}")
