# AI Port Recipe (v0.x)

**Purpose:** strict imperative recipe an AI agent can follow to port a fetcher with minimum decision-making. Each step has a verify command; STOP if any verify fails.

For rationale and tradeoffs see [`porting_playbook.md`](porting_playbook.md). This doc is the *what to do*, not the *why*.

---

## Inputs you need before starting

- `<category>` — e.g. `okta`, `gitlab`, `sentinelone`
- `<source_filename>` — the `.py` or `.sh` in `paramify/evidence-fetchers/fetchers/<category>/`
- `<short_name>` — `<source_filename>` minus the `<category>_` prefix and extension
- Globally-unique name — `<category>_<short_name>` (used in `name:` and logger and output filename, NOT the directory)

---

## Step 0: Pre-flight (STOP on any failure)

```bash
# Source must exist upstream
gh api repos/paramify/evidence-fetchers/contents/fetchers/<category>/<source_filename> > /dev/null

# No collision locally
test ! -d "fetchers/<category>/<short_name>"

# Category yaml exists (create empty stub if not — see Step 0b)
test -f "fetchers/_categories/<category>.yaml"

# Inventory env reads — this is your secrets: list. Read the output.
gh api repos/paramify/evidence-fetchers/contents/fetchers/<category>/<source_filename> \
  | python3 -c "import json,sys,base64; print(base64.b64decode(json.load(sys.stdin)['content']).decode())" \
  | grep -E 'os\.(environ|getenv)|getenv\('
```

**Decide fanout:** YES if any of these are true, else NO:
- Source iterates over a list of targets internally (for project in projects, for region in regions, etc.)
- Env vars look per-target (`*_PROJECT_ID`, `*_REGION`, `*_HOST`, `*_BRANCH`)
- The upstream `.env.example` shows `<CATEGORY>_PROJECT_<N>_*` or `<CATEGORY>_REGION_<N>_*` patterns

## Step 0b: New category? (only if `_categories/<category>.yaml` is missing)

```bash
touch fetchers/_categories/<category>.yaml
mkdir -p fetchers/<category>
# If the source has a shared module (e.g. okta_iam_core.py), also:
mkdir -p fetchers/<category>/_shared
# ...then port the shared module verbatim into _shared/
# Add any new Python deps to requirements.txt
```

---

## Step 1: Scaffold

```bash
cp -r fetchers/_template fetchers/<category>/<short_name>
```

**Verify:**
```bash
ls fetchers/<category>/<short_name>/
# Expect: README.md  fetcher.py  fetcher.yaml  schemas/  tests/
```

---

## Step 2: Write `fetcher.yaml`

Fill in every placeholder. The minimal shape:

```yaml
name: <category>_<short_name>
version: 0.1.0
description: <one or two sentences>
category: <category>

supports_targets: <true|false>      # explicit, not default

runtime:
  type: python                       # or bash
  entry: fetcher.py                  # or fetcher.sh

output:
  type: json
  path: <category>_<short_name>.json

secrets:
- name: api_token
  env: <UPPER_SNAKE_FROM_PRE_FLIGHT>
# ... one entry per env var the source reads
```

**If `supports_targets: true`,** also add:

```yaml
target_schema:
  <field>:
    type: string
    required: true
    env: <UPPER_SNAKE>
    description: ...
  # ... one entry per per-target field

output:
  type: json
  path: <category>_<short_name>.json
  aggregation: per_target

secrets:
- name: api_token
  env: <UPPER_SNAKE>
  per_target: true
```

**Verify:**
```bash
.venv/bin/python -m framework.runner list
# Your fetcher must appear in the list. If runner list errors, fix the yaml.
```

---

## Step 3: Write the entry script

### For Python (`fetcher.py`)

Start from the skeleton in [`porting_playbook.md`](porting_playbook.md) § 5. **Do NOT paste the upstream source verbatim** — the source uses the pattern we're moving away from. Apply this exact transformation:

| Upstream | Replace with |
|---|---|
| `sys.path.insert(0, ...)` to find `common/env_loader` | Delete |
| `from common.env_loader import parse_fetcher_args` | `from dotenv import load_dotenv` + `import logging` |
| `output_dir, _profile, _region = parse_fetcher_args()` | `output_dir = Path(os.environ.get("EVIDENCE_DIR", "./evidence"))` |
| `print("✅ Evidence saved to ...")` (or any `print` chatter) | `logger.info("Evidence saved to %s", output_path)` |
| `def main():` | `def main() -> int:` |
| `if __name__ == "__main__": main()` | `if __name__ == "__main__": sys.exit(main())` |
| No exit code handling | Return `1` if data collection had failures (see Step 4) |

**Add at module level:**

```python
logger = logging.getLogger("<category>_<short_name>")
```

**Inside `main()`, first thing:**

```python
logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
load_dotenv()
```

