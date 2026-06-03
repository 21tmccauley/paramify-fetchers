"""Standalone preview of the re-skinned Catalog screen (Go-TUI design language).

    python -m framework.tui.catalog_skin_demo

Sets the built-in tokyo-night theme and shows CatalogSkinScreen over the real
catalog. Does not touch the production app — it's a look-and-feel mock for
reviewing the design direction (see docs/tui_design.md). Tab toggles the active
pane (watch the border follow focus); / filters; q quits.
"""

from textual.app import App

from framework.tui.screens.catalog_skin import CatalogSkinScreen


class CatalogSkinDemo(App):
    def on_mount(self) -> None:
        self.theme = "tokyo-night"
        self.push_screen(CatalogSkinScreen())


def main() -> None:
    CatalogSkinDemo().run()


if __name__ == "__main__":
    main()
