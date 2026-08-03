import { tool, type Tool } from "ai";
import { z } from "zod";
import { isChinaRegion, isTavilySteerEnabled } from "@/lib/agents/chat-agent";
import { log } from "@/lib/log";

/**
 * Provider-agnostic progressive tool disclosure ("tool search").
 *
 * The problem: a single MCP connector can bring dozens of tools (Firecrawl ~28),
 * and every enabled connector's full schema is serialized into EVERY request —
 * the "menu tax" (see adapt.ts). It taxes context and, past a point, degrades the
 * model's tool choice. Anthropic ships a native `defer_loading` + tool-search
 * beta for this, but it rides the Messages API and would only help the Anthropic
 * path. Capka runs its own AI SDK loop across many providers, so we implement the
 * SAME pattern client-side, purely with ordinary function calling + the SDK's
 * `activeTools` lever — which works on any tool-capable model.
 *
 * How it works:
 *  - The model always sees the small "eager" core (sandbox, manage, ask, memory,
 *    skill, provider-native) plus this one `find_tool`. Connector tools are
 *    registered but kept OUT of `activeTools`, so their schemas never enter the
 *    request until needed.
 *  - A one-line-per-connector index in the system prompt tells the model what
 *    exists (so it can phrase a `find_tool` query), without paying per-tool cost.
 *  - `find_tool(query)` runs BM25 over the deferred tools' names+descriptions and
 *    marks the matches as expanded; `prepareStep` then adds them to `activeTools`
 *    for subsequent steps, so their full schemas arrive on demand.
 *
 * Cache: the tools block is serialized BEFORE system + messages, so changing
 * `activeTools` mid-turn invalidates the prompt cache for everything after it —
 * append-only does NOT preserve the conversation prefix. Its real value is
 * DETERMINISM: once the model has expanded what it needs, every later step of the
 * turn sees an identical tool set, so the rebuild happens exactly once (like the
 * one-off cost `stepSettings` already accepts for a late `toolChoice`), not once
 * per step.
 *
 * Gating: deferral kicks in when the connector tools' estimated cost exceeds
 * `min(percent of window, absolute ceiling)` — `MCP_DEFER_TOKEN_PCT` (default
 * 10%, Anthropic's `auto:N`) clamped by `MCP_DEFER_TOKEN_MAX` (default 8192).
 * The absolute cap matters on ~1M-token models: 10% of 1M is ~100k, so a
 * Firecrawl-scale block never deferred under percent-only gating. A small chat
 * with a couple of tools still stays eager — no index, no extra round-trip.
 */

export const FIND_TOOL_NAME = "find_tool";

/** Percentage of the effective context window the connector tool block may occupy
 *  before deferral kicks in. Matches Anthropic's `auto:N` default of ~10%.
 *  `0` means always defer (any non-empty MCP set). Do not use `|| 10` — that
 *  would treat an intentional `0` as "unset". */
const DEFER_PCT = (() => {
  const raw = process.env.MCP_DEFER_TOKEN_PCT;
  if (raw === undefined || raw === "") return 10;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : 10;
})();

/** Absolute token ceiling for the always-on connector tool block. Percent gating
 *  alone fails open on large windows; this keeps progressive disclosure useful
 *  without forcing `MCP_DEFER_TOKEN_PCT=0` (which always adds a find_tool hop).
 *  `0` disables the absolute cap (percent-only). Unset → 8192. */
const DEFER_MAX = (() => {
  const raw = process.env.MCP_DEFER_TOKEN_MAX;
  if (raw === undefined || raw === "") return 8192;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : 8192;
})();

/** Effective defer budget for this turn: percent of the window, optionally
 *  clamped by the absolute max. `thresholdPct === 0` → budget 0 (always defer). */
export function deferTokenBudget(effectiveLimit: number, thresholdPct = DEFER_PCT, maxTokens = DEFER_MAX): number {
  if (thresholdPct <= 0) return 0;
  const pctBudget = (effectiveLimit * thresholdPct) / 100;
  return maxTokens > 0 ? Math.min(pctBudget, maxTokens) : pctBudget;
}

