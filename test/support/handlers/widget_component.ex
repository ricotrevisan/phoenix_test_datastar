defmodule PhoenixTestDatastar.TestHandlers.WidgetComponent do
  @moduledoc false
  use Dstar.Component

  # The `!` is percent-encoded in the action URL (`/ping%21`).
  def handle_event(conn, "ping!", _signals) do
    conn
    |> start()
    |> patch_signals(%{pinged: true})
    |> patch_elements(~s(<span id="pinged">true</span>), selector: "#pinged")
  end
end
