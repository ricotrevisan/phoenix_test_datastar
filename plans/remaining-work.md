# PhoenixTestDatastar — Remaining Work Plan

## ✅ ALL STEPS COMPLETE

All 8 steps have been implemented and tested. 196 tests (31 doctests + 165 tests), 0 failures.

### Step 1: Session Struct + Public API ✅
- `lib/phoenix_test_datastar/session.ex` — Session struct
- `lib/phoenix_test_datastar.ex` — `build/1`, `visit/2`, signal accessors

### Step 2: Dispatcher ✅
- `lib/phoenix_test_datastar/dispatcher.ex` — HTTP dispatch, SSE parsing, event application

### Step 3: Driver Protocol ✅
- `lib/phoenix_test_datastar/driver.ex` — Full `PhoenixTest.Driver` implementation
  - Dual-mode: Datastar actions + standard form handling
  - `data-bind` signal binding for fill_in/select/check/uncheck/choose

### Step 4: Signal Assertions ✅
- `lib/phoenix_test_datastar/assertions.ex` — `assert_signal/3`, `assert_signal_set/2`, `refute_signal/2`

### Step 5: Test Infrastructure ✅
- `test/support/endpoint.ex`, `test/support/router.ex`
- `test/support/datastar_case.ex`
- 7 test handlers: CounterHandler, FormHandler, RedirectHandler, InitHandler, MultiHandler, StreamHandler, PageController

### Step 6: Integration Tests ✅
- `test/integration/visit_test.exs` — 6 tests
- `test/integration/click_test.exs` — 6 tests
- `test/integration/form_test.exs` — 7 tests
- `test/integration/navigation_test.exs` — 4 tests
- `test/integration/assertions_test.exs` — 11 tests
- `test/integration/data_init_test.exs` — 1 test
- `test/integration/stream_test.exs` — 3 tests

### Step 7: Real-Time SSE Streaming ✅
- `lib/phoenix_test_datastar/stream_adapter.ex` — Custom Plug adapter
- `lib/phoenix_test_datastar/stream.ex` — `open_stream/2`, `await_events/1`, `close_stream/1`

### Step 8: Polish ✅
- `data-init` auto-dispatching on visit
- Kebab-case to camelCase signal name conversion
- CSRF token auto-refresh from signals
- Clean error messages
- `open_browser/1` with static path prefixing
