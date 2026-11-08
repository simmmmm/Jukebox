"""Jukebox's app icon in the Arch identity: the mark lit on Cabinet, as the
tubes of a jukebox's arch light the room they stand in (docs/BRAND.md).
Four layers, as Icon Composer would have them: the ground, the outer tube,
the inner tube, the core; each with its halo, and the hot line inside each
tube. The geometry is geom.py's regular cut, 22.4 units to the 32-unit box,
a little below the middle (the room's floor glow under it).

Three appearances (iOS 18+): default (Cabinet), dark (a darker room for the
dark Home Screen), tinted (a grey ramp on black, which the system tints).
dev/make-icon.py renders them into the asset catalog.
"""
import sys
from geom import *

def icon_svg(size=1024, variant="default", ident="i"):
    """variant: default (cabinet ground), dark, tinted (grey ramp on black)."""
    k = 22.4
    tx, ty = 512 - 16 * k, 524 - 16 * k
    T = f'transform="translate({tx:.1f} {ty:.1f}) scale({k})"'
    sw = S * k
    if variant == "tinted":
        ground = ('#0A0A0A', '#141414', '#050505')
        cols = dict(outer=('#7A7A7A', '#A0A0A0', '#C4C4C4'), inner=('#B8B8B8', '#D8D8D8', '#F2F2F2'),
                    core=('#FFFFFF', '#F4F4F4'), glow='#FFFFFF', glowop=0.10)
    else:
        ground = ('#46190F', '#260C08', '#130605') if variant == "default" else ('#1E0C09', '#120706', '#080303')
        cols = dict(outer=('#D45A22', '#F07E36', '#FFB57A'), inner=('#F49A30', '#FFB44C', '#FFE2AA'),
                    core=('#FFFBF0', '#FFD58E'), glow='#FF8A2A', glowop=0.30)
    o, i = cols['outer'], cols['inner']
    p = ident
    floor_y = ty + BASE * k
    return f'''<svg width="{size}" height="{size}" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs>
  <radialGradient id="{p}g" cx="512" cy="470" r="760" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{ground[0]}"/><stop offset="0.55" stop-color="{ground[1]}"/><stop offset="1" stop-color="{ground[2]}"/>
  </radialGradient>
  <linearGradient id="{p}o" x1="0" y1="2" x2="0" y2="30" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{o[1]}"/><stop offset="1" stop-color="{o[0]}"/></linearGradient>
  <linearGradient id="{p}i" x1="0" y1="8" x2="0" y2="30" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{i[1]}"/><stop offset="1" stop-color="{i[0]}"/></linearGradient>
  <linearGradient id="{p}c" x1="0" y1="11.6" x2="0" y2="30" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{cols['core'][0]}"/><stop offset="1" stop-color="{cols['core'][1]}"/></linearGradient>
  <filter id="{p}b60" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="60"/></filter>
  <filter id="{p}b26" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="26"/></filter>
  <filter id="{p}b9" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="9"/></filter>
  <filter id="{p}b2" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="2.2"/></filter>
</defs>
<rect width="1024" height="1024" fill="url(#{p}g)"/>
<!-- the room the arch lights -->
<g filter="url(#{p}b60)" opacity="{cols['glowop']}"><path {T} d="{OUTER}" stroke="{cols['glow']}" stroke-width="{S*3}" fill="none"/></g>
<g filter="url(#{p}b26)" opacity="{cols['glowop']*1.4:.2f}"><ellipse cx="512" cy="{floor_y+6}" rx="300" ry="26" fill="{cols['glow']}"/></g>
<g filter="url(#{p}b60)" opacity="{cols['glowop']*0.9:.2f}"><path {T} d="M{CX-R2} {BASE}V{SPRING}A{R2} {R2} 0 0 1 {CX+R2} {SPRING}V{BASE}Z" fill="{cols['inner'][1]}"/></g>
<!-- halos -->
<g filter="url(#{p}b26)" opacity="0.46" fill="none" stroke-linecap="round">
  <path {T} d="{OUTER}" stroke="{o[1]}" stroke-width="{S*1.6}"/>
  <path {T} d="{INNER}" stroke="{i[1]}" stroke-width="{S*1.6}"/>
  <path {T} d="{CORE}" fill="{cols['core'][1]}" stroke="none"/>
</g>
<g filter="url(#{p}b9)" opacity="0.5" fill="none" stroke-linecap="round">
  <path {T} d="{OUTER}" stroke="{o[1]}" stroke-width="{S}"/>
  <path {T} d="{INNER}" stroke="{i[1]}" stroke-width="{S}"/>
  <path {T} d="{CORE}" fill="{cols['core'][1]}" stroke="none"/>
</g>
<!-- tubes -->
<g fill="none" stroke-linecap="round">
  <path {T} d="{OUTER}" stroke="url(#{p}o)" stroke-width="{S}"/>
  <path {T} d="{INNER}" stroke="url(#{p}i)" stroke-width="{S}"/>
</g>
<g filter="url(#{p}b26)" opacity="0.5"><path {T} d="{CORE}" fill="{cols['core'][1]}"/></g>
<path {T} d="{CORE}" fill="url(#{p}c)"/>
<!-- the hot line inside each tube -->
<g filter="url(#{p}b2)" fill="none" stroke-linecap="round" opacity="0.38">
  <path {T} d="{OUTER}" stroke="{o[2]}" stroke-width="{S*0.34}"/>
  <path {T} d="{INNER}" stroke="{i[2]}" stroke-width="{S*0.34}"/>
</g>
</svg>'''

def icon_html(size=1024, variant="default"):
    return f'<html><body style="margin:0;background:#000">{icon_svg(size, variant)}</body></html>'


if __name__ == "__main__":
    # python3 icon.py dark > icon-dark.html, to look at one in a browser.
    v = sys.argv[1] if len(sys.argv) > 1 else "default"
    sys.stdout.write(icon_html(1024, v))
