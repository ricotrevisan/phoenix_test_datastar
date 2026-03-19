defmodule PhoenixTestDatastar.DispatcherTest do
  use PhoenixTestDatastar.DatastarCase, async: true

  alias PhoenixTestDatastar.Dispatcher
  alias PhoenixTestDatastar.Session

  describe "apply_events/2" do
    test "applies patch_signals event" do
      session = %Session{
        conn: Phoenix.ConnTest.build_conn(),
        raw_html: "<div>hello</div>",
        signals: %{"count" => 0},
        csrf_token: nil,
        current_path: "/"
      }

      events = [
        %{type: :patch_signals, signals: %{"count" => 5}, only_if_missing: false}
      ]

      result = Dispatcher.apply_events(session, events)
      assert result.signals["count"] == 5
    end

    test "applies patch_signals with only_if_missing" do
      session = %Session{
        conn: Phoenix.ConnTest.build_conn(),
        raw_html: "<div>hello</div>",
        signals: %{"count" => 10},
        csrf_token: nil,
        current_path: "/"
      }

      events = [
        %{type: :patch_signals, signals: %{"count" => 0, "name" => "test"}, only_if_missing: true}
      ]

      result = Dispatcher.apply_events(session, events)
      assert result.signals["count"] == 10
      assert result.signals["name"] == "test"
    end

    test "applies patch_elements event to DOM" do
      session = %Session{
        conn: Phoenix.ConnTest.build_conn(),
        raw_html: "<html><body><span id=\"count\">0</span></body></html>",
        signals: %{},
        csrf_token: nil,
        current_path: "/"
      }

      events = [
        %{
          type: :patch_elements,
          selector: "#count",
          mode: :outer,
          elements: "<span id=\"count\">42</span>",
          namespace: :html
        }
      ]

      result = Dispatcher.apply_events(session, events)
      assert result.raw_html =~ "42"
      refute result.raw_html =~ ">0<"
    end

    test "applies multiple events in order" do
      session = %Session{
        conn: Phoenix.ConnTest.build_conn(),
        raw_html: "<html><body><span id=\"count\">0</span></body></html>",
        signals: %{"count" => 0},
        csrf_token: nil,
        current_path: "/"
      }

      events = [
        %{type: :patch_signals, signals: %{"count" => 5}, only_if_missing: false},
        %{
          type: :patch_elements,
          selector: "#count",
          mode: :outer,
          elements: "<span id=\"count\">5</span>",
          namespace: :html
        }
      ]

      result = Dispatcher.apply_events(session, events)
      assert result.signals["count"] == 5
      assert result.raw_html =~ ">5<"
    end

    test "updates CSRF token from signals" do
      session = %Session{
        conn: Phoenix.ConnTest.build_conn(),
        raw_html: "<div>hello</div>",
        signals: %{},
        csrf_token: nil,
        current_path: "/"
      }

      events = [
        %{type: :patch_signals, signals: %{"_csrfToken" => "new-token"}, only_if_missing: false}
      ]

      result = Dispatcher.apply_events(session, events)
      assert result.csrf_token == "new-token"
    end

    test "ignores nil elements in patch_elements" do
      session = %Session{
        conn: Phoenix.ConnTest.build_conn(),
        raw_html: "<div>hello</div>",
        signals: %{},
        csrf_token: nil,
        current_path: "/"
      }

      events = [
        %{type: :patch_elements, selector: "#x", mode: :remove, elements: nil, namespace: :html}
      ]

      result = Dispatcher.apply_events(session, events)
      assert result.raw_html == "<div>hello</div>"
    end
  end
end
