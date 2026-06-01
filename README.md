# Paramify Fetchers

Fetchers pull compliance evidence from the tools your organization already runs
— Okta, AWS, GitLab, SentinelOne, KnowBe4, Kubernetes, Rippling — and write it
to disk as JSON. A later stage uploads that evidence to Paramify. This repo is
the fetchers plus the runner that executes them; it does not talk to Paramify
directly.

There are 56 fetchers across 7 categories today. If you're a GRC or security
engineer here to add evidence collection for a new control or a new tool, this
README is for you.

```
  customer tool  ──fetcher──▶  JSON evidence file  ──uploader──▶  Paramify
   (Okta, AWS…)                (on disk, per run)     (separate stage)
```

---

## How it runs

Three pieces, kept deliberately separate:

- **Fetcher** — a small script (`fetcher.py` or `fetcher.sh`) that collects from
  *one* source and writes a JSON file. It reads everything it needs from
  environment variables and writes only to `EVIDENCE_DIR`.
- **`fetcher.yaml`** — the fetcher's self-description: its name, what secrets and
  config it needs, what it outputs. Ships with the code, validated against a
  schema. Customers never edit this.
- **Run manifest** — the customer's intent: which fetchers to run, with what
  config, against what targets. Lives in the customer's environment, not here.
- **Runner** — reads `fetcher.yaml` files and a manifest, resolves secrets and
  config into environment variables, and executes each fetcher.

```bash
python -m framework.runner list                  # discover + schema-validate every fetcher
python -m framework.runner validate <manifest>   # validate a manifest without running
python -m framework.runner run      <manifest>   # run it
```

Output lands in `<output_dir>/run-<timestamp>/`, one JSON file per fetcher (or
per target for fan-out), alongside a `_run_metadata.json` audit record.

---

## Why the design is strict

Every fetcher is forced through one contract, validated by JSON Schema, with a
narrow set of allowed shapes. That rigidity is intentional. The previous
generation of fetchers were freeform scripts, and each one invented its own
conventions for config, secrets, and output — which is exactly why none of them
composed and the central catalog had to be hand-maintained in sync. A few
principles keep that from happening again:

- **One contract, schema-enforced.** A fetcher declares itself in `fetcher.yaml`,
  validated at discovery time. Anything not in the schema is not a thing a
  fetcher can do. This is what lets the runner treat 56 fetchers identically.
- **Fetchers run on customer infrastructure**, never Paramify's. So a fetcher
  never assumes a Paramify connection, and the framework owns no scheduling.
- **Secrets are source-agnostic.** A fetcher reads `OKTA_API_TOKEN` from the
  environment. It never knows or cares whether that came from a `.env` file,
  AWS Secrets Manager, Vault, or a CI secret block — because every one of those
  already knows how to set an environment variable. We do not write per-provider
  secret integrations, and we don't intend to.
- **Collect facts; interpret elsewhere.** A fetcher gathers evidence. Whether
  that evidence *satisfies* a control is a Paramify-side mapping, not the
  fetcher's job. Keep pass/fail verdicts and compliance thresholds out of
  fetchers.
- **One source per fetcher.** Cross-source comparison (e.g. Okta users vs.
  Rippling employees) is a separate "comparator" that reads prior outputs — same
  contract, different inputs. A fetcher never reads another fetcher's output.

The full contract is in [`docs/fetcher_contract.md`](docs/fetcher_contract.md);
the rationale is in [`docs/design.md`](docs/design.md).

> **Status:** pre-1.0 (v0.x). Fetchers still write raw evidence dicts rather than
> an enveloped `metadata`+`payload` format, and read env directly rather than
> receiving a typed secrets object — both are tracked interim shortcuts, not the
> target. See `docs/design.md` for what's deferred.

---

## Repository layout

```
framework/                      # the runner, contract, schemas (shared code)
  schemas/                      # fetcher / manifest / category JSON Schemas
  runner/                       # list | validate | run
fetchers/
  _categories/<name>.yaml       # platform-wide config + auth for a category
  _template/                    # copy this to start a new fetcher
  <category>/
    _shared/                    # code shared across fetchers in this category
    <short_name>/               # one directory per fetcher
      fetcher.yaml
      fetcher.py | fetcher.sh
      README.md
comparators/                    # cross-source comparators (scaffold only so far)
uploaders/                      # push evidence to Paramify (scaffold only so far)
examples/                       # sample run manifests
docs/                           # contract, design, playbooks, this guide's deep dives
```

Directories starting with `_` are not fetchers — the runner skips them.

---

## Adding a new fetcher

The mechanical, copy-paste version with verify commands is
[`docs/ai_port_recipe.md`](docs/ai_port_recipe.md); the narrative version with
rationale is [`docs/authoring_a_fetcher.md`](docs/authoring_a_fetcher.md). The
short path:

### 1. Pick a category and a short name

The category is the source system (`okta`, `aws`, `gitlab`…). The short name is
the specific evidence (`phishing_resistant_mfa`). The globally-unique fetcher
name is the two joined: `okta_phishing_resistant_mfa`. The **directory** is the
short name only.

```bash
cp -r fetchers/_template fetchers/<category>/<short_name>
```

If the category is new, create `fetchers/_categories/<category>.yaml` (an empty
file is valid) and, if fetchers will share code, a `fetchers/<category>/_shared/`.

### 2. Fill in `fetcher.yaml`

Declare what the fetcher needs. The required fields:

