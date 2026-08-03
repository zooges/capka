/**
 * DeepSeek V4 DSML (DeepSeek Markup Language) tool-call recovery.
 *
 * When an OpenAI-compatible gateway (LiteLLM, raw /v1, …) does not parse V4's
 * proprietary DSML into structured `tool_calls`, the model emits raw markup in
 * assistant text — Capka then shows protocol garbage instead of running tools.
 *
 * Official shape (encoding/README.md):
 *   <｜DSML｜tool_calls>
 *   <｜DSML｜invoke name="tool">
 *   <｜DSML｜parameter name="arg" string="true">value</｜DSML｜parameter>
 *   </｜DSML｜invoke>
 *   </｜DSML｜tool_calls>
 *
 * Applied as LanguageModelMiddleware (same pattern as extractReasoningMiddleware)
 * so streamText's multi-step loop receives real tool-call parts and executes them.
 */
import type {
  LanguageModelV3Content,
  LanguageModelV3StreamPart,
  LanguageModelV3ToolCall,
} from "@ai-sdk/provider";
import type { LanguageModelMiddleware } from "ai";
import { generateId } from "ai";

/** Fast sentinel — skip regex when absent. Covers fullwidth, ASCII, and spaced forms. */
export function looksLikeDsml(text: string): boolean {
  return (
    text.includes("DSML") &&
    (/<[\s|｜]*DSML[\s|｜]/.test(text) || text.includes("｜DSML｜") || text.includes("|DSML|"))
  );
}

export type ParsedDsmlToolCall = {
  toolName: string;
  input: Record<string, unknown>;
};

/**
 * Parse DSML invoke blocks from text. Returns cleaned text (DSML removed) and
 * structured tool calls. Tolerates truncated / malformed blocks by stripping
 * residual DSML tags so users never see protocol markup.
 */
