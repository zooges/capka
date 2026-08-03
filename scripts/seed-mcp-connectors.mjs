/**
 * Register China-team system MCP connectors (idempotent).
 *
 * Default URLs target Capka compose DNS (docker-compose.mcp.yml sidecars).
 * Override with env:
 *   MCP_CHINESELAW_URL   default http://chineselaw-mcp:8317/mcp
 *   MCP_WECHAT_URL       default http://wechat-article-mcp:8809/mcp
 *   MCP_TAVILY_URL       default https://mcp.tavily.com/mcp/
 *   CHINESELAW_MCP_AUTH_TOKEN / WECHAT_MCP_AUTH_TOKEN → Bearer headers (encrypted)
 *   TAVILY_API_KEY       → Bearer for remote Tavily MCP (required to enable `tavily`)
 *   MCP_SEED_ONLY        comma list of names to seed (e.g. `tavily`); default = all
 *   CAPKA_MASTER_KEY     required when seeding auth tokens; else read auth_secret from DB
 *   DATABASE_URL         default local docker:dev Postgres
 */
import { randomBytes, createCipheriv } from "node:crypto";
import { randomUUID } from "node:crypto";
import pg from "pg";

const { Pool } = pg;
const DATABASE_URL = process.env.DATABASE_URL
  ?? "postgresql://Capka:Capka@127.0.0.1:5432/Capka";

const NAME_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

const CONNECTORS = [
  {
    name: "chineselaw",
    url: process.env.MCP_CHINESELAW_URL ?? "http://chineselaw-mcp:8317/mcp",
    transport: "http",
    tokenEnv: "CHINESELAW_MCP_AUTH_TOKEN",
  },
  {
    name: "wechat-article",
    url: process.env.MCP_WECHAT_URL ?? "http://wechat-article-mcp:8809/mcp",
    transport: "http",
    tokenEnv: "WECHAT_MCP_AUTH_TOKEN",
  },
  {
    // Official remote Streamable HTTP MCP (lazy-connect compatible). Auth via
    // Authorization: Bearer <TAVILY_API_KEY> — never put the key in the URL column.
    name: "tavily",
    url: process.env.MCP_TAVILY_URL ?? "https://mcp.tavily.com/mcp/",
    transport: "http",
    tokenEnv: "TAVILY_API_KEY",
    requireToken: true,
    // Keep quota light by default; the agent can still override per call.
    defaultParameters: { max_results: 5, search_depth: "basic", include_images: false },
  },
];

function slugify(name) {
  return name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function inferRemoteTransport(url) {
  try {
    const path = new URL(url).pathname.replace(/\/+$/, "").toLowerCase();
    if (path.endsWith("/sse") || path === "sse") return "sse";
  } catch { /* ignore */ }
  return "http";
}

function encrypt(plaintext, keyHex) {
  const key = Buffer.from(keyHex, "hex");
  if (key.length !== 32) throw new Error("Master key must be 32 bytes (64 hex characters)");
  const iv = randomBytes(16);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("hex")}:${tag.toString("hex")}:${encrypted.toString("hex")}`;
}

async function resolveMasterKey(client) {
  const envKey = process.env.CAPKA_MASTER_KEY?.trim();
  if (envKey) return envKey;
  const { rows } = await client.query(
    `SELECT value FROM settings WHERE key = 'auth_secret' LIMIT 1`,
  );
  if (rows[0]?.value) return rows[0].value;
  throw new Error(
    "No CAPKA_MASTER_KEY and no settings.auth_secret — start Capka once, or set CAPKA_MASTER_KEY.",
  );
}

function selectedConnectors() {
  const only = (process.env.MCP_SEED_ONLY ?? "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  if (only.length === 0) return CONNECTORS;
  const wanted = new Set(only);
  const picked = CONNECTORS.filter((c) => wanted.has(c.name));
  for (const name of wanted) {
    if (!CONNECTORS.some((c) => c.name === name)) {
      throw new Error(`Unknown connector in MCP_SEED_ONLY: ${name}`);
    }
  }
  return picked;
}

async function seedConnector(client, masterKey, cfg) {
  const name = slugify(cfg.name);
  if (!NAME_RE.test(name)) throw new Error(`Invalid connector name: ${cfg.name}`);

  const transport = cfg.transport ?? inferRemoteTransport(cfg.url);
  const token = process.env[cfg.tokenEnv]?.trim();
  if (cfg.requireToken && !token) {
    // Still register the URL so Connectors UI can show it; keep disabled until a key is set.
    await upsert(client, {
      name, url: cfg.url, transport, secrets: null, enabled: false,
    });
    return { action: "prepared-disabled", note: `set ${cfg.tokenEnv} then re-run (or paste Bearer in Connectors UI)` };
  }

  let secrets = null;
  if (token) {
    const headers = { Authorization: `Bearer ${token}` };
    if (cfg.defaultParameters && typeof cfg.defaultParameters === "object") {
      headers.DEFAULT_PARAMETERS = JSON.stringify(cfg.defaultParameters);
    }
    secrets = encrypt(JSON.stringify({ headers }), masterKey);
  }

  const action = await upsert(client, {
    name, url: cfg.url, transport, secrets, enabled: true,
  });
  return { action, note: token ? " (with auth token)" : "" };
}

async function upsert(client, { name, url, transport, secrets, enabled }) {
  await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
    `mcp:system:${name}:manual`,
  ]);

  const existing = await client.query(
    `UPDATE mcp_servers
     SET url = $1, transport = $2,
         secrets = CASE WHEN $3::text IS NULL THEN secrets ELSE $3 END,
         enabled = $4, auth_kind = 'token', updated_at = now()
     WHERE scope = 'system' AND name = $5 AND source = 'manual'
       AND user_id IS NULL AND project_id IS NULL
     RETURNING id`,
    [url, transport, secrets, enabled, name],
  );

  if (existing.rowCount > 0) return "updated";

  await client.query(
    `INSERT INTO mcp_servers (
       id, scope, user_id, project_id, name, transport, url, secrets,
       auth_kind, enabled, source
     ) VALUES ($1, 'system', NULL, NULL, $2, $3, $4, $5, 'token', $6, 'manual')`,
    [randomUUID(), name, transport, url, secrets, enabled],
  );
  return "inserted";
}

const pool = new Pool({ connectionString: DATABASE_URL });

try {
  const client = await pool.connect();
  try {
    const masterKey = await resolveMasterKey(client);
    for (const cfg of selectedConnectors()) {
      await client.query("BEGIN");
      try {
        const { action, note } = await seedConnector(client, masterKey, cfg);
        await client.query("COMMIT");
        console.log(`${action}: ${cfg.name} → ${cfg.url}${note ?? ""}`);
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      }
    }
  } finally {
    client.release();
  }
} finally {
  await pool.end();
}
