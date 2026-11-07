"""Partidas compartidas (rama experimental): varios jugadores se unen a la MISMA partida y
se ven moverse por el mapa en tiempo real. Por aquí solo viaja dónde está cada quien y en
qué partida juega; el estado del caso sigue en las rutas de siempre (/session, /talk...).
Cuando una ruta cambia la partida, el motor avisa a todos los de esa partida para que la
vuelvan a leer, y si alguien acusa, les manda el final.

Protocolo (JSON por WebSocket en /ws/presence):
  cliente -> motor   {"t": "hello", "name": "Fer", "s": "<session_id>"}            (primero)
                     {"t": "pos", "s": "<session_id>", "scene": "town", "x": 1.0, "y": 2.0, "f": "down", "m": true}
  motor -> cliente   {"t": "welcome", "id": "a1b2"}
                     {"t": "state", "players": [ {id, name, s, scene, x, y, f, m}, ... ]}   (los de tu partida)
                     {"t": "pos", "id", "name", "s", "scene", "x", "y", "f", "m"}
                     {"t": "leave", "id": ...}
                     {"t": "world", "s": ...}            la partida cambió: vuelve a leer /session
                     {"t": "ended", "s": ..., "ending": {...}}   alguien acusó: este es el final
GET /lobby -> las partidas que tienen jugadores conectados (para "Unirse a una partida").
"""
from __future__ import annotations

import asyncio
import json
import logging
import re
import secrets
import uuid

from fastapi import WebSocket, WebSocketDisconnect

log = logging.getLogger("leyendas.presence")

MAX_MESSAGE = 512
MAX_PLAYERS = 16
FACINGS = {"down", "up", "left", "right"}
_SCENE = re.compile(r"^[a-z_]{1,32}$")
_SESSION = re.compile(r"^[A-Za-z0-9_-]{0,64}$")
_NAME_BAD = re.compile(r"[^\w áéíóúüñÁÉÍÓÚÜÑ.()\-]")


def clean_name(raw: object) -> str:
    name = _NAME_BAD.sub("", str(raw or ""))[:20].strip()
    return name or "Investigador"


def clean_session(raw: object) -> str:
    s = str(raw or "")
    return s if _SESSION.match(s) else ""


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
    def __init__(self, access_code: str = "") -> None:
        self.access_code = access_code  # si no está vacío, el "hello" debe traerlo
        # id -> {"ws", "name", "s", "scene", "x", "y", "f", "m", "joined"}
        self.players: dict[str, dict] = {}
        self._lock = asyncio.Lock()
        self._order = 0

    def public(self, pid: str) -> dict:
        p = self.players[pid]
        return {"id": pid, **{k: p[k] for k in ("name", "s", "scene", "x", "y", "f", "m")}}

    def in_session(self, sid: str, except_id: str | None = None) -> list[str]:
        return [pid for pid, p in list(self.players.items()) if sid and p["s"] == sid and pid != except_id]

    async def _send(self, ws: WebSocket, data: dict) -> None:
        try:
            await ws.send_text(json.dumps(data, ensure_ascii=False))
        except Exception:  # se desconectó a medio envío: lo limpia su propio handler
            pass

    async def to_session(self, sid: str, data: dict, except_id: str | None = None) -> None:
        targets = [self.players[pid]["ws"] for pid in self.in_session(sid, except_id) if pid in self.players]
        await asyncio.gather(*(self._send(ws, data) for ws in targets))

    async def notify_world(self, sid: str) -> None:
        """Una ruta cambió la partida: los que juegan en ella la vuelven a leer."""
        await self.to_session(sid, {"t": "world", "s": sid})

    async def notify_ended(self, sid: str, ending: dict) -> None:
        await self.to_session(sid, {"t": "ended", "s": sid, "ending": ending})

    def lobby(self) -> list[dict]:
        """Partidas con jugadores conectados; el anfitrión es quien entró primero."""
        games: dict[str, list[dict]] = {}
        for p in sorted(self.players.values(), key=lambda p: p["joined"]):
            if p["s"]:
                games.setdefault(p["s"], []).append(p)
        return [{"session_id": sid, "host": ps[0]["name"], "players": [p["name"] for p in ps]}
                for sid, ps in games.items()]

    async def _set_session(self, pid: str, sid: str) -> None:
        """Cambió de partida: se despide de la anterior y conoce a los de la nueva."""
        p = self.players[pid]
        old = p["s"]
        if old == sid:
            return
        p["s"] = sid
        if old:
            await self.to_session(old, {"t": "leave", "id": pid}, except_id=pid)
        await self._send(p["ws"], {"t": "state", "players": [self.public(o) for o in self.in_session(sid, pid)]})

    async def handle(self, ws: WebSocket) -> None:
        await ws.accept()
        if len(self.players) >= MAX_PLAYERS:
            await ws.close(code=1013)
            return
        pid = uuid.uuid4().hex[:8]
        try:
            hello = json.loads((await ws.receive_text())[:MAX_MESSAGE])
            if not isinstance(hello, dict):
                hello = {}
        except (WebSocketDisconnect, ValueError):
            return
        if self.access_code and not secrets.compare_digest(
                str(hello.get("code", "")).encode(), self.access_code.encode()):
            await ws.close(code=1008)  # sin el código de acceso no entra
            return
        name = clean_name(hello.get("name"))
        async with self._lock:
            self._order += 1
            self.players[pid] = {"ws": ws, "name": name, "s": "", "scene": "", "x": 0.0, "y": 0.0,
                                 "f": "down", "m": False, "joined": self._order}
        log.info("Presencia: entra %s (%s); en línea: %d", name, pid, len(self.players))
        await self._send(ws, {"t": "welcome", "id": pid})
        await self._set_session(pid, clean_session(hello.get("s")))
        if not self.players[pid]["s"]:
            await self._send(ws, {"t": "state", "players": []})
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
                if "s" in msg:
                    await self._set_session(pid, clean_session(msg.get("s")))
                self.players[pid].update(pos)
                await self.to_session(self.players[pid]["s"], {"t": "pos", **self.public(pid)}, except_id=pid)
        except WebSocketDisconnect:
            pass
        finally:
            async with self._lock:
                gone = self.players.pop(pid, None)
            log.info("Presencia: sale %s (%s); en línea: %d", name, pid, len(self.players))
            if gone and gone["s"]:
                await self.to_session(gone["s"], {"t": "leave", "id": pid})
