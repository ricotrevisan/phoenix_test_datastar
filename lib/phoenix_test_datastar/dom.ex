defmodule PhoenixTestDatastar.DOM do
  @moduledoc """
  Applies Datastar SSE patch events to an in-memory HTML string using Floki.

  Supports various patch modes:
  - `:outer` - Morph by ID or replace element matching selector
  - `:inner` - Replace children of target element
  - `:append` - Add children at end of target
  - `:prepend` - Add children at start of target
  - `:before` - Insert siblings before target
  - `:after` - Insert siblings after target
  - `:replace` - Replace entire element matching selector
  - `:remove` - Remove elements matching selector
  """

  @type patch :: %{
          mode: atom(),
          selector: String.t(),
          elements: String.t()
        }

  @doc """
  Applies a patch to raw HTML and returns the updated HTML string.

  ## Parameters

  - `raw_html` - The full HTML document as a string
  - `patch` - A map with `:mode`, `:selector`, and optionally `:elements`

  ## Examples

      iex> html = "<div id='app'><span id='count'>0</span></div>"
      iex> patch = %{mode: :outer, selector: "", elements: "<span id='count'>1</span>"}
      iex> PhoenixTestDatastar.DOM.apply_patch(html, patch)
      "<div id='app'><span id='count'>1</span></div>"
  """
  @spec apply_patch(String.t(), patch()) :: String.t()
  def apply_patch(raw_html, %{mode: :outer, elements: elements} = patch) do
    doc = Floki.parse_document!(raw_html)
    new_elements = Floki.parse_fragment!(elements)

    # Try to morph by ID first
    updated_doc =
      Enum.reduce(new_elements, doc, fn new_element, acc_doc ->
        case get_id(new_element) do
          nil ->
            # No ID, skip for now (will handle with selector fallback)
            acc_doc

          id ->
            # Replace element with matching ID
            morph_by_id(acc_doc, id, new_element)
        end
      end)

    # If no elements had IDs and selector is provided, use selector fallback
    final_doc =
      if selector_fallback_needed?(new_elements, patch[:selector]) do
        replace_by_selector(updated_doc, patch.selector, new_elements)
      else
        updated_doc
      end

    Floki.raw_html(final_doc)
  end

  def apply_patch(raw_html, %{mode: :inner, selector: selector, elements: elements}) do
    doc = Floki.parse_document!(raw_html)
    new_elements = Floki.parse_fragment!(elements)

    updated_doc =
      Floki.traverse_and_update(doc, fn
        {tag, attrs, _children} = node ->
          if matches_selector?(node, selector, doc) do
            {tag, attrs, new_elements}
          else
            node
          end

        other ->
          other
      end)

    Floki.raw_html(updated_doc)
  end

  def apply_patch(raw_html, %{mode: :append, selector: selector, elements: elements}) do
    doc = Floki.parse_document!(raw_html)
    new_elements = Floki.parse_fragment!(elements)

    updated_doc =
      Floki.traverse_and_update(doc, fn
        {tag, attrs, children} = node ->
          if matches_selector?(node, selector, doc) do
            {tag, attrs, children ++ new_elements}
          else
            node
          end

        other ->
          other
      end)

    Floki.raw_html(updated_doc)
  end

  def apply_patch(raw_html, %{mode: :prepend, selector: selector, elements: elements}) do
    doc = Floki.parse_document!(raw_html)
    new_elements = Floki.parse_fragment!(elements)

    updated_doc =
      Floki.traverse_and_update(doc, fn
        {tag, attrs, children} = node ->
          if matches_selector?(node, selector, doc) do
            {tag, attrs, new_elements ++ children}
          else
            node
          end

        other ->
          other
      end)

    Floki.raw_html(updated_doc)
  end

  def apply_patch(raw_html, %{mode: :before, selector: selector, elements: elements}) do
    doc = Floki.parse_document!(raw_html)
    new_elements = Floki.parse_fragment!(elements)

    updated_doc =
      Floki.traverse_and_update(doc, fn
        {tag, attrs, children} ->
          # Check if any child matches the selector
          updated_children =
            Enum.flat_map(children, fn child ->
              if matches_selector?(child, selector, doc) do
                new_elements ++ [child]
              else
                [child]
              end
            end)

          {tag, attrs, updated_children}

        other ->
          other
      end)

    Floki.raw_html(updated_doc)
  end

  def apply_patch(raw_html, %{mode: :after, selector: selector, elements: elements}) do
    doc = Floki.parse_document!(raw_html)
    new_elements = Floki.parse_fragment!(elements)

    updated_doc =
      Floki.traverse_and_update(doc, fn
        {tag, attrs, children} ->
          # Check if any child matches the selector
          updated_children =
            Enum.flat_map(children, fn child ->
              if matches_selector?(child, selector, doc) do
                [child] ++ new_elements
              else
                [child]
              end
            end)

          {tag, attrs, updated_children}

        other ->
          other
      end)

    Floki.raw_html(updated_doc)
  end

  def apply_patch(raw_html, %{mode: :replace, selector: selector, elements: elements}) do
    doc = Floki.parse_document!(raw_html)
    new_elements = Floki.parse_fragment!(elements)

    updated_doc = replace_by_selector(doc, selector, new_elements)

    Floki.raw_html(updated_doc)
  end

  def apply_patch(raw_html, %{mode: :remove, selector: selector}) do
    doc = Floki.parse_document!(raw_html)

    updated_doc =
      Floki.traverse_and_update(doc, fn
        {tag, attrs, children} ->
          # Filter out children that match the selector
          updated_children =
            Enum.reject(children, fn child ->
              matches_selector?(child, selector, doc)
            end)

          {tag, attrs, updated_children}

        other ->
          other
      end)

    Floki.raw_html(updated_doc)
  end

  # Private helpers

  defp get_id({_tag, attrs, _children}) do
    Enum.find_value(attrs, fn
      {"id", id} -> id
      _ -> nil
    end)
  end

  defp get_id(_), do: nil

  defp morph_by_id(doc, id, new_element) do
    Floki.traverse_and_update(doc, fn
      {_tag, _attrs, _children} = node ->
        if get_id(node) == id do
          new_element
        else
          node
        end

      other ->
        other
    end)
  end

  defp replace_by_selector(doc, selector, new_elements) do
    replaced = {false}

    {updated_doc, _} =
      Floki.traverse_and_update(doc, replaced, fn
        {tag, attrs, children} = node, {false} = acc ->
          if matches_selector?(node, selector, doc) do
            # Replace with new elements - if multiple, we need to handle this at parent level
            # For simplicity, replace with first new element
            {List.first(new_elements) || node, {true}}
          else
            # Check children
            {updated_children, new_acc} =
              Enum.map_reduce(children, acc, fn child, child_acc ->
                case child do
                  {_child_tag, _child_attrs, _grandchildren} ->
                    if matches_selector?(child, selector, doc) and child_acc == {false} do
                      {List.first(new_elements) || child, {true}}
                    else
                      {child, child_acc}
                    end

                  _ ->
                    {child, child_acc}
                end
              end)

            {{tag, attrs, updated_children}, new_acc}
          end

        other, acc ->
          {other, acc}
      end)

    updated_doc
  end

  defp selector_fallback_needed?(new_elements, selector) do
    has_no_ids = Enum.all?(new_elements, fn elem -> get_id(elem) == nil end)
    has_selector = selector && selector != ""
    has_no_ids and has_selector
  end

  defp matches_selector?({tag, attrs, _children}, selector, _doc) do
    # Simple selector matching for id and class selectors
    cond do
      # ID selector
      String.starts_with?(selector, "#") ->
        id = String.trim_leading(selector, "#")
        get_id({tag, attrs, []}) == id

      # Class selector
      String.starts_with?(selector, ".") ->
        class_name = String.trim_leading(selector, ".")
        classes = get_classes({tag, attrs, []})
        class_name in classes

      # Tag selector
      true ->
        tag == selector
    end
  end

  defp matches_selector?(_, _, _), do: false

  defp get_classes({_tag, attrs, _children}) do
    Enum.find_value(attrs, [], fn
      {"class", class_str} -> String.split(class_str, " ", trim: true)
      _ -> nil
    end) || []
  end
end
