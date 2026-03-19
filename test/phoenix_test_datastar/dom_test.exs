defmodule PhoenixTestDatastar.DOMTest do
  use ExUnit.Case, async: true

  alias PhoenixTestDatastar.DOM

  @base_html """
  <!DOCTYPE html><html><head><title>Test</title></head><body><div id="app"><span id="count">0</span><div id="list"><p>item1</p></div></div></body></html>
  """

  describe "apply_patch/2 with :outer mode" do
    test "morphs by replacing element with matching ID" do
      patch = %{
        mode: :outer,
        selector: "",
        elements: "<span id=\"count\">42</span>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<span id=\"count\">42</span>"
      refute result =~ "<span id=\"count\">0</span>"
      # Ensure the rest of the document is preserved
      assert result =~ "<title>Test</title>"
      assert result =~ "<div id=\"app\">"
      assert result =~ "<div id=\"list\">"
    end

    test "morphs multiple elements by ID" do
      patch = %{
        mode: :outer,
        selector: "",
        elements: """
        <span id="count">99</span>
        <div id="list"><p>item2</p><p>item3</p></div>
        """
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<span id=\"count\">99</span>"
      assert result =~ "<p>item2</p>"
      assert result =~ "<p>item3</p>"
      refute result =~ "<span id=\"count\">0</span>"
      refute result =~ "<p>item1</p>"
    end

    test "falls back to selector when no ID present" do
      html = "<div><span class=\"counter\">0</span></div>"

      patch = %{
        mode: :outer,
        selector: ".counter",
        elements: "<span class=\"counter\">100</span>"
      }

      result = DOM.apply_patch(html, patch)

      assert result =~ "<span class=\"counter\">100</span>"
      refute result =~ "<span class=\"counter\">0</span>"
    end

    test "uses ID over selector when both present" do
      html = "<div><span id=\"count\" class=\"counter\">0</span></div>"

      patch = %{
        mode: :outer,
        selector: ".different",
        elements: "<span id=\"count\">200</span>"
      }

      result = DOM.apply_patch(html, patch)

      assert result =~ "<span id=\"count\">200</span>"
      refute result =~ ">0</span>"
    end
  end

  describe "apply_patch/2 with :inner mode" do
    test "replaces children of target element" do
      patch = %{
        mode: :inner,
        selector: "#list",
        elements: "<p>new item</p><p>another item</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<div id=\"list\"><p>new item</p><p>another item</p></div>"
      refute result =~ "<p>item1</p>"
      # Ensure other elements preserved
      assert result =~ "<span id=\"count\">0</span>"
    end

    test "replaces children with empty content" do
      patch = %{
        mode: :inner,
        selector: "#list",
        elements: ""
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<div id=\"list\"></div>"
      refute result =~ "<p>item1</p>"
    end
  end

  describe "apply_patch/2 with :append mode" do
    test "adds children at end of target" do
      patch = %{
        mode: :append,
        selector: "#list",
        elements: "<p>item2</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<div id=\"list\"><p>item1</p><p>item2</p></div>"
    end

    test "appends multiple elements" do
      patch = %{
        mode: :append,
        selector: "#list",
        elements: "<p>item2</p><p>item3</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<p>item1</p><p>item2</p><p>item3</p>"
    end
  end

  describe "apply_patch/2 with :prepend mode" do
    test "adds children at start of target" do
      patch = %{
        mode: :prepend,
        selector: "#list",
        elements: "<p>item0</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<div id=\"list\"><p>item0</p><p>item1</p></div>"
    end

    test "prepends multiple elements" do
      patch = %{
        mode: :prepend,
        selector: "#list",
        elements: "<p>first</p><p>second</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      # Check order
      assert result =~ "<p>first</p><p>second</p><p>item1</p>"
    end
  end

  describe "apply_patch/2 with :before mode" do
    test "inserts sibling before target element" do
      patch = %{
        mode: :before,
        selector: "#list",
        elements: "<p>before list</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      # The new element should appear before #list but after #count
      assert result =~ "<span id=\"count\">0</span><p>before list</p><div id=\"list\">"
    end

    test "inserts multiple siblings before target" do
      patch = %{
        mode: :before,
        selector: "#list",
        elements: "<p>first</p><p>second</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<p>first</p><p>second</p><div id=\"list\">"
    end
  end

  describe "apply_patch/2 with :after mode" do
    test "inserts sibling after target element" do
      patch = %{
        mode: :after,
        selector: "#count",
        elements: "<span>after count</span>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<span id=\"count\">0</span><span>after count</span>"
    end

    test "inserts multiple siblings after target" do
      patch = %{
        mode: :after,
        selector: "#count",
        elements: "<span>first</span><span>second</span>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<span id=\"count\">0</span><span>first</span><span>second</span>"
    end
  end

  describe "apply_patch/2 with :replace mode" do
    test "replaces element matching selector" do
      patch = %{
        mode: :replace,
        selector: "#count",
        elements: "<div id=\"counter\">100</div>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<div id=\"counter\">100</div>"
      refute result =~ "<span id=\"count\">"
      # Ensure rest preserved
      assert result =~ "<div id=\"list\">"
    end

    test "replaces with multiple elements (uses first)" do
      patch = %{
        mode: :replace,
        selector: "#count",
        elements: "<span>one</span><span>two</span>"
      }

      result = DOM.apply_patch(@base_html, patch)

      assert result =~ "<span>one</span>"
      refute result =~ "<span id=\"count\">0</span>"
    end
  end

  describe "apply_patch/2 with :remove mode" do
    test "removes element matching selector" do
      patch = %{
        mode: :remove,
        selector: "#count"
      }

      result = DOM.apply_patch(@base_html, patch)

      refute result =~ "<span id=\"count\">0</span>"
      # Ensure rest preserved
      assert result =~ "<div id=\"list\"><p>item1</p></div>"
    end

    test "removes nested element" do
      patch = %{
        mode: :remove,
        selector: "p"
      }

      result = DOM.apply_patch(@base_html, patch)

      refute result =~ "<p>item1</p>"
      # Container should still exist
      assert result =~ "<div id=\"list\"></div>"
    end
  end

  describe "patch preservation" do
    test "preserves rest of document structure" do
      patch = %{
        mode: :inner,
        selector: "#list",
        elements: "<p>changed</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      # Check that document structure is intact (note: Floki strips DOCTYPE)
      assert result =~ "<html>"
      assert result =~ "<head>"
      assert result =~ "<title>Test</title>"
      assert result =~ "</head>"
      assert result =~ "<body>"
      assert result =~ "<div id=\"app\">"
      assert result =~ "<span id=\"count\">0</span>"
      assert result =~ "</body>"
      assert result =~ "</html>"
    end

    test "handles nested elements correctly" do
      html = """
      <div id="outer">
        <div id="middle">
          <div id="inner">content</div>
        </div>
      </div>
      """

      patch = %{
        mode: :inner,
        selector: "#middle",
        elements: "<span>new content</span>"
      }

      result = DOM.apply_patch(html, patch)

      assert result =~ "<div id=\"outer\">"
      assert result =~ "<div id=\"middle\"><span>new content</span></div>"
      refute result =~ "<div id=\"inner\">"
      assert result =~ "</div>"
    end
  end

  describe "edge cases" do
    test "handles empty elements string for non-remove modes" do
      patch = %{
        mode: :append,
        selector: "#list",
        elements: ""
      }

      result = DOM.apply_patch(@base_html, patch)

      # Should be unchanged
      assert result =~ "<p>item1</p>"
    end

    test "handles selector that doesn't match anything" do
      patch = %{
        mode: :inner,
        selector: "#nonexistent",
        elements: "<p>new</p>"
      }

      result = DOM.apply_patch(@base_html, patch)

      # Document should be unchanged
      assert result =~ "<span id=\"count\">0</span>"
      assert result =~ "<p>item1</p>"
    end

    test "handles tag selector" do
      html = "<div><p>old</p></div>"

      patch = %{
        mode: :replace,
        selector: "p",
        elements: "<span>new</span>"
      }

      result = DOM.apply_patch(html, patch)

      assert result =~ "<span>new</span>"
      refute result =~ "<p>old</p>"
    end
  end
end
