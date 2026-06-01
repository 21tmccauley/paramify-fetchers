#!/bin/bash
#
# KnowBe4 — Module-Based Training Summary
#
# Aggregates all active training enrollments by module name with per-module
# assignment and completion metrics. Used for compliance evidence where
# completion does not map cleanly to a single campaign.
#
# Output: $EVIDENCE_DIR/knowbe4_module_based_summary.json
# Required env: KNOWBE4_API_KEY, KNOWBE4_REGION

set -o pipefail

[ -f .env ] && { set -a; . .env; set +a; }

OUTPUT_DIR="${EVIDENCE_DIR:-./evidence}"
mkdir -p "$OUTPUT_DIR"

if [ -z "${KNOWBE4_API_KEY:-}" ]; then
    echo "ERROR knowbe4_module_based_summary: KNOWBE4_API_KEY is not set" >&2
    exit 1
fi
if [ -z "${KNOWBE4_REGION:-}" ]; then
    echo "ERROR knowbe4_module_based_summary: KNOWBE4_REGION is not set" >&2
    exit 1
fi

OUTPUT_JSON="$OUTPUT_DIR/knowbe4_module_based_summary.json"
_FETCHER_TMP_JSON="$(mktemp -t knowbe4_module_based_summary.XXXXXX.json)"
_FAILURE_LOG="$(mktemp -t knowbe4_module_based_summary_fail.XXXXXX)"
trap 'rm -f "$_FETCHER_TMP_JSON" "$_FAILURE_LOG"' EXIT

log_info() {
    printf '%s INFO knowbe4_module_based_summary %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_error() {
    printf '%s ERROR knowbe4_module_based_summary %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

make_api_call() {
    local endpoint=$1
    local url="https://${KNOWBE4_REGION}.api.knowbe4.com/v1/${endpoint}"
    local response
    if ! response=$(curl -sf -H "Authorization: Bearer ${KNOWBE4_API_KEY}" -H "Content-Type: application/json" "${url}"); then
        echo "GET ${endpoint}" >> "$_FAILURE_LOG"
        echo "{}"
        return 1
    fi
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo "GET ${endpoint} (invalid JSON)" >> "$_FAILURE_LOG"
        echo "{}"
        return 1
    fi
    echo "$response"
    return 0
}

make_paginated_api_call() {
    local endpoint="$1"
    local page=1
    local all_results="[]"
    local separator
    if [[ "$endpoint" == *\?* ]]; then separator="&"; else separator="?"; fi

    while true; do
        response=$(make_api_call "${endpoint}${separator}page=${page}")
        count=$(echo "$response" | jq 'length' 2>/dev/null || echo 0)
        if [ "$count" -eq 0 ]; then break; fi
        all_results=$(jq -s '.[0] + .[1]' <(echo "$all_results") <(echo "$response"))
        page=$((page + 1))
    done
    echo "$all_results"
}

echo '{
  "results": {
    "enrollments": [],
    "summary": {
      "training_module_summary": {}
    }
  }
}' > "$OUTPUT_JSON"

enrollments_response=$(make_paginated_api_call "training/enrollments?exclude_archived_users=true&include_campaign_id=true")

echo "$enrollments_response" | jq -c '.[] | del(.policy_acknowledged)' | while read -r enrollment; do
    jq --argjson e "$enrollment" \
      '.results.enrollments += [$e]' \
      "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
done

module_summary=$(jq '
    .results.enrollments
    | sort_by(.module_name)
    | group_by(.module_name)
    | map(
        . as $group
        | {
            module: $group[0].module_name,
            assigned: ($group | length),
            passed: ($group | map(select(.status == "Passed")) | length),
            completion_rate:
              (if ($group | length) > 0
               then (
                 (($group | map(select(.status == "Passed")) | length) * 100.0
                 / ($group | length)
                 ) | floor
               )
               else 0
               end)
        }
    )
    | map({
        (.module): {
          assigned: .assigned,
          passed: .passed,
          completion_rate: .completion_rate
        }
    })
    | add
' "$OUTPUT_JSON")

jq --argjson module_summary "$module_summary" \
  '.results.summary.training_module_summary = $module_summary' \
  "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"

failure_count=$(wc -l < "$_FAILURE_LOG" 2>/dev/null | tr -d ' ')
failure_count=${failure_count:-0}
if [ "$failure_count" -gt 0 ]; then
    log_error "Encountered $failure_count API failures during collection"
    exit 1
fi

log_info "Evidence saved to $OUTPUT_JSON"
