# Paramify Fetcher Framework — Design Notes

**Status:** Living document — design rationale. For the current state of the
work (what's ported, what's in progress), see [`handoff.md`](handoff.md).
**Author:** Tate
**Last updated:** 2026-05-28

This document captures the design for a longer-term fetcher framework that supports both internal use and customer/FDE deployment. The near-term path (moving existing fetchers to GitHub Actions with OIDC for internal use) is a separate effort and is not the subject of this doc.

---

## Context & problem statement

Paramify's fetchers today are scripts in a GitHub repo, varying widely in shape, config conventions, and runtime expectations (see the existing `.env.example`). They're invoked via a TUI. This works for internal use but doesn't scale to:

- FDEs building integrations for customer-specific tools
- Customers running fetchers in their own environments (which is the only viable model — fetchers will not run on Paramify infra)
- Cross-fetcher data composition (e.g., reconciling Okta users against Rippling employees)
- Many-target fetchers (e.g., one CI/CD check across N GitLab repos)

The configuration sprawl in the current `.env` is a symptom of a deeper issue: **there is no fetcher contract**. Every fetcher invents its own conventions because none are imposed. Examples in the current state:

- `IAM_ROLES_FETCHER=--exclude-aws-managed-roles` — CLI args leaking into env vars
- `AWS_REGION_1_FETCHERS=iam_roles,guard_duty` vs `GITLAB_PROJECT_1_FETCHERS=...` — same idea, inconsistent naming
- A central `catalog.json` that has to be hand-maintained in sync with the scripts

Fixing the symptoms without fixing the cause just postpones the same problems.

---

## Core decisions

### Where fetchers run: customer infrastructure

Customer-side execution is settled. This cascades into everything else:

- Secrets must be **secret-agnostic** — read from env, populated however the customer wants (their secret manager, IRSA, CI vault, pasted `.env`)
- The framework does not own orchestration — it provides something the customer drops into their orchestrator of choice (GitHub Actions, Jenkins, cron, Prefect, Argo)
- Data residency and FedRAMP boundary concerns are mostly resolved by execution location

### Output format: JSON files on disk

Fetchers produce JSON files. This decouples every stage from every other stage — fetcher writes JSON, next thing reads JSON. No in-memory coupling, no shared runtime, no shared language requirement. This is load-bearing for everything else.

### Fetcher scope: pure data collection, separate comparison layer

Fetchers pull data from a single source. Cross-source comparison logic (the "layer 2" idea) lives in separate components with the *same contract* — they just read prior fetcher outputs instead of external APIs.

Rationale: fetchers and comparators have fundamentally different failure modes. Fetcher failures are transient (rate limits, auth, network) and need retry/backoff. Comparator failures are logical (malformed input, broken join) and retry doesn't help. Mixing them prevents writing sane retry policies for either.

### Intermediate data lives in the run's output directory

When comparators need prior fetcher output, they read it from the same directory those fetchers wrote to. No separate intermediate store, no external infrastructure. This stays consistent with "JSON files on disk" and avoids inventing a new substrate.

---

## The fetcher contract

Every fetcher must satisfy this interface. **The current stripped-down `fetcher_schema.json` enforces a subset of this — the full contract will be enforced as the framework matures.**

### Input

- A **config object** — structured, typed, validated on load — describing what to fetch and with what options
- A **secrets object** — read from env by the framework, passed to the fetcher as already-resolved values (fetchers do not read env directly)
- An **output directory path** to write to
- A **run ID / correlation ID** for logging

### Output

- One or more JSON files in the output directory following a defined **envelope schema** (metadata block + payload block)
  - Metadata: fetcher name, version, run ID, target identifier, timestamp, status, errors
  - Payload: the actual evidence data
- A **structured log stream** (stdout JSON lines is fine)
- An **exit code** with documented meanings (0 = success; non-zero for documented failure categories)

### Behavior

- Idempotent for the same config + target + time window
- Handles pagination internally
- Surfaces partial failures in output rather than failing the whole run when one target fails
- Never writes outside its given output directory
- Never reads secrets from anywhere except the secrets object handed to it

