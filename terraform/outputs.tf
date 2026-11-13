output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.main.id
}

output "api_direct_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "region" {
  value = local.region
}

output "medicos_user_pool_id" {
  value = aws_cognito_user_pool.medicos.id
}

output "medicos_client_id" {
  value = aws_cognito_user_pool_client.medicos.id
}

output "pacientes_user_pool_id" {
  value = aws_cognito_user_pool.pacientes.id
}

output "pacientes_client_id" {
  value = aws_cognito_user_pool_client.pacientes.id
}

output "docs_bucket" {
  value = aws_s3_bucket.docs.bucket
}

output "kms_key_arn" {
  value = aws_kms_key.docs.arn
}

output "docs_lambda_role_arn" {
  value = aws_iam_role.docs_lambda.arn
}

output "kms_admin_arns" {
  description = "Principales que administran (pero NO usan) la CMK"
  value       = local.kms_admin_arns
}
