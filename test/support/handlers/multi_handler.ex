defmodule PhoenixTestDatastar.TestHandlers.MultiHandler do
  @moduledoc false

  def handle_event(conn, "update", signals) do
    count = (signals["count"] || 0) + 1

    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{count: count, status: "active"})
    |> Dstar.patch_elements(~s(<span id="count">#{count}</span>), selector: "#count")
    |> Dstar.patch_elements(~s(<span id="status">active</span>), selector: "#status")
  end
end
