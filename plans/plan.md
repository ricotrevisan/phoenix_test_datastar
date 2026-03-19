# `phoenix_test_datastar` — Architecture & Implementation Plan

A PhoenixTest Driver that simulates the Datastar client, enabling full feature tests for Dstar-powered Phoenix applications using the PhoenixTest API.

---

## The Core Problem

Dstar is pure functions over `Plug.Conn` — no processes, no GenServers. But its interactivity model is fundamentally different from both static pages and LiveView:

| | Static Pages | LiveView | Dstar |
|---|---|---|---|
| **Transport** | HTTP request/response | WebSocket | SSE over HTTP |
| **State** | None (server-side sessions) | Server process | Client-side signals |
| **Interaction** | Form submits, link clicks | `phx-click`, `phx-change` | `data-on:click="@post(...)"` |
| **DOM updates** | Full page reload | Diff patching via socket | SSE `patch-elements` events |

PhoenixTest's static driver understands HTML forms and link navigation. Its Live driver understands `phx-*` bindings. Neither understands `data-signals`, `@post()`, or SSE event streams.

We need a third driver that **simulates the Datastar JS client**: maintaining signal state, dispatching `@post`/`@get` requests, parsing SSE responses, and applying patches to an in-memory DOM.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Test Code                         │
│  conn |> visit("/counter") |> click_button("+1")   │
│       |> assert_has("#count", "1")                  │
└────────────────────┬────────────────────────────────┘
                     │
         ┌───────────▼───────────┐
         │  PhoenixTest API      │
         │  (protocol dispatch)  │
         └───────────┬───────────┘
                     │
    ┌────────────────▼────────────────┐
    │   PhoenixTestDatastar.Session      │
    │   implements PhoenixTest.Driver │
    │                                 │
    │  ┌───────────────────────────┐  │
    │  │ Signal Store              │  │
    │  │ %{count: 0, name: "..."}  │  │
    │  └───────────────────────────┘  │
    │  ┌───────────────────────────┐  │
    │  │ DOM (Floki HTML tree)     │  │
    │  │ Current page HTML         │  │
    │  └───────────────────────────┘  │
    │  ┌───────────────────────────┐  │
    │  │ SSE Parser                │  │
    │  │ text/event-stream → cmds  │  │
    │  └───────────────────────────┘  │
    │  ┌───────────────────────────┐  │
    │  │ Action Dispatcher         │  │
    │  │ @post/@get → HTTP request │  │
    │  └───────────────────────────┘  │
    │  ┌───────────────────────────┐  │
    │  │ Stream Manager (Layer 2)  │  │
    │  │ Long-lived SSE via Task   │  │
    │  └───────────────────────────┘  │
    └─────────────────────────────────┘
```

---

## Package Structure

```
phoenix_test_datastar/
├── lib/
│   ├── phoenix_test_datastar.ex              # Public API & convenience functions
│   └── phoenix_test_datastar/
│       ├── session.ex                      # Session struct + Driver impl
│       ├── signals.ex                      # Signal extraction & state mgmt
│       ├── sse.ex                          # SSE response parser
│       ├── dom.ex                          # DOM querying & patching (Floki)
│       ├── actions.ex                      # @post/@get expression parser
│       ├── dispatcher.ex                   # HTTP request dispatcher
│       ├── stream.ex                       # Real-time SSE stream manager
│       └── assertions.ex                   # Dstar-specific assertions
├── test/
│   ├── test_helper.exs
│   ├── phoenix_test_datastar/
│   │   ├── signals_test.exs
│   │   ├── sse_test.exs
│   │   ├── dom_test.exs
│   │   ├── actions_test.exs
│   │   └── stream_test.exs
│   └── integration/
│       ├── support/
│       │   ├── endpoint.ex                 # Test Phoenix endpoint
│       │   ├── router.ex                   # Test router with Dstar routes
│       │   └── handlers/                   # Sample Dstar handlers
│       ├── click_test.exs
│       ├── form_test.exs
│       └── stream_test.exs
├── mix.exs
└── README.md
```

---

## Layer 1: Request/Response Flows

This is the bread and butter — click a button, POST with signals, parse SSE response, update DOM + signals.

### Session Struct

```elixir
defmodule PhoenixTestDatastar.Session do
  @enforce_keys [:conn, :endpoint, :html, :path]
  defstruct [
    :conn,           # The original Plug.Conn (for making new requests)
    :endpoint,       # Phoenix endpoint module
    :html,           # Current page HTML as string
    :path,           # Current request path
    :signals,        # %{} — current Datastar signal state
    :within,         # Optional CSS selector scope (for PhoenixTest.within/3)
    :stream_pid,     # Optional PID for active SSE stream (Layer 2)
    :csrf_token      # Extracted CSRF token
  ]
