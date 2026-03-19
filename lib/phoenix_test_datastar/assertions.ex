defmodule PhoenixTestDatastar.Assertions do
  @moduledoc """
  Datastar-specific assertion macros for testing signal state.

  Import this module in your test files:

      import PhoenixTestDatastar.Assertions

  ## Examples

      session
      |> click_button("Increment")
      |> assert_signal("count", 1)
      |> assert_signal_set("count")
      |> refute_signal("nonexistent")
  """

  @doc """
  Asserts that a signal has the expected value.

  ## Examples

      session |> assert_signal("count", 0)
      session |> assert_signal("name", "Alice")
  """
  defmacro assert_signal(session, name, expected) do
    quote do
      session = unquote(session)
      name = unquote(name)
      expected = unquote(expected)
      actual = Map.get(session.signals, name)

      if actual == expected do
        assert true
      else
        raise ExUnit.AssertionError,
          message: """
          Expected signal #{inspect(name)} to be #{inspect(expected)} but got #{inspect(actual)}

          Current signals: #{inspect(session.signals)}
          """
      end

      session
    end
  end

  @doc """
  Asserts that a signal exists (is set) in the session, regardless of its value.

  ## Examples

      session |> assert_signal_set("count")
  """
  defmacro assert_signal_set(session, name) do
    quote do
      session = unquote(session)
      name = unquote(name)

      if Map.has_key?(session.signals, name) do
        assert true
      else
        raise ExUnit.AssertionError,
          message: """
          Expected signal #{inspect(name)} to be set but it was not found.

          Current signals: #{inspect(session.signals)}
          """
      end

      session
    end
  end

  @doc """
  Asserts that a signal does not exist in the session.

  ## Examples

      session |> refute_signal("deleted_signal")
  """
  defmacro refute_signal(session, name) do
    quote do
      session = unquote(session)
      name = unquote(name)

      if Map.has_key?(session.signals, name) do
        value = Map.get(session.signals, name)

        raise ExUnit.AssertionError,
          message: """
          Expected signal #{inspect(name)} not to be set but found it with value #{inspect(value)}

          Current signals: #{inspect(session.signals)}
          """
      else
        refute false
      end

      session
    end
  end
end
