"""Voz: texto a voz (Magpie TTS Multilingual) y voz a texto (Parakeet CTC 0.6B español),
ambos alojados en build.nvidia.com y servidos por gRPC (Riva) con la NVIDIA_API_KEY.

- La síntesis arranca en segundo plano al responder /talk o /present: el texto sale ya,
  y GET /audio/{id}.mp3 espera a que termine si hace falta. Caché en server/cache/audio/.
- Si la voz falla, el juego sigue con texto (audio_url = null).
"""
from __future__ import annotations

import asyncio
import audioop
import hashlib
import io
import logging
import re
import time
import wave
from dataclasses import dataclass
from pathlib import Path

from . import data
from .config import ROOT, Settings

log = logging.getLogger("leyendas.voice")

AUDIO_DIR = ROOT / "server" / "cache" / "audio"
AUDIO_ID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
TTS_RATE = 22050
STT_RATE = 16000
MAX_STT_SECONDS = 30

# Voz Magpie de cada testigo (ES-US). Isabela y Diego tienen variantes por emoción.
VOICES: dict[str, str] = {
    "chonita": "ES-US.Isabela", "mercedes": "ES-US.Sofia",
    "ramirez": "ES-US.Diego", "padre_mauricio": "ES-US.Pascal", "tonito": "ES-US.Jason",
    "alcides": "ES-US.Ray", "chepe": "ES-US.Leo", "chente": "ES-US.Leo",
    "beto": "ES-US.Diego", "pilo": "ES-US.Jason",
}
DEFAULT_VOICE = {"female": "ES-US.Isabela", "male": "ES-US.Diego"}
EMOTION_STYLE = {"neutral": "Neutral", "nervioso": "Neutral", "enojado": "Angry",
                 "asustado": "Sad", "triste": "Sad", "aliviado": "Calm"}
STYLED = {"ES-US.Isabela": {"Neutral", "Calm", "Sad", "Angry", "Happy"},
          "ES-US.Diego": {"Neutral", "Calm", "Angry", "Happy", "PleasantSurprised"}}


class VoiceError(RuntimeError):
    pass


def voice_for(witness_id: str, emotion: str = "neutral") -> str:
    base = VOICES.get(witness_id)
    if not base:
        sheet = data.witness_sheet(witness_id) or {}
        gender = (sheet.get("voice") or {}).get("gender", "male")
        base = DEFAULT_VOICE.get(gender, "ES-US.Diego")
    style = EMOTION_STYLE.get(emotion, "Neutral")
    return f"Magpie-Multilingual.{base}.{style}" if style in STYLED.get(base, set()) \
        else f"Magpie-Multilingual.{base}"


def audio_id(voice: str, text: str) -> str:
    return hashlib.sha1(f"{voice}\x1f{text}".encode("utf-8")).hexdigest()[:24]


def pcm_to_mp3(pcm: bytes, rate: int) -> bytes:
    import lameenc
    enc = lameenc.Encoder()
    enc.set_bit_rate(64)
    enc.set_in_sample_rate(rate)
    enc.set_channels(1)
    enc.set_quality(5)
    return enc.encode(pcm) + enc.flush()


_MISPLACED_OPEN = re.compile(r"(\w+)([¿¡])", re.UNICODE)


def tidy_transcript(text: str) -> str:
    """El reconocedor pone '¿' y '¡' después de la palabra ('Qué¿ vio'): los regresa a su lugar."""
    text = _MISPLACED_OPEN.sub(lambda m: m.group(2) + m.group(1), text)
    return re.sub(r"\s+", " ", text).strip()


def wav_to_pcm16k(wav_bytes: bytes) -> bytes:
    """WAV cualquiera (16 bits, mono o estéreo, cualquier frecuencia) -> PCM 16 kHz mono."""
    try:
        with wave.open(io.BytesIO(wav_bytes)) as w:
            channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            pcm = w.readframes(frames)
    except (wave.Error, EOFError) as exc:
        raise VoiceError(f"No es un WAV válido: {exc}") from exc
    if width != 2:
        raise VoiceError("El WAV debe ser de 16 bits.")
    if frames / max(rate, 1) > MAX_STT_SECONDS:
        raise VoiceError(f"El audio dura más de {MAX_STT_SECONDS} s.")
    if channels == 2:
        pcm = audioop.tomono(pcm, 2, 0.5, 0.5)
    elif channels != 1:
        raise VoiceError("El WAV debe ser mono o estéreo.")
    if rate != STT_RATE:
        pcm, _ = audioop.ratecv(pcm, 2, 1, rate, STT_RATE, None)
    return pcm


@dataclass
class VoiceStatus:
    tts: bool = False
    stt: bool = False