end
```

### The Visit Flow

When `visit/2` is called:

```elixir
defimpl PhoenixTest.Driver, for: PhoenixTestDatastar.Session do
  def visit(session, path) do
    # 1. Make a standard GET request via Phoenix.ConnTest
    conn =
      session.conn
      |> Phoenix.ConnTest.dispatch(session.endpoint, :get, path)

    html = conn.resp_body

    # 2. Extract signals from data-signals:* attributes
    signals = PhoenixTestDatastar.Signals.extract_from_html(html)

    # 3. Extract CSRF token from data-signals:_csrf-token
    csrf = Map.get(signals, "_csrfToken") || Map.get(signals, "_csrf-token")

    # 4. Return updated session
    %{session |
      html: html,
      path: path,
      signals: signals,
      csrf_token: csrf,
      conn: Phoenix.ConnTest.recycle(conn)
    }
  end
end
```

### Signal Extraction

Datastar signals live in HTML attributes like `data-signals:count="0"` and `data-signals:name="'hello'"`. They can also be nested: `data-signals="{user: {name: '', age: 0}}"`.

```elixir
defmodule PhoenixTestDatastar.Signals do
  @doc """
  Extract all signals from HTML by finding data-signals* attributes.
  
  Handles:
    - data-signals:count="0"          → %{"count" => 0}
    - data-signals:name="'hello'"     → %{"name" => "hello"}
    - data-signals="{foo: 1, bar: 2}" → %{"foo" => 1, "bar" => 2}
    - data-signals:_csrfToken="'...'" → %{"_csrfToken" => "..."}
  
  The _ prefix means "client-only" in Datastar — sent as headers,
  not in the JSON body. We track them but exclude from POST bodies.
  """
  def extract_from_html(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-signals], [data-signals\\:*]")
    # ... walk all attributes starting with "data-signals"
    # ... parse JS-like values into Elixir terms
  end

  @doc """
  Apply a patch-signals event to existing signal state.
  Handles onlyIfMissing flag.
  """
  def apply_patch(signals, patch, opts \\ []) do
    only_if_missing = Keyword.get(opts, :only_if_missing, false)

    Enum.reduce(patch, signals, fn {key, value}, acc ->
      cond do
        value == nil -> Map.delete(acc, key)  # null = remove
        only_if_missing and Map.has_key?(acc, key) -> acc
        true -> Map.put(acc, key, value)
      end
    end)
  end

  @doc """
  Build the JSON body for a POST request from current signals.
  Excludes signals with _ prefix (client-only).
  """
  def to_request_body(signals) do
    signals
    |> Enum.reject(fn {key, _} -> String.starts_with?(key, "_") end)
    |> Map.new()
    |> Jason.encode!()
  end

  @doc """
  Build query param for GET requests.
  Signals go under the "datastar" key.
  """
  def to_query_param(signals) do
    signals
    |> Enum.reject(fn {key, _} -> String.starts_with?(key, "_") end)
    |> Map.new()
    |> Jason.encode!()
    |> then(&%{"datastar" => &1})
    |> URI.encode_query()
  end
