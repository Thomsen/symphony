# Spec: Gemini Linear Execution (Internal MCP Bridge)

**Date**: 2026-05-19
**Topic**: gemini-linear-execution
**Status**: Draft

## Overview

The ultimate goal is to enable Gemini to autonomously execute tasks fetched from Linear. To achieve this without altering the existing architecture, we will implement an **Internal MCP Bridge**. This allows the Gemini binary to "see" and "call" Symphony's Linear tools (like `linear_graphql`) using its native Model Context Protocol (MCP).

## Architecture

We will implement a 1:1 bridge between Codex Dynamic Tools and Gemini MCP Tools.

### 1. The MCP Adapter (`mcp-adapter`)
A new internal CLI mode for Symphony: `bin/symphony mcp-adapter`.
- **Protocol**: Implements the MCP JSON-RPC protocol over Stdio.
- **Tool Discovery**: Maps `SymphonyElixir.Codex.DynamicTool.tool_specs()` to the MCP `tools/list` response.
- **Tool Execution**: Maps MCP `tools/call` to `SymphonyElixir.Codex.DynamicTool.execute/2`.
- **Isolation**: This runs as a sub-process of the Gemini CLI, which itself is a sub-process of the `GeminiAppServer`.

### 2. GeminiAppServer Integration
Update `SymphonyElixir.Agent.GeminiAppServer` to inject the adapter:
- **Initialization**: When the orchestrator starts a thread, it passes tool definitions.
- **Session Setup**: During the `session/new` ACP call, `GeminiAppServer` will inject the following into the `mcpServers` list:
  ```json
  {
    "name": "symphony-linear-tools",
    "command": "bin/symphony",
    "args": ["mcp-adapter"]
  }
  ```
- **Execution Flow**:
  1. Gemini CLI needs to query Linear.
  2. Gemini CLI calls `tools/call` on the `mcp-adapter` process.
  3. `mcp-adapter` invokes Symphony's internal Linear client.
  4. Result is returned through MCP to Gemini.

## Data Flow
`Orchestrator` → `GeminiAppServer` → `Gemini CLI` → `mcp-adapter (Sub-process)` → `Symphony Tools (Linear)`

## Success Criteria
- Gemini can successfully execute `linear_graphql` queries via MCP.
- The orchestrator can assign a Linear issue to the Gemini agent, and the agent can complete the task and update the issue status autonomously.
- No changes are required to the existing `Orchestrator` or `AgentRunner` logic.

## Technical Tasks
- [ ] Implement `SymphonyElixir.Agent.McpAdapter` to handle standard MCP JSON-RPC messages.
- [ ] Add `mcp-adapter` command to `SymphonyElixir.CLI`.
- [ ] Update `GeminiAppServer` to pass the `mcpServers` configuration during `session/new`.
- [ ] Verify end-to-end flow with a mock Linear task.
