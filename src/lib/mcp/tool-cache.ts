import { mkdirSync, readFileSync, writeFileSync, unlinkSync, existsSync } from "fs";
import { dirname } from "path";

/**
 * Cache of each MCP server's tool SCHEMAS, keyed by server id.
 *
 * A server's tool list is a property of the server, not of the user or the run,
 * so it's the same for everyone and stable between turns. Caching it lets
 * `loadMcpTools` declare a connector's tools to the model WITHOUT connecting —
 * which, for a stdio connector, means without spinning the sandbox and waiting on
 * an `npx`/`uvx` self-install on the critical path of every turn. The real
 * connection is then established lazily, only when the model actually calls one of
 * the tools. A cold cache is warmed in the background (see load.ts).
 *
 * Storage is deliberately belt-and-braces:
 *  - `globalThis` — Next.js can evaluate this module more than once in one
 *    process (same pattern as `worker.ts` / `realtime.ts`); a plain module-level
 *    `Map` would miss every turn and re-dial every HTTP MCP on the TTFT path.
 *  - Disk under `/tmp` (or `MCP_SCHEMA_CACHE_PATH`) — shared across those
 *    duplicate module instances and survives soft reloads within a container.
 *    Lost on container recreate; the next turn background-warms again.
 */
export interface CachedTool {
  name: string;
  description?: string;
  inputSchema?: Record<string, unknown>;
}

type CacheStore = Map<string, CachedTool[]>;

const g = globalThis as unknown as { __capkaMcpToolCache?: CacheStore; __capkaMcpToolCacheDiskLoaded?: boolean };
const cache: CacheStore = (g.__capkaMcpToolCache ??= new Map());

/** Override in tests / odd layouts. Default: container-local tmp (writable by the
 *  non-root `nextjs` user; `/app/data` is root-owned on the compose volume).
 *  Keep this a plain string — `path.join(process.cwd(), …)` makes Turbopack NFT
 *  think the whole project tree is an asset dependency. */
function diskPath(): string {
  return process.env.MCP_SCHEMA_CACHE_PATH || "/tmp/capka-mcp-tool-schemas.json";
}

function loadDiskOnce(): void {
  if (g.__capkaMcpToolCacheDiskLoaded) return;
  g.__capkaMcpToolCacheDiskLoaded = true;
  try {
    const p = diskPath();
    if (!existsSync(p)) return;
    const raw = JSON.parse(readFileSync(p, "utf8")) as Record<string, CachedTool[]>;
    for (const [id, tools] of Object.entries(raw)) {
      if (Array.isArray(tools) && tools.length > 0 && !cache.has(id)) cache.set(id, tools);
    }
  } catch {
    /* corrupt / unreadable — ignore; background warm will refill */
  }
}

function persistDisk(): void {
  try {
    const p = diskPath();
    mkdirSync(dirname(p), { recursive: true });
    const obj: Record<string, CachedTool[]> = {};
    for (const [id, tools] of cache) obj[id] = tools;
    writeFileSync(p, JSON.stringify(obj));
  } catch {
    /* /tmp full or read-only — memory cache still works for this process */
  }
}

export function getCachedTools(serverId: string): CachedTool[] | undefined {
  loadDiskOnce();
  return cache.get(serverId);
}

export function setCachedTools(serverId: string, tools: CachedTool[]): void {
  loadDiskOnce();
  cache.set(serverId, tools);
  persistDisk();
}

export function clearCachedTools(serverId: string): void {
  loadDiskOnce();
  cache.delete(serverId);
  if (cache.size === 0) {
    try {
      const p = diskPath();
      if (existsSync(p)) unlinkSync(p);
    } catch { /* ignore */ }
  } else {
    persistDisk();
  }
}
