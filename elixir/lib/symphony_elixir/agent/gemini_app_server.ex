defmodule SymphonyElixir.Agent.GeminiAppServer do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc """
  Gemini app-server proxy for Symphony.
  Bridges Codex JSON-RPC protocol over stdio to Gemini ACP over stdio.
  """

  use GenServer
  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec main([String.t()]) :: no_return()
  def main(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [model: :string])
    {:ok, _pid} = start_link(opts)

    Process.monitor(__MODULE__)

    receive do
      {:DOWN, _, :process, _, _} ->
        System.halt(0)
    end
  end

  @impl GenServer
  def init(opts) do
    Logger.info("GeminiAppServer initializing with opts: #{inspect(opts)}")
    model = Keyword.get(opts, :model)

    parent = self()

    collector_pid =
      spawn_link(fn ->
        loop_read(parent)
      end)

    {:ok,
     %{
       model: model,
       gemini_port: nil,
       gemini_session_id: nil,
       pending_requests: %{},
       acp_id_counter: 10,
       cwd: nil,
       gemini_buffer: "",
       collector_pid: collector_pid
     }}
  end

  @impl GenServer
  def handle_info({:stdio_line, line}, state) do
    log("RECV SYMPHONY: #{String.trim(line)}")
    Logger.info("GeminiAppServer received stdio line: #{String.trim(line)}")
    {:noreply, handle_stdio(state, line)}
  end

  @impl GenServer
  def handle_info({port, {:data, {:eol, chunk}}}, state) when port == state.gemini_port do
    line = state.gemini_buffer <> chunk
    {:noreply, state |> Map.put(:gemini_buffer, "") |> handle_gemini_line(line)}
  end

  @impl GenServer
  def handle_info({port, {:data, {:noeol, chunk}}}, state) when port == state.gemini_port do
    {:noreply, %{state | gemini_buffer: state.gemini_buffer <> chunk}}
  end

  @impl GenServer
  def handle_info({port, {:exit_status, status}}, state) when port == state.gemini_port do
    # Graceful exit of the GenServer instead of System.halt
    Process.exit(self(), if(status == 0, do: :normal, else: {:port_exit, status}))
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

    if state.gemini_port do
      Port.close(state.gemini_port)
    end

    :ok
  end

  defp send_symphony(msg) do
    msg_with_rpc = Map.put(msg, :jsonrpc, "2.0")
    payload = Jason.encode!(msg_with_rpc)
    log("SEND SYMPHONY: #{payload}")
    Logger.info("GeminiAppServer sending to Symphony: #{payload}")
    IO.puts(payload)
  end

  defp send_acp(state, method, params) do
    id = state.acp_id_counter
    msg = %{jsonrpc: "2.0", method: method, id: id, params: params}
    payload = Jason.encode!(msg)
    log("SEND GEMINI: #{payload}")
    Logger.info("GeminiAppServer sending ACP request: #{payload}")
    Port.command(state.gemini_port, payload <> "\n")
    {id, %{state | acp_id_counter: id + 1}}
  end

  defp prepare_mcp_servers(symphony_mcp_servers) do
    internal_server = %{
      "name" => "symphony-mcp-adapter",
      "command" => Path.expand(to_string(:escript.script_name())),
      "args" => ["mcp-adapter"],
      "env" => []
    }

    orchestrator_servers =
      cond do
        is_list(symphony_mcp_servers) ->
          Enum.filter(symphony_mcp_servers, &is_map/1)

        is_map(symphony_mcp_servers) ->
          # If orchestrator sent a map (like gemini.json format), try to convert it to the array format
          Enum.map(symphony_mcp_servers, fn {name, config} ->
            Map.put(config, "name", to_string(name))
          end)

        true ->
          []
      end

    [internal_server | orchestrator_servers]
  end

  defp notify_acp(state, method, params) do
    msg = %{jsonrpc: "2.0", method: method, params: params}
    Port.command(state.gemini_port, Jason.encode!(msg) <> "\n")
  end

  defp handle_stdio(state, line) do
    line_trimmed = String.trim(line)

    if line_trimmed == "" do
      state
    else
      case Jason.decode(line_trimmed) do
        {:ok, msg} -> handle_symphony_message(state, msg)
        _ -> state
      end
    end
  end

  defp handle_symphony_message(state, %{"method" => "initialize", "id" => id}) do
    send_symphony(%{
      id: id,
      result: %{
        capabilities: %{experimentalApi: true},
        serverInfo: %{name: "gemini-app-server", version: "1.0.0"}
      }
    })

    state
  end

  defp handle_symphony_message(state, %{"method" => "initialized"}) do
    state
  end

  defp handle_symphony_message(state, %{"method" => "thread/start", "id" => id, "params" => params}) do
    cwd = Map.get(params, "cwd", File.cwd!())

    gemini_args = ["--acp", "--yolo"]
    gemini_args = if state.model, do: gemini_args ++ ["--model", state.model], else: gemini_args

    executable = System.find_executable("gemini")

    if is_nil(executable) do
      send_symphony(%{id: id, error: %{code: -32_603, message: "gemini executable not found"}})
      state
    else
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

      state = %{state | gemini_port: port, cwd: cwd}

      # ACP initialize
      {acp_id, state} =
        send_acp(state, "initialize", %{
          protocolVersion: 1,
          capabilities: %{fs: %{read: true, write: true}},
          clientInfo: %{name: "symphony-orchestrator", version: "0.1.0"}
        })

      state =
        put_pending(state, acp_id, fn _result, s ->
          notify_acp(s, "notifications/initialized", %{})

          # Attempt to authenticate
          {auth_id, s} = send_acp(s, "authenticate", %{methodId: "oauth-personal"})

          put_pending(
            s,
            auth_id,
            fn _res, s2 ->
              # session/new
              mcp_servers = prepare_mcp_servers(Map.get(params, "mcpServers", []))

              {session_id, s3} =
                send_acp(s2, "session/new", %{
                  cwd: cwd,
                  mcpServers: mcp_servers
                })

              put_pending(
                s3,
                session_id,
                fn res, s4 ->
                  symphony_thread_id = Ecto.UUID.generate()
                  send_symphony(%{id: id, result: %{thread: %{id: symphony_thread_id}}})
                  %{s4 | gemini_session_id: res["sessionId"]}
                end,
                fn err, s4 ->
                  send_symphony(%{id: id, error: %{code: -32_603, message: err["message"]}})
                  s4
                end
              )
            end,
            fn _err, s2 ->
              # If oauth fails, fallback to API key if present, otherwise fail
              if System.get_env("GEMINI_API_KEY") do
                {auth_id2, s3} = send_acp(s2, "authenticate", %{methodId: "gemini-api-key"})

                put_pending(
                  s3,
                  auth_id2,
                  fn _res, s4 ->
                    # session/new
                    mcp_servers = prepare_mcp_servers(Map.get(params, "mcpServers", []))

                    {session_id, s5} =
                      send_acp(s4, "session/new", %{
                        cwd: cwd,
                        mcpServers: mcp_servers
                      })

                    put_pending(
                      s5,
                      session_id,
                      fn res, s6 ->
                        symphony_thread_id = Ecto.UUID.generate()
                        send_symphony(%{id: id, result: %{thread: %{id: symphony_thread_id}}})
                        %{s6 | gemini_session_id: res["sessionId"]}
                      end,
                      fn err, s6 ->
                        send_symphony(%{id: id, error: %{code: -32_603, message: err["message"]}})
                        s6
                      end
                    )
                  end,
                  fn err, s4 ->
                    send_symphony(%{id: id, error: %{code: -32_603, message: err["message"]}})
                    s4
                  end
                )
              else
                send_symphony(%{id: id, error: %{code: -32_603, message: "Authentication failed"}})
                s2
              end
            end
          )
        end)

      state
    end
  end

  defp handle_symphony_message(state, %{"method" => "turn/start", "id" => id, "params" => params}) do
    turn_id = Ecto.UUID.generate()
    send_symphony(%{id: id, result: %{turn: %{id: turn_id}}})

    input_blocks = Map.get(params, "input", [])

    prompt =
      input_blocks
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n", & &1["text"])

    cwd = Map.get(params, "cwd", state.cwd)

    {acp_id, state} =
      send_acp(state, "session/prompt", %{
        sessionId: state.gemini_session_id,
        prompt: [%{type: "text", text: prompt}],
        cwd: cwd
      })

    put_pending(
      state,
      acp_id,
      fn _result, s ->
        send_symphony(%{method: "turn/completed", params: %{turnId: turn_id}})
        s
      end,
      fn err, s ->
        send_symphony(%{method: "turn/failed", params: %{turnId: turn_id, reason: err["message"]}})
        s
      end
    )
  end

  defp handle_symphony_message(state, %{"method" => "item/tool/result", "params" => params} = msg) do
    Logger.info("GeminiAppServer received tool result from Symphony: #{inspect(msg)}")

    id = params["id"]
    output = params["output"]

    # Translate back to Gemini response (ACP)
    msg = %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        "content" => [%{"type" => "text", "text" => output}],
        "isError" => false
      }
    }

    Port.command(state.gemini_port, Jason.encode!(msg) <> "\n")
    state
  end

  defp handle_symphony_message(state, %{"id" => id} = msg) when not is_nil(id) do
    # Generic response forwarding for requests initiated by Gemini (like tool calls)
    Logger.info("GeminiAppServer forwarding response to Gemini: #{inspect(msg)}")
    Port.command(state.gemini_port, Jason.encode!(msg) <> "\n")
    state
  end

  defp handle_symphony_message(state, _msg) do
    state
  end

  defp put_pending(state, id, on_resolve, on_reject \\ fn _, s -> s end) do
    %{state | pending_requests: Map.put(state.pending_requests, id, %{resolve: on_resolve, reject: on_reject})}
  end

  defp handle_gemini_line(state, line) do
    case Jason.decode(line) do
      {:ok, msg} ->
        log("RECV GEMINI: #{Jason.encode!(msg)}")
        handle_gemini_message(state, msg)

      _ ->
        state
    end
  end

  defp handle_gemini_message(state, %{"id" => id, "method" => "item/tool/call", "params" => params} = msg) do
    Logger.info("GeminiAppServer received tool call from Gemini: #{inspect(msg)}")

    # Translate to Codex item/tool/call
    call = params["call"]

    symphony_params = %{
      "name" => call["name"],
      "arguments" => call["input"],
      "callId" => call["id"]
    }

    send_symphony(%{
      method: "item/tool/call",
      id: id,
      params: symphony_params
    })

    state
  end

  defp handle_gemini_message(state, %{"method" => "item/text", "params" => params} = msg) do
    Logger.info("GeminiAppServer received text from Gemini: #{inspect(msg)}")

    send_symphony(%{
      method: "item/text",
      params: %{"text" => params["text"]}
    })

    state
  end

  defp handle_gemini_message(state, %{"id" => id} = msg) when not is_nil(id) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        state

      {callback, pending} ->
        s2 = %{state | pending_requests: pending}

        if msg["error"] do
          callback.reject.(msg["error"], s2)
        else
          callback.resolve.(msg["result"], s2)
        end
    end
  end

  defp handle_gemini_message(state, _msg) do
    state
  end

  defp log(message) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    log_file = Path.join([File.cwd!(), "log", "gemini_app_server.log"])
    File.mkdir_p!(Path.dirname(log_file))
    File.write!(log_file, "#{timestamp} #{message}\n", [:append])
  rescue
    _ -> :ok
  end

  defp loop_read(parent) do
    case :io.get_line(:standard_io, "") do
      :eof ->
        :ok

      line ->
        send(parent, {:stdio_line, line})
        loop_read(parent)
    end
  end
end
