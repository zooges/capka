/**
 * APNs delivery for the native iOS client.
 *
 * Why this exists at all: iOS gives a backgrounded app roughly 30 seconds of
 * runtime. A turn with a cold sandbox and a few tool calls routinely runs for
 * minutes, so the client-side "notify on the busy→idle edge" trick dies with the
 * suspended process — the user is simply never told their answer arrived. Only a
 * server push crosses that gap.
 *
 * Hand-rolled on `node:http2` + `node:crypto` rather than pulling in an APNs
 * SDK: the protocol here is one JWT and one POST, and the repo already prefers
 * not to add a dependency for a single call site.
 */
import { createSign } from "node:crypto";
import { connect, constants, type ClientHttp2Session } from "node:http2";
import { and, eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db";
import { pushTokens } from "@/lib/db/schema";
import { log } from "@/lib/log";

const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

type Environment = keyof typeof HOSTS;

function config() {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const bundleId = process.env.APNS_BUNDLE_ID;
  // The .p8 contents. Newlines survive an env var badly, so `\n` is accepted too.
  const key = process.env.APNS_KEY_P8?.replace(/\\n/g, "\n");
  if (!keyId || !teamId || !bundleId || !key) return null;
  return { keyId, teamId, bundleId, key };
}

/** Whether push is configured at all — callers skip silently when it isn't. */
export function isPushConfigured(): boolean {
  return config() !== null;
}

// Apple rejects tokens older than an hour and rate-limits minting, so one JWT is
// reused until it is close to expiry.
let cachedJwt: { token: string; issuedAt: number } | null = null;

function providerToken(): string | null {
  const cfg = config();
  if (!cfg) return null;
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 45 * 60) return cachedJwt.token;

  const header = { alg: "ES256", kid: cfg.keyId };
  const payload = { iss: cfg.teamId, iat: now };
  const b64 = (o: unknown) =>
    Buffer.from(JSON.stringify(o)).toString("base64url");
  const unsigned = `${b64(header)}.${b64(payload)}`;

  const signer = createSign("SHA256");
  signer.update(unsigned);
  // APNs wants the JOSE (r||s) form, not DER — `dsaEncoding` asks for it directly.
  const signature = signer.sign({ key: cfg.key, dsaEncoding: "ieee-p1363" });
  const token = `${unsigned}.${signature.toString("base64url")}`;
  cachedJwt = { token, issuedAt: now };
  return token;
}

const sessions = new Map<Environment, ClientHttp2Session>();

function session(environment: Environment): ClientHttp2Session {
  const existing = sessions.get(environment);
  if (existing && !existing.closed && !existing.destroyed) return existing;
  const next = connect(HOSTS[environment]);
  // A dead session must not take the process with it; the next send reconnects.
  next.on("error", () => sessions.delete(environment));
  next.on("close", () => sessions.delete(environment));
  sessions.set(environment, next);
  return next;
}

type PushResult = { status: number; reason?: string };

function post(
  environment: Environment,
  deviceToken: string,
  body: string,
  jwt: string,
  bundleId: string,
): Promise<PushResult> {
  return new Promise((resolve) => {
    let settled = false;
    const done = (result: PushResult) => {
      if (!settled) {
        settled = true;
        resolve(result);
      }
    };
    try {
      const request = session(environment).request({
        [constants.HTTP2_HEADER_METHOD]: "POST",
        [constants.HTTP2_HEADER_PATH]: `/3/device/${deviceToken}`,
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        // A finished answer is worth waking the screen for, but not worth
        // breaking Focus over.
        "apns-priority": "10",
        "content-type": "application/json",
      });
      let status = 0;
      let payload = "";
      request.on("response", (headers) => {
        status = Number(headers[constants.HTTP2_HEADER_STATUS] ?? 0);
      });
      request.setEncoding("utf8");
      request.on("data", (chunk) => {
        payload += chunk;
      });
      request.on("end", () => {
        let reason: string | undefined;
        try {
          reason = payload ? (JSON.parse(payload) as { reason?: string }).reason : undefined;
        } catch {
          reason = undefined;
        }
        done({ status, reason });
      });
      request.on("error", () => done({ status: 0 }));
      request.setTimeout(10_000, () => {
        request.close();
        done({ status: 0 });
      });
      request.end(body);
    } catch {
      done({ status: 0 });
    }
  });
}

export interface PushMessage {
  title: string;
  body: string;
  /** Opened chat when the user taps the notification. */
  chatId?: string;
}

/**
 * Send to every device registered for a user. Tokens Apple reports as dead are
 * deleted — a stale token otherwise costs a request on every future turn, and
 * Apple treats repeated sends to unregistered devices as abuse.
 */
export async function pushToUser(userId: string, message: PushMessage): Promise<void> {
  const cfg = config();
  const jwt = providerToken();
  if (!cfg || !jwt) return;

  const rows = await db
    .select({ token: pushTokens.token, environment: pushTokens.environment })
    .from(pushTokens)
    .where(eq(pushTokens.userId, userId));
  if (rows.length === 0) return;

  const body = JSON.stringify({
    aps: {
      alert: { title: message.title, body: message.body },
      sound: "default",
      "interruption-level": "active",
    },
    ...(message.chatId ? { chatId: message.chatId } : {}),
  });

  const dead: string[] = [];
  await Promise.all(
    rows.map(async (row) => {
      const environment: Environment = row.environment === "sandbox" ? "sandbox" : "production";
      const result = await post(environment, row.token, body, jwt, cfg.bundleId);
      // 410 = the device unregistered; 400/BadDeviceToken = wrong environment or
      // a token that was never valid. Both mean stop sending to it.
      if (result.status === 410 || result.reason === "BadDeviceToken" || result.reason === "Unregistered") {
        dead.push(row.token);
      } else if (result.status !== 200) {
        log.warn("apns send failed", { status: result.status, reason: result.reason });
      }
    }),
  );

  if (dead.length) {
    await db.delete(pushTokens).where(and(eq(pushTokens.userId, userId), inArray(pushTokens.token, dead)));
  }
}
