"""Experimental: presencia compartida por WebSocket (/ws/presence)."""
from __future__ import annotations

from server.app.presence import clean_name, clean_pos


def test_limpia_nombre_y_posicion():
    assert clean_name("Fer<script>") == "Ferscript" and clean_name("Fae (bot)") == "Fae (bot)"
    assert clean_name("") == "Investigador" and len(clean_name("x" * 99)) == 20
    assert clean_pos({"scene": "town", "x": 10, "y": "20", "f": "left", "m": 1}) == \
        {"scene": "town", "x": 10.0, "y": 20.0, "f": "left", "m": True}
    assert clean_pos({"scene": "../etc", "x": 1, "y": 1}) is None
    assert clean_pos({"scene": "town", "x": "nada", "y": 1}) is None
    assert clean_pos({"scene": "town", "x": 1e9, "y": 0, "f": "raro"})["x"] == 10_000.0


def test_dos_jugadores_se_ven(client):
    with client.websocket_connect("/ws/presence") as a:
        a.send_json({"t": "hello", "name": "Fer"})
        assert a.receive_json()["t"] == "welcome"
        assert a.receive_json() == {"t": "state", "players": []}
        with client.websocket_connect("/ws/presence") as b:
            b.send_json({"t": "hello", "name": "Fae"})
            b_id = b.receive_json()["id"]
            state = b.receive_json()
            assert [p["name"] for p in state["players"]] == ["Fer"]
            a.send_json({"t": "pos", "scene": "town", "x": 500, "y": 380, "f": "right", "m": True})
            seen = b.receive_json()
            assert seen["t"] == "pos" and seen["name"] == "Fer" and seen["x"] == 500.0 and seen["m"] is True
            # Mensajes malos se ignoran: lo siguiente que llega es la posición válida.
            a.send_text("esto no es json")
            a.send_json({"t": "pos", "scene": "NO VALE", "x": 1, "y": 1})
            a.send_json({"t": "pos", "scene": "iglesia", "x": 1, "y": 2})
            assert b.receive_json()["scene"] == "iglesia"
        # B se fue: A recibe el aviso.
        left = a.receive_json()
        assert left == {"t": "leave", "id": b_id}
