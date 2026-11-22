#!/usr/bin/env python3
"""Generates the DianaVoiceStudio app icon (1024x1024, no alpha): black background,
powder-pink gradient monogram "D" and a silver waveform."""
import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# Background: deep black radial vignette.
bg = Image.new("RGB", (S, S), (8, 8, 10))
px = bg.load()
for y in range(S):
    for x in range(S):
        d = math.hypot(x - S * 0.5, y - S * 0.42) / (S * 0.75)
        c = lerp((34, 30, 36), (6, 6, 8), min(1, d))
        px[x, y] = c

# Pink gradient layer (masked by the monogram).
pink = Image.new("RGB", (S, S))
pp = pink.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        pp[x, y] = lerp((248, 206, 218), (214, 118, 148), t)

mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 640)
bbox = md.textbbox((0, 0), "D", font=font)
w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
md.text(((S - w) / 2 - bbox[0], (S - h) / 2 - bbox[1] - 70), "D", font=font, fill=255)

# Soft pink glow.
glow = mask.filter(ImageFilter.GaussianBlur(40))
bg = Image.composite(Image.blend(bg, pink, 0.35), bg, glow)
bg = Image.composite(pink, bg, mask)

# Silver waveform under the monogram.
d = ImageDraw.Draw(bg)
bars = 23
base_y = 820
for i in range(bars):
    t = i / (bars - 1)
    amp = (0.25 + 0.75 * abs(math.sin(t * math.pi * 3.1 + 0.4))) * math.sin(t * math.pi)
    hgt = 18 + amp * 110
    x = 212 + i * 26
    shade = lerp((240, 240, 244), (150, 152, 160), abs(t - 0.5) * 2)
    d.rounded_rectangle([x, base_y - hgt / 2, x + 14, base_y + hgt / 2], radius=7, fill=shade)

bg.save(out, "PNG")
print("wrote", out)
