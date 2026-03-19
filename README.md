# PhoenixTestDatastar

[![Module Version](https://img.shields.io/hexpm/v/phoenix_test_datastar.svg)](https://hex.pm/packages/phoenix_test_datastar/)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/phoenix_test_datastar/)
[![License](https://img.shields.io/hexpm/l/phoenix_test_datastar.svg)](https://github.com/TODO/phoenix_test_datastar/blob/main/LICENSE)

A [PhoenixTest](https://hexdocs.pm/phoenix_test) driver for
[Dstar](https://hexdocs.pm/dstar)-powered Phoenix applications.

Write feature tests using the same `visit`, `click_button`, `fill_in`, and
`assert_has` API you already know — PhoenixTestDatastar handles the Datastar
parts: signals, SSE responses, and DOM patching.

```elixir
test "counter increments", %{conn: conn} do
  conn
  |> visit("/counter")
  |> click_button("+1")
  |> assert_has("#count", text: "1")
end
```

No browser. No JavaScript runtime. Just ExUnit.

## Why?

Dstar brings [Datastar's](https://data-star.dev/) reactive UI to Phoenix via
Server-Sent Events. It's a different model from both static pages and LiveView:

|                    | Static Pages       | LiveView              | Dstar                          |
|--------------------|--------------------|-----------------------|--------------------------------|
| **Transport**      | HTTP request/response | WebSocket          | SSE over HTTP                  |
| **State**          | Server sessions    | Server process        | Client-side signals            |
| **Interaction**    | Form submits       | `phx-click`           | `data-on:click="@post(...)"` |
| **DOM updates**    | Full page reload   | Diff patching via WS  | SSE `patch-elements` events    |

PhoenixTest's static driver understands HTML forms. Its Live driver understands
`phx-*` bindings. Neither understands `data-signals`, `@post()`, or SSE event
streams.

PhoenixTestDatastar is the third driver. It **simulates the Datastar JavaScript
client** inside your test process: maintaining signal state, dispatching HTTP
requests, parsing SSE responses, and applying patches to an in-memory DOM.

## Installation

Add `phoenix_test_datastar` to your test dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_test_datastar, "~> 0.1.0", only: :test, runtime: false}
  ]
end
```

### Configuration

PhoenixTestDatastar uses the same endpoint config as PhoenixTest. In
`config/test.exs`:

```elixir
config :phoenix_test, :endpoint, MyAppWeb.Endpoint
```

### Setup

Create a `DatastarCase` helper in `test/support/datastar_case.ex`:

```elixir
defmodule MyAppWeb.DatastarCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import PhoenixTest
      import PhoenixTestDatastar
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(
      MyApp.Repo, shared: not tags[:async]
    )
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, conn: PhoenixTestDatastar.build(MyAppWeb.Endpoint)}
  end
end
```

> **Note:** The entry point is `PhoenixTestDatastar.build(Endpoint)` instead of
> `Phoenix.ConnTest.build_conn()`. This returns a session struct that routes
> through the Datastar driver — the same pattern used by
> [PhoenixTest.Playwright](https://hexdocs.pm/phoenix_test_playwright).

## Usage

### Clicking buttons

Datastar buttons use `data-on:click="@post(...)"` instead of form submissions.
PhoenixTestDatastar detects these automatically:

```elixir
test "counter increments and decrements", %{conn: conn} do
  conn
  |> visit("/counter")
  |> click_button("+1")
  |> click_button("+1")
  |> assert_has("#count", text: "2")
  |> click_button("−1")
  |> assert_has("#count", text: "1")
end
```

When you call `click_button`, the driver:

1. Finds the button in the DOM
2. Reads its `data-on:click` attribute (e.g., `@post('/ds/counter_events/increment')`)
3. Builds a POST request with the current signals as JSON body
4. Dispatches through your endpoint
5. Parses the SSE response (`patch-signals`, `patch-elements`)
6. Applies patches to the in-memory DOM and signal state

Standard form buttons (without Datastar attributes) fall back to regular form
submission — so pages that mix Datastar and traditional forms work correctly.

### Filling in forms

Datastar inputs use `data-bind` to bind to signals. PhoenixTestDatastar handles
both signal-bound and traditional form inputs:

```elixir
test "search filters results", %{conn: conn} do
  conn
  |> visit("/users")
  |> fill_in("Search", with: "Aragorn")
  |> click_button("Filter")
  |> assert_has(".user", text: "Aragorn")
  |> refute_has(".user", text: "Gandalf")
end
```

For `data-bind` inputs, `fill_in` updates the signal directly. For traditional
inputs, it tracks the value for form submission — same as PhoenixTest's static
driver.

### Assertions

All standard PhoenixTest assertions work:

```elixir
conn
|> visit("/dashboard")
|> assert_has("h1", text: "Dashboard")
|> assert_has("#user-count", text: "42")
|> refute_has(".error")
|> assert_path("/dashboard")
```

### Signal assertions

PhoenixTestDatastar adds signal-aware assertions for testing reactive state:

```elixir
conn
|> visit("/counter")
|> assert_signal("count", 0)
|> click_button("+1")
|> assert_signal("count", 1)
```

### Navigation and redirects

Dstar redirects work via `Dstar.redirect/2`, which sends a script that sets
`window.location.href`. The driver detects these and follows the redirect:

```elixir
test "login redirects to dashboard", %{conn: conn} do
  conn
  |> visit("/login")
  |> fill_in("Email", with: "aragorn@gondor.com")
  |> fill_in("Password", with: "anduril")
  |> click_button("Sign in")
  |> assert_path("/dashboard")
  |> assert_has("h1", text: "Welcome back")
end
```

### Scoping with `within`

When a page has multiple forms or repeated elements, scope your interactions:

```elixir
test "edit specific todo", %{conn: conn} do
  conn
  |> visit("/todos")
  |> within("#todo-1", fn session ->
    session
    |> click_button("Complete")
  end)
  |> assert_has("#todo-1.completed")
end
```

### Debugging with `open_browser`

Inspect the current DOM state in your browser:

```elixir
conn
|> visit("/counter")
|> click_button("+1")
|> open_browser()  # opens the current HTML in your default browser
|> click_button("+1")
```

### Escape hatch with `unwrap`

Access the raw session data when you need it:

```elixir
conn
|> visit("/counter")
|> unwrap(fn %{conn: conn, signals: signals} ->
  assert signals["count"] == 0
  conn
end)
```

## How it works

```
┌─────────────────────────────────────────────────────┐
│                   Test Code                         │
│  conn |> visit("/counter") |> click_button("+1")   │
│       |> assert_has("#count", text: "1")            │
└────────────────────┬────────────────────────────────┘
                     │ PhoenixTest.Driver protocol
    ┌────────────────▼────────────────┐
    │   PhoenixTestDatastar.Session   │
    │                                 │
    │  • Signal Store (%{count: 0})   │
    │  • DOM (in-memory HTML)         │
    │  • SSE Parser                   │
    │  • Action Dispatcher            │
    └────────────────┬────────────────┘
                     │ Phoenix.ConnTest.dispatch
    ┌────────────────▼────────────────┐
    │   Your Phoenix Endpoint         │
    │   Router → Dstar Handlers       │
    └─────────────────────────────────┘
```

On `visit/2`, the driver makes a standard GET request, extracts signals from
`data-signals` attributes, and stores the HTML.

On `click_button/2`, it finds the Datastar action expression, POSTs the current
signals as JSON, parses the SSE response, and applies `patch-signals` and
`patch-elements` events to update state.

Assertions query the in-memory DOM — no network requests needed.

## Supported PhoenixTest API

PhoenixTestDatastar implements the full `PhoenixTest.Driver` protocol:

| Function | Datastar behavior |
|----------|-------------------|
| `visit/2` | GET request, extract signals from `data-signals` attributes |
| `click_button/2,3` | Detect `data-on:click`, dispatch `@post`/`@get`, apply SSE |
| `click_link/2,3` | Detect `data-on:click` or follow `href` |
| `fill_in/3,4` | Update signal (if `data-bind`) or track form value |
| `select/3,4` | Update signal or track selection |
| `check/2,3` | Update signal or track checkbox |
| `uncheck/2,3` | Update signal or track checkbox |
| `choose/2,3` | Update signal or track radio |
| `submit/1` | Submit active form |
| `within/3` | Scope to CSS selector |
| `assert_has/2,3` | Query in-memory DOM |
| `refute_has/2,3` | Query in-memory DOM |
| `assert_path/2,3` | Check current path |
| `refute_path/2,3` | Check current path |
| `open_browser/1` | Open HTML in system browser |
| `unwrap/2` | Access raw conn, signals, HTML |

## Dependencies

- [phoenix_test](https://hex.pm/packages/phoenix_test) — Driver protocol and test helpers
- [phoenix](https://hex.pm/packages/phoenix) — ConnTest dispatching
- [floki](https://hex.pm/packages/floki) — DOM parsing and patching
- [jason](https://hex.pm/packages/jason) — JSON encoding/decoding

Dstar itself is **not** a dependency. The driver only understands the Datastar
SSE wire format and HTML attribute conventions. This keeps the packages loosely
coupled and means PhoenixTestDatastar works with any Elixir library that speaks
the Datastar protocol.

## License

MIT