/** How many tools a single `find_tool` call may surface by default. Generous on
 *  purpose: BM25 is lexical, so a synonym gap ("fetch page" vs "scrape") is real —
 *  recall matters more than precision here since the cost of a miss is a wasted
 *  round-trip, while a couple of extra loaded tools is cheap. */
const DEFAULT_FIND_LIMIT = 8;

/**
 * Connector servers (or exact `mcp__server__tool` names) that stay active even
 * when deferral is on — no `find_tool` hop. Comma-separated via `MCP_ALWAYS_LOAD`.
 * When unset/empty and `CAPKA_REGION=cn` / `CAPKA_CHINA=1`, defaults to `tavily`.
 * Set `MCP_ALWAYS_LOAD=none` (or `-` / `off`) to disable the China default.
 * (Compose often passes an empty string when the host var is unset — treat that
 * as unset, not as "explicitly none".)
 */
export function alwaysLoadMatchers(raw = process.env.MCP_ALWAYS_LOAD): string[] {
  const region = (process.env.CAPKA_REGION ?? "").trim().toLowerCase();
  const china = region === "cn" || region === "china" || process.env.CAPKA_CHINA === "1";
  const trimmed = raw?.trim();
  if (trimmed === "none" || trimmed === "-" || trimmed === "off") return [];
  if (trimmed) {
    return trimmed.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  }
  return china ? ["tavily"] : [];
}

/** True when a connector *server* name is listed in `MCP_ALWAYS_LOAD` (or China default). */
export function isAlwaysLoadServer(serverName: string, matchers = alwaysLoadMatchers()): boolean {
  if (matchers.length === 0) return false;
  const lower = serverName.toLowerCase();
  return matchers.some((m) => m === lower || m === `mcp__${lower}`);
}

function isAlwaysLoaded(name: string, matchers: string[]): boolean {
  if (matchers.length === 0) return false;
  const { server, short } = splitMcpName(name);
  const lower = name.toLowerCase();
  return matchers.some(
    (m) => m === server || m === short || m === lower || lower === `mcp__${m}` || short === m,
  );
}

/** The minimal shape planToolSearch reads from an assembled tool. Accepting this
 *  structural type (not the AI SDK `Tool`) lets the caller pass its precisely-typed
 *  tool map without a cast — `Tool` is invariant on its input-schema generic, so a
 *  concrete `{ bash: Tool<…>, … }` is not assignable to `Record<string, Tool>`. */
type ReadableTool = { description?: string; inputSchema?: unknown };

/** An MCP tool is any registered tool keyed `mcp__server__tool` (see mcpToolName).
 *  Everything else (sandbox/manage/ask/memory/skill/native) is eager core. */
const isMcpToolName = (name: string) => name.startsWith("mcp__");

/** `mcp__firecrawl__firecrawl_search` → { server: "firecrawl", short: "firecrawl_search" }. */
function splitMcpName(name: string): { server: string; short: string } {
  const rest = name.slice("mcp__".length);
  const i = rest.indexOf("__");
  return i === -1
    ? { server: rest, short: rest }
    : { server: rest.slice(0, i), short: rest.slice(i + 2) };
}

/**
 * BM25 is Latin-token only; Chinese-only queries used to match nothing.
 * Expand domain zh intents to English / server-name tokens that hit the right
 * connector names+descriptions. Tavily expansion is **only** for general
 * open-web search — never append "tavily" for legal / company / wechat / etc.
 *
 * Production China connectors (examples): yuandian-*, qcc-*, wx-article,
 * local-legal, law-theory, people-case-civil, tavily.
 */
