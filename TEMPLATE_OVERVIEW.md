# Deploy and Host OpenClaw on Railway

> **Needs Railway's Hobby plan (or higher) and about 2 GB of RAM.** Measured on Railway with OpenClaw 2026.11.5, the service idles at about 1.8 GB and reaches about 3 GB while the browser tool runs Chromium. Trial (1 GB) and Free (0.5 GB) services run out of memory and restart in a loop.

OpenClaw is a personal AI agent that runs on your own server. Talk to it from the web Control UI, Telegram, WhatsApp, Discord, Slack and 20+ other chat apps. It can browse the web, run commands, manage files and work on tasks around the clock.

This template runs the **official OpenClaw image with Chromium built in**, and adds the Railway pieces other OpenClaw templates leave to you: no build step, no shell needed to pair your browser, a config that cannot brick the service, and scheduled backups.

## About Hosting OpenClaw

OpenClaw is one long-running gateway process. It needs a persistent disk for its config, sessions and workspace, a public HTTPS URL for the Control UI, and an API key for at least one AI provider.

This template deploys one service with a volume at `/data`. On first boot it onboards OpenClaw for you, connects your provider key and Telegram bot if you gave them, and starts the gateway on port 8080 behind Railway's HTTPS domain.

### Why this template instead of the others

| Common problem with other OpenClaw templates | This template |
|---|---|
| Builds from source on every deploy: slow, runs out of memory, breaks when a build tool changes | Pulls a prebuilt image. Deploys in about a minute. |
| "pairing required" or "Approve this browser", with no terminal to approve it | Browsers that log in with your token are approved automatically |
| "Application failed to respond" or `proxy_attribution_required` | Port, trusted proxy and allowed origins are set for Railway on every boot |
| The agent edits its own config and the service crash-loops | Config is checked and repaired on boot, with a fallback to the last good copy, plus a one-variable safe mode |
| Can't change the API key or model after setup | Keys and model are plain Railway variables. Change one and redeploy. |
| No headless browser for the browser tool | Chromium is included |
| Everything lost after the agent breaks something | Automatic backups every 24 hours |
| `brew install` disappears after a redeploy | Homebrew and your home directory live on the volume |
| An OpenClaw release breaks the template | Each new release must pass 18 automated checks before new deploys get it |

## Common Use Cases

- A personal assistant in Telegram or WhatsApp that remembers context, runs scheduled tasks and messages you back
- A web research agent that drives a real headless Chromium to read, click and fill in pages
- An always-on coding and automation agent with a persistent workspace, shell tools and Homebrew packages
- A shared team agent in Slack or Discord with its own sessions and memory

## Dependencies for OpenClaw Hosting

- An API key from at least one AI provider: Anthropic, OpenAI, OpenRouter or Google Gemini
- Optional: a Telegram bot token from [@BotFather](https://t.me/botfather)

### Deployment Dependencies

- [OpenClaw on GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw documentation](https://docs.openclaw.ai)
- [This template's source](https://github.com/hmseeb/openclaw-browser-railway-template)

### Implementation Details

**First login**

1. When the deploy finishes, open the service's **Variables** tab and copy `OPENCLAW_LOGIN_URL`.
2. Open it. You land in the Control UI, already logged in. The token travels in the URL fragment, which your browser never sends to any server.
3. On a new phone or browser, open the same link, or open your domain and paste `OPENCLAW_GATEWAY_TOKEN` as the Gateway secret.

New browsers are approved automatically once they present the correct token. A wrong token never creates an approval request. To approve each device yourself, set `OPENCLAW_AUTO_APPROVE_BROWSERS` to `false`.

**Variables**

| Variable | What it does |
|---|---|
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `GEMINI_API_KEY` | Provider keys. Set at least one. Add or rotate them any time and redeploy. |
| `OPENCLAW_MODEL` | Primary model as `provider/model`, for example `anthropic/claude-haiku-4-5`. Empty keeps the provider default or whatever you picked in the Control UI. |
| `TELEGRAM_BOT_TOKEN` | Connects your Telegram bot on boot. DM the bot, then approve the request in the Control UI. |
| `OPENCLAW_GATEWAY_TOKEN` | Your login secret. Generated for you. Change it and redeploy to sign out every device. |
| `OPENCLAW_BACKUP_EVERY` | Backup interval, default `24h`. `off` disables backups. |
| `OPENCLAW_SAFE_MODE` | `true` starts OpenClaw from a fresh config without touching your data. Set it back to `false` to return to your config. |
| `OPENCLAW_EXTRA_ORIGINS` | Extra Control UI origins, space or comma separated. Add `https://your.domain` here when you attach a custom domain. |

**Backups**

Backups use OpenClaw's own scheduler and land in `/data/backups`, keeping 7 daily and 4 weekly copies. They protect you from a broken config or a wiped workspace. They live on the same volume, so they do not protect against deleting the volume. For offsite copies, OpenClaw supports Cloudflare R2 storage locations; see the [backup docs](https://docs.openclaw.ai/cli/backup).

**If OpenClaw breaks itself**

On every boot the config is validated. If it is broken, `openclaw doctor --fix` repairs it and keeps the bad copy as `openclaw.json.clobbered.*`. If doctor cannot fix it, the file is set aside and the last good copy is restored. If the agent is still misbehaving, set `OPENCLAW_SAFE_MODE` to `true` and redeploy. If the service was killed (out of memory, crash), the next boot recovers the lock the stopped gateway left on the volume, so it does not stay down.

**Resources and cost**

Measured on Railway (OpenClaw 2026.11.5): the service idles at about 1.8 GB of RAM, and about 3 GB once the browser tool has started Chromium, so it needs the Hobby plan. At Railway's memory pricing that is roughly $18 to $30 a month for one always-on instance, plus your AI provider's charges. Pick a smaller model with `OPENCLAW_MODEL` to keep provider costs down.

**Security**

Your gateway is reachable on a public HTTPS URL and protected by `OPENCLAW_GATEWAY_TOKEN`. Anyone with that token has full control of your agent, so keep it private. To make the Control UI private after setup, remove the public domain in **Settings > Networking**. Chat channels such as Telegram keep working without it. Read the [OpenClaw security guide](https://docs.openclaw.ai/gateway/security).

**Updating**

New deploys are pinned to a tested image tag, `<openclaw-version>-r<n>` (for example `2026.11.5-r1`). To update, set the service's image to a newer tag from the [image page](https://github.com/hmseeb/openclaw-browser-railway-template/pkgs/container/openclaw-browser-railway) and redeploy. Use `:latest` instead to follow every OpenClaw release that passed this template's automated checks.

**Troubleshooting**

- *First deploy takes a few minutes:* first boot copies Homebrew onto the volume and onboards OpenClaw. Later boots are faster.
- *"This Gateway expects its token":* the token you pasted is wrong. Copy `OPENCLAW_LOGIN_URL` again.
- *Agent replies with an auth error:* check that the provider key variable is set and matches the model's provider.
- *Logs:* open the service's **Deployments** tab. Lines starting with `[railway]` come from this template's boot script.

## Why Deploy OpenClaw on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying OpenClaw on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
