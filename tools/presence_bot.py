"""Jugador de prueba para la presencia compartida (rama experimental).

Se une a una partida abierta (la primera del lobby, o --session ID) como otro jugador y
camina en círculo en el pueblo, cerca de donde empieza la partida, para probar sin una
segunda computadora. Empieza tú una partida (Nueva partida) y luego corre:

    .venv\\Scripts\\python tools\\presence_bot.py [--api http://127.0.0.1:8000] [--name "Fae (bot)"] [--seconds 60]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import math

import urllib.request

import websockets

TILE = 16
START = (31 * TILE + 8, 24 * TILE + 14)  # TownLayout.PLAYER_START en coordenadas del mundo


def facing(dx: float, dy: float) -> str:
    if abs(dx) > abs(dy):
        return "right" if dx > 0 else "left"
    return "down" if dy > 0 else "up"


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://127.0.0.1:8000")
    ap.add_argument("--name", default="Fae (bot)")
    ap.add_argument("--seconds", type=float, default=60.0)
    ap.add_argument("--radius", type=float, default=36.0)
    ap.add_argument("--session", default="", help="id de la partida (por defecto, la primera del lobby)")
    args = ap.parse_args()
    sid = args.session
    if not sid:
        with urllib.request.urlopen(args.api.rstrip("/") + "/lobby", timeout=10) as r:
            games = json.loads(r.read())["games"]
        if not games:
            raise SystemExit("No hay partidas abiertas: empieza una en el juego (Nueva partida) y vuelve a intentar.")
        sid = games[0]["session_id"]
        print(f"me uno a la partida de {games[0]['host']} ({sid})")
    url = args.api.replace("https://", "wss://").replace("http://", "ws://").rstrip("/") + "/ws/presence"
    async with websockets.connect(url) as ws:
        await ws.send(json.dumps({"t": "hello", "name": args.name, "s": sid}))
        print("conectado:", json.loads(await ws.recv()), "·", json.loads(await ws.recv()))

        async def listen() -> None:
            async for raw in ws:
                m = json.loads(raw)
                if m.get("t") in ("pos", "leave"):
                    who = m.get("name", m.get("id"))
                    print(f"  {m['t']}: {who} {m.get('scene', '')} ({m.get('x', '')}, {m.get('y', '')})")

        listener = asyncio.create_task(listen())
        t, last = 0.0, START
        while t < args.seconds:
            a = t * 0.9
            x = START[0] + 40 + args.radius * math.cos(a)
            y = START[1] - 10 + args.radius * 0.6 * math.sin(a)
            await ws.send(json.dumps({"t": "pos", "s": sid, "scene": "town", "x": round(x, 1), "y": round(y, 1),
                                      "f": facing(x - last[0], y - last[1]), "m": True}))
            last = (x, y)
            await asyncio.sleep(0.1)
            t += 0.1
        listener.cancel()
    print("bot desconectado")


if __name__ == "__main__":
    asyncio.run(main())
