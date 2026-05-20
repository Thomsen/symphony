# Spec: Gemini Linear Execution (Internal MCP Bridge)

## Problem
Gemini needs to execute tasks from Linear, but it doesn't natively support Symphony's Codex-style dynamic tools.

## Proposed Solution
Implement an internal MCP Adapter that bridges Symphony's Linear tools into Gemini's MCP ecosystem. This allows Gemini to use `linear_graphql` through a sub-process bridge.

## Key Changes
1.  **MCP Adapter**: New `mcp-adapter` command implementing MCP JSON-RPC over Stdio.
2.  **Tool Discovery**: Maps internal `DynamicTool` specs to MCP format.
3.  **Integration**: Update `GeminiAppServer` to inject this adapter into Gemini's `session/new` configuration.

## Verification Plan
1.  Verify `bin/symphony mcp-adapter` responds to MCP discovery.
2.  Run an end-to-end task where Gemini fetches and updates a Linear issue.
