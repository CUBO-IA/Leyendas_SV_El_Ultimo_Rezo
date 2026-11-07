"""Estado inicial de una partida, armado desde case_secret.json y world.json."""
from __future__ import annotations

import uuid

from . import data

# Partida del modo demo: dos evidencias del Acto I ya encontradas (igual que la fixture
# world_state__demo), para enseñar un interrogatorio sin recorrer el pueblo.
DEMO_EVIDENCE = ["registro_electrico", "cuaderno_ventas"]


def new_session_id() -> str:
    return uuid.uuid4().hex[:16]


def new_world_state(session_id: str, demo: bool = False, only_mvp: bool = False) -> tuple[dict, dict]:
    """Devuelve (estado público WorldState, estado privado)."""
    case = data.secret_case()
    act1 = case["acts"]["1"]
    witnesses = data.active_witnesses(only_mvp)
    npcs = []
    for wid in witnesses:
        start = data.witness_secret(wid)["start"]
        npcs.append({"id": wid, "level": "inicial", "trust": start["trust"],
                     "fear": start["fear"], "met": False})
    public = {
        "session_id": session_id,
        "act": 1,
        "clock": act1["clock"],
        "evidence": list(DEMO_EVIDENCE) if demo else [],
        "deductions": [],
        "npcs": npcs,
        "unlocked_locations": list(act1["unlocks"]),
        "can_accuse": False,
        "ended": False,
    }
    if demo:
        public["demo"] = True
    private = {"history": {wid: [] for wid in witnesses}, "examined": []}
    return public, private
