defmodule PhoenixTestDatastar.TestHandlers.InitHandler do
  @moduledoc false

  def handle_event(conn, "load", _signals) do
    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{count: 42})
    |> Dstar.patch_elements(~s(<span id="count">42</span>), selector: "#count")
  end
end
