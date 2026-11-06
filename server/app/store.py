"""Partidas guardadas en SQLite. Cada fila guarda el estado público (WorldState)
y uno privado (historial de diálogo, contadores) que nunca sale al cliente."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path


class SessionStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._lock = threading.Lock()
        with self._lock, self._conn:
            self._conn.execute(
                "CREATE TABLE IF NOT EXISTS sessions ("
                " id TEXT PRIMARY KEY, public TEXT NOT NULL, private TEXT NOT NULL,"
                " created_at REAL NOT NULL, updated_at REAL NOT NULL)"
            )

    def create(self, session_id: str, public: dict, private: dict) -> None:
        now = time.time()
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO sessions VALUES (?, ?, ?, ?, ?)",
                (session_id, json.dumps(public, ensure_ascii=False),
                 json.dumps(private, ensure_ascii=False), now, now),
            )

    def get(self, session_id: str) -> tuple[dict, dict] | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT public, private FROM sessions WHERE id = ?", (session_id,)
            ).fetchone()
        return (json.loads(row[0]), json.loads(row[1])) if row else None

    def save(self, session_id: str, public: dict, private: dict) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                "UPDATE sessions SET public = ?, private = ?, updated_at = ? WHERE id = ?",
                (json.dumps(public, ensure_ascii=False), json.dumps(private, ensure_ascii=False),
                 time.time(), session_id),
            )

    def close(self) -> None:
        self._conn.close()
