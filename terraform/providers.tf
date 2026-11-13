terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Si Terraform corre con un rol asumido (SSO, etc.), esto devuelve el ARN del ROL,
# que es lo que se debe poner en la política de la clave KMS.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  name       = var.project
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # Administradores de la clave KMS: quien despliega + los extra que se indiquen.
  # OJO: administran la clave pero NO pueden cifrar/descifrar con ella.
  kms_admin_arns = distinct(concat(
    [data.aws_iam_session_context.current.issuer_arn],
    var.extra_kms_admin_arns
  ))
}
