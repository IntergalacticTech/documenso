variable "name" {
  description = "Prefix for AWS resource names and the SSM parameter path."
  type        = string
  default     = "signature"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "domain" {
  description = "Public hostname the app is served on."
  type        = string
  default     = "signature.victorycto.com"
}

variable "allowed_signup_domains" {
  description = "Comma-separated email domains allowed to create accounts (via Google SSO)."
  type        = string
  default     = "victorycto.com"
}

variable "image" {
  description = "Container image to run. Start with the upstream release; switch to the fork's GHCR image once branding lands. Changeable later in SSM without Terraform."
  type        = string
  default     = "documenso/documenso:v2.21.1"
}

variable "instance_type" {
  description = "Graviton (arm64) instance; the upstream image and our build workflow are multi-arch / arm64."
  type        = string
  default     = "t4g.medium"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 20
}

variable "google_client_id" {
  description = "OAuth client ID from Google Cloud Console (Web application, consent screen type Internal)."
  type        = string
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}

variable "email_from_domain" {
  description = "Domain verified in SES and used for the From address."
  type        = string
  default     = "victorycto.com"
}

variable "email_from_address" {
  type    = string
  default = "signature@victorycto.com"
}

variable "email_from_name" {
  type    = string
  default = "Victory CTO Signature"
}
