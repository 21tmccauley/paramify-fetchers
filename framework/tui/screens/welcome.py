"""Welcome / manifest-selector screen — MOCK (Phase 5 proposal).

A visual prototype of a launchpad that lists the available run manifests and
lets you pick one to drive the rest of the session (view / edit / run). Modeled
on the Go evidence-tui-prototype's WelcomeModel (Tokyo Night palette + PARAMIFY
logo). This is a look-and-feel mock: rows are sample data and selection only
notifies — it is NOT wired into the app flow yet. Run it with:

    python -m framework.tui.welcome_demo
"""

from __future__ import annotations

from typing import List, Optional

from rich.text import Text
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Container, Vertical
from textual.message import Message
from textual.screen import Screen
from textual.widgets import DataTable, Static

# PARAMIFY block logo (from the Go prototype's app.LogoLines()).
LOGO = r"""
 ██████╗  █████╗ ██████╗  █████╗ ███╗   ███╗██╗███████╗██╗   ██╗
 ██╔══██╗██╔══██╗██╔══██╗██╔══██╗████╗ ████║██║██╔════╝╚██╗ ██╔╝
 ██████╔╝███████║██████╔╝███████║██╔████╔██║██║█████╗   ╚████╔╝
 ██╔═══╝ ██╔══██║██╔══██╗██╔══██║██║╚██╔╝██║██║██╔══╝    ╚██╔╝
 ██║     ██║  ██║██║  ██║██║  ██║██║ ╚═╝ ██║██║██║        ██║
 ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝        ╚═╝
""".strip("\n")
LOGO_LINES = LOGO.split("\n")

# Logo shimmer — a bright band sweeps left→right, then idles, then repeats
# (mirrors the Go prototype's app.RenderLogoSheen).
_SHEEN_STEP = 0.03        # seconds per column advance
_SHEEN_IDLE = 6.0         # pause between sweeps
_SHEEN_RADIUS = 10        # the band starts/ends this far off-edge
_SHEEN_CORE = "#C0CAF5"   # bright center of the band
_SHEEN_PEAK = "#7DCFFF"   # cyan, just off-center
_SHEEN_BASE = "#7AA2F7"   # the logo's resting blue

# Sample manifests — stand in for what api.list_manifests() would return.
MOCK_MANIFESTS: List[dict] = [
    {"name": "aws-prod.yaml", "fetchers": 12, "issues": 0,
     "last_run": "2026-06-02", "last_result": "11/12 ok"},
    {"name": "okta-quarterly.yaml", "fetchers": 8, "issues": 2,
     "last_run": "2026-05-30", "last_result": "8/8 ok"},
    {"name": "k8s-baseline.yaml", "fetchers": 3, "issues": 0,
     "last_run": None, "last_result": None},
    {"name": "gitlab-change-mgmt.yaml", "fetchers": 2, "issues": 0,
     "last_run": "2026-05-27", "last_result": "0/2 ok"},
]


class ManifestSelected(Message):
    """Emitted when a manifest is chosen (for later wiring into the app)."""

    def __init__(self, name: str) -> None:
        self.name = name
        super().__init__()


