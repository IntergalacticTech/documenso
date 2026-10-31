#!/usr/bin/env bash
# Pulls config from SSM Parameter Store and (re)starts the stack.
# Safe to re-run; this is also how you roll out config changes or a new image:
#   aws ssm send-command --document-name AWS-RunShellScript \
#     --targets Key=tag:Name,Values=<name> --parameters commands='/opt/signature/deploy.sh'
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=/dev/null
source ./deploy.conf

ssm_get() {
  aws ssm get-parameter --region "$AWS_REGION" --with-decryption --name "$1" \
    --query Parameter.Value --output text
}

umask 077

ssm_get "$SSM_PREFIX/env" > .env.tmp
mv .env.tmp .env

if cert_b64="$(ssm_get "$SSM_PREFIX/signing-cert-p12" 2>/dev/null)" && [ "$cert_b64" != "UNSET" ]; then
  echo "$cert_b64" | base64 -d > cert.p12.tmp
  mv cert.p12.tmp cert.p12
else
  echo "WARNING: $SSM_PREFIX/signing-cert-p12 not set; documents cannot be sealed until it is." >&2
  touch cert.p12
fi
# The container runs as a non-root user and must be able to read the cert.
chmod 644 cert.p12

image="$(ssm_get "$SSM_PREFIX/image")"

export SIGNATURE_IMAGE="$image" SIGNATURE_DOMAIN LOG_GROUP AWS_REGION

if [[ "$image" == *.dkr.ecr.*.amazonaws.com/* ]]; then
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${image%%/*}"
fi

docker compose pull
docker compose up -d --remove-orphans
docker image prune -f >/dev/null

echo "Deployed $image to https://$SIGNATURE_DOMAIN"
