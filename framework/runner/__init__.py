"""Paramify fetcher framework runner — v0.x.

A thin command surface over framework.api (the shared facade). Every command —
human or AI — goes through the facade; nothing here re-implements discovery,
validation, manifest editing, or execution.

Read / discover:
  python -m framework.runner list [--json]            # discovered fetchers (flat)
  python -m framework.runner catalog [--json]         # categories -> fetchers -> fields
  python -m framework.runner describe <fetcher> [--json]

Manifest editing (writes the manifest file; -f/--file, default ./manifest.yaml):
  python -m framework.runner manifest init [--output-dir DIR]
  python -m framework.runner manifest add <fetcher>
  python -m framework.runner manifest remove <fetcher>
  python -m framework.runner manifest set-config <fetcher> key=value
  python -m framework.runner manifest set-secret <fetcher> <secret_name> <ENV_VAR>
  python -m framework.runner manifest add-target <fetcher> k=v ... [--secret name=ENV_VAR ...]
  python -m framework.runner manifest set-platform-config <category> key=value
  python -m framework.runner manifest set-passthrough <category> ENV_VAR [ENV_VAR ...]
  python -m framework.runner manifest set-output-dir <dir>
  python -m framework.runner manifest show [--json]

Validate / run:
  python -m framework.runner validate <manifest> [--json]
  python -m framework.runner run <manifest> [--json]

Secrets are referenced as ${env:VAR} — set-secret/add-target take the ENV VAR
NAME, never the secret value. The runner resolves refs from its own environment.
Outputs land in <output_dir>/run-<timestamp>/ with a _run_metadata.json.
"""

import argparse
import json
import sys
from pathlib import Path

from framework import api

_DEFAULT_MANIFEST = "manifest.yaml"


def _coerce(raw: str, typ: str):
    """Coerce a CLI string value to a config/target field's declared type."""
    if typ == "boolean":
        return raw.strip().lower() in ("true", "1", "yes", "on")
    if typ == "integer":
        return int(raw)
    return raw


def _split_kv(arg: str):
    if "=" not in arg:
        raise ValueError(f"expected key=value, got: {arg!r}")
    key, value = arg.split("=", 1)
    return key, value


# --------------------------------------------------------------------------- #
# Discover / describe
# --------------------------------------------------------------------------- #

def cmd_list(args) -> int:
    root = api.find_repo_root()
    cat = api.catalog(root)
    fetchers = sorted(
        (f for c in cat["categories"] for f in c["fetchers"]),
        key=lambda f: f["name"],
    )
    if args.json:
        print(json.dumps(fetchers, indent=2))
        return 0
    if not fetchers:
        print("No fetchers discovered.")
        return 0
    print(f"Discovered {len(fetchers)} fetchers:\n")
    for f in fetchers:
        st = "fanout" if f["supports_targets"] else "single"
        print(f"  {f['name']:50s} v{f['version']:8s} [{st:6s}] category={f['category'] or '-'}")
    return 0


def cmd_catalog(args) -> int:
    root = api.find_repo_root()
    cat = api.catalog(root)
    if args.json:
        print(json.dumps(cat, indent=2))
        return 0
    for c in cat["categories"]:
        desc = f" — {c['description'].strip()}" if c.get("description") else ""
        print(f"\n{c['name']}{desc}")
        if c.get("platform") and c["platform"]["config"]:
            keys = ", ".join(f["name"] for f in c["platform"]["config"])
            print(f"  platform config: {keys}")
        for f in c["fetchers"]:
            tag = "fanout" if f["supports_targets"] else "single"
            print(f"    {f['name']:48s} [{tag}]")
    return 0


def _find_fetcher(cat: dict, name: str):
    for c in cat["categories"]:
        for f in c["fetchers"]:
            if f["name"] == name:
                return f
    return None