function expandFindQuery(query: string): string {
  const extras: string[] = [];

  // Domain connectors first — these must not fall through to Tavily.
  if (/法律|法规|案例|判例|司法解释|元典|chineselaw|yuandian|立法|裁判|判决|条文|诉讼|民法|刑法/.test(query)) {
    extras.push("yuandian chineselaw local legal law theory people case civil statute judgment");
  }
  if (/企查查|工商|企业信息|企业查询|公司信息|公司注册|天眼查|qcc|company registry|高管|经营风险/.test(query)) {
    extras.push("qcc company executive operation risk registry business credit enterprise agent");
  }
  if (/微信|公众号|wechat|weixin|wx-?article/.test(query)) {
    extras.push("wx article wechat weixin");
  }

  // General open-web search only (not 查资料/检索 alone — those are often domain).
  if (
    extras.length === 0 &&
    /搜索网页|查网页|搜网页|上网|新闻|联网|网络搜索|公开互联网|公开网页|web search|search the web/.test(query)
  ) {
    extras.push("search the web tavily");
  } else if (
    extras.length === 0 &&
    /搜索|检索|查资料|找资料|搜一下|搜下|搜一搜|查一下|查下/.test(query) &&
    /网页|网站|网上|互联网|新闻|百度|必应|google|bing|tavily/.test(query)
  ) {
    extras.push("search the web tavily");
  }

  return extras.length === 0 ? query : `${query} ${extras.join(" ")}`;
}

/** Rough token estimate for a tool's serialized definition (name + description +
 *  input schema), chars/4. Precision is irrelevant here — this only decides
 *  whether the block is big enough to bother deferring. */
function estimateToolTokens(t: ReadableTool): number {
  let chars = 40 + (t.description?.length ?? 0); // name + JSON wrapper + description
  try {
    // dynamicTool wraps the raw schema under `.jsonSchema`; fall back to the value
    // itself. JSON.stringify(undefined) returns undefined → caught, description-only.
    const schema = t.inputSchema as { jsonSchema?: unknown } | undefined;
    chars += JSON.stringify(schema?.jsonSchema ?? schema).length;
  } catch {
    /* description-only estimate */
  }
  return Math.ceil(chars / 4);
}

// ── BM25 ────────────────────────────────────────────────────────────────────
// Compact BM25 over the deferred tools. Zero deps, synchronous, provider-agnostic
// — the same regex/keyword default Anthropic's tool-search ships. Search quality
// rides on tool descriptions (already length-clamped in adapt.ts), which is why a
// good description matters more once tools are discovered rather than always-on.

const K1 = 1.5;
const B = 0.75;

/** Lowercase, split on non-alphanumerics, and also break snake_case/camelCase so
 *  `firecrawl_search` and `getUserOrders` yield useful terms. Drops 1-char noise. */
function tokenize(text: string): string[] {
  return text
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2") // camelCase → camel Case
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 1);
}

interface Doc {
  name: string;
  description: string;
  terms: string[];
}

