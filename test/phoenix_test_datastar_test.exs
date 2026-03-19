defmodule PhoenixTestDatastarTest do
  use ExUnit.Case, async: true

  alias PhoenixTestDatastar.Session

  test "build/1 creates a session" do
    conn = Phoenix.ConnTest.build_conn()
    session = PhoenixTestDatastar.build(conn)

    assert %Session{} = session
    assert session.signals == %{}
    assert session.raw_html == ""
    assert session.current_path == "/"
    assert session.csrf_token == nil
  end

  test "get_signal/2 returns signal value" do
    conn = Phoenix.ConnTest.build_conn()
    session = PhoenixTestDatastar.build(conn)
    session = %{session | signals: %{"count" => 42}}

    assert PhoenixTestDatastar.get_signal(session, "count") == 42
    assert PhoenixTestDatastar.get_signal(session, "missing") == nil
  end

  test "put_signal/3 sets a signal" do
    conn = Phoenix.ConnTest.build_conn()
    session = PhoenixTestDatastar.build(conn)
    session = PhoenixTestDatastar.put_signal(session, "count", 5)

    assert session.signals == %{"count" => 5}
  end

  test "get_signals/1 returns all signals" do
    conn = Phoenix.ConnTest.build_conn()
    session = PhoenixTestDatastar.build(conn)
    session = %{session | signals: %{"a" => 1, "b" => 2}}

    assert PhoenixTestDatastar.get_signals(session) == %{"a" => 1, "b" => 2}
  end
end
