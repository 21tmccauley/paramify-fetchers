# README demos

The GIFs embedded in the top-level `README.md` are generated with
[VHS](https://github.com/charmbracelet/vhs) from the `.tape` scripts here, so
they stay in sync with the CLI instead of being hand-recorded.

| Tape | GIF | Shows |
|---|---|---|
| `catalog.tape`  | `catalog.gif`  | `paramify catalog` / `list` / `describe` — the 8 categories, 107 fetchers, and one fetcher's contract |
| `manifest.tape` | `manifest.gif` | `paramify manifest` building a run manifest, with the "still missing" warnings shrinking to runnable |
| `tui.tape`      | `tui.gif`      | `paramify tui` — welcome screen, catalog search, manifest, run tabs |

## Regenerating

```bash
brew install vhs            # one-time; pulls ffmpeg + ttyd
docs/demo/render.sh         # re-renders all three
docs/demo/render.sh tui     # or just one
```

`render.sh` always runs from the repo root (the tapes `source .venv/bin/activate`
and use repo-relative paths). The `.tape` and `.gif` files are committed; the
throwaway `.scratch/` dir that `manifest.tape` records in is gitignored and
cleaned up by `render.sh`.
