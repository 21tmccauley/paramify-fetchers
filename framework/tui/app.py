"""FetcherApp — the TUI shell.

Holds the shared state every page reads (repo root, the cached catalog, the
manifest path) and hosts the four top-level tabs. Only the Catalog tab is live
in Phase 1; the rest are placeholders (see docs/tui_design.md).

Like the other front-ends, this talks only to framework.api.
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Footer, Header, TabbedContent, TabPane

from framework import api
from framework.tui.screens.catalog import CatalogPage
from framework.tui.screens.placeholder import PlaceholderPage


class FetcherApp(App):
    """Terminal console for the fetcher framework."""

    CSS_PATH = "styles/index.tcss"
    TITLE = "paramify-fetchers"

    TAB_IDS = ["tab-catalog", "tab-manifest", "tab-run", "tab-evidence"]

    BINDINGS = [
        Binding("1", "go_tab(0)", "Catalog"),
        Binding("2", "go_tab(1)", "Manifest"),
        Binding("3", "go_tab(2)", "Run"),
        Binding("4", "go_tab(3)", "Evidence"),
        Binding("slash", "focus_search", "Search"),
        Binding("escape", "unfocus", "Unfocus", show=False),
        Binding("r", "refresh", "Refresh"),
        Binding("q", "quit", "Quit"),
    ]

    def __init__(
        self, manifest_path: str = "manifest.yaml", root_override: Optional[str] = None
    ) -> None:
        super().__init__()
        self.manifest_path = Path(manifest_path)
        self._root_override = Path(root_override) if root_override else None
        # Shared state read by the pages:
        self.root_path: Optional[Path] = None
        self.catalog_data: Optional[dict] = None

    def compose(self) -> ComposeResult:
        yield Header()
        with TabbedContent(initial="tab-catalog"):
            with TabPane("Catalog", id="tab-catalog"):
                yield CatalogPage(id="catalog-page")
            with TabPane("Manifest", id="tab-manifest"):
                yield PlaceholderPage("Manifest editor", "Phase 2")
            with TabPane("Run", id="tab-run"):
                yield PlaceholderPage("Run console", "Phase 3")
            with TabPane("Evidence", id="tab-evidence"):
                yield PlaceholderPage("Evidence browser", "Phase 4")
        yield Footer()

    def on_mount(self) -> None:
        self._load_catalog()

    def _load_catalog(self) -> None:
        try:
            self.root_path = api.find_repo_root(self._root_override)
            self.catalog_data = api.catalog(self.root_path)
        except Exception as exc:  # repo-root discovery / fetcher load failures
            self.catalog_data = None
            self.sub_title = "catalog unavailable"
            self.notify(f"Could not load catalog: {exc}", severity="error", timeout=10)
            return

        n = self.catalog_data["fetcher_count"]
        c = len(self.catalog_data["categories"])
        self.sub_title = f"{self.root_path}  ·  {n} fetchers / {c} categories"
        self.query_one(CatalogPage).rebuild()

    # -- actions ---------------------------------------------------------- #

    def _go_to_tab(self, tab_id: str) -> None:
        # Blur first: Textual reverts an `active` change made while focus is
        # trapped inside the outgoing tab pane, so drop focus before switching.
        self.set_focus(None)
        self.query_one(TabbedContent).active = tab_id

    def action_go_tab(self, index: int) -> None:
        if 0 <= index < len(self.TAB_IDS):
            self._go_to_tab(self.TAB_IDS[index])

    def action_unfocus(self) -> None:
        self.set_focus(None)

    def action_refresh(self) -> None:
        self._load_catalog()
        if self.catalog_data is not None:
            self.notify("Catalog reloaded.")

    def action_focus_search(self) -> None:
        self._go_to_tab("tab-catalog")
        self.query_one(CatalogPage).focus_search()
