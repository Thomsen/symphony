defmodule SymphonyElixir.Agent.GeminiAppServer do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc """
  Gemini app-server proxy for Symphony.
  Bridges Codex JSON-RPC protocol over stdio to Gemini ACP over stdio.
  """

  @spec main([String.t()]) :: no_return()
  def main(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [model: :string])
    model = Keyword.get(opts, :model)

    parent = self()

    spawn_link(fn ->
      for line <- IO.stream(:stdio, :line) do
        send(parent, {:stdio_line, line})
      end
    end)

    loop(%{
      model: model,
      gemini_port: nil,
      gemini_session_id: nil,
      pending_requests: %{},
      acp_id_counter: 10,
      cwd: nil,
      gemini_buffer: ""
    })
  end

  defp loop(state) do
    receive do
      {:stdio_line, line} ->
        state |> handle_stdio(line) |> loop()

      {port, {:data, {:eol, chunk}}} when port == state.gemini_port ->
        line = state.gemini_buffer <> chunk
        state |> Map.put(:gemini_buffer, "") |> handle_gemini_line(line) |> loop()

      {port, {:data, {:noeol, chunk}}} when port == state.gemini_port ->
        loop(%{state | gemini_buffer: state.gemini_buffer <> chunk})

      {port, {:exit_status, status}} when port == state.gemini_port ->
        System.halt(status)

      _other ->
        loop(state)
    end
  end

  defp send_symphony(msg) do
    msg_with_rpc = Map.put(msg, :jsonrpc, "2.0")
    IO.write(:stdio, Jason.encode!(msg_with_rpc) <> "\n")
  end

  defp send_acp(state, method, params) do
    id = state.acp_id_counter
    msg = %{jsonrpc: "2.0", method: method, id: id, params: params}
    Port.command(state.gemini_port, Jason.encode!(msg) <> "\n")
    {id, %{state | acp_id_counter: id + 1}}
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

    gemini_args = ["--experimental-acp", "--yolo"]
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
              {session_id, s3} = send_acp(s2, "session/new", %{cwd: cwd, mcpServers: []})

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
                    {session_id, s5} = send_acp(s4, "session/new", %{cwd: cwd, mcpServers: []})

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

  defp handle_symphony_message(state, _msg) do
    state
  end

  defp put_pending(state, id, on_resolve, on_reject \\ fn _, s -> s end) do
    %{state | pending_requests: Map.put(state.pending_requests, id, %{resolve: on_resolve, reject: on_reject})}
  end

  defp handle_gemini_line(state, line) do
    case Jason.decode(line) do
      {:ok, %{"id" => id} = msg} when not is_nil(id) ->
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

      _ ->
        state
    end
  end
end
