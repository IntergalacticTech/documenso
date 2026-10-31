# Outbound mail via Amazon SES SMTP. Terraform creates an IAM user whose
# derived SMTP password goes into the app config, and optionally verifies the
# sending domain (skip that when the domain is already an SES identity).
#
# New SES accounts start in the sandbox (can only send to verified addresses).
# Request production access in the SES console before inviting real signers.

resource "aws_sesv2_email_identity" "sender" {
  count          = var.create_ses_identity ? 1 : 0
  email_identity = var.email_from_domain
}

locals {
  dkim_tokens = var.create_ses_identity ? aws_sesv2_email_identity.sender[0].dkim_signing_attributes[0].tokens : []
}

resource "aws_iam_user" "smtp" {
  name = "${var.name}-ses-smtp"
}

resource "aws_iam_user_policy" "smtp" {
  name = "send-email"
  user = aws_iam_user.smtp.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendRawEmail", "ses:SendEmail"]
      Resource = "*"
      Condition = {
        StringEquals = { "ses:FromAddress" = var.email_from_address }
      }
    }]
  })
}

resource "aws_iam_access_key" "smtp" {
  user = aws_iam_user.smtp.name
}
