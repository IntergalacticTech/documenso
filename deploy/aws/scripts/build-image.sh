#!/usr/bin/env bash
# Builds the fork's image for a git branch or tag in CodeBuild (native arm64)
# and pushes it to ECR. Prints the resulting image; pass it to redeploy.sh.
#
# Usage:
#   ./build-image.sh                      # build main
#   ./build-image.sh my-feature-branch
#   ./redeploy.sh "$(./build-image.sh my-feature-branch | tail -1)"
#
# Env: AWS_REGION (default us-east-1), PROJECT (default signature-image)
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT:-signature-image}"
GIT_REF="${1:-main}"

build_id="$(aws codebuild start-build --region "$AWS_REGION" --project-name "$PROJECT" \
  --environment-variables-override "name=GIT_REF,value=$GIT_REF,type=PLAINTEXT" \
  --query build.id --output text)"

echo "Building $GIT_REF ($build_id); this takes ~15 minutes..." >&2

while true; do
  status="$(aws codebuild batch-get-builds --region "$AWS_REGION" --ids "$build_id" \
    --query 'builds[0].buildStatus' --output text)"
  [ "$status" != "IN_PROGRESS" ] && break
  sleep 30
done

log_stream="$(aws codebuild batch-get-builds --region "$AWS_REGION" --ids "$build_id" \
  --query 'builds[0].logs.streamName' --output text)"
log_group="$(aws codebuild batch-get-builds --region "$AWS_REGION" --ids "$build_id" \
  --query 'builds[0].logs.groupName' --output text)"

if [ "$status" != "SUCCEEDED" ]; then
  echo "Build $status. Last log lines:" >&2
  aws logs get-log-events --region "$AWS_REGION" --log-group-name "$log_group" \
    --log-stream-name "$log_stream" --limit 40 --query 'events[].message' --output text >&2
  exit 1
fi

aws logs filter-log-events --region "$AWS_REGION" --log-group-name "$log_group" \
  --log-stream-names "$log_stream" --filter-pattern '"IMAGE="' \
  --query 'events[-1].message' --output text | sed -n 's/^IMAGE=//p' | tr -d '[:space:]'
echo
