defmodule SymphonyElixir.Agent.GeminiAppServerTest do
  use ExUnit.Case, async: true
  alias SymphonyElixir.Agent.GeminiAppServer

  test "starts as a GenServer" do
    # We use start_link which should fail now because it's not defined as a GenServer
    assert {:ok, _pid} = GeminiAppServer.start_link(model: "gemini-2.0-flash")
  end
end
