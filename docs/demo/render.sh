#!/usr/bin/env bash
# Regenerate the README demo GIFs from the .tape scripts.
#
#   docs/demo/render.sh            # render all tapes
#   docs/demo/render.sh tui        # render just docs/demo/tui.tape
#
# Requires VHS (brew install vhs — pulls ffmpeg + ttyd). Always renders from
# the repo root so the Output paths and `source .venv/bin/activate` line up.
set -euo pipefail

cd "$(dirname "$0")/../.."   # repo root

if ! command -v vhs >/dev/null 2>&1; then
  echo "vhs not found. Install with: brew install vhs" >&2
  exit 1
fi

tapes=("$@")
if [ ${#tapes[@]} -eq 0 ]; then
  tapes=(catalog manifest tui)
fi

for name in "${tapes[@]}"; do
  name=${name%.tape}                 # allow either "tui" or "tui.tape"
  tape="docs/demo/${name}.tape"
  [ -f "$tape" ] || { echo "no such tape: $tape" >&2; exit 1; }
  echo "==> rendering $tape"
  vhs "$tape"
done

# Scratch dir created by manifest.tape — never commit it.
rm -rf docs/demo/.scratch
echo "done."
