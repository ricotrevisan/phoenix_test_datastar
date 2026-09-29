defmodule PhoenixTestDatastar.Integration.PageEventTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  # Pages render the real dstar helper output (Dstar.Page.Helpers,
  # Dstar.Component, Dstar.Actions); see TestHandlers.PageController.
  describe "page-local event URLs" do
    test "click dispatches to current path + /_event/<name>", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/wire")
      |> click_button("Wire Check")
      |> assert_signal("wired", true)
      |> assert_has("#wired", text: "true")
    end

    test "a confirm() guard is accepted and the action dispatched", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/wire")
      |> click_button("Guarded Wiring")
      |> assert_signal("wired", true)
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

  describe "connect(include_search: true) data-init" do
    test "posts to the current path including the query string", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/connect-search?tab=songs")
      |> assert_signal("status", "connected:songs")
    end
  end

  describe "Dstar.Component actions" do
    test "dispatch to the default /ds base with a percent-encoded event", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/component")
      |> click_button("Ping")
      |> assert_signal("pinged", true)
      |> assert_has("#pinged", text: "true")
    end

    test "dispatch to the <body data-ds-base> base", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/acme/component")
      |> click_button("Ping")
      |> assert_signal("pinged", true)
    end
  end

  describe "module-form actions" do
    test "resolve a dynamic $_dstar_module segment", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/dynamic")
      |> click_button("Dynamic Increment")
      |> assert_signal("count", 1)
    end

    test "honour :prefix", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/dynamic")
      |> click_button("Prefixed Increment")
      |> assert_signal("count", 1)
    end
  end
end
