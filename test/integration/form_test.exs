defmodule PhoenixTestDatastar.Integration.FormTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  describe "fill_in with data-bind" do
    test "updates signal when filling in data-bound input", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/form")
      |> fill_in("Name", with: "Alice")
      |> assert_signal("name", "Alice")
    end

    test "updates multiple signals", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/form")
      |> fill_in("Name", with: "Bob")
      |> fill_in("Email", with: "bob@example.com")
      |> assert_signal("name", "Bob")
      |> assert_signal("email", "bob@example.com")
    end
  end

  describe "select with data-bind" do
    test "updates signal when selecting option", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/form")
      |> select("Favorite Color", option: "Blue")
      |> assert_signal("color", "blue")
    end
  end

  describe "check/uncheck with data-bind" do
    test "updates signal when checking checkbox", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/form")
      |> check("I agree")
      |> assert_signal("agree", true)
    end

    test "updates signal when unchecking checkbox", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/form")
      |> check("I agree")
      |> uncheck("I agree")
      |> assert_signal("agree", false)
    end
  end

  describe "choose with data-bind" do
    test "updates signal when choosing radio", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/form")
      |> choose("Admin")
      |> assert_signal("role", "admin")
    end
  end

  describe "submit with datastar form" do
    test "submits form with signal values", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/form")
      |> fill_in("Name", with: "Alice")
      |> fill_in("Email", with: "alice@example.com")
      |> select("Favorite Color", option: "Green")
      |> click_button("Submit")
      |> assert_has("#result-name", text: "Name: Alice")
      |> assert_has("#result-email", text: "Email: alice@example.com")
      |> assert_has("#result-color", text: "Color: green")
    end
  end

  describe "standard form (non-Datastar)" do
    test "fills in and submits a standard form", %{conn: conn} do
      conn
      |> PhoenixTestDatastar.visit("/standard-form")
      |> fill_in("Username", with: "alice")
      |> click_button("Login")
      |> assert_has("h1", text: "You were redirected!")
    end
  end
end
