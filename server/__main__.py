"""Arranca el motor:  .venv\\Scripts\\python -m server   (desde la raíz del repo)"""
import logging

import uvicorn

from server.app.config import Settings

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    s = Settings.from_env()
    uvicorn.run("server.app.main:app", host=s.api_host, port=s.api_port, log_level="info")
