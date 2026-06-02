"""Rich renderers for the JSON-able descriptors returned by framework.api.

These turn a `_fetcher_descriptor` dict (see framework/api.py) into Rich
renderables for display in a Textual `Static`. Kept separate from the screens so
later phases (the manifest editor) can reuse the same field rendering.
"""

from typing import Any, List, Optional

from rich.console import Group, RenderableType
from rich.table import Table
from rich.text import Text


def _fmt_default(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _field_table(title: str, fields: List[dict]) -> RenderableType:
    """Render a list of config / secret / target_schema descriptors as a table."""
    heading = Text(title, style="bold")
    if not fields:
        return Group(heading, Text("  (none)", style="dim"))

    table = Table(box=None, pad_edge=False, expand=True, show_edge=False)
    table.add_column("name", style="cyan", no_wrap=True)
    table.add_column("type", style="dim")
    table.add_column("req", justify="center")
    table.add_column("default")
    table.add_column("env var", style="green")
    table.add_column("description", style="dim", overflow="fold")

    for f in fields:
        required = f.get("required")
        req_cell = Text("yes", style="yellow") if required else Text("no", style="dim")
        per_target = " ·per-target" if f.get("per_target") else ""
        table.add_row(
            f.get("name", ""),
            str(f.get("type", "")) + per_target,
            req_cell,
            _fmt_default(f.get("default")),
            f.get("env") or "",
            f.get("description") or "",
        )
    return Group(heading, table)


def fetcher_detail(f: dict) -> RenderableType:
    """Full detail view for one fetcher descriptor."""
    title = Text()
    title.append(f.get("name", ""), style="bold white")
    if f.get("version"):
        title.append(f"  v{f['version']}", style="dim")

    meta = Text()
    meta.append("category: ", style="dim")
    meta.append(f.get("category") or "—", style="white")
    meta.append("    targets: ", style="dim")
    meta.append("yes" if f.get("supports_targets") else "no", style="white")

    description = Text(f.get("description") or "(no description)", style="italic")

    return Group(
        title,
        meta,
        Text(),
        description,
        Text(),
        _field_table("secrets", f.get("secrets", [])),
        Text(),
        _field_table("config", f.get("config", [])),
        Text(),
        _field_table("target fields", f.get("target_schema", [])),
    )


def empty_detail(message: Optional[str] = None) -> RenderableType:
    return Text(message or "Select a fetcher to see its contract.", style="dim italic")
