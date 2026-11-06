from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from server.app.config import Settings
from server.app.llm.provider import ChatResult
from server.app.main import create_app

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "contract" / "schemas"


def _registry() -> Registry:
    res = []
    for p in SCHEMAS.glob("*.schema.json"):
        s = json.loads(p.read_text(encoding="utf-8"))
        res.append((s["$id"], Resource.from_contents(s)))
    return Registry().with_resources(res)


_REGISTRY = _registry()


def assert_valid(schema_name: str, payload) -> None:
    schema = json.loads((SCHEMAS / f"{schema_name}.schema.json").read_text(encoding="utf-8"))
    errs = list(Draft202012Validator(schema, registry=_REGISTRY).iter_errors(payload))
    assert not errs, "\n".join(f"{list(e.path)}: {e.message}" for e in errs)


class FakeProvider:
    name = "fake"
    model = "fake-model"

    def __init__(self, fail_warmup: bool = False):
        self.fail_warmup = fail_warmup
        self.calls: list = []

    async def chat(self, messages, schema=None, max_tokens=220, temperature=0.7):
        self.calls.append(messages)
        text = '{"reply": "Fíjese que no sé nada.", "emotion": "nervioso", "trust_delta": 0, "fear_delta": 1}'
        return ChatResult(text, json.loads(text), 0.01, self.name, self.model)

    async def warmup(self):
        if self.fail_warmup:
            raise RuntimeError("sin conexión")

    async def aclose(self):
        pass


@pytest.fixture
def make_client(tmp_path):
    clients = []

    def _make(provider=None, **overrides):
        settings = Settings(db_path=tmp_path / "test.db", **overrides)
        c = TestClient(create_app(settings, provider or FakeProvider()))
        c.__enter__()
        clients.append(c)
        return c

    yield _make
    for c in clients:
        c.__exit__(None, None, None)


@pytest.fixture
def client(make_client):
    return make_client()
