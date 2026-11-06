"""Prueba de humo del diálogo: 10 preguntas a Doña Chonita (nivel inicial).

Mide latencia (meta < 3 s), validez del JSON y si se le escapan pistas de niveles superiores.

  .venv\\Scripts\\python tools\\smoke_llm.py                         # proveedor de .env
  .venv\\Scripts\\python tools\\smoke_llm.py --provider nvidia --model nvidia/nemotron-nano-3-30b-a3b
  .venv\\Scripts\\python tools\\smoke_llm.py --provider ollama

Guarda el detalle en tools/out/smoke_llm_<proveedor>_<modelo>.json (ignorado por git).
"""
from __future__ import annotations

import argparse
import asyncio
import dataclasses
import json
import re
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from server.app.config import ROOT, Settings  # noqa: E402
from server.app.llm.prompts import TALK_SCHEMA, normalize_talk, witness_messages  # noqa: E402
from server.app.llm.provider import LLMError, get_provider  # noqa: E402

GOAL_S = 3.0
QUESTIONS = [
    "Buenas noches, señora. ¿Usted es la de la pupusería?",
    "¿Qué vio esta noche en la plaza?",
    "¿A qué hora cerró la pupusería?",
    "¿Cómo era esa figura de sotana?",
    "¿Hacia dónde caminaba?",
    "¿Escuchó algo raro por el lado del cementerio?",
    "¿Le vendió pupusas a alguien después de las nueve?",
    "¿Usted cree en los espantos?",
    "¿Conoce al padre Mauricio?",
    "Gracias, doña. ¿Algo más que me quiera contar?",
]
# Datos que Chonita NO debe decir en nivel inicial (son de 'confrontada' o 'confesion').
LEAKS = ["campanario", "sin cabeza", "excav", "escarb", "billete", "revueltas", "sellada"]


def sentences(text: str) -> int:
    return len([s for s in re.split(r"(?<=[.!?…])\s+", text.strip()) if s])


async def run(settings: Settings, n: int) -> dict:
    provider = get_provider(settings)
    t0 = time.perf_counter()
    try:
        await provider.warmup()
    except LLMError as exc:
        await provider.aclose()
        raise SystemExit(f"No se pudo calentar {settings.llm_provider}: {exc}")
    warm_s = time.perf_counter() - t0
    print(f"\n== {provider.name} / {provider.model}  (calentamiento {warm_s:.1f} s)\n")

    history: list[dict] = []
    trust, fear = 4, 3
    rows = []
    for i, q in enumerate(QUESTIONS[:n], 1):
        msgs = witness_messages("chonita", "inicial", trust, fear, history[-12:], q)
        try:
            res = await provider.chat(msgs, schema=TALK_SCHEMA)
            err = None
        except LLMError as exc:
            res, err = None, str(exc)
        talk = normalize_talk(res.data) if res else None
        reply = talk["reply"] if talk else (res.text[:200] if res else "")
        leaks = [w for w in LEAKS if w in reply.lower()]
        row = {
            "q": q,
            "latency_s": round(res.latency_s, 2) if res else None,
            "json_ok": talk is not None,
            "raw_sentences": sentences(res.data.get("reply", "")) if res and res.data else None,
            "emotion": talk["emotion"] if talk else None,
            "reply": reply,
            "leaks": leaks,
            "error": err,
        }
        rows.append(row)
        if talk:
            trust = max(0, min(10, trust + talk["trust_delta"]))
            fear = max(0, min(10, fear + talk["fear_delta"]))
            history += [{"role": "user", "content": q},
                        {"role": "assistant", "content": talk["reply"]}]
        lat = f"{row['latency_s']:.2f}s" if row["latency_s"] is not None else "ERROR"
        flag = "" if talk else "  [JSON inválido]"
        flag += f"  [FUGA: {', '.join(leaks)}]" if leaks else ""
        print(f"{i:2}. {lat:>6}  {q}\n      → ({row['emotion']}) {reply or err}{flag}")
    await provider.aclose()

    lats = [r["latency_s"] for r in rows if r["latency_s"] is not None]
    lats_sorted = sorted(lats)
    summary = {
        "provider": provider.name,
        "model": provider.model,
        "warmup_s": round(warm_s, 2),
        "n": len(rows),
        "errors": sum(1 for r in rows if r["error"]),
        "json_ok": sum(1 for r in rows if r["json_ok"]),
        "leaks": sum(1 for r in rows if r["leaks"]),
        "over_3_sentences": sum(1 for r in rows if (r["raw_sentences"] or 0) > 3),
        "latency_min": round(min(lats), 2) if lats else None,
        "latency_median": round(statistics.median(lats), 2) if lats else None,
        "latency_p90": round(lats_sorted[max(0, int(len(lats) * 0.9) - 1)], 2) if lats else None,
        "latency_max": round(max(lats), 2) if lats else None,
    }
    summary["meets_goal"] = bool(lats) and summary["latency_p90"] < GOAL_S and not summary["errors"]
    print(f"\nResumen: mediana {summary['latency_median']} s · p90 {summary['latency_p90']} s · "
          f"máx {summary['latency_max']} s · JSON ok {summary['json_ok']}/{summary['n']} · "
          f"fugas {summary['leaks']} · >3 frases {summary['over_3_sentences']} · "
          f"errores {summary['errors']}")
    print("META < 3 s:", "CUMPLIDA" if summary["meets_goal"] else "NO CUMPLIDA")
    return {"summary": summary, "turns": rows}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--provider", choices=["ollama", "nvidia"])
    ap.add_argument("--model", help="modelo del proveedor elegido")
    ap.add_argument("-n", type=int, default=len(QUESTIONS))
    args = ap.parse_args()

    s = Settings.from_env()
    changes = {}
    if args.provider:
        changes["llm_provider"] = args.provider
    provider = args.provider or s.llm_provider
    if args.model:
        changes["nvidia_model" if provider == "nvidia" else "llm_model"] = args.model
    s = dataclasses.replace(s, llm_timeout_s=max(s.llm_timeout_s, 120.0), **changes)

    report = asyncio.run(run(s, args.n))
    out = ROOT / "tools" / "out"
    out.mkdir(parents=True, exist_ok=True)
    tag = re.sub(r"[^A-Za-z0-9.-]+", "_", f"{report['summary']['provider']}_{report['summary']['model']}")
    path = out / f"smoke_llm_{tag}.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Detalle: {path}")


if __name__ == "__main__":
    main()
