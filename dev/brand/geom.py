"""The Arch mark's geometry: the one source for the mark's SVGs, the app icon
(icon.py), and the app's ArchMark (Jukebox/Components/ArchMark.swift, whose
ArchCut carries these same numbers — change both together).

In a 32-unit box: everything concentric about the spring point (16, SPRING).
Two tubes of light (stroke S, round caps) and a core (a capsule), equal gaps G.

Two cuts, as SF Symbols have optical sizes:
  REGULAR  above 20 pt: width 24, height 28, baseline y=30.
  HEAVY    20 pt and below: heavier tubes, a wider core, tighter gaps, and a
           little more of the box (width 26), so the three parts stay three
           at 16 and 11 pt instead of running together (Tonearm's rule,
           taken into Arch by the judge, 8 November 2026).
"""
import os
import sys
from collections import namedtuple

CX = 16.0


class Cut(namedtuple("Cut", "stroke gap half spring base")):
    """stroke: tube stroke; gap: between tube, tube and core; half: half the
    mark's width, to a tube's outer edge; spring: where the arcs spring from;
    base: the baseline the caps and the core reach."""

    @property
    def r1(self):          # outer tube centre-line radius
        return self.half - self.stroke / 2

    @property
    def r2(self):          # inner tube centre-line radius
        return self.r1 - self.stroke - self.gap

    @property
    def rc(self):          # the core's radius (half its width)
        return self.r2 - self.stroke / 2 - self.gap

    @property
    def leg(self):         # where a tube's centre line ends: its cap reaches the base
        return self.base - self.stroke / 2

    def tube(self, r):
        return (f"M{CX-r:.2f} {self.leg:.2f}V{self.spring:.2f}"
                f"A{r:.2f} {r:.2f} 0 0 1 {CX+r:.2f} {self.spring:.2f}V{self.leg:.2f}")

    def core(self):
        rc, x0, x1 = self.rc, CX - self.rc, CX + self.rc
        return (f"M{x0:.2f} {self.spring:.2f}A{rc:.2f} {rc:.2f} 0 0 1 {x1:.2f} {self.spring:.2f}"
                f"V{self.base-rc:.2f}A{rc:.2f} {rc:.2f} 0 0 1 {x0:.2f} {self.base-rc:.2f}Z")

    def paths(self):
        return self.tube(self.r1), self.tube(self.r2), self.core()


REGULAR = Cut(stroke=2.6, gap=2.2, half=12.0, spring=14.0, base=30.0)   # core 4.8 wide
HEAVY = Cut(stroke=3.2, gap=1.9, half=13.0, spring=14.5, base=30.5)     # core 5.6 wide

# The regular cut's numbers, as the icon and the board use them.
S, G = REGULAR.stroke, REGULAR.gap
SPRING, BASE = REGULAR.spring, REGULAR.base
R1, R2, RC, LEG = REGULAR.r1, REGULAR.r2, REGULAR.rc, REGULAR.leg
OUTER, INNER, CORE = REGULAR.paths()


def mark_svg(size=None, colors=("currentColor",) * 3, transform="", extra_attrs="", cut=REGULAR):
    o, i, c = colors
    outer, inner, core = cut.paths()
    wh = f'width="{size}" height="{size}" ' if size else ''
    return (f'<svg {wh}viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg" {extra_attrs}>'
            f'<g fill="none" stroke-linecap="round" stroke-width="{cut.stroke}"{transform}>'
            f'<path d="{outer}" stroke="{o}"/><path d="{inner}" stroke="{i}"/></g>'
            f'<path d="{core}" fill="{c}"/></svg>')


# The accent pair (Theme.swift, AccentColor): Copper in light mode, Glow in dark.
COPPER, GLOW = "#A84A17", "#FFB54D"
# The mark lit: the tubes take the accent; the core is the light — amber on
# light grounds, filament on dark.
LIGHT = (COPPER, COPPER, "#F7A136")
DARK = (GLOW, GLOW, "#FFF1D6")

def write_svgs(folder):
    """docs/brand's mark-*.svg: lit by day, lit by night, the template, and
    the heavy cut's template for 20 pt and below."""
    note = ("<!-- Jukebox, the Arch mark: two tubes of light (round caps) and a core, concentric "
            "about (16, {spring}) in a 32-unit box ({cut} cut). {what} dev/brand/geom.py draws it. -->\n")
    for name, cols, cut, cut_name, what in (
            ("mark.svg", LIGHT, REGULAR, "regular", "Lit on light: the tubes Copper, the core amber."),
            ("mark-dark.svg", DARK, REGULAR, "regular", "Lit on dark: the tubes Glow, the core filament."),
            ("mark-template.svg", ("#000000",) * 3, REGULAR, "regular", "Template: one colour."),
            ("mark-small-template.svg", ("#000000",) * 3, HEAVY, "heavy, 20 pt and below", "Template: one colour.")):
        with open(os.path.join(folder, name), "w") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            f.write(note.format(spring=cut.spring, cut=cut_name, what=what))
            f.write(mark_svg(colors=cols, cut=cut) + "\n")


if __name__ == "__main__":
    # python3 geom.py svgs docs/brand   writes the mark's SVGs there.
    if sys.argv[1:2] == ["svgs"]:
        write_svgs(sys.argv[2])
        sys.exit()
    for name, cut in (("regular", REGULAR), ("heavy", HEAVY)):
        print(name, f"r1={cut.r1:.2f} r2={cut.r2:.2f} rc={cut.rc:.2f} leg={cut.leg:.2f}")
        for p in cut.paths():
            print(" ", p)
