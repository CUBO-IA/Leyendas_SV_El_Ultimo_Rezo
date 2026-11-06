"""Motor de Leyendas SV. Arranque:  .venv\\Scripts\\python -m server"""
from __future__ import annotations

import asyncio
import logging
from collections import defaultdict
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import FastAPI, Request
from pydantic import BaseModel, ConfigDict, Field

from . import data, errors, game, rules
from .config import Settings
from .dialogue import SITUATIONS, Dialogue, clean_player_text, evidence_message
from .errors import ApiError
from .llm.provider import Provider, get_provider
from .store import SessionStore

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


def create_app(settings: Settings | None = None, provider: Provider | None = None) -> FastAPI:
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
        task = None
        if app.state.provider is not None:
            if settings.warmup:
                task = asyncio.create_task(_warmup(app.state.provider, app.state.llm))
            else:
                app.state.llm.warm = True
        yield
        if task and not task.done():
            task.cancel()
        if app.state.provider is not None:
            await app.state.provider.aclose()
        app.state.store.close()

    app = FastAPI(title="Leyendas SV — motor", version="0.1.0", lifespan=lifespan)
    errors.install(app)

    @app.get("/health")
    async def health(request: Request):
        st = request.app.state
        ok = st.provider is not None and st.llm.warm and not st.llm.error
        return {
            "status": "ok" if ok else "degraded",
            "model": st.provider.model if st.provider else settings.active_model,
            "warm": st.llm.warm,
            "tts": False,  # B4
            "stt": False,  # B4
            "demo_mode": settings.demo_mode,
        }

    @app.post("/session")
    async def create_session(request: Request, body: SessionRequest | None = None):
        body = body or SessionRequest()
        demo = bool(body.demo) or settings.demo_mode
        sid = game.new_session_id()
        public, private = game.new_world_state(sid, demo=demo)
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
            return {
                "reply": said["reply"], "emotion": said["emotion"], "level": npc["level"],
                "trust": npc["trust"], "fear": npc["fear"],
                "new_evidence": outcome.new_evidence, "new_deductions": outcome.new_deductions,
                "audio_url": None, "source": source, "state": public,
            }

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
            return {
                "reply": said["reply"], "emotion": said["emotion"],
                "contradiction": outcome.changed_level, "level": npc["level"],
                "new_deductions": outcome.new_deductions, "new_evidence": outcome.new_evidence,
                "trust": npc["trust"], "fear": npc["fear"],
                "audio_url": None, "source": source, "state": public,
            }

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
            return ending

    return app


def _load(request: Request, session_id: str) -> tuple[dict, dict]:
    found = request.app.state.store.get(session_id)
    if not found:
        raise ApiError("session_not_found", f"No existe la sesión {session_id}.")
    return found


app = create_app()
