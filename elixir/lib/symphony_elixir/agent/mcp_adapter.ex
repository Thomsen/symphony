defmodule SymphonyElixir.Agent.McpAdapter do
  @moduledoc """
  Bridges Gemini MCP (Model Context Protocol) to Symphony's dynamic tools.
  Runs as a supervised GenServer.
  """

  use GenServer
  alias SymphonyElixir.Codex.DynamicTool

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def main(_args) do
    # This is called when running bin/symphony mcp-adapter directly without ensure_all_started
    # but the new CLI will call ensure_all_started, so this might not be reached
    # or should just block until the GenServer (started by app) is done.
    Process.monitor(__MODULE__)

    receive do
      {:DOWN, _, :process, _, _} ->
        System.halt(0)
    end
  end

  @impl GenServer
  def init(_opts) do
    parent = self()

    collector_pid =
      spawn_link(fn ->
        for line <- IO.stream(:stdio, :line) do
          send(parent, {:stdio_line, line})
        end
      end)

    {:ok, %{collector_pid: collector_pid}}
  end

  @impl GenServer
  def handle_info({:stdio_line, line}, state) do
    line
    |> String.trim()
    |> handle_line()
    |> case do
      "" -> :ok
      response -> IO.puts(response)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_other, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.collector_pid && Process.alive?(state.collector_pid) do
      Process.exit(state.collector_pid, :kill)
    end

    :ok
  end

  defp handle_line("") do
    ""
  end

  defp handle_line(line) do
    case Jason.decode(line) do
      {:ok, request} ->
        case handle_request(request) do
          nil -> ""
          response -> Jason.encode!(response)
        end

      {:error, _reason} ->
        ""
    end
  end

  def handle_request(%{"method" => "initialize", "id" => id}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{},
        "serverInfo" => %{"name" => "symphony-mcp-adapter", "version" => "1.0.0"}
      }
    }
  end

  def handle_request(%{"method" => "tools/list", "id" => id}) do
    tools =
      DynamicTool.tool_specs()
      |> Enum.map(fn spec ->
        %{
          "name" => spec["name"],
          "description" => spec["description"],
          "inputSchema" => spec["inputSchema"]
        }
      end)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{"tools" => tools}
    }
  end

  def handle_request(%{"method" => "tools/call", "id" => id, "params" => %{"name" => name, "arguments" => arguments}}) do
    result = DynamicTool.execute(name, arguments)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "content" => [
          %{
            "type" => "text",
            "text" => result["output"]
          }
        ],
        "isError" => !result["success"]
      }
    }
  end

  def handle_request(%{"id" => id}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => -32601, "message" => "Method not found"}
    }
  end

  def handle_request(_other) do
    nil
  end
end
