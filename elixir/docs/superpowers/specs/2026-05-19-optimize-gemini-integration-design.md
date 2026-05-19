# Spec: Gemini Integration Optimization & Build System Refactor

**Status:** Draft
**Date:** 2026-05-19
**Topic:** optimize-gemini-integration

## 1. Context & Problem Statement

Currently, Symphony's Gemini integration faces two primary issues:
1.  **Release Limitation**: When Symphony is packaged via Burrito (`mix release`), the resulting binary does not correctly handle CLI arguments like `gemini`. It defaults to OTP application management rather than our custom CLI entry point.
2.  **Build Inefficiency**: The Burrito configuration currently builds for all targets (macOS, Linux, Windows) by default, which is time-consuming for local development.
3.  **Non-Idiomatic Bootstrapping**: The `Application.start/2` function contains logic to branch based on `System.argv()`, which is fragile in a release context and complicates the supervisor tree.

## 2. Goals

-   **Multi-functional CLI**: Ensure the Burrito-packaged binary acts as a true CLI, supporting both the Orchestrator (default) and the Gemini Proxy (`gemini` subcommand).
-   **Optimized Build System**: Default `make release` to only compile for the current host system, while providing a `make release-all` option for full platform support.
-   **Clean Separation of Concerns**: Move all CLI dispatching logic into the `CLI` module and keep `Application` focused on starting the Orchestrator services.
-   **Robust Proxy**: Enhance `GeminiAppServer` to handle `stderr` and authentication more reliably.

## 3. Architecture & Design

### 3.1 CLI Dispatching (The Entry Point)
We will use Burrito's `entry_point` feature to make `SymphonyElixir.CLI.main/1` the absolute first point of execution.

-   **`bin/symphony gemini`**: Invokes `GeminiAppServer.main/1`. This path **will not** start the full `:symphony_elixir` application (no Orchestrator, no HTTP server), making it a lightweight proxy.
-   **`bin/symphony` (no args)**: Invokes the default Orchestrator path, which calls `Application.ensure_all_started(:symphony_elixir)`.

### 3.2 Dynamic Build Configuration
`mix.exs` will be updated to detect the host OS and CPU architecture.

-   **Default**: `burrito_targets` returns only the host target.
-   **Full Build**: Triggered by `SYMPHONY_BUILD_ALL=1`, returns the complete list of targets.

### 3.3 Gemini Proxy Robustness
`GeminiAppServer` will be updated to:
-   Redirect `stderr` to `stdout` (or a log) to prevent non-JSON output from breaking the JSON-RPC stream.
-   Ensure compatibility with the latest `gemini-cli` flags (e.g., using `--acp` instead of `--experimental-acp`).

## 4. Implementation Plan

### 4.1 Build System Changes
-   Modify `mix.exs` to include `host_target/0` detection logic.
-   Update `releases` in `mix.exs` to use `entry_point: {SymphonyElixir.CLI, :main}`.
-   Update `Makefile` to support `release` (default) and `release-all`.

### 4.2 Code Refactoring
-   **`lib/symphony_elixir.ex`**: Remove `System.argv()` case from `Application.start/2`. It should always start the default children.
-   **`lib/symphony_elixir/cli.ex`**: Ensure `evaluate(["gemini" | args], _deps)` is the first match and correctly calls the proxy without starting the app.
-   **`lib/symphony_elixir/agent/gemini_app_server.ex`**: Add `:stderr_to_stdout` to `Port.open`.

### 4.3 Configuration
-   Update `WORKFLOW.md` to point to `bin/symphony gemini` as the default `codex.command`.

## 5. Success Criteria

-   `make release` finishes significantly faster on a single host.
-   Running `./burrito_out/symphony_macos_silicon gemini` correctly starts the Gemini proxy and responds to JSON-RPC `initialize`.
-   Running `./burrito_out/symphony_macos_silicon` correctly starts the Orchestrator and begins polling.
-   `WORKFLOW.md` works out-of-the-box with Gemini if the CLI is installed.
