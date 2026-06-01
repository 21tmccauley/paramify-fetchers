# gitlab_ci_cd_pipeline_config

Pulls `.gitlab-ci.yml` for a single GitLab project and analyzes it for test
stages, security scanning, deployment jobs, and artifact configuration.

## Fanout-capable (v0.x)

This fetcher is **single-target per invocation** but declares
`supports_targets: true` in its `fetcher.yaml`. Fanout across multiple
projects happens at the runner layer (when the runner lands) — the runner
reads the manifest's `targets:` list, resolves per-target secrets and config,
sets the corresponding env vars, and exec's this script once per target.

For now (no runner yet), invoke directly with env vars set per project:

```bash
GITLAB_URL=https://gitlab.example.com \
GITLAB_API_TOKEN=glpat-... \
GITLAB_PROJECT_ID=group/project \
python fetchers/gitlab/ci_cd_pipeline_config/fetcher.py
```

To collect evidence for N projects, loop over them externally (cron, CI job,
shell loop), setting the per-target env vars for each invocation.

## Required env vars

| Var | Purpose | Declared in |
|-----|---------|-------------|
| `GITLAB_URL` | GitLab instance URL | `target_schema.url` |
| `GITLAB_API_TOKEN` | API token (project access token recommended) | `secrets` (per-target) |
| `GITLAB_PROJECT_ID` | Project path, e.g. `group/project` | `target_schema.project_id` |
| `GITLAB_BRANCH` | Branch (defaults to `main`) | `target_schema.branch` |
| `EVIDENCE_DIR` | Output directory (defaults to `./evidence`) | runner-set |

The fetcher reads from `os.environ`; how those vars get populated (`.env`,
`export`, secret manager, K8s, CI provider secrets, etc.) is the runner's /
customer's choice.

## Output

`<EVIDENCE_DIR>/gitlab_ci_cd_pipeline_config_<sanitized_project_id>.json`

The project ID is sanitized for filesystem safety: slashes become underscores
and any non-alphanumeric character (except `_-`) is collapsed. So
`group/change-management` produces
`gitlab_ci_cd_pipeline_config_group_change-management.json`.

## Exit codes

- `0` — success, or `.gitlab-ci.yml` not found (which is itself meaningful evidence)
- `1` — required env var missing, or hard API/network error

Structured exit code categories (auth-failure vs. target-unreachable vs.
internal) are deferred to the contract work.

## Known v0.x interim behavior

- Reads env vars directly via `os.environ` (replaced by the framework's secret resolver later).
- Reads `EVIDENCE_DIR` from env (replaced by the runner passing an output path later).
- Output filename includes target identifier via `sanitize_for_filename(project_id)` — this logic moves to the runner when output templating is formalized.
