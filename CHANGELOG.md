# Changelog

## 0.0.3

### Added

- Resolve the action URLs rendered by dstar 0.3:
  - `Dstar.Page.Helpers.event/2` (`location.pathname.replace(/^\/+/, '/').replace(/\/+$/, '') + "/_event/..."`)
  - `Dstar.Page.Helpers.connect/1`, with and without `include_search: true` (`location.search`)
  - `Dstar.Component` `event/2`, reading the dispatch base from `<body data-ds-base>` (default `/ds`)
  - dynamic `$_dstar_module` segments, percent-encoded like the browser does
  - double-quoted (JSON) string literals and percent-encoded event/module segments
- `PhoenixTestDatastar.Actions.resolve_url/4` takes a `:ds_base` option, and
  `PhoenixTestDatastar.Actions.find_ds_base/1` reads it from the page.

The dstar 0.1/0.2 URL shapes still work.

### Changed

- Action expressions are split on top-level `;`, `,` and `+` only, not on the
  ones inside string literals or dstar's browser expressions.
- `resolve_url` raises `ArgumentError` for URL parts it can't resolve, and for
  URLs the browser would reject (an invalid `data-ds-base`, or an empty or dot
  `$_dstar_module`). It used to dispatch the unresolved JavaScript as the
  request path.
- `confirm('...') && @action(...)` guards are treated as accepted and the
  action is dispatched, as in 0.0.2. Guards other than `confirm()` are now an
  invalid action expression.
- GET actions whose URL already has a query string (`connect(include_search: true)`)
  append the `datastar` query parameter with `&`.

## 0.0.2

- Adapt the driver to the phoenix_test 0.11 API.
- Resolve `location.pathname` URLs from dstar page-local helpers.
- Apply `mode: remove` element patches.
- Fix Datastar form bindings and stream coverage.

## 0.0.1

- Initial alpha release.
