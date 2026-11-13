#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8080}"
URL="http://127.0.0.1:${PORT}"

if curl -fsS "$URL/" 2>/dev/null | grep -q '<title>TeleMed'; then
  echo "TeleMed ya esta funcionando en $URL"
  exit 0
fi

echo "Iniciando TeleMed en $URL"
echo "Deten el servidor con Ctrl+C"
exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT_DIR/frontend"
