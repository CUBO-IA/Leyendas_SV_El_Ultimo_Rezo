"""B1: /health, /session y forma de los errores. Sin red: usa FakeProvider."""
from __future__ import annotations

import time

from server.app import data
from server.app.game import DEMO_EVIDENCE

from .conftest import FakeProvider, assert_valid


def _wait_warm(client, timeout=2.0):
    end = time.time() + timeout
    while time.time() < end:
        body = client.get("/health").json()
        if body["warm"]:
            return body
        time.sleep(0.02)
    return body


def test_health_ok_cuando_el_modelo_calienta(client):
    body = _wait_warm(client)
    assert_valid("health_response", body)
    assert body == {"status": "ok", "model": "fake-model", "warm": True,
                    "tts": False, "stt": False, "demo_mode": False}


def test_health_degradado_si_falla_el_calentamiento(make_client):
    c = make_client(FakeProvider(fail_warmup=True))
    time.sleep(0.1)
    body = c.get("/health").json()
    assert_valid("health_response", body)
    assert body["status"] == "degraded" and body["warm"] is False


def test_nueva_sesion_sin_cuerpo(client):
    r = client.post("/session")
    assert r.status_code == 200
    ws = r.json()
    assert_valid("world_state", ws)
    assert ws["act"] == 1 and ws["clock"] == "23:47" and ws["evidence"] == []
    assert [n["id"] for n in ws["npcs"]] == data.active_witnesses()
    for n in ws["npcs"]:
        start = data.witness_secret(n["id"])["start"]
        assert (n["trust"], n["fear"], n["level"], n["met"]) == (
            start["trust"], start["fear"], "inicial", False)
    assert "demo" not in ws


def test_nueva_sesion_igual_a_la_fixture_salvo_el_id(client):
    import json
    from .conftest import ROOT
    fixture = json.loads((ROOT / "contract/fixtures/world_state__nueva_partida.json")
                         .read_text(encoding="utf-8"))
    ws = client.post("/session", json={"player_name": "Investigador"}).json()
    ws["session_id"] = fixture["session_id"]
    assert ws == fixture


def test_sesion_demo(client):
    ws = client.post("/session", json={"demo": True}).json()
    assert_valid("world_state", ws)
    assert ws["demo"] is True and ws["evidence"] == DEMO_EVIDENCE
    evidence_ids = {e["id"] for e in data.evidence()["evidence"]}
    assert set(DEMO_EVIDENCE) <= evidence_ids


def test_demo_mode_global(make_client):
    c = make_client(demo_mode=True)
    assert c.post("/session").json()["demo"] is True
    assert c.get("/health").json()["demo_mode"] is True


def test_get_sesion_y_persistencia(make_client):
    c1 = make_client()
    ws = c1.post("/session").json()
    assert c1.get(f"/session/{ws['session_id']}").json() == ws
    # Otra instancia del motor con la misma base de datos ve la misma partida.
    c2 = make_client()
    assert c2.get(f"/session/{ws['session_id']}").json() == ws


def test_sesion_inexistente(client):
    r = client.get("/session/demo-9999")
    assert r.status_code == 404
    assert_valid("api_error", r.json())
    assert r.json()["error"] == "session_not_found"


def test_peticion_invalida_da_api_error(client):
    for bad in ({"player_name": "x" * 41}, {"color": "rojo"}, {"demo": "tal vez"}):
        r = client.post("/session", json=bad)
        assert r.status_code == 400, bad
        assert_valid("api_error", r.json())
        assert r.json()["error"] == "bad_request"


def test_ruta_desconocida_da_api_error(client):
    r = client.get("/no-existe")
    assert r.status_code == 404
    assert_valid("api_error", r.json())


def test_world_state_no_lleva_secretos(client):
    text = client.post("/session").text
    secret = data.secret_case()
    for word in [secret["solution"]["culprit"], "truth_behind_lie", "guide", "culprit"]:
        assert word not in text