class WelcomeScreen(Screen):
    CSS = """
    WelcomeScreen { background: #1A1B26; align: center middle; }

    #welcome-root { width: auto; height: auto; align: center middle; }

    #welcome-logo { width: auto; color: #7AA2F7; text-style: bold; }
    #welcome-tagline { width: auto; color: #BB9AF7; text-style: bold; padding-top: 1; }
    #welcome-subtitle { width: auto; color: #565F89; padding-bottom: 1; }

    #welcome-panel {
        width: 86;
        height: auto;
        border: round #565F89;
        padding: 0 1;
        background: #1A1B26;
    }
    #welcome-panel-title { color: #565F89; padding: 0 1; }

    #welcome-manifests {
        height: auto;
        max-height: 12;
        background: #1A1B26;
        color: #C0CAF5;
        margin-top: 1;
    }
    #welcome-manifests > .datatable--header { color: #565F89; background: #1A1B26; text-style: none; }
    #welcome-manifests > .datatable--cursor { background: #7AA2F7; color: #1A1B26; text-style: bold; }

    #welcome-hints { width: auto; color: #565F89; padding-top: 1; }
    """

    BINDINGS = [
        Binding("enter", "open", "open"),
        Binding("n", "new", "new"),
        Binding("d", "delete", "delete"),
        Binding("q", "quit", "quit"),
    ]

    def __init__(self, manifests: Optional[List[dict]] = None) -> None:
        super().__init__()
        self._manifests = manifests if manifests is not None else MOCK_MANIFESTS
        self.last_selected: Optional[str] = None
        # shimmer state
        self._sheen_col = -_SHEEN_RADIUS
        self._sheen_idle = False
        self._idle_ticks = 0
        self._sheen_max = max(len(line) for line in LOGO_LINES)

    def compose(self) -> ComposeResult:
        with Vertical(id="welcome-root"):
            yield Static(LOGO, id="welcome-logo", markup=False)
            yield Static("fetcher", id="welcome-tagline")
            yield Static("collect compliance evidence from your stack", id="welcome-subtitle")
            with Container(id="welcome-panel"):
                yield Static("select a run manifest", id="welcome-panel-title")
                yield DataTable(id="welcome-manifests")
            yield Static(self._hints(), id="welcome-hints")

    def on_mount(self) -> None:
        dt = self.query_one("#welcome-manifests", DataTable)
        dt.cursor_type = "row"
        dt.add_columns("manifest", "fetchers", "status", "last run")
        for m in self._manifests:
            dt.add_row(
                Text(m["name"], style="#7DCFFF"),
                Text(str(m["fetchers"]), style="#BB9AF7"),
                self._status_cell(m),
                self._last_run_cell(m),
                key=m["name"],
            )
        dt.focus()
        self._update_logo()
        self.set_interval(_SHEEN_STEP, self._sheen_tick)

    # -- logo shimmer ----------------------------------------------------- #

    def _render_logo(self, center: int) -> Text:
        """Style the logo with a bright band centered at column `center`.
        Consecutive same-color chars are coalesced into one span."""
        text = Text()
        for li, line in enumerate(LOGO_LINES):
            if li:
                text.append("\n")
            run: list = []
            run_color = None
            for i, ch in enumerate(line):
                d = abs(i - center)
                color = _SHEEN_CORE if d <= 1 else _SHEEN_PEAK if d <= 3 else _SHEEN_BASE
                if run and color != run_color:
                    text.append("".join(run), style=f"{run_color} bold")
                    run = []
                run_color = color
                run.append(ch)
            if run:
                text.append("".join(run), style=f"{run_color} bold")
        return text

    def _update_logo(self) -> None:
        self.query_one("#welcome-logo", Static).update(self._render_logo(self._sheen_col))

    def _sheen_tick(self) -> None:
        if self._sheen_idle:
            self._idle_ticks -= 1
            if self._idle_ticks <= 0:           # resume: restart the sweep
                self._sheen_idle = False
                self._sheen_col = -_SHEEN_RADIUS
            return
        self._sheen_col += 1
        if self._sheen_col > self._sheen_max + _SHEEN_RADIUS:
            self._sheen_idle = True              # band has swept past the end; rest
            self._idle_ticks = int(_SHEEN_IDLE / _SHEEN_STEP)
            return
        self._update_logo()

    # -- cells ------------------------------------------------------------ #

    @staticmethod
    def _status_cell(m: dict) -> Text:
        if m["issues"]:
            return Text(f"⚠ {m['issues']} issues", style="#E0AF68")
        return Text("✓ runnable", style="#9ECE6A")

    @staticmethod
    def _last_run_cell(m: dict) -> Text:
        if not m["last_run"]:
            return Text("— never run", style="#565F89")
        result = m.get("last_result") or ""
        ok = result.startswith(result.split("/")[0]) and "0/" not in result
        style = "#9ECE6A" if ok and "ok" in result else "#F7768E"
        t = Text(f"{m['last_run']}  ", style="#565F89")
        t.append(result, style=style)
        return t

    def _hints(self) -> Text:
        parts = [("enter", "open"), ("n", "new"), ("d", "delete"), ("s", "secrets"), ("q", "quit")]
        t = Text()
        for i, (key, desc) in enumerate(parts):
            if i:
                t.append("    ")
            t.append(key, style="#BB9AF7 bold")
            t.append(" ")
            t.append(desc, style="#565F89")
        return t

    # -- actions (mock: notify only) ------------------------------------- #

    def _selected(self) -> Optional[str]:
        dt = self.query_one("#welcome-manifests", DataTable)
        if dt.row_count == 0:
            return None
        row_key, _ = dt.coordinate_to_cell_key(dt.cursor_coordinate)
        return row_key.value

    def _open(self, name: Optional[str]) -> None:
        if not name:
            return
        self.last_selected = name
        self.post_message(ManifestSelected(name))
        self.notify(f"[mock] would open '{name}' and drive the session from it.")

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        # Enter on the focused table posts RowSelected (it shadows the screen's
        # enter binding) — open from here.
        self._open(event.row_key.value)

    def action_open(self) -> None:
        self._open(self._selected())

    def action_new(self) -> None:
        self.notify("[mock] would create a new manifest (api.init_manifest).")

    def action_delete(self) -> None:
        name = self._selected()
        if name:
            self.notify(f"[mock] would delete '{name}' (after confirm).")
