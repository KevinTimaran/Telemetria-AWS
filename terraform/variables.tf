variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo para nombrar los recursos (minúsculas, sin espacios)"
  type        = string
  default     = "telemed"
}

variable "extra_kms_admin_arns" {
  description = "ARNs IAM adicionales que pueden ADMINISTRAR (no usar) la clave KMS"
  type        = list(string)
  default     = []
}

variable "allowed_countries" {
  description = "Países (ISO 3166-1 alpha-2) desde los que CloudFront sirve el frontend"
  type        = list(string)
  default     = ["CO"]
}

variable "db_instance_class" {
  description = "Clase de instancia RDS MySQL"
  type        = string
  default     = "db.t3.micro"
}

variable "license_regex" {
  description = "Expresión regular que debe cumplir custom:license de los médicos"
  type        = string
  default     = "^RM-[0-9]{4,10}$"
}

variable "force_destroy_buckets" {
  description = "Permite que terraform destroy borre buckets con objetos (útil en laboratorio)"
  type        = bool
  default     = true
}
