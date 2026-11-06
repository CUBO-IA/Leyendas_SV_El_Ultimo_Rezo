"""Reglas deterministas del caso. Aquí se decide TODO lo que cambia el estado:
niveles, evidencias, deducciones, actos y finales. El LLM nunca toca esto.

Fuente: server/data/case_secret.json (_reglas_de_nivel, trust_rules, acts, accuse)
y server/data/endings.json.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from . import data
from .errors import ApiError

GATED_TEXT = "Hay algo raro aquí, pero todavía no sabes qué buscar."


# ---------- utilidades de estado ----------

def clamp(v: int, lo: int = 0, hi: int = 10) -> int:
    return max(lo, min(hi, int(v)))


def npc(public: dict, witness_id: str) -> dict:
    for n in public["npcs"]:
        if n["id"] == witness_id:
            return n
    raise ApiError("bad_npc", f"{witness_id} no está en esta partida.")


def deduction(did: str) -> dict:
    return {"id": did, "text": data.secret_case()["deductions"][did]}


def deduction_ids(public: dict) -> set[str]:
    return {d["id"] for d in public["deductions"]}


def add_deduction(public: dict, did: str) -> dict | None:
    """Agrega la deducción si es nueva y la devuelve; None si ya estaba."""
    if did in deduction_ids(public):
        return None
    d = deduction(did)
    public["deductions"].append(d)
    return d


def add_evidence(public: dict, eid: str | None) -> bool:
    if not eid or eid in public["evidence"]:
        return False
    public["evidence"].append(eid)
    return True


def evidence_exists(eid: str) -> bool:
    return any(e["id"] == eid for e in data.evidence()["evidence"])


def ensure_playing(public: dict) -> None:
    if public.get("ended"):
        raise ApiError("session_ended", "La partida ya terminó.")


# ---------- actos ----------

def advance_acts(public: dict) -> bool:
    """Sube de acto según las deducciones. Del 1 se puede saltar directo al 3."""
    acts = data.secret_case()["acts"]
    have = deduction_ids(public)
    act = int(public["act"])
    target = act
    req3 = acts["3"].get("requires", {})
    req2 = acts["2"].get("requires", {})
    if act < 3 and set(req3.get("all_deductions", [])) <= have:
        target = 3
    elif act < 2 and len(have) >= int(req2.get("min_deductions", 99)):
        target = 2
    if target != act:
        for a in range(act + 1, target + 1):
            for loc in acts[str(a)]["unlocks"]:
                if loc not in public["unlocked_locations"]:
                    public["unlocked_locations"].append(loc)
        public["act"] = target
        public["clock"] = acts[str(target)]["clock"]
    public["can_accuse"] = int(public["act"]) >= int(data.secret_case()["accuse"]["requires_act"])
    return target != act


# ---------- interrogatorio ----------

@dataclass
class Outcome:
    """Resultado de una presentación o de un turno de diálogo."""
    kind: str  # confront | confess | repeat | unrelated | talk
    level_before: str
    level: str
    new_deductions: list[dict] = field(default_factory=list)
    new_evidence: list[str] = field(default_factory=list)

    @property
    def changed_level(self) -> bool:
        return self.level != self.level_before


def _confess(public: dict, n: dict, sec: dict, out: Outcome) -> None:
    n["level"] = "confesion"
    conf = sec["confession"]
    if add_evidence(public, conf["grants_evidence"]):
        out.new_evidence.append(conf["grants_evidence"])
    d = add_deduction(public, conf["deduction"])
    if d:
        out.new_deductions.append(d)
    out.level = "confesion"


def present(public: dict, witness_id: str, evidence_id: str) -> Outcome:
    if not evidence_exists(evidence_id):
        raise ApiError("bad_evidence", f"No existe la evidencia {evidence_id}.")
    n = npc(public, witness_id)
    if evidence_id not in public["evidence"]:
        raise ApiError("evidence_not_owned", "Todavía no tienes esa evidencia.")
    sec = data.witness_secret(witness_id)
    rules = data.secret_case()["trust_rules"]
    level = n["level"]
    out = Outcome("unrelated", level, level)
    n["met"] = True

    if level == "inicial" and evidence_id in sec["contradicted_by"]:
        out.kind = "confront"
        n["level"] = out.level = "confrontada"
        n["trust"] = clamp(n["trust"] + rules["on_contradiction"]["trust"])
        n["fear"] = clamp(n["fear"] + rules["on_contradiction"]["fear"])
        d = add_deduction(public, sec["deduction_on_confront"])
        if d:
            out.new_deductions.append(d)
    elif level == "confrontada" and evidence_id in sec["confession"]["by_evidence"]:
        out.kind = "confess"
        _confess(public, n, sec, out)
    elif evidence_id in sec["contradicted_by"] or (
            level != "inicial" and evidence_id in sec["confession"]["by_evidence"]):
        out.kind = "repeat"  # ya se usó: ni premio ni castigo
    else:
        # No relacionada (incluye la evidencia de confesión presentada en nivel inicial).
        n["trust"] = clamp(n["trust"] + rules["on_wrong_evidence"]["trust"])
        n["fear"] = clamp(n["fear"] + rules["on_wrong_evidence"]["fear"])

    advance_acts(public)
    return out


def talk(public: dict, witness_id: str, trust_delta: int, fear_delta: int) -> Outcome:
    """Aplica el cambio de confianza y miedo de un turno. Si la confianza alcanza
    confession.by_trust estando confrontada, el testigo confiesa."""
    n = npc(public, witness_id)
    sec = data.witness_secret(witness_id)
    max_d = int(data.secret_case()["trust_rules"]["max_delta_per_turn"])
    n["met"] = True
    n["trust"] = clamp(n["trust"] + max(-max_d, min(max_d, int(trust_delta))))
    n["fear"] = clamp(n["fear"] + max(-max_d, min(max_d, int(fear_delta))))
    out = Outcome("talk", n["level"], n["level"])
    if n["level"] == "confrontada" and n["trust"] >= int(sec["confession"]["by_trust"]):
        out.kind = "confess"
        _confess(public, n, sec, out)
        advance_acts(public)
    return out


# ---------- examinar ----------

def _object(object_id: str) -> tuple[dict, dict]:
    for loc in data.world()["locations"]:
        for obj in loc["objects"]:
            if obj["id"] == object_id:
                return loc, obj
    raise ApiError("bad_object", f"No existe el objeto {object_id}.")


def examine(public: dict, object_id: str) -> tuple[str, list[str]]:
    loc, obj = _object(object_id)
    if loc["id"] not in public["unlocked_locations"] or int(loc["act"]) > int(public["act"]):
        raise ApiError("location_locked", f"Todavía no puedes entrar a {loc['name']}.")
    req = obj.get("requires_deduction")
    if req and req not in deduction_ids(public):
        return GATED_TEXT, []
    new = [obj["evidence_id"]] if add_evidence(public, obj.get("evidence_id")) else []
    return obj["description"], new


# ---------- acusación ----------

def accuse(public: dict, suspect_id: str, evidence_ids: list[str], decision: str) -> dict:
    if not public.get("can_accuse"):
        raise ApiError("cannot_accuse", "Todavía no sabes lo suficiente para acusar.")
    for eid in evidence_ids:
        if not evidence_exists(eid):
            raise ApiError("bad_evidence", f"No existe la evidencia {eid}.")
    solution = data.secret_case()["solution"]
    endings = data.secret_endings()
    # Solo cuentan las evidencias que el jugador de verdad tiene.
    usable = set(evidence_ids) & set(public["evidence"])
    proofs = {p["evidence_id"] for p in solution["proofs"]}
    enough = len(usable & proofs) >= int(endings["rules"]["min_proofs_true_ending"])
    if suspect_id != solution["culprit"]:
        key = "malo"
    elif decision == "revelar" and enough:
        key = "verdadero"
    elif decision == "negociar":
        key = "gris_negociar"
    else:
        key = "gris_incompleto"
    public["ended"] = True
    public["can_accuse"] = False
    return dict(endings["endings"][key])
