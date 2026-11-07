"""Motor de Leyendas SV. Arranque:  .venv\\Scripts\\python -m server"""
from __future__ import annotations

import asyncio
import logging
import secrets
from collections import defaultdict
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from . import data, errors, game, rules
from .config import Settings
from .dialogue import SITUATIONS, Dialogue, clean_player_text, evidence_message
from .errors import ApiError
from .llm.provider import Provider, get_provider
from .presence import PresenceHub
from .store import SessionStore
from .voice import Voice, VoiceError

log = logging.getLogger("leyendas")


class SessionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    player_name: str | None = Field(default=None, max_length=40)
    demo: bool | None = None


class _Req(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: str = Field(min_length=1, max_length=64)


class TalkRequest(_Req):
    npc_id: str = Field(max_length=64)
    text: str = Field(min_length=1, max_length=300)
    want_audio: bool = False


class PresentRequest(_Req):
    npc_id: str = Field(max_length=64)
    evidence_id: str = Field(max_length=64)
    want_audio: bool = False


class ExamineRequest(_Req):
    object_id: str = Field(max_length=64)


class AccuseRequest(_Req):
    suspect_id: str = Field(max_length=64)
    evidence_ids: list[str] = Field(max_length=10)
    decision: Literal["revelar", "negociar"]


class LLMState:
    """Estado del calentamiento: /health dice warm=false hasta que el modelo responde."""

    def __init__(self) -> None:
        self.warm = False
        self.error: str | None = None


async def _warmup(provider: Provider, state: LLMState) -> None:
    try:
        await provider.warmup()
        state.warm = True
        log.info("Modelo %s/%s caliente", provider.name, provider.model)
    except Exception as exc:  # el motor sigue vivo; /talk usará respaldos
        state.error = str(exc)
        log.warning("Calentamiento falló: %s", exc)


def create_app(settings: Settings | None = None, provider: Provider | None = None,
               voice: Voice | None = None) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = settings
        app.state.store = SessionStore(settings.db_path)
        app.state.llm = LLMState()
        try:
            app.state.provider = provider or get_provider(settings)
        except Exception as exc:
            app.state.provider = None
            app.state.llm.error = str(exc)
            log.error("No se pudo crear el proveedor LLM: %s", exc)
        app.state.dialogue = Dialogue(app.state.provider, timeout_s=settings.llm_reply_timeout_s)
        app.state.locks = defaultdict(asyncio.Lock)  # un candado por sesión
        app.state.voice = voice or Voice(settings)
        voice_task = None
        if settings.voice_warmup:
            voice_task = asyncio.create_task(app.state.voice.warmup())
        task = None
        if app.state.provider is not None:
            if settings.warmup:
                task = asyncio.create_task(_warmup(app.state.provider, app.state.llm))
            else:
                app.state.llm.warm = True
        yield
        for t_ in (task, voice_task):
            if t_ and not t_.done():
                t_.cancel()
        if app.state.provider is not None:
            await app.state.provider.aclose()
        app.state.store.close()

    app = FastAPI(title="Leyendas SV — motor", version="0.1.0", lifespan=lifespan)
    errors.install(app)
    presence = PresenceHub(settings.access_code)  # experimental: partidas compartidas

    @app.middleware("http")
    async def access_code(request: Request, call_next):
        """Motor público (Funnel): sin el código de acceso solo responde /health."""
        code = settings.access_code
        if code and request.url.path != "/health":
            given = request.headers.get("x-leyendas-code", "")
            if not secrets.compare_digest(given.encode(), code.encode()):
                return JSONResponse({"error": "forbidden", "detail": "Falta el código de acceso de esta partida."},
                                    status_code=403)
        return await call_next(request)

    @app.websocket("/ws/presence")
    async def ws_presence(ws: WebSocket):
        await presence.handle(ws)

    @app.get("/lobby")
    async def lobby(request: Request):
        """Partidas con jugadores conectados, para "Unirse a una partida"."""
        games = []
        for g in presence.lobby():
            try:
                public = _load(request, g["session_id"])[0]
            except ApiError:
                continue
            if public.get("ended"):
                continue
            games.append({**g, "act": public["act"], "clock": public["clock"],
                          "evidence": len(public["evidence"])})
        return {"games": games}

    @app.get("/health")
    async def health(request: Request):
        st = request.app.state
        ok = st.provider is not None and st.llm.warm and not st.llm.error
        return {
            "status": "ok" if ok else "degraded",
            "model": st.provider.model if st.provider else settings.active_model,
            "warm": st.llm.warm,
            "tts": st.voice.status.tts,
            "stt": st.voice.status.stt,
            "demo_mode": settings.demo_mode,
        }

    @app.post("/session")
    async def create_session(request: Request, body: SessionRequest | None = None):
        body = body or SessionRequest()
        demo = bool(body.demo) or settings.demo_mode
        sid = game.new_session_id()
        public, private = game.new_world_state(sid, demo=demo, only_mvp=settings.witnesses == "mvp")
        private["player_name"] = body.player_name or "Investigador"
        request.app.state.store.create(sid, public, private)
        return public

    @app.get("/session/{session_id}")
    async def get_session(request: Request, session_id: str):
        return _load(request, session_id)[0]

    @app.post("/talk")
    async def talk(request: Request, body: TalkRequest):
        st = request.app.state
        async with st.locks[body.session_id]:
            public, private = _load(request, body.session_id)
            rules.ensure_playing(public)
            npc = rules.npc(public, body.npc_id)
            text = clean_player_text(body.text)
            if not text:
                raise ApiError("bad_request", "El texto está vacío.")

            said, source = await st.dialogue.talk(npc, private, text)
            outcome = rules.talk(public, npc["id"], said["trust_delta"], said["fear_delta"])
            if outcome.kind == "confess":
                # La confianza alcanzó el umbral: el testigo se abre (guía de confesión).
                st.dialogue.forget_last(private, npc["id"])
                said, source = await st.dialogue.react(
                    npc, private, SITUATIONS["trust_confess"], text, "trust_confess")
            st.store.save(body.session_id, public, private)
            result = {
                "reply": said["reply"], "emotion": said["emotion"], "level": npc["level"],
                "trust": npc["trust"], "fear": npc["fear"],
                "new_evidence": outcome.new_evidence, "new_deductions": outcome.new_deductions,
                "audio_url": _audio(request, body.want_audio, npc["id"], said),
                "source": source, "state": public,
            }
            await presence.notify_world(body.session_id)  # los demás de la partida se actualizan
            return result

    @app.post("/present")
    async def present(request: Request, body: PresentRequest):
        st = request.app.state
        async with st.locks[body.session_id]:
            public, private = _load(request, body.session_id)
            rules.ensure_playing(public)
            outcome = rules.present(public, body.npc_id, body.evidence_id)
            npc = rules.npc(public, body.npc_id)
            shown = private.setdefault("presented", {}).setdefault(npc["id"], [])
            if body.evidence_id not in shown:
                shown.append(body.evidence_id)
            said, source = await st.dialogue.react(
                npc, private, SITUATIONS[outcome.kind], evidence_message(body.evidence_id),
                f"present:{body.evidence_id}:{outcome.kind}")
            st.store.save(body.session_id, public, private)
            result = {
                "reply": said["reply"], "emotion": said["emotion"],
                "contradiction": outcome.changed_level, "level": npc["level"],
                "new_deductions": outcome.new_deductions, "new_evidence": outcome.new_evidence,
                "trust": npc["trust"], "fear": npc["fear"],
                "audio_url": _audio(request, body.want_audio, npc["id"], said),
                "source": source, "state": public,
            }
            await presence.notify_world(body.session_id)
            return result

    @app.post("/examine")
    async def examine(request: Request, body: ExamineRequest):
        st = request.app.state
        async with st.locks[body.session_id]:
            public, private = _load(request, body.session_id)
            rules.ensure_playing(public)
            text, new = rules.examine(public, body.object_id)
            examined = private.setdefault("examined", [])
            if body.object_id not in examined:
                examined.append(body.object_id)
            st.store.save(body.session_id, public, private)
            await presence.notify_world(body.session_id)
            return {"text": text, "new_evidence": new, "state": public}

    @app.post("/accuse")
    async def accuse(request: Request, body: AccuseRequest):
        st = request.app.state
        async with st.locks[body.session_id]:
            public, private = _load(request, body.session_id)
            rules.ensure_playing(public)
            if body.suspect_id not in {s["id"] for s in data.characters()["suspects"]}:
                raise ApiError("bad_request", f"No existe el sospechoso {body.suspect_id}.")
            ending = rules.accuse(public, body.suspect_id, body.evidence_ids, body.decision)
            private["ending"] = ending["ending_id"]
            st.store.save(body.session_id, public, private)
            await presence.notify_ended(body.session_id, ending)  # el final, para todos
            return ending

    @app.get("/audio/{audio_file}")
    async def audio(request: Request, audio_file: str):
        aid = audio_file.removesuffix(".mp3")
        path = None
        if audio_file.endswith(".mp3"):
            path = await request.app.state.voice.audio_path(aid)
        if path is None:
            return JSONResponse({"error": "bad_request", "detail": "Ese audio no existe o no se pudo generar."},
                                status_code=404)
        return FileResponse(path, media_type="audio/mpeg")

    @app.post("/stt")
    async def stt(request: Request):
        """Recibe el WAV crudo (Content-Type: audio/wav, 16 bits, máx. 30 s)."""
        body = await request.body()
        if not body:
            raise ApiError("bad_request", "Falta el audio (WAV en el cuerpo de la petición).")
        if len(body) > 6 * 1024 * 1024:
            raise ApiError("bad_request", "El audio es demasiado grande.")
        try:
            text = await request.app.state.voice.transcribe(body)
        except VoiceError as exc:
            raise ApiError("stt_failed", str(exc))
        return {"text": text}

    return app


def _audio(request: Request, want: bool, witness_id: str, said: dict) -> str | None:
    """audio_url de la respuesta; la síntesis sigue en segundo plano."""
    if not want:
        return None
    try:
        return request.app.state.voice.request_audio(witness_id, said["reply"], said["emotion"])
    except Exception as exc:  # la voz nunca tumba una respuesta de texto
        log.warning("No se pudo agendar el audio: %s", exc)
        return None


def _load(request: Request, session_id: str) -> tuple[dict, dict]:
    found = request.app.state.store.get(session_id)
    if not found:
        raise ApiError("session_not_found", f"No existe la sesión {session_id}.")
    return found


app = create_app()
