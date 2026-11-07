"""Arte placeholder de interiores (iglesia y campanario) y fondos de los finales.

  .venv\\Scripts\\python tools\\make_story_art.py

Salida:
  game/assets/interior/tiles.png   atlas: piedra, piedra2, madera, madera2, alfombra, muro, muro_ventana
  game/assets/interior/props/*.png banca, altar, vela, cuerda, trampilla, escalera, campana, puerta
  game/assets/endings/{scene}.png  1280x720 (pintado a 320x180 y escalado x4), uno por final
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
INT = ROOT / "game" / "assets" / "interior"
END = ROOT / "game" / "assets" / "endings"
T = 16
OUTLINE = (16, 12, 20)
GLOW = (255, 196, 92)
# Los nuevos van al final para no mover los índices de los anteriores (InteriorLayout.Tile).
INTERIOR_TILES = ["stone", "stone2", "wood", "wood2", "carpet", "wall", "wall_window",
                  "grass", "grass2", "path"]


def tiles() -> None:
    rnd = random.Random(7)
    out = Image.new("RGB", (T * len(INTERIOR_TILES), T))
    for i, name in enumerate(INTERIOR_TILES):
        img = Image.new("RGB", (T, T))
        d = ImageDraw.Draw(img)
        if name.startswith("stone"):
            base = (92, 88, 96) if name == "stone" else (84, 80, 90)
            d.rectangle([0, 0, T, T], fill=base)
            d.line([0, 7, T, 7], fill=(70, 66, 76))
            d.line([0, 15, T, 15], fill=(70, 66, 76))
            d.line([5, 0, 5, 7], fill=(70, 66, 76))
            d.line([11, 8, 11, 15], fill=(70, 66, 76))
        elif name.startswith("wood"):
            base = (110, 74, 46) if name == "wood" else (100, 66, 40)
            d.rectangle([0, 0, T, T], fill=base)
            for y in (3, 7, 11, 15):
                d.line([0, y, T, y], fill=(80, 52, 32))
            d.point((rnd.randrange(T), rnd.randrange(T)), fill=(70, 44, 26))
        elif name.startswith("grass"):  # pasto del cementerio, de noche
            base = (38, 56, 42) if name == "grass" else (34, 50, 38)
            d.rectangle([0, 0, T, T], fill=base)
            for _ in range(5):
                x, y = rnd.randrange(T), rnd.randrange(2, T)
                d.line([x, y, x, y - 2], fill=(52, 76, 56))
        elif name == "path":  # sendero de tierra
            d.rectangle([0, 0, T, T], fill=(86, 70, 54))
            for _ in range(4):
                x, y = rnd.randrange(1, T - 1), rnd.randrange(1, T - 1)
                d.point((x, y), fill=(110, 96, 80))
                d.point((x + 1, y), fill=(66, 54, 42))
        elif name == "carpet":
            d.rectangle([0, 0, T, T], fill=(130, 30, 40))
            d.line([1, 0, 1, T], fill=(200, 160, 60))
            d.line([14, 0, 14, T], fill=(200, 160, 60))
        else:
            d.rectangle([0, 0, T, T], fill=(150, 140, 126))
            d.line([0, 15, T, 15], fill=(110, 100, 90))
            d.line([0, 7, T, 7], fill=(130, 120, 108))
            if name == "wall_window":
                d.rectangle([4, 2, 11, 13], fill=OUTLINE)
                d.rectangle([5, 3, 10, 12], fill=(70, 90, 150))
                d.line([7, 3, 7, 12], fill=(200, 60, 80))
                d.line([5, 7, 10, 7], fill=(230, 190, 60))
        out.paste(img, (i * T, 0))
    INT.mkdir(parents=True, exist_ok=True)
    out.save(INT / "tiles.png")


def props() -> None:
    p = INT / "props"
    p.mkdir(parents=True, exist_ok=True)
    # banca (3x1 baldosas, vista de frente)
    im = Image.new("RGBA", (48, 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 47, 8], fill=OUTLINE)
    d.rectangle([1, 1, 46, 7], fill=(100, 64, 38))
    d.rectangle([0, 9, 47, 13], fill=OUTLINE)
    d.rectangle([1, 10, 46, 12], fill=(120, 80, 48))
    for x in (2, 44):
        d.rectangle([x, 13, x + 2, 19], fill=(80, 52, 30))
    im.save(p / "banca.png")
    # altar (4x2) con mantel, cruz y cempasúchil
    im = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([4, 20, 59, 47], fill=OUTLINE)
    d.rectangle([5, 21, 58, 46], fill=(220, 214, 200))
    d.rectangle([5, 21, 58, 26], fill=(123, 79, 168))
    d.rectangle([29, 0, 34, 20], fill=(200, 160, 60))
    d.rectangle([22, 5, 41, 9], fill=(200, 160, 60))
    for x in range(8, 57, 6):
        d.ellipse([x, 40, x + 4, 44], fill=(232, 138, 44))
    im.save(p / "altar.png")
    # vela
    im = Image.new("RGBA", (6, 14), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([1, 5, 4, 13], fill=(236, 228, 210))
    d.ellipse([1, 0, 4, 5], fill=GLOW)
    im.save(p / "vela.png")
    # cuerda de la campana
    im = Image.new("RGBA", (6, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for y in range(0, 44, 3):
        d.rectangle([2, y, 3, y + 2], fill=(180, 150, 100) if y % 6 else (150, 120, 80))
    d.ellipse([0, 40, 5, 47], fill=(150, 120, 80))
    im.save(p / "cuerda.png")
    # campana (vista desde abajo, en el techo)
    im = Image.new("RGBA", (40, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.pieslice([0, 0, 39, 56], 180, 360, fill=OUTLINE)
    d.pieslice([2, 2, 37, 54], 180, 360, fill=(150, 116, 56))
    d.rectangle([17, 22, 22, 31], fill=(100, 76, 36))
    im.save(p / "campana.png")
    # trampilla
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 23, 23], fill=OUTLINE)
    d.rectangle([1, 1, 22, 22], fill=(76, 50, 30))
    for y in (6, 12, 18):
        d.line([1, y, 22, y], fill=(56, 36, 22))
    d.rectangle([9, 10, 14, 13], fill=(160, 150, 130))
    im.save(p / "trampilla.png")
    # escalera de caracol (2x2)
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, 31, 31], fill=OUTLINE)
    for k in range(8):
        a = k * math.pi / 4
        d.polygon([(16, 16), (16 + 15 * math.cos(a), 16 + 15 * math.sin(a)),
                   (16 + 15 * math.cos(a + 0.7), 16 + 15 * math.sin(a + 0.7))],
                  fill=(120 - k * 8, 90 - k * 6, 60 - k * 4))
    d.ellipse([12, 12, 19, 19], fill=(60, 50, 40))
    im.save(p / "escalera.png")
    # puerta (salida)
    im = Image.new("RGBA", (24, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 23, 29], fill=OUTLINE)
    d.rectangle([2, 2, 21, 29], fill=(80, 46, 30))
    d.line([11, 2, 11, 29], fill=OUTLINE)
    d.point((9, 16), fill=GLOW)
    d.point((14, 16), fill=GLOW)
    im.save(p / "puerta.png")


# ---------- finales ----------

def sky(d: ImageDraw.ImageDraw, top, bottom, h: int = 180) -> None:
    for y in range(h):
        k = y / h
        d.line([0, y, 320, y], fill=tuple(int(top[i] * (1 - k) + bottom[i] * k) for i in range(3)))


def church_silhouette(d: ImageDraw.ImageDraw, color, x: int = 150, base: int = 150) -> None:
    d.rectangle([x - 40, base - 50, x + 40, base], fill=color)
    d.polygon([(x - 46, base - 50), (x, base - 78), (x + 46, base - 50)], fill=color)
    d.rectangle([x - 12, base - 112, x + 12, base - 50], fill=color)
    d.polygon([(x - 15, base - 112), (x, base - 132), (x + 15, base - 112)], fill=color)
    d.rectangle([x - 1, base - 142, x + 1, base - 130], fill=color)
    d.rectangle([x - 5, base - 138, x + 5, base - 136], fill=color)


def town_silhouette(d: ImageDraw.ImageDraw, color, base: int = 150, seed: int = 3) -> None:
    rnd = random.Random(seed)
    x = 0
    while x < 320:
        w, h = rnd.randrange(18, 34), rnd.randrange(12, 26)
        if not 100 < x < 200:
            d.rectangle([x, base - h, x + w, base], fill=color)
            d.polygon([(x - 2, base - h), (x + w // 2, base - h - 8), (x + w + 2, base - h)], fill=color)
        x += w + rnd.randrange(2, 8)
    d.rectangle([0, base, 320, 180], fill=color)


def ending_malo() -> Image.Image:
    im = Image.new("RGB", (320, 180))
    d = ImageDraw.Draw(im)
    sky(d, (40, 6, 14), (110, 24, 30))
    d.ellipse([230, 18, 262, 50], fill=(220, 120, 110))
    d.ellipse([236, 16, 266, 46], fill=(70, 12, 20))  # luna menguante roja
    church_silhouette(d, (14, 6, 10))
    town_silhouette(d, (20, 8, 12))
    d.rectangle([146, 30, 154, 40], fill=(255, 180, 90))  # luz en el campanario
    rnd = random.Random(9)
    for _ in range(26):  # nombres que se borran: rayas que se desvanecen
        x, y = rnd.randrange(10, 300), rnd.randrange(155, 176)
        d.line([x, y, x + rnd.randrange(8, 22), y], fill=(90 + rnd.randrange(60), 40, 46))
    return im


def ending_gris() -> Image.Image:
    im = Image.new("RGB", (320, 180))
    d = ImageDraw.Draw(im)
    sky(d, (90, 96, 110), (190, 170, 150))
    church_silhouette(d, (60, 62, 72))
    town_silhouette(d, (54, 56, 66))
    rnd = random.Random(5)
    for _ in range(14):  # cohetes de fiesta, apagados por la niebla
        x, y = rnd.randrange(10, 310), rnd.randrange(10, 80)
        c = rnd.choice([(232, 138, 44), (123, 79, 168), (200, 60, 120)])
        for a in range(0, 360, 45):
            d.point((x + int(4 * math.cos(math.radians(a))), y + int(4 * math.sin(math.radians(a)))), fill=c)
    for y in range(120, 180, 3):  # niebla
        d.line([0, y, 320, y], fill=(150, 150, 156))
    return im


def ending_verdadero() -> Image.Image:
    im = Image.new("RGB", (320, 180))
    d = ImageDraw.Draw(im)
    sky(d, (40, 50, 110), (250, 170, 90))
    d.ellipse([130, 120, 190, 180], fill=(255, 220, 140))  # amanecer detrás de la iglesia
    church_silhouette(d, (40, 30, 50))
    town_silhouette(d, (36, 28, 46))
    for x in range(20, 300, 12):  # velas y cempasúchil en la calle
        d.rectangle([x, 160, x + 1, 165], fill=(240, 230, 210))
        d.point((x, 158), fill=(255, 200, 100))
        d.rectangle([x + 4, 166, x + 6, 168], fill=(232, 138, 44))
    for i, x in enumerate(range(0, 320, 8)):  # papel picado
        d.polygon([(x, 92), (x + 6, 92), (x + 3, 98)], fill=[(123, 79, 168), (232, 138, 44), (200, 60, 120)][i % 3])
    d.line([0, 92, 320, 92], fill=(60, 50, 60))
    return im


def endings() -> None:
    END.mkdir(parents=True, exist_ok=True)
    for name, fn in (("ending_malo", ending_malo), ("ending_gris", ending_gris),
                     ("ending_verdadero", ending_verdadero)):
        fn().resize((1280, 720), Image.NEAREST).save(END / f"{name}.png")


def cemetery_props() -> None:
    """Utilería del cementerio (Acto II)."""
    p = INT / "props"
    p.mkdir(parents=True, exist_ok=True)
    stone, stone_d = (150, 146, 140), (110, 106, 102)
    # lápida con cruz grabada (1 baldosa x 20 px)
    im = Image.new("RGBA", (16, 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([1, 0, 14, 19], radius=6, fill=OUTLINE)
    d.rounded_rectangle([2, 1, 13, 18], radius=5, fill=stone)
    d.rectangle([2, 15, 13, 18], fill=stone_d)
    d.line([7, 4, 7, 12], fill=stone_d)
    d.line([5, 6, 9, 6], fill=stone_d)
    im.save(p / "lapida.png")
    # cruz de madera torcida
    im = Image.new("RGBA", (16, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(6, 23), (9, 23), (11, 1), (8, 1)], fill=OUTLINE)
    d.polygon([(7, 22), (8, 22), (10, 2), (9, 2)], fill=(110, 76, 46))
    d.polygon([(2, 9), (14, 6), (14, 9), (2, 12)], fill=OUTLINE)
    d.polygon([(3, 10), (13, 7), (13, 8), (3, 11)], fill=(120, 84, 52))
    im.save(p / "cruz.png")
    # mausoleo (3x3)
    im = Image.new("RGBA", (48, 52), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(2, 16), (24, 2), (46, 16)], fill=OUTLINE)
    d.polygon([(5, 15), (24, 4), (43, 15)], fill=(160, 154, 146))
    d.rectangle([4, 16, 44, 51], fill=OUTLINE)
    d.rectangle([5, 17, 43, 50], fill=(140, 134, 126))
    d.rectangle([17, 26, 31, 50], fill=(30, 26, 34))
    d.line([24, 26, 24, 50], fill=(60, 56, 64))
    d.line([22, 8, 26, 8], fill=(200, 160, 60))
    d.line([24, 6, 24, 12], fill=(200, 160, 60))
    for x in (8, 38):
        d.rectangle([x, 20, x + 2, 50], fill=(170, 164, 156))
    im.save(p / "mausoleo.png")
    # tumba sin nombre: montículo de tierra recién removida, sin lápida (2x1)
    im = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 2, 31, 15], fill=OUTLINE)
    d.ellipse([1, 3, 30, 14], fill=(92, 64, 40))
    for x, y in ((6, 6), (12, 9), (20, 5), (25, 9), (16, 11)):
        d.rectangle([x, y, x + 2, y + 1], fill=(120, 88, 58))
    d.line([27, 0, 30, 10], fill=(150, 150, 160))  # pala clavada
    d.rectangle([25, 0, 29, 1], fill=(100, 70, 40))
    im.save(p / "tumba.png")
    # ciprés (1x3)
    im = Image.new("RGBA", (16, 44), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([1, 0, 14, 40], fill=OUTLINE)
    d.ellipse([2, 1, 13, 39], fill=(26, 52, 40))
    d.ellipse([5, 6, 10, 30], fill=(34, 66, 50))
    d.rectangle([6, 38, 9, 43], fill=(70, 50, 34))
    im.save(p / "cipres.png")
    # reja del cementerio (salida al pueblo)
    im = Image.new("RGBA", (32, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 31, 29], fill=(0, 0, 0, 0))
    for x in range(1, 31, 5):
        d.line([x, 3, x, 29], fill=(30, 30, 38), width=2)
        d.polygon([(x - 1, 3), (x + 1, 0), (x + 2, 3)], fill=(30, 30, 38))
    d.line([0, 10, 31, 10], fill=(30, 30, 38), width=2)
    d.line([0, 22, 31, 22], fill=(30, 30, 38), width=2)
    im.save(p / "reja.png")
    # flores de cempasúchil sobre una tumba
    im = Image.new("RGBA", (12, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for x, y in ((1, 3), (4, 1), (7, 3), (4, 5), (8, 0)):
        d.ellipse([x, y, x + 3, y + 3], fill=(232, 138, 44))
        d.point((x + 1, y + 1), fill=(255, 200, 80))
    im.save(p / "flores.png")


def main() -> None:
    import sys
    tiles()
    props()
    cemetery_props()
    if "--interior" in sys.argv:  # solo interiores (sin rehacer los finales)
        print("Interiores en", INT)
        return
    endings()
    print("Interiores en", INT, "· finales en", END)


if __name__ == "__main__":
    main()
