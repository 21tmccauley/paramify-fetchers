#!/bin/bash
#
# KnowBe4 — High-Risk (Role-Specific) Training Validation
#
# Identifies users in high-risk groups (Cloud Ops, IT, DevOps), checks
# completion of role-specific campaigns ("Privileged Users Training (Before
# CloudOps Access)"), reports per-user status with summary metrics.
#
# Output: $EVIDENCE_DIR/knowbe4_high_risk_training.json
# Required env: KNOWBE4_API_KEY, KNOWBE4_REGION

set -o pipefail

[ -f .env ] && { set -a; . .env; set +a; }

OUTPUT_DIR="${EVIDENCE_DIR:-./evidence}"
mkdir -p "$OUTPUT_DIR"

if [ -z "${KNOWBE4_API_KEY:-}" ]; then
    echo "ERROR knowbe4_high_risk_training: KNOWBE4_API_KEY is not set" >&2
    exit 1
fi
if [ -z "${KNOWBE4_REGION:-}" ]; then
    echo "ERROR knowbe4_high_risk_training: KNOWBE4_REGION is not set" >&2
    exit 1
fi

OUTPUT_JSON="$OUTPUT_DIR/knowbe4_high_risk_training.json"
_FETCHER_TMP_JSON="$(mktemp -t knowbe4_high_risk_training.XXXXXX.json)"
_FAILURE_LOG="$(mktemp -t knowbe4_high_risk_training_fail.XXXXXX)"
trap 'rm -f "$_FETCHER_TMP_JSON" "$_FAILURE_LOG"' EXIT

log_info() {
    printf '%s INFO knowbe4_high_risk_training %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_error() {
    printf '%s ERROR knowbe4_high_risk_training %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

ROLE_SPECIFIC_CAMPAIGNS=("Privileged Users Training (Before CloudOps Access)")

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
    "high_risk_users": [],
    "role_specific_campaigns": [],
    "enrollments": [],
    "user_training_status": {},
    "high_risk_groups": [],
    "summary": {
      "total_high_risk_users": 0,
      "completed_training": 0,
      "in_progress": 0,
      "past_due": 0,
      "not_started": 0,
      "completion_rate": 0,
      "total_campaigns": 0,
      "total_groups": 0
    }
  }
}' > "$OUTPUT_JSON"

users_response=$(make_paginated_api_call "users")
campaigns_response=$(make_paginated_api_call "training/campaigns")
enrollments_response=$(make_paginated_api_call "training/enrollments?exclude_archived_users=true&include_campaign_id=true")
groups_response=$(make_paginated_api_call "groups")

for campaign_name in "${ROLE_SPECIFIC_CAMPAIGNS[@]}"; do
    echo "$campaigns_response" | jq -c --arg name "$campaign_name" \
      '.[] | select(.name == $name)' | while read -r campaign; do
        jq --argjson campaign "$campaign" \
          '.results.role_specific_campaigns += [$campaign]' \
          "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
    done
done

high_risk_groups=("Cloud Ops" "IT" "DevOps")
high_risk_users=()
while read -r group_json; do
    group_name=$(echo "$group_json" | jq -r '.name')
    group_id=$(echo "$group_json" | jq -r '.id')
    for risk_group in "${high_risk_groups[@]}"; do
        if [[ "$group_name" == *"$risk_group"* ]]; then
            group_members=$(make_api_call "groups/$group_id/members")
            jq --arg name "$group_name" --arg id "$group_id" \
               '.results.high_risk_groups += [{"name": $name, "id": $id}]' \
               "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
            while read -r user_json; do
                user_email=$(echo "$user_json" | jq -r '.email')
                if [[ ! " ${high_risk_users[@]} " =~ " ${user_email} " ]]; then
                    high_risk_users+=("$user_email")
                    minimal_user=$(echo "$user_json" | jq '{id: .id, email: .email, status: .status}')
                    jq --argjson user "$minimal_user" \
                       '.results.high_risk_users += [$user]' \
                       "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
                fi
            done < <(echo "$group_members" | jq -c '.[] | select(.status == "active")')
            break
        fi
    done
