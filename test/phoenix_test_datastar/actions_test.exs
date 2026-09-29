defmodule PhoenixTestDatastar.ActionsTest do
  use ExUnit.Case, async: true
  alias PhoenixTestDatastar.Actions

  doctest PhoenixTestDatastar.Actions

  describe "parse/1" do
    test "parses simple @post action" do
      assert {:ok, [action]} = Actions.parse("@post('/path')")
      assert action.method == :post
      assert action.url == "/path"
      assert action.raw_url == "'/path'"
    end

    test "parses @post with headers" do
      expression = "@post('/path', {headers: {'x-csrf-token': $_csrfToken}})"
      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post
      assert action.url == "/path"
    end

    test "parses @get action" do
      assert {:ok, [action]} = Actions.parse("@get('/path')")
      assert action.method == :get
      assert action.url == "/path"
    end

    test "parses @put action" do
      assert {:ok, [action]} = Actions.parse("@put('/path')")
      assert action.method == :put
      assert action.url == "/path"
    end

    test "parses @patch action" do
      assert {:ok, [action]} = Actions.parse("@patch('/path')")
      assert action.method == :patch
      assert action.url == "/path"
    end

    test "parses @delete action" do
      assert {:ok, [action]} = Actions.parse("@delete('/path')")
      assert action.method == :delete
      assert action.url == "/path"
    end

    test "parses multiple actions separated by semicolon" do
      expression = "@get('/first'); @post('/second')"
      assert {:ok, actions} = Actions.parse(expression)
      assert length(actions) == 2
      assert Enum.at(actions, 0).method == :get
      assert Enum.at(actions, 0).url == "/first"
      assert Enum.at(actions, 1).method == :post
      assert Enum.at(actions, 1).url == "/second"
    end

    test "parses multiple actions separated by newline" do
      expression = """
      @get('/first')
      @post('/second')
      """

      assert {:ok, actions} = Actions.parse(expression)
      assert length(actions) == 2
      assert Enum.at(actions, 0).method == :get
      assert Enum.at(actions, 1).method == :post
    end

    test "parses action with path params" do
      assert {:ok, [action]} = Actions.parse("@post('/ds/my_app-counter/increment')")
      assert action.method == :post
      assert action.url == "/ds/my_app-counter/increment"
    end

    test "handles action with dynamic URL expression" do
      expression =
        "@post('/ds/' + $_dstar_module + '/increment', {headers: {'x-csrf-token': $_csrfToken}})"

      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post
      # Without signal resolution, dynamic parts are empty
      assert action.url == "/ds//increment"
    end

    test "returns error for invalid expression" do
      assert {:error, message} = Actions.parse("not an action")
      assert message =~ "Invalid action expression"
    end
  end

  describe "parse_one/1" do
    test "parses single @post action" do
      assert {:ok, action} = Actions.parse_one("@post('/path')")
      assert action.method == :post
      assert action.url == "/path"
    end

    test "parses @get action" do
      assert {:ok, action} = Actions.parse_one("@get('/items/load')")
      assert action.method == :get
      assert action.url == "/items/load"
    end

    test "parses action with options" do
      expression = "@post('/path', {headers: {'x-csrf-token': 'token123'}})"
      assert {:ok, action} = Actions.parse_one(expression)
      assert action.method == :post
      assert action.url == "/path"
    end

    test "returns error for invalid action" do
      assert {:error, _} = Actions.parse_one("invalid")
    end
  end

  describe "resolve_url/2" do
    test "resolves static URL without changes" do
      url = "'/ds/counter/increment'"
      assert Actions.resolve_url(url, %{}) == "/ds/counter/increment"
    end

    test "resolves dynamic URL with signal" do
      url = "'/ds/' + $_dstar_module + '/increment'"
      signals = %{"_dstar_module" => "my_app-counter"}
      assert Actions.resolve_url(url, signals) == "/ds/my_app-counter/increment"
    end

    test "resolves dynamic URL with multiple signals" do
      url = "'/prefix/' + $signal1 + '/middle/' + $signal2 + '/suffix'"
      signals = %{"signal1" => "value1", "signal2" => "value2"}
      assert Actions.resolve_url(url, signals) == "/prefix/value1/middle/value2/suffix"
    end

    test "resolves URL with missing signal as empty string" do
      url = "'/ds/' + $missing + '/path'"
      assert Actions.resolve_url(url, %{}) == "/ds//path"
    end

    test "handles signal without underscore prefix" do
      url = "'/path/' + $mySignal"
      signals = %{"mySignal" => "value"}
      assert Actions.resolve_url(url, signals) == "/path/value"
    end

    test "handles complex path" do
      url = "'/ds/my_app-counter/increment'"
      assert Actions.resolve_url(url, %{}) == "/ds/my_app-counter/increment"
    end
  end

  # Legacy URL expressions emitted by dstar 0.1/0.2 page helpers
  # (Dstar.Page.Helpers.event/2 and connect/1):
  #
  #   event("wire_check") #=> "@post(location.pathname.replace(/\/+$/, '') + '/_event/wire_check')"
  #   connect()           #=> "@post(location.pathname, {retryMaxCount: Infinity})"
  describe "resolve_url/3 with location.pathname (dstar page helpers)" do
    @event_raw_url "location.pathname.replace(/\\/+$/, '') + '/_event/wire_check'"

    test "resolves event() URL against the current path" do
      assert Actions.resolve_url(@event_raw_url, %{}, "/signin") ==
               "/signin/_event/wire_check"
    end

    test "strips trailing slashes from the current path when replace-chain is present" do
      assert Actions.resolve_url(@event_raw_url, %{}, "/signin/") ==
               "/signin/_event/wire_check"
    end

    test "resolves event() URL at the root path" do
      assert Actions.resolve_url(@event_raw_url, %{}, "/") == "/_event/wire_check"
    end

    test "resolves bare location.pathname (connect() case)" do
      assert Actions.resolve_url("location.pathname", %{}, "/chrismccord") == "/chrismccord"
    end

    test "bare location.pathname keeps a trailing slash (no replace-chain)" do
      assert Actions.resolve_url("location.pathname", %{}, "/chrismccord/") == "/chrismccord/"
    end

    test "ignores query string in the session current path" do
      assert Actions.resolve_url(@event_raw_url, %{}, "/signin?next=%2Fhome") ==
               "/signin/_event/wire_check"

      assert Actions.resolve_url("location.pathname", %{}, "/chrismccord?tab=songs") ==
               "/chrismccord"
    end

    test "resolve_url/2 (no current path) still resolves literals and signals" do
      assert Actions.resolve_url("'/ds/counter/increment'", %{}) == "/ds/counter/increment"

      assert Actions.resolve_url("'/ds/' + $_dstar_module + '/inc'", %{
               "_dstar_module" => "counter"
             }) == "/ds/counter/inc"
    end
  end

  describe "parse with location.pathname URLs (dstar 0.1/0.2 page helpers)" do
    test "parses event(\"wire_check\") expression without mangling the replace call" do
      expression = "@post(location.pathname.replace(/\\/+$/, '') + '/_event/wire_check')"

      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post
      assert action.raw_url == "location.pathname.replace(/\\/+$/, '') + '/_event/wire_check'"
    end

    test "parses event(\"remove\", verb: :delete) expression" do
      expression = "@delete(location.pathname.replace(/\\/+$/, '') + '/_event/remove')"

      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :delete
      assert action.raw_url == "location.pathname.replace(/\\/+$/, '') + '/_event/remove'"
    end

    test "parses connect() expression, dropping the options object" do
      expression = "@post(location.pathname, {retryMaxCount: Infinity})"

      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post
      assert action.raw_url == "location.pathname"
    end

    test "parses event() expression with an options object after the URL" do
      expression =
        "@post(location.pathname.replace(/\\/+$/, '') + '/_event/wire_check', {retryMaxCount: 5})"

      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post
      assert action.raw_url == "location.pathname.replace(/\\/+$/, '') + '/_event/wire_check'"
    end

    test "full workflow: find, parse, resolve against current path" do
      html = """
      <button id="wire-btn"
        data-on:click="@post(location.pathname.replace(/\\/+$/, '') + '/_event/wire_check')">
        Wire Check
      </button>
      """

      assert {:ok, expression} = Actions.find_action(html, "#wire-btn")
      assert {:ok, [action]} = Actions.parse(expression)

      assert Actions.resolve_url(action.raw_url, %{}, "/signin") ==
               "/signin/_event/wire_check"
    end
  end

  describe "find_action/2" do
    test "finds data-on:click action" do
      html = """
      <button data-on:click="@post('/increment')">Click me</button>
      """

      assert {:ok, expression} = Actions.find_action(html, "button")
      assert expression == "@post('/increment')"
    end

    test "finds data-on:submit action" do
      html = """
      <form data-on:submit="@post('/submit')">
        <button type="submit">Submit</button>
      </form>
      """

      assert {:ok, expression} = Actions.find_action(html, "form")
      assert expression == "@post('/submit')"
    end

    test "finds data-on:change action" do
      html = """
      <input data-on:change="@post('/update')" />
      """

      assert {:ok, expression} = Actions.find_action(html, "input")
      assert expression == "@post('/update')"
    end

    test "returns :none when element has no action" do
      html = """
      <div class="no-action">Content</div>
      """

      assert Actions.find_action(html, "div") == :none
    end

    test "returns :none when element not found" do
      html = """
      <div>Content</div>
      """

      assert Actions.find_action(html, "button") == :none
    end

    test "finds action with CSS selector" do
      html = """
      <button class="increment-btn" data-on:click="@post('/increment')">+</button>
      """

      assert {:ok, expression} = Actions.find_action(html, ".increment-btn")
      assert expression == "@post('/increment')"
    end

    test "finds action with ID selector" do
      html = """
      <button id="increment" data-on:click="@post('/increment')">+</button>
      """

      assert {:ok, expression} = Actions.find_action(html, "#increment")
      assert expression == "@post('/increment')"
    end

    test "prioritizes data-on:click over other attributes" do
      html = """
      <button data-on:click="@post('/click')" data-on:submit="@post('/submit')">Button</button>
      """

      assert {:ok, expression} = Actions.find_action(html, "button")
      assert expression == "@post('/click')"
    end

    test "finds action with complex expression" do
      html = """
      <button data-on:click="@post('/ds/my_app-counter/increment', {headers: {'x-csrf-token': $_csrfToken}})">
        Increment
      </button>
      """

      assert {:ok, expression} = Actions.find_action(html, "button")
      assert expression =~ "@post('/ds/my_app-counter/increment'"
      assert expression =~ "x-csrf-token"
    end
  end

  describe "find_init_actions/1" do
    test "finds single data-init action" do
      html = """
      <div id="counter" data-init="@get('/load')">Content</div>
      """

      assert [{selector, expression}] = Actions.find_init_actions(html)
      assert selector == "#counter"
      assert expression == "@get('/load')"
    end

    test "finds multiple data-init actions" do
      html = """
      <div id="first" data-init="@get('/first')">First</div>
      <div id="second" data-init="@post('/second')">Second</div>
      """

      results = Actions.find_init_actions(html)
      assert length(results) == 2

      assert {"#first", "@get('/first')"} in results
      assert {"#second", "@post('/second')"} in results
    end

    test "ignores data-init without action" do
      html = """
      <div id="with-action" data-init="@get('/load')">Has action</div>
      <div id="no-action" data-init="console.log('hi')">No action</div>
      """

      results = Actions.find_init_actions(html)
      assert length(results) == 1
      assert {"#with-action", "@get('/load')"} in results
    end

    test "returns empty list when no init actions found" do
      html = """
      <div>No init actions here</div>
      """

      assert Actions.find_init_actions(html) == []
    end

    test "creates selector from class when no id" do
      html = """
      <div class="counter-widget" data-init="@get('/load')">Content</div>
      """

      assert [{selector, expression}] = Actions.find_init_actions(html)
      assert selector == "div.counter-widget"
      assert expression == "@get('/load')"
    end

    test "handles multiple classes in selector" do
      html = """
      <div class="widget counter-widget" data-init="@get('/load')">Content</div>
      """

      assert [{selector, _}] = Actions.find_init_actions(html)
      assert selector == "div.widget.counter-widget"
    end

    test "finds @post, @put, @patch, @delete in data-init" do
      html = """
      <div id="a" data-init="@post('/a')">A</div>
      <div id="b" data-init="@put('/b')">B</div>
      <div id="c" data-init="@patch('/c')">C</div>
      <div id="d" data-init="@delete('/d')">D</div>
      """

      results = Actions.find_init_actions(html)
      assert length(results) == 4
    end
  end

  describe "integration tests" do
    test "full workflow: find, parse, resolve" do
      html = """
      <button id="increment" data-on:click="@post('/ds/' + $_dstar_module + '/increment')">
        Increment
      </button>
      """

      # Find the action
      assert {:ok, expression} = Actions.find_action(html, "#increment")

      # Parse it
      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post

      # Resolve with signals
      resolved = Actions.resolve_url(action.raw_url, %{"_dstar_module" => "counter"})
      assert resolved == "/ds/counter/increment"
    end

    test "handles action with path params and headers" do
      expression =
        "@post('/ds/my_app-counter/increment', {headers: {'x-csrf-token': $_csrfToken}})"

      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post
      assert action.url == "/ds/my_app-counter/increment"
    end
  end

  # Expressions rendered by the dstar test dependency itself, so these
  # break loudly if dstar changes its URL shapes again.
  describe "dstar >= 0.3 action URLs" do
    alias PhoenixTestDatastar.TestHandlers.{CounterHandler, WidgetComponent}

    @counter "phoenix_test_datastar-test_handlers-counter_handler"
    @widget "phoenix_test_datastar-test_handlers-widget_component"

    defp resolve(expression, signals \\ %{}, current_path \\ nil, opts \\ []) do
      assert {:ok, [action]} = Actions.parse(expression)
      {action.method, Actions.resolve_url(action.raw_url, signals, current_path, opts)}
    end

    test "Dstar.Page.Helpers.event/2 resolves against the current path" do
      expression = Dstar.Page.Helpers.event("save")

      assert resolve(expression, %{}, "/posts/42") == {:post, "/posts/42/_event/save"}
      assert resolve(expression, %{}, "/posts/42/?tab=a") == {:post, "/posts/42/_event/save"}
      assert resolve(expression, %{}, "//posts//") == {:post, "/posts/_event/save"}
      assert resolve(expression, %{}, "/") == {:post, "/_event/save"}
    end

    test "Dstar.Page.Helpers.event/2 percent-encodes the event and honours :verb" do
      expression = Dstar.Page.Helpers.event("remove item/1.(x)", verb: :delete)

      assert resolve(expression, %{}, "/items") ==
               {:delete, "/items/_event/remove%20item%2F1%2E%28x%29"}
    end

    test "Dstar.Page.Helpers.event/2 with :opts keeps only the URL" do
      expression = Dstar.Page.Helpers.event("save", opts: "{contentType: 'form'}")
      assert resolve(expression, %{}, "/posts") == {:post, "/posts/_event/save"}
    end

    test "Dstar.Page.Helpers.connect/0 posts to the current path without the query" do
      expression = Dstar.Page.Helpers.connect()

      assert resolve(expression, %{}, "/feed/?tab=a") == {:post, "/feed/"}
      assert resolve(expression, %{}, "//feed") == {:post, "/feed"}
    end

    test "Dstar.Page.Helpers.connect(include_search: true) keeps the query" do
      expression = Dstar.Page.Helpers.connect(include_search: true)

      assert resolve(expression, %{}, "/feed?tab=a&page=2#top") == {:post, "/feed?tab=a&page=2"}
      assert resolve(expression, %{}, "/feed?") == {:post, "/feed"}
      assert resolve(expression, %{}, "/feed") == {:post, "/feed"}
    end

    test "Dstar.Actions module form" do
      assert resolve(Dstar.Actions.post(CounterHandler, "increment")) ==
               {:post, "/ds/#{@counter}/increment"}

      assert resolve(Dstar.Actions.get(CounterHandler, "a.b!")) ==
               {:get, "/ds/#{@counter}/a%2Eb%21"}
    end

    test "Dstar.Actions module form with :prefix" do
      assert resolve(Dstar.Actions.put(CounterHandler, "save", prefix: "/acme/")) ==
               {:put, "/acme/ds/#{@counter}/save"}
    end

    test "Dstar.Actions dynamic module reads and encodes $_dstar_module" do
      expression = Dstar.Actions.post("increment")

      assert resolve(expression, %{"_dstar_module" => @counter}) ==
               {:post, "/ds/#{@counter}/increment"}

      assert resolve(expression, %{"_dstar_module" => "my app.x"}) ==
               {:post, "/ds/my%20app%2Ex/increment"}
    end

    test "Dstar.Actions dynamic module rejects values the browser rejects" do
      expression = Dstar.Actions.post("increment")

      for invalid <- [%{}, %{"_dstar_module" => ""}, %{"_dstar_module" => ".."}] do
        assert_raise ArgumentError, ~r/invalid Dstar module segment/, fn ->
          resolve(expression, invalid)
        end
      end
    end

    test "Dstar.Actions dynamic form with a literal :module" do
      assert resolve(Dstar.Actions.delete("remove", module: @counter)) ==
               {:delete, "/ds/#{@counter}/remove"}
    end

    test "Dstar.Component event/2 uses the default /ds base" do
      assert resolve(WidgetComponent.event("ping!")) == {:post, "/ds/#{@widget}/ping%21"}
    end

    test "Dstar.Component event/2 uses <body data-ds-base>" do
      expression = WidgetComponent.event("ping!", verb: :patch)

      assert resolve(expression, %{}, "/", ds_base: "/acme/ds/") ==
               {:patch, "/acme/ds/#{@widget}/ping%21"}
    end

    test "Dstar.Component event/2 rejects a base the browser rejects" do
      for base <- ["acme/ds", "//evil.example/ds", "/acme/../ds", "/acme/%2e%2e/ds", "/ds?x"] do
        assert_raise ArgumentError, ~r/invalid Dstar component base/, fn ->
          resolve(WidgetComponent.event("ping"), %{}, "/", ds_base: base)
        end
      end
    end

    test "full workflow from rendered HTML" do
      html = """
      <body data-ds-base="/acme/ds">
        <button id="btn" data-on:click="#{Plug.HTML.html_escape(WidgetComponent.event("ping"))}">
          Ping
        </button>
      </body>
      """

      assert {:ok, expression} = Actions.find_action(html, "#btn")
      ds_base = Actions.find_ds_base(html)

      assert resolve(expression, %{}, "/", ds_base: ds_base) ==
               {:post, "/acme/ds/#{@widget}/ping"}
    end

    test "multiple dstar actions split on top-level semicolons only" do
      expression =
        Dstar.Page.Helpers.event("a") <> "; " <> WidgetComponent.event("b")

      assert {:ok, [first, second]} = Actions.parse(expression)
      assert Actions.resolve_url(first.raw_url, %{}, "/p") == "/p/_event/a"
      assert Actions.resolve_url(second.raw_url, %{}) == "/ds/#{@widget}/b"
    end

    test "unresolvable URL parts raise instead of dispatching garbage" do
      assert_raise ArgumentError, ~r/cannot resolve Datastar action URL part/, fn ->
        Actions.resolve_url("window.myUrl + '/x'", %{})
      end
    end
  end

  # `confirm('...') && @action(...)` guards: tests accept the dialog.
  describe "confirm() guards" do
    test "dispatch the guarded @post" do
      expression =
        "confirm('Remove this app? You can re-add it later.') && " <>
          Dstar.Page.Helpers.event("revoke_app:42")

      assert {:ok, [action]} = Actions.parse(expression)
      assert action.method == :post
      assert Actions.resolve_url(action.raw_url, %{}, "/apps") == "/apps/_event/revoke_app%3A42"
    end

    test "dispatch the guarded @get" do
      assert {:ok, [action]} =
               Actions.parse(~s|confirm("Load (all) items; ok && go?") && @get("/items")|)

      assert action.method == :get
      assert action.url == "/items"
    end

    test "accept legacy single-quoted actions and chained guards" do
      assert {:ok, %{method: :delete, url: "/ds/x/remove"}} =
               Actions.parse_one(
                 "confirm('Sure?') && confirm('Really?') && @delete('/ds/x/remove')"
               )
    end

    test "reject guards other than confirm()" do
      assert {:error, _} = Actions.parse_one("$enabled && @post('/x')")
      assert {:error, _} = Actions.parse_one("confirm('Sure?') && alert('no')")
    end
  end
end
