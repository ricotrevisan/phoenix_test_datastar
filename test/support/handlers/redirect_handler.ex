defmodule PhoenixTestDatastar.TestHandlers.RedirectHandler do
  @moduledoc false

  def handle_event(conn, "go_counter", _signals) do
    conn
    |> Dstar.start()
    |> Dstar.redirect("/counter")
  end

  def handle_event(conn, "go_redirected", _signals) do
    conn
    |> Dstar.start()
    |> Dstar.redirect("/redirected")
  end
end
