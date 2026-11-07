"""Redacción de lo que dice cada testigo. Las reglas ya decidieron qué pasó
(rules.py); aquí el LLM solo pone las palabras, con:

- memoria: últimos 6 turnos con ese testigo + un resumen de lo anterior;
- filtros de entrada (texto del jugador) y de salida (spoilers o romper personaje);
- detalles inventados (llm/grounding.py): horas o nombres que el testigo no sabe. Se le
  pide una corrección; si insiste, se quitan esas frases;
- caché de respuestas y frases de respaldo si el modelo falla o tarda.
"""
from __future__ import annotations

import asyncio
import hashlib
import logging
import re
import time
import unicodedata
from collections import OrderedDict

from . import data
from .llm.grounding import drop_invented_sentences, invented
from .llm.prompts import TALK_SCHEMA, normalize_talk, witness_messages, witness_system_prompt
from .llm.provider import Provider

log = logging.getLogger("leyendas.dialogue")

HISTORY_TURNS = 6  # pares pregunta/respuesta que van completos al prompt
MAX_REPLY_CHARS = 600  # talk_response.reply maxLength
# 0.5 en vez de 0.7: con tools/eval_grounding.py el testigo se apega más a su guía
# (cuenta su pista en vez de adornar) sin perder su forma de hablar.
TEMPERATURE = 0.5

# Términos que el testigo no puede decir salvo que estén en la guía de su nivel actual.
SPOILER_TERMS = ["padre sin cabeza", "esteban", "nemotron", "chatgpt",
                 "inteligencia artificial", "modelo de lenguaje", "soy una ia", "system prompt"]

_ACTIONS = re.compile(r"\*[^*]{1,80}\*|\([^)]{1,60}\)")
_CTRL = re.compile(r"[\x00-\x1f\x7f]")


def clean_player_text(text: str) -> str:
    """Filtro de entrada: sin caracteres de control ni corchetes (con ellos el motor
    marca las evidencias presentadas; el jugador no los puede imitar)."""
    text = _CTRL.sub(" ", unicodedata.normalize("NFC", text))
    text = text.replace("[", "(").replace("]", ")")
    return re.sub(r"\s+", " ", text).strip()[:300]


