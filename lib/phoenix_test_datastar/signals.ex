defmodule PhoenixTestDatastar.Signals do
  @moduledoc """
  Handles Datastar signal extraction from HTML and signal state management.

  Datastar signals are declared in HTML via attributes:
  - `data-signals:count="0"` → individual signal named 'count' with value 0
  - `data-signals:name="'hello'"` → string value (JS-style single quotes)
  - `data-signals="{foo: 1, bar: 2}"` → object of signals
  - `data-signals:_csrfToken="'abc123'"` → underscore prefix = client-only signal
  """

  @doc """
  Extracts all Datastar signals from HTML.

  Parses the HTML, finds all `data-signals` and `data-signals:*` attributes,
  and returns a merged map of all signals.

  ## Examples

      iex> html = ~s(<div data-signals:count="0" data-signals:name="'hello'"></div>)
      iex> PhoenixTestDatastar.Signals.extract_from_html(html)
      %{"count" => 0, "name" => "hello"}

      iex> html = ~s(<div data-signals="{foo: 1, bar: 2}"></div>)
      iex> PhoenixTestDatastar.Signals.extract_from_html(html)
      %{"foo" => 1, "bar" => 2}
  """
  @spec extract_from_html(String.t()) :: map()
  def extract_from_html(html) do
    {:ok, document} = Floki.parse_document(html)

    # Traverse all elements and extract signals from any with data-signals attributes
    traverse_and_extract(document, %{})
  end

  @doc """
  Parses a JavaScript-like value string into an Elixir term.

  Handles JS-style syntax including single quotes, unquoted object keys,
  and standard JSON primitives.

  ## Examples

      iex> PhoenixTestDatastar.Signals.parse_js_value("0")
      0

      iex> PhoenixTestDatastar.Signals.parse_js_value("'hello'")
      "hello"

      iex> PhoenixTestDatastar.Signals.parse_js_value("true")
      true

      iex> PhoenixTestDatastar.Signals.parse_js_value("{foo: 1}")
      %{"foo" => 1}
  """
  @spec parse_js_value(String.t()) :: term()
  def parse_js_value(value) do
    value
    |> String.trim()
    |> normalize_to_json()
    |> Jason.decode!()
  end

  @doc """
  Converts a JavaScript-like expression to valid JSON.

  - Converts single quotes to double quotes
  - Adds quotes around unquoted object keys
  - Handles numbers, booleans, null, arrays, and objects

  ## Examples

      iex> PhoenixTestDatastar.Signals.normalize_to_json("'hello'")
      ~s("hello")

      iex> PhoenixTestDatastar.Signals.normalize_to_json("{foo: 1, bar: 2}")
      ~s({"foo": 1,"bar": 2})
  """
  @spec normalize_to_json(String.t()) :: String.t()
  def normalize_to_json(js_value) do
    js_value
    |> replace_single_quotes()
    |> quote_unquoted_keys()
  end

  @doc """
  Merges new signals into existing state.

  ## Options

  - `:only_if_missing` - When true, only add signals not already present (default: false)

  When a value is `nil`, that signal is removed from the state.

  ## Examples

      iex> PhoenixTestDatastar.Signals.apply_patch(%{"count" => 1}, %{"name" => "test"})
      %{"count" => 1, "name" => "test"}

      iex> PhoenixTestDatastar.Signals.apply_patch(%{"count" => 1}, %{"count" => 2}, only_if_missing: true)
      %{"count" => 1}

      iex> PhoenixTestDatastar.Signals.apply_patch(%{"count" => 1}, %{"count" => nil})
      %{}
  """
  @spec apply_patch(map(), map(), keyword()) :: map()
  def apply_patch(state, new_signals, opts \\ []) do
    only_if_missing = Keyword.get(opts, :only_if_missing, false)

    Enum.reduce(new_signals, state, fn {key, value}, acc ->
      cond do
        # Remove signal if value is nil
        is_nil(value) ->
          Map.delete(acc, key)

        # Skip if only_if_missing and key already exists
        only_if_missing && Map.has_key?(acc, key) ->
          acc

        # Add or update signal
        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  @doc """
  Encodes signals as JSON for POST body, excluding client-only signals.

  Client-only signals (prefixed with underscore) are excluded.

  ## Examples

      iex> PhoenixTestDatastar.Signals.to_post_body(%{"count" => 1, "_csrfToken" => "abc"})
      ~s({"count":1})
  """
  @spec to_post_body(map()) :: String.t()
  def to_post_body(signals) do
    signals
    |> public_signals()
    |> Jason.encode!()
  end

  @doc """
  Encodes signals as datastar query parameter, excluding client-only signals.

  Returns a query string in the format: `datastar=<json>`

  ## Examples

      iex> PhoenixTestDatastar.Signals.to_get_query(%{"count" => 1, "name" => "test"})
      "datastar=%7B%22count%22%3A1%2C%22name%22%3A%22test%22%7D"
  """
  @spec to_get_query(map()) :: String.t()
  def to_get_query(signals) do
    json = to_post_body(signals)
    "datastar=" <> URI.encode_www_form(json)
  end

  @doc """
  Filters out client-only signals (prefixed with underscore).

  ## Examples

      iex> PhoenixTestDatastar.Signals.public_signals(%{"count" => 1, "_csrfToken" => "abc"})
      %{"count" => 1}
  """
  @spec public_signals(map()) :: map()
  def public_signals(signals) do
    signals
    |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_") end)
    |> Enum.into(%{})
  end

  ## Private Functions

  defp traverse_and_extract(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, acc ->
      traverse_and_extract(node, acc)
    end)
  end

  defp traverse_and_extract({_tag, attrs, children}, acc) do
    # Extract signals from this element's attributes
    signals = extract_signals_from_attrs(attrs)
    acc = Map.merge(acc, signals)

    # Traverse children
    traverse_and_extract(children, acc)
  end

  defp traverse_and_extract(_other, acc) do
    # Text nodes, comments, etc.
    acc
  end

  defp extract_signals_from_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn {name, value}, acc ->
      cond do
        # Individual signal like data-signals:count="0" or data-signals:_csrf-token="'abc'"
        String.starts_with?(name, "data-signals:") ->
          key =
            name
            |> String.replace_prefix("data-signals:", "")
            |> kebab_to_camel()

          Map.put(acc, key, parse_js_value(value))

        # Object-style data-signals="{foo: 1, bar: 2}"
        name == "data-signals" ->
          parsed = parse_js_value(value)
          if is_map(parsed) do
            Map.merge(acc, parsed)
          else
            acc
          end

        true ->
          acc
      end
    end)
  end

  @doc """
  Converts a kebab-case string to camelCase.

  HTML attributes are case-insensitive, so Datastar uses kebab-case in
  attribute suffixes (e.g., `data-signals:_csrf-token`) and converts to
  camelCase signal names (`_csrfToken`) on the client.

  Handles leading underscores (preserved) and already-camelCase input.

  ## Examples

      iex> PhoenixTestDatastar.Signals.kebab_to_camel("_csrf-token")
      "_csrfToken"

      iex> PhoenixTestDatastar.Signals.kebab_to_camel("my-signal-name")
      "mySignalName"

      iex> PhoenixTestDatastar.Signals.kebab_to_camel("count")
      "count"

      iex> PhoenixTestDatastar.Signals.kebab_to_camel("_dstar_module")
      "_dstar_module"
  """
  @spec kebab_to_camel(String.t()) :: String.t()
  def kebab_to_camel(str) do
    # Preserve leading underscores
    {prefix, rest} =
      case str do
        "_" <> remainder -> {"_", remainder}
        other -> {"", other}
      end

    parts = String.split(rest, "-")

    camel =
      case parts do
        [first | rest_parts] ->
          first <> Enum.map_join(rest_parts, "", &String.capitalize/1)

        [] ->
          ""
      end

    prefix <> camel
  end

  defp replace_single_quotes(str) do
    # Replace single quotes with double quotes, but be careful about escaping
    # This is a simplified approach - we look for patterns like 'string'
    Regex.replace(~r/'([^']*)'/, str, ~s("\\1"))
  end

  defp quote_unquoted_keys(str) do
    # Add quotes around unquoted object keys like {foo: 1} -> {"foo": 1}
    # Match word characters followed by colon (not already quoted)
    Regex.replace(~r/(\{|,)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:/, str, ~s(\\1"\\2":))
  end
end