### Reality check

Existing fetchers being ported into the new structure violate parts of this contract today — most notably, they read env vars directly and write hardcoded filenames without envelopes. These are tracked as version 0.x in their `fetcher.yaml` and will be brought into compliance over time, not as part of the initial port.

---

## Configuration architecture: two distinct artifacts

A critical distinction:

### Fetcher schema (`fetcher.yaml`)

Ships **with** the fetcher in the repo. The fetcher's *self-description*: what config it accepts, what secrets it needs, what version it is, how to invoke it. Doesn't change between runs. Authored by fetcher developers.

See `framework/schemas/fetcher_schema.json`. Required fields:

- `name`, `version`, `description`, `runtime`, `output`, `secrets`

Optional fields:

- `category`, `config_schema`, `supports_targets`, `target_schema`, `depends_on`

Plus optional sub-fields that became real when the first fanout fetcher landed:

- `output.aggregation` — `per_target` | `aggregate` (only meaningful when `supports_targets: true`)
- `secrets[].per_target` — boolean; secret resolved per-target invocation rather than once per fetcher
- `target_schema.<field>.env` — env var name the runner sets from this field per target

Fields like envelope versioning and conditional validation rules remain deliberately cut. They'll be added when their absence causes real friction.

Example for the first ported fetcher:

```yaml
name: okta_phishing_resistant_mfa
version: 0.1.0
description: >
  FedRAMP 20x KSI-IAM-01 evidence. Collects phishing-resistant MFA
  configuration and adoption from Okta.
category: okta

runtime:
  type: python
  entry: fetcher.py

secrets:
  - name: api_token
    env: OKTA_API_TOKEN
  - name: org_url
    env: OKTA_ORG_URL
```

### Run manifest

Lives in the customer's environment, not in the framework repo. The customer's *intent*: which fetchers to invoke, with what config values, against what targets. Read by the runner at execution time. Changes constantly.

Customers will typically have multiple manifests in their environment — one per "kind of run" (daily evidence pull, weekly deep scan, quarterly access review, etc.) — rather than one giant manifest.

The manifest schema lives in `framework/schemas/run_manifest_schema.json`. Minimal v0.x shape:

```yaml
run:
  output_dir: ./evidence
  fetchers:
    - use: <fetcher_name>
      secrets:
        <secret_name>: ${env:VAR_NAME}

    - use: <fanout_fetcher>
      targets:
        - <target_schema_field>: <value>
          secrets:
            <per_target_secret>: ${env:OTHER_VAR}
```

The runner resolves `${env:VAR_NAME}` references from its own environment. See `examples/minimal_run.yaml` for a working example exercising both single-target and fanout shapes.

### Why this split matters

- **Customers never edit fetcher.yaml** — that's your code, your versioned release
- **Runners never hardcode fetcher specifics** — they read `fetcher.yaml` to know what each fetcher needs and resolve generically
- **Secrets are referenced by env var name**, so manifests are safe to commit; resolution happens at runtime
- **The runner is the join point** between code-side contract and customer-side intent

---

## Fanout: many targets, one fetcher

The pattern for "run this fetcher against N targets" (multi-region AWS, multi-project GitLab, multi-cluster K8s, etc.):

- Fetcher's `fetcher.yaml` declares `supports_targets: true`
- Run manifest provides a `targets` list under that fetcher
- Runner iterates: for each target, merge config + target overrides, resolve secrets, invoke fetcher with target identifier
- Each invocation produces its own envelope file, tagged with the target ID
- Independent failure domains — one expired token doesn't break the others

Two aggregation modes:

- **`per_target`** — one envelope per target (e.g., one piece of evidence per GitLab repo)
- **`aggregate`** — fetcher receives the whole target list and emits one combined envelope (e.g., "S3 bucket public access across all buckets")

Both modes are declared via `output.aggregation` in `fetcher.yaml`. The first fanout port (`gitlab_ci_cd_pipeline_config`) uses `per_target`; no `aggregate`-mode fetcher exists yet.

