"""Web UI for the fetcher framework.

A thin FastAPI layer over framework.api — the SAME facade the CLI uses. Endpoints
map 1:1 to facade calls; no orchestration logic lives here. Run via:

    python -m framework.web            # http://127.0.0.1:8765
"""

from framework.web.server import app, create_app

__all__ = ["app", "create_app"]
