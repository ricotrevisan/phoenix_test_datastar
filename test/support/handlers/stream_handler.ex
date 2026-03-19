defmodule PhoenixTestDatastar.TestHandlers.StreamHandler do
  @moduledoc """
  Test handler that demonstrates long-lived SSE streaming.

  Uses Phoenix.PubSub to simulate real-time updates.
  """

  def handle_event(conn, "listen", _signals) do
    conn = Dstar.start(conn)

    # Send initial data
    conn =
      conn
      |> Dstar.patch_signals(%{count: 0, status: "connected"})
      |> Dstar.patch_elements(~s(<span id="count">0</span>), selector: "#count")
      |> Dstar.patch_elements(~s(<span id="status">connected</span>), selector: "#status")

    # Enter receive loop for PubSub messages
    stream_loop(conn)
  end

  defp stream_loop(conn) do
    receive do
      {:update_count, count} ->
        case Dstar.check_connection(conn) do
          {:ok, conn} ->
            conn
            |> Dstar.patch_signals(%{count: count})
            |> Dstar.patch_elements(~s(<span id="count">#{count}</span>), selector: "#count")
            |> stream_loop()

          {:error, _conn} ->
            :ok
        end

      :stop ->
        :ok
    after
      30_000 ->
        :ok
    end
  end
end
