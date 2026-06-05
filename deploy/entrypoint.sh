#!/usr/bin/env bash
#
# Container entrypoint. Two roles:
#   1. Pass-through runner  — `docker compose run --rm collector paramify run ...`
#      (also: bash, paramify tui, python ..., anything). This is the default.
#   2. Scheduler            — `... scheduler` runs cron on a cadence (see crontab).
#
set -euo pipefail
cd /app

# Default upload host if the caller didn't set one. Must be https (the uploader
# refuses to send the bearer token over cleartext to a non-loopback host).
export PARAMIFY_API_BASE_URL="${PARAMIFY_API_BASE_URL:-https://stage.paramify.com/api/v0}"

case "${1:-}" in
  scheduler)
    echo "[entrypoint] starting cron scheduler (times are UTC inside the container)"
    # cron does NOT inherit the container's environment. Snapshot it so each job
    # can restore it via BASH_ENV (see deploy/crontab). NOTE: values containing
    # single quotes won't survive this simple snapshot — fine for typical tokens.
    printenv | sed -E "s/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/export \1='\2'/" > /tmp/container-env.sh
    crontab /app/deploy/crontab
    echo "[entrypoint] installed crontab:"
    crontab -l | sed 's/^/    /'
    exec cron -f
    ;;
  ""|-h|--help)
    echo "usage: <command>            run any command (default: paramify list)"
    echo "       scheduler            run cron on the cadence in deploy/crontab"
    echo
    echo "examples:"
    echo "   docker compose run --rm collector paramify list"
    echo "   docker compose run --rm collector paramify run deploy/manifests/daily.yaml"
    echo "   docker compose run --rm collector ./deploy/run-and-upload.sh daily"
    echo "   docker compose run --rm collector paramify tui"
    echo "   docker compose run --rm collector bash"
    exec paramify list
    ;;
  *)
    exec "$@"
    ;;
esac
