# Antes de terraform apply ejecutar: ./scripts/build.sh  (instala node_modules)

data "archive_file" "backend" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/backend"
  output_path = "${path.module}/build/backend.zip"
}

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/authorizer"
  output_path = "${path.module}/build/authorizer.zip"
}

locals {
  backend_env = {
    DOCS_BUCKET   = aws_s3_bucket.docs.bucket
    KMS_KEY_ARN   = aws_kms_key.docs.arn
    DB_HOST       = aws_db_instance.mysql.address
    DB_PORT       = tostring(aws_db_instance.mysql.port)
    DB_NAME       = aws_db_instance.mysql.db_name
    DB_SECRET_ARN = aws_db_instance.mysql.master_user_secret[0].secret_arn
  }
}

# ------------------------- Lambda API de documentos -------------------------

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.name}-api"
  retention_in_days = 14
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.name}-api"
  role             = aws_iam_role.docs_lambda.arn
  runtime          = "nodejs20.x"
  handler          = "api.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 15
  memory_size      = 256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = local.backend_env
  }

  depends_on = [aws_cloudwatch_log_group.api, aws_iam_role_policy_attachment.docs_lambda_vpc]
}

# -------------------- Lambda indexador (evento S3 -> RDS) -------------------

resource "aws_cloudwatch_log_group" "indexer" {
  name              = "/aws/lambda/${local.name}-indexer"
  retention_in_days = 14
}

resource "aws_lambda_function" "indexer" {
  function_name    = "${local.name}-indexer"
  role             = aws_iam_role.docs_lambda.arn
  runtime          = "nodejs20.x"
  handler          = "indexer.handler"
  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = local.backend_env
  }

  depends_on = [aws_cloudwatch_log_group.indexer, aws_iam_role_policy_attachment.docs_lambda_vpc]
}

resource "aws_lambda_permission" "s3_invoke_indexer" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.indexer.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.docs.arn
  source_account = local.account_id
}

# --------------------------- Lambda Authorizer ------------------------------
# Fuera de la VPC: necesita descargar las JWKS públicas de Cognito.

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = "/aws/lambda/${local.name}-authorizer"
  retention_in_days = 14
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "${local.name}-authorizer"
  role             = aws_iam_role.authorizer.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      MEDICOS_POOL_ID     = aws_cognito_user_pool.medicos.id
      MEDICOS_CLIENT_ID   = aws_cognito_user_pool_client.medicos.id
      PACIENTES_POOL_ID   = aws_cognito_user_pool.pacientes.id
      PACIENTES_CLIENT_ID = aws_cognito_user_pool_client.pacientes.id
      LICENSE_REGEX       = var.license_regex
    }
  }

  depends_on = [aws_cloudwatch_log_group.authorizer]
}