```yaml
name: <category>_<short_name>          # globally unique
version: 0.1.0
description: <one or two sentences — what evidence this collects>
category: <category>

supports_targets: false                # true only for fan-out (see below)

runtime:
  type: python                         # or bash
  entry: fetcher.py                    # or fetcher.sh

output:
  type: json
  path: <category>_<short_name>.json   # filename inside EVIDENCE_DIR

secrets:                               # one entry per SECRET env var read
  - name: api_token
    env: <UPPER_SNAKE_ENV_VAR>
```

**Secrets vs. config.** A `secrets:` entry is a credential. A *non-secret* knob
(a base URL, a page size, a boolean toggle) goes in `config_schema:` instead, so
the runner injects it as an env var:

```yaml
config_schema:
  exclude_aws_managed_roles:
    type: boolean
    default: false
    env: EXCLUDE_AWS_MANAGED_ROLES
    description: When true, skip AWS-managed roles.
```

Every environment variable your fetcher reads must be declared as either a
secret or a config field — otherwise the runner strips it (it passes only a
minimal, declared environment to each fetcher) and your knob silently does
nothing.

Verify the YAML before writing code:

```bash
python -m framework.runner list   # your fetcher should appear; errors mean fix the yaml
```

### 3. Write the entry script

The contract the script must honor:

- Read `EVIDENCE_DIR` from the environment (default `./evidence`); write **only**
  there. The runner sets the working directory to your fetcher's own folder, so
  a relative or hard-coded write path will pollute the repo — always write under
  `EVIDENCE_DIR`.
- Write the JSON file named in `output.path`.
- Read secrets/config from the env var names you declared.
- Log status to stderr (Python: the `logging` module; bash: `printf … >&2`). No
  `print()` chatter, no progress spam.
- **Exit non-zero if collection failed** — if any API call, target, or
  precondition failed. Returning 0 with empty data hides outages and is the one
  mistake that makes evidence untrustworthy.

The Python skeleton (`fetchers/_template/fetcher.py`) and the bash equivalent in
[`docs/porting_playbook.md`](docs/porting_playbook.md) §5 give you the frame. The
only part you write is the data collection in the middle.

**Detecting failure** has no single recipe; pick what fits:

| Style | Pattern |
|---|---|
| Python, requests in the script | a `failures: list` appended in the `except` block, checked at the end → `return 1` |
| Python, requests in a shared client | expose a `client.api_failures` list; check it in the wrapper |
| Bash | append each failed call to a temp file, `wc -l` it at the end, `exit 1` if non-zero |

(Bash subshells in `… | while read` can't update a parent counter — that's why
the temp-file pattern exists. Wrap **every** external call; a single unguarded
one is how a fetcher exits 0 on a partial failure.)

### 4. Smoke-test the wiring with fake creds

Prove the env-passing path before pointing at a real tenant:

```bash
<YOUR_ENV_VAR>=fake EVIDENCE_DIR=/tmp/verify \
  python fetchers/<category>/<short_name>/fetcher.py
echo "exit: $?"
```

You want a **non-zero exit** with a DNS/connection/401 error — that proves the
env vars arrived and the fetcher reached the network. An exit of 0 with empty
data means your failure detection (step 3) is wrong. For bash, run
`bash -n fetcher.sh && chmod +x fetcher.sh` first.

### 5. Run it through the runner

Add the fetcher to a manifest (see `examples/`), then:

```bash
python -m framework.runner validate path/to/manifest.yaml
python -m framework.runner run      path/to/manifest.yaml
```

Confirm the JSON lands in the run directory and the contents look right.

---

## Fan-out: one fetcher, many targets

When a fetcher should run once per target (per AWS region, per GitLab project,
per cluster), set `supports_targets: true` and declare a `target_schema`. The
runner iterates, sets per-target env vars, runs the entry once per target, and
isolates failures so one bad target doesn't sink the rest. Worked example:
[`fetchers/gitlab/ci_cd_pipeline_config/`](fetchers/gitlab/ci_cd_pipeline_config/).

---

## Adding a new platform (category)

Most fetchers in a category share connection settings (a base URL, a region) and
an auth model. Put those once in `fetchers/_categories/<category>.yaml` rather
than repeating them per fetcher:

```yaml
description: Rippling Platform API.

config_schema:                 # injected for every fetcher in this category
  base_url:
    type: string
    default: https://api.rippling.com
    env: RIPPLING_BASE_URL

auth:                          # for cloud-identity auth (e.g. AWS IRSA)
  passthrough_env:
    - AWS_WEB_IDENTITY_TOKEN_FILE
```

Customers override these per run in the manifest's `platforms:` block. The full
model — platform config, per-fetcher config, and how auth (`.env`, secret
managers, or ambient cloud identity) flows — is in
[`docs/config_injection_design.md`](docs/config_injection_design.md).

---

## Where to read next

| Doc | What it covers |
|---|---|
| [`docs/fetcher_contract.md`](docs/fetcher_contract.md) | The binding runner↔fetcher contract |
| [`docs/authoring_a_fetcher.md`](docs/authoring_a_fetcher.md) | Writing a new fetcher from scratch (narrative) |
| [`docs/ai_port_recipe.md`](docs/ai_port_recipe.md) | Strict step-by-step checklist with verify commands |
| [`docs/run_manifest_reference.md`](docs/run_manifest_reference.md) | Manifest format |
| [`docs/config_injection_design.md`](docs/config_injection_design.md) | Platform/config/auth model |
| [`docs/design.md`](docs/design.md) | Why the framework is shaped this way |
| [`docs/handoff.md`](docs/handoff.md) | Current state of the work |
