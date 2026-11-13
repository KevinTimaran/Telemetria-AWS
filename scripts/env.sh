#!/usr/bin/env bash
# Carga los outputs de Terraform como variables de entorno. Uso: source scripts/env.sh
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

export AWS_REGION="$(out region)"
export CF_URL="$(out cloudfront_url)"
export API_DIRECT="$(out api_direct_url)"
export MED_POOL="$(out medicos_user_pool_id)"
export MED_CLIENT="$(out medicos_client_id)"
export PAC_POOL="$(out pacientes_user_pool_id)"
export PAC_CLIENT="$(out pacientes_client_id)"
export DOCS_BUCKET="$(out docs_bucket)"
export KMS_KEY_ARN="$(out kms_key_arn)"

# Usuarios de demo (cámbialos si quieres)
export MED_EMAIL="${MED_EMAIL:-dra.lopez@example.com}"
export PAC_EMAIL="${PAC_EMAIL:-juan.perez@example.com}"
export PAC2_EMAIL="${PAC2_EMAIL:-ana.gomez@example.com}"
export DEMO_PASS="${DEMO_PASS:-Telemed#2026demo}"

# Base de la API: por CloudFront (requiere estar en un país permitido) o directa.
export API="${API:-$CF_URL}"

login() { # login <client_id> <email>
  aws cognito-idp initiate-auth --region "$AWS_REGION" --client-id "$1" \
    --auth-flow USER_PASSWORD_AUTH --auth-parameters "USERNAME=$2,PASSWORD=$DEMO_PASS" \
    --query 'AuthenticationResult.IdToken' --output text
}

claims() { # claims <jwt>  -> imprime el payload
  local p; p="$(echo "$1" | cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done
  echo "$p" | base64 -d 2>/dev/null | jq .
}

echo "Variables cargadas. API=$API"
