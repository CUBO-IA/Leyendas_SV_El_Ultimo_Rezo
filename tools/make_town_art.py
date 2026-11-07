"""Arte placeholder del pueblo (pixel art, 16 px por baldosa, paleta nocturna).

  .venv\\Scripts\\python tools\\make_town_art.py

Salida en game/assets/town/:
  tiles.png            atlas de baldosas (ver TILES: el orden es el índice del atlas)
  facades/{id}.png     fachada de cada lugar de world.json (más kiosco)
  props/*.png          farol, marcador de objeto
  chars/{id}.png       hoja 16x24: 4 direcciones (abajo, arriba, izquierda, derecha) x 3 cuadros
Reemplazar estos PNG por arte final no exige tocar código (mismo tamaño de cuadro).
"""
from __future__ import annotations

import colorsys
import hashlib
import json
import sys
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "town"
T = 16

# ---------- paleta ----------
GRASS = [(34, 52, 40), (30, 47, 37), (38, 57, 43)]
COBBLE = [(86, 82, 92), (74, 70, 80), (98, 94, 104)]
PLAZA = [(112, 104, 96), (100, 92, 86), (124, 116, 106)]
DIRT = [(82, 64, 48), (72, 56, 42), (92, 72, 54)]
WATER = [(30, 54, 86), (36, 64, 100), (48, 84, 124)]
OUTLINE = (16, 12, 20)
GLOW = (255, 196, 92)
MARIGOLD = (232, 138, 44)
PURPLE = (123, 79, 168)

TILES = ["grass", "grass2", "grass_flowers", "cobble", "cobble2", "plaza", "plaza2",
         "dirt", "water", "water2", "hedge"]


def noise_tile(base: list[tuple], seed: int, specks: int = 18) -> Image.Image:
    rnd = random.Random(seed)
    img = Image.new("RGB", (T, T), base[0])
    px = img.load()
    for _ in range(specks):
        x, y = rnd.randrange(T), rnd.randrange(T)
        px[x, y] = rnd.choice(base[1:])
    return img


