"""B2: selección de personas, validaciones de la fusión y fichas generadas (sin red)."""
from __future__ import annotations

import json

import pytest

from server.app import data
from server.app.llm.prompts import witness_system_prompt
from server.pipelines import personas as P

from .conftest import ROOT


def row(uuid, sex="Femenino", age=55, occ=P.OCC_FOOD, area="rural", marital="casado", dept="Chalatenango"):
    return {"uuid": uuid, "sex": sex, "age": age, "occupation": occ, "area": area,
            "marital_status": marital, "department": dept}


def test_score_filtra_sexo_y_edad():
    a = P.ARCHETYPES["chonita"]
    assert P.score(row("a", sex="Masculino"), a) is None
    assert P.score(row("a", age=40), a) is None
    good = P.score(row("a"), a)
    worse_occ = P.score(row("b", occ="Actividades de hospitales"), a)
    urban = P.score(row("c", area="urbano"), a)
    assert good > urban > worse_occ


def test_select_determinista_y_sin_repetir():
    rows = [row("u1"), row("u2"), row("u3", age=60)]
    a = P.select(rows, ["chonita"])
    b = P.select(list(reversed(rows)), ["chonita"])
    assert a["chonita"][0]["uuid"] == b["chonita"][0]["uuid"]
    # Dos testigos con el mismo arquetipo no pueden quedarse con la misma persona.
    saved = P.ARCHETYPES.get("_otra")
    P.ARCHETYPES["_otra"] = P.ARCHETYPES["chonita"]
    try:
        both = P.select(rows, ["chonita", "_otra"])
        assert both["chonita"][0]["uuid"] != both["_otra"][0]["uuid"]
    finally:
        P.ARCHETYPES.pop("_otra")
        if saved:
            P.ARCHETYPES["_otra"] = saved


def test_cada_testigo_tiene_arquetipo():
    assert set(P.ARCHETYPES) == {w["id"] for w in data.characters()["witnesses"]}


def test_detecta_spoilers_y_estilo():
    assert P.spoilers_in("Era amigo del padre Esteban") == ["esteban"]
    assert P.spoilers_in("Vende pupusas desde niña") == []
    sheet = {"full_name": "María Asunción Pérez", "muletillas": ["¡Ni modo, chavo!", "puchica"],
             "visual_prompt": "Una señora de 57 años con delantal y el cabello recogido"}
    problems = P.check_style("chonita", sheet)
    assert any("mexicanismos" in p for p in problems)
    assert any("inglés" in p for p in problems)
    ok = {"full_name": "María Asunción Pérez", "muletillas": ["puchica", "va pues"],
          "visual_prompt": "57-year-old woman with an apron, bun hair, warm smile"}
    assert P.check_style("chonita", ok) == []
    assert any("Portillo" in p for p in P.check_style("mercedes", dict(ok, full_name="María Mercedes Cruz")))
    other = {"id": "chepe", "muletillas": ["puchica", "va pues", "a la gran"]}
    assert P.check_style("chonita", dict(ok, muletillas=["puchica", "va pues", "a la gran"]), [other])


def test_voz_por_sexo_y_edad():
    assert P.voice_profile("Femenino", 81) == {"gender": "female", "age_band": "mayor", "language": "es-US", "voice": None}
    assert P.voice_profile("Masculino", 24)["age_band"] == "joven"


def test_el_prompt_de_fusion_no_lleva_secretos():
    persona = {"sex": "Femenino", "age": 57, "marital_status": "casado", "household_type": "nuclear",
               "education_level": "primaria", "occupation": P.OCC_FOOD, "area": "rural",
               "municipality": "X", "department": "Y", "persona": "p"}
    text = json.dumps(P.fusion_messages("chonita", persona), ensure_ascii=False)
    sec = data.witness_secret("chonita")
    for secret in [sec["lie"], sec["truth_behind_lie"], sec["true_clue"], sec["guide"]["confesion"]]:
        assert secret not in text


# ---------- fichas generadas (si ya se corrió el pipeline) ----------

SHEETS = sorted((ROOT / "server" / "data" / "characters").glob("*.json"))
PUBLIC = ROOT / "content" / "generated" / "characters_public.json"


@pytest.mark.skipif(not SHEETS, reason="aún no se corre server.pipelines.personas")
def test_fichas_generadas_completas_y_sin_spoilers():
    ids = {w["id"] for w in data.characters()["witnesses"]}
    uuids = set()
    for path in SHEETS:
        s = json.loads(path.read_text(encoding="utf-8"))
        assert s["id"] in ids and path.stem == s["id"]
        assert s["full_name"] and s["bio"] and len(s["muletillas"]) >= 2 and s["visual_prompt"]
        assert not P.spoilers_in(s["bio"]), s["id"]
        assert not P.check_style(s["id"], s), s["id"]
        assert s["persona"]["dataset"] == P.DATASET
        uuids.add(s["persona"]["uuid"])
    assert len(uuids) == len(SHEETS), "dos testigos con la misma persona"


@pytest.mark.skipif(not PUBLIC.exists(), reason="aún no se corre server.pipelines.personas")
def test_export_publico_solo_campos_publicos():
    pub = json.loads(PUBLIC.read_text(encoding="utf-8"))
    assert pub["license"] == "CC BY 4.0"
    culprit = data.secret_case()["solution"]["culprit"]
    for w in pub["witnesses"]:
        assert set(w) == {"id", "full_name", "age", "occupation", "bio"}
    text = PUBLIC.read_text(encoding="utf-8")
    assert culprit not in text and "uuid" not in text and "visual_prompt" not in text
    credits = (ROOT / "server" / "CREDITS.md").read_text(encoding="utf-8")
    assert "CC BY 4.0" in credits and all(json.loads(p.read_text(encoding="utf-8"))["persona"]["uuid"] in credits for p in SHEETS)


@pytest.mark.skipif(not SHEETS, reason="aún no se corre server.pipelines.personas")
def test_prompt_del_testigo_usa_su_ficha():
    data.witness_sheet.cache_clear()
    sheet = data.witness_sheet("chonita")
    prompt = witness_system_prompt("chonita", "inicial", 4, 3)
    assert sheet["full_name"] in prompt and sheet["muletillas"][0] in prompt
    assert data.witness_secret("chonita")["guide"]["confesion"] not in prompt
