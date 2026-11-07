"""Juega por HTTP contra el motor real el recorrido de la Unión 1:
hablar con Doña Chonita, examinar el tablero eléctrico y quebrar a Don Alcides.

  .venv\\Scripts\\python -m server            (en otra terminal)
  .venv\\Scripts\\python tools\\smoke_game.py [--url http://127.0.0.1:8000] [--voice]

--voice pide audio (Magpie) en cada respuesta, lo descarga, mide texto + voz y al final
prueba /stt con una frase conocida.
"""
from __future__ import annotations

import argparse
import sys
import time

import httpx

STEPS = [
    ("talk", "chonita", "Buenas noches, doña. ¿Vio algo raro esta noche?"),
    ("talk", "chonita", "¿A qué hora cerró la pupusería?"),
    ("examine", "tablero_electrico", None),
    ("examine", "empedrado_plaza", None),
    ("talk", "alcides", "Don Alcides, ¿qué vio desde la caseta?"),
    ("present", "alcides", "surcos_ruedas"),
    ("present", "alcides", "registro_electrico"),
    ("talk", "alcides", "Tranquilo, nadie va a saber que usted me lo dijo. ¿Qué más vio?"),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8000")
    ap.add_argument("--voice", action="store_true", help="pide audio y mide texto + voz; prueba /stt")
    args = ap.parse_args()
    url = args.url.rstrip("/")
    want = args.voice
    c = httpx.Client(base_url=url, timeout=30)
    try:
        h = c.get("/health").json()
    except httpx.HTTPError as exc:
        print(f"No hay motor en {url}: {exc}")
        return 1
    print(f"Motor: {h['status']} · {h['model']} · warm={h['warm']}\n")
    sid = c.post("/session", json={"player_name": "Prueba"}).json()["session_id"]
    lat: list[float] = []
    audio_lat: list[float] = []
    for kind, target, arg in STEPS:
        t0 = time.perf_counter()
        if kind == "talk":
            r = c.post("/talk", json={"session_id": sid, "npc_id": target, "text": arg,
                                      "want_audio": want})
        elif kind == "present":
            r = c.post("/present", json={"session_id": sid, "npc_id": target,
                                         "evidence_id": arg, "want_audio": want})
        else:
            r = c.post("/examine", json={"session_id": sid, "object_id": target})
        dt = time.perf_counter() - t0
        body = r.json()
        if r.status_code != 200:
            print(f"!! {kind} {target}: {r.status_code} {body}")
            return 1
        if kind == "examine":
            print(f"[examina {target}] {body['text']}  -> evidencia {body['new_evidence']}")
            continue
        lat.append(dt)
        head = f"[{kind} {target}{' · ' + arg if kind == 'present' else ''}] {dt:.2f}s"
        if kind == "talk":
            print(f"\n> {arg}")
        print(f"{head}  nivel={body['level']} confianza={body['trust']} miedo={body['fear']} "
              f"({body['emotion']}, {body['source']})"
              f"{'  ¡CONTRADICCIÓN!' if body.get('contradiction') else ''}")
        print(f"  {body['reply']}")
        if want and body.get("audio_url"):
            t1 = time.perf_counter()
            a = c.get(body["audio_url"])
            da = time.perf_counter() - t1
            audio_lat.append(dt + da)
            print(f"  [voz] {a.status_code} {len(a.content) // 1024} KB, {da:.2f}s después del texto; total {dt + da:.2f}s")
        elif want:
            print("  [voz] sin audio_url (TTS apagado o falló)")
        for d in body["new_deductions"]:
            print(f"  + deducción: {d['text']}")
        for e in body["new_evidence"]:
            print(f"  + evidencia: {e}")
    st = c.get(f"/session/{sid}").json()
    print(f"\nEstado: acto {st['act']} · {st['clock']} · evidencias {st['evidence']} · "
          f"deducciones {[d['id'] for d in st['deductions']]}")
    lat.sort()
    print(f"Latencia con LLM: mediana {lat[len(lat) // 2]:.2f}s · máx {lat[-1]:.2f}s")
    if audio_lat:
        audio_lat.sort()
        print(f"Texto + voz: mediana {audio_lat[len(audio_lat) // 2]:.2f}s · máx {audio_lat[-1]:.2f}s")
    if want:
        check_stt(c)
    return 0


def check_stt(c: httpx.Client) -> None:
    """Sintetiza una frase conocida con la voz de Chonita, la manda a /stt como WAV y compara."""
    import io
    import wave
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from server.app.config import Settings
    from server.app.voice import TTS_RATE, Voice, voice_for
    phrase = "Buenas noches, doña. ¿A qué hora cerró la pupusería?"
    pcm = Voice(Settings.from_env())._synth_pcm(phrase, voice_for("chonita"))
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TTS_RATE)
        w.writeframes(pcm)
    t0 = time.perf_counter()
    r = c.post("/stt", content=buf.getvalue(), headers={"Content-Type": "audio/wav"})
    heard = r.json().get("text", r.json())
    print(f"[stt] {r.status_code} en {time.perf_counter() - t0:.2f}s: «{phrase}» -> «{heard}»")


if __name__ == "__main__":
    sys.exit(main())
