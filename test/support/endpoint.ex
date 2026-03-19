defmodule PhoenixTestDatastar.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :phoenix_test_datastar

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride

  plug PhoenixTestDatastar.TestRouter
end
