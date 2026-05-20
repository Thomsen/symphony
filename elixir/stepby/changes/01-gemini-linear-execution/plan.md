# Gemini Linear Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Gemini to execute Linear tasks by bridging Symphony's tools via an internal MCP Adapter.

**Architecture:** A new `mcp-adapter` CLI command provides an MCP interface to Symphony's `DynamicTool` module. `GeminiAppServer` configures the Gemini binary to use this adapter during session initialization.

**Tech Stack:** Elixir, JSON-RPC, MCP (Model Context Protocol).

---

### Task 1: Implement `McpAdapter` Module

**Files:**
- Create: `lib/symphony_elixir/agent/mcp_adapter.ex`
- Create: `test/symphony_elixir/agent/mcp_adapter_test.exs`

- [x] **Step 1: Create failing test for MCP tool discovery**
Write a test verifying that the adapter responds correctly to a `tools/list` request.

```elixir
defmodule SymphonyElixir.Agent.McpAdapterTest do
  use ExUnit.Case, async: true
  alias SymphonyElixir.Agent.McpAdapter

  test "responds to tools/list" do
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
    response = McpAdapter.handle_request(request)
    assert response["result"]["tools"] |> Enum.any?(&(&1["name"] == "linear_graphql"))
  end
end
```

- [x] **Step 2: Implement `McpAdapter` module structure**
Implement `handle_request/1` and the protocol bridging logic.

- [x] **Step 3: Implement Stdio main loop**
A blocking loop that reads JSON-RPC from stdio and writes responses.

- [x] **Step 4: Verify tests pass**
Run `mix test test/symphony_elixir/agent/mcp_adapter_test.exs`.

### Task 2: Add `mcp-adapter` to CLI

**Files:**
- Modify: `lib/symphony_elixir/cli.ex`

- [x] **Step 1: Add `mcp-adapter` command to `evaluate/2`**
Register the command to start the adapter loop.

- [x] **Step 2: Update `usage_message`**
Add the command to the help text.

### Task 3: Integrate with `GeminiAppServer`

**Files:**
- Modify: `lib/symphony_elixir/agent/gemini_app_server.ex`

- [x] **Step 1: Update `session/new` ACP call**
Inject the `mcpServers` list into the ACP message.

```elixir
# In GeminiAppServer
{session_id, s3} = send_acp(s2, "session/new", %{
  cwd: cwd, 
  mcpServers: [
    %{
      "name" => "symphony-linear-tools",
      "command" => "bin/symphony",
      "args" => ["mcp-adapter"]
    }
  ]
})
```

- [ ] **Step 2: Final manual verification**
Run `bin/symphony gemini-app-server` and verify that Gemini can call `linear_graphql`.
