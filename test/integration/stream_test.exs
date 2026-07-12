defmodule PhoenixTestDatastar.Integration.StreamTest do
  use PhoenixTestDatastar.DatastarCase, async: false

  alias PhoenixTestDatastar.Stream

  describe "open_stream/2" do
    test "opens an SSE stream and receives initial events", %{conn: conn} do
      session =
        conn
        |> PhoenixTestDatastar.visit("/stream")

      session =
        session
        |> Stream.open_stream("/ds/phoenix_test_datastar-test_handlers-stream_handler/listen")
        |> Stream.await_events()

      assert PhoenixTestDatastar.get_signal(session, "count") == 0
      assert PhoenixTestDatastar.get_signal(session, "status") == "connected"

      Stream.close_stream(session)
    end

    test "receives streamed updates via process messages", %{conn: conn} do
      session =
        conn
        |> PhoenixTestDatastar.visit("/stream")
        |> Stream.open_stream("/ds/phoenix_test_datastar-test_handlers-stream_handler/listen")
        |> Stream.await_events()

      # Get the stream task to send it a message
      {task, _ref} = Stream.stream_info(session)

      # Send a message to the handler process to trigger an update
      send(task.pid, {:update_count, 42})

      # Wait for the update
      session = Stream.await_events(session, timeout: 1_000)

      assert PhoenixTestDatastar.get_signal(session, "count") == 42

      Stream.close_stream(session)
    end

    test "stream_open?/1 reports stream state", %{conn: conn} do
      session =
        conn
        |> PhoenixTestDatastar.visit("/stream")

      refute Stream.stream_open?(session)

      session =
        session
        |> Stream.open_stream("/ds/phoenix_test_datastar-test_handlers-stream_handler/listen")
        |> Stream.await_events()

      assert Stream.stream_open?(session)

      session = Stream.close_stream(session)

      refute Stream.stream_open?(session)
    end
  end

  describe "authenticated Dstar.Page POST streams" do
    setup %{conn: conn} do
      :ok =
        Phoenix.PubSub.subscribe(
          PhoenixTestDatastar.TestPubSub,
          "authenticated-stream-observer"
        )

      endpoint = PhoenixTestDatastar.TestEndpoint

      conn =
        conn
        |> Phoenix.ConnTest.dispatch(endpoint, :get, "/authenticate-stream", nil)
        |> Phoenix.ConnTest.recycle()
        |> PhoenixTest.put_endpoint(endpoint)

      {:ok, conn: conn}
    end

    test "carries the authenticated session and CSRF token through the connect barrier", %{
      conn: conn
    } do
      session =
        open_authenticated_stream(conn)

      assert_receive {:stream_connected, stream_pid, "test-user", [csrf_token]}, 1_000
      assert csrf_token == session.csrf_token

      session = Stream.await_events(session)

      assert stream_pid == elem(Stream.stream_info(session), 0).pid
      assert_signal(session, "status", "connected")
      assert_has(session, "#status", text: "connected")

      Stream.close_stream(session)
    end

    test "applies PubSub-driven patches after the stream connects", %{conn: conn} do
      session =
        open_authenticated_stream(conn)

      assert_receive {:stream_connected, _stream_pid, "test-user", [_csrf_token]}, 1_000
      session = Stream.await_events(session)

      Phoenix.PubSub.broadcast(
        PhoenixTestDatastar.TestPubSub,
        "authenticated-stream",
        {:set_count, 42}
      )

      session = Stream.await_events(session, timeout: 1_000)

      assert_signal(session, "count", 42)
      assert_has(session, "#count", text: "42")

      Stream.close_stream(session)
    end

    test "a reconnect replaces the previous stream for the same page session", %{conn: conn} do
      session =
        open_authenticated_stream(conn)

      assert_receive {:stream_connected, first_pid, "test-user", [_csrf_token]}, 1_000
      assert Stream.stream_open?(session)

      reconnected = Stream.open_stream(session, "/authenticated-stream", method: :post)

      assert_receive {:stream_connected, second_pid, "test-user", [_csrf_token]}, 1_000
      assert first_pid != second_pid
      refute Process.alive?(first_pid)
      refute Stream.stream_open?(session)
      assert Stream.stream_open?(reconnected)

      Stream.close_stream(reconnected)
    end

    test "explicit close clears the session stream state", %{conn: conn} do
      session =
        open_authenticated_stream(conn)

      assert_receive {:stream_connected, _stream_pid, "test-user", [_csrf_token]}, 1_000
      assert Stream.stream_info(session)

      session = Stream.close_stream(session)

      refute Stream.stream_open?(session)
      assert Stream.stream_info(session) == nil
    end
  end

  defp open_authenticated_stream(conn) do
    session = PhoenixTestDatastar.visit(conn, "/authenticated-stream", init: false)

    assert Plug.Conn.get_req_header(session.conn, "cookie") != []
    assert Plug.Conn.get_resp_header(session.conn, "set-cookie") == []

    Stream.open_stream(session, "/authenticated-stream", method: :post)
  end
end
