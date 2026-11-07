"""Efectos de sonido sintetizados (sin descargas ni licencias): WAV mono 22 kHz, 16 bits.

  .venv\\Scripts\\python tools\\make_sfx.py

Salida en game/assets/sfx/:
  contradiccion.wav  golpe grave + campana disonante (al quebrar a un testigo)
  evidencia.wav      dos notas ascendentes (evidencia nueva)
  voz.wav            parpadeo corto para el texto letra a letra
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "sfx"
RATE = 22050


def save(name: str, samples: list[float]) -> None:
    peak = max(1e-6, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(32767 * 0.85 * s / peak)) for s in samples)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def env(t: float, attack: float, decay: float) -> float:
    return min(1.0, t / attack) * math.exp(-t / decay) if attack > 0 else math.exp(-t / decay)


def contradiccion() -> list[float]:
    rnd = random.Random(1147)
    n = int(RATE * 1.4)
    out = []
    for i in range(n):
        t = i / RATE
        thud = math.sin(2 * math.pi * (70 - 30 * t) * t) * env(t, 0.004, 0.18)
        noise = (rnd.random() * 2 - 1) * env(t, 0.001, 0.04) * 0.6
        bell = sum(math.sin(2 * math.pi * f * t) * a for f, a in
                   ((311.1, 0.5), (329.6, 0.45), (622.3, 0.2), (987.8, 0.1)))
        out.append(thud * 1.2 + noise + bell * env(t, 0.01, 0.45) * 0.45)
    return out


def evidencia() -> list[float]:
    out = []
    for f, start in ((659.3, 0.0), (987.8, 0.11)):
        for i in range(int(RATE * 0.5)):
            t = i / RATE
            idx = int((start + t) * RATE)
            while len(out) <= idx:
                out.append(0.0)
            out[idx] += (math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t)) \
                * env(t, 0.005, 0.16)
    return out


def voz() -> list[float]:
    n = int(RATE * 0.05)
    return [math.copysign(1, math.sin(2 * math.pi * 330 * i / RATE)) * 0.5 * env(i / RATE, 0.002, 0.015)
            for i in range(n)]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save("contradiccion.wav", contradiccion())
    save("evidencia.wav", evidencia())
    save("voz.wav", voz())
    print("Sonidos en", OUT)


if __name__ == "__main__":
    main()
