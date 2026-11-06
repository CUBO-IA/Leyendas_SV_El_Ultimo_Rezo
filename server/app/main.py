"""Motor de Leyendas SV. Arranque:  .venv\\Scripts\\python -m server"""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from pydantic import BaseModel, ConfigDict, Field

from . import errors, game
from .config import Settings
from .errors import ApiError
from .llm.provider import Provider, get_provider
from .store import SessionStore

log = logging.getLogger("leyendas")


class SessionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    player_name: str | None = Field(default=None, max_length=40)
    demo: bool | None = None


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
        found = request.app.state.store.get(session_id)
        if not found:
            raise ApiError("session_not_found", f"No existe la sesión {session_id}.")
        return found[0]

    return app


app = create_app()
