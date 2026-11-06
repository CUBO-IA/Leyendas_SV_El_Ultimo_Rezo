"""B1: el proveedor de NVIDIA elige el modo de JSON que acepta el modelo (sin red)."""
from __future__ import annotations

import asyncio
import json

import httpx

from server.app.config import Settings
from server.app.llm.prompts import TALK_SCHEMA
from server.app.llm.provider import NvidiaProvider

OK = {"choices": [{"message": {"content": '{"reply": "Buenas", "emotion": "neutral", '
                                          '"trust_delta": 0, "fear_delta": 0}'}}]}


def _mode(body: dict) -> str:
    if "nvext" in body:
        return "guided"
    rf = body.get("response_format", {}).get("type")
    return rf or "plain"


def _provider(accepted: set[str], seen: list[str]) -> NvidiaProvider:
    def handler(request: httpx.Request) -> httpx.Response:
        mode = _mode(json.loads(request.content))
        seen.append(mode)
        # Como la API real: una petición sin restricción de JSON siempre se acepta.
        if mode in accepted or mode == "plain":
            return httpx.Response(200, json=OK)
        return httpx.Response(400, json={"message": f"unknown field for {mode}"})

    settings = Settings(llm_provider="nvidia", nvidia_api_key="test")
    return NvidiaProvider(settings, transport=httpx.MockTransport(handler))


def test_usa_json_schema_cuando_se_acepta():
    seen: list[str] = []
    p = _provider({"json_schema", "json_object"}, seen)
    res = asyncio.run(p.chat([{"role": "user", "content": "hola"}], schema=TALK_SCHEMA))
    assert res.data["reply"] == "Buenas" and seen == ["json_schema"]


def test_cae_al_siguiente_modo_y_lo_recuerda():
    seen: list[str] = []
    p = _provider({"json_object"}, seen)

    async def go():
        await p.warmup()  # sin esquema: no debe fijar el modo
        await p.chat([{"role": "user", "content": "a"}], schema=TALK_SCHEMA)
        await p.chat([{"role": "user", "content": "b"}], schema=TALK_SCHEMA)

    asyncio.run(go())
    assert seen == ["plain", "json_schema", "guided", "json_object", "json_object"]
