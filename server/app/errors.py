"""Toda respuesta de error sale con la forma ApiError del contrato: {error, detail}."""
from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

STATUS = {
    "bad_request": 400,
    "bad_npc": 400,
    "bad_evidence": 400,
    "bad_object": 400,
    "evidence_not_owned": 409,
    "location_locked": 409,
    "cannot_accuse": 409,
    "session_ended": 409,
    "session_not_found": 404,
    "model_not_ready": 503,
    "stt_failed": 502,
    "internal": 500,
}


class ApiError(Exception):
    def __init__(self, error: str, detail: str):
        assert error in STATUS, error
        self.error, self.detail = error, detail


def _body(error: str, detail: str, status: int | None = None) -> JSONResponse:
    return JSONResponse({"error": error, "detail": detail}, status_code=status or STATUS[error])


def install(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api(_: Request, exc: ApiError):
        return _body(exc.error, exc.detail)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError):
        first = exc.errors()[0] if exc.errors() else {}
        where = ".".join(str(p) for p in first.get("loc", []) if p != "body")
        return _body("bad_request", f"Petición inválida{' en ' + where if where else ''}: "
                                    f"{first.get('msg', 'formato incorrecto')}.")

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException):
        if exc.status_code == 404:
            return _body("bad_request", "Ruta no encontrada.", 404)
        if exc.status_code == 405:
            return _body("bad_request", "Método no permitido en esta ruta.", 405)
        return _body("internal", str(exc.detail), exc.status_code)

    @app.exception_handler(Exception)
    async def _unexpected(_: Request, exc: Exception):
        return _body("internal", "Error interno del motor.")
