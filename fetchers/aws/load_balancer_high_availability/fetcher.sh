#!/bin/bash
#
# AWS — Load Balancer High Availability
#
# Lists ELBv2 load balancers (ALB, NLB) and per-LB target groups, attributes,
# and availability zones.
#
# Output: $EVIDENCE_DIR/aws_load_balancer_high_availability.json
# Required env: AWS_PROFILE, AWS_DEFAULT_REGION
# Required tools: aws, jq

set -o pipefail

[ -f .env ] && { set -a; . .env; set +a; }

OUTPUT_DIR="${EVIDENCE_DIR:-./evidence}"
mkdir -p "$OUTPUT_DIR"

if [ -z "${AWS_PROFILE:-}" ]; then
    echo "ERROR aws_load_balancer_high_availability: AWS_PROFILE is not set" >&2; exit 1
fi
if [ -z "${AWS_DEFAULT_REGION:-}" ]; then
    echo "ERROR aws_load_balancer_high_availability: AWS_DEFAULT_REGION is not set" >&2; exit 1
fi

PROFILE="$AWS_PROFILE"
REGION="$AWS_DEFAULT_REGION"

# Per-target output filename (profile+region) so multi-target runs don't overwrite.
_TARGET_ID=$(printf '%s_%s' "$PROFILE" "$REGION" | tr -c 'A-Za-z0-9._-' '_')
OUTPUT_JSON="$OUTPUT_DIR/aws_load_balancer_high_availability_${_TARGET_ID}.json"
_FETCHER_TMP_JSON="$(mktemp -t aws_load_balancer_high_availability.XXXXXX.json)"
_FAILURE_LOG="$(mktemp -t aws_load_balancer_high_availability_fail.XXXXXX)"
trap 'rm -f "$_FETCHER_TMP_JSON" "$_FAILURE_LOG"' EXIT

log_info() { printf '%s INFO aws_load_balancer_high_availability %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_error() { printf '%s ERROR aws_load_balancer_high_availability %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }

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

load_balancers=$(aws elbv2 describe-load-balancers --profile "$PROFILE" --region "$REGION" --query 'LoadBalancers[*]' --output json 2>/dev/null)
lb_exit=$?
if [ $lb_exit -ne 0 ]; then
    echo "aws elbv2 describe-load-balancers failed (exit=$lb_exit)" >> "$_FAILURE_LOG"
    log_error "Failed to describe load balancers"
else
    echo "$load_balancers" | jq -c '.[]' | while read -r lb; do
        lb_arn=$(echo "$lb" | jq -r '.LoadBalancerArn')
        lb_azs=$(echo "$lb" | jq -r '.AvailabilityZones[]' 2>/dev/null | tr '\n' ' ')

        target_groups=$(aws elbv2 describe-target-groups --profile "$PROFILE" --region "$REGION" --load-balancer-arn "$lb_arn" --query 'TargetGroups[*]' --output json 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "aws elbv2 describe-target-groups ($lb_arn) failed" >> "$_FAILURE_LOG"
            target_groups='[]'
        fi

        lb_attributes=$(aws elbv2 describe-load-balancer-attributes --profile "$PROFILE" --region "$REGION" --load-balancer-arn "$lb_arn" --query 'Attributes[*]' --output json 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "aws elbv2 describe-load-balancer-attributes ($lb_arn) failed" >> "$_FAILURE_LOG"
            lb_attributes='[]'
        fi

        jq --argjson lb "$lb" --arg azs "$lb_azs" --argjson targets "$target_groups" --argjson attrs "$lb_attributes" \
           '.results += [{"Type": "LoadBalancer", "LoadBalancerInfo": $lb, "AvailabilityZones": $azs, "TargetGroups": $targets, "Attributes": $attrs}]' \
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
