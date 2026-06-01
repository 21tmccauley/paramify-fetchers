#!/bin/bash
#
# AWS — Network Resilience High Availability
#
# Lists VPC subnets and NAT gateways. Per-AZ distribution evidence.
#
# Output: $EVIDENCE_DIR/aws_network_resilience_high_availability.json
# Required env: AWS_PROFILE, AWS_DEFAULT_REGION
# Required tools: aws, jq

set -o pipefail

[ -f .env ] && { set -a; . .env; set +a; }

OUTPUT_DIR="${EVIDENCE_DIR:-./evidence}"
mkdir -p "$OUTPUT_DIR"

if [ -z "${AWS_PROFILE:-}" ]; then
    echo "ERROR aws_network_resilience_high_availability: AWS_PROFILE is not set" >&2
    exit 1
fi
if [ -z "${AWS_DEFAULT_REGION:-}" ]; then
    echo "ERROR aws_network_resilience_high_availability: AWS_DEFAULT_REGION is not set" >&2
    exit 1
fi

PROFILE="$AWS_PROFILE"
REGION="$AWS_DEFAULT_REGION"

# Per-target output filename (profile+region) so multi-target runs don't overwrite.
_TARGET_ID=$(printf '%s_%s' "$PROFILE" "$REGION" | tr -c 'A-Za-z0-9._-' '_')
OUTPUT_JSON="$OUTPUT_DIR/aws_network_resilience_high_availability_${_TARGET_ID}.json"
_FETCHER_TMP_JSON="$(mktemp -t aws_network_resilience_high_availability.XXXXXX.json)"
_FAILURE_LOG="$(mktemp -t aws_network_resilience_high_availability_fail.XXXXXX)"
trap 'rm -f "$_FETCHER_TMP_JSON" "$_FAILURE_LOG"' EXIT

log_info() { printf '%s INFO aws_network_resilience_high_availability %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_error() { printf '%s ERROR aws_network_resilience_high_availability %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }

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

subnets=$(aws ec2 describe-subnets --profile "$PROFILE" --region "$REGION" --query 'Subnets[*]' --output json 2>/dev/null)
subnets_exit=$?
if [ $subnets_exit -ne 0 ]; then
    echo "aws ec2 describe-subnets failed (exit=$subnets_exit)" >> "$_FAILURE_LOG"
    log_error "Failed to describe subnets"
else
    echo "$subnets" | jq -c '.[]' | while read -r subnet; do
        jq --argjson subnet "$subnet" \
           '.results += [{"Type": "VPC_Subnet", "SubnetInfo": $subnet}]' \
           "$OUTPUT_JSON" > "$_FETCHER_TMP_JSON" && mv "$_FETCHER_TMP_JSON" "$OUTPUT_JSON"
    done
fi

nat_gateways=$(aws ec2 describe-nat-gateways --profile "$PROFILE" --region "$REGION" --query 'NatGateways[*]' --output json 2>/dev/null)
nat_exit=$?
if [ $nat_exit -ne 0 ]; then
    echo "aws ec2 describe-nat-gateways failed (exit=$nat_exit)" >> "$_FAILURE_LOG"
    log_error "Failed to describe NAT gateways"
else
    echo "$nat_gateways" | jq -c '.[]' | while read -r nat; do
        jq --argjson nat "$nat" \
           '.results += [{"Type": "NAT_Gateway", "NATInfo": $nat}]' \
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
