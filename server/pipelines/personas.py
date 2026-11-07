"""Fichas de personajes desde nvidia/Nemotron-Personas-El-Salvador (CC BY 4.0).

  .venv\\Scripts\\python -m server.pipelines.personas            # todo
  .venv\\Scripts\\python -m server.pipelines.personas --dry-run  # solo elegir y mostrar candidatos
  .venv\\Scripts\\python -m server.pipelines.personas --only chonita --force

1. Descarga 1 de los 3 parquet del dataset (~190 MB, ~49 000 personas; caché de HF,
   fuera del repo) e imprime el esquema real y un registro de ejemplo.
2. Para cada testigo filtra por arquetipo (sexo y edad obligatorios; ocupación, zona,
   estado civil y departamento suman puntos) y elige el mejor, sin repetir persona.
3. Con el LLM fusiona persona + papel en la historia. Al LLM NO se le pasa la pista ni
   la mentira del testigo: la biografía pública no puede filtrar el caso.
4. Escribe server/data/characters/{id}.json (ficha completa, solo servidor),
   content/generated/characters_public.json (nombre, edad, oficio, biografía) y
   server/CREDITS.md (uuid de cada persona y atribución CC BY 4.0).
"""
from __future__ import annotations

import argparse
import asyncio
import dataclasses
import json
import random
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from server.app import data  # noqa: E402
from server.app.config import Settings  # noqa: E402
from server.app.llm.provider import LLMError, get_provider  # noqa: E402

DATASET = "nvidia/Nemotron-Personas-El-Salvador"
DATASET_URL = "https://huggingface.co/datasets/nvidia/Nemotron-Personas-El-Salvador"
SHARDS = [f"data/train-0000{i}-of-00003.parquet" for i in range(3)]
SHEETS = ROOT / "server" / "data" / "characters"
PUBLIC = ROOT / "content" / "generated" / "characters_public.json"
CREDITS = ROOT / "server" / "CREDITS.md"
MOUNTAIN_DEPTS = {"Chalatenango", "Morazán", "Cabañas", "Santa Ana", "Ahuachapán", "La Libertad"}

OCC_FOOD = "Actividades de restaurantes y de comida ambulante"
OCC_PASSENGERS = "Transporte urbano y suburbano de pasajeros por vía terrestre"
OCC_POLICE = "Actividades de mantenimiento del orden público y de seguridad"
OCC_PRIVATE_SECURITY = "Actividades de seguridad privada"
OCC_RELIGIOUS = "Actividades de organizaciones religiosas"
OCC_MARKET_FOOD = "Venta al por menor de alimentos, bebidas y tabaco en puestos de venta y mercados"


@dataclasses.dataclass(frozen=True)
class Archetype:
    sex: str
    age: tuple[int, int]
    occupations: tuple[str, ...] = ()
    area: str | None = "rural"
    marital: tuple[str, ...] = ()
    prefer_young: bool = False


# La historia (docs/historia.md) manda; el dataset aporta realismo.
ARCHETYPES: dict[str, Archetype] = {
    "chonita": Archetype("Femenino", (50, 65), (OCC_FOOD,)),
    "chepe": Archetype("Masculino", (40, 60), (OCC_PASSENGERS,)),
    "chente": Archetype("Masculino", (35, 60), (), marital=("soltero", "divorciado", "separado")),
    "ramirez": Archetype("Masculino", (30, 45), (OCC_POLICE,), area=None),
    "padre_mauricio": Archetype("Masculino", (45, 70), (OCC_RELIGIOUS,), marital=("soltero",)),
    "tonito": Archetype("Masculino", (18, 21), (OCC_MARKET_FOOD, OCC_FOOD), prefer_young=True),
    "beto": Archetype("Masculino", (25, 45), (OCC_MARKET_FOOD,)),
    "pilo": Archetype("Masculino", (18, 30), (OCC_PASSENGERS,)),
    "alcides": Archetype("Masculino", (55, 72), (OCC_PRIVATE_SECURITY,)),
    "mercedes": Archetype("Femenino", (72, 90), (), marital=("viudo",)),
}

# Nombre de pila detrás de cada apodo y apellido obligatorio cuando la historia lo fija.
NAMES: dict[str, tuple[str | None, str | None]] = {
    "chonita": ("María Asunción", None), "chepe": ("José", None), "chente": ("Vicente", None),
    "ramirez": (None, "Ramírez"), "padre_mauricio": ("Mauricio", None), "tonito": ("Antonio", None),
    "beto": ("Roberto", None), "pilo": (None, None), "alcides": ("Alcides", None),
    "mercedes": ("María Mercedes", "Portillo"),
}

