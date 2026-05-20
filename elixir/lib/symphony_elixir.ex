defmodule SymphonyElixir do
  @moduledoc """
  Entry point for the Symphony orchestrator.
  """

  @doc """
  Start the orchestrator in the current BEAM node.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    SymphonyElixir.Orchestrator.start_link(opts)
  end
end

defmodule SymphonyElixir.Application do
  @moduledoc """
  OTP application entrypoint that starts core supervisors and workers.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Try multiple ways to get arguments in a release context
    burrito_args = if Code.ensure_loaded?(Burrito.Util.Args), do: Burrito.Util.Args.argv(), else: nil
    argv = burrito_args || System.argv()
    init_args = Enum.map(:init.get_plain_arguments(), &to_string/1)

    all_args = argv ++ init_args

    is_proxy_mode? =
      Enum.any?(all_args, fn arg ->
        cmd = if String.contains?(arg, "/"), do: Path.basename(arg), else: arg
        cmd in ["gemini", "gemini-app-server", "mcp-adapter"]
      end)

    :ok = SymphonyElixir.LogFile.configure()

    common_children = [
      {Phoenix.PubSub, name: SymphonyElixir.PubSub},
      {Task.Supervisor, name: SymphonyElixir.TaskSupervisor}
    ]

    children =
      if is_proxy_mode? do
        # Extract command-specific args
        proxy_command = Enum.find(["mcp-adapter", "gemini-app-server", "gemini"], fn cmd ->
          Enum.any?(all_args, fn arg ->
            if String.contains?(arg, "/"), do: Path.basename(arg) == cmd, else: arg == cmd
          end)
        end)

        case proxy_command do
          "mcp-adapter" ->
            common_children ++ [SymphonyElixir.Agent.McpAdapter]

          cmd when cmd in ["gemini", "gemini-app-server"] ->
            gemini_args_raw =
              cond do
                cmd in argv -> Enum.drop_while(argv, &(&1 != cmd)) |> tl()
                cmd in init_args -> Enum.drop_while(init_args, &(&1 != cmd)) |> tl()
                true ->
                  # Find by basename
                  arg_with_cmd = Enum.find(all_args, fn arg -> String.contains?(arg, "/") and Path.basename(arg) == cmd end)
                  src_args = if arg_with_cmd in argv, do: argv, else: init_args
                  Enum.drop_while(src_args, &(&1 != arg_with_cmd)) |> tl()
              end

            {gemini_opts, _, _} = OptionParser.parse(gemini_args_raw, strict: [model: :string])
            common_children ++ [{SymphonyElixir.Agent.GeminiAppServer, gemini_opts}]
        end
      else
        common_children ++
          [
            SymphonyElixir.WorkflowStore,
            SymphonyElixir.Orchestrator,
            SymphonyElixir.HttpServer,
            SymphonyElixir.StatusDashboard
          ]
      end

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: SymphonyElixir.Supervisor
    )
  end

  @impl true
  def stop(_state) do
    SymphonyElixir.StatusDashboard.render_offline_status()
    :ok
  end
end
