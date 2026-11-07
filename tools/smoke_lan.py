"""Prueba de varias partidas a la vez contra un motor en red (tools/motor_en_red.ps1).

    .venv\\Scripts\\python tools\\smoke_lan.py --api http://192.168.31.60:8000 --players 4

Cada "jugador" crea su partida, examina, habla con un testigo (con voz) y le presenta
una evidencia, todos al mismo tiempo. Comprueba que las partidas no se mezclan y mide
la latencia y los errores (p. ej. 429 de la API de NVIDIA).
"""
from __future__ import annotations

import argparse
import json
import statistics
import threading
import time
import urllib.error
import urllib.request

PLAN = [  # (testigo, objeto que da la evidencia, evidencia que lo confronta)
    ("alcides", "tablero_electrico", "registro_electrico"),
    ("beto", "carreton_beto", "recibo_coleccionista"),
    ("pilo", "asiento_bus", "moneda_agujero"),
    ("chente", "libreta_cantinero", "cuenta_cantina"),
]


def call(api: str, method: str, path: str, body: dict | None = None, timeout: float = 60) -> tuple[int, dict, float]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(api + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}"), time.perf_counter() - t0
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}"), time.perf_counter() - t0


def player(api: str, i: int, out: dict) -> None:
    wid, obj, ev = PLAN[i % len(PLAN)]
    res = {"witness": wid, "lat": [], "errors": [], "sources": []}
    _, ws, _ = call(api, "POST", "/session", {"player_name": f"Jugador {i + 1}"})
    sid = ws["session_id"]
    res["sid"] = sid
    st, ex, t = call(api, "POST", "/examine", {"session_id": sid, "object_id": obj})
    res["lat"].append(t)
    if st != 200:
        res["errors"].append(f"examine {st}")
    # Preguntas distintas por jugador: si no, saldrían de la caché y no se mediría nada.
    for text in (f"Buenas noches, soy el investigador {i + 1}. ¿Qué vio esta noche?",
                 f"Disculpe otra vez (pregunta {i + 1}): ¿dónde estaba cuando se fue la luz?"):
        st, r, t = call(api, "POST", "/talk", {"session_id": sid, "npc_id": wid, "text": text, "want_audio": True})
        res["lat"].append(t)
        res["sources"].append(r.get("source"))
        if st != 200:
            res["errors"].append(f"talk {st} {r.get('error')}")
        elif r.get("audio_url"):
            a0 = time.perf_counter()
            with urllib.request.urlopen(api + r["audio_url"], timeout=60) as a:
                ok = a.status == 200 and len(a.read()) > 1000
            res["lat"].append(time.perf_counter() - a0)
            if not ok:
                res["errors"].append("audio")
    st, r, t = call(api, "POST", "/present", {"session_id": sid, "npc_id": wid, "evidence_id": ev, "want_audio": False})
    res["lat"].append(t)
    res["sources"].append(r.get("source"))
    if st != 200 or not r.get("contradiction"):
        res["errors"].append(f"present {st} contradiction={r.get('contradiction')}")
    _, final, _ = call(api, "GET", f"/session/{sid}")
    res["evidence"] = final.get("evidence", [])
    out[i] = res


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://127.0.0.1:8000")
    ap.add_argument("--players", type=int, default=4)
    args = ap.parse_args()
    st, h, _ = call(args.api, "GET", "/health")
    print(f"motor {args.api}: {h.get('status')} · tts={h.get('tts')} stt={h.get('stt')}")
    out: dict = {}
    t0 = time.perf_counter()
    threads = [threading.Thread(target=player, args=(args.api, i, out)) for i in range(args.players)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    total = time.perf_counter() - t0
    all_lat, bad = [], 0
    for i in sorted(out):
        r = out[i]
        all_lat += r["lat"]
        bad += len(r["errors"])
        print(f"jugador {i + 1} ({r['witness']:7}) sesión {r['sid'][:6]} · evidencias {r['evidence']} · "
              f"fuentes {r['sources']} · máx {max(r['lat']):.1f} s · errores {r['errors'] or 'ninguno'}")
    # Aislamiento: cada partida tiene exactamente la evidencia de su propio plan.
    mixed = any(out[i]["evidence"] != [PLAN[i % len(PLAN)][2]] for i in out)
    print(f"\n{args.players} jugadores a la vez en {total:.1f} s · latencia mediana {statistics.median(all_lat):.2f} s · "
          f"máx {max(all_lat):.1f} s · errores {bad} · partidas mezcladas: {'SÍ' if mixed else 'no'}")


if __name__ == "__main__":
    main()
