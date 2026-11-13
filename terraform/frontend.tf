locals {
  frontend_dir = "${path.module}/../frontend"
  frontend_files = {
    "index.html" = "text/html; charset=utf-8"
    "app.js"     = "application/javascript"
    "styles.css" = "text/css"
  }
}

resource "aws_s3_object" "frontend" {
  for_each     = local.frontend_files
  bucket       = aws_s3_bucket.frontend.id
  key          = each.key
  source       = "${local.frontend_dir}/${each.key}"
  etag         = filemd5("${local.frontend_dir}/${each.key}")
  content_type = each.value
}

# Configuración generada con los IDs reales de Cognito.
resource "aws_s3_object" "frontend_config" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "config.js"
  content_type = "application/javascript"
  content      = <<-EOT
    window.TELEMED_CONFIG = ${jsonencode({
  region = local.region
  pools = {
    medico    = { userPoolId = aws_cognito_user_pool.medicos.id, clientId = aws_cognito_user_pool_client.medicos.id }
    paciente  = { userPoolId = aws_cognito_user_pool.pacientes.id, clientId = aws_cognito_user_pool_client.pacientes.id }
  }
})};
  EOT
}
