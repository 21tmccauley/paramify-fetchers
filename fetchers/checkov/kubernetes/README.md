# checkov_kubernetes

Runs [Checkov](https://www.checkov.io/) IaC security scanning over the Kubernetes
manifests in a repository and emits the result as JSON evidence.

A **scanner** fetcher (see `../terraform/README.md` for the archetype). Each
invocation shallow-clones one git repo with the per-target `GIT_CLONE_TOKEN`,
runs `checkov --framework kubernetes` over its `.yaml`/`.yml` files, and records
pass/fail/skip counts plus repo + commit provenance. The runner fans out across
repos.

## Runner dependencies
`git`, `checkov`, and `jq` on PATH (`checkov` via the top-level `requirements.txt`).

## Target (per repo)
Same as `checkov_terraform`: `repo_url` (`CHECKOV_REPO_URL`, required),
`branch` (`CHECKOV_CLONE_BRANCH`, optional), secret `clone_token`
(`GIT_CLONE_TOKEN`, per-target, omit for public repos).

## Config knobs
Two-tier skip model: `../_shared/skip-checks-k8s.default.txt` (a curated set of
commonly-failing/too-strict K8s checks) is **merged** with `skip_checks`.

`soft_fail` (default true), `compact` (true), `repo_id`, `skip_checks`
(`CKV_K8S_*`/`CKV2_K8S_*` only), `skip_paths`, `checks` (allowlist),
`external_checks_dir`, `git_username`. See `fetcher.yaml` for full descriptions.

## Output & exit codes
Writes `checkov_kubernetes_<repo>.json` with `metadata` (`repo_url`, `branch`,
`commit_sha`, `scan_timestamp`), `summary`, and `results`.

- **exit 0** — scan completed, including with failed checks (findings are
  evidence); also when the repo has no manifests (`status: no_files`).
- **exit 1** — could not clone, missing `CHECKOV_REPO_URL`, or checkov failed
  (`status: error`).
