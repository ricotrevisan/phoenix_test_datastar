# PhoenixTestDatastar — Implementation Plan

## Overview

A PhoenixTest driver that simulates the Datastar client for testing Dstar-powered Phoenix apps. It maintains client-side signal state, dispatches HTTP requests, parses SSE responses, and applies DOM patches — all through the standard PhoenixTest API.

---

## Prerequisites & Corrections to Original Plan

Based on analysis of the actual `Dstar` source code (v0.0.5) and `PhoenixTest` (v0.10.0):

### Dstar Wire Format (actual)

1. **SSE events use `datastar-patch-signals`** and **`datastar-patch-elements`** — there is no separate `datastar-execute-script` event type. Scripts are sent via `Elements.patch(conn, script_html, selector: "body", mode: :append)`.

2. **Default patch mode** is `:outer` (omitted from SSE when default). Valid modes: `outer`, `inner`, `remove`, `replace`, `prepend`, `append`, `before`, `after`.

3. **Redirect format**: `setTimeout(function(){window.location.href=<json_encoded_url>},0)` — wrapped in a `<script>` tag appended to body.

4. **Console log format**: `console.<level>(<message>)` — also wrapped in `<script>` tag.

5. **Action expressions**: Dstar generates `@post('/ds/module_name/event_name', {headers: {'x-csrf-token': $_csrfToken}})`. The URL pattern is always `/ds/:encoded_module/:event_name`.

6. **Module encoding**: `MyApp.CounterView` → `"my_app-counter_view"` (underscore segments joined by dashes).

7. **Signal reading**: POST body is raw JSON. GET uses `?datastar=<json_string>` query parameter.

8. **`onlyIfMissing`** defaults to `false` (line omitted from SSE when false).

9. **Retry** defaults to `1000` (line omitted when exactly 1000).

10. **Namespace** defaults to `:html` (line omitted when html). Valid: `html`, `svg`, `mathml`.

### PhoenixTest Driver Protocol (actual)

The protocol has **36 functions** (not all shown in the plan). Key details:

- `visit/2` receives the initial struct, not a session — it's the entry point
- `render_html/1` must return a `LazyHTML` struct (not raw HTML string) — PhoenixTest uses LazyHTML, not Floki
- `render_page_title/1` returns title text or nil
- `current_path/1` returns the current path string
- Assertions (`assert_has`, `refute_has`, `assert_path`, `refute_path`) can be delegated to `PhoenixTest.Assertions`
- `within/3` can be delegated to `PhoenixTest.SessionHelpers`
- The Static driver uses `@endpoint Application.compile_env(:phoenix_test, :endpoint)` — we must do the same
- Form tracking uses `ActiveForm` struct with `FormData` — we need to support this for non-Datastar forms

### HTML Parsing

PhoenixTest uses **LazyHTML** (not Floki) for all DOM operations. We must use LazyHTML for compatibility with PhoenixTest's Query, Assertions, and Html modules.

---

## Phase 1: Project Setup & Core Infrastructure

### Step 1.1: Initialize the Mix project

```
mix new phoenix_test_datastar --sup false
```

**`mix.exs`**:
```elixir
defp deps do
  [
    {:phoenix_test, "~> 0.10"},
    {:phoenix, "~> 1.7"},
    {:plug, "~> 1.15"},
    {:jason, "~> 1.4"},
    {:lazy_html, "~> 0.2"},   # Same HTML parser as PhoenixTest
    {:ex_doc, "~> 0.30", only: :dev, runtime: false}
  ]
end
```

Note: `dstar` is **not** a dependency. We only understand the wire format, not the library internals.

### Step 1.2: Session struct

**`lib/phoenix_test_datastar/session.ex`**

```elixir
defstruct [
  :conn,           # Plug.Conn for making requests
  :endpoint,       # Phoenix endpoint module
  :raw_html,       # Current page HTML as raw string (for SSE patching)
  :parsed_html,    # LazyHTML parsed version (for PhoenixTest compatibility)
  :current_path,   # Current request path with query string
  :signals,        # %{string => term} — current Datastar signal state
  :csrf_token,     # Extracted CSRF token
  active_form: ActiveForm.new(),  # PhoenixTest form tracking
  within: :none    # CSS selector scope
]
```

