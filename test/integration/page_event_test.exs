defmodule PhoenixTestDatastar.Integration.PageEventTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  # Exercises URL expressions emitted by dstar >= 0.1.0-alpha.2 page-local
  # helpers (Dstar.Page.Helpers):
  #
  #   event("wire_check") #=> "@post(location.pathname.replace(/\/+$/, '') + '/_event/wire_check')"
  #   connect()           #=> "@post(location.pathname, {retryMaxCount: Infinity})"
  describe "page-local event URLs" do
    test "click dispatches to current path + /_event/<name>", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/wire")
      |> click_button("Wire Check")
      |> assert_signal("wired", true)
      |> assert_has("#wired", text: "true")
    end

    test "trailing slash in the visited path is stripped", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/wire/")
      |> click_button("Wire Check")
      |> assert_signal("wired", true)
    end
  end

  describe "connect()-style data-init" do
    test "posts to the current page path on visit", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/connect-page")
      |> assert_signal("status", "connected")
      |> assert_has("#status", text: "connected")
    end
  end
end
