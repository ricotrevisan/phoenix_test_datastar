defmodule PhoenixTestDatastar do
  @moduledoc """
  A PhoenixTest driver for Datastar-powered Phoenix applications.

  Provides a way to test Datastar apps through the standard PhoenixTest API.
  It maintains client-side signal state, dispatches HTTP requests, parses SSE
  responses, and applies DOM patches.

  ## Setup

  Configure your endpoint in `config/test.exs`:

      config :phoenix_test, :endpoint, MyAppWeb.Endpoint

  Or set it on the conn:

      conn = Phoenix.ConnTest.build_conn() |> PhoenixTest.put_endpoint(MyAppWeb.Endpoint)

  ## Usage

      import PhoenixTest

      test "counter increments", %{conn: conn} do
        conn
        |> PhoenixTestDatastar.visit("/counter")
        |> click_button("Increment")
        |> assert_has("#count", text: "1")
      end
  """

  alias PhoenixTestDatastar.Session

  @doc """
  Visits a page and creates a Datastar session.

  This is the entry point for Datastar tests. It makes a GET request to the
  given path, extracts signals from the HTML, and returns a session that
  can be used with standard PhoenixTest functions.
  """
  def visit(conn, path) do
    session = build(conn)
    PhoenixTest.Driver.visit(session, path)
  end

  @doc """
  Builds a new Datastar session from a Plug.Conn.

  This creates the initial session struct. You typically don't need to call
  this directly - use `visit/2` instead.
  """
  def build(conn) do
    %Session{
      conn: conn,
      raw_html: "",
      current_path: "/",
      signals: %{},
      csrf_token: nil
    }
  end

  @doc """
  Gets a signal value from the session.

  ## Examples

      signal_value = PhoenixTestDatastar.get_signal(session, "count")
  """
  def get_signal(%Session{signals: signals}, name) do
    Map.get(signals, name)
  end

  @doc """
  Gets all signals from the session.

  ## Examples

      all_signals = PhoenixTestDatastar.get_signals(session)
  """
  def get_signals(%Session{signals: signals}) do
    signals
  end

  @doc """
  Sets a signal value in the session. Useful for test setup.

  ## Examples

      session = PhoenixTestDatastar.put_signal(session, "count", 5)
  """
  def put_signal(%Session{} = session, name, value) do
    %{session | signals: Map.put(session.signals, name, value)}
  end
end