### Inversion from current model

Current `.env` groups by region, lists fetchers under each region:

```
AWS_REGION_1=us-gov-west-1
AWS_REGION_1_FETCHERS=iam_roles,guard_duty
```

New model groups by fetcher, lists regions as targets:

```yaml
- use: iam_roles
  targets:
    - region: us-gov-west-1
    - region: us-east-1
- use: guard_duty
  targets:
    - region: us-gov-west-1
```

Isolates failure domains and avoids re-listing fetchers per region.

---

## Layer 2 / comparators

Comparators satisfy the same contract as fetchers. Their distinguishing properties:

- Their "source" is a directory of prior envelope files, not an external API
- They declare `depends_on: [fetcher_a, fetcher_b]` in their `fetcher.yaml`
- The runner ensures dependencies complete (with acceptable status) before invoking
- They produce envelope output just like any other fetcher

So "reconcile Okta against Rippling" is just a fetcher whose inputs happen to be other fetchers' outputs. No special category, no special runtime, no special data store.

Structurally identical to fetchers. Filed under a separate `comparators/` directory for human navigation, but the runner treats them the same way.

---

## Uploaders as a separate stage

Pushing evidence to Paramify is **not** a fetcher concern. It's a separate stage that:

- Reads envelopes from the run's output directory
- Pushes to Paramify via API
- Handles its own retries, auth, idempotency

Benefits of separation:

- Fetchers can run with no Paramify connection at all (useful for dev, testing, customer dry-runs)
- Customers can insert a review/approval step between fetch and upload
- Re-uploading from a prior run is trivial — point the uploader at an old output directory
- The Wiz-style case (writing issues back to Paramify, not just evidence) becomes a different uploader, not a hack inside the fetcher

---

## Repository structure

```
paramify-fetchers/
├── CLAUDE.md                         # context for Claude Code sessions
├── README.md
├── .gitignore
│
├── framework/                        # contract + runner code
│   ├── contract.py                   # dataclasses (Fetcher, Manifest, RunResult, ...)
│   ├── config_loader.py              # discover fetchers; validate against schema
│   ├── secret_resolver.py            # ${env:VAR_NAME} resolution
│   ├── runner/
│   │   ├── __init__.py               # CLI: list / validate / run subcommands
│   │   ├── __main__.py               # entry point for `python -m framework.runner`
│   │   ├── manifest_loader.py        # load + validate manifests
│   │   └── executor.py               # single-target + fanout execution
│   └── schemas/
│       ├── fetcher_schema.json
│       └── run_manifest_schema.json
│
├── fetchers/                         # 56 fetchers across 7 categories
│   ├── _categories/                  # category metadata (per-category access docs)
│   │   ├── okta.yaml
│   │   ├── aws.yaml
│   │   ├── gitlab.yaml
│   │   └── ...
│   ├── _template/                    # starter directory for new fetchers
│   ├── okta/                         # 8 (7 Python KSI wrappers + 1 bash); _shared/okta_iam_core.py
│   ├── aws/                          # 30 bash (largest category; fanout per region/profile)
│   ├── sentinelone/                  # 5 single-target Python
│   ├── knowbe4/                      # 4 bash
│   ├── k8s/                          # 3 bash (aws-cli + kubectl)
│   ├── rippling/                     # 3 single-target Python
│   └── gitlab/                       # 3 fanout-capable Python (e.g. ci_cd_pipeline_config, KSI-CMT-03)
│
├── comparators/                      # scaffold only (_template/); no comparator ported, runner doesn't honor depends_on
│
├── uploaders/                        # scaffold only (empty paramify_evidence/, paramify_issues/ dirs); separate stage, not implemented
│
├── catalog/                          # not built yet (will be GENERATED from fetcher.yaml files)
│
├── examples/
│   └── minimal_run.yaml              # exercises single-target + fanout
│
├── requirements.txt                  # python-dotenv, requests, pyyaml
│
└── docs/
    ├── design.md                     # this file — design rationale
    ├── handoff.md                    # current state of the work (source of truth)
    ├── fetcher_contract.md           # the runner⇄fetcher contract
    ├── porting_playbook.md           # how to port an existing fetcher (the "why")
    ├── ai_port_recipe.md             # strict imperative port checklist (the "what")
    ├── authoring_a_fetcher.md        # how to write a new fetcher from scratch
    ├── run_manifest_reference.md     # manifest format reference
    └── fetcher_purity_audit.md       # point-in-time audit of the first 26 fetchers
```

