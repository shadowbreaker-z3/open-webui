#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/.env.mac-local"
PROJECT_ENV="$ROOT/.env"
COMPOSE_FILE="docker-compose.mac-local.yaml"

read_env_var() {
  local key="$1"
  local file="$2"
  local line value
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  value="${line#*=}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

if [[ -f "$PROJECT_ENV" ]]; then
  OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-$(read_env_var OPEN_WEBUI_PORT "$PROJECT_ENV")}"
  OPENAI_API_BASE_URLS="${OPENAI_API_BASE_URLS:-$(read_env_var OPENAI_API_BASE_URLS "$PROJECT_ENV")}"
  OPENAI_API_KEYS="${OPENAI_API_KEYS:-$(read_env_var OPENAI_API_KEYS "$PROJECT_ENV")}"
  DEFAULT_MODELS="${DEFAULT_MODELS:-$(read_env_var DEFAULT_MODELS "$PROJECT_ENV")}"
fi

WEBUI_URL="${WEBUI_URL:-http://localhost:${OPEN_WEBUI_PORT:-3000}}"
THAILLM_URL="${OPENAI_API_BASE_URLS:-http://thaillm.or.th/api/v1}"
THAILLM_KEY="${OPENAI_API_KEYS:-}"
DEFAULT_MODEL="${DEFAULT_MODELS:-typhoon-s-thaillm-8b-instruct}"

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

if [[ -z "$THAILLM_KEY" ]]; then
  echo "Missing OPENAI_API_KEYS in .env"
  exit 1
fi

echo "Starting Open WebUI (Mac local + ThaiLLM)..."
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

echo "Verifying ThaiLLM API..."
curl -fsS "$THAILLM_URL/models" \
  -H "Authorization: Bearer $THAILLM_KEY" >/dev/null

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

echo "Configuring ThaiLLM connection..."
curl -fsS "$WEBUI_URL/openai/config/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{
    \"ENABLE_OPENAI_API\": true,
    \"OPENAI_API_BASE_URLS\": [\"$THAILLM_URL\"],
    \"OPENAI_API_KEYS\": [\"$THAILLM_KEY\"],
    \"OPENAI_API_CONFIGS\": {
      \"0\": {
        \"enable\": true,
        \"auth_type\": \"bearer\",
        \"model_ids\": [\"$DEFAULT_MODEL\"]
      }
    }
  }" >/dev/null

echo "Disabling Ollama..."
curl -fsS "$WEBUI_URL/ollama/config/update" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "ENABLE_OLLAMA_API": false,
    "OLLAMA_BASE_URLS": [],
    "OLLAMA_API_CONFIGS": {}
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
echo "  API:     $THAILLM_URL"
echo "  Model:   $DEFAULT_MODEL"
echo "  Email:   $ADMIN_EMAIL"
echo "  Password stored in: $ENV_FILE"
echo ""
echo "Models:"
echo "$MODELS"
