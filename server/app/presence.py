"""Presencia compartida (rama experimental): los jugadores conectados al mismo motor
se ven moverse por el mapa en tiempo real. Cada uno sigue con su propia partida; aquí
solo viaja dónde está cada quien (escena, posición, hacia dónde mira), nunca nada del caso.

Protocolo (JSON por WebSocket en /ws/presence):
  cliente -> motor   {"t": "hello", "name": "Fer"}                       (primero)
                     {"t": "pos", "scene": "town", "x": 1.0, "y": 2.0, "f": "down", "m": true}
  motor -> cliente   {"t": "welcome", "id": "a1b2"}
                     {"t": "state", "players": [ {id, name, scene, x, y, f, m}, ... ]}  (al entrar)
                     {"t": "pos", "id": ..., "name": ..., "scene": ..., "x", "y", "f", "m"}
                     {"t": "leave", "id": ...}
"""
from __future__ import annotations

import asyncio
import json
import logging
import re
import uuid

from fastapi import WebSocket, WebSocketDisconnect

log = logging.getLogger("leyendas.presence")

MAX_MESSAGE = 512
MAX_PLAYERS = 16
FACINGS = {"down", "up", "left", "right"}
_SCENE = re.compile(r"^[a-z_]{1,32}$")
_NAME_BAD = re.compile(r"[^\w áéíóúüñÁÉÍÓÚÜÑ.()\-]")


def clean_name(raw: object) -> str:
    name = _NAME_BAD.sub("", str(raw or ""))[:20].strip()
    return name or "Investigador"


def clean_pos(msg: dict) -> dict | None:
    """Valida un mensaje de posición. None si no sirve."""
    scene = str(msg.get("scene", ""))
    if not _SCENE.match(scene):
        return None
    try:
        x = max(-10_000.0, min(10_000.0, float(msg.get("x", 0))))
        y = max(-10_000.0, min(10_000.0, float(msg.get("y", 0))))
    except (TypeError, ValueError):
        return None
    f = msg.get("f") if msg.get("f") in FACINGS else "down"
    return {"scene": scene, "x": round(x, 1), "y": round(y, 1), "f": f, "m": bool(msg.get("m", False))}


class PresenceHub:
    def __init__(self) -> None:
        self.players: dict[str, dict] = {}  # id -> {"ws", "name", "scene", "x", "y", "f", "m"}
        self._lock = asyncio.Lock()

    def public(self, pid: str) -> dict:
        p = self.players[pid]
        return {"id": pid, **{k: p[k] for k in ("name", "scene", "x", "y", "f", "m")}}

    async def _send(self, ws: WebSocket, data: dict) -> None:
        try:
            await ws.send_text(json.dumps(data, ensure_ascii=False))
        except Exception:  # se desconectó a medio envío: lo limpia su propio handler
            pass

    async def broadcast(self, data: dict, except_id: str | None = None) -> None:
        targets = [p["ws"] for pid, p in list(self.players.items()) if pid != except_id]
        await asyncio.gather(*(self._send(ws, data) for ws in targets))

    async def handle(self, ws: WebSocket) -> None:
        await ws.accept()
        if len(self.players) >= MAX_PLAYERS:
            await ws.close(code=1013)
            return
        pid = uuid.uuid4().hex[:8]
        try:
            hello = json.loads((await ws.receive_text())[:MAX_MESSAGE])
            name = clean_name(hello.get("name") if isinstance(hello, dict) else "")
        except (WebSocketDisconnect, ValueError):
            return
        async with self._lock:
            others = [self.public(o) for o in self.players]
            self.players[pid] = {"ws": ws, "name": name, "scene": "", "x": 0.0, "y": 0.0, "f": "down", "m": False}
        log.info("Presencia: entra %s (%s); en línea: %d", name, pid, len(self.players))
        await self._send(ws, {"t": "welcome", "id": pid})
        await self._send(ws, {"t": "state", "players": others})
        try:
            while True:
                text = await ws.receive_text()
                if len(text) > MAX_MESSAGE:
                    continue
                try:
                    msg = json.loads(text)
                except ValueError:
                    continue
                if not isinstance(msg, dict) or msg.get("t") != "pos":
                    continue
                pos = clean_pos(msg)
                if pos is None:
                    continue
                self.players[pid].update(pos)
                await self.broadcast({"t": "pos", **self.public(pid)}, except_id=pid)
        except WebSocketDisconnect:
            pass
        finally:
            async with self._lock:
                self.players.pop(pid, None)
            log.info("Presencia: sale %s (%s); en línea: %d", name, pid, len(self.players))
            await self.broadcast({"t": "leave", "id": pid})
