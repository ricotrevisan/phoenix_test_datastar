defmodule PhoenixTestDatastar.Integration.VisitTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  describe "visit" do
    test "visits a page and extracts signals", %{conn: conn} do
      session = PhoenixTestDatastar.visit(conn, "/counter")

      assert PhoenixTestDatastar.get_signal(session, "count") == 0
      assert PhoenixTestDatastar.get_signal(session, "_csrfToken") == "test-csrf-token"
    end

    test "renders page title", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_has("title", text: "Counter")
    end

    test "renders page HTML", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_has("h1", text: "Counter")
      |> assert_has("#count", text: "0")
    end

    test "sets current path", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_path("/counter")
    end

    test "extracts CSRF token from signals", %{conn: conn} do
      session = PhoenixTestDatastar.visit(conn, "/counter")
      assert session.csrf_token == "test-csrf-token"
    end

    test "extracts nested signals", %{conn: conn} do
      session = PhoenixTestDatastar.visit(conn, "/nested-signals")

      assert PhoenixTestDatastar.get_signal(session, "user") == %{"name" => "Alice", "age" => 30}
      assert PhoenixTestDatastar.get_signal(session, "settings") == %{"theme" => "dark"}
    end
  end
end