class Voice:
    """TTS/STT por Riva. Las llamadas gRPC son bloqueantes: van a un hilo aparte."""

    def __init__(self, settings: Settings, audio_dir: Path | None = None):
        self.settings = settings
        self.audio_dir = audio_dir or AUDIO_DIR
        self.status = VoiceStatus()
        self._tasks: dict[str, asyncio.Task] = {}
        self._tts = None
        self._asr = None
        self.asr_function_id = ""
        self.audio_dir.mkdir(parents=True, exist_ok=True)

    # ---------- conexión ----------

    def _auth(self, function_id: str):
        import riva.client
        return riva.client.Auth(None, True, self.settings.riva_server,
                                [["function-id", function_id],
                                 ["authorization", f"Bearer {self.settings.nvidia_api_key}"]])

    def _tts_service(self):
        if self._tts is None:
            import riva.client
            self._tts = riva.client.SpeechSynthesisService(self._auth(self.settings.tts_function_id))
        return self._tts

    def _asr_service(self):
        if self._asr is None:
            import riva.client
            self._asr = riva.client.ASRService(self._auth(self.asr_function_id))
        return self._asr

    @property
    def asr_candidates(self) -> list[str]:
        return [f.strip() for f in self.settings.asr_function_ids.split(",") if f.strip()]

    async def warmup(self) -> None:
        """Comprueba que los servicios responden; /health refleja el resultado."""
        if not self.settings.nvidia_api_key:
            return
        if self.settings.tts_provider == "magpie":
            try:
                await asyncio.to_thread(self._synth_pcm, "Buenas noches.", voice_for("chonita"))
                self.status.tts = True
            except Exception as exc:
                log.warning("TTS no disponible: %s", exc)
        if self.settings.stt_provider == "nvidia":
            silence = b"\x00\x00" * (STT_RATE // 2)  # medio segundo de silencio
            for fid in self.asr_candidates:
                self.asr_function_id, self._asr = fid, None
                try:
                    await asyncio.to_thread(self._recognize, silence)
                    self.status.stt = True
                    log.info("STT con la función %s", fid)
                    break
                except Exception as exc:
                    log.warning("STT %s no disponible: %s", fid, str(exc)[:160])

    # ---------- texto a voz ----------

    def _synth_pcm(self, text: str, voice: str) -> bytes:
        import riva.client
        resp = self._tts_service().synthesize(
            text, voice_name=voice, language_code="es-US",
            encoding=riva.client.AudioEncoding.LINEAR_PCM, sample_rate_hz=TTS_RATE)
        return resp.audio

    def _synth_to_file(self, text: str, voice: str, path: Path) -> None:
        t0 = time.perf_counter()
        mp3 = pcm_to_mp3(self._synth_pcm(text, voice), TTS_RATE)
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(mp3)
        tmp.replace(path)
        log.info("TTS %s (%d bytes) en %.2f s", path.name, len(mp3), time.perf_counter() - t0)

    def request_audio(self, witness_id: str, text: str, emotion: str) -> str | None:
        """Agenda la síntesis y devuelve el audio_url (o None si la voz está apagada)."""
        if not self.status.tts:
            return None
        voice = voice_for(witness_id, emotion)
        aid = audio_id(voice, text)
        path = self.audio_dir / f"{aid}.mp3"
        if not path.exists() and aid not in self._tasks:
            task = asyncio.create_task(asyncio.to_thread(self._synth_to_file, text, voice, path))
            self._tasks[aid] = task
            task.add_done_callback(lambda _t, a=aid: self._tasks.pop(a, None))
        return f"/audio/{aid}.mp3"

    async def audio_path(self, aid: str, timeout: float = 20.0) -> Path | None:
        if not AUDIO_ID.match(aid):
            return None
        path = self.audio_dir / f"{aid}.mp3"
        task = self._tasks.get(aid)
        if task is not None:
            try:
                await asyncio.wait_for(asyncio.shield(task), timeout)
            except Exception as exc:
                log.warning("TTS %s falló: %s", aid, exc)
                return None
        return path if path.exists() else None

    # ---------- voz a texto ----------

    def _recognize(self, pcm16k: bytes) -> str:
        import riva.client
        config = riva.client.RecognitionConfig(
            encoding=riva.client.AudioEncoding.LINEAR_PCM, sample_rate_hertz=STT_RATE,
            audio_channel_count=1, language_code="es-US", max_alternatives=1,
            enable_automatic_punctuation=True)
        resp = self._asr_service().offline_recognize(pcm16k, config)
        return " ".join(r.alternatives[0].transcript.strip() for r in resp.results
                        if r.alternatives).strip()

    async def transcribe(self, wav_bytes: bytes) -> str:
        if not self.status.stt:
            raise VoiceError("El reconocimiento de voz no está disponible.")
        pcm = wav_to_pcm16k(wav_bytes)
        t0 = time.perf_counter()
        try:
            text = tidy_transcript(await asyncio.wait_for(asyncio.to_thread(self._recognize, pcm), 20))
        except Exception as exc:
            raise VoiceError(f"No se pudo transcribir: {exc}") from exc
        log.info("STT %.1f s de audio en %.2f s: %s", len(pcm) / 2 / STT_RATE, time.perf_counter() - t0, text)
        return text