def cmd_describe(args) -> int:
    root = api.find_repo_root()
    cat = api.catalog(root)
    f = _find_fetcher(cat, args.fetcher)
    if f is None:
        print(f"Unknown fetcher: {args.fetcher}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(f, indent=2))
        return 0
    print(f"{f['name']}  v{f['version']}  (category={f['category'] or '-'})")
    print(f"  {f['description']}")
    print(f"  supports_targets: {f['supports_targets']}")
    for label, fields in (("config", f["config"]), ("secrets", f["secrets"]),
                          ("target_schema", f["target_schema"])):
        if fields:
            print(f"  {label}:")
            for fld in fields:
                req = "required" if fld.get("required") else "optional"
                extra = f" default={fld['default']}" if fld.get("default") is not None else ""
                print(f"    - {fld['name']} ({fld['type']}, {req}){extra}")
    return 0


# --------------------------------------------------------------------------- #
# Validate / run
# --------------------------------------------------------------------------- #

def cmd_validate(args) -> int:
    root = api.find_repo_root()
    try:
        manifest = api.read_manifest(Path(args.manifest).resolve())
    except Exception as e:  # noqa: BLE001 — surface any load error to the user
        print(f"Validation failed: {e}", file=sys.stderr)
        return 1
    errors = api.validate(manifest, root)
    if args.json:
        print(json.dumps({"ok": not errors, "errors": errors}, indent=2))
        return 0 if not errors else 1
    if errors:
        for e in errors:
            print(f"  ERROR  {e}", file=sys.stderr)
        return 1
    n = len(manifest.get("run", {}).get("fetchers", []))
    print(f"OK  manifest valid; {n} fetcher entries")
    return 0


def _human_run_printer():
    """Return an on_event callback that reproduces the original CLI run output."""
    def on_event(ev: dict) -> None:
        kind = ev["event"]
        if kind == "run_start":
            print(f"Run {ev['run_id']} → {ev['run_dir']}\n")
        elif kind == "fetcher_skip":
            print(f"  SKIP  {ev['fetcher']} ({ev['reason']})", file=sys.stderr)
        elif kind == "fetcher_start":
            if ev["fanout"]:
                print(f"  RUN   {ev['fetcher']}  ({ev['targets']} targets)")
            else:
                print(f"  RUN   {ev['fetcher']}")
        elif kind == "fetcher_error":
            print(f"        runner error: {ev['error']}", file=sys.stderr)
        elif kind == "fetcher_result":
            mark = "OK" if ev["exit_code"] == 0 else "FAIL"
            target = f"  target={ev['target']}" if ev["target"] else ""
            print(f"        [{mark}] exit={ev['exit_code']} duration={ev['duration_sec']}s{target}")
        elif kind == "run_complete":
            print(f"\n_run_metadata.json → {ev['metadata_path']}")
        # log_line is intentionally not printed (matches prior non-streaming CLI)
    return on_event


def cmd_run(args) -> int:
    root = api.find_repo_root()
    try:
        manifest = api.read_manifest(Path(args.manifest).resolve())
    except Exception as e:  # noqa: BLE001
        print(f"Setup failed: {e}", file=sys.stderr)
        return 1
    try:
        summary = api.run(manifest, root, on_event=None if args.json else _human_run_printer())
    except (ValueError, RuntimeError) as e:
        print(f"Run failed: {e}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(summary, indent=2, default=str))
    return 0 if summary["ok"] else 1


# --------------------------------------------------------------------------- #
# Manifest editing
# --------------------------------------------------------------------------- #

def _config_type(root: Path, fetcher_name: str, key: str) -> str:
    """Look up a config field's declared type (fetcher then platform), else string."""
    cat = api.catalog(root)
    f = _find_fetcher(cat, fetcher_name)
    if f:
        for fld in f["config"]:
            if fld["name"] == key:
                return fld["type"]
        cat_name = f["category"]
        for c in cat["categories"]:
            if c["name"] == cat_name and c.get("platform"):
                for fld in c["platform"]["config"]:
                    if fld["name"] == key:
                        return fld["type"]
    return "string"


def _platform_config_type(root: Path, category: str, key: str) -> str:
    cat = api.catalog(root)
    for c in cat["categories"]:
        if c["name"] == category and c.get("platform"):
            for fld in c["platform"]["config"]:
                if fld["name"] == key:
                    return fld["type"]
    return "string"


def _target_field_type(root: Path, fetcher_name: str, key: str) -> str:
    cat = api.catalog(root)
    f = _find_fetcher(cat, fetcher_name)
    if f:
        for fld in f["target_schema"]:
            if fld["name"] == key:
                return fld["type"]
    return "string"


def cmd_manifest(args) -> int:
    root = api.find_repo_root()
    path = Path(args.file).resolve()
    op = args.manifest_op

    if op == "init":
        manifest = api.init_manifest(args.output_dir)
    else:
        try:
            manifest = api.read_manifest(path)
        except Exception as e:  # noqa: BLE001
            print(f"Could not read {path}: {e}", file=sys.stderr)
            return 1

    if op == "add":
        api.add_entry(manifest, args.fetcher)
    elif op == "remove":
        api.remove_entry(manifest, args.fetcher)
    elif op == "set-config":
        key, value = _split_kv(args.kv)
        api.set_fetcher_config(manifest, args.fetcher, key, _coerce(value, _config_type(root, args.fetcher, key)))
    elif op == "set-secret":
        api.set_secret(manifest, args.fetcher, args.secret_name, args.env_var)
    elif op == "add-target":
        values = {}
        for kv in args.values:
            k, v = _split_kv(kv)
            values[k] = _coerce(v, _target_field_type(root, args.fetcher, k))
        secret_env = {}
        for s in (args.secret or []):
            k, v = _split_kv(s)
            secret_env[k] = v
        api.add_target(manifest, args.fetcher, values, secret_env or None)
    elif op == "set-platform-config":
        key, value = _split_kv(args.kv)
        api.set_platform_config(manifest, args.category, key, _coerce(value, _platform_config_type(root, args.category, key)))
    elif op == "set-passthrough":
        api.set_passthrough_env(manifest, args.category, args.env_vars)
    elif op == "set-output-dir":
        api.set_output_dir(manifest, args.output_dir)
    elif op == "show":
        if args.json:
            print(json.dumps(manifest, indent=2))
        else:
            import yaml
            print(yaml.safe_dump(manifest, sort_keys=False))
        return 0

    try:
        api.dump_manifest(manifest, path, root)
    except ValueError as e:
        print(f"Not written: {e}", file=sys.stderr)
        return 1

    errors = api.validate(manifest, root)
    print(f"Wrote {path}")
    if errors:
        print("  (manifest saved but not yet runnable):", file=sys.stderr)
        for e in errors:
            print(f"    {e}", file=sys.stderr)
    return 0


# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="framework.runner",
        description="Paramify fetcher framework runner",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list", help="List discovered fetchers")
    p_list.add_argument("--json", action="store_true", help="Emit JSON")
    p_list.set_defaults(func=cmd_list)

    p_cat = sub.add_parser("catalog", help="Categories -> fetchers -> editable fields")
    p_cat.add_argument("--json", action="store_true", help="Emit JSON")
    p_cat.set_defaults(func=cmd_catalog)

    p_desc = sub.add_parser("describe", help="Describe one fetcher's fields")
    p_desc.add_argument("fetcher")
    p_desc.add_argument("--json", action="store_true", help="Emit JSON")
    p_desc.set_defaults(func=cmd_describe)

    p_val = sub.add_parser("validate", help="Validate a manifest")
    p_val.add_argument("manifest", help="Path to manifest yaml")
    p_val.add_argument("--json", action="store_true", help="Emit JSON")
    p_val.set_defaults(func=cmd_validate)

    p_run = sub.add_parser("run", help="Run a manifest")
    p_run.add_argument("manifest", help="Path to manifest yaml")
    p_run.add_argument("--json", action="store_true", help="Emit JSON summary")
    p_run.set_defaults(func=cmd_run)

    # -f/--file is shared by every manifest subcommand (via a parent parser) so
    # it can appear in any position, e.g. `manifest add okta -f m.yaml`.
    file_parser = argparse.ArgumentParser(add_help=False)
    file_parser.add_argument("-f", "--file", default=_DEFAULT_MANIFEST, help="Manifest path")

    p_man = sub.add_parser("manifest", help="Create/edit a manifest file")
    man_sub = p_man.add_subparsers(dest="manifest_op", required=True)
    man_sub.add_parser("init", parents=[file_parser]).add_argument("--output-dir", default="./evidence")
    man_sub.add_parser("add", parents=[file_parser]).add_argument("fetcher")
    man_sub.add_parser("remove", parents=[file_parser]).add_argument("fetcher")
    m_sc = man_sub.add_parser("set-config", parents=[file_parser])
    m_sc.add_argument("fetcher")
    m_sc.add_argument("kv", help="key=value")
    m_ss = man_sub.add_parser("set-secret", parents=[file_parser])
    m_ss.add_argument("fetcher")
    m_ss.add_argument("secret_name")
    m_ss.add_argument("env_var", help="ENV VAR NAME holding the secret (not the value)")
    m_at = man_sub.add_parser("add-target", parents=[file_parser])
    m_at.add_argument("fetcher")
    m_at.add_argument("values", nargs="*", help="target field key=value pairs")
    m_at.add_argument("--secret", action="append", help="per_target secret name=ENV_VAR")
    m_pc = man_sub.add_parser("set-platform-config", parents=[file_parser])
    m_pc.add_argument("category")
    m_pc.add_argument("kv", help="key=value")
    m_pt = man_sub.add_parser("set-passthrough", parents=[file_parser])
    m_pt.add_argument("category")
    m_pt.add_argument("env_vars", nargs="+")
    man_sub.add_parser("set-output-dir", parents=[file_parser]).add_argument("output_dir")
    m_show = man_sub.add_parser("show", parents=[file_parser])
    m_show.add_argument("--json", action="store_true")
    p_man.set_defaults(func=cmd_manifest)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