end
```

**Signal value parsing challenge**: Datastar uses JS-style values in attributes (`'hello'` for strings, `0` for numbers, `true`/`false` for booleans, `{nested: 'objects'}`). We need a lightweight parser for these JS-like expressions. Options:

1. **Regex-based heuristic** — handles 90% of cases (string literals, numbers, booleans)
2. **Adapt Jason** — preprocess JS object notation `{foo: 1}` → `{"foo": 1}` then parse as JSON
3. **Tiny parser** — a small recursive descent parser for the JS subset Datastar uses

Option 2 is the sweet spot. The transformation is mechanical: quote unquoted keys, convert single quotes to double quotes, handle unquoted identifiers (`true`/`false`/`null`).

### Action Expression Parser

When a user clicks a button with `data-on:click="@post('/counter/increment')"`, we need to parse that expression to know what HTTP request to make.

```elixir
defmodule PhoenixTestDatastar.Actions do
  @type action :: %{
    method: :get | :post | :put | :patch | :delete,
    url: String.t(),
    headers: map(),
    options: map()
  }

  @doc """
  Parse a Datastar action expression like:
    @post('/endpoint')
    @post('/endpoint', {headers: {'x-csrf-token': $_csrfToken}})
    @get('/endpoint', {filterSignals: {include: /^foo/}})
  
  Returns structured action data.
  """
  @spec parse(String.t()) :: {:ok, action()} | {:error, term()}
  def parse(expression) do
    # Match: @method('url') or @method('url', {options})
    regex = ~r/@(get|post|put|patch|delete)\(\s*'([^']+)'\s*(?:,\s*(\{.*\}))?\s*\)/s
    
    case Regex.run(regex, expression) do
      [_, method, url] ->
        {:ok, %{method: String.to_atom(method), url: url, headers: %{}, options: %{}}}
      
      [_, method, url, options_str] ->
        options = parse_options(options_str)
        headers = Map.get(options, "headers", %{})
        {:ok, %{method: String.to_atom(method), url: url, headers: headers, options: options}}
      
      nil ->
        {:error, :unparseable_action}
    end
  end

  @doc """
  Find the action expression on an element or its ancestors.
  Checks data-on:click, data-on:submit, data-init, etc.
  """
  def find_action(html_tree, element) do
    # Look for data-on:click="@post(...)" on the element
    # Then walk up ancestors for inherited actions
  end
end
```

### SSE Response Parser

This is the core engine. When Dstar sends a response, it's `text/event-stream` with chunks like:

```
event: datastar-patch-signals
data: signals {"count":1}

event: datastar-patch-elements
data: selector #count
data: mode outer
data: elements <span id="count">1</span>

```

```elixir
defmodule PhoenixTestDatastar.SSE do
  @type event :: %{
    type: :patch_signals | :patch_elements | :execute_script,
    data: map()
  }

  @doc """
  Parse a complete SSE response body into a list of Datastar events.
  
  The Plug test adapter accumulates all chunks in conn.resp_body,
  so for request/response flows we get the complete SSE stream
  as a single string after the handler returns.
  """
  @spec parse(String.t()) :: [event()]
  def parse(raw_sse) do
    raw_sse
    |> String.split("\n\n")           # SSE events separated by double newline
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_event/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_event(raw_event) do
    lines = String.split(raw_event, "\n")
    
    event_type =
      lines
      |> Enum.find_value(fn
        "event: " <> type -> type
        _ -> nil
      end)

    data_lines =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data: "))
      |> Enum.map(&String.trim_leading(&1, "data: "))

    case event_type do
      "datastar-patch-signals" -> parse_patch_signals(data_lines)
      "datastar-patch-elements" -> parse_patch_elements(data_lines)
      "datastar-execute-script" -> parse_execute_script(data_lines)
      _ -> nil
    end
  end

  defp parse_patch_signals(data_lines) do
    only_if_missing =
      Enum.any?(data_lines, &(&1 == "onlyIfMissing true"))

    signals_line =
      data_lines
      |> Enum.find_value(fn
        "signals " <> json -> json
        _ -> nil
      end)

    case signals_line do
      nil -> nil
      json ->
        %{
          type: :patch_signals,
          data: %{
            signals: parse_signals_json(json),
            only_if_missing: only_if_missing
          }
        }
    end
  end

  defp parse_patch_elements(data_lines) do
    # Collect multi-line elements (data lines starting with "elements ")
    elements =
      data_lines
      |> Enum.filter(&String.starts_with?(&1, "elements "))
      |> Enum.map(&String.trim_leading(&1, "elements "))
      |> Enum.join("\n")

    selector =
      Enum.find_value(data_lines, fn
        "selector " <> sel -> sel
        _ -> nil
      end)

    mode =
      Enum.find_value(data_lines, "outer", fn
        "mode " <> m -> m
        _ -> nil
      end)

    %{
      type: :patch_elements,
      data: %{
        elements: elements,
        selector: selector,
        mode: String.to_atom(mode)
      }
    }
  end

  defp parse_execute_script(data_lines) do
    script =
      data_lines
      |> Enum.filter(&String.starts_with?(&1, "script "))
      |> Enum.map(&String.trim_leading(&1, "script "))
      |> Enum.join("\n")

    %{type: :execute_script, data: %{script: script}}
  end
