data "aws_route53_zone" "this" {
  count = var.route53_zone_name == "" ? 0 : 1
  name  = var.route53_zone_name
}

resource "aws_route53_record" "app" {
  count   = var.route53_zone_name == "" ? 0 : 1
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}

resource "aws_route53_record" "dkim" {
  # Easy DKIM always issues three tokens; a literal count keeps plan working
  # before the identity (and its tokens) exist.
  count   = var.route53_zone_name != "" && var.create_ses_identity ? 3 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "${local.dkim_tokens[count.index]}._domainkey.${var.email_from_domain}"
  type    = "CNAME"
  ttl     = 1800
  records = ["${local.dkim_tokens[count.index]}.dkim.amazonses.com"]
}
