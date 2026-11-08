"""Made-up album covers, each an SVG fragment in a 100x100 box. ids must be unique per use: pass p."""
def c_velvet1(p):  # Velvet Static - "Low Hum": plum to rose gradient, thin white ring
    return f'''<defs><linearGradient id="{p}a" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2B1650"/><stop offset="1" stop-color="#C2477A"/></linearGradient></defs>
<rect width="100" height="100" fill="url(#{p}a)"/><circle cx="58" cy="44" r="22" fill="none" stroke="#FCE7F0" stroke-width="1.6"/><rect x="10" y="84" width="34" height="2.2" fill="#FCE7F0" opacity=".8"/>'''
def c_velvet2(p):  # "Tape Saturation": black with red scan stripes
    bars=''.join(f'<rect x="0" y="{18+i*9}" width="100" height="{2+ (i%3)}" fill="#E0322E" opacity="{0.35+0.12*(i%4)}"/>' for i in range(8))
    return f'<rect width="100" height="100" fill="#121214"/>{bars}<rect x="12" y="12" width="20" height="20" fill="#F4EFE6"/>'
def c_velvet3(p):  # "Glasshouse": teal with a pale diagonal band
    return '<rect width="100" height="100" fill="#1F6F78"/><path d="M-10 70L70 -10H100L0 100Z" fill="#9ED9CF" opacity=".85"/><circle cx="76" cy="76" r="9" fill="#F7D24A"/>'
def c_velvet4(p):  # "Night Bus": cream with a black block and a small red dot
    return '<rect width="100" height="100" fill="#EDE5D6"/><rect x="18" y="30" width="64" height="44" fill="#16161A"/><circle cx="70" cy="40" r="4" fill="#E0322E"/>'

def c_shoe1(p):  # hazy pink/blue blur
    return f'''<defs><radialGradient id="{p}a" cx=".3" cy=".35" r=".8"><stop offset="0" stop-color="#F7C6DA"/><stop offset=".55" stop-color="#9B8FD6"/><stop offset="1" stop-color="#3A3F7A"/></radialGradient></defs><rect width="100" height="100" fill="url(#{p}a)"/>'''
def c_shoe2(p):  # wall of noise: washed green, blurred sun
    return f'''<defs><radialGradient id="{p}a" cx=".65" cy=".4" r=".5"><stop offset="0" stop-color="#FFF4C9"/><stop offset=".4" stop-color="#C9D9A8"/><stop offset="1" stop-color="#4E6B5C"/></radialGradient></defs><rect width="100" height="100" fill="url(#{p}a)"/><rect y="70" width="100" height="30" fill="#2F4A43" opacity=".55"/>'''
def c_shoe3(p):  # deep blue with soft vertical streaks
    st=''.join(f'<rect x="{8+i*13}" y="0" width="5" height="100" fill="#B9C8FF" opacity="{0.10+0.06*(i%3)}"/>' for i in range(7))
    return f'<rect width="100" height="100" fill="#1B2350"/>{st}<circle cx="50" cy="56" r="16" fill="#E9A6C9" opacity=".75"/>'
def c_shoe4(p):  # rose to amber haze
    return f'''<defs><linearGradient id="{p}a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#E8889C"/><stop offset="1" stop-color="#F3C98B"/></linearGradient></defs><rect width="100" height="100" fill="url(#{p}a)"/><ellipse cx="50" cy="80" rx="60" ry="14" fill="#FFF3E2" opacity=".5"/>'''

def c_90s1(p):  # yellow with black hand-drawn-ish circle
    return '<rect width="100" height="100" fill="#F2C84B"/><circle cx="50" cy="50" r="26" fill="none" stroke="#1A1A1A" stroke-width="7"/><rect x="12" y="12" width="14" height="4" fill="#1A1A1A"/>'
def c_90s2(p):  # sky photo-ish gradient with white cloud bands
    return f'''<defs><linearGradient id="{p}a" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2E7FD1"/><stop offset="1" stop-color="#A9D6F5"/></linearGradient></defs><rect width="100" height="100" fill="url(#{p}a)"/><ellipse cx="30" cy="66" rx="30" ry="8" fill="#fff" opacity=".7"/><ellipse cx="72" cy="78" rx="34" ry="7" fill="#fff" opacity=".6"/>'''
def c_90s3(p):  # black/white checker strip
    sq=''.join(f'<rect x="{i*12.5}" y="{38 + (i%2)*12.5}" width="12.5" height="12.5" fill="#fff"/>' for i in range(8))
    return f'<rect width="100" height="100" fill="#111"/>{sq}<rect x="0" y="38" width="100" height="25" fill="none" stroke="#fff" stroke-width=".8"/><circle cx="80" cy="18" r="5" fill="#E8463A"/>'
def c_90s4(p):  # orange disc on olive
    return '<rect width="100" height="100" fill="#5C6230"/><circle cx="50" cy="46" r="30" fill="#EF7B2B"/><rect x="0" y="82" width="100" height="18" fill="#2E3018"/>'

VELVET=[c_velvet1,c_velvet2,c_velvet3,c_velvet4]
SHOE=[c_shoe1,c_shoe2,c_shoe3,c_shoe4]
NINETIES=[c_90s1,c_90s2,c_90s3,c_90s4]
