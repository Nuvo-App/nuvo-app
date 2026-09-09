#!/usr/bin/env python3
"""
Render the Nuvo app icon from the Icon Composer source project into the three
PNG appearances flutter_launcher_icons expands into AppIcon.appiconset.

Source: "Scam Call v3/nuvo/App icons/working v2/Untitled.icon"
  icon.json: automatic-gradient fill extended-srgb(0.0, 0.53333, 1.0)
             one layer "main.png" (actually an SVG "M" mark).

Xcode 26's actool does not compile a lone `.icon` stack inside the Flutter
build, so we flatten it here rather than ship a broken build.

Deps:  pip install --break-system-packages cairosvg pillow
Usage: python3 tools/render_app_icon.py \
         "/path/to/App icons/working v2/Untitled.icon"
"""
import io
import sys
from pathlib import Path

import cairosvg
from PIL import Image

CANVAS = 1024
BASE = (0, 136, 255)  # extended-srgb(0.0, 0.53333, 1.0)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main(src_dir: str) -> None:
    src = Path(src_dir)
    svg = src / "Assets" / "main.png"  # SVG despite the name
    out = Path(__file__).resolve().parent.parent / "assets" / "branding"

    top, bot = lerp(BASE, (255, 255, 255), 0.13), lerp(BASE, (0, 0, 0), 0.15)
    row = Image.new("RGB", (1, CANVAS))
    for y in range(CANVAS):
        row.putpixel((0, y), lerp(top, bot, y / (CANVAS - 1)))
    bg = row.resize((CANVAS, CANVAS)).convert("RGBA")

    svg_w, svg_h = 1189, 1138
    tw = round(CANVAS * 0.60)
    th = round(tw * svg_h / svg_w)
    png = cairosvg.svg2png(url=str(svg), output_width=tw, output_height=th)
    layer = Image.open(io.BytesIO(png)).convert("RGBA")
    x, y = (CANVAS - tw) // 2, (CANVAS - th) // 2 - 14

    def place(canvas):
        c = canvas.copy()
        c.alpha_composite(layer, (x, y))
        return c

    place(bg).convert("RGB").save(out / "nuvo_app_icon.png")
    place(Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))).save(
        out / "nuvo_app_icon_dark.png"
    )
    g = layer.convert("LA").convert("RGBA")
    tint = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    tint.alpha_composite(g, (x, y))
    tint.save(out / "nuvo_app_icon_tinted.png")
    print(f"wrote 3 files to {out}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
