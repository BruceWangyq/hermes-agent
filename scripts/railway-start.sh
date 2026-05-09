#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="${HERMES_INSTALL_DIR:-/opt/hermes}"

if [[ -f "${INSTALL_DIR}/.venv/bin/activate" ]]; then
  # Railway's start command can run without the Docker entrypoint's activated
  # shell environment, so make the Hermes console script available explicitly.
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

if [[ -n "${PORT:-}" && -z "${TELEGRAM_WEBHOOK_PORT:-}" ]]; then
  export TELEGRAM_WEBHOOK_PORT="${PORT}"
fi

if [[ -n "${RAILWAY_PUBLIC_DOMAIN:-}" && -z "${TELEGRAM_WEBHOOK_URL:-}" ]]; then
  export TELEGRAM_WEBHOOK_URL="https://${RAILWAY_PUBLIC_DOMAIN}/telegram"
fi

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

echo "Starting Hermes gateway"
echo "HERMES_HOME=${HERMES_HOME}"
echo "terminal.backend=${terminal_backend}"
echo "telegram.webhook=$([[ -n "${TELEGRAM_WEBHOOK_URL:-}" ]] && echo enabled || echo disabled)"

exec hermes gateway run
