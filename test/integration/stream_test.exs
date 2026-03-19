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
      {task, _ref} = session.conn.private[:stream_info]

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
end
