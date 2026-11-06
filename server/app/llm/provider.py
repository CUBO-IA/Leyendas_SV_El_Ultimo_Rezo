"""Proveedores de diálogo: Ollama local o la API de NVIDIA (compatible con OpenAI).

Uso:  result = await provider.chat(messages, schema=TALK_SCHEMA)
`result.data` trae el JSON ya parseado (o None si el modelo no devolvió JSON válido);
quien llama decide el respaldo. El modelo solo redacta: las reglas viven en el código.
"""
from __future__ import annotations

import asyncio
import json
import re
import time
from dataclasses import dataclass
from typing import Any, Protocol

import httpx

from ..config import Settings

Message = dict[str, str]


class LLMError(RuntimeError):
    """Fallo de red, de autenticación o respuesta inutilizable del proveedor."""


@dataclass
class ChatResult:
    text: str
    data: dict | None
    latency_s: float
    provider: str
    model: str


class Provider(Protocol):
    name: str
    model: str

    async def chat(self, messages: list[Message], schema: dict | None = None,
                   max_tokens: int = 220, temperature: float = 0.7) -> ChatResult: ...

    async def warmup(self) -> None: ...

    async def aclose(self) -> None: ...


_THINK = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)
_FENCE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)


def parse_json(text: str) -> dict | None:
    """Extrae un objeto JSON aunque venga con <think>, cercas de código o texto alrededor."""
    if not text:
        return None
    cleaned = _THINK.sub("", text).strip()
    cleaned = _FENCE.sub("", cleaned).strip()
    for candidate in (cleaned, cleaned[cleaned.find("{"): cleaned.rfind("}") + 1]):
        if not candidate:
            continue
        try:
            value = json.loads(candidate)
        except (json.JSONDecodeError, ValueError):
            continue
        if isinstance(value, dict):
            return value
    return None


class OllamaProvider:
    name = "ollama"

    def __init__(self, settings: Settings):
        self.model = settings.llm_model
        self._url = settings.ollama_url
        self._client = httpx.AsyncClient(timeout=settings.llm_timeout_s)

    async def chat(self, messages, schema=None, max_tokens=220, temperature=0.7) -> ChatResult:
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "think": False,
            "keep_alive": -1,  # el modelo se queda cargado en memoria
            "options": {"temperature": temperature, "num_predict": max_tokens},
        }
        if schema:
            payload["format"] = schema
        t0 = time.perf_counter()
        try:
            r = await self._client.post(f"{self._url}/api/chat", json=payload)
            r.raise_for_status()
        except httpx.HTTPError as exc:
            raise LLMError(f"Ollama no respondió: {exc}") from exc
        text = r.json().get("message", {}).get("content", "")
        return ChatResult(text, parse_json(text) if schema else None,
                          time.perf_counter() - t0, self.name, self.model)

    async def warmup(self) -> None:
        await self.chat([{"role": "user", "content": "Hola"}], max_tokens=1)

    async def aclose(self) -> None:
        await self._client.aclose()


class NvidiaProvider:
    """build.nvidia.com. Pide JSON con esquema (response_format json_schema, estilo OpenAI);
    si el modelo no lo acepta, prueba nvext.guided_json, json_object y al final sin
    restricción. El modo que funcionó se recuerda para las siguientes llamadas."""

    MODES = ["json_schema", "guided", "json_object", "plain"]
    RETRY_429_S = 2.0

    name = "nvidia"

    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None):
        if not settings.nvidia_api_key:
            raise LLMError("Falta NVIDIA_API_KEY en .env")
        self.model = settings.nvidia_model
        self._url = settings.nvidia_base_url
        self._client = httpx.AsyncClient(
            timeout=settings.llm_timeout_s,
            headers={"Authorization": f"Bearer {settings.nvidia_api_key}"},
            transport=transport,
        )
        self._json_mode: str | None = None  # se recuerda el modo que funcionó

    def _payload(self, messages, schema, max_tokens, temperature, mode) -> dict:
        p: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": False,
            "chat_template_kwargs": {"enable_thinking": False},
        }
        if schema and mode == "json_schema":
            p["response_format"] = {"type": "json_schema",
                                    "json_schema": {"name": "respuesta", "schema": schema}}
        elif schema and mode == "guided":
            p["nvext"] = {"guided_json": schema}
        elif schema and mode == "json_object":
            p["response_format"] = {"type": "json_object"}
        if mode == "plain":  # último recurso: petición mínima
            p.pop("chat_template_kwargs")
        return p

    async def chat(self, messages, schema=None, max_tokens=220, temperature=0.7) -> ChatResult:
        if not schema:
            modes = ["free"]  # sin esquema no hay restricción de JSON; no se recuerda
        elif self._json_mode:
            modes = [self._json_mode]
        else:
            modes = self.MODES
        t0 = time.perf_counter()
        last_error = ""
        for mode in modes:
            payload = self._payload(messages, schema, max_tokens, temperature, mode)
            try:
                r = await self._client.post(f"{self._url}/chat/completions", json=payload)
                if r.status_code == 429:  # límite del plan gratuito: un reintento
                    await asyncio.sleep(float(r.headers.get("retry-after", self.RETRY_429_S)))
                    r = await self._client.post(f"{self._url}/chat/completions", json=payload)
            except httpx.HTTPError as exc:
                raise LLMError(f"API de NVIDIA no respondió: {exc}") from exc
            if r.status_code in (400, 422) and len(modes) > 1:
                last_error = r.text[:200]
                continue  # el modelo no acepta este modo: probar el siguiente
            if r.status_code >= 400:
                raise LLMError(f"API de NVIDIA {r.status_code}: {r.text[:200]}")
            if schema:
                self._json_mode = mode
            text = r.json()["choices"][0]["message"].get("content") or ""
            return ChatResult(text, parse_json(text) if schema else None,
                              time.perf_counter() - t0, self.name, self.model)
        raise LLMError(f"API de NVIDIA rechazó todos los modos: {last_error}")

    async def warmup(self) -> None:
        await self.chat([{"role": "user", "content": "Hola"}], max_tokens=1)

    async def aclose(self) -> None:
        await self._client.aclose()


def get_provider(settings: Settings) -> Provider:
    if settings.llm_provider == "nvidia":
        return NvidiaProvider(settings)
    if settings.llm_provider == "ollama":
        return OllamaProvider(settings)
    raise LLMError(f"LLM_PROVIDER desconocido: {settings.llm_provider}")
