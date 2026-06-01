"""Launch the web UI: python -m framework.web [--host H] [--port P]"""

import argparse

import uvicorn


def main() -> None:
    parser = argparse.ArgumentParser(prog="framework.web", description="Fetcher console")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--reload", action="store_true", help="auto-reload on code changes")
    args = parser.parse_args()
    uvicorn.run("framework.web.server:app", host=args.host, port=args.port, reload=args.reload)


if __name__ == "__main__":
    main()
