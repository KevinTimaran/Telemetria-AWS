#!/usr/bin/env bash
# Crea un médico y dos pacientes de prueba con sus atributos personalizados.
set -euo pipefail
source "$(dirname "$0")/env.sh"

crear() { # crear <pool> <email> <atributos...>
  local pool="$1" email="$2"; shift 2
  aws cognito-idp admin-create-user --region "$AWS_REGION" --user-pool-id "$pool" \
    --username "$email" --message-action SUPPRESS \
    --user-attributes Name=email,Value="$email" Name=email_verified,Value=true "$@" >/dev/null \
    || echo "  (ya existía $email)"
  aws cognito-idp admin-set-user-password --region "$AWS_REGION" --user-pool-id "$pool" \
    --username "$email" --password "$DEMO_PASS" --permanent
  echo "  ✓ $email"
}

echo ">> Pool de MÉDICOS"
crear "$MED_POOL" "$MED_EMAIL" \
  Name=name,Value="Dra. Laura López" \
  Name=custom:role,Value=medico \
  Name=custom:license,Value=RM-204581 \
  Name=custom:specialty,Value="Radiología"

echo ">> Pool de PACIENTES"
crear "$PAC_POOL" "$PAC_EMAIL" \
  Name=name,Value="Juan Pérez" \
  Name=custom:role,Value=paciente \
  Name=custom:document_id,Value=1012345678 \
  Name=custom:eps,Value="EPS Demo"

crear "$PAC_POOL" "$PAC2_EMAIL" \
  Name=name,Value="Ana Gómez" \
  Name=custom:role,Value=paciente \
  Name=custom:document_id,Value=1098765432 \
  Name=custom:eps,Value="EPS Demo"

echo "Contraseña de todos: $DEMO_PASS"
