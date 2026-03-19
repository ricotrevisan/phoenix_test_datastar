defmodule PhoenixTestDatastar.TestHandlers.CounterHandler do
  @moduledoc false

  def handle_event(conn, "increment", signals) do
    count = (signals["count"] || 0) + 1

    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{count: count})
    |> Dstar.patch_elements(~s(<span id="count">#{count}</span>), selector: "#count")
  end

  def handle_event(conn, "decrement", signals) do
    count = (signals["count"] || 0) - 1

    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{count: count})
    |> Dstar.patch_elements(~s(<span id="count">#{count}</span>), selector: "#count")
  end

  def handle_event(conn, "increment_by", signals) do
    count = (signals["count"] || 0) + 5

    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{count: count})
    |> Dstar.patch_elements(~s(<span id="count">#{count}</span>), selector: "#count")
  end
end
