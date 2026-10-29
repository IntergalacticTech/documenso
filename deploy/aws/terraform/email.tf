# Outbound mail via Amazon SES SMTP. Terraform verifies the sending domain
# (DKIM records are printed as outputs for you to add to DNS) and creates an
# IAM user whose derived SMTP password goes into the app config.
#
# New SES accounts start in the sandbox (can only send to verified addresses).
# Request production access in the SES console before inviting real signers.

resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.email_from_domain
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
