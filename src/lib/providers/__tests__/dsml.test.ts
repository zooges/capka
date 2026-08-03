import { describe, it, expect } from "vitest";
import { looksLikeDsml, parseDsmlToolCalls, stripResidualDsml } from "../dsml";

const SAMPLE = `<｜DSML｜tool_calls>
<｜DSML｜invoke name="execute_python">
<｜DSML｜parameter name="code" string="true">import datetime
print(datetime.datetime.now())</｜DSML｜parameter>
</｜DSML｜invoke>
</｜DSML｜tool_calls>`;

describe("parseDsmlToolCalls", () => {
  it("parses official DeepSeek V4 invoke/parameter DSML", () => {
    const { text, toolCalls } = parseDsmlToolCalls(`I'll look that up.\n${SAMPLE}`);
    expect(toolCalls).toHaveLength(1);
    expect(toolCalls[0].toolName).toBe("execute_python");
    expect(toolCalls[0].input).toEqual({
      code: "import datetime\nprint(datetime.datetime.now())",
    });
    expect(text).toBe("I'll look that up.");
    expect(looksLikeDsml(text)).toBe(false);
  });

  it("parses ASCII-spaced DSML variants seen in leaked UI text", () => {
    const raw =
      `< | DSML | tool_calls> < | DSML | invoke name="execute_bash">` +
      `< | DSML | parameter name="command" string="true">curl -sL 'https://www.bing.com/search?q=news'</ | DSML | parameter>` +
      `</ | DSML | invoke></ | DSML | tool_calls>`;
    const { toolCalls, text } = parseDsmlToolCalls(raw);
    expect(toolCalls).toHaveLength(1);
    expect(toolCalls[0].toolName).toBe("execute_bash");
    expect(String(toolCalls[0].input.command)).toContain("bing.com");
    expect(text).toBe("");
  });

  it("parses non-string JSON parameters", () => {
    const raw = `<｜DSML｜tool_calls>
<｜DSML｜invoke name="read_file">
<｜DSML｜parameter name="path" string="true">/workspace/a.txt</｜DSML｜parameter>
<｜DSML｜parameter name="offset" string="false">10</｜DSML｜parameter>
</｜DSML｜invoke>
</｜DSML｜tool_calls>`;
    const { toolCalls } = parseDsmlToolCalls(raw);
    expect(toolCalls[0].input).toEqual({ path: "/workspace/a.txt", offset: 10 });
  });

  it("strips unparseable residual DSML so users never see protocol markup", () => {
    const leaked = `Sorry.<｜DSML｜tool_calls> <｜DSML｜invoke name="execute_python"> datetime beijing`;
    const cleaned = stripResidualDsml(leaked);
    expect(cleaned).not.toMatch(/DSML/);
    expect(cleaned).toContain("Sorry");
  });

  it("is a no-op on ordinary assistant prose", () => {
    const prose = "Here are today's headlines from Bing.";
    expect(parseDsmlToolCalls(prose)).toEqual({ text: prose, toolCalls: [] });
  });
});
