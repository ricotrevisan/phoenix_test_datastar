defmodule PhoenixTestDatastar.Integration.ClickTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  describe "click_button with Datastar action" do
    test "dispatches datastar action and updates signals", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> click_button("Increment")
      |> assert_signal("count", 1)
    end

    test "dispatches datastar action and updates DOM", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> click_button("Increment")
      |> assert_has("#count", text: "1")
    end

    test "clicking multiple times accumulates state", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> click_button("Increment")
      |> click_button("Increment")
      |> click_button("Increment")
      |> assert_signal("count", 3)
      |> assert_has("#count", text: "3")
    end

    test "decrement works", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> click_button("Increment")
      |> click_button("Increment")
      |> click_button("Decrement")
      |> assert_signal("count", 1)
      |> assert_has("#count", text: "1")
    end

    test "click_button with selector", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> click_button("#increment-btn", "Increment")
      |> assert_signal("count", 1)
    end

    test "multiple signals updated in one action", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/multi-action")
      |> click_button("Update Both")
      |> assert_signal("count", 1)
      |> assert_signal("status", "active")
      |> assert_has("#count", text: "1")
      |> assert_has("#status", text: "active")
    end
  end

  describe "click_button with Datastar attributes" do
    test "submits an id-less button without using data attributes in its form selector", %{
      conn: conn
    } do
      conn
      |> PhoenixTestDatastar.visit("/standard-form")
      |> fill_in("Username", with: "alice")
      |> click_button("Login")
      |> assert_has("h1", text: "You were redirected!")
    end
  end
end
