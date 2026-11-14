#!/usr/bin/env bash
# Railway boot for OpenClaw. Starts as root only to fix volume ownership, applies
# the settings a Railway deploy needs, then hands off to the upstream entrypoint
# (doctor --fix, then the gateway) as the image's node user.
set -euo pipefail

log() { echo "[railway] $*"; }
truthy() { case "${1:-}" in 1 | true | TRUE | True | yes | on) return 0 ;; *) return 1 ;; esac; }

DATA=${OPENCLAW_DATA_DIR:-/data}
export OPENCLAW_STATE_DIR=${OPENCLAW_STATE_DIR:-$DATA/.openclaw}
export OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR:-$DATA/workspace}
export OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT:-${PORT:-8080}}
export HOME=$DATA/home
BACKUP_DIR=$DATA/backups
cd /app

if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  log "OPENCLAW_GATEWAY_TOKEN is empty. Set it in the service Variables (any long random string) and redeploy."
  exit 1
fi
if [ "$(id -u)" != 0 ]; then
  log "must start as root to prepare the volume; remove RAILWAY_RUN_UID or set it to 0"
  exit 1
fi

# gosu resets HOME to the passwd entry; keep it on the volume.
as_node() { gosu node env HOME="$HOME" "$@"; }
oc() { as_node node /app/openclaw.mjs "$@"; }

# Volume layout. Railway volumes arrive root-owned; only re-chown what is wrong so
# big volumes do not pay a recursive chown on every boot.
mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR" "$HOME" "$BACKUP_DIR"
chown node:node "$DATA"
for d in "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR" "$HOME" "$BACKUP_DIR"; do
  [ "$(stat -c %U "$d")" = node ] || chown -R node:node "$d"
done
chmod 700 "$OPENCLAW_STATE_DIR"

# Homebrew lives on the volume so `brew install` from skills survives redeploys.
if [ -d /home/linuxbrew/.linuxbrew ] && [ ! -L /home/linuxbrew/.linuxbrew ]; then
  if [ ! -x "$DATA/.linuxbrew/bin/brew" ]; then
    log "copying Homebrew onto the volume (first boot only)"
    rm -rf "$DATA/.linuxbrew"
    cp -a /home/linuxbrew/.linuxbrew "$DATA/.linuxbrew"
  fi
  rm -rf /home/linuxbrew/.linuxbrew
  ln -s "$DATA/.linuxbrew" /home/linuxbrew/.linuxbrew
fi

CFG=$OPENCLAW_STATE_DIR/openclaw.json
if truthy "${OPENCLAW_SAFE_MODE:-}"; then
  SAFE=$OPENCLAW_STATE_DIR/safe-mode
  log "SAFE MODE: starting from a fresh config in $SAFE. Your openclaw.json is untouched; unset OPENCLAW_SAFE_MODE to return to it."
  rm -rf "$SAFE" && mkdir -p "$SAFE" && chown node:node "$SAFE"
  export OPENCLAW_CONFIG_PATH=$SAFE/openclaw.json
  CFG=$OPENCLAW_CONFIG_PATH
fi

# A config the gateway cannot load must not crash-loop the service: let doctor try
# first, then set the file aside and fall back to upstream's last-good copy.
if [ -f "$CFG" ] && ! oc config validate >/dev/null 2>&1; then
  log "openclaw.json does not validate; running doctor --fix"
  oc doctor --fix --non-interactive >/dev/null 2>&1 || true
  if oc config validate >/dev/null 2>&1; then
    log "doctor repaired openclaw.json (the bad copy is kept as openclaw.json.clobbered.*)"
  else
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    mv "$CFG" "$CFG.broken-$ts"
    log "set the broken config aside as $(basename "$CFG").broken-$ts"
    if [ -f "$CFG.last-good" ] && cp -p "$CFG.last-good" "$CFG" && oc config validate >/dev/null 2>&1; then
      log "restored openclaw.json.last-good"
    else
      rm -f "$CFG"
      log "no usable last-good copy; starting from a fresh config"
    fi
  fi
fi

