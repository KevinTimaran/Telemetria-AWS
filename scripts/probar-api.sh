#!/usr/bin/env bash
# Prueba de punta a punta: claims, permisos por rol, ownership (sub == patientId),
# TTL dinámico de presigned URLs y consentimiento médico.
# Si no estás en un país permitido por CloudFront:  API=$API_DIRECT ./scripts/probar-api.sh
set -uo pipefail
source "$(dirname "$0")/env.sh"

TMP="$(mktemp -d)"
check() { # check <descripcion> <esperado> <obtenido>
  if [ "$2" = "$3" ]; then echo "  ✅ $1 (HTTP $3)"; else echo "  ❌ $1: esperado $2, obtenido $3"; fi
}
call() { # call <token> <método> <ruta> [json]  -> imprime código; cuerpo en $TMP/body
  curl -s -o "$TMP/body" -w '%{http_code}' -X "$2" "$API$3" \
    -H "Authorization: Bearer $1" ${4:+-H "Content-Type: application/json" -d "$4"}
}

echo "== 1. Login y claims personalizados =="
TK_PAC="$(login "$PAC_CLIENT" "$PAC_EMAIL")"
TK_PAC2="$(login "$PAC_CLIENT" "$PAC2_EMAIL")"
TK_MED="$(login "$MED_CLIENT" "$MED_EMAIL")"
echo "-- Paciente:"; claims "$TK_PAC" | jq '{sub, "custom:role", "custom:document_id", iss}'
echo "-- Médico:";   claims "$TK_MED" | jq '{sub, "custom:role", "custom:license", iss}'
PAC_SUB="$(claims "$TK_PAC" | jq -r .sub)"
MED_SUB="$(claims "$TK_MED" | jq -r .sub)"

echo "== 2. Lambda Authorizer: permisos por rol =="
check "Sin token -> 401"                       401 "$(curl -s -o /dev/null -w '%{http_code}' "$API/api/documents")"
check "Token basura -> 401"                    401 "$(call "abc.def.ghi" GET /api/documents)"
check "Paciente llama endpoint de médico -> 403" 403 "$(call "$TK_PAC" GET "/api/medico/patients/$PAC_SUB/documents")"
check "Médico pide URL de subida -> 403"       403 "$(call "$TK_MED" POST /api/documents/upload-url '{}')"

echo "== 3. Subida cifrada con presigned PUT =="
printf '%%PDF-1.4\n%% informe demo\n' > "$TMP/informe.pdf"
printf '\x89PNG\r\n\x1a\n' > "$TMP/rx.png"
up() { # up <docType> <archivo> <contentType>
  call "$TK_PAC" POST /api/documents/upload-url \
    "{\"fileName\":\"$(basename "$2")\",\"docType\":\"$1\",\"contentType\":\"$3\"}" >/dev/null
  local url id; url="$(jq -r .uploadUrl "$TMP/body")"; id="$(jq -r .documentId "$TMP/body")"
  curl -s -o /dev/null -w "  PUT S3 $1 -> %{http_code}\n" -X PUT -H "Content-Type: $3" --data-binary "@$2" "$url"
  echo "$id"
}
INF_ID="$(up informe "$TMP/informe.pdf" application/pdf | tee /dev/stderr | tail -1)"
IMG_ID="$(up imagen_diagnostica "$TMP/rx.png" image/png | tee /dev/stderr | tail -1)"
echo "  esperando al indexador..."; sleep 6
call "$TK_PAC" GET /api/documents >/dev/null; jq '.documents[] | {documentId, docType, fileName}' "$TMP/body"

echo "== 4. TTL dinámico de las presigned URLs =="
call "$TK_PAC" GET "/api/documents/$IMG_ID/download-url" >/dev/null
echo "  imagen_diagnostica expiresIn=$(jq .expiresIn "$TMP/body")s  (X-Amz-Expires=$(jq -r .url "$TMP/body" | grep -o 'X-Amz-Expires=[0-9]*'))"
IMG_URL="$(jq -r .url "$TMP/body")"
call "$TK_PAC" GET "/api/documents/$INF_ID/download-url" >/dev/null
echo "  informe            expiresIn=$(jq .expiresIn "$TMP/body")s  (X-Amz-Expires=$(jq -r .url "$TMP/body" | grep -o 'X-Amz-Expires=[0-9]*'))"
check "Descarga con presigned URL" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$IMG_URL")"

echo "== 5. Validación sub == patientId =="
check "Otro paciente pide el documento -> 403" 403 "$(call "$TK_PAC2" GET "/api/documents/$INF_ID/download-url")"
cat "$TMP/body"; echo

echo "== 6. Médico y consentimiento =="
check "Médico sin consentimiento -> 403" 403 "$(call "$TK_MED" GET "/api/documents/$INF_ID/download-url")"
check "Paciente autoriza al médico"     201 "$(call "$TK_PAC" POST /api/consents "{\"doctorId\":\"$MED_SUB\"}")"
check "Médico lista expediente"         200 "$(call "$TK_MED" GET "/api/medico/patients/$PAC_SUB/documents")"
check "Médico con consentimiento -> 200" 200 "$(call "$TK_MED" GET "/api/documents/$INF_ID/download-url")"

echo
echo "Para probar la expiración: espera 5+ min y ejecuta"
echo "  curl -s \"$IMG_URL\" | grep -o '<Code>.*</Code>'   # => AccessDenied / Request has expired"
rm -rf "$TMP"
