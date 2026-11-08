#!/usr/bin/env python3
"""Jukebox's app icon, drawn the way Numa's eclipse mark is built (Numa-mac's
NumaMark.swift: two discs of one diameter, centres 0.505 diameters apart, the
light one on the left and on top, a glow brightest at its rim that clears
toward its centre so the dark disc shows through), with one change that
makes it Jukebox: the dark disc is a record — fine grooves, a label, the
spindle hole. "Qua branding mag het wel op Numa lijken" (the photographer,
8 November 2026).

    python3 dev/make-icon.py   writes Jukebox/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
SS = 2  # drawn at twice the size, then scaled down: smooth edges
N = S * SS
OUT = os.path.join(os.path.dirname(__file__), "..", "Jukebox", "Resources", "Assets.xcassets",
                   "AppIcon.appiconset", "AppIcon.png")

D = int(N * 0.50)          # disc diameter
GAP = 0.505                # centre to centre, in diameters
width = D * (1 + GAP)
x0 = (N - width) / 2
cy = N / 2
light_c = (x0 + D / 2, cy)
dark_c = (x0 + D / 2 + D * GAP, cy)


def disc_mask(c, r):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=255)
    return m


# Ground: Numa's page, #141414, a little lighter at the top as a lit surface.
ground = Image.new("RGB", (N, N))
gd = ImageDraw.Draw(ground)
for y in range(N):
    v = int(0x1c - (0x1c - 0x10) * (y / N))
    gd.line([(0, y), (N, y)], fill=(v, v, v))

# The record: #444 at the upper left rim to #080808 at the lower right.
r = D / 2
# A plane across the disc's own box, upper left to lower right.
ramp = Image.linear_gradient("L").resize((N, N)).rotate(45, resample=Image.BICUBIC, expand=True)
ramp = ramp.crop(((ramp.width - N) // 2, (ramp.height - N) // 2, (ramp.width + N) // 2, (ramp.height + N) // 2))
box = int(D * 1.2)
ramp = ramp.resize((box, box))
plane = Image.new("L", (N, N), 0)
plane.paste(ramp, (int(dark_c[0] - box / 2), int(dark_c[1] - box / 2)))
lo, hi = 0x06, 0x4c
rec = Image.merge("RGB", [plane.point(lambda v: int(hi + (lo - hi) * v / 255))] * 3)
# Grooves: rings a shade lighter, more of them toward the rim.
grooves = Image.new("L", (N, N), 0)
gr = ImageDraw.Draw(grooves)
k = r * 0.40
while k < r * 0.965:
    a = 90 if random.random() < 0.15 else 45
    gr.ellipse([dark_c[0] - k, dark_c[1] - k, dark_c[0] + k, dark_c[1] + k], outline=a, width=SS)
    k += r * 0.018
rec = Image.composite(Image.new("RGB", (N, N), (120, 120, 120)), rec, grooves)
# A sheen across the grooves, as light falls on vinyl.
sheen = Image.new("L", (N, N), 0)
sd = ImageDraw.Draw(sheen)
sd.pieslice([dark_c[0] - r, dark_c[1] - r, dark_c[0] + r, dark_c[1] + r], 200, 250, fill=40)
sd.pieslice([dark_c[0] - r, dark_c[1] - r, dark_c[0] + r, dark_c[1] + r], 20, 70, fill=22)
sheen = sheen.filter(ImageFilter.GaussianBlur(N * 0.05))
rec = Image.composite(Image.new("RGB", (N, N), (200, 200, 200)), rec, sheen)
# A crisp rim, lit at the upper left.
rim = Image.new("L", (N, N), 0)
ImageDraw.Draw(rim).arc([dark_c[0] - r, dark_c[1] - r, dark_c[0] + r, dark_c[1] + r], 150, 330, fill=110, width=int(N * 0.003))
rec = Image.composite(Image.new("RGB", (N, N), (170, 170, 170)), rec, rim.filter(ImageFilter.GaussianBlur(SS)))
# The label and the spindle hole.
lr = r * 0.30
ImageDraw.Draw(rec).ellipse([dark_c[0] - lr, dark_c[1] - lr, dark_c[0] + lr, dark_c[1] + lr], fill=(0x30, 0x30, 0x30), outline=(0x48, 0x48, 0x48), width=SS * 2)
hr = r * 0.035
ImageDraw.Draw(rec).ellipse([dark_c[0] - hr, dark_c[1] - hr, dark_c[0] + hr, dark_c[1] + hr], fill=(0x10, 0x10, 0x10))

img = ground.copy()
img.paste(rec, (0, 0), disc_mask(dark_c, r))

# The light disc: white at the rim, clear toward the centre (NumaMark's
# stops: opacity 0.22 at the centre to 0.97 at the rim, grey 0.5 to white).
stops = [(0, 0.500, 0.22), (0.1, 0.543, 0.24), (0.2, 0.745, 0.266), (0.3, 0.803, 0.35),
         (0.4, 0.846, 0.443), (0.5, 0.878, 0.539), (0.6, 0.909, 0.633), (0.7, 0.938, 0.727),
         (0.8, 0.968, 0.818), (0.9, 0.999, 0.907), (0.97, 1.0, 0.96), (1.0, 1.0, 0.97)]


def at(t):
    for (t0, w0, a0), (t1, w1, a1) in zip(stops, stops[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0) if t1 > t0 else 0
            return w0 + (w1 - w0) * f, a0 + (a1 - a0) * f
    return stops[-1][1], stops[-1][2]


glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
gp = ImageDraw.Draw(glow)
steps = 400
for i in range(steps, 0, -1):
    t = i / steps
    w, a = at(t)
    rr = r * t
    g = int(255 * w)
    gp.ellipse([light_c[0] - rr, light_c[1] - rr, light_c[0] + rr, light_c[1] + rr], fill=(g, g, g, int(255 * a)))
# Each ring drawn over the last would stack its alpha; the stops are what
# one ring at that radius shows, so draw them as one layer of their own.
img = img.convert("RGBA")
img.alpha_composite(glow)
# The rim's slight bloom over the record.
bloom = Image.new("L", (N, N), 0)
ImageDraw.Draw(bloom).ellipse([light_c[0] - r, light_c[1] - r, light_c[0] + r, light_c[1] + r], outline=120, width=int(N * 0.004))
bloom = bloom.filter(ImageFilter.GaussianBlur(N * 0.006))
img = Image.composite(Image.new("RGBA", (N, N), (255, 255, 255, 255)), img, bloom)

# Fine grain over everything, as the mark has.
random.seed(3)
noise = Image.effect_noise((N, N), 18).convert("RGBA")
img = ImageChops.overlay(img, Image.blend(Image.new("RGBA", (N, N), (128, 128, 128, 255)), noise, 0.25))

img = img.convert("RGB").resize((S, S), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print("wrote", os.path.normpath(OUT))