def stones(base: list[tuple], seed: int, size: int) -> Image.Image:
    img = Image.new("RGB", (T, T), base[1])
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)
    for y in range(0, T, size):
        off = (y // size % 2) * (size // 2)
        for x in range(-size, T, size):
            c = rnd.choice([base[0], base[2], base[0]])
            d.rectangle([x + off + 1, y + 1, x + off + size - 1, y + size - 1], fill=c)
    return img


def make_tiles() -> None:
    tiles = {
        "grass": noise_tile(GRASS, 1),
        "grass2": noise_tile(GRASS, 2, 26),
        "cobble": stones(COBBLE, 3, 4),
        "cobble2": stones(COBBLE, 4, 4),
        "plaza": stones(PLAZA, 5, 8),
        "plaza2": stones(PLAZA, 6, 8),
        "dirt": noise_tile(DIRT, 7, 22),
        "water": noise_tile(WATER, 8, 10),
        "water2": noise_tile(WATER, 9, 14),
    }
    fl = noise_tile(GRASS, 10)
    d = ImageDraw.Draw(fl)
    for x, y in [(3, 4), (10, 2), (6, 10), (12, 11), (2, 13)]:
        d.rectangle([x, y, x + 1, y + 1], fill=MARIGOLD)
        d.point((x, y + 2), fill=(40, 90, 40))
    tiles["grass_flowers"] = fl
    hedge = Image.new("RGB", (T, T), (22, 40, 28))
    d = ImageDraw.Draw(hedge)
    for x in range(0, T, 4):
        d.ellipse([x - 1, 0, x + 5, 7], fill=(30, 54, 36))
        d.ellipse([x + 1, 6, x + 7, 14], fill=(26, 46, 32))
    tiles["hedge"] = hedge
    atlas = Image.new("RGB", (T * len(TILES), T))
    for i, name in enumerate(TILES):
        atlas.paste(tiles[name], (i * T, 0))
    atlas.save(OUT / "tiles.png")


# ---------- fachadas ----------

def window(d: ImageDraw.ImageDraw, x: int, y: int, lit: bool, w: int = 6, h: int = 7) -> None:
    d.rectangle([x, y, x + w, y + h], fill=OUTLINE)
    d.rectangle([x + 1, y + 1, x + w - 1, y + h - 1], fill=GLOW if lit else (40, 44, 70))
    d.line([x + w // 2, y + 1, x + w // 2, y + h - 1], fill=OUTLINE)


def door(d: ImageDraw.ImageDraw, cx: int, bottom: int, w: int = 8, h: int = 12,
         color=(70, 44, 30), arch: bool = False) -> None:
    x0, y0 = cx - w // 2, bottom - h
    if arch:
        d.ellipse([x0, y0 - w // 2, x0 + w, y0 + w // 2], fill=OUTLINE)
        d.ellipse([x0 + 1, y0 - w // 2 + 1, x0 + w - 1, y0 + w // 2 - 1], fill=color)
    d.rectangle([x0, y0, x0 + w, bottom], fill=OUTLINE)
    d.rectangle([x0 + 1, y0 + 1, x0 + w - 1, bottom], fill=color)
    d.point((x0 + w - 2, y0 + h // 2), fill=GLOW)


def house(w: int, h: int, wall, roof, roof_h: int = 18, lit=(True, False),
          sign: tuple | None = None, door_color=(70, 44, 30)) -> Image.Image:
    W, H = w * T, h * T
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # muro
    d.rectangle([0, roof_h - 2, W - 1, H - 1], fill=OUTLINE)
    d.rectangle([1, roof_h - 1, W - 2, H - 2], fill=wall)
    for y in range(roof_h + 3, H - 2, 6):  # textura de adobe
        d.line([2, y, W - 3, y], fill=tuple(max(0, c - 10) for c in wall))
    # techo de teja
    d.polygon([(-2, roof_h), (6, 0), (W - 7, 0), (W + 1, roof_h)], fill=OUTLINE)
    d.polygon([(0, roof_h - 1), (7, 1), (W - 8, 1), (W - 1, roof_h - 1)], fill=roof)
    for x in range(4, W - 4, 4):
        d.line([x, 2, x - 2, roof_h - 2], fill=tuple(max(0, c - 25) for c in roof))
    # ventanas y puerta
    door(d, W // 2, H - 2, color=door_color)
    wy = roof_h + 6
    window(d, 6, wy, lit[0])
    window(d, W - 13, wy, lit[1])
    if sign:
        text_color, board = sign
        d.rectangle([W // 2 - 14, roof_h + 1, W // 2 + 14, roof_h + 6], fill=OUTLINE)
        d.rectangle([W // 2 - 13, roof_h + 2, W // 2 + 13, roof_h + 5], fill=board)
        for x in range(W // 2 - 11, W // 2 + 11, 3):
            d.point((x, roof_h + 3), fill=text_color)
    return img


def church() -> Image.Image:
    w, h = 10, 11
    W, H = w * T, h * T
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    wall, shade = (196, 186, 168), (164, 154, 138)
    # nave
    d.rectangle([4, 70, W - 5, H - 1], fill=OUTLINE)
    d.rectangle([5, 71, W - 6, H - 2], fill=wall)
    d.polygon([(2, 72), (W // 2, 46), (W - 3, 72)], fill=OUTLINE)
    d.polygon([(6, 71), (W // 2, 49), (W - 7, 71)], fill=(150, 70, 52))
    # campanario (torre central)
    tx0, tx1 = W // 2 - 16, W // 2 + 15
    d.rectangle([tx0, 12, tx1, 74], fill=OUTLINE)
    d.rectangle([tx0 + 1, 13, tx1 - 1, 73], fill=shade)
    d.rectangle([tx0 + 7, 22, tx1 - 7, 40], fill=OUTLINE)  # vano de la campana
    d.rectangle([tx0 + 8, 23, tx1 - 8, 39], fill=(26, 22, 34))
    d.ellipse([W // 2 - 5, 28, W // 2 + 4, 38], fill=(150, 120, 60))  # campana
    d.polygon([(tx0 - 2, 13), (W // 2, -1), (tx1 + 2, 13)], fill=OUTLINE)
    d.polygon([(tx0 + 1, 12), (W // 2, 2), (tx1 - 1, 12)], fill=(120, 60, 46))
    d.line([W // 2, 0, W // 2, 6], fill=(220, 210, 180))  # cruz
    d.line([W // 2 - 2, 2, W // 2 + 2, 2], fill=(220, 210, 180))
    d.rectangle([tx0 + 10, 50, tx1 - 10, 58], fill=OUTLINE)  # reloj/ventana sellada
    d.rectangle([tx0 + 11, 51, tx1 - 11, 57], fill=(60, 50, 40))
    # puerta principal, ventanas y papel picado
    door(d, W // 2, H - 2, w=16, h=26, color=(80, 46, 30), arch=True)
    for x in (16, W - 24):
        window(d, x, 92, True, 7, 14)
    for i, x in enumerate(range(8, W - 8, 6)):
        d.polygon([(x, 78), (x + 5, 78), (x + 2, 83)], fill=[PURPLE, MARIGOLD, (200, 60, 120)][i % 3])
    return img


def caseta() -> Image.Image:
    img = house(3, 3, (150, 150, 120), (60, 70, 60), roof_h=12, lit=(True, True))
    return img


def terminal() -> Image.Image:
    W, H = 6 * T, 3 * T
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 6, W - 1, 14], fill=OUTLINE)
    d.rectangle([1, 7, W - 2, 13], fill=(60, 110, 120))
    for x in (6, W - 8):
        d.rectangle([x, 14, x + 2, H - 1], fill=(90, 90, 90))
    d.rectangle([14, 30, W - 16, 34], fill=(110, 76, 50))  # banca
    d.rectangle([14, 35, 16, 40], fill=(80, 56, 40))
    d.rectangle([W - 18, 35, W - 16, 40], fill=(80, 56, 40))
    d.rectangle([W // 2 - 8, 16, W // 2 + 8, 26], fill=OUTLINE)  # tablero de rutas
    d.rectangle([W // 2 - 7, 17, W // 2 + 7, 25], fill=(230, 220, 190))
    return img


def market() -> Image.Image:
    W, H = 7 * T, 4 * T
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    colors = [(200, 60, 60), (60, 120, 200), (230, 170, 40)]
    for i in range(3):
        x0 = i * 37
        d.rectangle([x0 + 2, 26, x0 + 34, H - 2], fill=OUTLINE)
        d.rectangle([x0 + 3, 27, x0 + 33, H - 3], fill=(110, 80, 52))
        for s in range(0, 32, 6):  # toldo a rayas
            d.rectangle([x0 + 2 + s, 12, x0 + 4 + s + 2, 24], fill=colors[i] if s % 12 == 0 else (230, 225, 210))
        d.rectangle([x0 + 2, 10, x0 + 34, 12], fill=OUTLINE)
        for fx in range(x0 + 6, x0 + 32, 5):  # frutas
            d.ellipse([fx, 30, fx + 3, 33], fill=[MARIGOLD, (180, 40, 40), (90, 160, 60)][fx % 3])
    return img


def cemetery() -> Image.Image:
    W, H = 12 * T, 9 * T
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], fill=(28, 40, 32))
    rnd = random.Random(11)
    for _ in range(18):  # cruces y lápidas
        x, y = rnd.randrange(12, W - 16), rnd.randrange(12, H - 40)
        if rnd.random() < 0.5:
            d.rectangle([x + 3, y, x + 5, y + 12], fill=(170, 165, 150))
            d.rectangle([x, y + 3, x + 8, y + 5], fill=(170, 165, 150))
        else:
            d.rectangle([x, y + 2, x + 8, y + 12], fill=(120, 120, 124))
            d.ellipse([x, y, x + 8, y + 6], fill=(120, 120, 124))
        d.point((x + 4, y + 13), fill=MARIGOLD)
    # muro con portón
    d.rectangle([0, H - 26, W - 1, H - 1], fill=OUTLINE)
    d.rectangle([1, H - 25, W - 2, H - 2], fill=(150, 140, 130))
    for x in range(0, W, 8):
        d.line([x, H - 25, x, H - 2], fill=(130, 120, 110))
    gx = W // 2
    d.rectangle([gx - 14, H - 30, gx + 14, H - 1], fill=OUTLINE)
    for x in range(gx - 12, gx + 12, 4):
        d.line([x, H - 28, x, H - 2], fill=(60, 60, 70))
    d.rectangle([gx - 18, H - 36, gx - 14, H - 1], fill=(170, 160, 150))
    d.rectangle([gx + 14, H - 36, gx + 18, H - 1], fill=(170, 160, 150))
    return img


def kiosk() -> Image.Image:
    W, H = 4 * T, 4 * T
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(2, 20), (W // 2, 2), (W - 3, 20)], fill=OUTLINE)
    d.polygon([(5, 19), (W // 2, 5), (W - 6, 19)], fill=(40, 110, 90))
    for x in (8, W // 2 - 1, W - 10):
        d.rectangle([x, 20, x + 2, H - 10], fill=(220, 210, 190))
    d.rectangle([2, H - 10, W - 3, H - 2], fill=OUTLINE)
    d.rectangle([3, H - 9, W - 4, H - 3], fill=(150, 140, 130))
    for i, x in enumerate(range(6, W - 6, 6)):
        d.polygon([(x, 21), (x + 5, 21), (x + 2, 26)], fill=[PURPLE, MARIGOLD][i % 2])
    return img


def make_facades() -> dict[str, tuple[int, int]]:
    f = OUT / "facades"
    f.mkdir(parents=True, exist_ok=True)
    arts = {
        "iglesia": church(),
        "casa_parroquial": house(6, 5, (190, 180, 160), (130, 64, 50), lit=(True, False)),
        "pupuseria": house(7, 5, (214, 160, 90), (150, 70, 50), lit=(True, True),
                           sign=((240, 230, 200), (150, 40, 40))),
        "puesto_policial": house(6, 5, (150, 170, 190), (60, 70, 100), lit=(False, True),
                                 sign=((230, 230, 240), (30, 50, 120)), door_color=(50, 60, 90)),
        "caseta_vigilancia": caseta(),
        "casa_portillo": house(6, 5, (170, 120, 150), (110, 60, 60), lit=(True, True)),
        "cantina": house(6, 5, (140, 90, 70), (90, 50, 40), lit=(True, True),
                         sign=((255, 120, 90), (40, 20, 20)), door_color=(120, 70, 30)),
        "terminal": terminal(),
        "mercado": market(),
        "cementerio": cemetery(),
        "kiosco": kiosk(),
    }
    sizes = {}
    for name, img in arts.items():
        img.save(f / f"{name}.png")
        sizes[name] = (img.width // T, img.height // T)
    return sizes


# ---------- props ----------

def make_props() -> None:
    p = OUT / "props"
    p.mkdir(parents=True, exist_ok=True)
    lamp = Image.new("RGBA", (8, 28), (0, 0, 0, 0))
    d = ImageDraw.Draw(lamp)
    d.rectangle([3, 8, 4, 27], fill=(40, 40, 48))
    d.rectangle([1, 26, 6, 27], fill=(40, 40, 48))
    d.rectangle([0, 1, 7, 8], fill=OUTLINE)
    d.rectangle([1, 2, 6, 7], fill=GLOW)
    d.rectangle([2, 0, 5, 1], fill=(40, 40, 48))
    lamp.save(p / "farol.png")
    # marcador de objeto examinable: destello de 2 cuadros (8x8 cada uno)
    mark = Image.new("RGBA", (16, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(mark)
    for i, r in enumerate((2, 3)):
        cx = i * 8 + 4
        d.line([cx, 4 - r, cx, 4 + r], fill=(255, 236, 170))
        d.line([cx - r, 4, cx + r, 4], fill=(255, 236, 170))
        d.point((cx, 4), fill=(255, 255, 255))
    mark.save(p / "marcador.png")


# ---------- personajes ----------

def char_color(cid: str) -> tuple[int, int, int]:
    # Mismo tono que tools/make_placeholders.py, para que retrato y sprite combinen.
    h = int(hashlib.md5(cid.encode()).hexdigest()[:4], 16) / 0xFFFF
    return tuple(int(c * 255) for c in colorsys.hsv_to_rgb(h, 0.55, 0.75))


def figure(d: ImageDraw.ImageDraw, ox: int, facing: str, step: int, body, skin=(196, 150, 110),
           hair=(30, 22, 18), hat=None) -> None:
    # piernas (animación de paso)
    legs = {0: (0, 0), 1: (-1, 1), 2: (1, -1)}[step]
    d.rectangle([ox + 5, 18 + max(0, legs[0]), ox + 7, 23], fill=(40, 36, 50))
    d.rectangle([ox + 9, 18 + max(0, legs[1]), ox + 11, 23], fill=(40, 36, 50))
    # cuerpo
    d.rectangle([ox + 4, 10, ox + 12, 19], fill=OUTLINE)
    d.rectangle([ox + 5, 11, ox + 11, 18], fill=body)
    # brazos
    sway = {0: 0, 1: 1, 2: -1}[step]
    if facing in ("down", "up"):
        d.rectangle([ox + 3, 11 + sway, ox + 4, 17 + sway], fill=body)
        d.rectangle([ox + 12, 11 - sway, ox + 13, 17 - sway], fill=body)
    else:
        ax = ox + 7 if facing == "left" else ox + 9
        d.rectangle([ax, 12 + sway, ax + 1, 18 + sway], fill=tuple(max(0, c - 30) for c in body))
    # cabeza
    d.rectangle([ox + 4, 2, ox + 12, 10], fill=OUTLINE)
    d.rectangle([ox + 5, 3, ox + 11, 9], fill=skin)
    if facing == "up":
        d.rectangle([ox + 5, 3, ox + 11, 9], fill=hair)
    else:
        d.rectangle([ox + 5, 3, ox + 11, 4], fill=hair)
        eyes = {"down": (6, 9), "left": (5, 7), "right": (9, 11)}[facing]
        for ex in eyes:
            d.point((ox + ex, 6), fill=OUTLINE)
    if hat:
        d.rectangle([ox + 2, 2, ox + 14, 3], fill=hat)
        d.rectangle([ox + 5, 0, ox + 11, 2], fill=hat)


def make_chars() -> None:
    c = OUT / "chars"
    c.mkdir(parents=True, exist_ok=True)
    chars = json.loads((ROOT / "content/public/characters.json").read_text(encoding="utf-8"))
    specs = {"player": dict(body=(60, 56, 80), hat=(36, 30, 26), skin=(176, 130, 96))}
    for w in chars["witnesses"]:
        specs[w["id"]] = dict(body=char_color(w["id"]))
    specs["padre_mauricio"]["body"] = (40, 36, 44)
    specs["ramirez"]["hat"] = (40, 50, 80)
    specs["alcides"]["hat"] = (90, 80, 50)
    specs["tonito"]["hair"] = (60, 40, 20)
    # Vecinos de ambiente (content/public/villagers.json): colores de su campo "look".
    vill = json.loads((ROOT / "content/public/villagers.json").read_text(encoding="utf-8"))
    for v in vill["villagers"]:
        specs[v["id"]] = {k: tuple(c) for k, c in v.get("look", {}).items()} or dict(body=char_color(v["id"]))
    for cid, kw in specs.items():
        sheet = Image.new("RGBA", (16 * 12, 24), (0, 0, 0, 0))
        d = ImageDraw.Draw(sheet)
        for di, facing in enumerate(("down", "up", "left", "right")):
            for step in range(3):
                figure(d, (di * 3 + step) * 16, facing, step, **kw)
        sheet.save(c / f"{cid}.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    if "--chars" in sys.argv:  # solo los sprites de personajes (testigos, jugador y vecinos)
        make_chars()
        print("Personajes en", OUT / "chars")
        return
    make_tiles()
    sizes = make_facades()
    make_props()
    make_chars()
    print("Arte del pueblo en", OUT)
    print("Tamaños de fachada (baldosas):", sizes)


if __name__ == "__main__":
    main()
