# signature.victorycto.com on AWS

Self-hosted [Documenso](https://github.com/documenso/documenso) for Victory CTO:
Google Workspace sign-in limited to `@victorycto.com`, sequential signing, our
branding. This fork is public and AGPL-3.0 like upstream. Nothing from
`packages/ee` (commercially licensed) is enabled or modified.

## Architecture

```
              ┌──────────────── AWS (us-east-1) ────────────────┐
 Browser ───► │ EC2 t4g.medium (Elastic IP)                     │
  HTTPS       │   Caddy :443 (Let's Encrypt) ─► Documenso :3000 │──► RDS Postgres 16 (private, encrypted, 14-day backups)
              │   config + cert pulled from SSM Parameter Store │──► S3 bucket (documents, versioned, private)
              │   logs ─► CloudWatch /signature/app             │──► SES SMTP (outbound email)
              └─────────────────────────────────────────────────┘
 Staff log in with Google (OAuth "Internal" app, domain allow-list).
 External signers use emailed one-time links; they never need an account.
```

- No SSH. Shell access is through **SSM Session Manager**.
- No static AWS keys on the host. S3 access uses the instance role.
- All runtime config is in **SSM Parameter Store** under `/signature/`:
  - `/signature/env`: the app's environment (SecureString)
  - `/signature/image`: the container image to run
  - `/signature/signing-cert-p12`: base64 PKCS#12 used to seal PDFs
- Rough cost: about $45/month (EC2 ~$25, RDS ~$13, plus EIP, S3, SES, CloudWatch).

## First-time setup

You need the AWS CLI (logged in to the target account), Terraform ≥ 1.6, and
admin access to Google Workspace and to DNS for `victorycto.com`.

### 1. Google OAuth client

In Google Cloud Console, use a project owned by the victorycto.com Workspace:

1. **APIs & Services → OAuth consent screen**: set user type to **Internal**.
   Google then refuses anyone outside the Workspace. The app's
   `NEXT_PRIVATE_ALLOWED_SIGNUP_DOMAINS` check is a second layer.
   App name: "Victory CTO Signature". Scopes: `openid`, `email`, `profile`.
2. **Credentials → Create credentials → OAuth client ID → Web application**
   - Authorised JavaScript origin: `https://signature.victorycto.com`
   - Authorised redirect URI: `https://signature.victorycto.com/api/auth/callback/google`
3. Copy the client ID and secret.

### 2. Provision AWS

All inputs and secrets are listed in [`.env.example`](.env.example). You
supply only AWS credentials and the Google client ID/secret. Terraform
generates the rest (DB password, app keys, SES SMTP credentials) into SSM.

```bash
cd deploy/aws
cp .env.example .env        # fill in Part 1
set -a; source .env; set +a
cd terraform
terraform init -backend-config=backend.hcl   # state bucket must already exist
terraform apply
terraform output dns_records
```

The instance boots, installs Docker, pulls config from SSM and starts the app.
HTTPS won't work until DNS is in place (step 3); Caddy keeps retrying.

### 3. DNS

Skip this step when `route53_zone_name` is set (as it is in
`victorycto.auto.tfvars`): Terraform creates the records itself.


Add the records from `terraform output dns_records` at the DNS provider for
`victorycto.com`:

- `A signature.victorycto.com → <Elastic IP>`
- three `CNAME <token>._domainkey.victorycto.com → <token>.dkim.amazonses.com`
  (SES DKIM; these leave your existing Google Workspace mail untouched)

DMARC passes through the aligned DKIM signature, so SPF doesn't need changing.

### 4. Leave the SES sandbox

SES console → **Account dashboard → Request production access**: transactional,
low volume, sending to contract signers. Until approved, mail only reaches
addresses verified in SES. That's fine for internal testing.

### 5. Signing certificate

```bash
cd deploy/aws/scripts
./create-signing-cert.sh            # self-signed, 10 years
./redeploy.sh
```

A self-signed cert makes completed PDFs tamper-evident, but Adobe Reader shows
"validity unknown". For a trusted green tick, buy a document-signing cert from
an AATL-listed CA and run `./create-signing-cert.sh --p12 your-cert.p12`.

### 6. Smoke test

1. Open `https://signature.victorycto.com` and **Sign in with Google** with a
   victorycto.com account. Your account is created automatically.
2. Try a non-victorycto.com Google account. It should be refused.
3. Run the sequential signing check below.

## Sequential signing check

1. Upload a PDF and add three signers.
2. Turn on **sequential signing** and set the order to 1, 2, 3. Place a signature field for each.
3. Send. Expected:
   - only signer 1 gets an email.
   - opening signer 2's link (copy it from the document's recipient menu)
     shows a waiting state, not the document.
   - after signer 1 signs, only signer 2 is emailed, and so on.
   - after signer 3 signs, everyone gets the completed, sealed PDF.
4. Repeat with signer 2 **rejecting**. Signer 3 must never be contacted.

## Operating

| Task | How |
|---|---|
| Change config | Edit `/signature/env` in SSM, then `scripts/redeploy.sh` |
| Deploy a new image | `scripts/redeploy.sh ghcr.io/intergalactictech/documenso:sha-<commit>` |
| Upgrade to a new upstream release | Merge upstream into `main` (CI builds the image), or for unmodified upstream: `scripts/redeploy.sh documenso/documenso:vX.Y.Z` |
| Shell on host | `aws ssm start-session --target $(terraform output -raw instance_id)` |
| Logs | CloudWatch → `/signature/app` (streams `app`, `caddy`) |
| Backups | RDS automated snapshots (14 days) + S3 versioning. Take a manual snapshot before upgrades. |

Database migrations run automatically on container start.

## Building our own image

`.github/workflows/signature-image.yml` builds `ghcr.io/intergalactictech/documenso`
(arm64) on every push to `main`. After the first build, set the GHCR package
visibility to **public** (package settings) so the host can pull it without
credentials. Then switch the host to it with `scripts/redeploy.sh`.

Upstream's own workflows (`publish.yml`, `deploy.yml`, ...) target Documenso's
infrastructure. Disable them in the fork under **Actions** so they don't run.
