"""Valida contract/fixtures contra contract/schemas y la coherencia de los datos del caso.

Correr desde la raíz del repo:  python -m pytest tests/contract -q
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "contract" / "schemas"
FIXTURES = ROOT / "contract" / "fixtures"
PUBLIC = ROOT / "content" / "public"
SECRET = ROOT / "server" / "data"

WITNESSES = ["chonita", "chepe", "chente", "ramirez", "padre_mauricio",
             "tonito", "beto", "pilo", "alcides", "mercedes"]
SUSPECTS = ["cipitio", "siguanaba", "cadejo", "padre_sin_cabeza", "carreta_chillona", "descarnada"]
MVP = {"chonita", "tonito", "ramirez", "padre_mauricio", "alcides", "mercedes"}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _registry() -> Registry:
    resources = []
    for p in SCHEMAS.glob("*.schema.json"):
        schema = load(p)
        resources.append((schema["$id"], Resource.from_contents(schema)))
    return Registry().with_resources(resources)


REGISTRY = _registry()


def validator_for(schema_name: str) -> Draft202012Validator:
    schema = load(SCHEMAS / f"{schema_name}.schema.json")
    return Draft202012Validator(schema, registry=REGISTRY)


# ---------- contrato ----------

@pytest.mark.parametrize("path", sorted(SCHEMAS.glob("*.schema.json")), ids=lambda p: p.name)
def test_schema_es_valido(path: Path):
    Draft202012Validator.check_schema(load(path))


@pytest.mark.parametrize("path", sorted(FIXTURES.glob("*.json")), ids=lambda p: p.name)
def test_fixture_valida_contra_schema(path: Path):
    assert "__" in path.stem, f"{path.name} debe llamarse {{schema}}__{{variante}}.json"
    schema_name = path.stem.split("__")[0]
    assert (SCHEMAS / f"{schema_name}.schema.json").exists(), f"no hay schema {schema_name}"
    errors = sorted(validator_for(schema_name).iter_errors(load(path)), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{list(e.path)}: {e.message}" for e in errors)


def test_fixtures_minimas_existen():
    names = {p.stem for p in FIXTURES.glob("*.json")}
    required = {
        "talk_response__chonita_inicial",
        "present_response__alcides_contradiccion",
        "present_response__alcides_sin_relacion",
        "ending__malo", "ending__gris", "ending__verdadero",
    }
    assert required <= names, f"faltan: {required - names}"
    for schema in ["world_state", "health_response", "talk_response", "present_response",
                   "examine_response", "ending", "stt_response", "api_error"]:
        assert any(n.startswith(schema + "__") for n in names), f"sin fixture para {schema}"


def test_contradiccion_de_alcides_es_coherente():
    yes = load(FIXTURES / "present_response__alcides_contradiccion.json")
    no = load(FIXTURES / "present_response__alcides_sin_relacion.json")
    assert yes["contradiction"] is True and yes["level"] == "confrontada" and yes["new_deductions"]
    assert no["contradiction"] is False and no["level"] == "inicial" and not no["new_deductions"]


def test_fixtures_no_revelan_la_solucion():
    culprit = load(SECRET / "case_secret.json")["solution"]["culprit"]
    proofs = {p["evidence_id"] for p in load(SECRET / "case_secret.json")["solution"]["proofs"]}
    banned = {culprit, "Padre Sin Cabeza", "padre Esteban", "Esteban"} | proofs
    for p in FIXTURES.glob("*.json"):
        text = p.read_text(encoding="utf-8")
        for word in banned:
            assert word not in text, f"{p.name} revela '{word}'"


# ---------- datos del caso ----------

def test_personajes_completos():
    chars = load(PUBLIC / "characters.json")
    assert [w["id"] for w in chars["witnesses"]] == WITNESSES
    assert [s["id"] for s in chars["suspects"]] == SUSPECTS
    assert {w["id"] for w in chars["witnesses"] if w["mvp"]} == MVP


def test_referencias_cruzadas():
    world = load(PUBLIC / "world.json")
    evidence_ids = {e["id"] for e in load(PUBLIC / "evidence.json")["evidence"]}
    location_ids = {loc["id"] for loc in world["locations"]}
    secret = load(SECRET / "case_secret.json")
    deductions = set(secret["deductions"])

    for w in load(PUBLIC / "characters.json")["witnesses"]:
        assert w["location"] in location_ids, w["id"]

    object_ids = []
    for loc in world["locations"]:
        for obj in loc["objects"]:
            object_ids.append(obj["id"])
            if obj["evidence_id"]:
                assert obj["evidence_id"] in evidence_ids, obj["id"]
            if obj.get("requires_deduction"):
                assert obj["requires_deduction"] in deductions, obj["id"]
    assert len(object_ids) == len(set(object_ids)), "ids de objeto repetidos"

    assert set(secret["witnesses"]) == set(WITNESSES)
    for wid, w in secret["witnesses"].items():
        for ev in w["contradicted_by"] + w["confession"]["by_evidence"]:
            assert ev in evidence_ids, f"{wid}: {ev}"
        g = w["confession"]["grants_evidence"]
        assert g is None or g in evidence_ids, f"{wid}: {g}"
        assert w["deduction_on_confront"] in deductions, wid
        assert w["confession"]["deduction"] in deductions, wid
        assert set(w["guide"]) == {"inicial", "confrontada", "confesion"}, wid

    for proof in secret["solution"]["proofs"]:
        assert proof["evidence_id"] in evidence_ids
    assert secret["solution"]["culprit"] in SUSPECTS
    for act in secret["acts"].values():
        assert set(act["unlocks"]) <= location_ids
        for d in act.get("requires", {}).get("all_deductions", []):
            assert d in deductions


def test_caso_resoluble_solo_con_mvp():
    """Simula al jugador ideal: examina todo lo abierto y presenta todo a los testigos MVP."""
    world = load(PUBLIC / "world.json")
    secret = load(SECRET / "case_secret.json")
    acts = secret["acts"]
    wit = {k: v for k, v in secret["witnesses"].items() if k in MVP}

    act, evidence, deductions = 1, set(), set()
    level = {w: "inicial" for w in wit}
    unlocked = set(acts["1"]["unlocks"])

    for _ in range(20):
        before = (act, len(evidence), len(deductions))
        for loc in world["locations"]:
            if loc["id"] not in unlocked or loc["act"] > act:
                continue
            for obj in loc["objects"]:
                req = obj.get("requires_deduction")
                if obj["evidence_id"] and (not req or req in deductions):
                    evidence.add(obj["evidence_id"])
        for wid, w in wit.items():
            if level[wid] == "inicial" and evidence & set(w["contradicted_by"]):
                level[wid] = "confrontada"
                deductions.add(w["deduction_on_confront"])
            elif level[wid] == "confrontada" and evidence & set(w["confession"]["by_evidence"]):
                level[wid] = "confesion"
                deductions.add(w["confession"]["deduction"])
                if w["confession"]["grants_evidence"]:
                    evidence.add(w["confession"]["grants_evidence"])
        if act < 3 and set(acts["3"]["requires"]["all_deductions"]) <= deductions:
            act = 3
            unlocked |= set(acts["2"]["unlocks"]) | set(acts["3"]["unlocks"])
        if (act, len(evidence), len(deductions)) == before:
            break

    proofs = {p["evidence_id"] for p in secret["solution"]["proofs"]}
    assert act == 3, "no se llega al Acto III"
    assert proofs <= evidence, f"pruebas inalcanzables: {proofs - evidence}"
    assert all(lv == "confesion" for lv in level.values()), level


def test_finales_definidos():
    endings = load(SECRET / "endings.json")
    v = validator_for("ending")
    for key, e in endings["endings"].items():
        assert not list(v.iter_errors(e)), key
    assert {e["ending_id"] for e in endings["endings"].values()} == {"malo", "gris", "verdadero"}
    assert endings["rules"]["min_proofs_true_ending"] == 5


def test_solucion_no_esta_en_contenido_publico():
    culprit = load(SECRET / "case_secret.json")["solution"]["culprit"]
    for p in PUBLIC.glob("*.json"):
        data = load(p)
        # El culpable puede aparecer como sospechoso, pero nunca marcado como tal.
        assert "culprit" not in p.read_text(encoding="utf-8"), p.name
        assert "solution" not in data, p.name
    assert culprit in SUSPECTS