Key design: We store **both** `raw_html` (string, for Floki-based DOM patching) and expose `parsed_html` (LazyHTML, for PhoenixTest compatibility). After each DOM patch, we re-parse.

Actually — simplification: store only `raw_html` and lazily parse to LazyHTML in `render_html/1`. DOM patching operates on the raw string via Floki (since LazyHTML doesn't support surgical DOM mutations). Re-parsing is cheap.

### Step 1.3: Public API entry point

**`lib/phoenix_test_datastar.ex`**

```elixir
defmodule PhoenixTestDatastar do
  alias PhoenixTestDatastar.Session

  def build(endpoint) do
    %Session{
      conn: Phoenix.ConnTest.build_conn(),
      endpoint: endpoint,
      raw_html: "",
      current_path: "/",
      signals: %{},
      csrf_token: nil
    }
  end

  # Signal accessors
  def get_signal(session, name)
  def get_signals(session)
  def put_signal(session, name, value)  # For test setup
end
```

---

## Phase 2: SSE Parser

**`lib/phoenix_test_datastar/sse.ex`**

This is the foundation — everything else depends on correctly parsing SSE responses.

### SSE Event Format (from Dstar source)

```
event: datastar-patch-signals
data: onlyIfMissing true
data: signals {"count":1}

event: datastar-patch-elements
data: selector #count
data: mode inner
data: elements <span>1</span>

event: datastar-patch-elements
data: selector body
data: mode append
data: elements <script data-effect="el.remove()">setTimeout(function(){window.location.href="/new-path"},0)</script>
```

### Parser Output Types

```elixir
@type event ::
  %{type: :patch_signals, signals: map(), only_if_missing: boolean()}
  | %{type: :patch_elements, selector: String.t() | nil, mode: atom(), elements: String.t(), namespace: atom()}
```

### Implementation

```elixir
def parse(raw_sse) when is_binary(raw_sse) do
  raw_sse
  |> String.split("\n\n")
  |> Enum.reject(&(String.trim(&1) == ""))
  |> Enum.map(&parse_event/1)
  |> Enum.reject(&is_nil/1)
end
```

Parse each event by:
1. Extract `event:` line → event type
2. Collect all `data:` lines
3. Dispatch to type-specific parser

For `patch_signals`:
- Look for `data: onlyIfMissing true` → boolean flag
- Look for `data: signals <json>` → decode JSON

For `patch_elements`:
- Look for `data: selector <sel>` (optional for outer/morph mode)
- Look for `data: mode <mode>` (default: `outer`)
- Look for `data: namespace <ns>` (default: `html`)
- Look for `data: useViewTransitions true` (default: false)
- Collect all `data: elements <html>` lines → join with `\n`

### Tests

- Parse single `patch_signals` event
- Parse single `patch_elements` event
- Parse multi-event response
- Parse with `onlyIfMissing true`
- Parse with non-default mode (`inner`, `append`, etc.)
- Parse with missing optional fields (defaults applied)
- Handle empty/whitespace input
- Handle events with `id:` and `retry:` lines (ignored)

---

## Phase 3: Signal Management

**`lib/phoenix_test_datastar/signals.ex`**

### Signal Extraction from HTML

Datastar signals are declared in HTML via:
- `data-signals:count="0"` → individual signal
- `data-signals:name="'hello'"` → string value (JS-style single quotes)
- `data-signals="{foo: 1, bar: 2}"` → object of signals
- `data-signals:_csrfToken="'abc123'"` → underscore prefix = client-only

We need to:
1. Parse the HTML document
2. Find all elements with attributes starting with `data-signals`
3. Extract signal names and values
4. Parse JS-like values into Elixir terms

### Value Parsing Strategy

Use JSON normalization (as the plan suggests):
1. `'hello'` → `"hello"` (single to double quotes)
2. `{foo: 1, bar: 'x'}` → `{"foo": 1, "bar": "x"}` (quote unquoted keys)
3. `0`, `true`, `false`, `null` → direct JSON
4. Then `Jason.decode!/1`

```elixir
def extract_from_html(raw_html) do
  doc = Floki.parse_document!(raw_html)
  # Walk all elements, collect data-signals* attributes
  # Return merged signal map
end

def parse_value(js_value_string) do
  js_value_string
  |> normalize_to_json()
  |> Jason.decode!()
end
```

### Signal State Operations

```elixir
def apply_patch(signals, new_signals, opts \\ [])
# Merge new_signals into existing, respecting only_if_missing

def to_post_body(signals)
# JSON encode, excluding _ prefixed keys

def to_get_params(signals)
# Encode as ?datastar=<json> query string, excluding _ prefixed keys
```

### Tests

- Extract `data-signals:key="value"` for numbers, strings, booleans
- Extract `data-signals="{...}"` object syntax
- Extract `_csrfToken` signal
- `apply_patch` with normal merge
- `apply_patch` with `only_if_missing: true`
- `apply_patch` with `nil` value removes signal
- `to_post_body` excludes `_` prefixed signals
- `to_get_params` encodes as `datastar` query param
- JS value normalization edge cases

---

## Phase 4: DOM Patching

**`lib/phoenix_test_datastar/dom.ex`**

Operates on raw HTML strings using Floki, then the session re-parses to LazyHTML.

### Patch Modes

| Mode | Behavior |
|------|----------|
| `:outer` | **Morph**: For each new element with an `id`, find matching element in doc and replace it entirely. This is Datastar's default. |
| `:inner` | Replace the inner content of the element matching `selector` |
| `:append` | Append new elements as children of `selector` target |
| `:prepend` | Prepend new elements as children of `selector` target |
| `:before` | Insert new elements before the `selector` target |
| `:after` | Insert new elements after the `selector` target |
| `:replace` | Replace the element matching `selector` entirely (like outer but by selector) |
| `:remove` | Remove elements matching `selector` |

### Implementation

```elixir
def apply_patch(raw_html, %{mode: mode, selector: selector, elements: elements}) do
  doc = Floki.parse_document!(raw_html)
  new_elements = Floki.parse_fragment!(elements)

  updated = case mode do
    :outer -> morph_by_id(doc, new_elements)
    :inner -> replace_inner(doc, selector, new_elements)
    :append -> append_to(doc, selector, new_elements)
    :prepend -> prepend_to(doc, selector, new_elements)
    :before -> insert_before(doc, selector, new_elements)
    :after -> insert_after(doc, selector, new_elements)
    :replace -> replace_selector(doc, selector, new_elements)
    :remove -> remove_selector(doc, selector)
  end

  Floki.raw_html(updated)
end
```

**Morph implementation**: Walk `new_elements`, for each element that has an `id` attribute, find the element in `doc` with the same `id` and replace it. This is simpler than Idiomorph but sufficient for testing.

**Floki tree walking**: Use `Floki.traverse_and_update/2` for in-place mutations.

### Tests

- Morph (outer) replaces element by ID
- Morph with multiple elements
- Inner mode replaces children
- Append/prepend add children
- Before/after insert siblings
- Replace replaces by selector
- Remove deletes by selector
- Preserve elements not targeted by patch
- Handle nested selectors

---

## Phase 5: Action Expression Parser

**`lib/phoenix_test_datastar/actions.ex`**

Parse Datastar action expressions from `data-on:click`, `data-on:submit`, etc.

### Expression Format (from Dstar source)

```
@post('/ds/my_app-counter_view/increment', {headers: {'x-csrf-token': $_csrfToken}})
@get('/ds/my_app-counter_view/load')
@post('/ds/' + $_dstar_module + '/increment', {headers: {'x-csrf-token': $_csrfToken}})
```

### Parser

```elixir
def parse(expression) do
  # Regex to match: @method(url_expression, options?)
  # Handle both static URLs ('/path') and dynamic ('prefix' + $signal + '/suffix')
  # Return: %{method: :post, url: "/ds/...", options: %{}}
end
```

For static URLs: direct extraction.
For dynamic URLs with `$_dstar_module`: resolve by looking up the signal value in current session signals.

### Element Action Discovery

```elixir
def find_action(raw_html, element_selector) do
  # 1. Find the element
  # 2. Check for data-on:click, data-on:submit, data-on:change attributes
  # 3. Parse the action expression
  # Return: {:ok, parsed_action} | :none
end
```

### Tests

- Parse `@post('/path')`
- Parse `@post('/path', {headers: {...}})`
- Parse `@get('/path')`
- Parse all verb types (get, post, put, patch, delete)
- Parse dynamic URL with `$_dstar_module`
- Handle multiple actions in one expression (e.g., chained with `;`)
- `find_action` on element with `data-on:click`
- `find_action` returns `:none` for non-Datastar elements

---

## Phase 6: HTTP Dispatcher

**`lib/phoenix_test_datastar/dispatcher.ex`**

Ties everything together: builds HTTP requests, dispatches through the endpoint, parses SSE responses, applies events to session state.

### Request Building

**POST requests**:
```elixir
conn
|> Plug.Conn.put_req_header("content-type", "application/json")
|> Plug.Conn.put_req_header("datastar-request", "true")
|> Plug.Conn.put_req_header("x-csrf-token", csrf_token)
# Body: JSON-encoded signals (excluding _ prefixed)
```

**GET requests**:
```elixir
# Signals go as ?datastar=<json> query parameter
url = path <> "?" <> Signals.to_get_params(signals)
```

### Dispatch Flow

```elixir
def dispatch(session, action) do
  # 1. Build conn with appropriate headers/body
  # 2. Phoenix.ConnTest.dispatch(conn, endpoint, method, url, body)
  # 3. Check response content type
  # 4. If "text/event-stream" → parse SSE, apply events
  # 5. If redirect (302) → follow redirect
  # 6. Return updated session
end
```

### Event Application

```elixir
def apply_events(session, events) do
  Enum.reduce(events, session, fn event, acc ->
    case event.type do
      :patch_signals ->
        signals = Signals.apply_patch(acc.signals, event.signals, ...)
        # Also re-extract signals from updated HTML (in case new data-signals attributes appeared)
        %{acc | signals: signals}

      :patch_elements ->
        # Check if this is a script (redirect/console.log)
        if script_element?(event.elements) do
          handle_script(acc, event.elements)
        else
          raw_html = DOM.apply_patch(acc.raw_html, event)
          # Re-extract signals from new HTML
          new_html_signals = Signals.extract_from_html(raw_html)
          signals = Map.merge(acc.signals, new_html_signals)
          %{acc | raw_html: raw_html, signals: signals}
        end
    end
  end)
end
```

### Script Handling

Detect `<script>` elements in patch-elements and extract behavior:

```elixir
def handle_script(session, elements_html) do
  cond do
    # Redirect: setTimeout(function(){window.location.href="..."}, 0)
    match = Regex.run(~r/window\.location\.href\s*=\s*(".*?"|'.*?')/, elements_html) ->
      url = match |> List.last() |> Jason.decode!()
      # Follow the redirect via visit
      PhoenixTest.Driver.visit(session, url)

    # Console log: no-op in tests
    String.contains?(elements_html, "console.") ->
      session

    # Other scripts: apply as DOM patch (script gets appended to body)
    true ->
      raw_html = DOM.apply_patch(session.raw_html, %{...})
      %{session | raw_html: raw_html}
  end
end
```

### Tests

- Dispatch POST with signals → SSE response → updated session
- Dispatch GET with signals as query params
- Apply patch_signals event
- Apply patch_elements event
- Handle redirect via script
- Handle console.log (no-op)
- CSRF token injection
- Multiple events in single response

---

## Phase 7: Driver Protocol Implementation

**`lib/phoenix_test_datastar/driver.ex`** (the `defimpl` block)

### `visit/2`

```elixir
def visit(session, path) do
  conn =
    session.conn
    |> Phoenix.ConnTest.dispatch(session.endpoint, :get, path)

  raw_html = conn.resp_body
  signals = Signals.extract_from_html(raw_html)
  csrf = Map.get(signals, "_csrfToken")
  current_path = ConnHandler.build_current_path(conn)

  %{session |
    conn: Phoenix.ConnTest.recycle(conn),
    raw_html: raw_html,
    current_path: current_path,
    signals: signals,
    csrf_token: csrf,
    active_form: ActiveForm.new(),
    within: :none
  }
end
```

### `render_html/1`

```elixir
def render_html(%{raw_html: raw_html, within: within}) do
  html = LazyHTML.from_document(raw_html)

  case within do
    :none -> html
    selector when is_binary(selector) -> LazyHTML.query(html, selector)
  end
end
```

### `click_button/2` and `click_button/3`

The core interaction. Must handle:

1. **Datastar buttons**: Have `data-on:click="@post(...)"` → parse action, dispatch
2. **Standard form buttons**: Have `data-method`/`data-to` or are inside `<form>` → delegate to standard form handling
3. **Active form buttons**: User filled in fields first with `fill_in` → merge active form data

```elixir
def click_button(session, selector, text) do
  html = render_html(session)
  button = Button.find!(html, selector, text)

  case find_datastar_action(session.raw_html, button) do
    {:ok, action_expr} ->
      {:ok, action} = Actions.parse(action_expr)
      action = resolve_signal_refs(action, session.signals)
      Dispatcher.dispatch(%{session | active_form: ActiveForm.new()}, action)

    :none ->
      # Fall back to standard form handling (same as Static driver)
      handle_standard_button(session, button, selector, text)
  end
end
```

### `click_link/2` and `click_link/3`

Similar pattern — check for `data-on:click` first, fall back to standard navigation.

### `fill_in/3` and `fill_in/4`

Must handle both Datastar signal-bound inputs and standard form inputs:

```elixir
def fill_in(session, input_selector, label, opts) do
  {value, opts} = Keyword.pop!(opts, :with)
  html = render_html(session)
  field = Field.find_input!(html, input_selector, label, opts)

  # Check for data-bind:* attribute on the input
  case find_data_bind(session.raw_html, field) do
    {:ok, signal_name} ->
      # Update the signal directly
      signals = Map.put(session.signals, signal_name, value)
      %{session | signals: signals}

    :none ->
      # Standard form field — track in active_form (same as Static driver)
      field = Map.put(field, :value, to_string(value))
      fill_in_field_data(session, field)
  end
end
```

### `select/3`, `check/3`, `uncheck/3`, `choose/3`

Same dual-mode pattern: check for `data-bind` → update signal, or track in `active_form`.

### `submit/1`

Submit the active form. If the form has a Datastar action (`data-on:submit`), dispatch that. Otherwise, standard form submit.

### Assertions

Delegate entirely to `PhoenixTest.Assertions`:
```elixir
defdelegate assert_has(session, selector), to: Assertions
defdelegate assert_has(session, selector, opts), to: Assertions
# ... etc
```

### `within/3`

Delegate to `PhoenixTest.SessionHelpers.within/3`.

### `unwrap/2`

```elixir
def unwrap(session, fun) do
  result = fun.(%{conn: session.conn, signals: session.signals, raw_html: session.raw_html})
  # Handle the result (could be a conn, could be arbitrary)
  session
end
```

### `open_browser/1`

Similar to Static driver — write HTML to temp file, open system browser.

### `current_path/1`

```elixir
def current_path(session), do: session.current_path
```

### `render_page_title/1`

```elixir
def render_page_title(session) do
  session
  |> render_html()
  |> Query.find("title")
  |> case do
    {:found, element} -> Html.inner_text(element)
    _ -> nil
  end
end
```

---

## Phase 8: Datastar-Specific Assertions

**`lib/phoenix_test_datastar/assertions.ex`**

Macros for signal-level assertions (not part of the Driver protocol, but useful for Dstar tests):

```elixir
defmacro assert_signal(session, name, expected)
defmacro assert_signal_set(session, name)
defmacro refute_signal(session, name)
```

These are `import`-able extras, not protocol requirements.

---

## Phase 9: Integration Tests

### Test Infrastructure

Create a minimal Phoenix endpoint + router + Dstar handlers for testing:

**`test/support/endpoint.ex`** — Test Phoenix endpoint
**`test/support/router.ex`** — Routes with `Dstar.Plugs.Dispatch`
**`test/support/handlers/`** — Sample Dstar handler modules:

- `CounterHandler` — increment/decrement with signal patching
- `FormHandler` — form with signal-bound inputs
- `RedirectHandler` — handler that redirects
- `StreamHandler` — handler with long-lived SSE (Phase 10)

### Test Cases

```
test/integration/visit_test.exs       — visit page, extract signals, assert HTML
test/integration/click_test.exs       — click Datastar buttons, verify signal/DOM updates
test/integration/form_test.exs        — fill_in with data-bind, submit forms
test/integration/navigation_test.exs  — redirects, link clicks, path assertions
test/integration/assertions_test.exs  — signal assertions, DOM assertions
```

---

## Phase 10: Real-Time SSE Streams (Layer 2)

**`lib/phoenix_test_datastar/stream.ex`**

This phase handles long-lived SSE connections (e.g., `data-init="@post('/stream')"`).

### The Problem

Plug's test adapter accumulates chunks in `conn.resp_body`. When a handler enters a `receive` loop (waiting for PubSub messages), `dispatch/5` blocks forever because the handler never returns.

### Solution: Custom Plug Adapter

Create a minimal Plug adapter that forwards `chunk/2` calls as process messages:

```elixir
defmodule PhoenixTestDatastar.StreamAdapter do
  @behaviour Plug.Conn.Adapter

  def send_chunked(state, status, headers) do
    send(state.subscriber, {:stream_started, status, headers})
    {:ok, nil, state}
  end

  def chunk(state, body) do
    send(state.subscriber, {:stream_chunk, IO.iodata_to_binary(body)})
    {:ok, nil, state}
  end

  # Delegate remaining callbacks to Plug.Adapters.Test.Conn
end
```

### Stream Manager

```elixir
def open_stream(session, path, opts \\ []) do
  # 1. Build conn with custom adapter
  # 2. Spawn Task to run the handler
  # 3. Wait for {:stream_started, ...}
  # 4. Return session with stream_pid
end

def await_and_apply(session, event_type, opts \\ []) do
  # 1. Wait for {:stream_chunk, ...} messages
  # 2. Parse chunks as SSE events
  # 3. Find matching event type
  # 4. Apply to session via Dispatcher.apply_events
end

def close_stream(session) do
  # Kill the stream Task
end
```

### Tests

- Open stream, broadcast PubSub message, receive SSE event
- Await specific event type with timeout
- Close stream cleanly
- Multiple sequential events

---

## Phase 11: Polish & Edge Cases

1. **`data-init` auto-dispatching**: When visiting a page, check for `data-init="@post(...)"` attributes and automatically dispatch those requests. This is how Datastar initializes real-time connections.

2. **CSRF auto-refresh**: After each request, check if the response includes a new CSRF token and update the session.

3. **Multiple `data-on:*` events**: An element might have `data-on:click`, `data-on:mouseenter`, etc. The driver should pick the appropriate one based on the interaction type.

4. **Error handling**: Good error messages when:
   - Action expression can't be parsed
   - SSE response is malformed
   - Signal not found
   - Element not found

5. **`open_browser/1`**: Write raw HTML to temp file with static path prefixing.

6. **Nested signals**: Handle `data-signals="{user: {name: '', age: 0}}"` → nested maps in signal state.

---

## Implementation Order & Dependencies

```
Phase 1: Setup ──────────────────────────┐
                                         │
Phase 2: SSE Parser ◄───────────────────┤ (no dependencies)
                                         │
Phase 3: Signal Management ◄────────────┤ (no dependencies)
                                         │
Phase 4: DOM Patching ◄─────────────────┤ (no dependencies)
                                         │
Phase 5: Action Parser ◄────────────────┤ (no dependencies)
                                         │
Phase 6: Dispatcher ◄───────────────────┘ (depends on 2, 3, 4, 5)
         │
Phase 7: Driver Protocol ◄──────────────── (depends on 6, 3, 4, 5)
         │
Phase 8: Assertions ◄───────────────────── (depends on 7)
         │
Phase 9: Integration Tests ◄────────────── (depends on 7, 8)
         │
Phase 10: Streaming ◄───────────────────── (depends on 6, 7)
         │
Phase 11: Polish ◄──────────────────────── (depends on all)
```

**Phases 2-5 can be implemented in parallel** — they have no interdependencies.

---

## File Structure

```
phoenix_test_datastar/
├── lib/
│   ├── phoenix_test_datastar.ex                    # Public API, build/1, signal accessors
│   └── phoenix_test_datastar/
│       ├── session.ex                           # Session struct definition
│       ├── driver.ex                            # defimpl PhoenixTest.Driver
│       ├── sse.ex                               # SSE response parser
│       ├── signals.ex                           # Signal extraction, patching, serialization
│       ├── dom.ex                               # DOM patching (Floki-based)
│       ├── actions.ex                           # Action expression parser
│       ├── dispatcher.ex                        # HTTP dispatch + event application
│       ├── assertions.ex                        # Signal-specific assertion macros
│       ├── stream.ex                            # Real-time SSE stream manager (Phase 10)
│       └── stream_adapter.ex                    # Custom Plug adapter (Phase 10)
├── test/
│   ├── test_helper.exs
│   ├── phoenix_test_datastar/
│   │   ├── sse_test.exs                         # SSE parser unit tests
│   │   ├── signals_test.exs                     # Signal extraction/patching tests
│   │   ├── dom_test.exs                         # DOM patching tests
│   │   ├── actions_test.exs                     # Action parser tests
│   │   └── dispatcher_test.exs                  # Dispatcher unit tests
│   ├── integration/
│   │   ├── support/
│   │   │   ├── endpoint.ex                      # Test Phoenix endpoint
│   │   │   ├── router.ex                        # Test router
│   │   │   └── handlers/
│   │   │       ├── counter_handler.ex           # Counter increment/decrement
│   │   │       ├── form_handler.ex              # Form with data-bind
│   │   │       ├── redirect_handler.ex          # Redirect handler
│   │   │       └── stream_handler.ex            # Streaming handler
│   │   ├── visit_test.exs
│   │   ├── click_test.exs
│   │   ├── form_test.exs
│   │   ├── navigation_test.exs
│   │   └── stream_test.exs
│   └── support/
│       └── dstar_case.ex                        # ExUnit case template
├── mix.exs
├── mix.lock
└── README.md
```

---

## Key Risk Areas

1. **LazyHTML vs Floki incompatibility**: PhoenixTest uses LazyHTML for querying, but we need Floki for DOM mutations (LazyHTML doesn't support `traverse_and_update`). Solution: keep raw HTML string as source of truth, use Floki for mutations, re-parse to LazyHTML for PhoenixTest compatibility.

2. **JS value parsing**: Datastar uses JS-like values in `data-signals:*` attributes. The JSON normalization approach handles most cases but may fail on complex expressions. Start simple, add cases as needed.

3. **Plug test adapter limitations for streaming**: The custom `StreamAdapter` needs to correctly implement all `Plug.Conn.Adapter` callbacks. We may need to delegate most callbacks to the real test adapter.

4. **Action expression parsing**: Dynamic URLs with signal interpolation (`'/ds/' + $_dstar_module + '/event'`) require resolving signals at parse time. Start with static URLs only.

5. **Form handling dual-mode**: Supporting both Datastar signal-bound inputs and standard HTML forms adds complexity. The `data-bind` check on each `fill_in` call must be reliable.
