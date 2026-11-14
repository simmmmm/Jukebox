#!/usr/bin/env python3
"""Jukebox's app icon, the Arch identity's (docs/BRAND.md): the mark lit on
Cabinet, drawn by dev/brand/icon.py from dev/brand/geom.py, in its three
appearances — default, dark and tinted — for the asset catalog's single-size
icon (Xcode 16 and later), and the Mac's sizes from the default one.

The photographer, 8 November 2026, on the eclipse icon this replaces: "Het
heeft nu wel heel weinig eigen branding en je hergebruikt nu het numa logo
daar mag je wel meer eigen vorm aan geven." Of the four directions drawn:
"Die arch is leuk."

The SVG is rendered by Chromium (node with playwright: `npm i playwright`
and `npx playwright install chromium` once), at twice the size and scaled
down, then flattened to opaque RGB: App Store Connect turns away an icon
with an alpha channel.

    python3 dev/make-icon.py   writes AppIcon.png, AppIcon-dark.png,
                               AppIcon-tinted.png, AppIcon-mac-*.png and
                               Contents.json into
                               Jukebox/Resources/Assets.xcassets/AppIcon.appiconset/
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "brand"))
from icon import icon_html  # noqa: E402

OUT = os.path.join(HERE, "..", "Jukebox", "Resources", "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024
VARIANTS = [("default", "AppIcon.png", None), ("dark", "AppIcon-dark.png", "dark"),
            ("tinted", "AppIcon-tinted.png", "tinted")]
# Apple's Mac grid: the artwork on a rounded square of 824 in the 1024 canvas,
# transparent around it, because a Mac icon carries its own shape (the
# iPhone's is masked by the system). 185.4 is the corner of Apple's template,
# approximately: Apple's corner is continuous, this one is circular.
MAC_BODY, MAC_CORNER = 824, 185.4
MAC_SIZES = [16, 32, 128, 256, 512]


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


def mac_icons(art_path):
    """The Mac's ten slots (16 to 512, @1x and @2x), one file each, from the
    default artwork; returns their Contents.json entries."""
    body = Image.open(art_path).convert("RGB").resize((MAC_BODY, MAC_BODY), Image.LANCZOS)
    # The mask drawn at four times and scaled down, for a smooth edge.
    big = MAC_BODY * 4
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=MAC_CORNER * 4, fill=255)
    body.putalpha(mask.resize((MAC_BODY, MAC_BODY), Image.LANCZOS))
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(body, ((SIZE - MAC_BODY) // 2,) * 2)
    entries = []
    for size in MAC_SIZES:
        for scale in (1, 2):
            px = size * scale
            name = f"AppIcon-mac-{size}{'@2x' if scale == 2 else ''}.png"
            path = os.path.join(OUT, name)
            canvas.resize((px, px), Image.LANCZOS).save(path)
            check = Image.open(path)
            assert check.mode == "RGBA" and check.size == (px, px), (path, check.mode, check.size)
            entries.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"})
            print("wrote", os.path.normpath(path))
    return entries


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
    images += mac_icons(os.path.join(OUT, "AppIcon.png"))
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
