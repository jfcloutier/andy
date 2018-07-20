defmodule AndyTest do
  use ExUnit.Case
  doctest Andy

  test "greets the world" do
    assert Andy.hello() == :world
  end
end
