defmodule PhoenixTestDatastar.Actions do
  @moduledoc """
  Parses Datastar action expressions from HTML element attributes.

  Datastar actions appear in attributes like `data-on:click`, `data-on:submit`,
  `data-on:change`, and `data-init`. They specify HTTP requests to make when
  events occur.

  URL expressions are resolved the way the Datastar client would resolve them
  in the browser. Besides string literals and `$signal` references, the
  browser expressions emitted by dstar are understood:

    * `location.pathname`, with dstar's `.replace(/^\\/+/, '/')` and
      `.replace(/\\/+$/, '')` normalisations (`Dstar.Page.Helpers.event/2`,
      `connect/1`)
    * `location.search` (`connect(include_search: true)`)
    * the component dispatch base IIFE reading `<body data-ds-base>`
      (`Dstar.Component` `event/2`)
    * the `$_dstar_module` segment encoder (`Dstar.Actions.post/2` and friends
      with a dynamic module)

  Both dstar >= 0.3 (double-quoted, percent-encoded literals) and the older
  0.1/0.2 shapes (single-quoted literals, `location.pathname.replace(/\\/+$/, '')`)
  are supported.

  ## Examples

      iex> PhoenixTestDatastar.Actions.parse("@post('/ds/counter/increment')")
      {:ok, [%{method: :post, url: "/ds/counter/increment", raw_url: "'/ds/counter/increment'"}]}

      iex> PhoenixTestDatastar.Actions.parse(~s|@get("/ds/items/load")|)
      {:ok, [%{method: :get, url: "/ds/items/load", raw_url: ~s|"/ds/items/load"|}]}
  """

  @type action :: %{
          method: :get | :post | :put | :patch | :delete,
          url: String.t(),
          raw_url: String.t()
        }

  # Browser expressions emitted by dstar, masked before an expression is split
  # so the quotes, commas, semicolons and `+` inside them are never mistaken for
  # expression structure. Order matters: the component base IIFE contains its
  # own `.replace(...)` call and must be masked before anything else.
  @fragments [
    # Dstar.Component (dstar >= 0.3): `<body data-ds-base>` or the default base.
    component_base:
      ~r/\(\(\) => \{ const base = document\.body\.dataset\.dsBase \|\| '([^']*)';.*?return base\.replace\(\/\\\/\+\$\/, ''\) \}\)\(\)/s,
    # Dynamic module segment (dstar >= 0.3), encoded like encodeURIComponent
    # plus `!'()*.`.
    encoded_segment: ~r/\(\(segment\) => \{.*?\}\)\(\$([\w.]+)\)/s,
    # Page helpers. dstar >= 0.3 collapses leading slashes; dstar 0.1/0.2 and
    # 0.3 strip trailing slashes for event URLs.
    pathname:
      ~r/location\.pathname(\.replace\(\/\^\\\/\+\/,\s*'\/'\))?(\.replace\(\/\\\/\+\$\/,\s*''\))?/,
    search: ~r/location\.search/
  ]

  @verb_regex ~r/\A@(get|post|put|patch|delete)\((.*)\)\z/s

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
    {masked, tokens} = mask(expression)

    results =
      masked
      |> split_top_level([?;, ?\n])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&(&1 |> unmask(tokens) |> parse_one()))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, action} -> action end)}
      error -> error
    end
  end

  @doc """
  Parse a single action expression.

  The `url` is resolved without signals or a current path; use
  `resolve_url/4` with the session state to get the request path.

  Leading `confirm(...) &&` guards are treated as accepted: the guarded
  action is returned.

  ## Examples

      iex> PhoenixTestDatastar.Actions.parse_one("@post('/path')")
      {:ok, %{method: :post, url: "/path", raw_url: "'/path'"}}

      iex> PhoenixTestDatastar.Actions.parse_one("@post('/path', {headers: {'x-csrf-token': $_csrfToken}})")
      {:ok, %{method: :post, url: "/path", raw_url: "'/path'"}}

      iex> PhoenixTestDatastar.Actions.parse_one("@get('/ds/items/load')")
      {:ok, %{method: :get, url: "/ds/items/load", raw_url: "'/ds/items/load'"}}

      iex> PhoenixTestDatastar.Actions.parse_one("confirm('Sure?') && @post('/ds/items/remove')")
      {:ok, %{method: :post, url: "/ds/items/remove", raw_url: "'/ds/items/remove'"}}
  """
  @spec parse_one(String.t()) :: {:ok, action()} | {:error, term()}
  def parse_one(expression) when is_binary(expression) do
    {masked, tokens} = mask(String.trim(expression))

    with {:ok, masked} <- strip_confirm_guards(masked),
         [_, method_str, args] <- Regex.run(@verb_regex, masked),
         [url_part | _options] <- split_top_level(args, [?,]),
         url_part when url_part != "" <- String.trim(url_part) do
      raw_url = unmask(url_part, tokens)
      url = resolve(raw_url, %{signals: %{}, current_path: nil, ds_base: nil, strict: false})

      {:ok, %{method: String.to_existing_atom(method_str), url: url, raw_url: raw_url}}
    else
      _ -> {:error, "Invalid action expression: #{expression}"}
    end
  end

  @doc """
  Resolve a URL expression to the request path the browser would use.

  `signals` resolves `$signal` references and dstar's dynamic
  `$_dstar_module` segment. `current_path` (the session's current path,
  query string included) resolves `location.pathname` and `location.search`.

  ## Options

    * `:ds_base` - the `data-ds-base` attribute of the page's `<body>`, used
      by `Dstar.Component` actions. Defaults to the base the expression falls
      back to (`/ds`).

  Raises `ArgumentError` when the expression contains parts that can't be
  resolved outside a browser, or when the browser would reject the URL
  (invalid component base, empty or dot module segment).

  ## Examples

      iex> PhoenixTestDatastar.Actions.resolve_url("'/ds/counter/increment'", %{})
      "/ds/counter/increment"

      iex> PhoenixTestDatastar.Actions.resolve_url(~s|"/ds/my_app-counter/increment"|, %{})
      "/ds/my_app-counter/increment"

      iex> PhoenixTestDatastar.Actions.resolve_url("'/ds/' + $_dstar_module + '/increment'", %{"_dstar_module" => "my_app-counter"})
      "/ds/my_app-counter/increment"

      iex> PhoenixTestDatastar.Actions.resolve_url("'/prefix/' + $mySignal + '/suffix'", %{"mySignal" => "value"})
      "/prefix/value/suffix"

      iex> PhoenixTestDatastar.Actions.resolve_url("location.pathname", %{}, "/chrismccord")
      "/chrismccord"

      iex> PhoenixTestDatastar.Actions.resolve_url(
      ...>   ~S|location.pathname.replace(/^\\/+/, '/').replace(/\\/+$/, '') + "/_event/save"|,
      ...>   %{},
      ...>   "/posts/"
      ...> )
      "/posts/_event/save"
  """
  @spec resolve_url(String.t(), map(), String.t() | nil, keyword()) :: String.t()
  def resolve_url(url_expression, signals, current_path \\ nil, opts \\ [])

  def resolve_url(url_expression, signals, current_path, opts)
      when is_binary(url_expression) and is_map(signals) and is_list(opts) do
    resolve(url_expression, %{
      signals: signals,
      current_path: current_path,
      ds_base: Keyword.get(opts, :ds_base),
      strict: true
    })
  end

  @doc """
  Returns the `data-ds-base` attribute of the page's `<body>`, if any.

  `Dstar.Component` actions read it in the browser to find the component
  dispatch base.

  ## Examples

      iex> PhoenixTestDatastar.Actions.find_ds_base(~s|<body data-ds-base="/acme/ds"></body>|)
      "/acme/ds"

      iex> PhoenixTestDatastar.Actions.find_ds_base("<body></body>")
      nil
  """
  @spec find_ds_base(String.t()) :: String.t() | nil
  def find_ds_base(raw_html) when is_binary(raw_html) do
    raw_html
    |> Floki.parse_document!()
    |> Floki.find("body")
    |> Floki.attribute("data-ds-base")
    |> List.first()
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

  # ── URL resolution ──────────────────────────────────────────────────

  defp resolve(url_expression, ctx) do
    {masked, tokens} = mask(String.trim(url_expression))

    masked
    |> split_top_level([?+])
    |> Enum.map_join(&resolve_part(String.trim(&1), tokens, ctx))
  end

  defp resolve_part(part, tokens, ctx) do
    cond do
      Map.has_key?(tokens, part) ->
        resolve_token(Map.fetch!(tokens, part), ctx)

      String.starts_with?(part, "\"") and String.ends_with?(part, "\"") ->
        case Jason.decode(part) do
          {:ok, literal} when is_binary(literal) -> literal
          _ -> unresolvable!(part, ctx)
        end

      single_quoted?(part) ->
        part |> String.slice(1..-2//1) |> String.replace("\\'", "'")

      String.starts_with?(part, "$") ->
        part |> String.trim_leading("$") |> signal_value(ctx.signals) |> to_string()

      true ->
        unresolvable!(part, ctx)
    end
  end

  defp single_quoted?(part) do
    String.length(part) >= 2 and String.starts_with?(part, "'") and String.ends_with?(part, "'")
  end

  # Lenient (parse-time) resolution keeps unknown parts verbatim, as 0.0.2 did.
  defp unresolvable!(part, %{strict: false}), do: part

  defp unresolvable!(part, _ctx) do
    raise ArgumentError,
          "cannot resolve Datastar action URL part #{inspect(part)}; " <>
            "phoenix_test_datastar understands string literals, $signals and the " <>
            "location/data-ds-base/module expressions emitted by dstar"
  end

  defp resolve_token({:pathname, [_match | chains], _original}, ctx) do
    pathname = current_pathname(ctx.current_path)

    # Mirrors dstar's `.replace(/^\/+/, '/')` then `.replace(/\/+$/, '')`
    pathname =
      if Enum.at(chains, 0, "") != "",
        do: String.replace(pathname, ~r{^/+}, "/"),
        else: pathname

    if Enum.at(chains, 1, "") != "",
      do: String.replace(pathname, ~r{/+$}, ""),
      else: pathname
  end

  defp resolve_token({:search, _captures, _original}, ctx), do: current_search(ctx.current_path)

  defp resolve_token({:component_base, [_match, default], _original}, ctx) do
    base = ctx.ds_base || default

    if unsafe_base?(base) do
      raise ArgumentError,
            "invalid Dstar component base #{inspect(base)} (from <body data-ds-base>); " <>
              "the browser would reject this action"
    end

    String.replace(base, ~r{/+$}, "")
  end

  defp resolve_token({:encoded_segment, [_match, signal], _original}, ctx) do
    case signal_value(signal, ctx.signals) do
      segment when is_binary(segment) and segment not in ["", ".", ".."] ->
        encode_segment(segment)

      _invalid when not ctx.strict ->
        ""

      invalid ->
        raise ArgumentError,
              "invalid Dstar module segment #{inspect(invalid)} in signal $#{signal}; " <>
                "the browser would reject this action"
    end
  end

  # Mirrors the checks in dstar's component base IIFE.
  defp unsafe_base?(base) do
    Enum.any?([base, URI.decode(base)], fn value ->
      not String.valid?(value) or not String.starts_with?(value, "/") or
        String.starts_with?(value, "//") or String.match?(value, ~r/[\\?#\x00-\x1F\x7F]/) or
        Enum.any?(String.split(value, "/"), &(&1 in [".", ".."]))
    end)
  rescue
    ArgumentError -> true
  end

  # encodeURIComponent plus `!'()*.`, as done by dstar in the browser.
  defp encode_segment(segment) do
    URI.encode(segment, fn char ->
      char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?-, ?_, ?~]
    end)
  end

  defp signal_value(name, signals) do
    case Map.fetch(signals, name) do
      {:ok, value} ->
        value

      :error ->
        # `$user.name` reads a nested signal.
        Enum.reduce_while(String.split(name, "."), signals, fn key, acc ->
          case acc do
            %{^key => value} -> {:cont, value}
            _ -> {:halt, ""}
          end
        end)
    end
  end

  # `location.pathname` never includes the query string or fragment.
  defp current_pathname(nil), do: ""

  defp current_pathname(current_path) do
    current_path |> String.split(["?", "#"], parts: 2) |> List.first()
  end

  # `location.search` is `?query`, or "" when the query is empty.
  defp current_search(nil), do: ""

  defp current_search(current_path) do
    current_path
    |> String.split("#", parts: 2)
    |> List.first()
    |> String.split("?", parts: 2)
    |> case do
      [_path, query] when query != "" -> "?" <> query
      _ -> ""
    end
  end

  # ── Expression scanning ─────────────────────────────────────────────

  # `confirm('...') && @post(...)`: a test always accepts the dialog, so drop
  # the guards and keep the action. Any other guard is rejected.
  defp strip_confirm_guards(masked) do
    {guards, [action]} =
      masked
      |> split_top_level([?&])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.split(-1)

    if Enum.all?(guards, &Regex.match?(~r/\Aconfirm\(.*\)\z/s, &1)),
      do: {:ok, action},
      else: :error
  end

  # Replaces every known dstar fragment with an opaque placeholder token.
  # Returns the masked expression and a map of placeholder => token.
  defp mask(expression) do
    Enum.reduce(@fragments, {expression, %{}}, fn {kind, regex}, {text, tokens} ->
      regex
      |> Regex.scan(text, return: :index)
      |> Enum.reverse()
      |> Enum.reduce({text, tokens}, fn [{start, length} | _] = indexes, {text, tokens} ->
        captures = Enum.map(indexes, &capture(text, &1))
        original = binary_part(text, start, length)
        placeholder = <<0>> <> Integer.to_string(map_size(tokens)) <> <<0>>

        text =
          binary_part(text, 0, start) <>
            placeholder <> binary_part(text, start + length, byte_size(text) - start - length)

        {text, Map.put(tokens, placeholder, {kind, captures, original})}
      end)
    end)
  end

  defp capture(_text, {-1, 0}), do: ""
  defp capture(text, {start, length}), do: binary_part(text, start, length)

  defp unmask(text, tokens) do
    Enum.reduce(tokens, text, fn {placeholder, {_kind, _captures, original}}, acc ->
      String.replace(acc, placeholder, original)
    end)
  end

  # Splits on `separators` outside of string literals and brackets.
  defp split_top_level(text, separators), do: split_top_level(text, separators, [], "", [])

  defp split_top_level(<<>>, _separators, _stack, current, parts),
    do: Enum.reverse([current | parts])

  defp split_top_level(
         <<?\\, char::utf8, rest::binary>>,
         separators,
         [quote | _] = stack,
         current,
         parts
       )
       when quote in [?', ?", ?`] do
    split_top_level(rest, separators, stack, current <> <<?\\, char::utf8>>, parts)
  end

  defp split_top_level(
         <<char::utf8, rest::binary>>,
         separators,
         [quote | stack_rest] = stack,
         current,
         parts
       )
       when quote in [?', ?", ?`] do
    stack = if char == quote, do: stack_rest, else: stack
    split_top_level(rest, separators, stack, current <> <<char::utf8>>, parts)
  end

  defp split_top_level(<<char::utf8, rest::binary>>, separators, stack, current, parts) do
    cond do
      char in [?', ?", ?`, ?(, ?[, ?{] ->
        split_top_level(rest, separators, [char | stack], current <> <<char::utf8>>, parts)

      char in [?), ?], ?}] ->
        split_top_level(rest, separators, Enum.drop(stack, 1), current <> <<char::utf8>>, parts)

      stack == [] and char in separators ->
        split_top_level(rest, separators, stack, "", [current | parts])

      true ->
        split_top_level(rest, separators, stack, current <> <<char::utf8>>, parts)
    end
  end
end
