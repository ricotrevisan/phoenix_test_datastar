Application.put_env(:phoenix_test_datastar, PhoenixTestDatastar.TestEndpoint,
  server: false,
  secret_key_base: String.duplicate("a", 64),
  url: [host: "localhost"]
)

Application.put_env(:phoenix_test, :endpoint, PhoenixTestDatastar.TestEndpoint)

{:ok, _} = PhoenixTestDatastar.TestEndpoint.start_link()

ExUnit.start()
