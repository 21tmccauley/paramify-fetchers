#!/bin/bash
#
# AWS — Auto Scaling High Availability
#
# Lists Auto Scaling Groups and their EC2 instances.
#
# Output: $EVIDENCE_DIR/aws_auto_scaling_high_availability.json
# Required env: AWS_PROFILE, AWS_DEFAULT_REGION
# Required tools: aws, jq

set -o pipefail

[ -f .env ] && { set -a; . .env; set +a; }

OUTPUT_DIR="${EVIDENCE_DIR:-./evidence}"
mkdir -p "$OUTPUT_DIR"

if [ -z "${AWS_PROFILE:-}" ]; then
    echo "ERROR aws_auto_scaling_high_availability: AWS_PROFILE is not set" >&2; exit 1
fi
if [ -z "${AWS_DEFAULT_REGION:-}" ]; then
    echo "ERROR aws_auto_scaling_high_availability: AWS_DEFAULT_REGION is not set" >&2; exit 1
fi

PROFILE="$AWS_PROFILE"
REGION="$AWS_DEFAULT_REGION"

# Per-target output filename (profile+region) so multi-target runs don't overwrite.
_TARGET_ID=$(printf '%s_%s' "$PROFILE" "$REGION" | tr -c 'A-Za-z0-9._-' '_')
OUTPUT_JSON="$OUTPUT_DIR/aws_auto_scaling_high_availability_${_TARGET_ID}.json"
_FETCHER_TMP_JSON="$(mktemp -t aws_auto_scaling_high_availability.XXXXXX.json)"
_FAILURE_LOG="$(mktemp -t aws_auto_scaling_high_availability_fail.XXXXXX)"
trap 'rm -f "$_FETCHER_TMP_JSON" "$_FAILURE_LOG"' EXIT

log_info() { printf '%s INFO aws_auto_scaling_high_availability %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_error() { printf '%s ERROR aws_auto_scaling_high_availability %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }

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

asgs=$(aws autoscaling describe-auto-scaling-groups --profile "$PROFILE" --region "$REGION" --query 'AutoScalingGroups[*]' --output json 2>/dev/null)
asg_exit=$?
if [ $asg_exit -ne 0 ]; then
    echo "aws autoscaling describe-auto-scaling-groups failed (exit=$asg_exit)" >> "$_FAILURE_LOG"
    log_error "Failed to describe Auto Scaling groups"
else
    echo "$asgs" | jq -c '.[]' | while read -r asg; do
        asg_name=$(echo "$asg" | jq -r '.AutoScalingGroupName')

        asg_instances=$(aws autoscaling describe-auto-scaling-instances --profile "$PROFILE" --region "$REGION" \
            --query "AutoScalingInstances[?AutoScalingGroupName=='$asg_name'][*]" --output json 2>/dev/null)
        inst_exit=$?
        if [ $inst_exit -ne 0 ]; then
            echo "aws autoscaling describe-auto-scaling-instances ($asg_name) failed" >> "$_FAILURE_LOG"
            asg_instances='[]'
        fi

        jq --argjson asg "$asg" --argjson instances "$asg_instances" \
           '.results += [{"Type": "AutoScalingGroup", "ASGInfo": $asg, "Instances": $instances}]' \
           "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
    done
fi

failure_count=$(wc -l < "$_FAILURE_LOG" 2>/dev/null | tr -d ' ')
failure_count=${failure_count:-0}
if [ "$failure_count" -gt 0 ]; then
    log_error "Encountered $failure_count AWS API failures during collection"
    exit 1
fi

log_info "Evidence saved to $OUTPUT_JSON"
