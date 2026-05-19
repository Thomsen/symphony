# Spec: Gemini Long Task (Supervised gemini-app-server)

**Date**: 2026-05-19
**Topic**: gemini-long-task
**Status**: Approved

## Overview

Refactor the existing `gemini` command from a standalone standalone proxy into a supervised `GenServer` task named `gemini-app-server`. This ensures the proxy is part of the OTP supervision tree, has access to all application resources (like Ecto), and behaves as a robust "long task".

## Architecture

### 1. GeminiAppServer GenServer
The `SymphonyElixir.Agent.GeminiAppServer` will be refactored into a `GenServer`:
- **init/1**: Spawns a linked Stdio Collector process.
- **Stdio Collector**: Reads from `:stdio` line-by-line and sends messages to the GenServer.
- **Port Management**: Manages the `gemini` executable via Elixir Ports.
- **Message Handling**: Uses `handle_info/2` to process stdio lines and Port data.
- **Protocol**: Bridges Codex JSON-RPC (stdio) to Gemini ACP (Port).

### 2. Application Integration
`SymphonyElixir.Application` will be updated to supervise the `GeminiAppServer`:
- Detection logic will check for the `gemini-app-server` command in arguments.
- When detected, it starts `GeminiAppServer` as a child worker instead of the full orchestrator suite.

### 3. CLI Command
A new CLI command `gemini-app-server` will be added to `SymphonyElixir.CLI`:
- Triggers full application startup via `ensure_all_started`.
- Blocks until shutdown using `wait_for_shutdown`.

## Data Flow
`Orchestrator (Stdio)` ⇄ `Stdio Collector` → `GeminiAppServer (GenServer)` ⇄ `Gemini Binary (Port)`

## Success Criteria
- `bin/symphony gemini-app-server --model gemini-2.0-flash` starts the supervised proxy.
- The proxy correctly handles JSON-RPC initialization and turn requests.
- The process is supervised and restarts if it crashes unexpectedly.
- Access to `Ecto.UUID` and other application services is available during startup.
