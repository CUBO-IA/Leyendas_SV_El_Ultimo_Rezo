"""B4: voz (TTS y STT) sin red, con un servicio de voz falso."""
from __future__ import annotations

import io
import math
import re
import struct
import time
import wave

from server.app import voice as V
from server.app.config import Settings

from .conftest import FakeProvider, assert_valid


class FakeVoice(V.Voice):
    """Sintetiza un tono corto y 'reconoce' siempre la misma frase."""

    def __init__(self, settings: Settings, audio_dir=None, tts: bool = True, stt: bool = True):
        super().__init__(settings, audio_dir)
        self.status = V.VoiceStatus(tts=tts, stt=stt)
        self.synth_calls: list[tuple[str, str]] = []

    async def warmup(self) -> None:
        pass

    def _synth_pcm(self, text: str, voice: str) -> bytes:
        self.synth_calls.append((text, voice))
        n = V.TTS_RATE // 5
        return b"".join(struct.pack("<h", int(8000 * math.sin(i / 10))) for i in range(n))

    def _recognize(self, pcm16k: bytes) -> str:
        self.last_pcm = pcm16k
        return "Buenas noches, doña."


def wav(seconds: float, rate: int = 48000, channels: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00" * channels * int(rate * seconds))
    return buf.getvalue()


def make(make_client, tmp_path, **kw):
    voice = FakeVoice(Settings(db_path=tmp_path / "v.db"), tmp_path / "audio", **kw)
    from fastapi.testclient import TestClient
    from server.app.main import create_app
    c = TestClient(create_app(Settings(db_path=tmp_path / "v.db"), FakeProvider(), voice))
    c.__enter__()
    return c, voice


def talk(c, sid, want=True, text="¿Qué vio?"):
    return c.post("/talk", json={"session_id": sid, "npc_id": "chonita", "text": text, "want_audio": want})


def test_health_refleja_la_voz(make_client, tmp_path):
    c, _ = make(make_client, tmp_path)
    body = c.get("/health").json()
    assert body["tts"] is True and body["stt"] is True
    c.__exit__(None, None, None)


def test_talk_con_audio_y_descarga_mp3(make_client, tmp_path):
    c, voice = make(make_client, tmp_path)
    sid = c.post("/session").json()["session_id"]
    body = talk(c, sid).json()
    assert_valid("talk_response", body)
    assert re.match(r"^/audio/[A-Za-z0-9_-]+\.mp3$", body["audio_url"])
    r = c.get(body["audio_url"])
    assert r.status_code == 200 and r.headers["content-type"] == "audio/mpeg"
    assert r.content[:3] == b"ID3" or r.content[0] == 0xFF  # cabecera MP3
    text, used_voice = voice.synth_calls[-1]
    assert text == body["reply"] and used_voice.startswith("Magpie-Multilingual.ES-US.Isabela")
    # La misma frase con la misma voz no se sintetiza dos veces.
    n = len(voice.synth_calls)
    sid2 = c.post("/session").json()["session_id"]
    again = talk(c, sid2).json()
    assert again["audio_url"] == body["audio_url"]
    c.get(again["audio_url"])
    assert len(voice.synth_calls) == n
    c.__exit__(None, None, None)


def test_sin_want_audio_o_sin_tts_no_hay_audio(make_client, tmp_path):
    c, _ = make(make_client, tmp_path)
    sid = c.post("/session").json()["session_id"]
    assert talk(c, sid, want=False).json()["audio_url"] is None
    c.__exit__(None, None, None)
    c2, _ = make(make_client, tmp_path, tts=False)
    sid = c2.post("/session").json()["session_id"]
    assert talk(c2, sid).json()["audio_url"] is None
    c2.__exit__(None, None, None)


def test_present_con_audio(make_client, tmp_path):
    c, _ = make(make_client, tmp_path)
    sid = c.post("/session").json()["session_id"]
    c.post("/examine", json={"session_id": sid, "object_id": "tablero_electrico"})
    body = c.post("/present", json={"session_id": sid, "npc_id": "alcides",
                                     "evidence_id": "registro_electrico", "want_audio": True}).json()
    assert_valid("present_response", body)
    assert body["audio_url"] and c.get(body["audio_url"]).status_code == 200
    c.__exit__(None, None, None)


def test_audio_inexistente_o_ruta_maliciosa(make_client, tmp_path):
    c, _ = make(make_client, tmp_path)
    for path in ["/audio/no_existe_1234567.mp3", "/audio/..%2F..%2Fserver%2F.env", "/audio/abc.wav"]:
        r = c.get(path)
        assert r.status_code == 404, path
        assert_valid("api_error", r.json())
    c.__exit__(None, None, None)


def test_stt_wav_estereo_48k(make_client, tmp_path):
    c, voice = make(make_client, tmp_path)
    r = c.post("/stt", content=wav(1.0), headers={"Content-Type": "audio/wav"})
    assert r.status_code == 200
    assert_valid("stt_response", r.json())
    assert r.json()["text"] == "Buenas noches, doña."
    assert len(voice.last_pcm) == V.STT_RATE * 2  # 1 s a 16 kHz mono, 16 bits
    c.__exit__(None, None, None)


def test_stt_errores(make_client, tmp_path):
    c, _ = make(make_client, tmp_path)
    for content, code, status in [(b"", "bad_request", 400), (b"no soy un wav", "stt_failed", 502),
                                  (wav(31, rate=8000, channels=1), "stt_failed", 502)]:
        r = c.post("/stt", content=content, headers={"Content-Type": "audio/wav"})
        assert r.status_code == status, code
        assert_valid("api_error", r.json())
        assert r.json()["error"] == code
    c.__exit__(None, None, None)
    c2, _ = make(make_client, tmp_path, stt=False)
    r = c2.post("/stt", content=wav(1), headers={"Content-Type": "audio/wav"})
    assert r.status_code == 502 and r.json()["error"] == "stt_failed"
    c2.__exit__(None, None, None)


def test_signos_de_apertura_en_su_lugar():
    assert V.tidy_transcript("Buenas noches. Qué¿ vio esta noche en la plaza?") == \
        "Buenas noches. ¿Qué vio esta noche en la plaza?"
    assert V.tidy_transcript("doña A¿ qué hora cerró?") == "doña ¿A qué hora cerró?"
    assert V.tidy_transcript("Puchica¡ qué miedo!") == "¡Puchica qué miedo!"
    assert V.tidy_transcript("¿Qué vio?") == "¿Qué vio?"


def test_voz_por_testigo_y_emocion():
    assert V.voice_for("chonita", "enojado") == "Magpie-Multilingual.ES-US.Isabela.Angry"
    assert V.voice_for("chonita", "nervioso") == "Magpie-Multilingual.ES-US.Isabela.Neutral"
    assert V.voice_for("ramirez", "triste") == "Magpie-Multilingual.ES-US.Diego"  # Diego no tiene Sad
    assert V.voice_for("mercedes", "enojado") == "Magpie-Multilingual.ES-US.Sofia"  # sin variantes
    assert V.audio_id("a", "b") == V.audio_id("a", "b") != V.audio_id("a", "c")
