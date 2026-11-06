"""B1: parseo de la salida del modelo y prompt del testigo (sin red)."""
from __future__ import annotations

from server.app import data
from server.app.llm.prompts import normalize_talk, witness_messages, witness_system_prompt
from server.app.llm.provider import parse_json


def test_parse_json_tolera_think_y_cercas():
    assert parse_json('{"a": 1}') == {"a": 1}
    assert parse_json('<think>mmm</think>\n```json\n{"a": 2}\n```') == {"a": 2}
    assert parse_json('Claro: {"a": 3} listo') == {"a": 3}
    assert parse_json("no hay json") is None
    assert parse_json("[1, 2]") is None


def test_normalize_talk_recorta_y_valida():
    out = normalize_talk({"reply": "Uno. Dos. Tres. Cuatro.", "emotion": "furioso",
                          "trust_delta": 9, "fear_delta": "-5"})
    assert out == {"reply": "Uno. Dos. Tres.", "emotion": "neutral",
                   "trust_delta": 2, "fear_delta": -2}
    assert normalize_talk({"reply": "  "}) is None
    keep = "Está bueno, pues... ya se habían ido. No diga nada. Esa cosa regresa."
    assert normalize_talk({"reply": keep})["reply"] == keep
    assert normalize_talk(None) is None


def test_prompt_solo_lleva_la_guia_del_nivel_actual():
    for wid in data.active_witnesses():
        sec = data.witness_secret(wid)
        prompt = witness_system_prompt(wid, "inicial", 4, 3)
        assert sec["guide"]["inicial"] in prompt
        assert sec["guide"]["confrontada"] not in prompt
        assert sec["guide"]["confesion"] not in prompt
        assert sec["truth_behind_lie"] not in prompt
        assert data.secret_case()["solution"]["culprit"] not in prompt


def test_witness_messages_orden():
    msgs = witness_messages("chonita", "inicial", 4, 3,
                            [{"role": "user", "content": "Hola"},
                             {"role": "assistant", "content": "Buenas"}], "¿Qué vio?")
    assert [m["role"] for m in msgs] == ["system", "user", "assistant", "user"]
    assert msgs[-1]["content"] == "¿Qué vio?"
