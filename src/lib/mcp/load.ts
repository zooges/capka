import type { Tool } from "ai";
import { getBlockPrivateProviderUrls } from "@/lib/settings";
import { log } from "@/lib/log";
import { connectMcpServer, disconnectMcp, type ConnectedMcp } from "./client";
import { adaptMcpTool, mcpToolName } from "./adapt";
import { listEnabledServerConfigs } from "./service";
import { recordConnectError, clearConnectError, recentlyFailed } from "./connect-errors";
import { getCachedTools, setCachedTools } from "./tool-cache";
import { hasUserTokens } from "./oauth/store";
import { McpOAuthProvider } from "./oauth/provider";
import { needsPluginRoot, resolvePluginRoot } from "./plugin-runtime";
import { alwaysLoadMatchers, isAlwaysLoadServer } from "./tool-search";
import type { McpServerConfig } from "./types";

/** Don't re-dial a connector that failed recently — one broken server shouldn't
 *  re-spend its connect cost every turn. Gates the background schema warm; a lazy
 *  connect triggered by an actual tool call is never blocked (the model chose to
 *  use it). 10 min matches the connect-error TTL the UI shows, so a persistently
 *  broken connector is retried rarely, not every minute. A config edit or a
 *  successful connect clears it immediately. */
const CONNECT_BACKOFF_MS = 10 * 60_000;

const cacheKey = (c: McpServerConfig) => c.id ?? c.name;

/**
 * Build the agent's MCP tool set for a run — WITHOUT putting a slow connector on
 * the critical path of time-to-first-token (except always-load servers below).
 *
 * Both **http/sse** and **stdio** connectors are served from an in-process schema
 * cache and connected LAZILY (first tool call). A cold cache is warmed in the
 * background (schema-only: dial → listTools → hang up) so tools appear from the
 * next turn — never blocking this one, and never holding live sessions during the
 * LLM stream. Cloudflare-hosted MCP `initialize` routinely costs 1–2s each; with
 * several enabled connectors an eager await used to tax every turn even when tools
 * were deferred and never called. stdio is the slower case (`docker exec` + npx).
 *
 * **Always-load** (`MCP_ALWAYS_LOAD`, China default `tavily`): cold → await connect
 * so tools exist on this turn; warm cache → register immediately and pre-dial so
 * the first `callTool` reuses the live session. Other connectors stay lazy.
 *
 * Tools are collected in deterministic order (servers by name, tools by name) so
 * the position-0 tool prefix stays cache-stable for prompt caching. A server that
 * fails to connect is logged + skipped — never fatal — and its error is recorded
 * for the connectors UI to surface (G1 governance still applies via isServerAllowed).
 */
