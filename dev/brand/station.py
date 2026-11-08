"""A station's artwork, as the app draws it (Jukebox/Components/StationArtwork.swift,
whose StationArtCut carries these same numbers — change both together): the
arch window with the seed's covers in it, two tubes of light around it, the
first cover's own colour, darkened, as the room, and from 200 pt the
station's name under the window. Drawn in a 300-unit square.

    python3 dev/brand/station.py preview.html   every kind at 240, 150, 64 and 34 pt
    node dev/brand/render.js preview.html preview.png 1240 560 2
"""
import colorsys
import itertools
import os
import sys

_n = itertools.count()

# The tubes in art (Theme.Arch.outerTube, innerTube) and their hot lines.
OUTER, INNER = "#F07E36", "#FFB44C"
OUTER_HOT, INNER_HOT = "#FFC08A", "#FFE3AE"
CABINET, CABINET_HAZE = "#1E0A07", "#4A1D0F"


class Cut:
    """t: tube stroke; g: the gaps; rw: the window's half width; top: the
    outer tube's top edge; base: where the window, the legs and the core end."""

    def __init__(self, t, g, rw, top, base):
        self.t, self.g, self.rw, self.top, self.base = t, g, rw, top, base
        self.ri = rw + g + t / 2               # inner tube centre line
        self.ro = self.ri + t + g              # outer tube centre line
        self.sp = top + t / 2 + self.ro        # spring line
        self.leg = base - t / 2
        self.win_top = self.sp - rw
        self.rc = rw * 25 / 70                 # the lit core's radius


# From 200 pt the name is drawn under the window (shelves have real Text
# under their tiles, for Dynamic Type); below 60 pt the tubes are heavier
# and the window shows one cover, as four would be specks.
NAMED = Cut(t=4.4, g=5.6, rw=70, top=22, base=228)
TILE = Cut(t=6.0, g=6.5, rw=82, top=26, base=274)
SMALL = Cut(t=9.0, g=8.0, rw=80, top=22, base=280)


def cut_for(size):
    return NAMED if size >= 200 else (TILE if size >= 60 else SMALL)


