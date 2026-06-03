"""Catalog screen re-skinned in the Go-TUI design language — PROTOTYPE.

A look-and-feel mock that dresses the real catalog (api.catalog) in the
evidence-tui-prototype's chrome: tokyo-night palette, a "paramify fetcher"
header bar with a centered breadcrumb + live clock, titled panels whose border
follows focus (the active-pane idiom), and a key-hint footer. Standalone — does
not touch the real app. Run it with:

    python -m framework.tui.catalog_skin_demo

If the direction lands, AppHeader / HintFooter / the .panel CSS become the
shared "chrome" layer applied across all screens (Tier A of the design sweep).
"""

from __future__ import annotations

from datetime import datetime
from typing import List, Optional, Tuple

from rich.text import Text
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import Screen
from textual.widgets import Input, Static, Tree

from framework import api
from framework.tui import render

_ACCENT = "#BB9AF7"   # purple
_ORANGE = "#FF9E64"
_SUBTLE = "#565F89"


class AppHeader(Horizontal):
    """Persistent top bar: title • crumb (centered) • clock, with a rule under."""

    def __init__(self, crumb: str) -> None:
        super().__init__(id="cat-header")
        self._crumb = crumb

    def compose(self) -> ComposeResult:
        yield Static(
            f"[b]paramify fetcher[/]  [{_ORANGE}]•[/]  [{_SUBTLE}]evidence tui[/]",
            id="hdr-left",
        )
        yield Static(self._crumb, id="hdr-crumb")
        yield Static("", id="hdr-clock")

    def on_mount(self) -> None:
        self._tick()
        self.set_interval(1.0, self._tick)

    def _tick(self) -> None:
        self.query_one("#hdr-clock", Static).update(datetime.now().strftime("%H:%M:%S"))


class HintFooter(Static):
    """Footer hint bar: key (accent) + desc (subtle), with a rule above."""

    def __init__(self, hints: List[Tuple[str, str]], **kwargs) -> None:
        text = Text()
        for i, (key, desc) in enumerate(hints):
            if i:
                text.append("    ")
            text.append(key, style=f"{_ACCENT} bold")
            text.append(" ")
            text.append(desc, style=_SUBTLE)
        super().__init__(text, **kwargs)


class CatalogSkinScreen(Screen):
    CSS = """
    CatalogSkinScreen { background: $background; }

    #cat-header { height: auto; border-bottom: solid $panel; padding: 0 1; }
    #hdr-left { width: auto; }
    #hdr-crumb { width: 1fr; text-align: center; color: #7DCFFF; }
    #hdr-clock { width: auto; color: $text-muted; }

    #cat-body { height: 1fr; padding: 1 1 0 1; }

    .panel { border: round $panel; padding: 0 1; height: 1fr; }
    .panel:focus-within { border: round $primary; }
    .panel-title { color: $text-muted; text-style: bold; }

    #cat-left { width: 42%; }
    #cat-right { width: 1fr; margin-left: 1; }

    #cat-search { margin: 1 0; }
    #cat-tree { height: 1fr; background: $background; }
    #cat-tree > .tree--cursor { background: $primary; color: $background; text-style: bold; }
    #cat-tree > .tree--guides { color: $panel; }

    #cat-footer { height: auto; border-top: solid $panel; padding: 0 1; }
    """

    BINDINGS = [
        Binding("slash", "focus_search", "filter"),
        Binding("tab", "next_pane", "pane", show=False),
        Binding("j", "tree_down", "down", show=False),
        Binding("k", "tree_up", "up", show=False),
        Binding("q", "quit", "quit"),
    ]

    _filter: str = ""

    def compose(self) -> ComposeResult:
        yield AppHeader("catalog")
        with Horizontal(id="cat-body"):
            with Vertical(id="cat-left", classes="panel"):
                yield Static("fetchers", classes="panel-title")
                yield Input(placeholder="/ filter fetchers…", id="cat-search")
                yield Tree("catalog", id="cat-tree")
            with VerticalScroll(id="cat-right", classes="panel"):
                yield Static("contract", classes="panel-title")
                yield Static(render.empty_detail(), id="cat-detail")
        yield HintFooter(
            [("↑↓/jk", "navigate"), ("/", "filter"), ("enter", "view"), ("tab", "pane"), ("q", "quit")],
            id="cat-footer",
        )

    def on_mount(self) -> None:
        self._catalog = api.catalog(api.find_repo_root())
        self.query_one("#cat-right", VerticalScroll).can_focus = True
        self._build_tree()
        self.query_one("#cat-tree", Tree).focus()

    # -- data ------------------------------------------------------------- #

    def _build_tree(self) -> None:
        tree = self.query_one("#cat-tree", Tree)
        tree.show_root = False
        tree.clear()
        flt = self._filter.strip().lower()
        total = 0
        for cat in self._catalog["categories"]:
            matches = [
                f for f in cat["fetchers"]
                if not flt or flt in f["name"].lower() or flt in (f.get("description") or "").lower()
            ]
            if not matches:
                continue
            node = tree.root.add(f"{cat['name']}  ({len(matches)})", expand=bool(flt))
            for f in matches:
                node.add_leaf(f["name"], data=f)
                total += 1
        tree.root.expand()

    # -- events ----------------------------------------------------------- #

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "cat-search":
            self._filter = event.value
            self._build_tree()

    def on_tree_node_highlighted(self, event: Tree.NodeHighlighted) -> None:
        detail = self.query_one("#cat-detail", Static)
        data = event.node.data
        detail.update(render.fetcher_detail(data) if data else render.empty_detail())

    # -- actions ---------------------------------------------------------- #

    def action_focus_search(self) -> None:
        self.query_one("#cat-search", Input).focus()

    def action_next_pane(self) -> None:
        tree = self.query_one("#cat-tree", Tree)
        right = self.query_one("#cat-right", VerticalScroll)
        (right if tree.has_focus or self.query_one("#cat-search", Input).has_focus else tree).focus()

    def action_tree_down(self) -> None:
        self.query_one("#cat-tree", Tree).action_cursor_down()

    def action_tree_up(self) -> None:
        self.query_one("#cat-tree", Tree).action_cursor_up()
