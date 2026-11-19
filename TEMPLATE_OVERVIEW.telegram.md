# Deploy and Host an OpenClaw AI Agent for Telegram on Railway

**Needs Railway's Hobby plan (or higher) and about 2 GB of RAM.** Measured on Railway with OpenClaw 2026.11.5, the agent idles at about 1.8 GB and reaches about 3 GB while it browses with Chromium. Trial (1 GB) and Free (0.5 GB) services run out of memory and restart in a loop.

Your own AI agent, living in a Telegram chat. Message it like a friend and it answers, remembers the conversation, runs scheduled tasks and messages you back. It also has a real Chromium browser, so it can open pages, read them, click and fill in forms for you.

It runs [OpenClaw](https://github.com/openclaw/openclaw) on your Railway account with the official Chromium image. You bring a Telegram bot token and an AI provider key; the template does the rest on first boot.

## About Hosting an OpenClaw Telegram Agent

OpenClaw is one long-running gateway process. It talks to Telegram by long polling, so your bot works without webhooks or any extra setup. It keeps its config, chat sessions, memory and workspace on a Railway volume at `/data`, and serves a web Control UI on a public HTTPS URL where you approve who may talk to the bot.

On first boot the template onboards OpenClaw, connects the provider key and the Telegram bot you entered, and starts the gateway on port 8080.

## Common Use Cases

- A personal assistant in your pocket: ask questions, draft messages, get reminders and daily summaries in Telegram
- A research helper: send it a link or a question and it reads the pages in Chromium and replies with what it found
- Web chores from your phone: check a site, fill in a form, compare prices, watch a page for changes
- A private agent for your family or team, with access only for the people you approve

## Dependencies for OpenClaw Telegram Agent Hosting

- A Telegram bot token from [@BotFather](https://t.me/botfather) (free, takes a minute; steps below)
- An API key from at least one AI provider: Anthropic, OpenAI, OpenRouter or Google Gemini

### Deployment Dependencies

- [OpenClaw on GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw Telegram docs](https://docs.openclaw.ai/channels/telegram)
- [OpenClaw pairing docs](https://docs.openclaw.ai/channels/pairing)
- [This template's source](https://github.com/hmseeb/openclaw-browser-railway-template)

### Implementation Details

**Step 1: create your Telegram bot (before you deploy)**

1. In Telegram, open a chat with [@BotFather](https://t.me/botfather).
2. Send `/newbot`.
3. Choose a display name, for example "My Agent".
4. Choose a username. It must end in `bot`, for example `my_agent_bot`.
5. BotFather replies with a token that looks like `123456789:AAH...`. Copy it. Anyone with this token controls your bot, so keep it private.

Optional: send `/setdescription` and `/setuserpic` to BotFather to give your bot a description and a picture.

**Step 2: deploy**

Paste the token into `TELEGRAM_BOT_TOKEN` and your provider key into `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY` or `GEMINI_API_KEY`. Set `OPENCLAW_MODEL` if you want a specific model, for example `anthropic/claude-haiku-4-5` for a fast, cheap agent. Then deploy. The first boot takes a few minutes.

`TELEGRAM_BOT_TOKEN` is optional on the form, so you can also deploy first and add it later. Add the variable on the service and redeploy, and the bot is connected on the next boot.

**Step 3: pair yourself with the bot**

Your bot does not answer strangers. Every new person goes through pairing first:

1. Open your bot in Telegram and send it any message.
2. The bot replies with an 8-character pairing code. Your message is held until you approve it. Codes expire after one hour.
3. On Railway, open the service's **Variables** tab, copy `OPENCLAW_LOGIN_URL` and open it. You land in the Control UI, already logged in.
4. In the Control UI, open **Settings**, then **Channels**, then **DM access requests**. Find your code and choose **Approve**. Tick "make this sender the first command owner" so you can manage the agent from chat.
5. Message the bot again. It now answers you.

Do the same for anyone else you want to let in. Approving a person gives them direct messages only. Group chats need their own setup, see the [Telegram docs](https://docs.openclaw.ai/channels/telegram).

**The browser**

Chromium ships inside the image, so the browser tool works with no extra setup. Ask in Telegram, for example "open example.com and tell me the page title", and the agent drives a headless Chromium on your Railway service and replies with the result. Browsing is what pushes memory toward 3 GB, which is why the Hobby plan is needed.

**Variables**

| Variable | What it does |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Your bot token from BotFather. Connects the bot on boot. Optional on the form, add it any time and redeploy. |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `GEMINI_API_KEY` | AI provider keys. Set at least one. Change them any time and redeploy. |
| `OPENCLAW_MODEL` | Primary model as `provider/model`. Empty keeps the provider default or the model you picked in the Control UI. |
| `OPENCLAW_LOGIN_URL` | One-click login link to the Control UI. |
| `OPENCLAW_GATEWAY_TOKEN` | Your Control UI password. Generated for you. Change it and redeploy to sign out every browser. |
| `OPENCLAW_BACKUP_EVERY` | Backup interval, default `24h`. `off` disables backups. |
| `OPENCLAW_SAFE_MODE` | `true` starts OpenClaw from a fresh config without touching your chats or workspace. |

**Keeping it running**

- Config is checked on every boot and repaired automatically, with a fallback to the last good copy, so an agent that edits its own settings cannot crash-loop the service.
- Config, sessions and workspace are backed up to `/data/backups` every 24 hours (7 daily and 4 weekly copies). They live on the same volume, so they do not protect against deleting it.
- New browsers that log in with your token are approved automatically, so you never need a terminal.
- After a crash or out-of-memory kill, the next boot recovers on its own.

**Resources and cost**

Measured on Railway (OpenClaw 2026.11.5): about 1.8 GB of RAM idle and about 3 GB while Chromium is open. At Railway's memory pricing that is roughly $18 to $30 a month for one always-on agent, plus your AI provider's charges. A small model such as Claude Haiku keeps provider costs low.

**Security**

Only people you approve can talk to your bot. The Control UI is on a public HTTPS URL protected by `OPENCLAW_GATEWAY_TOKEN`; anyone with that token or your bot token can control the agent, so keep both private. Telegram keeps working without the public URL, so after pairing you can remove the domain under **Settings**, **Networking** and add it back when you need the Control UI. Read the [OpenClaw security guide](https://docs.openclaw.ai/gateway/security).

**Updating**

New deploys are pinned to a tested image tag, for example `2026.11.5-r1`. To update, set the service's image to a newer tag from the [image page](https://github.com/hmseeb/openclaw-browser-railway-template/pkgs/container/openclaw-browser-railway) and redeploy.

**Troubleshooting**

- *The bot never replies, not even with a code:* check that `TELEGRAM_BOT_TOKEN` is set and redeploy. Look for `[railway] adding Telegram` in the deploy logs.
- *No new pairing code:* the bot sends a code once per hour per person, and holds at most 3 pending requests. Approve or dismiss the waiting ones in the Control UI.
- *The bot answers with an auth error:* the provider key is missing or does not match the model's provider.
- *The service keeps restarting:* it is out of memory. Move to the Hobby plan or higher.
- *Logs:* open the service's **Deployments** tab. Lines starting with `[railway]` come from this template's boot script.

## Why Deploy an OpenClaw Telegram Agent on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying an OpenClaw Telegram agent on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
