#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-/opt/data}"
export HOME="${HERMES_HOME}"
INSTALL_DIR="${HERMES_INSTALL_DIR:-/opt/hermes}"
WEBUI_PORT="${HERMES_WEBUI_PORT:-8648}"
GATEWAY_PORT="${HERMES_GATEWAY_PORT:-8642}"
GATEWAY_HOST="${HERMES_GATEWAY_HOST:-127.0.0.1}"
PUBLIC_PORT="${PORT:-8080}"
LOG_DIR="${HERMES_HOME}/logs"
GATEWAY_LOG="${LOG_DIR}/railway-gateway.log"
WEBUI_LOG="${LOG_DIR}/railway-webui.log"

if [[ -f "${INSTALL_DIR}/.venv/bin/activate" ]]; then
  source "${INSTALL_DIR}/.venv/bin/activate"
fi

if ! command -v hermes >/dev/null 2>&1; then
  if [[ -x "${INSTALL_DIR}/.venv/bin/hermes" ]]; then
    export PATH="${INSTALL_DIR}/.venv/bin:${PATH}"
  else
    echo "Refusing to start: hermes executable was not found in PATH or ${INSTALL_DIR}/.venv/bin."
    exit 69
  fi
fi

mkdir -p "${HERMES_HOME}"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}
mkdir -p "${LOG_DIR}"

if [[ ! -f "${HERMES_HOME}/.env" && -f "${INSTALL_DIR}/.env.example" ]]; then
  cp "${INSTALL_DIR}/.env.example" "${HERMES_HOME}/.env"
fi

if [[ ! -f "${HERMES_HOME}/config.yaml" && -f "${INSTALL_DIR}/cli-config.yaml.example" ]]; then
  cp "${INSTALL_DIR}/cli-config.yaml.example" "${HERMES_HOME}/config.yaml"
fi

if [[ ! -f "${HERMES_HOME}/SOUL.md" && -f "${INSTALL_DIR}/docker/SOUL.md" ]]; then
  cp "${INSTALL_DIR}/docker/SOUL.md" "${HERMES_HOME}/SOUL.md"
fi

if [[ ! -f "${HERMES_HOME}/auth.json" && -n "${HERMES_AUTH_JSON_BOOTSTRAP:-}" ]]; then
  printf '%s' "${HERMES_AUTH_JSON_BOOTSTRAP}" > "${HERMES_HOME}/auth.json"
  chmod 600 "${HERMES_HOME}/auth.json"
fi

if [[ ! -e "${HERMES_HOME}/.hermes" ]]; then
  ln -s "${HERMES_HOME}" "${HERMES_HOME}/.hermes"
fi

if [[ -n "${RAILWAY_PUBLIC_DOMAIN:-}" && -z "${TELEGRAM_WEBHOOK_URL:-}" ]]; then
  export TELEGRAM_WEBHOOK_URL="https://${RAILWAY_PUBLIC_DOMAIN}/telegram"
fi
export TELEGRAM_WEBHOOK_PORT="${GATEWAY_PORT}"

if [[ "${GATEWAY_ALLOW_ALL_USERS:-false}" == "true" && "${HERMES_RAILWAY_ALLOW_UNSAFE:-}" != "1" ]]; then
  echo "Refusing to start: GATEWAY_ALLOW_ALL_USERS=true is unsafe for a public Railway gateway."
  echo "Set TELEGRAM_ALLOWED_USERS to your Telegram numeric user id instead."
  exit 64
fi

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "Refusing to start: TELEGRAM_BOT_TOKEN is required for the Telegram gateway."
  exit 64
fi

if [[ -z "${TELEGRAM_ALLOWED_USERS:-}" && "${GATEWAY_ALLOW_ALL_USERS:-false}" != "true" ]]; then
  echo "Refusing to start: set TELEGRAM_ALLOWED_USERS to your Telegram numeric user id."
  exit 64
fi

if [[ -n "${TELEGRAM_WEBHOOK_URL:-}" && -z "${TELEGRAM_WEBHOOK_SECRET:-}" ]]; then
  echo "Refusing to start: TELEGRAM_WEBHOOK_SECRET is required when TELEGRAM_WEBHOOK_URL is set."
  echo "Generate one with: openssl rand -hex 32"
  exit 64
fi

