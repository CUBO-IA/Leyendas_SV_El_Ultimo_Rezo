"""Detalles inventados: el detector (llm/grounding.py) y cómo Dialogue lo usa
(pide corrección, quita frases o usa la frase de respaldo)."""
from __future__ import annotations

import asyncio

from server.app.dialogue import Dialogue
from server.app.llm.grounding import drop_invented_sentences, invented, times_in
from server.app.llm.prompts import witness_system_prompt

from .conftest import FakeProvider

PILO = witness_system_prompt("pilo", "inicial", 5, 4)
ALCIDES = witness_system_prompt("alcides", "inicial", 3, 6)


def test_lee_horas_habladas_y_con_numeros():
    assert times_in("A las once y cuarenta y siete se fue la luz.") == {(11, 47)}
    assert times_in("a las doce y media cuando pasó") == {(12, 30)}
    assert times_in("a las doce menos cuarto") == {(11, 45)}
    assert times_in("dio la una.") == {(1, None)}
    assert (12, 10) in times_in("a las 12:10 pagó")
    assert times_in("cerca de medianoche") == {(12, None)}
    # No son horas.
    assert times_in("pidió las dos pupusas") == set()
    assert times_in("de las tres personas") == set()


def test_horas_inventadas():
    assert invented("Yo vi la carreta cuando dio la una.", ALCIDES) == ["la hora 1"]
    assert invented("La vi exactamente cuando dieron las doce.", ALCIDES) == []  # está en su guía
    assert invented("Como a las once se fue la luz.", ALCIDES) == []  # aproxima 11:47
    assert invented("Eran las doce y media.", PILO) == ["la hora 12:30"]


def test_nombres_inventados_y_gente_del_pueblo():
    found = invented("Venían Don Roque del molino y la señora María con su nieta.", PILO)
    assert any("Roque" in f for f in found) and any("María" in f for f in found)
    # La gente de la lista del pueblo sí se puede nombrar.
    assert invented("Pregúntele a Doña Chonita o al Agente Ramírez.", PILO) == []
    # Lo que dijo el investigador también cuenta como sabido.
    assert invented("¿Don Roque? No lo conozco.", PILO + "\n¿Vio a Don Roque?") == []
    # Mayúscula al inicio de frase no es un nombre.
    assert invented("Puchica. Fíjese que no me acuerdo.", PILO) == []


def test_quita_solo_la_frase_inventada():
    reply = "Yo vi la carreta cuando dio la una. Nunca dejé la caseta."
    assert drop_invented_sentences(reply, ALCIDES) == "Nunca dejé la caseta."
    assert drop_invented_sentences("Lo vio Don Roque.", ALCIDES) == ""


def test_el_prompt_lista_al_pueblo_sin_el_culpable():
    assert "Doña Chonita" in PILO and "Pupusería La Bendición" in PILO
    assert "La Siguanaba" in PILO and "Padre Sin Cabeza" not in PILO
    assert "Pilo" not in PILO.split("Gente del pueblo que conoces:")[1].split("\n")[0]


def _run(provider, npc_id="pilo", text="¿Quién iba en su bus?"):
    dlg = Dialogue(provider, timeout_s=10)
    npc = {"id": npc_id, "level": "inicial", "trust": 5, "fear": 4}
    return asyncio.run(dlg.talk(npc, {}, text))


def _seq(*replies):
    """Proveedor que devuelve las respuestas en orden (la última se repite)."""
    it = iter(replies)
    last = {}

    def reply(_msgs):
        nonlocal last
        last = next(it, last)
        return {"reply": last, "emotion": "nervioso", "trust_delta": 0, "fear_delta": 0}
    return FakeProvider(reply=reply)


def test_respuesta_limpia_una_sola_llamada():
    p = _seq("Fíjese que no me fijé quién subía.")
    talk, source = _run(p)
    assert talk["reply"] == "Fíjese que no me fijé quién subía." and source == "llm"
    assert len(p.calls) == 1


def test_inventa_y_se_corrige():
    p = _seq("Venía Don Roque del molino.", "Fíjese que no me acuerdo de quién venía.")
    talk, source = _run(p)
    assert talk["reply"] == "Fíjese que no me acuerdo de quién venía." and source == "llm"
    assert len(p.calls) == 2
    nota = p.calls[1][-1]["content"]
    assert "Roque" in nota and nota.startswith("¿Quién iba en su bus?")


def test_insiste_y_se_quita_la_frase():
    p = _seq("Venía Don Roque. El niño del sombrero se bajó.", "Venía Don Roque. Ya no me acuerdo.")
    talk, _ = _run(p)
    assert talk["reply"] == "Ya no me acuerdo."


def test_todo_inventado_usa_el_respaldo():
    p = _seq("Venía Don Roque.", "Venía la señora María.")
    talk, source = _run(p)
    assert source == "fallback" and "Roque" not in talk["reply"] and "María" not in talk["reply"]
