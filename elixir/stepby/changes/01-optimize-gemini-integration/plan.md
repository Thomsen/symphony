# [Optimize Gemini Integration] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable seamless Gemini integration through a multi-functional Symphony binary and an optimized build process.

**Architecture:** Burrito-packaged CLI entry point for proxy/orchestrator dispatching and dynamic host-based builds.

**Tech Stack:** Elixir, Burrito, JSON-RPC, Gemini CLI.

---

### Task 1: Update Build Configuration in `mix.exs`

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Implement `host_target/0` and update `burrito` targets**
  Add detection logic and wrap the `targets` in a conditional based on `SYMPHONY_BUILD_ALL`.

```elixir
  defp host_target do
    {os_family, os_name} = :os.type()
    arch = :erlang.system_info(:system_architecture) |> to_string()

    case {os_family, os_name, arch} do
      {:unix, :darwin, aarch64} when String.contains?(aarch64, "arm64") -> :macos_silicon
      {:unix, :darwin, _} -> :macos
      {:unix, :linux, _} -> :linux
      {:win32, _, _} -> :windows
      _ -> :linux
    end
  end

  def releases do
    [
      symphony: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          entry_point: {SymphonyElixir.CLI, :main},
          targets: burrito_targets()
        ]
      ]
    ]
  end

  defp burrito_targets do
    all_targets = [
      macos: [os: :darwin, cpu: :x86_64],
      macos_silicon: [os: :darwin, cpu: :aarch64],
      linux: [os: :linux, cpu: :x86_64],
      windows: [os: :windows, cpu: :x86_64]
    ]

    if System.get_env("SYMPHONY_BUILD_ALL") == "1" do
      all_targets
    else
      Keyword.take(all_targets, [host_target()])
    end
  end
```

- [ ] **Step 2: Verify `mix.exs` compiles**
  Run: `mix compile`
  Expected: Successful compilation.

- [ ] **Step 3: Commit build configuration**
  ```bash
  git add mix.exs
  git commit -m "build: optimize burrito targets and set entry_point"
  ```

### Task 2: Refactor Application and CLI Entry Logic

**Files:**
- Modify: `lib/symphony_elixir.ex`
- Modify: `lib/symphony_elixir/cli.ex`

- [ ] **Step 1: Clean up `Application.start/2`**
  Remove the `case System.argv()` block so the app always starts its standard children.

```elixir
  @impl true
  def start(_type, _args) do
    :ok = SymphonyElixir.LogFile.configure()

    children = [
      {Phoenix.PubSub, name: SymphonyElixir.PubSub},
      {Task.Supervisor, name: SymphonyElixir.TaskSupervisor},
      SymphonyElixir.WorkflowStore,
      SymphonyElixir.Orchestrator,
      SymphonyElixir.HttpServer,
      SymphonyElixir.StatusDashboard
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: SymphonyElixir.Supervisor
    )
  end
```

- [ ] **Step 2: Ensure `CLI.evaluate` handles `gemini` before starting the app**
  Verify the `evaluate(["gemini" | args], _deps)` match is prioritized.

```elixir
  def evaluate(["gemini" | args], _deps) do
    GeminiAppServer.main(args)
    :ok
  end
```

- [ ] **Step 3: Run tests to ensure no regressions in Orchestrator startup**
  Run: `mix test test/symphony_elixir/cli_test.exs`
  Expected: Tests pass.

- [ ] **Step 4: Commit CLI refactor**
  ```bash
  git add lib/symphony_elixir.ex lib/symphony_elixir/cli.ex
  git commit -m "refactor: move CLI dispatch logic to CLI module and clean up Application"
  ```

### Task 3: Enhance `GeminiAppServer` and Update `Makefile`

**Files:**
- Modify: `lib/symphony_elixir/agent/gemini_app_server.ex`
- Modify: `Makefile`
- Modify: `WORKFLOW.md`

- [ ] **Step 1: Improve Port handling and update flags in `GeminiAppServer`**
  Add `:stderr_to_stdout` and update the flag to `--acp`.

```elixir
    gemini_args = ["--acp", "--yolo"]

    # ...
          port =
            Port.open(
              {:spawn_executable, executable},
              [
                :binary,
                :exit_status,
                :stderr_to_stdout,
                args: gemini_args,
                cd: cwd,
                line: 1_048_576
              ]
            )
```

- [ ] **Step 2: Update `Makefile` targets**
  Support `release-all` and keep `release` as the host-only default.

```makefile
release:
	$(MIX) release

release-all:
	SYMPHONY_BUILD_ALL=1 $(MIX) release
```

- [ ] **Step 3: Update `WORKFLOW.md` default command**
```yaml
codex:
  command: bin/symphony gemini --model gemini-2.0-flash
  approval_policy: never
```

- [ ] **Step 4: Final Validation Build**
  Run: `make release`
  Run: `./burrito_out/symphony_<host> gemini`
  Enter: `{"jsonrpc":"2.0","method":"initialize","id":1}`
  Expected: Returns JSON-RPC server info.

- [ ] **Step 5: Commit remaining changes**
  ```bash
  git add lib/symphony_elixir/agent/gemini_app_server.ex Makefile WORKFLOW.md
  git commit -m "feat: enhance gemini proxy and update workflow defaults"
  ```
