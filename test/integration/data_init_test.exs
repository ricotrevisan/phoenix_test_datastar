defmodule PhoenixTestDatastar.Integration.DataInitTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  describe "data-init auto-dispatching" do
    test "automatically dispatches data-init actions on visit", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/data-init")
      |> assert_signal("count", 42)
      |> assert_has("#count", text: "42")
    end
  end
end