### Naming conventions

- Fetcher directories grouped by category: `fetchers/<category>/<short_name>/`
- The fetcher's `name` field in `fetcher.yaml` is globally unique (e.g. `okta_phishing_resistant_mfa`), not category-scoped
- Directories prefixed with `_` are not fetchers (`_categories/`, `_template/`, `_shared/`); runner discovery walks `fetchers/*/*/fetcher.yaml` and skips underscore-prefixed paths

### Shared code

Code shared across fetchers in the same category lives in `fetchers/<category>/_shared/`. Cross-category framework code lives under `framework/`. Per-category shared code (like `okta_iam_core.py`) is allowed to be large and is ported as-is rather than refactored as a side quest.

---

## Catalog: from source of truth to derived artifact

The current `catalog.json` is hand-maintained and conflates several concerns:

- Fetcher discovery (name, script path, description)
- Runtime dependencies (`aws-cli`, `python3`)
- Compliance metadata (`controls`, `solution_capabilities`)
- Output validation rules (regex patterns + pass/fail logic)
- Per-category access guidance

**Decomposition:**

- **Discovery + runtime** → into each `fetcher.yaml`
- **Category metadata** → into `_categories/<name>.yaml`
- **Catalog** → generated by walking the tree and assembling, not hand-maintained

This makes fetchers self-describe and turns the catalog into derived data.

### Two concerns to revisit later

**Compliance metadata (`controls`, `solution_capabilities`):**

Whether a fetcher's output speaks to IAM-01 in one customer's SSP and a different control in another customer's SSP is a *Paramify configuration* concern, not a fetcher concern. Baking it into the fetcher couples its identity to a control framework that will evolve. Likely outcome: demote to documentation or move out of the fetcher entirely; let Paramify own the mapping per customer program.

Not in the current schema. Decide what to do with it after a few more fetchers are ported.

**Validation rules (regex against JSON output):**

The current approach parses JSON output with regex to determine pass/fail. Most fetchers have `validation_rules: []`, so the pattern isn't consistently applied today. The blurry boundary between "evidence was collected" (fetcher concern) and "evidence indicates compliance" (Paramify concern) needs to be resolved before this is ported. Cut from the schema entirely for now.

---

## Current state of the work

**The authoritative, kept-current account of what's ported and what's in
progress lives in [`handoff.md`](handoff.md).** Snapshot: 56 fetchers across
7 categories (okta, aws, sentinelone, knowbe4, gitlab, k8s, rippling); the
AWS port is complete (30/30). The pieces that make this run:

