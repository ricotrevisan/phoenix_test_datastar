defmodule PhoenixTestDatastar.TestRouter do
  @moduledoc false
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_query_params
  end

  scope "/", PhoenixTestDatastar.TestHandlers do
    pipe_through :browser

    get "/counter", PageController, :counter
    get "/form", PageController, :form
    get "/standard-form", PageController, :standard_form
    get "/links", PageController, :links
    get "/redirected", PageController, :redirected
    get "/multi-action", PageController, :multi_action
    get "/data-init", PageController, :data_init
    get "/nested-signals", PageController, :nested_signals
    get "/stream", PageController, :stream
  end

  # Dstar dispatch route — handles all Datastar SSE requests
  scope "/" do
    post "/ds/:module/:event", Dstar.Plugs.Dispatch,
      modules: [
        PhoenixTestDatastar.TestHandlers.CounterHandler,
        PhoenixTestDatastar.TestHandlers.FormHandler,
        PhoenixTestDatastar.TestHandlers.RedirectHandler,
        PhoenixTestDatastar.TestHandlers.InitHandler,
        PhoenixTestDatastar.TestHandlers.MultiHandler
      ]

    get "/ds/:module/:event", Dstar.Plugs.Dispatch,
      modules: [
        PhoenixTestDatastar.TestHandlers.InitHandler,
        PhoenixTestDatastar.TestHandlers.StreamHandler
      ]
  end
end
