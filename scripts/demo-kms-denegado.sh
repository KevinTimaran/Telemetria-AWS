#!/usr/bin/env bash
# Demuestra que un usuario/rol de CONSOLA (aunque sea AdministratorAccess) NO puede
# leer ni escribir documentos: S3 lo deja pasar, pero KMS lo deniega.
# Ejecutar con las MISMAS credenciales que usas en la consola.
set -uo pipefail
source "$(dirname "$0")/env.sh"

echo "Identidad actual:"; aws sts get-caller-identity --query Arn --output text
KEY="$(aws s3api list-objects-v2 --bucket "$DOCS_BUCKET" --prefix patients/ \
        --query 'Contents[0].Key' --output text)"
[ "$KEY" = "None" ] && { echo "No hay documentos. Ejecuta antes ./scripts/probar-api.sh"; exit 1; }
echo "Objeto de prueba: s3://$DOCS_BUCKET/$KEY"

echo; echo "== 1. Metadatos del objeto (S3 sí deja ver que existe y cómo está cifrado) =="
aws s3api head-object --bucket "$DOCS_BUCKET" --key "$KEY" \
  --query '{SSE:ServerSideEncryption,Clave:SSEKMSKeyId}'

echo; echo "== 2. Descargar el objeto (esperado: AccessDenied por KMS) =="
aws s3 cp "s3://$DOCS_BUCKET/$KEY" /tmp/robado.bin 2>&1 | tail -2

echo; echo "== 3. Subir un objeto (esperado: AccessDenied por KMS GenerateDataKey) =="
echo intento > /tmp/intento.txt
aws s3 cp /tmp/intento.txt "s3://$DOCS_BUCKET/patients/intento.txt" 2>&1 | tail -2

echo; echo "== 4. Usar la clave directamente (esperado: AccessDenied, Deny explícito) =="
aws kms generate-data-key --key-id "$KMS_KEY_ARN" --key-spec AES_256 2>&1 | tail -2

echo; echo "== 5. Administrar la clave (esperado: PERMITIDO, administrar != usar) =="
aws kms describe-key --key-id "$KMS_KEY_ARN" --query 'KeyMetadata.{Estado:KeyState,Rotacion:KeyManager}'
aws kms get-key-rotation-status --key-id "$KMS_KEY_ARN"

echo; echo "== 6. Política de la clave =="
aws kms get-key-policy --key-id "$KMS_KEY_ARN" --policy-name default --output text \
  | jq '.Statement[] | {Sid, Effect, Principal, Action}'

echo
echo "Conclusión: solo el rol $(terraform -chdir="$(dirname "$0")/../terraform" output -raw docs_lambda_role_arn)"
echo "puede cifrar/descifrar; el acceso legítimo se hace con presigned URLs firmadas por ese rol."
