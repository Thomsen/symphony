defmodule SymphonyElixir.Agent.McpAdapterTest do
  use ExUnit.Case, async: true
  alias SymphonyElixir.Agent.McpAdapter

  test "responds to initialize" do
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}
    response = McpAdapter.handle_request(request)
    assert response["result"]["protocolVersion"] == "2024-11-05"
    assert response["result"]["serverInfo"]["name"] == "symphony-mcp-adapter"
  end

  test "responds to tools/list" do
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
    response = McpAdapter.handle_request(request)
    assert response["result"]["tools"] |> Enum.any?(&(&1["name"] == "linear_graphql"))
  end
end
