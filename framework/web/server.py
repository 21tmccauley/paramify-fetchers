"""FastAPI server exposing the framework.api facade to the web UI.

Endpoints mirror the facade:
  GET  /api/catalog                 -> api.catalog()        (form schema)
  GET  /api/manifests               -> list example manifests
  GET  /api/manifest?path=...       -> api.read_manifest()
  PUT  /api/manifest                -> api.dump_manifest()  (+ validation)
  POST /api/manifest/validate       -> api.validate()
  POST /api/run                     -> api.run() streamed as Server-Sent Events
  GET  /                            -> single-page frontend

The web UI is a third front-end alongside the human CLI and the AI CLI; all
three call only framework.api, so behavior stays identical across them.
"""

import asyncio
import json
import queue
import threading
from pathlib import Path
from typing import Optional

import yaml
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from framework import api

_STATIC = Path(__file__).parent / "static"


class SavePayload(BaseModel):
    path: str
    manifest: dict


class ManifestPayload(BaseModel):
    manifest: dict


def _resolve_in_repo(root: Path, raw: str) -> Path:
    """Resolve a user-supplied path under the repo root (prevents traversal)."""
    p = (root / raw).resolve() if not Path(raw).is_absolute() else Path(raw).resolve()
    if root not in p.parents and p != root:
        raise HTTPException(status_code=400, detail=f"path escapes repo root: {raw}")
    return p


def create_app(root: Optional[Path] = None) -> FastAPI:
    root = (root or api.find_repo_root(Path(__file__))).resolve()
    app = FastAPI(title="Paramify Fetcher Console")

    @app.get("/api/catalog")
    def get_catalog() -> dict:
        return api.catalog(root)

    @app.get("/api/manifests")
    def list_manifests() -> dict:
        examples = sorted((root / "examples").glob("*.yaml"))
        items = [
            {"name": p.name, "path": str(p.relative_to(root))}
            for p in examples
            if p.stat().st_size > 0
        ]
        return {"manifests": items}

    @app.get("/api/manifest")
    def get_manifest(path: str) -> dict:
        p = _resolve_in_repo(root, path)
        try:
            return {"path": path, "manifest": api.read_manifest(p)}
        except yaml.YAMLError as e:
            raise HTTPException(status_code=400, detail=f"malformed YAML: {e}")

    @app.put("/api/manifest")
    def save_manifest(payload: SavePayload) -> dict:
        p = _resolve_in_repo(root, payload.path)
        try:
            api.dump_manifest(payload.manifest, p, root)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
        return {"path": payload.path, "errors": api.validate(payload.manifest, root)}

    @app.post("/api/manifest/validate")
    def validate_manifest(payload: ManifestPayload) -> dict:
        errors = api.validate(payload.manifest, root)
        return {"ok": not errors, "errors": errors}

    @app.post("/api/run")
    async def run_manifest(payload: ManifestPayload):
        events: "queue.Queue[dict]" = queue.Queue()

        def worker() -> None:
            try:
                api.run(payload.manifest, root, on_event=events.put)
            except Exception as e:  # noqa: BLE001 — surface to the stream, don't 500
                events.put({"event": "run_error", "error": str(e)})
            finally:
                events.put({"event": "_end"})

        threading.Thread(target=worker, daemon=True).start()

        async def stream():
            loop = asyncio.get_event_loop()
            while True:
                ev = await loop.run_in_executor(None, events.get)
                if ev.get("event") == "_end":
                    break
                yield f"data: {json.dumps(ev, default=str)}\n\n"

        return StreamingResponse(stream(), media_type="text/event-stream")

    if _STATIC.is_dir():
        app.mount("/static", StaticFiles(directory=str(_STATIC)), name="static")

        @app.get("/")
        def index() -> FileResponse:
            return FileResponse(str(_STATIC / "index.html"))

    return app


app = create_app()
