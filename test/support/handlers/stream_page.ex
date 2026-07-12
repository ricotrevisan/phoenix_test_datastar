defmodule PhoenixTestDatastar.TestHandlers.StreamPage do
  @moduledoc false
  use Dstar.Page

  import Plug.Conn, only: [get_req_header: 2, get_session: 2]

  alias PhoenixTestDatastar.TestPubSub

  @stream_topic "authenticated-stream"
  @observer_topic "authenticated-stream-observer"

  @impl true
  def mount(conn, _params) do
    "test-user" = get_session(conn, :user_id)
    assign(conn, :csrf_token, Plug.CSRFProtection.get_csrf_token())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="stream-page"
      data-signals={
        Jason.encode!(%{
          count: 0,
          status: "disconnected",
          tabId: "integration-test-tab",
          _csrfToken: @csrf_token
        })
      }
      data-init={connect()}
    >
      <span id="count">0</span>
      <span id="status">disconnected</span>
    </div>
    """
  end

  @impl true
  def stream_key(conn), do: get_session(conn, :user_id)

  @impl true
  def handle_connect(conn, _params) do
    :ok = Phoenix.PubSub.subscribe(TestPubSub, @stream_topic)

    Phoenix.PubSub.broadcast(TestPubSub, @observer_topic, {
      :stream_connected,
      self(),
      get_session(conn, :user_id),
      get_req_header(conn, "x-csrf-token")
    })

    conn
    |> patch_signals(%{status: "connected"})
    |> patch_elements(~s(<span id="status">connected</span>), selector: "#status")
  end

  @impl true
  def handle_info({:set_count, count}, conn) do
    conn
    |> patch_signals(%{count: count})
    |> patch_elements(~s(<span id="count">#{count}</span>), selector: "#count")
  end
end
