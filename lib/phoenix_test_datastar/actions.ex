defmodule PhoenixTestDatastar.Actions do
  @moduledoc """
  Parses Datastar action expressions from HTML element attributes.

  Datastar actions appear in attributes like `data-on:click`, `data-on:submit`,
  `data-on:change`, and `data-init`. They specify HTTP requests to make when
  events occur.

  ## Examples

      iex> PhoenixTestDatastar.Actions.parse("@post('/ds/counter/increment')")
      {:ok, [%{method: :post, url: "/ds/counter/increment", raw_url: "'/ds/counter/increment'"}]}

      iex> PhoenixTestDatastar.Actions.parse("@get('/ds/items/load')")
      {:ok, [%{method: :get, url: "/ds/items/load", raw_url: "'/ds/items/load'"}]}
  """

  @type action :: %{
          method: :get | :post | :put | :patch | :delete,
          url: String.t(),
          raw_url: String.t()
        }

  # Matches the `location.pathname` token emitted by dstar's page-local
  # helpers (Dstar.Page.Helpers, dstar >= 0.1.0-alpha.2), with an optional
  # trailing-slash-stripping `.replace(/\/+$/, '')` chain:
  #
  #   event("wire_check") #=> "@post(location.pathname.replace(/\/+$/, '') + '/_event/wire_check')"
  #   connect()           #=> "@post(location.pathname, {retryMaxCount: Infinity})"
  @location_pathname_regex ~r{location\.pathname(\.replace\(/\\/\+\$/,\s*''\))?}

  @doc """
  Parse an action expression string into a list of actions.

  Multiple actions can be separated by semicolons or newlines.

  ## Examples

      iex> PhoenixTestDatastar.Actions.parse("@post('/path')")
      {:ok, [%{method: :post, url: "/path", raw_url: "'/path'"}]}

      iex> PhoenixTestDatastar.Actions.parse("@get('/first'); @post('/second')")
      {:ok, [
        %{method: :get, url: "/first", raw_url: "'/first'"},
        %{method: :post, url: "/second", raw_url: "'/second'"}
      ]}
  """
  @spec parse(String.t()) :: {:ok, [action()]} | {:error, term()}
  def parse(expression) when is_binary(expression) do
    # Split by semicolons or newlines to handle multiple actions
    action_strings =
      expression
      |> String.split(~r/[;\n]/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    results = Enum.map(action_strings, &parse_one/1)

    # Check if all parsing succeeded
    if Enum.all?(results, fn {status, _} -> status == :ok end) do
      actions = Enum.map(results, fn {:ok, action} -> action end)
      {:ok, actions}
    else
      # Return the first error
      Enum.find(results, fn {status, _} -> status == :error end)
    end
  end

  @doc """
  Parse a single action expression.

  ## Examples

      iex> PhoenixTestDatastar.Actions.parse_one("@post('/path')")
      {:ok, %{method: :post, url: "/path", raw_url: "'/path'"}}

      iex> PhoenixTestDatastar.Actions.parse_one("@post('/path', {headers: {'x-csrf-token': $_csrfToken}})")
      {:ok, %{method: :post, url: "/path", raw_url: "'/path'"}}

      iex> PhoenixTestDatastar.Actions.parse_one("@get('/ds/items/load')")
      {:ok, %{method: :get, url: "/ds/items/load", raw_url: "'/ds/items/load'"}}
  """
  @spec parse_one(String.t()) :: {:ok, action()} | {:error, term()}
  def parse_one(expression) when is_binary(expression) do
    # Regex to match @method(url) or @method(url, {options})
    # Supports both static strings and dynamic concatenation
    regex = ~r/@(get|post|put|patch|delete)\((.*?)\)(?:\s*,\s*\{.*?\})?\s*$/s

    case Regex.run(regex, String.trim(expression)) do
      [_, method_str, url_part] ->
        method = String.to_atom(method_str)
        {raw_url, resolved_url} = extract_url(url_part)

        {:ok, %{method: method, url: resolved_url, raw_url: raw_url}}

      nil ->
        {:error, "Invalid action expression: #{expression}"}
    end
  end

  @doc """
  Resolve dynamic URL expressions by replacing $signal references with values.

  An optional `current_path` (the session's current path) resolves the
  `location.pathname` token emitted by dstar's page-local helpers
  (`Dstar.Page.Helpers.event/2` and `connect/1` in dstar >= 0.1.0-alpha.2).
  A chained `.replace(/\\/+$/, '')` strips trailing slashes from the current
  path, mirroring what the Datastar JS client computes in the browser. Any
  query string or fragment in `current_path` is ignored, like
  `location.pathname` in the browser.

  ## Examples

      iex> PhoenixTestDatastar.Actions.resolve_url("'/ds/counter/increment'", %{})
      "/ds/counter/increment"

      iex> PhoenixTestDatastar.Actions.resolve_url("'/ds/' + $_dstar_module + '/increment'", %{"_dstar_module" => "my_app-counter"})
      "/ds/my_app-counter/increment"

      iex> PhoenixTestDatastar.Actions.resolve_url("'/prefix/' + $mySignal + '/suffix'", %{"mySignal" => "value"})
      "/prefix/value/suffix"

      iex> PhoenixTestDatastar.Actions.resolve_url("location.pathname", %{}, "/chrismccord")
      "/chrismccord"
  """
  @spec resolve_url(String.t(), map(), String.t() | nil) :: String.t()
  def resolve_url(url_expression, signals, current_path \\ nil)

  def resolve_url(url_expression, signals, current_path)
      when is_binary(url_expression) and is_map(signals) do
    # Remove outer quotes if present and trim
    url_expression =
      url_expression
      |> String.trim()
      |> substitute_location_pathname(current_path)

    # Check if it's a simple static string
    if String.match?(url_expression, ~r/^'[^']*'$/) do
      # Static URL - just remove quotes
      String.slice(url_expression, 1..-2//1)
    else
      # Dynamic URL with concatenation
      # Split by + and process each part
      parts =
        url_expression
        |> String.split("+")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn part ->
          cond do
            # It's a signal reference like $_dstar_module or $mySignal
            String.starts_with?(part, "$") ->
              signal_name = String.trim_leading(part, "$")
              Map.get(signals, signal_name, "")

            # It's a string literal
            String.starts_with?(part, "'") and String.ends_with?(part, "'") ->
              String.slice(part, 1..-2//1)

            # Unknown part, keep as is
            true ->
              part
          end
        end)

      Enum.join(parts, "")
    end
  end

  @doc """
  Find a Datastar action expression in HTML for a given selector.

  Checks attributes in order: data-on:click, data-on:submit, data-on:change.
  Returns the raw expression string or :none if no action is found.

  ## Examples

      iex> html = ~s[<button data-on:click="@post('/increment')">Click</button>]
      iex> PhoenixTestDatastar.Actions.find_action(html, "button")
      {:ok, "@post('/increment')"}

      iex> html = ~s[<div class="no-action">Content</div>]
      iex> PhoenixTestDatastar.Actions.find_action(html, "div")
      :none
  """
  @spec find_action(String.t(), String.t()) :: {:ok, String.t()} | :none
  def find_action(raw_html, selector) when is_binary(raw_html) and is_binary(selector) do
    doc = Floki.parse_document!(raw_html)
    elements = Floki.find(doc, selector)

    action_prefixes = ["data-on:click", "data-on:submit", "data-on:change"]

    result =
      Enum.find_value(elements, fn {_tag, attrs, _children} ->
        Enum.find_value(action_prefixes, fn prefix ->
          Enum.find_value(attrs, fn
            {attr_name, value} ->
              if (attr_name == prefix or String.starts_with?(attr_name, prefix <> "__")) and
                   value != "" do
                value
              end

            _ ->
              nil
          end)
        end)
      end)

    case result do
      nil -> :none
      expr -> {:ok, expr}
    end
  end

  @doc """
  Find all data-init attributes in HTML that contain @post/@get actions.

  Returns a list of {selector_or_id, expression} tuples.

  ## Examples

      iex> html = ~s[<div id="counter" data-init="@get('/load')">Content</div>]
      iex> PhoenixTestDatastar.Actions.find_init_actions(html)
      [{"#counter", "@get('/load')"}]
  """
  @spec find_init_actions(String.t()) :: [{String.t(), String.t()}]
  def find_init_actions(raw_html) when is_binary(raw_html) do
    doc = Floki.parse_document!(raw_html)

    doc
    |> Floki.find("[data-init]")
    |> Enum.filter(fn element ->
      case Floki.attribute(element, "data-init") do
        [value | _] -> String.match?(value, ~r/@(get|post|put|patch|delete)/)
        _ -> false
      end
    end)
    |> Enum.map(fn element ->
      # Get the data-init value
      [init_value | _] = Floki.attribute(element, "data-init")

      # Try to create a selector - prefer ID, otherwise use tag and class
      selector =
        case Floki.attribute(element, "id") do
          [id | _] when id != "" ->
            "##{id}"

          _ ->
            # Build a selector from tag and class
            {tag, attrs, _} = element

            classes =
              case Enum.find(attrs, fn {key, _} -> key == "class" end) do
                {_, class_value} -> ".#{String.replace(class_value, " ", ".")}"
                _ -> ""
              end

            "#{tag}#{classes}"
        end

      {selector, init_value}
    end)
  end

  # Private helper to extract URL from the action expression
  defp extract_url(url_part) do
    # Clean up the URL part - remove trailing options if present
    url_part =
      url_part
      |> String.trim()
      |> strip_options_object()
      |> String.trim()

    # The raw URL is what we got
    raw_url = url_part

    # Resolve it as a static URL for now (no signals provided at parse time)
    resolved_url = resolve_url(url_part, %{})

    {raw_url, resolved_url}
  end

  # Drops a trailing `, {...}` options object (headers, retryMaxCount, ...)
  # without splitting on commas that belong to the URL expression itself,
  # such as the one inside `location.pathname.replace(/\/+$/, '')`.
  defp strip_options_object(url_part) do
    Regex.replace(~r/,\s*\{.*\}\s*$/s, url_part, "")
  end

  # Replaces the `location.pathname` token (optionally chained with
  # `.replace(/\/+$/, '')`) with the session's current path as a quoted
  # string literal, so the rest of the expression resolves as usual.
  defp substitute_location_pathname(url_expression, current_path) do
    Regex.replace(@location_pathname_regex, url_expression, fn _match, replace_chain ->
      pathname = current_pathname(current_path)

      resolved =
        if replace_chain == "" do
          pathname
        else
          # Mirror the client-side `.replace(/\/+$/, '')`
          String.replace(pathname, ~r{/+$}, "")
        end

      "'" <> resolved <> "'"
    end)
  end

  # `location.pathname` never includes the query string or fragment.
  defp current_pathname(nil), do: ""

  defp current_pathname(current_path) when is_binary(current_path) do
    current_path
    |> String.split(["?", "#"], parts: 2)
    |> List.first()
  end
end