if [ "$(oc config get gateway.mode 2>/dev/null | tr -d '"[:space:]')" != local ]; then
  choice=skip
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then choice=apiKey
  elif [ -n "${OPENROUTER_API_KEY:-}" ]; then choice=openrouter-api-key
  elif [ -n "${GEMINI_API_KEY:-}" ]; then choice=gemini-api-key
  elif [ -n "${OPENAI_API_KEY:-}" ]; then choice=openai-api-key
  fi
  log "first boot: onboarding (provider auth: $choice)"
  onboard() {
    oc onboard --non-interactive --accept-risk --skip-health --skip-daemon --mode local \
      --auth-choice "$choice" --secret-input-mode ref \
      --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
      --gateway-bind lan --gateway-port "$OPENCLAW_GATEWAY_PORT" \
      --skip-channels --skip-ui --skip-search --skip-skills --json
  }
  # After a container is killed (OOM, crash) upstream refuses state writes until
  # the dead gateway's heartbeat is 90s old ("cannot verify Gateway ownership").
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if out=$(onboard 2>&1); then printf '%s\n' "$out" | tail -3; break; fi
    if [ "$attempt" = 10 ]; then printf '%s\n' "$out" | tail -20; log "onboarding failed"; exit 1; fi
    # A provider flow that cannot finish unattended must not block the gateway:
    # OpenClaw also reads provider keys straight from the environment.
    if [ "$choice" != skip ] && ! printf '%s' "$out" | grep -q 'Gateway ownership'; then
      log "provider onboarding ($choice) failed; continuing without it (the key is still read from the environment)"
      choice=skip
    fi
    log "onboarding failed (attempt $attempt): $(printf '%s' "$out" | grep -E '"message"' | head -1); retrying in 12s"
    sleep 12
  done
fi

# Railway invariants, re-applied every boot in one validated write.
# 100.64.0.0/10 is where Railway's edge proxy connects from; without it every
# request fails with proxy_attribution_required.
origins='[]'
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  origins=$(printf '%s' "https://$RAILWAY_PUBLIC_DOMAIN ${OPENCLAW_EXTRA_ORIGINS:-}" | tr ', ' '\n\n' | sed '/^$/d' |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.stringify(s.trim().split("\n"))))')
fi
oc config patch --stdin >/dev/null <<EOF
{
  gateway: {
    mode: "local",
    bind: "lan",
    port: $OPENCLAW_GATEWAY_PORT,
    auth: { mode: "token", token: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" } },
    trustedProxies: ["100.64.0.0/10"],
    ${RAILWAY_PUBLIC_DOMAIN:+publicOrigin: \"https://$RAILWAY_PUBLIC_DOMAIN\",}
    controlUi: { allowedOrigins: $origins },
  },
}
EOF

if [ -n "${OPENCLAW_MODEL:-}" ] && [ "$(oc config get agents.defaults.model.primary 2>/dev/null | tr -d '"[:space:]')" != "$OPENCLAW_MODEL" ]; then
  log "setting primary model to $OPENCLAW_MODEL"
  oc models set "$OPENCLAW_MODEL" >/dev/null || log "could not set model $OPENCLAW_MODEL; keeping the current one"
fi

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && ! oc config get channels.telegram >/dev/null 2>&1; then
  log "adding Telegram from TELEGRAM_BOT_TOKEN"
  oc channels add --channel telegram --use-env >/dev/null || log "Telegram setup failed; add it from the Control UI"
fi

# After the gateway is up: provision the backup schedule (it is a gateway-owned
# cron job) and start the browser auto-approver.
(
  for _ in $(seq 1 150); do curl -sf "http://127.0.0.1:$OPENCLAW_GATEWAY_PORT/startupz" >/dev/null 2>&1 && break; sleep 2; done
  every=${OPENCLAW_BACKUP_EVERY:-24h}
  if [ "$every" != off ]; then
    if ! oc config get storage.locations.volume >/dev/null 2>&1; then
      oc config patch --stdin >/dev/null <<EOF
{ storage: { locations: { volume: { provider: "filesystem", settings: { path: "$BACKUP_DIR" }, encryption: "none" } } } }
EOF
      oc storage init volume >/dev/null || log "backup storage init failed"
    fi
    if [ "$(cat "$OPENCLAW_STATE_DIR/.railway-backup-every" 2>/dev/null)" != "$every" ]; then
      # The schedule is a gateway cron job; right after startup the cron service
      # can still refuse it, so retry for a minute.
      for attempt in 1 2 3 4 5 6; do
        if out=$(oc backup enable --to volume --every "$every" --keep-daily 7 --keep-weekly 4 2>&1); then
          as_node sh -c "echo '$every' > '$OPENCLAW_STATE_DIR/.railway-backup-every'"
          log "backups: every $every to $BACKUP_DIR (7 daily, 4 weekly kept)"
          break
        fi
        [ "$attempt" = 6 ] && log "could not enable scheduled backups: $(printf '%s' "$out" | tail -1)"
        sleep 10
      done
    fi
  fi
  if ! truthy "${OPENCLAW_AUTO_APPROVE_BROWSERS:-true}"; then
    log "browser auto-approval is off; approve new browsers with: openclaw devices approve <id>"
  else
    exec gosu node env HOME="$HOME" node /usr/local/lib/openclaw-railway/approve-browsers.mjs
  fi
) &

log "starting OpenClaw gateway on port $OPENCLAW_GATEWAY_PORT"
exec gosu node env HOME="$HOME" node /app/docker-entrypoint.mjs node openclaw.mjs gateway