terminal_backend="${HERMES_TERMINAL_BACKEND:-}"
if [[ -z "${terminal_backend}" ]]; then
  if [[ -n "${VERCEL_TOKEN:-}" && -n "${VERCEL_PROJECT_ID:-}" && -n "${VERCEL_TEAM_ID:-}" ]]; then
    terminal_backend="vercel_sandbox"
  elif [[ -n "${MODAL_TOKEN_ID:-}" && -n "${MODAL_TOKEN_SECRET:-}" ]]; then
    terminal_backend="modal"
  elif [[ -n "${DAYTONA_API_KEY:-}" ]]; then
    terminal_backend="daytona"
  else
    terminal_backend="local"
  fi
fi

hermes config set terminal.backend "${terminal_backend}"
if [[ "${terminal_backend}" == "local" ]]; then
  hermes config set terminal.cwd "${HERMES_HOME}/workspace"
fi

if [[ -n "${HERMES_MODEL_PROVIDER:-}" ]]; then
  hermes config set model.provider "${HERMES_MODEL_PROVIDER}"
fi

if [[ -n "${HERMES_MODEL:-}" ]]; then
  hermes config set model.default "${HERMES_MODEL}"
fi

if [[ -n "${HERMES_AUX_MODEL:-}" && -n "${HERMES_AUX_PROVIDER:-}" ]]; then
  for task in title_generation compression web_extract approval session_search; do
    hermes config set "auxiliary.${task}.provider" "${HERMES_AUX_PROVIDER}"
    hermes config set "auxiliary.${task}.model" "${HERMES_AUX_MODEL}"
  done
fi

hermes config set platforms.api_server.enabled true
hermes config set platforms.api_server.extra.host "${GATEWAY_HOST}"
hermes config set platforms.api_server.extra.port "${GATEWAY_PORT}"
hermes config set platforms.api_server.cors_origins "*"
if [[ -n "${API_SERVER_KEY:-}" ]]; then
  hermes config set platforms.api_server.key "${API_SERVER_KEY}"
else
  hermes config set platforms.api_server.key ""
fi

wait_for_http() {
  local url="$1"
  local name="$2"
  local attempts="${3:-60}"
  local sleep_s="${4:-1}"
  for ((i=1; i<=attempts; i++)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "${name} is ready: ${url}"
      return 0
    fi
    sleep "$sleep_s"
  done
  echo "Timed out waiting for ${name}: ${url}"
  return 1
}

cleanup() {
  set +e
  if [[ -n "${PROXY_PID:-}" ]]; then kill "${PROXY_PID}" 2>/dev/null || true; fi
  if [[ -n "${WEBUI_PID:-}" ]]; then kill "${WEBUI_PID}" 2>/dev/null || true; fi
  if [[ -n "${GATEWAY_PID:-}" ]]; then kill "${GATEWAY_PID}" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

echo "Starting Hermes gateway on ${GATEWAY_HOST}:${GATEWAY_PORT}"
hermes gateway run --replace >"${GATEWAY_LOG}" 2>&1 &
GATEWAY_PID=$!
wait_for_http "http://${GATEWAY_HOST}:${GATEWAY_PORT}/health" "gateway"

echo "Starting hermes-web-ui on 127.0.0.1:${WEBUI_PORT}"
export HERMES_BIN="$(command -v hermes)"
export HOME="${HERMES_HOME}"
if [[ -n "${HERMES_WEBUI_AUTH_TOKEN:-}" ]]; then
  export AUTH_TOKEN="${HERMES_WEBUI_AUTH_TOKEN}"
fi
hermes-web-ui "${WEBUI_PORT}" >"${WEBUI_LOG}" 2>&1 &
WEBUI_PID=$!
wait_for_http "http://127.0.0.1:${WEBUI_PORT}/health" "web-ui"

echo "Public URL: https://${RAILWAY_PUBLIC_DOMAIN:-<your-railway-domain>}"
echo "Web UI token file: ${HERMES_HOME}/.hermes-web-ui/.token"
echo "Gateway log: ${GATEWAY_LOG}"
echo "Web UI log: ${WEBUI_LOG}"
echo "Starting public reverse proxy on 0.0.0.0:${PUBLIC_PORT}"
node "${INSTALL_DIR}/scripts/railway-webui-proxy.mjs" &
PROXY_PID=$!
wait "$PROXY_PID"
