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


def campanada() -> list[float]:
    """Campana de bronce: parciales inarmónicos con caída larga."""
    n = int(RATE * 4.0)
    partials = ((196.0, 1.0, 1.6), (392.0, 0.55, 1.2), (466.2, 0.35, 0.9), (588.0, 0.3, 0.8),
                (783.9, 0.18, 0.6), (1046.5, 0.08, 0.4), (98.0, 0.4, 2.2))
    out = []
    for i in range(n):
        t = i / RATE
        strike = math.exp(-t / 0.01) * 0.3 * math.sin(2 * math.pi * 1500 * t)
        out.append(strike + sum(a * math.sin(2 * math.pi * f * t) * env(t, 0.003, d) for f, a, d in partials))
    return out


def viento(seconds: float = 8.0) -> list[float]:
    """Ruido filtrado con ráfagas lentas; empieza y termina en silencio para hacer bucle."""
    rnd = random.Random(47)
    n = int(RATE * seconds)
    out, low, low2 = [], 0.0, 0.0
    for i in range(n):
        t = i / RATE
        low += 0.02 * ((rnd.random() * 2 - 1) - low)
        low2 += 0.05 * (low - low2)
        gust = 0.55 + 0.45 * math.sin(2 * math.pi * t / seconds) ** 2 + 0.15 * math.sin(2 * math.pi * 3 * t / seconds)
        out.append(low2 * gust)
    fade = int(RATE * 0.5)
    for i in range(fade):  # cruce suave en los extremos del bucle
        k = i / fade
        out[i] *= k
        out[-1 - i] *= k
    return out


def musica(bars: int = 8, bpm: float = 72.0) -> list[float]:
    """Arpegio lento de marimba en la menor sobre un bordón grave. Bucle exacto."""
    beat = 60.0 / bpm
    n = int(RATE * beat * 4 * bars)
    out = [0.0] * n
    # La menor, Fa, Do, Mi (i - VI - III - V), dos compases cada uno
    chords = [(220.0, 261.6, 329.6), (174.6, 220.0, 261.6), (130.8, 164.8, 196.0), (164.8, 207.7, 246.9)]
    pattern = [0, 1, 2, 1, 0, 2, 1, 2]
    for bar in range(bars):
        chord = chords[(bar // 2) % len(chords)]
        for step, idx in enumerate(pattern):
            start = int(((bar * 8) + step) * beat / 2 * RATE)
            f = chord[idx] * (2 if step == 5 else 1)
            for i in range(int(RATE * 0.9)):
                j = start + i
                if j >= n:
                    break
                tt = i / RATE
                tone = math.sin(2 * math.pi * f * tt) + 0.25 * math.sin(2 * math.pi * 4 * f * tt) * math.exp(-tt / 0.05)
                out[j] += tone * env(tt, 0.004, 0.35) * 0.5
        root = chord[0] / 2
        b0 = int(bar * 4 * beat * RATE)
        for i in range(int(4 * beat * RATE)):  # bordón
            j = b0 + i
            if j < n:
                out[j] += 0.18 * math.sin(2 * math.pi * root * i / RATE) * (0.6 + 0.4 * math.sin(math.pi * i / (4 * beat * RATE)))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save("contradiccion.wav", contradiccion())
    save("evidencia.wav", evidencia())
    save("voz.wav", voz())
    save("campanada.wav", campanada())
    save("viento.wav", viento())
    save("musica.wav", musica())
    print("Sonidos en", OUT)


if __name__ == "__main__":
    main()
