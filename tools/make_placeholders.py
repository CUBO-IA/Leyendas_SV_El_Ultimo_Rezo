"""Genera los retratos placeholder: silueta pixelada de color con el nombre del personaje.

  .venv\\Scripts\\python tools\\make_placeholders.py

Salida: game/assets/placeholders/{id}.png (512x512) para los 10 testigos y los 6
sospechosos, más _unknown.png. Godot los usa cuando no hay retrato real en
assets_generated/portraits/.
"""
from __future__ import annotations

import colorsys
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "placeholders"
SIZE, GRID = 512, 64  # se dibuja en 64x64 y se escala x8 para el aspecto pixel art
FONT = Path("C:/Windows/Fonts/arialbd.ttf")


def color_for(cid: str, suspect: bool) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    h = int(hashlib.md5(cid.encode()).hexdigest()[:4], 16) / 0xFFFF
    sat, val = (0.55, 0.75) if not suspect else (0.35, 0.55)
    fg = colorsys.hsv_to_rgb(h, sat, val)
    bg = colorsys.hsv_to_rgb(h, 0.45, 0.16)
    return tuple(int(c * 255) for c in fg), tuple(int(c * 255) for c in bg)


def silhouette(fg, bg, suspect: bool) -> Image.Image:
    img = Image.new("RGB", (GRID, GRID), bg)
    d = ImageDraw.Draw(img)
    # viñeta: bordes más oscuros
    for i in range(4):
        d.rectangle([i, i, GRID - 1 - i, GRID - 1 - i],
                    outline=tuple(max(0, c - 12 * (4 - i)) for c in bg))
    if suspect:  # figura encapuchada, sin cara
        d.polygon([(32, 10), (18, 30), (14, 56), (50, 56), (46, 30)], fill=fg)
        d.ellipse([24, 18, 40, 34], fill=bg)
        d.rectangle([29, 25, 30, 26], fill=(230, 220, 160))
        d.rectangle([34, 25, 35, 26], fill=(230, 220, 160))
    else:  # cabeza y hombros
        d.ellipse([22, 12, 42, 34], fill=fg)
        d.rectangle([29, 33, 35, 38], fill=fg)
        d.ellipse([12, 36, 52, 70], fill=fg)
    return img.resize((SIZE, SIZE), Image.NEAREST)


def draw_name(img: Image.Image, name: str, subtitle: str) -> None:
    d = ImageDraw.Draw(img)
    d.rectangle([0, SIZE - 96, SIZE, SIZE], fill=(10, 8, 16))
    font = ImageFont.truetype(str(FONT), 38) if FONT.exists() else ImageFont.load_default()
    small = ImageFont.truetype(str(FONT), 22) if FONT.exists() else ImageFont.load_default()
    for text, f, y in ((name, font, SIZE - 82), (subtitle, small, SIZE - 36)):
        w = d.textlength(text, font=f)
        d.text(((SIZE - w) / 2, y), text, font=f, fill=(240, 232, 210))


def main() -> None:
    chars = json.loads((ROOT / "content/public/characters.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    people = [(w["id"], w["name"], w["role"], False) for w in chars["witnesses"]]
    people += [(s["id"], s["name"], s["epithet"], True) for s in chars["suspects"]]
    people.append(("_unknown", "???", "sin retrato", False))
    for cid, name, sub, suspect in people:
        fg, bg = color_for(cid, suspect)
        img = silhouette(fg, bg, suspect)
        draw_name(img, name, sub)
        img.save(OUT / f"{cid}.png")
    print(f"{len(people)} placeholders en {OUT}")


if __name__ == "__main__":
    main()
