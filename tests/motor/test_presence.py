"""Experimental: partidas compartidas por WebSocket (/ws/presence) y /lobby."""
from __future__ import annotations

import asyncio

from server.app.presence import PresenceHub, clean_name, clean_pos, clean_session


def test_limpia_nombre_partida_y_posicion():
    assert clean_name("Fer<script>") == "Ferscript" and clean_name("Fae (bot)") == "Fae (bot)"
    assert clean_name("") == "Investigador" and len(clean_name("x" * 99)) == 20
    assert clean_session("ab12cd34ef56") == "ab12cd34ef56" and clean_session("../x") == ""
    assert clean_pos({"scene": "town", "x": 10, "y": "20", "f": "left", "m": 1}) == \
        {"scene": "town", "x": 10.0, "y": 20.0, "f": "left", "m": True}
    assert clean_pos({"scene": "../etc", "x": 1, "y": 1}) is None
    assert clean_pos({"scene": "town", "x": "nada", "y": 1}) is None
    assert clean_pos({"scene": "town", "x": 1e9, "y": 0, "f": "raro"})["x"] == 10_000.0


def _hello(ws, name, sid):
    ws.send_json({"t": "hello", "name": name, "s": sid})
    pid = ws.receive_json()["id"]
    state = ws.receive_json()
    assert state["t"] == "state"
    return pid, state


def test_misma_partida_se_ven_otra_partida_no(client):
    s1 = client.post("/session", json={}).json()["session_id"]
    s2 = client.post("/session", json={}).json()["session_id"]
    with client.websocket_connect("/ws/presence") as a, client.websocket_connect("/ws/presence") as c:
        _, st = _hello(a, "Fer", s1)
        assert st["players"] == []
        _hello(c, "Otro", s2)  # otra partida
        with client.websocket_connect("/ws/presence") as b:
            b_id, st = _hello(b, "Fae", s1)
            assert [p["name"] for p in st["players"]] == ["Fer"]
            a.send_json({"t": "pos", "s": s1, "scene": "town", "x": 500, "y": 380, "f": "right", "m": True})
            seen = b.receive_json()
            assert seen["t"] == "pos" and seen["name"] == "Fer" and seen["x"] == 500.0 and seen["s"] == s1
            # Mensajes malos se ignoran.
            a.send_text("esto no es json")
            a.send_json({"t": "pos", "s": s1, "scene": "NO VALE", "x": 1, "y": 1})
            a.send_json({"t": "pos", "s": s1, "scene": "iglesia", "x": 1, "y": 2})
            assert b.receive_json()["scene"] == "iglesia"
            # El lobby lista la partida con su anfitrión, acto y hora.
            games = client.get("/lobby").json()["games"]
            g1 = next(g for g in games if g["session_id"] == s1)
            assert g1["host"] == "Fer" and g1["players"] == ["Fer", "Fae"] and g1["act"] == 1 and g1["clock"] == "23:47"
            # Una ruta que cambia la partida avisa a los dos (y no a la otra partida).
            client.post("/examine", json={"session_id": s1, "object_id": "tablero_electrico"})
            assert a.receive_json() == {"t": "world", "s": s1}
            assert b.receive_json() == {"t": "world", "s": s1}
        assert a.receive_json() == {"t": "leave", "id": b_id}
        # C (otra partida) no recibió nada de s1: lo siguiente que le llega es lo suyo.
        client.post("/examine", json={"session_id": s2, "object_id": "tablero_electrico"})
        assert c.receive_json() == {"t": "world", "s": s2}


class _FakeWS:
    def __init__(self):
        self.sent = []

    async def send_text(self, text):
        import json
        self.sent.append(json.loads(text))


def test_el_final_llega_a_toda_la_partida():
    hub = PresenceHub()
    a, b, c = _FakeWS(), _FakeWS(), _FakeWS()
    hub.players = {
        "a": {"ws": a, "name": "Fer", "s": "s1", "scene": "town", "x": 0, "y": 0, "f": "down", "m": False, "joined": 1},
        "b": {"ws": b, "name": "Fae", "s": "s1", "scene": "town", "x": 0, "y": 0, "f": "down", "m": False, "joined": 2},
        "c": {"ws": c, "name": "Otro", "s": "s2", "scene": "town", "x": 0, "y": 0, "f": "down", "m": False, "joined": 3},
    }
    ending = {"ending_id": "verdadero", "title": "La última confesión"}
    asyncio.run(hub.notify_ended("s1", ending))
    assert a.sent == b.sent == [{"t": "ended", "s": "s1", "ending": ending}] and c.sent == []
    assert [g["host"] for g in hub.lobby()] == ["Fer", "Otro"]
