import { describe, it, expect } from "vitest";
import { inferRemoteTransport } from "../types";

describe("inferRemoteTransport", () => {
  it("defaults to Streamable HTTP", () => {
    expect(inferRemoteTransport("https://mcp.example.com/mcp")).toBe("http");
    expect(inferRemoteTransport("http://chineselaw-mcp:8317/mcp")).toBe("http");
  });

  it("detects legacy SSE from the path", () => {
    expect(inferRemoteTransport("https://mcp.notion.com/sse")).toBe("sse");
    expect(inferRemoteTransport("https://host.example/v1/sse/")).toBe("sse");
    expect(inferRemoteTransport("http://127.0.0.1:8080/sse")).toBe("sse");
  });

  it("does not treat /sse as a substring of unrelated paths", () => {
    expect(inferRemoteTransport("https://mcp.example.com/assess")).toBe("http");
    expect(inferRemoteTransport("https://mcp.example.com/sse-tools")).toBe("http");
  });
});
