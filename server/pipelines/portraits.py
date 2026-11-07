"""Retratos del juego en assets_generated/portraits/{id}_{emocion}.png (512x512).

  .venv\\Scripts\\python -m server.pipelines.portraits

- Testigos: arte de referencia del equipo (assets_generated/personajes/, fescobar85),
  recortado a busto sobre fondo nocturno. Cada dibujo es el neutral del testigo y
  además la emoción que expresa; las demás emociones caen al neutral (Godot ya lo hace).
- Sospechosos: retratos pixel art procedurales (no hay arte de referencia).

Por qué no hay 6 emociones por personaje: sin GPU NVIDIA no hay SDXL local, y el
2026-11-06 las APIs alojadas fallaron (FLUX Kontext solo acepta imágenes de ejemplo;
FLUX schnell/dev dieron timeout y 500). CLAUDE.md prevé este caso: 1-2 emociones.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
REFS = ROOT / "assets_generated" / "personajes"
OUT = ROOT / "assets_generated" / "portraits"
SIZE = 512
BG_TOP, BG_BOTTOM = (34, 26, 52), (12, 10, 20)

# archivo de referencia -> (testigo, emoción que muestra el dibujo)
REFERENCES: dict[str, tuple[str, str]] = {
    "Señora_Pupusas.png": ("chonita", "aliviado"),
    "Vigilante.png": ("alcides", "nervioso"),
    "Agente_PNC.png": ("ramirez", "neutral"),
    "Cura.png": ("padre_mauricio", "neutral"),
    "LustraZapatos.png": ("tonito", "asustado"),
    "Abuela.png": ("mercedes", "enojado"),
    "Motorista.png": ("chepe", "enojado"),
    "El_bolo.png": ("chente", "neutral"),
    "Vendedor.png": ("beto", "nervioso"),
    "El_Cobrador.png": ("pilo", "neutral"),
}
# Nayik.png no se usa: no es un personaje del juego y parece caricatura de una persona real.

# Ajustes de encuadre por dibujo (fracción del alto de la figura): (tamaño, desplazamiento x)
FRAMING: dict[str, tuple[float, float]] = {
    "El_Cobrador.png": (0.55, -0.02),
    "Cura.png": (0.5, 0.0),
    "Motorista.png": (0.75, 0.02),
}


def background(size: int = SIZE, glow: tuple[int, int, int] | None = None) -> Image.Image:
    """Degradado nocturno con viñeta y un halo opcional detrás de la cabeza."""
    bg = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):
        k = y / size
        d.line([0, y, size, y], fill=tuple(int(BG_TOP[i] * (1 - k) + BG_BOTTOM[i] * k) for i in range(3)))
    if glow:
        halo = Image.new("L", (size, size), 0)
        ImageDraw.Draw(halo).ellipse([size * 0.15, size * 0.05, size * 0.85, size * 0.75], fill=90)
        halo = halo.filter(ImageFilter.GaussianBlur(size // 8))
        bg = Image.composite(Image.new("RGB", (size, size), glow), bg, halo)
    vign = Image.new("L", (size, size), 0)
    ImageDraw.Draw(vign).ellipse([-size * 0.2, -size * 0.2, size * 1.2, size * 1.2], fill=255)
    vign = vign.filter(ImageFilter.GaussianBlur(size // 6))
    return Image.composite(bg, Image.new("RGB", (size, size), (6, 5, 10)), vign)


def bust(ref: Image.Image, scale: float = 0.6, dx: float = 0.0) -> Image.Image:
    """Recorte cuadrado de la parte alta de la figura, centrado en la cabeza."""
    ref = ref.convert("RGBA")
    alpha = ref.getchannel("A")
    l, t, r, b = alpha.getbbox()
    fig_h = b - t
    # centro de la cabeza: centroide de lo opaco en el 20 % superior de la figura
    band = alpha.crop((l, t, r, t + int(fig_h * 0.2)))
    px = band.load()
    xs = [x for y in range(band.height) for x in range(band.width) if px[x, y] > 128]
    head_x = l + (sum(xs) / len(xs) if xs else (r - l) / 2)
    side = int(fig_h * scale)
    cx = head_x + dx * fig_h
    box = (int(cx - side / 2), int(t - side * 0.05), int(cx + side / 2), int(t - side * 0.05) + side)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(ref.crop((max(box[0], 0), max(box[1], 0), min(box[2], ref.width), min(box[3], ref.height))),
                           (max(-box[0], 0), max(-box[1], 0)))
    return canvas


def compose(figure: Image.Image, glow=(70, 52, 110)) -> Image.Image:
    bg = background(SIZE, glow).convert("RGBA")
    fig = figure.resize((SIZE, SIZE), Image.LANCZOS)
    shadow = Image.new("RGBA", fig.size, (0, 0, 0, 0))
    shadow.putalpha(fig.getchannel("A").filter(ImageFilter.GaussianBlur(6)).point(lambda a: a * 0.6))
    bg.alpha_composite(shadow, (6, 8))
    bg.alpha_composite(fig)
    return bg.convert("RGB")


def witnesses() -> list[Path]:
    written = []
    for fname, (wid, emotion) in REFERENCES.items():
        src = REFS / fname
        if not src.exists():
            print(f"  falta {fname}: {wid} se queda con su placeholder")
            continue
        scale, dx = FRAMING.get(fname, (0.6, 0.0))
        img = compose(bust(Image.open(src), scale, dx))
        for emo in {"neutral", emotion}:
            path = OUT / f"{wid}_{emo}.png"
            img.save(path)
            written.append(path)
    return written


# ---------- sospechosos: pixel art procedural (64x64 escalado x8) ----------

G = 64
OUTLINE = (12, 8, 16)


def _canvas(glow) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def cipitio():
    im, d = _canvas(None)
    d.ellipse([22, 26, 42, 46], fill=OUTLINE)  # cabeza
    d.ellipse([23, 27, 41, 45], fill=(196, 140, 96))
    d.ellipse([8, 18, 56, 30], fill=OUTLINE)  # ala del sombrero enorme
    d.ellipse([9, 19, 55, 29], fill=(212, 170, 80))
    d.polygon([(20, 22), (32, 2), (44, 22)], fill=OUTLINE)
    d.polygon([(22, 21), (32, 5), (42, 21)], fill=(226, 186, 92))
    d.line([20, 20, 44, 20], fill=(150, 60, 40), width=2)
    for x in (26, 34):  # ojos traviesos, grandes
        d.rectangle([x, 31, x + 4, 35], fill=(250, 245, 230))
        d.rectangle([x + 2, 32, x + 3, 34], fill=OUTLINE)
    d.arc([26, 35, 38, 43], 10, 170, fill=(110, 40, 30), width=2)  # sonrisa pícara
    d.point((24, 38), fill=(220, 110, 90))
    d.point((40, 38), fill=(220, 110, 90))
    d.rectangle([20, 46, 44, 64], fill=OUTLINE)  # cuerpo de niño, panzón
    d.ellipse([19, 44, 45, 66], fill=(196, 140, 96))
    d.rectangle([19, 58, 45, 64], fill=(110, 80, 50))  # calzón de manta
    return im, (110, 90, 40)


def siguanaba():
    im, d = _canvas(None)
    d.rectangle([16, 14, 48, 64], fill=(18, 14, 20))  # cabello largo
    d.ellipse([22, 12, 42, 36], fill=OUTLINE)
    d.ellipse([23, 13, 41, 35], fill=(214, 200, 190))  # rostro pálido
    d.rectangle([22, 10, 42, 18], fill=(18, 14, 20))  # flequillo
    for x in (27, 34):
        d.rectangle([x, 23, x + 3, 25], fill=(20, 30, 30))
    d.line([29, 31, 35, 31], fill=(120, 40, 50))
    d.polygon([(18, 40), (46, 40), (54, 64), (10, 64)], fill=OUTLINE)  # vestido blanco
    d.polygon([(19, 41), (45, 41), (52, 64), (12, 64)], fill=(232, 230, 220))
    d.rectangle([20, 36, 44, 42], fill=(18, 14, 20))
    return im, (90, 110, 120)


def cadejo():
    im, d = _canvas(None)
    d.ellipse([10, 30, 54, 64], fill=OUTLINE)  # lomo
    d.ellipse([11, 31, 53, 63], fill=(26, 22, 30))
    d.polygon([(18, 10), (24, 24), (14, 26)], fill=(26, 22, 30))  # orejas
    d.polygon([(46, 10), (40, 24), (50, 26)], fill=(26, 22, 30))
    d.ellipse([16, 16, 48, 46], fill=(30, 26, 36))  # cabeza
    d.polygon([(24, 36), (40, 36), (32, 50)], fill=(36, 30, 42))  # hocico
    for x in (22, 37):  # ojos rojos
        d.ellipse([x, 26, x + 6, 31], fill=(220, 30, 40))
        d.point((x + 3, 28), fill=(255, 200, 200))
    d.rectangle([28, 48, 36, 50], fill=(230, 220, 210))  # colmillos
    return im, (110, 30, 40)


def padre_sin_cabeza():
    im, d = _canvas(None)
    d.polygon([(14, 26), (50, 26), (58, 64), (6, 64)], fill=OUTLINE)  # sotana
    d.polygon([(16, 27), (48, 27), (55, 64), (9, 64)], fill=(20, 18, 24))
    d.rectangle([26, 22, 38, 28], fill=OUTLINE)
    d.rectangle([27, 23, 37, 27], fill=(230, 230, 220))  # alzacuello vacío
    for i in range(6):  # resplandor verdoso donde iría la cabeza
        y = 20 - i * 3
        d.ellipse([30 - i, y - 2, 34 + i, y + 2], outline=(90 + i * 15, 200, 140, 160 - i * 20))
    d.line([32, 34, 32, 52], fill=(150, 120, 70))  # rosario
    d.line([28, 40, 36, 40], fill=(150, 120, 70))
    return im, (40, 110, 80)


def carreta_chillona():
    im, d = _canvas(None)
    d.rectangle([10, 22, 54, 42], fill=OUTLINE)  # caja de la carreta
    d.rectangle([11, 23, 53, 41], fill=(96, 64, 40))
    for x in range(14, 52, 6):
        d.line([x, 23, x, 41], fill=(70, 46, 28))
    for cx in (18, 46):  # ruedas de madera
        d.ellipse([cx - 11, 36, cx + 11, 58], fill=OUTLINE)
        d.ellipse([cx - 9, 38, cx + 9, 56], fill=(120, 86, 52))
        for k in range(4):
            a = k * math.pi / 4
            d.line([cx + 9 * math.cos(a), 47 + 9 * math.sin(a), cx - 9 * math.cos(a), 47 - 9 * math.sin(a)],
                   fill=(70, 46, 28))
    for i in range(4):  # llamas azules de ánimas
        x = 16 + i * 10
        d.polygon([(x, 22), (x + 4, 8 + (i % 2) * 4), (x + 8, 22)], fill=(80, 140, 230, 200))
    return im, (40, 70, 140)


def descarnada():
    im, d = _canvas(None)
    d.rectangle([18, 12, 46, 40], fill=(30, 10, 14))  # cabello oscuro
    d.ellipse([22, 12, 42, 36], fill=OUTLINE)
    left = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    d.ellipse([23, 13, 41, 35], fill=(226, 196, 180))  # mitad bella
    d.pieslice([23, 13, 41, 35], 90, 270, fill=(214, 210, 196))  # mitad calavera
    d.ellipse([25, 21, 30, 26], fill=OUTLINE)  # cuenca vacía
    d.rectangle([34, 22, 37, 24], fill=(40, 20, 20))
    for x in range(25, 32, 2):
        d.line([x, 30, x, 33], fill=OUTLINE)  # dientes
    d.line([33, 31, 38, 31], fill=(170, 30, 50))
    d.polygon([(16, 40), (48, 40), (56, 64), (8, 64)], fill=OUTLINE)  # vestido rojo
    d.polygon([(17, 41), (47, 41), (53, 64), (11, 64)], fill=(170, 24, 40))
    d.ellipse([40, 14, 46, 20], fill=(230, 60, 90))  # flor en el pelo
    del left
    return im, (120, 30, 50)


SUSPECTS = {"cipitio": cipitio, "siguanaba": siguanaba, "cadejo": cadejo,
            "padre_sin_cabeza": padre_sin_cabeza, "carreta_chillona": carreta_chillona,
            "descarnada": descarnada}


def suspects() -> list[Path]:
    written = []
    for sid, fn in SUSPECTS.items():
        small, glow = fn()
        bg = background(SIZE, glow).convert("RGBA")
        fig = small.resize((SIZE, SIZE), Image.NEAREST)
        bg.alpha_composite(fig)
        path = OUT / f"{sid}_neutral.png"
        bg.convert("RGB").save(path)
        written.append(path)
    return written


CREDITS_TEXT = """# Créditos de los retratos

- **Testigos:** arte de referencia del equipo (fescobar85), en `assets_generated/personajes/`.
  `server/pipelines/portraits.py` los recorta a busto de 512x512 sobre un fondo nocturno.
- **Sospechosos:** pixel art procedural generado por `server/pipelines/portraits.py`.
- `Nayik.png` no se usa en el juego.
"""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "CREDITOS.md").write_text(CREDITS_TEXT, encoding="utf-8")
    w = witnesses()
    s = suspects()
    print(f"{len(w)} retratos de testigos y {len(s)} de sospechosos en {OUT}")


if __name__ == "__main__":
    random.seed(0)
    main()
