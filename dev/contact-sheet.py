#!/usr/bin/env python3
"""A contact sheet from a folder of screenshots: a grid of thumbnails, each
labelled with its file name, on Numa's dark page (#141414), under a title.
And a small JPEG of the sheet, 900 pixels wide, for the places where the
full sheet is too much: the run's log (ci/screenshots.sh prints it there as
base64, the one thing of a run the lead can read) and the README of the
`screenshots` branch, which the photographer opens on a phone. Needs Pillow.

    contact-sheet.py <folder> <sheet.png> <preview.jpg> [title...]

Run with no arguments, it checks itself on made-up pictures.

After Numa-mac's dev/contact-sheet.py, with fewer and larger thumbnails:
four portrait screens a row (three landscape ones), so that the 900-pixel
copy still shows each screen about 210 pixels wide.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

GAP = 16
LABEL = 36
PAGE = (20, 20, 20)
INK = (200, 200, 200)
PREVIEW_WIDTH = 900
PICTURES = (".png", ".jpg", ".jpeg")


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        # Pillow before 10.1 has its small bitmap font only.
        return ImageFont.load_default()


def sheet(folder, out, title=""):
    """The sheet of every picture in `folder`, by name; how many it has."""
    names = sorted(n for n in os.listdir(folder) if n.lower().endswith(PICTURES))
    if not names:
        return 0
    pictures = []
    for name in names:
        with Image.open(os.path.join(folder, name)) as im:
            pictures.append((os.path.splitext(name)[0], im.convert("RGB")))
    landscape = sum(1 for _, im in pictures if im.width > im.height) * 2 > len(pictures)
    width, columns = (480, 3) if landscape else (360, 4)
    for _, im in pictures:
        im.thumbnail((width, width * 3))
    height = max(im.height for _, im in pictures)
    columns = min(columns, len(pictures))
    rows = math.ceil(len(pictures) / columns)
    top = 60 if title else GAP
    cell = height + LABEL + GAP
    canvas = Image.new("RGB", (GAP + columns * (width + GAP), top + rows * cell), PAGE)
    draw = ImageDraw.Draw(canvas)
    if title:
        draw.text((GAP, 14), title, fill=(235, 235, 235), font=font(30))
    # Large enough to read in the 900-pixel copy (about 14 pixels there).
    label_font = font(24)
    for i, (label, im) in enumerate(pictures):
        x = GAP + (i % columns) * (width + GAP)
        y = top + (i // columns) * cell
        canvas.paste(im, (x + (width - im.width) // 2, y))
        draw.text((x, y + height + 6), label, fill=INK, font=label_font)
    canvas.save(out, optimize=True)
    return len(pictures)


def preview(sheet_png, out, width=PREVIEW_WIDTH):
    """The sheet `width` pixels wide, as a JPEG small enough for a log."""
    lanczos = getattr(Image, "Resampling", Image).LANCZOS
    with Image.open(sheet_png) as im:
        im = im.convert("RGB")
        if im.width > width:
            im = im.resize((width, round(im.height * width / im.width)), lanczos)
        im.save(out, "JPEG", quality=72, optimize=True, progressive=True)
    return os.path.getsize(out)


def check():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        # An iPhone 17 Pro's screen, an iPad Pro's held sideways, and odd ones.
        for i, size in enumerate([(1206, 2622), (2752, 2064), (100, 100)] * 3):
            Image.new("RGB", size, (40 * i, 90, 160)).save(os.path.join(d, f"{i:02d}-shot.png"))
        out = os.path.join(d, "sheet.png")
        assert sheet(d, out, "test") == 9
        with Image.open(out) as im:
            assert im.width == GAP + 4 * (360 + GAP), im.size
            assert im.height > 3 * 360, im.size
        jpg = os.path.join(d, "sheet.jpg")
        preview(out, jpg)
        with Image.open(jpg) as im:
            assert im.width == PREVIEW_WIDTH and im.format == "JPEG", (im.size, im.format)
        empty = tempfile.mkdtemp(dir=d)
        assert sheet(empty, os.path.join(d, "none.png")) == 0
        wide = tempfile.mkdtemp(dir=d)
        for i in range(4):
            Image.new("RGB", (2752, 2064)).save(os.path.join(wide, f"{i:02d}-pad.png"))
        assert sheet(wide, out) == 4
        with Image.open(out) as im:
            assert im.width == GAP + 3 * (480 + GAP), im.size
    print("ok")


if __name__ == "__main__":
    if len(sys.argv) >= 4:
        count = sheet(sys.argv[1], sys.argv[2], " ".join(sys.argv[4:]))
        if count:
            size = preview(sys.argv[2], sys.argv[3])
            print(f"{count} pictures on {sys.argv[2]}; {sys.argv[3]} is {size // 1024} KB")
        else:
            print(f"no pictures in {sys.argv[1]}")
    else:
        check()