end
```

### DOM Patching

After parsing SSE events, we apply patches to the in-memory HTML:

```elixir
defmodule PhoenixTestDatastar.DOM do
  @doc """
  Apply a patch-elements event to the current HTML.
  Returns updated HTML string.
  """
  def apply_patch(html, %{selector: selector, elements: elements, mode: mode}) do
    doc = Floki.parse_document!(html)

    updated =
      case mode do
        :outer ->
          # Morph: replace matching elements by ID
          morph(doc, Floki.parse_fragment!(elements))

        :inner ->
          # Replace inner content of selector target
          replace_inner(doc, selector, elements)

        :append ->
          append_children(doc, selector, elements)

        :prepend ->
          prepend_children(doc, selector, elements)

        :remove ->
          Floki.filter_out(doc, selector)

        :before ->
          insert_before(doc, selector, elements)

        :after ->
          insert_after(doc, selector, elements)

        :replace ->
          replace_outer(doc, selector, elements)
      end

    Floki.raw_html(updated)
  end

  defp morph(doc, new_elements) do
    # For each new element with an id, find the matching element
    # in the doc and replace it. This is the default Datastar behavior.
    Enum.reduce(new_elements, doc, fn new_el, acc ->
      case Floki.attribute(new_el, "id") do
        [id] -> replace_by_id(acc, id, new_el)
        _ -> acc
      end
    end)
  end

  @doc """
  Find an element by CSS selector and return it.
  """
  def find(html, selector) do
    html |> Floki.parse_document!() |> Floki.find(selector)
  end
end
```

### The Dispatcher — Tying It All Together

When `click_button/2` is called, the driver needs to:

1. Find the button in the DOM
2. Detect if it has a Datastar action (vs a regular form submit)
3. If Datastar: parse the action, make the request, process SSE response
4. If regular: fall back to standard form submission behavior

```elixir
defmodule PhoenixTestDatastar.Dispatcher do
  @doc """
  Execute a Datastar action and return the updated session.
  """
  def dispatch(session, action) do
    # 1. Build the request
    conn = build_request(session, action)

    # 2. Dispatch through the endpoint
    result_conn =
      Phoenix.ConnTest.dispatch(conn, session.endpoint, action.method, action.url)

    # 3. Check content type to determine response handling
    content_type = get_content_type(result_conn)

    case content_type do
      "text/event-stream" ->
        # Parse SSE events from the accumulated response body
        events = PhoenixTestDatastar.SSE.parse(result_conn.resp_body)
        apply_events(session, events, result_conn)

      "text/html" ->
        # Direct HTML response — patch into DOM
        apply_html_response(session, result_conn)

      "application/json" ->
        # JSON signals response
        apply_json_response(session, result_conn)

      _ ->
        session
    end
  end

  defp build_request(session, %{method: :get} = action) do
    query = PhoenixTestDatastar.Signals.to_query_param(session.signals)
    url = action.url <> "?" <> query

    session.conn
    |> put_req_headers(action.headers)
    |> put_req_header("datastar-request", "true")

    # GET signals go as query params
  end

  defp build_request(session, action) do
    body = PhoenixTestDatastar.Signals.to_request_body(session.signals)

    session.conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("datastar-request", "true")
    |> put_csrf_header(session)
    |> put_req_headers(action.headers)
    # ... set body for JSON dispatch
  end

  defp apply_events(session, events, result_conn) do
    Enum.reduce(events, session, fn event, acc ->
      case event.type do
        :patch_signals ->
          signals = PhoenixTestDatastar.Signals.apply_patch(
            acc.signals,
            event.data.signals,
            only_if_missing: event.data.only_if_missing
          )
          %{acc | signals: signals}

        :patch_elements ->
          html = PhoenixTestDatastar.DOM.apply_patch(acc.html, event.data)
          %{acc | html: html}

        :execute_script ->
          handle_script(acc, event.data.script)
      end
    end)
    |> then(&%{&1 | conn: Phoenix.ConnTest.recycle(result_conn)})
  end

  defp handle_script(session, script) do
    # Handle known script patterns:
    # - window.location = '/path'  → update path
    # - console.log(...)           → no-op in tests
    cond do
      String.contains?(script, "window.location") ->
        path = extract_redirect_path(script)
        %{session | path: path}

      true ->
        session
    end
  end
