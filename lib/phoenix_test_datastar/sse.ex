defmodule PhoenixTest.Dstar.SSE do
  @moduledoc """
  Parses Datastar SSE (Server-Sent Events) response bodies into structured events.

  Supports the following Datastar event types:
  - `datastar-patch-signals` — updates client signal state
  - `datastar-patch-elements` — patches DOM elements
  """

  @type event :: patch_signals_event() | patch_elements_event()

  @type patch_signals_event :: %{
          type: :patch_signals,
          signals: map(),
          only_if_missing: boolean()
        }

  @type patch_elements_event :: %{
          type: :patch_elements,
          selector: String.t() | nil,
          mode: :outer | :inner | :remove | :replace | :prepend | :append | :before | :after,
          elements: String.t() | nil,
          namespace: :html | :svg | :mathml
        }

  @doc """
  Parses an SSE response body into a list of structured events.

  ## Examples

      iex> parse("event: datastar-patch-signals\\ndata: signals {\\"count\\":1}\\n\\n")
      [%{type: :patch_signals, signals: %{"count" => 1}, only_if_missing: false}]
  """
  @spec parse(String.t()) :: [event()]
  def parse(body) do
    body
    |> String.trim()
    |> case do
      "" -> []
      trimmed -> trimmed
    end
    |> then(fn
      [] -> []
      content -> String.split(content, "\n\n")
    end)
    |> Enum.map(&parse_event/1)
    |> Enum.reject(&is_nil/1)
  end

  # Parse a single SSE event block
  defp parse_event(event_block) do
    lines =
      event_block
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    event_type = extract_event_type(lines)
    data_lines = extract_data_lines(lines)

    case event_type do
      "datastar-patch-signals" -> parse_patch_signals(data_lines)
      "datastar-patch-elements" -> parse_patch_elements(data_lines)
      _ -> nil
    end
  end

  # Extract the event type from event: line
  defp extract_event_type(lines) do
    Enum.find_value(lines, fn line ->
      case String.split(line, ":", parts: 2) do
        ["event", type] -> String.trim(type)
        _ -> nil
      end
    end)
  end

  # Extract all data: lines
  defp extract_data_lines(lines) do
    lines
    |> Enum.filter(&String.starts_with?(&1, "data:"))
    |> Enum.map(fn line ->
      line
      |> String.trim_leading("data:")
      |> String.trim()
    end)
  end

  # Parse patch_signals event
  defp parse_patch_signals(data_lines) do
    signals =
      Enum.find_value(data_lines, %{}, fn line ->
        case parse_key_value(line) do
          {"signals", json} ->
            case Jason.decode(json) do
              {:ok, decoded} -> decoded
              _ -> %{}
            end

          _ ->
            nil
        end
      end)

    only_if_missing =
      Enum.any?(data_lines, fn line ->
        case parse_key_value(line) do
          {"onlyIfMissing", "true"} -> true
          _ -> false
        end
      end)

    %{
      type: :patch_signals,
      signals: signals,
      only_if_missing: only_if_missing
    }
  end

  # Parse patch_elements event
  defp parse_patch_elements(data_lines) do
    # Collect all elements data lines (they can span multiple lines)
    elements_lines =
      Enum.reduce(data_lines, [], fn line, acc ->
        case parse_key_value(line) do
          {"elements", content} -> [content | acc]
          _ -> acc
        end
      end)
      |> Enum.reverse()
      |> Enum.join("\n")

    elements = if elements_lines == "", do: nil, else: elements_lines

    selector =
      Enum.find_value(data_lines, fn line ->
        case parse_key_value(line) do
          {"selector", val} -> val
          _ -> nil
        end
      end)

    mode =
      Enum.find_value(data_lines, :outer, fn line ->
        case parse_key_value(line) do
          {"mode", val} -> parse_mode(val)
          _ -> nil
        end
      end)

    namespace =
      Enum.find_value(data_lines, :html, fn line ->
        case parse_key_value(line) do
          {"namespace", val} -> parse_namespace(val)
          _ -> nil
        end
      end)

    %{
      type: :patch_elements,
      selector: selector,
      mode: mode,
      elements: elements,
      namespace: namespace
    }
  end

  # Parse a "key value" data line
  defp parse_key_value(line) do
    case String.split(line, " ", parts: 2) do
      [key, value] -> {key, value}
      [key] -> {key, ""}
      _ -> nil
    end
  end

  # Parse mode string to atom
  defp parse_mode("outer"), do: :outer
  defp parse_mode("inner"), do: :inner
  defp parse_mode("remove"), do: :remove
  defp parse_mode("replace"), do: :replace
  defp parse_mode("prepend"), do: :prepend
  defp parse_mode("append"), do: :append
  defp parse_mode("before"), do: :before
  defp parse_mode("after"), do: :after
  defp parse_mode(_), do: :outer

  # Parse namespace string to atom
  defp parse_namespace("html"), do: :html
  defp parse_namespace("svg"), do: :svg
  defp parse_namespace("mathml"), do: :mathml
  defp parse_namespace(_), do: :html
end
