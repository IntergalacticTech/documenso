#!/usr/bin/env bash
# Re-runs /opt/signature/deploy.sh on the host via SSM Run Command, picking up
# any changes to the SSM config, signing cert, or image.
#
# Usage:
#   ./redeploy.sh                                   # re-apply current config
#   ./redeploy.sh ghcr.io/intergalactictech/documenso:sha-abc123   # switch image first
#
# Env: AWS_REGION (default us-east-1), SSM_PREFIX (default /signature),
#      INSTANCE_NAME (default signature)
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
SSM_PREFIX="${SSM_PREFIX:-/signature}"
INSTANCE_NAME="${INSTANCE_NAME:-signature}"

if [ -n "${1:-}" ]; then
  aws ssm put-parameter --region "$AWS_REGION" --overwrite \
    --name "$SSM_PREFIX/image" --type String --value "$1" >/dev/null
  echo "Image set to $1"
fi

host_dir="$(cd "$(dirname "$0")/../host" && pwd)"
sync_commands=()
for f in compose.yml Caddyfile deploy.sh; do
  sync_commands+=("echo $(base64 -w0 < "$host_dir/$f") | base64 -d > /opt/signature/$f")
done
sync_commands+=("chmod 700 /opt/signature/deploy.sh" "/opt/signature/deploy.sh")

command_id="$(aws ssm send-command --region "$AWS_REGION" \
  --document-name AWS-RunShellScript \
  --targets "Key=tag:Name,Values=$INSTANCE_NAME" \
  --parameters "$(jq -cn '$ARGS.positional | {commands: .}' --args "${sync_commands[@]}")" \
  --query Command.CommandId --output text)"

echo "Sent command $command_id; waiting..."
instance_id="$(aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"

aws ssm wait command-executed --region "$AWS_REGION" \
  --command-id "$command_id" --instance-id "$instance_id" || true

aws ssm get-command-invocation --region "$AWS_REGION" \
  --command-id "$command_id" --instance-id "$instance_id" \
  --query '[Status, StandardOutputContent, StandardErrorContent]' --output text
