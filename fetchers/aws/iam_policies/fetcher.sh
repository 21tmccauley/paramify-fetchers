#!/bin/bash
#
# AWS — IAM Policies
#
# Lists customer-managed IAM policies and per-policy default version document
# + attached entities.
#
# Output: $EVIDENCE_DIR/aws_iam_policies.json
# Required env: AWS_PROFILE, AWS_DEFAULT_REGION
# Required tools: aws, jq

set -o pipefail

[ -f .env ] && { set -a; . .env; set +a; }

OUTPUT_DIR="${EVIDENCE_DIR:-./evidence}"
mkdir -p "$OUTPUT_DIR"

if [ -z "${AWS_PROFILE:-}" ]; then
    echo "ERROR aws_iam_policies: AWS_PROFILE is not set" >&2; exit 1
fi

PROFILE="$AWS_PROFILE"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Per-account output filename (profile) — global service, region not part of identity.
_TARGET_ID=$(printf '%s' "$PROFILE" | tr -c 'A-Za-z0-9._-' '_')
OUTPUT_JSON="$OUTPUT_DIR/aws_iam_policies_${_TARGET_ID}.json"
_FETCHER_TMP_JSON="$(mktemp -t aws_iam_policies.XXXXXX.json)"
_FAILURE_LOG="$(mktemp -t aws_iam_policies_fail.XXXXXX)"
trap 'rm -f "$_FETCHER_TMP_JSON" "$_FAILURE_LOG"' EXIT

log_info() { printf '%s INFO aws_iam_policies %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_error() { printf '%s ERROR aws_iam_policies %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }

CALLER_IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" --output json 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "aws sts get-caller-identity failed" >> "$_FAILURE_LOG"
    CALLER_IDENTITY='{"Account":"unknown","Arn":"unknown"}'
fi
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account // "unknown"')
ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn // "unknown"')
DATETIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg profile "$PROFILE" --arg region "$REGION" --arg datetime "$DATETIME" \
  --arg account_id "$ACCOUNT_ID" --arg arn "$ARN" \
  '{"metadata": {"profile": $profile, "region": $region, "datetime": $datetime, "account_id": $account_id, "arn": $arn}, "results": []}' \
  > "$OUTPUT_JSON"

policies=$(aws iam list-policies --profile "$PROFILE" --region "$REGION" --scope Local --query 'Policies[*].[PolicyName,PolicyId,Arn]' --output json 2>/dev/null)
list_exit=$?
if [ $list_exit -ne 0 ]; then
    echo "aws iam list-policies failed (exit=$list_exit)" >> "$_FAILURE_LOG"
    log_error "Failed to list IAM policies"
else
    echo "$policies" | jq -c '.[]' | while read -r policy; do
        policy_arn=$(echo "$policy" | jq -r '.[2]')

        policy_data=$(aws iam get-policy --profile "$PROFILE" --region "$REGION" --policy-arn "$policy_arn" --query 'Policy' --output json 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "aws iam get-policy ($policy_arn) failed" >> "$_FAILURE_LOG"
            continue
        fi

        default_version=$(echo "$policy_data" | jq -r '.DefaultVersionId')

        policy_doc=$(aws iam get-policy-version --profile "$PROFILE" --region "$REGION" --policy-arn "$policy_arn" --version-id "$default_version" --query 'PolicyVersion.Document' --output json 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "aws iam get-policy-version ($policy_arn, $default_version) failed" >> "$_FAILURE_LOG"
            policy_doc='{}'
        fi

        attached_entities=$(aws iam list-entities-for-policy --profile "$PROFILE" --region "$REGION" --policy-arn "$policy_arn" --query '[PolicyGroups[*].GroupName,PolicyUsers[*].UserName,PolicyRoles[*].RoleName]' --output json 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "aws iam list-entities-for-policy ($policy_arn) failed" >> "$_FAILURE_LOG"
            attached_entities='[[],[],[]]'
        fi

        policy_info=$(jq -n \
            --argjson policy "$policy_data" \
            --argjson doc "$policy_doc" \
            --argjson entities "$attached_entities" \
            '{
                "PolicyName": $policy.PolicyName,
                "PolicyId": $policy.PolicyId,
                "Arn": $policy.Arn,
                "CreateDate": $policy.CreateDate,
                "UpdateDate": $policy.UpdateDate,
                "Description": $policy.Description,
                "PolicyDocument": $doc,
                "AttachedGroups": $entities[0],
                "AttachedUsers": $entities[1],
                "AttachedRoles": $entities[2]
            }')

        jq --argjson policy "$policy_info" '.results += [$policy]' "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
    done
fi

failure_count=$(wc -l < "$_FAILURE_LOG" 2>/dev/null | tr -d ' ')
failure_count=${failure_count:-0}
if [ "$failure_count" -gt 0 ]; then
    log_error "Encountered $failure_count AWS API failures during collection"
    exit 1
fi

log_info "Evidence saved to $OUTPUT_JSON"
