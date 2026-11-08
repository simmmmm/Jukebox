"""The contrast numbers in docs/BRAND.md, as WCAG 2 computes them.

    python3 dev/brand/contrast.py
"""


def luminance(hex_colour):
    r, g, b = (int(hex_colour.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def ratio(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


PAIRS = [
    ("Copper", "#A84A17", "white", "#FFFFFF"),
    ("Copper", "#A84A17", "grouped grey", "#F2F2F7"),
    ("Glow", "#FFB54D", "black", "#000000"),
    ("Glow", "#FFB54D", "dark grouped grey", "#1C1C1E"),
    ("Glow", "#FFB54D", "Cabinet", "#1E0A07"),
    ("Ink", "#2A1505", "Glow", "#FFB54D"),
    ("white", "#FFFFFF", "Cabinet", "#1E0A07"),
    ("mark core by day", "#F7A136", "white", "#FFFFFF"),
]

if __name__ == "__main__":
    for name, a, on, b in PAIRS:
        print(f"{name} {a} on {on} {b}: {ratio(a, b):.2f}:1")
