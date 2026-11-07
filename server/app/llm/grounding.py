"""Detector de detalles inventados en lo que dice un testigo.

El LLM tiende a rellenar: si le preguntan "¿quién más iba en el bus?" inventa
"Don Roque del molino"; si le preguntan la hora, dice "cuando dio la una". Aquí se
revisa la respuesta contra lo que el testigo SABE (su prompt), lo que dijo el
investigador y la conversación, y se marcan:

- horas que no aparecen en ese material ("a la una", "12:30");
- nombres propios de personas o lugares que no aparecen ("Don Roque", "la señora María").

Es determinista y barato. dialogue.py le pide al modelo que corrija y, si insiste,
quita la frase inventada.
"""
from __future__ import annotations

import re
import unicodedata

_UNITS = {"cero": 0, "una": 1, "uno": 1, "un": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
          "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12,
          "trece": 13, "catorce": 14, "quince": 15, "dieciseis": 16, "diecisiete": 17,
          "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiuno": 21, "veintiuna": 21,
          "veintidos": 22, "veintitres": 23, "veinticuatro": 24, "veinticinco": 25,
          "veintiseis": 26, "veintisiete": 27, "veintiocho": 28, "veintinueve": 29}
_TENS = {"treinta": 30, "cuarenta": 40, "cincuenta": 50}
_HOURS = "una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|[1-9]|1[0-2]"
_MIN_WORD = r"(?:cuarto|media|(?:treinta|cuarenta|cincuenta)(?: y \w+)?|\w+|\d{1,2})"

# "a las once y cuarenta", "eran como las doce", "dio la una", "antes de las diez".
_SPOKEN_TIME = re.compile(
    r"\b(?:a|de|desde|hasta|para|eran|era|son|es|dieron|dio|daban|daba|sonaron|sono|pasadas|tipo)"
    r"\s+(?:como\s+(?:a\s+)?|eso\s+de\s+|casi\s+)?(?:la|las)\s+(" + _HOURS + r")"
    # Grupo atómico: "y cuarenta y siete" no retrocede a "y cuarenta".
    r"(?>\s+(y|menos)\s+" + _MIN_WORD + r")?"
    # Lo que sigue debe ser fin de frase o una palabra que puede ir tras una hora;
    # así "las dos pupusas" no cuenta como hora.
    r"(?=\s*(?:$|[.,;:!?)]|(?:y|o|en|de|del|a|al|con|por|cuando|que|mas|menos|pasadas|ya|se|me|te|"
    r"le|lo|la|nos|fue|fui|era|iba|vi|paso|sono|dio|en punto|exactas|exacto|exactamente)\b))")
_DIGIT_TIME = re.compile(r"\b([0-2]?\d)[:.]([0-5]\d)\b")
_MIDNIGHT = re.compile(r"\bmedianoche\b")

# Título + nombre propio: "Don Roque", "la señora María" (sobre el texto original, con mayúsculas;
# el título en cualquier caja, el nombre con mayúscula inicial).
_TITLED_NAME = re.compile(
    r"\b(?i:don|doña|niña|niño|seño|señorita|señora|señor|padre|madre|sor|tío|tía|compadre|"
    r"comadre|mister|profesora|profesor|profe|doctora|doctor|licenciada|licenciado|joven)\s+"
    r"([A-ZÁÉÍÓÚÑ][a-záéíóúñü]+(?:\s+[A-ZÁÉÍÓÚÑ][a-záéíóúñü]+)?)")
_CAP_WORD = re.compile(r"[A-ZÁÉÍÓÚÑ][a-záéíóúñü]{2,}")
# Palabras con mayúscula que no son detalles inventados.
_ALWAYS_OK = {"dios", "diosito", "virgen", "santisimo", "jesus", "cristo", "senor", "senora",
              "usted", "ustedes", "salvador", "san", "santa", "animas", "difuntos", "ave", "maria",
              "santo", "espiritu", "papa", "mama", "ay", "puchica", "mire", "fijese", "oiga",
              "pues", "bueno", "va", "si", "no", "noviembre", "octubre"}


def fold(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def _number(words: str) -> int | None:
    words = words.strip()
    if words.isdigit():
        return int(words)
    if words in _UNITS:
        return _UNITS[words]
    if words in _TENS:
        return _TENS[words]
    m = re.fullmatch(r"(\w+) y (\w+)", words)
    if m and m.group(1) in _TENS and m.group(2) in _UNITS and _UNITS[m.group(2)] < 10:
        return _TENS[m.group(1)] + _UNITS[m.group(2)]
    return None


def times_in(text: str) -> set[tuple[int, int | None]]:
    """Horas mencionadas como (hora 1-12, minutos o None si solo dice la hora)."""
    t = fold(text)
    out: set[tuple[int, int | None]] = set()
    for h, m in _DIGIT_TIME.findall(t):
        hh = int(h) % 12 or 12
        out.add((hh, int(m)))
    for m in _SPOKEN_TIME.finditer(t):
        hour = _number(m.group(1))
        if hour is None:
            continue
        minutes: int | None = None
        if m.group(2):
            rest = m.group(0).split(" " + m.group(2) + " ", 1)[-1].strip()
            val = {"cuarto": 15, "media": 30}.get(rest, _number(rest))
            if val is not None:
                if m.group(2) == "menos":
                    hour, val = (hour - 2) % 12 + 1, 60 - val
                minutes = val
        out.add((hour, minutes))
    if _MIDNIGHT.search(t):
        out.add((12, None))
    return out


def invented_times(reply: str, known: str) -> list[tuple[int, int | None]]:
    allowed = times_in(known)
    allowed_hours = {h for h, _ in allowed}
    bad = []
    for h, m in sorted(times_in(reply), key=lambda x: (x[0], x[1] or 0)):
        if (h, m) in allowed:
            continue
        if m is None and h in allowed_hours:
            continue  # "como a las once" cuando sabe "11:47": es una aproximación válida
        bad.append((h, m))
    return bad


def _sentence_starts(text: str) -> set[int]:
    starts = {0}
    for m in re.finditer(r"[.!?¿¡:«\"“]\s*", text):
        starts.add(m.end())
    return starts


def invented_names(reply: str, known: str) -> list[str]:
    """Nombres propios de la respuesta que no aparecen en lo que el testigo sabe."""
    k = fold(known)
    known_words = set(re.findall(r"\w+", k))
    bad: list[str] = []
    for m in _TITLED_NAME.finditer(reply):
        name = m.group(1)
        if not all(fold(w) in known_words for w in name.split()):
            bad.append(m.group(0))
    starts = _sentence_starts(reply)
    for m in _CAP_WORD.finditer(reply):
        w = fold(m.group(0))
        if m.start() in starts or w in _ALWAYS_OK or w in known_words:
            continue
        if any(m.group(0) in b for b in bad):
            continue
        bad.append(m.group(0))
    return bad


def invented(reply: str, known: str) -> list[str]:
    """Lista legible de detalles inventados (vacía si todo está respaldado)."""
    out = [f"la hora {h}:{m:02d}" if m is not None else f"la hora {h}"
           for h, m in invented_times(reply, known)]
    out += [f"el nombre «{n}»" for n in invented_names(reply, known)]
    return out


def drop_invented_sentences(reply: str, known: str) -> str:
    """Quita las frases que traen un detalle inventado. Devuelve "" si no queda nada."""
    parts = [p for p in re.split(r"(?<=[^.][.!?])\s+", reply.strip()) if p]
    keep = [p for p in parts if not invented(p, known)]
    return " ".join(keep).strip()