Keep all the upstream's data-collection helpers (pagination, parsing, analysis). Only the entry-point shape changes.

**Verify:**
```bash
.venv/bin/python -c "
import importlib.util
spec = importlib.util.spec_from_file_location('chk', 'fetchers/<category>/<short_name>/fetcher.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print('OK logger=' + m.logger.name)
"
```

### For Bash (`fetcher.sh`)

Use the bash skeleton in [`porting_playbook.md`](porting_playbook.md) § 5. Drop ANSI color codes and "Processing X" echo chatter from the upstream. Add `set -o pipefail` near the top.

**Verify:**
```bash
bash -n fetchers/<category>/<short_name>/fetcher.sh
chmod +x fetchers/<category>/<short_name>/fetcher.sh
```

---

## Step 4: Add exit-code detection

If the source already returns `1` on hard errors via a `status` field (gitlab style) — preserve that. Done.

If the source swallows API failures and returns `0` regardless (okta_iam_core, sentinelone style):

- **Python with shared module that does the requests:** add an `api_failures: List[Dict]` list on the shared client, append in the `RequestException` handler, check it in the wrapper. See the Okta `OktaAPIClient.api_failures` pattern.
- **Python where the entry script does the requests:** add `api_failures: List[Dict]` as a parameter to `fetch_all_pages`, append on exception, surface in result dict, check in `main()`. See `fetchers/sentinelone/agents/fetcher.py`.
- **Bash:** use a temp file counter pattern (subshells in `… | while read` can't mutate parent counters). See `fetchers/okta/authenticators/fetcher.sh`.

The rule: any unhandled network failure during data collection → exit non-zero.

---

## Step 5: Smoke-test wiring with fake creds

```bash
<UPPER_ENV>=fake-token \
<ANOTHER_ENV>=https://fake.example \
EVIDENCE_DIR=/tmp/paramify-verify \
.venv/bin/python fetchers/<category>/<short_name>/fetcher.py
echo "exit: $?"
```

**Acceptable:**
- Exit non-zero with DNS / connection / 401 error in the log
- Output JSON written

**STOP and fix if:**
- Exit 0 — your exit-code detection (Step 4) doesn't work
- `ModuleNotFoundError` — fix imports in `fetcher.py`
- `Missing required env var` raised before main work begins — fix the env var name in `fetcher.yaml` or the test command

---

## Step 6: Final acceptance

```bash
# (a) All yamls validate (your new one included)
.venv/bin/python -m framework.runner list

# (b) Module imports cleanly
.venv/bin/python -c "
import importlib.util
spec = importlib.util.spec_from_file_location('chk', 'fetchers/<category>/<short_name>/fetcher.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print('OK')
"

# (c) Fake-cred smoke test exits non-zero
EVIDENCE_DIR=/tmp/paramify-verify \
<ENV_VARS>=fake \
.venv/bin/python fetchers/<category>/<short_name>/fetcher.py
test $? -ne 0 && echo "PASS" || echo "FAIL exit was 0 — fix Step 4"
```

All three must pass.

---

## Anti-patterns (NEVER do)

| ❌ Don't | ✓ Do |
|---|---|
| Directory `<category>_<short_name>/` | Directory `<short_name>/` |
| Yaml file `fether.yaml` / `fetcher.yml` / anything else | Yaml file `fetcher.yaml` exactly |
| `version: 1.0.0` | `version: 0.1.0` for pre-contract-conformant ports |
| Keep `from common.env_loader import …` | Drop it; use `load_dotenv()` |
| Keep `parse_fetcher_args()` / `--output-dir` / `--profile` / `--region` | Read `EVIDENCE_DIR` from env only |
| Keep `print(…)` for status | Use `logger.info(…)` |
| `def main():` without return type | `def main() -> int:` |
| `if __name__ == "__main__": main()` | `if __name__ == "__main__": sys.exit(main())` |
| Forget `chmod +x` on `fetcher.sh` | `chmod +x` after writing |
| Add `controls:` / `validation_rules:` / `tags:` to yaml | Cut from v0.x — schema rejects them |
| Refactor `_shared/` modules structurally | Only ADDITIVE changes (e.g., `api_failures` list) |
| Paste source verbatim and just rename imports | Apply the transformation table in Step 3 |

---

## When you're stuck

If verify commands fail in ways not described here:

1. Compare your port file-by-file to the closest reference (see [`porting_playbook.md`](porting_playbook.md) § "Reference ports")
2. Run `.venv/bin/python -m framework.runner validate <some-manifest.yaml>` to see schema errors with line context
3. Check that `requirements.txt` has any new deps your source imports (e.g. `pyyaml` was added for `gitlab_ci_cd_pipeline_config`)
4. Confirm the upstream `.env.example` shows the env vars you've declared — name mismatches are easy to miss
