#!/usr/bin/env python3
"""Jukebox's app icon, the Arch identity's (docs/BRAND.md): the mark lit on
Cabinet, drawn by dev/brand/icon.py from dev/brand/geom.py, in its three
appearances — default, dark and tinted — for the asset catalog's single-size
icon (Xcode 16 and later).

The photographer, 8 November 2026, on the eclipse icon this replaces: "Het
heeft nu wel heel weinig eigen branding en je hergebruikt nu het numa logo
daar mag je wel meer eigen vorm aan geven." Of the four directions drawn:
"Die arch is leuk."

The SVG is rendered by Chromium (node with playwright: `npm i playwright`
and `npx playwright install chromium` once), at twice the size and scaled
down, then flattened to opaque RGB: App Store Connect turns away an icon
with an alpha channel.

    python3 dev/make-icon.py   writes AppIcon.png, AppIcon-dark.png,
                               AppIcon-tinted.png and Contents.json into
                               Jukebox/Resources/Assets.xcassets/AppIcon.appiconset/
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "brand"))
from icon import icon_html  # noqa: E402

OUT = os.path.join(HERE, "..", "Jukebox", "Resources", "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024
VARIANTS = [("default", "AppIcon.png", None), ("dark", "AppIcon-dark.png", "dark"),
            ("tinted", "AppIcon-tinted.png", "tinted")]


def render(variant, path):
    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, "icon.html")
        shot = os.path.join(tmp, "icon.png")
        with open(page, "w") as f:
            f.write(icon_html(SIZE, variant))
        subprocess.run(["node", os.path.join(HERE, "brand", "render.js"), page, shot, str(SIZE), str(SIZE), "2"],
                       check=True)
        img = Image.open(shot).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    img.save(path)
    check = Image.open(path)
    assert check.mode == "RGB" and check.size == (SIZE, SIZE), (path, check.mode, check.size)


def main():
    os.makedirs(OUT, exist_ok=True)
    images = []
    for variant, name, appearance in VARIANTS:
        render(variant, os.path.join(OUT, name))
        entry = {"filename": name, "idiom": "universal", "platform": "ios", "size": f"{SIZE}x{SIZE}"}
        if appearance:
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        images.append(entry)
        print("wrote", os.path.normpath(os.path.join(OUT, name)))
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
