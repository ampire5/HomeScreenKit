#!/usr/bin/env python3
"""Writes Sources/HomeChrome/LucideFont.swift: the Lucide icon font cut down to the icons of scripts/lucide-names.txt,
as base64, and their code points.

The font is lucide-static's font/lucide.ttf (ISC, the licence in Sources/HomeChrome/LICENSE-lucide). Its code points
change from one Lucide release to the next, so the release is pinned here and the table is written with the font.
The font goes into the code, not into a resource bundle: the apps' bundles (scripts/make-app.sh) carry no SwiftPM
resource bundles.

    curl -sL https://registry.npmjs.org/lucide-static/-/lucide-static-0.469.0.tgz | tar xz -C /tmp
    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install fonttools
    /tmp/venv/bin/python scripts/lucide-font.py /tmp/package
"""
import base64
import io
import json
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

VERSION = "0.469.0"
ROOT = pathlib.Path(__file__).resolve().parent.parent

package = pathlib.Path(sys.argv[1])
if json.loads((package / "package.json").read_text())["version"] != VERSION:
    sys.exit(f"lucide-static {VERSION} expected in {package}")
info = json.loads((package / "font/info.json").read_text())
names = [line.strip() for line in (ROOT / "scripts/lucide-names.txt").read_text().splitlines()
         if line.strip() and not line.startswith("#")]
missing = [n for n in names if n not in info]
if missing:
    sys.exit(f"not in Lucide {VERSION}: {', '.join(missing)}")
codepoints = {n: int(info[n]["encodedCode"].lstrip("\\"), 16) for n in names}

font = TTFont(package / "font/lucide.ttf")
options = subset.Options()
options.name_IDs = ["*"]
options.notdef_outline = True
subsetter = subset.Subsetter(options)
subsetter.populate(unicodes=codepoints.values())
subsetter.subset(font)
out = io.BytesIO()
font.save(out)
data = base64.b64encode(out.getvalue()).decode()

table = "\n".join(f'        "{n}": 0x{c:X},' for n, c in sorted(codepoints.items()))
lines = "\n".join(data[i:i + 116] for i in range(0, len(data), 116))
(ROOT / "Sources/HomeChrome/LucideFont.swift").write_text(f'''// Written by scripts/lucide-font.py from lucide-static {VERSION} (ISC, LICENSE-lucide); do not edit.

extension Lucide {{
    /// The Lucide release the font and the table come from: its code points are its own.
    public static let version = "{VERSION}"

    /// The icons the font has, by Lucide's name, and their code points.
    static let codepoints: [String: UInt32] = [
{table}
    ]

    /// The font (TrueType) with only those icons.
    static let fontData = """
{lines}
"""
}}
''')
print(f"{len(names)} icons, {len(out.getvalue())} bytes")
