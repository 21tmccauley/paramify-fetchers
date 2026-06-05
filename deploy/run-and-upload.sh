#!/usr/bin/env bash
#
# Collect a cadence's manifest, then upload the resulting run to Paramify.
# These are two SEPARATE framework stages; this script just chains them — the
# kind of glue that lives in your cron/CI, not in the framework itself.
#
#   ./deploy/run-and-upload.sh [cadence]      # cadence -> deploy/manifests/<cadence>.yaml
#
# Secrets must already be in the environment (the manifest references them as
# ${env:VAR}); PARAMIFY_UPLOAD_API_TOKEN is required for the upload step.
set -uo pipefail
cd "$(dirname "$0")/.."   # repo root (/app in the image)

cadence="${1:-daily}"
manifest="deploy/manifests/${cadence}.yaml"
if [ ! -f "$manifest" ]; then
    echo "no manifest for cadence '$cadence' (expected $manifest)" >&2
    exit 2
fi

echo "==> [$cadence] collect: $manifest"
paramify run "$manifest"
collect_rc=$?
if [ "$collect_rc" -ne 0 ]; then
    echo "WARN: collect exited $collect_rc (a fetcher reported failures); uploading whatever was produced" >&2
fi

echo "==> [$cadence] upload latest run -> ${PARAMIFY_API_BASE_URL:-<default>}"
python uploaders/paramify_evidence/uploader.py
upload_rc=$?

# Surface the worst non-zero so cron/monitoring can alert.
if [ "$collect_rc" -ne 0 ]; then exit "$collect_rc"; fi
exit "$upload_rc"
