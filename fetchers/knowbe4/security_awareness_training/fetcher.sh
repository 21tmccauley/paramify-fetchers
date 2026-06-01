#!/bin/bash
#
# KnowBe4 — Annual Security Awareness Training Validation
#
# Tracks completion of the annual SAT campaign for all active users.
# Flags users needing retraining (last completion > 1 year ago).
#
# Output: $EVIDENCE_DIR/knowbe4_security_awareness_training.json
# Required env: KNOWBE4_API_KEY, KNOWBE4_REGION

set -o pipefail

[ -f .env ] && { set -a; . .env; set +a; }

OUTPUT_DIR="${EVIDENCE_DIR:-./evidence}"
mkdir -p "$OUTPUT_DIR"

if [ -z "${KNOWBE4_API_KEY:-}" ]; then
    echo "ERROR knowbe4_security_awareness_training: KNOWBE4_API_KEY is not set" >&2
    exit 1
fi
if [ -z "${KNOWBE4_REGION:-}" ]; then
    echo "ERROR knowbe4_security_awareness_training: KNOWBE4_REGION is not set" >&2
    exit 1
fi

OUTPUT_JSON="$OUTPUT_DIR/knowbe4_security_awareness_training.json"
_FETCHER_TMP_JSON="$(mktemp -t knowbe4_security_awareness_training.XXXXXX.json)"
_FAILURE_LOG="$(mktemp -t knowbe4_security_awareness_training_fail.XXXXXX)"
trap 'rm -f "$_FETCHER_TMP_JSON" "$_FAILURE_LOG"' EXIT

log_info() {
    printf '%s INFO knowbe4_security_awareness_training %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_error() {
    printf '%s ERROR knowbe4_security_awareness_training %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

SECURITY_AWARENESS_CAMPAIGN="2026 Annual Security Awareness Training"
# Portable 1-year-ago timestamp (handle macOS vs GNU date)
ONE_YEAR_AGO=$(date -u -v-1y +%s 2>/dev/null || date -u -d "1 year ago" +%s)

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
    "users": [],
    "enrollments": [],
    "user_training_status": {},
    "user_retraining_required": {},
    "summary": {
      "total_users": 0,
      "completed_training": 0,
      "in_progress": 0,
      "past_due": 0,
      "not_started": 0,
      "needs_retraining": 0,
      "completion_rate": 0
    }
  }
}' > "$OUTPUT_JSON"

users_response=$(make_paginated_api_call "users")
enrollments_response=$(make_paginated_api_call "training/enrollments?exclude_archived_users=true&include_campaign_id=true")

security_awareness_enrollments=$(echo "$enrollments_response" | jq -c \
  --arg campaign "$SECURITY_AWARENESS_CAMPAIGN" \
  '[.[] | select(.campaign_name == $campaign)]')

echo "$users_response" | jq -c '.[] | select(.status == "active")' | while read -r user; do
    user_id=$(echo "$user" | jq -r '.id')
    user_email=$(echo "$user" | jq -r '.email')

    minimal_user=$(echo "$user" | jq '{id: .id, email: .email, status: .status}')
    jq --argjson user "$minimal_user" \
       '.results.users += [$user]' \
       "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"

    user_enrollments=$(echo "$security_awareness_enrollments" | jq -c \
        --arg user_id "$user_id" \
        '[.[] | select(.user.id == ($user_id|tonumber))]')

    user_status="not_started"
    needs_retraining=false

    if echo "$user_enrollments" | jq -e 'type=="array" and length > 0' >/dev/null; then
        while read -r enrollment; do
            jq --argjson enrollment "$enrollment" \
               '.results.enrollments += [$enrollment]' \
               "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
        done < <(echo "$user_enrollments" | jq -c '.[]')

        total_modules=$(echo "$user_enrollments" | jq 'length')
        passed_modules=$(echo "$user_enrollments" | jq '[.[] | select(.status == "Passed")] | length')

        if [ "$passed_modules" -eq "$total_modules" ] && [ "$total_modules" -gt 0 ]; then
            user_status="completed"
            latest_passed_date=$(echo "$user_enrollments" | jq -r '[.[] | .completion_date] | max')
            # Portable date parse: try GNU date first, fall back to BSD/macOS
            completed_epoch=$(date -u -d "$latest_passed_date" +%s 2>/dev/null \
                          || date -j -u -f "%Y-%m-%dT%H:%M:%S" "${latest_passed_date%.*}" +%s 2>/dev/null \
                          || echo "")
            if [ -n "$completed_epoch" ] && [ "$completed_epoch" -lt "$ONE_YEAR_AGO" ]; then
                needs_retraining=true
            fi
        elif echo "$user_enrollments" | jq -e 'any(.status == "Past Due")' >/dev/null; then
            user_status="past_due"
        elif echo "$user_enrollments" | jq -e 'any(.status == "In Progress" or .status == "Passed")' >/dev/null; then
            user_status="in_progress"
        fi
    fi

    jq --arg email "$user_email" \
       --arg status "$user_status" \
       --argjson retrain "$needs_retraining" \
       '.results.user_training_status[$email] = $status
        | .results.user_retraining_required[$email] = $retrain' \
       "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
done

total_users=$(jq '.results.users | length' "$OUTPUT_JSON")
completed_training=$(jq '.results.user_training_status | to_entries | map(select(.value == "completed")) | length' "$OUTPUT_JSON")
in_progress=$(jq '.results.user_training_status | to_entries | map(select(.value == "in_progress")) | length' "$OUTPUT_JSON")
past_due=$(jq '.results.user_training_status | to_entries | map(select(.value == "past_due")) | length' "$OUTPUT_JSON")
not_started=$(jq '.results.user_training_status | to_entries | map(select(.value == "not_started")) | length' "$OUTPUT_JSON")
needs_retraining=$(jq '.results.user_retraining_required | to_entries | map(select(.value == true)) | length' "$OUTPUT_JSON")
completion_rate=0
if [ "$total_users" -gt 0 ]; then
    completion_rate=$((completed_training * 100 / total_users))
fi

jq --arg total "$total_users" \
   --arg completed "$completed_training" \
   --arg in_progress "$in_progress" \
   --arg past_due "$past_due" \
   --arg not_started "$not_started" \
   --arg needs_retraining "$needs_retraining" \
   --arg rate "$completion_rate" \
   '.results.summary = {
       "total_users": ($total|tonumber),
       "completed_training": ($completed|tonumber),
       "in_progress": ($in_progress|tonumber),
       "past_due": ($past_due|tonumber),
       "not_started": ($not_started|tonumber),
       "needs_retraining": ($needs_retraining|tonumber),
       "completion_rate": ($rate|tonumber)
   }' "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"

failure_count=$(wc -l < "$_FAILURE_LOG" 2>/dev/null | tr -d ' ')
failure_count=${failure_count:-0}
if [ "$failure_count" -gt 0 ]; then
    log_error "Encountered $failure_count API failures during collection"
    exit 1
fi

log_info "Evidence saved to $OUTPUT_JSON"
