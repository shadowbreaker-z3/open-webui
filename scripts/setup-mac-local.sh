#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/.env.mac-local"
COMPOSE_FILE="docker-compose.mac-local.yaml"
WEBUI_URL="${WEBUI_URL:-http://localhost:3000}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

ADMIN_EMAIL="${ADMIN_EMAIL:-admin@local.openwebui}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
ADMIN_NAME="${ADMIN_NAME:-Admin}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)"
  {
    echo "ADMIN_EMAIL=$ADMIN_EMAIL"
    echo "ADMIN_PASSWORD=$ADMIN_PASSWORD"
    echo "ADMIN_NAME=$ADMIN_NAME"
  } >"$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

echo "Starting Open WebUI (Mac local)..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Waiting for Open WebUI..."
for _ in $(seq 1 60); do
  if curl -fsS "$WEBUI_URL/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "$WEBUI_URL/health" >/dev/null 2>&1; then
  echo "Open WebUI did not become ready. Check: docker logs open-webui"
  exit 1
fi

echo "Verifying llama.cpp from inside the container..."
docker exec open-webui curl -fsS http://host.docker.internal:8080/v1/models >/dev/null

get_token() {
  curl -fsS "$WEBUI_URL/api/v1/auths/signin" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
}

TOKEN=""
if TOKEN="$(get_token 2>/dev/null)"; then
  echo "Signed in as existing admin."
else
  echo "Creating admin account..."
  TOKEN="$(
    curl -fsS "$WEBUI_URL/api/v1/auths/signup" \
      -H 'Content-Type: application/json' \
      -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\",\"name\":\"$ADMIN_NAME\"}" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
  )"
fi

echo "Configuring llama.cpp connection..."
curl -fsS "$WEBUI_URL/openai/config/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "ENABLE_OPENAI_API": true,
    "OPENAI_API_BASE_URLS": ["http://host.docker.internal:8080/v1"],
    "OPENAI_API_KEYS": [""],
    "OPENAI_API_CONFIGS": {
      "0": {
        "enable": true,
        "provider": "llama.cpp",
        "auth_type": "bearer"
      }
    }
  }' >/dev/null

MODELS="$(curl -fsS "$WEBUI_URL/api/v1/models" -H "Authorization: Bearer $TOKEN" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for m in data.get("data", []):
    mid = m.get("id", m)
    print("  - " + str(mid))
')"

echo ""
echo "Done."
echo "  Web UI:  $WEBUI_URL"
echo "  Email:   $ADMIN_EMAIL"
echo "  Password stored in: $ENV_FILE"
echo ""
echo "Models:"
echo "$MODELS"
