# PhoenixTestDatastar

[![Module Version](https://img.shields.io/hexpm/v/phoenix_test_datastar.svg)](https://hex.pm/packages/phoenix_test_datastar/)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/phoenix_test_datastar/)
[![License](https://img.shields.io/hexpm/l/phoenix_test_datastar.svg)](https://hex.pm/packages/phoenix_test_datastar)

A [PhoenixTest](https://hexdocs.pm/phoenix_test) driver for
[Dstar](https://hexdocs.pm/dstar)-powered Phoenix applications.

Write feature tests using the same `visit`, `click_button`, `fill_in`, and
`assert_has` API you already know — PhoenixTestDatastar handles the Datastar
parts: signals, SSE responses, and DOM patching.

```elixir
test "torpedo launch increments warhead count", %{conn: conn} do
  conn
  |> visit("/rocinante/weapons")
  |> click_button("Fire torpedo")
  |> assert_has("#warheads-remaining", text: "4")
end
```

Test real-time SSE streams too — open a long-lived connection, trigger server
events, and assert on the updates as they arrive:

```elixir
alias PhoenixTestDatastar.Stream

test "sensor dashboard updates on new contact", %{conn: conn} do
  session =
    conn
    |> visit("/rocinante/sensors")
    |> Stream.open_stream("/ds/sensor_handler/listen")
    |> Stream.await_events()

  assert_signal(session, "contacts", 0)

  # Simulate a server-side event
  Phoenix.PubSub.broadcast(Roci.PubSub, "sensors", {:contact_detected, 1})

  session
  |> Stream.await_events()
  |> assert_signal("contacts", 1)
  |> assert_has("#contact-count", text: "1")
  |> Stream.close_stream()
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
    {:phoenix_test_datastar, "~> 0.0.3", only: :test, runtime: false}
  ]
end
```

### Configuration

PhoenixTestDatastar uses the same endpoint config as PhoenixTest. In
`config/test.exs`:

```elixir
config :phoenix_test, :endpoint, RociWeb.Endpoint
```

### Setup

Create a `DatastarCase` helper in `test/support/datastar_case.ex`:

```elixir
defmodule RociWeb.DatastarCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import PhoenixTest
      import PhoenixTestDatastar
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(
      Roci.Repo, shared: not tags[:async]
    )
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    conn =
      Phoenix.ConnTest.build_conn()
      |> PhoenixTest.put_endpoint(RociWeb.Endpoint)

    {:ok, conn: conn}
  end
end
```

Then in your tests, use `PhoenixTestDatastar.visit/2` as the entry point:

```elixir
test "my test", %{conn: conn} do
  conn
  |> PhoenixTestDatastar.visit("/some-page")
  |> click_button("Do something")
  |> assert_has("#result", text: "Done")
end
```

> **Note:** Use `PhoenixTestDatastar.visit/2` instead of `PhoenixTest.visit/2`.
> This returns a `PhoenixTestDatastar.Session` struct that routes through the
> Datastar driver. All subsequent `click_button`, `fill_in`, `assert_has` etc.
> calls work through PhoenixTest's standard API.

## Usage

### Clicking buttons

Datastar buttons use `data-on:click="@post(...)"` instead of form submissions.
PhoenixTestDatastar detects these automatically:

```elixir
test "adjust reactor output", %{conn: conn} do
  conn
  |> visit("/rocinante/engineering")
  |> click_button("Increase thrust")
  |> click_button("Increase thrust")
  |> assert_has("#reactor-output", text: "75%")
  |> click_button("Decrease thrust")
  |> assert_has("#reactor-output", text: "50%")
end
```

When you call `click_button`, the driver:

1. Finds the button in the DOM
2. Reads its `data-on:click` attribute (e.g., `@post('/ds/engineering_events/increase_thrust')`)
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
test "search filters crew roster", %{conn: conn} do
  conn
  |> visit("/rocinante/crew")
  |> fill_in("Search", with: "Holden")
  |> click_button("Filter")
  |> assert_has(".crew-member", text: "James Holden")
  |> refute_has(".crew-member", text: "Amos Burton")
end
```

For `data-bind` inputs, `fill_in` updates the signal directly. For traditional
inputs, it tracks the value for form submission — same as PhoenixTest's static
driver.

### Assertions

All standard PhoenixTest assertions work:

```elixir
conn
|> visit("/ops/dashboard")
|> assert_has("h1", text: "OPS Dashboard")
|> assert_has("#crew-count", text: "4")
|> refute_has(".hull-breach")
|> assert_path("/ops/dashboard")
```

### Signal assertions

Import `PhoenixTestDatastar.Assertions` for signal-aware assertions:

```elixir
import PhoenixTestDatastar.Assertions

test "torpedo launch decrements warhead count", %{conn: conn} do
  conn
  |> visit("/rocinante/weapons")
  |> assert_signal("warheads", 5)
  |> assert_signal_set("warheads")
  |> refute_signal("nonexistent")
  |> click_button("Fire torpedo")
  |> assert_signal("warheads", 4)
end
```

### Navigation and redirects

Dstar redirects work via `Dstar.redirect/2`, which sends a script that sets
`window.location.href`. The driver detects these and follows the redirect:

```elixir
test "login redirects to bridge", %{conn: conn} do
  conn
  |> visit("/login")
  |> fill_in("Callsign", with: "holden@rocinante.belt")
  |> fill_in("Access code", with: "donnager-7")
  |> click_button("Authenticate")
  |> assert_path("/bridge")
  |> assert_has("h1", text: "Welcome aboard, Captain")
end
```

### Scoping with `within`

When a page has multiple forms or repeated elements, scope your interactions:

```elixir
test "repair specific ship system", %{conn: conn} do
  conn
  |> visit("/rocinante/damage-report")
  |> within("#system-pdc-array", fn session ->
    session
    |> click_button("Repair")
  end)
  |> assert_has("#system-pdc-array.operational")
end
```

### Debugging with `open_browser`

Inspect the current DOM state in your browser:

```elixir
conn
|> visit("/rocinante/weapons")
|> click_button("Fire torpedo")
|> open_browser()  # opens the current HTML in your default browser
|> click_button("Fire torpedo")
```

### Real-time SSE streams

For handlers that enter long-lived receive loops (e.g., PubSub-driven updates),
use the streaming API:

```elixir
alias PhoenixTestDatastar.Stream

test "live dashboard updates on sensor change", %{conn: conn} do
  session =
    conn
    |> visit("/rocinante/sensors")
    |> Stream.open_stream("/ds/sensor_handler/listen")
    |> Stream.await_events()

  assert_signal(session, "contacts", 0)

  # Simulate external event (e.g., PubSub broadcast)
  Phoenix.PubSub.broadcast(Roci.PubSub, "sensors", {:contact_detected, 1})

  session
  |> Stream.await_events()
  |> assert_signal("contacts", 1)
  |> Stream.close_stream()
end
```

### `data-init` auto-dispatching

When visiting a page with `data-init` attributes, the driver automatically
dispatches the init actions — just like the Datastar JS client would:

```elixir
# If the page has: <div data-init="@get('/ds/dashboard/load')">
test "dashboard loads initial data on visit", %{conn: conn} do
  conn
  |> visit("/dashboard")           # data-init actions fire automatically
  |> assert_has("#stats", text: "42")
end
```

### Escape hatch with `unwrap`

Access the raw conn when you need it:

```elixir
conn
|> visit("/rocinante/weapons")
|> unwrap(fn conn ->
  # do something with the raw conn
  conn
end)
```

## How it works

```
┌──────────────────────────────────────────────────────────────────┐
│                        Test Code                                 │
│  conn |> visit("/rocinante/weapons") |> click_button("Fire")    │
│       |> assert_has("#warheads-remaining", text: "4")            │
└────────────────────┬─────────────────────────────────────────────┘
                     │ PhoenixTest.Driver protocol
    ┌────────────────▼────────────────┐
    │   PhoenixTestDatastar.Session   │
    │                                 │
    │  • Signal Store (%{warheads: 5}) │
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
`data-signals` attributes, and stores the HTML — like pulling up the Roci's
tactical display.

On `click_button/2`, it finds the Datastar action expression, POSTs the current
signals as JSON, parses the SSE response, and applies `patch-signals` and
`patch-elements` events to update state — like the CIC processing a fire
command.

Assertions query the in-memory DOM — no network round-trip needed.

## Supported PhoenixTest API

PhoenixTestDatastar implements the full PhoenixTest driver protocol:

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
| `unwrap/2` | Access raw conn |
| `reload_page/1` | Re-visit current path |

### Datastar-specific API

| Function | Description |
|----------|-------------|
| `PhoenixTestDatastar.visit/2` | Entry point — creates Datastar session |
| `PhoenixTestDatastar.get_signal/2` | Read a signal value |
| `PhoenixTestDatastar.get_signals/1` | Read all signals |
| `PhoenixTestDatastar.put_signal/3` | Set a signal (for test setup) |
| `PhoenixTestDatastar.Assertions.assert_signal/3` | Assert signal value |
| `PhoenixTestDatastar.Assertions.assert_signal_set/2` | Assert signal exists |
| `PhoenixTestDatastar.Assertions.refute_signal/2` | Assert signal absent |
| `PhoenixTestDatastar.Stream.open_stream/2` | Open SSE stream connection |
| `PhoenixTestDatastar.Stream.await_events/1` | Wait for and apply SSE events |
| `PhoenixTestDatastar.Stream.close_stream/1` | Close SSE stream |

## Dependencies

- [phoenix_test](https://hex.pm/packages/phoenix_test) — Driver protocol and test helpers
- [phoenix](https://hex.pm/packages/phoenix) — ConnTest dispatching
- [floki](https://hex.pm/packages/floki) — DOM parsing and patching
- [jason](https://hex.pm/packages/jason) — JSON encoding/decoding

### Dstar compatibility

Action URLs are resolved the way the Datastar client resolves them in the
browser, including the expressions dstar renders:

| dstar helper | Resolved against |
|--------------|------------------|
| `Dstar.post(Module, "event")`, `prefix:` | Literal `/ds/...` path |
| `Dstar.post("event")` (dynamic module) | The `_dstar_module` signal, percent-encoded like dstar does |
| `Dstar.Page.Helpers.event/2` | The session's current path + `/_event/<event>` |
| `Dstar.Page.Helpers.connect/1` (`include_search:`) | The session's current path (and query string) |
| `Dstar.Component` `event/2` | `<body data-ds-base>`, defaulting to `/ds` |

Both the dstar 0.3 URL shapes (double-quoted, percent-encoded literals) and the
older 0.1/0.2 shapes are supported. A URL expression the driver can't resolve
raises an `ArgumentError` rather than dispatching a garbage path.

If you interpolate dstar helpers into hand-written HTML strings, HTML-escape
them: dstar 0.3 renders double-quoted JavaScript literals, which break an
unescaped `data-on:click="..."` attribute. HEEx does this for you.

Dstar itself is **not** a dependency. The driver only understands the Datastar
SSE wire format and HTML attribute conventions. This keeps the packages loosely
coupled and means PhoenixTestDatastar works with any Elixir library that speaks
the Datastar protocol.

## License

MIT
