"""Los 4 testigos restantes (Beto, Pilo, Chente, Chepe) en la partida.

Cada uno se confronta y confiesa con las evidencias de case_secret.json, igual que los
del MVP. Sus pistas apuntan a otras leyendas (pistas falsas) y no son necesarias para
ningún final. Con WITNESSES=mvp no están en la partida.
"""
from __future__ import annotations

from .conftest import FakeProvider, assert_valid
from .test_b3 import examine, new, present, talk


def _ids(body) -> list[str]:
    return [d["id"] for d in body["new_deductions"]]


def test_beto_vendio_la_moneda(client):
    sid = new(client)
    assert examine(client, sid, "carreton_beto").json()["new_evidence"] == ["recibo_coleccionista"]
    r = present(client, sid, "beto", "recibo_coleccionista").json()
    assert_valid("present_response", r)
    assert r["contradiction"] and r["level"] == "confrontada" and _ids(r) == ["d_moneda_vendida"]
    examine(client, sid, "mesa_cantina")
    r = present(client, sid, "beto", "perfume_floral").json()
    assert r["level"] == "confesion" and _ids(r) == ["d_descarnada_busca"]
    assert r["new_evidence"] == ["moneda_plata"] and "moneda_plata" in r["state"]["evidence"]


def test_pilo_y_el_nino_del_sombrero(client):
    sid = new(client)
    examine(client, sid, "asiento_bus")
    r = present(client, sid, "pilo", "moneda_agujero").json()
    assert r["level"] == "confrontada" and _ids(r) == ["d_cipitio_observa"]
    examine(client, sid, "suelo_plaza")
    r = present(client, sid, "pilo", "huellas_invertidas").json()
    assert r["level"] == "confesion" and _ids(r) == ["d_huellas_alejan"]


def test_chente_estaba_despierto(client):
    sid = new(client)
    examine(client, sid, "libreta_cantinero")
    r = present(client, sid, "chente", "cuenta_cantina").json()
    assert r["level"] == "confrontada" and _ids(r) == ["d_cadejo_protege"]


def test_chepe_necesita_la_quebrada_del_acto_2(client):
    sid = new(client)
    # Antes del acto 2 la quebrada está cerrada.
    assert examine(client, sid, "piedras_quebrada").status_code != 200
    # Dos deducciones (las de Beto) abren el acto 2.
    examine(client, sid, "carreton_beto")
    present(client, sid, "beto", "recibo_coleccionista")
    examine(client, sid, "mesa_cantina")
    r = present(client, sid, "beto", "perfume_floral").json()
    assert r["state"]["act"] == 2 and "quebrada" in r["state"]["unlocked_locations"]
    examine(client, sid, "piedras_quebrada")
    r = present(client, sid, "chepe", "boleto_microbus").json()
    assert r["level"] == "confrontada" and _ids(r) == ["d_viaje_clandestino"]
    examine(client, sid, "orilla_quebrada")
    r = present(client, sid, "chepe", "cabello_negro").json()
    assert r["level"] == "confesion" and _ids(r) == ["d_siguanaba_quebrada"]


def test_hablar_con_un_testigo_extra(make_client):
    c = make_client(FakeProvider(reply={"reply": "¡Suban, suban, hay campo atrás!",
                                        "emotion": "nervioso", "trust_delta": 1, "fear_delta": 0}))
    sid = new(c)
    r = talk(c, sid, "pilo").json()
    assert_valid("talk_response", r)
    assert r["reply"] and r["level"] == "inicial" and r["trust"] == 6
    pilo = next(n for n in r["state"]["npcs"] if n["id"] == "pilo")
    assert pilo["met"] is True


def test_en_modo_mvp_no_estan(make_client):
    c = make_client(witnesses="mvp")
    sid = new(c)
    r = talk(c, sid, "beto")
    assert r.status_code == 400 and r.json()["error"] == "bad_npc"