# Expresiones salvadoreñas de referencia para las muletillas, y mexicanismos que no van.
# Repertorios por edad: la abuela no habla como el cobrador de 24 años.
SV_EXPRESSIONS: dict[str, list[str]] = {
    "joven": ["qué onda vos", "chivo", "simón", "chero", "de a cachete", "va", "bicho",
              "a la gran", "puchica", "ideay", "pisto", "qué pedo", "bayunco"],
    "adulta": ["puchica", "va pues", "a la gran", "ideay", "chivo", "mire", "fíjese",
               "ajá pues", "vaya pues", "cipote", "¿verdad?", "salú", "ni modo", "bayunco"],
    "mayor": ["fíjese", "mire", "válgame Dios", "Virgen santísima", "Dios guarde", "mijo",
              "bichito", "ajá pues", "ay, no", "Dios se lo pague", "va pues", "cipote"],
}
# Notas para apodos que el modelo suele malinterpretar.
ROLE_NOTES: dict[str, str] = {
    "chente": "«bolito» en El Salvador es alguien que toma mucho guaro (un borracho de cantina), no un bolero ni un vendedor.",
    "tonito": "Lustra zapatos en el parque central.",
    "pilo": "«Cobrador» es quien grita las paradas y cobra el pasaje en el bus.",
}
NOT_SALVADORAN = ["chavo", "nomás", "no mas", "güey", "wey", "órale", "chido", "padrísimo", "neta",
                  "carnal", "mande"]
SPANISH_MARKERS = [" años", " con ", " de ", " usa ", " cabello", " piel ", " y ", " una ", " el "]

COLUMNS_FOR_SCORING = ["uuid", "sex", "age", "occupation", "area", "marital_status", "department"]

# Términos que la biografía pública jamás puede contener (spoilers del caso).
SPOILERS = ["esteban", "padre sin cabeza", "sin cabeza", "campanario", "2006", "excav",
            "saque", "tumba", "campana funeraria", "culpable", "trece campanadas"]

SHEET_SCHEMA = {
    "type": "object",
    "properties": {
        "full_name": {"type": "string"},
        "occupation": {"type": "string"},
        "bio": {"type": "string"},
        "speech_style": {"type": "string"},
        "muletillas": {"type": "array", "items": {"type": "string"}},
        "family": {"type": "string"},
        "fears": {"type": "array", "items": {"type": "string"}},
        "visual_prompt": {"type": "string"},
    },
    "required": ["full_name", "occupation", "bio", "speech_style", "muletillas", "family",
                 "fears", "visual_prompt"],
    "additionalProperties": False,
}


# ---------- datos ----------

def shard_paths(n: int) -> list[str]:
    from huggingface_hub import hf_hub_download
    return [hf_hub_download(DATASET, s, repo_type="dataset") for s in SHARDS[:n]]


def load_rows(paths: list[str], columns: list[str] | None = None) -> list[dict]:
    import pyarrow.parquet as pq
    rows: list[dict] = []
    for p in paths:
        rows += pq.read_table(p, columns=columns).to_pylist()
    return rows


def show_schema(path: str) -> None:
    import pyarrow.parquet as pq
    pf = pq.ParquetFile(path)
    print("Esquema real del dataset:")
    for field in pf.schema_arrow:
        print(f"  {field.name}: {field.type}")
    sample = pf.read_row_group(0).slice(0, 1).to_pylist()[0]
    print("Registro de ejemplo:")
    for k, v in sample.items():
        print(f"  {k}: {str(v)[:120]}")


def score(row: dict, a: Archetype) -> float | None:
    """None si no cumple sexo y edad; si cumple, más puntos = mejor candidato."""
    if row["sex"] != a.sex or not a.age[0] <= row["age"] <= a.age[1]:
        return None
    s = 0.0
    if a.occupations:
        if row["occupation"] in a.occupations:
            s += 5 - a.occupations.index(row["occupation"])  # la primera ocupación vale más
        else:
            s -= 3
    if a.area and row["area"] == a.area:
        s += 2
    if a.marital and row["marital_status"] in a.marital:
        s += 2
    if row["department"] in MOUNTAIN_DEPTS:
        s += 1
    if a.prefer_young:
        s += (a.age[1] - row["age"]) * 0.5
    else:  # cerca del centro del rango
        mid = sum(a.age) / 2
        s -= abs(row["age"] - mid) * 0.05
    return s