export async function loadMcpTools(opts: {
  userId: string;
  projectId: string | null;
  /** The run's sandbox session — required to bridge stdio connectors. */
  sessionKey?: string;
  /** Shared, memoized session creator. A stdio connector runs via `docker exec`
   *  inside the sandbox, so the container must exist before we connect — the lazy
   *  connect calls this first. http/sse connectors don't need it. */
  ensureSession?: () => Promise<unknown>;
  /** Governance gate — a denied connector is never connected (G1). */
  isServerAllowed?: (name: string) => boolean;
  /** Present during a live turn: lets a connector elicit input from the user
   *  mid-tool-call (block-and-poll). Omitted for background cache warms. */
  elicitContext?: import("./client").ElicitContext;
}): Promise<{
  tools: Record<string, Tool>;
  close: () => Promise<void>;
  /** Resolves when background cache-warms finish. The runner ignores it; tests
   *  await it to observe the warm deterministically. */
  warming: Promise<unknown>;
}> {
  const allow = opts.isServerAllowed ?? (() => true);
  // Passed to every adapted tool so an oversized result can be parked in the
  // workspace (off-disk via the controller file API — no container needed).
  const spillCtx = { sessionKey: opts.sessionKey, userId: opts.userId };
  const configs = (await listEnabledServerConfigs(opts.userId, opts.projectId))
    .filter((c) => allow(c.name))
    .sort((a, b) => a.name.localeCompare(b.name));

  const blockPrivate = await getBlockPrivateProviderUrls();
  const connected: ConnectedMcp[] = [];
  const tools: Record<string, Tool> = {};
  const warmups: Promise<unknown>[] = [];

  // One connection per server, memoized, so a server's tools share a single
  // (slow, for stdio) connection. Held for the whole run and torn down in close().
  // Schema warms below deliberately bypass this map so they never leave a dead
  // client in the memo after hanging up.
  const connections = new Map<string, Promise<ConnectedMcp>>();
  const connect = (c: McpServerConfig): Promise<ConnectedMcp> => {
    const k = cacheKey(c);
    let p = connections.get(k);
    if (!p) {
      p = (async () => {
        // stdio: its server is `docker exec`'d into the sandbox (and a plugin's
        // files are materialized via exec), so the container must exist first.
        if (c.transport === "stdio" && opts.ensureSession) await opts.ensureSession();
        const authProvider = c.authKind === "oauth" && c.id
          ? new McpOAuthProvider(opts.userId, c.id, "runtime")
          : undefined;
        const cfg = opts.sessionKey && needsPluginRoot(c)
          ? await resolvePluginRoot(opts.sessionKey, c)
          : c;
        const conn = await connectMcpServer(cfg, { blockPrivate, authProvider, sessionKey: opts.sessionKey, elicitContext: opts.elicitContext });
        connected.push(conn);
        setCachedTools(k, conn.tools); // refresh the schema cache for next turn
        clearConnectError(opts.userId, c.id);
        return conn;
      })().catch((e) => {
        // Let a later consumer in the same run retry, and surface WHY in the UI.
        connections.delete(k);
        recordConnectError(opts.userId, c.id, e instanceof Error ? e.message : String(e));
        throw e;
      });
      connections.set(k, p);
    }
    return p;
  };

  // Schema-only warm: dial → listTools → hang up. Populates the in-process cache
  // for the NEXT turn without holding a live session through the LLM stream, and
  // without sharing the turn's connection memo (a hung-up client must not be reused).
  const warmSchema = async (c: McpServerConfig): Promise<void> => {
    try {
      if (c.transport === "stdio" && opts.ensureSession) await opts.ensureSession();
      const authProvider = c.authKind === "oauth" && c.id
        ? new McpOAuthProvider(opts.userId, c.id, "runtime")
        : undefined;
      const cfg = opts.sessionKey && needsPluginRoot(c)
        ? await resolvePluginRoot(opts.sessionKey, c)
        : c;
      // No elicitContext: warms never surface mid-call questions.
      const conn = await connectMcpServer(cfg, { blockPrivate, authProvider, sessionKey: opts.sessionKey });
      setCachedTools(cacheKey(c), conn.tools);
      clearConnectError(opts.userId, c.id);
      await disconnectMcp(conn).catch(() => {});
    } catch (e) {
      recordConnectError(opts.userId, c.id, e instanceof Error ? e.message : String(e));
    }
  };

  // A lazy MCP client: it connects on the first tool call, then delegates. Shared
  // across all of a server's tools via the memoized `connect`.
  const lazyCaller = (c: McpServerConfig) => ({
    callTool: async (
      params: { name: string; arguments: Record<string, unknown> },
      resultSchema?: undefined,
      options?: { signal?: AbortSignal },
    ) => (await connect(c)).client.callTool(params, resultSchema, options),
  });

  // http + stdio share the same path: cache → declare + lazy connect; cold →
  // background schema warm (never await on the TTFT path). Always-load servers
  // are the exception (see loop). OAuth without a token is skipped entirely (a
  // connect would only 401 and arm a backoff that hid the connector after the
  // user signed in).
  const t0 = Date.now();
  let fromCache = 0;
  let cold = 0;
  let alwaysEager = 0;
  const alwaysMatchers = alwaysLoadMatchers();
  for (const c of configs) {
    if (c.authKind === "oauth" && c.id && !(await hasUserTokens(opts.userId, c.id))) continue;
    if (c.id && recentlyFailed(opts.userId, c.id, CONNECT_BACKOFF_MS)) continue;
    const always = isAlwaysLoadServer(c.name, alwaysMatchers);
    const cached = getCachedTools(cacheKey(c));

    if (always) {
      // Hot path (China Tavily): tools must be callable this turn, and the HTTP
      // session should already be open when the model first searches.
      if (cached) {
        fromCache++;
        alwaysEager++;
        const caller = lazyCaller(c);
        for (const mt of [...cached].sort((a, b) => a.name.localeCompare(b.name))) {
          tools[mcpToolName(c.name, mt.name)] = adaptMcpTool(caller, c.name, mt, spillCtx);
        }
        // Pre-dial without awaiting TTFT — memoized connect finishes while the
        // model thinks; first callTool reuses the live client.
        void connect(c).catch(() => {});
      } else {
        cold++;
        alwaysEager++;
        try {
          const conn = await connect(c);
          for (const mt of [...conn.tools].sort((a, b) => a.name.localeCompare(b.name))) {
            tools[mcpToolName(c.name, mt.name)] = adaptMcpTool(lazyCaller(c), c.name, mt, spillCtx);
          }
        } catch {
          // connect() already recorded the error; skip tools this turn.
        }
      }
      continue;
    }

    if (cached) {
      fromCache++;
      const caller = lazyCaller(c);
      for (const mt of [...cached].sort((a, b) => a.name.localeCompare(b.name))) {
        tools[mcpToolName(c.name, mt.name)] = adaptMcpTool(caller, c.name, mt, spillCtx);
      }
    } else {
      cold++;
      warmups.push(warmSchema(c));
    }
  }
  log.info("mcp.load", {
    ms: Date.now() - t0,
    servers: configs.length,
    fromCache,
    cold,
    alwaysEager,
    tools: Object.keys(tools).length,
  });

  const warming = Promise.allSettled(warmups);
  return {
    tools,
    warming,
    close: async () => {
      // Only tear down connections held for real tool calls. Schema warms hang up
      // themselves and must NOT be awaited here — otherwise a slow Cloudflare warm
      // would block the worker between turns even after the reply finished.
      await Promise.allSettled(connected.map(disconnectMcp));
    },
  };
}
