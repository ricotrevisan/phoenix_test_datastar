defmodule PhoenixTestDatastar.Stream do
  @moduledoc """
  Manages long-lived SSE stream connections for testing real-time Datastar features.

  This module enables testing of handlers that enter receive loops
  (e.g., waiting for PubSub messages). It spawns the handler in a
  separate task and forwards SSE chunks to the test process.

  ## Usage

      session
      |> PhoenixTestDatastar.Stream.open_stream("/ds/my_handler/listen")
      |> PhoenixTestDatastar.Stream.await_events()
      |> assert_signal("count", 1)
      |> PhoenixTestDatastar.Stream.close_stream()
  """

  alias PhoenixTest.Dstar.SSE
  alias PhoenixTestDatastar.Dispatcher
  alias PhoenixTestDatastar.Session
  alias PhoenixTestDatastar.Signals
  alias PhoenixTestDatastar.StreamAdapter

  @default_timeout 5_000

  @doc """
  Opens a long-lived SSE stream connection.

  Spawns the handler in a task and sets up the session to receive
  SSE events via process messages.

  ## Options

  - `:method` - HTTP method (default: `:get`)
  - `:timeout` - Timeout for initial connection in ms (default: 5000)

  ## Examples

      session
      |> open_stream("/ds/my_handler/listen")
      |> await_events()
  """
  @spec open_stream(%Session{}, String.t(), keyword()) :: %Session{}
  def open_stream(%Session{} = session, path, opts \\ []) do
    method = Keyword.get(opts, :method, :get)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    ref = make_ref()
    adapter = StreamAdapter.new(self(), ref)

    # Build the conn with our custom adapter
    conn = build_stream_conn(session, adapter, ref, method, path)

    # Spawn the handler in a task
    endpoint = PhoenixTest.EndpointHelpers.endpoint_from!(session.conn)

    task =
      Task.async(fn ->
        try do
          endpoint.call(conn, endpoint.init([]))
        rescue
          _ -> :handler_crashed
        end
      end)

    # Wait for the stream to start
    receive do
      {:stream_started, ^ref, _status, _headers} ->
        %{session | conn: Map.put(session.conn.private, :stream_task, task)
                         |> then(&%{session.conn | private: &1})}
        |> put_stream_info(task, ref)

      {:stream_resp, ^ref, _status, _headers, _body} ->
        # Handler sent a regular response instead of chunked
        Task.await(task, timeout)
        session
    after
      timeout ->
        Task.shutdown(task, :brutal_kill)

        raise "Timeout waiting for SSE stream to start on #{path}. " <>
                "The handler must call Dstar.start/1 to begin an SSE stream."
    end
  end

  @doc """
  Waits for SSE events from an open stream and applies them to the session.

  Collects all available events within the timeout window.

  ## Options

  - `:timeout` - Maximum time to wait for events in ms (default: 5000)
  - `:count` - Number of events to wait for (default: collect all available)

  ## Examples

      session
      |> open_stream("/stream")
      |> await_events()          # Wait for any events
      |> await_events(count: 2)  # Wait for exactly 2 events
  """
  @spec await_events(%Session{}, keyword()) :: %Session{}
  def await_events(%Session{} = session, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    count = Keyword.get(opts, :count, nil)

    {_task, ref} = get_stream_info!(session)

    chunks = collect_chunks(ref, timeout, count, [])

    # Parse all collected chunks as SSE events
    raw_sse = Enum.join(chunks, "")
    events = SSE.parse(raw_sse)

    # Apply events to session
    Dispatcher.apply_events(session, events)
  end

  @doc """
  Closes an open SSE stream.

  Shuts down the task running the handler.

  ## Examples

      session
      |> open_stream("/stream")
      |> await_events()
      |> close_stream()
  """
  @spec close_stream(%Session{}) :: %Session{}
  def close_stream(%Session{} = session) do
    {task, _ref} = get_stream_info!(session)
    Task.shutdown(task, :brutal_kill)

    session
    |> clear_stream_info()
  end

  @doc """
  Checks if a session has an open stream.
  """
  @spec stream_open?(%Session{}) :: boolean()
  def stream_open?(%Session{} = session) do
    case get_stream_info(session) do
      nil -> false
      {_task, _ref} -> true
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────

  defp build_stream_conn(session, adapter, _ref, method, path) do
    # Build request body for POST
    {path, body} =
      case method do
        :get ->
          query = Signals.to_get_query(session.signals)

          path =
            if query != "" and query != "datastar=%7B%7D" do
              path <> "?" <> query
            else
              path
            end

          {path, ""}

        _ ->
          {path, Signals.to_post_body(session.signals)}
      end

    uri = URI.parse(path)
    query_string = uri.query || ""
    request_path = uri.path || path

    %Plug.Conn{
      adapter: {StreamAdapter, %{adapter | test_state: %{req_body: body}}},
      host: "www.example.com",
      method: method |> to_string() |> String.upcase(),
      owner: self(),
      path_info: String.split(request_path, "/", trim: true),
      path_params: %{},
      port: 80,
      query_string: query_string,
      remote_ip: {127, 0, 0, 1},
      req_headers: build_stream_headers(session, method),
      request_path: request_path,
      scheme: :http
    }
    |> Plug.Conn.put_private(:phoenix_endpoint, PhoenixTest.EndpointHelpers.endpoint_from!(session.conn))
    |> Plug.Conn.put_private(:phoenix_router, session.conn.private[:phoenix_router])
  end

  defp build_stream_headers(session, method) do
    headers = [
      {"host", "www.example.com"},
      {"datastar-request", "true"}
    ]

    headers =
      if method in [:post, :put, :patch, :delete] do
        [{"content-type", "application/json"} | headers]
      else
        headers
      end

    headers =
      if session.csrf_token do
        [{"x-csrf-token", session.csrf_token} | headers]
      else
        headers
      end

    headers
  end

  defp collect_chunks(ref, timeout, count, acc) do
    remaining = if count, do: count - length(acc), else: nil

    if remaining != nil and remaining <= 0 do
      Enum.reverse(acc)
    else
      receive do
        {:stream_chunk, ^ref, data} ->
          new_acc = [data | acc]

          if remaining != nil and length(new_acc) >= count do
            Enum.reverse(new_acc)
          else
            # Try to collect more with a short timeout
            collect_chunks(ref, 100, count, new_acc)
          end
      after
        timeout ->
          Enum.reverse(acc)
      end
    end
  end

  # Stream info is stored in conn.private under :stream_info
  defp put_stream_info(session, task, ref) do
    conn = Plug.Conn.put_private(session.conn, :stream_info, {task, ref})
    %{session | conn: conn}
  end

  defp get_stream_info(%Session{conn: conn}) do
    conn.private[:stream_info]
  end

  defp get_stream_info!(%Session{} = session) do
    case get_stream_info(session) do
      nil ->
        raise "No open stream. Call open_stream/2 first."

      info ->
        info
    end
  end

  defp clear_stream_info(session) do
    private = Map.delete(session.conn.private, :stream_info)
    %{session | conn: %{session.conn | private: private}}
  end
end
