# ---------------------------------------------------------------------------
# CMK para cifrar los documentos médicos (SSE-KMS).
#
# Diseño de la política de clave:
#  * NO incluye el statement típico "Enable IAM User Permissions" (root de la
#    cuenta). Sin él, ninguna política IAM (ni AdministratorAccess) puede dar
#    permisos sobre la clave: solo cuenta lo que diga esta política.
#  * Los administradores (quien despliega con Terraform / rol de consola) pueden
#    GESTIONAR la clave (describir, rotar, cambiar política, programar borrado)
#    pero NO usarla para cifrar/descifrar.
#  * Solo el rol IAM de las Lambdas de documentos puede USAR la clave, y solo a
#    través de S3 (kms:ViaService).
#  * Un Deny explícito bloquea operaciones criptográficas a cualquier otro
#    principal, para que el error sea inequívoco en la demostración.
#
# ADVERTENCIA: si los ARNs de administración son incorrectos la clave queda
# inadministrable. Por eso se toma automáticamente el rol de quien despliega.
# ---------------------------------------------------------------------------

locals {
  kms_crypto_actions = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
  ]
}

data "aws_iam_policy_document" "kms_docs" {
  statement {
    sid    = "AdministracionSinUso"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.kms_admin_arns
    }
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:RotateKeyOnDemand",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "UsoSoloRolLambdaViaS3"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.docs_lambda.arn]
    }
    actions   = concat(local.kms_crypto_actions, ["kms:DescribeKey"])
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid    = "DenegarUsoACualquierOtroPrincipal"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = local.kms_crypto_actions
    resources = ["*"]
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.docs_lambda.arn]
    }
  }
}

resource "aws_kms_key" "docs" {
  description             = "${local.name} - CMK para documentos médicos en S3"
  key_usage               = "ENCRYPT_DECRYPT"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_docs.json
}

resource "aws_kms_alias" "docs" {
  name          = "alias/${local.name}-docs"
  target_key_id = aws_kms_key.docs.key_id
}
