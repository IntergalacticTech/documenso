#!/usr/bin/env bash
# Creates a self-signed PKCS#12 certificate used to seal completed PDFs and
# uploads it to SSM, then sets the passphrase in the app env.
#
# A self-signed cert makes signatures tamper-evident, but Adobe will show
# "validity unknown" until the cert is trusted. For a green tick, buy a
# document-signing cert from an AATL-listed CA and pass it with --p12.
#
# Usage:
#   ./create-signing-cert.sh                 # generate a new self-signed cert
#   ./create-signing-cert.sh --p12 cert.p12  # upload an existing cert (prompts for passphrase)
#
# Env: AWS_REGION (default us-east-1), SSM_PREFIX (default /signature),
#      CERT_SUBJECT (default "/CN=Victory CTO Signature/O=Victory CTO")
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
SSM_PREFIX="${SSM_PREFIX:-/signature}"
CERT_SUBJECT="${CERT_SUBJECT:-/CN=Victory CTO Signature/O=Victory CTO}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
umask 077

if [ "${1:-}" = "--p12" ]; then
  p12="$2"
  read -rsp "Passphrase for $p12: " passphrase
  echo
else
  p12="$workdir/cert.p12"
  passphrase="$(openssl rand -hex 24)"
  openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
    -subj "$CERT_SUBJECT" \
    -keyout "$workdir/key.pem" -out "$workdir/cert.pem"
  openssl pkcs12 -export -out "$p12" \
    -inkey "$workdir/key.pem" -in "$workdir/cert.pem" \
    -passout "pass:$passphrase"
  echo "Generated self-signed certificate: $CERT_SUBJECT"
fi

aws ssm put-parameter --region "$AWS_REGION" --overwrite \
  --name "$SSM_PREFIX/signing-cert-p12" --type SecureString --tier Advanced \
  --value "$(base64 < "$p12" | tr -d '\n')" >/dev/null

# Write the passphrase into the env parameter.
env_value="$(aws ssm get-parameter --region "$AWS_REGION" --with-decryption \
  --name "$SSM_PREFIX/env" --query Parameter.Value --output text)"
env_value="$(printf '%s\n' "$env_value" | sed "s|^NEXT_PRIVATE_SIGNING_PASSPHRASE=.*|NEXT_PRIVATE_SIGNING_PASSPHRASE=$passphrase|")"
aws ssm put-parameter --region "$AWS_REGION" --overwrite \
  --name "$SSM_PREFIX/env" --type SecureString --tier Advanced \
  --value "$env_value" >/dev/null

echo "Uploaded to $SSM_PREFIX/signing-cert-p12 and set passphrase in $SSM_PREFIX/env."
echo "Run scripts/redeploy.sh to apply."
