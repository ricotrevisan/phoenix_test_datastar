defmodule PhoenixTestDatastar.Integration.AssertionsTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  describe "DOM assertions (PhoenixTest)" do
    test "assert_has with selector", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_has("#count")
    end

    test "assert_has with selector and text", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_has("#count", text: "0")
    end

    test "refute_has with selector", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> refute_has("#nonexistent")
    end

    test "refute_has with selector and text", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> refute_has("#count", text: "999")
    end
  end

  describe "signal assertions" do
    test "assert_signal checks signal value", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_signal("count", 0)
    end

    test "assert_signal fails with wrong value", %{conn: conn} do
      session = PhoenixTestDatastar.visit(conn, "/counter")

      assert_raise ExUnit.AssertionError, ~r/Expected signal "count"/, fn ->
        assert_signal(session, "count", 999)
      end
    end

    test "assert_signal_set checks signal exists", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> assert_signal_set("count")
    end

    test "assert_signal_set fails for missing signal", %{conn: conn} do
      session = PhoenixTestDatastar.visit(conn, "/counter")

      assert_raise ExUnit.AssertionError, ~r/Expected signal "nonexistent"/, fn ->
        assert_signal_set(session, "nonexistent")
      end
    end

    test "refute_signal checks signal absent", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> refute_signal("nonexistent")
    end

    test "refute_signal fails when signal exists", %{conn: conn} do
      session = PhoenixTestDatastar.visit(conn, "/counter")

      assert_raise ExUnit.AssertionError, ~r/Expected signal "count" not to be set/, fn ->
        refute_signal(session, "count")
      end
    end
  end

  describe "within scope" do
    test "scopes assertions to a selector", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/counter")
      |> within("#app", fn session ->
        session
        |> assert_has("h1", text: "Counter")
        |> assert_has("#count", text: "0")
      end)
    end
  end
end
