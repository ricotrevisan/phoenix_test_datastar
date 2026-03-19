defmodule PhoenixTest.Dstar.SSETest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Dstar.SSE

  describe "parse/1" do
    test "parses a single patch_signals event" do
      sse = """
      event: datastar-patch-signals
      data: signals {"count":1}

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_signals
      assert event.signals == %{"count" => 1}
      assert event.only_if_missing == false
    end

    test "parses patch_signals with onlyIfMissing true" do
      sse = """
      event: datastar-patch-signals
      data: onlyIfMissing true
      data: signals {"user":"alice","active":true}

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_signals
      assert event.signals == %{"user" => "alice", "active" => true}
      assert event.only_if_missing == true
    end

    test "parses a single patch_elements event with selector and mode" do
      sse = """
      event: datastar-patch-elements
      data: selector #count
      data: mode inner
      data: elements <span>1</span>

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_elements
      assert event.selector == "#count"
      assert event.mode == :inner
      assert event.elements == "<span>1</span>"
      assert event.namespace == :html
    end

    test "parses patch_elements with default mode (no mode line = outer)" do
      sse = """
      event: datastar-patch-elements
      data: selector #app
      data: elements <div>Hello</div>

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_elements
      assert event.selector == "#app"
      assert event.mode == :outer
      assert event.elements == "<div>Hello</div>"
    end

    test "parses multi-event response (signals + elements)" do
      sse = """
      event: datastar-patch-signals
      data: signals {"count":1}

      event: datastar-patch-elements
      data: selector #count
      data: mode inner
      data: elements <span>1</span>

      """

      assert [signals_event, elements_event] = SSE.parse(sse)

      assert signals_event.type == :patch_signals
      assert signals_event.signals == %{"count" => 1}
      assert signals_event.only_if_missing == false

      assert elements_event.type == :patch_elements
      assert elements_event.selector == "#count"
      assert elements_event.mode == :inner
      assert elements_event.elements == "<span>1</span>"
    end

    test "parses patch_elements with multi-line elements data" do
      sse = """
      event: datastar-patch-elements
      data: selector #app
      data: mode inner
      data: elements <div>
      data: elements   <h1>Title</h1>
      data: elements   <p>Content</p>
      data: elements </div>

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_elements
      assert event.selector == "#app"
      assert event.mode == :inner

      expected_html = "<div>\n  <h1>Title</h1>\n  <p>Content</p>\n</div>"
      assert event.elements == expected_html
    end

    test "handles empty input" do
      assert SSE.parse("") == []
    end

    test "handles whitespace-only input" do
      assert SSE.parse("   \n\n  ") == []
    end

    test "handles events with id: and retry: lines (ignores them)" do
      sse = """
      event: datastar-patch-signals
      id: 123
      retry: 5000
      data: signals {"status":"ok"}

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_signals
      assert event.signals == %{"status" => "ok"}
      assert event.only_if_missing == false
    end

    test "parses patch_elements with non-default namespace" do
      sse = """
      event: datastar-patch-elements
      data: selector #svg-container
      data: namespace svg
      data: mode inner
      data: elements <circle cx="50" cy="50" r="40"/>

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_elements
      assert event.selector == "#svg-container"
      assert event.mode == :inner
      assert event.namespace == :svg
      assert event.elements == ~s(<circle cx="50" cy="50" r="40"/>)
    end

    test "parses patch_elements with mathml namespace" do
      sse = """
      event: datastar-patch-elements
      data: namespace mathml
      data: elements <math><mi>x</mi></math>

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_elements
      assert event.namespace == :mathml
      assert event.elements == "<math><mi>x</mi></math>"
    end

    test "parses all valid modes" do
      modes = [
        "outer",
        "inner",
        "remove",
        "replace",
        "prepend",
        "append",
        "before",
        "after"
      ]

      for mode_str <- modes do
        mode_atom = String.to_atom(mode_str)

        sse = """
        event: datastar-patch-elements
        data: mode #{mode_str}
        data: elements <div>test</div>

        """

        assert [event] = SSE.parse(sse)
        assert event.mode == mode_atom
      end
    end

    test "parses patch_elements without selector (for outer mode)" do
      sse = """
      event: datastar-patch-elements
      data: mode outer
      data: elements <div>Full replacement</div>

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_elements
      assert event.selector == nil
      assert event.mode == :outer
      assert event.elements == "<div>Full replacement</div>"
    end

    test "parses patch_elements without elements (for remove mode)" do
      sse = """
      event: datastar-patch-elements
      data: selector #to-remove
      data: mode remove

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_elements
      assert event.selector == "#to-remove"
      assert event.mode == :remove
      assert event.elements == nil
    end

    test "parses complex signals with nested data" do
      sse = """
      event: datastar-patch-signals
      data: signals {"user":{"name":"Alice","roles":["admin","user"]},"count":42}

      """

      assert [event] = SSE.parse(sse)
      assert event.type == :patch_signals

      assert event.signals == %{
               "user" => %{"name" => "Alice", "roles" => ["admin", "user"]},
               "count" => 42
             }
    end

    test "handles multiple events of the same type" do
      sse = """
      event: datastar-patch-signals
      data: signals {"a":1}

      event: datastar-patch-signals
      data: signals {"b":2}

      event: datastar-patch-signals
      data: onlyIfMissing true
      data: signals {"c":3}

      """

      assert [event1, event2, event3] = SSE.parse(sse)

      assert event1.signals == %{"a" => 1}
      assert event1.only_if_missing == false

      assert event2.signals == %{"b" => 2}
      assert event2.only_if_missing == false

      assert event3.signals == %{"c" => 3}
      assert event3.only_if_missing == true
    end
  end
end