def select(rows: list[dict], ids: list[str]) -> dict[str, list[dict]]:
    """Top 3 candidatos por testigo, sin repetir uuid entre testigos (orden determinista)."""
    used: set[str] = set()
    out: dict[str, list[dict]] = {}
    for wid in ids:
        a = ARCHETYPES[wid]
        scored = [(sc, r["uuid"], r) for r in rows if (sc := score(r, a)) is not None]
        scored.sort(key=lambda t: (-t[0], t[1]))
        top = [dict(r, _score=round(sc, 2)) for sc, _, r in scored if r["uuid"] not in used][:3]
        if not top:
            raise SystemExit(f"Sin candidatos para {wid}: revisa su arquetipo.")
        used.add(top[0]["uuid"])
        out[wid] = top
    return out


# ---------- fusión con el LLM ----------

def fold(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def spoilers_in(text: str) -> list[str]:
    t = fold(text)
    return [w for w in SPOILERS if fold(w) in t]


def voice_profile(sex: str, age: int) -> dict:
    """Perfil de voz determinista. B4 lo traduce a una voz concreta de Magpie TTS."""
    band = "joven" if age < 30 else ("adulta" if age < 60 else "mayor")
    return {"gender": "female" if sex == "Femenino" else "male", "age_band": band,
            "language": "es-US", "voice": None}


def fusion_messages(wid: str, persona: dict) -> list[dict]:
    pub = data.witness_public(wid)
    loc = data.world()["locations"]
    place = next((l["name"] for l in loc if l["id"] == pub["location"]), pub["location"])
    fields = ["persona", "cultural_background", "family_persona", "professional_persona",
              "culinary_persona", "hobbies_and_interests", "skills_and_expertise"]
    persona_text = "\n".join(f"- {f}: {persona.get(f, '')}" for f in fields)
    facts = (f"sexo {persona['sex']}, {persona['age']} años, estado civil {persona['marital_status']}, "
             f"hogar {persona['household_type']}, estudios {persona['education_level']}, "
             f"ocupación del censo «{persona['occupation']}», zona {persona['area']}, "
             f"de {persona['municipality']} ({persona['department']}).")
    band = voice_profile(persona["sex"], int(persona["age"]))["age_band"]
    pool = list(SV_EXPRESSIONS[band])
    random.Random(wid).shuffle(pool)
    pool = pool[:7]
    note = f"\n- Ojo: {ROLE_NOTES[wid]}" if wid in ROLE_NOTES else ""
    given, surname = NAMES.get(wid, (None, None))
    name_rule = "nombre de pila y dos apellidos; "
    name_rule += f"el nombre de pila es «{given}» (su apodo es «{pub['name']}»); " if given else f"un nombre de pila del que salga el apodo «{pub['name']}»; "
    name_rule += f"uno de los apellidos debe ser «{surname}»; el otro tómalo de la persona." if surname else "los apellidos tómalos de la persona."
    system = (
        "Eres guionista de un juego de misterio ambientado en El Salvador. Fusionas una persona "
        "sintética basada en el censo salvadoreño con un personaje ya escrito de la historia. "
        "La persona aporta realismo (familia, costumbres, forma de vivir); la historia manda "
        "sobre el apodo, el oficio en el pueblo y su lugar. Escribe en español salvadoreño natural. "
        "Responde solo con JSON."
    )
    user = f"""PERSONAJE DE LA HISTORIA
- Apodo con el que todos lo conocen: {pub['name']}
- Oficio en el pueblo: {pub['role']}
- Dónde se le encuentra: {place}
- Cómo se presenta: «{pub['intro']}»{note}

PERSONA DEL DATASET (datos reales del censo, resumidos)
- Datos: {facts}
{persona_text}

REGLAS
- Vive desde siempre en San Jacinto de las Ánimas, un pueblo ficticio de montaña en El Salvador. Cambia el municipio del dataset por ese pueblo.
- full_name: {name_rule}
- occupation: el oficio en el pueblo, en pocas palabras (manda la historia, no el censo).
- Conserva su edad: {persona['age']} años.
- bio: 2 o 3 frases en tercera persona sobre su vida y su carácter. NO hables de la noche de las desapariciones, de espantos, del cura muerto, de iglesias ni campanarios, de tumbas ni de nada del misterio.
- speech_style: 1 o 2 frases sobre cómo habla (ritmo, trato de usted o de vos, tono).
- muletillas: 3 a 5 expresiones salvadoreñas propias de este personaje (elige entre estas o parecidas: {", ".join(pool)}). Nada de mexicanismos como chavo, nomás, güey u órale.
- family: 1 frase sobre su familia, tomada de la persona.
- fears: 2 o 3 miedos cotidianos y creíbles (puede temerle a los espantos en general).
- visual_prompt: escrito COMPLETAMENTE EN INGLÉS, para un retrato pixel art de 16 bits de busto: edad, rasgos, piel, cabello, ropa típica de su oficio, un detalle distintivo. Sin texto ni letreros."""
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def check_style(wid: str, sheet: dict, others: list[dict] | None = None) -> list[str]:
    """Problemas de forma que justifican pedir otra versión al modelo."""
    problems = []
    mine = {fold(m).strip("¡!¿?., ") for m in sheet["muletillas"]}
    for o in others or []:
        shared = mine & {fold(m).strip("¡!¿?., ") for m in o["muletillas"]}
        if len(shared) > 2:
            problems.append(f"muletillas demasiado parecidas a las de {o['id']} ({', '.join(sorted(shared))}); usa otras")
            break
    muletillas = fold(" | ".join(sheet["muletillas"]))
    bad = [w for w in NOT_SALVADORAN if re.search("(?<![a-z])" + re.escape(fold(w)) + "(?![a-z])", muletillas)]
    if bad:
        problems.append(f"las muletillas tienen mexicanismos ({', '.join(bad)})")
    vp = " " + sheet["visual_prompt"].lower() + " "
    if sum(m in vp for m in SPANISH_MARKERS) >= 3:
        problems.append("visual_prompt debe estar en inglés")
    given, surname = NAMES.get(wid, (None, None))
    if given and not fold(sheet["full_name"]).startswith(fold(given)):
        problems.append(f"full_name debe empezar con «{given}»")
    if surname and fold(surname) not in fold(sheet["full_name"]):
        problems.append(f"full_name debe llevar el apellido «{surname}»")
    return problems


def clean_sheet(raw: dict) -> dict:
    def s(k: str, n: int = 600) -> str:
        return re.sub(r"\s+", " ", str(raw.get(k, ""))).strip()[:n]

    def lst(k: str, n: int) -> list[str]:
        v = raw.get(k) or []
        return [re.sub(r"\s+", " ", str(x)).strip() for x in v if str(x).strip()][:n]

    return {"full_name": s("full_name", 80), "occupation": s("occupation", 80), "bio": s("bio"),
            "speech_style": s("speech_style", 300), "muletillas": lst("muletillas", 5),
            "family": s("family", 300), "fears": lst("fears", 3),
            "visual_prompt": s("visual_prompt", 700)}


async def fuse(provider, wid: str, persona: dict, others: list[dict] | None = None, tries: int = 4) -> dict:
    msgs = fusion_messages(wid, persona)
    last = ""
    for attempt in range(tries):
        try:
            res = await provider.chat(msgs, schema=SHEET_SCHEMA, max_tokens=900, temperature=0.7)
        except LLMError as exc:
            last = str(exc)
            continue
        if not res.data:
            last = f"JSON inválido: {res.text[:120]}"
            continue
        sheet = clean_sheet(res.data)
        missing = [k for k in ("full_name", "bio", "speech_style", "visual_prompt") if not sheet[k]]
        leaks = spoilers_in(sheet["bio"] + " " + sheet["family"] + " " + " ".join(sheet["fears"]))
        if missing or len(sheet["muletillas"]) < 2:
            last = f"faltan campos {missing}"
            continue
        problems = check_style(wid, sheet, others)
        if problems:
            last = "; ".join(problems)
            msgs = msgs + [{"role": "user", "content": f"Corrige esto: {last}. Vuelve a escribir el JSON completo."}]
            continue
        if leaks:
            last = f"la biografía menciona {leaks}"
            msgs = msgs + [{"role": "user", "content": f"No menciones {', '.join(leaks)}. Vuelve a escribir el JSON completo."}]
            continue
        return sheet
    raise SystemExit(f"No se pudo generar la ficha de {wid}: {last}")


def build_sheet(wid: str, persona: dict, fused: dict) -> dict:
    return {
        "id": wid,
        "story_name": data.witness_public(wid)["name"],
        **fused,
        "age": int(persona["age"]),
        "sex": persona["sex"],
        "voice": voice_profile(persona["sex"], int(persona["age"])),
        "persona": {
            "uuid": persona["uuid"],
            "dataset": DATASET,
            "occupation": persona["occupation"],
            "origin": f"{persona['municipality']}, {persona['department']}",
            "area": persona["area"],
            "marital_status": persona["marital_status"],
            "education_level": persona["education_level"],
        },
    }


def public_entry(sheet: dict) -> dict:
    return {k: sheet[k] for k in ("id", "full_name", "age", "occupation", "bio")}


def write_credits(sheets: list[dict]) -> None:
    rows = "\n".join(f"| {s['id']} | {s['full_name']} | `{s['persona']['uuid']}` |" for s in sheets)
    CREDITS.write_text(f"""# Créditos de datos

## Nemotron-Personas-El-Salvador

Las fichas de los testigos (`server/data/characters/`, `content/generated/characters_public.json`)
se basan en personas sintéticas del dataset **Nemotron-Personas-El-Salvador** de NVIDIA,
publicado bajo licencia [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/):
{DATASET_URL}

**Cambios:** cada persona se fusionó con un personaje ficticio del juego mediante un modelo de
lenguaje (nombre, oficio y lugar los define la historia; se trasladó a un pueblo ficticio).
Generado con `server/pipelines/personas.py`.

| Testigo | Nombre en el juego | uuid de la persona |
| --- | --- | --- |
{rows}
""", encoding="utf-8")


# ---------- programa ----------

async def run(args: argparse.Namespace) -> None:
    paths = shard_paths(args.shards)
    show_schema(paths[0])
    ids = args.only or [w["id"] for w in data.characters()["witnesses"]]
    all_ids = [w["id"] for w in data.characters()["witnesses"]]
    rows = load_rows(paths, COLUMNS_FOR_SCORING)
    print(f"\n{len(rows)} personas cargadas de {len(paths)} archivo(s).")
    # Se elige para todos (orden fijo) para que --only no cambie quién le toca a cada uno.
    choice = select(rows, all_ids)
    for wid in ids:
        print(f"\n{wid}:")
        for c in choice[wid]:
            print(f"  {c['_score']:>5}  {c['uuid'][:8]}  {c['sex'][0]} {c['age']:>3}  {c['area']:<6} "
                  f"{c['marital_status']:<11} {c['department']:<13} {c['occupation'][:60]}")
    if args.dry_run:
        return

    wanted = {choice[w][0]["uuid"] for w in ids}
    full = {r["uuid"]: r for r in load_rows(paths) if r["uuid"] in wanted}
    settings = Settings.from_env()
    settings = dataclasses.replace(settings, llm_timeout_s=max(settings.llm_timeout_s, 90.0))
    provider = get_provider(settings)
    SHEETS.mkdir(parents=True, exist_ok=True)
    done: set[str] = set()
    try:
        for wid in ids:
            out = SHEETS / f"{wid}.json"
            if out.exists() and not args.force:
                print(f"{wid}: ya existe (usa --force para regenerar)")
                continue
            persona = full[choice[wid][0]["uuid"]]
            others = [json.loads(p.read_text(encoding="utf-8")) for p in SHEETS.glob("*.json")
                      if p.stem != wid and (p.stem in done or not args.force)]
            fused = await fuse(provider, wid, persona, others)
            sheet = build_sheet(wid, persona, fused)
            out.write_text(json.dumps(sheet, ensure_ascii=False, indent=2), encoding="utf-8")
            done.add(wid)
            print(f"{wid}: {sheet['full_name']}, {sheet['age']} años — {sheet['bio'][:110]}…")
    finally:
        await provider.aclose()

    sheets = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(SHEETS.glob("*.json"))]
    order = {w: i for i, w in enumerate(all_ids)}
    sheets.sort(key=lambda s: order.get(s["id"], 99))
    PUBLIC.parent.mkdir(parents=True, exist_ok=True)
    PUBLIC.write_text(json.dumps({"source": DATASET, "license": "CC BY 4.0",
                                  "witnesses": [public_entry(s) for s in sheets]},
                                 ensure_ascii=False, indent=2), encoding="utf-8")
    write_credits(sheets)
    print(f"\nFichas: {SHEETS}\nPúblico: {PUBLIC}\nCréditos: {CREDITS}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--shards", type=int, default=1, choices=[1, 2, 3])
    ap.add_argument("--only", nargs="*", help="ids de testigos (por defecto, los 10)")
    ap.add_argument("--dry-run", action="store_true", help="solo elegir y mostrar candidatos")
    ap.add_argument("--force", action="store_true", help="regenerar fichas existentes")
    asyncio.run(run(ap.parse_args()))


if __name__ == "__main__":
    main()
