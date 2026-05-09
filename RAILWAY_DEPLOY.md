# Hermes Agent on Railway

This repo is configured for a safer Railway deployment:

- Dockerfile build from the upstream Hermes image.
- Telegram webhook mode for Railway public HTTPS.
- Persistent Hermes data on a Railway Volume.
- Gateway user allowlist required at startup.
- Dashboard and API server disabled by default.

## Railway service

Create a Railway project from this GitHub repo. Railway will read `railway.json` and run:

```bash
bash scripts/railway-start.sh
```

Add a Railway Volume:

```text
Mount path: /opt/data
```

Hermes stores `config.yaml`, `.env`, sessions, logs, memories, skills, and workspace files under that path.

## Required variables

Set these in Railway service variables:

```bash
HERMES_HOME=/opt/data

TELEGRAM_BOT_TOKEN=replace_me
TELEGRAM_ALLOWED_USERS=123456789
GATEWAY_ALLOW_ALL_USERS=false

TELEGRAM_WEBHOOK_URL=https://${{RAILWAY_PUBLIC_DOMAIN}}/telegram
TELEGRAM_WEBHOOK_SECRET=replace_with_openssl_rand_hex_32
TELEGRAM_WEBHOOK_PORT=${{PORT}}

OPENROUTER_API_KEY=replace_me
HERMES_MODEL_PROVIDER=openrouter
HERMES_MODEL=anthropic/claude-sonnet-4.6
```

Generate the webhook secret locally:

```bash
openssl rand -hex 32
```

Find your Telegram user id with `@userinfobot`, then put the numeric id in `TELEGRAM_ALLOWED_USERS`.

## Safer terminal backend

By default, the script uses `local` terminal execution inside the Railway container and sets the working directory to `/opt/data/workspace`.

For stronger isolation, use a cloud sandbox backend. The script auto-selects one if these credentials exist:

```bash
# Vercel Sandbox
VERCEL_TOKEN=...
VERCEL_PROJECT_ID=...
VERCEL_TEAM_ID=...

# or Modal
MODAL_TOKEN_ID=...
MODAL_TOKEN_SECRET=...

# or Daytona
DAYTONA_API_KEY=...
```

You can also force one:

```bash
HERMES_TERMINAL_BACKEND=vercel_sandbox
```

## Optional cheaper auxiliary model

To keep side tasks cheaper:

```bash
HERMES_AUX_PROVIDER=openrouter
HERMES_AUX_MODEL=google/gemini-3-flash-preview
```

This applies to title generation, compression, web extraction, approval, and session search.

## Do not enable publicly

Do not set these on Railway unless you have added separate authentication and understand the risk:

```bash
GATEWAY_ALLOW_ALL_USERS=true
HERMES_DASHBOARD=1
API_SERVER_HOST=0.0.0.0
```

Hermes can execute tools and terminal commands. Keep the gateway allowlisted.

## Smoke test

After deploy:

1. Open Railway logs and confirm the gateway starts.
2. Send `/status` to the Telegram bot.
3. Send `/model` to confirm the model.
4. Send `reply pong only`.
5. Send a small tool task such as `what is your current working directory?`.
