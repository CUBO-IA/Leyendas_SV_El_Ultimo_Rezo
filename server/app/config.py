"""Configuración del motor, leída del .env de la raíz del repo.

Las claves llevan repr=False para que nunca aparezcan en logs ni en tracebacks.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]


def _bool(value: str | None, default: bool = False) -> bool:
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "si", "sí", "on"}


@dataclass(frozen=True)
class Settings:
    api_host: str = "127.0.0.1"
    api_port: int = 8000
    demo_mode: bool = False

    # Diálogo
    llm_provider: str = "ollama"  # ollama | nvidia
    llm_model: str = "nemotron-3-nano:4b"  # modelo de Ollama
    ollama_url: str = "http://127.0.0.1:11434"
    nvidia_model: str = "nvidia/nemotron-3.5-lightning-30b-a3b"
    nvidia_base_url: str = "https://integrate.api.nvidia.com/v1"
    nvidia_api_key: str = field(default="", repr=False)
    llm_timeout_s: float = 30.0
    llm_reply_timeout_s: float = 12.0  # tope por respuesta en juego; luego, frase de respaldo
    warmup: bool = True

    # Voz (B4): Magpie TTS y Parakeet ES por gRPC (Riva) en build.nvidia.com
    stt_provider: str = "nvidia"  # nvidia | none
    stt_api_key: str = field(default="", repr=False)
    tts_provider: str = "magpie"  # magpie | none
    riva_server: str = "grpc.nvcf.nvidia.com:443"
    tts_function_id: str = "877104f7-e885-42b9-8de8-f6e4c6303969"  # magpie-tts-multilingual
    # Reconocedores en orden de preferencia; el calentamiento usa el primero que responda.
    # parakeet-1_1b-rnnt-multilingual (responde hoy) y parakeet-ctc-0_6b-es (sin servidores el 2026-11-06).
    asr_function_ids: str = "71203149-d3b7-4460-8231-1be2543a1fca,a9eeee8f-b509-4712-b19d-194361fa5f31"
    voice_warmup: bool = True

    # Estado
    db_path: Path = ROOT / "server" / "sessions.db"

    @property
    def active_model(self) -> str:
        return self.nvidia_model if self.llm_provider == "nvidia" else self.llm_model

    @classmethod
    def from_env(cls, env_file: Path | None = ROOT / ".env") -> "Settings":
        if env_file and env_file.exists():
            load_dotenv(env_file, override=False)
        e = os.environ.get
        d = cls()
        return cls(
            api_host=e("API_HOST", d.api_host),
            api_port=int(e("API_PORT", d.api_port)),
            demo_mode=_bool(e("DEMO_MODE"), d.demo_mode),
            llm_provider=e("LLM_PROVIDER", d.llm_provider).strip().lower(),
            llm_model=e("LLM_MODEL", d.llm_model),
            ollama_url=e("OLLAMA_URL", d.ollama_url).rstrip("/"),
            nvidia_model=e("NVIDIA_MODEL", d.nvidia_model),
            nvidia_base_url=e("NVIDIA_BASE_URL", d.nvidia_base_url).rstrip("/"),
            nvidia_api_key=e("NVIDIA_API_KEY", ""),
            llm_timeout_s=float(e("LLM_TIMEOUT_S", d.llm_timeout_s)),
            llm_reply_timeout_s=float(e("LLM_REPLY_TIMEOUT_S", d.llm_reply_timeout_s)),
            warmup=_bool(e("LLM_WARMUP"), d.warmup),
            stt_provider=e("STT_PROVIDER", d.stt_provider).strip().lower(),
            stt_api_key=e("STT_API_KEY", ""),
            tts_provider=e("TTS_PROVIDER", d.tts_provider).strip().lower(),
            riva_server=e("RIVA_SERVER", d.riva_server),
            tts_function_id=e("TTS_FUNCTION_ID", d.tts_function_id),
            asr_function_ids=e("ASR_FUNCTION_IDS", d.asr_function_ids),
            voice_warmup=_bool(e("VOICE_WARMUP"), d.voice_warmup),
            db_path=Path(e("DB_PATH", str(d.db_path))),
        )
