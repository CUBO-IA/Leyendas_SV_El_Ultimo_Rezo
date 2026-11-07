"""B5: retratos en assets_generated/portraits/{id}_{emocion}.png (512x512)."""
from __future__ import annotations

import pytest
from PIL import Image

from server.app import data
from server.pipelines import portraits as P

from .conftest import ROOT

OUT = ROOT / "assets_generated" / "portraits"
EMOTIONS = {"neutral", "nervioso", "enojado", "asustado", "triste", "aliviado"}


def test_referencias_bien_mapeadas():
    witnesses = {w["id"] for w in data.characters()["witnesses"]}
    ids = [wid for wid, _ in P.REFERENCES.values()]
    assert set(ids) == witnesses and len(ids) == len(set(ids))
    assert all(emo in EMOTIONS for _, emo in P.REFERENCES.values())
    assert "Nayik.png" not in P.REFERENCES
    assert set(P.SUSPECTS) == {s["id"] for s in data.characters()["suspects"]}


@pytest.mark.skipif(not OUT.exists(), reason="aún no se corre server.pipelines.portraits")
def test_cada_personaje_tiene_neutral_512():
    ids = [w["id"] for w in data.characters()["witnesses"]] + [s["id"] for s in data.characters()["suspects"]]
    for cid in ids:
        path = OUT / f"{cid}_neutral.png"
        assert path.exists(), cid
        with Image.open(path) as im:
            assert im.size == (512, 512), cid
    for path in OUT.glob("*.png"):
        cid, emo = path.stem.rsplit("_", 1)
        assert emo in EMOTIONS, path.name


def test_busto_cuadrado_y_compuesto():
    fig = Image.new("RGBA", (300, 600), (0, 0, 0, 0))
    fig.paste((200, 120, 80, 255), (100, 50, 200, 550))
    b = P.bust(fig)
    assert b.width == b.height == int(500 * 0.6)
    out = P.compose(b)
    assert out.size == (512, 512) and out.mode == "RGB"


def test_cada_testigo_tiene_las_6_emociones():
    for w in data.characters()["witnesses"]:
        for emo in EMOTIONS:
            path = OUT / f"{w['id']}_{emo}.png"
            assert path.exists(), path.name
            with Image.open(path) as im:
                assert im.size == (512, 512), path.name


def test_emocion_derivada_cambia_color_y_lleva_icono():
    base = Image.new("RGB", (512, 512), (120, 120, 120))
    for emo in P.DERIVED:
        out = P.derive(base, emo)
        assert out.size == (512, 512)
        assert out.getpixel((10, 400)) != (120, 120, 120), emo  # gradación
        corner = {c for _, c in out.crop((512 - 120, 20, 512, 140)).getcolors(1 << 16)}
        assert len(corner - {out.getpixel((512 - 8, 400))}) >= 1 and len(corner) >= 2, emo  # el ícono
    assert set(P.DERIVED) == EMOTIONS - {"neutral"} and set(P.ICONS) == {v[4] for v in P.DERIVED.values()}


def test_las_emociones_dibujadas_no_se_reemplazan():
    # Mercedes trae "enojado" dibujado: es idéntico a su neutral (mismo dibujo), no un derivado.
    a = Image.open(OUT / "mercedes_enojado.png").convert("RGB")
    b = Image.open(OUT / "mercedes_neutral.png").convert("RGB")
    assert a.tobytes() == b.tobytes()


def test_cipitio_con_arte_del_equipo():
    path, _, _ = P.TEAM_SUSPECTS["cipitio"]
    assert path.exists() and path.name == "Cipitio.png"