end
```

### Driver Protocol Implementation

The full `PhoenixTest.Driver` implementation for the session:

```elixir
defimpl PhoenixTest.Driver, for: PhoenixTestDatastar.Session do
  alias PhoenixTestDatastar.{DOM, Actions, Dispatcher, Signals}

  # --- Navigation ---

  def visit(session, path) do
    # Standard GET, extract signals, build session
    # (as shown above)
  end

  def reload_page(session) do
    visit(session, session.path)
  end

  # --- Clicking ---

  def click_button(session, selector, text) do
    # 1. Find the button in the DOM
    button = DOM.find_button(session.html, selector, text)

    # 2. Check for Datastar action
    case Actions.find_action_on_element(session.html, button) do
      {:ok, action_expr} ->
        # It's a Datastar button — parse and dispatch
        {:ok, action} = Actions.parse(action_expr)
        action = resolve_signal_refs(action, session.signals)
        Dispatcher.dispatch(session, action)

      :none ->
        # Fall back to standard form submission behavior
        # (check for data-method, form action, etc.)
        dispatch_standard_form(session, button)
    end
  end

  def click_link(session, selector, text) do
    link = DOM.find_link(session.html, selector, text)

    case Actions.find_action_on_element(session.html, link) do
      {:ok, action_expr} ->
        {:ok, action} = Actions.parse(action_expr)
        Dispatcher.dispatch(session, action)

      :none ->
        # Standard link navigation
        href = DOM.get_attribute(link, "href")
        visit(session, href)
    end
  end

  # --- Form Filling ---
  # 
  # Dstar doesn't use traditional forms for most interactions.
  # But it CAN have forms (with contentType: 'form').
  # Signal-based inputs use data-bind:signal-name.
  #
  # When fill_in is called, we:
  # 1. Find the input by label
  # 2. Check if it has data-bind:* → update the signal
  # 3. Check if it's in a form with phx-change → trigger change
  # 4. Otherwise, track the value for form submission

  def fill_in(session, input_selector, label, opts) do
    value = Keyword.fetch!(opts, :with)
    input = DOM.find_input_by_label(session.html, input_selector, label)

    case DOM.get_data_bind(input) do
      {:ok, signal_name} ->
        # data-bind means this input is bound to a signal
        signals = Map.put(session.signals, signal_name, value)
        html = DOM.set_input_value(session.html, input, value)
        %{session | signals: signals, html: html}

      :none ->
        # Standard form input — track value in the DOM
        html = DOM.set_input_value(session.html, input, value)
        %{session | html: html}
    end
  end

  # select/4, choose/4, check/3, uncheck/3 follow the same pattern:
  # check for data-bind, update signal if present, update DOM

  # --- Assertions ---
  # 
  # These work on the in-memory HTML, same as PhoenixTest's static driver.

  def assert_has(session, selector, opts) do
    PhoenixTest.Assertions.assert_has(session.html, selector, opts)
    session
  end

  def refute_has(session, selector, opts) do
    PhoenixTest.Assertions.refute_has(session.html, selector, opts)
    session
  end

  def assert_path(session, path, opts) do
    # Compare session.path with expected path
  end

  # --- Escape Hatch ---

  def unwrap(session, fun) do
    # Give access to the raw conn and signals
    fun.(%{conn: session.conn, signals: session.signals, html: session.html})
  end
