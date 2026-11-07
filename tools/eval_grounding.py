"""Mide cuánto inventan los testigos con preguntas "trampa" (piden nombres, horas exactas
y detalles que su guía no trae).

    .venv\\Scripts\\python tools\\eval_grounding.py            # prompt solo (una llamada)
    .venv\\Scripts\\python tools\\eval_grounding.py --dialogue # como en el juego (corrige y filtra)

Usa el proveedor del .env (API de NVIDIA). Escribe el detalle en tools/out/eval_grounding.json.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from server.app import data  # noqa: E402
from server.app.config import Settings  # noqa: E402
from server.app.dialogue import Dialogue  # noqa: E402
from server.app.llm.grounding import invented  # noqa: E402
from server.app.llm.prompts import TALK_SCHEMA, normalize_talk, witness_messages  # noqa: E402
from server.app.llm.provider import get_provider  # noqa: E402

TRAPS = [
    "¿Quién más estaba con usted esa noche? Dígame sus nombres.",
    "¿A qué hora exacta pasó todo?",
    "¿Cómo se llaman los que desaparecieron?",
    "¿Qué vecinos vio pasar por aquí? Deme nombres.",
    "Cuénteme algo que vio y que nadie más sepa.",
]


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dialogue", action="store_true", help="pasar por Dialogue (corrección y filtro)")
    ap.add_argument("--only", default="", help="ids separados por coma")
    args = ap.parse_args()
    settings = Settings.from_env()
    provider = get_provider(settings)
    dlg = Dialogue(provider, timeout_s=settings.llm_reply_timeout_s)
    ids = [i for i in data.active_witnesses() if not args.only or i in args.only.split(",")]
    rows, bad_count, fallbacks, t0 = [], 0, 0, time.perf_counter()
    for wid in ids:
        start = data.witness_secret(wid)["start"]
        for q in TRAPS:
            npc = {"id": wid, "level": "inicial", "trust": start["trust"], "fear": start["fear"]}
            msgs = witness_messages(wid, "inicial", npc["trust"], npc["fear"], [], q)
            known = msgs[0]["content"] + "\n" + q
            t = time.perf_counter()
            if args.dialogue:
                talk, source = await dlg.talk(npc, {}, q)
                reply = talk["reply"]
                fallbacks += source == "fallback"
            else:
                for attempt in range(4):  # la API corta con 429 si se le pide muy seguido
                    try:
                        res = await provider.chat(msgs, schema=TALK_SCHEMA)
                        break
                    except Exception as exc:
                        if "429" not in str(exc) or attempt == 3:
                            raise
                        await asyncio.sleep(8)
                talk = normalize_talk(res.data) or {"reply": res.text}
                reply, source = talk["reply"], "llm"
            await asyncio.sleep(1.0)
            found = invented(reply, known)
            bad_count += bool(found)
            rows.append({"witness": wid, "question": q, "reply": reply, "invented": found,
                         "source": source, "seconds": round(time.perf_counter() - t, 2)})
            mark = "INVENTA " + ", ".join(found) if found else "ok"
            print(f"[{wid:15}] {mark:40} | {reply[:110]}")
    n = len(rows)
    print(f"\n{bad_count}/{n} respuestas con detalles inventados ({100 * bad_count / n:.0f} %)"
          f" · respaldos: {fallbacks} · {time.perf_counter() - t0:.0f} s"
          f" · modo: {'dialogue' if args.dialogue else 'prompt'}")
    out = ROOT / "tools" / "out"
    out.mkdir(exist_ok=True)
    (out / "eval_grounding.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    await provider.aclose()


if __name__ == "__main__":
    asyncio.run(main())
