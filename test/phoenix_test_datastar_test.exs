defmodule PhoenixTestDatastarTest do
  use ExUnit.Case
  doctest PhoenixTestDatastar

  test "greets the world" do
    assert PhoenixTestDatastar.hello() == :world
  end
end
