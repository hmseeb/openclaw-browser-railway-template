// Drive the Control UI like a first-time visitor. Runs inside the OpenClaw image,
// which ships playwright-core and Chromium:
//   docker run --rm -v "$PWD/test:/t" -e URL=... -e TOKEN=... -e OUT=/t/out \
//     --entrypoint node ghcr.io/openclaw/openclaw:<tag>-browser /t/ui_probe.mjs
import { chromium } from "/app/node_modules/playwright-core/index.mjs";
import fs from "node:fs";

const url = process.env.URL;
const token = process.env.TOKEN ?? "";
const out = process.env.OUT ?? "/tmp/out";
const waitMs = Number(process.env.WAIT_MS ?? 20000);
const profile = process.env.PROFILE; // reuse a browser identity across runs
fs.mkdirSync(out, { recursive: true });

const ctx = profile
  ? await chromium.launchPersistentContext(profile, { headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"] })
  : await (await chromium.launch({ headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"] })).newContext();
const page = ctx.pages()[0] ?? (await ctx.newPage());
const consoleLines = [];
page.on("console", (m) => consoleLines.push(`${m.type()}: ${m.text()}`));
page.on("websocket", (ws) => {
  ws.on("close", () => consoleLines.push(`ws closed ${ws.url()}`));
  ws.on("framereceived", (f) => {
    const s = String(f.payload);
    if (/error|pair|denied|NOT_PAIRED/i.test(s)) consoleLines.push(`ws<- ${s.slice(0, 300)}`);
  });
});

console.log("launched");
await page.goto(token ? `${url}/#token=${encodeURIComponent(token)}` : url, { waitUntil: "domcontentloaded" });
await page.waitForTimeout(waitMs);
if (process.env.SEND) {
  const box = page.locator("textarea").first();
  await box.fill(process.env.SEND);
  await box.press("Enter");
  await page.waitForTimeout(Number(process.env.REPLY_WAIT_MS ?? 45000));
}
const text = (await page.locator("body").innerText()).replace(/\n{2,}/g, "\n");
await page.screenshot({ path: `${out}/${process.env.SHOT ?? "ui"}.png`, fullPage: false });
console.log("=== TEXT\n" + text.slice(0, 2500));
console.log("=== CONSOLE\n" + consoleLines.slice(-25).join("\n"));
await ctx.close();
