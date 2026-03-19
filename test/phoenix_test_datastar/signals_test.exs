defmodule PhoenixTestDatastar.SignalsTest do
  use ExUnit.Case, async: true
  doctest PhoenixTestDatastar.Signals

  alias PhoenixTestDatastar.Signals

  describe "extract_from_html/1" do
    test "extracts individual data-signals:key attributes" do
      html = """
      <div data-signals:count="0" data-signals:name="'hello'" data-signals:active="true"></div>
      """

      assert Signals.extract_from_html(html) == %{
               "count" => 0,
               "name" => "hello",
               "active" => true
             }
    end

    test "extracts object-style data-signals attribute" do
      html = """
      <div data-signals="{foo: 1, bar: 2, baz: 'test'}"></div>
      """

      assert Signals.extract_from_html(html) == %{
               "foo" => 1,
               "bar" => 2,
               "baz" => "test"
             }
    end

    test "extracts mixed individual and object signals" do
      html = """
      <div data-signals="{foo: 1, bar: 2}">
        <span data-signals:count="5" data-signals:name="'world'"></span>
      </div>
      """

      assert Signals.extract_from_html(html) == %{
               "foo" => 1,
               "bar" => 2,
               "count" => 5,
               "name" => "world"
             }
    end

    test "extracts client-only signals with underscore prefix" do
      html = """
      <div data-signals:_csrftoken="'abc123'" data-signals:count="0"></div>
      """

      assert Signals.extract_from_html(html) == %{
               "_csrftoken" => "abc123",
               "count" => 0
             }
    end

    test "handles nested object signals" do
      html = """
      <div data-signals="{user: {name: 'Alice', age: 30}, count: 5}"></div>
      """

      assert Signals.extract_from_html(html) == %{
               "user" => %{"name" => "Alice", "age" => 30},
               "count" => 5
             }
    end

    test "merges signals from multiple elements" do
      html = """
      <div>
        <span data-signals:count="1"></span>
        <span data-signals:name="'test'"></span>
      </div>
      """

      assert Signals.extract_from_html(html) == %{
               "count" => 1,
               "name" => "test"
             }
    end
  end

  describe "parse_js_value/1" do
    test "parses numbers" do
      assert Signals.parse_js_value("0") == 0
      assert Signals.parse_js_value("42") == 42
      assert Signals.parse_js_value("-10") == -10
      assert Signals.parse_js_value("3.14") == 3.14
    end

    test "parses single-quoted strings" do
      assert Signals.parse_js_value("'hello'") == "hello"
      assert Signals.parse_js_value("'world'") == "world"
      assert Signals.parse_js_value("'abc123'") == "abc123"
    end

    test "parses booleans" do
      assert Signals.parse_js_value("true") == true
      assert Signals.parse_js_value("false") == false
    end

    test "parses null" do
      assert Signals.parse_js_value("null") == nil
    end

    test "parses arrays" do
      assert Signals.parse_js_value("[1,2,3]") == [1, 2, 3]
      assert Signals.parse_js_value("['a','b','c']") == ["a", "b", "c"]
      assert Signals.parse_js_value("[1, 'test', true]") == [1, "test", true]
    end

    test "parses objects with unquoted keys" do
      assert Signals.parse_js_value("{foo: 1}") == %{"foo" => 1}
      assert Signals.parse_js_value("{foo: 1, bar: 2}") == %{"foo" => 1, "bar" => 2}
      assert Signals.parse_js_value("{name: 'Alice', age: 30}") == %{
               "name" => "Alice",
               "age" => 30
             }
    end

    test "parses nested objects" do
      assert Signals.parse_js_value("{user: {name: 'Bob'}, count: 5}") == %{
               "user" => %{"name" => "Bob"},
               "count" => 5
             }
    end
  end

  describe "normalize_to_json/1" do
    test "converts single quotes to double quotes" do
      assert Signals.normalize_to_json("'hello'") == ~s("hello")
      assert Signals.normalize_to_json("'world'") == ~s("world")
    end

    test "quotes unquoted object keys" do
      assert Signals.normalize_to_json("{foo: 1}") == ~s({"foo": 1})
      assert Signals.normalize_to_json("{foo: 1, bar: 2}") == ~s({"foo": 1,"bar": 2})
    end

    test "handles mixed JS expressions" do
      assert Signals.normalize_to_json("{name: 'Alice', age: 30}") ==
               ~s({"name": "Alice","age": 30})
    end

    test "handles nested objects" do
      result = Signals.normalize_to_json("{user: {name: 'Bob'}, count: 5}")
      assert result == ~s({"user": {"name": "Bob"},"count": 5})
    end

    test "preserves primitives" do
      assert Signals.normalize_to_json("42") == "42"
      assert Signals.normalize_to_json("true") == "true"
      assert Signals.normalize_to_json("null") == "null"
    end
  end

  describe "apply_patch/3" do
    test "merges new signals into existing state" do
      state = %{"count" => 1, "name" => "test"}
      new_signals = %{"age" => 30, "active" => true}

      result = Signals.apply_patch(state, new_signals)

      assert result == %{
               "count" => 1,
               "name" => "test",
               "age" => 30,
               "active" => true
             }
    end

    test "overwrites existing signals by default" do
      state = %{"count" => 1, "name" => "test"}
      new_signals = %{"count" => 2, "name" => "updated"}

      result = Signals.apply_patch(state, new_signals)

      assert result == %{"count" => 2, "name" => "updated"}
    end

    test "with only_if_missing: true, keeps existing signals" do
      state = %{"count" => 1, "name" => "test"}
      new_signals = %{"count" => 2, "age" => 30}

      result = Signals.apply_patch(state, new_signals, only_if_missing: true)

      assert result == %{
               "count" => 1,
               "name" => "test",
               "age" => 30
             }
    end

    test "removes signal when value is nil" do
      state = %{"count" => 1, "name" => "test", "age" => 30}
      new_signals = %{"name" => nil}

      result = Signals.apply_patch(state, new_signals)

      assert result == %{"count" => 1, "age" => 30}
    end

    test "removes multiple signals with nil values" do
      state = %{"count" => 1, "name" => "test", "age" => 30}
      new_signals = %{"name" => nil, "age" => nil}

      result = Signals.apply_patch(state, new_signals)

      assert result == %{"count" => 1}
    end

    test "handles empty maps" do
      assert Signals.apply_patch(%{}, %{"count" => 1}) == %{"count" => 1}
      assert Signals.apply_patch(%{"count" => 1}, %{}) == %{"count" => 1}
      assert Signals.apply_patch(%{}, %{}) == %{}
    end
  end

  describe "to_post_body/1" do
    test "encodes signals as JSON" do
      signals = %{"count" => 1, "name" => "test"}
      result = Signals.to_post_body(signals)
      decoded = Jason.decode!(result)

      assert decoded == %{"count" => 1, "name" => "test"}
    end

    test "excludes client-only signals with underscore prefix" do
      signals = %{"count" => 1, "_csrfToken" => "abc123", "name" => "test"}
      result = Signals.to_post_body(signals)
      decoded = Jason.decode!(result)

      assert decoded == %{"count" => 1, "name" => "test"}
      refute Map.has_key?(decoded, "_csrfToken")
    end

    test "handles nested objects" do
      signals = %{"user" => %{"name" => "Alice", "age" => 30}, "count" => 5}
      result = Signals.to_post_body(signals)
      decoded = Jason.decode!(result)

      assert decoded == %{"user" => %{"name" => "Alice", "age" => 30}, "count" => 5}
    end

    test "returns empty object for empty signals" do
      assert Signals.to_post_body(%{}) == "{}"
    end

    test "returns empty object when all signals are client-only" do
      signals = %{"_csrfToken" => "abc", "_sessionId" => "xyz"}
      assert Signals.to_post_body(signals) == "{}"
    end
  end

  describe "to_get_query/1" do
    test "formats as datastar query parameter" do
      signals = %{"count" => 1, "name" => "test"}
      result = Signals.to_get_query(signals)

      assert String.starts_with?(result, "datastar=")

      # Decode the query parameter
      [_key, encoded_value] = String.split(result, "=", parts: 2)
      decoded_json = URI.decode_www_form(encoded_value)
      decoded = Jason.decode!(decoded_json)

      assert decoded == %{"count" => 1, "name" => "test"}
    end

    test "excludes client-only signals" do
      signals = %{"count" => 1, "_csrfToken" => "abc"}
      result = Signals.to_get_query(signals)

      [_key, encoded_value] = String.split(result, "=", parts: 2)
      decoded_json = URI.decode_www_form(encoded_value)
      decoded = Jason.decode!(decoded_json)

      assert decoded == %{"count" => 1}
      refute Map.has_key?(decoded, "_csrfToken")
    end

    test "URL encodes special characters" do
      signals = %{"name" => "hello world"}
      result = Signals.to_get_query(signals)

      # Should be URL encoded
      assert result =~ "%"
      assert String.starts_with?(result, "datastar=")
    end
  end

  describe "public_signals/1" do
    test "filters out underscore-prefixed signals" do
      signals = %{
        "count" => 1,
        "_csrfToken" => "abc123",
        "name" => "test",
        "_sessionId" => "xyz"
      }

      result = Signals.public_signals(signals)

      assert result == %{"count" => 1, "name" => "test"}
    end

    test "returns all signals when none are client-only" do
      signals = %{"count" => 1, "name" => "test", "age" => 30}

      result = Signals.public_signals(signals)

      assert result == signals
    end

    test "returns empty map when all signals are client-only" do
      signals = %{"_csrfToken" => "abc", "_sessionId" => "xyz"}

      result = Signals.public_signals(signals)

      assert result == %{}
    end

    test "handles empty map" do
      assert Signals.public_signals(%{}) == %{}
    end
  end
end