- **Fetcher schema** (`framework/schemas/fetcher_schema.json`) — supports fanout: `supports_targets`, `target_schema`, `per_target` secrets, `output.aggregation`. Extended additively from the original minimal version.
- **Runner** (`framework/runner/`) — `list` / `validate` / `run` subcommands, single-target + fanout execution, per-target failure isolation, secret resolution from `${env:...}` references, `_run_metadata.json` recording (run_id, per-invocation timestamps, durations, exit codes, outputs)
- **Manifest schema** (`framework/schemas/run_manifest_schema.json`) + working example (`examples/minimal_run.yaml`)
- **Secret resolver** (`framework/secret_resolver.py`) — `${env:VAR_NAME}` only for v0.x; shape leaves room for future backends (`${aws-secret:...}`, `${vault:...}`)
- **Conventions established**:
  - Logging: Python `logging` module; bash uses structured `printf` with a matching format
  - Exit codes: v0.x is binary 0/1 — Okta wrappers check `OktaAPIClient.api_failures`; GitLab checks result `status`; bash tracks via temp file (subshells can't mutate parent counters)
  - Output filenames: per_target fetchers derive their own filename from the target identifier
- **Docs** — see the `docs/` tree above; `handoff.md` is the entry point each session.

What's deferred:

- ~~**Envelope schema**~~ — DONE (2026-05-28). The runner wraps each output file in the standard `metadata` + `payload` envelope; fetchers still write raw payloads. See [`envelope_design.md`](envelope_design.md).
- **Uploader** — separate stage; empty scaffold dirs exist under `uploaders/` (`paramify_evidence/`, `paramify_issues/`) but no implementation
- **Comparators** — `comparators/_template/` scaffold exists but no comparator ported; `depends_on` is in the schema but not honored by the runner because nothing consumes it
- **Structured exit codes** — still binary 0/1. Categorized auth/network/internal/partial codes are contract-era work.
- **Catalog generator** — fetchers self-describe; the derived `catalog.json` walker isn't written yet
- **`aggregate` mode** — declared in schema; no fetcher uses it yet
- **Shared module refactor** — `okta_iam_core.py` still reads env directly (with one tiny additive change: it now exposes `api_failures` for exit-code purposes). Full rework waits on the framework's secret resolver taking over per-fetcher invocation.
- **Cleanup**: `framework/common/env_loader.py` (3.4KB) is a verbatim copy of the upstream `common/env_loader.py` that we explicitly chose not to port. The runner doesn't import it; it's unused dead weight that should be removed.

---

## Workflow: handing off to Claude Code

Implementation work is moving to Claude Code. The repo carries enough context for Claude Code to work without re-explaining the design each session:

- `CLAUDE.md` at the repo root holds the operational summary (decisions, conventions, current state, what's NOT being done yet)
- `docs/design.md` (this file) holds the full design rationale
- `framework/schemas/fetcher_schema.json` is the enforceable part of the contract

Claude Code's default behavior is to refactor as it works. For fetcher ports, scope discipline matters: ports are explicitly as-is, with refactoring deferred. The CLAUDE.md and per-task prompts should be explicit about what's out of scope.

---

## Near-term path (separate from this document)

Internal evidence collection is moving to GitHub Actions with OIDC for AWS credentials. This is explicitly a temporary internal solution, not a customer-facing product. Two principles to follow during that work so it doesn't constrain the real framework later:

1. **Keep secret resolution at the workflow layer**, not in the fetchers. Fetchers stay env-var-driven; the Actions workflow handles OIDC → env var resolution. This means the eventual framework's secret resolver replaces the workflow logic without touching fetchers.
2. **Write a `_run_metadata.json`** for each run capturing timestamp, fetcher versions/commit SHA, exit codes, durations. Cheap to add now, gives an audit trail, and validates the shape of the artifact the real framework will produce.

Risk to watch: the Actions workflow becoming the de facto deployment model for customers by inertia. When a customer needs to run fetchers, that's the trigger to do the real framework work, not to generalize the internal workflow.

---

## Open questions

Honest list — these are real and not yet resolved:

- **Schema evolution.** When `fetcher.yaml` changes between versions, how do existing run manifests handle the change? The schema has already been extended once additively (fanout fields); the harder case — renaming/removing fields with manifests in flight — is still untested.
- **Long-running fetchers.** Some scans (SSL Labs) take hours. Framework needs a story for timeouts beyond simple subprocess kill.
- **Customer-authored fetchers.** Distribution, validation, sandboxing, trust model all undefined.
- **Multi-tenancy in a single run.** Can one run touch multiple Paramify programs? Probably not, but worth confirming.
- **Streaming vs. batch.** Current model is batch. Some use cases (ConMon) want continuous streaming, which is a different paradigm.
- **Backfill and replay.** Re-running a fetcher against historical data isn't always possible (most APIs only return current state); framework should be explicit about which fetchers support point-in-time queries.
- **Shared code refactor scope.** When `okta_iam_core.py` (and equivalents for other categories) eventually gets refactored to receive secrets explicitly, what's the migration strategy across the fetchers that depend on it?