export function parseDsmlToolCalls(text: string): {
  text: string;
  toolCalls: ParsedDsmlToolCall[];
} {
  if (!looksLikeDsml(text)) return { text, toolCalls: [] };

  const toolCalls: ParsedDsmlToolCall[] = [];

  // Prefer the outer tool_calls / function_calls wrapper; fall back to bare invoke.
  const blockRe = new RegExp(
    `<\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*(?:tool_calls|function_calls)\\b[^>]*>` +
      `([\\s\\S]*?)` +
      `(?:<\\s*/\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*(?:tool_calls|function_calls)\\s*>|$)`,
    "gi",
  );

  let working = text;
  const blocks: string[] = [];
  working = working.replace(blockRe, (_m, inner: string) => {
    blocks.push(inner);
    return "";
  });

  // Bare invoke blocks left outside a wrapper (partial leak / truncated close).
  const bareInvoke = new RegExp(
    `<\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*invoke\\b[^>]*>[\\s\\S]*?(?:<\\s*/\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*invoke\\s*>|$)`,
    "gi",
  );
  working = working.replace(bareInvoke, (m) => {
    blocks.push(m);
    return "";
  });

  for (const block of blocks) {
    const invokeRe = new RegExp(
      `<\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*invoke\\b([^>]*)>` +
        `([\\s\\S]*?)` +
        `(?:<\\s*/\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*invoke\\s*>|$)`,
      "gi",
    );
    let inv: RegExpExecArray | null;
    while ((inv = invokeRe.exec(block)) !== null) {
      const nameAttr = /name\s*=\s*["']([^"']+)["']/i.exec(inv[1] ?? "");
      const toolName = nameAttr?.[1]?.trim();
      if (!toolName) continue;

      const body = inv[2] ?? "";
      const input: Record<string, unknown> = {};
      const paramRe = new RegExp(
        `<\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*parameter\\b([^>]*)>` +
          `([\\s\\S]*?)` +
          `<\\s*/\\s*[|｜]+\\s*DSML\\s*[|｜]+\\s*parameter\\s*>`,
        "gi",
      );
      let pm: RegExpExecArray | null;
      while ((pm = paramRe.exec(body)) !== null) {
        const attrs = pm[1] ?? "";
        const rawVal = (pm[2] ?? "").trim();
        const pName = /name\s*=\s*["']([^"']+)["']/i.exec(attrs)?.[1];
        if (!pName) continue;
        const isString = /string\s*=\s*["']true["']/i.test(attrs);
        if (isString) {
          input[pName] = rawVal;
        } else {
          try {
            input[pName] = JSON.parse(rawVal);
          } catch {
            input[pName] = rawVal;
          }
        }
      }

      // No <parameter> tags — treat remaining body as a single string arg when
      // it looks like Python/code (common truncated DSML for execute_python).
      if (Object.keys(input).length === 0 && body.trim()) {
        const code = body.trim();
        if (toolName === "execute_python" || toolName === "execute_bash" || toolName === "execute_node") {
          input[toolName === "execute_bash" ? "command" : "code"] = code;
        } else {
          input.input = code;
        }
      }

      toolCalls.push({ toolName, input });
    }
  }

  // Strip any leftover DSML tags so protocol never reaches the user.
  working = stripResidualDsml(working).replace(/\n{3,}/g, "\n\n").trim();

  return { text: working, toolCalls };
}

/** Remove residual DSML open/close tags (and orphaned fragments) from display text. */
export function stripResidualDsml(text: string): string {
  if (!looksLikeDsml(text)) return text;
  return text
    .replace(/<\s*\/?\s*[|｜]+\s*DSML\s*[|｜]+\s*[^>]*>/gi, "")
    .replace(/<\s*[|｜]+\s*DSML\s*[|｜][^>]*/gi, "")
    .trim();
}

function toV3ToolCalls(calls: ParsedDsmlToolCall[]): LanguageModelV3ToolCall[] {
  return calls.map((c) => ({
    type: "tool-call" as const,
    toolCallId: `dsml_${generateId()}`,
    toolName: c.toolName,
    input: JSON.stringify(c.input),
  }));
}

/**
 * Middleware: turn DSML-in-text into structured tool-call content so Capka's
 * agent loop executes them. No-op when the provider already emits tool_calls.
 */
export function extractDsmlToolMiddleware(): LanguageModelMiddleware {
  return {
    specificationVersion: "v3",

    wrapGenerate: async ({ doGenerate }) => {
      const result = await doGenerate();
      const { content, finishReason, ...rest } = result;

      const transformed: LanguageModelV3Content[] = [];
      let extracted = 0;

      for (const part of content) {
        if (part.type !== "text") {
          transformed.push(part);
          continue;
        }
        const { text, toolCalls } = parseDsmlToolCalls(part.text);
        if (toolCalls.length === 0) {
          transformed.push(part);
          continue;
        }
        extracted += toolCalls.length;
        if (text) transformed.push({ type: "text", text });
        transformed.push(...toV3ToolCalls(toolCalls));
      }

      const nextFinish =
        extracted > 0 && (finishReason.unified === "stop" || finishReason.unified === "other")
          ? { unified: "tool-calls" as const, raw: finishReason.raw }
          : finishReason;

      return {
        ...rest,
        content: transformed,
        finishReason: nextFinish,
      };
    },

    wrapStream: async ({ doStream }) => {
      const { stream, ...rest } = await doStream();

      // Per text-block buffer. We only hold back deltas once a DSML sentinel
      // appears; otherwise stream through unchanged (zero latency).
      type Buf = {
        id: string;
        text: string;
        holding: boolean;
        startEmitted: boolean;
      };
      const buffers = new Map<string, Buf>();
      let emittedToolCalls = 0;

      const flushText = (
        buf: Buf,
        controller: TransformStreamDefaultController<LanguageModelV3StreamPart>,
        end: boolean,
      ) => {
        const { text, toolCalls } = parseDsmlToolCalls(buf.text);
        if (toolCalls.length > 0) {
          emittedToolCalls += toolCalls.length;
          if (text) {
            if (!buf.startEmitted) {
              controller.enqueue({ type: "text-start", id: buf.id });
              buf.startEmitted = true;
            }
            controller.enqueue({ type: "text-delta", id: buf.id, delta: text });
          }
          if (buf.startEmitted) {
            controller.enqueue({ type: "text-end", id: buf.id });
            buf.startEmitted = false;
          }
          for (const tc of toV3ToolCalls(toolCalls)) {
            controller.enqueue({
              type: "tool-input-start",
              id: tc.toolCallId,
              toolName: tc.toolName,
            });
            controller.enqueue({
              type: "tool-input-delta",
              id: tc.toolCallId,
              delta: tc.input,
            });
            controller.enqueue({ type: "tool-input-end", id: tc.toolCallId });
            controller.enqueue(tc);
          }
        } else {
          const clean = stripResidualDsml(buf.text);
          if (clean) {
            if (!buf.startEmitted) {
              controller.enqueue({ type: "text-start", id: buf.id });
              buf.startEmitted = true;
            }
            controller.enqueue({ type: "text-delta", id: buf.id, delta: clean });
          }
          if (end && buf.startEmitted) {
            controller.enqueue({ type: "text-end", id: buf.id });
            buf.startEmitted = false;
          }
        }
        buf.text = "";
        buf.holding = false;
      };

      return {
        stream: stream.pipeThrough(
          new TransformStream<LanguageModelV3StreamPart, LanguageModelV3StreamPart>({
            transform(chunk, controller) {
              if (chunk.type === "text-start") {
                buffers.set(chunk.id, {
                  id: chunk.id,
                  text: "",
                  holding: false,
                  startEmitted: false,
                });
                // Defer text-start until we know whether this block is DSML.
                return;
              }

              if (chunk.type === "text-delta") {
                let buf = buffers.get(chunk.id);
                if (!buf) {
                  buf = { id: chunk.id, text: "", holding: false, startEmitted: false };
                  buffers.set(chunk.id, buf);
                }
                buf.text += chunk.delta;

                if (!buf.holding && looksLikeDsml(buf.text)) {
                  buf.holding = true;
                  return;
                }
                if (buf.holding) return;

                // Live path: forward immediately.
                if (!buf.startEmitted) {
                  controller.enqueue({ type: "text-start", id: buf.id });
                  buf.startEmitted = true;
                }
                controller.enqueue({ type: "text-delta", id: buf.id, delta: chunk.delta });
                // Keep only a small tail for sentinel detection across chunk boundaries.
                if (buf.text.length > 32) buf.text = buf.text.slice(-32);
                return;
              }

              if (chunk.type === "text-end") {
                const buf = buffers.get(chunk.id);
                if (!buf) {
                  controller.enqueue(chunk);
                  return;
                }
                if (buf.holding || looksLikeDsml(buf.text)) {
                  flushText(buf, controller, true);
                } else if (buf.startEmitted) {
                  controller.enqueue(chunk);
                }
                buffers.delete(chunk.id);
                return;
              }

              if (chunk.type === "finish") {
                // Flush any held text blocks before finish.
                for (const buf of buffers.values()) {
                  if (buf.holding || looksLikeDsml(buf.text)) {
                    flushText(buf, controller, true);
                  } else if (buf.text && !buf.startEmitted) {
                    // Unlikely: deltas without start — emit cleanly.
                    controller.enqueue({ type: "text-start", id: buf.id });
                    controller.enqueue({ type: "text-delta", id: buf.id, delta: buf.text });
                    controller.enqueue({ type: "text-end", id: buf.id });
                  }
                }
                buffers.clear();
                const finishReason =
                  emittedToolCalls > 0 &&
                  (chunk.finishReason.unified === "stop" || chunk.finishReason.unified === "other")
                    ? { unified: "tool-calls" as const, raw: chunk.finishReason.raw }
                    : chunk.finishReason;
                controller.enqueue({ ...chunk, finishReason });
                return;
              }

              controller.enqueue(chunk);
            },
          }),
        ),
        ...rest,
      };
    },
  };
}
