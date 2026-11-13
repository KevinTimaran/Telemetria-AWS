# ---------------------------------------------------------------------------
# Rol IAM de las Lambdas de documentos (API + indexador).
# Es el ÚNICO principal autorizado a USAR la CMK (ver kms.tf).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "docs_lambda" {
  name               = "${local.name}-docs-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "docs_lambda_vpc" {
  role       = aws_iam_role.docs_lambda.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "docs_lambda" {
  statement {
    sid       = "DocumentosPacientes"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.docs.arn}/patients/*"]
  }

  statement {
    sid       = "UsoCMK"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.docs.arn]
  }

  statement {
    sid       = "CredencialesRDS"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.mysql.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "docs_lambda" {
  name   = "${local.name}-docs-lambda-policy"
  role   = aws_iam_role.docs_lambda.id
  policy = data.aws_iam_policy_document.docs_lambda.json
}

# ---------------------------------------------------------------------------
# Rol del Lambda Authorizer: solo logs. NO tiene acceso a S3 ni a KMS.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "authorizer" {
  name               = "${local.name}-authorizer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "authorizer_logs" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
