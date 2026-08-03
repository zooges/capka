import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

describe("mcp tool-cache", () => {
  let dir: string;
  let getCachedTools: typeof import("../tool-cache").getCachedTools;
  let setCachedTools: typeof import("../tool-cache").setCachedTools;
  let clearCachedTools: typeof import("../tool-cache").clearCachedTools;

  const tools = [{ name: "scan", description: "scan", inputSchema: { type: "object", properties: {} } }];

  beforeEach(async () => {
    dir = mkdtempSync(join(tmpdir(), "capka-mcp-cache-"));
    process.env.MCP_SCHEMA_CACHE_PATH = join(dir, "schemas.json");
    // Fresh module + globalThis so disk/memory state does not leak across tests.
    const g = globalThis as unknown as {
      __capkaMcpToolCache?: Map<string, unknown>;
      __capkaMcpToolCacheDiskLoaded?: boolean;
    };
    delete g.__capkaMcpToolCache;
    delete g.__capkaMcpToolCacheDiskLoaded;
    vi.resetModules();
    ({ getCachedTools, setCachedTools, clearCachedTools } = await import("../tool-cache"));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
    delete process.env.MCP_SCHEMA_CACHE_PATH;
  });

  it("returns undefined for an unknown server", () => {
    expect(getCachedTools("srv")).toBeUndefined();
  });

  it("stores and returns a server's tool schemas", () => {
    setCachedTools("srv", tools);
    expect(getCachedTools("srv")).toEqual(tools);
  });

  it("clears a server's cached tools", () => {
    setCachedTools("srv", tools);
    clearCachedTools("srv");
    expect(getCachedTools("srv")).toBeUndefined();
  });

  it("reloads schemas from disk after a fresh module load (survives duplicate bundles)", async () => {
    setCachedTools("srv", tools);
    const g = globalThis as unknown as {
      __capkaMcpToolCache?: Map<string, unknown>;
      __capkaMcpToolCacheDiskLoaded?: boolean;
    };
    delete g.__capkaMcpToolCache;
    delete g.__capkaMcpToolCacheDiskLoaded;
    vi.resetModules();
    const again = await import("../tool-cache");
    expect(again.getCachedTools("srv")).toEqual(tools);
  });
});
