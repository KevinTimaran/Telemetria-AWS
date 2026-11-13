#!/usr/bin/env bash
# Instala dependencias de producción de las Lambdas (Terraform luego las empaqueta).
set -euo pipefail
cd "$(dirname "$0")/../lambdas"
for fn in authorizer backend; do
  echo ">> npm install en lambdas/$fn"
  (cd "$fn" && npm install --omit=dev --no-audit --no-fund)
done
echo "Listo. Ahora: cd terraform && terraform init && terraform apply"
