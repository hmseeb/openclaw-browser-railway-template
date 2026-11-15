# OpenClaw for Railway: (w/ Browser) and (w/ Dashboard)

[![Deploy OpenClaw (w/ Browser)](https://railway.com/button.svg)](https://railway.com/deploy/openclaw-w-browser) **OpenClaw (w/ Browser)**: Chromium included for the browser tool, about 2.3 GB RAM with the browser running.

[![Deploy OpenClaw (w/ Dashboard)](https://railway.com/button.svg)](https://railway.com/deploy/openclaw-w-dashboard) **OpenClaw (w/ Dashboard)**: lite, no Chromium, about 1.1 GB RAM.

Two Railway templates for [OpenClaw](https://github.com/openclaw/openclaw) built on
the official `ghcr.io/openclaw/openclaw:<version>` images (`-browser` variant for the Browser edition). This repo only
adds what a Railway deploy needs and upstream leaves to the operator.

| Problem users report with other OpenClaw templates | What this image does |
|---|---|
| Builds from source on every deploy: out of memory, pnpm build breaks | Pulls a prebuilt image. Nothing compiles at deploy time. |
| "pairing required" / "Approve this browser" with no shell to approve it | `railway/approve-browsers.mjs` approves browsers that already passed token auth |
| `proxy_attribution_required`, origin not allowed, 502 from port mismatch | Boot sets `gateway.trustedProxies` to Railway's edge (`100.64.0.0/10`), `publicOrigin`, allowed origins, and port 8080 |
| Agent edits its own config and crash-loops the gateway | Validates the config on boot, lets `doctor --fix` repair it, falls back to `last-good`; `OPENCLAW_SAFE_MODE=true` for a fresh start |
| Can't change the API key or model after setup | Keys and the gateway token are env refs; `OPENCLAW_MODEL` sets the primary model |
| No headless browser (`libnspr4.so` missing) | Chromium ships in the image |
| Data lost after the agent breaks things | Scheduled backups via upstream's `openclaw backup enable` to `/data/backups` |
| `brew install` gone after a redeploy | Homebrew, `HOME` and all state live on the `/data` volume |
| An upstream release breaks the template | CI builds each new release, runs `test/contract.sh`, and only then moves `:latest` |

## Layout

- `Dockerfile`: the thin image.
- `railway/boot.sh`: entrypoint. Prepares the volume as root, onboards on first
  boot, applies Railway settings in one validated `config patch`, then execs the
  upstream entrypoint as `node`.
- `railway/approve-browsers.mjs`: browser auto-approval.
- `test/contract.sh`: 19 checks (`EXPECT_BROWSER=0` for the lite image) against a freshly booted container.
- `test/ui_probe.mjs`: drives the Control UI with the Chromium inside the image.
- `template.json`: the Railway template build sheet. `upsert.py` writes it,
  `build_source.py` materializes it into a live project, `deploy_as_stranger.py`
  deploys the template like the button does.

## Images

- `ghcr.io/hmseeb/openclaw-browser-railway:<openclaw-version>` and `:latest`
- `ghcr.io/hmseeb/openclaw-dashboard-railway:<openclaw-version>` and `:latest`

The Dashboard sheet and listing live in `dashboard/`; run the scripts with `SHEET_DIR=dashboard`.
