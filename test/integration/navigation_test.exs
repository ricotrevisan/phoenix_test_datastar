defmodule PhoenixTestDatastar.Integration.NavigationTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  describe "click_link" do
    test "follows standard href links", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/links")
      |> click_link("Go to Counter")
      |> assert_has("h1", text: "Counter")
      |> assert_path("/counter")
    end
  end

  describe "redirect via Datastar" do
    test "handles redirect scripts from Datastar", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/links")
      |> click_link("Datastar Navigate")
      |> assert_has("h1", text: "Counter")
      |> assert_path("/counter")
    end
  end

  describe "path assertions" do
    test "assert_path works", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_path("/counter")
    end

    test "refute_path works", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> refute_path("/other")
    end
  end
end
