defmodule PhoenixTestDatastar.DatastarCase do
  @moduledoc """
  ExUnit case template for Datastar integration tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import PhoenixTest
      import PhoenixTestDatastar.Assertions
    end
  end

  setup _tags do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_private(:phoenix_endpoint, PhoenixTestDatastar.TestEndpoint)
      |> Plug.Conn.put_private(:phoenix_router, PhoenixTestDatastar.TestRouter)

    {:ok, conn: conn}
  end
end
