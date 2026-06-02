"""A stand-in page for views designed but not yet built (Phases 2-4)."""

from textual.app import ComposeResult
from textual.containers import Center, Middle
from textual.widgets import Static


class PlaceholderPage(Static):
    """Centered 'coming soon' message for an unimplemented tab."""

    def __init__(self, title: str, phase: str) -> None:
        super().__init__()
        self._title = title
        self._phase = phase

    def compose(self) -> ComposeResult:
        with Middle():
            with Center():
                yield Static(
                    f"[b]{self._title}[/b]\n\n"
                    f"[dim]Planned for {self._phase}. See docs/tui_design.md.[/dim]",
                    classes="placeholder-text",
                )
