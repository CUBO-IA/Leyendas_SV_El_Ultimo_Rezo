"""Importa las fachadas del equipo (assets_generated/fachadas/, arte de fescobar85) al pueblo.

Cada imagen es una escena completa (cielo, luna, árboles, suelo). Por cada edificio:
  1. recorta el recuadro del edificio (BOXES, en píxeles de la imagen original);
  2. quita el cielo: relleno por inundación desde el borde de arriba sobre píxeles
     azul oscuro o morados (cielo y nubes);
  3. quita lo que quedó flotando (luna, estrellas, nubes sueltas): solo se queda lo que
     toca la base del recorte;
  4. lo escala al ANCHO del lote actual del edificio (game/assets/town/facades/{id}.png)
     multiplicado por HD, con la base en el mismo lugar.

Salida: game/assets/town/facades_hd/{id}.png. town.gd la dibuja a escala 1/HD, así que con
el zoom x3 de la cámara se ve a 1 píxel de imagen por píxel de pantalla (los letreros se leen).

    .venv\\Scripts\\python tools\\import_facades.py [--only pupuseria,iglesia] [--preview]
y después: Godot --headless --path game --import
"""
from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets_generated" / "fachadas"
LOWRES = ROOT / "game" / "assets" / "town" / "facades"
OUT = ROOT / "game" / "assets" / "town" / "facades_hd"
HD = 3  # resolución de la textura respecto al lote (cámara con zoom x3)
WORK_W = 700  # ancho de trabajo para el relleno (rápido en Python puro)

# Recuadro (x0, y0, x1, y1) del edificio en la imagen original de 1670x941 (caseta: 1448x1086).
BOXES: dict[str, tuple[int, int, int, int]] = {
    "cantina": (0, 60, 1672, 870),
    "casa_parroquial": (85, 60, 1645, 870),
    "casa_portillo": (0, 70, 1672, 885),
    "caseta_vigilancia": (275, 160, 1160, 880),
    "cementerio": (0, 70, 1672, 860),
    "iglesia": (130, 0, 1590, 875),
    "kiosco": (300, 40, 1370, 870),
    "mercado": (20, 40, 1660, 875),
    "puesto_policial": (30, 40, 1620, 870),
    "pupuseria": (20, 30, 1640, 880),
    "terminal": (0, 30, 1672, 885),
}


# Edificios abiertos (se ve el fondo entre columnas): también se quita el fondo oscuro
# (árboles de noche) que entra por los costados, solo en esta franja de altura del recorte
# (fracciones 0..1): debajo del techo y por encima del piso.
OPEN_SIDES: dict[str, tuple[float, float]] = {"kiosco": (0.40, 0.86)}


def is_sky(p: tuple[int, int, int]) -> bool:
    """Cielo nocturno y nubes: oscuro o morado, con el azul dominando."""
    r, g, b = p[:3]
    return b > r + 18 and b > g + 12 and (r + g + b) / 3 < 150


def is_dark(p: tuple[int, int, int]) -> bool:
    """Fondo nocturno (árboles, casas lejanas en sombra): muy oscuro o frío."""
    r, g, b = p[:3]
    return is_sky(p) or (r + g + b) / 3 < 45 or (b >= r and (r + g + b) / 3 < 80)


def cut_out(img: Image.Image, open_sides: tuple[float, float] = (0.0, 0.0)) -> Image.Image:
    """Devuelve RGBA sin cielo ni restos flotantes (a la resolución de img)."""
    w, h = img.size
    px = img.load()
    side_from, side_to = int(h * open_sides[0]), int(h * open_sides[1])

    def is_bg(p: tuple[int, int, int], y: int) -> bool:
        # Con open_sides, en la franja side_from..side_to el fondo oscuro también es fondo.
        return is_sky(p) or (side_from <= y < side_to and is_dark(p))

    removed = bytearray(w * h)
    q: deque[int] = deque()
    seeds = [(x, 0) for x in range(w)] + [(x, y) for y in range(side_from, side_to) for x in (0, w - 1)]
    for x, y in seeds:  # el cielo entra por arriba (y el fondo por los lados si es abierto)
        i = y * w + x
        if not removed[i] and is_bg(px[x, y], y):
            removed[i] = 1
            q.append(i)
    while q:
        i = q.popleft()
        x, y = i % w, i // w
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not removed[j] and is_bg(px[nx, ny], ny):
                    removed[j] = 1
                    q.append(j)
    # Lo que no toca la base (luna, estrellas, nubes sueltas) también se va.
    keep = bytearray(w * h)
    q = deque(i for i in range((h - 1) * w, h * w) if not removed[i])
    for i in q:
        keep[i] = 1
    while q:
        i = q.popleft()
        x, y = i % w, i // w
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not keep[j] and not removed[j]:
                    keep[j] = 1
                    q.append(j)
    alpha = Image.frombytes("L", (w, h), bytes(255 if k else 0 for k in keep))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    return out


def import_one(fid: str) -> Path:
    box = BOXES[fid]
    src = Image.open(SRC / f"{fid}.png").convert("RGB").crop(box)
    work = src.resize((WORK_W, round(src.height * WORK_W / src.width)), Image.LANCZOS)
    cut = cut_out(work, OPEN_SIDES.get(fid, (0.0, 0.0)))
    bbox = cut.getchannel("A").getbbox()  # recorta el aire que sobra arriba y a los lados
    cut = cut.crop(bbox)
    lot_w = Image.open(LOWRES / f"{fid}.png").width
    tw = lot_w * HD
    th = round(cut.height * tw / cut.width)
    rgb = cut.convert("RGB").resize((tw, th), Image.LANCZOS)
    a = cut.getchannel("A").resize((tw, th), Image.BOX).point(lambda v: 255 if v >= 128 else 0)
    rgb.putalpha(a)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{fid}.png"
    rgb.save(path, optimize=True)
    return path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", action="store_true", help="hoja de muestra sobre pasto en tools/out/")
    args = ap.parse_args()
    ids = [i for i in BOXES if not args.only or i in args.only.split(",")]
    made = []
    for fid in ids:
        p = import_one(fid)
        im = Image.open(p)
        lot = Image.open(LOWRES / f"{fid}.png").size
        print(f"{fid:18} {im.size[0]}x{im.size[1]} (lote {lot[0]}x{lot[1]} -> {im.size[0] // HD}x{im.size[1] // HD})")
        made.append(im)
    if args.preview:
        cols = 3
        cw = max(m.width for m in made) + 20
        ch = max(m.height for m in made) + 20
        sheet = Image.new("RGBA", (cw * cols, ch * ((len(made) + cols - 1) // cols)), (40, 70, 45, 255))
        for i, m in enumerate(made):
            sheet.alpha_composite(m, ((i % cols) * cw + 10, (i // cols) * ch + 10))
        out = ROOT / "tools" / "out"
        out.mkdir(exist_ok=True)
        sheet.save(out / "facades_preview.png")
        print("muestra:", out / "facades_preview.png")


if __name__ == "__main__":
    main()
