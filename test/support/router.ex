defmodule PhoenixTestDatastar.TestRouter do
  @moduledoc false
  use Phoenix.Router
  import Dstar.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_query_params)
  end

  pipeline :authenticated do
    plug(:fetch_session)
    plug(:protect_from_forgery)
  end

  scope "/", PhoenixTestDatastar.TestHandlers do
    pipe_through([:browser, :authenticated])

    get("/authenticate-stream", PageController, :authenticate_stream)
    dstar("/authenticated-stream", StreamPage)
  end

  scope "/", PhoenixTestDatastar.TestHandlers do
    pipe_through(:browser)

    get("/counter", PageController, :counter)
    get("/form", PageController, :form)
    get("/standard-form", PageController, :standard_form)
    get("/links", PageController, :links)
    get("/redirected", PageController, :redirected)
    get("/multi-action", PageController, :multi_action)
    get("/data-init", PageController, :data_init)
    get("/nested-signals", PageController, :nested_signals)
    get("/stream", PageController, :stream)

    # Page-local event routes (dstar >= 0.1.0-alpha.2 page helpers)
    get("/wire", PageController, :wire)
    post("/wire/_event/wire_check", PageController, :wire_event)
    get("/connect-page", PageController, :connect_page)
    post("/connect-page", PageController, :connect_stream)
    get("/connect-search", PageController, :connect_search_page)
    post("/connect-search", PageController, :connect_search_stream)

    # dstar >= 0.3 component and module-form action URLs
    get("/component", PageController, :component)
    get("/:workspace/component", PageController, :component)
    get("/dynamic", PageController, :dynamic)
  end

  # Component dispatch under a workspace base (`<body data-ds-base="/acme/ds">`)
  # and module actions rendered with `prefix: "/acme"`.
  scope "/acme" do
    dstar_components("/ds", [
      PhoenixTestDatastar.TestHandlers.WidgetComponent,
      PhoenixTestDatastar.TestHandlers.CounterHandler
    ])
  end

  # Dstar dispatch route — handles all Datastar SSE requests
  scope "/" do
    post("/ds/:module/:event", Dstar.Plugs.Dispatch,
      modules: [
        PhoenixTestDatastar.TestHandlers.CounterHandler,
        PhoenixTestDatastar.TestHandlers.FormHandler,
        PhoenixTestDatastar.TestHandlers.RedirectHandler,
        PhoenixTestDatastar.TestHandlers.InitHandler,
        PhoenixTestDatastar.TestHandlers.MultiHandler,
        PhoenixTestDatastar.TestHandlers.WidgetComponent
      ]
    )

    get("/ds/:module/:event", Dstar.Plugs.Dispatch,
      modules: [
        PhoenixTestDatastar.TestHandlers.InitHandler,
        PhoenixTestDatastar.TestHandlers.StreamHandler
      ]
    )
  end
end
