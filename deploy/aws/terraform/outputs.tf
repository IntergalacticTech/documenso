output "public_ip" {
  description = "Point an A record for var.domain at this."
  value       = aws_eip.app.public_ip
}

output "dns_records" {
  description = "Records to add at your DNS provider (already created when route53_zone_name is set)."
  value = concat(
    [{ type = "A", name = var.domain, value = aws_eip.app.public_ip }],
    [for t in local.dkim_tokens : {
      type  = "CNAME"
      name  = "${t}._domainkey.${var.email_from_domain}"
      value = "${t}.dkim.amazonses.com"
    }],
  )
}

output "instance_id" {
  value = aws_instance.app.id
}

output "ssm_prefix" {
  value = local.ssm_prefix
}

output "documents_bucket" {
  value = aws_s3_bucket.documents.bucket
}

output "google_oauth_redirect_uri" {
  value = "https://${var.domain}/api/auth/callback/google"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
