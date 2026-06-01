# Paramify Fetcher Framework

## What this is
A redesign of Paramify's evidence fetcher system. Fetchers pull data from
customer tools (Okta, AWS, GitLab, etc.) and produce JSON evidence files
that get uploaded to Paramify.

## Current state
Pre-1.0. 56 fetchers ported across 7 categories (okta, aws, sentinelone,
knowbe4, gitlab, k8s, rippling); the AWS category is complete (30/30);
v0.x runner built (`framework/runner/`);
manifest format settled (see `examples/minimal_run.yaml`). Ported fetchers
are version 0.x and write raw evidence payloads; the runner wraps each output
file in the standard evidence envelope (`metadata` + `payload`, see
`docs/envelope_design.md`). See `docs/handoff.md` for the current
state-of-the-work breakdown and `docs/design.md` for the design rationale.

## Key design decisions
- Fetchers run on customer infrastructure, not Paramify infra
- Each fetcher self-describes via a `fetcher.yaml` validated against
  `framework/schemas/fetcher_schema.json`
- Fetchers produce JSON files on disk; an uploader stage (separate)
  pushes to Paramify
- Cross-fetcher comparisons (e.g., Okta vs Rippling) are "comparators"
  that satisfy the same contract but read prior fetcher outputs
- Customers will eventually run fetchers via their own orchestration
  (GitHub Actions, cron, etc.); the framework doesn't own scheduling

## Directory layout
- `framework/` — shared code (runner, schemas, contract)
- `fetchers/<category>/<name>/` — one directory per fetcher
- `fetchers/<category>/_shared/` — code shared across fetchers in a category
- `fetchers/_categories/<name>.yaml` — category metadata + platform-wide
  `config_schema` and `auth.passthrough_env` (validated against
  `framework/schemas/category_schema.json`)
- Directories starting with `_` are not fetchers; runner discovery skips them

## Fetcher schema
Required: name, version, description, runtime, output, secrets.
Optional: category, config_schema, supports_targets, target_schema,
depends_on. Plus optional sub-fields: output.aggregation,
secrets[].per_target, target_schema.<field>.env (for fanout fetchers),
config_schema.<field>.env (runner injects the value as that env var),
runtime.timeout (per-invocation cap in seconds, default 600).
See `framework/schemas/fetcher_schema.json`.

## Config & auth injection
The runner injects non-secret config as env vars from `config_schema`
(per-fetcher) and `_categories/<category>.yaml` (platform-wide), merged with
a manifest `platforms:` block (category defaults ← platform values ← per-fetcher
config). `auth.passthrough_env` lets ambient cloud-identity vars (e.g. IRSA)
through the runner's minimal env whitelist. Every env var a fetcher reads must
be declared as a secret OR a config field, else the runner strips it. See
`docs/config_injection_design.md`.

## Conventions
- Fetcher entry point is `fetcher.py` or `fetcher.sh`
- Fetcher name in `fetcher.yaml` is globally unique (e.g.
  `okta_phishing_resistant_mfa`), not category-scoped
- Versions follow semver (0.x.y for pre-contract-conformant ports)
- Secrets are declared in fetcher.yaml; fetchers should NOT read env
  vars directly. v0.x ports do this anyway as an accepted interim
  violation — their entry script calls `load_dotenv()` and reads
  `os.environ` for both secrets and `EVIDENCE_DIR`. The framework's
  runner + secret resolver will replace this pattern.

## What we're NOT doing yet
- Refactoring shared code like okta_iam_core.py (port as-is; one tiny
  additive change for `api_failures` is the exception, not the start of
  a refactor)
- Uploader integration (separate stage; the envelope it consumes is now
  built — runner wraps outputs — but the uploader itself is not)
- Comparators (`depends_on` is in the schema but the runner doesn't
  honor it yet — no consumer)
- Structured exit code categories (auth-failure vs. target-unreachable
  vs. internal); v0.x is binary 0/1

## Active conventions
- v0.x port pattern: see `docs/porting_playbook.md` for the per-fetcher
  steps and the "don't" list
- Exit codes: fetcher returns non-zero on collection failures; how that's
  detected is per-shared-module (Okta uses `OktaAPIClient.api_failures`,
  GitLab uses result `status`, bash tracks via temp file)
- Secrets are source-agnostic — fetchers read `os.environ`; how that env
  gets populated (`.env`, export, AWS Secrets Manager, Vault, K8s, etc.)
  is the customer/runner's choice. `.env` is not privileged.