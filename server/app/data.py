"""Carga de datos del caso. Lo público viene de content/public; lo secreto, de server/data.

Nada de lo que sale de aquí con prefijo `secret_` debe viajar tal cual al cliente.
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from .config import ROOT

PUBLIC = ROOT / "content" / "public"
SECRET = ROOT / "server" / "data"


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


@lru_cache
def world() -> dict:
    return _load(PUBLIC / "world.json")


@lru_cache
def characters() -> dict:
    return _load(PUBLIC / "characters.json")


@lru_cache
def evidence() -> dict:
    return _load(PUBLIC / "evidence.json")


@lru_cache
def secret_case() -> dict:
    return _load(SECRET / "case_secret.json")


@lru_cache
def secret_endings() -> dict:
    return _load(SECRET / "endings.json")


@lru_cache
def witness_sheet(witness_id: str) -> dict | None:
    """Ficha generada en B2 (server/data/characters/{id}.json) o None si no existe."""
    path = SECRET / "characters" / f"{witness_id}.json"
    return _load(path) if path.exists() else None


def witness_public(witness_id: str) -> dict:
    for w in characters()["witnesses"]:
        if w["id"] == witness_id:
            return w
    raise KeyError(witness_id)


def witness_secret(witness_id: str) -> dict:
    return secret_case()["witnesses"][witness_id]


# Orden de los NPC en WorldState: primero los del MVP, como en contract/fixtures/world_state__*.json,
# y después los 4 restantes (pistas de las otras leyendas).
MVP_ORDER = ["chonita", "tonito", "ramirez", "padre_mauricio", "alcides", "mercedes"]
EXTRA_ORDER = ["beto", "pilo", "chente", "chepe"]
ORDER = MVP_ORDER + EXTRA_ORDER


def active_witnesses(only_mvp: bool = False) -> list[str]:
    """Testigos jugables en el orden del contrato: los 10, o solo los 6 del MVP (WITNESSES=mvp)."""
    ids = [w["id"] for w in characters()["witnesses"] if w["mvp"] or not only_mvp]
    return sorted(ids, key=lambda i: ORDER.index(i) if i in ORDER else len(ORDER))
