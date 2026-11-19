#!/usr/bin/env bash
# Contract tests for the image. Builds it, boots it the way Railway does (fresh
# root-owned volume with lost+found, RAILWAY_RUN_UID unset, raw env), and asserts
# the behavior the template promises. Usage: test/contract.sh [image]
set -uo pipefail
cd "$(dirname "$0")/.."

IMG=${1:-openclaw-browser:test}
# EXPECT_BROWSER=0 for the lite (w/ Dashboard) image, which ships no Chromium.
EXPECT_BROWSER=${EXPECT_BROWSER:-1}
[ "${1:-}" ] || docker build -q -t "$IMG" . >/dev/null || { echo "build failed"; exit 1; }

NAME=ocb-contract-$$
VOL=ocb-contract-vol-$$
TOKEN=contract-token-0123456789abcdef
pass=0; fail=0
ok()   { echo "ok    $1"; pass=$((pass+1)); }
bad()  { echo "FAIL  $1"; fail=$((fail+1)); }
check() {
  local out
  if out=$(eval "$2" 2>&1); then ok "$1"; else bad "$1"; printf '%s\n' "$out" | grep -vE 'Deprecation|trace-deprecation' | tail -15 | sed 's/^/      /'; fi
}
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; }
trap cleanup EXIT

boot() {
  docker rm -f "$NAME" >/dev/null 2>&1
  docker run -d --name "$NAME" -v "$VOL:/data" \
    -e PORT=8080 -e RAILWAY_PUBLIC_DOMAIN=example.up.railway.app \
    -e OPENCLAW_GATEWAY_TOKEN=$TOKEN -e OPENCLAW_BACKUP_EVERY=1m \
    "$@" "$IMG" >/dev/null
  for _ in $(seq 1 120); do
    docker exec "$NAME" curl -sf http://127.0.0.1:8080/startupz >/dev/null 2>&1 && return 0
    sleep 2
  done
  docker logs "$NAME" 2>&1 | tail -40
  return 1
}
x() { docker exec "$NAME" sh -c "$1"; }

# Railway volumes are root-owned and ship a lost+found directory.
docker volume create "$VOL" >/dev/null
docker run --rm -v "$VOL:/data" --user root --entrypoint sh "$IMG" -c 'mkdir /data/lost+found && chown root:root /data' >/dev/null 2>&1

check "first boot reaches /startupz on a root-owned volume" boot
check "gateway runs as node, not root" "x 'ps -eo user=,args= | grep -q \"^node *openclaw-gateway\"'"
check "listens on IPv4 (Railway healthchecker)" "x 'curl -sf http://127.0.0.1:8080/healthz'"
check "config seeded with gateway.mode local" "x 'grep -q \"\\\"mode\\\": \\\"local\\\"\" /data/.openclaw/openclaw.json'"
check "gateway token is an env ref, not plaintext" "x '! grep -q $TOKEN /data/.openclaw/openclaw.json'"
check "publicOrigin set from RAILWAY_PUBLIC_DOMAIN" "x 'grep -q https://example.up.railway.app /data/.openclaw/openclaw.json'"
check "HOME persists on the volume" "docker exec -u node $NAME sh -c 'grep -qz ^HOME=/data/home\$ /proc/\$(pgrep -u node -f ^openclaw-gateway)/environ'"
check "homebrew lives on the volume" "x 'test -x /data/.linuxbrew/bin/brew && readlink /home/linuxbrew/.linuxbrew | grep -q /data/.linuxbrew'"
if [ "$EXPECT_BROWSER" = 1 ]; then
  check "browser tool launches Chromium and opens a page" "docker exec -u node -e HOME=/data/home -e OPENCLAW_STATE_DIR=/data/.openclaw -w /app $NAME sh -c 'for i in 1 2 3; do node openclaw.mjs browser open https://example.com --json 2>&1 | grep -q tabId && exit 0; sleep 10; done; exit 1'"
  check "chromium is available for the browser tool" "x 'ls \$PLAYWRIGHT_BROWSERS_PATH | grep -q chromium'"
else
  check "no Chromium in the lite image" "x '! ls /home/node/.cache/ms-playwright 2>/dev/null | grep -q chromium'"
fi
check "control UI rejects requests without the token" "x '! curl -sf http://127.0.0.1:8080/control-ui-config.json'"

# Backups: interval forced tiny above; wait for the first archive.
for _ in $(seq 1 60); do x 'ls /data/backups/backups/*/*.tar.gz' >/dev/null 2>&1 && break; sleep 2; done
check "browser auto-approver is running" "x 'pgrep -u node -f approve-browsers.mjs'"
check "scheduled backup writes an archive to /data/backups" "x 'ls /data/backups/backups/*/*.tar.gz'"

# Model override applies on boot.
docker restart "$NAME" >/dev/null; docker rm -f "$NAME" >/dev/null
check "reboot with OPENCLAW_MODEL override" "boot -e OPENCLAW_MODEL=anthropic/claude-haiku-4-5"
check "OPENCLAW_MODEL becomes the primary model" "x 'grep -q claude-haiku-4-5 /data/.openclaw/openclaw.json'"

# A killed container (OOM, crash) leaves its Gateway lock on the volume, and the
# next container has another hostname. It must still boot without a manual
# `openclaw gateway recover-lock`.
docker kill "$NAME" >/dev/null; docker rm -f "$NAME" >/dev/null
check "boots after the previous container was killed (OOM)" boot
check "the killed container's lock was recovered" "docker logs $NAME 2>&1 | grep -F '[railway]' | tee /dev/stderr | grep -q 'recovered the Gateway lock'"

# In-place restart (Railway restarts keep the container filesystem): boots again.
docker restart "$NAME" >/dev/null
check "boots again after an in-place restart" "for i in \$(seq 1 90); do x 'curl -sf http://127.0.0.1:8080/startupz' >/dev/null 2>&1 && exit 0; sleep 2; done; docker logs $NAME 2>&1 | tail -20; exit 1"
docker kill "$NAME" >/dev/null; docker start "$NAME" >/dev/null
check "boots again after a crash restart of the same container" "for i in \$(seq 1 90); do x 'curl -sf http://127.0.0.1:8080/startupz' >/dev/null 2>&1 && exit 0; sleep 2; done; docker logs $NAME 2>&1 | tail -20; exit 1"

# Safe boot: a config the gateway cannot start with must not crash-loop forever.
x 'echo "{ this is not json" > /data/.openclaw/openclaw.json'
docker rm -f "$NAME" >/dev/null
check "boots despite a corrupted openclaw.json" boot
check "corrupted config was set aside for inspection" "x 'ls /data/.openclaw/ | grep -qE \"openclaw.json.(broken|clobbered)\"'"

# Safe mode: start with a pristine config, keep the user's file.
docker rm -f "$NAME" >/dev/null
check "boots with OPENCLAW_SAFE_MODE=1" "boot -e OPENCLAW_SAFE_MODE=1"
check "safe mode reports itself in the logs" "docker logs $NAME 2>&1 | grep -i 'safe mode' >/dev/null"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