def _fold(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def leaks(reply: str, system_prompt: str) -> list[str]:
    """Filtro de salida: términos prohibidos que no vienen de la guía actual."""
    r, allowed = _fold(reply), _fold(system_prompt)
    return [t for t in SPOILER_TERMS if t in r and t not in allowed]


def tidy(reply: str) -> str:
    reply = _ACTIONS.sub("", reply)
    reply = re.sub(r"\s+", " ", reply).strip().strip('"')
    return reply[:MAX_REPLY_CHARS].strip() or "..."


class Dialogue:
    def __init__(self, provider: Provider | None, timeout_s: float = 12.0, cache_size: int = 512):
        self.provider = provider
        self.timeout_s = timeout_s
        self._cache: OrderedDict[str, dict] = OrderedDict()
        self._cache_size = cache_size

    # ---------- memoria ----------

    @staticmethod
    def _memory(private: dict, wid: str) -> tuple[list[dict], str | None]:
        hist: list[dict] = private.setdefault("history", {}).setdefault(wid, [])
        recent = hist[-2 * HISTORY_TURNS:]
        older = hist[:-2 * HISTORY_TURNS]
        bits = []
        asked = [m["content"] for m in older if m["role"] == "user"][-5:]
        if asked:
            bits.append("antes te preguntó: " + "; ".join(a[:80] for a in asked))
        shown = private.setdefault("presented", {}).get(wid, [])
        if shown:
            names = ", ".join(_evidence_name(e) for e in shown)
            bits.append(f"ya te mostró: {names}")
        return recent, (". ".join(bits) + ".") if bits else None

    @staticmethod
    def remember(private: dict, wid: str, user: str, reply: str) -> None:
        hist = private.setdefault("history", {}).setdefault(wid, [])
        hist += [{"role": "user", "content": user}, {"role": "assistant", "content": reply}]
        del hist[:-40]  # tope de almacenamiento; al prompt solo van los últimos 6 turnos

    @staticmethod
    def forget_last(private: dict, wid: str) -> None:
        hist = private.setdefault("history", {}).setdefault(wid, [])
        del hist[-2:]

    # ---------- respaldo ----------

    @staticmethod
    def fallback(private: dict, wid: str, emotion: str = "nervioso") -> dict:
        lines = data.witness_secret(wid).get("fallback") or ["..."]
        counters = private.setdefault("fallback_i", {})
        i = counters.get(wid, 0)
        counters[wid] = i + 1
        return {"reply": lines[i % len(lines)], "emotion": emotion,
                "trust_delta": 0, "fear_delta": 0}

    # ---------- llamada al modelo ----------

    def _cache_key(self, *parts: str) -> str:
        return hashlib.sha1("\x1f".join(parts).encode("utf-8")).hexdigest()

    async def _generate(self, wid: str, level: str, trust: int, fear: int, private: dict,
                        user_msg: str, situation: str | None, cache_parts: tuple[str, ...]
                        ) -> tuple[dict | None, str]:
        """Devuelve (respuesta normalizada o None, source)."""
        history, summary = self._memory(private, wid)
        last = history[-1]["content"] if history else ""
        key = self._cache_key(wid, level, *cache_parts, _fold(user_msg), last)
        if key in self._cache:
            self._cache.move_to_end(key)
            return dict(self._cache[key]), "cache"
        if self.provider is None:
            return None, "fallback"

        msgs = witness_messages(wid, level, trust, fear, history, user_msg, situation, summary)
        # Lo que el testigo puede saber: su prompt y lo que le dijo el investigador.
        known = "\n".join([msgs[0]["content"]] + [m["content"] for m in msgs[1:] if m["role"] == "user"])
        t0 = time.monotonic()
        talk = await self._ask(wid, msgs, self.timeout_s)
        if talk is None:
            return None, "fallback"
        found = invented(talk["reply"], known)
        if found:
            log.info("Detalles inventados por %s (%s): %s", wid, "; ".join(found), talk["reply"])
            first = talk
            left = self.timeout_s - (time.monotonic() - t0)
            retry = None
            if left > 2.0:
                fix = (f"{user_msg}\n\n[Nota para ti, no la repitas: no menciones {', '.join(found)}; "
                       "eso no lo sabes. Si no sabes algo, dilo en personaje.]")
                retry = await self._ask(wid, msgs[:-1] + [{"role": "user", "content": fix}], left)
            if retry is not None and not invented(retry["reply"], known):
                talk = retry
            else:
                # Insiste: se quedan solo las frases sin detalles inventados.
                base = retry or first
                kept = drop_invented_sentences(base["reply"], known) or \
                    drop_invented_sentences(first["reply"], known)
                if not kept:
                    log.warning("Todo inventado para %s; frase de respaldo", wid)
                    return None, "fallback"
                talk = {**base, "reply": kept}
        self._cache[key] = dict(talk)
        if len(self._cache) > self._cache_size:
            self._cache.popitem(last=False)
        return talk, "llm"

    async def _ask(self, wid: str, msgs: list[dict], timeout: float) -> dict | None:
        """Una llamada al modelo con normalización y filtro de spoilers. None si no sirve."""
        try:
            res = await asyncio.wait_for(
                self.provider.chat(msgs, schema=TALK_SCHEMA, temperature=TEMPERATURE), timeout=timeout)
        except Exception as exc:  # red, cuota, tiempo: el juego sigue con respaldo
            log.warning("LLM falló para %s: %s", wid, exc or type(exc).__name__)
            return None
        talk = normalize_talk(res.data)
        if talk is None:
            log.warning("LLM devolvió algo inutilizable para %s: %.120s", wid, res.text)
            return None
        talk["reply"] = tidy(talk["reply"])
        bad = leaks(talk["reply"], msgs[0]["content"])
        if bad:
            log.warning("Filtro de salida (%s) para %s: %s", ", ".join(bad), wid, talk["reply"])
            return None
        return talk

    # ---------- casos de uso ----------

    async def talk(self, npc: dict, private: dict, text: str) -> tuple[dict, str]:
        wid = npc["id"]
        talk, source = await self._generate(wid, npc["level"], npc["trust"], npc["fear"],
                                            private, text, None, ("talk",))
        if talk is None:
            talk = self.fallback(private, wid)
        self.remember(private, wid, text, talk["reply"])
        return talk, source

    async def react(self, npc: dict, private: dict, situation: str, user_msg: str,
                    cache_tag: str) -> tuple[dict, str]:
        """Reacción a una presentación de evidencia o a una confesión por confianza.
        npc ya trae el nivel resultante, así que el modelo usa la guía nueva."""
        wid = npc["id"]
        talk, source = await self._generate(wid, npc["level"], npc["trust"], npc["fear"],
                                            private, user_msg, situation, (cache_tag,))
        if talk is None:
            talk = self.fallback(private, wid)
        self.remember(private, wid, user_msg, talk["reply"])
        return talk, source


def _evidence_name(eid: str) -> str:
    for e in data.evidence()["evidence"]:
        if e["id"] == eid:
            return e["name"]
    return eid


def evidence_message(eid: str) -> str:
    for e in data.evidence()["evidence"]:
        if e["id"] == eid:
            return f"[El investigador te muestra: {e['name']}. {e['description']}]"
    return f"[El investigador te muestra: {eid}]"


SITUATIONS = {
    "confront": ("Lo que el investigador te muestra deja al descubierto tu mentira. Ya no "
                 "puedes sostenerla: reacciona y admite solo lo que dice tu guía."),
    "confess": ("Ya no puedes callar más. Cuenta lo que sabes, como dice tu guía, con "
                "el miedo que sientes."),
    "repeat": "Eso ya lo hablaron antes. Contesta corto, sin agregar nada nuevo.",
    "unrelated": ("Lo que te muestra no tiene que ver contigo ni con lo que viste. "
                  "Responde con desconfianza o fastidio, sin revelar nada nuevo."),
    "trust_confess": ("Has decidido confiar en el investigador. Cuéntale lo que sabes, "
                      "como dice tu guía."),
}


__all__ = ["Dialogue", "SITUATIONS", "clean_player_text", "evidence_message", "leaks",
           "witness_system_prompt"]
