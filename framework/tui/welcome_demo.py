"""Standalone preview of the mock welcome / manifest-selector screen.

    python -m framework.tui.welcome_demo

This does not touch the real app (the 4-tab UI) — it just shows the WelcomeScreen
with sample manifests so the look-and-feel can be reviewed before deciding on the
full multi-manifest design. See docs/tui_design.md (Phase 5 proposal).
"""

from textual.app import App

from framework.tui.screens.welcome import WelcomeScreen


class WelcomeDemo(App):
    def on_mount(self) -> None:
        self.push_screen(WelcomeScreen())


def main() -> None:
    WelcomeDemo().run()


if __name__ == "__main__":
    main()
