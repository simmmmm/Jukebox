#!/usr/bin/env python3
"""Now Playing's accent from a cover, in Python: the same steps and numbers
as JukeboxKit's CoverAccent.swift (read its comment for why), for sketches
and for trying covers before the app has them.

    dev/accent.py cover.jpg [more.jpg …]   the accent of each, or "Glow"
    dev/accent.py --sheet out.png a.jpg …  a sheet of them on Cabinet

Needs Pillow and NumPy. CoverAccentTests checks the Swift against colours
this file gave for the same pixels."""
import math
import sys

import numpy as np
from PIL import Image

GLOW = (0xFF, 0xB5, 0x4D)
CABINET = (0x1E, 0x0A, 0x07)
SIDE = 32
STEPS = 36
MINIMUM_CHROMA = 0.035
MINIMUM_SHARE = 0.02
LEAST_ACCENT_CHROMA = 0.10
LOWEST_LIGHTNESS = 0.70
SECOND_APART = 60
SECOND_SHARE = 0.02


def linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def encoded(l):
    l = np.clip(l, 0, 1)
    return np.where(l <= 0.0031308, 12.92 * l, 1.055 * l ** (1 / 2.4) - 0.055)


def oklab(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    l = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def linear_rgb(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return np.array([4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s])


def luminance(rgb8):
    lin = linear(np.array(rgb8, float) / 255)
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


GLOW_LIGHTNESS = float(oklab(linear(np.array(GLOW, float) / 255))[0])


def most_chroma(L, hue):
    low, high = 0.0, 0.4
    for _ in range(30):
        mid = (low + high) / 2
        rgb = linear_rgb(L, mid * math.cos(math.radians(hue)), mid * math.sin(math.radians(hue)))
        if (rgb >= 0).all() and (rgb <= 1).all():
            low = mid
        else:
            high = mid
    return low


def group(C, h, vivid, middle):
    """The pixels within 20 degrees of a hue: their share of the cover,
    their hue (the mean of the angles, weighed by chroma) and their 75th
    percentile of chroma."""
    near = vivid & (np.abs((h - middle + 180) % 360 - 180) <= 20)
    if near.sum() == 0:
        return None
    ang = np.radians(h[near])
    hue = math.degrees(math.atan2((C[near] * np.sin(ang)).sum(), (C[near] * np.cos(ang)).sum())) % 360
    return dict(share=near.sum() / len(C), hue=hue, chroma=float(np.percentile(C[near], 75)))


def colour(hue, chroma):
    """A hue at Glow's lightness, or a little darker where it has no room."""
    wanted = max(chroma, LEAST_ACCENT_CHROMA)
    chosen = None
    L_try = GLOW_LIGHTNESS
    while L_try >= LOWEST_LIGHTNESS - 1e-9:
        c = min(wanted, most_chroma(L_try, hue))
        if chosen is None or c > chosen[1] + 0.01:
            chosen = (L_try, c)
        L_try -= 0.01
    L_c, c = chosen
    rgb = encoded(linear_rgb(L_c, c * math.cos(math.radians(hue)), c * math.sin(math.radians(hue))))
    return tuple(int(round(v * 255)) for v in rgb)


def accent_of_pixels(rgb8):
    """rgb8: N x 3, 0 … 255 (opaque). The accent as 8-bit RGB, or None."""
    lab = oklab(linear(np.asarray(rgb8, float) / 255))
    L, a, b = lab
    C = np.hypot(a, b)
    h = np.degrees(np.arctan2(b, a)) % 360
    vivid = (C >= MINIMUM_CHROMA) & (L > 0.25) & (L < 0.97)
    if vivid.sum() == 0:
        return None
    hist = np.zeros(STEPS)
    np.add.at(hist, (h[vivid] // (360 / STEPS)).astype(int) % STEPS, C[vivid] ** 2)
    smooth = hist + 0.5 * (np.roll(hist, 1) + np.roll(hist, -1))
    order = np.argsort(-smooth, kind='stable')
    first = group(C, h, vivid, (int(order[0]) + 0.5) * 360 / STEPS)
    if first is None or first['share'] < MINIMUM_SHARE:
        return None
    # The cover's second colour: the strongest step 60 degrees or more from
    # the first, if it colours 2% of the cover.
    for step in order:
        if smooth[step] <= 0:
            break
        middle = (int(step) + 0.5) * 360 / STEPS
        if abs((middle - first['hue'] + 180) % 360 - 180) < SECOND_APART:
            continue
        second = group(C, h, vivid, middle)
        if second is not None and second['share'] >= SECOND_SHARE:
            return colour(second['hue'], second['chroma'])
        break
    return colour(first['hue'], first['chroma'])


def accent(path):
    """A cover file's accent, or None (the app keeps Glow)."""
    im = Image.open(path).convert('RGB').resize((SIDE, SIDE), Image.BOX)
    return accent_of_pixels(np.asarray(im, float).reshape(-1, 3))


def hexs(rgb):
    return '#%02X%02X%02X' % rgb


def sheet(out, paths):
    from PIL import ImageDraw
    row, width = 112, 520
    im = Image.new('RGB', (width, row * len(paths)), CABINET)
    d = ImageDraw.Draw(im)
    for i, p in enumerate(paths):
        found = accent(p)
        colour = found or GLOW
        y = i * row
        im.paste(Image.open(p).convert('RGB').resize((88, 88)), (12, y + 12))
        d.rectangle((116, y + 30, 116 + 220, y + 34), fill=(80, 64, 60))
        d.rectangle((116, y + 30, 116 + 90, y + 34), fill=colour)
        d.ellipse((116, y + 50, 140, y + 74), fill=colour)
        d.text((150, y + 54), f"{hexs(colour)}{'' if found else ' (Glow)'}  {contrast(colour, CABINET):.1f}:1",
               fill=colour)
    im.save(out)


if __name__ == '__main__':
    args = sys.argv[1:]
    if args[:1] == ['--sheet']:
        sheet(args[1], args[2:])
    else:
        for p in args:
            found = accent(p)
            print(p, hexs(found) if found else 'Glow')
