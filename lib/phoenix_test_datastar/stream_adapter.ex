defmodule PhoenixTestDatastar.StreamAdapter do
  @moduledoc """
  Custom Plug adapter for testing long-lived SSE connections.

  This adapter intercepts `send_chunked/3` and `chunk/2` calls,
  forwarding chunks as messages to a subscriber process. This allows
  tests to consume SSE events from handlers that enter long-lived
  receive loops (e.g., waiting for PubSub messages).

  ## How it works

  1. The adapter wraps the standard test adapter
  2. When `send_chunked/3` is called, it notifies the subscriber
  3. When `chunk/2` is called, it sends the chunk content to the subscriber
  4. The subscriber can `receive` these messages and parse them as SSE events
  """

  @behaviour Plug.Conn.Adapter

  defstruct [:subscriber, :test_state, :ref]

  @doc false
  def new(subscriber, ref) do
    %__MODULE__{
      subscriber: subscriber,
      test_state: nil,
      ref: ref
    }
  end

  # ── Plug.Conn.Adapter callbacks ────────────────────────────────────────

  @impl true
  def send_resp(%__MODULE__{} = state, status, headers, body) do
    send(state.subscriber, {:stream_resp, state.ref, status, headers, body})
    {:ok, body, state}
  end

  @impl true
  def send_file(%__MODULE__{} = state, _status, _headers, _path, _offset, _length) do
    {:ok, nil, state}
  end

  @impl true
  def send_chunked(%__MODULE__{} = state, status, headers) do
    send(state.subscriber, {:stream_started, state.ref, status, headers})
    {:ok, nil, state}
  end

  @impl true
  def chunk(%__MODULE__{} = state, body) do
    data = IO.iodata_to_binary(body)
    send(state.subscriber, {:stream_chunk, state.ref, data})
    {:ok, nil, state}
  end

  @impl true
  def read_req_body(%__MODULE__{test_state: %{req_body: body}} = state, _opts) do
    {:ok, body, %{state | test_state: %{state.test_state | req_body: ""}}}
  end

  def read_req_body(%__MODULE__{} = state, _opts) do
    {:ok, "", state}
  end

  @impl true
  def inform(%__MODULE__{} = _state, _status, _headers) do
    {:error, :not_supported}
  end

  @impl true
  def push(%__MODULE__{} = _state, _path, _headers) do
    {:error, :not_supported}
  end

  @impl true
  def get_peer_data(%__MODULE__{}) do
    %{address: {127, 0, 0, 1}, port: 111_317, ssl_cert: nil}
  end

  @impl true
  def get_http_protocol(%__MODULE__{}) do
    :"HTTP/1.1"
  end

  @impl true
  def upgrade(%__MODULE__{} = _state, _protocol, _opts) do
    {:error, :not_supported}
  end
end