function bm25Search(docs: Doc[], query: string, limit: number): Doc[] {
  const qTerms = tokenize(query);
  if (qTerms.length === 0) return [];

  const avgLen = docs.reduce((s, d) => s + d.terms.length, 0) / (docs.length || 1);
  // Document frequency per query term.
  const df = new Map<string, number>();
  for (const term of new Set(qTerms)) {
    df.set(term, docs.filter((d) => d.terms.includes(term)).length);
  }

  const scored = docs.map((d) => {
    let score = 0;
    for (const term of qTerms) {
      const n = df.get(term) ?? 0;
      if (n === 0) continue;
      const idf = Math.log(1 + (docs.length - n + 0.5) / (n + 0.5));
      const tf = d.terms.filter((t) => t === term).length;
      const denom = tf + K1 * (1 - B + (B * d.terms.length) / (avgLen || 1));
      score += idf * ((tf * (K1 + 1)) / (denom || 1));
    }
    return { doc: d, score };
  });

  return scored
    .filter((s) => s.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((s) => s.doc);
}

// ── Plan ──────────────────────────────────────────────────────────────────────

export interface ToolSearchPlan {
  /** Whether deferral is active this turn. When false, every field below is inert
   *  and the caller behaves exactly as before (all tools active, no index). */
  defer: boolean;
  /** Index block for the system prompt (one line per connector). "" when !defer. */
  indexText: string;
  /** The `find_tool` to merge into the tool set. Empty record when !defer. */
  extraTools: Record<string, Tool>;
  /** `activeTools` for streamText / prepareStep. `undefined` when !defer, meaning
   *  "all tools active" (the SDK default). When deferring, returns the eager core
   *  + find_tool + whatever the model has expanded so far (append-only). */
  activeToolNames(): string[] | undefined;
}

const INERT_PLAN: ToolSearchPlan = {
  defer: false,
  indexText: "",
  extraTools: {},
  activeToolNames: () => undefined,
};

/**
 * Decide whether to defer connector tools this turn and, if so, build the
 * `find_tool`, the system-prompt index, and the active-tool accounting.
 *
 * `tools` is the fully assembled set (eager core + MCP). `effectiveLimit` is the
 * turn's context window after the admin cap (runner already computes it).
 */
export function planToolSearch(opts: {
  // Values may be `undefined` in the caller's union type (provider-native tools
  // exist only for some providers); MCP keys are always present at runtime.
  tools: Record<string, ReadableTool | undefined>;
  effectiveLimit: number;
  thresholdPct?: number;
  /** Absolute token ceiling; omit to use `MCP_DEFER_TOKEN_MAX` / default 8192. */
  maxTokens?: number;
}): ToolSearchPlan {
  const mcpNames = Object.keys(opts.tools).filter(isMcpToolName);
  if (mcpNames.length === 0) return INERT_PLAN;

  const mcpTokens = mcpNames.reduce((s, n) => s + estimateToolTokens(opts.tools[n]!), 0);
  const budget = deferTokenBudget(opts.effectiveLimit, opts.thresholdPct ?? DEFER_PCT, opts.maxTokens ?? DEFER_MAX);
  if (mcpTokens <= budget) return INERT_PLAN;

  // Decision is made ONCE, at the start of the turn, off the connector set as it
  // stands now — it never flips mid-turn. Logged so a chat that silently crosses
  // the threshold (e.g. the user just added a connector via `manage`) is visible.
  log.info("mcp.defer", { tools: mcpNames.length, estTokens: mcpTokens, budget: Math.round(budget) });

  const eagerNames = Object.keys(opts.tools).filter((n) => !isMcpToolName(n));
  const sortedMcp = [...mcpNames].sort();
  const alwaysMatchers = alwaysLoadMatchers();
  const alwaysOn = sortedMcp.filter((n) => isAlwaysLoaded(n, alwaysMatchers));

  // Deterministic catalog (sorted) so BM25 and the index are stable turn to turn.
  // BM25 indexes the server name + SHORT NAME as well as its description: names are
  // always English and snake_case-tokenized (generate_image → generate, image), so an
  // English query still matches a connector whose description is in another
  // language (e.g. a Ukrainian-described image server) — the cross-lingual floor.
  const docs: Doc[] = sortedMcp.map((name) => {
    const { server, short } = splitMcpName(name);
    const description = opts.tools[name]?.description ?? "";
    return { name, description, terms: tokenize(`${server} ${short} ${description}`) };
  });

  // ── System-prompt index: one line per connector — NAME + tool count only.
  //    Capability essays / per-family gists used to inflate the stable prompt by
  //    hundreds of tokens on every deferred turn; BM25 still searches full
  //    descriptions when the model calls find_tool. Always-loaded servers are
  //    called out so the model knows they need no find_tool hop. ───────────────
  const byServer = new Map<string, number>();
  for (const name of sortedMcp) {
    const { server } = splitMcpName(name);
    byServer.set(server, (byServer.get(server) ?? 0) + 1);
  }
  const alwaysServers = new Set(alwaysOn.map((n) => splitMcpName(n).server));
  // Soften Tavily-first index/find_tool copy only on China hosts with steer off.
  // Non-China always-load of tavily keeps the original "already configured" hints.
  const tavilySoft = isChinaRegion() && !isTavilySteerEnabled();
  const serverLines = [...byServer.entries()].map(([server, n]) => {
    const count = `${n} tool${n === 1 ? "" : "s"}`;
    if (alwaysServers.has(server)) {
      const hint =
        server === "tavily"
          ? tavilySoft
            ? "; optional general web search — already loaded if you want it; open curl/Google/Bing also OK; not for legal/company/wechat"
            : "; general web search only — already configured, call mcp__tavily__tavily_search now (never install / find_tool); not for legal/company/wechat"
          : "; already loaded — use directly";
      return `- **${server}** (${count}${hint})`;
    }
    return `- **${server}** (${count})`;
  });
  const alwaysIntro = tavilySoft
    ? `Connectors marked "use directly" / "already loaded" are available without \`${FIND_TOOL_NAME}\`. Tavily (if listed) is **optional** general web search — not mandatory; open \`curl\`/Google/Bing/Baidu are fine. Do not use Tavily for 法律/案例/元典/企查查/微信文章. For deferred domain connectors (chineselaw, wechat-article, company registry, …), call \`${FIND_TOOL_NAME}\` with a short need description first. Do not guess deferred tool names.`
    : `Connectors marked "use directly" / "already configured" are loaded — call their \`mcp__…\` tools now. Tavily is **general web search only** (\`mcp__tavily__tavily_search\`) — do not use it for 法律/案例/元典/企查查/微信文章. Do not install always-loaded connectors, do not \`find_tool\` for them. For other connectors (chineselaw, wechat-article, company registry, …), call \`${FIND_TOOL_NAME}\` with a short need description first (Chinese or English domain keywords are fine). Do not guess deferred tool names.`;
  const indexText = [
    "## Connector tools (on demand)",
    alwaysOn.length > 0
      ? alwaysIntro
      : `Call \`${FIND_TOOL_NAME}\` with a short need description before any connector tool. Do not guess tool names.`,
    "Connectors:",
    ...serverLines,
  ].join("\n");

  // ── find_tool: BM25 over the deferred catalog; matches become active next step.
  // Always-load matchers start expanded so hot tools (e.g. tavily on China deploys)
  // skip the discovery hop.
  const expanded = new Set<string>(alwaysOn);
  if (alwaysOn.length > 0) {
    log.info("mcp.always_load", { tools: alwaysOn });
  }
  const findTool = tool({
    description:
      "Discover connector tools that are not yet loaded. Pass a short natural-language description of the capability you need " +
      "(e.g. \"chineselaw 案例\", \"wechat article\", \"company registry 企查查\", \"read a PDF from a URL\"). Returns the best-matching tools; they become callable on your next step. " +
      "Chinese or English domain keywords are fine. " +
      (tavilySoft
        ? "General open-web search may use sandbox curl/Google/Bing; Tavily is optional if loaded. "
        : "Do NOT use this for Tavily / general web search when the prompt marks tavily as already configured — call \`mcp__tavily__tavily_search\` directly. ") +
      "Do use this for deferred domain connectors (legal, company registry, wechat, …) — never substitute Tavily for those. " +
      "Call this before using any deferred connector listed under \"Connector tools\" in the system prompt.",
    inputSchema: z.object({
      query: z.string().describe("What you want to do, in a few words"),
      limit: z.number().int().min(1).max(15).optional().describe("Max tools to return (default 5)"),
    }),
    execute: async ({ query, limit }) => {
      const expandedQuery = expandFindQuery(query);
      const hits = bm25Search(docs, expandedQuery, limit ?? DEFAULT_FIND_LIMIT);
      // Telemetry: query → matches. The only lever for tuning BM25, the sample
      // breadth, and the defer threshold — without it none of these is observable.
      log.info("mcp.find_tool", {
        query,
        expandedQuery: expandedQuery !== query ? expandedQuery : undefined,
        matched: hits.map((h) => h.name),
      });
      if (hits.length === 0) {
        return {
          matched: [],
          message: `No connector tools matched "${query}". Available connectors:\n${serverLines.join("\n")}`,
        };
      }
      for (const h of hits) expanded.add(h.name);
      return {
        matched: hits.map((h) => ({ name: h.name, description: h.description })),
        message: "These tools are now callable. Call the one you need on your next step.",
      };
    },
  });

  return {
    defer: true,
    indexText,
    extraTools: { [FIND_TOOL_NAME]: findTool },
    activeToolNames: () => [...eagerNames, FIND_TOOL_NAME, ...expanded],
  };
}