done < <(echo "$groups_response" | jq -c '.[]')

for user_email in "${high_risk_users[@]}"; do
    user=$(echo "$users_response" | jq -c --arg email "$user_email" '.[] | select(.email == $email)')
    user_id=$(echo "$user" | jq -r '.id')

    campaign_filter=$(printf ' or .campaign_name == "%s"' "${ROLE_SPECIFIC_CAMPAIGNS[@]}")
    campaign_filter=${campaign_filter# or }

    user_enrollments=$(echo "$enrollments_response" | jq -c \
        --arg user_id "$user_id" \
        ".[] | select(.user.id == (\$user_id|tonumber) and ( $campaign_filter ))" | jq -s '.')

    user_status="not_started"
    if [ "$user_enrollments" != "[]" ]; then
        echo "$user_enrollments" | jq -c '.[]' | while read -r enrollment; do
            clean_enrollment=$(echo "$enrollment" | jq 'del(.policy_acknowledged)')
            jq --argjson enrollment "$clean_enrollment" \
              '.results.enrollments += [$enrollment]' \
              "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
        done

        if echo "$user_enrollments" | jq -e 'all(.status == "Passed")' >/dev/null 2>&1; then
            user_status="completed"
        elif echo "$user_enrollments" | jq -e 'any(.status == "Past Due")' >/dev/null 2>&1; then
            user_status="past_due"
        elif echo "$user_enrollments" | jq -e 'any(.status == "In Progress")' >/dev/null 2>&1; then
            user_status="in_progress"
        fi
    fi

    jq --arg email "$user_email" --arg status "$user_status" \
       '.results.user_training_status[$email] = $status' \
       "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
done

total_high_risk_users=$(jq '.results.high_risk_users | length' "$OUTPUT_JSON")
completed_training=$(jq '.results.user_training_status | to_entries | map(select(.value == "completed")) | length' "$OUTPUT_JSON")
in_progress=$(jq '.results.user_training_status | to_entries | map(select(.value == "in_progress")) | length' "$OUTPUT_JSON")
past_due=$(jq '.results.user_training_status | to_entries | map(select(.value == "past_due")) | length' "$OUTPUT_JSON")
not_started=$(jq '.results.user_training_status | to_entries | map(select(.value == "not_started")) | length' "$OUTPUT_JSON")
total_campaigns=$(jq '.results.role_specific_campaigns | length' "$OUTPUT_JSON")
total_groups=$(jq '.results.high_risk_groups | length' "$OUTPUT_JSON")
completion_rate=0
if [ "$total_high_risk_users" -gt 0 ]; then
    completion_rate=$((completed_training * 100 / total_high_risk_users))
fi

jq --arg total "$total_high_risk_users" \
   --arg completed "$completed_training" \
   --arg in_progress "$in_progress" \
   --arg past_due "$past_due" \
   --arg not_started "$not_started" \
   --arg rate "$completion_rate" \
   --arg campaigns "$total_campaigns" \
   --arg groups "$total_groups" \
   '.results.summary = {
       "total_high_risk_users": ($total|tonumber),
       "completed_training": ($completed|tonumber),
       "in_progress": ($in_progress|tonumber),
       "past_due": ($past_due|tonumber),
       "not_started": ($not_started|tonumber),
       "completion_rate": ($rate|tonumber),
       "total_campaigns": ($campaigns|tonumber),
       "total_groups": ($groups|tonumber)
   }' "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"

failure_count=$(wc -l < "$_FAILURE_LOG" 2>/dev/null | tr -d ' ')
failure_count=${failure_count:-0}
if [ "$failure_count" -gt 0 ]; then
    log_error "Encountered $failure_count API failures during collection"
    exit 1
fi

log_info "Evidence saved to $OUTPUT_JSON"
