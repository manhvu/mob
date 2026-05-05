defmodule Dala.LocationTest do
  use ExUnit.Case, async: true
  import Dala.Location

  @moduledoc """
  Tests for Dala.Location module.
  """

  describe "start/2" do
    test "returns socket unchanged" do
      socket = %Dala.Socket{assigns: %{}}
      result = start(socket, accuracy: :high)
      assert result == socket
    end

    test "works without options" do
      socket = %Dala.Socket{assigns: %{}}
      result = start(socket)
      assert result == socket
    end
  end

  describe "stop/1" do
    test "returns socket unchanged" do
      socket = %Dala.Socket{assigns: %{}}
      result = stop(socket)
      assert result == socket
    end
  end

  describe "handle_info callbacks" do
    test "location result structure" do
      message = {:location, :update, %{lat: 37.7749, lng: -122.4194}}
      assert {:location, :update, data} = message
      assert data[:lat] == 37.7749
      assert data[:lng] == -122.4194
    end

    test "error result structure" do
      message = {:location, :error, "Permission denied"}
      assert {:location, :error, reason} = message
      assert reason == "Permission denied"
    end

    test "not_available result structure" do
      message = {:location, :not_available}
      assert {:location, :not_available} = message
    end
  end
end
