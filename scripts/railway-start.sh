#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-/opt/data}"

mkdir -p "${HERMES_HOME}/workspace"

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
