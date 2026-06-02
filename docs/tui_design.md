# TUI design — a terminal front-end for paramify-fetchers

Status: **Phase 1 implemented** (`framework/tui/`, read-only catalog browser).
Phases 2–4 are designed here but not yet built.

This document describes a Textual-based terminal UI for the framework, modeled
on the architecture of the [Bagels](https://github.com/EnhancedJax/Bagels)
expense-tracker TUI. It is a design + implementation plan, not a tutorial.

## 1. Why this maps cleanly

Bagels' whole design rests on one rule: **the UI talks only to its
`managers/*` layer, never to the database.** paramify-fetchers already enforces
the identical rule with `framework/api.py` — per `CLAUDE.md`, *"three front-ends
call ONLY `framework.api` so behavior is identical."* The human CLI
(`python -m framework.runner`), the AI `--json` CLI, and the FastAPI web UI
(`python -m framework.web`) all sit on that one facade.

**A TUI is simply front-end #4 over the same facade.** No domain logic, no
persistence, and no subprocess handling needs to be re-implemented — the TUI is
pure presentation. The web UI already proved the facade is GUI-sufficient: it
pipes `api.run()`'s `on_event` dicts through a thread+queue into a Server-Sent-
Events stream (`framework/web/server.py`). A Textual worker collapses that
bridge to a single `@work(thread=True)` call plus a message pump.

The enabling facts, all verified against `framework/api.py`:

- `api.catalog(root)` returns the form schema directly: categories → fetchers →
  typed field descriptors (`name / kind / type / required / default /
  description / env`). This is *both* the AI-readable catalog and the UI form
  spec (`api.py:104`).
- The in-place manifest mutators (`add_entry`, `remove_entry`,
  `set_fetcher_config`, `set_secret`, `add_target`, `set_platform_config`,
  `set_passthrough_env`, `set_output_dir`) do every edit and return the dict for
  chaining (`api.py:166-243`).
- `api.validate(manifest, root) -> List[str]` returns the human-readable
  "why won't this run" list; empty == runnable (`api.py:251`).
- `api.run(manifest, root, on_event=...)` streams a **closed vocabulary of
  seven events** to the callback: `run_start`, `fetcher_start`, `log_line`,
  `fetcher_result`, `fetcher_skip`, `fetcher_error`, `run_complete`
  (`api.py:331-437`).

**Verdict:** strongly recommended, low-to-moderate effort. A read-only catalog
browser is a few days (Phase 1, done); a full editor + run console + evidence
browser is a few weeks of part-time work, shippable in phases.

## 2. Architecture correspondence

| Bagels element | What it does | paramify-fetchers equivalent | Gap |
|---|---|---|---|
| `managers/*` — the only layer that opens DB sessions | Data-access layer; UI never touches SQLAlchemy | **`framework/api.py`** — `catalog` / mutators / `validate` / `run` | Exact role match. `api` mutates an in-memory dict; managers persist to SQLite per call. |
| `App` shell: header + `Tabs` + lazy body mount (`app.py`) | Thin shell routing between top-level views | `framework/tui/app.py` — `TabbedContent` with Catalog / Manifest / Run / Evidence panes | Direct port (we use idiomatic `TabbedContent` rather than the manual mount/remove dance). |
| Modules = `Static` with `compose()`-skeleton + `rebuild()`-data | Self-contained screen sections that re-query managers | Each page re-queries `api.catalog()` / re-renders the manifest dict | Direct port — the core recipe. |
| `forms/form.py` + `Fields`/`Field` (switch on `field.type`) | One generic widget renders any declarative form | `api`'s `_config_descriptor` / `_secret_descriptor` / `_target_descriptor` | **Highest-leverage reuse — `api` *already emits* the form spec; we build only the renderer.** |
| `modals/` confirmation + input, `dismiss(result)` → callback | Collect input → validate → return to caller | Add/edit-fetcher modal → `api.set_*`; confirm before remove/run | Direct port. |
| Jump Mode (`jumper.py`) + command palette (`provider.py`) | Single-key spatial nav; fuzzy cross-cutting actions | Jump between pages; `manifest: validate / run`, `theme: X` | Reimplement; cheap, high value. |
| vendored `DataTable` (~2,790 lines, group-header rows) | Data sink with typed row keys | **stock Textual `DataTable`** (or `Tree` for the category hierarchy) | Don't vendor — stock `DataTable`/`Tree` cover it. |
| `models/*` + SQLite, soft-delete, timestamps | ORM rows + engine | **none needed** — the "model" is the raw manifest dict + `fetcher.yaml` on disk | Gap that *helps*: nothing to build. |
| `tplot` / `barchart` / budgets / spinning donut | Terminal charts and finance widgets | **not applicable** | Drop entirely. |

## 3. Proposed screen architecture

The App owns shared state — `root` (from `api.find_repo_root()`),
`catalog_data` (cached `api.catalog(root)`), `manifest_path`, and the in-memory
`manifest` raw dict — and a top-level `rebuild()` that fans out to each page's
`rebuild()`, exactly as Bagels' `Home.rebuild()` fans out to its modules.

### 3.1 Catalog browser — `api.catalog(root)`  *(Phase 1, implemented)*

Left pane: a `Tree` of categories → fetchers with a live search `Input` filter.
Right pane: the selected fetcher's descriptor — `version`, `description`,
`supports_targets`, and three tables built from `config[]`, `secrets[]`,
`target_schema[]` (each descriptor's `name / type / required / default /
description / env`). Read-only.

```
┌─ paramify-fetchers ─────────────  Catalog · Manifest · Run · Evidence ────────┐
│ search: okta_                    │ okta_phishing_resistant_mfa          v0.3.0 │
│ ▾ aws            (30)            │ Collects phishing-resistant MFA enrollment… │
│ ▾ okta            (8)            │ targets: no   category: okta                │
│   okta_admin_mfa                 │ ── secrets ────────────────────────────────│
│ ▸ okta_phishing_resistant_mfa    │  OKTA_TOKEN    required   env OKTA_API_TOKEN │
│   okta_password_policy           │  OKTA_DOMAIN   required   env OKTA_DOMAIN    │
│ ▸ sentinelone     (5)            │ ── config ─────────────────────────────────│
│                                  │  (none)                                     │
└──[q]uit  [/]search  [r]efresh ───┴─────────────────────────────────────────────┘
```

### 3.2 Manifest editor — `api` mutators + `validate()`  *(Phase 2)*

The document is the raw manifest dict held in App state. The page renders a
generated form per `manifest['run']['fetchers'][]` entry, plus a `platforms`
section per category and an output-dir field. Field → mutator bindings:

- `config[]` → typed inputs (Switch for `boolean`, restricted numeric `Input`
  for `integer`, text otherwise; `default` as placeholder) → `set_fetcher_config`.
- `secrets[]` → a text input holding the **env-var NAME** (never a value),
  pre-filled from descriptor `env` → `set_secret` (which stores `${env:VAR}`).
- targets (if `supports_targets`) → a repeatable sub-form → `add_target`.
- output-dir → `set_output_dir`; platform config → `set_platform_config` /
  `set_passthrough_env`.

A live `api.validate()` "issues" panel gates the Run action; empty == runnable.
Writes go through the modal + `dismiss(result)` + callback + try/except +
`notify` + `rebuild` triad; removes/overwrites sit behind a `ConfirmationModal`.
Save = `api.dump_manifest()`, catching its `ValueError` so schema-invalid WIP is
reported but semantically-incomplete WIP can still be saved.

```
┌─ MANIFEST EDITOR ──  path: ./manifest.yaml   out: ./evidence ─────────────────┐
│ ┌ okta_phishing_resistant_mfa  [single]                              [x] ────┐ │
│ │ secrets:  OKTA_TOKEN  = [OKTA_API_TOKEN ] req                              │ │
│ │           OKTA_DOMAIN = [OKTA_DOMAIN    ] req                              │ │
│ └────────────────────────────────────────────────────────────────────────────┘ │
│ ┌ s3_encryption_status  [fanout]                                     [x] ────┐ │
│ │ targets: • region=us-east-1 profile=prod        [+ add target]            │ │
│ └────────────────────────────────────────────────────────────────────────────┘ │
│ ISSUES (validate): ✗ okta…: missing secret 'OKTA_DOMAIN'                        │
└──[a]dd  [s]ave  [v]alidate  [r]un ──────────────────────────────────────────────┘
```

### 3.3 Run console — `api.run(on_event=...)` on a Textual worker  *(Phase 3)*

A status `DataTable` (one row per `(fetcher, target)` unit) plus a streaming
`RichLog`, driven by the seven events on a `@work(thread=True)` worker. State
machine per row:

| event | effect |
|---|---|
| `run_start{fetchers[]}` | seed all rows QUEUED; show `run_dir` |
| `fetcher_start{fetcher, targets, fanout}` | mark RUNNING; expand into target sub-rows if `fanout` |
| `log_line{fetcher, line}` | append to `RichLog` (stdout only) |
| `fetcher_result{exit_code, duration_sec, target, outputs}` | OK if `exit_code==0`; `124`→TIMEOUT |
| `fetcher_skip{reason}` | SKIPPED |
| `fetcher_error{error}` | ERROR |
| `run_complete{ok, run_dir, metadata_path}` | footer banner; re-enable Run |

```
┌─ RUN CONSOLE ──────────────────────────  run-2026-06-02T14-03-11Z ────────────┐
│ summary: ██████ ok 4  ██ fail 1  ░ skip 0           [▶ run] [■ stop] [v]alidate│
│ ┌ STATUS ──────────────────────────┐ ┌ LOG ───────────────────────────────────┐│
│ │ FETCHER          TARGET   ST EXIT│  s3_encryption ▸ us-east-1: 18 buckets     ││
│ │ okta_phishing_mfa —       OK  0  │  s3_encryption ▸ eu-west-1: AccessDenied   ││
│ │ s3_encryption    us-east1 OK  0  │  knowbe4_training ▸ fetching campaigns…    ││
│ │ s3_encryption    eu-west1 FAIL 1 │                                            ││
│ └──────────────────────────────────┘ └────────────────────────────────────────┘│
│ done → ./evidence/run-…/_run_metadata.json   ok=false                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.4 Evidence browser  *(Phase 4)*

A `DataTable` listing produced evidence files under `<output_dir>/run-*/`,
reading the envelope shape (`framework/envelope.py`: `metadata.fetcher_name`,
`schema_version`, `metadata.status` / `exit_code`, `evidence_set`). A run picker
lists `run-*` dirs and re-opens `_run_metadata.json` — a run-history feature the
web UI lacks. Note: there is **no `api` function for evidence browsing today**
(see §7).

## 4. Data flow

The invariant matches Bagels: a UI module never touches the subprocess, the
filesystem, or `fetcher.yaml` directly — it calls `framework.api`.

- **Startup:** `root = api.find_repo_root()`; `catalog_data = api.catalog(root)`;
  `manifest = api.read_manifest(path)` (or `api.init_manifest()`). Cached in App
  state.
- **Browse / describe:** render `catalog` dicts directly — they are JSON-able.
- **Edit:** each form save handler maps 1:1 onto an in-place mutator.
- **Validate:** after each edit (debounced), `api.validate()`; gate Run on `[]`.
- **Persist:** `api.dump_manifest()`; catch `ValueError` (schema-invalid).

The run event protocol → Textual worker (the SSE analog):

```python
class RunEvent(Message):
    def __init__(self, ev: dict) -> None:
        self.ev = ev; super().__init__()

@work(thread=True, exclusive=True)
def _run_worker(self) -> None:
    api.run(self.manifest, self.root,
            on_event=lambda ev: self.post_message(RunEvent(ev)))

def on_run_event(self, message: RunEvent) -> None:   # back on the UI thread
    match message.ev["event"]:
        case "log_line":     self.query_one(RichLog).write(message.ev["line"])
        case "fetcher_result": ...   # OK / FAIL / 124→TIMEOUT
        case "run_complete": ...
```

`post_message` is thread-safe; Textual marshals back onto the UI thread, so the
web layer's manual queue + `_end` sentinel are unnecessary.

## 5. File layout

Mirrors `framework/web/`'s package shape and honors the "front-ends call ONLY
`framework.api`" rule — nothing under `tui/` imports `runner.executor`,
`manifest_loader`, or reads `fetcher.yaml` directly.

```
framework/tui/
├── __init__.py
├── __main__.py            # python -m framework.tui [--manifest PATH] [--at ROOT]
├── app.py                 # FetcherApp(App): TabbedContent, shared state, rebuild fan-out
├── render.py              # Rich renderers for fetcher descriptors (shared by pages)
├── screens/
│   ├── catalog.py         # CatalogPage   — api.catalog(root)            (Phase 1)
│   ├── placeholder.py     # PlaceholderPage — "coming in Phase N"        (Phase 1)
│   ├── manifest.py        # ManifestPage  — api mutators + validate      (Phase 2)
│   ├── run.py             # RunPage       — api.run(on_event=...)         (Phase 3)
│   └── evidence.py        # EvidencePage  — run-*/ envelope files         (Phase 4)
├── components/            # reusable widgets (REIMPLEMENTED, not copied — see §6)
│   ├── fetcher_form.py    # FetcherForm/FieldWidget switching on kind+type (Phase 2)
│   ├── jumper.py          # id->key map + JumpOverlay                      (Phase 4)
│   └── status_table.py    # run status DataTable wrapper                   (Phase 3)
├── provider.py            # command palette → cross-cutting api.* actions  (Phase 4)
└── styles/
    └── index.tcss
```

`framework/tui/__main__.py` deliberately parallels `framework/web/__main__.py`:
`python -m framework.tui` launches the app, mirroring `python -m framework.web`.

## 6. Dependencies & license

**Runtime dep:** `textual` (which pulls in `rich`). Bagels pins
`textual>=1.0,<2.0`; we pin the same to keep the Jump Mode / DataTable patterns
portable 1:1. Added to `requirements.txt` under a TUI section, matching how the
web deps are treated. Textual and Rich are MIT-licensed.

**Bagels code reuse — license:** Bagels is **GPL-3.0** (confirmed in its
`LICENSE`). GPL is copyleft — copying its source files would impose GPL on this
repo, which is not what a commercial product wants. **We reimplement the
patterns; we do not copy the code.** This is low-cost: the high-value pieces are
thin (the jump overlay is a small modal; the `Fields`/`Field` switch-on-type is
straightforward), and the heavyweight vendored `DataTable` is unnecessary —
stock Textual `DataTable`/`Tree` already provide row keys, zebra striping, and
`RowHighlighted`/`NodeHighlighted` messages. Bagels stays *design inspiration*
documented in comments, never derived source.

## 7. Gaps, risks, and what NOT to do

- **No evidence-browsing API and no cancel hook.** Phases 1–3 require **zero
  `framework.api` changes**. Evidence browsing (Phase 4) either reads run dirs
  directly (a presentation concern) or motivates two small additive functions
  (`api.list_runs` / `api.read_evidence`) to stay on the facade. A "stop" button
  can `worker.cancel()` future entries but cannot kill an in-flight subprocess
  without an executor change — do **not** promise a hard cancel in v1.
- **`logger.py` / `retry.py` / `dependency_graph.py` are empty stubs** — no
  retries, no comparator `depends_on` DAG. Don't build retry/progress-bar UI.
- **Whole-manifest validation, not per-field.** `api.validate` returns strings
  naming the entry/field (e.g. `"<use>: missing secret '<name>'"`), not a
  field-keyed dict. Surface them in a global issues panel; don't over-engineer
  field-level error routing on day one.
- **Bagels features that don't apply:** all plotting, budgets, the spinning
  donut, the finance modules, and the entire `models/` + SQLite layer. There is
  no DB — that's a simplification, not a gap.

## 8. Phased implementation plan

Each phase is independently shippable and uses only `framework.api` (except the
optional Phase 4 evidence additions).

1. **Catalog browser** *(done)* — App shell + read-only browse. `api`:
   `find_repo_root`, `catalog`. Validates the whole shell and the
   "render descriptors directly" assumption.
2. **Manifest editor** (~1 wk) — declarative `FetcherForm`, add/remove,
   edit config/secrets/targets/platform/output-dir, live preview, issues panel.
   `api`: `read_manifest`, `init_manifest`, all mutators, `validate`,
   `dump_manifest`.
3. **Run console** (~3–5 days) — status table + streaming log on a Textual
   worker. `api`: `validate` (gate), `run(on_event=...)`. Render `124`→TIMEOUT;
   reuse the web client's validate-before-run / disable-while-running guards.
4. **Evidence browser + polish** (~3–5 days) — run history, Jump Mode, command
   palette, themes. Reads the envelope / `_run_metadata.json` shape, or adds the
   two `api` functions above to stay on the facade.
