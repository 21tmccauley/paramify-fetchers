"""Launch the TUI: python -m framework.tui [--manifest PATH] [--at ROOT]

Deliberately parallels framework/web/__main__.py so the front-ends share a shape.
"""

import argparse

from framework.tui.app import FetcherApp


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="framework.tui", description="Fetcher console (terminal UI)"
    )
    parser.add_argument(
        "--manifest",
        default="manifest.yaml",
        help="path to the manifest to edit (default: ./manifest.yaml)",
    )
    parser.add_argument(
        "--at",
        default=None,
        help="repo root override (default: discovered by walking up)",
    )
    args = parser.parse_args()
    FetcherApp(manifest_path=args.manifest, root_override=args.at).run()


if __name__ == "__main__":
    main()
