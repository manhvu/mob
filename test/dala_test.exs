defmodule DalaTest do
  use ExUnit.Case, async: true

  test "assign/3 convenience delegate works" do
    socket = Dala.Socket.new(SomeScreen)
    socket = Dala.assign(socket, :count, 42)
    assert socket.assigns.count == 42
  end

  test "assign/2 convenience delegate works" do
    socket = Dala.Socket.new(SomeScreen)
    socket = Dala.assign(socket, count: 1, name: "dala")
    assert socket.assigns.count == 1
    assert socket.assigns.name == "dala"
  end
end
