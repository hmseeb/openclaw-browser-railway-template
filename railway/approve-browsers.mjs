// Approves Control UI browsers that already passed gateway token auth.
//
// On Railway there is no terminal on the gateway host, so upstream's "run
// `openclaw devices approve <id>` on the host" step strands every new browser.
// A pending request only exists after the browser presented the correct
// OPENCLAW_GATEWAY_TOKEN (a wrong token never creates one), so approving it
// grants nothing the token did not already grant.
//
// Polls the pending table read-only every few seconds (cheap) and shells out to
// the real CLI only when there is something to approve. Disable with
// OPENCLAW_AUTO_APPROVE_BROWSERS=false.
import { execFile } from "node:child_process";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const db = path.join(process.env.OPENCLAW_STATE_DIR ?? "/data/.openclaw", "state", "openclaw.sqlite");
const POLL_MS = 3000;
const seen = new Set();
let warned = false;

const log = (msg) => console.log(`[railway] ${msg}`);

function pending() {
  const conn = new DatabaseSync(db, { readOnly: true });
  try {
    return conn
      .prepare(
        `select request_id, platform, remote_ip from device_pairing_pending
         where client_id = 'openclaw-control-ui' and role = 'operator' and is_repair = 0`,
      )
      .all();
  } finally {
    conn.close();
  }
}

function approve(row) {
  return new Promise((resolve) => {
    execFile(
      process.execPath,
      ["/app/openclaw.mjs", "devices", "approve", row.request_id, "--json"],
      { cwd: "/app", timeout: 60000 },
      (err) => {
        if (err) log(`could not approve browser ${row.request_id}: ${String(err.message).split("\n")[0]}`);
        else log(`approved new browser (${row.platform ?? "unknown platform"}, ${row.remote_ip ?? "unknown ip"})`);
        resolve();
      },
    );
  });
}

log("browser auto-approval on: browsers that enter the gateway token are approved automatically");
for (;;) {
  try {
    for (const row of pending()) {
      if (seen.has(row.request_id)) continue;
      seen.add(row.request_id);
      await approve(row);
    }
    warned = false;
  } catch (err) {
    // The table appears after the gateway's first start and its schema is upstream's;
    // never crash the container over it.
    if (!warned) log(`auto-approval waiting: ${String(err.message).split("\n")[0]}`);
    warned = true;
  }
  await new Promise((r) => setTimeout(r, POLL_MS));
}
