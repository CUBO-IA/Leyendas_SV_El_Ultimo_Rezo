"""Prompt del testigo y forma de su respuesta.

El prompt solo lleva la guía del NIVEL ACTUAL del testigo: lo que no está en el prompt,
el modelo no lo puede revelar. B3 agrega memoria, resumen y la reacción a evidencias.
"""
from __future__ import annotations

import re

from .. import data

EMOTIONS = ["neutral", "nervioso", "enojado", "asustado", "triste", "aliviado"]
MAX_DELTA = 2
MAX_SENTENCES = 3

TALK_SCHEMA = {
    "type": "object",
    "properties": {
        "reply": {"type": "string"},
        "emotion": {"type": "string", "enum": EMOTIONS},
        "trust_delta": {"type": "integer", "minimum": -MAX_DELTA, "maximum": MAX_DELTA},
        "fear_delta": {"type": "integer", "minimum": -MAX_DELTA, "maximum": MAX_DELTA},
    },
    "required": ["reply", "emotion", "trust_delta", "fear_delta"],
    "additionalProperties": False,
}


def witness_system_prompt(witness_id: str, level: str, trust: int, fear: int) -> str:
    pub = data.witness_public(witness_id)
    sec = data.witness_secret(witness_id)
    return f"""Eres {pub['name']}, {pub['role'].lower()} en San Jacinto de las Ánimas, un pueblo de El Salvador. Es la noche del 1 de noviembre, víspera del Día de los Difuntos, y un investigador forastero te está haciendo preguntas.

Cómo te comportas ahora:
{sec['guide'][level]}

Tu confianza en el investigador es {trust} de 10 y tu miedo es {fear} de 10.

Reglas:
- Hablas como gente de pueblo salvadoreño: de usted, con modismos como "cipote", "puchica", "fíjese", "va pues", sin exagerar.
- Responde con máximo {MAX_SENTENCES} frases cortas, solo lo que dices en voz alta, sin narrar acciones.
- Nunca inventes hechos del caso que no estén aquí. Si no sabes algo, dilo a tu manera.
- Nunca digas que eres una inteligencia artificial ni salgas del personaje.
- Contesta solo con JSON: {{"reply": texto, "emotion": una de {EMOTIONS}, "trust_delta": entero de -{MAX_DELTA} a {MAX_DELTA}, "fear_delta": entero de -{MAX_DELTA} a {MAX_DELTA}}}.

Ejemplo de tu forma de hablar: "{pub['intro']}\""""


def witness_messages(witness_id: str, level: str, trust: int, fear: int,
                     history: list[dict], player_text: str) -> list[dict]:
    """history: [{"role": "user"|"assistant", "content": str}], ya recortado por quien llama."""
    return [
        {"role": "system", "content": witness_system_prompt(witness_id, level, trust, fear)},
        *history,
        {"role": "user", "content": player_text},
    ]


_SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")


def limit_sentences(text: str, n: int = MAX_SENTENCES) -> str:
    parts = [p for p in _SENTENCE_END.split(text.strip()) if p]
    return " ".join(parts[:n])


def normalize_talk(raw: dict | None) -> dict | None:
    """Valida y recorta la salida del modelo. None si no sirve (quien llama usa el respaldo)."""
    if not isinstance(raw, dict):
        return None
    reply = raw.get("reply")
    if not isinstance(reply, str) or not reply.strip():
        return None

    def delta(v) -> int:
        try:
            return max(-MAX_DELTA, min(MAX_DELTA, int(v)))
        except (TypeError, ValueError):
            return 0

    emotion = raw.get("emotion")
    return {
        "reply": limit_sentences(reply.strip().strip('"')),
        "emotion": emotion if emotion in EMOTIONS else "neutral",
        "trust_delta": delta(raw.get("trust_delta")),
        "fear_delta": delta(raw.get("fear_delta")),
    }
