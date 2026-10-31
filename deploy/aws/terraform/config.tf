# All runtime config lives in SSM Parameter Store under /<name>/. The host's
# deploy.sh reads it on every deploy. Terraform seeds the values once and then
# ignores edits, so you can change config in the console/CLI without drift.

resource "random_password" "nextauth_secret" {
  length  = 64
  special = false
}

resource "random_password" "encryption_key" {
  length  = 64
  special = false
}

resource "random_password" "encryption_secondary_key" {
  length  = 64
  special = false
}

locals {
  ssm_prefix = "/${var.name}"

  database_url = format(
    "postgresql://%s:%s@%s/%s?sslmode=require",
    aws_db_instance.this.username,
    random_password.db.result,
    aws_db_instance.this.endpoint,
    aws_db_instance.this.db_name,
  )

  app_env = templatefile("${path.module}/env.tftpl", {
    domain                   = var.domain
    nextauth_secret          = random_password.nextauth_secret.result
    encryption_key           = random_password.encryption_key.result
    encryption_secondary_key = random_password.encryption_secondary_key.result
    database_url             = local.database_url
    region                   = var.aws_region
    bucket                   = aws_s3_bucket.documents.bucket
    smtp_host                = "email-smtp.${var.aws_region}.amazonaws.com"
    smtp_username            = aws_iam_access_key.smtp.id
    smtp_password            = aws_iam_access_key.smtp.ses_smtp_password_v4
    email_from_address       = var.email_from_address
    email_from_name          = var.email_from_name
    google_client_id         = var.google_client_id
    google_client_secret     = var.google_client_secret
    allowed_signup_domains   = var.allowed_signup_domains
    single_organisation_url  = var.single_organisation_url
    single_organisation_name = var.single_organisation_name
  })
}

resource "aws_ssm_parameter" "env" {
  name  = "${local.ssm_prefix}/env"
  type  = "SecureString"
  tier  = "Advanced"
  value = local.app_env

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "image" {
  name  = "${local.ssm_prefix}/image"
  type  = "String"
  value = var.image

  lifecycle {
    ignore_changes = [value]
  }
}

# Base64 of the PKCS#12 signing certificate. Upload it with
# scripts/upload-signing-cert.sh; Terraform only creates the placeholder.
resource "aws_ssm_parameter" "signing_cert" {
  name  = "${local.ssm_prefix}/signing-cert-p12"
  type  = "SecureString"
  tier  = "Advanced"
  value = "UNSET"

  lifecycle {
    ignore_changes = [value]
  }
}