end
```

---

## Layer 2: Real-Time SSE Streams

This is where things get interesting. When a Dstar page has:

```html
<div data-init="@post('/ticker/stream', {retryMaxCount: Infinity})">
```

The Datastar client opens a long-lived SSE connection. The server handler enters a `receive` loop, sending patches as PubSub messages arrive. The connection stays open indefinitely.

### The Problem with Plug's Test Adapter

Plug's test adapter accumulates chunks in `conn.resp_body`. But the handler function never returns (it's in a `receive` loop), so `Phoenix.ConnTest.dispatch/5` blocks forever.

### Solution: Process-Based Stream Manager

We run the SSE handler in a separate process and use a custom mechanism to intercept chunks as they're sent:

```elixir
defmodule PhoenixTestDatastar.Stream do
  @moduledoc """
  Manages long-lived SSE connections for real-time testing.
  
  The stream runs the Dstar handler in a linked Task. A custom
  Plug adapter intercept sends chunks to the test process via
  message passing, allowing us to assert on SSE events as they
  arrive.
  """

  defmodule StreamAdapter do
    @moduledoc """
    Custom Plug adapter that forwards chunks to a subscriber process
    instead of accumulating them.
    """
    @behaviour Plug.Conn.Adapter

    def send_chunked(%{subscriber: subscriber} = state, status, headers) do
      send(subscriber, {:stream_started, status, headers})
      {:ok, "", state}
    end

    def chunk(%{subscriber: subscriber} = state, body) do
      send(subscriber, {:stream_chunk, IO.iodata_to_binary(body)})
      {:ok, nil, state}
    end

    # Delegate other adapter callbacks to Plug.Adapters.Test.Conn
    # (read_req_body, send_resp, etc.)
  end

  @doc """
  Open a long-lived SSE stream.
  
  Returns updated session with stream_pid set.
  The stream handler runs in a linked Task.
  
  ## Example
  
      session
      |> PhoenixTestDatastar.open_stream("/ticker/stream")
      |> PhoenixTestDatastar.broadcast(MyApp.PubSub, "ticker", {:tick, 1})
      |> PhoenixTestDatastar.assert_signal("tick", 1)
  """
  def open(session, path, opts \\ []) do
    test_pid = self()

    # Build a conn with our custom adapter that forwards chunks
    conn = build_stream_conn(session, test_pid, path, opts)

    # Run the handler in a separate process
    task =
      Task.async(fn ->
        try do
          session.endpoint.call(conn, [])
        catch
          :exit, _ -> :stream_closed
        end
      end)

    # Wait for the stream to start
    receive do
      {:stream_started, 200, _headers} -> :ok
    after
      5_000 -> raise "SSE stream did not start within 5s"
    end

    %{session | stream_pid: task.pid}
  end

  @doc """
  Collect SSE events that have arrived on the stream.
  Parses accumulated chunks into Datastar events.
  """
  def collect_events(timeout \\ 100) do
    collect_events([], timeout)
  end

  defp collect_events(acc, timeout) do
    receive do
      {:stream_chunk, chunk} ->
        events = PhoenixTestDatastar.SSE.parse(chunk)
        collect_events(acc ++ events, timeout)
    after
      timeout -> acc
    end
  end

  @doc """
  Wait for a specific SSE event type, then apply it to the session.
  """
  def await_event(session, event_type, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    case await_event_loop(event_type, deadline) do
      {:ok, event} ->
        PhoenixTestDatastar.Dispatcher.apply_event(session, event)

      :timeout ->
        raise PhoenixTestDatastar.StreamTimeoutError,
          message: "Expected #{event_type} event within #{timeout}ms"
    end
  end

  defp await_event_loop(event_type, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      :timeout
    else
      receive do
        {:stream_chunk, chunk} ->
          events = PhoenixTestDatastar.SSE.parse(chunk)
          
          case Enum.find(events, &(&1.type == event_type)) do
            nil -> await_event_loop(event_type, deadline)
            event -> {:ok, event}
          end
      after
        remaining -> :timeout
      end
    end
  end

  @doc """
  Close an active SSE stream.
  """
  def close(%{stream_pid: nil} = session), do: session
  def close(%{stream_pid: pid} = session) do
    Process.exit(pid, :shutdown)
    %{session | stream_pid: nil}
  end
end
```

### Real-Time Test Flow

Here's what a real-time test looks like:

```elixir
defmodule MyApp.TickerTest do
  use MyAppWeb.DstarCase, async: true

  test "ticker updates in real-time", %{conn: conn} do
    session =
      conn
      |> visit("/ticker")
      |> assert_has("[data-signals\\:tick]")

    # Open the SSE stream (simulates data-init="@post('/ticker/stream')")
    session = PhoenixTestDatastar.open_stream(session, "/ticker/stream")

    # Simulate a PubSub broadcast (what your app does in production)
    Phoenix.PubSub.broadcast(MyApp.PubSub, "ticker", {:tick, 42})

    # Wait for the SSE event and apply it
    session =
      session
      |> PhoenixTestDatastar.await_and_apply(:patch_signals, timeout: 500)

    # Assert on updated signal state
    assert PhoenixTestDatastar.get_signal(session, "tick") == 42

    # Or assert on updated DOM (if handler also patches elements)
    session
    |> assert_has("#tick-display", "42")

    # Clean up
    PhoenixTestDatastar.close_stream(session)
  end
end
```

---

## Dstar-Specific Assertions

Beyond the standard PhoenixTest assertions (`assert_has`, `refute_has`, `assert_path`), we need signal-aware assertions:

```elixir
defmodule PhoenixTestDatastar.Assertions do
  @doc "Assert a signal has a specific value"
  defmacro assert_signal(session, name, expected) do
    quote do
      actual = PhoenixTestDatastar.get_signal(unquote(session), unquote(name))
      
      assert actual == unquote(expected),
        """
        Expected signal "#{unquote(name)}" to be:
          #{inspect(unquote(expected))}
        
        Got:
          #{inspect(actual)}
        
        All signals:
          #{inspect(unquote(session).signals)}
        """
    end
  end

  @doc "Assert a signal exists (is set)"
  defmacro assert_signal_set(session, name) do
    quote do
      assert Map.has_key?(unquote(session).signals, unquote(name)),
        """
        Expected signal "#{unquote(name)}" to be set.
        
        Existing signals: #{inspect(Map.keys(unquote(session).signals))}
        """
    end
  end

  @doc "Refute a signal exists"
  defmacro refute_signal(session, name) do
    quote do
      refute Map.has_key?(unquote(session).signals, unquote(name)),
        """
        Expected signal "#{unquote(name)}" to NOT be set, but it was:
          #{inspect(Map.get(unquote(session).signals, unquote(name)))}
        """
    end
  end
end
```

---

## Entry Point & Public API

```elixir
defmodule PhoenixTestDatastar do
  @moduledoc """
  PhoenixTest driver for Dstar-powered Phoenix applications.
  
  ## Setup
  
  Add to your deps:
  
      {:phoenix_test_datastar, "~> 0.1.0", only: :test}
  
  Create a DstarCase in your test support:
  
      defmodule MyAppWeb.DstarCase do
        use ExUnit.CaseTemplate
  
        using do
          quote do
            import PhoenixTest
            import PhoenixTestDatastar
            import PhoenixTestDatastar.Assertions
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
  
  ## Usage
  
      test "counter increments", %{conn: conn} do
        conn
        |> visit("/counter")
        |> assert_signal("count", 0)
        |> click_button("+1")
        |> assert_signal("count", 1)
        |> assert_has("#count", "1")
      end
  """

  alias PhoenixTestDatastar.Session

  @doc """
  Build a new Dstar test session for the given endpoint.
  """
  def build(endpoint) do
    conn = Phoenix.ConnTest.build_conn()

    %Session{
      conn: conn,
      endpoint: endpoint,
      html: "",
      path: "/",
      signals: %{},
      within: nil,
      stream_pid: nil,
      csrf_token: nil
    }
  end

  # Signal accessors
  def get_signal(%Session{signals: signals}, name), do: Map.get(signals, name)
  def get_signals(%Session{signals: signals}), do: signals

  # Stream management (Layer 2)
  defdelegate open_stream(session, path, opts \\ []), to: PhoenixTestDatastar.Stream, as: :open
  defdelegate close_stream(session), to: PhoenixTestDatastar.Stream, as: :close

  def await_and_apply(session, event_type, opts \\ []) do
    PhoenixTestDatastar.Stream.await_event(session, event_type, Keyword.get(opts, :timeout, 1_000))
  end

  # Convenience: broadcast + await in one step
  def broadcast_and_await(session, pubsub, topic, message, opts \\ []) do
    Phoenix.PubSub.broadcast!(pubsub, topic, message)
    await_and_apply(session, Keyword.get(opts, :expect, :patch_signals), opts)
  end
end
```

---

## Key Design Decisions & Trade-offs

### 1. Floki for DOM manipulation

Floki is the standard Elixir HTML parser. It handles parsing and querying well, but **morphing** (Datastar's default mode) is nuanced — it matches by element ID and preserves state. Our `morph/2` implementation will be simpler than Idiomorph (Datastar's actual morphing lib) but sufficient for testing: match by ID, replace content.

### 2. JS expression parsing is intentionally limited

We don't need a full JavaScript parser. Datastar action expressions follow a predictable pattern: `@method(url, options)`. We parse the method, URL, and a limited subset of options (headers, filterSignals). Complex JS expressions in `data-on:click` that aren't `@method()` calls would need special handling — but in practice, Dstar handlers are almost always `@post`/`@get` calls.

### 3. Signal value parsing via JSON normalization

Rather than writing a JS parser, we normalize JS-like values to JSON (`{foo: 'bar'}` → `{"foo": "bar"}`) and use Jason. This handles 95% of real-world signal declarations. Edge cases (computed expressions, function calls) would be flagged as parse errors.

### 4. The Stream adapter is a test-only construct

The custom `StreamAdapter` exists only to solve the blocking-handler problem. It intercepts `Plug.Conn.chunk/2` calls and forwards them as messages. This is similar to how Phoenix's own test infrastructure works — `Phoenix.ChannelTest` uses process messaging to simulate real-time communication.

### 5. PhoenixTest's `visit/2` entry point

PhoenixTest's `visit/2` dispatches on the struct type: `%Plug.Conn{}` goes to `ConnHandler`, everything else goes through `Driver`. Our session struct naturally gets protocol dispatch. The user starts with `PhoenixTestDatastar.build(Endpoint)` instead of `Phoenix.ConnTest.build_conn()` — this is the same pattern the Playwright driver uses.

---

## Implementation Roadmap

### Phase 1: Core request/response (MVP)
- [ ] Session struct + basic Driver protocol
- [ ] Signal extraction from HTML (`data-signals:*`)
- [ ] SSE response parser
- [ ] DOM patching (outer, inner, append, remove modes)
- [ ] Action expression parser (`@post`, `@get`)
- [ ] Dispatcher (signals → POST → SSE → apply)
- [ ] `visit/2`, `click_button/2`, `assert_has/2,3`
- [ ] Signal assertions

### Phase 2: Form interactions
- [ ] `fill_in/3` with `data-bind` support
- [ ] `select/3`, `choose/3`, `check/3` for signal-bound inputs
- [ ] `submit/1` for `contentType: 'form'` actions
- [ ] `within/3` scoping

### Phase 3: Real-time SSE streams
- [ ] Custom StreamAdapter for chunk interception
- [ ] `open_stream/3`, `close_stream/1`
- [ ] `await_and_apply/3` with timeout
- [ ] `broadcast_and_await/5` convenience

### Phase 4: Polish & edge cases
- [ ] Redirect handling (`Dstar.redirect/2` → script-based navigation)
- [ ] CSRF token auto-injection
- [ ] `open_browser/1` support
- [ ] Error messages with signal state context
- [ ] `data-init` auto-dispatching on visit
- [ ] Multiple concurrent SSE streams
- [ ] `Dstar.Plugs.Dispatch` integration (dynamic routing)

---

## Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:phoenix_test, "~> 0.10"},
    {:floki, "~> 0.36"},
    {:jason, "~> 1.4"},
    {:plug, "~> 1.15"},
    # Dstar itself is NOT a dependency —
    # this package tests apps that USE Dstar,
    # it doesn't depend on Dstar's internals.
  ]
end
```

Note: Dstar is intentionally not a dependency. The driver only needs to understand the Datastar SSE wire format and HTML attribute conventions, not Dstar's Elixir API. This keeps the packages loosely coupled and means `phoenix_test_datastar` could also work with other Elixir Datastar libraries (`datastar_ex`, `phoenix_datastar`).

---

## What a Full Test Looks Like

```elixir
defmodule MyApp.TodoTest do
  use MyAppWeb.DstarCase, async: true

  test "complete todo workflow", %{conn: conn} do
    conn
    |> visit("/todos")
    |> assert_signal("todos", [])
    
    # Add a todo via Dstar
    |> fill_in("New todo", with: "Buy milk")
    |> click_button("Add")
    |> assert_has("#todo-list li", "Buy milk")
    |> assert_signal("newTodo", "")     # input cleared after add
    
    # Toggle complete
    |> click_button("Complete", within: "#todo-1")
    |> assert_has("#todo-1.completed")
    
    # Delete
    |> click_button("Delete", within: "#todo-1")
    |> refute_has("#todo-1")
  end

  test "real-time collaboration", %{conn: conn} do
    session =
      conn
      |> visit("/todos")
      |> open_stream("/todos/stream")

    # Simulate another user adding a todo (via PubSub)
    Phoenix.PubSub.broadcast!(MyApp.PubSub, "todos", {:todo_added, "Walk the dog"})

    session
    |> await_and_apply(:patch_elements, timeout: 500)
    |> assert_has("#todo-list li", "Walk the dog")
    |> close_stream()
  end
end
```