def room(rgb_hex):
    """The ground and the haze from a cover's average colour: its hue, the
    saturation held to 0.5, brightness 0.14 and 0.28 (the station's room)."""
    r, g, b = (int(rgb_hex[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, s, _ = colorsys.rgb_to_hsv(r, g, b)
    s = min(s, 0.5)
    out = []
    for v in (0.14, 0.28):
        rr, gg, bb = colorsys.hsv_to_rgb(h, s, v)
        out.append("#%02X%02X%02X" % (round(rr * 255), round(gg * 255), round(bb * 255)))
    return out


def arch_d(cx, base, r, top):
    sp = top + r
    return f"M{cx-r} {base}V{sp}A{r} {r} 0 0 1 {cx+r} {sp}V{base}Z"


def tube_d(cx, foot, r, sp):
    return f"M{cx-r} {foot}V{sp}A{r} {r} 0 0 1 {cx+r} {sp}V{foot}"


# The lit core's light per station (StationArtwork's LitCore): Your Station
# the filament; Discovery a paler, newer light; Loved a warmer, rosier one.
CORES = {
    "personal": ("#FFFBF0", "#FFD58E", "#FFC46A"),
    "discovery": ("#FFFFFF", "#FFE9B8", "#FFE08A"),
    "favorites": ("#FFF1EA", "#FFB58E", "#FF9A6A"),
}


def station_svg(size, covers=(), name="", eyebrow="", tone=None, kind="covers", radius=0):
    """covers: callables (from covers.py) drawing a cover in a 100 box; tone:
    the first cover's average colour; kind: "covers" or a CORES key."""
    p = f"s{next(_n)}"
    c = cut_for(size)
    cx = 150
    lit = kind in CORES
    ground, haze = (CABINET, CABINET_HAZE) if lit or tone is None else room(tone)
    win = arch_d(cx, c.base, c.rw, c.win_top)
    wx, wy, ww, wh = cx - c.rw, c.win_top, 2 * c.rw, c.base - c.win_top
    if lit:
        top_col, bottom_col, bloom = CORES[kind]
        rc = c.rc
        cap = f"M{cx-rc} {c.sp}A{rc} {rc} 0 0 1 {cx+rc} {c.sp}V{c.base-rc}A{rc} {rc} 0 0 1 {cx-rc} {c.base-rc}Z"
        content = f'''<defs><radialGradient id="{p}w" cx="150" cy="{(c.sp + c.base) / 2}" r="{c.rw * 1.7}" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#8A3A14"/><stop offset=".6" stop-color="#3A150B"/><stop offset="1" stop-color="#220C07"/></radialGradient>
<linearGradient id="{p}c" x1="0" y1="{c.sp - rc}" x2="0" y2="{c.base}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{top_col}"/><stop offset="1" stop-color="{bottom_col}"/></linearGradient>
<filter id="{p}cb" filterUnits="userSpaceOnUse" x="0" y="0" width="300" height="300"><feGaussianBlur stdDeviation="9"/></filter></defs>
<rect x="0" y="0" width="300" height="300" fill="url(#{p}w)"/>
<path d="{cap}" fill="{bloom}" filter="url(#{p}cb)" opacity=".75"/>
<path d="{cap}" fill="url(#{p}c)"/>'''
    else:
        parts = []
        if len(covers) >= 4 and c is not SMALL:
            gap = 3
            cw, ch = (ww - gap) / 2, (wh - gap) / 2
            # The mullions between the panes: the room, half dark.
            parts.append(f'<rect x="{wx}" y="{wy}" width="{ww}" height="{wh}" fill="#000" fill-opacity=".5"/>')
            for j, cover in enumerate(covers[:4]):
                x, y = wx + (j % 2) * (cw + gap), wy + (j // 2) * (ch + gap)
                s = max(cw, ch)
                parts.append(f'<clipPath id="{p}k{j}"><rect x="{x}" y="{y}" width="{cw}" height="{ch}"/></clipPath>'
                             f'<g clip-path="url(#{p}k{j})"><g transform="translate({x + cw/2 - s/2} {y + ch/2 - s/2}) scale({s/100})">{cover(p+"c"+str(j))}</g></g>')
        elif covers:
            s = wh
            parts.append(f'<g transform="translate({cx - s/2} {wy}) scale({s/100})">{covers[0](p+"c0")}</g>')
        content = "".join(parts)
    label = ""
    if c is NAMED and name:
        label = (f'<text x="150" y="266" text-anchor="middle" font-family="Inter Display, Inter, sans-serif" font-weight="650" font-size="23" fill="#fff" letter-spacing="-0.2">{name}</text>'
                 f'<text x="150" y="284" text-anchor="middle" font-family="Inter, sans-serif" font-weight="600" font-size="9.5" letter-spacing="1.5" fill="#fff" fill-opacity=".62">{eyebrow}</text>')
    hot = "" if c is SMALL else f'''<g filter="url(#{p}b2)" opacity=".45" fill="none" stroke-linecap="round" stroke-width="{c.t*0.4}">
  <path d="{tube_d(cx, c.leg, c.ro, c.sp)}" stroke="{OUTER_HOT}"/>
  <path d="{tube_d(cx, c.leg, c.ri, c.sp)}" stroke="{INNER_HOT}"/>
</g>'''
    return f'''<svg width="{size}" height="{size}" viewBox="0 0 300 300" xmlns="http://www.w3.org/2000/svg" style="display:block;border-radius:{radius}px">
<defs>
 <radialGradient id="{p}g" cx="150" cy="120" r="230" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{haze}"/><stop offset="1" stop-color="{ground}"/></radialGradient>
 <filter id="{p}b" filterUnits="userSpaceOnUse" x="0" y="0" width="300" height="300"><feGaussianBlur stdDeviation="7"/></filter>
 <filter id="{p}b2" filterUnits="userSpaceOnUse" x="0" y="0" width="300" height="300"><feGaussianBlur stdDeviation="2"/></filter>
 <clipPath id="{p}win"><path d="{win}"/></clipPath>
</defs>
<rect width="300" height="300" fill="url(#{p}g)"/>
<g filter="url(#{p}b)" opacity=".42" fill="none" stroke-linecap="round">
  <path d="{tube_d(cx, c.leg, c.ro, c.sp)}" stroke="{OUTER}" stroke-width="{c.t*2.2}"/>
  <path d="{tube_d(cx, c.leg, c.ri, c.sp)}" stroke="{INNER}" stroke-width="{c.t*2.2}"/>
</g>
<g clip-path="url(#{p}win)">{content}</g>
<path d="{win}" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="1"/>
<g fill="none" stroke-linecap="round" stroke-width="{c.t}">
  <path d="{tube_d(cx, c.leg, c.ro, c.sp)}" stroke="{OUTER}"/>
  <path d="{tube_d(cx, c.leg, c.ri, c.sp)}" stroke="{INNER}"/>
</g>
{hot}
{label}
</svg>'''


if __name__ == "__main__":
    from covers import VELVET, SHOE, NINETIES
    stations = [
        dict(covers=VELVET, name="Velvet Static", eyebrow="ARTIST STATION", tone="#6A2E63"),
        dict(covers=SHOE, name="Shoegaze", eyebrow="GENRE STATION", tone="#9C8FC0"),
        dict(covers=NINETIES, name="1990s", eyebrow="DECADE STATION", tone="#E0B53E"),
        dict(covers=VELVET[:1], name="Low Hum", eyebrow="SONG STATION", tone="#6A2E63"),
        dict(kind="personal", name="Your Station", eyebrow="FROM YOUR LISTENING"),
        dict(kind="discovery", name="Discovery", eyebrow="NEW TO YOU"),
        dict(kind="favorites", name="Loved", eyebrow="YOUR FAVORITES"),
    ]
    rows = []
    for size in (240, 150, 64, 34):
        cells = "".join(f'<div style="border-radius:{size*0.06}px;overflow:hidden">{station_svg(size, **s)}</div>' for s in stations)
        rows.append(f'<div style="display:flex;gap:16px;padding:12px;align-items:flex-start">{cells}</div>')
    out = sys.argv[1] if len(sys.argv) > 1 else "station-preview.html"
    open(out, "w").write('<html><body style="margin:0;background:#fff">' + "".join(rows) + "</body></html>")
    print("wrote", out)
